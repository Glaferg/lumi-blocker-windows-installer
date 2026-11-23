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
}
