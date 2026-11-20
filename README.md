# PHP DevServer Manager

**EN:** Lightweight CLI tool for managing multiple local PHP development servers on Windows and Git Bash. Run servers independently of the terminal, monitor their status, check HTTP responses and view logs.

**PL:** Lekkie narzędzie CLI do zarządzania wieloma lokalnymi serwerami PHP w Windows i Git Bash. Umożliwia uruchamianie serwerów niezależnie od terminala, monitorowanie ich stanu, sprawdzanie odpowiedzi HTTP oraz przeglądanie logów.

> **Wersja:** `1.0.0` - pierwsze stabilne wydanie menedżera CLI, przetestowane automatycznie na Windows. Wbudowany serwer PHP służy wyłącznie do developmentu i nie jest przeznaczony do obsługi ruchu produkcyjnego.

## Wymagania

- Windows 10/11, PowerShell 5.1+ oraz Git Bash (Git for Windows).
- PHP CLI (`php.exe`) dostępny w **Windows PATH**, również z PowerShell.
- Uprawnienia do uruchamiania własnych procesów. Nie potrzeba uprawnień administratora.
- Polecenie `cygpath` dostępne w Git Bash.

## Instalacja

Przykładowa lokalizacja to `C:\projects\devserver`. Można wybrać dowolny katalog poza katalogiem udostępnianym przez serwer HTTP.

Z Git Bash:

```bash
mkdir -p /c/projects
cd /c/projects
git clone https://github.com/Tycjann/php-devserver-manager.git devserver
cd devserver
./devserver --help
./devserver --version
```

### Dostęp do polecenia z dowolnego katalogu (Git Bash)

Żeby uruchamiać `devserver` bez prefiksu `./` z każdego katalogu projektu, dodaj katalog menedżera do zmiennej `PATH` w Git Bash. W poniższych przykładach menedżer znajduje się w `C:\projects\devserver`; dostosuj ścieżkę do własnej instalacji.

1. Otwórz plik konfiguracyjny powłoki:

   ```bash
   nano ~/.bashrc
   ```

2. Dodaj na końcu pliku:

   ```bash
   export PATH="/c/projects/devserver:$PATH"
   ```

3. Zapisz plik, a następnie wczytaj ustawienia i sprawdź, czy polecenie jest dostępne:

   ```bash
   source ~/.bashrc
   command -v devserver
   ```

   Oczekiwany wynik dla przykładowej lokalizacji: `/c/projects/devserver/devserver`.

Od tej chwili można uruchamiać `devserver list` z dowolnego katalogu. Polecenia `devserver start .`, `devserver stop .` i `devserver restart .` korzystają z bieżącego katalogu, jeżeli jest on zarejestrowany jako projekt.

Jeżeli pojawi się `Permission denied`, nadaj uprawnienie wykonywania launcherowi (`chmod +x /c/projects/devserver/devserver`) lub wywołuj go przez `bash /c/projects/devserver/devserver ...`.

Ustawienie `~/.bashrc` dotyczy Git Bash, nie dodaje automatycznie polecenia do PowerShell ani CMD.

## Pierwsze uruchomienie

Rejestracja może być interaktywna. Uruchom `devserver add`, aby odpowiedzieć na pytania o nazwę, lokalizację, katalog WWW i port. Naciśnięcie Enter akceptuje proponowaną wartość. Parametry podane w poleceniu nie są ponownie zadawane. `--yes` całkowicie pomija pytania, co przydaje się agentom AI.

Przykładowy kreator:

```text
$ devserver add
Nazwa projektu [example-app]:
Sciezka projektu [C:\projects\example-app]:
Katalog WWW (- = bez -t) [public]: -
Port serwera [3000]:
```

Przejdź do katalogu aplikacji (nie do `public`):

```bash
cd /c/projects/example-app
devserver add example-app                  # port automatyczny, katalog public
devserver start example-app
devserver list
```

Opcje można łączyć w dowolnej kolejności:

```bash
devserver add website --dir htdocs --port 3010
devserver add test --port 3020 --no-dir
devserver add api --port 3030 --dir web
devserver add example-app --path "/c/projects/example-app" --port 3000
devserver add sample-bot --path "/c/projects/test" --no-dir --yes
```

