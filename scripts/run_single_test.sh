#!/bin/bash

# Run a simple test without the Swift Testing framework issues
# This compiles and runs just our XCTest file directly

cd "$(dirname "$0")/.."

echo "🔨 Building Echo library..."
swift build

echo ""
echo "🧪 Compiling and running single test..."

# Compile test file against the built library
swiftc -I .build/debug \
       -L .build/debug \
       -lEcho \
       -framework XCTest \
       Tests/EchoTests/LiveAPIXCTests.swift \
       Tests/EchoTests/TestHelpers.swift \
       -o test_runner

# Run the test
./test_runner

# Clean up
rm -f test_runner
