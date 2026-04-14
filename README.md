# TFG: Despliegue de Infraestructura de Red Segura Híbrida en AWS con Monitorización Centralizada

**Autores:** "Víctor Alberjón Hidalgo y Pablo Arias Montilla" 

---

## 1. Planificación inicial

En esta fase se establecen las bases del proyecto, definiendo el alcance, los recursos necesarios y las restricciones que guiarán el desarrollo.

### 1.1. Objetivo

El objetivo principal es diseñar e implantar una infraestructura de red segura en la nube pública (AWS), utilizando una arquitectura de Gateway Linux (Ubuntu) para proteger y enrutar el tráfico de una subred privada donde reside un servidor Windows. Adicionalmente, se busca implementar un sistema de observabilidad que centralice la monitorización de tráfico y recursos de ambos servidores, integrando mecanismos de alerta temprana ante fallos críticos, todo ello bajo un paradigma de **automatización y GitOps**.

### 1.2. Alcance del proyecto

El proyecto contempla la ejecución de las siguientes tareas clave:

* **Infraestructura como Código (IaC):** Automatización total del despliegue mediante AWS CloudFormation (GitOps).
* **Despliegue de Red (VPC):** Configuración de una nube privada virtual segmentada en subredes pública (DMZ) y privada (Intranet).
* **Servidor de Borde (Ubuntu Server):** Configuración como NAT Instance, seguridad perimetral (iptables) y despliegue de stack de monitorización (Prometheus + Grafana).
* **Servidor Interno (Windows Server):** Aislamiento de red (sin IP pública directa) y configuración de servicios internos (Active Directory).
* **Active Directory:** Despliegue de dominio Windows para gestión centralizada de identidades.
* **VPN (WireGuard):** Configuración de túnel VPN para acceso remoto seguro de usuarios al dominio.
* **Gestión y Acceso:** Acceso remoto seguro mediante SSH y RDP (vía Port Forwarding en el Gateway).
* **Interconexión y Visibilidad:** Configuración de tablas de rutas para forzar el tráfico a través del Gateway.

### 1.3. Recursos identificados

* **Infraestructura (AWS EC2 & CloudFormation):**
    * 1x Instancia **t3.micro** (Ubuntu Server 22.04 LTS) + **IP Elástica**.
    * 1x Instancia **t3.small** (Windows Server 2022). *Nota: Se aumentó de micro a small para garantizar la estabilidad del sistema.*
* **Software y Servicios:**
    * Red y Automatización: IPTables, VPC Routing, YAML (CloudFormation).
    * Monitorización: Prometheus, Grafana, Alertmanager, Node Exporter, Windows Exporter.
    * VPN: WireGuard para acceso remoto seguro.

### 1.4. Restricciones y condicionantes

* **Económicas:** Viabilidad dentro de la capa gratuita (Free Tier) de AWS siempre que sea posible.
* **Seguridad:** Administración a través de puertos estándar (22 y 3389) protegidos por Security Groups.
* **Plazos:** Despliegue funcional antes de la fecha de defensa del TFG.

### 1.5. Cronograma preliminar

| Fase | Tarea Principal | Semanas | Descripción |
| :--- | :--- | :--- | :--- |
| Fase 1 | Planificación | 1 - 2 | Definición de alcance y estudio de viabilidad. |
| Fase 2 | Diseño | 3 - 4 | Diagramas de red VPC y políticas de seguridad. |
| Fase 3 | Despliegue Infra | 5 - 6 | Creación de VPC, subredes y automatización IaC. |
| Fase 4 | Configuración | 7 - 8 | Configuración de NAT, Firewall y Monitorización. |
| Fase 5 | Accesos | 9 | Habilitación de SSH y RDP mediante Port Forwarding. |
| Fase 6 | Validación | 10 | Pruebas de conectividad y estrés. |
| Fase 7 | Documentación | 11 - 12 | Redacción final de la memoria y defensa. |

---

## 2. Análisis de requisitos

### 2.1. Requisitos Funcionales (RF)

* **RF-01 (Enrutamiento NAT):** El servidor Ubuntu debe actuar como puerta de enlace para la subred privada.
* **RF-02 (Despliegue Automatizado):** La infraestructura debe poder recrearse de forma idéntica sin intervención manual.
* **RF-03 (Seguridad de Red):** Gestión del tráfico mediante firewall permitiendo solo administración autorizada.
* **RF-04 (Monitorización de Tráfico):** Captura de métricas de ancho de banda en la interfaz del Gateway.
* **RF-05 (Dashboard Unificado):** Grafana debe mostrar el estado de recursos de ambos servidores.
* **RF-06 (Active Directory):** Implementar dominio Windows con AD para gestión centralizada de usuarios y recursos.
* **RF-07 (Acceso VPN):** Configurar WireGuard para permitir acceso remoto seguro de usuarios al dominio corporativo.
* **RF-08 (Gestión de Alertas):** Notificaciones en tiempo real (Telegram/Discord) ante anomalías críticas.
* **RF-09 (Acceso Remoto):** Garantizar acceso administrativo vía SSH (22) y RDP (3389).

### 2.2. Requisitos No Funcionales (RNF)

* **RNF-01 (Aislamiento):** La instancia Windows debe residir en una subred privada sin IP pública directa.
* **RNF-02 (Inmutabilidad):** Aplicación de principios GitOps para garantizar la consistencia del entorno.
* **RNF-03 (Disponibilidad):** Los servicios de enrutamiento deben iniciarse automáticamente (systemd).
* **RNF-04 (Seguridad VPN):** Las conexiones VPN deben utilizar cifrado fuerte. WireGuard emplea criptografía moderna (ChaCha20, Curve25519).
* **RNF-05 (Rendimiento):** El Gateway debe mantener latencias de enrutamiento aceptables sin afectar significativamente el rendimiento de la red.
* **RNF-06 (Documentación):** Toda configuración debe estar documentada y versionada para garantizar replicabilidad del entorno.

