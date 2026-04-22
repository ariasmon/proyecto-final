#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Interactive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:LogFile = $null

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $basePath = $null

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $basePath = $PSScriptRoot
    } elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $basePath = Split-Path -Path $PSCommandPath -Parent
    } else {
        $basePath = (Get-Location).Path
    }

    $ConfigPath = Join-Path -Path $basePath -ChildPath "backup-config.json"
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    if ($null -eq $Message -or $Message.Length -eq 0) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    if (-not $DryRun -and -not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($DryRun) {
            Write-Log "[DryRun] Se crearia la carpeta: $Path"
        } else {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Read-TextWithDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}

function Read-IntWithDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][int]$DefaultValue,
        [int]$MinValue = 0,
        [int]$MaxValue = 100000
    )

    while ($true) {
        $raw = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $DefaultValue
        }

        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge $MinValue -and $parsed -le $MaxValue) {
            return $parsed
        }

        Write-Host "Valor invalido. Debe ser un numero entre $MinValue y $MaxValue."
    }
}

function Read-TimeWithDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    while ($true) {
        $value = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $DefaultValue
        }

        $candidate = $value.Trim()
        if ($candidate -match '^(?:[01]\d|2[0-3]):[0-5]\d$') {
            return $candidate
        }

        Write-Host "Formato invalido. Usa HH:mm (ej. 03:00)."
    }
}

function Read-ListFromInput {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $raw = Read-Host "$Prompt (separa por coma, vacio para ninguno)"
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $items = $raw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($items)
}

function Get-AvailableBackupVolumes {
    try {
        $volumes = Get-Volume -ErrorAction Stop |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } |
            Sort-Object DriveLetter |
            ForEach-Object { "$($_.DriveLetter):" }

        if ($volumes -and $volumes.Count -gt 0) {
            return @($volumes)
        }
    } catch {
        # Si Get-Volume no esta disponible, usar fallback con Get-PSDrive.
    }

    $fallback = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[A-Z]$' } |
        Sort-Object Name |
        ForEach-Object { "$($_.Name):" }

    return @($fallback)
}

function Read-VolumeSelectionFromSystem {
    $availableVolumes = Get-AvailableBackupVolumes
    if (-not $availableVolumes -or $availableVolumes.Count -eq 0) {
        Write-Host "No se detectaron volumenes automaticamente."
        return Read-ListFromInput -Prompt "Volumenes a incluir (ej. C:,D:)"
    }

    Write-Host "Volumenes detectados:"
    for ($i = 0; $i -lt $availableVolumes.Count; $i++) {
        Write-Host "  $($i + 1)=$($availableVolumes[$i])"
    }

    while ($true) {
        $raw = Read-Host "Selecciona numeros separados por coma, A=todos, Enter=manual"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return Read-ListFromInput -Prompt "Volumenes a incluir (ej. C:,D:)"
        }

        $normalized = $raw.Trim().ToUpperInvariant()
        if ($normalized -eq "A") {
            return @($availableVolumes)
        }

        $parts = $raw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $selected = @()
        $valid = $true

        foreach ($part in $parts) {
            $idx = 0
            if (-not [int]::TryParse($part, [ref]$idx)) {
                $valid = $false
                break
            }

            if ($idx -lt 1 -or $idx -gt $availableVolumes.Count) {
                $valid = $false
                break
            }

            $volume = $availableVolumes[$idx - 1]
            if ($selected -notcontains $volume) {
                $selected += $volume
            }
        }

        if ($valid -and $selected.Count -gt 0) {
            return @($selected)
        }

        Write-Host "Seleccion invalida. Ejemplos: 1,2 o A"
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$DefaultValue = $true
    )

    $defaultLabel = if ($DefaultValue) { "S" } else { "N" }
    while ($true) {
        $raw = Read-Host "$Prompt (S/N) [$defaultLabel]"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $DefaultValue
        }

        switch ($raw.Trim().ToUpperInvariant()) {
            "S" { return $true }
            "SI" { return $true }
            "Y" { return $true }
            "YES" { return $true }
            "N" { return $false }
            "NO" { return $false }
            default {
                Write-Host "Opcion invalida. Usa S o N."
            }
        }
    }
}

