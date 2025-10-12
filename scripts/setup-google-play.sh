#!/bin/bash

# Setup script for Google Play deployment
# This script helps you configure the necessary secrets for automated deployment

set -e

echo "==========================================="
echo "Google Play Deployment Setup"
echo "==========================================="
echo ""
echo "This script will help you set up automated deployment to Google Play Store."
echo ""
echo "Prerequisites:"
echo "1. Google Play Developer Account"
echo "2. Published app on Google Play (at least internal testing)"
echo "3. Service account JSON from Google Cloud Console"
echo "4. GitHub repository with admin access"
echo ""

# Function to check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) is not installed."
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
}

# Function to check if user is authenticated with gh
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        echo "You are not authenticated with GitHub CLI."
        echo "Run: gh auth login"
        exit 1
    fi
}

# Function to add a GitHub secret
add_secret() {
    local name=$1
    local value=$2
    local repo=$3

    echo "Adding secret: $name"
    echo "$value" | gh secret set "$name" --repo "$repo"
}

# Main setup
main() {
    check_gh_cli
    check_gh_auth

    # Get repository
    read -p "Enter your GitHub repository (owner/repo): " REPO

    echo ""
    echo "Step 1: Service Account Setup"
    echo "------------------------------"
    echo "1. Go to: https://play.google.com/console"
    echo "2. Navigate to: Setup → API access"
    echo "3. Create a service account and download the JSON key"
    echo ""
    read -p "Enter the path to your service account JSON file: " SERVICE_ACCOUNT_PATH

    if [ ! -f "$SERVICE_ACCOUNT_PATH" ]; then
        echo "Error: File not found: $SERVICE_ACCOUNT_PATH"
        exit 1
    fi

    # Read service account JSON
    SERVICE_ACCOUNT_JSON=$(cat "$SERVICE_ACCOUNT_PATH")

    echo ""
    echo "Step 2: App Signing Configuration"
    echo "---------------------------------"
    echo "Choose your signing method:"
    echo "1. Google Play App Signing (recommended)"
    echo "2. Self-managed signing"
    read -p "Enter choice (1 or 2): " SIGNING_CHOICE

    if [ "$SIGNING_CHOICE" = "2" ]; then
        echo ""
        echo "Self-managed signing setup:"
        read -p "Enter path to your keystore file: " KEYSTORE_PATH

        if [ ! -f "$KEYSTORE_PATH" ]; then
            echo "Error: Keystore file not found: $KEYSTORE_PATH"
            exit 1
        fi

        # Base64 encode the keystore
        KEYSTORE_BASE64=$(base64 -i "$KEYSTORE_PATH" | tr -d '\n')

        read -sp "Enter keystore password: " KEYSTORE_PASSWORD
        echo ""
        read -p "Enter key alias: " KEY_ALIAS
        read -sp "Enter key password: " KEY_PASSWORD
        echo ""
    fi

    echo ""
    echo "Step 3: API Keys Configuration"
    echo "-------------------------------"
    echo "These are the same API keys from your .env file"
    echo ""

    # Check if .env file exists
    if [ -f "the_paragliding_app/.env" ]; then
        echo "Found .env file. Reading API keys..."
        source the_paragliding_app/.env

        read -p "Use FFVL_API_KEY from .env? (y/n): " USE_ENV
        if [ "$USE_ENV" != "y" ]; then
            read -p "Enter FFVL API key: " FFVL_API_KEY
        fi

        read -p "Use other keys from .env? (y/n): " USE_OTHER_ENV
        if [ "$USE_OTHER_ENV" != "y" ]; then
            read -p "Enter Google Maps API key (optional): " GOOGLE_MAPS_API_KEY
            read -p "Enter OpenAIP API key (optional): " OPENAIP_API_KEY
            read -p "Enter Cesium Ion token (optional): " CESIUM_ION_TOKEN
        fi
    else
        read -p "Enter FFVL API key: " FFVL_API_KEY
        read -p "Enter Google Maps API key (optional): " GOOGLE_MAPS_API_KEY
        read -p "Enter OpenAIP API key (optional): " OPENAIP_API_KEY
        read -p "Enter Cesium Ion token (optional): " CESIUM_ION_TOKEN
    fi

    echo ""
    echo "Step 4: Adding Secrets to GitHub"
    echo "---------------------------------"

    # Add service account JSON
    add_secret "PLAY_STORE_SERVICE_ACCOUNT_JSON" "$SERVICE_ACCOUNT_JSON" "$REPO"

    # Add signing secrets if self-managed
    if [ "$SIGNING_CHOICE" = "2" ]; then
        add_secret "ANDROID_KEYSTORE" "$KEYSTORE_BASE64" "$REPO"
        add_secret "ANDROID_KEYSTORE_PASSWORD" "$KEYSTORE_PASSWORD" "$REPO"
        add_secret "ANDROID_KEY_ALIAS" "$KEY_ALIAS" "$REPO"
        add_secret "ANDROID_KEY_PASSWORD" "$KEY_PASSWORD" "$REPO"
    fi

    # Add API keys
    [ -n "$FFVL_API_KEY" ] && add_secret "FFVL_API_KEY" "$FFVL_API_KEY" "$REPO"
    [ -n "$GOOGLE_MAPS_API_KEY" ] && add_secret "GOOGLE_MAPS_API_KEY" "$GOOGLE_MAPS_API_KEY" "$REPO"
    [ -n "$OPENAIP_API_KEY" ] && add_secret "OPENAIP_API_KEY" "$OPENAIP_API_KEY" "$REPO"
    [ -n "$CESIUM_ION_TOKEN" ] && add_secret "CESIUM_ION_TOKEN" "$CESIUM_ION_TOKEN" "$REPO"

    echo ""
    echo "✅ Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Ensure your app is published on Google Play (at least internal testing)"
    echo "2. Grant permissions to the service account in Play Console"
    echo "3. Create a version tag to trigger deployment: git tag v1.0.0 && git push --tags"
    echo "4. Or manually trigger the workflow from GitHub Actions tab"
    echo ""
    echo "For more details, see GOOGLE_PLAY_DEPLOYMENT.md"
}

# Run main function
main