### 2.3. Usuarios finales y sus necesidades

El sistema está diseñado para ser utilizado por diferentes perfiles de usuario, cada uno con necesidades específicas:

| Perfil | Descripción | Necesidades |
|--------|-------------|-------------|
| **Administrador de sistemas** | Responsable de la gestión y mantenimiento de la infraestructura | Acceso SSH al Gateway, acceso RDP al Windows Server, visualización de dashboards de monitorización, recepción de alertas |
| **Administrador de dominio** | Gestiona el Active Directory y los usuarios del dominio | Acceso RDP al Windows Server, acceso al dominio tfg.vp |
| **Usuario corporativo** | Usuario final que accede a recursos del dominio | Conexión VPN para acceso remoto, acceso al dominio corporativo |
| **Operador de monitorización** | Supervisa el estado de la infraestructura | Acceso a Grafana, recepción de alertas en Telegram/Discord |

#### Matriz de acceso por perfil

| Recurso | Admin Sistemas | Admin Dominio | Usuario Corp. | Operador |
|---------|---------------|---------------|---------------|----------|
| SSH Gateway | ✓ | - | - | ✓ |
| RDP Windows | ✓ | ✓ | - | - |
| VPN | ✓ | ✓ | ✓ | - |
| Grafana | ✓ | - | - | ✓ |
| Dominio AD | ✓ | ✓ | ✓ | - |
| Alertas | ✓ | - | - | ✓ |

---

## 3. Diseño de la solución

### 3.1. Arquitectura de Red y Topología (AWS VPC)

* **VPC CIDR:** `10.0.0.0/16`
* **Subred Pública (DMZ):** `10.0.1.0/24`. Aloja el Gateway Ubuntu con IP Elástica.
* **Subred Privada (Intranet):** `10.0.2.0/24`. Aloja el Windows Server. Su tráfico `0.0.0.0/0` apunta a la interfaz de red del Ubuntu.
* **Subred VPN (WireGuard):** `172.16.3.0/24`. Fuera del CIDR de la VPC para evitar conflictos con las tablas de rutas de AWS.

### 3.2. Diseño de Seguridad y Accesos

1. **SG-Gateway (Ubuntu):** Inbound: 22/TCP (SSH), 3389/TCP (RDP Forward), 3000/TCP (Grafana), 9090/TCP desde VPC (Prometheus), 9093/TCP desde VPC (Alertmanager), 51820/UDP (WireGuard), todo el tráfico desde `10.0.2.0/24` y `172.16.3.0/24`. Outbound: Todo permitido.
2. **SG-Internal (Windows):** Inbound: todo el tráfico desde `172.16.3.0/24` (VPN), 3389/TCP (RDP) desde SG-Gateway, 9182/TCP (Windows Exporter) desde SG-Gateway, 53/TCP-UDP (DNS) desde SG-Gateway, ICMP desde SG-Gateway. Outbound: Todo permitido.

### 3.3 Esquema de la arquitectura
![Diagrama de Topología de Red](imagenes/topologia.png)
*Figura 1: Topología de red en AWS con segmentación de subredes.*
---

## 4. Implantación y configuración

### 4.1. Despliegue de Infraestructura Base en AWS

1. **IP Elástica:** Asociada al Ubuntu para mantener un punto de acceso administrativo fijo.
2. **IP Estática Windows:** Configurada como `10.0.2.75` para evitar desincronización de servicios internos.
3. **Source/Destination Check:** Desactivado en la instancia Ubuntu para permitir el funcionamiento del NAT.

### 4.2. Configuración del Enrutamiento y NAT en Linux

