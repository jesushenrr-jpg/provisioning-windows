<#
.SYNOPSIS
  run-provisioning.ps1 — Orquestrador principal (SEM FEATURES) com gate de pré-check.

.DESCRIPTION
  Estrutura esperada do repositório:
    RepoRoot\
      run\run-provisioning.ps1
      checks\Test-Environment.ps1
      steps\drivers.ps1
      steps\apps-install.ps1
      steps\validation\full-validation.ps1

  Fluxo:
    0) checks\Test-Environment.ps1   (gate humano por tecla)
    1) steps\drivers.ps1             (WU -> analysis -> report)
    2) steps\apps-install.ps1        (winget + config.json)
    3) steps\validation\full-validation.ps1

  - Auto-elevação para Administrador
  - Execução sequencial (um após o outro)
  - Não fecha automaticamente
#>

# ============================
# AUTO-ELEVAÇÃO
# ============================
function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)

  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Reiniciando com privilégios de Administrador..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", "`"$PSCommandPath`""
    ) -Verb RunAs | Out-Null
    exit 0
  }
}
Ensure-Administrator

# ============================
# PATHS (baseado no repo)
# ============================
$RunDir   = $PSScriptRoot
$RepoRoot = Split-Path -Path $RunDir -Parent

$ChecksDir = Join-Path $RepoRoot "checks"
$StepsDir  = Join-Path $RepoRoot "steps"
$ValDir    = Join-Path $StepsDir "validation"

$LogsDir = "C:\Logs\setup"
if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

$PreCheckScript = Join-Path $ChecksDir "Test-Environment.ps1"
$PreCheckLog    = Join-Path $LogsDir "Test-Environment.log"
$ValidationLog  = Join-Path $LogsDir "07-full-validation.log"

# ============================
# PIPELINE (SEM FEATURES)
# ============================
$Pipeline = @(
  @{ Name="Drivers";   Path=(Join-Path $StepsDir "drivers.ps1") },
  @{ Name="Apps";      Path=(Join-Path $StepsDir "apps-install.ps1") },
  @{ Name="Validation";Path=(Join-Path $ValDir  "full-validation.ps1") }
)

# ============================
# HELPERS UX
# ============================
function Read-KeyUpper {
  # Retorna uma string em UpperInvariant a partir de ReadKey().Character
  return $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToUpperInvariant()
}

