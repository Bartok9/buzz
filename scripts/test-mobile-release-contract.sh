#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/mobile-release.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
remote="$tmp/remote.git"
work="$tmp/work"
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$1:$2" in
  api:repos/{owner}/{repo}/rulesets/14378754) printf '%s\n' "${GH_RULESET_STATE:-active}" ;;
  release:view) exit 1 ;;
  release:create) printf '%s\n' "$*" > "$GH_CAPTURE" ;;
  *) exit 2 ;;
esac
GH
chmod +x "$bin/gh"
export PATH="$bin:$PATH"
git init -q --bare "$remote"
git init -q "$work"
git -C "$work" config user.name test
git -C "$work" config user.email test@example.com
git -C "$work" remote add origin "$remote"
echo first > "$work/file"
git -C "$work" add file
git -C "$work" commit -qm first
git -C "$work" branch -M main
git -C "$work" push -q -u origin main

(
  cd "$work"
  "$script" start 1.2.3
)
[[ "$(git --git-dir="$remote" rev-parse refs/heads/mobile-release/1.2.3)" == \
   "$(git -C "$work" rev-parse main)" ]]

# Candidate tags always point at the remote release branch, not the operator's
# current checkout, and sequence monotonically without moving an old tag.
echo second >> "$work/file"
git -C "$work" commit -qam second
git -C "$work" push -q origin HEAD:refs/heads/mobile-release/1.2.3
(
  cd "$work"
  "$script" candidate 1.2.3
  "$script" candidate 1.2.3
)
branch_sha="$(git --git-dir="$remote" rev-parse refs/heads/mobile-release/1.2.3)"
[[ "$(git --git-dir="$remote" rev-parse 'refs/tags/mobile-v1.2.3-rc.1^{commit}')" == "$branch_sha" ]]
[[ "$(git --git-dir="$remote" rev-parse 'refs/tags/mobile-v1.2.3-rc.2^{commit}')" == "$branch_sha" ]]

# Authoritative candidates are blocked until the tag ruleset is active.
if (
  cd "$work"
  GH_RULESET_STATE=disabled "$script" candidate 1.2.3 >/dev/null 2>&1
); then
  echo "candidate was published with tag protection disabled" >&2
  exit 1
fi
if git --git-dir="$remote" rev-parse --verify refs/tags/mobile-v1.2.3-rc.3 >/dev/null 2>&1; then
  echo "disabled-ruleset attempt created a candidate tag" >&2
  exit 1
fi

# The script must verify the existing tag, record the tested candidate, and
# never create a stable mobile-vX.Y.Z tag.
(
  export GH_CAPTURE="$tmp/gh-call"
  cd "$work"
  "$script" finalize 1.2.3-rc.2
)
grep -Fq 'release create mobile-v1.2.3-rc.2 --verify-tag' "$tmp/gh-call"
if git --git-dir="$remote" rev-parse --verify refs/tags/mobile-v1.2.3 >/dev/null 2>&1; then
  echo "finalization created a stable alias tag" >&2
  exit 1
fi

# A lightweight candidate tag is rejected. Candidate identity must carry an
# immutable annotated tag object, not only a commit ref.
git -C "$work" -c tag.gpgSign=false tag mobile-v1.2.3-rc.3 main
git -C "$work" push -q origin refs/tags/mobile-v1.2.3-rc.3
if GH_CAPTURE="$tmp/lightweight-gh-call" PATH="$bin:$PATH" \
    "$script" finalize 1.2.3-rc.3 >/dev/null 2>&1; then
  echo "lightweight candidate tag was accepted" >&2
  exit 1
fi

# A candidate outside the matching release branch is rejected at finalization.
git -C "$work" tag -m "unrelated candidate" mobile-v1.2.3-rc.4 main
git -C "$work" push -q origin refs/tags/mobile-v1.2.3-rc.4
if GH_CAPTURE="$tmp/bad-gh-call" PATH="$bin:$PATH" \
    "$script" finalize 1.2.3-rc.4 >/dev/null 2>&1; then
  echo "unrelated candidate tag was accepted" >&2
  exit 1
fi

grep -Fq 'version: 0.0.0+1' "$repo_root/mobile/pubspec.yaml"
if grep -qE 'release-mobile|bump-mobile-version|get-current-mobile-version' "$repo_root/Justfile"; then
  echo "metadata-only mobile release recipe remains in Justfile" >&2
  exit 1
fi

echo "mobile release contract passed"
