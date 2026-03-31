<#
.SYNOPSIS
  bootstrap.ps1 — Bootstrap "clicar e funcionar" para baixar o repositório público do GitHub e executar a pipeline.

.DESCRIPTION
  - Repositório embutido (sem prompts): jesushenrr-jpg/provisioning-windows
  - Ref padrão: latest (último release)
  - Baixa ZIP do GitHub (tag/branch)
  - Extrai em C:\Provisioning\provisioning-windows\<Ref>\
  - Executa: run\run-provisioning.ps1

  Observação:
  - Se não houver Releases ainda e Ref=latest falhar, faz fallback automático para "main".

.PARAMETER Ref
  "latest" (padrão), "main" (branch) ou uma tag (ex: v1.0.0)

.PARAMETER InstallRoot
  Pasta local para extrair (padrão: C:\Provisioning)

.PARAMETER Force
  Rebaixa e re-extrai mesmo que já exista
#>

[CmdletBinding()]
param(
  [string]$Ref = "latest",
  [string]$InstallRoot = "C:\Provisioning",
  [switch]$Force
)

# =============================
# Config embutida (sem prompts)
# =============================
$RepoOwner  = "jesushenrr-jpg"
$RepoName   = "provisioning-windows"
$DefaultRef = "latest"

# ✅ Correção: uso correto do método .NET
if ([string]::IsNullOrWhiteSpace($Ref)) { $Ref = $DefaultRef }

# =============================
# Admin / Auto-elevate
# =============================
function Ensure-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevando bootstrap para Administrador..." -ForegroundColor Yellow
    $args = @(
      "-NoProfile","-ExecutionPolicy","Bypass",
      "-File", "`"$PSCommandPath`"",
      "-Ref", "`"$Ref`"",
      "-InstallRoot", "`"$InstallRoot`""
    )
    if ($Force) { $args += "-Force" }
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs | Out-Null
    exit 0
  }
}

# =============================
# Helpers
# =============================
function Ensure-Folder {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Set-Tls12 {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Get-LatestReleaseTag {
  param(
    [Parameter(Mandatory=$true)][string]$Owner,
    [Parameter(Mandatory=$true)][string]$Repo
  )
  $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  $r = Invoke-RestMethod -Uri $api -UseBasicParsing -ErrorAction Stop
  return $r.tag_name
}

function Resolve-DownloadUrl {
  param(
    [Parameter(Mandatory=$true)][string]$Owner,
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][string]$RefValue
  )

  $finalRef = $RefValue

  if ($RefValue -ieq "latest") {
    try {
      $finalRef = Get-LatestReleaseTag -Owner $Owner -Repo $Repo
      Write-Host "Ref=latest => tag '$finalRef'" -ForegroundColor Cyan
    } catch {
      Write-Host "Não foi possível resolver latest (sem releases?). Usando 'main'." -ForegroundColor Yellow
      $finalRef = "main"
    }
  }

  $looksLikeTag = ($finalRef -match '^v\d' -or $finalRef -match '^\d' -or $finalRef -match '\d+\.\d+')
  $zipUrl = if ($looksLikeTag) {
    "https://github.com/$Owner/$Repo/archive/refs/tags/$finalRef.zip"
  } else {
    "https://github.com/$Owner/$Repo/archive/refs/heads/$finalRef.zip"
  }

  return [pscustomobject]@{ FinalRef = $finalRef; ZipUrl = $zipUrl }
}

# =============================
# MAIN
# =============================
Ensure-Administrator
Set-Tls12
Ensure-Folder -Path $InstallRoot

Write-Host ""
Write-Host "=== BOOTSTRAP (plug-and-play) ===" -ForegroundColor Green
Write-Host "Repo: $RepoOwner/$RepoName"
Write-Host "Ref : $Ref"
Write-Host "Dest: $InstallRoot"
Write-Host ""

$resolved = Resolve-DownloadUrl -Owner $RepoOwner -Repo $RepoName -RefValue $Ref
$finalRef = $resolved.FinalRef
$zipUrl   = $resolved.ZipUrl

$targetDir = Join-Path $InstallRoot (Join-Path $RepoName $finalRef)
if ($Force -and (Test-Path $targetDir)) {
  Write-Host "Force: removendo $targetDir" -ForegroundColor Yellow
  Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
}
Ensure-Folder -Path $targetDir

$zipPath = Join-Path $env:TEMP ("{0}_{1}.zip" -f $RepoName, $finalRef)

Write-Host "Baixando: $zipUrl" -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

Write-Host "Extraindo para: $targetDir" -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force

$extractedFolder = Get-ChildItem -Path $targetDir -Directory | Select-Object -First 1
if (-not $extractedFolder) {
  throw "Falha ao localizar pasta extraída em $targetDir"
}

$runPath = Join-Path $extractedFolder.FullName "run\run-provisioning.ps1"
if (-not (Test-Path $runPath)) {
  throw "Orquestrador não encontrado em: $runPath (verifique se existe run/run-provisioning.ps1 no repo)"
}

Write-Host ""
Write-Host "Iniciando pipeline: $runPath" -ForegroundColor Green
Write-Host ""

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runPath
exit $LASTEXITCODE
``
