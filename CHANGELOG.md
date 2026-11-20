# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-20

### Added
- Optional `--json` output for `list`, `status`, and `check`, with consistent fields and exit codes.
- JSON tests for empty project lists, server state, HTTP 200/404, and invalid arguments.
- README instructions for integrating Cursor, Codex, and Claude Code agents.

### Compatibility
- Existing text output for commands without `--json` remains unchanged.

## [1.0.0] - 2026-11-20

### Added
- Management of multiple local PHP development servers using Git Bash and PowerShell.
- Project registration and editing (`add`, `edit`, `remove`).
- Starting, stopping, and restarting servers, including bulk operations.
- Process status and uptime reporting (`list`, `status`).
- HTTP diagnostics (`check`) and log viewing (`logs`).
- Windows integration tests in GitHub Actions.
- The `devserver --version` command and centralized `VERSION` file.

### Security
- Binding limited to `127.0.0.1`.
- Process identity verification before stopping a managed server.
- Warning about possible file exposure when using `--no-dir`.

### Documentation
- English and Polish project introductions, Git Bash `PATH` setup, and generic examples.
