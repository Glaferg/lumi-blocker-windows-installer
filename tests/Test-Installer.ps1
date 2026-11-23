$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-Logic.ps1')

$dist = Join-Path $repo 'dist\LumiSetup'
$installer = Join-Path $dist 'Install-Lumi.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw 'Build the installer before running this test.'
}

. (Join-Path $dist 'lib\Log.ps1')
. (Join-Path $dist 'lib\Product.ps1')
. (Join-Path $dist 'lib\Messages.ps1')
. (Join-Path $dist 'lib\Firefox.ps1')
. (Join-Path $dist 'lib\Origins.ps1')
. (Join-Path $dist 'lib\NativeHost.ps1')
. (Join-Path $dist 'lib\Ollama.ps1')
. (Join-Path $dist 'lib\Settings.ps1')
. (Join-Path $dist 'lib\Ui.ps1')
. (Join-Path $PSScriptRoot '..\build\Compile.ps1')

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Test-SameFile {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return $false }
    try {
        $a = (Get-Item -LiteralPath $Left).FullName
        $b = (Get-Item -LiteralPath $Right).FullName
        return ($a -eq $b)
    } catch {
        return ($Left -eq $Right)
    }
}

function Assert-CleanOutput {
    param([string]$Text)
    foreach ($token in @('VERYSILENT', 'Exception', 'registry', 'native messaging', 'HRESULT', 'OLLAMA_ORIGINS', 'LUMI:', 'stack trace')) {
        if ($Text -and $Text.ToLower().Contains($token.ToLower())) {
            throw ('User text contained "' + $token + '"')
        }
    }
}

function Start-LocalByteServer {
    param([byte[]]$Payload)
    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $pipe = [powershell]::Create()
    $pipe.Runspace = $runspace
    [void]$pipe.AddScript({
        param($Server, $Body)
        while ($true) {
            $client = $null
            try {
                $client = $Server.AcceptTcpClient()
                $stream = $client.GetStream()
                $stream.ReadTimeout = 5000
                $buf = New-Object byte[] 4096
                $raw = New-Object System.IO.MemoryStream
                $header = ''
                while ($header -notmatch "`r`n`r`n") {
                    $n = $stream.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $raw.Write($buf, 0, $n)
                    $header = [System.Text.Encoding]::ASCII.GetString($raw.ToArray())
                    if ($header.Length -gt 65536) { break }
                }
                $length = 0
                foreach ($line in ($header -split "`r`n")) {
                    if ($line -like 'Content-Length:*') { $length = [int]($line.Substring(15).Trim()) }
                }
                $marker = $header.IndexOf("`r`n`r`n")
                $have = 0
                if ($marker -ge 0) { $have = $raw.Length - ($marker + 4) }
                while ($have -lt $length) {
                    $n = $stream.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $have += $n
                }
                $prefixText = 'HTTP/1.1 200 OK' + "`r`n" + 'Content-Length: ' + $Body.Length + "`r`n" + 'Connection: close' + "`r`n`r`n"
                $prefix = [System.Text.Encoding]::ASCII.GetBytes($prefixText)
                $stream.Write($prefix, 0, $prefix.Length)
                $stream.Write($Body, 0, $Body.Length)
                $stream.Flush()
            } catch {
                if (-not $client) { break }
            } finally {
                if ($client) { $client.Close() }
            }
        }
    })
    [void]$pipe.AddArgument($listener)
    [void]$pipe.AddArgument($Payload)
    $handle = $pipe.BeginInvoke()
    return @{ Listener = $listener; PowerShell = $pipe; Handle = $handle; Port = $port }
}

