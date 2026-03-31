<#
.SYNOPSIS
  drivers-report.ps1 — Etapa 3: relatório consolidado (WU + análise) incluindo HWIDs e INF dos dispositivos em erro.

.DESCRIPTION
  - Lê WU JSON (drivers instalados/falhas)
  - Lê Analysis JSON (OK/WARN/ERROR)
  - Para dispositivos em ERROR:
      - Busca Hardware IDs (DEVPKEY_Device_HardwareIds)
      - Confirma INF instalado (se disponível)
  - Gera relatório em TXT para ação manual

.OUTPUT
  - C:\Logs\setup\drivers-analysis-report.txt
  - Log: C:\Logs\setup\drivers-report.log
#>

[CmdletBinding()]
param(
  [string]$WuResultJson = "C:\Logs\setup\drivers-wu-results.json",
  [string]$AnalysisJson = "C:\Logs\setup\drivers-analysis-results.json",
  [string]$ReportPath = "C:\Logs\setup\drivers-analysis-report.txt",
  [string]$LogPath = "C:\Logs\setup\drivers-report.log"
)

function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevando drivers-report.ps1 para Administrador..." -ForegroundColor Yellow
    $args = @(
      "-NoProfile","-ExecutionPolicy","Bypass",
      "-File", "`"$PSCommandPath`"",
      "-WuResultJson", "`"$WuResultJson`"",
      "-AnalysisJson", "`"$AnalysisJson`"",
      "-ReportPath", "`"$ReportPath`"",
      "-LogPath", "`"$LogPath`""
    )
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

function Write-ReportLine { param([string]$Text="") Add-Content -Path $ReportPath -Value $Text -Encoding UTF8 }

function Read-JsonOrNull {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  try { return (Get-Content $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-HardwareIds {
  param([Parameter(Mandatory)][string]$InstanceId)
  $ids = @()
  try {
    $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
    if ($p -and $p.Data) { $ids = @($p.Data) }
  } catch {
    # fallback WMI Win32_PnPEntity
    try {
      $flt = "PNPDeviceID = '{0}'" -f $InstanceId.Replace('\','\\')
      $w = Get-CimInstance -ClassName Win32_PnPEntity -Filter $flt -ErrorAction Stop
      if ($w.HardwareID) { $ids = @($w.HardwareID) }
    } catch {}
  }
  return $ids
}

function Build-DriverMap {
  $map = @{}
  try {
    $signed = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
    foreach ($s in $signed) {
      if ($s.DeviceID -and -not $map.ContainsKey($s.DeviceID)) { $map[$s.DeviceID] = $s }
    }
  } catch {
    Write-Log "Aviso: Win32_PnPSignedDriver indisponível: $($_.Exception.Message)" "WARN"
  }
  return $map
}

function Generate-DriversReport {
  Write-Host "Gerando relatório completo de drivers (com HWIDs e INF)..." -ForegroundColor Cyan

  $wu = Read-JsonOrNull $WuResultJson
  $analysis = Read-JsonOrNull $AnalysisJson

  if (-not $analysis) {
    Write-Log "Analysis JSON ausente/ inválido: $AnalysisJson" "ERROR"
    return 2
  }

  $driverMap = Build-DriverMap

  # preparar report
  Ensure-Folder -Path (Split-Path $ReportPath -Parent)
  try { if (Test-Path $ReportPath) { Remove-Item $ReportPath -Force -ErrorAction SilentlyContinue } } catch {}
  New-Item -ItemType File -Path $ReportPath -Force | Out-Null

  $now = Get-Date
  Write-ReportLine "DRIVERS REPORT (WU + ANALYSIS + HWIDs/INF)"
  Write-ReportLine "Gerado em: $now"
  Write-ReportLine "WU JSON: $WuResultJson"
  Write-ReportLine "Analysis JSON: $AnalysisJson"
  Write-ReportLine "============================================================="
  Write-ReportLine ""

  # 1) Windows Update
  Write-ReportLine "1) WINDOWS UPDATE (DRIVERS)"
  if (-not $wu) {
    Write-ReportLine "   - Sem dados do Windows Update (JSON ausente ou inválido)."
  } else {
    Write-ReportLine ("   - Início:  {0}" -f $wu.StartedAt)
    Write-ReportLine ("   - Fim:     {0}" -f $wu.FinishedAt)
    Write-ReportLine ("   - Reboot?: {0}" -f $wu.RebootRequired)
    Write-ReportLine ("   - Encontrados: {0}" -f ($wu.UpdatesFound.Count))
    Write-ReportLine ("   - Instalados:  {0}" -f ($wu.UpdatesInstalled.Count))
    Write-ReportLine ("   - Falharam:    {0}" -f ($wu.UpdatesFailed.Count))
    if ($wu.Error) { Write-ReportLine ("   - Erro geral:  {0}" -f $wu.Error) }

    Write-ReportLine ""
    Write-ReportLine "   1.1 Instalados com sucesso:"
    if ($wu.UpdatesInstalled.Count -eq 0) { Write-ReportLine "     (nenhum)" }
    else {
      foreach ($u in $wu.UpdatesInstalled) {
        Write-ReportLine ("     - {0} | ResultCode={1} | HResult={2} | Reboot={3}" -f $u.Title, $u.ResultCode, $u.HResult, $u.RebootRequired)
      }
    }

    Write-ReportLine ""
    Write-ReportLine "   1.2 Falhas durante instalação:"
    if ($wu.UpdatesFailed.Count -eq 0) { Write-ReportLine "     (nenhuma)" }
    else {
      foreach ($u in $wu.UpdatesFailed) {
        Write-ReportLine ("     - {0} | ResultCode={1} | HResult={2} | Reboot={3}" -f $u.Title, $u.ResultCode, $u.HResult, $u.RebootRequired)
      }
    }
  }

  Write-ReportLine ""
  Write-ReportLine "============================================================="
  Write-ReportLine ""

  # 2) Análise local
  Write-ReportLine "2) ANÁLISE LOCAL (Get-PnpDevice)"
  Write-ReportLine ("   - Resumo: {0}" -f $analysis.Summary)
  Write-ReportLine ("   - Gerado em: {0}" -f $analysis.GeneratedAt)
  Write-ReportLine ""

  # 2.1 Erros: incluir HWIDs e INF
  Write-ReportLine "   2.1 Dispositivos com ERRO (inclui HWIDs + INF quando disponível):"
  if ($analysis.Error.Count -eq 0) {
    Write-ReportLine "     (nenhum)"
  } else {
    foreach ($d in $analysis.Error) {
      $inst = $d.InstanceId
      $inf = $d.InfName

      # se analysis não trouxe INF, tenta no map
      if ((-not $inf) -and $inst -and $driverMap.ContainsKey($inst)) {
        $inf = $driverMap[$inst].InfName
      }

      $hwids = @()
      if ($inst) { $hwids = Get-HardwareIds -InstanceId $inst }

      Write-ReportLine ("     - [{0}] {1}" -f $d.Class, $d.Name)
      Write-ReportLine ("       Status={0} | ProblemCode={1}" -f $d.Status, $d.ProblemCode)
      Write-ReportLine ("       Provider={0} | Version={1}" -f ($d.DriverProvider ?? "N/A"), ($d.DriverVersion ?? "N/A"))
      Write-ReportLine ("       INF={0}" -f ($inf ?? "N/A"))

      if ($hwids.Count -gt 0) {
        Write-ReportLine "       HardwareIDs:"
        foreach ($h in $hwids) { Write-ReportLine ("         - {0}" -f $h) }
      } else {
        Write-ReportLine "       HardwareIDs: N/A"
      }

      Write-ReportLine ""
    }
  }

  # 2.2 Warnings
  Write-ReportLine "   2.2 Dispositivos em WARNING (possível driver genérico):"
  if ($analysis.Warning.Count -eq 0) {
    Write-ReportLine "     (nenhum)"
  } else {
    foreach ($d in $analysis.Warning) {
      Write-ReportLine ("     - [{0}] {1} | Provider={2} | Version={3} | INF={4}" -f
        $d.Class, $d.Name, ($d.DriverProvider ?? "N/A"), ($d.DriverVersion ?? "N/A"), ($d.InfName ?? "N/A"))
    }
  }

  Write-ReportLine ""
  Write-ReportLine "============================================================="
  Write-ReportLine "AÇÃO MANUAL SUGERIDA"
  Write-ReportLine " - Priorize corrigir itens em '2.1 Dispositivos com ERRO'."
  Write-ReportLine " - Use os Hardware IDs acima para buscar no Microsoft Update Catalog ou site do OEM."
  Write-ReportLine " - Se INF existir mas o dispositivo está em erro, pode haver conflito/corrupção; tente reinstalar o driver."
  Write-ReportLine ""

  Write-Log "Relatório gerado: $ReportPath" "INFO"
  return 0
}

# MAIN
Ensure-Administrator
Ensure-Folder -Path (Split-Path $LogPath -Parent)
try { if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue } } catch {}
New-Item -ItemType File -Path $LogPath -Force | Out-Null

Write-Log "========== INÍCIO drivers-report.ps1 ==========" "INFO"
Write-Log "WU JSON: $WuResultJson" "INFO"
Write-Log "Analysis JSON: $AnalysisJson" "INFO"

$code = Generate-DriversReport

Write-Log "========== FIM drivers-report.ps1 ==========" "INFO"
Write-Host ""
Write-Host "Relatório pronto: $ReportPath" -ForegroundColor Green
Write-Host "Log:            $LogPath" -ForegroundColor Green

exit $code
