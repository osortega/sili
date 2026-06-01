#!/usr/bin/env bash
# scripts/release.sh — cut a new sili release end-to-end.
#
# Tags origin/main, computes the GitHub tarball's sha256, then opens a PR
# against the Homebrew tap with the bumped formula. Idempotent enough to
# rerun on failure (re-running with an existing tag will refuse).
#
# Usage: scripts/release.sh <version>
#   e.g. scripts/release.sh 0.1.3
#        scripts/release.sh v0.1.3   (leading 'v' is stripped)
#
# Env overrides:
#   SILI_REPO         default: osortega/sili
#   TAP_REPO          default: osortega/homebrew-tap
#   TAP_FORMULA_PATH  default: Formula/sili.rb

set -euo pipefail

SILI_REPO=${SILI_REPO:-osortega/sili}
TAP_REPO=${TAP_REPO:-osortega/homebrew-tap}
TAP_FORMULA_PATH=${TAP_FORMULA_PATH:-Formula/sili.rb}

VERSION=${1:-}
if [[ -z $VERSION ]]; then
  echo "usage: $(basename "$0") <version>  (e.g. 0.1.3)" >&2
  exit 64
fi
VERSION=${VERSION#v}
TAG="v${VERSION}"

log()  { printf '\033[1;34m[release]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[release]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[release]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] \
  || die "version must be semver (e.g. 0.1.3 or 1.0.0-rc1), got: $VERSION"

command -v gh     >/dev/null || die "gh not installed"
command -v curl   >/dev/null || die "curl not installed"
command -v shasum >/dev/null || die "shasum not installed"

gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"

cd "$(git rev-parse --show-toplevel)"

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
[[ $branch == main ]] || die "not on main (currently: ${branch:-detached}); run: git checkout main"

git diff --quiet && git diff --cached --quiet \
  || die "working tree not clean; commit or stash first"

log "fetching origin/main"
git fetch --quiet origin main

[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] \
  || die "local main is not in sync with origin/main; pull/rebase first"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists locally; bump the version or delete the tag"
fi

if git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
  die "tag $TAG already exists on origin"
fi

gh repo view "$TAP_REPO" >/dev/null 2>&1 \
  || die "cannot access $TAP_REPO (check gh auth scopes / repo name)"

# --- tag + push ------------------------------------------------------------

last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
notes=""
if [[ -n $last_tag ]]; then
  notes=$(git log --pretty=format:'- %s' "${last_tag}..HEAD")
fi

log "tagging $TAG"
if [[ -n $notes ]]; then
  git tag -a "$TAG" -m "$TAG" -m "$notes"
else
  git tag -a "$TAG" -m "$TAG"
fi

log "pushing $TAG to origin"
git push origin "$TAG"

# --- compute sha256 of the GitHub-generated tarball -----------------------

URL="https://github.com/${SILI_REPO}/archive/refs/tags/${TAG}.tar.gz"

log "waiting for tarball at $URL"
ok=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sILf -o /dev/null "$URL"; then
    ok=1
    break
  fi
  sleep 3
done
(( ok )) || die "tarball never became available at $URL"

log "computing sha256"
SHA=$(curl -sLf "$URL" | shasum -a 256 | awk '{print $1}')
[[ ${#SHA} -eq 64 ]] || die "could not compute sha256 (got: $SHA)"
log "sha256: $SHA"

# --- update the tap, push a branch, open a PR -----------------------------

TAP_DIR=$(mktemp -d -t sili-tap-XXXXXX)
TAP_BRANCH="bump-sili-${VERSION}"

log "cloning $TAP_REPO into $TAP_DIR"
gh repo clone "$TAP_REPO" "$TAP_DIR" >/dev/null
cd "$TAP_DIR"

[[ -f $TAP_FORMULA_PATH ]] \
  || die "$TAP_FORMULA_PATH not found in tap; expected the formula at this path"

if git ls-remote --heads origin "$TAP_BRANCH" | grep -q .; then
  die "branch $TAP_BRANCH already exists on the tap remote; delete it or bump the version"
fi

git checkout -b "$TAP_BRANCH" >/dev/null

log "rewriting url + sha256 in $TAP_FORMULA_PATH"
# -E for extended regex (works on both BSD and GNU sed). -i.bak for the
# same reason. URL/SHA contain no sed-special chars, so direct interpolation
# is safe; use | as delimiter so the / in URLs doesn't clash.
sed -E -i.bak \
  -e "s|^([[:space:]]*url[[:space:]]+).*|\\1\"${URL}\"|" \
  -e "s|^([[:space:]]*sha256[[:space:]]+).*|\\1\"${SHA}\"|" \
  "$TAP_FORMULA_PATH"
rm -f "${TAP_FORMULA_PATH}.bak"

grep -qF "$URL" "$TAP_FORMULA_PATH" || die "url substitution failed; inspect $TAP_DIR/$TAP_FORMULA_PATH"
grep -qF "$SHA" "$TAP_FORMULA_PATH" || die "sha256 substitution failed; inspect $TAP_DIR/$TAP_FORMULA_PATH"

if git diff --quiet "$TAP_FORMULA_PATH"; then
  die "formula did not change after edit; perhaps it's already at $TAG?"
fi

git add "$TAP_FORMULA_PATH"
git commit -m "Bump sili to ${TAG}" >/dev/null
git push -u origin "$TAP_BRANCH" >/dev/null

log "opening PR on $TAP_REPO"
pr_body_file=$(mktemp)
{
  printf 'Bumps sili to `%s`.\n\n' "$TAG"
  printf '- url: `%s`\n'   "$URL"
  printf '- sha256: `%s`\n\n' "$SHA"
  printf 'Release: https://github.com/%s/releases/tag/%s\n' "$SILI_REPO" "$TAG"
  if [[ -n $notes ]]; then
    printf '\n## Changes since %s\n\n%s\n' "$last_tag" "$notes"
  fi
} > "$pr_body_file"

pr_url=$(gh pr create -R "$TAP_REPO" \
  --title "Bump sili to ${TAG}" \
  --body-file "$pr_body_file" \
  --head "$TAP_BRANCH")

rm -f "$pr_body_file"

log "PR: $pr_url"
log "done. tap working copy left at: $TAP_DIR"
