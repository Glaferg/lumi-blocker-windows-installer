function Get-LumiMessages {
    param($Product)
    $ready = 'Close this tab and let''s get started!'
    if ($Product -and $Product.readyText) { $ready = [string]$Product.readyText }
    $ollamaStep = 'Downloading Ollama App...'
    $modelStep = 'Downloading Model'
    $backendStep = 'Starting Application Backend'
    if ($Product -and $Product.steps) {
        if ($Product.steps.ollamaApp) { $ollamaStep = [string]$Product.steps.ollamaApp }
        if ($Product.steps.model) { $modelStep = [string]$Product.steps.model }
        if ($Product.steps.backend) { $backendStep = [string]$Product.steps.backend }
    }
    return @{
        ReadyText = $ready
        StepOllama = $ollamaStep
        StepModel = $modelStep
        StepBackend = $backendStep
        StepSave = 'Saving Lumi on this computer...'
        StepFirefox = 'Checking Firefox...'
        StepShortcut = 'Press Ctrl+Alt+S to bring back the last tab.'
        StepModelReady = 'Model is already on this computer'
        StepOllamaReady = 'Ollama is already on this computer'
        StepBackendReady = 'Application backend is already running'
        HeadingComplete = 'Installation complete'
        Success = 'Lumi is ready on this computer.'
        Declined = 'Lumi was not installed.'
        DownloadFailed = 'Lumi could not download the Ollama app. Check your internet connection and run setup again.'
        Unverified = 'Lumi could not verify the download, so it stopped. Run setup again.'
        SetupFailed = 'Lumi could not finish setting up the Ollama app. Run setup again.'
        ModelFailed = 'Lumi could not finish the model download. Balanced mode will be used for now. You can run setup again later.'
        FirefoxMissing = 'Firefox is not on this computer yet. Install Firefox, then add Lumi Focus.'
        FirefoxOlder = 'This Firefox is too old for Lumi. Update Firefox, then try again.'
        ExtensionMissing = 'Add Lumi Focus in Firefox, then run setup again so they can work together.'
        BackendAlreadyOpen = 'Ollama was already open. Quit it and open it again so Thorough mode can work.'
        GenericError = 'Lumi could not finish. Close this window and run setup again.'
        RemoveLocked = 'Close Firefox, then run Remove Lumi again.'
        Continue = 'Continue'
        NotNow = 'Not now'
        ErrorHint = 'You can close this window and try again.'
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
