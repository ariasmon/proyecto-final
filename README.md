# Documentacion del Script de Backup para Windows Server 2016

## 1. Objetivo
Se ha creado un sistema de backup personalizable para Windows Server 2016 con dos modos principales:

- Backup de carpetas (con Robocopy)
- Backup completo de disco (con wbadmin)

Ademas, se incluyo un asistente interactivo para elegir opciones en tiempo de ejecucion, y la posibilidad de crear tareas programadas (diaria, semanal o mensual).

## 2. Archivos creados y actualizados

- scripts/backup-windows-server.ps1
  Script principal con toda la logica de backup.

- scripts/backup-config.json
  Configuracion activa por defecto para ejecucion no interactiva.

## 3. Funcionalidades implementadas

### 3.1 Modos de ejecucion

- Modo interactivo
  Permite configurar todo mediante preguntas en consola.

- Modo por configuracion JSON
  Lee valores desde backup-config.json o desde la ruta indicada con el parametro ConfigPath.

- Modo simulacion (DryRun)
  Muestra que se haria sin ejecutar cambios reales.

### 3.2 Backup de carpetas con Robocopy

- Copia por origen definido en Sources.
- Modo espejo opcional por origen (Mirror).
- Soporte de exclusion de archivos y carpetas (cuando vengan en JSON).
- Manejo de codigos de salida de Robocopy:
  - 0 a 7: exito total o parcial
  - mayor a 7: error

### 3.3 Backup de estado del sistema

- Opcion EnableSystemStateBackup.
- Ejecuta wbadmin start systemstatebackup con destino configurable.

### 3.4 Backup completo de disco

- Nueva seccion FullDiskBackup en configuracion.
- Permite dos enfoques:
  - allCritical para volumenes criticos del sistema
  - include para volumenes especificos (por ejemplo C:, D:)
- Valida que exista destino y que haya criterio valido de seleccion de volumenes.

### 3.5 Seleccion automatica de volumenes

En modo interactivo, cuando se elige copia completa por volumenes especificos:

- Se detectan volumenes locales automaticamente.
- Se muestran numerados.
- Se puede seleccionar por indices (ejemplo: 1,2), todos con A o entrada manual.

### 3.6 Tareas programadas

Se puede crear o actualizar una tarea programada desde el asistente:

- Frecuencia diaria, semanal o mensual
- Hora de ejecucion
- Dia de semana (si semanal)
- Dia del mes (si mensual)
- Ejecuta como SYSTEM con privilegios altos

### 3.7 Retencion y limpieza

- Eliminacion por antiguedad (RetentionDays)
- Eliminacion por limite de copias (MaxBackupSets)

## 4. Mejoras de robustez aplicadas

Se corrigieron incidencias detectadas durante pruebas:

- Error con ConfigPath cuando PSScriptRoot estaba vacio
  Se agregaron rutas de fallback para construir la ruta de configuracion.

- Error por variable LogFile no inicializada bajo StrictMode
  Se inicializo script:LogFile y se controlo escritura condicional.

- Error al registrar lineas vacias de salida externa
  Se ignoran lineas vacias de Robocopy, wbadmin y schtasks antes de loguear.

## 5. Estructura de configuracion JSON

Campos principales disponibles:

- DestinationRoot
- CreateTimestampFolder
- CompressArchive
- RetentionDays
- MaxBackupSets
- LogDirectory
- EnableSystemStateBackup
- SystemStateTarget
- FullDiskBackup:
  - Enabled
  - BackupTarget
  - UseAllCritical
  - IncludeVolumes
- RobocopyThreads
- RobocopyRetryCount
- RobocopyWaitSeconds
- ScheduledTask:
  - Enabled
  - Frequency
  - Time
  - DayOfWeek
  - DayOfMonth
  - TaskName
- Sources (lista de origenes)

## 6. Formas de uso

### 6.1 Interactivo

powershell -ExecutionPolicy Bypass -File backup-windows-server.ps1 -Interactive

### 6.2 Interactivo en simulacion

powershell -ExecutionPolicy Bypass -File backup-windows-server.ps1 -Interactive -DryRun

### 6.3 Configuracion JSON

powershell -ExecutionPolicy Bypass -File backup-windows-server.ps1

### 6.4 Configuracion JSON personalizada

powershell -ExecutionPolicy Bypass -File backup-windows-server.ps1 -ConfigPath C:\ruta\mi-config.json

## 7. Recomendaciones operativas

- Probar siempre primero con DryRun.
- Evitar usar el mismo volumen como origen y destino de backup completo.
- Si se usa copia completa, preferir allCritical cuando el objetivo sea recuperacion del sistema.
- Verificar periodicamente logs y espacio libre del destino.

## 8. Resultado final

Se ha construido una solucion de backup flexible y guiada, pensada para administracion real de Windows Server 2016, con automatizacion por tarea programada y soporte para backup de archivos y backup completo del sistema/disco.
