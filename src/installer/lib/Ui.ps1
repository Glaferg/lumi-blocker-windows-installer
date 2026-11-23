function Get-LumiLayout {
    return @{
        Width = 960
        Height = 600
        CharacterX = 480
        CharacterY = 220
        CharacterRadius = 86
    }
}

function ConvertTo-LumiColor {
    param(
        [string]$Hex,
        [double]$Opacity = 1
    )
    $value = $Hex.Trim().TrimStart('#')
    $red = [Convert]::ToInt32($value.Substring(0, 2), 16)
    $green = [Convert]::ToInt32($value.Substring(2, 2), 16)
    $blue = [Convert]::ToInt32($value.Substring(4, 2), 16)
    $alpha = [int][Math]::Round(255 * $Opacity)
    if ($alpha -lt 0) { $alpha = 0 }
    if ($alpha -gt 255) { $alpha = 255 }
    return [System.Drawing.Color]::FromArgb($alpha, $red, $green, $blue)
}

function Draw-LumiGlyph {
    param(
        $Graphics,
        [int]$CenterX,
        [int]$CenterY,
        [int]$Radius,
        $Fill,
        $Ink,
        [string]$Mood
    )
    $brush = New-Object System.Drawing.SolidBrush $Fill
    $eye = New-Object System.Drawing.SolidBrush $Ink
    $pen = New-Object System.Drawing.Pen $Ink, ([single]([Math]::Max(2, $Radius * 0.08)))
    try {
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $Graphics.FillEllipse($brush, $CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)
        $eyeR = [int]([Math]::Max(3, $Radius * 0.12))
        $eyeY = $CenterY - [int]($Radius * 0.12)
        $Graphics.FillEllipse($eye, $CenterX - [int]($Radius * 0.38) - $eyeR, $eyeY - $eyeR, $eyeR * 2, $eyeR * 2)
        $Graphics.FillEllipse($eye, $CenterX + [int]($Radius * 0.38) - $eyeR, $eyeY - $eyeR, $eyeR * 2, $eyeR * 2)
        if ($Mood -eq 'gentle') {
            $Graphics.DrawArc($pen, $CenterX - [int]($Radius * 0.22), $CenterY + [int]($Radius * 0.1), [int]($Radius * 0.44), [int]($Radius * 0.28), 15, 150)
        } elseif ($Mood -eq 'ready') {
            $Graphics.DrawArc($pen, $CenterX - [int]($Radius * 0.26), $CenterY + [int]($Radius * 0.08), [int]($Radius * 0.52), [int]($Radius * 0.32), 15, 150)
        } else {
            $Graphics.DrawArc($pen, $CenterX - [int]($Radius * 0.34), $CenterY - [int]($Radius * 0.02), [int]($Radius * 0.68), [int]($Radius * 0.5), 15, 150)
        }
    } finally {
        $brush.Dispose()
        $eye.Dispose()
        $pen.Dispose()
    }
}

function Draw-LumiString {
    param(
        $Graphics,
        [string]$Text,
        $Font,
        $Color,
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [double]$Opacity,
        $Alignment
    )
    if ([string]::IsNullOrEmpty($Text) -or $Opacity -le 0.01) { return }
    $bmp = New-Object System.Drawing.Bitmap ([int]$Width), ([int]$Height), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $inner = [System.Drawing.Graphics]::FromImage($bmp)
    $brush = New-Object System.Drawing.SolidBrush $Color
    $format = New-Object System.Drawing.StringFormat
    try {
        $inner.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $inner.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $inner.Clear([System.Drawing.Color]::Transparent)
        $format.Alignment = $Alignment
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF 0, 0, $Width, $Height
        $inner.DrawString($Text, $Font, $brush, $rect, $format)
        $matrix = New-Object System.Drawing.Imaging.ColorMatrix
        $matrix.Matrix33 = [single]$Opacity
        $attrs = New-Object System.Drawing.Imaging.ImageAttributes
        $attrs.SetColorMatrix($matrix)
        $dest = New-Object System.Drawing.Rectangle ([int]$X), ([int]$Y), $bmp.Width, $bmp.Height
        $Graphics.DrawImage($bmp, $dest, 0, 0, $bmp.Width, $bmp.Height, [System.Drawing.GraphicsUnit]::Pixel, $attrs)
        $attrs.Dispose()
    } finally {
        $format.Dispose()
        $brush.Dispose()
        $inner.Dispose()
        $bmp.Dispose()
    }
}

