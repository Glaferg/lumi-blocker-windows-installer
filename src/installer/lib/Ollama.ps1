function Save-RemoteFile {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$TimeoutMs = 3600000
    )
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if ($TimeoutMs -gt 20000 -and $Url -match '(?i)^https?://(127\.0\.0\.1|localhost)(:|/|$)') {
        $TimeoutMs = 20000
    }
    $attempts = 0
    $lastError = $null
    while ($attempts -lt 2) {
        $attempts += 1
        try {
            $request = [System.Net.WebRequest]::Create($Url)
            if ($Url -match '(?i)^https?://(127\.0\.0\.1|localhost)(:|/|$)') {
                $request.Proxy = $null
            }
            $request.Timeout = $TimeoutMs
            $request.ReadWriteTimeout = $TimeoutMs
            $response = $request.GetResponse()
            try {
                $inputStream = $response.GetResponseStream()
                $output = [System.IO.File]::Create($Destination)
                try {
                    $inputStream.CopyTo($output)
                } finally {
                    $output.Dispose()
                    $inputStream.Dispose()
                }
            } finally {
                $response.Dispose()
            }
            return
        } catch {
            $lastError = $_
            Write-LumiLog ('download attempt ' + $attempts + ' failed')
        }
    }
    throw 'LUMI:download'
}

function Test-TrustedExecutable {
    param([string]$Path)
    $sig = Get-AuthenticodeSignature -FilePath $Path
    Write-LumiLog ('signature ' + $sig.Status)
    return ($sig.Status -eq 'Valid')
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList
    )
    $logDir = Split-Path -Parent $script:LumiLogPath
    if (-not $logDir) { $logDir = $env:TEMP }
    $stamp = [Guid]::NewGuid().ToString('n')
    $outFile = Join-Path $logDir ($stamp + '.out.txt')
    $errFile = Join-Path $logDir ($stamp + '.err.txt')
    Write-LumiLog ('run ' + $FilePath + ' ' + ($ArgumentList -join ' '))
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (Test-Path -LiteralPath $outFile) {
        Write-LumiLog ([System.IO.File]::ReadAllText($outFile))
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $errFile) {
        Write-LumiLog ([System.IO.File]::ReadAllText($errFile))
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    return [int]$proc.ExitCode
}

function Stop-OllamaGracefully {
    param([string]$ExePath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    if (-not $name) { return }
    $running = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }
    foreach ($proc in $running) {
        try { [void]$proc.CloseMainWindow() } catch {}
    }
    $deadline = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name $name -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 200
    }
    foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 300
    foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Start-OllamaBackend {
    param([string]$ExePath)
    Stop-OllamaGracefully -ExePath $ExePath
    $backend = Start-Process -FilePath $ExePath -ArgumentList @('app') -PassThru -WindowStyle Hidden
    return [int]$backend.Id
}

function Test-OllamaCorsAllowed {
    param([string]$BaseUrl)
    if (-not $BaseUrl) { $BaseUrl = 'http://127.0.0.1:11434' }
    $url = $BaseUrl.TrimEnd('/') + '/api/version'
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        $response = $null
        try {
            $request = [System.Net.WebRequest]::Create($url)
            $request.Method = 'GET'
            $request.Timeout = 2000
            $request.Proxy = $null
            $request.Headers.Add('Origin', 'moz-extension://test')
            $response = $request.GetResponse()
            $allow = [string]$response.Headers['Access-Control-Allow-Origin']
            Write-LumiLog ('cors ' + $allow)
            if ($allow -eq 'moz-extension://test' -or $allow -eq '*') { return $true }
        } catch {
            Start-Sleep -Milliseconds 250
        } finally {
            if ($response) { $response.Close() }
        }
    }
    return $false
}

function Test-OllamaModelPresent {
    param(
        [string]$OllamaExe,
        [string]$Model
    )
    $logDir = Split-Path -Parent $script:LumiLogPath
    if (-not $logDir) { $logDir = $env:TEMP }
    $stamp = [Guid]::NewGuid().ToString('n')
    $outFile = Join-Path $logDir ($stamp + '.list.txt')
    $errFile = Join-Path $logDir ($stamp + '.list.err.txt')
    $proc = Start-Process -FilePath $OllamaExe -ArgumentList @('list') -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $text = ''
    if (Test-Path -LiteralPath $outFile) { $text = [System.IO.File]::ReadAllText($outFile) }
    Write-LumiLog $text
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) { return $false }
    foreach ($line in ($text -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.ToLower().StartsWith($Model.ToLower())) { return $true }
    }
    return $false
}
