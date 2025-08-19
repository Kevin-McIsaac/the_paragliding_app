import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/preferences_helper.dart';
import 'dart:io';
import '../../data/models/flight.dart';
import '../../data/models/import_result.dart';
import '../widgets/duplicate_flight_dialog.dart';
import '../../services/igc_parser.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';
import '../../services/igc_import_service.dart';
import '../../services/paragliding_earth_api.dart';

class IgcImportScreen extends StatefulWidget {
  final List<String>? initialFiles;
  
  const IgcImportScreen({super.key, this.initialFiles});

  @override
  State<IgcImportScreen> createState() => _IgcImportScreenState();
}

class _IgcImportScreenState extends State<IgcImportScreen> {
  bool _isLoading = false;
  bool _isSelectingFiles = false; // New state for file selection
  String? _selectionStatus; // Status message during selection
  List<String> _selectedFilePaths = [];
  String? _errorMessage;
  final List<ImportResult> _importResults = [];
  String? _currentlyProcessingFile;
  String? _lastFolder;
  final IgcParser _igcParser = IgcParser();
  
  // User preferences for handling duplicates
  bool _skipAllDuplicates = false;
  bool _replaceAllDuplicates = false;
  
  // Preference key is now in PreferencesHelper
  
  @override
  void initState() {
    super.initState();
    _loadLastFolder();
    
    // If initial files were provided (from intent), set them
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _selectedFilePaths = widget.initialFiles!;
      // Automatically start import for shared files
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _importFiles();
      });
    }
  }
  
  Future<void> _loadLastFolder() async {
    final folder = await _getLastFolder();
    if (mounted) {
      setState(() {
        _lastFolder = folder;
      });
    }
  }

  Future<String?> _getLastFolder() async {
    return await PreferencesHelper.getIgcLastFolder();
  }

  Future<void> _saveLastFolder(String filePath) async {
    final directory = File(filePath).parent.path;
    await PreferencesHelper.setIgcLastFolder(directory);
    setState(() {
      _lastFolder = directory;
    });
  }
  
  Future<void> _clearLastFolder() async {
    await PreferencesHelper.removeIgcLastFolder();
    setState(() {
      _lastFolder = null;
    });
  }

  Future<void> _pickIgcFiles() async {
    // Prevent double-clicks while already selecting
    if (_isSelectingFiles) return;
    
    setState(() {
      _isSelectingFiles = true;
      _selectionStatus = "Loading list of selected files...";
      _errorMessage = null; // Clear any previous errors
    });
    
    try {
      // For Android 14+ (API 34+), use a more compatible approach
      FilePickerResult? result;
      
      try {
        // For Android, use withData to ensure file content is accessible
        // Add timeout to prevent permanent UI lock
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['igc', 'IGC'],
          allowMultiple: true,
          withData: false,
          withReadStream: false,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            setState(() {
              _errorMessage = 'File selection timed out. Please try again with fewer files.';
            });
            return null;
          },
        );
      } catch (e) {
        // Fallback: try with any file type and filter manually
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: true,
          withData: false,
          withReadStream: false,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            setState(() {
              _errorMessage = 'File selection timed out. Please try again with fewer files.';
            });
            return null;
          },
        );
        
        // Filter for .igc files manually
        if (result != null) {
          final igcFiles = result.files.where((file) => 
            file.name.toLowerCase().endsWith('.igc') && file.path != null
          ).toList();
          
          if (igcFiles.isEmpty) {
            setState(() {
              _errorMessage = 'No IGC files selected. Please select files with .igc extension.';
            });
            return;
          }
          
          // Create a new result with only IGC files
          result = FilePickerResult(igcFiles);
        }
      }

      // Update status when picker returns
      if (result != null && result.files.isNotEmpty) {
        final fileCount = result.files.length;
        setState(() {
          _selectionStatus = "Processing $fileCount files...";
        });
        
        final validPaths = result.files
            .where((file) => file.path != null)
            .map((file) => file.path!)
            .toList();
        
        // Save the folder of the first selected file for next time (if accessible)
        if (validPaths.isNotEmpty) {
          try {
            await _saveLastFolder(validPaths.first);
          } catch (e) {
            // Ignore folder saving errors on newer Android versions
            // due to scoped storage restrictions
          }
        }
        
        setState(() {
          _selectedFilePaths = validPaths;
          _errorMessage = null;
          _importResults.clear();
          _currentlyProcessingFile = null;
          // Reset duplicate handling preferences for new batch
          _skipAllDuplicates = false;
          _replaceAllDuplicates = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error selecting files: $e';
      });
    } finally {
      // Always clear selection state when done
      setState(() {
        _isSelectingFiles = false;
        _selectionStatus = null;
      });
    }
  }

  Future<void> _importFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _importResults.clear();
      // Reset preferences for this import session
      _skipAllDuplicates = false;
      _replaceAllDuplicates = false;
    });
    
    final databaseService = DatabaseService.instance;
    final importService = IgcImportService.instance;
    
    int processedCount = 0;

    for (final filePath in _selectedFilePaths) {
      setState(() {
        _currentlyProcessingFile = filePath.split('/').last;
      });
      
      try {
        // Phase 1: Quick filename check (no parsing needed)
        final filename = filePath.split('/').last;
        var existingFlight = await importService.checkForDuplicateByFilename(filename);
        bool isFilenameDuplicate = existingFlight != null;
        
        // Phase 2: If no filename match, check by date/time (requires parsing)
        if (existingFlight == null) {
          try {
            existingFlight = await importService.checkForDuplicate(filePath);
          } catch (e) {
            LoggingService.error('IgcImportScreen: Error checking for duplicate', e);
          }
        }
        
        bool shouldReplace = false;
        
        if (existingFlight != null) {
          // Duplicate found - check user preferences
          if (_skipAllDuplicates) {
            // User chose skip all, create skipped result
            final result = ImportResult.skipped(
              fileName: filePath.split('/').last,
              flightDate: existingFlight.date,
              flightTime: existingFlight.launchTime,
              duration: existingFlight.duration,
            );
            setState(() {
              _importResults.add(result);
            });
            continue;
          } else if (_replaceAllDuplicates) {
            shouldReplace = true;
          } else {
            // Show dialog to user
            final action = await _showDuplicateDialog(existingFlight, filePath, isFilenameDuplicate);
            
            if (action == DuplicateAction.skip) {
              // Skip this file
              final result = ImportResult.skipped(
                fileName: filePath.split('/').last,
                flightDate: existingFlight.date,
                flightTime: existingFlight.launchTime,
                duration: existingFlight.duration,
              );
              setState(() {
                _importResults.add(result);
              });
              continue;
            } else if (action == DuplicateAction.skipAll) {
              // Skip this and all remaining duplicates
              setState(() {
                _skipAllDuplicates = true;
              });
              final result = ImportResult.skipped(
                fileName: filePath.split('/').last,
                flightDate: existingFlight.date,
                flightTime: existingFlight.launchTime,
                duration: existingFlight.duration,
              );
              setState(() {
                _importResults.add(result);
              });
              continue;
            } else if (action == DuplicateAction.replace) {
              shouldReplace = true;
            } else if (action == DuplicateAction.replaceAll) {
              // Replace this and all remaining duplicates
              setState(() {
                _replaceAllDuplicates = true;
              });
              shouldReplace = true;
            }
          }
        }
        
        // Import the file (either new or replace)
        final result = await importService.importIgcFileWithDuplicateHandling(
          filePath,
          replace: shouldReplace,
        );
        
        setState(() {
          _importResults.add(result);
        });
        
      } catch (e) {
        final result = ImportResult.failed(
          fileName: filePath.split('/').last,
          errorMessage: e.toString(),
        );
        setState(() {
          _importResults.add(result);
        });
      }
      
      // Increment processed count and cleanup periodically
      processedCount++;
      if ((processedCount % 20) == 0) {
        LoggingService.info('IgcImportScreen: Cleaning up API resources after $processedCount files');
        ParaglidingEarthApi.cleanup();
        // Small delay to ensure cleanup completes
        await Future.delayed(Duration(milliseconds: 100));
      }
    }

    setState(() {
      _currentlyProcessingFile = null;
      _isLoading = false;
    });
    
    // Clean up API resources after batch import
    ParaglidingEarthApi.cleanup();

    // Show results dialog
    if (mounted) {
      await _showResultsDialog();
    }
  }

  /// Show duplicate handling dialog to user
  Future<DuplicateAction?> _showDuplicateDialog(Flight existingFlight, String filePath, bool isFilenameDuplicate) async {
    // Parse the IGC file to get details for comparison
    try {
      // Parse IGC file to get details for comparison
      final igcData = await _igcParser.parseFile(filePath);
      
      // Check if widget is still mounted before using context
      if (!mounted) return DuplicateAction.skip;
      
      return await showDialog<DuplicateAction>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DuplicateFlightDialog(
          existingFlight: existingFlight,
          newFileName: filePath.split('/').last,
          newFlightDate: igcData.date,
          newFlightTime: _formatTime(igcData.launchTime),
          newFlightDuration: igcData.duration,
          isFilenameDuplicate: isFilenameDuplicate,
        ),
      );
    } catch (e) {
      // If we can't parse the file, default to skip
      return DuplicateAction.skip;
    }
  }

  /// Show final results dialog
  Future<void> _showResultsDialog() async {
    final summary = ImportSummary(_importResults);
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(summary.failedCount == 0 ? 'Import Complete' : 'Import Complete with Errors'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.summaryMessage,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              
              // Imported flights
              if (summary.imported.isNotEmpty) ...[
                Text(
                  'Successfully Imported (${summary.importedCount}):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                ...summary.imported.map((result) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${result.fileName} - ${result.flightInfo}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                const SizedBox(height: 12),
              ],
              
              // Replaced flights
              if (summary.replaced.isNotEmpty) ...[
                Text(
                  'Replaced Existing (${summary.replacedCount}):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                ...summary.replaced.map((result) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${result.fileName} - ${result.flightInfo}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                const SizedBox(height: 12),
              ],
              
              // Skipped flights
              if (summary.skipped.isNotEmpty) ...[
                Text(
                  'Skipped (${summary.skippedCount}):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                ...summary.skipped.map((result) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${result.fileName} - ${result.flightInfo}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                const SizedBox(height: 12),
              ],
              
              // Failed imports
              if (summary.failed.isNotEmpty) ...[
                Text(
                  'Failed (${summary.failedCount}):',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                ...summary.failed.map((result) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${result.fileName}: ${result.errorMessage}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();  // Close dialog
              Navigator.of(context).pop(true); // Always return to flight list
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import IGC File'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IGC File Import',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Import flight data from IGC files recorded by your flight instrument. You can select multiple files at once.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    if (_lastFolder != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Default folder: ${_lastFolder!.split('/').last}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: _clearLastFolder,
                              tooltip: 'Clear default folder',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (_isLoading || _isSelectingFiles) ? null : _pickIgcFiles,
                      icon: _isSelectingFiles
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          )
                        : const Icon(Icons.folder_open),
                      label: Text(_isSelectingFiles 
                        ? 'Selecting Files...' 
                        : 'Select IGC Files'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    if (_selectionStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _selectionStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            if (_selectedFilePaths.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file, size: 48),
                      title: Text('Selected Files (${_selectedFilePaths.length})'),
                      trailing: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _selectedFilePaths.clear();
                            _importResults.clear();
                            _currentlyProcessingFile = null;
                            _skipAllDuplicates = false;
                            _replaceAllDuplicates = false;
                          });
                        },
                      ),
                    ),
                    if (_selectedFilePaths.length <= 5) 
                      ...(_selectedFilePaths.map((path) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.description, size: 20),
                        title: Text(
                          path.split('/').last,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )))
                    else ...[
                      ...(_selectedFilePaths.take(3).map((path) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.description, size: 20),
                        title: Text(
                          path.split('/').last,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.more_horiz, size: 20),
                        title: Text(
                          'and ${_selectedFilePaths.length - 3} more files...',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_isLoading && _currentlyProcessingFile != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Processing: $_currentlyProcessingFile'),
                      const SizedBox(height: 4),
                      Text(
                        'Processed ${_importResults.length} of ${_selectedFilePaths.length} files',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const Spacer(),

            if (_selectedFilePaths.isNotEmpty)
              ElevatedButton(
                onPressed: _isLoading ? null : _importFiles,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _selectedFilePaths.length == 1 
                          ? 'Import Flight' 
                          : 'Import ${_selectedFilePaths.length} Flights',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}