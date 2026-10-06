Add-Type -AssemblyName System.Drawing

function Create-PromoScreenshot {
    param (
        [string]$title,
        [string]$subtitle,
        [string]$badge,
        [string]$outputPath,
        [string]$featureSnippet
    )

    $width = 1080
    $height = 1920
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # Background gradient matching DESIGN.md
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(0, $height)),
        [System.Drawing.Color]::FromArgb(255, 16, 18, 22),       # Dark Canvas #101216
        [System.Drawing.Color]::FromArgb(255, 20, 35, 74)        # Deep Navy #14234A
    )
    $g.FillRectangle($bgBrush, 0, 0, $width, $height)
    $bgBrush.Dispose()

    # Subtle ambient glow
    $glowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 36, 87, 214))
    $g.FillEllipse($glowBrush, 140, 100, 800, 450)
    $glowBrush.Dispose()

    # Badge Pill (Secondary Container #0F4B44, text #6FD6C8)
    $badgeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 75, 68))
    $badgePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 111, 214, 200), 2)
    $g.FillRectangle($badgeBrush, 360, 120, 360, 56)
    $g.DrawRectangle($badgePen, 360, 120, 360, 56)
    $badgeBrush.Dispose(); $badgePen.Dispose()

    $badgeFont = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
    $badgeTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 111, 214, 200))
    $sfCenter = New-Object System.Drawing.StringFormat
    $sfCenter.Alignment = [System.Drawing.StringAlignment]::Center
    $sfCenter.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($badge, $badgeFont, $badgeTextBrush, (New-Object System.Drawing.RectangleF(360, 120, 360, 56)), $sfCenter)

    # Title & Subtitle
    $titleFont = New-Object System.Drawing.Font("Arial", 42, [System.Drawing.FontStyle]::Bold)
    $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.DrawString($title, $titleFont, $titleBrush, (New-Object System.Drawing.RectangleF(60, 200, 960, 120)), $sfCenter)

    $subFont = New-Object System.Drawing.Font("Arial", 22, [System.Drawing.FontStyle]::Regular)
    $subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 180, 187, 199))
    $g.DrawString($subtitle, $subFont, $subBrush, (New-Object System.Drawing.RectangleF(80, 310, 920, 90)), $sfCenter)

    # Phone Frame Container
    $phoneX = 140
    $phoneY = 430
    $phoneW = 800
    $phoneH = 1420
    $phoneBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 25, 28, 34))
    $phoneBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 52, 59, 71), 6)
    $g.FillRectangle($phoneBg, $phoneX, $phoneY, $phoneW, $phoneH)
    $g.DrawRectangle($phoneBorder, $phoneX, $phoneY, $phoneW, $phoneH)

    # Notch / Header
    $notchBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 37, 42, 51))
    $g.FillRectangle($notchBrush, 390, 440, 300, 28)
    $notchBrush.Dispose()

    # Mock App Bar
    $appBarFont = New-Object System.Drawing.Font("Arial", 26, [System.Drawing.FontStyle]::Bold)
    $appBarBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 142, 171, 255))
    $g.DrawString("IDSnap", $appBarFont, $appBarBrush, 180, 490)

    # Feature Card Mockup inside the phone
    $cardBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 32, 38, 48))
    $cardBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 60, 70, 85), 2)
    $g.FillRectangle($cardBrush, 180, 560, 720, 1180)
    $g.DrawRectangle($cardBorder, 180, 560, 720, 1180)

    if ($featureSnippet -eq "compress") {
        $hFont = New-Object System.Drawing.Font("Arial", 28, [System.Drawing.FontStyle]::Bold)
        $g.DrawString("Target Size: Strictly Under 200 KB", $hFont, [System.Drawing.Brushes]::White, 220, 610)

        $boxBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 20, 24, 30))
        $g.FillRectangle($boxBg, 220, 680, 640, 240)
        
        $bigNumFont = New-Object System.Drawing.Font("Arial", 52, [System.Drawing.FontStyle]::Bold)
        $statBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 111, 214, 200))
        $g.DrawString("184 KB", $bigNumFont, $statBrush, 240, 720)
        
        $statSubFont = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Regular)
        $g.DrawString("Reduced from 4.8 MB (-96%) - Portal Verified", $statSubFont, [System.Drawing.Brushes]::LightGray, 240, 810)

        $g.DrawString("Quality: Intelligent Binary Search Optimization", $statSubFont, [System.Drawing.Brushes]::White, 220, 960)
        $barBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 36, 87, 214))
        $g.FillRectangle($barBg, 220, 1010, 640, 16)
        
        $g.DrawString("Resolution: 300 DPI Native", $statSubFont, [System.Drawing.Brushes]::LightGray, 220, 1060)
        $g.DrawString("Format: ISO Standard PDF / High Contrast JPEG", $statSubFont, [System.Drawing.Brushes]::LightGray, 220, 1100)
        $g.DrawString("Processing: 100% On-Device (0 bytes uploaded)", $statSubFont, $statBrush, 220, 1140)
    }
    elseif ($featureSnippet -eq "passport") {
        $hFont = New-Object System.Drawing.Font("Arial", 28, [System.Drawing.FontStyle]::Bold)
        $g.DrawString("Official Visa and Passport Standards", $hFont, [System.Drawing.Brushes]::White, 220, 610)

        $presets = @(
            "[PRESET] US Visa and Green Card - 2x2 in (51x51 mm)",
            "[PRESET] European Schengen Visa - 35x45 mm",
            "[PRESET] Indian Passport and OCI - 35x45 mm",
            "[PRESET] China Visa - 33x48 mm",
            "[PRESET] Universal ID Card and Badge Size"
        )
        $py = 680
        $pFont = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Bold)
        $pBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 142, 171, 255))
        foreach ($p in $presets) {
            $pBox = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 22, 28, 38))
            $g.FillRectangle($pBox, 220, $py, 640, 80)
            $g.DrawRectangle([System.Drawing.Pens]::SlateGray, 220, $py, 640, 80)
            $g.DrawString($p, $pFont, $pBrush, 240, $py + 26)
            $pBox.Dispose()
            $py += 100
        }
        
        $noteFont = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Italic)
        $g.DrawString("Includes dynamic face, eye-level and chin guideline overlays", $noteFont, [System.Drawing.Brushes]::LightGray, 220, 1210)
    }

    $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $titleFont.Dispose(); $subFont.Dispose(); $titleBrush.Dispose(); $subBrush.Dispose()
    $phoneBg.Dispose(); $phoneBorder.Dispose(); $cardBrush.Dispose(); $cardBorder.Dispose()
    $g.Dispose(); $bmp.Dispose()
}

$assetsDir = "c:\Users\saavi\Desktop\docscan\apps\marketing-web\public\store-assets"

Create-PromoScreenshot `
    -title "TARGET COMPRESSOR" `
    -subtitle "Compress PDFs strictly under 200 KB for portal submission" `
    -badge "PORTAL COMPLIANT" `
    -outputPath "$assetsDir\phone_screenshot_3_compress.png" `
    -featureSnippet "compress"

Create-PromoScreenshot `
    -title "PASSPORT PHOTO STUDIO" `
    -subtitle "Official millimeter crop presets for US, Schengen and global visas" `
    -badge "EMBASSY PRESETS" `
    -outputPath "$assetsDir\phone_screenshot_4_passport.png" `
    -featureSnippet "passport"

Write-Host "Promotional screenshots 3 and 4 generated successfully!"
