# Copia de seguridad de Active Directory

## 1. Objetivo

Configurar una estrategia de copia de seguridad para el controlador de dominio Windows Server mediante un volumen EBS adicional, utilizando Windows Server Backup y `wbadmin` para proteger el estado del sistema de Active Directory.

## 2. Prerrequisito: volumen de backup

El servidor Windows no dispone de un segundo volumen dedicado para copias de seguridad, por lo que primero hay que añadir un disco adicional en AWS.

### 2.1. Creación del volumen en AWS

1. Abrir la consola de AWS.
2. Ir a **EC2 > Volumes**.
3. Seleccionar **Create volume**.
4. Configurar:
   - Tipo: `gp3`
   - Tamaño: `10 GiB`
   - Availability Zone: la misma que la instancia `Windows-AD-TFG`
5. Crear el volumen.
6. Seleccionarlo y pulsar **Attach volume**.
7. Asociarlo a la instancia `Windows-AD-TFG`.

### 2.2. Inicialización en Windows Server

Una vez adjuntado el disco:

1. Abrir **Disk Management**.
2. Inicializar el nuevo disco si aparece sin inicializar.
3. Crear un volumen simple.
4. Formatearlo en **NTFS**.
5. Asignar la letra **E:**.
6. Poner la etiqueta **Backup**.

<img width="941" height="91" alt="Creaccion disco duro " src="https://github.com/user-attachments/assets/1281f5dc-721a-4892-87e6-e4b172a3b8fe" />


## 3. Instalación de Windows Server Backup

Para usar la consola de copias de seguridad y `wbadmin`, hay que instalar la característica **Windows Server Backup**.

### 3.1. Desde Server Manager

1. Abrir **Server Manager**.
2. Ir a **Add roles and features**.
3. Avanzar hasta **Features**.
4. Marcar **Windows Server Backup**.
5. Completar la instalación.

### 3.2. Desde PowerShell

```powershell
Install-WindowsFeature Windows-Server-Backup -IncludeManagementTools
```

## 4. Backup manual del estado del sistema

El backup manual del estado del sistema guarda los componentes esenciales de Active Directory y del sistema operativo necesarios para restaurar el controlador de dominio.

### 4.1. Ejecutar la copia

Abrir una consola como administrador y ejecutar:

```cmd
wbadmin start systemstatebackup -backuptarget:E: -quiet
```

<img width="702" height="301" alt="Creacciondelbackup" src="https://github.com/user-attachments/assets/0f7d7f18-b4bb-419f-8efb-cfb9f113f751" />


### 4.2. Qué incluye

Este backup protege, entre otros elementos:

- Base de datos de Active Directory (`ntds.dit`)
- SYSVOL, donde residen GPOs y scripts
- Registro del sistema
- DNS integrado en AD
- COM+
- Certificados del sistema

## 5. Verificación de backups existentes

Para comprobar que las copias se están generando correctamente:

```cmd
wbadmin get versions -backuptarget:E:
```

<img width="437" height="116" alt="CopiasDisponiblesbackup" src="https://github.com/user-attachments/assets/3c845115-3ec1-42e5-abca-f38e998623d5" />


Este comando muestra las versiones disponibles almacenadas en el volumen de backup.

## 6. Backup completo del servidor

Si se quiere preparar una recuperación completa del equipo, incluyendo los volúmenes críticos necesarios para arrancar el sistema desde cero, se puede ejecutar:

```cmd
wbadmin start backup -allcritical -backuptarget:E: -quiet
```

Este tipo de copia es más amplia que el estado del sistema, porque incluye los volúmenes críticos del servidor.

## 7. Automatización con Task Scheduler

Para programar la copia de forma semanal, se puede usar Task Scheduler o crear la tarea por línea de comandos.

### 7.1. Crear tarea con `schtasks`

```cmd
schtasks /create /tn "Backup-AD-Semanal" /tr "wbadmin start systemstatebackup -backuptarget:E: -quiet" /sc weekly /d SUN /st 03:00 /ru SYSTEM
```

### 7.2. Parámetros de la tarea

- Nombre: `Backup-AD-Semanal`
- Frecuencia: semanal
- Día: domingo
- Hora: 03:00
- Usuario: `SYSTEM`
- Acción: ejecutar `wbadmin start systemstatebackup -backuptarget:E: -quiet`

<img width="469" height="367" alt="CreaccionSemanalbackup" src="https://github.com/user-attachments/assets/4837afb5-600f-4f0f-8f6d-9629d6547c71" />


### 7.3. Configuración desde la interfaz gráfica

Si se prefieren capturas más visuales, se puede crear la tarea manualmente desde **Task Scheduler**:

1. Abrir **Task Scheduler**.
2. Crear una tarea nueva.
3. Definir un desencadenador semanal, domingo a las 03:00.
4. Configurar la acción para ejecutar `wbadmin`.
5. Indicar que la tarea se ejecute como `SYSTEM`.

## 8. Restauración

En caso de fallo, la restauración debe hacerse desde **Directory Services Restore Mode (DSRM)**.

### 8.1. Arranque en DSRM

1. Reiniciar el servidor en modo DSRM.
2. Iniciar sesión con la contraseña configurada al promover el controlador de dominio.

### 8.2. Recuperación del estado del sistema

Consultar primero las versiones disponibles:

```cmd
wbadmin get versions -backuptarget:E:
```

Después, restaurar la versión elegida:

```cmd
wbadmin start systemstaterecovery -version:<VERSION_ID>
```

Sustituir `<VERSION_ID>` por la versión exacta obtenida en el paso anterior.
