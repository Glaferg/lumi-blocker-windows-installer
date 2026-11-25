function Merge-OllamaOrigins {
    param(
        [string]$Current,
        [string]$Required
    )
    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($Current) {
        foreach ($piece in ($Current -split ',')) {
            $trimmed = $piece.Trim()
            if ($trimmed -and -not $parts.Contains($trimmed)) { $parts.Add($trimmed) }
        }
    }
    if ($Required -and -not $parts.Contains($Required)) { $parts.Add($Required) }
    return ($parts -join ',')
}

function Get-UserOllamaOrigins {
    return [Environment]::GetEnvironmentVariable('OLLAMA_ORIGINS', 'User')
}

function Set-UserOllamaOrigins {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        [Environment]::SetEnvironmentVariable('OLLAMA_ORIGINS', $null, 'User')
    } else {
        [Environment]::SetEnvironmentVariable('OLLAMA_ORIGINS', $Value, 'User')
    }
    $env:OLLAMA_ORIGINS = $Value
    Send-UserEnvironmentNotice
}

function Send-UserEnvironmentNotice {
    # SMTO_ABORTIFHUNG is 2. The call itself waits at most 300 ms, and it runs
    # in its own process so a stuck window cannot stall or crash setup.
    $runner = Join-Path $env:TEMP 'lumi-env-notice.ps1'
    $script = @'
$ErrorActionPreference = "Stop"
Add-Type -Namespace LumiNative -Name EnvironmentNotice -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
"@
$noticeResult = [UIntPtr]::Zero
[LumiNative.EnvironmentNotice]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 2, 300, [ref]$noticeResult) | Out-Null
'@
    try {
        [System.IO.File]::WriteAllText($runner, $script)
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $notice = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $runner) -WindowStyle Hidden -PassThru
        if (-not $notice.WaitForExit(1000)) {
            try { Stop-Process -Id $notice.Id -Force -ErrorAction SilentlyContinue } catch {}
            Write-LumiLog 'environment notice stopped'
        } else {
            Write-LumiLog ('environment notice ' + $notice.ExitCode)
        }
    } catch {
        Write-LumiLog 'environment notice skipped'
    }
}
