# Historia zmian

Wersje zgodne z [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) i [SemVer](https://semver.org/lang/pl/).

## [1.1.0] - 2026-11-20

### Dodano
- Opcjonalny format `--json` dla `list`, `status` i `check` z jednoznacznymi polami i kodami wyjścia.
- Testy JSON: brak projektów, stan serwera, HTTP 200/404 oraz błędne argumenty.
- Instrukcje integracji CLI z agentami Cursor, Codex i Claude Code w README.

### Zgodność
- Tekstowe odpowiedzi poleceń bez `--json` pozostają bez zmian.

## [1.0.0] - 2026-11-20

### Dodano
- Zarządzanie wieloma lokalnymi serwerami PHP z Git Bash i PowerShell.
- Rejestrację i edycję projektów (`add`, `edit`, `remove`).
- Uruchamianie, zatrzymywanie i restartowanie serwerów oraz operacje zbiorcze.
- Informacje o stanie procesów i czasie działania (`list`, `status`).
- Diagnostykę HTTP (`check`) i podgląd logów (`logs`).
- Testy integracyjne uruchamiane na Windows w GitHub Actions.
- Polecenie `devserver --version` i wspólny plik `VERSION`.

### Bezpieczeństwo
- Nasłuch ograniczony do `127.0.0.1`.
- Weryfikację tożsamości procesu przed jego zatrzymaniem.
- Ostrzeżenie o potencjalnym ujawnieniu plików przy użyciu `--no-dir`.

### Dokumentacja
- Wstęp w języku angielskim i polskim, instrukcję konfiguracji `PATH` oraz przykłady niezwiązane z konkretnym środowiskiem.
