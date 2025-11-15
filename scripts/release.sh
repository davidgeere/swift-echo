#!/bin/bash

# Release script for Swift Echo
# Usage: ./scripts/release.sh [major|minor|patch] "Release message"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current version from Version.swift
VERSION_FILE="Sources/Echo/Version.swift"
CURRENT_VERSION=$(grep "public static let current = Version" "$VERSION_FILE" | sed -E 's/.*major: ([0-9]+), minor: ([0-9]+), patch: ([0-9]+).*/\1.\2.\3/')

echo "Current version: ${GREEN}v$CURRENT_VERSION${NC}"

# Parse current version
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# Determine bump type
BUMP_TYPE=${1:-patch}
RELEASE_MESSAGE=${2:-"Release version"}

# Calculate new version
case $BUMP_TYPE in
    major)
        NEW_MAJOR=$((MAJOR + 1))
        NEW_MINOR=0
        NEW_PATCH=0
        ;;
    minor)
        NEW_MAJOR=$MAJOR
        NEW_MINOR=$((MINOR + 1))
        NEW_PATCH=0
        ;;
    patch)
        NEW_MAJOR=$MAJOR
        NEW_MINOR=$MINOR
        NEW_PATCH=$((PATCH + 1))
        ;;
    *)
        echo "${RED}Invalid bump type. Use: major, minor, or patch${NC}"
        exit 1
        ;;
esac

NEW_VERSION="$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"
echo "New version: ${GREEN}v$NEW_VERSION${NC}"

# Ask for confirmation
echo ""
echo "${YELLOW}This will:${NC}"
echo "  1. Update Version.swift to $NEW_VERSION"
echo "  2. Update CHANGELOG.md"
echo "  3. Commit the changes"
echo "  4. Create tag v$NEW_VERSION"
echo "  5. Push to origin"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "${RED}Aborted${NC}"
    exit 1
fi

# Update Version.swift
echo "Updating Version.swift..."
sed -i '' "s/Version(major: $MAJOR, minor: $MINOR, patch: $PATCH)/Version(major: $NEW_MAJOR, minor: $NEW_MINOR, patch: $NEW_PATCH)/" "$VERSION_FILE"

# Update build date
TODAY=$(date +%Y-%m-%d)
sed -i '' "s/date: \".*\"/date: \"$TODAY\"/" "$VERSION_FILE"

# Update CHANGELOG.md - Add new unreleased section
echo "Updating CHANGELOG.md..."
cat > CHANGELOG.tmp.md << EOF
# Changelog

All notable changes to Swift Echo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [$NEW_VERSION] - $TODAY

### Added
- (Add your changes here)

### Changed
- (Add your changes here)

### Fixed
- (Add your changes here)

EOF

# Append the rest of the changelog
tail -n +9 CHANGELOG.md >> CHANGELOG.tmp.md
mv CHANGELOG.tmp.md CHANGELOG.md

# Commit changes
echo "Committing changes..."
git add "$VERSION_FILE" CHANGELOG.md
git commit -m "chore: Release version $NEW_VERSION

$RELEASE_MESSAGE"

# Create tag
echo "Creating tag v$NEW_VERSION..."
git tag -a "v$NEW_VERSION" -m "Release version $NEW_VERSION

$RELEASE_MESSAGE"

# Push changes
echo "Pushing to origin..."
git push origin main
git push origin "v$NEW_VERSION"

echo ""
echo "${GREEN}✅ Successfully released version $NEW_VERSION!${NC}"
echo ""

# Create GitHub Release
if command -v gh &> /dev/null; then
    read -p "Create GitHub Release? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./scripts/create-release.sh "v$NEW_VERSION"
    else
        echo "To create a GitHub Release later, run:"
        echo "  ${YELLOW}./scripts/create-release.sh v$NEW_VERSION${NC}"
    fi
else
    echo "${YELLOW}GitHub CLI not installed. To create a release:${NC}"
    echo "  1. Install GitHub CLI: https://cli.github.com/"
    echo "  2. Run: ./scripts/create-release.sh v$NEW_VERSION"
fi

echo ""
echo "Next steps:"
echo "  1. Announce the release"
echo "  2. Update documentation if needed"
echo ""
echo "To publish to Swift Package Index:"
echo "  The package will be automatically indexed from the tag"
