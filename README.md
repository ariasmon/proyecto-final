# 4.4. Implementación del Controlador de Dominio

Tras completar la configuración de la infraestructura de red y verificar la conectividad entre las instancias de la VPC, se procedió a la configuración del servidor interno basado en **Windows Server 2022** como controlador de dominio mediante la instalación del rol **Active Directory Domain Services**. El objetivo de esta fase fue establecer un sistema centralizado de autenticación y gestión de identidades para la red privada del proyecto, permitiendo administrar usuarios, equipos y políticas de seguridad desde un único punto.

## Instalación del rol Active Directory

La instalación del servicio se realizó a través del **Server Manager** del sistema operativo, utilizando el asistente de instalación de roles y características. Durante este proceso se seleccionó el rol **Active Directory Domain Services (AD DS)**, incluyendo automáticamente las dependencias necesarias para su funcionamiento. Entre estas dependencias se encuentra el servicio **DNS**, fundamental para el funcionamiento de Active Directory, ya que permite localizar los distintos servicios del dominio dentro de la red interna.  

Una vez completada la instalación del rol, el sistema solicitó **promover el servidor a controlador de dominio**.

## Promoción del servidor a controlador de dominio

El servidor fue configurado como el **primer controlador de dominio** dentro de un nuevo bosque (*Forest*). Para ello se definió el nombre del dominio interno utilizado en el entorno de laboratorio:  

- **Dominio del proyecto:** tfg.vp  
- **Nombre NetBIOS del dominio:** TFG  

Durante el proceso de configuración se habilitaron las siguientes funciones:  

- Servidor **DNS integrado**  
- **Catálogo global (Global Catalog)**  
- Base de datos del directorio de **Active Directory**  

Asimismo, se estableció una **contraseña de recuperación para el modo Directory Services Restore Mode (DSRM)**, utilizada para tareas de mantenimiento o recuperación del servicio en caso de fallo crítico.  

Una vez completada la validación de requisitos por parte del asistente de instalación, el sistema procedió a instalar los componentes necesarios y **reinició automáticamente el servidor** para finalizar el proceso.

## Configuración del servicio DNS

Durante la promoción del servidor a controlador de dominio se instaló automáticamente el servicio **DNS integrado**. Este servicio es esencial para el funcionamiento de Active Directory, ya que permite a los equipos de la red localizar servicios como:  

- Controladores de dominio  
- Servidores LDAP  
- Otros recursos del directorio  

Durante el proceso de instalación se mostró una advertencia relacionada con la **imposibilidad de crear una delegación DNS**. Este mensaje es habitual cuando se crea un dominio completamente nuevo dentro de una red privada sin una zona DNS superior existente, por lo que **no afecta al funcionamiento del entorno desplegado**.

## Verificación del servicio

Una vez completada la instalación, se verificó el correcto funcionamiento del dominio mediante las herramientas administrativas incluidas en el sistema operativo, especialmente la consola **Active Directory Users and Computers**. A través de esta herramienta se comprobó:  

- La creación correcta del dominio  
- La disponibilidad del controlador de dominio  
- El funcionamiento del servicio de autenticación  
- La correcta resolución de nombres mediante **DNS** dentro de la red privada  

Finalmente, se confirmó que el servidor **Windows mantiene conectividad hacia Internet** a través del servidor Ubuntu configurado previamente como **gateway NAT**, validando así la integración entre la infraestructura de red y los servicios de directorio implementados.

# 4.5 Implementación de Windows Exporter para la Monitorización del Servidor

Con el objetivo de permitir la monitorización del servidor Windows dentro de la infraestructura del proyecto, se implementó **Windows Exporter**, una herramienta que expone métricas del sistema operativo Windows en un formato compatible con sistemas de monitorización.

Windows Exporter recopila información del sistema como el uso de CPU, memoria, disco y red, y la expone a través de un endpoint HTTP interno que puede ser consultado desde la red privada.

## Instalación de Windows Exporter

La instalación se realizó en el servidor **Windows Server 2022** mediante el paquete instalador en formato `.msi`. Durante el proceso de instalación se configuraron los *collectors*, responsables de recopilar diferentes métricas del sistema.

Entre los módulos habilitados se encuentran:

- `cpu` – uso del procesador  
- `memory` – consumo de memoria RAM  
- `logical_disk` – espacio disponible y uso de discos  
- `net` – estadísticas de tráfico de red  
- `os` – información general del sistema operativo  
- `system` – estado general del sistema y tiempo de actividad  

