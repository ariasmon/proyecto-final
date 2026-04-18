#Requires -RunAsAdministrator
param(
    [string]$DomainName = "tfg.vp",
    [string]$NetBIOSName = "TFG",
    [SecureString]$SafeModePassword
)

$ErrorActionPreference = "Continue"
$LogFile = "C:\tfg-bootstrap.log"
$MarkerFile = "C:\tfg-bootstrap-done"
$RepoDir = "C:\tfg-despliegue"
$SiteDir = "C:\inetpub\wwwroot\misitio"
$ApiDir = "$SiteDir\api"
$LogsDir = "$SiteDir\logs"
$GitHubRepo = "https://github.com/ariasmon/proyecto-final.git"

# Forzar creacion del archivo de log inmediatamente
"Log inicializado: $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8

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
# Importar modulo ServerManager para evitar errores
Import-Module ServerManager -ErrorAction SilentlyContinue

if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {

    # Validar contraseña solo en primer arranque (necesaria para promoción a DC)
    if (-not $SafeModePassword) {
        Write-Host "ERROR: Debe proporcionar -SafeModePassword para la promoción a DC. Ejemplo:"
        Write-Host "  .\bootstrap-windows.ps1 -SafeModePassword (ConvertTo-SecureString 'TuClave' -AsPlainText -Force)"
        exit 1
    }

    Write-Log "[ESTADO 0] Primer arranque - preparando sistema antes de promoción a DC"

    # ------------------------------------------------------------------
    # 1. Instalar Git for Windows
    # ------------------------------------------------------------------
    try {
        Write-Log "[1/9] Instalando Git for Windows..."
        $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
        $gitInstaller = "C:\Git-installer.exe"
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=gitlfs" -NoNewWindow -Wait
        Remove-Item $gitInstaller -ErrorAction SilentlyContinue
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Log "Git instalado correctamente."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo instalar Git: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 2. Instalar características (features)
    # ------------------------------------------------------------------
    try {
        Write-Log "[2/9] Instalando roles y características..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
        Install-WindowsFeature -Name Web-WebServer, Web-Windows-Auth, Web-CGI -IncludeManagementTools | Out-Null
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools | Out-Null
        Write-Log "Roles y características instalados."
    } catch {
        Write-Log "ERROR: No se pudieron instalar roles y características: $($_.Exception.Message)"
        exit 1
    }

    # ------------------------------------------------------------------
    # 3. Instalar Windows Exporter
    # ------------------------------------------------------------------
    try {
        Write-Log "[3/9] Instalando Windows Exporter..."
        $exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.27.2/windows_exporter-0.27.2-amd64.msi"
        Invoke-WebRequest -Uri $exporterUrl -OutFile "C:\windows_exporter.msi" -UseBasicParsing
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i C:\windows_exporter.msi ENABLED_COLLECTORS=`"cpu,memory,logical_disk,net,os,system`" /qn" -NoNewWindow -Wait
        Remove-Item C:\windows_exporter.msi -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Windows Exporter instalado."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo instalar Windows Exporter: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 4. Esperar y montar disco de backup
    # ------------------------------------------------------------------
    Write-Log "[4/9] Buscando disco de backup (máx 5 min)..."
    Write-Log "Enumerando todos los discos del sistema..."
    $allDisks = Get-Disk
    Write-Log "Total de discos detectados: $($allDisks.Count)"
    foreach ($d in $allDisks) {
        Write-Log "  Disco $($d.Number): Status=$($d.OperationalStatus), PartitionStyle=$($d.PartitionStyle), Size=$([math]::Round($d.Size/1GB, 2))GB"
    }
    
    $elapsed = 0
    $maxWait = 300
    $diskReady = $false
    while ($elapsed -lt $maxWait) {
        try {
            # Buscar discos Offline + Online sin letra de unidad asignada
            # Esto detecta discos "Not initialized" (Offline) y discos Online sin particiones
            Write-Log "Buscando disco sin inicializar o sin letra asignada..."
            $disk = Get-Disk | Where-Object { 
                $_.OperationalStatus -eq 'Offline' -or 
                $_.OperationalStatus -eq 'Online' 
            } | Where-Object { 
                $partitions = Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue
                -not ($partitions | Where-Object { $_.DriveLetter })
            } | Select-Object -First 1

            if ($disk) {
                Write-Log ">>> Disco encontrado: Num=$($disk.Number), Status=$($disk.OperationalStatus), PartitionStyle=$($disk.PartitionStyle)"
                Write-Log "Inicializando disco..."
                try {
                    # Si el disco está sin inicializar (RAW o Offline), inicializarlo con MBR
                    if ($disk.PartitionStyle -eq 'RAW') {
                        Write-Log "Inicializando disco como MBR..."
                        Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction Stop
                    }
                    # Crear partición simple con letra E
                    Write-Log "Creando volumen simple..."
                    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter E -ErrorAction Stop
                    # Formatear como NTFS con etiqueta Backup
                    Write-Log "Formateando disco como NTFS..."
                    Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "Backup" -Confirm:$false -Force -ErrorAction Stop | Out-Null
                    $diskReady = $true
                    Write-Log ">>>> Disco de backup configurado correctamente (E:\)"
                    break
                } catch {
                    Write-Log "ERROR al configurar disco: $($_.Exception.Message)"
                }
            } else {
                Write-Log "No se encontró disco sin inicializar en este ciclo"
            }
        } catch {
            Write-Log "ADVERTENCIA: Error al procesar disco de backup: $($_.Exception.Message)"
        }
        Write-Log "Esperando... ($elapsed/$maxWait s)"
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
    if (-not $diskReady) {
        Write-Log "ADVERTENCIA: Disco de backup no detectado en 5 min. Se omitirá el backup."
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
    try {
        Write-Log "[6/9] Clonando repositorio..."
        if (Test-Path $RepoDir) {
            Write-Log "Repositorio ya existe, actualizando..."
            & git -C $RepoDir pull origin main 2>&1 | ForEach-Object { Write-Log $_ }
        } else {
            & git clone $GitHubRepo $RepoDir 2>&1 | ForEach-Object { Write-Log $_ }
        }
        Write-Log "Repositorio listo."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo clonar el repositorio: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 7. Crear ScheduledTask para post-reboot
    # ------------------------------------------------------------------
    try {
        Write-Log "[7/9] Registrando tarea TFG-Bootstrap para post-reinicio..."
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\bootstrap-windows.ps1"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName "TFG-Bootstrap" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "Tarea TFG-Bootstrap registrada."
    } catch {
        Write-Log "ERROR: No se pudo registrar la tarea TFG-Bootstrap: $($_.Exception.Message)"
        exit 1
    }

    # ------------------------------------------------------------------
    # 8. Habilitar RDP antes de promoción a DC
    # ------------------------------------------------------------------
    try {
        Write-Log "[8/9] Habilitando RDP antes de promoción a DC..."
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
        Start-Service TermService -ErrorAction SilentlyContinue
        Set-Service -Name TermService -StartupType Automatic
        Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-Log "RDP habilitado."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo habilitar RDP: $($_.Exception.Message)"
    }

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

    Write-Log "Promoción iniciada. El servidor se reiniciará automáticamente."
    exit 0
}

# ============================================================================
# ESTADO 1: AD DS ya instalado -> Segundo arranque (post-reinicio)
# ============================================================================
# Importar modulo ServerManager para evitar errores
Import-Module ServerManager -ErrorAction SilentlyContinue

Write-Log "=============================================="
Write-Log "[ESTADO 1] Segundo arranque - configurando AD, IIS, API..."
Write-Log "Modulo ServerManager importado"

# ------------------------------------------------------------------
# 0. Detectar e inicializar disco de backup (si existe y no está configurado)
# ------------------------------------------------------------------
Write-Log "[0/12] Buscando disco de backup..."
Write-Log "Enumerando todos los discos del sistema..."
$allDisks = Get-Disk
Write-Log "Total de discos detectados: $($allDisks.Count)"
foreach ($d in $allDisks) {
    Write-Log "  Disco $($d.Number): Status=$($d.OperationalStatus), PartitionStyle=$($d.PartitionStyle), Size=$([math]::Round($d.Size/1GB, 2))GB"
}

$diskReady = $false
$elapsed = 0
$maxWait = 300
while ($elapsed -lt $maxWait) {
    try {
        Write-Log "Buscando disco sin inicializar o sin letra asignada..."
        $disk = Get-Disk | Where-Object { 
            $_.OperationalStatus -eq 'Offline' -or 
            $_.OperationalStatus -eq 'Online' 
        } | Where-Object { 
            $partitions = Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue
            -not ($partitions | Where-Object { $_.DriveLetter })
        } | Select-Object -First 1

        if ($disk) {
            Write-Log ">>> Disco encontrado: Num=$($disk.Number), Status=$($disk.OperationalStatus), PartitionStyle=$($disk.PartitionStyle)"
            Write-Log "Inicializando disco..."
            try {
                if ($disk.PartitionStyle -eq 'RAW') {
                    Write-Log "Inicializando disco como MBR..."
                    Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction Stop
                }
                Write-Log "Creando volumen simple..."
                $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter E -ErrorAction Stop
                Write-Log "Formateando disco como NTFS..."
                Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "Backup" -Confirm:$false -Force -ErrorAction Stop | Out-Null
                $diskReady = $true
                Write-Log ">>>> Disco de backup configurado correctamente (E:\)"
                break
            } catch {
                Write-Log "ERROR al configurar disco: $($_.Exception.Message)"
            }
        } else {
            Write-Log "No se encontró disco sin inicializar en este ciclo"
        }
    } catch {
        Write-Log "ADVERTENCIA: Error al procesar disco de backup: $($_.Exception.Message)"
    }
    Write-Log "Esperando... ($elapsed/$maxWait s)"
    Start-Sleep -Seconds 10
    $elapsed += 10
}
if (-not $diskReady) {
    Write-Log "ADVERTENCIA: Disco de backup no detectado o no se pudo configurar"
}

# ------------------------------------------------------------------
# 0b. Instalar Git y clonar repositorio (si no existen)
# ------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    try {
        Write-Log "[0/11] Instalando Git for Windows..."
        $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
        $gitInstaller = "C:\Git-installer.exe"
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=gitlfs" -NoNewWindow -Wait
        Remove-Item $gitInstaller -ErrorAction SilentlyContinue
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Log "Git instalado correctamente."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo instalar Git: $($_.Exception.Message)"
    }
}

if (-not (Test-Path $RepoDir)) {
    try {
        Write-Log "[0/11] Clonando repositorio..."
        & git clone $GitHubRepo $RepoDir 2>&1 | ForEach-Object { Write-Log $_ }
        Write-Log "Repositorio clonado."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo clonar el repositorio: $($_.Exception.Message)"
    }
} else {
    Write-Log "Repositorio ya existe, actualizando..."
    & git -C $RepoDir pull origin main 2>&1 | ForEach-Object { Write-Log $_ }
}

# ------------------------------------------------------------------
# 0b. Instalar Windows Exporter (si no está instalado)
# ------------------------------------------------------------------
if (-not (Get-Service -Name windows_exporter -ErrorAction SilentlyContinue)) {
    try {
        Write-Log "[0b/11] Instalando Windows Exporter..."
        $exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.27.2/windows_exporter-0.27.2-amd64.msi"
        Invoke-WebRequest -Uri $exporterUrl -OutFile "C:\windows_exporter.msi" -UseBasicParsing
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i C:\windows_exporter.msi ENABLED_COLLECTORS=`"cpu,memory,logical_disk,net,os,system`" /qn" -NoNewWindow -Wait
        Remove-Item C:\windows_exporter.msi -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Windows Exporter instalado."
    } catch {
        Write-Log "ADVERTENCIA: No se pudo instalar Windows Exporter: $($_.Exception.Message)"
    }
} else {
    Write-Log "Windows Exporter ya instalado, omitiendo."
}

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
try {
    Write-Log "[2b/11] Habilitando RDP..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    Start-Service TermService -ErrorAction SilentlyContinue
    Set-Service -Name TermService -StartupType Automatic
    New-NetFirewallRule -DisplayName "RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Log "RDP habilitado y configurado."
} catch {
    Write-Log "ADVERTENCIA: No se pudo habilitar RDP: $($_.Exception.Message)"
}

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
try {
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
                Write-Log "ADVERTENCIA: No se pudo descargar sysmonconfig.xml, usando config básica."
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
} catch {
    Write-Log "ADVERTENCIA: No se pudo instalar Sysmon: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 6. Desplegar IIS: sitio MiSitio + contenido web
# ------------------------------------------------------------------
try {
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
} catch {
    Write-Log "ADVERTENCIA: No se pudo configurar IIS: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 7. Configurar API AD
# ------------------------------------------------------------------
try {
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
            Write-Log "ADVERTENCIA: No se encontró $file en el repositorio."
        }
    }

    if (-not (Test-Path "IIS:\Sites\MiSitio\api")) {
        New-WebApplication -Site "MiSitio" -Name "api" -PhysicalPath $ApiDir -ApplicationPool "DefaultAppPool" | Out-Null
        Write-Log "Aplicación /api creada en MiSitio."
    } else {
        Write-Log "Aplicación /api ya existe."
    }

    Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value False -Location "MiSitio/api"
    Set-WebConfigurationProperty -PSPath IIS:\ -Filter /system.webServer/security/authentication/windowsAuthentication -Name enabled -Value True -Location "MiSitio/api"
    Write-Log "Autenticación Windows habilitada en /api (Anonymous deshabilitado)."

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
} catch {
    Write-Log "ADVERTENCIA: No se pudo configurar la API AD: $($_.Exception.Message)"
}

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
# 9. Tarea programada para exportar usuarios (diaria a las 03:00)
# ------------------------------------------------------------------
Write-Log "[9/11] Creando tarea programada de exportación de usuarios..."
$exportAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$exportScript`" -OutputPath `"$adUsersJson`""
$exportTrigger = New-ScheduledTaskTrigger -Daily -At "03:00AM"
$exportPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$exportSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
try {
    Register-ScheduledTask -TaskName "Exportar-Usuarios-AD" -Action $exportAction -Trigger $exportTrigger -Principal $exportPrincipal -Settings $exportSettings -Force | Out-Null
    Write-Log "Tarea 'Exportar-Usuarios-AD' registrada (diaria a las 03:00)."
} catch {
    Write-Log "ADVERTENCIA: No se pudo crear tarea de exportación: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# 10. Eliminar ScheduledTask de bootstrap
# ------------------------------------------------------------------
Write-Log "[10/11] Eliminando tareas de bootstrap..."
Unregister-ScheduledTask -TaskName "TFG-Bootstrap" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "TFG-Stage2" -Confirm:$false -ErrorAction SilentlyContinue
Write-Log "Tareas de bootstrap eliminadas."

# ------------------------------------------------------------------
# 11. Crear marcador de finalización
# ------------------------------------------------------------------
Write-Log "[11/11] Creando marcador de finalización..."
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