function Paint-LumiFrame {
    param(
        $Graphics,
        [int]$Width,
        [int]$Height,
        $Frame
    )
    Add-Type -AssemblyName System.Drawing
    $product = Get-LumiProduct
    $messages = Get-LumiMessages -Product $product
    $colors = $product.colors
    $bg = ConvertTo-LumiColor -Hex $colors.background
    $cream = ConvertTo-LumiColor -Hex $colors.cream
    $sage = ConvertTo-LumiColor -Hex $colors.sage
    $accent = ConvertTo-LumiColor -Hex $colors.accent
    $readyColor = ConvertTo-LumiColor -Hex $colors.readyText
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $Graphics.Clear($bg)

    $titleFont = New-Object System.Drawing.Font 'Segoe UI', 18, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Point)
    $stepFont = New-Object System.Drawing.Font 'Segoe UI', 22, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Point)
    $bodyFont = New-Object System.Drawing.Font 'Segoe UI', 15, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Point)
    $smallFont = New-Object System.Drawing.Font 'Segoe UI', 13, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Point)
    $buttonFont = New-Object System.Drawing.Font 'Segoe UI', 14, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Point)
    try {
        Draw-LumiString -Graphics $Graphics -Text $product.productName -Font $titleFont -Color $sage -X 0 -Y 28 -Width $Width -Height 36 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Center)
        $closeBrush = New-Object System.Drawing.SolidBrush $cream
        $Graphics.DrawString('x', $buttonFont, $closeBrush, 916, 22)
        $closeBrush.Dispose()
        $script:LumiCloseRect = New-Object System.Drawing.Rectangle 900, 12, 44, 36

        $phase = [string]$Frame.Phase
        if ($phase -eq 'consent') {
            Draw-LumiGlyph -Graphics $Graphics -CenterX 480 -CenterY 118 -Radius 36 -Fill $sage -Ink $bg -Mood 'calm'
            $consent = Get-LumiConsentText
            Draw-LumiString -Graphics $Graphics -Text $consent -Font $bodyFont -Color $cream -X 120 -Y 170 -Width 720 -Height 280 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Near)
            $button = New-Object System.Drawing.SolidBrush $accent
            $Graphics.FillRectangle($button, 250, 490, 200, 48)
            $button.Dispose()
            $outline = New-Object System.Drawing.Pen $sage, 2
            $Graphics.DrawRectangle($outline, 510, 490, 200, 48)
            $outline.Dispose()
            Draw-LumiString -Graphics $Graphics -Text $messages.Continue -Font $buttonFont -Color $cream -X 250 -Y 490 -Width 200 -Height 48 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Center)
            Draw-LumiString -Graphics $Graphics -Text $messages.NotNow -Font $buttonFont -Color $sage -X 510 -Y 490 -Width 200 -Height 48 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Center)
            $script:LumiContinueRect = New-Object System.Drawing.Rectangle 250, 490, 200, 48
            $script:LumiNotNowRect = New-Object System.Drawing.Rectangle 510, 490, 200, 48
            return
        }

        $layout = Get-LumiLayout
        $happy = 0
        $ready = 0
        if ($Frame.ContainsKey('HappyOpacity')) { $happy = [double]$Frame.HappyOpacity }
        if ($Frame.ContainsKey('ReadyOpacity')) { $ready = [double]$Frame.ReadyOpacity }
        $textOpacity = 0
        if ($Frame.ContainsKey('TextOpacity')) { $textOpacity = [double]$Frame.TextOpacity }

        if ($phase -eq 'working') {
            Draw-LumiGlyph -Graphics $Graphics -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $sage -Ink $bg -Mood 'calm'
            Draw-LumiString -Graphics $Graphics -Text ([string]$Frame.Step) -Font $stepFont -Color $cream -X 80 -Y 360 -Width 800 -Height 70 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Center)
            Draw-LumiString -Graphics $Graphics -Text ([string]$Frame.Detail) -Font $smallFont -Color $sage -X 120 -Y 430 -Width 720 -Height 70 -Opacity 1 -Alignment ([System.Drawing.StringAlignment]::Center)
            return
        }
        if ($phase -eq 'error') {
            $fadeIn = 1.0
            if ($Frame.ContainsKey('ErrorOpacity')) { $fadeIn = [double]$Frame.ErrorOpacity }
            if ($fadeIn -lt 0) { $fadeIn = 0 }
            if ($fadeIn -gt 1) { $fadeIn = 1 }
            $soft = ConvertTo-LumiColor -Hex $colors.sage -Opacity $fadeIn
            Draw-LumiGlyph -Graphics $Graphics -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $soft -Ink $bg -Mood 'gentle'
            Draw-LumiString -Graphics $Graphics -Text ([string]$Frame.Message) -Font $bodyFont -Color $cream -X 80 -Y 350 -Width 800 -Height 120 -Opacity $fadeIn -Alignment ([System.Drawing.StringAlignment]::Center)
            return
        }

        if ($happy -ge 0.999 -and $ready -le 0.001) {
            Draw-LumiGlyph -Graphics $Graphics -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $sage -Ink $bg -Mood 'happy'
        } elseif ($ready -ge 0.999 -and $happy -le 0.001) {
            Draw-LumiGlyph -Graphics $Graphics -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $accent -Ink $bg -Mood 'ready'
        } else {
            $glyph = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $gHappy = [System.Drawing.Graphics]::FromImage($glyph)
            $gHappy.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $gHappy.Clear([System.Drawing.Color]::Transparent)
            Draw-LumiGlyph -Graphics $gHappy -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $sage -Ink $bg -Mood 'happy'
            $readyBmp = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $gReady = [System.Drawing.Graphics]::FromImage($readyBmp)
            $gReady.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $gReady.Clear([System.Drawing.Color]::Transparent)
            Draw-LumiGlyph -Graphics $gReady -CenterX $layout.CharacterX -CenterY $layout.CharacterY -Radius $layout.CharacterRadius -Fill $accent -Ink $bg -Mood 'ready'
            $attrs = New-Object System.Drawing.Imaging.ImageAttributes
            $matrix = New-Object System.Drawing.Imaging.ColorMatrix
            $matrix.Matrix33 = [single]$ready
            $attrs.SetColorMatrix($matrix)
            $gHappy.DrawImage($readyBmp, (New-Object System.Drawing.Rectangle 0, 0, $Width, $Height), 0, 0, $Width, $Height, [System.Drawing.GraphicsUnit]::Pixel, $attrs)
            $Graphics.DrawImage($glyph, 0, 0)
            $attrs.Dispose()
            $gReady.Dispose()
            $readyBmp.Dispose()
            $gHappy.Dispose()
            $glyph.Dispose()
        }

        if ($happy -gt 0.05) {
            Draw-LumiString -Graphics $Graphics -Text $messages.HeadingComplete -Font $stepFont -Color $cream -X 80 -Y 360 -Width 800 -Height 60 -Opacity $happy -Alignment ([System.Drawing.StringAlignment]::Center)
            Draw-LumiString -Graphics $Graphics -Text ([string]$Frame.Detail) -Font $smallFont -Color $sage -X 100 -Y 430 -Width 760 -Height 70 -Opacity $happy -Alignment ([System.Drawing.StringAlignment]::Center)
        }
        $readyText = $messages.ReadyText
        if ($Frame.ContainsKey('ReadyText') -and $Frame.ReadyText) { $readyText = [string]$Frame.ReadyText }
        Draw-LumiString -Graphics $Graphics -Text $readyText -Font $stepFont -Color $readyColor -X 70 -Y 390 -Width 820 -Height 90 -Opacity $textOpacity -Alignment ([System.Drawing.StringAlignment]::Center)
    } finally {
        $titleFont.Dispose()
        $stepFont.Dispose()
        $bodyFont.Dispose()
        $smallFont.Dispose()
        $buttonFont.Dispose()
    }
}