```bash
# Habilitar IP Forwarding (runtime y persistente)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# NAT para subred privada hacia Internet
sudo iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o ens5 -j MASQUERADE

# NAT para tráfico VPN hacia subred privada
sudo iptables -t nat -A POSTROUTING -s 172.16.3.0/24 -d 10.0.2.0/24 -j MASQUERADE

# Reenvío de puerto RDP (DNAT)
sudo iptables -t nat -A PREROUTING -p tcp --dport 3389 -j DNAT --to-destination 10.0.2.75:3389

# Forwarding VPN ↔ subred privada
sudo iptables -A FORWARD -s 172.16.3.0/24 -d 10.0.2.0/24 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.2.0/24 -d 172.16.3.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Persistencia de reglas
sudo apt update && sudo apt install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

### 4.3. Configuración del Servidor Interno (Windows Server)

Para garantizar la estabilidad operativa y la conectividad a través del Gateway, se han realizado las siguientes configuraciones críticas:

1. **Optimización de Instancia:** Migración del servidor a una instancia de familia **`t3.small`** (2 vCPU, 2GB RAM).
2. **Configuración de Red Estática:** Direccionamiento IPv4 fijado en `10.0.2.75`, Gateway en `10.0.2.1` y DNS apuntando a `127.0.0.1` y `8.8.8.8`.
3. **Ruta estática VPN:** Ruta hacia la subred VPN (`172.16.3.0/24`) a través del Gateway (`10.0.2.1`), necesaria para que el Windows Server pueda responder a clientes VPN.
4. **Gestión del Firewall:** Desactivación del cortafuegos de Windows mediante PowerShell:

```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
route add 172.16.3.0 mask 255.255.255.0 10.0.2.1
```

### 4.4. Implementación del Controlador de Dominio (Active Directory)

Tras completar la configuración de la infraestructura de red y verificar la conectividad entre las instancias de la VPC, se procedió a la configuración del servidor interno basado en **Windows Server 2022** como controlador de dominio mediante la instalación del rol **Active Directory Domain Services**. El objetivo de esta fase fue establecer un sistema centralizado de autenticación y gestión de identidades para la red privada del proyecto.

#### Instalación del rol Active Directory

La instalación del servicio se realizó a través del **Server Manager**, utilizando el asistente de instalación de roles y características. Se seleccionó el rol **Active Directory Domain Services (AD DS)**, incluyendo automáticamente las dependencias necesarias, entre ellas el servicio **DNS**, fundamental para localizar los distintos servicios del dominio dentro de la red interna.

Una vez completada la instalación del rol, el sistema solicitó **promover el servidor a controlador de dominio**.

#### Promoción del servidor a controlador de dominio

El servidor fue configurado como el **primer controlador de dominio** dentro de un nuevo bosque (*Forest*). Se definieron los siguientes parámetros:

| Parámetro | Valor |
|-----------|-------|
| Dominio del proyecto | `tfg.vp` |
| Nombre NetBIOS | `TFG` |

Durante el proceso de configuración se habilitaron:
- Servidor **DNS integrado**
- **Catálogo global (Global Catalog)**
- Base de datos del directorio de **Active Directory**

Asimismo, se estableció una **contraseña de recuperación para el modo Directory Services Restore Mode (DSRM)**, utilizada para tareas de mantenimiento o recuperación del servicio en caso de fallo crítico.

Tras la validación de requisitos, el sistema instaló los componentes necesarios y **reinició automáticamente el servidor** para finalizar el proceso.

#### Configuración del servicio DNS

Durante la promoción del servidor a controlador de dominio se instaló automáticamente el servicio **DNS integrado**. Este servicio es esencial para el funcionamiento de Active Directory, ya que permite a los equipos de la red localizar:
- Controladores de dominio
- Servidores LDAP
- Otros recursos del directorio

Durante la instalación se mostró una advertencia relacionada con la **imposibilidad de crear una delegación DNS**. Este mensaje es habitual cuando se crea un dominio completamente nuevo dentro de una red privada sin una zona DNS superior existente, por lo que **no afecta al funcionamiento del entorno desplegado**.

#### Verificación del servicio

Una vez completada la instalación, se verificó el correcto funcionamiento del dominio mediante las herramientas administrativas incluidas, especialmente la consola **Active Directory Users and Computers**. Se comprobó:
- La creación correcta del dominio
- La disponibilidad del controlador de dominio
- El funcionamiento del servicio de autenticación
- La correcta resolución de nombres mediante **DNS** dentro de la red privada

Finalmente, se confirmó que el servidor Windows mantiene conectividad hacia Internet a través del servidor Ubuntu configurado como gateway NAT, validando la integración entre la infraestructura de red y los servicios de directorio implementados.

### 4.5. Implementación de Windows Exporter para Monitorización

Con el objetivo de permitir la monitorización del servidor Windows dentro de la infraestructura del proyecto, se implementó **Windows Exporter**, una herramienta que expone métricas del sistema operativo Windows en un formato compatible con Prometheus.

Windows Exporter recopila información del sistema como el uso de CPU, memoria, disco y red, y la expone a través de un endpoint HTTP interno que puede ser consultado desde la red privada.

#### Paso 1: Descarga del instalador

Abrir PowerShell como Administrador y ejecutar el siguiente comando para descargar el paquete MSI:

```powershell
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v0.27.2/windows_exporter-0.27.2-amd64.msi"
Invoke-WebRequest -Uri $url -OutFile "C:\windows_exporter.msi"
```

#### Paso 2: Instalación del agente

Instalar el servicio de forma silenciosa con los *collectors* optimizados para el entorno:

```powershell
msiexec /i C:\windows_exporter.msi ENABLED_COLLECTORS="cpu,memory,logical_disk,net,os,system" /qn
```

**Módulos habilitados:**

| Módulo | Descripción |
|--------|-------------|
| `cpu` | Uso del procesador |
| `memory` | Consumo de memoria RAM |
| `logical_disk` | Espacio disponible y uso de discos |
| `net` | Estadísticas de tráfico de red |
| `os` | Información general del sistema operativo |
| `system` | Estado general del sistema y tiempo de actividad |

Una vez completada la instalación, Windows Exporter se ejecuta automáticamente como un servicio de Windows llamado **windows_exporter**.

#### Paso 3: Verificación y Firewall

Verificar que el servicio está en ejecución y habilitar el puerto de escucha:

```powershell
# Verificar estado del servicio
Get-Service windows_exporter

