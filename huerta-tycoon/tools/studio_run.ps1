# Opens a place in Roblox Studio on the SECONDARY monitor (keeps focus on whatever the user is using),
# waits for the AutoTestRunner plugin to print [AUTOTEST DONE], prints [TEST] lines, closes Studio.
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [string]$Project = "test.project.json",
  [int]$TimeoutSec = 300,
  [switch]$KeepOpen,
  [string[]]$Sizes = @(),          # e.g. "1920x1032","1400x760","1100x620": resize Studio during the playtest
  [string]$ShotDir = "C:\work\_Personal\media\roblox-shots",
  [string]$ShotPrefix = "shot"
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public static IntPtr FindMain(int[] pids) {
    IntPtr best = IntPtr.Zero; int area = 0;
    EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid);
      if (Array.IndexOf(pids, (int)pid) >= 0 && IsWindowVisible(h)) { RECT r; GetWindowRect(h, out r);
        int a = (r.R - r.L) * (r.B - r.T); if (a > area) { area = a; best = h; } } return true; }, IntPtr.Zero);
    return best;
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
if (-not ("W" -as [type])) { Write-Error "window helper failed to compile; not launching Studio"; exit 1 }
$second = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $second) { Write-Error "No secondary monitor"; exit 1 }
$wa = $second.WorkingArea

function Move-StudioWindows([int[]]$pids) {
  $script:moved = 0
  [W]::EnumWindows({ param($h, $l)
    $procId = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$procId)
    if ($pids -contains [int]$procId -and [W]::IsWindowVisible($h)) {
      $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
      if ($r.L -lt $wa.X -or $r.L -ge ($wa.X + $wa.Width)) {
        [void][W]::ShowWindow($h, 4)  # SW_SHOWNOACTIVATE
        $w = [Math]::Min($r.R - $r.L, $wa.Width); $hh = [Math]::Min($r.B - $r.T, $wa.Height)
        if ($w -gt 800) { $w = $wa.Width; $hh = $wa.Height }
        [void][W]::SetWindowPos($h, [IntPtr]::Zero, $wa.X + [int](($wa.Width - $w) / 2), $wa.Y + [int](($wa.Height - $hh) / 2), $w, $hh, 0x0010 -bor 0x0004)  # NOACTIVATE|NOZORDER
        $script:moved++
      }
    }
    return $true }, [IntPtr]::Zero) | Out-Null
}

# one Studio run at a time (several agents share this runner)
$lockFile = "C:\work\_Personal\proyectos\huerta-tycoon\tools\.studio.lock"
# atomic acquire (CreateNew): two waiters can never both get it and kill each other's Studio
while ($true) {
  try {
    $fs = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
    $b = [Text.Encoding]::ASCII.GetBytes("$PID"); $fs.Write($b, 0, $b.Length); $fs.Close(); break
  } catch {
    $li = Get-Item $lockFile -ErrorAction SilentlyContinue
    if ($li -and ((Get-Date) - $li.LastWriteTime).TotalMinutes -ge 12) { Remove-Item $lockFile -ErrorAction SilentlyContinue }
    else { Start-Sleep (Get-Random -Minimum 3 -Maximum 8) }
  }
}
try {
Set-Location $ProjectDir
$tools = "C:\work\_Personal\proyectos\huerta-tycoon\tools"
Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$place = Join-Path $ProjectDir "autotest.rbxlx"
& "$tools\rojo.exe" build $Project -o $place | Out-Null
$exe = (Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\*\RobloxStudioBeta.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$userWindow = [W]::GetForegroundWindow()
$start = Get-Date
Start-Process $exe -ArgumentList "`"$place`"" -WindowStyle Minimized
$logDir = "$env:LOCALAPPDATA\Roblox\logs"
$log = $null
$sizesDone = $Sizes.Count -eq 0
$playStarted = $null
New-Item -ItemType Directory -Force $ShotDir | Out-Null
Add-Type -AssemblyName System.Drawing
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
  Start-Sleep -Milliseconds 400
  $pids = @(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if ($pids.Count) {
    Move-StudioWindows $pids
    if ($script:moved -gt 0 -and $userWindow -ne [IntPtr]::Zero) { [void][W]::SetForegroundWindow($userWindow) }
  }
  $log = Get-ChildItem $logDir -Filter "*Studio*" | Where-Object { $_.LastWriteTime -gt $start } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($log -and (Select-String -Path $log.FullName -Pattern "\[AUTOTEST DONE\]" -Quiet)) { break }
  if (-not $sizesDone -and $log -and -not $playStarted -and (Select-String -Path $log.FullName -Pattern "\[AUTOTEST\] starting playtest" -Quiet)) { $playStarted = Get-Date }
  if (-not $sizesDone -and $playStarted -and ((Get-Date) - $playStarted).TotalSeconds -gt 14) {
    foreach ($sz in $Sizes) {
      $w, $h = $sz.Split("x") | ForEach-Object { [int]$_ }
      $main = [W]::FindMain($pids)
      [void][W]::ShowWindow($main, 4)
      [void][W]::SetWindowPos($main, [IntPtr]::Zero, $wa.X, $wa.Y, $w, $h, 0x0010 -bor 0x0004)
      Start-Sleep 7
      $r = New-Object W+RECT; [void][W]::GetWindowRect($main, [ref]$r)
      $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      # PrintWindow (PW_RENDERFULLCONTENT) captures Studio even when another window covers it on monitor 2
      $hdc = $g.GetHdc(); $pwOk = [W]::PrintWindow($main, $hdc, 2); $g.ReleaseHdc($hdc)
      if (-not $pwOk) { $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size) }
      $bmp.Save((Join-Path $ShotDir "$ShotPrefix-$sz.png")); $g.Dispose(); $bmp.Dispose()
      if ($userWindow -ne [IntPtr]::Zero) { [void][W]::SetForegroundWindow($userWindow) }
    }
    $sizesDone = $true
  }
}
if ($log) {
  Select-String -Path $log.FullName -Pattern "\[TEST|\[AUTOTEST|CreatorError|Stack Begin|Script '" |
    ForEach-Object { $_.Line -replace '^.*?(Info|Error|Warning) \[\w+::\w+\] ', '' } | Select-Object -Unique -First 200
} else { "NO LOG FOUND" }
if (-not $KeepOpen) { Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force }
Remove-Item $place -ErrorAction SilentlyContinue
} finally { Remove-Item $lockFile -ErrorAction SilentlyContinue }