function Save-LumiPng {
    param(
        [string]$Path,
        $Frame
    )
    Add-Type -AssemblyName System.Drawing
    $layout = Get-LumiLayout
    $bmp = New-Object System.Drawing.Bitmap $layout.Width, $layout.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        Paint-LumiFrame -Graphics $graphics -Width $layout.Width -Height $layout.Height -Frame $Frame
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bmp.Dispose()
    }
}

function Open-LumiForm {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $layout = Get-LumiLayout
    $product = Get-LumiProduct
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $product.productName
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize = New-Object System.Drawing.Size $layout.Width, $layout.Height
    $form.BackColor = ConvertTo-LumiColor -Hex $product.colors.background
    $form.ShowInTaskbar = $true
    $form.Add_Paint({
        param($sender, $eventArgs)
        if ($script:UiState -and $script:UiState.Frame) {
            Paint-LumiFrame -Graphics $eventArgs.Graphics -Width $sender.ClientSize.Width -Height $sender.ClientSize.Height -Frame $script:UiState.Frame
        }
    })
    $form.Add_MouseUp({
        param($sender, $eventArgs)
        if ($script:LumiCloseRect -and $script:LumiCloseRect.Contains($eventArgs.Location)) {
            $script:UiState.Closed = $true
            $sender.Close()
            return
        }
        if ($script:UiState.Frame.Phase -eq 'consent') {
            if ($script:LumiContinueRect -and $script:LumiContinueRect.Contains($eventArgs.Location)) {
                $script:UiState.Consent = 'continue'
            }
            if ($script:LumiNotNowRect -and $script:LumiNotNowRect.Contains($eventArgs.Location)) {
                $script:UiState.Consent = 'decline'
            }
        }
    })
    $form.Add_FormClosing({
        $script:UiState.Closed = $true
    })
    $script:LumiForm = $form
    $form.Show()
    $form.Activate()
    return $form
}

function Update-LumiForm {
    param($Frame)
    $script:UiState.Frame = $Frame
    if ($script:LumiForm -and -not $script:LumiForm.IsDisposed) {
        $script:LumiForm.Invalidate()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Wait-LumiFormClose {
    while ($script:LumiForm -and -not $script:LumiForm.IsDisposed -and -not $script:UiState.Closed) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
}