# Abrir puerto en el firewall de Windows
New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow
```

> **Nota:** Aunque el firewall de Windows está desactivado en el controlador de dominio (véase la sección 4.3), esta regla se crea por completitud de configuración. Si el firewall se reactivara en el futuro, el puerto 9182 quedaría automáticamente habilitado sin intervención adicional.

#### Paso 4: Validación de métricas

Para confirmar que el agente está exponiendo datos correctamente, acceder desde el navegador del servidor a:

```
http://localhost:9182/metrics
```

Al abrir esta dirección se muestran múltiples métricas del sistema en formato de texto estructurado. Ejemplos de métricas visibles:

```
windows_cpu_time_total
windows_memory_available_bytes
windows_logical_disk_free_bytes
windows_os_info
windows_system_system_up_time
```

Con esto, el servidor Windows queda preparado para exponer sus métricas del sistema de manera centralizada, lo que permite su monitorización desde Prometheus en el servidor Gateway.

### 4.6. Automatización y Enfoque GitOps (Infraestructura como Código)

Para garantizar la inmutabilidad y replicabilidad del entorno, se ha adoptado una metodología GitOps utilizando **AWS CloudFormation**.

Toda la infraestructura descrita en los apartados anteriores (VPC, Subredes, Tablas de Rutas, Security Groups e Instancias EC2) está definida de forma declarativa en un único archivo YAML (`despliegue-tfg.yml`).

Adicionalmente, se ha implementado un aprovisionamiento de cero toques (**Zero-Touch Provisioning**) utilizando la propiedad `UserData`. Esto permite que, en el momento de crear la pila en AWS, las instancias ejecuten automáticamente sus configuraciones internas:

* El **Ubuntu Gateway** ejecuta un script bash en el arranque que habilita el reenvío de paquetes IP (`ip_forward`), establece las reglas de iptables (NAT, Port Forwarding y forwarding VPN→subred privada) y las hace persistentes mediante `iptables-persistent` y `netfilter-persistent`.
* El **Windows Server** ejecuta un script de PowerShell en el arranque que localiza la interfaz de red activa, le asigna la IP estática requerida para el Active Directory, configura los servidores DNS, añade una ruta estática hacia la subred VPN (`172.16.3.0/24`) a través del Gateway, y desactiva los perfiles del cortafuegos.

Esta aproximación elimina la necesidad de intervención manual inicial (SSH/RDP) para la configuración de red y previene errores humanos durante el despliegue del laboratorio.

### 4.7. Implementación de VPN con WireGuard

Para permitir el acceso remoto seguro de usuarios a la infraestructura desde fuera de AWS, se ha implementado una VPN basada en **WireGuard**. Esta solución permite que los usuarios se conecten a la red privada y accedan a los recursos del dominio Active Directory de forma segura.

#### Arquitectura de la VPN

| Componente | Descripción |
|------------|-------------|
| **Rango VPN** | `172.16.3.0/24` - Subred dedicada para clientes VPN (fuera del CIDR de la VPC) |
| **Puerto** | UDP 51820 - Puerto estándar de WireGuard |
| **DNS** | `10.0.2.75` - Controlador de dominio Active Directory |
| **Gateway** | Ubuntu Server actúa como servidor VPN y NAT |

La configuración permite que los clientes VPN accedan a:
- **Subred privada** (`10.0.2.0/24`): Windows Server, Active Directory y otros recursos internos
- **Subred VPN** (`172.16.3.0/24`): Comunicación entre clientes conectados

#### Instalación del servidor WireGuard

La instalación se realiza en el **Ubuntu Gateway**. Los pasos ejecutados fueron:

```bash
# Instalar WireGuard
sudo apt update && sudo apt install -y wireguard

# Generar claves del servidor
sudo wg genkey | sudo tee /etc/wireguard/privatekey | sudo wg pubkey | sudo tee /etc/wireguard/publickey
sudo chmod 600 /etc/wireguard/privatekey
```

#### Configuración del servidor

El archivo de configuración `/etc/wireguard/wg0.conf` define la interfaz VPN:

```ini
[Interface]
Address = 172.16.3.1/24
ListenPort = 51820
PrivateKey = <clave_privada_servidor>

# Peers (clientes) se añaden dinámicamente con el script de gestión
```

#### Reglas de firewall para VPN

Se han añadido las siguientes reglas iptables para permitir el tráfico VPN y el enrutamiento hacia la subred privada:

```bash
# NAT para tráfico VPN hacia la subred privada
sudo iptables -t nat -A POSTROUTING -s 172.16.3.0/24 -d 10.0.2.0/24 -j MASQUERADE

# Forwarding entre VPN y subred privada
sudo iptables -A FORWARD -s 172.16.3.0/24 -d 10.0.2.0/24 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.2.0/24 -d 172.16.3.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Persistir reglas
sudo netfilter-persistent save
```

Adicionalmente, el **Security Group de AWS** (`SG-Gateway`) debe permitir tráfico entrante en el puerto **UDP 51820** desde las IPs de origen autorizadas.

> **Nota importante:** Dado que la subred VPN (`172.16.3.0/24`) está fuera del CIDR de la VPC (`10.0.0.0/16`), es necesario añadir una ruta en la tabla de rutas de la subred privada que dirija el tráfico VPN hacia el Gateway. Esta ruta se define automáticamente en el template de CloudFormation mediante el recurso `VpnRoute`.

#### Inicio del servicio WireGuard

```bash
# Habilitar e iniciar el servicio
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Verificar estado
sudo wg show
```

#### Gestión de clientes VPN

Se ha desarrollado un script de automatización (`scripts/crear-cliente-vpn.sh`) que facilita la creación de nuevos clientes VPN. Este script:

1. **Genera claves** del cliente (pública y privada)
2. **Asigna una IP automática** dentro del rango `172.16.3.2-254`
3. **Registra el peer** en el servidor WireGuard
4. **Crea el archivo de configuración** listo para importar
5. **Configura el DNS** para apuntar al Active Directory

**Uso del script:**

```bash
# En el servidor Ubuntu Gateway
sudo ./crear-cliente-vpn.sh <nombre_cliente> [ip_elastica]

# Ejemplo
sudo ./crear-cliente-vpn.sh usuario1
sudo ./crear-cliente-vpn.sh portatil_juan 54.123.45.67
```

El script genera un archivo `.conf` en `/etc/wireguard/clients/` que debe ser transferido al dispositivo cliente e importado en la aplicación WireGuard.

#### Configuración de clientes

**Archivo de configuración del cliente (ejemplo):**

```ini
[Interface]
PrivateKey = <clave_privada_cliente>
Address = 172.16.3.2/24
DNS = 10.0.2.75

[Peer]
PublicKey = <clave_publica_servidor>
Endpoint = <IP_ELASTICA_GATEWAY>:51820
AllowedIPs = 10.0.2.0/24, 172.16.3.0/24
PersistentKeepalive = 25
```

| Parámetro | Descripción |
|-----------|-------------|
| `Address` | IP asignada al cliente en la VPN |
| `DNS` | Servidor DNS (Controlador de Dominio AD) |
| `Endpoint` | IP pública del Gateway y puerto WireGuard |
| `AllowedIPs` | Rutas que se envían a través de la VPN |
| `PersistentKeepalive` | Mantiene la conexión activa (útil tras NAT) |

#### Integración con Active Directory

Una vez conectado a la VPN, el cliente puede unirse al dominio **tfg.vp**:

1. **Verificar conectividad DNS:**
   ```bash
   nslookup tfg.vp 10.0.2.75
   ```

2. **Unirse al dominio (Windows):**
   - Configuración → Sistema → Acerca de → Unirse a un dominio
   - Introducir dominio: `tfg.vp`
   - Proporcionar credenciales de administrador del dominio

3. **Unirse al dominio (Linux):**
   ```bash
   sudo realm join tfg.vp -U administrador
   ```

#### Verificación de la conexión VPN

Para verificar clientes conectados desde el servidor:

```bash
# Ver peers activos
sudo wg show

