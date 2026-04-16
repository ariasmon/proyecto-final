#Requires -RunAsAdministrator
#
# bootstrap-windows.ps1 - Configuracion completa del Windows Server para TFG
# Automatiza: Active Directory, DNS, Sysmon
#
# Uso: Ejecutar tras primer arranque del Windows Server.
# El script detecta el estado actual y ejecuta los pasos necesarios.
#

param(
    [string]$DomainName = "tfg.vp",
    [string]$NetBIOSName = "TFG",
    [SecureString]$SafeModePassword = (ConvertTo-SecureString "REDACTED" -AsPlainText -Force)
)

$ErrorActionPreference = "Stop"

Write-Host "=============================================="
Write-Host "Bootstrap del Windows Server - TFG"
Write-Host "=============================================="
Write-Host ""

# ============================================================================
# ESTADO 1: No es DC -> Instalar AD DS y promover
# ============================================================================
if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {

    Write-Host "[1/3] Instalando rol AD DS..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

    Write-Host "[2/3] Promocionando a Domain Controller ($DomainName)..."
    Import-Module ADDSDeployment

    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetBIOSName $NetBIOSName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -Force

    # NoRebootOnCompletion no se usa para que reinicie automaticamente
    exit 0
}

# ============================================================================
# ESTADO 2: Ya es DC -> Instalar Sysmon
# ============================================================================
Write-Host "[1/3] Servidor ya es Domain Controller, saltando instalacion AD DS..."
Write-Host "[2/3] Instalando Sysmon..."

$sysmonUrl = "https://download.sysinternals.com/files/Sysmon.zip"
$sysmonZip = "C:\Sysmon.zip"
$sysmonDir = "C:\Sysmon"
$configUrl = "https://raw.githubusercontent.com/ariasmon/proyecto-final/main/configs/sysmonconfig.xml"
$configPath = "$sysmonDir\sysmonconfig.xml"

Invoke-WebRequest -Uri $sysmonUrl -OutFile $sysmonZip
Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
Remove-Item $sysmonZip

try {
    Invoke-WebRequest -Uri $configUrl -OutFile $configPath -UseBasicParsing
} catch {
    Write-Host "ADVERTENCIA: No se pudo descargar sysmonconfig.xml, usando configuracion basica..."
    @"
<SysmonSchema xmlns="http://schemas.microsoft.com/sysmon/2016/09/schema">
<Schemas>
<EventFiltering>
</EventFiltering>
</Schemas>
</SysmonSchema>
"@ | Set-Content -Path $configPath -Encoding UTF8
}

cd $sysmonDir
.\sysmon64.exe -accepteula -i $configPath

Write-Host "[3/3] Configuracion completada."
Write-Host ""
Write-Host "=============================================="
Write-Host "Bootstrap Windows completado."
Write-Host "=============================================="

