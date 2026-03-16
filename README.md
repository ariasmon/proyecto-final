# TFG: Despliegue de Infraestructura de Red Segura Híbrida en AWS con Monitorización Centralizada
**Proyecto de Víctor Alberjón Hidalgo y Pablo Arias Montilla**

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

### 1.3. Recursos identificados (Actualizado)
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

---

## 3. Diseño de la solución

### 3.1. Arquitectura de Red y Topología (AWS VPC)
* **VPC CIDR:** `10.0.0.0/16`
* **Subred Pública (DMZ):** `10.0.1.0/24`. Aloja el Gateway Ubuntu con IP Elástica.
* **Subred Privada (Intranet):** `10.0.2.0/24`. Aloja el Windows Server. Su tráfico `0.0.0.0/0` apunta a la interfaz de red del Ubuntu.

### 3.2. Diseño de Seguridad y Accesos
1. **SG-Gateway (Ubuntu):** Inbound: 22 (SSH), 3389 (RDP Forward), 3000 (Grafana). Outbound: Todo permitido.
2. **SG-Internal (Windows):** Inbound: 3389 (RDP) e ICMP (Ping) solo desde el SG-Gateway. Outbound: Todo permitido hacia el Gateway.

---

## 4. Implantación y configuración

### 4.1. Despliegue de Infraestructura Base en AWS
1. **IP Elástica:** Asociada al Ubuntu para mantener un punto de acceso administrativo fijo.
2. **IP Estática Windows:** Configurada como `10.0.2.75` para evitar desincronización de servicios internos.
3. **Source/Destination Check:** Desactivado en la instancia Ubuntu para permitir el funcionamiento del NAT.

### 4.2. Configuración del Enrutamiento y NAT en Linux
```bash
# Habilitar IP Forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Configuración de NAT (Masquerade)
sudo iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o ens5 -j MASQUERADE

# Reenvío de puerto RDP (DNAT)
sudo iptables -t nat -A PREROUTING -p tcp --dport 3389 -j DNAT --to-destination 10.0.2.75:3389

# Persistencia de reglas
sudo apt update && sudo apt install iptables-persistent -y
sudo netfilter-persistent save
```
### 4.3. Configuración del Servidor Interno (Windows Server)
Para garantizar la estabilidad operativa y la conectividad a través del Gateway, se han realizado las siguientes configuraciones críticas:

1. **Optimización de Instancia:** Migración del servidor a una instancia de familia **`t3.small`** (2 vCPU, 2GB RAM).
2. **Configuración de Red Estática:** Direccionamiento IPv4 fijado en `10.0.2.75`, Gateway en `10.0.2.1` y DNS apuntando a `127.0.0.1` y `8.8.8.8`.
3. **Gestión del Firewall:** Desactivación del cortafuegos de Windows mediante PowerShell (`Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`).

### 4.4. Automatización y Enfoque GitOps (Infraestructura como Código)
Para garantizar la inmutabilidad y replicabilidad del entorno, se ha adoptado una metodología GitOps utilizando **AWS CloudFormation**. 

Toda la infraestructura descrita en los apartados anteriores (VPC, Subredes, Tablas de Rutas, Security Groups e Instancias EC2) está definida de forma declarativa en un único archivo YAML (`despliegue-tfg.yaml`).

Adicionalmente, se ha implementado un aprovisionamiento de cero toques (**Zero-Touch Provisioning**) utilizando la propiedad `UserData`. Esto permite que, en el momento de crear la pila en AWS, las instancias ejecuten automáticamente sus configuraciones internas:
* El **Ubuntu Gateway** ejecuta un script bash en el arranque que habilita el reenvío de paquetes IP (`ip_forward`) y establece las reglas de iptables (NAT y Port Forwarding) haciéndolas persistentes.
* El **Windows Server** ejecuta un script de PowerShell en el arranque que localiza la interfaz de red activa, le asigna la IP estática requerida para el Active Directory, configura los servidores DNS y desactiva los perfiles del cortafuegos.

Esta aproximación anula la necesidad de intervención manual inicial (SSH/RDP) para la configuración de red y previene errores humanos durante el despliegue del laboratorio.

---

## 5. Trabajo pendiente

### 5.1. Implementación de Active Directory
- Instalar rol de AD DS en Windows Server.
- Promocionar el servidor como controlador de dominio.
- Crear estructura de unidades organizativas (OU).
- Configurar políticas de grupo (GPO) básicas.

### 5.2. Configuración de VPN con WireGuard
- Instalar WireGuard en el Gateway Ubuntu.
- Generar claves y configurar interfaz VPN.
- Configurar clientes para acceso remoto.
- Integrar reglas de firewall para tráfico VPN.
- Documentar proceso de conexión para usuarios finales.
