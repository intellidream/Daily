Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$copyOp = [System.Drawing.CopyPixelOperation]([int][System.Drawing.CopyPixelOperation]::SourceCopy -bor [int][System.Drawing.CopyPixelOperation]::CaptureBlt)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size, $copyOp)
$bmp.Save('C:\Users\mihai\desktop_screen.png', [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$bmp.Dispose()
Write-Host "Screen captured with CaptureBlt ($($bounds.Width)x$($bounds.Height)) and saved to C:\Users\mihai\desktop_screen.png"
