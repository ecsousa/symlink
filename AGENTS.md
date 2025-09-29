# Codex Agent Context

## Repository Snapshot

- **Root path**: directory contains backup automation helpers.
- **Shell defaults**: Codex CLI launches PowerShell 7 (`pwsh`).
- **Sandbox**: workspace-write filesystem; network access restricted; approval policy `on-request`.

## Key Files

- `configure.ps1`: manages directory mappings and symbolic links based on `mappings.txt`. Handles inline comments, environment-variable expansion, and error reporting with exit codes. Requires Developer Mode for symlink creation.
- `README.md`: user-facing instructions covering requirements, mapping syntax, and behavior.
- `mappings.txt`: not committed; expected to sit beside the script listing `LOCAL_NAME: TARGET` pairs.

## Script Behaviors

- Resolves `LOCAL_NAME` relative to script directory; `TARGET` expands Windows-style env vars.
- Creates local directories or symbolic links as needed; moves existing targets into place when local paths missing.
- Error cases (non-link conflicts, missing locals with symlink targets, parse issues) emit warnings and set exit code 1.

## Operational Notes

- Prefer `pwsh ./configure.ps1` for execution; pass `-MappingsPath` to override default file location.
- When editing, maintain ASCII text and follow existing logging style.
- Approval may be required for commands that go beyond workspace access; use `with_escalated_permissions` when needed.

## Future Tasks

- Populate `mappings.txt` with actual mappings before running script.
- Consider adding tests or dry-run mode if automation needs confidence without making changes.
