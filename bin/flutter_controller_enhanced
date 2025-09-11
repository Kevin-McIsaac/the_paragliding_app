#!/bin/bash

# Enhanced Flutter Controller with logging and monitoring for Claude
# Provides comprehensive control and logging for Flutter development

# Create log directory if it doesn't exist
LOG_DIR="/tmp/flutter_controller"
mkdir -p "$LOG_DIR"

PIPE="$LOG_DIR/flutter_cmd"
LOG_FILE="$LOG_DIR/flutter_output.log"
PID_FILE="$LOG_DIR/flutter.pid"
STATUS_FILE="$LOG_DIR/flutter_status"
MAX_LOG_SIZE=10485760  # 10MB

# Utility functions
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

update_status() {
    echo "$1|$(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
}

rotate_logs() {
    if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
        # Create archive subdirectory if it doesn't exist
        mkdir -p "$LOG_DIR/archive"
        
        # Create timestamped archive filename
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local archive_file="$LOG_DIR/archive/flutter_output_${timestamp}.log"
        
        log_message "Rotating logs to: $archive_file"
        
        # Copy current log to archive
        cp "$LOG_FILE" "$archive_file"
        
        # Truncate the main log file
        > "$LOG_FILE"
        
        log_message "Log rotation completed - archived and truncated"
    fi
}

setup_flutter_pipe() {
    local device=${1:-"emulator-5554"}
    
    # Clean up any existing setup
    cleanup_flutter_process
    rotate_logs
    
    # Create pipe if needed
    [[ -e "$PIPE" && ! -p "$PIPE" ]] && rm "$PIPE"
    [[ ! -p "$PIPE" ]] && mkfifo "$PIPE"
    
    # Change to Flutter app directory
    cd ../free_flight_log_app ||
    cd /home/kmcisaac/Projects/free_flight_log/free_flight_log_app || {
        log_message "ERROR: Cannot change to Flutter app directory"
        update_status "ERROR"
        return 1
    }
    
    log_message "Starting Flutter on $device in $PWD"
    update_status "STARTING"
    
    # Start Flutter with comprehensive logging
    {
        tail -f "$PIPE" | flutter run -d "$device" 2>&1 | while IFS= read -r line; do
            echo "$line" | tee -a "$LOG_FILE"
            
            # Monitor for specific events
            case "$line" in
                *"Flutter run key commands"*)
                    update_status "RUNNING"
                    ;;
                *"Application finished"*)
                    update_status "STOPPED"
                    ;;
                *"EXCEPTION CAUGHT"*|*"ERROR"*|*"FATAL"*)
                    update_status "ERROR"
                    ;;
                *"Hot reload"*)
                    update_status "HOT_RELOAD"
                    ;;
                *"Hot restart"*)
                    update_status "HOT_RESTART"
                    ;;
            esac
        done
    } &
    
    # Store the background process PID
    echo $! > "$PID_FILE"
    log_message "Flutter controller started with PID: $!"
}

cleanup_flutter_process() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_message "Cleaning up Flutter process (PID: $pid)"
            kill "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
    
    # Clean up any remaining Flutter processes
    pkill -f "flutter run" 2>/dev/null
    pkill -f "tail -f $LOG_DIR/flutter_cmd" 2>/dev/null
    
    update_status "STOPPED"
}

check_flutter_status() {
    local status="UNKNOWN"
    local timestamp=""
    
    if [[ -f "$STATUS_FILE" ]]; then
        IFS='|' read -r status timestamp < "$STATUS_FILE"
    fi
    
    # Verify process is actually running
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ! kill -0 "$pid" 2>/dev/null; then
            status="CRASHED"
            update_status "CRASHED"
        fi
    else
        if [[ "$status" == "RUNNING" ]]; then
            status="STOPPED"
            update_status "STOPPED"
        fi
    fi
    
    echo "Flutter Status: $status"
    if [[ -n "$timestamp" ]]; then
        echo "Last Update: $timestamp"
    fi
    
    # Show recent activity from logs
    if [[ -f "$LOG_FILE" ]]; then
        echo "Recent Activity:"
        tail -n 3 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    fi
    
    case "$status" in
        "RUNNING") return 0 ;;
        "STARTING") return 0 ;;
        "HOT_RELOAD") return 0 ;;
        "HOT_RESTART") return 0 ;;
        "HOT_RELOAD_REQUESTED") return 0 ;;
        "HOT_RESTART_REQUESTED") return 0 ;;
        *) return 1 ;;
    esac
}

