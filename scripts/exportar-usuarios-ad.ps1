param(
    [string]$OutputPath = $(Join-Path $PSScriptRoot "..\ad-users.json")
)

Import-Module ActiveDirectory -ErrorAction Stop

$users = Get-ADUser -Filter * -Properties SamAccountName, DisplayName, Name, mail, Department, Enabled |
    Select-Object SamAccountName, DisplayName, Name, @{Name='Mail';Expression={$_.mail}}, Department, Enabled |
    Sort-Object SamAccountName

$users | ConvertTo-Json -Depth 3 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "Exportados $($users.Count) usuarios en: $OutputPath"
