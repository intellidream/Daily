& "C:\Users\mihai\source\repos\Daily\Scripts\inspect_daily_windows.ps1" | Set-Content -Path "C:\Users\mihai\windows_dump.txt"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save('C:\Users\mihai\desktop_screen.png', [System.Drawing.Imaging.ImageFormat]::Png)

$thumbWidth = 1024
$thumbHeight = [int]($bounds.Height * ($thumbWidth / $bounds.Width))
$thumb = New-Object System.Drawing.Bitmap $thumbWidth, $thumbHeight
$gThumb = [System.Drawing.Graphics]::FromImage($thumb)
$gThumb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gThumb.DrawImage($bmp, 0, 0, $thumbWidth, $thumbHeight)
$thumb.Save('C:\Users\mihai\desktop_small.png', [System.Drawing.Imaging.ImageFormat]::Png)

$gThumb.Dispose()
$thumb.Dispose()
$graphics.Dispose()
$bmp.Dispose()
Write-Host "Screen captured ($($bounds.Width)x$($bounds.Height)) and saved to C:\Users\mihai\desktop_screen.png"