# Salida esperada:
# interface: wg0
#   public key: (clave_del_servidor)
#   private key: (hidden)
#   listening port: 51820
#
# peer: (clave_publica_cliente)
#   endpoint: (IP_cliente):puerto
#   allowed ips: 172.16.3.2/32
```

#### Consideraciones de seguridad

- **Cifrado:** WireGuard utiliza criptografía moderna (ChaCha20, Curve25519, BLAKE2s)
- **Autenticación:** Basada en claves públicas/privadas
- **Punto único de entrada:** Todo el tráfico pasa por el Gateway Ubuntu
- **DNS:** Resolución de nombres a través del Active Directory
- **Acceso restringido:** Los clientes VPN solo pueden acceder a las subredes permitidas

### 4.8. Implementación de Node Exporter para Monitorización de Ubuntu

Para monitorizar el servidor Ubuntu Gateway, se ha instalado **Node Exporter**, una herramienta que expone métricas del sistema operativo Linux en un formato compatible con Prometheus.

Node Exporter recopila información del sistema como el uso de CPU, memoria, disco y red, y la expone a través de un endpoint HTTP en el puerto 9100.

#### Instalación de Node Exporter

La instalación se realizó desde los repositorios de Ubuntu:

```bash
sudo apt update
sudo apt install -y prometheus-node-exporter
sudo systemctl enable prometheus-node-exporter
sudo systemctl start prometheus-node-exporter
```

#### Verificación del servicio

Para verificar que Node Exporter está funcionando correctamente:

```bash
sudo systemctl status prometheus-node-exporter
curl http://localhost:9100/metrics
```

El servicio expone métricas en formato de texto que pueden ser consultadas desde `http://localhost:9100/metrics`.

#### Métricas disponibles

| Métrica | Descripción |
|---------|-------------|
| `node_cpu_seconds_total` | Tiempo de CPU por modo |
| `node_memory_MemAvailable_bytes` | Memoria disponible |
| `node_memory_MemTotal_bytes` | Memoria total |
| `node_filesystem_avail_bytes` | Espacio disponible en disco |
| `node_filesystem_size_bytes` | Tamaño total del sistema de archivos |
| `node_network_receive_bytes_total` | Bytes recibidos por red |
| `node_network_transmit_bytes_total` | Bytes transmitidos por red |

### 4.9. Implementación de Prometheus para Recolección de Métricas

Prometheus es el sistema de monitorización centralizado que recopila métricas de todos los servidores de la infraestructura y las almacena en una base de datos temporal.

#### Instalación de Prometheus

La instalación se realizó desde los repositorios de Ubuntu:

```bash
sudo apt install -y prometheus
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

#### Configuración de Targets

El archivo de configuración `/etc/prometheus/prometheus.yml` define los objetivos de recolección:

```yaml
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: node
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'windows-server'
    static_configs:
      - targets: ['10.0.2.75:9182']
```

| Target | Descripción | Puerto |
|--------|-------------|--------|
| `prometheus` | Métricas de Prometheus | 9090 |
| `node` | Métricas de Ubuntu Gateway | 9100 |
| `windows-server` | Métricas de Windows Server | 9182 |

> **Nota sobre intervalos de recolección:** El job `prometheus` tiene configurado un `scrape_interval` de 5s para la automonitorización del propio servidor. Los jobs `node` y `windows-server` utilizan el intervalo por defecto de 1 minuto. Este diseño es deliberado: dadas las limitaciones de recursos de las instancias (t3.micro para el Gateway y t3.small para Windows Server), un intervalo de 1 minuto proporciona suficiente granularidad para las consultas `rate(...[5m])` del dashboard y las reglas de alerta, sin comprometer la estabilidad del sistema.

#### Reglas de Alerta

Se han configurado las siguientes reglas de alerta en `/etc/prometheus/alert_rules.yml`:

| Regla | Descripción | Umbral |
|-------|-------------|--------|
| `InstanceDown` | Servidor caído | 1 minuto sin respuesta |
| `HighCPU` | Uso de CPU elevado | >80% durante 5 minutos |
| `HighMemory` | Uso de memoria elevado | >85% durante 5 minutos |
| `DiskSpaceLow` | Espacio de disco bajo | >85% de uso durante 5 minutos |

#### Verificación de Targets

Para verificar que Prometheus está recolectando métricas correctamente:

```bash
curl http://localhost:9090/api/v1/targets | python3 -m json.tool
```

Cada target debe mostrar `"health": "up"` en su estado.

### 4.10. Implementación de Grafana para Visualización

Grafana proporciona una interfaz web para visualizar las métricas recolectadas por Prometheus mediante dashboards personalizables.

#### Instalación de Grafana

Se instaló desde el repositorio oficial de Grafana:

```bash
sudo apt install -y apt-transport-https software-properties-common wget
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

#### Acceso a Grafana

| Parámetro | Valor |
|-----------|-------|
| **URL** | `http://<IP_ELASTICA_GATEWAY>:3000` |
| **Usuario por defecto** | `admin` |
| **Contraseña por defecto** | `admin` |

Se recomienda cambiar la contraseña en el primer acceso.

#### Configuración de Data Source

Para conectar Grafana con Prometheus:

