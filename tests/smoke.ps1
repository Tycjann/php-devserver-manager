#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'devserver.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('php-devserver-test-' + [guid]::NewGuid().ToString('N'))
$manager = Join-Path $testRoot 'manager'
$project = Join-Path $testRoot 'project with spaces'
$other = Join-Path $testRoot 'other'
$script = Join-Path $manager 'devserver.ps1'
$serverStarted = $false
$port = 0

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw "TEST FAILED: $message" }
}
function Run([string[]]$params, [int]$expected = 0) {
    Write-Host ('TEST COMMAND: devserver ' + ($params -join ' '))
    $id = [guid]::NewGuid().ToString('N')
    $argfile = Join-Path $testRoot "$id.args.json"
    $outfile = Join-Path $testRoot "$id.output.txt"
    # Use a temporary PowerShell wrapper that redirects into a file, not a pipe:
    # detached PHP processes may inherit pipe handles and prevent EOF.
    $wrapper = Join-Path $testRoot 'invoke.ps1'
    if (!(Test-Path -LiteralPath $wrapper)) {
        @'
param([string]$Target, [string]$ArgumentFile, [string]$OutputFile)
$ErrorActionPreference = 'Continue'
$values = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ArgumentFile -Raw)
& $Target @values *> $OutputFile
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $wrapper -Encoding UTF8
    }
    ConvertTo-Json -InputObject @($params) -Compress | Set-Content -LiteralPath $argfile -Encoding UTF8
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $wrapper + '" "' + $script + '" "' + $argfile + '" "' + $outfile + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $outerOut = $proc.StandardOutput.ReadToEndAsync()
        $outerErr = $proc.StandardError.ReadToEndAsync()
        if (!$proc.WaitForExit(15000)) {
            $proc.Kill()
            throw "TEST TIMEOUT: devserver $($params -join ' ')"
        }
        $code = [int]$proc.ExitCode
        $output = if (Test-Path -LiteralPath $outfile) { Get-Content -LiteralPath $outfile -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($outerOut.Wait(1000)) { $output += $outerOut.Result }
        if ($outerErr.Wait(1000)) { $output += $outerErr.Result }
        Write-Host "TEST EXIT: $code"
        Assert ($code -eq $expected) ("devserver " + ($params -join ' ') + " returned $code, expected $expected : $output")
        return $output
    } finally {
        $proc.Dispose()
        Remove-Item -LiteralPath $argfile,$outfile -Force -ErrorAction SilentlyContinue
    }
}
function FindPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}
try {
    $null = New-Item -ItemType Directory -Path $manager,$project,$other -Force
    Copy-Item -LiteralPath $source -Destination $script
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'VERSION') -Destination (Join-Path $manager 'VERSION')
    $null = New-Item -ItemType Directory -Path (Join-Path $project 'public'),(Join-Path $project 'web') -Force
    Set-Content -LiteralPath (Join-Path $project 'public\index.php') -Value '<?php http_response_code(200); echo "ready";'
    Set-Content -LiteralPath (Join-Path $project 'public\missing.php') -Value '<?php http_response_code(404); echo "missing";'
    Set-Content -LiteralPath (Join-Path $project 'web\index.php') -Value '<?php echo "web";'
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) ('Parser errors: ' + (($errors | ForEach-Object Message) -join '; '))
    Assert ((Run @('--help')) -match 'devserver check') 'main help'
    Assert ((Run @('--version')) -match ('PHP DevServer Manager ' + [regex]::Escape((Get-Content -LiteralPath (Join-Path $manager 'VERSION') -Raw).Trim()))) 'CLI version'
    Assert ((Run @('help','edit')) -match 'devserver edit') 'edit help'
    Assert ((Run @('help','logs')) -match '--follow') 'logs help'
    $emptyJson = (Run @('list','--json') | ConvertFrom-Json)
    Assert ($emptyJson.version -eq '1.1.0') 'JSON version'
    Assert (@($emptyJson.projects).Count -eq 0) 'empty JSON projects array'
    Assert ((Run @('status','--json') | ConvertFrom-Json).version -eq '1.1.0') 'JSON status alias'
    Assert ((Run @('list','--unexpected') 1) -match 'Uzycie') 'reject list unknown flags'
    $port = FindPort
    $add = Run @('add','sample','--path',$project,'--dir','public','--port',"$port",'--yes')
    Assert ($add -match 'Dodano sample') 'add project'
    $list = Run @('list')
    Assert ($list -match 'STOPPED') 'initial stopped state'
    Assert ($list -match 'uptime: -') 'stopped uptime'
    Assert ($list -match [regex]::Escape($project)) 'stored path'
    $stopped = (Run @('list','--json') | ConvertFrom-Json)
    Assert (@($stopped.projects).Count -eq 1) 'stopped JSON projects'
    Assert ($stopped.projects[0].name -eq 'sample') 'JSON project name'
    Assert ($stopped.projects[0].status -eq 'STOPPED') 'JSON stopped state'
    Assert ($stopped.projects[0].running -eq $false) 'JSON stopped boolean'
    Assert ($null -eq $stopped.projects[0].uptime_seconds) 'JSON stopped uptime'
    Assert ($stopped.projects[0].port -eq $port) 'JSON port'
    Assert ($stopped.projects[0].document_root -eq 'public') 'JSON document root'
    Assert ((Run @('add','duplicate','--path',$project,'--port',"$port",'--yes') 1) -match 'juz') 'reject duplicate path'
    Assert ((Run @('check','sample') 1) -match 'nie jest uruchomiony') 'reject check for stopped server'
    Assert ((Run @('check','sample','--json') 1 | ConvertFrom-Json).error.message -match 'nie jest uruchomiony') 'JSON error for stopped server'
    $start = Run @('start','sample')
    Assert ($start -match 'START sample') "start server: $start"
    $serverStarted = $true
    Start-Sleep -Seconds 2
    $list = Run @('list')
    Assert ($list -match 'RUNNING') "running status: $list"
    Assert ($list -match 'uptime: [0-9]') "running uptime: $list"
    $running = (Run @('list','--json') | ConvertFrom-Json).projects[0]
    Assert ($running.status -eq 'RUNNING') 'JSON running state'
    Assert ($running.running -eq $true) 'JSON running boolean'
    Assert ($running.pid -gt 0) 'JSON running PID'
    Assert ($running.uptime_seconds -ge 0) 'JSON uptime seconds'
    $http = Run @('check','sample','--path','/')
    Assert ($http -match 'HTTP 200') "HTTP 200: $http"
    $json200 = Run @('check','sample','--json','--path','/') | ConvertFrom-Json
    Assert ($json200.http_status -eq 200) 'JSON HTTP 200'
    Assert ($json200.ok -eq $true) 'JSON ok for 200'
    Assert ($json200.response_time_ms -ge 0) 'JSON HTTP elapsed ms'
    Assert ($json200.name -eq 'sample') 'JSON HTTP name'
    $http404 = Run @('check','sample','--path','/missing.php')
    Assert ($http404 -match 'HTTP 404') "404 accepted as HTTP response: $http404"
    $json404 = Run @('check','sample','--path','/missing.php','--json') | ConvertFrom-Json
    Assert ($json404.http_status -eq 404 -and $json404.ok -eq $true) 'JSON HTTP 404 is responding'
    Assert ((Run @('check','sample','--json','--path','//other.example/') 1 | ConvertFrom-Json).error.message -match 'Sciezka HTTP') 'JSON rejects remote host'
    Assert ((Run @('check','sample','--json','--json') 1 | ConvertFrom-Json).error.message -match 'Powtorzona') 'JSON duplicate flag validation'
    Assert ((Run @('check','sample','--json','--bogus') 1 | ConvertFrom-Json).error.message -match 'Nieznana') 'JSON unknown flag validation'
    Assert ((Run @('check','sample','--path','//other.example/') 1) -match 'Sciezka HTTP') 'reject network path'
    $log = Run @('logs','sample','--lines','20')
    Assert ($log -match 'Log:') 'read stderr log'
    Assert ((Run @('logs','sample','--lines','0') 1) -match '1..10000') 'validate log line count'
    Assert ((Run @('edit','sample','--port',"$port",'--yes') 1) -match 'zatrzymaj') 'cannot edit running server'
    $null = Run @('stop','sample')
    $serverStarted = $false
    Assert ((Run @('list')) -match 'STOPPED') 'stopped server'
    Assert ((Run @('list','--json') | ConvertFrom-Json).projects[0].running -eq $false) 'JSON stopped after stop'
    $newPort = FindPort
    while ($newPort -eq $port) { $newPort = FindPort }
    $edited = Run @('edit','sample','--port',"$newPort",'--dir','web','--yes')
    Assert ($edited -match 'Zaktualizowano') "edit result: $edited"
    $list = Run @('list')
    Assert ($list -match ":$newPort") 'edited port'
    Assert ($list -match 'WWW:\s+web') 'edited document root'
    Assert ((Run @('edit','sample','--no-dir','--dir','public','--yes') 1) -match 'wykluczaja') 'reject conflicting root flags'
    Assert ((Run @('edit','sample','--dir','not-existing','--yes') 1) -match 'Nie istnieje katalog WWW') 'reject missing root'
    $null = Run @('start','sample')
    $serverStarted = $true
    Start-Sleep -Seconds 1
    Assert ((Run @('check','sample')) -match 'HTTP 200') 'HTTP after edit'
    $null = Run @('stop','sample')
    $serverStarted = $false
    $null = Run @('remove','sample')
    Assert ((Run @('list')) -match 'Brak zarejestrowanych') 'remove project'
    Write-Host 'PASS: syntax, CLI help, add, list JSON, HTTP JSON, logs, edit, validation, start/stop/remove'
} finally {
    if ($serverStarted -and (Test-Path -LiteralPath $script)) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script stop sample | Out-Null
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
