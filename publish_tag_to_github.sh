#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# publish-to-github.sh
#
# Publishes a tagged revision to GitHub as a single squashed commit on
# the local 'github-release' branch. Each release is parented on the
# previous one, producing a clean linear history on GitHub with no
# private development details.
#
# Prerequisites:
#   git remote add github git@github.com:<user>/<repo>.git
#
# Usage:
#   ./publish-to-github.sh <tag-name>
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly REMOTE="github"
readonly RELEASE_BRANCH="github-release"

# ── Helpers ──────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") <tag-name>

Publishes the file snapshot of <tag-name> as a new commit on the
'${RELEASE_BRANCH}' branch and pushes it to the '${REMOTE}' remote.

GitHub sees a clean linear history — one commit per release, no
development noise.
EOF
    exit 1
}

die() {
    echo "Error: $1" >&2
    exit 1
}

# ── Validation ───────────────────────────────────────────────────────

[[ $# -eq 1 ]] || usage

readonly TAG="$1"

git rev-parse "${TAG}^{commit}" &>/dev/null \
    || die "Tag '${TAG}' does not exist or is not a valid commit-ish."

git remote get-url "${REMOTE}" &>/dev/null \
    || die "Remote '${REMOTE}' is not configured. Add it with:\n  git remote add ${REMOTE} <url>"

# ── Resolve source commit ───────────────────────────────────────────

readonly SOURCE_COMMIT=$(git rev-parse "${TAG}^{commit}")
readonly SOURCE_TREE=$(git rev-parse "${TAG}^{tree}")
readonly SOURCE_MSG=$(git log -1 --format='%B' "${SOURCE_COMMIT}")

# ── Ensure the release branch exists ────────────────────────────────

if ! git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}"; then
    # Local branch missing — fetch remote to see if it already has history
    echo "Local '${RELEASE_BRANCH}' branch not found, fetching from '${REMOTE}'..."
    git fetch "${REMOTE}" main 2>/dev/null || true
    if git show-ref --verify --quiet "refs/remotes/${REMOTE}/main"; then
        echo "Rebuilding '${RELEASE_BRANCH}' from ${REMOTE}/main..."
        git update-ref "refs/heads/${RELEASE_BRANCH}" "$(git rev-parse ${REMOTE}/main)"
    fi
fi

if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}"; then
    readonly PARENT_COMMIT=$(git rev-parse "${RELEASE_BRANCH}")
    readonly PARENT_TREE=$(git rev-parse "${RELEASE_BRANCH}^{tree}")

    if [[ "${SOURCE_TREE}" == "${PARENT_TREE}" ]]; then
        die "Tree for '${TAG}' is identical to the current ${RELEASE_BRANCH} head. Nothing to publish."
    fi

    readonly NEW_COMMIT=$(git commit-tree "${SOURCE_TREE}" \
        -p "${PARENT_COMMIT}" \
        -m "${SOURCE_MSG}")
else
    echo "Creating '${RELEASE_BRANCH}' branch (first release)..."
    readonly NEW_COMMIT=$(git commit-tree "${SOURCE_TREE}" \
        -m "${SOURCE_MSG}")
fi

# ── Update local branch ref (no checkout needed) ────────────────────

git update-ref "refs/heads/${RELEASE_BRANCH}" "${NEW_COMMIT}"

# ── Push to GitHub ───────────────────────────────────────────────────

echo "Pushing ${TAG} → ${REMOTE}/main ..."

git push "${REMOTE}" "${RELEASE_BRANCH}:refs/heads/main" --force-with-lease
git tag --force "github-${TAG}" "${NEW_COMMIT}"
git push "${REMOTE}" "github-${TAG}" --force

# ── Summary ──────────────────────────────────────────────────────────

cat <<EOF

✔ Published ${TAG} to ${REMOTE}
  Source commit : ${SOURCE_COMMIT:0:12}
  Release commit: ${NEW_COMMIT:0:12}
  Branch        : ${RELEASE_BRANCH} → ${REMOTE}/main
  Tag           : github-${TAG}
EOF