1. Acceder a **Configuration** → **Data Sources**
2. Añadir nuevo data source tipo **Prometheus**
3. Configurar URL: `http://localhost:9090`
4. Guardar y probar conexión

#### Dashboard Recomendado

Se recomienda importar el dashboard **Node Exporter Full** (ID: 1860) desde Grafana:

1. **Dashboards** → **Import**
2. Introducir ID: `1860`
3. Seleccionar data source: Prometheus
4. Importar

Este dashboard proporciona una vista completa de las métricas del sistema Ubuntu.

#### Dashboard de Windows Server

Se configuró un dashboard específico en Grafana para visualizar el estado del Windows Server. El dashboard se adaptó a las métricas reales expuestas por Windows Exporter y al datasource Prometheus disponible en el entorno.

**Adaptación del dashboard:**

Se tomó una plantilla de dashboard de Windows Exporter y se corrigieron las consultas PromQL para ajustarlas a las métricas que realmente expone el servidor Windows, evitando paneles con errores, valores vacíos o consultas incompatibles con el exporter instalado. También se eliminó la dependencia de un UID fijo en el datasource para hacer el dashboard más portable entre instalaciones de Grafana.

**Métricas utilizadas:**

| Métrica | Descripción |
|---------|-------------|
| `windows_cpu_time_total` | Tiempo de CPU por modo |
| `windows_os_physical_memory_free_bytes` | Memoria física libre |
| `windows_os_visible_memory_bytes` | Memoria física total visible |
| `windows_logical_disk_free_bytes` | Espacio libre en disco |
| `windows_logical_disk_size_bytes` | Tamaño total del disco |
| `windows_net_bytes_sent_total` | Bytes enviados por red |
| `windows_net_bytes_received_total` | Bytes recibidos por red |
| `windows_os_processes` | Número de procesos |
| `windows_system_threads` | Número de hilos del sistema |
| `windows_system_system_up_time` | Tiempo de actividad del sistema |
| `windows_os_time` | Hora del sistema |
| `windows_system_processor_queue_length` | Longitud de cola del procesador |
| `windows_service_state` | Estado de los servicios del sistema |

**Consultas PromQL recomendadas:**

Uso de CPU:

```promql
100 * (1 - avg(rate(windows_cpu_time_total{instance=~"$server",mode="idle"}[5m])))
```

Uso de memoria:

```promql
100 * (1 - windows_os_physical_memory_free_bytes{instance=~"$server"} / windows_os_visible_memory_bytes{instance=~"$server"})
```

Uso de disco:

```promql
100 - (windows_logical_disk_free_bytes{instance=~"$server",volume!~"HarddiskVolume.+"} / windows_logical_disk_size_bytes{instance=~"$server",volume!~"HarddiskVolume.+"}) * 100
```

Tráfico de red (envío):

```promql
rate(windows_net_bytes_sent_total{instance=~"$server"}[5m]) * 8
```

Tráfico de red (recepción):

```promql
rate(windows_net_bytes_received_total{instance=~"$server"}[5m]) * 8
```

Número de procesos:

```promql
windows_os_processes{instance=~"$server"}
```

Hilos del sistema:

```promql
windows_system_threads{instance=~"$server"}
```

Tiempo activo del sistema:

```promql
time() - windows_system_system_up_time{instance=~"$server"}
```

Desfase horario aproximado:

```promql
abs(time() - windows_os_time{instance=~"$server"})
```

Cola de procesador:

```promql
windows_system_processor_queue_length{instance=~"$server"}
```

**Visualizaciones recomendadas:**

| Tipo de panel | Métricas recomendadas |
|---------------|----------------------|
| Stat | CPU, memoria, procesos, hilos, uptime, desfase horario |
| Gauge | Memoria, uso de disco |
| Bar gauge | Uso de discos por partición, estado de servicios |
| Time series | Tráfico de red, CPU histórica, memoria histórica, disco histórica, presión de procesador |

**Problemas detectados y corregidos:**

1. **Fuentes de datos con UID fijo:** Se eliminó la dependencia de un UID fijo para hacer el dashboard más portable entre instalaciones de Grafana.
2. **Consultas no compatibles con Windows Exporter:** Se sustituyeron consultas procedentes de Node Exporter o de otros entornos Linux por equivalentes válidos para Windows.
3. **Valores mostrados como N/A o No data:** Se corrigieron paneles que dependían de métricas inexistentes en el exporter instalado o de expresiones PromQL incorrectas.
4. **Unidades incorrectas:** Se ajustaron las unidades de los paneles para mostrar porcentaje, bytes, segundos o bits por segundo según la naturaleza de cada métrica.

**Métricas descartadas:**

Las siguientes métricas fueron eliminadas del dashboard por no estar disponibles en Windows Exporter o pertenecer a otros exporters:

- `windows_cs_physical_memory_bytes` (no disponible en la versión instalada)
- `windows_process_thread_count` (métrica inexistente)
- `windows_time_computed_time_offset_seconds` (métrica inexistente)
- `windows_process_start_time` (métrica inexistente)

### 4.11. Implementación de Alertmanager para Notificaciones

Alertmanager gestiona las alertas generadas por Prometheus y las envía a través de diferentes canales de notificación.

#### Instalación de Alertmanager

La versión inicial instalada desde repositorios era la 0.23.0, pero se actualizó a la versión 0.28.1 para soportar notificaciones de Telegram nativas:

```bash
# Descargar versión 0.28.1
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz
tar xvf alertmanager-0.28.1.linux-amd64.tar.gz

# Detener servicio
sudo systemctl stop prometheus-alertmanager

# Reemplazar binario
sudo cp /tmp/alertmanager-0.28.1.linux-amd64/alertmanager /usr/bin/prometheus-alertmanager

# Crear directorio de datos
sudo mkdir -p /var/lib/prometheus/alertmanager
sudo chown -R prometheus:prometheus /var/lib/prometheus/alertmanager

# Iniciar servicio
sudo systemctl start prometheus-alertmanager
```

