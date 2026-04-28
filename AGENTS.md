# AGENTS.md

## North Star

**sprig-commit** exists to eliminate the friction of linking commits to issue trackers. Developers should never have to manually type a ticket ID into a commit message — the branch name already has it. This tool bridges that gap with zero dependencies and zero configuration overhead: a single bash script that runs as a git hook.

The core value proposition: **adopt in 30 seconds, never think about it again.** Every design decision should optimize for simplicity, reliability, and staying out of the developer's way. If a feature adds complexity without meaningfully reducing friction, it doesn't belong here.

---

## Project Overview

- **Language**: Bash (3.2+ compatible)
- **Entry point**: `sprig-commit` — a self-contained bash script used as a git `prepare-commit-msg` hook
- **Config**: `.sprig-commit.cfg` (key=value format, searched in repo root then `$HOME`)
- **Tests**: `test/test.sh` using a minimal framework in `test/framework.sh`
- **Installer**: `install.sh` — curl-friendly script that sets up the hook

## File Structure

```
sprig-commit          # Main script (the hook itself)
install.sh            # curl-pipe installer
.sprig-commit.cfg     # Example/template config
test/
  framework.sh        # Minimal bash test framework (assert_eq, assert_contains, etc.)
  test.sh             # Test suite
README.md
LICENSE
AGENTS.md             # This file
```

## Key Design Decisions

1. **Single file, zero dependencies.** The entire tool is one bash script. No package manager, no compile step, no runtime. Only `bash`, `git`, `sed`, and `grep` (all POSIX standard).
2. **Conventional commits enforced.** Non-conventional messages are wrapped as `chore(TICKET): message` (the default type is configurable via `default_type`). This is intentional — the tool assumes users want conventional commits.
3. **Config is key=value.** No JSON, YAML, TOML, or package.json integration. The config file is sourced by bash with security validation. This keeps the tool ecosystem-agnostic.
4. **Config is validated before sourcing.** Lines are filtered through strict regex patterns to prevent command injection. Only known keys (`ticket_pattern`, `ignored_branches`, `ignore_missing_tickets`, `default_type`) with safe values are evaluated.
5. **Idempotent.** If the ticket is already in the message, the hook does nothing. Running it twice produces the same result.

## Development Guidelines

- Keep the script under 150 lines. If it grows beyond that, something is being over-engineered.
- All changes must pass `bash test/test.sh` and `shellcheck sprig-commit install.sh test/test.sh`.
- No external dependencies. If a feature requires `jq`, `python`, `node`, or any non-POSIX tool, it doesn't belong here.
- Support bash 3.2 (macOS default). Avoid bash 4+ features like associative arrays, `readarray`, or `${var,,}` lowercasing.

## Verification

Before merging any change, run:

```bash
# 1. Lint (requires shellcheck installed: brew install shellcheck)
shellcheck sprig-commit install.sh test/test.sh

# 2. Unit tests
bash test/test.sh
```

Both must pass with zero errors. Tests create temporary git repos, run the hook, and verify commit message output. They clean up after themselves.

If adding new behavior, add a corresponding test case in `test/test.sh` following the existing pattern:

```bash
describe "Description of behavior"
repo=$(setup_repo "branch/TICKET-123-name")
run_hook "${repo}" "input message" "optional_config=value"
result=$(read_msg "${repo}")
assert_eq "expected output" "${result}" "assertion description"
cleanup_repo "${repo}"
```

## Config Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `ticket_pattern` | regex | `[A-Z]+-[0-9]+` | Pattern to extract ticket from branch name |
| `ignored_branches` | regex | `^(master\|main\|dev\|develop\|development\|release)$` | Branches to skip |
| `ignore_missing_tickets` | bool | `false` | Skip silently when no ticket found |
| `default_type` | string | `chore` | Conventional commit type for non-conventional messages and empty commits |
