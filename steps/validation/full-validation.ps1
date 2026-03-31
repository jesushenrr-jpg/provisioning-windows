<#
.SYNOPSIS
  full-validation.ps1 — Orquestrador da validação (drivers, apps, internet)

.DESCRIPTION
  Executa as validações modulares restantes e consolida o resultado final.
#>

$baseDir = $PSScriptRoot
$logsDir = "C:\Logs\setup"

$logPath    = Join-Path $logsDir "07-full-validation.log"
$reportPath = Join-Path $logsDir "full-validation-report.txt"

# Etapas ativas de validação (FEATURES REMOVIDO)
$steps = @(
  "validation-01-drivers.ps1",
  "validation-03-apps.ps1",
  "validation-04-internet.ps1"
)

# -----------------------------
# Preparação
# -----------------------------
if (-not (Test-Path $logsDir)) {
  New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

if (Test-Path $logPath) {
  Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}

function Write-Log {
  param([string]$Message)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] $Message"
  Add-Content -Path $logPath -Value $line
  Write-Host $line
}

Write-Log "========== INÍCIO FULL VALIDATION =========="

# -----------------------------
# Execução das etapas
# -----------------------------
$results = @()

foreach ($step in $steps) {
  $path = Join-Path $baseDir $step

  if (-not (Test-Path $path)) {
    Write-Log "ERRO: Script não encontrado: $path"
    continue
  }

  Write-Log "Executando validação: $step"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path
}

# -----------------------------
# Consolidação
# -----------------------------
$jsonFiles = Get-ChildItem -Path $logsDir -Filter "validation-*.json" -ErrorAction SilentlyContinue

foreach ($file in $jsonFiles) {
  try {
    $results += Get-Content $file.FullName -Raw | ConvertFrom-Json
  } catch {
    Write-Log "Falha ao ler JSON: $($file.FullName)"
  }
}

$finalStatus =
  if ($results.Status -contains "ERROR") { "ERROR" }
  elseif ($results.Status -contains "WARNING") { "WARNING" }
  else { "SUCCESS" }

# -----------------------------
# Relatório final
# -----------------------------
"STATUS FINAL: $finalStatus" | Set-Content $reportPath
Add-Content $reportPath "--------------------------------------------------"

foreach ($r in $results) {
  Add-Content $reportPath "[$($r.Stage)] $($r.Status) — $($r.Summary)"
}

Add-Content $reportPath ""
Add-Content $reportPath "Relatório gerado em: $(Get-Date)"

Write-Log "STATUS FINAL: $finalStatus"
Write-Log "Relatório: $reportPath"
Write-Log "========== FIM FULL VALIDATION =========="

# Exit code padrão
if ($finalStatus -eq "SUCCESS") { exit 0 }
elseif ($finalStatus -eq "WARNING") { exit 1 }
else { exit 2 }
