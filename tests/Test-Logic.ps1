$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $repo 'src\installer\lib'
. (Join-Path $lib 'Log.ps1')
. (Join-Path $lib 'Product.ps1')
. (Join-Path $lib 'Messages.ps1')
. (Join-Path $lib 'Animation.ps1')
. (Join-Path $lib 'Firefox.ps1')
. (Join-Path $lib 'Origins.ps1')
. (Join-Path $lib 'NativeHost.ps1')

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$product = Get-LumiProduct
Assert-True ($product.colors.background -eq '#1E222A') 'Background color changed.'
Assert-True ($product.colors.cream -eq '#E5E9F0') 'Cream color changed.'
Assert-True ($product.colors.sage -eq '#A3BE8C') 'Sage color changed.'
Assert-True ($product.colors.accent -eq '#6A8CAF') 'Accent color changed.'
Assert-True (-not $product.colors.error) 'A harsh color is still listed.'
$paletteText = [System.IO.File]::ReadAllText((Join-Path $repo 'share\product.json')) + [System.IO.File]::ReadAllText((Join-Path $repo 'src\installer\lib\Ui.ps1'))
Assert-True (-not $paletteText.Contains('#E05A5A')) 'Red is still in the installer screens.'
Assert-True (-not $paletteText.Contains('#000000')) 'Jet black is still in the installer screens.'
Assert-True (-not $paletteText.Contains('#FF0000')) 'Bright red is still in the installer screens.'
$notice = [System.IO.File]::ReadAllText((Join-Path $repo 'src\installer\lib\Origins.ps1'))
Assert-True ($notice.Contains(', 2, 300,')) 'The environment notice is not the short aborting kind.'
Assert-True ($notice.Contains('WaitForExit(1000)')) 'The environment notice can stall setup.'
Assert-True ([int]$product.completionHoldSeconds -eq 4) 'Completion hold is not 4 seconds.'
Assert-True ([int]$product.completionFadeSeconds -eq 2) 'Completion fade is not 2 seconds.'
Assert-True ($product.readyText -eq "Close this tab and let's get started!") 'Ready text changed.'
Assert-True ($product.steps.save -eq 'Saving Lumi on this computer') 'Save step text changed.'
Assert-True ($product.steps.ollamaCheck -eq 'Checking Ollama') 'Ollama check text changed.'
Assert-True ($product.steps.ollamaApp -eq 'Downloading Ollama') 'Ollama step text changed.'
Assert-True ($product.steps.start -eq 'Starting Ollama') 'Start step text changed.'
Assert-True ($product.steps.model -eq 'Getting Gemma ready') 'Model step text changed.'
Assert-True ($product.steps.talk -eq 'Checking that Lumi can talk to Gemma') 'Talk step text changed.'
Assert-True ($product.ollamaOrigin -eq 'moz-extension://*') 'Firefox origin changed.'
Assert-True ($product.nativeHostName -eq 'lumi_focus') 'Helper name changed.'

$messages = Get-LumiMessages -Product $product
Assert-True ($messages.ReadyText -eq "Close this tab and let's get started!") 'Ready message changed.'
Assert-True ($messages.StepSave -eq 'Saving Lumi on this computer') 'Save message changed.'
Assert-True ($messages.StepOllama -eq 'Downloading Ollama') 'Ollama message changed.'
Assert-True ($messages.StepTalk -eq 'Checking that Lumi can talk to Gemma') 'Talk message changed.'
Assert-True ($messages.ErrorHint -match 'Lumi[\\/]logs[\\/]install\.log') 'Error hint does not point at the install log.'

$banned = @('System Override', 'Diagnostic', 'Recalibrating', 'Press Enter')
$scanFiles = @(
    (Join-Path $repo 'src\installer\lib\Messages.ps1'),
    (Join-Path $repo 'src\installer\lib\Ui.ps1'),
    (Join-Path $repo 'share\consent.txt'),
    (Join-Path $repo 'share\bring-a-tab-back.txt'),
    (Join-Path $repo 'share\product.json'),
    (Join-Path $repo 'share\default-settings.json'),
    (Join-Path $repo 'share\firefox-command.json')
)
foreach ($file in $scanFiles) {
    $text = [System.IO.File]::ReadAllText($file)
    foreach ($word in $banned) {
        Assert-True (-not $text.Contains($word)) ($word + ' appears in ' + $file)
    }
}
$installerSource = [System.IO.File]::ReadAllText((Join-Path $repo 'src\installer\Install-Lumi.ps1'))
foreach ($word in @('System Override', 'Recalibrating', 'Press Enter')) {
    Assert-True (-not $installerSource.Contains($word)) ($word + ' appears in the installer.')
}
foreach ($value in @(Get-LumiUserStrings -Product $product)) {
    foreach ($word in $banned) {
        Assert-True (-not $value.Contains($word)) ($word + ' appears in a user message.')
    }
}

