<#
.SYNOPSIS
  Instala aplicativos essenciais pós-instalação (Windows 10/11) com WinGet
  e gera automaticamente config.json com a lista de apps selecionados.

.DESCRIPTION
  - Usa winget com instalação silenciosa e aceite automático de termos
  - Idempotente: verifica se já está instalado antes de instalar
  - Robusto: continua mesmo se algum app falhar
  - Logging: C:\Logs\setup\apps-install.log
  - Gera config.json: C:\Logs\setup\config.json (por padrão)
  - Exibe progresso

.REQUIREMENTS
  - Executar como Administrador
  - WinGet disponível (App Installer)
#>

[CmdletBinding()]
param(
  [string]$LogPath = "C:\Logs\setup\apps-install.log",
  [string]$ConfigOutPath = "C:\Logs\setup\config.json"
)

# -----------------------------
# Config / Logging
# -----------------------------
function Ensure-Folder {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

Ensure-Folder -Path (Split-Path $LogPath -Parent)
Ensure-Folder -Path (Split-Path $ConfigOutPath -Parent)

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][string]$Message,
    [ValidateSet("INFO","WARN","ERROR","DEBUG")][string]$Level = "INFO"
  )
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

# -----------------------------
# Admin Check
# -----------------------------
function Assert-Administrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Este script precisa ser executado como Administrador." "ERROR"
    throw "Not running as Administrator"
  }
}

# -----------------------------
# WinGet Check
# -----------------------------
function Assert-WinGet {
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $wg) {
    Write-Log "winget não encontrado. Instale/atualize o App Installer (Microsoft Store) e tente novamente." "ERROR"
    throw "winget missing"
  }
  Write-Log ("winget encontrado: {0}" -f $wg.Source) "INFO"
}

# -----------------------------
# Helpers (Idempotência)
# -----------------------------
function Test-AppInstalled {
  param(
    [Parameter(Mandatory=$true)][string]$Id,
    [Parameter(Mandatory=$true)][string]$Name,
    [ValidateSet("winget","msstore")][string]$Source = "winget"
  )

  # 1) tenta por ID exato
  try {
    $out = & winget list --id $Id --exact --source $Source 2>$null
    $txt = ($out | Out-String)
    if ($txt -match [regex]::Escape($Id)) { return $true }
  } catch {}

  # 2) fallback por nome
  try {
    $out2 = & winget list --name $Name --source $Source 2>$null
    $txt2 = ($out2 | Out-String)
    if ($txt2 -match [regex]::Escape($Name)) { return $true }
  } catch {}

  return $false
}

# -----------------------------
# Função principal: Install-App
# -----------------------------
function Install-App {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Id,
    [ValidateSet("winget","msstore")][string]$Source = "winget",
    [string]$OverrideArgs = ""
  )

  Write-Log "---- App: $Name | Id=$Id | Source=$Source ----" "INFO"

  if (Test-AppInstalled -Id $Id -Name $Name -Source $Source) {
    Write-Log "Já instalado. Pulando: $Name ($Id)" "INFO"
    return
  }

  $args = @(
    "install",
    "--id", $Id,
    "--exact",
    "--source", $Source,
    "--silent",
    "--accept-package-agreements",
    "--accept-source-agreements",
    "--disable-interactivity"
  )

  if ($OverrideArgs -and $OverrideArgs.Trim().Length -gt 0) {
    $args += @("--override", $OverrideArgs)
  }

  try {
    Write-Log ("Instalando via winget: {0}" -f ($args -join " ")) "DEBUG"
    $p = Start-Process -FilePath "winget" -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) {
      Write-Log "Instalação concluída: $Name ($Id)" "INFO"
    } else {
      Write-Log "Falha na instalação: $Name ($Id) ExitCode=$($p.ExitCode)" "WARN"
    }
  } catch {
    Write-Log "Erro ao instalar $Name ($Id): $($_.Exception.Message)" "ERROR"
  }
}

# -----------------------------
# Geração automática do config.json
# -----------------------------
function Write-AppsConfig {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][array]$Apps,
    [Parameter(Mandatory=$true)][string]$OutPath
  )

  try {
    # mantém somente IDs "principais" da lista aprovada (sem duplicar)
    $ids = $Apps |
      Where-Object { $_.Id -and $_.Id.Trim().Length -gt 0 } |
      ForEach-Object { $_.Id.Trim() } |
      Select-Object -Unique

    $obj = [pscustomobject]@{ apps = $ids }

    $json = $obj | ConvertTo-Json -Depth 5
    Set-Content -Path $OutPath -Value $json -Encoding UTF8 -Force

    Write-Log "config.json gerado/atualizado em: $OutPath" "INFO"
    Write-Log ("Apps gravados no config.json: {0}" -f $ids.Count) "INFO"
  } catch {
    Write-Log "Falha ao gerar config.json: $($_.Exception.Message)" "ERROR"
  }
}

