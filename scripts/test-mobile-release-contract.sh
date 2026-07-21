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
  api:repos/block/buzz/rulesets/14378754)
    case "$*" in
      *'.enforcement'*) printf '%s\n' "${GH_TAG_RULESET_STATE:-active}" ;;
      *'.bypass_actors[]'*) printf '%s\n' "${GH_BYPASS_ACTORS:-Integration:4349119:always}" ;;
      *'[.rules[].type]'*) printf '%s\n' "${GH_TAG_RULE_TYPES:-creation,deletion,non_fast_forward,update}" ;;
      *'.conditions.ref_name.include[]'*) printf '%s\n' "${GH_TAG_INCLUDES:-refs/tags/mobile-v*}" ;;
      *'.conditions.ref_name.exclude[]'*) printf '%s\n' "${GH_TAG_EXCLUDES:-}" ;;
      *) exit 2 ;;
    esac
    ;;
  api:repos/block/buzz/rulesets/19321162)
    case "$*" in
      *'.enforcement'*) printf '%s\n' "${GH_BRANCH_RULESET_STATE:-active}" ;;
      *'[.rules[].type]'*) printf '%s\n' "${GH_BRANCH_RULE_TYPES:-deletion,non_fast_forward}" ;;
      *'.conditions.ref_name.include[]'*) printf '%s\n' "${GH_BRANCH_INCLUDES:-refs/heads/mobile-release/*}" ;;
      *'.conditions.ref_name.exclude[]'*) printf '%s\n' "${GH_BRANCH_EXCLUDES:-}" ;;
      *) exit 2 ;;
    esac
    ;;
  api:/apps/buzz-release-bot) printf '%s\n' 4349119 ;;
  workflow:run)
    version=""
    number=""
    sha=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        version=*) version="${1#version=}" ;;
        candidate_number=*) number="${1#candidate_number=}" ;;
        target_sha=*) sha="${1#target_sha=}" ;;
      esac
      shift
    done
    [[ -n "$version" && -n "$number" && -n "$sha" ]]
    printf '%s\t%s\t%s\n' "$version" "$number" "$sha" >> "$GH_WORKFLOW_CAPTURE"
    if [[ "${GH_WORKFLOW_NO_URL:-}" == "1" ]]; then
      exit 0
    fi
    printf 'https://github.com/block/buzz/actions/runs/%s\n' "$number"
    ;;
  run:watch)
    [[ "${GH_WORKFLOW_FAIL:-}" != "1" ]] || exit 1
    number="$3"
    IFS=$'\t' read -r version expected sha < <(tail -n 1 "$GH_WORKFLOW_CAPTURE")
    [[ "$number" == "$expected" ]]
    git -C "$GH_WORKTREE" tag -m "Buzz Mobile $version release candidate $expected" \
      "mobile-v${version}-rc.${expected}" "$sha"
    git -C "$GH_WORKTREE" push -q origin "refs/tags/mobile-v${version}-rc.${expected}"
    ;;
  release:view) exit 1 ;;
  release:create) printf '%s\n' "$*" > "$GH_CAPTURE" ;;
  *) exit 2 ;;
esac
GH
chmod +x "$bin/gh"
export PATH="$bin:$PATH"
export GH_WORKFLOW_CAPTURE="$tmp/workflow-dispatches"
export GH_WORKTREE="$work"
export BUZZ_RELEASE_CONTRACT_TEST=1
export BUZZ_RELEASE_CANONICAL_REMOTE="$remote"
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

# Start must work from a stale operator clone by fetching the remotely resolved
# source commit before creating the local release branch.
operator="$tmp/operator"
git clone -q "$remote" "$operator"
git -C "$operator" config user.name test
git -C "$operator" config user.email test@example.com
echo remote-only >> "$work/file"
git -C "$work" commit -qam remote-only
git -C "$work" push -q origin main
remote_main_sha="$(git --git-dir="$remote" rev-parse refs/heads/main)"
if git -C "$operator" cat-file -e "$remote_main_sha^{commit}" 2>/dev/null; then
  echo "stale-clone fixture already contains the remote-only commit" >&2
  exit 1
fi
(
  cd "$operator"
  "$script" start 1.2.3
)
[[ "$(git --git-dir="$remote" rev-parse refs/heads/mobile-release/1.2.3)" == \
   "$remote_main_sha" ]]
git -C "$work" fetch -q origin refs/heads/mobile-release/1.2.3

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
[[ "$(git --git-dir="$remote" cat-file -t refs/tags/mobile-v1.2.3-rc.1)" == "tag" ]]
[[ "$(git --git-dir="$remote" cat-file -t refs/tags/mobile-v1.2.3-rc.2)" == "tag" ]]
grep -Fq $'1.2.3\t1\t' "$GH_WORKFLOW_CAPTURE"
grep -Fq $'1.2.3\t2\t' "$GH_WORKFLOW_CAPTURE"

