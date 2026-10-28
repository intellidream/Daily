Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

$activated = [Microsoft.VisualBasic.Interaction]::AppActivate("DayOne")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("^9")
Start-Sleep -Milliseconds 800
Write-Output "Cosmos Nav Complete (Activated: $activated)"