# -----------------------------
# Lista aprovada de Apps (como sugerida)
# -----------------------------
$Apps = @(
  # Produtividade
  @{ Category="Produtividade"; Name="Microsoft 365 Apps for enterprise"; Id="Microsoft.Office"; Source="winget" },
  @{ Category="Produtividade"; Name="LibreOffice"; Id="TheDocumentFoundation.LibreOffice"; Source="winget" },
  @{ Category="Produtividade"; Name="Adobe Acrobat Reader DC (64-bit)"; Id="Adobe.Acrobat.Reader.64-bit"; Source="winget" },
  @{ Category="Produtividade"; Name="SumatraPDF"; Id="SumatraPDF.SumatraPDF"; Source="winget" },

  # Navegadores
  @{ Category="Navegadores"; Name="Google Chrome"; Id="Google.Chrome"; Source="winget" },
  @{ Category="Navegadores"; Name="Mozilla Firefox"; Id="Mozilla.Firefox"; Source="winget" },

  # Desenvolvimento (aprovado)
  @{ Category="Desenvolvimento"; Name="Visual Studio Code"; Id="Microsoft.VisualStudioCode"; Source="winget" },
  @{ Category="Desenvolvimento"; Name="Git"; Id="Git.Git"; Source="winget" },
  @{ Category="Desenvolvimento"; Name="Node.js LTS"; Id="OpenJS.NodeJS.LTS"; Source="winget" },
  @{ Category="Desenvolvimento"; Name="Python 3.12"; Id="Python.Python.3.12"; Source="winget" },

  # Utilitários
  @{ Category="Utilitários"; Name="7-Zip"; Id="7zip.7zip"; Source="winget" },
  @{ Category="Utilitários"; Name="WinRAR"; Id="RARLab.WinRAR"; Source="winget" },
  @{ Category="Utilitários"; Name="VLC media player"; Id="VideoLAN.VLC"; Source="winget" },
  @{ Category="Utilitários"; Name="Everything"; Id="voidtools.Everything"; Source="winget" },
  @{ Category="Utilitários"; Name="Notepad++"; Id="Notepad++.Notepad++"; Source="winget" },

  # Comunicação
  @{ Category="Comunicação"; Name="WhatsApp"; Id="WhatsApp.WhatsApp"; Source="winget" },
  @{ Category="Comunicação"; Name="Discord"; Id="Discord.Discord"; Source="winget" },
  @{ Category="Comunicação"; Name="Zoom Workplace"; Id="Zoom.Zoom"; Source="winget" },
  @{ Category="Comunicação"; Name="Microsoft Teams"; Id="Microsoft.Teams"; Source="winget" },

  # Sistema
  @{ Category="Sistema"; Name="Microsoft PowerToys"; Id="Microsoft.PowerToys"; Source="winget" },
  @{ Category="Sistema"; Name="HWiNFO"; Id="REALiX.HWiNFO"; Source="winget" }
)

# WhatsApp Store fallback (não vai para o config.json — somente para instalação)
$WhatsAppStoreId = "9NKSQGP7F2NH"

# -----------------------------
# Execução Principal
# -----------------------------
try {
  Assert-Administrator
  Assert-WinGet
} catch {
  Write-Log "Abortando: pré-requisitos não atendidos. $($_.Exception.Message)" "ERROR"
  exit 1
}

Write-Log "========== INÍCIO: Instalação de Apps ==========" "INFO"
Write-Log ("Total de apps na lista: {0}" -f $Apps.Count) "INFO"

# Gera/atualiza config.json ANTES (fonte da verdade: seleção de apps)
Write-AppsConfig -Apps $Apps -OutPath $ConfigOutPath

$idx = 0
$total = $Apps.Count

foreach ($app in $Apps) {
  $idx++
  $pct = ($idx / [double]$total * 100)
  $status = "{0}/{1} — {2} ({3})" -f $idx, $total, $app.Name, $app.Category
  Write-Progress -Activity "Instalando aplicativos essenciais..." -Status $status -PercentComplete $pct

  Install-App -Name $app.Name -Id $app.Id -Source $app.Source

  # Fallback específico WhatsApp (se o "winget" não confirmar)
  if ($app.Id -eq "WhatsApp.WhatsApp") {
    if (-not (Test-AppInstalled -Id $app.Id -Name $app.Name -Source "winget")) {
      Write-Log "WhatsApp: tentando fallback via Microsoft Store (msstore)..." "WARN"
      Install-App -Name "WhatsApp (Microsoft Store)" -Id $WhatsAppStoreId -Source "msstore"
    }
  }
}

Write-Progress -Activity "Instalando aplicativos essenciais..." -Completed
Write-Log "========== FIM: Instalação de Apps ==========" "INFO"
Write-Log "Log salvo em: $LogPath" "INFO"
Write-Log "Config salvo em: $ConfigOutPath" "INFO"

exit 0
