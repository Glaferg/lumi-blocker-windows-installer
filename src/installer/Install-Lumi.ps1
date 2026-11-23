param(
    [switch]$Silent,
    [switch]$Uninstall,
    [switch]$AcceptConsent,
    [switch]$AllowUnsignedOllamaSetup,
    [switch]$RemoveOllama,
    [string]$InstallRoot,
    [string]$OllamaSetupUrl,
    [string]$OllamaProgramDir,
    [string]$Model,
    [string]$FirefoxExecutable,
    [string]$FirefoxProfileRoot,
    [string]$ScreenshotDir,
    [string]$ResultPath,
    [string]$ExtensionId
)

$ErrorActionPreference = 'Stop'
if ($env:LUMI_SILENT -eq '1') { $Silent = $true }
if ($env:LUMI_ACCEPT -eq '1') { $AcceptConsent = $true }
if ($env:LUMI_ALLOW_UNSIGNED -eq '1') { $AllowUnsignedOllamaSetup = $true }
$script:LumiHome = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $script:LumiHome 'lib\Log.ps1')
. (Join-Path $script:LumiHome 'lib\Product.ps1')
. (Join-Path $script:LumiHome 'lib\Messages.ps1')
. (Join-Path $script:LumiHome 'lib\Animation.ps1')
. (Join-Path $script:LumiHome 'lib\Firefox.ps1')
. (Join-Path $script:LumiHome 'lib\Origins.ps1')
. (Join-Path $script:LumiHome 'lib\NativeHost.ps1')
. (Join-Path $script:LumiHome 'lib\Settings.ps1')
. (Join-Path $script:LumiHome 'lib\Ollama.ps1')
. (Join-Path $script:LumiHome 'lib\Ui.ps1')
. (Join-Path $script:LumiHome 'lib\Uninstall.ps1')

function Write-LumiUser {
    param([string]$Message)
    if ($Message) { [Console]::Out.WriteLine($Message) }
}

function Copy-LumiFile {
    param([string]$From, [string]$To)
    $left = [System.IO.Path]::GetFullPath($From)
    $right = [System.IO.Path]::GetFullPath($To)
    if ($left -eq $right) { return }
    $dir = Split-Path -Parent $To
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Copy-LumiPayload {
    param([string]$Destination)
    Copy-LumiFile -From (Join-Path $script:LumiHome 'Install-Lumi.ps1') -To (Join-Path $Destination 'Install-Lumi.ps1')
    $libDest = Join-Path $Destination 'lib'
    New-Item -ItemType Directory -Force -Path $libDest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $script:LumiHome 'lib') -File | ForEach-Object {
        Copy-LumiFile -From $_.FullName -To (Join-Path $libDest $_.Name)
    }
    $shareDest = Join-Path $Destination 'share'
    New-Item -ItemType Directory -Force -Path $shareDest | Out-Null
    Get-ChildItem -LiteralPath (Get-LumiShareDir) -File | ForEach-Object {
        Copy-LumiFile -From $_.FullName -To (Join-Path $shareDest $_.Name)
    }
    $helper = Join-Path $script:LumiHome 'LumiHelper.exe'
    if (-not (Test-Path -LiteralPath $helper)) { throw 'LUMI:generic' }
    Copy-LumiFile -From $helper -To (Join-Path $Destination 'LumiHelper.exe')
    Copy-LumiFile -From (Join-Path (Get-LumiShareDir) 'default-settings.json') -To (Join-Path $Destination 'default-settings.json')
    Copy-LumiFile -From (Join-Path (Get-LumiShareDir) 'consent.txt') -To (Join-Path $Destination 'consent.txt')
    Copy-LumiFile -From (Join-Path (Get-LumiShareDir) 'bring-a-tab-back.txt') -To (Join-Path $Destination 'bring-a-tab-back.txt')
    Copy-LumiFile -From (Join-Path (Get-LumiShareDir) 'firefox-command.json') -To (Join-Path $Destination 'firefox-command.json')
}