function Open-LogsFolder {
  try {
    Start-Process -FilePath "explorer.exe" -ArgumentList $LogsDir | Out-Null
    Write-Host "Abrindo pasta de logs: $LogsDir" -ForegroundColor Green
  } catch {
    Write-Host "Falha ao abrir pasta de logs: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function Open-PreCheckLogNotepad {
  try {
    if (Test-Path $PreCheckLog) {
      Start-Process -FilePath "notepad.exe" -ArgumentList $PreCheckLog | Out-Null
      Write-Host "Abrindo log do Test-Environment: $PreCheckLog" -ForegroundColor Green
    } else {
      Write-Host "Log do Test-Environment ainda não existe: $PreCheckLog" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "Falha ao abrir Notepad: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function Show-FullValidationLog {
  Write-Host ""
  Write-Host "===============================================" -ForegroundColor Cyan
  Write-Host "LOG DA VALIDAÇÃO FINAL (full-validation)" -ForegroundColor Cyan
  Write-Host "===============================================" -ForegroundColor Cyan
  Write-Host "Arquivo: $ValidationLog"
  Write-Host ""

  if (Test-Path $ValidationLog) {
    Get-Content $ValidationLog | ForEach-Object {
      if ($_ -match "\[ERROR\]") { Write-Host $_ -ForegroundColor Red }
      elseif ($_ -match "\[WARN\]") { Write-Host $_ -ForegroundColor Yellow }
      else { Write-Host $_ }
    }
  } else {
    Write-Host "Log de validação não encontrado: $ValidationLog" -ForegroundColor Yellow
  }
  Write-Host ""
}

# ============================
# EXECUÇÃO CONTROLADA DE UM STEP
# ============================
function Invoke-Step {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Path
  )

  Write-Host ""
  Write-Host "===============================================" -ForegroundColor DarkGray
  Write-Host "Executando: $Name" -ForegroundColor Cyan
  Write-Host "Arquivo:    $Path"
  Write-Host "===============================================" -ForegroundColor DarkGray

  if (-not (Test-Path $Path)) {
    Write-Host "ERRO: Script não encontrado: $Path" -ForegroundColor Red
    return 2
  }

  $p = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$Path`""
  ) -Wait -PassThru -NoNewWindow

  return $p.ExitCode
}

# ============================
# PRÉ-CHECK (GATE HUMANO)
# ============================
function Run-PreCheck {
  if (-not (Test-Path $PreCheckScript)) {
    Write-Host "ERRO: Test-Environment.ps1 não encontrado em: $PreCheckScript" -ForegroundColor Red
    return 2
  }

  Write-Host ""
  Write-Host "==== PRÉ-VALIDAÇÃO DO AMBIENTE (Test-Environment) ====" -ForegroundColor Green
  Write-Host "Arquivo: $PreCheckScript"
  Write-Host ""

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreCheckScript
  return $LASTEXITCODE
}

function PreCheck-Gate {
  $code = Run-PreCheck

  while ($true) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor DarkGray
    Write-Host "AÇÕES (PRÉ-CHECK)" -ForegroundColor Green
    Write-Host "  [C] Continuar pipeline"
    Write-Host "  [R] Rodar Test-Environment novamente"
    Write-Host "  [O] Abrir pasta de logs (C:\Logs\setup)"
    Write-Host "  [N] Abrir log do Test-Environment no Notepad"
    Write-Host "  [Q] Sair"
    Write-Host "===============================================" -ForegroundColor DarkGray

    if ($code -eq 2) {
      Write-Host "STATUS: ERROR (corrija antes de continuar — ou prossiga por sua conta e risco)" -ForegroundColor Red
    } elseif ($code -eq 1) {
      Write-Host "STATUS: WARNING (pode prosseguir, mas pode falhar em pontos dependentes)" -ForegroundColor Yellow
    } else {
      Write-Host "STATUS: OK (ambiente pronto)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Escolha (C/R/O/N/Q): " -NoNewline
    $k = Read-KeyUpper
    Write-Host $k

    switch ($k) {
      "C" { return }  # libera pipeline
      "R" { $code = Run-PreCheck; continue }
      "O" { Open-LogsFolder; continue }
      "N" { Open-PreCheckLogNotepad; continue }
      "Q" { exit $code }
      default { Write-Host "Opção inválida. Use C, R, O, N ou Q." -ForegroundColor Yellow }
    }
  }
}

# ============================
# FINAL: MENU INTERATIVO
# ============================
function Final-Menu {
  while ($true) {
    Write-Host "===============================================" -ForegroundColor DarkGray
    Write-Host "AÇÕES DISPONÍVEIS" -ForegroundColor Green
    Write-Host "  [R] Rodar novamente: full-validation.ps1"
    Write-Host "  [L] Recarregar/exibir novamente o log"
    Write-Host "  [Q] Sair"
    Write-Host "===============================================" -ForegroundColor DarkGray
    Write-Host "Escolha (R/L/Q): " -NoNewline

    $k = Read-KeyUpper
    Write-Host $k

    switch ($k) {
      "R" {
        $valScript = Join-Path $ValDir "full-validation.ps1"
        Write-Host "Reexecutando validação final..." -ForegroundColor Cyan
        $code = Invoke-Step -Name "Validation (re-run)" -Path $valScript
        Write-Host "ExitCode: $code" -ForegroundColor Yellow
        Show-FullValidationLog
      }
      "L" { Show-FullValidationLog }
      "Q" {
        Write-Host "Encerrando por solicitação do usuário." -ForegroundColor Green
        break
      }
      default { Write-Host "Opção inválida. Use R, L ou Q." -ForegroundColor Yellow }
    }
  }
}

# ============================
# MAIN
# ============================
Write-Host ""
Write-Host "INICIANDO PIPELINE DE PROVISIONAMENTO DO WINDOWS" -ForegroundColor Green
Write-Host "RepoRoot: $RepoRoot"
Write-Host ""

# 0) Pré-check gate
PreCheck-Gate

# 1) Executa pipeline (drivers -> apps -> validation)
$finalExitCode = 0

foreach ($step in $Pipeline) {
  $code = Invoke-Step -Name $step.Name -Path $step.Path
  if ($code -ne 0) {
    Write-Host ""
    Write-Host "Falha na etapa '$($step.Name)' (ExitCode=$code). Pipeline interrompida." -ForegroundColor Red
    $finalExitCode = $code
    break
  }
}

# Exibe log final de validação (se existir)
Show-FullValidationLog

# Menu interativo final (não fecha sozinho)
Final-Menu

exit $finalExitCode
