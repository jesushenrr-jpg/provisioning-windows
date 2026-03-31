<#
.SYNOPSIS
  Orquestrador principal de provisionamento Windows (SEM FEATURES)

.DESCRIPTION
  Fluxo:
    0) Test-Environment.ps1 (pré-check + gate humano)
    1) drivers.ps1
    2) apps-install.ps1
    3) full-validation.ps1

  - Executa como Administrador
  - Encadeia scripts corretamente
  - Não fecha automaticamente
#>

# ============================
# AUTO-ELEVAÇÃO
# ============================
function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell `
      "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
      -Verb RunAs
    exit 0
  }
}
Ensure-Administrator

# ============================
# PATHS
# ============================
$RunDir   = $PSScriptRoot
$RepoRoot = Split-Path $RunDir -Parent

$ChecksDir = Join-Path $RepoRoot "checks"
$StepsDir  = Join-Path $RepoRoot "steps"

$LogsDir = "C:\Logs\setup"

# ============================
# SCRIPTS
# ============================
$PreCheckScript = Join-Path $ChecksDir "Test-Environment.ps1"

$Pipeline = @(
  @{ Name="Drivers"; Path=(Join-Path $StepsDir "drivers.ps1") },
  @{ Name="Apps";    Path=(Join-Path $StepsDir "apps-install.ps1") },
  @{ Name="Validate";Path=(Join-Path $StepsDir "full-validation.ps1") }
)

# ============================
# EXECUÇÃO COM CONTROLE
# ============================
function Invoke-Step {
  param([string]$Name,[string]$Path)

  Write-Host ""
  Write-Host ">>> $Name" -ForegroundColor Cyan
  Write-Host "Arquivo: $Path"

  if (-not (Test-Path $Path)) {
    Write-Host "ERRO: Script não encontrado!" -ForegroundColor Red
    exit 2
  }

  $p = Start-Process powershell `
    "-NoProfile -ExecutionPolicy Bypass -File `"$Path`"" `
    -Wait -PassThru -NoNewWindow

  return $p.ExitCode
}

# ============================
# PRÉ-CHECK (GATE)
# ============================
Write-Host ""
Write-Host "==== PRÉ-VALIDAÇÃO DO AMBIENTE ====" -ForegroundColor Green

& powershell -NoProfile -ExecutionPolicy Bypass -File $PreCheckScript
$preCode = $LASTEXITCODE

while ($true) {
  Write-Host ""
  Write-Host "[C] Continuar pipeline"
  Write-Host "[R] Rodar Test-Environment novamente"
  Write-Host "[O] Abrir pasta de logs"
  Write-Host "[N] Abrir log do Test-Environment"
  Write-Host "[Q] Sair"

  $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToUpper()

  switch ($k) {
    "C" { break }
    "R" {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $PreCheckScript
      $preCode = $LASTEXITCODE
    }
    "O" { Start-Process explorer.exe $LogsDir }
    "N" {
      $f = Join-Path $LogsDir "Test-Environment.log"
      if (Test-Path $f) { Start-Process notepad.exe $f }
    }
    "Q" { exit $preCode }
  }
}

# ============================
# PIPELINE
# ============================
foreach ($step in $Pipeline) {
  $code = Invoke-Step -Name $step.Name -Path $step.Path
  if ($code -ne 0) {
    Write-Host "Falha em $($step.Name). Pipeline interrompida." -ForegroundColor Red
    exit $code
  }
}

Write-Host ""
Write-Host "PROVISIONAMENTO FINALIZADO ✅" -ForegroundColor Green
exit 0
``
