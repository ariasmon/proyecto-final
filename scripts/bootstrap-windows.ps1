#Requires -RunAsAdministrator
param(
    [string]$DomainName = "tfg.vp",
    [string]$NetBIOSName = "TFG",
    [SecureString]$SafeModePassword
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\tfg-bootstrap.log"
$MarkerFile = "C:\tfg-bootstrap-done"
$RepoDir = "C:\tfg-despliegue"
$SiteDir = "C:\inetpub\wwwroot\misitio"
$ApiDir = "$SiteDir\api"
$LogsDir = "$SiteDir\logs"
$GitHubRepo = "https://github.com/ariasmon/proyecto-final.git"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

if (Test-Path $MarkerFile) {
    Write-Host "Bootstrap ya completado ($MarkerFile existe). Saliendo."
    exit 0
}

Write-Log "=============================================="
Write-Log "Bootstrap Windows Server - TFG"
Write-Log "=============================================="

# ============================================================================
# ESTADO 0: AD DS no instalado -> Primer arranque
# ============================================================================
if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {

    # Validar contraseña solo en primer arranque (necesaria para promocion a DC)
    if (-not $SafeModePassword) {
        Write-Host "ERROR: Debe proporcionar -SafeModePassword para la promocion a DC. Ejemplo:"
        Write-Host "  .\bootstrap-windows.ps1 -SafeModePassword (ConvertTo-SecureString 'TuClave' -AsPlainText -Force)"
        exit 1
    }

    Write-Log "[ESTADO 0] Primer arranque - preparando sistema antes de promocion a DC"

    # ------------------------------------------------------------------
    # 1. Instalar Git for Windows
    # ------------------------------------------------------------------
    Write-Log "[1/9] Instalando Git for Windows..."
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
    $gitInstaller = "C:\Git-installer.exe"
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=gitlfs" -NoNewWindow -Wait
    Remove-Item $gitInstaller -ErrorAction SilentlyContinue
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # ------------------------------------------------------------------
    # 2. Instalar features
    # ------------------------------------------------------------------
    Write-Log "[2/9] Instalando roles y features..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-WebServer, Web-Windows-Auth, Web-CGI -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools | Out-Null

    # ------------------------------------------------------------------
    # 3. Instalar Windows Exporter
    # ------------------------------------------------------------------
    Write-Log "[3/9] Instalando Windows Exporter..."
    $exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.27.2/windows_exporter-0.27.2-amd64.msi"
    Invoke-WebRequest -Uri $exporterUrl -OutFile "C:\windows_exporter.msi" -UseBasicParsing
    msiexec /i C:\windows_exporter.msi ENABLED_COLLECTORS="cpu,memory,logical_disk,net,os,system" /qn | Out-Null
    Remove-Item C:\windows_exporter.msi -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow | Out-Null

    # ------------------------------------------------------------------
    # 4. Esperar y montar disco de backup
    # ------------------------------------------------------------------
    Write-Log "[4/9] Esperando disco de backup (max 5 min)..."
    $elapsed = 0
    $maxWait = 300
    $diskReady = $false
    while ($elapsed -lt $maxWait) {
        try {
            $disk = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -or $_.NumberOfPartitions -eq 0 }
            if ($disk) {
                Write-Log "Disco de backup detectado, inicializando..."
                Initialize-Disk -Number $disk[0].Number -PartitionStyle MBR -PassThru |
                    New-Partition -UseMaximumSize -DriveLetter E |
                    Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "Backup" -Confirm:$false -Force | Out-Null
                $diskReady = $true
                break
            }
        } catch { }
        Write-Log "Disco no disponible, esperando... ($elapsed/$maxWait s)"
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
    if (-not $diskReady) {
        Write-Log "ADVERTENCIA: Disco de backup no detectado en 5 min. Se omitira el backup."
    }

    # ------------------------------------------------------------------
    # 5. Tarea programada de backup semanal
    # ------------------------------------------------------------------
    if ($diskReady) {
        Write-Log "[5/9] Creando tarea de backup semanal..."
        schtasks /create /tn "Backup-AD-Semanal" /tr "wbadmin start systemstatebackup -backuptarget:E: -quiet" /sc weekly /d SUN /st 03:00 /ru SYSTEM 2>$null | Out-Null
    } else {
        Write-Log "[5/9] Omitiendo tarea de backup (disco no disponible)"
    }

    # ------------------------------------------------------------------
    # 6. Clonar repositorio
    # ------------------------------------------------------------------
    Write-Log "[6/9] Clonando repositorio..."
    if (Test-Path $RepoDir) {
        Write-Log "Repositorio ya existe, actualizando..."
        & git -C $RepoDir pull origin main 2>&1 | ForEach-Object { Write-Log $_ }
    } else {
        & git clone $GitHubRepo $RepoDir 2>&1 | ForEach-Object { Write-Log $_ }
    }

    # ------------------------------------------------------------------
    # 7. Crear ScheduledTask para post-reboot
    # ------------------------------------------------------------------
    Write-Log "[7/9] Registrando tarea TFG-Bootstrap para post-reboot..."
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\bootstrap-windows.ps1"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "TFG-Bootstrap" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    # ------------------------------------------------------------------
    # 8. Habilitar RDP antes de promocion a DC
    # ------------------------------------------------------------------
    Write-Log "[8/9] Habilitando RDP antes de promocion a DC..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    Start-Service TermService -ErrorAction SilentlyContinue
    Set-Service -Name TermService -StartupType Automatic
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Log "RDP habilitado."

    # ------------------------------------------------------------------
    # 9. Promocionar a Domain Controller
    # ------------------------------------------------------------------
    Write-Log "[9/9] Promocionando a Domain Controller ($DomainName)..."
    Import-Module ADDSDeployment

    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetBIOSName $NetBIOSName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -Force

    Write-Log "Promocion iniciada. El servidor se reiniciara automaticamente."
    exit 0
}

# ============================================================================
# ESTADO 1: AD DS ya instalado -> Segundo arranque (post-reboot)
# ============================================================================
Write-Log "[ESTADO 1] Segundo arranque - configurando AD, IIS, API..."

# ------------------------------------------------------------------
# 1. Configurar DNS forwarders
# ------------------------------------------------------------------
Write-Log "[1/11] Configurando DNS forwarders..."
try {
    Import-Module DnsServer -ErrorAction Stop
    $existingForwarders = Get-DnsServerForwarder -ErrorAction SilentlyContinue
    if ($existingForwarders.IPAddress -notcontains "8.8.8.8") {
        Set-DnsServerForwarder -IPAddress @("8.8.8.8", "8.8.4.4") -PassThru | Out-Null
        Write-Log "DNS forwarders configurados: 8.8.8.8, 8.8.4.4"
    } else {
        Write-Log "DNS forwarders ya configurados, omitiendo."
    }
} catch {
    Write-Log "ADVERTENCIA: No se pudieron configurar DNS forwarders: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 2. Cambiar DNS del adaptador
# ------------------------------------------------------------------
Write-Log "[2/11] Ajustando DNS del adaptador (127.0.0.1 + 8.8.8.8)..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
if ($adapter) {
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("127.0.0.1", "8.8.8.8")
    Write-Log "DNS del adaptador actualizado."
}

# ------------------------------------------------------------------
# 2b. Habilitar y configurar RDP
# ------------------------------------------------------------------
Write-Log "[2b/11] Habilitando RDP..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
Start-Service TermService
Set-Service -Name TermService -StartupType Automatic
New-NetFirewallRule -DisplayName "RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow | Out-Null
Write-Log "RDP habilitado y configurado."

# ------------------------------------------------------------------
# 3. Crear estructura de OUs
# ------------------------------------------------------------------
Write-Log "[3/11] Creando estructura de OUs..."
$ouList = @("Usuarios", "Equipos", "Servidores", "Grupos", "Admins")
foreach ($ou in $ouList) {
    $ouPath = "OU=$ou,DC=tfg,DC=vp"
    try {
        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
        Write-Log "OU '$ou' ya existe."
    } catch {
        New-ADOrganizationalUnit -Name $ou -Path "DC=tfg,DC=vp" -ErrorAction Stop | Out-Null
        Write-Log "OU '$ou' creada."
    }
}

# ------------------------------------------------------------------
# 4. Crear grupos de seguridad
# ------------------------------------------------------------------
Write-Log "[4/11] Creando grupos de seguridad..."
$groupsOU = "OU=Grupos,DC=tfg,DC=vp"
$groups = @(
    @{ Name = "GG_Usuarios"; Description = "Grupo global de usuarios del dominio" },
    @{ Name = "GG_Admins"; Description = "Grupo global de administradores" },
    @{ Name = "GG_Portal-AD-Admins"; Description = "Administradores del portal AD (API altas)" }
)
foreach ($g in $groups) {
    try {
        Get-ADGroup -Identity $g.Name -ErrorAction Stop | Out-Null
        Write-Log "Grupo '$($g.Name)' ya existe."
    } catch {
        New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupCategory Security -GroupScope Global -Path $groupsOU -Description $g.Description | Out-Null
        Write-Log "Grupo '$($g.Name)' creado."
    }
}

# ------------------------------------------------------------------
# 5. Instalar Sysmon
# ------------------------------------------------------------------
Write-Log "[5/11] Instalando Sysmon..."
$sysmonZip = "C:\Sysmon.zip"
$sysmonDir = "C:\Sysmon"
$configPath = "$sysmonDir\sysmonconfig.xml"

if (-not (Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue)) {
    $sysmonUrl = "https://download.sysinternals.com/files/Sysmon.zip"
    Invoke-WebRequest -Uri $sysmonUrl -OutFile $sysmonZip -UseBasicParsing
    Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
    Remove-Item $sysmonZip -ErrorAction SilentlyContinue

    $repoConfig = Join-Path $RepoDir "configs\sysmonconfig.xml"
    if (Test-Path $repoConfig) {
        Copy-Item -Path $repoConfig -Destination $configPath -Force
        Write-Log "sysmonconfig.xml copiado desde repositorio."
    } else {
        $fallbackUrl = "https://raw.githubusercontent.com/ariasmon/proyecto-final/main/configs/sysmonconfig.xml"
        try {
            Invoke-WebRequest -Uri $fallbackUrl -OutFile $configPath -UseBasicParsing
            Write-Log "sysmonconfig.xml descargado desde GitHub."
        } catch {
            Write-Log "ADVERTENCIA: No se pudo descargar sysmonconfig.xml, usando config basica."
            @"
<SysmonSchema xmlns="http://schemas.microsoft.com/sysmon/2016/09/schema">
<Schemas>
<EventFiltering>
</EventFiltering>
</Schemas>
</SysmonSchema>
"@ | Set-Content -Path $configPath -Encoding UTF8
        }
    }

    Push-Location $sysmonDir
    .\sysmon64.exe -accepteula -i $configPath
    Pop-Location
    Write-Log "Sysmon instalado."
} else {
    Write-Log "Sysmon ya instalado, omitiendo."
}

# ------------------------------------------------------------------
# 6. Desplegar IIS: sitio MiSitio + contenido web
# ------------------------------------------------------------------
Write-Log "[6/11] Configurando IIS..."
Import-Module WebAdministration -ErrorAction Stop

if (-not (Test-Path $SiteDir)) {
    New-Item -Path $SiteDir -ItemType Directory -Force | Out-Null
}

$webSource = Join-Path $RepoDir "Pagina IIS"
if (Test-Path $webSource) {
    Copy-Item -Path "$webSource\*" -Destination $SiteDir -Recurse -Force
    Write-Log "Contenido web copiado a $SiteDir"
}

if (-not (Test-Path "IIS:\Sites\MiSitio")) {
    Remove-Item "IIS:\Sites\Default Web Site" -Recurse -Force -ErrorAction SilentlyContinue
    New-Website -Name "MiSitio" -PhysicalPath $SiteDir -Port 80 -Force | Out-Null
    Write-Log "Sitio IIS 'MiSitio' creado."
} else {
    Write-Log "Sitio IIS 'MiSitio' ya existe."
}

# ------------------------------------------------------------------
# 7. Configurar API AD
# ------------------------------------------------------------------
Write-Log "[7/11] Configurando API de altas de usuarios AD..."

if (-not (Test-Path $ApiDir)) {
    New-Item -Path $ApiDir -ItemType Directory -Force | Out-Null
}

$apiScripts = @("ad-user-service.ps1", "create-user.ps1", "web.config")
foreach ($file in $apiScripts) {
    $src = Join-Path $RepoDir "scripts\$file"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $ApiDir -Force
        Write-Log "  $file copiado a $ApiDir"
    } else {
        Write-Log "ADVERTENCIA: No se encontro $file en el repositorio."
    }
}

if (-not (Test-Path "IIS:\Sites\MiSitio\api")) {
    New-WebApplication -Site "MiSitio" -Name "api" -PhysicalPath $ApiDir -ApplicationPool "DefaultAppPool" | Out-Null
    Write-Log "Aplicacion /api creada en MiSitio."
} else {
    Write-Log "Aplicacion /api ya existe."
}

Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value False -Location "MiSitio/api"
Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/windowsAuthentication -Name enabled -Value True -Location "MiSitio/api"
Write-Log "Autenticacion Windows habilitada en /api (Anonymous deshabilitado)."

if (-not (Test-Path $LogsDir)) {
    New-Item -Path $LogsDir -ItemType Directory -Force | Out-Null
}
$auditLog = "$LogsDir\ad-user-audit.log"
if (-not (Test-Path $auditLog)) {
    New-Item -Path $auditLog -ItemType File -Force | Out-Null
}
icacls $LogsDir /grant "IIS_IUSRS:(OI)(CI)M" 2>$null | Out-Null
icacls $LogsDir /grant "IUSR:(OI)(CI)M" 2>$null | Out-Null
Write-Log "Directorio de logs y permisos configurados."

# ------------------------------------------------------------------
# 8. Generar ad-users.json
# ------------------------------------------------------------------
Write-Log "[8/11] Generando ad-users.json..."
$exportScript = Join-Path $RepoDir "scripts\exportar-usuarios-ad.ps1"
$adUsersJson = "$SiteDir\ad-users.json"
try {
    & powershell -ExecutionPolicy Bypass -File $exportScript -OutputPath $adUsersJson
    Write-Log "ad-users.json generado en $adUsersJson"
} catch {
    Write-Log "ADVERTENCIA: No se pudo generar ad-users.json: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 9. Tarea programada para exportar usuarios cada hora
# ------------------------------------------------------------------
Write-Log "[9/11] Creando tarea programada de exportacion de usuarios..."
$exportAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$exportScript`" -OutputPath `"$adUsersJson`""
$exportTrigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -At (Get-Date) -Once -Enabled
$exportPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$exportSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
try {
    Register-ScheduledTask -TaskName "Exportar-Usuarios-AD" -Action $exportAction -Trigger $exportTrigger -Principal $exportPrincipal -Settings $exportSettings -Force | Out-Null
    Write-Log "Tarea 'Exportar-Usuarios-AD' registrada (cada hora)."
} catch {
    Write-Log "ADVERTENCIA: No se pudo crear tarea de exportacion: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 10. Eliminar ScheduledTask de bootstrap
# ------------------------------------------------------------------
Write-Log "[10/11] Eliminando tarea TFG-Bootstrap..."
Unregister-ScheduledTask -TaskName "TFG-Bootstrap" -Confirm:$false -ErrorAction SilentlyContinue
Write-Log "Tarea TFG-Bootstrap eliminada."

# ------------------------------------------------------------------
# 11. Crear marcador de finalizacion
# ------------------------------------------------------------------
Write-Log "[11/11] Creando marcador de finalizacion..."
$bootstrapInfo = @{
    CompletedAt = (Get-Date).ToString("o")
    DomainName = $DomainName
    NetBIOSName = $NetBIOSName
} | ConvertTo-Json
Set-Content -Path $MarkerFile -Value $bootstrapInfo -Encoding UTF8

Write-Log "=============================================="
Write-Log "Bootstrap Windows completado."
Write-Log "=============================================="
Write-Log ""
Write-Log "Dominio: $DomainName"
Write-Log "IIS: http://10.0.2.75 (MiSitio)"
Write-Log "API: http://10.0.2.75/api/create-user.ps1"
Write-Log "Log: $LogFile"
