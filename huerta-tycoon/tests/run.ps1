# Builds the test place, opens it in Studio, waits for the AutoTest plugin to finish, prints [TEST] lines.
param([string]$Project = "test.project.json", [int]$TimeoutSec = 240)
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$place = Join-Path $root "autotest.rbxlx"
& .\tools\rojo.exe build $Project -o $place | Out-Null
$exe = (Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\*\RobloxStudioBeta.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$start = Get-Date
Start-Process $exe -ArgumentList "`"$place`""
$logDir = "$env:LOCALAPPDATA\Roblox\logs"
$log = $null
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
  Start-Sleep 3
  $log = Get-ChildItem $logDir -Filter "*Studio*" | Where-Object { $_.LastWriteTime -gt $start } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($log -and (Select-String -Path $log.FullName -Pattern "\[AUTOTEST DONE\]" -Quiet)) { break }
}
if ($log) {
  Select-String -Path $log.FullName -Pattern "\[TEST|\[AUTOTEST|Error|error" | ForEach-Object { $_.Line -replace '^.*?\[FLog::Output\] ','' } | Select-Object -Unique -First 150
} else { "NO LOG FOUND" }
Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force
