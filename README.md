# TFG: Despliegue de Infraestructura de Red Segura Híbrida en AWS con Monitorización Centralizada

### Proyecto de Víctor Alberjón Hidalgo y Pablo Arias Montilla

## 1. Planificación inicial

En esta fase se establecen las bases del proyecto, definiendo el alcance, los recursos necesarios y las restricciones que guiarán el desarrollo.

### 1.1. Objetivo
El objetivo principal es diseñar e implantar una infraestructura de red segura en la nube pública (AWS), utilizando una arquitectura de **Gateway Linux** (Ubuntu) para proteger y enrutar el tráfico de una subred privada donde reside un **Controlador de Dominio Windows**. Adicionalmente, se busca implementar un sistema de observabilidad que centralice la monitorización de tráfico y recursos de ambos servidores, integrando mecanismos de alerta temprana ante fallos críticos.

### 1.2. Alcance del proyecto
El proyecto contempla la ejecución de las siguientes tareas clave:

* **Despliegue de Red (VPC):** Configuración de una nube privada virtual segmentada en subredes pública (DMZ) y privada (Intranet).
* **Servidor de Borde (Ubuntu Server):**
    * Configuración como **NAT Instance** para enrutamiento de paquetes.
    * Implementación de seguridad perimetral mediante Firewall (UFW/iptables).
    * Despliegue de stack de monitorización (Prometheus + Grafana).
    * **Configuración de Alertmanager:** Integración de notificaciones automáticas a plataformas externas (Telegram/Discord) ante incidentes críticos.
* **Servidor Interno (Windows Server):**
    * Promoción a Controlador de Dominio (Active Directory DS).
    * Aislamiento de red (sin IP pública directa).
* **Gestión y Acceso:**
    * Configuración de acceso remoto para administración mediante protocolos estándar (SSH para Linux y RDP para Windows).
    * Configuración de reglas de reenvío (Port Forwarding) o Bastion en el Gateway para permitir el acceso RDP al servidor interno.
* **Interconexión y Visibilidad:** Configuración de tablas de rutas para forzar el tráfico a través del Gateway y visualización de métricas en tiempo real.

### 1.3. Recursos identificados
Para llevar a cabo el proyecto se han identificado los siguientes recursos:

* **Infraestructura (AWS EC2):**
    * 1x Instancia `t2.micro` (Ubuntu Server 22.04 LTS).
    * 1x Instancia `t2.micro` o `t3.micro` (**Windows Server 2022**).
* **Software y Servicios:**
    * **Sistemas Operativos:** Linux y Windows Server.
    * **Red:** IPTables, UFW, VPC Routing.
    * **Monitorización y Alertas:** Prometheus, Grafana, Alertmanager, Node Exporter, Windows Exporter.
* **Personal:** 1 Técnico Administrador de Sistemas.

### 1.4. Restricciones y condicionantes
El proyecto debe adherirse a las siguientes limitaciones:

* **Económicas:** El proyecto debe ser viable dentro de la capa gratuita (*Free Tier*) de AWS.
* **Seguridad y Acceso:** La administración remota se realizará a través de los puertos estándar (22 y 3389). Se deben aplicar reglas de seguridad (Security Groups) para restringir el acceso a IPs autorizadas siempre que sea posible.
* **Plazos:** El despliegue funcional debe estar listo antes de la fecha de defensa del TFG.

### 1.5. Documentos generados
* Documento de alcance del proyecto.
* Cronograma preliminar de fases.

### 1.6. Cronograma preliminar
Para garantizar el cumplimiento de los objetivos en el plazo establecido, se ha diseñado una planificación temporal dividida en semanas de trabajo. La estimación total del proyecto es de **12 semanas**, cubriendo desde la investigación inicial hasta la defensa del TFG.

| Fase | Tarea Principal | Semanas Estimadas | Descripción |
| :--- | :--- | :---: | :--- |
| **Fase 1** | Planificación y Análisis | 1 - 2 | Definición de alcance, requisitos y estudio de viabilidad en AWS Free Tier. |
| **Fase 2** | Diseño de la Solución | 3 - 4 | Elaboración de diagramas de red (VPC), diseño de direccionamiento IP y políticas de seguridad (Security Groups). |
| **Fase 3** | Despliegue de Infraestructura | 5 - 6 | Creación de VPC, subredes, tablas de enrutamiento y lanzamiento de instancias EC2 (Ubuntu y Windows). |
| **Fase 4** | Configuración de Servicios | 7 - 8 | Configuración de NAT, Active Directory, Prometheus, Grafana y **Alertmanager**. |
| **Fase 5** | Configuración de Accesos | 9 | Habilitación y securización de servicios SSH y RDP (reglas de firewall y reenvío de puertos). |
| **Fase 6** | Pruebas y Validación | 10 | Ejecución del plan de pruebas (conectividad, estrés y simulacros de alertas). |
| **Fase 7** | Documentación y Cierre | 11 - 12 | Redacción final de la memoria, manuales de administración y preparación de la defensa. |