Una vez completada la instalación, Windows Exporter se ejecuta automáticamente como un servicio de Windows llamado **windows_exporter**.

## Exposición de métricas

Windows Exporter expone las métricas a través de un servidor HTTP que escucha en el puerto **9182**. Para verificar el correcto funcionamiento del servicio, se accedió desde el propio servidor a:


http://localhost:9182/metrics


Al abrir esta dirección se muestran múltiples métricas del sistema en formato de texto estructurado, incluyendo información sobre CPU, memoria, discos y estado del sistema.

Ejemplos de métricas visibles:


windows_cpu_time_total
windows_memory_available_bytes
windows_logical_disk_free_bytes
windows_os_info
windows_system_system_up_time


## Configuración del firewall

Para permitir que otros equipos dentro de la red privada puedan acceder a las métricas, se creó una regla en el firewall de Windows que permite conexiones entrantes al puerto 9182:

```powershell
New-NetFirewallRule -DisplayName "windows_exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow

Con esto, el servidor Windows queda preparado para exponer sus métricas del sistema de manera centralizada, lo que permitirá su monitorización en futuras fases del proyecto.

```

# 5. Implementación de Active Directory y configuración básica de seguridad

## 5.1 Estado actual

- Servidor con **Active Directory Domain Services (AD DS)** instalado y promocionado como **Controlador de Dominio**.  
- Dominio configurado: `tfg.vp`  
- Nivel funcional de dominio y bosque: **Windows Server 2016**  
- DNS y Global Catalog habilitados.  
- Inicio de sesión posterior: `TFG\Administrator`.  
- Estructura de OU creada en AD para organización de usuarios, equipos y grupos.

---

## 5.2 Estructura de Active Directory

### Unidades Organizativas (OU)


TFG
├── Usuarios
├── Equipos
├── Servidores
├── Grupos
└── Admins


> Nota: Los contenedores y grupos por defecto del dominio (`Users`, `Domain Admins`, `Domain Users`, etc.) **no se movieron** ni modificaron para evitar errores en el dominio.

### Grupos de seguridad

Se aplicó el modelo **AGDLP** (Accounts → Global Groups → Domain Local → Permissions):

- **Global Groups (GG_)** → Agrupan usuarios según función:
  - `GG_Usuarios`
  - `GG_Admins`  

- **Domain Local Groups (DL_)** → Asignación de permisos a recursos:
  - Ninguno implementado aún (solo se creó la estructura de grupos)

> Todos los permisos se deben asignar a los **DL_**, los usuarios se agregan a los **GG_**, siguiendo buenas prácticas.

---

## 5.3 GPO básicas implementadas

Se crearon y vincularon a las **OUs correspondientes** las siguientes políticas de grupo:

| GPO                          | OU aplicada    | Configuración principal |
|-------------------------------|----------------|------------------------|
| **GPO_Seguridad_Contraseñas** | Dominio        | Longitud mínima 8-12 caracteres, complejidad habilitada, historial y expiración opcional |
| **GPO_Seguridad_Equipos**     | OU Equipos     | Firewall activado para Domain/Private/Public Profiles, bloqueo de conexiones entrantes no autorizadas |

> Nota: Los perfiles del firewall se configuraron como **On (activados)**; no se agregaron reglas específicas de entrada o salida para simplificar el laboratorio.

---

## 5.4 Observaciones y buenas prácticas aplicadas

- Se mantuvieron los grupos por defecto del dominio en el contenedor `Users` sin modificaciones.  
- Se crearon OUs específicas para separar usuarios, equipos, servidores y grupos.  
- Se siguió la convención de nombres profesional para grupos de seguridad (`GG_` y `DL_`).  
- Se aplicó la política de firewall básica para proteger todos los equipos del dominio.  

---


# Instalación de Windows Exporter en Windows Server



Paso 1: Descarga del Instalador
Abra PowerShell como Administrador y ejecute el siguiente comando para obtener el paquete MSI:

```
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.27.2/windows_exporter-0.27.2-amd64.msi"
Invoke-WebRequest -Uri $url -OutFile "C:\windows_exporter.msi"
```
Paso 2: Instalación del Agente
Instale el servicio de forma silenciosa con los colectores de sistema optimizados:

```
msiexec /i C:\windows_exporter.msi ENABLED_COLLECTORS="cpu,memory,logical_disk,net,os,system" /qn
```

Paso 3: Verificación y Firewall
Asegúrese de que el servicio esté corriendo y habilite el puerto de escucha (9182):