function New-InteractiveSchedule {
    $createTask = Read-YesNo -Prompt "Quieres crear una tarea programada para este backup" -DefaultValue $false
    if (-not $createTask) {
        return [PSCustomObject]@{
            Enabled = $false
            Frequency = "None"
            Time = "03:00"
            DayOfWeek = "SUN"
            DayOfMonth = 1
            TaskName = "Backup-Windows-Server"
        }
    }

    Write-Host "Frecuencia: 1=Diaria, 2=Semanal, 3=Mensual"
    $frequencyOption = Read-IntWithDefault -Prompt "Elige frecuencia" -DefaultValue 2 -MinValue 1 -MaxValue 3
    $frequency = switch ($frequencyOption) {
        1 { "Daily" }
        2 { "Weekly" }
        3 { "Monthly" }
        default { "Weekly" }
    }

    $taskTime = Read-TimeWithDefault -Prompt "Hora de ejecucion" -DefaultValue "03:00"
    $taskName = Read-TextWithDefault -Prompt "Nombre de la tarea" -DefaultValue "Backup-Windows-Server"

    $dayOfWeek = "SUN"
    if ($frequency -eq "Weekly") {
        Write-Host "Dia semanal: 1=LUN, 2=MAR, 3=MIE, 4=JUE, 5=VIE, 6=SAB, 7=DOM"
        $dayOption = Read-IntWithDefault -Prompt "Elige dia de la semana" -DefaultValue 7 -MinValue 1 -MaxValue 7
        $dayOfWeek = switch ($dayOption) {
            1 { "MON" }
            2 { "TUE" }
            3 { "WED" }
            4 { "THU" }
            5 { "FRI" }
            6 { "SAT" }
            7 { "SUN" }
            default { "SUN" }
        }
    }

    $dayOfMonth = 1
    if ($frequency -eq "Monthly") {
        $dayOfMonth = Read-IntWithDefault -Prompt "Dia del mes" -DefaultValue 1 -MinValue 1 -MaxValue 28
    }

    return [PSCustomObject]@{
        Enabled = $true
        Frequency = $frequency
        Time = $taskTime
        DayOfWeek = $dayOfWeek
        DayOfMonth = $dayOfMonth
        TaskName = $taskName
    }
}

function Register-BackupScheduledTask {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$ScheduledTask,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ConfigPathValue
    )

    if (-not $ScheduledTask.Enabled) {
        return
    }

    $taskName = if ($ScheduledTask.TaskName) { [string]$ScheduledTask.TaskName } else { "Backup-Windows-Server" }
    $frequency = if ($ScheduledTask.Frequency) { [string]$ScheduledTask.Frequency } else { "Weekly" }
    $time = if ($ScheduledTask.Time) { [string]$ScheduledTask.Time } else { "03:00" }

    $taskCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigPath `"$ConfigPathValue`""

    $arguments = @(
        "/Create",
        "/F",
        "/TN", $taskName,
        "/TR", $taskCommand,
        "/ST", $time,
        "/RU", "SYSTEM",
        "/RL", "HIGHEST"
    )

    switch ($frequency.ToUpperInvariant()) {
        "DAILY" {
            $arguments += @("/SC", "DAILY")
        }
        "WEEKLY" {
            $day = if ($ScheduledTask.DayOfWeek) { [string]$ScheduledTask.DayOfWeek } else { "SUN" }
            $arguments += @("/SC", "WEEKLY", "/D", $day)
        }
        "MONTHLY" {
            $dayNumber = if ($ScheduledTask.DayOfMonth -ne $null) { [int]$ScheduledTask.DayOfMonth } else { 1 }
            $arguments += @("/SC", "MONTHLY", "/D", "$dayNumber")
        }
        default {
            throw "Frecuencia de tarea no valida: $frequency"
        }
    }

    if ($DryRun) {
        Write-Log "[DryRun] Tarea programada: schtasks $($arguments -join ' ')"
        return
    }

    Write-Log "Creando/actualizando tarea programada '$taskName' ($frequency)..."
    & schtasks.exe @arguments | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            Write-Log $_
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo crear la tarea programada '$taskName' (codigo $LASTEXITCODE)."
    }

    Write-Log "Tarea programada '$taskName' creada/actualizada correctamente."
}