function Save-LumiShot {
    param([string]$Name, $Frame)
    if (-not $script:ShotDir) { return }
    Save-LumiPng -Path (Join-Path $script:ShotDir ($Name + '.png')) -Frame $Frame
}

function Set-LumiStep {
    param([string]$Text, [string]$Detail, [string]$ShotName)
    Write-LumiLog ('STEP ' + $Text)
    $frame = @{
        Phase = 'working'
        Step = $Text
        Detail = $Detail
        HappyOpacity = 0
        ReadyOpacity = 0
        TextOpacity = 0
    }
    if (-not $Silent -and $script:LumiForm) { Update-LumiForm -Frame $frame }
    if ($ShotName) { Save-LumiShot -Name $ShotName -Frame $frame }
}

function Publish-LumiResult {
    param(
        [bool]$Ok,
        [int]$Code,
        [string]$Message,
        [string[]]$Warnings
    )
    $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $dict['ok'] = $Ok
    $dict['exitCode'] = $Code
    $dict['message'] = $Message
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($warning in @($Warnings)) {
        if ($warning) { $list.Add([string]$warning) }
    }
    $dict['warnings'] = $list
    $targets = New-Object System.Collections.Generic.List[string]
    if ($ResultPath) { $targets.Add($ResultPath) }
    if ($InstallRoot -and (Test-Path -LiteralPath $InstallRoot)) {
        $targets.Add((Join-Path $InstallRoot 'result.json'))
    }
    foreach ($target in $targets) {
        $dir = Split-Path -Parent $target
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Write-LumiJsonFile -Object $dict -Path $target
    }
    Write-LumiUser $Message
    foreach ($warning in $list) { Write-LumiUser $warning }
}

function Get-FriendlyMessage {
    param([string]$Kind, $Messages)
    switch ($Kind) {
        'download' { return $Messages.DownloadFailed }
        'unverified' { return $Messages.Unverified }
        'setup' { return $Messages.SetupFailed }
        'model' { return $Messages.ModelFailed }
        'declined' { return $Messages.Declined }
        default { return $Messages.GenericError }
    }
}

function Show-LumiTrouble {
    param([string]$Message, [string]$ShotName)
    $fading = @{
        Phase = 'error'
        Message = $Message
        ErrorOpacity = 0.45
    }
    $settled = @{
        Phase = 'error'
        Message = $Message
        ErrorOpacity = 1
    }
    Save-LumiShot -Name ($ShotName + '-fade') -Frame $fading
    Save-LumiShot -Name $ShotName -Frame $settled
    if ($Silent -or -not $script:LumiForm) { return }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt 1 -and -not $script:UiState.Closed) {
        $amount = $watch.Elapsed.TotalSeconds
        if ($amount -gt 1) { $amount = 1 }
        Update-LumiForm -Frame @{ Phase = 'error'; Message = $Message; ErrorOpacity = $amount }
        Start-Sleep -Milliseconds 40
    }
    if (-not $script:UiState.Closed) {
        Update-LumiForm -Frame $settled
        Wait-LumiFormClose
    }
}

function Test-BackendAlive {
    param($ProcessId)
    $idValue = 0
    if (-not [int]::TryParse([string]$ProcessId, [ref]$idValue)) { return $false }
    if ($idValue -le 0) { return $false }
    return [bool](Get-Process -Id $idValue -ErrorAction SilentlyContinue)
}

function Install-LumiShortcuts {
    param([string]$Root)
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    if (-not (Test-Path -LiteralPath $programs)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $setup = $shell.CreateShortcut((Join-Path $programs 'Lumi Setup.lnk'))
    $setup.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $setup.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + (Join-Path $Root 'Install-Lumi.ps1') + '" -InstallRoot "' + $Root + '"'
    $setup.WorkingDirectory = $Root
    $setup.Description = 'Set up Lumi'
    $setup.Save()
    $remove = $shell.CreateShortcut((Join-Path $programs 'Remove Lumi.lnk'))
    $remove.TargetPath = $setup.TargetPath
    $remove.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'Install-Lumi.ps1') + '" -Uninstall -InstallRoot "' + $Root + '"'
    $remove.WorkingDirectory = $Root
    $remove.Description = 'Remove Lumi'
    $remove.Save()
}

