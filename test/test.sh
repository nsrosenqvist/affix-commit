#!/usr/bin/env bash
# affix-commit test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AFFIX_COMMIT="${PROJECT_DIR}/affix-commit"

# shellcheck source=test/framework.sh
source "${SCRIPT_DIR}/framework.sh"

# --- Helpers ---

# Create a temporary git repo on a given branch, returning the repo path
# Usage: repo=$(setup_repo "feature/PROJ-123-my-feature")
setup_repo() {
  local branch_name="$1"
  local tmp
  tmp="$(mktemp -d)"

  git -C "${tmp}" init -b "${branch_name}" --quiet
  git -C "${tmp}" config user.email "test@test.com"
  git -C "${tmp}" config user.name "Test"

  # Need at least one commit so HEAD exists
  touch "${tmp}/.gitkeep"
  git -C "${tmp}" add .gitkeep
  git -C "${tmp}" commit -m "init" --quiet

  echo "${tmp}"
}

# Write a commit message file and run affix-commit against it
# Usage: run_hook <repo_path> <message> [config_content]
# Returns: exit code; modifies $hook_output and the commit message file
run_hook() {
  local repo="$1"
  local message="$2"
  local config="${3:-}"

  local msg_file="${repo}/.git/COMMIT_EDITMSG"
  printf '%s' "${message}" > "${msg_file}"

  if [[ -n "${config}" ]]; then
    printf '%s\n' "${config}" > "${repo}/.affix-commit.cfg"
  else
    rm -f "${repo}/.affix-commit.cfg"
  fi

  local exit_code=0
  (cd "${repo}" && bash "${AFFIX_COMMIT}" "${msg_file}" 2>&1) || exit_code=$?

  return ${exit_code}
}

# Read the commit message file after hook ran
read_msg() {
  local repo="$1"
  cat "${repo}/.git/COMMIT_EDITMSG"
}

cleanup_repo() {
  rm -rf "$1"
}

# ============================================================================
# TESTS
# ============================================================================

# --- Conventional commit with existing scope ---
describe "Conventional commit with single scope"
repo=$(setup_repo "feature/PROJ-123-add-login")
run_hook "${repo}" "chore(deps): update dependencies"
result=$(read_msg "${repo}")
assert_eq "chore(deps, PROJ-123): update dependencies" "${result}" "ticket appended to existing scope"
cleanup_repo "${repo}"

# --- Hyphenated scope ---
describe "Conventional commit with hyphenated scope"
repo=$(setup_repo "feature/PROJ-123-add-login")
run_hook "${repo}" "feat(new-service): add endpoint"
result=$(read_msg "${repo}")
assert_eq "feat(new-service, PROJ-123): add endpoint" "${result}" "ticket appended to hyphenated scope"
cleanup_repo "${repo}"

# --- Multiple existing scopes ---
describe "Conventional commit with multiple scopes"
repo=$(setup_repo "feature/PROJ-123-update")
run_hook "${repo}" "feat(scope1,scope2, scope3): big change"
result=$(read_msg "${repo}")
assert_eq "feat(scope1,scope2, scope3, PROJ-123): big change" "${result}" "ticket appended after multiple scopes"
cleanup_repo "${repo}"

# --- Conventional commit without scope ---
describe "Conventional commit without scope"
repo=$(setup_repo "feature/PROJ-123-add-login")
run_hook "${repo}" "feat: add login page"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123): add login page" "${result}" "ticket inserted as scope"
cleanup_repo "${repo}"

# --- Breaking change marker preserved ---
describe "Breaking change marker preserved"
repo=$(setup_repo "feature/PROJ-123-breaking")
run_hook "${repo}" "feat!: remove deprecated API"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123)!: remove deprecated API" "${result}" "bang preserved after scope"
cleanup_repo "${repo}"

# --- Breaking change with existing scope ---
describe "Breaking change with existing scope"
repo=$(setup_repo "feature/PROJ-123-breaking")
run_hook "${repo}" "feat(api)!: remove deprecated endpoint"
result=$(read_msg "${repo}")
assert_eq "feat(api, PROJ-123)!: remove deprecated endpoint" "${result}" "bang preserved with scope"
cleanup_repo "${repo}"

