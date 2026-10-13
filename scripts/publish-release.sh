#!/bin/bash
# Publish an Ultimit release on GitHub, where every Ultimit PC's Settings > Updates finds it.
#
#   scripts/publish-release.sh v0.2.0 [--notes FILE] [--draft]
#
# Before: commit everything, then install this checkout on this machine so /opt/ultimit is built
# from exactly what is being released (it tags HEAD first if the tag doesn't exist yet):
#   git tag -a v0.2.0 -m "Ultimit 0.2.0" && scripts/install.sh --no-apps --keep-login-screen
# Then this builds the precompiled release (scripts/build-release.sh), pushes the tag and uploads
# ultimit-0.2.0-amd64.tar.gz + .sha256 to a GitHub release (needs gh, logged in).
# Version numbers only go up: an update is offered when the release is newer than what is installed.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
TAG=${1:-}
shift || true
NOTES="" DRAFT=()
while [ $# -gt 0 ]; do
	case "$1" in
	--notes) NOTES=$2; shift ;;
	--draft) DRAFT=(--draft) ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
die() { echo "publish-release: $*" >&2; exit 1; }
[[ "$TAG" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] || die "give a version tag like v0.2.0"
command -v gh >/dev/null || die "needs the GitHub CLI: sudo apt install gh && gh auth login"
cd "$ROOT"
[ -z "$(git status --porcelain)" ] || die "commit (or stash) your changes first"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	git tag -a "$TAG" -m "Ultimit ${TAG#v}"
	echo "Tagged HEAD as $TAG"
fi
[ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || die "$TAG isn't HEAD: check it out first"
installed=$(cat /opt/ultimit/VERSION 2>/dev/null || echo none)
[ "$installed" = "$TAG" ] || die "/opt/ultimit is $installed, not $TAG: run scripts/install.sh --no-apps --keep-login-screen first"

dist="$ROOT/dist"
mkdir -p "$dist"
"$ROOT/scripts/build-release.sh" "$dist"
tarball="$dist/ultimit-${TAG#v}-amd64.tar.gz"
[ -f "$tarball" ] || die "build-release.sh didn't make $tarball"

git push origin "$TAG"
notes=(--generate-notes)
[ -n "$NOTES" ] && notes=(--notes-file "$NOTES")
gh release create "$TAG" "$tarball" "$tarball.sha256" --title "Ultimit ${TAG#v}" "${notes[@]}" "${DRAFT[@]}"
echo "Published $TAG. Ultimit PCs see it in Settings > Updates."