$start = Get-LumiCompletionFrame -ElapsedSeconds 0 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($start.Phase -eq 'complete' -and $start.HappyOpacity -eq 1 -and $start.TextOpacity -eq 0) 'Start frame is not the happy screen.'
$justBefore = Get-LumiCompletionFrame -ElapsedSeconds 3.99 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($justBefore.Phase -eq 'complete') 'Happy screen ended early.'
$fadeStart = Get-LumiCompletionFrame -ElapsedSeconds 4 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($fadeStart.Phase -eq 'fade' -and [Math]::Abs($fadeStart.HappyOpacity - 1) -lt 0.001 -and $fadeStart.TextOpacity -eq 0) 'Fade did not start at 4 seconds.'
$mid = Get-LumiCompletionFrame -ElapsedSeconds 5 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($mid.Phase -eq 'fade' -and [Math]::Abs($mid.HappyOpacity - 0.5) -lt 0.001 -and [Math]::Abs($mid.TextOpacity - 0.5) -lt 0.001) 'Mid fade is not half way.'
$ready = Get-LumiCompletionFrame -ElapsedSeconds 6 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($ready.Phase -eq 'ready' -and $ready.ReadyOpacity -eq 1 -and $ready.TextOpacity -eq 1 -and $ready.HappyOpacity -eq 0) 'Ready screen is wrong at 6 seconds.'
$later = Get-LumiCompletionFrame -ElapsedSeconds 8 -HoldSeconds 4 -FadeSeconds 2
Assert-True ($later.Phase -eq 'ready' -and $later.TextOpacity -eq 1) 'Ready screen did not stay.'

Assert-True ((Merge-OllamaOrigins -Current '' -Required 'moz-extension://*') -eq 'moz-extension://*') 'Empty origin merge failed.'
$once = Merge-OllamaOrigins -Current 'chrome-extension://*' -Required 'moz-extension://*'
Assert-True ($once -eq 'chrome-extension://*,moz-extension://*') 'Origin merge dropped an existing value.'
$twice = Merge-OllamaOrigins -Current $once -Required 'moz-extension://*'
Assert-True ($twice -eq $once) 'Origin merge duplicated a value.'

Assert-True ((Get-FirefoxClass -Found $false -Major 0 -Minimum 115) -eq 'missing') 'Missing Firefox was not reported.'
Assert-True ((Get-FirefoxClass -Found $true -Major 100 -Minimum 115) -eq 'older') 'Older Firefox was not reported.'
Assert-True ((Get-FirefoxClass -Found $true -Major 115 -Minimum 115) -eq 'ok') 'Current Firefox was rejected.'
Assert-True ((Get-FirefoxClass -Found $true -Major 128 -Minimum 115) -eq 'ok') 'Newer Firefox was rejected.'