`--path` przyjmuje ścieżkę Windows (`C:\\projects\\...`) lub Git Bash (`/c/projects/...`), także ze spacjami (w cudzysłowie). Bez `--path` wybierany jest bieżący katalog. `--dir` oraz `--no-dir` wzajemnie się wykluczają. Bez `--dir` w trybie nieinteraktywnym (`--yes`) domyślnym katalogiem jest `public`. W kreatorze można wpisać `-`, aby zrezygnować z `-t`. **Ostrzeżenie:** `--no-dir` uruchamia PHP bez `-t`, czyli udostępnia katalog projektu. Może to prowadzić do ujawnienia przez HTTP plików `.env`, kopii zapasowych lub innych poufnych plików, jeśli serwer je udostępni. Preferuj `--dir public` i stosuj `--no-dir` tylko w projektach, w których cały katalog jest bezpieczny do udostępniania. Domyślnie przydzielany jest pierwszy nieprzypisany i aktualnie wolny port od 3000.

## Polecenia

| Polecenie | Znaczenie |
| --- | --- |
| `devserver add [NAZWA] [OPCJE]` | Kreator rejestracji projektu, opcjonalnie `--path`, `--dir` / `--no-dir`, `--port`, `--yes` |
| `devserver remove NAZWA` | Usuwa wpis z konfiguracji, nie usuwa plików |
| `devserver start NAZWA` | Uruchamia serwer |
| `devserver stop NAZWA` | Zatrzymuje zarządzany serwer |
| `devserver restart NAZWA` | Zatrzymuje i ponownie uruchamia |
| `devserver list` | Wyświetla projekty, porty, katalogi WWW, stan i uptime procesów PHP |
| `devserver status` | Alias `list`, zachowany dla zgodności ze starszymi wywołaniami |
| `devserver check NAZWA [--path /up]` | Sprawdza HTTP metodą GET (5 s, bez przekierowań) |
| `devserver logs NAZWA [--lines N] [--stdout] [--follow]` | Odczytuje log PHP (domyślnie ostatnie 30 linii stderr) |
| `devserver edit NAZWA [OPCJE]` | Zmienia ścieżkę projektu, katalog WWW i port (serwer musi być zatrzymany) |
| `devserver start-all` | Uruchamia wszystkie |
| `devserver stop-all` | Zatrzymuje wszystkie zarządzane serwery |
| `devserver help [POLECENIE]` | Pomoc |
| `devserver -h`, `--help`, `/?` | Pomoc |
| `devserver --version` | Wyświetla numer wersji z pliku `VERSION` |

Przykładowe wyjście `devserver list`:

```text
example-app | RUNNING | uptime: 2h 34m | http://127.0.0.1:3000 | C:\projects\example-app | WWW: public
another-app | STOPPED | uptime: - | http://127.0.0.1:3001 | C:\projects\another-app | WWW: bez -t
```

Stan RUNNING oznacza, że menedżer rozpoznaje własny proces PHP, nie że aplikacja pomyślnie odpowiada HTTP. Polecenie `status` jest nadal akceptowane jako alias, ale nie jest już osobno reklamowane w pomocy.

W poleceniach `start`, `stop` i `restart` zamiast nazwy możesz użyć kropki (`.`), aby odwołać się do projektu zarejestrowanego dla bieżącego katalogu.

## Uptime, diagnostyka HTTP i logi

Czas działania w `list` liczony jest od uruchomienia rozpoznanego procesu PHP. Nie oznacza czasu pracy aplikacji ani czasu od ostatniego żądania. Dla procesu zatrzymanego pokazuje `-`. `status` pozostaje aliasem `list`.

```bash
devserver check example-app
devserver check example-app --path /up
devserver check example-app --path /login
```

`check` wysyła GET na `http://127.0.0.1:PORT/ścieżka`, bez przekierowań i z limitem 5 sekund. Wyświetla kod HTTP i czas odpowiedzi. Kody 404, 401 i 302 nadal oznaczają, że serwer odpowiedział. Kod 5xx lub błąd połączenia oznacza kod wyjścia 1. `--path` przyjmuje lokalną ścieżkę bez hosta oraz parametrów URL.

```bash
devserver logs example-app
devserver logs example-app --lines 100
devserver logs example-app --stdout
devserver logs example-app --follow
```

Domyślnie odczytywany jest plik `logs/example-app.err.log` (ostatnie 30 linii). `--stdout` przełącza na stdout, a `--follow` obserwuje dalsze wpisy do Ctrl+C. Menedżer nie czyści logów automatycznie.