function New-InteractiveConfig {
    Write-Host ""
    Write-Host "===== Asistente de Backup (Windows Server 2016) ====="

    $destinationRoot = Read-TextWithDefault -Prompt "Ruta destino de backups" -DefaultValue "E:\Backups"
    $createTimestampFolder = Read-YesNo -Prompt "Crear carpeta por fecha/hora en cada backup" -DefaultValue $true
    $compressArchive = Read-YesNo -Prompt "Comprimir cada backup en ZIP" -DefaultValue $false
    $maxBackupSets = Read-IntWithDefault -Prompt "Numero maximo de copias (0 desactiva)" -DefaultValue 12 -MinValue 0 -MaxValue 9999
    $logDirectory = Read-TextWithDefault -Prompt "Directorio de logs" -DefaultValue "C:\Logs\Backups"
    $enableSystemState = Read-YesNo -Prompt "Incluir System State (wbadmin)" -DefaultValue $false
    $systemStateTarget = "E:"
    if ($enableSystemState) {
        $systemStateTarget = Read-TextWithDefault -Prompt "Destino de System State (ej. E: o \\servidor\share)" -DefaultValue "E:"
    }

    $enableFullDiskBackup = Read-YesNo -Prompt "Quieres copia completa de disco (wbadmin)" -DefaultValue $false
    $fullDiskTarget = "E:"
    $fullDiskUseAllCritical = $true
    $fullDiskVolumes = @()
    if ($enableFullDiskBackup) {
        $fullDiskTarget = Read-TextWithDefault -Prompt "Destino de copia completa (ej. E: o \\servidor\share)" -DefaultValue "E:"
        Write-Host "Modo copia completa: 1=Volumenes criticos del sistema (recomendado), 2=Volumenes especificos"
        $diskMode = Read-IntWithDefault -Prompt "Elige modo de copia completa" -DefaultValue 1 -MinValue 1 -MaxValue 2
        if ($diskMode -eq 2) {
            $fullDiskUseAllCritical = $false
            $fullDiskVolumes = Read-VolumeSelectionFromSystem
        }
    }

    $robocopyThreads = Read-IntWithDefault -Prompt "Hilos Robocopy (/MT)" -DefaultValue 8 -MinValue 1 -MaxValue 128
    $robocopyRetry = Read-IntWithDefault -Prompt "Reintentos Robocopy (/R)" -DefaultValue 2 -MinValue 0 -MaxValue 100
    $robocopyWait = Read-IntWithDefault -Prompt "Espera entre reintentos en segundos (/W)" -DefaultValue 5 -MinValue 0 -MaxValue 600
    $scheduledTask = New-InteractiveSchedule

    $sources = @()
    while ($true) {
        $addSource = Read-YesNo -Prompt "Quieres agregar una carpeta de origen al backup" -DefaultValue ($sources.Count -eq 0)
        if (-not $addSource) {
            break
        }

        $path = Read-Host "Ruta de origen (ej. C:\inetpub\wwwroot)"
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Host "Ruta vacia. Se omite este origen."
            continue
        }

        $nameDefault = Split-Path -Path $path.Trim() -Leaf
        if ([string]::IsNullOrWhiteSpace($nameDefault)) {
            $nameDefault = "origen"
        }

        $sourceName = Read-TextWithDefault -Prompt "Nombre para este origen" -DefaultValue $nameDefault
        $mirror = Read-YesNo -Prompt "Modo espejo (/MIR) para este origen" -DefaultValue $false

        $sources += [PSCustomObject]@{
            Name = $sourceName
            Path = $path.Trim()
            Mirror = $mirror
            ExcludeFiles = @()
            ExcludeDirs = @()
        }
    }

    if ($sources.Count -eq 0 -and -not $enableFullDiskBackup) {
        throw "Debes agregar al menos un origen o activar copia completa de disco."
    }

    return [PSCustomObject]@{
        DestinationRoot = $destinationRoot
        CreateTimestampFolder = $createTimestampFolder
        CompressArchive = $compressArchive
        RetentionDays = 30
        MaxBackupSets = $maxBackupSets
        LogDirectory = $logDirectory
        EnableSystemStateBackup = $enableSystemState
        SystemStateTarget = $systemStateTarget
        FullDiskBackup = [PSCustomObject]@{
            Enabled = $enableFullDiskBackup
            BackupTarget = $fullDiskTarget
            UseAllCritical = $fullDiskUseAllCritical
            IncludeVolumes = @($fullDiskVolumes)
        }
        RobocopyThreads = $robocopyThreads
        RobocopyRetryCount = $robocopyRetry
        RobocopyWaitSeconds = $robocopyWait
        ScheduledTask = $scheduledTask
        Sources = @($sources)
    }
}

