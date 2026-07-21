#!/usr/bin/env bash

readonly RELEASE_TAG_RULESET_ID=14378754
readonly RELEASE_BRANCH_RULESET_ID=19321162
readonly RELEASE_APP_SLUG=buzz-release-bot

fail_release_ruleset() {
  echo "Error: $*" >&2
  return 1
}

require_canonical_repository() {
  local origin_url canonical_remote="${BUZZ_RELEASE_CANONICAL_REMOTE:-}"

  origin_url="$(git remote get-url origin 2>/dev/null)" || \
    fail_release_ruleset "origin is required and must point to block/buzz" || return 1
  if [[ "${BUZZ_RELEASE_CONTRACT_TEST:-}" == "1" && -n "$canonical_remote" && "$origin_url" == "$canonical_remote" ]]; then
    return 0
  fi
  case "$origin_url" in
    git@github.com:block/buzz.git|ssh://git@github.com/block/buzz.git|https://github.com/block/buzz.git|https://github.com/block/buzz)
      ;;
    *)
      fail_release_ruleset "origin must point to canonical block/buzz, not '$origin_url'" || return 1
      ;;
  esac
}

require_release_tag_ruleset() {
  local ruleset_endpoint state app_id bypass_actors rule_types includes excludes

  command -v gh >/dev/null 2>&1 || fail_release_ruleset "gh is required" || return 1
  ruleset_endpoint="repos/block/buzz/rulesets/$RELEASE_TAG_RULESET_ID"

  state="$(gh api "$ruleset_endpoint" --jq .enforcement)" || \
    fail_release_ruleset "could not verify Release tag ruleset $RELEASE_TAG_RULESET_ID" || return 1
  [[ "$state" == "active" ]] || \
    fail_release_ruleset "Release tag ruleset $RELEASE_TAG_RULESET_ID is '$state'" || return 1

  app_id="$(gh api "/apps/$RELEASE_APP_SLUG" --jq .id)" || \
    fail_release_ruleset "could not resolve the $RELEASE_APP_SLUG App" || return 1
  [[ "$app_id" =~ ^[1-9][0-9]*$ ]] || \
    fail_release_ruleset "$RELEASE_APP_SLUG returned an invalid App ID" || return 1

  bypass_actors="$(
    gh api "$ruleset_endpoint" \
      --jq '[.bypass_actors[] | "\(.actor_type):\(.actor_id):\(.bypass_mode)"] | sort | join(",")'
  )" || fail_release_ruleset "could not verify the $RELEASE_APP_SLUG ruleset bypass" || return 1
  [[ "$bypass_actors" == "Integration:$app_id:always" ]] || \
    fail_release_ruleset "Release tag ruleset $RELEASE_TAG_RULESET_ID has unexpected bypass actors: '$bypass_actors'" || return 1

  rule_types="$(gh api "$ruleset_endpoint" --jq '[.rules[].type] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Release tag ruleset $RELEASE_TAG_RULESET_ID rules" || return 1
  [[ "$rule_types" == "creation,deletion,non_fast_forward,update" ]] || \
    fail_release_ruleset "Release tag ruleset $RELEASE_TAG_RULESET_ID has unexpected rules: '$rule_types'" || return 1

  includes="$(gh api "$ruleset_endpoint" --jq '[.conditions.ref_name.include[]] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Release tag ruleset $RELEASE_TAG_RULESET_ID scope" || return 1
  [[ ",$includes," == *",refs/tags/mobile-v*,"* ]] || \
    fail_release_ruleset "Release tag ruleset $RELEASE_TAG_RULESET_ID does not include refs/tags/mobile-v*" || return 1

  excludes="$(gh api "$ruleset_endpoint" --jq '[.conditions.ref_name.exclude[]] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Release tag ruleset $RELEASE_TAG_RULESET_ID exclusions" || return 1
  [[ -z "$excludes" ]] || \
    fail_release_ruleset "Release tag ruleset $RELEASE_TAG_RULESET_ID has unexpected exclusions: '$excludes'" || return 1
}

require_release_branch_ruleset() {
  local ruleset_endpoint state rule_types includes excludes

  command -v gh >/dev/null 2>&1 || fail_release_ruleset "gh is required" || return 1
  ruleset_endpoint="repos/block/buzz/rulesets/$RELEASE_BRANCH_RULESET_ID"

  state="$(gh api "$ruleset_endpoint" --jq .enforcement)" || \
    fail_release_ruleset "could not verify Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID" || return 1
  [[ "$state" == "active" ]] || \
    fail_release_ruleset "Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID is '$state'" || return 1

  rule_types="$(gh api "$ruleset_endpoint" --jq '[.rules[].type] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID rules" || return 1
  [[ "$rule_types" == "deletion,non_fast_forward" ]] || \
    fail_release_ruleset "Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID has unexpected rules: '$rule_types'" || return 1

  includes="$(gh api "$ruleset_endpoint" --jq '[.conditions.ref_name.include[]] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID scope" || return 1
  [[ "$includes" == "refs/heads/mobile-release/*" ]] || \
    fail_release_ruleset "Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID has unexpected scope: '$includes'" || return 1

  excludes="$(gh api "$ruleset_endpoint" --jq '[.conditions.ref_name.exclude[]] | sort | join(",")')" || \
    fail_release_ruleset "could not verify Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID exclusions" || return 1
  [[ -z "$excludes" ]] || \
    fail_release_ruleset "Mobile Release Branches ruleset $RELEASE_BRANCH_RULESET_ID has unexpected exclusions: '$excludes'" || return 1
}
