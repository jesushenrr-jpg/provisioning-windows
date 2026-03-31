<#
.SYNOPSIS
  drivers-analysis.ps1 — Etapa 2: análise local de drivers (somente).

.DESCRIPTION
  - Inventaria dispositivos com Get-PnpDevice
  - Usa Win32_PnPSignedDriver para provider/version/inf (quando disponível)
  - Classifica OK / WARNING / ERROR
  - Gera JSON com o resultado para ser consumido pelo drivers-report.ps1

.ARTEFATO
  - OutAnalysisJson (default: C:\Logs\setup\drivers-analysis-results.json)
#>

[CmdletBinding()]
param(
  [string]$WuResultJson = "C:\Logs\setup\drivers-wu-results.json",
  [string]$OutAnalysisJson = "C:\Logs\setup\drivers-analysis-results.json",
  [string]$LogPath = "C:\Logs\setup\drivers-analysis.log"
)

function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevando drivers-analysis.ps1 para Administrador..." -ForegroundColor Yellow
    $args = @(
      "-NoProfile","-ExecutionPolicy","Bypass",
      "-File", "`"$PSCommandPath`"",
      "-WuResultJson", "`"$WuResultJson`"",
      "-OutAnalysisJson", "`"$OutAnalysisJson`"",
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

function Get-DriverMap {
  $map = @{}
  try {
    $signed = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
    foreach ($s in $signed) {
      if ($s.DeviceID -and -not $map.ContainsKey($s.DeviceID)) { $map[$s.DeviceID] = $s }
    }
  } catch {
    Write-Log "Win32_PnPSignedDriver indisponível: $($_.Exception.Message)" "WARN"
  }
  return $map
}

function Analyze-Devices {
  Write-Host "Analisando dispositivos e drivers atuais..." -ForegroundColor Cyan
  $driverMap = Get-DriverMap

  $devices = @()
  try { $devices = Get-PnpDevice -PresentOnly -ErrorAction Stop } catch {
    Write-Log "Falha ao executar Get-PnpDevice: $($_.Exception.Message)" "ERROR"
    return [pscustomobject]@{ Ok=@(); Warning=@(); Error=@(); Summary="Falha no Get-PnpDevice" }
  }

  $ok = New-Object System.Collections.Generic.List[object]
  $warn = New-Object System.Collections.Generic.List[object]
  $err = New-Object System.Collections.Generic.List[object]

  foreach ($d in $devices) {
    $inst = $d.InstanceId
    $name = $d.FriendlyName
    $cls  = $d.Class
    $status = $d.Status
    $prob = $d.ProblemCode

    $provider = $null
    $ver = $null
    $inf = $null
    if ($inst -and $driverMap.ContainsKey($inst)) {
      $provider = $driverMap[$inst].DriverProviderName
      $ver      = $driverMap[$inst].DriverVersion
      $inf      = $driverMap[$inst].InfName
    }

    $isError = $false
    if ($status -ne "OK") { $isError = $true }
    if ($null -ne $prob -and $prob -ne 0) { $isError = $true }
    if ($name -match "Unknown|Desconhecido") { $isError = $true }
    if ($cls  -match "Unknown|Desconhecido") { $isError = $true }

    $isWarn = $false
    if (-not $isError) {
      if ($provider -match "Microsoft") {
        $sensitive = @("Display","Net","MEDIA","Bluetooth","System","HDC","SCSIAdapter")
        if ($sensitive -contains $cls) {
          $exceptions = @("Microsoft Basic Display Adapter","Generic USB Hub","USB Root Hub","Microsoft ACPI")
          $isException = $false
          foreach ($ex in $exceptions) { if ($name -like "*$ex*") { $isException = $true; break } }
          if (-not $isException) { $isWarn = $true }
        }
      }
    }

    $obj = [pscustomobject]@{
      Name           = $name
      Class          = $cls
      Status         = $status
      ProblemCode    = $prob
      InstanceId     = $inst
      DriverProvider = $provider
      DriverVersion  = $ver
      InfName        = $inf
    }

    if ($isError)      { $err.Add($obj)  | Out-Null }
    elseif ($isWarn)   { $warn.Add($obj) | Out-Null }
    else               { $ok.Add($obj)   | Out-Null }
  }

  $summary = "OK=$($ok.Count) | WARNING=$($warn.Count) | ERROR=$($err.Count) | Total=$($devices.Count)"
  Write-Log "Análise concluída: $summary" "INFO"

  return [pscustomobject]@{
    Ok      = $ok
    Warning = $warn
    Error   = $err
    Summary = $summary
    GeneratedAt = (Get-Date)
  }
}

# MAIN
Ensure-Administrator
Ensure-Folder -Path (Split-Path $LogPath -Parent)
try { if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue } } catch {}
New-Item -ItemType File -Path $LogPath -Force | Out-Null

Write-Log "========== INÍCIO drivers-analysis.ps1 ==========" "INFO"

$analysis = Analyze-Devices

try {
  Ensure-Folder -Path (Split-Path $OutAnalysisJson -Parent)
  $analysis | ConvertTo-Json -Depth 8 | Set-Content -Path $OutAnalysisJson -Encoding UTF8 -Force
  Write-Log "Artefato de análise gerado: $OutAnalysisJson" "INFO"
} catch {
  Write-Log "Falha ao salvar JSON de análise: $($_.Exception.Message)" "ERROR"
}

Write-Log "========== FIM drivers-analysis.ps1 ==========" "INFO"
exit 0
``