---

## 2. Análisis de requisitos

Esta fase detalla las especificaciones técnicas y funcionales que el sistema final debe cumplir para garantizar el éxito del despliegue.

### 2.1. Requisitos Funcionales (RF)
* **RF-01 (Enrutamiento NAT):** El servidor Ubuntu debe actuar como puerta de enlace, realizando enmascaramiento de IP (*Masquerading*) para dotar de conectividad a la subred privada.
* **RF-02 (Gestión de Identidad):** Windows Server debe proporcionar servicios de autenticación y autorización mediante Active Directory.
* **RF-03 (Seguridad de Red):** El sistema debe gestionar el tráfico mediante firewall, permitiendo explícitamente el tráfico de administración y servicios autorizados.
* **RF-04 (Monitorización de Tráfico):** Se deben capturar y visualizar métricas de ancho de banda (entrada/salida) en la interfaz del servidor Gateway para auditar el consumo total.
* **RF-05 (Dashboard Unificado):** Grafana debe mostrar el estado de recursos (CPU, RAM, Disco) de ambos servidores en un único panel centralizado.
* **RF-06 (Resolución DNS):** La red interna debe resolver correctamente nombres de dominio locales y externos a través del Controlador de Dominio.
* **RF-07 (Gestión de Alertas):** El sistema debe detectar anomalías críticas y enviar notificaciones en tiempo real a un canal externo (Telegram/Discord). Las alertas deben incluir, como mínimo: caída del servicio Active Directory (NTDS) y agotamiento de créditos de CPU (*CPU Credit Balance*) en las instancias T2/T3.
* **RF-08 (Acceso Remoto):** Se debe garantizar el acceso administrativo remoto a los servidores mediante SSH (puerto 22) para Linux y RDP (puerto 3389) para Windows, asegurando la conectividad necesaria para tareas de gestión.

### 2.2. Requisitos No Funcionales (RNF)
* **RNF-01 (Aislamiento):** La instancia de Windows Server debe residir obligatoriamente en una subred privada sin dirección IP pública asignada directamente.
* **RNF-02 (Rendimiento):** El proceso de recolección de métricas no debe impactar significativamente el rendimiento de la red ni superar el 10% de uso de CPU de la instancia.
* **RNF-03 (Disponibilidad):** Los servicios de enrutamiento y monitorización deben iniciarse automáticamente tras el arranque del sistema (*systemd*).
* **RNF-04 (Escalabilidad):** La arquitectura debe permitir la adición de futuros clientes en la subred privada sin necesidad de reconfigurar el enrutamiento del Gateway.

### 2.3. Usuarios y Roles
* **Administrador:** Acceso total (Root/Administrator) mediante SSH/RDP para configuración de infraestructura y servicios.
* **Operador:** Acceso de lectura a los paneles de monitorización.
* **Cliente de Dominio:** Usuario estándar con permisos restringidos y navegación filtrada por el Gateway.

### 2.4. Análisis de sistemas actuales
Se descarta el uso de *NAT Gateways* nativos de AWS por su elevado coste y falta de visibilidad interna del tráfico. La solución propuesta basada en una instancia Linux permite un control granular del tráfico y auditoría completa sin costes adicionales de licencia, aprovechando herramientas *Open Source*.

Respecto a la administración, se opta por el uso de protocolos estándar (SSH y RDP) configurados sobre la infraestructura de red propia, permitiendo una gestión directa y compatible con las herramientas de administración habituales en entornos de sistemas.

### 2.5. Documentos generados
* Documento de Análisis de Requisitos (Funcionales y No Funcionales).

---

## 3. Diseño de la solución

En esta fase se define la arquitectura técnica detallada que dará soporte a los requisitos planteados, estableciendo la topología de red, la selección de tecnologías y las políticas de seguridad.

### 3.1. Arquitectura de Red y Topología (AWS VPC)
La infraestructura se desplegará sobre una única **VPC (Virtual Private Cloud)** en AWS, segmentada para garantizar el aislamiento del servidor de dominio.

