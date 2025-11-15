#!/bin/bash

# Create a GitHub Release from an existing tag
# Requires: GitHub CLI (gh) to be installed and authenticated
# Usage: ./scripts/create-release.sh v1.1.0

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "${RED}GitHub CLI (gh) is not installed!${NC}"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Get tag from argument or find latest
if [ -z "$1" ]; then
    TAG=$(git describe --tags --abbrev=0)
    echo "No tag specified, using latest: ${GREEN}$TAG${NC}"
else
    TAG=$1
fi

# Check if tag exists
if ! git rev-list "$TAG" &> /dev/null; then
    echo "${RED}Tag $TAG does not exist!${NC}"
    exit 1
fi

# Extract version number (remove 'v' prefix if present)
VERSION=${TAG#v}

# Get release notes from CHANGELOG.md
echo "Extracting release notes from CHANGELOG.md..."

# Extract the release notes for this version
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

if [ -z "$RELEASE_NOTES" ]; then
    echo "${YELLOW}No release notes found in CHANGELOG.md for version $VERSION${NC}"
    RELEASE_NOTES="Release $VERSION"
fi

# Create temporary file with release notes
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF
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

echo ""
echo "Creating GitHub Release for ${GREEN}$TAG${NC}..."
echo ""

# Create the release
gh release create "$TAG" \
    --title "Swift Echo $VERSION" \
    --notes-file "$TEMP_FILE" \
    --verify-tag

# Clean up
rm "$TEMP_FILE"

echo ""
echo "${GREEN}✅ GitHub Release created successfully!${NC}"
echo ""
echo "View it at: https://github.com/davidgeere/swift-echo/releases/tag/$TAG"
echo ""

# Optional: Open in browser
read -p "Open release in browser? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    gh release view "$TAG" --web
fi
