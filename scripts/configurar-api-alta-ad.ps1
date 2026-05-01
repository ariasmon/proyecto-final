param(
    [string]$SiteName = 'MiSitio',
    [string]$ApiPhysicalPath = 'C:\inetpub\wwwroot\misitio\api',
    [string]$AuditLogPath = 'C:\inetpub\wwwroot\misitio\logs\ad-user-audit.log'
)

Import-Module WebAdministration -ErrorAction Stop

Write-Host 'Habilitando módulos IIS requeridos...'
Install-WindowsFeature Web-CGI, Web-Windows-Auth -IncludeManagementTools | Out-Null

if (-not (Test-Path "IIS:\Sites\$SiteName")) {
    throw "No existe el sitio IIS '$SiteName'."
}

if (-not (Test-Path $ApiPhysicalPath)) {
    throw "No existe el path de API: $ApiPhysicalPath"
}

if (-not (Test-Path "IIS:\Sites\$SiteName\api")) {
    New-WebApplication -Site $SiteName -Name 'api' -PhysicalPath $ApiPhysicalPath -ApplicationPool 'DefaultAppPool' | Out-Null
    Write-Host "Aplicación /api creada en sitio $SiteName"
} else {
    Set-ItemProperty "IIS:\Sites\$SiteName\api" -Name physicalPath -Value $ApiPhysicalPath
    Write-Host 'Aplicación /api ya existente, path actualizado.'
}

Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value False -Location "$SiteName/api"
Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/windowsAuthentication -Name enabled -Value True -Location "$SiteName/api"

if (-not (Test-Path (Split-Path $AuditLogPath -Parent))) {
    New-Item -Path (Split-Path $AuditLogPath -Parent) -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $AuditLogPath)) {
    New-Item -Path $AuditLogPath -ItemType File -Force | Out-Null
}

icacls (Split-Path $AuditLogPath -Parent) /grant "IIS_IUSRS:(OI)(CI)M" | Out-Null
icacls (Split-Path $AuditLogPath -Parent) /grant "IUSR:(OI)(CI)M" | Out-Null

$serviceScript = Join-Path $PSScriptRoot 'ad-user-service.ps1'
if (-not (Test-Path $serviceScript)) {
    throw "No se encontró '$serviceScript'. Asegurate de que ad-user-service.ps1 esta en el mismo directorio que configurar-api-alta-ad.ps1."
}
Copy-Item -Path $serviceScript -Destination $ApiPhysicalPath -Force
Write-Host "ad-user-service.ps1 copiado a $ApiPhysicalPath"

Write-Host 'Configuracion completada.'
Write-Host 'Endpoint disponible en: /api/create-user.ps1 (solo POST y usuarios autorizados).'
