Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\ad-user-service.ps1"

$allowedUsers = @('TFG\Administrator')
$allowedGroups = @('TFG\GG-Portal-AD-Admins')
$defaultOu = 'OU=Usuarios,DC=tfg,DC=vp'
$auditLog = "$PSScriptRoot\..\logs\ad-user-audit.log"

function Write-JsonResponse {
    param(
        [int]$StatusCode,
        [hashtable]$Payload
    )

    $statusText = switch ($StatusCode) {
        200 { '200 OK' }
        400 { '400 Bad Request' }
        401 { '401 Unauthorized' }
        403 { '403 Forbidden' }
        405 { '405 Method Not Allowed' }
        default { '500 Internal Server Error' }
    }

    Write-Output "Status: $statusText"
    Write-Output 'Content-Type: application/json; charset=utf-8'
    Write-Output ''
    Write-Output ($Payload | ConvertTo-Json -Depth 6)
}

try {
    if ($env:REQUEST_METHOD -and $env:REQUEST_METHOD -ne 'POST') {
        Write-JsonResponse -StatusCode 405 -Payload @{ ok = $false; error = 'Metodo no permitido. Usa POST.' }
        exit 0
    }

    $rawBody = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($rawBody)) {
        Write-JsonResponse -StatusCode 400 -Payload @{ ok = $false; error = 'Body vacio.' }
        exit 0
    }

    $payloadObj = $rawBody | ConvertFrom-Json -ErrorAction Stop
    $payload = @{}
    foreach ($p in $payloadObj.PSObject.Properties) {
        $payload[$p.Name] = $p.Value
    }

    $caller = Resolve-CallerIdentity -ExplicitCaller $payload.CallerIdentity

    $result = New-AdUserFromPayload -Payload $payload `
        -CallerIdentity $caller `
        -AllowedUsers $allowedUsers `
        -AllowedGroups $allowedGroups `
        -DefaultOU $defaultOu `
        -AuditLogPath $auditLog

    Write-JsonResponse -StatusCode 200 -Payload $result
    exit 0
} catch {
    $msg = $_.Exception.Message
    $status = if ($msg -like 'Acceso denegado*') { 403 } else { 400 }

    Write-AuditLog -LogPath $auditLog -Entry @{
        timestamp = (Get-Date).ToString('o')
        action = 'create-user'
        actor = Resolve-CallerIdentity -ExplicitCaller $null
        status = 'error'
        error = $msg
    }

    Write-JsonResponse -StatusCode $status -Payload @{ ok = $false; error = $msg }
    exit 0
}