## Edycja istniejącego projektu

```bash
devserver stop example-app
devserver edit example-app
devserver edit example-app --path "/c/projects/example-app" --dir public --port 3005 --yes
devserver edit example-app --no-dir --yes
devserver start example-app
```

Bez `--yes` polecenie `edit` pyta o niewskazane wartości i proponuje aktualne ustawienia. `--yes` używa ich bez dodatkowych pytań. `--dir` i `--no-dir` wykluczają się wzajemnie. Sprawdzane są porty, ścieżki i duplikaty katalogów. Serwer musi być zatrzymany przed edycją.

## Testy automatyczne na Windows

Workflow `.github/workflows/windows-smoke.yml` sprawdza składnię PowerShell oraz scenariusze integracyjne na Windows z PHP CLI. Testy pracują w odrębnym katalogu tymczasowym, nie modyfikują projektów użytkownika.

```powershell
.\tests\smoke.ps1
```

Scenariusze obejmują pomoc, rejestrację, start/stop, uptime, HTTP, logi, edycję, walidację i usuwanie projektu. Wymagany jest `php.exe` w Windows PATH. Aktualny wynik testów jest widoczny w zakładce Actions na GitHubie.

## Wersje i wydania

Numer wersji przechowywany jest w pliku `VERSION` i wyświetlany przez `devserver --version`. Zmiany między wersjami opisuje [`CHANGELOG.md`](CHANGELOG.md). Stosujemy numerację [SemVer](https://semver.org/lang/pl/): `MAJOR.MINOR.PATCH`. Wersja `1.0.0` oznacza pierwszy stabilny zestaw poleceń CLI. Dalsze wydania będą wersjonowane zgodnie z zasadami SemVer.

Wydania oznaczamy tagami Git `vX.Y.Z` i publikujemy w GitHub Releases. Numer w `VERSION` identyfikuje kod, a tagi i wydania są publikowane osobno.

## Dane i kopie zapasowe

```text
C:\projects\devserver\
├── devserver          # launcher Git Bash
├── devserver.ps1      # menedżer PowerShell
├── VERSION            # numer wersji CLI
├── CHANGELOG.md       # historia zmian
├── config\
│   └── projects.json  # lokalne ścieżki, porty, katalogi WWW
├── logs\              # stderr/stdout
└── runtime\           # identyfikatory procesów
```

Foldery `config/`, `logs/`, `runtime/` powstają w trakcie pracy. Repozytorium **nie śledzi** lokalnych danych. Do backupu wystarczy objąć nim w szczególności `config/projects.json`; `runtime` i `logs` można pominąć. Ścieżki projektów zapisujemy względem katalogu menedżera, gdy tylko jest to możliwe.

Logi serwerów trafiają do `logs/NAZWA.err.log` i `logs/NAZWA.out.log`. Nie umieszczaj menedżera w katalogu udostępnianym przez serwer HTTP, np. `public/`.

## Bezpieczeństwo i ograniczenia

- Nasłuch tylko na `127.0.0.1` (bez wystawiania serwera do sieci).
- `localhost` zwykle prowadzi do tego samego komputera, ale może wskazywać na `127.0.0.1` (IPv4) albo `::1` (IPv6), zależnie od konfiguracji systemu. Serwer nasłuchuje wyłącznie na `127.0.0.1`, dlatego dokumentacja konsekwentnie używa tego adresu.
- `stop` sprawdza PID oraz polecenie i ścieżkę pliku wykonywalnego przed zatrzymaniem procesu; nie wykonuje `taskkill` dla wszystkich procesów `php.exe`.
- `list` oraz jego alias `status` sprawdzają proces, a nie kondycję aplikacji. Do diagnostyki HTTP służy `check`.
- Gdy proces zarządzany zakończy się niespodziewanie, przy ponownym uruchomieniu nadpisywane są jego dane runtime.
- Przy uruchamianiu wielu serwerów z równoczesnymi żądaniami mogą ujawnić się ograniczenia wbudowanego serwera PHP.
- Wersja 1.0.0 nie zapewnia automatycznego startu systemowego ani centralnego panelu GUI.
- Automatyczne testy na Windows obejmują parser PowerShell i podstawowe scenariusze integracyjne. Tryb interaktywny (`Read-Host`) warto dodatkowo przetestować w lokalnym terminalu.

Licencja: [MIT](LICENSE).
