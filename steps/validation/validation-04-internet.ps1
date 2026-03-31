[CmdletBinding()]
param(
  [string]$OutJson = "C:\Logs\setup\validation-internet.json"
)

$ok = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet

$status = if ($ok) { "OK" } else { "ERROR" }

[pscustomobject]@{
  Stage       = "Internet"
  Status      = $status
  Summary     = if ($ok) { "Conectividade OK" } else { "Sem internet" }
  Problems    = if ($ok) { @() } else { @("Falha de conectividade") }
  GeneratedAt = Get-Date
} | ConvertTo-Json -Depth 4 | Set-Content $OutJson

exit 0
