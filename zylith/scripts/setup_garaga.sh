#!/bin/bash
# Setup script for Garaga verifier generation
# This script sets up the environment for generating Cairo verifiers from Circom circuits

set -e

echo "=========================================="
echo "Zylith - Garaga Setup Script"
echo "=========================================="
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed"
    echo "Please install Node.js from https://nodejs.org/"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "Error: npm is not installed"
    exit 1
fi

# Install Garaga
echo "Installing Garaga..."
pip install garaga

# Verify Garaga installation
if ! command -v garaga &> /dev/null; then
    echo "Error: Garaga installation failed"
    echo "Try: pip install garaga"
    exit 1
fi

echo "Garaga installed successfully!"
echo "Version: $(garaga --version 2>/dev/null || echo 'installed')"
echo ""

# Setup circuits directory
echo "Setting up circuits directory..."
cd circuits

# Install circuit dependencies
if [ -f "package.json" ]; then
    echo "Installing circuit dependencies..."
    npm install
else
    echo "Warning: package.json not found in circuits directory"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Compile circuits: cd circuits && npm run compile"
echo "2. Run trusted setup: npm run setup"
echo "3. Generate verification keys: npm run generate-keys"
echo "4. Export verification keys: npm run export-vk"
echo "5. Generate Cairo verifiers: npm run generate-garaga"
echo ""
echo "For more information, see: https://github.com/lambdaclass/garaga"