# --- Ticket already in message (no duplication) ---
describe "Ticket already in message"
repo=$(setup_repo "feature/PROJ-123-add-login")
run_hook "${repo}" "feat(PROJ-123): already tagged"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123): already tagged" "${result}" "message unchanged when ticket present"
cleanup_repo "${repo}"

# --- Non-conventional message gets wrapped ---
describe "Non-conventional message"
repo=$(setup_repo "feature/PROJ-123-fix-bug")
run_hook "${repo}" "fixed the login bug"
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-123): fixed the login bug" "${result}" "plain message wrapped in conventional format"
cleanup_repo "${repo}"

# --- Comment lines are skipped ---
describe "Comment lines skipped"
repo=$(setup_repo "feature/PROJ-123-fix")
run_hook "${repo}" $'# This is a comment\nchore(fix): resolve issue'
result=$(read_msg "${repo}")
assert_eq $'# This is a comment\nchore(fix, PROJ-123): resolve issue' "${result}" "comment preserved, next line modified"
cleanup_repo "${repo}"

# --- Empty/verbose commit generates conventional message ---
describe "Empty commit with only comments (verbose mode)"
repo=$(setup_repo "feature/PROJ-123-wip")
run_hook "${repo}" $'# Please enter the commit message\n# Changes to be committed:\n# ------------------------ >8 ------------------------'
result=$(read_msg "${repo}")
assert_contains "${result}" "chore(PROJ-123): wip" "generated conventional commit for empty message"
cleanup_repo "${repo}"

# --- Completely empty message ---
describe "Completely empty commit message"
repo=$(setup_repo "feature/PROJ-123-wip")
run_hook "${repo}" ""
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-123): wip" "${result}" "generated placeholder for empty message"
cleanup_repo "${repo}"

# --- Ignored branch (main) ---
describe "Ignored branch: main"
repo=$(setup_repo "main")
# Need to be on main — setup_repo already puts us there
run_hook "${repo}" "feat: some change"
result=$(read_msg "${repo}")
assert_eq "feat: some change" "${result}" "message unchanged on ignored branch"
cleanup_repo "${repo}"

# --- Ignored branch (develop) ---
describe "Ignored branch: develop"
repo=$(setup_repo "develop")
run_hook "${repo}" "fix: something"
result=$(read_msg "${repo}")
assert_eq "fix: something" "${result}" "message unchanged on develop"
cleanup_repo "${repo}"

# --- Custom ignored branches via config ---
describe "Custom ignored branches pattern"
repo=$(setup_repo "feature/PROJ-123-test")
run_hook "${repo}" "feat(scope): change" "ignored_branches='^feature/PROJ-123-test$'"
result=$(read_msg "${repo}")
assert_eq "feat(scope): change" "${result}" "custom ignored pattern matches"
cleanup_repo "${repo}"

# --- Non-ignored branch with custom pattern ---
describe "Custom ignored pattern does not match other branches"
repo=$(setup_repo "feature/PROJ-123-other")
run_hook "${repo}" "feat(scope): change" "ignored_branches='^release/.*$'"
result=$(read_msg "${repo}")
assert_eq "feat(scope, PROJ-123): change" "${result}" "non-matching branch is processed"
cleanup_repo "${repo}"

# --- Missing ticket with ignore_missing_tickets=false (default) ---
describe "Missing ticket — error by default"
repo=$(setup_repo "feature/no-ticket-here")
exit_code=0
run_hook "${repo}" "feat: change" || exit_code=$?
assert_eq "1" "${exit_code}" "exits with code 1 when no ticket found"
result=$(read_msg "${repo}")
assert_eq "feat: change" "${result}" "message unchanged on error"
cleanup_repo "${repo}"

# --- Missing ticket with ignore_missing_tickets=true ---
describe "Missing ticket — ignored when configured"
repo=$(setup_repo "feature/no-ticket-here")
run_hook "${repo}" "feat: change" "ignore_missing_tickets=true"
result=$(read_msg "${repo}")
assert_eq "feat: change" "${result}" "message unchanged when missing tickets ignored"
cleanup_repo "${repo}"

