# PHP DevServer Manager

**English** | [Polski](README.pl.md)

Lightweight CLI tool for managing multiple local PHP development servers on Windows and Git Bash. Run servers independently of the terminal, monitor their status, check HTTP responses, and view logs.

> **Version:** [Latest release](https://github.com/Tycjann/php-devserver-manager/releases/latest) (source version: [VERSION](VERSION)). The CLI has a stable release and is tested automatically on Windows. PHP's built-in web server is intended for development only, **not production traffic**.

## Requirements

- Windows 10/11, PowerShell 5.1+, and Git Bash (Git for Windows).
- PHP CLI (`php.exe`) available on the **Windows PATH**, including from PowerShell.
- Permission to start processes as your current user; administrator privileges are not required.
- The `cygpath` utility available in Git Bash.

## Installation

The examples use `C:\projects\devserver`. You can choose another location, but **do not place the manager in a directory served over HTTP**.

From Git Bash:

```bash
mkdir -p /c/projects
cd /c/projects
git clone https://github.com/Tycjann/php-devserver-manager.git devserver
cd devserver
./devserver --help
./devserver --version
```

### Run `devserver` from any directory (Git Bash)

To run `devserver` without the `./` prefix, add the manager directory to your Git Bash `PATH`. Adjust the example path if your installation is elsewhere.

1. Open your shell configuration:

   ```bash
   nano ~/.bashrc
   ```

2. Append:

   ```bash
   export PATH="/c/projects/devserver:$PATH"
   ```

3. Save the file, reload the configuration, and verify:

   ```bash
   source ~/.bashrc
   command -v devserver
   ```

   Expected path for this example: `/c/projects/devserver/devserver`.

You can now run `devserver list` from any directory. Commands such as `devserver start .`, `devserver stop .`, and `devserver restart .` use the current working directory if it belongs to a registered project.

If you receive `Permission denied`, make the launcher executable with `chmod +x /c/projects/devserver/devserver`, or invoke it using `bash /c/projects/devserver/devserver ...`.

The `~/.bashrc` setting applies to Git Bash; it does not automatically expose the command in PowerShell or CMD.

## Getting started

Registration can be interactive. Run `devserver add` to be prompted for a name, project location, document root, and port. Press Enter to accept a suggested value. Options specified on the command line will not be requested again. Use `--yes` to skip all prompts, which is useful for AI agents.

Example interactive session (the prompts currently appear in Polish):

```text
$ devserver add
Nazwa projektu [example-app]:
Sciezka projektu [C:\projects\example-app]:
Katalog WWW (- = bez -t) [public]: -
Port serwera [3000]:
```

From the application directory (not its `public` subdirectory):

```bash
cd /c/projects/example-app
devserver add example-app                  # automatic port, public document root
devserver start example-app
devserver list
```

Options may be combined in any order:

```bash
devserver add website --dir htdocs --port 3010
devserver add test --port 3020 --no-dir
devserver add api --port 3030 --dir web
devserver add example-app --path "/c/projects/example-app" --port 3000
devserver add sample-bot --path "/c/projects/test" --no-dir --yes
```

`--path` accepts Windows paths (`C:\projects\...`) and Git Bash paths (`/c/projects/...`), including paths containing spaces (quote them). Without `--path`, the current directory is used. `--dir` and `--no-dir` are mutually exclusive. In noninteractive mode (`--yes`), `public` is the default document root unless `--dir` or `--no-dir` is specified. In interactive mode, enter `-` to omit PHP's `-t` option.

**Security warning:** `--no-dir` starts PHP without `-t` and serves the project directory. Depending on its contents and PHP server behavior, this may expose files such as `.env`, backups, or other sensitive resources over HTTP. Prefer `--dir public` and use `--no-dir` only when the entire directory is safe to serve.

By default, the manager assigns the first unassigned, available port starting at 3000.

## Commands

| Command | Description |
| --- | --- |
| `devserver add [NAME] [OPTIONS]` | Register a project; supports `--path`, `--dir` / `--no-dir`, `--port`, `--yes` |
| `devserver remove NAME` | Remove the project from configuration without deleting its files |
| `devserver start NAME` | Start the project's server |
| `devserver stop NAME` | Stop the managed server |
| `devserver restart NAME` | Stop and start the server |
| `devserver list [--json]` | List projects, ports, document roots, process status, and uptime; optionally output JSON |
| `devserver status [--json]` | Backward-compatible alias for `list` |
| `devserver check NAME [--path /up] [--json]` | Perform an HTTP GET check (5-second timeout, no redirects); optionally output JSON |
| `devserver logs NAME [--lines N] [--stdout] [--follow]` | Read PHP logs (last 30 stderr lines by default) |
| `devserver edit NAME [OPTIONS]` | Change the project path, document root, or port (server must be stopped) |
| `devserver start-all` | Start all registered servers |
| `devserver stop-all` | Stop all managed servers |
| `devserver help [COMMAND]` | Show help |
| `devserver -h`, `--help`, `/?` | Show help |
| `devserver --version` | Display the version from `VERSION` |

Example `devserver list` output (labels are emitted by the current CLI):

```text
example-app | RUNNING | uptime: 2h 34m | http://127.0.0.1:3000 | C:\projects\example-app | WWW: public
another-app | STOPPED | uptime: - | http://127.0.0.1:3001 | C:\projects\another-app | WWW: bez -t
```

`RUNNING` means that the manager recognizes its PHP process, not that the application responds successfully to HTTP. `status` remains available as an alias of `list`, even though it is not listed separately in the CLI's general help.

For `start`, `stop`, and `restart`, you may use a dot (`.`) instead of a name to address the project registered for your current directory.

## Uptime, HTTP diagnostics, and logs

Uptime reported by `list` is calculated from the start time of the recognized PHP process. It does not represent application uptime or the time since the last request. Stopped processes display `-`. `status` is an alias of `list`.

```bash
devserver check example-app
devserver check example-app --path /up
devserver check example-app --path /login
```

`check` sends a GET request to `http://127.0.0.1:PORT/path`, without following redirects, with a 5-second timeout. It reports the HTTP status code and response time. Responses such as 404, 401, and 302 still mean the server responded. An HTTP 5xx status or connection error results in exit code 1. The `--path` argument must be a local URL path, with no host or query string.

```bash
devserver logs example-app
devserver logs example-app --lines 100
devserver logs example-app --stdout
devserver logs example-app --follow
```

By default, `logs` reads the last 30 lines of `logs/example-app.err.log`. Use `--stdout` to switch streams and `--follow` to follow new log entries until Ctrl+C. Logs are not automatically rotated or deleted.

## Editing a registered project

```bash
devserver stop example-app
devserver edit example-app
devserver edit example-app --path "/c/projects/example-app" --dir public --port 3005 --yes
devserver edit example-app --no-dir --yes
devserver start example-app
```

Without `--yes`, `edit` prompts for unspecified settings and suggests their current values. With `--yes`, existing values are reused without prompting. `--dir` and `--no-dir` are mutually exclusive. Ports, paths, and duplicate project directories are validated. Stop a server before editing its configuration.

## Automated tests on Windows

The `.github/workflows/windows-smoke.yml` workflow checks PowerShell syntax and integration scenarios on Windows with PHP CLI. Tests use an isolated temporary directory and do not modify users' registered projects.

```powershell
.\tests\smoke.ps1
```

Test scenarios include help, project registration, start/stop, uptime, HTTP and JSON diagnostics, logs, editing, validation, and project removal. `php.exe` must be on the Windows `PATH`. Current results are available in the GitHub Actions tab.

## Versioning and releases

The source version is stored in `VERSION` and displayed by `devserver --version`. Changes are recorded in [CHANGELOG.md](CHANGELOG.md). Releases follow [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`). Version 1.0.0 established the initial stable CLI command set; subsequent releases follow SemVer compatibility rules.

Releases are tagged `vX.Y.Z` and published using GitHub Releases. Updating `VERSION` does not create a Git tag or release automatically. See the [latest release](https://github.com/Tycjann/php-devserver-manager/releases/latest).

## AI agent integration (Cursor, Codex, Claude Code)

Because the manager exposes a CLI, AI agents with access to a **local Windows terminal** can use it without a separate MCP server. The agent must have `devserver` on its Git Bash `PATH`, or call `devserver.ps1` using PowerShell. Commands run **on your computer**, not inside a remote isolated execution environment. Command approval and execution permissions depend on the agent's configuration.

### Machine-readable output: `--json`

```bash
devserver list --json
devserver status --json
devserver check example-app --path /up --json
```

Example `list --json` response (illustrative values):

```json
{
  "version": "1.1.0",
  "projects": [
    {
      "name": "example-app",
      "status": "RUNNING",
      "running": true,
      "pid": 12345,
      "port": 3000,
      "url": "http://127.0.0.1:3000",
      "path": "C:\\projects\\example-app",
      "document_root": "public",
      "uptime_seconds": 123
    }
  ]
}
```

If there are no projects, `projects` is an empty array (`[]`). The `document_root`, `pid`, and `uptime_seconds` values may be `null`; port and uptime values are numeric when present. The `status` field is `RUNNING` or `STOPPED`.

**Privacy:** `path` contains a **local filesystem path**. Do not publish raw output containing private paths.

Example `check --json` response:

```json
{
  "name": "example-app",
  "url": "http://127.0.0.1:3000/up",
  "http_status": 200,
  "response_time_ms": 14,
  "ok": true
}
```

`ok` indicates that the server responded with an HTTP status below 500. HTTP 4xx responses also produce `ok: true`: the server responded, even if the resource is unavailable. An HTTP 5xx response produces JSON with `ok: false` and exit code 1. Invalid arguments, a stopped server, or a connection error return an object such as `{"error":{"message":"..."}}` with exit code 1. Without `--json`, the existing text output is preserved.

### Agent instructions

Add the following instructions to the agent configuration in your application project. All three agents use the same underlying CLI commands:

```text
Use PHP DevServer Manager to manage local PHP development servers.
First run devserver list --json; do not start a server that is already running.
For the current registered project, use devserver start . and devserver check . --json.
For errors, inspect devserver logs . --lines 50.
Do not register projects or stop other servers, including stop-all, without user approval.
Do not use --no-dir unless the served directory is confirmed safe for HTTP access.
Do not treat HTTP 200 as proof that the application works correctly.
Do not publish logs or list --json output without redacting private paths.
If devserver is unavailable, report it instead of changing the environment automatically.
```

**Cursor:** Put these instructions in a project rule such as `.cursor/rules/php-devserver.mdc` with YAML front matter:

```text
---
description: Local PHP development servers
alwaysApply: true
---
```

Then append the agent instructions above. See [Cursor Rules](https://docs.cursor.com/context/rules).

**Codex:** Add the instructions to `AGENTS.md` in the application project's root directory. See [Codex AGENTS.md](https://developers.openai.com/codex/guides/agents-md).

**Claude Code:** Add the instructions to `CLAUDE.md` in the application project's root directory. See [Claude Code memory](https://code.claude.com/docs/en/memory).

Place agent instruction files in the **application project**, not the manager's directory. Local terminal access and permissions vary by editor and agent installation.

## Local data and backups

```text
C:\projects\devserver\
├── devserver          # Git Bash launcher
├── devserver.ps1      # PowerShell manager
├── VERSION            # CLI version
├── CHANGELOG.md       # release history
├── README.md          # English documentation
├── README.pl.md       # Polish documentation
├── config\
│   └── projects.json  # local project paths, ports, document roots
├── logs\              # stderr/stdout
└── runtime\           # process identifiers
```

The `config/`, `logs/`, and `runtime/` directories are created while the manager runs. Git **does not track** local project configuration and runtime data. For backups, preserve at least `config/projects.json`; `runtime` and `logs` can usually be omitted. Project paths are stored relative to the manager directory when possible.

Server logs are written to `logs/NAME.err.log` and `logs/NAME.out.log`. Do not install the manager under an HTTP-served directory such as `public/`.

## Security and limitations

- The PHP server binds only to `127.0.0.1`, not external network interfaces.
- Depending on system configuration, `localhost` may resolve to `127.0.0.1` (IPv4) or `::1` (IPv6). The server listens only on `127.0.0.1`, so examples consistently use that address.
- Before stopping a server, the manager checks the PID, command line, and executable path. It does not run `taskkill` against every `php.exe` process.
- `list` and `status` report recognized processes, not application health. Use `check` for HTTP diagnostics.
- If a managed process exits unexpectedly, its runtime data is overwritten when started again.
- PHP's built-in server may have limitations under concurrent requests, even when several managed servers are running.
- The manager does not provide automatic startup on system boot or a centralized graphical interface.
- Automated Windows tests cover PowerShell parsing and basic integration scenarios. Interactive `Read-Host` behavior is also worth testing in a local terminal.

License: [MIT](LICENSE).
