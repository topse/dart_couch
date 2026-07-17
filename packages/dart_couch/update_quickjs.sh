#!/bin/bash
# Updates the embedded QuickJS source to the latest *release tag* of quickjs-ng.
#
# Usage: ./update_quickjs.sh [tag] [--force]
#
#   tag      Optional explicit tag (e.g. v0.15.1). Default: latest vX.Y.Z tag.
#   --force  Re-download even if CONFIG_VERSION already matches the tag.
#
# This scans the upstream tags, downloads the release source from GitHub,
# replaces the files in third_party/quickjs/, and updates CONFIG_VERSION in
# hook/build.dart. Deliberately never pulls master — releases only, so the
# embedded source is always a reproducible, reviewed upstream state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/third_party/quickjs"
HOOK_FILE="$SCRIPT_DIR/hook/build.dart"
REPO_URL="https://github.com/quickjs-ng/quickjs"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

# ── Parse arguments ──────────────────────────────────────────────────
TAG=""
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    v*) TAG="$arg" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Resolve the target tag ───────────────────────────────────────────
if [ -z "$TAG" ]; then
  echo "Scanning $REPO_URL for the latest release tag..."
  # ls-remote sorts lexically (v0.9.0 > v0.14.0), so sort -V is required.
  TAG=$(git ls-remote --tags "$REPO_URL" 'v*' \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -1)
  [ -n "$TAG" ] || { echo "ERROR: no vX.Y.Z tags found upstream." >&2; exit 1; }
fi

VERSION="${TAG#v}"
echo "Target release: $TAG"

# ── Skip if already up to date ───────────────────────────────────────
# CONFIG_VERSION in hook/build.dart records what is currently embedded.
# (A date there means a legacy unpinned master snapshot -> always update.)
CURRENT=$(sed -n "s/.*'CONFIG_VERSION': '\"\([^\"]*\)\"'.*/\1/p" "$HOOK_FILE" | head -1)
if [ "$CURRENT" = "$VERSION" ] && [ "$FORCE" -eq 0 ]; then
  echo "Already at $TAG (CONFIG_VERSION \"$CURRENT\") — nothing to do. Use --force to re-download."
  exit 0
fi
echo "Currently embedded: \"${CURRENT:-unknown}\""

# ── Download the release tarball ─────────────────────────────────────
echo "Downloading QuickJS $TAG..."
curl -fsSL "$REPO_URL/archive/refs/tags/$TAG.tar.gz" | tar xz -C "$TMP_DIR"

SRC_DIR="$TMP_DIR/quickjs-$VERSION"

if [ ! -f "$SRC_DIR/quickjs.c" ]; then
  echo "ERROR: quickjs.c not found in downloaded archive." >&2
  exit 1
fi

# Sanity check: the tag's source should declare the same version.
if grep -q 'QJS_VERSION_MAJOR' "$SRC_DIR/quickjs.h" 2>/dev/null; then
  MAJOR=$(sed -n 's/#define QJS_VERSION_MAJOR \([0-9]*\)/\1/p' "$SRC_DIR/quickjs.h")
  MINOR=$(sed -n 's/#define QJS_VERSION_MINOR \([0-9]*\)/\1/p' "$SRC_DIR/quickjs.h")
  PATCH=$(sed -n 's/#define QJS_VERSION_PATCH \([0-9]*\)/\1/p' "$SRC_DIR/quickjs.h")
  HEADER_VERSION="$MAJOR.$MINOR.$PATCH"
  if [ "$HEADER_VERSION" != "$VERSION" ]; then
    echo "WARNING: tag $TAG but quickjs.h declares $HEADER_VERSION" >&2
  fi
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

# Update CONFIG_VERSION in hook/build.dart (the "what is embedded" marker
# that the up-to-date check above reads).
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
echo "QuickJS updated to $TAG"
echo "Next steps:"
echo "  1. Run 'dart test' to verify the build still works"
echo "  2. Commit the changes"
