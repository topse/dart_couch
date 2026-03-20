#!/bin/bash
# Updates the embedded QuickJS source to the latest version from the main branch.
#
# Usage: ./update_quickjs.sh
#
# This downloads the quickjs-ng source from GitHub, replaces the files in
# third_party/quickjs/, and updates CONFIG_VERSION in hook/build.dart.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/third_party/quickjs"
REPO_URL="https://github.com/quickjs-ng/quickjs"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading latest QuickJS from $REPO_URL (master branch)..."
curl -sL "$REPO_URL/archive/refs/heads/master.tar.gz" | tar xz -C "$TMP_DIR"

SRC_DIR="$TMP_DIR/quickjs-master"

if [ ! -f "$SRC_DIR/quickjs.c" ]; then
  echo "ERROR: quickjs.c not found in downloaded archive." >&2
  exit 1
fi

# Preserve our .gitignore if it exists
GITIGNORE_BAK=""
if [ -f "$TARGET_DIR/.gitignore" ]; then
  GITIGNORE_BAK=$(mktemp)
  cp "$TARGET_DIR/.gitignore" "$GITIGNORE_BAK"
fi

echo "Replacing $TARGET_DIR with new sources..."
rm -rf "$TARGET_DIR"
cp -r "$SRC_DIR" "$TARGET_DIR"

# Remove files we don't need (tests, CI, build configs for standalone build)
rm -rf "$TARGET_DIR/.github" \
       "$TARGET_DIR/.git" \
       "$TARGET_DIR/.gitignore" \
       "$TARGET_DIR/.gitattributes" \
       "$TARGET_DIR/.gitmodules" \
       "$TARGET_DIR/test262" \
       "$TARGET_DIR/tests"

# Restore .gitignore if we had one
if [ -n "$GITIGNORE_BAK" ]; then
  mv "$GITIGNORE_BAK" "$TARGET_DIR/.gitignore"
fi

# Extract version from quickjs.h or VERSION file
VERSION=""
if [ -f "$TARGET_DIR/VERSION" ]; then
  VERSION=$(cat "$TARGET_DIR/VERSION" | tr -d '[:space:]')
elif grep -q 'QUICKJS_VERSION_STRING' "$TARGET_DIR/quickjs.h" 2>/dev/null; then
  VERSION=$(grep 'QUICKJS_VERSION_STRING' "$TARGET_DIR/quickjs.h" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$VERSION" ]; then
  VERSION=$(date +%Y-%m-%d)
  echo "Could not detect version, using today's date: $VERSION"
fi

# Update CONFIG_VERSION in hook/build.dart
HOOK_FILE="$SCRIPT_DIR/hook/build.dart"
if [ -f "$HOOK_FILE" ]; then
  sed -i "s/'CONFIG_VERSION': '\"[^\"]*\"'/'CONFIG_VERSION': '\"$VERSION\"'/" "$HOOK_FILE"
  echo "Updated CONFIG_VERSION to \"$VERSION\" in hook/build.dart"
fi

# Verify critical files exist
MISSING=0
for f in quickjs.c quickjs.h dtoa.c libregexp.c libunicode.c; do
  if [ ! -f "$TARGET_DIR/$f" ]; then
    echo "WARNING: Expected file missing: $f" >&2
    MISSING=1
  fi
done

if [ "$MISSING" -eq 1 ]; then
  echo "Some expected source files are missing. Check if upstream renamed them." >&2
  exit 1
fi

echo ""
echo "QuickJS updated to $VERSION"
echo "Next steps:"
echo "  1. Run 'dart test' to verify the build still works"
echo "  2. Commit the changes"