# A failed App-backed workflow is surfaced and does not publish a candidate.
if (
  cd "$work"
  GH_WORKFLOW_FAIL=1 "$script" candidate 1.2.3 >/dev/null 2>&1
); then
  echo "candidate succeeded despite a failed App-backed workflow" >&2
  exit 1
fi
if git --git-dir="$remote" rev-parse --verify refs/tags/mobile-v1.2.3-rc.3 >/dev/null 2>&1; then
  echo "failed App-backed workflow created a candidate tag" >&2
  exit 1
fi

# A dispatch without an attributable run URL fails closed instead of guessing
# which concurrent workflow run to watch.
if (
  cd "$work"
  GH_WORKFLOW_NO_URL=1 "$script" candidate 1.2.3 >/dev/null 2>&1
); then
  echo "candidate succeeded without a workflow run URL" >&2
  exit 1
fi
if git --git-dir="$remote" rev-parse --verify refs/tags/mobile-v1.2.3-rc.3 >/dev/null 2>&1; then
  echo "URL-less dispatch created a candidate tag" >&2
  exit 1
fi

# A selected candidate remains valid after the release branch advances. This is
# the normal finalization shape when later fixes or RCs landed after testing.
echo third >> "$work/file"
git -C "$work" commit -qam third
git -C "$work" push -q origin HEAD:refs/heads/mobile-release/1.2.3
advanced_branch_sha="$(git --git-dir="$remote" rev-parse refs/heads/mobile-release/1.2.3)"
[[ "$advanced_branch_sha" != "$branch_sha" ]]

# Authoritative candidates are blocked until the tag ruleset is active.
if (
  cd "$work"
  GH_TAG_RULESET_STATE=disabled "$script" candidate 1.2.3 >/dev/null 2>&1
); then
  echo "candidate was published with tag protection disabled" >&2
  exit 1
fi
if git --git-dir="$remote" rev-parse --verify refs/tags/mobile-v1.2.3-rc.3 >/dev/null 2>&1; then
  echo "disabled-ruleset attempt created a candidate tag" >&2
  exit 1
fi

# Finalization also fails closed if tag protection is disabled.
if (
  cd "$work"
  GH_TAG_RULESET_STATE=disabled GH_CAPTURE="$tmp/disabled-finalize-gh-call" \
    "$script" finalize 1.2.3-rc.2 >/dev/null 2>&1
); then
  echo "candidate was finalized with tag protection disabled" >&2
  exit 1
fi
[[ ! -e "$tmp/disabled-finalize-gh-call" ]]

# Every command is bound to canonical block/buzz rather than the ambient clone.
wrong_repo="$tmp/wrong-repo"
git clone -q "$remote" "$wrong_repo"
git -C "$wrong_repo" remote set-url origin https://github.com/attacker/buzz.git
if (
  cd "$wrong_repo"
  unset BUZZ_RELEASE_CANONICAL_REMOTE
  "$script" candidate 1.2.3 >/dev/null 2>&1
); then
  echo "candidate accepted a non-canonical origin" >&2
  exit 1
fi

# Candidate publication also fails closed when either ruleset's required scope
# or rule contract drifts.
for scenario in \
  'GH_TAG_INCLUDES=refs/tags/v*' \
  'GH_TAG_EXCLUDES=refs/tags/mobile-v0.0.0' \
  'GH_BYPASS_ACTORS=Integration:4349119:pull_request' \
  'GH_BRANCH_RULESET_STATE=disabled' \
  'GH_BRANCH_RULE_TYPES=deletion' \
  'GH_BRANCH_INCLUDES=refs/heads/main' \
  'GH_BRANCH_EXCLUDES=refs/heads/mobile-release/0.0.0'
do
  if (
    cd "$work"
    eval "$scenario \"$script\" candidate 1.2.3 >/dev/null 2>&1"
  ); then
    echo "candidate accepted drifted ruleset contract: $scenario" >&2
    exit 1
  fi
done

# A failed branch publication does not strand the local release branch.
failing_operator="$tmp/failing-operator"
git clone -q "$remote" "$failing_operator"
git -C "$failing_operator" config user.name test
git -C "$failing_operator" config user.email test@example.com
cat > "$failing_operator/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$failing_operator/.git/hooks/pre-push"
if (
  cd "$failing_operator"
  git config core.hooksPath .git/hooks
  "$script" start 9.9.9 >/dev/null 2>&1
); then
  echo "start succeeded despite a rejected push" >&2
  exit 1
fi
if git -C "$failing_operator" show-ref --verify --quiet refs/heads/mobile-release/9.9.9; then
  echo "failed start stranded a local release branch" >&2
  exit 1
fi
if git --git-dir="$remote" show-ref --verify --quiet refs/heads/mobile-release/9.9.9; then
  echo "failed start published a remote release branch" >&2
  exit 1
fi

# The script must verify the existing non-tip tag, record the tested candidate,
# and never create a stable mobile-vX.Y.Z tag.
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
