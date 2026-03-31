[CmdletBinding()]
param(
  [string]$OutJson = "C:\Logs\setup\validation-drivers.json"
)

$errors = @()
$warnings = @()

$devices = Get-PnpDevice -PresentOnly

foreach ($d in $devices) {
  if ($d.Status -ne "OK") {
    $errors += "$($d.Class): $($d.FriendlyName) (Status=$($d.Status))"
  }
}

$status =
  if ($errors.Count -gt 0) { "ERROR" }
  elseif ($warnings.Count -gt 0) { "WARNING" }
  else { "OK" }

$result = [pscustomobject]@{
  Stage       = "Drivers"
  Status      = $status
  Summary     = "Drivers com erro: $($errors.Count)"
  Problems    = $errors + $warnings
  GeneratedAt = Get-Date
}

$result | ConvertTo-Json -Depth 4 | Set-Content $OutJson -Encoding UTF8
exit 0