function Invoke-RobocopyBackup {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][pscustomobject]$SourceConfig,
        [Parameter(Mandatory = $true)][pscustomobject]$GlobalConfig
    )

    $threads = if ($GlobalConfig.RobocopyThreads) { [int]$GlobalConfig.RobocopyThreads } else { 8 }
    $retries = if ($GlobalConfig.RobocopyRetryCount -ne $null) { [int]$GlobalConfig.RobocopyRetryCount } else { 2 }
    $waitSeconds = if ($GlobalConfig.RobocopyWaitSeconds -ne $null) { [int]$GlobalConfig.RobocopyWaitSeconds } else { 5 }

    $useMirror = $false
    if ($SourceConfig.PSObject.Properties.Name -contains "Mirror") {
        $useMirror = [bool]$SourceConfig.Mirror
    }

    $sourcePathSanitized = $SourcePath.TrimEnd('\\')
    $copyMode = if ($useMirror) { "/MIR" } else { "/E" }

    $robocopyArgs = @(
        "`"$sourcePathSanitized`"",
        "`"$DestinationPath`"",
        $copyMode,
        "/Z",
        "/FFT",
        "/R:$retries",
        "/W:$waitSeconds",
        "/MT:$threads",
        "/NP",
        "/XJ"
    )

    if ($SourceConfig.PSObject.Properties.Name -contains "ExcludeFiles" -and $SourceConfig.ExcludeFiles) {
        $robocopyArgs += "/XF"
        $robocopyArgs += @($SourceConfig.ExcludeFiles)
    }

    if ($SourceConfig.PSObject.Properties.Name -contains "ExcludeDirs" -and $SourceConfig.ExcludeDirs) {
        $robocopyArgs += "/XD"
        $robocopyArgs += @($SourceConfig.ExcludeDirs)
    }

    if ($DryRun) {
        Write-Log "[DryRun] Robocopy: robocopy $($robocopyArgs -join ' ')"
        return $true
    }

    Write-Log "Ejecutando robocopy para origen: $SourcePath"
    & robocopy @robocopyArgs | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            Write-Log $_
        }
    }
    $exitCode = $LASTEXITCODE

    # Robocopy: 0-7 exito parcial/total, >7 error.
    if ($exitCode -gt 7) {
        Write-Log "Robocopy finalizo con error (codigo $exitCode) en origen $SourcePath" "ERROR"
        return $false
    }

    Write-Log "Robocopy completado (codigo $exitCode) para $SourcePath"
    return $true
}

function Invoke-SystemStateBackup {
    param([Parameter(Mandatory = $true)][pscustomobject]$Config)

    if (-not $Config.EnableSystemStateBackup) {
        return
    }

    if (-not $Config.SystemStateTarget) {
        throw "EnableSystemStateBackup esta activo pero falta SystemStateTarget en la configuracion."
    }

    $command = "wbadmin start systemstatebackup -backuptarget:$($Config.SystemStateTarget) -quiet"
    if ($DryRun) {
        Write-Log "[DryRun] Comando system state: $command"
        return
    }

    Write-Log "Iniciando backup de estado del sistema con wbadmin..."
    cmd /c $command | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            Write-Log $_
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "wbadmin devolvio codigo $LASTEXITCODE"
    }

    Write-Log "Backup de estado del sistema finalizado correctamente."
}