#### Configuración del servicio

El archivo `/etc/default/prometheus-alertmanager` debe contener:

```bash
ARGS="--storage.path=/var/lib/prometheus/alertmanager --config.file=/etc/prometheus/alertmanager.yml"
```

#### Configuración de Telegram

El archivo `/etc/prometheus/alertmanager.yml` configura las notificaciones:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: telegram-notifications

receivers:
  - name: telegram-notifications
    telegram_configs:
      - bot_token: 'TU_BOT_TOKEN'
        chat_id: TU_CHAT_ID
        parse_mode: HTML

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['alertname', 'instance']
```

#### Creación del Bot de Telegram

Para configurar las notificaciones por Telegram:

1. **Crear un bot:** Abrir [@BotFather](https://t.me/botfather) en Telegram y ejecutar `/newbot`
2. **Obtener el token:** Guardar el token proporcionado (ej: `1234567890:ABCdef...`)
3. **Crear un grupo:** Crear un grupo de Telegram para recibir alertas
4. **Añadir el bot:** Añadir el bot al grupo como administrador
5. **Obtener el Chat ID:** Acceder a `https://api.telegram.org/bot<TOKEN>/getUpdates` y buscar el campo `chat.id`
6. **Configurar en Alertmanager:** Añadir el token y Chat ID en `/etc/prometheus/alertmanager.yml`

#### Prueba de Alertas

Para enviar una alerta de prueba:

```bash
amtool alert add prueba severity=critical --annotation=summary="Alerta de prueba" --annotation=description="Prueba desde TFG" --alertmanager.url=http://localhost:9093
```

La alerta debe llegar al grupo de Telegram configurado.

#### Ejemplo de alerta recibida

A continuación se muestra un ejemplo real de una alerta recibida en Telegram cuando el servidor Windows deja de responder:

![Alerta de Windows Server caído](imagenes/Alerta-WindowsServer-Caido.png)

*Ejemplo de alerta `InstanceDown` recibida en Telegram indicando que el servidor Windows (10.0.2.75:9182) está caído.*

#### Verificación del Estado

Para verificar que Alertmanager está funcionando:

```bash
sudo systemctl status prometheus-alertmanager
curl http://localhost:9093/api/v2/status | python3 -m json.tool
```

#### Estado de las Notificaciones

| Canal | Estado | Notas |
|-------|--------|-------|
| Telegram | ✓ Funcional | Configurado con bot token y Chat ID |
| Discord | ⏳ Pendiente | Requiere servicio intermedio para formato JSON |