$emptyProfile = Join-Path ([System.IO.Path]::GetTempPath()) ('lumi-empty-' + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $emptyProfile | Out-Null
$none = @(Get-LumiExtensionIdsFromProfiles -ProfileRoot $emptyProfile -ExtensionName 'Lumi Focus')
Assert-True ($none.Count -eq 0) 'An empty Firefox folder looked like Lumi Focus was installed.'
Remove-Item -LiteralPath $emptyProfile -Recurse -Force

$manifestDir = Join-Path ([System.IO.Path]::GetTempPath()) ('lumi-manifest-' + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
$manifestPath = Join-Path $manifestDir 'lumi_focus.json'
Write-LumiNativeManifest -ManifestPath $manifestPath -HostName 'lumi_focus' -ExePath 'C:\Program Files\Lumi\LumiHelper.exe' -ExtensionIds @('lumi-focus@test')
$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
Assert-True ($manifest.name -eq 'lumi_focus') 'Manifest name is wrong.'
Assert-True ($manifest.path -eq 'C:\Program Files\Lumi\LumiHelper.exe') 'Manifest path is wrong.'
Assert-True ($manifest.type -eq 'stdio') 'Manifest type is wrong.'
$extensionIds = @($manifest.allowed_extensions)
Assert-True ($extensionIds.Count -eq 1) 'Manifest did not keep a one-item list.'
Assert-True ([string]$extensionIds[0] -eq 'lumi-focus@test') 'Manifest extension id is wrong.'
Remove-Item -LiteralPath $manifestDir -Recurse -Force

$defaults = [System.IO.File]::ReadAllText((Join-Path $repo 'share\default-settings.json')) | ConvertFrom-Json
Assert-True ($defaults.mode -eq 'thorough') 'Default mode is not Thorough.'
Assert-True ($defaults.fallbackMode -eq 'balanced') 'Fallback mode is not Balanced.'
Assert-True ($defaults.reopenLastClosedShortcut.windows -eq 'Ctrl+Alt+S') 'Windows shortcut is not Ctrl+Alt+S.'
Assert-True ([double]$defaults.lightKeepOpenAtOrBelow -eq 0.17) 'Light cutoff is not 0.17.'
Assert-True ($defaults.collectPersonalData -eq $false) 'Helper defaults collect personal data.'
Assert-True ($defaults.pageTextSentOffMachine -eq $false) 'Helper defaults send page text away.'
$command = [System.IO.File]::ReadAllText((Join-Path $repo 'share\firefox-command.json')) | ConvertFrom-Json
Assert-True ($command.commands.'reopen-last-closed-tab'.suggested_key.windows -eq 'Ctrl+Alt+S') 'Firefox command is not Ctrl+Alt+S on Windows.'
$bringBack = [System.IO.File]::ReadAllText((Join-Path $repo 'share\bring-a-tab-back.txt'))
Assert-True ($bringBack.Contains('Ctrl+Alt+S')) 'Shortcut note does not mention Ctrl+Alt+S.'
Assert-True ($bringBack.Contains('Ctrl+Shift+T')) 'Shortcut note does not mention Firefox''s own shortcut.'

$uiText = [System.IO.File]::ReadAllText((Join-Path $repo 'src\installer\lib\Ui.ps1'))
Assert-True ($uiText.Contains('ErrorHint')) 'The error screen does not show the log.'
Assert-True ($uiText.Contains('StepLabel')) 'Numbered steps are not drawn.'
$ollamaText = [System.IO.File]::ReadAllText((Join-Path $lib 'Ollama.ps1'))
Assert-True ($ollamaText.Contains('/api/show')) 'The model check is missing.'
Assert-True ($ollamaText.Contains('Downloading Ollama...')) 'Ollama progress text is missing.'
Assert-True ($ollamaText.Contains('Downloading Gemma...')) 'Gemma progress text is missing.'
Assert-True ($ollamaText.Contains('DoEvents')) 'The window can freeze during a download.'
Assert-True ($ollamaText.Contains('BeginInvoke')) 'Downloads still block the window.'
$buildText = [System.IO.File]::ReadAllText((Join-Path $repo 'build\Build-Installer.ps1'))
Assert-True ($buildText.Contains('-WindowStyle Hidden')) 'The installer console stays visible.'
Assert-True ($buildText.Contains('wscript.exe')) 'The installer does not hide its console.'
Assert-True ($buildText.Contains('shell.Run command, 0, False')) 'The hidden launcher can leave a console behind.'
$installerText = [System.IO.File]::ReadAllText((Join-Path $repo 'src\installer\Install-Lumi.ps1'))
Assert-True (-not $installerText.Contains('RunAs')) 'Installer asks for administrator.'
Assert-True (-not $installerText.Contains('requireAdministrator')) 'Installer requires administrator.'
Assert-True (-not $installerText.Contains('HKLM:')) 'Installer writes machine-wide registry data.'
$originText = [System.IO.File]::ReadAllText((Join-Path $lib 'Origins.ps1'))
Assert-True ($originText.Contains("'User'")) 'Origin is not saved for the current user.'
Assert-True (-not $originText.Contains("'Machine'")) 'Origin is saved for the whole computer.'

Write-Output 'Logic checks passed.'
