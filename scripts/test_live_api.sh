#!/bin/bash

# Script to run live API integration tests
# The API key can be provided via:
#   1. OPENAI_API_KEY environment variable
#   2. .env file in project root

set -e

echo "🔨 Building Echo library..."
swift build

echo ""
echo "🧪 Running live API integration tests..."

# Check if API key is available
if [ -n "$OPENAI_API_KEY" ]; then
    echo "   Using API key from environment: ${OPENAI_API_KEY:0:10}..."
elif [ -f .env ]; then
    echo "   Using API key from .env file"
else
    echo "   ⚠️  No API key found. Tests will be skipped unless key is in .env"
    echo ""
    echo "   To provide API key:"
    echo "     1. Create .env file: cp .env.example .env && edit .env"
    echo "     2. Or set environment: export OPENAI_API_KEY=your-key"
fi
echo ""

# Run the live API tests
swift test --filter LiveAPIXCTests

echo ""
echo "✅ Live API tests completed!"
