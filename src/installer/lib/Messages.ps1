function Get-LumiErrorHint {
    $path = '%LOCALAPPDATA%\Lumi\logs\install.log'
    if ($script:LumiLogPath) {
        $path = [string]$script:LumiLogPath
    } elseif ($env:LOCALAPPDATA) {
        $path = Join-Path $env:LOCALAPPDATA 'Lumi\logs\install.log'
    }
    return $path
}

function Get-LumiMessages {
    param($Product)
    $ready = 'Close this tab and let''s get started!'
    if ($Product -and $Product.readyText) { $ready = [string]$Product.readyText }
    $saveStep = 'Saving Lumi on this computer'
    $checkStep = 'Checking Ollama'
    $ollamaStep = 'Downloading Ollama'
    $startStep = 'Starting Ollama'
    $modelStep = 'Getting Gemma ready'
    $talkStep = 'Checking that Lumi can talk to Gemma'
    if ($Product -and $Product.steps) {
        if ($Product.steps.save) { $saveStep = [string]$Product.steps.save }
        if ($Product.steps.ollamaCheck) { $checkStep = [string]$Product.steps.ollamaCheck }
        if ($Product.steps.ollamaApp) { $ollamaStep = [string]$Product.steps.ollamaApp }
        if ($Product.steps.start) { $startStep = [string]$Product.steps.start }
        if ($Product.steps.model) { $modelStep = [string]$Product.steps.model }
        if ($Product.steps.talk) { $talkStep = [string]$Product.steps.talk }
    }
    return @{
        ReadyText = $ready
        StepSave = $saveStep
        StepOllamaCheck = $checkStep
        StepOllama = $ollamaStep
        StepStart = $startStep
        StepModel = $modelStep
        StepTalk = $talkStep
        StepFirefox = 'Checking Firefox'
        StepShortcut = 'Press Ctrl+Alt+S to bring back the last tab.'
        StepModelReady = 'Model is already on this computer'
        StepOllamaReady = 'Ollama is already on this computer'
        StepBackendReady = 'Ollama is already running'
        HeadingComplete = 'Installation complete'
        Success = 'Lumi is ready on this computer.'
        Declined = 'Lumi was not installed.'
        DownloadFailed = 'The download can wait a moment. Check your connection, then run setup again.'
        Unverified = 'Lumi set that download aside. Run setup again.'
        SetupFailed = 'Ollama can wait. Run setup again.'
        ModelFailed = 'Balanced mode will carry you for now. Run setup again whenever you like.'
        FirefoxMissing = 'Firefox is not on this computer yet. Install Firefox, then add Lumi Focus.'
        FirefoxOlder = 'This Firefox is too old for Lumi. Update Firefox, then try again.'
        ExtensionMissing = 'Add Lumi Focus in Firefox, then run setup again so they can work together.'
        BackendAlreadyOpen = 'Ollama is opening again so Thorough mode can see Firefox.'
        GenericError = 'We can try that once more. Run setup again.'
        RemoveLocked = 'Close Firefox, then run Remove Lumi again.'
        Continue = 'Continue'
        NotNow = 'Not now'
        ErrorHint = (Get-LumiErrorHint)
    }
}

function Get-LumiUserStrings {
    param($Product)
    $msgs = Get-LumiMessages -Product $Product
    $values = @()
    foreach ($key in $msgs.Keys) { $values += [string]$msgs[$key] }
    $values += (Get-LumiConsentText)
    $share = Get-LumiShareDir
    $values += [System.IO.File]::ReadAllText((Join-Path $share 'bring-a-tab-back.txt'))
    return $values
}