function Invoke-FullDiskBackup {
    param([Parameter(Mandatory = $true)][pscustomobject]$Config)

    if (-not ($Config.PSObject.Properties.Name -contains "FullDiskBackup") -or -not $Config.FullDiskBackup) {
        return
    }

    if (-not $Config.FullDiskBackup.Enabled) {
        return
    }

    $target = if ($Config.FullDiskBackup.BackupTarget) { [string]$Config.FullDiskBackup.BackupTarget } else { "" }
    if ([string]::IsNullOrWhiteSpace($target)) {
        throw "Copia completa activada pero falta FullDiskBackup.BackupTarget en la configuracion."
    }

    $useAllCritical = $true
    if ($Config.FullDiskBackup.PSObject.Properties.Name -contains "UseAllCritical") {
        $useAllCritical = [bool]$Config.FullDiskBackup.UseAllCritical
    }

    $includeVolumes = @()
    if ($Config.FullDiskBackup.PSObject.Properties.Name -contains "IncludeVolumes" -and $Config.FullDiskBackup.IncludeVolumes) {
        $includeVolumes = @($Config.FullDiskBackup.IncludeVolumes)
    }

    $command = "wbadmin start backup -backuptarget:$target"
    if ($useAllCritical) {
        $command += " -allCritical"
    }
    if ($includeVolumes.Count -gt 0) {
        $command += " -include:$($includeVolumes -join ',')"
    }
    $command += " -quiet"

    if (-not $useAllCritical -and $includeVolumes.Count -eq 0) {
        throw "Copia completa activada sin volumenes. Activa UseAllCritical o define IncludeVolumes."
    }

    if ($DryRun) {
        Write-Log "[DryRun] Comando copia completa: $command"
        return
    }

    Write-Log "Iniciando copia completa de disco con wbadmin..."
    cmd /c $command | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            Write-Log $_
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "wbadmin (copia completa) devolvio codigo $LASTEXITCODE"
    }

    Write-Log "Copia completa de disco finalizada correctamente."
}

function Invoke-RetentionPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][int]$RetentionDays,
        [Parameter(Mandatory = $true)][int]$MaxBackupSets
    )

    $backupDirs = Get-ChildItem -Path $DestinationRoot -Directory -Filter "backup_*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if (-not $backupDirs) {
        return
    }

    if ($RetentionDays -gt 0) {
        $limitDate = (Get-Date).AddDays(-$RetentionDays)
        foreach ($dir in $backupDirs) {
            if ($dir.LastWriteTime -lt $limitDate) {
                if ($DryRun) {
                    Write-Log "[DryRun] Se eliminaria por antiguedad: $($dir.FullName)"
                } else {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force
                    Write-Log "Eliminado por antiguedad: $($dir.FullName)"
                }
            }
        }
    }

    if ($MaxBackupSets -gt 0) {
        $remaining = Get-ChildItem -Path $DestinationRoot -Directory -Filter "backup_*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

        if ($remaining.Count -gt $MaxBackupSets) {
            $toDelete = $remaining | Select-Object -Skip $MaxBackupSets
            foreach ($dir in $toDelete) {
                if ($DryRun) {
                    Write-Log "[DryRun] Se eliminaria por limite de copias: $($dir.FullName)"
                } else {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force
                    Write-Log "Eliminado por limite de copias: $($dir.FullName)"
                }
            }
        }
    }
}