# --- Custom ticket pattern ---
describe "Custom ticket pattern"
repo=$(setup_repo "feature/proj-123-lowercase")
run_hook "${repo}" "feat: change" "ticket_pattern='[a-z]+-[0-9]+'"
result=$(read_msg "${repo}")
assert_eq "feat(proj-123): change" "${result}" "custom lowercase ticket pattern works"
cleanup_repo "${repo}"

# --- Ticket in middle of branch name ---
describe "Ticket in middle of branch name"
repo=$(setup_repo "feature/PROJ-456-implement-auth")
run_hook "${repo}" "feat: implement auth"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-456): implement auth" "${result}" "ticket extracted from middle of branch"
cleanup_repo "${repo}"

# --- Ticket at end of branch name ---
describe "Ticket at end of branch name"
repo=$(setup_repo "fix-bug-PROJ-789")
run_hook "${repo}" "fix: resolve crash"
result=$(read_msg "${repo}")
assert_eq "fix(PROJ-789): resolve crash" "${result}" "ticket extracted from end of branch"
cleanup_repo "${repo}"

# --- No commit msg file argument ---
describe "No arguments provided"
repo=$(setup_repo "feature/PROJ-123-test")
exit_code=0
(cd "${repo}" && bash "${AFFIX_COMMIT}" 2>/dev/null) || exit_code=$?
assert_eq "1" "${exit_code}" "exits with code 1 when no file arg"
cleanup_repo "${repo}"

# --- Multiline commit message ---
describe "Multiline commit message"
repo=$(setup_repo "feature/PROJ-123-multiline")
run_hook "${repo}" $'feat: add feature\n\nThis is a detailed description\nof the changes made.'
result=$(read_msg "${repo}")
expected=$'feat(PROJ-123): add feature\n\nThis is a detailed description\nof the changes made.'
assert_eq "${expected}" "${result}" "only first line modified, body preserved"
cleanup_repo "${repo}"

# --- Multiline with comments interspersed ---
describe "Multiline with comments before content"
repo=$(setup_repo "feature/PROJ-123-comments")
run_hook "${repo}" $'# comment 1\n# comment 2\nfix: resolve bug\n\nMore details here'
result=$(read_msg "${repo}")
expected=$'# comment 1\n# comment 2\nfix(PROJ-123): resolve bug\n\nMore details here'
assert_eq "${expected}" "${result}" "comments preserved, first content line modified"
cleanup_repo "${repo}"

# --- Config from home directory fallback ---
describe "Config from home directory fallback"
repo=$(setup_repo "feature/proj-999-home-config")
# Write config to a temporary HOME
fake_home="$(mktemp -d)"
printf "ticket_pattern='[a-z]+-[0-9]+'\n" > "${fake_home}/.affix-commit.cfg"
msg_file="${repo}/.git/COMMIT_EDITMSG"
printf '%s' "feat: change" > "${msg_file}"
rm -f "${repo}/.affix-commit.cfg"
(cd "${repo}" && HOME="${fake_home}" bash "${AFFIX_COMMIT}" "${msg_file}" 2>&1) || true
result=$(cat "${msg_file}")
assert_eq "feat(proj-999): change" "${result}" "config loaded from HOME fallback"
rm -rf "${fake_home}"
cleanup_repo "${repo}"

# --- Detached HEAD exits silently ---
describe "Detached HEAD"
repo=$(setup_repo "feature/PROJ-123-detach")
# Detach HEAD
git -C "${repo}" checkout --detach --quiet
msg_file="${repo}/.git/COMMIT_EDITMSG"
printf '%s' "feat: change" > "${msg_file}"
exit_code=0
(cd "${repo}" && bash "${AFFIX_COMMIT}" "${msg_file}" 2>&1) || exit_code=$?
result=$(cat "${msg_file}")
assert_eq "0" "${exit_code}" "exits with 0 on detached HEAD"
assert_eq "feat: change" "${result}" "message unchanged on detached HEAD"
cleanup_repo "${repo}"