**Discord:** La integración con Discord se deja pendiente para futuras implementaciones. Discord requiere un servicio intermedio que transforme el formato de alertas de Alertmanager al formato JSON esperado (`{"content": "mensaje"}`). Posibles soluciones incluyen crear un servicio web intermedio o utilizar herramientas como [Prometheus Discord Webhook](https://github.com/benjojo/alertmanager-discord).

#### Archivos de Configuración

Los archivos de configuración de ejemplo están disponibles en el directorio `configs/` del repositorio:

| Archivo | Descripción |
|---------|-------------|
| `configs/prometheus.yml.example` | Configuración de Prometheus |
| `configs/alert_rules.yml` | Reglas de alerta |
| `configs/alertmanager.yml.example` | Configuración de Alertmanager |
| `configs/prometheus-alertmanager.defaults` | Variables de entorno de Alertmanager |

### 4.12. Incidencias durante la implantación

Durante el despliegue de la infraestructura se encontraron y resolvieron diversas incidencias técnicas:

| Incidencia | Descripción | Solución | Fecha |
|------------|-------------|----------|-------|
| Windows Exporter no accesible | Prometheus no podía conectar con el puerto 9182 del Windows Server | Añadir regla en Security Group de AWS para permitir tráfico desde el Gateway | Marzo |
| Alertmanager no iniciaba | Error "permission denied" al crear directorio de datos | Crear directorio `/var/lib/prometheus/alertmanager` con permisos correctos | Marzo |
| Alertmanager versión antigua | La versión 0.23.0 no soportaba `telegram_configs` | Actualizar a versión 0.28.1 manualmente | Marzo |
| Discord no recibe alertas | Formato de mensaje incompatible con Discord webhook | Pendiente - requiere servicio intermedio para transformar JSON | Marzo |
| Clientes VPN no conectan con AD | La subred VPN original (`10.0.3.0/24`) estaba dentro del CIDR de la VPC (`10.0.0.0/16`), impidiendo que AWS enrutara tráfico de respuesta hacia clientes VPN | Cambiar subred VPN a `172.16.3.0/24` (fuera del CIDR de la VPC), añadir ruta VPN en RouteTable privada, reglas iptables de forwarding y NAT VPN→subred privada | Abril |

#### Lecciones aprendidas

1. **Security Groups:** Es importante verificar que todos los puertos necesarios estén abiertos en los Security Groups de AWS antes de desplegar servicios que requieren comunicación entre instancias.

2. **Versiones de software:** Las versiones de los paquetes de repositorios pueden estar desactualizadas. Es recomendable verificar la compatibilidad de características específicas (como `telegram_configs` en Alertmanager) antes de la instalación.

3. **Documentación:** Mantener un registro de las incidencias facilita la resolución de problemas similares en futuros despliegues y mejora la replicabilidad del entorno.

4. **Subredes VPN y CIDR de VPC:** Al configurar una subred VPN en AWS, esta no debe estar dentro del CIDR de la VPC. Si lo está, AWS no permite añadir rutas específicas en las tablas de rutas, ya que las considera tráfico local. Esto impide que las instancias de la VPC puedan responder a los clientes VPN. La subred VPN debe usar un rango CIDR externo a la VPC.

### 4.13. Configuración avanzada de Active Directory

Tras la implementación inicial del controlador de dominio, se realizó una configuración avanzada para estructurar correctamente el directorio activo y aplicar políticas de seguridad.

#### Estado actual del dominio

| Parámetro | Valor |
|-----------|-------|
| Dominio | `tfg.vp` |
| Nombre NetBIOS | `TFG` |
| Nivel funcional del dominio | Windows Server 2016 |
| Nivel funcional del bosque | Windows Server 2016 |
| DNS integrado | Habilitado |
| Catálogo global | Habilitado |
| Credenciales de administrador | `TFG\Administrator` |

#### Estructura de Unidades Organizativas (OU)

Se creó una estructura de Unidades Organizativas para organizar los objetos del directorio de manera lógica:

```
TFG
├── Usuarios
├── Equipos
├── Servidores
├── Grupos
└── Admins
```

**Nota:** Los contenedores y grupos por defecto del dominio (`Users`, `Domain Admins`, `Domain Users`, etc.) no se movieron ni modificaron para evitar errores en el dominio.

#### Grupos de seguridad

Se aplicó el modelo **AGDLP** (Accounts → Global Groups → Domain Local → Permissions), que es una práctica recomendada para la gestión de permisos en Active Directory:

| Tipo de grupo | Prefijo | Ejemplos | Función |
|---------------|---------|----------|---------|
| Grupos Globales (GG_) | `GG_` | `GG_Usuarios`, `GG_Admins` | Agrupan usuarios según función |
| Grupos Domain Local (DL_) | `DL_` | Por definir | Asignación de permisos a recursos |

**Principio AGDLP:**
1. Los **usuarios** se agregan a los **Grupos Globales (GG_)**
2. Los **Grupos Globales** se agregan a los **Grupos Domain Local (DL_)**
3. Los **permisos** se asignan a los **Grupos Domain Local**

Esta estructura permite una gestión de permisos escalable y facilita la administración de recursos.

#### GPO implementadas

Se crearon y vincularon a las OUs correspondientes las siguientes políticas de grupo:

| GPO | OU aplicada | Configuración principal |
|-----|-------------|------------------------|
| `GPO_Seguridad_Contraseñas` | Dominio | Longitud mínima 8-12 caracteres, complejidad habilitada, historial de contraseñas |
| `GPO_Seguridad_Equipos` | OU Equipos | Firewall activado para Domain/Private/Public Profiles, bloqueo de conexiones entrantes no autorizadas |

**Configuración de la GPO de contraseñas:**
- Longitud mínima: 8 caracteres
- Complejidad: habilitada (mayúsculas, minúsculas, números, símbolos)
- Historial: 24 contraseñas recordadas
- Caducidad: opcional según política organizativa

**Configuración de la GPO de firewall:**
- Perfiles Domain, Private y Public: activados
- Bloqueo de conexiones entrantes: habilitado
- Excepciones: puertos necesarios para AD (88/TCP Kerberos, 389/TCP LDAP, etc.)

> **Nota sobre el firewall del servidor AD:** El firewall de Windows en el controlador de dominio permanece desactivado intencionadamente. La seguridad perimetral está garantizada por capas superiores:
> - Security Groups de AWS que filtran todo el tráfico a nivel de red
> - iptables en el Gateway Ubuntu actuando como firewall perimetral
> - El servidor reside en una subred privada sin acceso directo desde Internet
> 
> La GPO `GPO_Seguridad_Equipos` aplica a **equipos clientes** que se unan al dominio corporativo (por ejemplo, portátiles conectados vía VPN), donde sí es necesario mantener el firewall activado para proteger los dispositivos individuales.

#### Observaciones y buenas prácticas

1. **Contenedores por defecto:** Se mantuvieron los grupos por defecto del dominio en el contenedor `Users` sin modificaciones, evitando problemas de herencia y permisos.

2. **Separación de OUs:** Se crearon OUs específicas para separar usuarios, equipos, servidores y grupos, facilitando la aplicación de GPOs específicas.

3. **Convención de nombres:** Se siguió la convención profesional para grupos de seguridad (`GG_` para globales, `DL_` para domain local), mejorando la legibilidad y mantenibilidad.

4. **Política de firewall:** Se aplicó una política de firewall básica para proteger todos los equipos del dominio, permitiendo únicamente el tráfico necesario para el funcionamiento de Active Directory.

5. **Modelo AGDLP:** La implementación del modelo AGDLP permite una gestión de permisos granular y escalable, separando la agrupación de usuarios de la asignación de permisos.

### 4.14. Auditoría de seguridad y Sysmon

Con el objetivo de reforzar la trazabilidad del Windows Server, se habilitaron políticas de auditoría del sistema y se instaló **Sysmon** como herramienta complementaria de monitorización de eventos avanzados.

#### Políticas de auditoría activadas

Se habilitaron las siguientes directivas de auditoría mediante **GPO del dominio**:

- Audit logon events
- Audit account logon events
- Audit account management
- Audit policy change
- Audit object access
- Audit process tracking

Además, se configuraron las siguientes categorías de auditoría avanzada dentro de la GPO, en **Computer Configuration > Windows Settings > Security Settings > Advanced Audit Policy Configuration**:

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

Sysmon se instaló para ampliar la capacidad de análisis de procesos, conexiones y actividad sospechosa en el servidor. La instalación se realizó utilizando un fichero de configuración XML con reglas de filtrado y detección:

```powershell
# Descargar Sysmon desde Microsoft Sysinternals
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "C:\Sysmon.zip"
Expand-Archive -Path "C:\Sysmon.zip" -DestinationPath "C:\Sysmon"

# Instalar Sysmon con configuración XML
cd C:\Sysmon
sysmon64.exe -accepteula -i sysmonconfig.xml
```

> **Nota:** Para que la instalación funcione correctamente, el fichero `sysmonconfig.xml` debe estar en la misma carpeta que `sysmon64.exe` o indicarse con ruta completa.
