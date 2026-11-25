function Send-LumiUiPulse {
    if (-not ('System.Windows.Forms.Application' -as [type])) { return }
    if (-not $script:LumiForm) { return }
    try {
        if (-not $script:LumiForm.IsDisposed) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    } catch {}
}

function Get-LumiOllamaProgressText {
    param(
        [int64]$Bytes,
        [int]$Dot
    )
    if ($Bytes -le 0) {
        $count = ($Dot % 3) + 1
        return ('Downloading Ollama' + ('.' * $count))
    }
    $mb = [Math]::Round(($Bytes / 1MB), 1)
    if ($mb -lt 0.1) { $mb = 0.1 }
    return ('Downloading Ollama... ' + $mb + ' MB')
}

function Get-LumiGemmaProgressText {
    param(
        [int]$Percent,
        [int]$Dot
    )
    if ($Percent -ge 0) {
        return ('Downloading Gemma... ' + $Percent + '%')
    }
    $count = ($Dot % 3) + 1
    return ('Downloading Gemma' + ('.' * $count))
}

function Save-RemoteFile {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$TimeoutMs = 3600000,
        [scriptblock]$OnProgress
    )
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if ($TimeoutMs -gt 20000 -and $Url -match '(?i)^https?://(127\.0\.0\.1|localhost)(:|/|$)') {
        $TimeoutMs = 20000
    }
    $sync = [hashtable]::Synchronized(@{
        Bytes = [int64]0
        Total = [int64]-1
        Failed = $true
        Error = ''
    })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $pipe = [powershell]::Create()
    $pipe.Runspace = $runspace
    [void]$pipe.AddScript({
        param($FileUrl, $FileDestination, $FileTimeoutMs, $Progress)
        $ErrorActionPreference = 'Stop'
        $attempts = 0
        while ($attempts -lt 2) {
            $attempts += 1
            $response = $null
            $inputStream = $null
            $output = $null
            try {
                if (Test-Path -LiteralPath $FileDestination) {
                    Remove-Item -LiteralPath $FileDestination -Force
                }
                $request = [System.Net.WebRequest]::Create($FileUrl)
                if ($FileUrl -match '(?i)^https?://(127\.0\.0\.1|localhost)(:|/|$)') {
                    $request.Proxy = $null
                }
                $request.Timeout = $FileTimeoutMs
                $request.ReadWriteTimeout = $FileTimeoutMs
                $response = $request.GetResponse()
                if ($response.ContentLength -gt 0) { $Progress.Total = [int64]$response.ContentLength }
                $inputStream = $response.GetResponseStream()
                $output = [System.IO.File]::Create($FileDestination)
                $buffer = New-Object byte[] 8192
                $Progress.Bytes = [int64]0
                while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $output.Write($buffer, 0, $read)
                    $Progress.Bytes = [int64]($Progress.Bytes + $read)
                }
                $output.Flush()
                $Progress.Failed = $false
                $Progress.Error = ''
                return
            } catch {
                $Progress.Failed = $true
                $Progress.Error = $_.Exception.Message
            } finally {
                if ($output) { $output.Dispose() }
                if ($inputStream) { $inputStream.Dispose() }
                if ($response) { $response.Dispose() }
            }
        }
    }).AddArgument($Url).AddArgument($Destination).AddArgument($TimeoutMs).AddArgument($sync)
    $handle = $null
    try {
        $handle = $pipe.BeginInvoke()
        $deadline = (Get-Date).AddMilliseconds(($TimeoutMs * 2) + 5000)
        while (-not $handle.IsCompleted) {
            if ($OnProgress) { & $OnProgress ([int64]$sync.Bytes) ([int64]$sync.Total) }
            Send-LumiUiPulse
            if ((Get-Date) -gt $deadline) {
                try { $pipe.Stop() } catch {}
                throw 'LUMI:download'
            }
            Start-Sleep -Milliseconds 100
        }
        try { $pipe.EndInvoke($handle) | Out-Null } catch {
            $sync.Failed = $true
            $sync.Error = $_.Exception.Message
        }
    } finally {
        $pipe.Dispose()
        $runspace.Close()
        $runspace.Dispose()
    }
    if ($OnProgress) { & $OnProgress ([int64]$sync.Bytes) ([int64]$sync.Total) }
    if ($sync.Failed -or -not (Test-Path -LiteralPath $Destination)) {
        Write-LumiLog ('download failed ' + $sync.Error)
        throw 'LUMI:download'
    }
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
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    while ($proc -and -not $proc.HasExited) {
        Send-LumiUiPulse
        Start-Sleep -Milliseconds 100
    }
    if ($proc) { try { $proc.WaitForExit() } catch {} }
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

