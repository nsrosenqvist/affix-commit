# sprig-commit

A zero-dependency git hook that extracts ticket IDs from branch names and injects them into [conventional commit](https://www.conventionalcommits.org/) message scopes.

```
Branch:    feature/PROJ-123-add-login
You type:  feat: add login page
You get:   feat(PROJ-123): add login page
```

**Why?** Linking commits to issue trackers (Jira, Linear, etc.) is valuable but tedious. `sprig-commit` automates it at commit time — no plugins, no runtime dependencies, just a single bash script.

## How it works

`sprig-commit` runs as a git `prepare-commit-msg` hook. When you commit:

1. Reads the current branch name
2. Extracts a ticket ID using a configurable regex (default: `[A-Z]+-[0-9]+`)
3. Parses your commit message as a conventional commit
4. Injects the ticket into the scope

| Input message | Branch | Result |
|---|---|---|
| `feat: add login` | `feature/PROJ-123-login` | `feat(PROJ-123): add login` |
| `fix(auth): token refresh` | `bugfix/AUTH-42-refresh` | `fix(auth, AUTH-42): token refresh` |
| `feat(s1,s2): big change` | `feature/PROJ-99-refactor` | `feat(s1,s2, PROJ-99): big change` |
| `feat!: drop v1 support` | `feature/PROJ-10-breaking` | `feat(PROJ-10)!: drop v1 support` |
| `fixed the bug` | `fix/PROJ-55-crash` | `chore(PROJ-55): fixed the bug` |
| `feat(PROJ-123): already there` | `feature/PROJ-123-thing` | `feat(PROJ-123): already there` *(unchanged)* |

Non-conventional messages are automatically wrapped: `fixed the bug` → `chore(PROJ-55): fixed the bug`.

## Install

### Quick install (curl)

Run from inside your git repository:

```bash
curl -fsSL https://raw.githubusercontent.com/nsrosenqvist/sprig-commit/main/install.sh | bash
```

This places the hook at `.git/hooks/prepare-commit-msg` and creates a template `.sprig-commit.cfg`.

### Manual install

1. Download the `sprig-commit` script
2. Copy it to `.git/hooks/prepare-commit-msg`
3. Make it executable:

```bash
cp sprig-commit .git/hooks/prepare-commit-msg
chmod +x .git/hooks/prepare-commit-msg
```

### With Husky

If you use [Husky](https://typicode.github.io/husky/) to manage git hooks, add to `.husky/prepare-commit-msg`:

```bash
#!/usr/bin/env bash
exec ./sprig-commit "$1"
```

Or keep the script in your repo and reference it:

```bash
#!/usr/bin/env bash
exec ./scripts/sprig-commit "$1"
```

### Shared via repository

To share the hook with your team, commit the script to your repo (e.g., `scripts/sprig-commit`) and have each developer symlink or copy it:

```bash
ln -sf ../../scripts/sprig-commit .git/hooks/prepare-commit-msg
```

## Configuration

Create a `.sprig-commit.cfg` file at the root of your repository or at `~/.sprig-commit.cfg` (global fallback). The format is simple key=value:

```bash
# Regex to extract ticket ID from branch name
# Default: [A-Z]+-[0-9]+  (matches PROJ-123, AUTH-42, etc.)
ticket_pattern='[A-Z]+-[0-9]+'

# Regex for branches where ticket injection should be skipped
# Default: ^(master|main|dev|develop|development|release)$
ignored_branches='^(master|main|dev|develop|development|release)$'

# Silently skip when no ticket ID is found in the branch name
# If false (default), exit with an error when no ticket is found
# Set to true if you have branches that intentionally lack ticket IDs
ignore_missing_tickets=false

# Conventional commit type to use when the message is not already conventional
# Default: chore  (e.g., "fixed bug" → "chore(TICKET): fixed bug")
default_type=chore
```

### Config search order

1. `.sprig-commit.cfg` in the repository root (found via `git rev-parse --show-toplevel`)
2. `~/.sprig-commit.cfg` (user-global fallback)
3. Built-in defaults

### Options reference

| Option | Default | Description |
|---|---|---|
| `ticket_pattern` | `[A-Z]+-[0-9]+` | Regex to extract ticket ID from branch name. First match is used. |
| `ignored_branches` | `^(master\|main\|dev\|develop\|development\|release)$` | Regex for branches to skip entirely. The hook exits silently on matching branches. |
| `ignore_missing_tickets` | `false` | When `true`, the hook exits silently if no ticket is found. When `false`, exits with an error. |
| `default_type` | `chore` | Conventional commit type used when wrapping non-conventional messages or generating empty commit placeholders. |

## Behavior details

### Branch patterns

The ticket regex is matched against the full branch name. Common branch naming conventions all work:

| Branch name | Extracted ticket |
|---|---|
| `feature/PROJ-123-add-login` | `PROJ-123` |
| `PROJ-456/fix-auth` | `PROJ-456` |
| `bugfix-PROJ-789` | `PROJ-789` |
| `feature/no-ticket` | *(none — error or skip depending on config)* |

### Conventional commit enforcement

All commit messages are formatted as conventional commits:

- **Already conventional**: Ticket is added to the scope — `feat: msg` → `feat(TICKET): msg`
- **Not conventional**: Message is wrapped — `plain text` → `chore(TICKET): plain text` (type is configurable via `default_type`)
- **Breaking changes**: The `!` marker is preserved — `feat!: msg` → `feat(TICKET)!: msg`

### Edge cases

| Scenario | Behavior |
|---|---|
| Ticket already in message | No change (prevents duplication) |
| Detached HEAD | Hook exits silently (exit 0) |
| Empty commit message | Generates `chore(TICKET): wip` (type configurable via `default_type`) |
| Verbose commit (`--verbose`) | Comments and scissors separator preserved, first content line modified |
| Comment-only lines before content | Skipped; first non-comment line is modified |
| Ignored branch (main, develop, etc.) | Hook exits silently (exit 0) |

### Custom ticket patterns

For non-standard ticket formats, override `ticket_pattern`:

```bash
# Lowercase tickets (e.g., proj-123)
ticket_pattern='[a-z]+-[0-9]+'

# GitHub issue numbers (e.g., #42)
ticket_pattern='#[0-9]+'

# Multiple prefixes (e.g., PROJ-123 or BUG-456)
ticket_pattern='(PROJ|BUG)-[0-9]+'
```

## Requirements

- **bash** 3.2+ (ships with macOS, all Linux distros, and Git Bash on Windows)
- **git** (any modern version)
- No other dependencies

## Testing

Run the test suite:

```bash
bash test/test.sh
```

The tests create temporary git repositories, run the hook against various scenarios, and verify the output. No external test framework is required.

For development, also run ShellCheck:

```bash
shellcheck sprig-commit install.sh test/test.sh
```

## License

MIT — see [LICENSE](LICENSE).
