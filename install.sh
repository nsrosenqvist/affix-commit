#!/usr/bin/env bash
# affix-commit installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nsrosenqvist/affix-commit/main/install.sh | bash
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/nsrosenqvist/affix-commit/main/affix-commit"

echo "affix-commit: installing..."

# Ensure we're in a git repository
if ! git rev-parse --show-toplevel &>/dev/null; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
hooks_dir="${repo_root}/.git/hooks"
hook_path="${hooks_dir}/prepare-commit-msg"

# Download the script
if command -v curl &>/dev/null; then
  curl -fsSL "${SCRIPT_URL}" -o "${hook_path}"
elif command -v wget &>/dev/null; then
  wget -qO "${hook_path}" "${SCRIPT_URL}"
else
  echo "error: curl or wget required" >&2
  exit 1
fi

chmod +x "${hook_path}"

# Create template config if none exists
config_path="${repo_root}/.affix-commit.cfg"
if [[ ! -f "${config_path}" ]]; then
  cat > "${config_path}" << 'EOF'
# affix-commit configuration
# See https://github.com/nsrosenqvist/affix-commit for details

# ticket_pattern='[A-Z]+-[0-9]+'
# ignored_branches='^(master|main|dev|develop|development|release)$'
# ignore_missing_tickets=false
# default_type=chore
# infer_type_from_branch=false
# branch_type_map='feat:feat,fix:fix,chore:chore,refactor:refactor,docs:docs,test:test,style:style,perf:perf,build:build,ci:ci,revert:revert,feature:feat,bugfix:fix,hotfix:fix'
EOF
  echo "affix-commit: created ${config_path} (edit to customize)"
fi

echo "affix-commit: installed to ${hook_path}"
echo "affix-commit: done!"
