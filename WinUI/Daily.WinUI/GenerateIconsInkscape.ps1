# GenerateIconsInkscape.ps1
# Uses Inkscape (MS Store) to rasterize the SVG icon at high quality for all required sizes.

$inkscape  = "C:\Program Files\WindowsApps\25415Inkscape.Inkscape_1.4.30.0_x64__9waqn51p1ttv2\VFS\ProgramFilesX64\Inkscape\bin\inkscape.exe"
$assetsDir = Join-Path $PSScriptRoot "Assets"
$tmpDir    = Join-Path $env:TEMP "DailyIcons"
New-Item -ItemType Directory -Force $tmpDir | Out-Null

# ── Color helpers ──────────────────────────────────────────────────────────────
$navy   = "#0B1121"  # dark bg
$yellow = "#F5F0E8"  # light yellowish-gray fg for dark theme

# Build a colored SVG: flat background rect + recolored icon paths
function Make-ColoredSvg($srcSvg, $iconColor, $bgColor, $outPath) {
	$content = Get-Content $srcSvg -Raw
	# Replace fill:white with the desired icon color
	$content = $content -replace 'fill:white', "fill:$iconColor"
	# Also replace any explicit style="fill:white"
	$content = $content -replace 'style="fill:white', "style=`"fill:$iconColor"
	# Insert a background rect right after the opening <svg ...> tag
	# We target the first > that closes the <svg element
	$bgRect = "<rect width=`"1024`" height=`"1024`" style=`"fill:$bgColor;`"/>"
	$content = $content -replace '(<svg[^>]*>)', "`$1`n  $bgRect"
	# Ensure viewBox and explicit size are present so Inkscape knows dimensions
	if ($content -notmatch 'viewBox') {
		$content = $content -replace '<svg ', '<svg viewBox="0 0 1024 1024" '
	}
	# Replace width/height="100%" with absolute values Inkscape can use
	$content = $content -replace 'width="100%"', 'width="1024"'
	$content = $content -replace 'height="100%"', 'height="1024"'
	Set-Content -Path $outPath -Value $content -Encoding UTF8
}

