$ErrorActionPreference = 'Stop'
# Run as the same Windows user who runs Claude Code / Codex. No administrator needed.
$InstallDir = Join-Path $env:LOCALAPPDATA 'TokenCurrent\bin'
New-Item -ItemType Directory -Force $InstallDir | Out-Null
$TaskName = 'Token Current Agent'
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$Binary = Join-Path $InstallDir 'token-current-agent.exe'
Copy-Item (Join-Path $PSScriptRoot 'token-current-agent.exe') $Binary -Force
$ConfigDir = Join-Path $env:APPDATA 'Token Current'
$ConfigPath = Join-Path $ConfigDir 'agent.json'
if (!(Test-Path $ConfigPath)) { & $Binary init; if ($LASTEXITCODE -ne 0) { throw 'Agent initialization failed' } }
# Configuration contains pairing credentials. Restrict access to the current user and SYSTEM.
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $ConfigDir /inheritance:r /grant:r "${Identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect agent configuration' }
$Action = New-ScheduledTaskAction -Execute $Binary -Argument 'run --background' -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $Identity
$Principal = New-ScheduledTaskPrincipal -UserId $Identity -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
# Existing signed-in Tailscale installations need no copied pairing token.
if ((Get-Command tailscale -ErrorAction SilentlyContinue) -or (Test-Path 'C:\Program Files\Tailscale\tailscale.exe')) { & $Binary tailscale }
Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed and running. Pairing token: & '$Binary' token"
Write-Host "Tailscale: & '$Binary' tailscale"