* **Espacio de Direcciones (CIDR):** `10.0.0.0/16`
* **Subred Pública (DMZ):**
    * **CIDR:** `10.0.1.0/24`
    * **Recurso:** Servidor Ubuntu (Gateway).
    * **Enrutamiento:** Conectada a un Internet Gateway (IGW) para tráfico directo de entrada/salida.
* **Subred Privada (Intranet):**
    * **CIDR:** `10.0.2.0/24`
    * **Recurso:** Windows Server 2022 (Controlador de Dominio).
    * **Enrutamiento:** Sin acceso directo a Internet. Su tabla de rutas apuntará a la interfaz de red (ENI) de la instancia Ubuntu para todo el tráfico `0.0.0.0/0` (NAT).

### 3.2. Selección de Tecnologías y Componentes
Se han seleccionado las siguientes tecnologías para cubrir los requisitos funcionales:

* **Servidor de Borde (Gateway):**
    * **SO:** Ubuntu Server 22.04 LTS.
    * **NAT:** Configuración mediante `iptables` (IP Masquerade) y *IP Forwarding* a nivel de kernel.
    * **Monitorización:** Prometheus (TSDB), Alertmanager (gestión de alertas) y Grafana (visualización).
* **Servidor Interno:**
    * **SO:** Windows Server 2022 Base.
    * **Roles:** Active Directory Domain Services (AD DS) y DNS.
* **Agentes de Métricas:**
    * *Node Exporter* (para métricas de Linux).
    * *Windows Exporter* (para métricas de Windows Server).

### 3.3. Diseño de Seguridad y Accesos
La seguridad se implementará en dos capas: **Security Groups** (firewall de red de AWS) y configuración del sistema operativo.

#### A. Estrategia de Security Groups (AWS)
Definición de reglas de tráfico permitidas:

**1. SG-Gateway (Instancia Ubuntu):**
* **Inbound (Entrada):**
    * `TCP/22` (SSH): Permitido desde `0.0.0.0/0` (Recomendado restringir a IP de administración).
    * `TCP/3389` (RDP Forwarded): Permitido para redirigir tráfico al Windows Server.
    * `TCP/3000` (Grafana): Acceso al dashboard de monitorización.
    * `Tráfico Interno`: Todo el tráfico procedente de la subred privada (`10.0.2.0/24`) para permitir la salida a Internet (NAT).
* **Outbound (Salida):** Todo permitido.

**2. SG-Internal (Windows Server):**
* **Inbound (Entrada):**
    * `TCP/3389` (RDP): Permitido **exclusivamente** desde el Grupo de Seguridad del Gateway (SG-Gateway).
    * `TCP/UDP 53, 88, 135, 389, 445, 464, 636` (Active Directory): Tráfico interno permitido desde la subred pública.
    * `TCP/9182` (Métricas): Puerto del *Windows Exporter* permitido solo desde la IP privada del Gateway (Prometheus).
* **Outbound (Salida):** Todo permitido (el tráfico saldrá efectivamente a través del Gateway).

#### B. Acceso Remoto y Port Forwarding
Dado que el Windows Server se encuentra en una red privada aislada, se implementará una regla de **DNAT (Destination NAT)** en el servidor Ubuntu.
* El administrador conectará por RDP a la IP Pública del Ubuntu (`IP_Ubuntu:3389`).
* `iptables` redirigirá esa petición a la IP Privada del Windows (`IP_Windows:3389`), garantizando la administración sin exponer el servidor interno directamente.

### 3.4. Diseño del Sistema de Monitorización y Alertas
El flujo de datos para la observabilidad seguirá el siguiente esquema:

1.  **Recolección:** *Prometheus* (en Ubuntu) realizará peticiones periódicas (*scraping*) al `localhost:9100` (Node Exporter) y a la `IP_Privada_Windows:9182` (Windows Exporter).
2.  **Visualización:** *Grafana* leerá la base de datos de Prometheus para pintar los paneles de control.
3.  **Alertado:**
    * Se definirán reglas en Prometheus.
    * Cuando se active una regla, Prometheus enviará la señal a *Alertmanager*.
    * *Alertmanager* gestionará la notificación y la enviará al canal configurado (Webhook de Discord o Bot de Telegram).

### 3.5. Documentos generados
* Documento de Diseño de la Solución (Diagramas de red y esquemas de direccionamiento).
* Especificación de reglas de Firewall y Security Groups.

### 3.6. Esquema de la Solución
A continuación se presenta el diagrama topológico de la infraestructura...

![Diagrama de Topología de Red](imagenes/topologia.png)
*Figura 1: Topología de red en AWS con segmentación de subredes.*
