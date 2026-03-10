# TFG: Despliegue de Infraestructura de Red Segura Híbrida en AWS con Monitorización Centralizada
**Proyecto de Víctor Alberjón Hidalgo y Pablo Arias Montilla**

## 1. Planificación inicial
En esta fase se establecen las bases del proyecto, definiendo el alcance, los recursos necesarios y las restricciones que guiarán el desarrollo.

### 1.1. Objetivo
El objetivo principal es diseñar e implantar una infraestructura de red segura en la nube pública (AWS), utilizando una arquitectura de Gateway Linux (Ubuntu) para proteger y enrutar el tráfico de una subred privada donde reside un servidor Windows. Adicionalmente, se busca implementar un sistema de observabilidad que centralice la monitorización de tráfico y recursos de ambos servidores, integrando mecanismos de alerta temprana ante fallos críticos.

### 1.2. Alcance del proyecto
El proyecto contempla la ejecución de las siguientes tareas clave:
* **Despliegue de Red (VPC):** Configuración de una nube privada virtual segmentada en subredes pública (DMZ) y privada (Intranet).
* **Servidor de Borde (Ubuntu Server):** Configuración como NAT Instance, seguridad perimetral (iptables) y despliegue de stack de monitorización (Prometheus + Grafana).
* **Servidor Interno (Windows Server):** Aislamiento de red (sin IP pública directa) y configuración de servicios internos.
* **Gestión y Acceso:** Acceso remoto seguro mediante SSH y RDP (vía Port Forwarding en el Gateway).
* **Interconexión y Visibilidad:** Configuración de tablas de rutas para forzar el tráfico a través del Gateway.

### 1.3. Recursos identificados (Actualizado)
* **Infraestructura (AWS EC2):**
    * 1x Instancia **t3.micro** (Ubuntu Server 22.04 LTS) + **IP Elástica**.
    * 1x Instancia **t3.small** (Windows Server 2022). *Nota: Se aumentó de micro a small para garantizar la estabilidad del sistema.*
* **Software y Servicios:**
    * Red: IPTables, VPC Routing.
    * Monitorización: Prometheus, Grafana, Alertmanager, Node Exporter, Windows Exporter.

### 1.4. Restricciones y condicionantes
* **Económicas:** Viabilidad dentro de la capa gratuita (Free Tier) de AWS siempre que sea posible.
* **Seguridad:** Administración a través de puertos estándar (22 y 3389) protegidos por Security Groups.
* **Plazos:** Despliegue funcional antes de la fecha de defensa del TFG.

### 1.6. Cronograma preliminar
| Fase | Tarea Principal | Semanas | Descripción |
| :--- | :--- | :--- | :--- |
| Fase 1 | Planificación | 1 - 2 | Definición de alcance y estudio de viabilidad. |
| Fase 2 | Diseño | 3 - 4 | Diagramas de red VPC y políticas de seguridad. |
| Fase 3 | Despliegue Infra | 5 - 6 | Creación de VPC, subredes y lanzamiento de instancias. |
| Fase 4 | Configuración | 7 - 8 | Configuración de NAT, Firewall y Monitorización. |
| Fase 5 | Accesos | 9 | Habilitación de SSH y RDP mediante Port Forwarding. |
| Fase 6 | Validación | 10 | Pruebas de conectividad y estrés. |
| Fase 7 | Documentación | 11 - 12 | Redacción final de la memoria y defensa. |

---

## 2. Análisis de requisitos

### 2.1. Requisitos Funcionales (RF)
* **RF-01 (Enrutamiento NAT):** El servidor Ubuntu debe actuar como puerta de enlace para la subred privada.
* **RF-03 (Seguridad de Red):** Gestión del tráfico mediante firewall permitiendo solo administración autorizada.
* **RF-04 (Monitorización de Tráfico):** Captura de métricas de ancho de banda en la interfaz del Gateway.
* **RF-05 (Dashboard Unificado):** Grafana debe mostrar el estado de recursos de ambos servidores.
* **RF-07 (Gestión de Alertas):** Notificaciones en tiempo real (Telegram/Discord) ante anomalías críticas.
* **RF-08 (Acceso Remoto):** Garantizar acceso administrativo vía SSH (22) y RDP (3389).

### 2.2. Requisitos No Funcionales (RNF)
* **RNF-01 (Aislamiento):** La instancia Windows debe residir en una subred privada sin IP pública directa.
* **RNF-03 (Disponibilidad):** Los servicios de enrutamiento deben iniciarse automáticamente (systemd).

---

## 3. Diseño de la solución

### 3.1. Arquitectura de Red y Topología (AWS VPC)
* **VPC CIDR:** `10.0.0.0/16`
* **Subred Pública (DMZ):** `10.0.1.0/24`. Aloja el Gateway Ubuntu con IP Elástica.
* **Subred Privada (Intranet):** `10.0.2.0/24`. Aloja el Windows Server. Su tráfico `0.0.0.0/0` apunta a la interfaz de red del Ubuntu.

### 3.3. Diseño de Seguridad y Accesos
1. **SG-Gateway (Ubuntu):** Inbound: 22 (SSH), 3389 (RDP Forward), 3000 (Grafana). Outbound: Todo permitido.
2. **SG-Internal (Windows):** Inbound: 3389 (RDP) e ICMP (Ping) solo desde el SG-Gateway. Outbound: Todo permitido hacia el Gateway.

---

## 4. Implantación y configuración

### 4.1. Despliegue de Infraestructura Base en AWS
1. **IP Elástica:** Asociada al Ubuntu para mantener un punto de acceso administrativo fijo.
2. **IP Estática Windows:** Configurada manualmente como `10.0.2.75` para evitar desincronización de servicios internos.
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

1. **Optimización de Instancia:**
   * Migración del servidor a una instancia de familia **`t3.small`** (2 vCPU, 2GB RAM). Esta actualización técnica asegura que el sistema operativo disponga de recursos suficientes para ejecutar procesos de red y servicios de fondo sin degradación de rendimiento.

2. **Configuración de Red Estática:**
   * **Direccionamiento IPv4:** Se ha fijado manualmente la IP `10.0.2.75` con máscara de subred `255.255.255.0`.
   * **Puerta de enlace (Gateway):** Se ha establecido la dirección `10.0.2.1`. Esta configuración permite que el tráfico sea gestionado por el enrutador virtual de la VPC y derivado al Gateway Ubuntu según la tabla de rutas privada definida en AWS.
   * **Servidores DNS:** Se han configurado `127.0.0.1` y `8.8.8.8` para garantizar la resolución de nombres local y externa durante la fase de despliegue.

3. **Seguridad y Acceso:**
   * **Gestión del Firewall:** Se ha desactivado el cortafuegos de Windows mediante PowerShell para evitar bloqueos en la comunicación interna con el Gateway y permitir la entrada de tráfico RDP redirigido.
     * Comando utilizado: `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`
   * **Validación de Conectividad:** Se ha confirmado mediante pruebas de navegación y respuesta ICMP que el servidor tiene salida total a Internet a través del NAT configurado en el Ubuntu, validando así la arquitectura de red híbrida.
