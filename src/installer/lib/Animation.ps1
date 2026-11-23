function Get-LumiCompletionFrame {
    param(
        [double]$ElapsedSeconds,
        [double]$HoldSeconds = 4,
        [double]$FadeSeconds = 2
    )
    if ($FadeSeconds -le 0) { $FadeSeconds = 2 }
    if ($ElapsedSeconds -lt $HoldSeconds) {
        return @{
            Phase = 'complete'
            HappyOpacity = 1.0
            ReadyOpacity = 0.0
            TextOpacity = 0.0
        }
    }
    $fadeEnd = $HoldSeconds + $FadeSeconds
    if ($ElapsedSeconds -ge $fadeEnd) {
        return @{
            Phase = 'ready'
            HappyOpacity = 0.0
            ReadyOpacity = 1.0
            TextOpacity = 1.0
        }
    }
    $t = ($ElapsedSeconds - $HoldSeconds) / $FadeSeconds
    return @{
        Phase = 'fade'
        HappyOpacity = (1.0 - $t)
        ReadyOpacity = $t
        TextOpacity = $t
    }
}
