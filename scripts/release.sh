#!/usr/bin/env bash
# Bump VERSION and CHANGELOG.md, commit them and create the annotated tag.
# Usage: scripts/release.sh <major|minor|patch> [--dry-run]
# Never pushes. RELEASE_SKIP_FORMAT=1 skips the treefmt pass.
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/pedrohrb7/claudinho.nvim"

die() {
  echo "release: $*" >&2
  exit 1
}

usage() {
  echo "usage: scripts/release.sh <major|minor|patch> [--dry-run]" >&2
}

kind=""
dry_run=0
for arg in "$@"; do
  case "$arg" in
  --dry-run) dry_run=1 ;;
  major | minor | patch) kind="$arg" ;;
  *)
    usage
    die "unknown argument: $arg"
    ;;
  esac
done
if [ -z "$kind" ]; then
  usage
  die "missing bump kind (major, minor or patch)"
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$root"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash your changes first"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || die "current branch is '$branch'; releases are made from main"

[ -f VERSION ] || die "VERSION file not found"
current="$(head -n 1 VERSION | tr -d '[:space:]')"
if ! printf '%s\n' "$current" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  die "VERSION is '$current', expected X.Y.Z"
fi

[ -f CHANGELOG.md ] || die "CHANGELOG.md not found"
grep -q '^## \[Unreleased\]' CHANGELOG.md || die "CHANGELOG.md has no '## [Unreleased]' heading"
entries="$(awk '
  /^## \[Unreleased\]/ { inside = 1; next }
  inside && /^## \[/ { exit }
  inside && /^- / { n++ }
  END { print n + 0 }
' CHANGELOG.md)"
[ "$entries" -gt 0 ] || die "the Unreleased section of CHANGELOG.md has no entries (lines starting with '- ')"

IFS=. read -r major minor patch <<EOV
$current
EOV
case "$kind" in
major) next="$((major + 1)).0.0" ;;
minor) next="${major}.$((minor + 1)).0" ;;
patch) next="${major}.${minor}.$((patch + 1))" ;;
esac
tag="v$next"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi

# GitHub repo URL from origin (ssh or https), else the default.
repo_url="$DEFAULT_REPO_URL"
if origin="$(git remote get-url origin 2>/dev/null)"; then
  path="$(printf '%s\n' "$origin" | sed -En 's#^(git@|ssh://git@|https?://([^/@]+@)?)github\.com[:/]+([^/]+/[^/]+)$#\3#p')"
  path="${path%.git}"
  path="${path%/}"
  if [ -n "$path" ]; then
    repo_url="https://github.com/$path"
  fi
fi

today="$(date +%F)"
tmp="$(mktemp "${TMPDIR:-/tmp}/release-changelog.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v ver="$next" -v date="$today" -v url="$repo_url" '
  function links() {
    print "[Unreleased]: " url "/compare/v" ver "...HEAD"
    print "[" ver "]: " url "/releases/tag/v" ver
    done = 1
  }
  /^## \[Unreleased\]/ && !heading {
    print
    print ""
    print "## [" ver "] - " date
    heading = 1
    next
  }
  /^\[Unreleased\]:/ && !done { links(); next }
  /^\[[0-9]+\.[0-9]+\.[0-9]+\]:/ && !done { links() }
  { print }
  END {
    if (!done) {
      print ""
      links()
    }
  }
' CHANGELOG.md >"$tmp"

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run: nothing will be changed."
  echo "Current version: $current"
  echo "New version:     $next ($tag)"
  echo
  echo "CHANGELOG.md diff:"
  diff -u CHANGELOG.md "$tmp" || true
  echo
  echo "Commands that would run:"
  printf '  printf %%s\\n %s > VERSION\n' "'$next'"
  echo "  (write the CHANGELOG.md changes above)"
  echo "  treefmt CHANGELOG.md   # when treefmt is on PATH"
  echo "  git add VERSION CHANGELOG.md"
  echo "  git commit -m 'chore(release): $next'"
  echo "  git tag -a $tag -m 'claudinho.nvim $next'"
  echo "  git push origin main $tag   # you run this one"
  exit 0
fi

cat "$tmp" >CHANGELOG.md
printf '%s\n' "$next" >VERSION

if [ "${RELEASE_SKIP_FORMAT:-0}" != "1" ] && command -v treefmt >/dev/null 2>&1; then
  treefmt CHANGELOG.md
fi

git add VERSION CHANGELOG.md
git commit -q -m "chore(release): $next"
git tag -a "$tag" -m "claudinho.nvim $next"

echo "Released $next: commit and annotated tag $tag created (not pushed)."
echo "Push with:"
echo "  git push origin main $tag"
