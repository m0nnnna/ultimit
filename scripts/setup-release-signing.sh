#!/bin/bash
# One time: make the release signing key and hand it to GitHub (needs gh, logged in as the owner).
#
#   scripts/setup-release-signing.sh
#
# Makes an ed25519 key, stores the private half as the ULTIMIT_SIGNING_KEY secret of a
# `release-signing` environment (runs wait for the owner's approval; only main and v* tags may
# use it), writes the public half to distro/release-signers, and deletes the private key here.
# Commit distro/release-signers afterwards. Running it again replaces the key: PCs then only
# accept releases signed with the new one after they've installed a release carrying it, so
# sign that one release with the old key first.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
REPO=${REPO:-$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ROOT/distro/update-source" | grep -m1 /)}
die() { echo "setup-release-signing: $*" >&2; exit 1; }
command -v gh >/dev/null || die "needs the GitHub CLI: sudo apt install gh && gh auth login"
command -v ssh-keygen >/dev/null || die "needs ssh-keygen: sudo apt install openssh-client"
owner=${REPO%%/*}
id=$(gh api "users/$owner" -q .id)

echo "Environment release-signing on $REPO (approval by $owner)"
gh api -X PUT "repos/$REPO/environments/release-signing" --input - >/dev/null <<JSON
{"reviewers": [{"type": "User", "id": $id}],
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
have=$(gh api "repos/$REPO/environments/release-signing/deployment-branch-policies" -q '.branch_policies[] | .type + ":" + .name')
grep -qx "branch:main" <<<"$have" || gh api -X POST "repos/$REPO/environments/release-signing/deployment-branch-policies" -f name=main -f type=branch >/dev/null
grep -qx "tag:v\*" <<<"$have" || gh api -X POST "repos/$REPO/environments/release-signing/deployment-branch-policies" -f name='v*' -f type=tag >/dev/null

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
ssh-keygen -q -t ed25519 -N "" -C ultimit-release -f "$dir/key"
gh secret set ULTIMIT_SIGNING_KEY -R "$REPO" --env release-signing < "$dir/key"
shred -u "$dir/key" 2>/dev/null || rm -f "$dir/key"
{
	echo "# Who may sign Ultimit releases (ssh-keygen allowed_signers). updates-helper refuses a release"
	echo "# whose .sig doesn't verify against this. Made by scripts/setup-release-signing.sh."
	echo "ultimit-release namespaces=\"ultimit-release\" $(cut -d' ' -f1,2 "$dir/key.pub")"
} > "$ROOT/distro/release-signers"
echo "Done. Public key in distro/release-signers: commit and push it."