function Invoke-OllamaPull {
    param(
        [string]$FilePath,
        [string]$Model,
        [scriptblock]$OnProgress
    )
    if (-not ('LumiLinePump' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Collections.Concurrent;
using System.IO;
using System.Threading;
public class LumiLinePump {
    public static Thread Start(StreamReader reader, ConcurrentQueue<string> lines) {
        Thread thread = new Thread(() => Pump(reader, lines));
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }
    static void Pump(StreamReader reader, ConcurrentQueue<string> lines) {
        try {
            string line;
            while ((line = reader.ReadLine()) != null) {
                lines.Enqueue(line);
            }
        } catch (System.Exception) {}
    }
}
'@
    }
    Write-LumiLog ('run ' + $FilePath + ' pull ' + $Model)
    $quoted = $Model
    if ($quoted.Contains(' ')) { $quoted = '"' + $quoted.Replace('"', '') + '"' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = 'pull ' + $quoted
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $lines = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $kept = New-Object System.Collections.Generic.List[string]
    $outThread = [LumiLinePump]::Start($proc.StandardOutput, $lines)
    $errThread = [LumiLinePump]::Start($proc.StandardError, $lines)
    $dots = 0
    $idle = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $running = (-not $proc.HasExited) -or $outThread.IsAlive -or $errThread.IsAlive
        $pulled = ''
        while ($lines.TryDequeue([ref]$pulled)) { $kept.Add($pulled) }
        if (-not $running) { break }
        if ($proc.HasExited -and $idle.Elapsed.TotalSeconds -gt 3) { break }
        if (-not $proc.HasExited) { $idle.Restart() }
        $percent = -1
        for ($i = $kept.Count - 1; $i -ge 0; $i--) {
            if ([string]$kept[$i] -match '(\d+)\s*%') {
                $percent = [int]$Matches[1]
                break
            }
        }
        $dots += 1
        $detail = Get-LumiGemmaProgressText -Percent $percent -Dot $dots
        if ($OnProgress) { & $OnProgress $detail }
        Send-LumiUiPulse
        Start-Sleep -Milliseconds 100
    }
    try { $proc.WaitForExit() } catch {}
    $pulled = ''
    while ($lines.TryDequeue([ref]$pulled)) { $kept.Add($pulled) }
    if ($kept.Count -gt 0) { Write-LumiLog ($kept -join "`n") }
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
        Send-LumiUiPulse
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
            Send-LumiUiPulse
            Start-Sleep -Milliseconds 250
        } finally {
            if ($response) { $response.Close() }
        }
    }
    return $false
}

function Test-OllamaModelShown {
    param(
        [string]$BaseUrl,
        [string]$Model
    )
    if (-not $BaseUrl) { $BaseUrl = 'http://127.0.0.1:11434' }
    $url = $BaseUrl.TrimEnd('/') + '/api/show'
    $safeModel = ($Model -replace '\\', '\\\\') -replace '"', '\"'
    $payload = '{"model":"' + $safeModel + '"}'
    $sync = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; Note = '' })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $pipe = [powershell]::Create()
    $pipe.Runspace = $runspace
    [void]$pipe.AddScript({
        param($ShowUrl, $Body, $ModelName, $Progress)
        $ErrorActionPreference = 'Stop'
        [System.Net.ServicePointManager]::Expect100Continue = $false
        $deadline = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $deadline) {
            $response = $null
            $stream = $null
            try {
                $request = [System.Net.WebRequest]::Create($ShowUrl)
                $request.Method = 'POST'
                $request.ContentType = 'application/json'
                $request.Timeout = 2000
                $request.Proxy = $null
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                $request.ContentLength = $bytes.Length
                $stream = $request.GetRequestStream()
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Close()
                $stream = $null
                $response = $request.GetResponse()
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $text = $reader.ReadToEnd()
                $reader.Dispose()
                $code = [int]$response.StatusCode
                $Progress.Note = 'api/show ' + $code + ' ' + $text
                if ($code -eq 200 -and $text.ToLower().Contains($ModelName.ToLower())) {
                    $Progress.Ok = $true
                    $Progress.Done = $true
                    return
                }
            } catch {
                $Progress.Note = 'api/show wait'
            } finally {
                if ($stream) { $stream.Dispose() }
                if ($response) { $response.Close() }
            }
            Start-Sleep -Milliseconds 250
        }
        $Progress.Done = $true
        $Progress.Ok = $false
    }).AddArgument($url).AddArgument($payload).AddArgument($Model).AddArgument($sync)
    try {
        $handle = $pipe.BeginInvoke()
        $dots = 0
        $deadline = (Get-Date).AddSeconds(12)
        while (-not $handle.IsCompleted) {
            $dots += 1
            if (Get-Command -Name Update-LumiStepDetail -ErrorAction SilentlyContinue) {
                $count = ($dots % 3) + 1
                Update-LumiStepDetail -Detail ('Just a moment' + ('.' * $count))
            }
            Send-LumiUiPulse
            if ((Get-Date) -gt $deadline) {
                try { $pipe.Stop() } catch {}
                break
            }
            Start-Sleep -Milliseconds 120
        }
        if ($handle.IsCompleted) {
            try { $pipe.EndInvoke($handle) | Out-Null } catch {
                $sync.Note = 'api/show ' + $_.Exception.Message
                $sync.Ok = $false
            }
        }
    } finally {
        $pipe.Dispose()
        $runspace.Close()
        $runspace.Dispose()
    }
    if ($sync.Note) { Write-LumiLog ([string]$sync.Note) } else { Write-LumiLog 'api/show' }
    return [bool]$sync.Ok
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
    $proc = Start-Process -FilePath $OllamaExe -ArgumentList @('list') -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    while ($proc -and -not $proc.HasExited) {
        Send-LumiUiPulse
        Start-Sleep -Milliseconds 100
    }
    if ($proc) { try { $proc.WaitForExit() } catch {} }
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
