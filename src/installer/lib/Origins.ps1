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
    try {
        if (-not ('LumiNative.EnvironmentNotice' -as [type])) {
            Add-Type -Namespace LumiNative -Name EnvironmentNotice -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $result = [UIntPtr]::Zero
        [LumiNative.EnvironmentNotice]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$result) | Out-Null
    } catch {
        Write-LumiLog 'environment notice skipped'
    }
}