function Invoke-LumiChild {
    param([string[]]$InstallerArgs, [hashtable]$Environment)
    $quoted = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $InstallerArgs) {
        if ($arg -match '[\s"]') { $quoted.Add('"' + ($arg -replace '"', '`"') + '"') }
        else { $quoted.Add($arg) }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer + '" ' + ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($InstallerArgs -contains '-Silent') { $psi.EnvironmentVariables['LUMI_SILENT'] = '1' }
    if ($InstallerArgs -contains '-AcceptConsent') { $psi.EnvironmentVariables['LUMI_ACCEPT'] = '1' }
    if ($InstallerArgs -contains '-AllowUnsignedOllamaSetup') { $psi.EnvironmentVariables['LUMI_ALLOW_UNSIGNED'] = '1' }
    if ($Environment) {
        foreach ($key in @($Environment.Keys)) {
            $psi.EnvironmentVariables[$key] = [string]$Environment[$key]
        }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit(180000)
    if (-not $finished) {
        try { $process.Kill() } catch {}
        $process.WaitForExit(5000) | Out-Null
    }
    $outTask.Wait(10000) | Out-Null
    $errTask.Wait(10000) | Out-Null
    $stdout = ''
    $stderr = ''
    if ($outTask.IsCompleted) { $stdout = $outTask.Result }
    if ($errTask.IsCompleted) { $stderr = $errTask.Result }
    $logDir = Join-Path $repo 'tests\out\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $stamp = [DateTime]::UtcNow.ToString('HHmmssfff')
    [System.IO.File]::WriteAllText((Join-Path $logDir ($stamp + '-exit.txt')), ('exit ' + $process.ExitCode + "`r`n" + $psi.Arguments + "`r`n--- stdout ---`r`n" + $stdout + "`r`n--- stderr ---`r`n" + $stderr))
    if (-not $finished) { throw 'Setup did not finish.' }
    return @{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Send-NativeMessage {
    param([string]$Exe, [string]$Json)
    $dir = Join-Path $env:TEMP ('lumi-pipe-' + [Guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    try {
        $inFile = Join-Path $dir 'in.bin'
        $outFile = Join-Path $dir 'out.bin'
        $errFile = Join-Path $dir 'err.txt'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $len = [System.BitConverter]::GetBytes([int]$bytes.Length)
        $all = New-Object byte[] (4 + $bytes.Length)
        [System.Buffer]::BlockCopy($len, 0, $all, 0, 4)
        [System.Buffer]::BlockCopy($bytes, 0, $all, 4, $bytes.Length)
        [System.IO.File]::WriteAllBytes($inFile, $all)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/d /s /c ""' + $Exe + '" < "' + $inFile + '" > "' + $outFile + '" 2> "' + $errFile + '""'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch {}
            throw 'The helper did not answer.'
        }
        $errText = ''
        if (Test-Path -LiteralPath $errFile) { $errText = [System.IO.File]::ReadAllText($errFile) }
        $helperLog = Join-Path (Split-Path -Parent $Exe) 'logs\helper.log'
        $logText = ''
        if (Test-Path -LiteralPath $helperLog) { $logText = [System.IO.File]::ReadAllText($helperLog) }
        if (-not (Test-Path -LiteralPath $outFile)) {
            throw ('The helper answer was incomplete. exit=' + $process.ExitCode + ' err=' + $errText + ' log=' + $logText)
        }
        $memory = [System.IO.File]::ReadAllBytes($outFile)
        if ($memory.Length -lt 4) {
            throw ('The helper answer was incomplete. bytes=' + $memory.Length + ' exit=' + $process.ExitCode + ' err=' + $errText + ' log=' + $logText)
        }
        $count = [System.BitConverter]::ToInt32($memory, 0)
        if ($count -lt 2 -or $memory.Length -lt (4 + $count)) {
            throw ('The helper answer was incomplete. count=' + $count + ' bytes=' + $memory.Length + ' exit=' + $process.ExitCode + ' err=' + $errText + ' log=' + $logText)
        }
        $text = [System.Text.Encoding]::UTF8.GetString($memory, 4, $count)
        return ($text | ConvertFrom-Json)
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-GentleBitmap {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $corner = $bmp.GetPixel(8, 8)
        if ($corner.R -ne 30 -or $corner.G -ne 34 -or $corner.B -ne 42) {
            throw ('Background drifted in ' + $Path)
        }
        for ($y = 0; $y -lt $bmp.Height; $y += 4) {
            for ($x = 0; $x -lt $bmp.Width; $x += 4) {
                $color = $bmp.GetPixel($x, $y)
                if ($color.A -gt 0 -and $color.R -eq 0 -and $color.G -eq 0 -and $color.B -eq 0) {
                    throw ('Jet black in ' + $Path)
                }
                if ($color.R -gt 200 -and $color.G -lt 90 -and $color.B -lt 90) {
                    throw ('Harsh red in ' + $Path)
                }
            }
        }
    } finally {
        $bmp.Dispose()
    }
}

function Assert-Pixel {
    param([string]$Path, [int]$X, [int]$Y, [int]$Red, [int]$Green, [int]$Blue, [string]$Message)
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $color = $bmp.GetPixel($X, $Y)
    } finally {
        $bmp.Dispose()
    }
    if ($color.R -ne $Red -or $color.G -ne $Green -or $color.B -ne $Blue) {
        throw ($Message + ' was ' + $color.R + ',' + $color.G + ',' + $color.B)
    }
}

$work = Join-Path $env:TEMP ('lumi-ci-' + [Guid]::NewGuid().ToString('n'))
$savedOrigins = [Environment]::GetEnvironmentVariable('OLLAMA_ORIGINS', 'User')
$hostKey = 'HKCU:\Software\Mozilla\NativeMessagingHosts\lumi_focus'
$savedHost = $null
if (Test-Path -LiteralPath $hostKey) { $savedHost = (Get-Item -LiteralPath $hostKey).GetValue('') }
$cleanupPids = New-Object System.Collections.Generic.List[int]
$servers = New-Object System.Collections.Generic.List[object]
$layout = Get-LumiLayout

try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $fakeDir = Join-Path $work 'fakes'
    New-Item -ItemType Directory -Force -Path $fakeDir | Out-Null
    $fakeSetup = Join-Path $fakeDir 'OllamaSetup.exe'
    Invoke-Csc -Output $fakeSetup -Sources @((Join-Path $repo 'tests\fakes\FakeOllama.cs'))
    $oldFirefox = Join-Path $fakeDir 'FirefoxOld.exe'
    $newFirefox = Join-Path $fakeDir 'FirefoxNew.exe'
    Invoke-Csc -Output $oldFirefox -Sources @((Join-Path $repo 'tests\fakes\FakeFirefox.cs'))
    Invoke-Csc -Output $newFirefox -Sources @((Join-Path $repo 'tests\fakes\FakeFirefoxNew.cs'))
    $oldStatus = Get-LumiFirefoxStatus -ExecutablePath $oldFirefox -MinimumMajor 115
    $newStatus = Get-LumiFirefoxStatus -ExecutablePath $newFirefox -MinimumMajor 115
    Assert-True ($oldStatus.Status -eq 'older' -and $oldStatus.Major -eq 100) 'An older Firefox build was accepted.'
    Assert-True ($newStatus.Status -eq 'ok' -and $newStatus.Major -eq 128) 'A current Firefox build was rejected.'
    $missingStatus = Get-LumiFirefoxStatus -ExecutablePath (Join-Path $work 'missing-firefox.exe') -MinimumMajor 115
    Assert-True ($missingStatus.Status -eq 'missing') 'A missing Firefox build was treated as installed.'
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
    Assert-True (Test-TrustedExecutable -Path $notepad) 'Signature check did not trust a Windows program.'

    $profile = Join-Path $work 'firefox'
    $profileDir = Join-Path $profile 'profile'
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $profile 'profiles.ini'), "[Profile0]`r`nName=test`r`nIsRelative=1`r`nPath=profile`r`n")
    [System.IO.File]::WriteAllText((Join-Path $profileDir 'extensions.json'), '{"addons":[{"id":"lumi-focus@test","type":"extension","defaultLocale":{"name":"Lumi Focus"},"active":true}]}')

    $payload = [System.IO.File]::ReadAllBytes($fakeSetup)
    $fileServer = Start-LocalByteServer -Payload $payload
    $servers.Add($fileServer)
    $setupUrl = 'http://127.0.0.1:' + $fileServer.Port + '/OllamaSetup.exe'
    $probe = Join-Path $work 'probe.exe'
    try {
        Save-RemoteFile -Url $setupUrl -Destination $probe -TimeoutMs 20000
    } catch {
        $serverErrors = @($fileServer.PowerShell.Streams.Error | ForEach-Object { $_.ToString() })
        throw ('The download check failed. ' + ($serverErrors -join ' '))
    }
    Assert-True ((Get-Item -LiteralPath $probe).Length -eq $payload.Length) 'The download helper did not save the file.'

    $common = @{
        FirefoxExecutable = (Join-Path $work 'missing-firefox.exe')
        FirefoxProfileRoot = $profile
        Model = 'lumi-ci-tiny'
        OllamaSetupUrl = $setupUrl
    }

    $declinedRoot = Join-Path $work 'Declined Install'
    $declined = Invoke-LumiChild -InstallerArgs @(
        '-Silent', '-InstallRoot', $declinedRoot, '-ResultPath', (Join-Path $work 'declined.json'),
        '-FirefoxExecutable', $common.FirefoxExecutable
    )
    Assert-True ($declined.ExitCode -eq 3) ('Setup continued without a yes. Exit ' + $declined.ExitCode + ' out=' + $declined.Stdout + ' err=' + $declined.Stderr)
    Assert-CleanOutput $declined.Stdout
    Assert-True ($declined.Stdout.Contains('Lumi was not installed.')) 'Decline text was wrong.'
    Assert-True (-not (Test-Path -LiteralPath $declinedRoot)) 'Setup created files after a no.'
    Assert-True (-not (Test-Path -LiteralPath $hostKey)) 'Setup changed Firefox before a yes.'

    $unverifiedRoot = Join-Path $work 'Unverified Install'
    $unverifiedOllama = Join-Path $work 'unverified\Ollama'
    $unverifiedShots = Join-Path $repo 'tests\out\screenshots\unverified'
    $unverified = Invoke-LumiChild -InstallerArgs @(
        '-Silent', '-AcceptConsent', '-InstallRoot', $unverifiedRoot,
        '-OllamaSetupUrl', $setupUrl, '-OllamaProgramDir', $unverifiedOllama,
        '-Model', $common.Model, '-FirefoxExecutable', $common.FirefoxExecutable,
        '-FirefoxProfileRoot', $profile, '-ScreenshotDir', $unverifiedShots,
        '-ResultPath', (Join-Path $work 'unverified.json')
    )
    Assert-True ($unverified.ExitCode -eq 1) 'An unverified download was accepted.'
    Assert-CleanOutput $unverified.Stdout
    Assert-True ($unverified.Stdout.Contains('Run setup again.')) ('Unverified text was wrong. out=' + $unverified.Stdout + ' err=' + $unverified.Stderr)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $unverifiedOllama 'setup-count.txt'))) 'The unverified download was started.'
    Assert-Pixel -Path (Join-Path $unverifiedShots 'error.png') -X $layout.CharacterX -Y $layout.CharacterY -Red 163 -Green 190 -Blue 140 -Message 'Gentle Lumi'
    $unverifiedRemove = Invoke-LumiChild -InstallerArgs @('-Silent', '-Uninstall', '-InstallRoot', $unverifiedRoot)
    Assert-True ($unverifiedRemove.ExitCode -eq 0) 'Remove failed after an unverified download.'

    $modelRoot = Join-Path $work 'Model Install'
    $modelOllama = Join-Path $work 'modelfail\Ollama'
    $modelShots = Join-Path $repo 'tests\out\screenshots\model'
    $modelRun = Invoke-LumiChild -InstallerArgs @(
        '-Silent', '-AcceptConsent', '-AllowUnsignedOllamaSetup', '-InstallRoot', $modelRoot,
        '-OllamaSetupUrl', $setupUrl, '-OllamaProgramDir', $modelOllama,
        '-Model', $common.Model, '-FirefoxExecutable', $common.FirefoxExecutable,
        '-FirefoxProfileRoot', $profile, '-ScreenshotDir', $modelShots,
        '-ResultPath', (Join-Path $work 'model.json')
    ) -Environment @{ LUMI_FAKE_PULL_EXIT = '3' }
    Assert-True ($modelRun.ExitCode -eq 1) 'A failed model download looked successful.'
    Assert-CleanOutput $modelRun.Stdout
    Assert-True ($modelRun.Stdout.Contains('Balanced mode will carry you for now.')) 'Model problem text was wrong.'
    $modelSettings = [System.IO.File]::ReadAllText((Join-Path $modelRoot 'settings.json')) | ConvertFrom-Json
    Assert-True ($modelSettings.mode -eq 'balanced') 'Failed Thorough setup did not move to Balanced.'
    $modelState = Read-LumiJsonFile -Path (Join-Path $modelRoot 'install-state.json')
    if ($modelState.ContainsKey('backendPid')) { $cleanupPids.Add([int]$modelState['backendPid']) }
    Assert-Pixel -Path (Join-Path $modelShots 'error.png') -X $layout.CharacterX -Y $layout.CharacterY -Red 163 -Green 190 -Blue 140 -Message 'Gentle Lumi'
    $modelLog = [System.IO.File]::ReadAllText((Join-Path $modelRoot 'logs\install.log'))
    Assert-True ($modelLog.Contains('Downloading Model')) 'Model download step was skipped.'
    Assert-True ($modelRun.Stdout -notmatch 'fake pull') 'Model error text included program output.'
    $modelRemove = Invoke-LumiChild -InstallerArgs @('-Silent', '-Uninstall', '-InstallRoot', $modelRoot)
    Assert-True ($modelRemove.ExitCode -eq 0) 'Remove failed after a model problem.'
    Assert-True (Test-Path -LiteralPath $modelOllama) 'Ollama was removed when it should stay.'
    if ($modelState.ContainsKey('backendPid')) {
        $still = Get-Process -Id ([int]$modelState['backendPid']) -ErrorAction SilentlyContinue
        Assert-True (-not $still) 'The background program kept running after Remove.'
    }

    $root = Join-Path $work 'Lumi Install'
    $ollamaDir = Join-Path $work 'happy\Ollama'
    $shots = Join-Path $repo 'tests\out\screenshots\success'
    $resultPath = Join-Path $work 'success.json'
    $run = Invoke-LumiChild -InstallerArgs @(
        '-Silent', '-AcceptConsent', '-AllowUnsignedOllamaSetup', '-InstallRoot', $root,
        '-OllamaSetupUrl', $setupUrl, '-OllamaProgramDir', $ollamaDir,
        '-Model', 'lumi-ci-tiny', '-FirefoxExecutable', $common.FirefoxExecutable,
        '-FirefoxProfileRoot', $profile, '-ScreenshotDir', $shots, '-ResultPath', $resultPath
    )
    Assert-True ($run.ExitCode -eq 0) ('Setup failed: ' + $run.Stdout + $run.Stderr)
    Assert-CleanOutput $run.Stdout
    Assert-True ($run.Stdout.Contains('Lumi is ready on this computer.')) 'Success text was wrong.'
    Assert-True ($run.Stdout.Contains('Firefox is not on this computer yet.')) 'Missing Firefox was not explained.'
    Assert-True (-not $run.Stdout.Contains('Add Lumi Focus')) 'Installed Lumi Focus was not found.'
    foreach ($relative in @(
        'LumiHelper.exe', 'settings.json', 'default-settings.json', 'consent.txt',
        'bring-a-tab-back.txt', 'firefox-command.json', 'install-state.json', 'result.json',
        'native-host\lumi_focus.json', 'logs\install.log', 'share\product.json', 'lib\Ui.ps1'
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $root $relative)) ('Missing ' + $relative)
    }
    $manifest = [System.IO.File]::ReadAllText((Join-Path $root 'native-host\lumi_focus.json')) | ConvertFrom-Json
    $helperPath = Join-Path $root 'LumiHelper.exe'
    Assert-True ($manifest.name -eq 'lumi_focus') 'Helper name was not registered.'
    Assert-True ($manifest.type -eq 'stdio') 'Helper type was not registered.'
    Assert-True (Test-SameFile $manifest.path $helperPath) ('Helper path was not registered. manifest=' + $manifest.path)
    Assert-True (@($manifest.allowed_extensions) -contains 'lumi-focus@test') 'Lumi Focus was not allowed to talk to the helper.'
    $registered = (Get-Item -LiteralPath $hostKey).GetValue('')
    Assert-True (Test-SameFile $registered (Join-Path $root 'native-host\lumi_focus.json')) ('Firefox was not pointed at the helper note. registered=' + $registered)
    Assert-True (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Mozilla\NativeMessagingHosts\lumi_focus')) 'Setup wrote a machine-wide Firefox key.'
    Assert-True (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\NativeMessagingHosts\lumi_focus')) 'Setup wrote a 32-bit machine-wide Firefox key.'
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    Assert-True (Test-Path -LiteralPath (Join-Path $programs 'Lumi Setup.lnk')) 'Setup shortcut is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $programs 'Remove Lumi.lnk')) 'Remove shortcut is missing.'
    $settings = [System.IO.File]::ReadAllText((Join-Path $root 'settings.json')) | ConvertFrom-Json
    Assert-True ($settings.mode -eq 'thorough') 'A finished setup did not choose Thorough.'
    Assert-True ($settings.model -eq 'lumi-ci-tiny') 'The setup did not record the model it downloaded.'
    Assert-True ($settings.fallbackMode -eq 'balanced') 'Thorough fallback is not Balanced.'
    Assert-True ($settings.reopenLastClosedShortcut.windows -eq 'Ctrl+Alt+S') 'Settings shortcut is not Ctrl+Alt+S.'
    Assert-True ($settings.collectPersonalData -eq $false) 'Settings allow personal data collection.'
    $defaultsOnDisk = [System.IO.File]::ReadAllText((Join-Path $root 'default-settings.json')) | ConvertFrom-Json
    Assert-True ($defaultsOnDisk.model -eq 'gemma3:4b') 'The default model file was overwritten.'
    $origins = [Environment]::GetEnvironmentVariable('OLLAMA_ORIGINS', 'User')
    Assert-True ($origins -eq (Merge-OllamaOrigins -Current $savedOrigins -Required 'moz-extension://*')) 'Firefox was not allowed to reach the model.'
    $log = [System.IO.File]::ReadAllText((Join-Path $root 'logs\install.log'))
    Assert-True ($log.Contains('STEP Downloading Ollama App...')) 'Ollama step was not recorded.'
    Assert-True ($log.Contains('STEP Downloading Model')) 'Model step was not recorded.'
    Assert-True ($log.Contains('STEP Starting Application Backend')) 'Backend step was not recorded.'
    Assert-True ($log.Contains('VERYSILENT')) 'Program output was not kept in the log.'
    Assert-True ($log.Contains('pull lumi-ci-tiny')) 'Model download output was not kept in the log.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $ollamaDir 'setup-count.txt') -Raw).Trim() -eq '1') 'Ollama setup did not run once.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $ollamaDir 'pull-count.txt') -Raw).Trim() -eq '1') 'The model was not downloaded once.'
    $started = $false
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $marker = Join-Path $ollamaDir 'backend-started.txt'
        if (Test-Path -LiteralPath $marker) {
            $started = ([System.IO.File]::ReadAllText($marker).Contains('moz-extension://*'))
            break
        }
        Start-Sleep -Milliseconds 200
    }
    Assert-True $started 'The background program did not see the Firefox permission.'
    Assert-True (Test-OllamaCorsAllowed -BaseUrl 'http://127.0.0.1:11434') 'Firefox was not allowed to reach the model.'
    $state = Read-LumiJsonFile -Path (Join-Path $root 'install-state.json')
    $cleanupPids.Add([int]$state['backendPid'])

    $ping = Send-NativeMessage -Exe $helperPath -Json '{"action":"getSettings"}'
    Assert-True ($ping.ok -eq $true) 'Helper did not answer.'
    Assert-True ($ping.shortcut -eq 'Ctrl+Alt+S') 'Helper shortcut is not Ctrl+Alt+S.'
    Assert-True ($ping.mode -eq 'thorough') 'Helper mode is not Thorough.'
    Assert-True ($ping.fallbackMode -eq 'balanced') 'Helper fallback is not Balanced.'
    Assert-True ($ping.settings.collectPersonalData -eq $false) 'Helper reported data collection.'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $blocked = Send-NativeMessage -Exe $helperPath -Json '{"action":"classify","title":"SECRET-TITLE-DO-NOT-LOG","url":"http://example.test/page","ollamaBaseUrl":"http://example.test:9"}'
    $watch.Stop()
    Assert-True ($blocked.fallback -eq $true -and $blocked.mode -eq 'balanced') 'A non-local model was used.'
    Assert-True ($watch.Elapsed.TotalSeconds -lt 5) 'A non-local model call waited too long.'
    $chatJson = '{"message":{"role":"assistant","content":"close"}}'
    $chatServer = Start-LocalByteServer -Payload ([System.Text.Encoding]::UTF8.GetBytes($chatJson))
    $servers.Add($chatServer)
    $chatUrl = 'http://127.0.0.1:' + $chatServer.Port + '/api/chat'
    $good = Send-NativeMessage -Exe $helperPath -Json ('{"action":"classify","title":"SECRET-TITLE-DO-NOT-LOG","url":"http://127.0.0.1/page","ollamaBaseUrl":"' + $chatUrl + '"}')
    Assert-True ($good.ok -eq $true -and $good.fallback -eq $false -and $good.mode -eq 'thorough' -and $good.decision -eq 'close') 'The model path did not return a Thorough answer.'
    $helperLog = ''
    $helperLogPath = Join-Path $root 'logs\helper.log'
    if (Test-Path -LiteralPath $helperLogPath) { $helperLog = [System.IO.File]::ReadAllText($helperLogPath) }
    Assert-True (-not $helperLog.Contains('SECRET-TITLE-DO-NOT-LOG')) 'The helper stored a page title.'

    $edited = Read-LumiJsonFile -Path (Join-Path $root 'settings.json')
    $edited['mode'] = 'light'
    if ($edited.ContainsKey('closeDistractingTabs')) { $edited.Remove('closeDistractingTabs') | Out-Null }
    Write-LumiJsonFile -Object $edited -Path (Join-Path $root 'settings.json')
    $again = Invoke-LumiChild -InstallerArgs @(
        '-Silent', '-AcceptConsent', '-AllowUnsignedOllamaSetup', '-InstallRoot', $root,
        '-OllamaSetupUrl', $setupUrl, '-OllamaProgramDir', $ollamaDir,
        '-Model', 'lumi-ci-tiny', '-FirefoxExecutable', $common.FirefoxExecutable,
        '-FirefoxProfileRoot', $profile, '-ResultPath', (Join-Path $work 'rerun.json')
    )
    Assert-True ($again.ExitCode -eq 0) ('Running setup again failed: ' + $again.Stdout + $again.Stderr)
    Assert-CleanOutput $again.Stdout
    $rerunSettings = [System.IO.File]::ReadAllText((Join-Path $root 'settings.json')) | ConvertFrom-Json
    Assert-True ($rerunSettings.mode -eq 'light') 'Running setup again replaced a chosen mode.'
    Assert-True ($rerunSettings.closeDistractingTabs -eq $true) 'Running setup again dropped a missing setting.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $ollamaDir 'setup-count.txt') -Raw).Trim() -eq '1') 'Ollama setup ran again.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $ollamaDir 'pull-count.txt') -Raw).Trim() -eq '1') 'The model downloaded again.'
    $rerunLog = [System.IO.File]::ReadAllText((Join-Path $root 'logs\install.log'))
    $lastRun = $rerunLog.Substring($rerunLog.LastIndexOf('RUN BEGIN'))
    Assert-True ($lastRun.Contains('Model is already on this computer')) 'A second run downloaded the model again.'
    Assert-True ($lastRun.Contains('STEP Starting Application Backend')) 'A second run did not restart the background program.'
    Assert-True (Test-OllamaCorsAllowed -BaseUrl 'http://127.0.0.1:11434') 'Firefox was not allowed to reach the model after a restart.'
    Assert-True ($lastRun.Contains('Ollama is already on this computer')) 'A second run downloaded Ollama again.'
    $kept = Send-NativeMessage -Exe $helperPath -Json '{"action":"getSettings"}'
    Assert-True ($kept.mode -eq 'light') 'Helper forgot the chosen mode.'
    Assert-True ($kept.shortcut -eq 'Ctrl+Alt+S') 'Helper lost Ctrl+Alt+S.'
    Assert-True ($kept.settings.closeDistractingTabs -eq $true) 'Helper did not fill a missing setting.'

    $layout = Get-LumiLayout
    Assert-Pixel -Path (Join-Path $shots '01-consent.png') -X 8 -Y 8 -Red 30 -Green 34 -Blue 42 -Message 'Consent background'
    Assert-Pixel -Path (Join-Path $shots '01-consent.png') -X 260 -Y 496 -Red 106 -Green 140 -Blue 175 -Message 'Continue button'
    Assert-Pixel -Path (Join-Path $shots '05-complete.png') -X $layout.CharacterX -Y $layout.CharacterY -Red 163 -Green 190 -Blue 140 -Message 'Happy Lumi'
    Assert-Pixel -Path (Join-Path $shots '07-ready.png') -X $layout.CharacterX -Y $layout.CharacterY -Red 106 -Green 140 -Blue 175 -Message 'Ready Lumi'
    Assert-Pixel -Path (Join-Path $shots '02-downloading-ollama.png') -X $layout.CharacterX -Y $layout.CharacterY -Red 163 -Green 190 -Blue 140 -Message 'Working Lumi'
    foreach ($name in @('01-consent.png', '02-downloading-ollama.png', '03-downloading-model.png', '04-starting-backend.png', '05-complete.png', '06-fade.png', '07-ready.png')) {
        $file = Join-Path $shots $name
        Assert-True ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1500)) ('Screenshot missing: ' + $name)
        Assert-GentleBitmap -Path $file
    }
    Assert-GentleBitmap -Path (Join-Path $unverifiedShots 'error.png')
    Assert-GentleBitmap -Path (Join-Path $modelShots 'error.png')
    Assert-GentleBitmap -Path (Join-Path $unverifiedShots 'error-fade.png')

    $remove = Invoke-LumiChild -InstallerArgs @('-Silent', '-Uninstall', '-RemoveOllama', '-InstallRoot', $root, '-ResultPath', (Join-Path $work 'remove.json'))
    Assert-True ($remove.ExitCode -eq 0) 'Remove failed.'
    Assert-CleanOutput $remove.Stdout
    Assert-True (-not (Test-Path -LiteralPath $root)) 'Lumi files remained.'
    Assert-True (-not (Test-Path -LiteralPath $ollamaDir)) 'Ollama files installed by setup remained.'
    Assert-True (-not (Test-Path -LiteralPath $hostKey)) 'Firefox helper registration remained.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $programs 'Lumi Setup.lnk'))) 'Setup shortcut remained.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $programs 'Remove Lumi.lnk'))) 'Remove shortcut remained.'
    $afterOrigins = [Environment]::GetEnvironmentVariable('OLLAMA_ORIGINS', 'User')
    if ([string]::IsNullOrEmpty($savedOrigins)) { Assert-True ([string]::IsNullOrEmpty($afterOrigins)) 'Firefox permission was not cleared.' }
    else { Assert-True ($afterOrigins -eq $savedOrigins) 'The previous Firefox permission was not restored.' }
    if ($state.ContainsKey('backendPid')) {
        $alive = Get-Process -Id ([int]$state['backendPid']) -ErrorAction SilentlyContinue
        Assert-True (-not $alive) 'The background program remained.'
    }
    $removeAgain = Invoke-LumiChild -InstallerArgs @('-Silent', '-Uninstall', '-InstallRoot', $root)
    Assert-True ($removeAgain.ExitCode -eq 0) 'Remove was not safe to run twice.'

    $logDest = Join-Path $repo 'tests\out\logs'
    New-Item -ItemType Directory -Force -Path $logDest | Out-Null
    foreach ($pair in @(
        @{ Name = 'success.txt'; Text = $run.Stdout },
        @{ Name = 'rerun.txt'; Text = $again.Stdout },
        @{ Name = 'model.txt'; Text = $modelRun.Stdout },
        @{ Name = 'unverified.txt'; Text = $unverified.Stdout }
    )) {
        [System.IO.File]::WriteAllText((Join-Path $logDest $pair.Name), $pair.Text)
    }
    Write-Output 'Installer checks passed.'
} finally {
    foreach ($server in $servers) {
        try { $server.Listener.Stop() } catch {}
        try { $server.PowerShell.Stop() } catch {}
        try { $server.PowerShell.Dispose() } catch {}
        try { $server.Handle.AsyncWaitHandle.Close() } catch {}
    }
    foreach ($processId in $cleanupPids) {
        try { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($null -ne $savedHost) {
        try { Register-LumiNativeHost -HostName 'lumi_focus' -ManifestPath $savedHost } catch {}
    } else {
        try { Unregister-LumiNativeHost -HostName 'lumi_focus' } catch {}
    }
    try { Set-UserOllamaOrigins -Value $savedOrigins } catch {
        try { [Environment]::SetEnvironmentVariable('OLLAMA_ORIGINS', $savedOrigins, 'User') } catch {}
    }
    if (Test-Path -LiteralPath $work) {
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
