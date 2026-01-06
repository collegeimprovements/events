#!/bin/bash
# Documentation Enhancement Helper Script

LIBRARY=$1

if [ -z "$LIBRARY" ]; then
  echo "======================================================================"
  echo "Documentation Enhancement Helper"
  echo "======================================================================"
  echo ""
  echo "Usage: ./enhance_docs.sh <library_name>"
  echo ""
  echo "Example: ./enhance_docs.sh om_middleware"
  echo ""
  echo "Priority libraries needing enhancement:"
  echo "  1. om_credo      - 0% function docs, 0% examples (CRITICAL)"
  echo "  2. om_middleware - 33% moduledoc, needs examples"
  echo "  3. om_ttyd       - 6% examples"
  echo "  4. om_health     - 0% examples"
  echo "  5. om_scheduler  - 7% examples"
  echo ""
  echo "Quick wins (small libraries):"
  echo "  - om_middleware  (3 files)"
  echo "  - om_ttyd        (4 files)"
  echo "  - om_google      (3 files)"
  echo ""
  exit 1
fi

LIB_PATH="libs/$LIBRARY"

if [ ! -d "$LIB_PATH" ]; then
  echo "Error: Library $LIBRARY not found at $LIB_PATH"
  exit 1
fi

echo "======================================================================"
echo "Analyzing: $LIBRARY"
echo "======================================================================"
echo ""

# Count source files
FILE_COUNT=$(find "$LIB_PATH/lib" -name "*.ex" -type f | wc -l | tr -d ' ')
echo "Source files: $FILE_COUNT"
echo ""

# Count documentation elements
MODULEDOC_COUNT=$(grep -r "@moduledoc \"\"\"" "$LIB_PATH/lib" 2>/dev/null | wc -l | tr -d ' ')
DOC_COUNT=$(grep -r "^  @doc \"\"\"" "$LIB_PATH/lib" 2>/dev/null | wc -l | tr -d ' ')
EXAMPLE_COUNT=$(grep -r "## Examples" "$LIB_PATH/lib" 2>/dev/null | wc -l | tr -d ' ')
SPEC_COUNT=$(grep -r "@spec " "$LIB_PATH/lib" 2>/dev/null | wc -l | tr -d ' ')
PUBLIC_FN_COUNT=$(grep -r "^  def " "$LIB_PATH/lib" 2>/dev/null | wc -l | tr -d ' ')

echo "Current documentation coverage:"
echo "  @moduledoc: $MODULEDOC_COUNT"
echo "  @doc:       $DOC_COUNT / ~$PUBLIC_FN_COUNT public functions"
echo "  Examples:   $EXAMPLE_COUNT"
echo "  @spec:      $SPEC_COUNT"
echo ""

# Calculate rough percentages
if [ "$PUBLIC_FN_COUNT" -gt 0 ]; then
  DOC_PCT=$(echo "scale=0; $DOC_COUNT * 100 / $PUBLIC_FN_COUNT" | bc 2>/dev/null || echo "N/A")
  EXAMPLE_PCT=$(echo "scale=0; $EXAMPLE_COUNT * 100 / $PUBLIC_FN_COUNT" | bc 2>/dev/null || echo "N/A")
  SPEC_PCT=$(echo "scale=0; $SPEC_COUNT * 100 / $PUBLIC_FN_COUNT" | bc 2>/dev/null || echo "N/A")

  echo "Rough coverage percentages:"
  echo "  Function docs: ~${DOC_PCT}%"
  echo "  Examples:      ~${EXAMPLE_PCT}%"
  echo "  Type specs:    ~${SPEC_PCT}%"
  echo ""
fi

echo "Files to enhance:"
echo "----------------------------------------------------------------------"
find "$LIB_PATH/lib" -name "*.ex" -type f | sort
echo ""

echo "======================================================================"
echo "Enhancement Steps"
echo "======================================================================"
echo ""
echo "1. Review the documentation guide:"
echo "   less docs/development/DOCUMENTATION_GUIDE.md"
echo ""
echo "2. Start with the main module:"
echo "   \${EDITOR} $LIB_PATH/lib/$LIBRARY.ex"
echo ""
echo "3. For each public function, add:"
echo "   - @doc with description"
echo "   - ## Parameters section"
echo "   - ## Returns section"
echo "   - ## Examples section (2-3 examples)"
echo "   - @spec type specification"
echo ""
echo "4. Use om_behaviours as a reference:"
echo "   less libs/om_behaviours/lib/om_behaviours/adapter.ex"
echo ""
echo "5. Verify your changes:"
echo "   cd $LIB_PATH"
echo "   mix docs"
echo "   open doc/index.html"
echo ""
echo "6. Re-run coverage analysis:"
echo "   elixir analyze_docs.exs | grep $LIBRARY"
echo ""

# Check if README exists
if [ -f "$LIB_PATH/README.md" ]; then
  README_LINES=$(wc -l < "$LIB_PATH/README.md" | tr -d ' ')
  echo "README.md: $README_LINES lines"
  if [ "$README_LINES" -lt 500 ]; then
    echo "  ⚠️  README could be more comprehensive (< 500 lines)"
  else
    echo "  ✓ README is comprehensive"
  fi
else
  echo "  ⚠️  No README.md found!"
fi

echo ""
echo "======================================================================"
