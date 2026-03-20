#!/usr/bin/env bash
# git remote add github git@github.com:topse/dart_couch.git
set -euo pipefail

REMOTE="github"

# --- Usage ---
usage() {
    echo "Usage: $(basename "$0") <tag-name>"
    echo ""
    echo "Publishes a tagged revision to GitHub as a standalone commit"
    echo "with no history. The tag's file snapshot is pushed as the"
    echo "main branch head on the '${REMOTE}' remote."
    exit 1
}

# --- Validation ---
if [[ $# -ne 1 ]]; then
    usage
fi

TAG="$1"

if ! git rev-parse "$TAG" &>/dev/null; then
    echo "Error: Tag '${TAG}' does not exist."
    exit 1
fi

if ! git remote get-url "$REMOTE" &>/dev/null; then
    echo "Error: Remote '${REMOTE}' is not configured."
    echo "Add it with: git remote add ${REMOTE} <url>"
    exit 1
fi

# --- Publish ---
echo "Publishing ${TAG} to ${REMOTE}..."

TREE=$(git rev-parse "${TAG}^{tree}")
NEW_COMMIT=$(git commit-tree "$TREE" -m "Release ${TAG}")

git push "$REMOTE" "${NEW_COMMIT}:refs/heads/main" --force
echo "Pushed main branch."

git tag --force "github-${TAG}" "$NEW_COMMIT"
git push "$REMOTE" "github-${TAG}" --force
echo "Pushed tag github-${TAG}."

echo ""
echo "Done. Published ${TAG} to ${REMOTE} as an orphan commit."