# Verificar servicio
```
Get-Service windows_exporter
```
# Abrir puerto en el firewall
```
New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow
```
Paso 4: Validación de Métricas
Para confirmar que el agente está exponiendo datos, acceda a la siguiente URL en el navegador del servidor:

 http://localhost:9182/metrics


# Documentacion de Grafana

## Objetivo

Se configuro Grafana para visualizar el estado del Windows Server dentro de la infraestructura del TFG. El dashboard se adapto a las metricas reales expuestas por Windows Exporter y al datasource Prometheus disponible en el entorno.

## Trabajo realizado

### 1. Adaptacion del dashboard

Se tomo una plantilla de dashboard de Windows Exporter y se corrigieron las consultas PromQL para ajustarlas a las metricas que realmente expone el servidor Windows. El objetivo fue evitar paneles con errores, valores vacios o consultas incompatibles con el exporter instalado.

### 2. Configuracion del datasource

Grafana se configuro para utilizar el datasource Prometheus llamado `Prometheus`, apuntando a la instancia local disponible en el entorno.

### 3. Normalizacion de variables

Se revisaron las variables del dashboard para que el selector de servidor funcionara correctamente con la serie de metricas del Windows Server.



## Metricas que se usaron

Las metricas que si se aprovecharon en el dashboard fueron estas:

- `windows_cpu_time_total`
- `windows_os_physical_memory_free_bytes`
- `windows_os_visible_memory_bytes`
- `windows_logical_disk_free_bytes`
- `windows_logical_disk_size_bytes`
- `windows_net_bytes_sent_total`
- `windows_net_bytes_received_total`
- `windows_os_processes`
- `windows_system_threads`
- `windows_system_system_up_time`
- `windows_os_time`
- `windows_system_processor_queue_length`
- `windows_service_state`

## Consultas finales recomendadas

### Uso de CPU

```promql
100 * (1 - avg(rate(windows_cpu_time_total{instance=~"$server",mode="idle"}[5m])))
```

### Uso de memoria

```promql
100 * (1 - windows_os_physical_memory_free_bytes{instance=~"$server"} / windows_os_visible_memory_bytes{instance=~"$server"})
```

### Uso de disco

```promql
100 - (windows_logical_disk_free_bytes{instance=~"$server",volume!~"HarddiskVolume.+"} / windows_logical_disk_size_bytes{instance=~"$server",volume!~"HarddiskVolume.+"}) * 100
```

### Trafico de red

```promql
rate(windows_net_bytes_sent_total{instance=~"$server"}[5m]) * 8
```

```promql
rate(windows_net_bytes_received_total{instance=~"$server"}[5m]) * 8
```

### Numero de procesos

```promql
windows_os_processes{instance=~"$server"}
```

### Hilos del sistema

```promql
windows_system_threads{instance=~"$server"}
```

### Tiempo activo del sistema

```promql
time() - windows_system_system_up_time{instance=~"$server"}
```

### Desfase horario aproximado

```promql
abs(time() - windows_os_time{instance=~"$server"})
```

### Cola de procesador

```promql
windows_system_processor_queue_length{instance=~"$server"}
```

# 6. Auditoría de seguridad y Sysmon

Con el objetivo de reforzar la trazabilidad del Windows Server, se habilitaron políticas de auditoría del sistema y se instaló Sysmon como herramienta complementaria de monitorización de eventos avanzados.

#### Políticas de auditoría activadas

Se habilitaron las siguientes directivas de auditoría en el servidor:

- Audit logon events
- Audit account logon events
- Audit account management
- Audit policy change
- Audit object access
- Audit process tracking

Además, dentro de **Computer Configuration > Windows Settings > Security Settings > Advanced Audit Policy Configuration**, se activaron estas categorías:

- Logon/Logoff
- Account Logon
- Account Management
- Object Access
- Policy Change
- Detailed Tracking

También se habilitaron de forma específica los siguientes eventos avanzados:

- Audit Logon
- Audit Logoff
- Audit Account Lockout
- Audit User Account Management
- Audit Security Group Management
- Audit Directory Service Access
- Audit File Share
- Audit Process Creation

#### Instalación de Sysmon

Sysmon se instaló para ampliar la capacidad de análisis de procesos, conexiones y actividad sospechosa en el servidor. La instalación se realizó utilizando un fichero de configuración XML con reglas de filtrado y detección.

```powershell
sysmon64.exe -accepteula -i sysmonconfig.xml
```

Este comando instala Sysmon y aplica la configuración definida en `sysmonconfig.xml`. Para que la instalación funcione correctamente, el ejecutable y el fichero XML deben estar en la misma carpeta o indicarse con ruta completa.