send_flutter_command() {
    local cmd="$1"
    if [[ ! -p "$PIPE" ]]; then
        echo "ERROR: Flutter pipe not found. Is Flutter running?"
        return 1
    fi
    
    log_message "Sending command: $cmd"
    echo "$cmd" > "$PIPE"
    
    case "$cmd" in
        "r") update_status "HOT_RELOAD_REQUESTED" ;;
        "R") update_status "HOT_RESTART_REQUESTED" ;;
        "q") 
            update_status "QUIT_REQUESTED"
            sleep 3
            cleanup_flutter_process
            ;;
    esac
}

show_logs() {
    local lines=${1:-50}
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE"
    fi
}

clear_logs() {
    > "$LOG_FILE"
    log_message "Log file cleared by user request"
}

monitor_logs() {
    echo "Monitoring Flutter logs (Ctrl+C to exit)..."
    if [[ -f "$LOG_FILE" ]]; then
        tail -f "$LOG_FILE"
    else
        echo "No log file found. Start Flutter first."
        return 1
    fi
}

restart_flutter() {
    local device=${1:-"emulator-5554"}
    log_message "Restarting Flutter..."
    cleanup_flutter_process
    sleep 2
    setup_flutter_pipe "$device"
}

# Main command handling
case "$1" in
    "run")
        # Check if already running and cleanup if needed
        if check_flutter_status >/dev/null 2>&1; then
            log_message "WARNING: Flutter is already running. Cleaning up and restarting..."
            cleanup_flutter_process
            sleep 2
        fi
        setup_flutter_pipe "$2"
        ;;
    "r")
        # Check if running, auto-start if needed
        if ! check_flutter_status >/dev/null 2>&1; then
            log_message "WARNING: Flutter is not running. Starting Flutter first..."
            cleanup_flutter_process  # Clean up any stale files
            setup_flutter_pipe "emulator-5554"
            sleep 3  # Give Flutter time to start
        else
            rotate_logs
        fi
        send_flutter_command "r"
        ;;
    "R")
        # Check if running, auto-start if needed
        if ! check_flutter_status >/dev/null 2>&1; then
            log_message "WARNING: Flutter is not running. Starting Flutter first..."
            cleanup_flutter_process  # Clean up any stale files
            setup_flutter_pipe "emulator-5554"
            sleep 3  # Give Flutter time to start
        else
            rotate_logs
        fi
        send_flutter_command "R"
        ;;
    "q"|"quit")
        send_flutter_command "q"
        ;;
    "status")
        check_flutter_status
        ;;
    "logs")
        show_logs "$2"
        ;;
    "clear-logs")
        clear_logs
        ;;
    "monitor")
        monitor_logs
        ;;
    "restart")
        restart_flutter "$2"
        ;;
    "cleanup")
        cleanup_flutter_process
        ;;
    *)
        echo "Enhanced Flutter Controller v2.0"
        echo "Usage: $0 {command} [options]"
        echo ""
        echo "Commands:"
        echo "  run [device]     - Start Flutter with logging (default: emulator-5554)"
        echo "  r                - Hot reload"
        echo "  R                - Hot restart"
        echo "  q, quit          - Quit Flutter"
        echo "  status           - Check Flutter status and health"
        echo "  logs [lines]     - Show recent logs (default: 50 lines)"
        echo "  clear-logs       - Clear the log file"
        echo "  monitor          - Monitor logs in real-time"
        echo "  restart [device] - Force restart Flutter"
        echo "  cleanup          - Clean up crashed processes"
        echo ""
        echo "Log Files:"
        echo "  Directory: $LOG_DIR"
        echo "  Output:    $LOG_FILE"
        echo "  Status:    $STATUS_FILE" 
        echo "  PID:       $PID_FILE"
        echo ""
        echo "Examples:"
        echo "  $0 run                    # Start Flutter on default emulator"
        echo "  $0 run chrome             # Start Flutter on Chrome"
        echo "  $0 status                 # Check if Flutter is running"
        echo "  $0 logs 100               # Show last 100 log lines"
        echo "  $0 monitor                # Watch logs in real-time"
        ;;
esac