# --- Security: config with dangerous values is rejected ---
describe "Config security: command injection rejected"
repo=$(setup_repo "feature/PROJ-123-security")
# Write a malicious config
# shellcheck disable=SC2016
printf 'ticket_pattern=$(echo pwned)\n' > "${repo}/.affix-commit.cfg"
msg_file="${repo}/.git/COMMIT_EDITMSG"
printf '%s' "feat: change" > "${msg_file}"
# Should use default pattern (malicious line filtered out)
(cd "${repo}" && bash "${AFFIX_COMMIT}" "${msg_file}" 2>&1) || true
result=$(cat "${msg_file}")
assert_eq "feat(PROJ-123): change" "${result}" "malicious config line filtered, default used"
cleanup_repo "${repo}"

# --- Custom default_type for non-conventional messages ---
describe "Custom default_type for non-conventional message"
repo=$(setup_repo "feature/PROJ-123-custom-type")
run_hook "${repo}" "fixed the login bug" "default_type=fix"
result=$(read_msg "${repo}")
assert_eq "fix(PROJ-123): fixed the login bug" "${result}" "custom default_type used for non-conventional"
cleanup_repo "${repo}"

# --- Custom default_type for empty message ---
describe "Custom default_type for empty message"
repo=$(setup_repo "feature/PROJ-123-empty-type")
run_hook "${repo}" "" "default_type=feat"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123): wip" "${result}" "custom default_type used for empty message"
cleanup_repo "${repo}"

# --- Default default_type remains chore ---
describe "Default type is chore when not configured"
repo=$(setup_repo "feature/PROJ-123-default")
run_hook "${repo}" "plain message no type"
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-123): plain message no type" "${result}" "default_type defaults to chore"
cleanup_repo "${repo}"

# --- Branch type inference: feat ---
describe "Branch type inference: feat from feat/ prefix"
repo=$(setup_repo "feat/PROJ-123-add-login")
run_hook "${repo}" "fixed the login bug" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123): fixed the login bug" "${result}" "type inferred from feat/ branch prefix"
cleanup_repo "${repo}"

# --- Branch type inference: alias feature/ -> feat ---
describe "Branch type inference: feature/ aliased to feat"
repo=$(setup_repo "feature/PROJ-123-add-login")
run_hook "${repo}" "added login" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-123): added login" "${result}" "feature/ alias maps to feat"
cleanup_repo "${repo}"

# --- Branch type inference: bugfix/ -> fix ---
describe "Branch type inference: bugfix/ aliased to fix"
repo=$(setup_repo "bugfix/PROJ-55-crash")
run_hook "${repo}" "fixed the crash" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "fix(PROJ-55): fixed the crash" "${result}" "bugfix/ alias maps to fix"
cleanup_repo "${repo}"

# --- Branch type inference: hotfix/ -> fix ---
describe "Branch type inference: hotfix/ aliased to fix"
repo=$(setup_repo "hotfix/PROJ-99-urgent")
run_hook "${repo}" "patched it" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "fix(PROJ-99): patched it" "${result}" "hotfix/ alias maps to fix"
cleanup_repo "${repo}"

# --- Branch type inference: unknown prefix falls back to default_type ---
describe "Branch type inference: unknown prefix falls back to default_type"
repo=$(setup_repo "wibble/PROJ-1-thing")
run_hook "${repo}" "did a thing" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-1): did a thing" "${result}" "unknown prefix falls back to default_type"
cleanup_repo "${repo}"

# --- Branch type inference: explicit conventional type wins ---
describe "Branch type inference: explicit type in message overrides branch"
repo=$(setup_repo "fix/PROJ-10-thing")
run_hook "${repo}" "feat: new shiny" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-10): new shiny" "${result}" "explicit conventional type beats branch prefix"
cleanup_repo "${repo}"

# --- Branch type inference: no slash -> no inference ---
describe "Branch type inference: branch without slash falls back to default_type"
repo=$(setup_repo "PROJ-7-no-prefix")
run_hook "${repo}" "did stuff" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-7): did stuff" "${result}" "no '/' in branch -> default_type"
cleanup_repo "${repo}"

# --- Branch type inference: empty message uses inferred type ---
describe "Branch type inference: empty message uses inferred type"
repo=$(setup_repo "feat/PROJ-8-wip")
run_hook "${repo}" "" "infer_type_from_branch=true"
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-8): wip" "${result}" "empty message uses inferred type"
cleanup_repo "${repo}"