try {
    $config = $null
    if ($Interactive) {
        $config = New-InteractiveConfig

        if (Read-YesNo -Prompt "Guardar esta configuracion para futuras ejecuciones" -DefaultValue $true) {
            $config | ConvertTo-Json -Depth 8 | Out-File -FilePath $ConfigPath -Encoding UTF8
            Write-Host "Configuracion guardada en: $ConfigPath"
        }
    } else {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "No se encontro el archivo de configuracion: $ConfigPath. Usa -Interactive para crearla de forma guiada."
        }
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    if (-not $config.DestinationRoot) {
        throw "Falta DestinationRoot en la configuracion."
    }
    $hasFullDiskBackup = $false
    if ($config.PSObject.Properties.Name -contains "FullDiskBackup" -and $config.FullDiskBackup) {
        if ($config.FullDiskBackup.PSObject.Properties.Name -contains "Enabled") {
            $hasFullDiskBackup = [bool]$config.FullDiskBackup.Enabled
        }
    }

    if ((-not $config.Sources -or $config.Sources.Count -eq 0) -and -not $hasFullDiskBackup) {
        throw "Debe definir al menos un origen en Sources o activar FullDiskBackup.Enabled."
    }

    if ($config.PSObject.Properties.Name -contains "ScheduledTask" -and $config.ScheduledTask) {
        $scriptPathForTask = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
            $PSCommandPath
        } else {
            Join-Path -Path (Get-Location).Path -ChildPath "backup-windows-server.ps1"
        }

        Register-BackupScheduledTask -ScheduledTask $config.ScheduledTask -ScriptPath $scriptPathForTask -ConfigPathValue $ConfigPath
    }

    Ensure-Directory -Path $config.DestinationRoot

    $logDirectory = if ($config.LogDirectory) { [string]$config.LogDirectory } else { (Join-Path $config.DestinationRoot "logs") }
    Ensure-Directory -Path $logDirectory

    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path -Path $logDirectory -ChildPath "backup_$runId.log"
    if (-not $DryRun) {
        "Log de backup iniciado: $(Get-Date)" | Out-File -FilePath $script:LogFile -Encoding UTF8
    }

    Write-Log "=============================================="
    Write-Log "Backup personalizable Windows Server 2016"
    Write-Log "Config: $ConfigPath"
    Write-Log "Interactive: $Interactive"
    Write-Log "DryRun: $DryRun"
    Write-Log "=============================================="

    $createTimestampFolder = $true
    if ($config.PSObject.Properties.Name -contains "CreateTimestampFolder") {
        $createTimestampFolder = [bool]$config.CreateTimestampFolder
    }

    $backupRoot = if ($createTimestampFolder) {
        Join-Path $config.DestinationRoot "backup_$runId"
    } else {
        Join-Path $config.DestinationRoot "backup_actual"
    }

    Ensure-Directory -Path $backupRoot

    $hasErrors = $false
    foreach ($source in $config.Sources) {
        if (-not $source.Path) {
            Write-Log "Origen sin Path detectado en configuracion, se omite." "WARN"
            continue
        }

        $sourcePath = [string]$source.Path
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            Write-Log "El origen no existe y se omite: $sourcePath" "WARN"
            continue
        }

        $sourceName = if ($source.Name) { [string]$source.Name } else { (Split-Path -Path $sourcePath -Leaf) }
        $safeName = ($sourceName -replace '[^a-zA-Z0-9._-]', '_')
        $destinationPath = Join-Path -Path $backupRoot -ChildPath $safeName
        Ensure-Directory -Path $destinationPath

        $ok = Invoke-RobocopyBackup -SourcePath $sourcePath -DestinationPath $destinationPath -SourceConfig $source -GlobalConfig $config
        if (-not $ok) {
            $hasErrors = $true
        }
    }

    $compressArchive = $false
    if ($config.PSObject.Properties.Name -contains "CompressArchive") {
        $compressArchive = [bool]$config.CompressArchive
    }

    if ($compressArchive) {
        $zipPath = Join-Path -Path $config.DestinationRoot -ChildPath "backup_$runId.zip"
        if ($DryRun) {
            Write-Log "[DryRun] Se comprimira la copia en: $zipPath"
        } else {
            Write-Log "Comprimiendo backup en: $zipPath"
            Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
        }
    }

    Invoke-SystemStateBackup -Config $config
    Invoke-FullDiskBackup -Config $config

    $retentionDays = if ($config.RetentionDays -ne $null) { [int]$config.RetentionDays } else { 30 }
    $maxBackupSets = if ($config.MaxBackupSets -ne $null) { [int]$config.MaxBackupSets } else { 10 }

    Invoke-RetentionPolicy -DestinationRoot $config.DestinationRoot -RetentionDays $retentionDays -MaxBackupSets $maxBackupSets

    if ($hasErrors) {
        Write-Log "Backup finalizado con errores en uno o mas origenes." "ERROR"
        exit 2
    }

    Write-Log "Backup finalizado correctamente."
    exit 0
} catch {
    Write-Log "Fallo en la ejecucion: $($_.Exception.Message)" "ERROR"
    exit 1
}
