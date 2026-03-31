<#
.SYNOPSIS
  drivers.ps1 — Etapa 1: Atualização de drivers via Windows Update (WUA) e chamada automática das etapas 2 e 3.

.DESCRIPTION
  - Busca updates do tipo Driver via Windows Update Agent (COM)
  - Baixa e instala (sem reiniciar)
  - Registra resultados em JSON (artefato)
  - Chama drivers-analysis.ps1 (Etapa 2) e drivers-report.ps1 (Etapa 3)

.LOGS/ARTEFATOS
  - C:\Logs\setup\drivers-update.log
  - C:\Logs\setup\drivers-wu-results.json
  - C:\Logs\setup\drivers-analysis-results.json
  - C:\Logs\setup\drivers-analysis-report.txt
#>

[CmdletBinding()]
param(
  [string]$LogPath = "C:\Logs\setup\drivers-update.log",
  [string]$ResultJsonPath = "C:\Logs\setup\drivers-wu-results.json",
  [string]$AnalysisJsonPath = "C:\Logs\setup\drivers-analysis-results.json",
  [string]$ReportPath = "C:\Logs\setup\drivers-analysis-report.txt",
  [switch]$SkipAnalysis,
  [switch]$SkipReport
)

function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevando drivers.ps1 para Administrador..." -ForegroundColor Yellow
    $args = @(
      "-NoProfile","-ExecutionPolicy","Bypass",
      "-File", "`"$PSCommandPath`"",
      "-LogPath", "`"$LogPath`"",
      "-ResultJsonPath", "`"$ResultJsonPath`"",
      "-AnalysisJsonPath", "`"$AnalysisJsonPath`"",
      "-ReportPath", "`"$ReportPath`""
    )
    if ($SkipAnalysis) { $args += "-SkipAnalysis" }
    if ($SkipReport)   { $args += "-SkipReport" }
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs | Out-Null
    exit 0
  }
}

function Ensure-Folder { param([string]$Path) if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function Write-Log {
  param([string]$Message,[ValidateSet("INFO","WARN","ERROR","DEBUG")][string]$Level="INFO")
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
  $line = "[$ts][$Level] $Message"
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  switch ($Level) {
    "ERROR" { Write-Host $line -ForegroundColor Red }
    "WARN"  { Write-Host $line -ForegroundColor Yellow }
    "DEBUG" { Write-Host $line -ForegroundColor DarkGray }
    default { Write-Host $line }
  }
}

function Invoke-WindowsUpdateDrivers {
  Write-Host "Executando Windows Update (somente drivers)..." -ForegroundColor Cyan
  Write-Log "Iniciando Windows Update (Type='Driver')..." "INFO"

  $results = [ordered]@{
    StartedAt        = (Get-Date)
    UpdatesFound     = @()
    UpdatesAttempted = @()
    UpdatesInstalled = @()
    UpdatesFailed    = @()
    RebootRequired   = $false
    FinishedAt       = $null
    Error            = $null
  }

  try {
    $session  = New-Object -ComObject "Microsoft.Update.Session"
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search("IsInstalled=0 and Type='Driver'")

    $count = 0
    if ($searchResult -and $searchResult.Updates) { $count = $searchResult.Updates.Count }
    Write-Log ("Drivers encontrados via WU: {0}" -f $count) "INFO"

    if ($count -eq 0) {
      $results.FinishedAt = Get-Date
      return [pscustomobject]$results
    }

    for ($i=0; $i -lt $count; $i++) {
      $u = $searchResult.Updates.Item($i)
      $results.UpdatesFound += [pscustomobject]@{
        Title        = $u.Title
        IsDownloaded = $u.IsDownloaded
        Categories   = (($u.Categories | ForEach-Object { $_.Name }) -join "; ")
      }
    }

    $coll = New-Object -ComObject "Microsoft.Update.UpdateColl"
    for ($i=0; $i -lt $count; $i++) {
      $u = $searchResult.Updates.Item($i)
      if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }
      $null = $coll.Add($u)
      $results.UpdatesAttempted += [pscustomobject]@{
        Title      = $u.Title
        Categories = (($u.Categories | ForEach-Object { $_.Name }) -join "; ")
      }
    }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $coll
    Write-Log "Baixando updates de driver..." "INFO"
    $null = $downloader.Download()

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $coll
    $installer.ForceQuiet = $true
    $installer.AllowSourcePrompts = $false

    Write-Log "Instalando updates de driver..." "INFO"
    $ires = $installer.Install()

    $results.RebootRequired = [bool]$ires.RebootRequired
    Write-Log ("Install ResultCode={0} RebootRequired={1}" -f $ires.ResultCode, $ires.RebootRequired) "INFO"

    for ($i=0; $i -lt $coll.Count; $i++) {
      $u  = $coll.Item($i)
      $ur = $ires.GetUpdateResult($i)

      $item = [pscustomobject]@{
        Title          = $u.Title
        ResultCode     = [int]$ur.ResultCode
        HResult        = ("0x{0:X8}" -f ($ur.HResult -band 0xFFFFFFFF))
        RebootRequired = [bool]$ur.RebootRequired
      }

      if ($ur.ResultCode -eq 2 -or $ur.ResultCode -eq 3) {
        $results.UpdatesInstalled += $item
      } else {
        $results.UpdatesFailed += $item
      }
    }

    $results.FinishedAt = Get-Date
    return [pscustomobject]$results
  }
  catch {
    $results.Error = $_.Exception.Message
    $results.FinishedAt = Get-Date
    Write-Log "Falha no Windows Update Drivers: $($_.Exception.Message)" "ERROR"
    return [pscustomobject]$results
  }
}

# MAIN
Ensure-Administrator
Ensure-Folder -Path (Split-Path $LogPath -Parent)

try { if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue } } catch {}
New-Item -ItemType File -Path $LogPath -Force | Out-Null

Write-Log "========== INÍCIO drivers.ps1 (WU Drivers) ==========" "INFO"

$wu = Invoke-WindowsUpdateDrivers

try {
  Ensure-Folder -Path (Split-Path $ResultJsonPath -Parent)
  $wu | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultJsonPath -Encoding UTF8 -Force
  Write-Log "Artefato WU JSON gerado: $ResultJsonPath" "INFO"
} catch {
  Write-Log "Falha ao salvar JSON WU: $($_.Exception.Message)" "ERROR"
}

Write-Log "========== FIM drivers.ps1 ==========" "INFO"

# Etapa 2: análise
if (-not $SkipAnalysis) {
  $analysisPath = Join-Path $PSScriptRoot "drivers-analysis.ps1"
  if (Test-Path $analysisPath) {
    Write-Log "Chamando análise: $analysisPath" "INFO"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analysisPath -WuResultJson $ResultJsonPath -OutAnalysisJson $AnalysisJsonPath
    Write-Log ("drivers-analysis ExitCode={0}" -f $LASTEXITCODE) "INFO"
  } else {
    Write-Log "drivers-analysis.ps1 não encontrado em $PSScriptRoot" "WARN"
  }
}

# Etapa 3: relatório (HWIDs + INF)
if (-not $SkipReport) {
  $reporterPath = Join-Path $PSScriptRoot "drivers-report.ps1"
  if (Test-Path $reporterPath) {
    Write-Log "Chamando relatório: $reporterPath" "INFO"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $reporterPath -WuResultJson $ResultJsonPath -AnalysisJson $AnalysisJsonPath -ReportPath $ReportPath
    exit $LASTEXITCODE
  } else {
    Write-Log "drivers-report.ps1 não encontrado em $PSScriptRoot" "WARN"
  }
}

exit 0