# --- Branch type inference disabled by default ---
describe "Branch type inference disabled by default"
repo=$(setup_repo "feat/PROJ-123-default-off")
run_hook "${repo}" "plain message"
result=$(read_msg "${repo}")
assert_eq "chore(PROJ-123): plain message" "${result}" "inference off by default; default_type used"
cleanup_repo "${repo}"

# --- Custom branch_type_map ---
describe "Custom branch_type_map"
repo=$(setup_repo "spike/PROJ-42-experiment")
run_hook "${repo}" "trying things" $'infer_type_from_branch=true\nbranch_type_map=\'spike:feat,chore:chore\''
result=$(read_msg "${repo}")
assert_eq "feat(PROJ-42): trying things" "${result}" "custom branch_type_map honoured"
cleanup_repo "${repo}"

# --- Branch type inference: missing ticket still errors by default ---
describe "Branch type inference: missing ticket still errors by default"
repo=$(setup_repo "feat/my-branch")
exit_code=0
run_hook "${repo}" "feat: change" "infer_type_from_branch=true" || exit_code=$?
assert_eq "1" "${exit_code}" "missing ticket errors even with inference enabled"
result=$(read_msg "${repo}")
assert_eq "feat: change" "${result}" "message unchanged when no ticket found"
cleanup_repo "${repo}"

# --- Branch type inference without ticket: non-conventional gets type prefix ---
describe "Branch type inference without ticket: non-conventional message gets type"
repo=$(setup_repo "feat/cool-ui")
run_hook "${repo}" "My message" $'infer_type_from_branch=true\nignore_missing_tickets=true'
result=$(read_msg "${repo}")
assert_eq "feat: My message" "${result}" "type injected even without ticket"
cleanup_repo "${repo}"

# --- Branch type inference without ticket: alias prefix ---
describe "Branch type inference without ticket: alias prefix"
repo=$(setup_repo "bugfix/cool-ui")
run_hook "${repo}" "patched it" $'infer_type_from_branch=true\nignore_missing_tickets=true'
result=$(read_msg "${repo}")
assert_eq "fix: patched it" "${result}" "alias resolved without ticket"
cleanup_repo "${repo}"

# --- Branch type inference without ticket: empty message ---
describe "Branch type inference without ticket: empty message"
repo=$(setup_repo "feat/cool-ui")
run_hook "${repo}" "" $'infer_type_from_branch=true\nignore_missing_tickets=true'
result=$(read_msg "${repo}")
assert_eq "feat: wip" "${result}" "empty message gets type without ticket"
cleanup_repo "${repo}"

# --- Branch type inference without ticket: conventional message left untouched ---
describe "Branch type inference without ticket: conventional message untouched"
repo=$(setup_repo "feat/cool-ui")
run_hook "${repo}" "fix: already typed" $'infer_type_from_branch=true\nignore_missing_tickets=true'
result=$(read_msg "${repo}")
assert_eq "fix: already typed" "${result}" "explicit type wins; nothing to inject without ticket"
cleanup_repo "${repo}"

# --- Branch type inference without ticket: unknown prefix exits silently ---
describe "Branch type inference without ticket: unknown prefix is a no-op"
repo=$(setup_repo "wibble/no-ticket")
run_hook "${repo}" "did stuff" $'infer_type_from_branch=true\nignore_missing_tickets=true'
result=$(read_msg "${repo}")
assert_eq "did stuff" "${result}" "no ticket + unknown prefix -> message left untouched"
cleanup_repo "${repo}"

# --- Missing ticket without inference still passes through silently ---
describe "Missing ticket with ignore_missing_tickets and no inference is a no-op"
repo=$(setup_repo "feat/my-branch")
run_hook "${repo}" "did stuff" "ignore_missing_tickets=true"
result=$(read_msg "${repo}")
assert_eq "did stuff" "${result}" "no inference -> message left untouched even on typed branch"
cleanup_repo "${repo}"

# ============================================================================
# Summary
# ============================================================================
test_summary
