Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-AuditLog {
    param(
        [string]$LogPath,
        [hashtable]$Entry
    )

    $dir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $line = ($Entry | ConvertTo-Json -Compress)
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Test-PasswordPolicy {
    param([string]$Password)

    if ([string]::IsNullOrWhiteSpace($Password)) {
        return $false
    }

    if ($Password.Length -lt 10) { return $false }
    if ($Password -notmatch '[A-Z]') { return $false }
    if ($Password -notmatch '[a-z]') { return $false }
    if ($Password -notmatch '\d') { return $false }
    if ($Password -notmatch '[^a-zA-Z0-9]') { return $false }

    return $true
}

function Resolve-CallerIdentity {
    param([string]$ExplicitCaller)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitCaller)) {
        return $ExplicitCaller
    }

    if (-not [string]::IsNullOrWhiteSpace($env:AUTH_USER)) {
        return $env:AUTH_USER
    }

    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Test-IsCallerAuthorized {
    param(
        [string]$CallerIdentity,
        [string[]]$AllowedUsers,
        [string[]]$AllowedGroups
    )

    if ($AllowedUsers -contains $CallerIdentity) {
        return $true
    }

    if ($AllowedGroups.Count -eq 0) {
        return $false
    }

    try {
        $sam = $CallerIdentity.Split('\\')[-1]
        $groupNames = Get-ADPrincipalGroupMembership -Identity $sam | Select-Object -ExpandProperty Name
        foreach ($group in $AllowedGroups) {
            $name = $group.Split('\\')[-1]
            if ($groupNames -contains $name) {
                return $true
            }
        }
    } catch {
        return $false
    }

    return $false
}

function New-AdUserFromPayload {
    param(
        [hashtable]$Payload,
        [string]$CallerIdentity,
        [string[]]$AllowedUsers,
        [string[]]$AllowedGroups,
        [string]$DefaultOU,
        [string]$AuditLogPath
    )

    Import-Module ActiveDirectory -ErrorAction Stop

    if (-not (Test-IsCallerAuthorized -CallerIdentity $CallerIdentity -AllowedUsers $AllowedUsers -AllowedGroups $AllowedGroups)) {
        throw "Acceso denegado para '$CallerIdentity'."
    }

    $required = @('SamAccountName', 'GivenName', 'Surname', 'DisplayName', 'UserPrincipalName', 'Password')
    foreach ($field in $required) {
        if (-not $Payload.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$Payload[$field])) {
            throw "Falta el campo obligatorio: $field"
        }
    }

    $sam = [string]$Payload.SamAccountName
    $given = [string]$Payload.GivenName
    $surname = [string]$Payload.Surname
    $display = [string]$Payload.DisplayName
    $upn = [string]$Payload.UserPrincipalName
    $mail = [string]$Payload.Mail
    $department = [string]$Payload.Department
    $password = [string]$Payload.Password
    $targetOu = if ([string]::IsNullOrWhiteSpace([string]$Payload.OU)) { $DefaultOU } else { [string]$Payload.OU }

    if ($sam -notmatch '^[a-zA-Z][a-zA-Z0-9._-]{2,30}$') {
        throw 'SamAccountName inválido. Usa 3-31 caracteres alfanumericos, punto, guion o guion bajo.'
    }

    if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw 'UserPrincipalName inválido.'
    }

    if (-not (Test-PasswordPolicy -Password $password)) {
        throw 'La contraseña no cumple política mínima: 10 caracteres, mayuscula, minuscula, numero y simbolo.'
    }

    if ($targetOu -notmatch '^OU=.+,DC=.+') {
        throw 'OU inválida. Debe tener formato LDAP (ejemplo: OU=Usuarios,DC=tfg,DC=vp).'
    }

    $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        throw "Ya existe un usuario con SamAccountName '$sam'."
    }

    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

    $newParams = @{
        SamAccountName    = $sam
        Name              = $display
        GivenName         = $given
        Surname           = $surname
        DisplayName       = $display
        UserPrincipalName = $upn
        AccountPassword   = $securePassword
        Enabled           = $true
        Path              = $targetOu
        ChangePasswordAtLogon = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($mail)) {
        $newParams['EmailAddress'] = $mail
    }

    if (-not [string]::IsNullOrWhiteSpace($department)) {
        $newParams['Department'] = $department
    }

    New-ADUser @newParams

    if ($Payload.ContainsKey('Groups') -and $Payload.Groups -is [System.Collections.IEnumerable]) {
        foreach ($group in $Payload.Groups) {
            if (-not [string]::IsNullOrWhiteSpace([string]$group)) {
                Add-ADGroupMember -Identity ([string]$group) -Members $sam -ErrorAction Stop
            }
        }
    }

    Write-AuditLog -LogPath $AuditLogPath -Entry @{
        timestamp = (Get-Date).ToString('o')
        action = 'create-user'
        actor = $CallerIdentity
        samAccountName = $sam
        upn = $upn
        ou = $targetOu
        status = 'success'
    }

    return @{
        ok = $true
        message = 'Usuario creado correctamente'
        user = @{
            SamAccountName = $sam
            DisplayName = $display
            UserPrincipalName = $upn
            OU = $targetOu
        }
    }
}
