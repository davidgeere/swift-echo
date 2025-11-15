#!/bin/bash

# Generate release notes for manual GitHub Release creation
# Usage: ./scripts/generate-release-notes.sh [tag]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get tag from argument or find latest
if [ -z "$1" ]; then
    TAG=$(git describe --tags --abbrev=0)
    echo "Using latest tag: ${GREEN}$TAG${NC}"
else
    TAG=$1
fi

# Extract version number
VERSION=${TAG#v}

# Get release notes from CHANGELOG.md
echo ""
echo "Extracting release notes for version ${GREEN}$VERSION${NC}..."
echo ""

RELEASE_NOTES=$(awk -v version="$VERSION" '
    /^## \[/ {
        if (found) exit
        if ($0 ~ version) {
            found = 1
            next
        }
    }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md)

# Create release notes file
OUTPUT_FILE="release-notes-$VERSION.md"

cat > "$OUTPUT_FILE" << EOF
# Swift Echo $VERSION

$RELEASE_NOTES

## Installation

Add to your \`Package.swift\`:

\`\`\`swift
dependencies: [
    .package(url: "https://github.com/davidgeere/swift-echo.git", from: "$VERSION")
]
\`\`\`

## What's New

See the [CHANGELOG](https://github.com/davidgeere/swift-echo/blob/$TAG/CHANGELOG.md) for full details.

---

**Full Documentation:** [README](https://github.com/davidgeere/swift-echo/blob/$TAG/README.md)
EOF

echo "${GREEN}✅ Release notes generated: $OUTPUT_FILE${NC}"
echo ""
echo "${BLUE}To create a GitHub Release manually:${NC}"
echo "  1. Go to: https://github.com/davidgeere/swift-echo/releases/new"
echo "  2. Select tag: ${GREEN}$TAG${NC}"
echo "  3. Title: ${GREEN}Swift Echo $VERSION${NC}"
echo "  4. Copy and paste the contents of ${GREEN}$OUTPUT_FILE${NC}"
echo "  5. Click 'Publish release'"
echo ""
echo "${YELLOW}Contents of release notes:${NC}"
echo "----------------------------------------"
cat "$OUTPUT_FILE"
echo "----------------------------------------"
