#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Version = (Get-Content -LiteralPath (Join-Path $base 'VERSION') -Raw -Encoding UTF8).Trim()
$config = Join-Path $base 'config\projects.json'
$runtime = Join-Path $base 'runtime'
$logs = Join-Path $base 'logs'
function Fail($msg) { throw $msg }
function Init {
  foreach ($d in @((Split-Path $config -Parent),$runtime,$logs)) {
    if (!(Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
}
function Load {
  $map = @{}
  if (Test-Path -LiteralPath $config) {
    $doc = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($doc.projects) { foreach ($x in $doc.projects.PSObject.Properties) { $map[$x.Name] = $x.Value } }
  }
  return ,$map
}
function Save($map) {
  Init
  $sorted = [ordered]@{}
  foreach ($n in @($map.Keys | Sort-Object)) { $sorted[$n] = $map[$n] }
  $json = @{projects=$sorted} | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText("$config.tmp",$json,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath "$config.tmp" -Destination $config -Force
}
function FullPath($p) {
  if ([IO.Path]::IsPathRooted([string]$p.path)) { return [IO.Path]::GetFullPath([string]$p.path) }
  return [IO.Path]::GetFullPath((Join-Path $base ([string]$p.path)))
}
function LocalPath($path) {
  Push-Location $base
  try {
    # Resolve-Path -Relative returns a string (not a PathInfo object).
    $relative = [string](Resolve-Path -LiteralPath $path -Relative)
    if ([string]::IsNullOrWhiteSpace($relative)) { Fail "Nie udalo sie wyznaczyc sciezki wzglednej: $path" }
    $roundTrip = [IO.Path]::GetFullPath((Join-Path $base $relative))
    if ($roundTrip -ine [IO.Path]::GetFullPath($path)) { Fail "Blad zapisu sciezki projektu: $path" }
    return $relative
  } finally { Pop-Location }
}
function UserPath($value) {
  if ($value -match '^/([a-zA-Z])/(.*)$') {
    $value = $Matches[1] + ':\' + $Matches[2].Replace('/', '\')
  }
  if (![IO.Path]::IsPathRooted($value)) { $value = Join-Path (Get-Location).Path $value }
  return [IO.Path]::GetFullPath($value)
}
function Ask($question,$default) {
  $answer = Read-Host "$question [$default]"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
  return $answer.Trim()
}
function PidFile($n) { return (Join-Path $runtime "$n.json") }
function Managed($n,$p) {
  $f = PidFile $n
  if (!(Test-Path -LiteralPath $f)) { return $null }
  try {
    $record = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    $processId = [int]$record.pid
    if ($processId -le 0) { return $null }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
    if (!$proc) { return $null }
    $needle = "-S 127.0.0.1:$($p.port)"
    if (([string]$proc.CommandLine).Contains($needle) -and
      ([string]$proc.ExecutablePath).Equals([string]$record.php,[StringComparison]::OrdinalIgnoreCase) -and
      ([string]$record.path -ieq (FullPath $p))) { return $proc }
  } catch { return $null }
  return $null
}
function FreePort($port) {
  $listener = $null
  try {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,[int]$port)
    $listener.Start()
    return $true
  } catch { return $false } finally { if ($listener) { $listener.Stop() } }
}
function ResolveName($name,$map) {
  if ($name -eq '.') {
    $matches = @($map.Keys | Where-Object { (FullPath $map[$_]).TrimEnd('\') -ieq ([IO.Path]::GetFullPath((Get-Location).Path)).TrimEnd('\') })
    if ($matches.Count -ne 1) { Fail 'Biezacy katalog nie jest zarejestrowany.' }
    return $matches[0]
  }
  if (!$map.ContainsKey($name)) { Fail "Nieznany projekt: $name" }
  return $name
}
function StartServer($n,$map) {
  $p = $map[$n]
  if (Managed $n $p) { Write-Host "$n - juz uruchomiony"; return }
  $dir = FullPath $p
  if ($null -eq $p.documentRoot) {
    Write-Warning 'Bez -t PHP udostepnia katalog projektu. Pliki konfiguracyjne i inne poufne zasoby moga byc dostepne przez HTTP. Zalecany jest osobny katalog public.'
  }
  if (!(Test-Path -LiteralPath $dir -PathType Container)) { Fail "Nie istnieje katalog: $dir" }
  if ($null -ne $p.documentRoot -and !(Test-Path -LiteralPath (Join-Path $dir $p.documentRoot) -PathType Container)) {
    Fail "Brak katalogu WWW: $($p.documentRoot)"
  }
  if (!(FreePort $p.port)) { Fail "Port $($p.port) jest zajety." }
  $php = Get-Command php.exe -ErrorAction SilentlyContinue
  if (!$php) { Fail 'Brak php.exe w PATH Windows (PowerShell).' }
  Init
  $arguments = "-S 127.0.0.1:$($p.port)"
  if ($null -ne $p.documentRoot) { $arguments += ' -t "' + $p.documentRoot + '"' }
  $proc = Start-Process -FilePath $php.Source -ArgumentList $arguments -WorkingDirectory $dir -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs "$n.out.log") -RedirectStandardError (Join-Path $logs "$n.err.log")
  @{ pid=$proc.Id; php=$php.Source; path=$dir } | ConvertTo-Json | Set-Content -LiteralPath (PidFile $n) -Encoding UTF8
  Start-Sleep -Milliseconds 350
  if (!(Managed $n $p)) {
    Remove-Item -LiteralPath (PidFile $n) -Force -ErrorAction SilentlyContinue
    Fail "Serwer nie wystartowal. Sprawdz logs/$n.err.log"
  }
  Write-Host "START $n http://127.0.0.1:$($p.port) PID=$($proc.Id)"
}
function StopServer($n,$map) {
  $proc = Managed $n $map[$n]
  if ($proc) {
    Stop-Process -Id ([int]$proc.ProcessId) -ErrorAction Stop
    Write-Host "STOP $n PID=$($proc.ProcessId)"
  } else { Write-Host "$n - serwer nie jest uruchomiony przez menedzer" }
  Remove-Item -LiteralPath (PidFile $n) -Force -ErrorAction SilentlyContinue
}
function Uptime($proc) {
  if (!$proc -or !$proc.CreationDate) { return '-' }
  try {
    $elapsed = (Get-Date) - ([datetime]$proc.CreationDate)
    if ($elapsed.TotalSeconds -lt 0) { return '-' }
    $days = [math]::Floor($elapsed.TotalDays)
    if ($days -gt 0) { return ('{0}d {1}h {2}m' -f $days,$elapsed.Hours,$elapsed.Minutes) }
    if ($elapsed.TotalHours -ge 1) { return ('{0}h {1}m' -f [math]::Floor($elapsed.TotalHours),$elapsed.Minutes) }
    if ($elapsed.TotalMinutes -ge 1) { return ('{0}m {1}s' -f [math]::Floor($elapsed.TotalMinutes),$elapsed.Seconds) }
    return ('{0}s' -f [math]::Floor($elapsed.TotalSeconds))
  } catch { return '-' }
}
function ValidateRoot($root,$dir) {
  if ($null -eq $root) { return }
  if ($root -eq '' -or [IO.Path]::IsPathRooted($root) -or
      $root -match '(^|[\\/])\.\.([\\/]|$)' -or $root.Contains('"')) {
    Fail 'Katalog WWW musi byc sciezka wzgledna wewnatrz projektu.'
  }
  $full = [IO.Path]::GetFullPath((Join-Path $dir $root))
  if (!$full.StartsWith($dir.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) {
    Fail 'Katalog WWW musi znajdowac sie wewnatrz projektu.'
  }
  if (!(Test-Path -LiteralPath $full -PathType Container)) { Fail "Nie istnieje katalog WWW: $root" }
}
function ValidatePort($port,$map,$exclude) {
  if ($port -lt 1 -or $port -gt 65535) { Fail 'Port musi byc w zakresie 1..65535.' }
  foreach ($key in $map.Keys) {
    if ($key -ne $exclude -and [int]$map[$key].port -eq $port) { Fail "Port $port jest przypisany projektowi $key." }
  }
  if (!(FreePort $port)) { Fail "Port $port jest juz zajety." }
}
function CheckServer($name,$map,$relative) {
  $p = $map[$name]
  $proc = Managed $name $p
  if (!$proc) { Fail "Serwer $name nie jest uruchomiony przez menedzer." }
  if (!$relative.StartsWith('/') -or $relative.StartsWith('//') -or
      $relative.Contains('#') -or $relative.Contains('?') -or $relative.Contains('\') -or
      $relative.Contains('@')) { Fail 'Sciezka HTTP musi miec postac /, /up lub /login (bez hosta i parametrów).' }
  $uri = [Uri]("http://127.0.0.1:$($p.port)$relative")
  if ($uri.Host -ne '127.0.0.1' -or $uri.Port -ne [int]$p.port) { Fail 'Nieprawidlowa sciezka HTTP.' }
  $request = [Net.HttpWebRequest][Net.WebRequest]::Create($uri)
  $request.Method = 'GET'
  $request.Timeout = 5000
  $request.ReadWriteTimeout = 5000
  $request.AllowAutoRedirect = $false
  $request.Proxy = $null
  $request.UserAgent = 'PHP-DevServer-Manager/' + $script:Version
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $response = $null
  try {
    try { $response = $request.GetResponse() }
    catch [Net.WebException] {
      if ($_.Exception.Response) { $response = $_.Exception.Response }
      else { Fail "Brak odpowiedzi HTTP: $($_.Exception.Message)" }
    }
    $code = [int]([Net.HttpWebResponse]$response).StatusCode
    $watch.Stop()
    Write-Host "$name | HTTP $code | $($watch.ElapsedMilliseconds) ms | $uri"
    if ($code -ge 500) { exit 1 }
  } finally { if ($response) { $response.Close() } }
}
function ShowLogs($name,$options) {
  $stream = 'err'; $follow = $false; $tail = 30; $seen = @{}
  for ($i=0; $i -lt $options.Count; $i++) {
    $o = $options[$i]
    if ($o -notin @('--follow','--stdout','--lines')) { Fail "Nieznana opcja: $o" }
    if ($seen.ContainsKey($o)) { Fail "Powtorzona opcja: $o" }
    $seen[$o] = $true
    if ($o -eq '--follow') { $follow = $true }
    elseif ($o -eq '--stdout') { $stream = 'out' }
    else {
      $i++
      if ($i -ge $options.Count) { Fail 'Brak liczby dla --lines.' }
      $parsed = 0
      if (![int]::TryParse($options[$i],[ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 10000) { Fail '--lines: zakres 1..10000.' }
      $tail = $parsed
    }
  }
  $file = Join-Path $logs "$name.$stream.log"
  if (!(Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Brak pliku logu: $file. Uruchom serwer, aby utworzyc log." }
  Write-Host "Log: $file"
  if ($follow) { Get-Content -LiteralPath $file -Tail $tail -Wait }
  else { Get-Content -LiteralPath $file -Tail $tail }
}
function EditServer($name,$map,$options) {
  $old = $map[$name]
  if (Managed $name $old) { Fail "Najpierw zatrzymaj serwer: devserver stop $name" }
  $path = FullPath $old; $root = $old.documentRoot; $port = [int]$old.port
  $seen = @{}; $yes = $false
  for ($i=0; $i -lt $options.Count; $i++) {
    $opt = $options[$i]
    if ($opt -notin @('--path','--dir','--no-dir','--port','--yes')) { Fail "Nieznana opcja: $opt" }
    if ($seen.ContainsKey($opt)) { Fail "Powtorzona opcja: $opt" }
    $seen[$opt] = $true
    if ($opt -eq '--yes') { $yes = $true; continue }
    if ($opt -eq '--no-dir') { $root = $null; continue }
    $i++
    if ($i -ge $options.Count -or $options[$i].StartsWith('--')) { Fail "Brak wartosci dla $opt" }
    switch ($opt) {
      '--path' { $path = UserPath $options[$i] }
      '--dir' { $root = $options[$i] }
      '--port' {
        $parsed = 0
        if (![int]::TryParse($options[$i],[ref]$parsed)) { Fail 'Port musi byc liczba.' }
        $port = $parsed
      }
    }
  }
  if ($seen.ContainsKey('--dir') -and $seen.ContainsKey('--no-dir')) { Fail '--dir i --no-dir wzajemnie sie wykluczaja.' }
  if (!$yes) {
    if (!$seen.ContainsKey('--path')) { $path = UserPath (Ask 'Sciezka projektu' $path) }
    if (!$seen.ContainsKey('--dir') -and !$seen.ContainsKey('--no-dir')) {
      $defaultRoot = if ($null -eq $root) { '-' } else { [string]$root }
      $answer = Ask 'Katalog WWW (- = bez -t)' $defaultRoot
      $root = if ($answer -eq '-') { $null } else { $answer }
    }
    if (!$seen.ContainsKey('--port')) {
      $answer = Ask 'Port serwera' ([string]$port)
      $parsed = 0
      if (![int]::TryParse($answer,[ref]$parsed)) { Fail 'Port musi byc liczba.' }
      $port = $parsed
    }
  }
  if (!(Test-Path -LiteralPath $path -PathType Container)) { Fail "Katalog projektu nie istnieje: $path" }
  ValidateRoot $root $path
  foreach ($key in $map.Keys) {
    if ($key -ne $name -and (FullPath $map[$key]) -ieq $path) { Fail "Katalog jest juz uzywany przez projekt $key." }
  }
  if ($port -ne [int]$old.port) { ValidatePort $port $map $name }
  elseif ($port -lt 1 -or $port -gt 65535) { Fail 'Port musi byc w zakresie 1..65535.' }
  $map[$name] = @{path=(LocalPath $path);port=$port;documentRoot=$root}
  Save $map
  Write-Host "Zaktualizowano $name | http://127.0.0.1:$port | $path | WWW: $(if ($null -eq $root) {'bez -t'} else {$root})"
}
function ShowList($map) {
  if ($map.Count -eq 0) { Write-Host 'Brak zarejestrowanych projektow.'; return }
  foreach ($n in @($map.Keys | Sort-Object)) {
    $p = $map[$n]
    $proc = Managed $n $p
    $state = if ($proc) { 'RUNNING' } else { 'STOPPED' }
    $uptime = Uptime $proc
    $root = if ($null -eq $p.documentRoot) { 'bez -t' } else { [string]$p.documentRoot }
    Write-Host "$n | $state | uptime: $uptime | http://127.0.0.1:$($p.port) | $(FullPath $p) | WWW: $root"
  }
}
function Help($topic) {
  if ($topic -eq 'add') {
    Write-Host 'devserver add [nazwa] [--path <sciezka>] [--dir <katalog> | --no-dir] [--port <1..65535>] [--yes]'
    Write-Host 'Brakujace wartosci: pytania z domyslnymi odpowiedziami (Enter); --yes pomija pytania. --path przyjmuje takze /c/projects/...'
  } elseif ($topic -eq 'edit') {
    Write-Host 'devserver edit <nazwa|.> [--path <sciezka>] [--dir <katalog> | --no-dir] [--port <numer>] [--yes]'
    Write-Host 'Serwer musi byc zatrzymany. Bez --yes pytania o pozostale wartosci.'
  } elseif ($topic -eq 'check') {
    Write-Host 'devserver check <nazwa|.> [--path /up]'
    Write-Host 'GET z limitem 5s bez przekierowan; dowolny kod HTTP oznacza, ze serwer odpowiada (5xx = exit 1).'
  } elseif ($topic -eq 'logs') {
    Write-Host 'devserver logs <nazwa|.> [--lines 30] [--stdout] [--follow]'
    Write-Host 'Domyslnie stderr. --follow konczy sie Ctrl+C.'
  } elseif ($topic -in @('start','stop','restart')) {
    Write-Host "devserver $topic <nazwa|.> (kropka = biezacy projekt)"
  } else {
    Write-Host "PHP DevServer Manager $script:Version (Windows / Git Bash)"
    Write-Host @'
  devserver add [nazwa] [--path <sciezka>] [--dir <katalog> | --no-dir] [--port <numer>] [--yes]
  devserver remove <nazwa>
  devserver start <nazwa|.>
  devserver stop <nazwa|.>
  devserver restart <nazwa|.>
  devserver list       (projekty, stan procesow i uptime)
  devserver check <nazwa|.> [--path /up]
  devserver logs <nazwa|.> [--lines 30] [--stdout] [--follow]
  devserver edit <nazwa|.> [--path <sciezka>] [--dir <katalog> | --no-dir] [--port <numer>] [--yes]
  devserver start-all
  devserver stop-all
  devserver help [polecenie]
  devserver -h / --help / /?
  devserver --version
Przyklady:
  devserver add
  devserver add example-app --path "/c/projects/example-app" --port 3000
  devserver add demo --no-dir --port 3010
  devserver add witryna --port 3020 --dir htdocs
'@
  }
}
try {
  $tokens = @($args)
  if ($tokens.Count -eq 1 -and $tokens[0] -in @('version','--version','-V')) {
    Write-Host "PHP DevServer Manager $script:Version"
    exit 0
  }
  if ($tokens.Count -eq 0 -or $tokens[0] -in @('help','-h','--help','/?')) {
    if ($tokens.Count -gt 1) { Help $tokens[1] } else { Help '' }
    exit 0
  }
  $cmd = $tokens[0]
  if ($tokens -contains '--help' -or $tokens -contains '-h' -or $tokens -contains '/?') { Help $cmd; exit 0 }
  if ($cmd -eq 'add') {
    $name = $null; $root = 'public'; $port = $null; $path = $null
    $seen = @{}; $yes = $false
    for ($i=1; $i -lt $tokens.Count; $i++) {
      $opt = $tokens[$i]
      if ($opt -eq '--yes') {
        if ($seen.ContainsKey($opt)) { Fail 'Powtorzona opcja: --yes' }
        $seen[$opt] = $true; $yes = $true; continue
      }
      if (!$opt.StartsWith('--')) {
        if ($null -ne $name) { Fail "Nieoczekiwany argument: $opt" }
        $name = $opt; continue
      }
      if ($opt -notin @('--path','--dir','--no-dir','--port')) { Fail "Nieznana opcja: $opt" }
      if ($seen.ContainsKey($opt)) { Fail "Powtorzona opcja: $opt" }
      $seen[$opt] = $true
      if ($opt -eq '--no-dir') { $root = $null; continue }
      $i++
      if ($i -ge $tokens.Count -or $tokens[$i].StartsWith('--')) { Fail "Brak wartosci dla $opt" }
      switch ($opt) {
        '--path' { $path = $tokens[$i] }
        '--dir' { $root = $tokens[$i] }
        '--port' {
          $parsed = 0
          if (![int]::TryParse($tokens[$i],[ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) { Fail 'Port musi byc w zakresie 1..65535.' }
          $port = $parsed
        }
      }
    }
    if ($seen.ContainsKey('--dir') -and $seen.ContainsKey('--no-dir')) { Fail '--dir i --no-dir wzajemnie sie wykluczaja.' }
    if ($null -eq $name) {
      $defaultName = (Split-Path (Get-Location).Path -Leaf) -replace '[^a-zA-Z0-9_-]','-'
      if ($defaultName -notmatch '^[a-zA-Z0-9]') { $defaultName = 'projekt' }
      $name = if ($yes) { $defaultName } else { Ask 'Nazwa projektu' $defaultName }
    }
    if ($name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { Fail 'Nazwa projektu moze zawierac tylko litery ASCII, cyfry, _ oraz -.' }
    if ($null -eq $path) { $path = if ($yes) { (Get-Location).Path } else { Ask 'Sciezka projektu' (Get-Location).Path } }
    $cwd = UserPath $path
    if (!(Test-Path -LiteralPath $cwd -PathType Container)) { Fail "Katalog projektu nie istnieje: $cwd" }
    if (!$seen.ContainsKey('--dir') -and !$seen.ContainsKey('--no-dir') -and !$yes) {
      $answer = Ask 'Katalog WWW (- = bez -t)' 'public'
      $root = if ($answer -eq '-') { $null } else { $answer }
    }
    if ($null -ne $root -and ($root -eq '' -or [IO.Path]::IsPathRooted($root) -or $root -match '(^|[\\/])\.\.([\\/]|$)' -or $root.Contains('"'))) {
      Fail 'Katalog WWW musi byc sciezka wzgledna wewnatrz projektu.'
    }
    $map = Load
    if ($map.ContainsKey($name)) { Fail "Projekt '$name' juz istnieje." }
    foreach ($key in $map.Keys) { if ((FullPath $map[$key]) -ieq $cwd) { Fail "Ten katalog jest juz zarejestrowany: $key" } }
    if ($null -ne $root -and !(Test-Path -LiteralPath (Join-Path $cwd $root) -PathType Container)) { Fail "Nie istnieje katalog WWW: $root" }
    $ports = @($map.Values | ForEach-Object { [int]$_.port })
    if ($null -eq $port) {
      $port = 3000
      while (($ports -contains $port) -or !(FreePort $port)) {
        $port++
        if ($port -gt 65535) { Fail 'Nie znaleziono wolnego portu.' }
      }
      if (!$yes) {
        $entered = Ask 'Port serwera' ([string]$port)
        $parsed = 0
        if (![int]::TryParse($entered,[ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) { Fail 'Port musi byc w zakresie 1..65535.' }
        $port = $parsed
      }
    }
    if ($ports -contains $port) { Fail "Port $port jest juz przypisany." }
    if (!(FreePort $port)) { Fail "Port $port jest zajety." }
    $map[$name] = @{path=(LocalPath $cwd);port=$port;documentRoot=$root}
    Save $map
    Write-Host "Dodano $name | http://127.0.0.1:$port | $cwd"
    exit 0
  }
  $map = Load
  switch ($cmd) {
    'list' { ShowList $map }
    'status' { ShowList $map } # zgodnosc wsteczna
    'check' {
      if ($tokens.Count -notin @(2,4)) { Fail 'Uzycie: devserver check <nazwa|.> [--path /up]' }
      $n = ResolveName $tokens[1] $map
      $uriPath = '/'
      if ($tokens.Count -eq 4) {
        if ($tokens[2] -ne '--path') { Fail "Nieznana opcja: $($tokens[2])" }
        $uriPath = $tokens[3]
      }
      CheckServer $n $map $uriPath
    }
    'logs' {
      if ($tokens.Count -lt 2) { Fail 'Uzycie: devserver logs <nazwa|.> [--lines 30] [--stdout] [--follow]' }
      $n = ResolveName $tokens[1] $map
      ShowLogs $n @($tokens | Select-Object -Skip 2)
    }
    'edit' {
      if ($tokens.Count -lt 2) { Fail 'Uzycie: devserver edit <nazwa|.> [opcje]' }
      $n = ResolveName $tokens[1] $map
      EditServer $n $map @($tokens | Select-Object -Skip 2)
    }
    'start-all' { $failed=$false; foreach ($n in @($map.Keys | Sort-Object)) { try { StartServer $n $map } catch { Write-Warning $_.Exception.Message; $failed=$true } }; if ($failed) { exit 1 } }
    'stop-all' { $failed=$false; foreach ($n in @($map.Keys | Sort-Object)) { try { StopServer $n $map } catch { Write-Warning $_.Exception.Message; $failed=$true } }; if ($failed) { exit 1 } }
    { $_ -in @('start','stop','restart','remove') } {
      if ($tokens.Count -ne 2) { Fail "Uzycie: devserver $cmd <nazwa|.>" }
      $n = ResolveName $tokens[1] $map
      switch ($cmd) {
        'start' { StartServer $n $map }
        'stop' { StopServer $n $map }
        'restart' { StopServer $n $map; StartServer $n $map }
        'remove' {
          if (Managed $n $map[$n]) { Fail "Najpierw zatrzymaj projekt: devserver stop $n" }
          $map.Remove($n)
          Save $map
          Remove-Item -LiteralPath (PidFile $n) -Force -ErrorAction SilentlyContinue
          Write-Host "Usunieto $n z konfiguracji (pliki projektu pozostaly)."
        }
      }
    }
    default { Fail "Nieznane polecenie '$cmd'. Uruchom: devserver help" }
  }
} catch {
  [Console]::Error.WriteLine('BLAD: ' + $_.Exception.Message)
  exit 1
}