# Export a PNG at a given size using Inkscape
function Export-Png($svgPath, $size, $outPath) {
	& $inkscape `
		"--export-type=png" `
		"--export-width=$size" `
		"--export-height=$size" `
		"--export-filename=$outPath" `
		$svgPath 2>$null
}

# Assemble an ICO from a list of PNG files using MemoryStream.Write (avoids PowerShell byte-array unrolling)
function Make-Ico($pngFiles, $outPath) {
	$pngDatas = @($pngFiles | ForEach-Object { ,[byte[]][System.IO.File]::ReadAllBytes($_) })
	$count    = $pngDatas.Count
	$ms       = [System.IO.MemoryStream]::new()

	# Helper: write little-endian uint16
	function WriteU16($s, $v) { $s.WriteByte($v -band 0xFF); $s.WriteByte(($v -shr 8) -band 0xFF) }
	# Helper: write little-endian uint32
	function WriteU32($s, $v) { $s.WriteByte($v -band 0xFF); $s.WriteByte(($v -shr 8) -band 0xFF); $s.WriteByte(($v -shr 16) -band 0xFF); $s.WriteByte(($v -shr 24) -band 0xFF) }

	# ICO header
	WriteU16 $ms 0      # reserved
	WriteU16 $ms 1      # type = ICO
	WriteU16 $ms $count

	$dataOffset = 6 + $count * 16

	for ($i = 0; $i -lt $count; $i++) {
		$b  = $pngDatas[$i]
		$sz = $b.Length
		$pw = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
		$ph = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
		$ms.WriteByte( $(if ($pw -ge 256) { 0 } else { $pw }) )   # width
		$ms.WriteByte( $(if ($ph -ge 256) { 0 } else { $ph }) )   # height
		$ms.WriteByte(0)  # colorCount
		$ms.WriteByte(0)  # reserved
		WriteU16 $ms 1    # planes
		WriteU16 $ms 32   # bpp
		WriteU32 $ms $sz
		WriteU32 $ms $dataOffset
		$dataOffset += $sz
	}

	for ($i = 0; $i -lt $count; $i++) {
		$b = $pngDatas[$i]
		$ms.Write($b, 0, $b.Length)
	}

	[System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
	$ms.Dispose()
	Write-Host "  saved $([System.IO.Path]::GetFileName($outPath)) (multi-size ICO)"
}

# ── Prepare colored SVG variants ───────────────────────────────────────────────
$darkSvgSrc  = Join-Path $assetsDir "appicon.theme-dark.svg"
$lightSvgSrc = Join-Path $assetsDir "appicon.theme-light.svg"

# Use assetsDir for colored SVGs and ICO temp PNGs — Inkscape Store sandbox can write here
$darkColored  = Join-Path $assetsDir "_icon-dark-colored.svg"
$lightColored = Join-Path $assetsDir "_icon-light-colored.svg"

Make-ColoredSvg $darkSvgSrc  $yellow $navy   $darkColored
Make-ColoredSvg $lightSvgSrc $navy   $yellow $lightColored

Write-Host "Generating app icons via Inkscape..."

# ── Manifest / shell PNG assets ────────────────────────────────────────────────
$specs = @(
	@{ file = "Square44x44Logo.png";                                      size = 44  },
	@{ file = "Square44x44Logo.scale-100.png";                            size = 44  },
	@{ file = "Square44x44Logo.scale-200.png";                            size = 88  },
	@{ file = "Square44x44Logo.targetsize-16_altform-unplated.png";       size = 16  },
	@{ file = "Square44x44Logo.targetsize-20_altform-unplated.png";       size = 20  },
	@{ file = "Square44x44Logo.targetsize-24_altform-unplated.png";       size = 24  },
	@{ file = "Square44x44Logo.targetsize-32_altform-unplated.png";       size = 32  },
	@{ file = "Square44x44Logo.targetsize-48_altform-unplated.png";       size = 48  },
	@{ file = "Square44x44Logo.targetsize-48_altform-lightunplated.png";  size = 48  },
	@{ file = "Square44x44Logo.targetsize-256_altform-unplated.png";      size = 256 },
	@{ file = "Square150x150Logo.scale-100.png";                          size = 150 },
	@{ file = "Square150x150Logo.scale-200.png";                          size = 300 },
	@{ file = "StoreLogo.png";                                            size = 50; useLightSvg = $true }
)

foreach ($spec in $specs) {
	$svgToUse = if ($spec.useLightSvg) { $lightColored } else { $darkColored }
	$outFile  = Join-Path $assetsDir $spec.file
	Export-Png $svgToUse $spec.size $outFile
	Write-Host "  saved $($spec.file) ($($spec.size)x$($spec.size))"
}

# ── Wide 310x150 logo ─────────────────────────────────────────────────────────
# Reuse already-exported 150x150 icon, composite centered on 310x150 canvas
Add-Type -AssemblyName System.Drawing
$navyColor = [System.Drawing.ColorTranslator]::FromHtml($navy)

$wide = New-Object System.Drawing.Bitmap(310, 150, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gWide = [System.Drawing.Graphics]::FromImage($wide)
$gWide.Clear($navyColor)
$icon150bmp = [System.Drawing.Bitmap]::new((Join-Path $assetsDir "Square150x150Logo.scale-100.png"))
# Draw centered, fitting within height (110px)
$gWide.DrawImage($icon150bmp, [int]((310-110)/2), [int]((150-110)/2), 110, 110)
$icon150bmp.Dispose()
$gWide.Dispose()
$wideOut = Join-Path $assetsDir "Wide310x150Logo.scale-200.png"
$wide.Save($wideOut, [System.Drawing.Imaging.ImageFormat]::Png)
$wide.Dispose()
Write-Host "  saved Wide310x150Logo.scale-200.png (310x150)"

# ── Splash screen ─────────────────────────────────────────────────────────────
$splash = New-Object System.Drawing.Bitmap(620, 300, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gSplash = [System.Drawing.Graphics]::FromImage($splash)
$gSplash.Clear($navyColor)
$icon200bmp = [System.Drawing.Bitmap]::new((Join-Path $assetsDir "Square150x150Logo.scale-200.png"))
$gSplash.DrawImage($icon200bmp, [int]((620-200)/2), [int]((300-200)/2), 200, 200)
$icon200bmp.Dispose()
$gSplash.Dispose()
$splashOut = Join-Path $assetsDir "SplashScreen.scale-200.png"
$splash.Save($splashOut, [System.Drawing.Imaging.ImageFormat]::Png)
$splash.Dispose()
Write-Host "  saved SplashScreen.scale-200.png (620x300)"

# ── ICO (title bar, taskbar, Alt+Tab) ─────────────────────────────────────────
# Reuse already-exported targetsize PNGs — no extra Inkscape calls needed
$icoPngs = @(
	(Join-Path $assetsDir "Square44x44Logo.targetsize-16_altform-unplated.png"),
	(Join-Path $assetsDir "Square44x44Logo.targetsize-20_altform-unplated.png"),
	(Join-Path $assetsDir "Square44x44Logo.targetsize-24_altform-unplated.png"),
	(Join-Path $assetsDir "Square44x44Logo.targetsize-32_altform-unplated.png"),
	(Join-Path $assetsDir "Square44x44Logo.targetsize-48_altform-unplated.png"),
	(Join-Path $assetsDir "Square150x150Logo.scale-100.png"),       # 150px
	(Join-Path $assetsDir "Square44x44Logo.targetsize-256_altform-unplated.png")
)
$icoOut = Join-Path $assetsDir "AppIcon.ico"
Make-Ico $icoPngs $icoOut

Write-Host "Done! All assets regenerated with Inkscape."

# Cleanup temp files
Get-ChildItem $assetsDir -Filter "_*" | Remove-Item -Force