function Invoke-LumiSetup {
    $product = Get-LumiProduct
    $messages = Get-LumiMessages -Product $product
    $script:ShotDir = $ScreenshotDir
    if (-not $InstallRoot) {
        $script:InstallRoot = Join-Path $env:LOCALAPPDATA $product.installFolderName
        $InstallRoot = $script:InstallRoot
    }
    if ($Uninstall) {
        if (Test-Path -LiteralPath $InstallRoot) {
            Start-LumiLog -Path (Join-Path $InstallRoot 'logs\uninstall.log')
        }
        $code = Uninstall-LumiProduct -InstallRoot $InstallRoot -RemoveOllama:$RemoveOllama -ResultPath $ResultPath -Product $product
        if ($code -eq 0) { Write-LumiUser 'Lumi has been removed.' }
        else { Write-LumiUser $messages.RemoveLocked }
        return $code
    }

    $consentFrame = @{
        Phase = 'consent'
        Step = ''
        Detail = ''
        Message = ''
        HappyOpacity = 0
        ReadyOpacity = 0
        TextOpacity = 0
    }
    Save-LumiShot -Name '01-consent' -Frame $consentFrame

    if (-not $Silent) {
        $script:UiState = @{ Consent = ''; Closed = $false; Frame = $consentFrame }
        Open-LumiForm | Out-Null
        Update-LumiForm -Frame $consentFrame
        while (-not $script:UiState.Consent -and -not $script:UiState.Closed) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
        if ($script:UiState.Consent -ne 'continue') {
            if ($script:LumiForm) { $script:LumiForm.Close() }
            Publish-LumiResult -Ok $false -Code 3 -Message $messages.Declined -Warnings @()
            return 3
        }
    } elseif (-not $AcceptConsent) {
        try {
            Publish-LumiResult -Ok $false -Code 3 -Message $messages.Declined -Warnings @()
        } catch {
            [Console]::Error.WriteLine($_.Exception.ToString())
            [Console]::Out.WriteLine($messages.Declined)
        }
        return 3
    }

    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Start-LumiLog -Path (Join-Path $InstallRoot 'logs\install.log')
    Write-LumiLog 'RUN BEGIN'

    try {
        Copy-LumiPayload -Destination $InstallRoot
        $chosenModel = $product.model
        if ($Model) { $chosenModel = $Model }
        Initialize-LumiSettings -InstallRoot $InstallRoot -Model $chosenModel | Out-Null

        $statePath = Join-Path $InstallRoot 'install-state.json'
        if (Test-Path -LiteralPath $statePath) {
            $state = Read-LumiJsonFile -Path $statePath
        } else {
            $state = New-Object 'System.Collections.Generic.Dictionary[string,object]'
        }
        $state['version'] = [string]$product.version
        $state['model'] = [string]$chosenModel

        $minimum = [int]$product.minFirefoxMajor
        $firefox = Get-LumiFirefoxStatus -ExecutablePath $FirefoxExecutable -MinimumMajor $minimum
        $state['firefox'] = [string]$firefox.Status
        Write-LumiLog ('firefox ' + $firefox.Status)
        $warnings = New-Object System.Collections.Generic.List[string]
        $detail = $messages.StepShortcut
        if ($firefox.Status -eq 'missing') {
            $warnings.Add($messages.FirefoxMissing)
            $detail = $messages.FirefoxMissing
        } elseif ($firefox.Status -eq 'older') {
            $warnings.Add($messages.FirefoxOlder)
            $detail = $messages.FirefoxOlder
        }

        $ids = New-Object 'System.Collections.Generic.List[string]'
        foreach ($configured in @(Read-ConfiguredExtensionIds -Path (Join-Path (Get-LumiShareDir) 'extension-ids.json'))) {
            if ($configured -and -not $ids.Contains($configured)) { $ids.Add($configured) }
        }
        if ($ExtensionId -and -not $ids.Contains($ExtensionId)) { $ids.Add($ExtensionId) }
        $profileRoot = $FirefoxProfileRoot
        if (-not $profileRoot) { $profileRoot = Join-Path $env:APPDATA 'Mozilla\Firefox' }
        foreach ($found in @(Get-LumiExtensionIdsFromProfiles -ProfileRoot $profileRoot -ExtensionName $product.extensionName)) {
            if ($found -and -not $ids.Contains($found)) { $ids.Add($found) }
        }
        if ($ids.Count -eq 0) { $warnings.Add($messages.ExtensionMissing) }
        $state['extensionIds'] = $ids

        $helperPath = Join-Path $InstallRoot 'LumiHelper.exe'
        $manifestPath = Join-Path $InstallRoot ('native-host\' + $product.nativeHostName + '.json')
        Write-LumiNativeManifest -ManifestPath $manifestPath -HostName $product.nativeHostName -ExePath $helperPath -ExtensionIds @($ids.ToArray())
        Register-LumiNativeHost -HostName $product.nativeHostName -ManifestPath $manifestPath
        try { Install-LumiShortcuts -Root $InstallRoot } catch { Write-LumiLog 'shortcut skipped' }
        Set-LumiStep -Text $messages.StepSave -Detail $detail -ShotName '00-saving'
        Write-LumiJsonFile -Object $state -Path $statePath

        if (-not ($state.ContainsKey('originsSaved') -and $state['originsSaved'])) {
            $previous = Get-UserOllamaOrigins
            if ($previous) { $state['previousOllamaOrigins'] = [string]$previous }
            else { $state['previousOllamaOrigins'] = '' }
            $state['originsSaved'] = $true
            Write-LumiJsonFile -Object $state -Path $statePath
        }
        $merged = Merge-OllamaOrigins -Current (Get-UserOllamaOrigins) -Required ([string]$product.ollamaOrigin)
        Set-UserOllamaOrigins -Value $merged
        $env:OLLAMA_ORIGINS = $merged
        Write-LumiLog 'origins updated'

        if (-not $OllamaProgramDir) {
            $OllamaProgramDir = Join-Path $env:LOCALAPPDATA 'Programs\Ollama'
        }
        $env:LUMI_OLLAMA_DIR = $OllamaProgramDir
        $state['ollamaProgramDir'] = $OllamaProgramDir
        $ollamaExe = Join-Path $OllamaProgramDir 'ollama.exe'
        if (Test-Path -LiteralPath $ollamaExe) {
            Set-LumiStep -Text $messages.StepOllamaReady -Detail $detail -ShotName '02-downloading-ollama'
            if (-not $state.ContainsKey('ollamaInstalledByLumi')) { $state['ollamaInstalledByLumi'] = $false }
        } else {
            Set-LumiStep -Text $messages.StepOllama -Detail 'This can take a while on a slow connection.' -ShotName '02-downloading-ollama'
            $setupUrl = $OllamaSetupUrl
            if (-not $setupUrl) { $setupUrl = [string]$product.ollamaSetupUrl }
            $setupPath = Join-Path $InstallRoot 'cache\OllamaSetup.exe'
            Save-RemoteFile -Url $setupUrl -Destination $setupPath
            if (-not $AllowUnsignedOllamaSetup) {
                if (-not (Test-TrustedExecutable -Path $setupPath)) {
                    Remove-Item -LiteralPath $setupPath -Force -ErrorAction SilentlyContinue
                    throw 'LUMI:unverified'
                }
            }
            $setupCode = Invoke-LoggedProcess -FilePath $setupPath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-')
            if ($setupCode -ne 0 -or -not (Test-Path -LiteralPath $ollamaExe)) { throw 'LUMI:setup' }
            $state['ollamaInstalledByLumi'] = $true
            Write-LumiLog 'ollama installed'
        }
        Write-LumiJsonFile -Object $state -Path $statePath

        $modelFailed = $false
        if (Test-OllamaModelPresent -OllamaExe $ollamaExe -Model $chosenModel) {
            Set-LumiStep -Text $messages.StepModelReady -Detail $detail -ShotName '03-downloading-model'
        } else {
            Set-LumiStep -Text $messages.StepModel -Detail $detail -ShotName '03-downloading-model'
            $pullCode = Invoke-LoggedProcess -FilePath $ollamaExe -ArgumentList @('pull', $chosenModel)
            if ($pullCode -ne 0) {
                $modelFailed = $true
                Set-LumiSetting -InstallRoot $InstallRoot -Name 'mode' -Value 'balanced'
                Write-LumiLog 'model failed'
            }
        }

        Set-LumiStep -Text $messages.StepBackend -Detail $detail -ShotName '04-starting-backend'
        $state['backendPid'] = Start-OllamaBackend -ExePath $ollamaExe
        Write-LumiLog ('backend ' + $state['backendPid'])
        $cors = Test-OllamaCorsAllowed -BaseUrl ([string]$product.ollamaBaseUrl)
        $state['corsAllowed'] = [bool]$cors
        if (-not $cors) { $warnings.Add($messages.BackendAlreadyOpen) }
        Write-LumiJsonFile -Object $state -Path $statePath

        if ($modelFailed) {
            Show-LumiTrouble -Message $messages.ModelFailed -ShotName 'error'
            Publish-LumiResult -Ok $false -Code 1 -Message $messages.ModelFailed -Warnings @($warnings.ToArray())
            return 1
        }

        $hold = [double]$product.completionHoldSeconds
        $fade = [double]$product.completionFadeSeconds
        $complete = Get-LumiCompletionFrame -ElapsedSeconds 0 -HoldSeconds $hold -FadeSeconds $fade
        $complete['Detail'] = $detail
        Save-LumiShot -Name '05-complete' -Frame $complete
        $midpoint = Get-LumiCompletionFrame -ElapsedSeconds ($hold + ($fade / 2)) -HoldSeconds $hold -FadeSeconds $fade
        $midpoint['Detail'] = $detail
        Save-LumiShot -Name '06-fade' -Frame $midpoint
        $ready = Get-LumiCompletionFrame -ElapsedSeconds ($hold + $fade) -HoldSeconds $hold -FadeSeconds $fade
        $ready['Detail'] = ''
        $ready['ReadyText'] = $messages.ReadyText
        Save-LumiShot -Name '07-ready' -Frame $ready

        if (-not $Silent -and $script:LumiForm) {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($watch.Elapsed.TotalSeconds -lt ($hold + $fade) -and -not $script:UiState.Closed) {
                $live = Get-LumiCompletionFrame -ElapsedSeconds $watch.Elapsed.TotalSeconds -HoldSeconds $hold -FadeSeconds $fade
                $live['Detail'] = $detail
                $live['ReadyText'] = $messages.ReadyText
                Update-LumiForm -Frame $live
                Start-Sleep -Milliseconds 40
            }
            if (-not $script:UiState.Closed) {
                Update-LumiForm -Frame $ready
                Wait-LumiFormClose
            }
        }

        Publish-LumiResult -Ok $true -Code 0 -Message $messages.Success -Warnings @($warnings.ToArray())
        return 0
    } catch {
        $kind = 'generic'
        $raw = $_.Exception.Message
        Write-LumiLog $raw
        if ($raw -like 'LUMI:*') { $kind = $raw.Substring(5) }
        $message = Get-FriendlyMessage -Kind $kind -Messages $messages
        Show-LumiTrouble -Message $message -ShotName 'error'
        Publish-LumiResult -Ok $false -Code 1 -Message $message -Warnings @()
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $code = 1
    try {
        $result = @(Invoke-LumiSetup)
        if ($result.Count -gt 0) { $code = [int]$result[-1] }
    } catch {
        [Console]::Error.WriteLine($_.Exception.ToString())
        [Console]::Out.WriteLine('Lumi could not finish. Close this window and run setup again.')
        $code = 1
    }
    try { $host.SetShouldExit($code) } catch {}
    exit $code
}
