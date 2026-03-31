[CmdletBinding()]
param(
  [string]$ConfigJson = "C:\Logs\setup\config.json",
  [string]$OutJson = "C:\Logs\setup\validation-apps.json"
)

$errors = @()

$cfg = Get-Content $ConfigJson -Raw | ConvertFrom-Json

foreach ($app in $cfg.apps) {
  $found = winget list --id $app --exact 2>$null
  if (-not $found) {
    $errors += "App ausente: $app"
  }
}

$status = if ($errors) { "ERROR" } else { "OK" }

[pscustomobject]@{
  Stage       = "Applications"
  Status      = $status
  Summary     = "Apps ausentes: $($errors.Count)"
  Problems    = $errors
  GeneratedAt = Get-Date
} | ConvertTo-Json -Depth 4 | Set-Content $OutJson

exit 0
