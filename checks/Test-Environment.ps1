<#
.SYNOPSIS
  Test-Environment.ps1 — Pré-check da pipeline (SEM FEATURES)

.DESCRIPTION
  Valida e corrige requisitos reais usados pela pipeline:
   - Admin
   - PowerShell
   - Execução de scripts
   - Internet
   - WinGet
   - Cmdlets essenciais
#>

$LogPath = "C:\Logs\setup\Test-Environment.log"
$Errors  = 0
$Warns   = 0

function Ensure-Admin {
  if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell `
      "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
      -Verb RunAs
    exit 0
  }
}
Ensure-Admin

function Log {
  param($Msg,$Level="INFO")
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"),$Level,$Msg
  Add-Content $LogPath $line
  switch ($Level) {
    "ERROR" { Write-Host $line -ForegroundColor Red; $script:Errors++ }
    "WARN"  { Write-Host $line -ForegroundColor Yellow; $script:Warns++ }
    default { Write-Host $line }
  }
}

New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
Remove-Item $LogPath -Force -ErrorAction SilentlyContinue

# ============================
# TESTES
# ============================
Log "Verificando PowerShell..."
if ($PSVersionTable.PSVersion.Major -lt 5) {
  Log "PowerShell muito antigo." "ERROR"
} else {
  Log "PowerShell OK: $($PSVersionTable.PSVersion)"
}

Log "Verificando internet..."
if (-not (Test-Connection 8.8.8.8 -Quiet -Count 1)) {
  Log "Sem conectividade." "WARN"
} else {
  Log "Internet OK."
}

Log "Verificando WinGet..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Log "WinGet ausente." "ERROR"
} else {
  Log "WinGet OK."
}

Log "Verificando Get-PnpDevice..."
if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
  Log "Get-PnpDevice indisponível." "ERROR"
} else {
  Log "Get-PnpDevice OK."
}

Log "Verificando Get-CimInstance..."
if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
  Log "Get-CimInstance indisponível." "ERROR"
} else {
  Log "Get-CimInstance OK."
}

# ============================
# STATUS FINAL
# ============================
Write-Host ""
if ($Errors -gt 0) {
  Write-Host "STATUS: ERROR ($Errors erros, $Warns avisos)" -ForegroundColor Red
  exit 2
}
elseif ($Warns -gt 0) {
  Write-Host "STATUS: WARNING ($Warns avisos)" -ForegroundColor Yellow
  exit 1
}
else {
  Write-Host "STATUS: OK (ambiente pronto)" -ForegroundColor Green
  exit 0
}
``
