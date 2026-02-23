#!/bin/bash
# Package the autonomy skill for distribution

VERSION="${1:-1.0.0}"
SKILL_DIR="$(dirname $(dirname $0))"
OUTPUT_DIR="${2:-.}"

echo "Packaging autonomy skill v${VERSION}..."

cd "$SKILL_DIR"

# Create distribution
tar czf "${OUTPUT_DIR}/autonomy-${VERSION}.tar.gz" \
  --exclude='logs/*' \
  --exclude='*.tar.gz' \
  --exclude='.git' \
  .

echo ""
echo "✓ Packaged: ${OUTPUT_DIR}/autonomy-${VERSION}.tar.gz"
echo ""
echo "To share with a friend:"
echo "  1. Send them the .tar.gz file"
echo "  2. They extract to ~/.openclaw/workspace/skills/autonomy"
echo "  3. They run: ~/.openclaw/workspace/skills/autonomy/scripts/install.sh"
echo ""
echo "Or publish to ClawHub:"
echo "  clawhub login"
echo "  clawhub publish ${SKILL_DIR} --slug autonomy --version ${VERSION}"
