#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

REMOTE="${RELEASE_REMOTE:-origin}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid VERSION: $VERSION" >&2
    exit 1
fi
TAG="v$VERSION"

git rev-parse --is-inside-work-tree >/dev/null
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Cannot publish from a detached HEAD." >&2
    exit 1
}

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit all release changes first:" >&2
    git status --short >&2
    exit 1
fi

COMMITTED_VERSION="$(git show HEAD:VERSION | tr -d '[:space:]')"
if [[ "$COMMITTED_VERSION" != "$VERSION" ]]; then
    echo "VERSION $VERSION is not committed at HEAD." >&2
    exit 1
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Remote tag $TAG already exists on $REMOTE." >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    TAG_COMMIT="$(git rev-list -n 1 "$TAG")"
    HEAD_COMMIT="$(git rev-parse HEAD)"
    if [[ "$TAG_COMMIT" != "$HEAD_COMMIT" ]]; then
        echo "Local tag $TAG points to a different commit." >&2
        exit 1
    fi
else
    git tag -a "$TAG" -m "BoomPet $TAG"
fi

echo "Pushing $BRANCH and publishing $TAG..."
git push "$REMOTE" "HEAD:$BRANCH"
git push "$REMOTE" "$TAG"

echo "Published tag $TAG."
echo "GitHub Actions will build and create the Release:"
echo "https://github.com/vinfolhu/boom/actions"
