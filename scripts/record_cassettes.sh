#!/bin/bash
# record_cassettes.sh
# Records VCR cassettes from real OpenAI API calls

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🎬 VCR Cassette Recording Script${NC}"
echo ""

# Load API key from .env if it exists
if [ -f .env ]; then
    echo "Loading API key from .env file..."
    export $(cat .env | grep OPENAI_API_KEY | xargs)
fi

# Check if API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}❌ Error: OPENAI_API_KEY not set${NC}"
    echo ""
    echo "Please set your OpenAI API key:"
    echo "  export OPENAI_API_KEY=sk-proj-..."
    echo ""
    echo "Get your API key from: https://platform.openai.com/api-keys"
    exit 1
fi

# Verify API key format
if [[ ! "$OPENAI_API_KEY" =~ ^sk-(proj-)?[A-Za-z0-9]{20,} ]]; then
    echo -e "${YELLOW}⚠️  Warning: API key format looks unusual${NC}"
    echo "Expected format: sk-proj-... or sk-..."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}✅ API key configured${NC}"
echo ""

# Estimate cost
echo -e "${YELLOW}💰 Cost Estimate${NC}"
echo "Recording cassettes will make real API calls:"
echo "  • Responses API tests: ~10 calls (~\$0.02)"
echo "  • Total estimated cost: ~\$0.02-0.05"
echo ""
read -p "Continue with recording? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}🔴 Starting cassette recording (saving API responses)...${NC}"
echo ""

# Tests run in REAL API mode by default
# We just need to ensure cassettes are saved
echo "NOTE: Tests will hit real OpenAI API and save responses to cassettes..."

echo "Running Responses API tests..."
swift test --filter "ResponsesAPIRealIntegrationTests" 2>&1 | grep -E "Calling|Saved|Test.*started|passed|failed" || true

echo ""
echo -e "${GREEN}✅ Recording complete!${NC}"
echo ""

# Show recorded cassettes
CASSETTES_DIR="Tests/EchoTests/Fixtures/Cassettes"
if [ -d "$CASSETTES_DIR" ]; then
    echo "📼 Recorded cassettes:"
    ls -lh "$CASSETTES_DIR"/*.json 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'  || echo "  (none found)"
    echo ""
fi

echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Review the cassettes in Tests/EchoTests/Fixtures/Cassettes/"
echo "2. Run tests in playback mode: swift test --filter ResponsesAPIRealIntegrationTests"
echo "3. Commit cassettes: git add Tests/EchoTests/Fixtures/Cassettes/"
echo ""
echo -e "${GREEN}Done! 🎉${NC}"
