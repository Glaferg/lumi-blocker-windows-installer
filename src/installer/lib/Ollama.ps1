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
