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
    * Aislamiento de red (sin IP pública).
* **Gestión y Acceso Seguro:**
    * **Implementación de AWS Systems Manager (SSM):** Configuración del agente SSM para permitir el acceso por consola y el reenvío de puertos (*Port Forwarding*) hacia el servidor Windows, eliminando la necesidad de exponer servicios administrativos a Internet.
* **Interconexión y Visibilidad:** Configuración de tablas de rutas para forzar el tráfico a través del Gateway y visualización de métricas en tiempo real.

### 1.3. Recursos identificados
Para llevar a cabo el proyecto se han identificado los siguientes recursos:

* **Infraestructura (AWS EC2):**
    * 1x Instancia `t2.micro` (Ubuntu Server 22.04 LTS).
    * 1x Instancia `t2.micro` o `t3.micro` (Windows Server 2019/2022).
* **Software y Servicios:**
    * **Sistemas Operativos:** Linux y Windows Server.
    * **Red:** IPTables, UFW, VPC Routing.
    * **Monitorización y Alertas:** Prometheus, Grafana, Alertmanager, Node Exporter, Windows Exporter.
    * **Gestión Cloud:** AWS Systems Manager Agent (SSM Agent).
* **Personal:** 1 Técnico Administrador de Sistemas.

### 1.4. Restricciones y condicionantes
El proyecto debe adherirse a las siguientes limitaciones:

* **Económicas:** El proyecto debe ser viable dentro de la capa gratuita (*Free Tier*) de AWS.
* **Seguridad y Acceso:** Ningún puerto de gestión (SSH/22, RDP/3389) debe estar abierto a Internet (`0.0.0.0/0`). Todo acceso administrativo debe realizarse mediante sesiones gestionadas por **AWS SSM**, garantizando una arquitectura de "puertos cerrados".
* **Plazos:** El despliegue funcional debe estar listo antes de la fecha de defensa del TFG.

### 1.5. Documentos generados
* Documento de alcance del proyecto.
* Cronograma preliminar de fases.

### 1.6. Cronograma preliminar
Para garantizar el cumplimiento de los objetivos en el plazo establecido, se ha diseñado una planificación temporal dividida en semanas de trabajo. La estimación total del proyecto es de **12 semanas**, cubriendo desde la investigación inicial hasta la defensa del TFG.

| Fase | Tarea Principal | Semanas Estimadas | Descripción |
| :--- | :--- | :---: | :--- |
| **Fase 1** | Planificación y Análisis | 1 - 2 | Definición de alcance, requisitos y estudio de viabilidad en AWS Free Tier. |
| **Fase 2** | Diseño de la Solución | 3 - 4 | Elaboración de diagramas de red (VPC), diseño de direccionamiento IP y políticas de seguridad (Security Groups/IAM). |
| **Fase 3** | Despliegue de Infraestructura | 5 - 6 | Creación de VPC, subredes, tablas de enrutamiento y lanzamiento de instancias EC2 (Ubuntu y Windows). |
| **Fase 4** | Configuración de Servicios | 7 - 8 | Configuración de NAT, Active Directory, Prometheus, Grafana y **Alertmanager**. |
| **Fase 5** | Hardening y Seguridad | 9 | Implementación de **AWS SSM**, cierre de puertos (22/3389) y reglas de firewall avanzadas. |
| **Fase 6** | Pruebas y Validación | 10 | Ejecución del plan de pruebas (funcionales, estrés y simulacros de alertas). |
| **Fase 7** | Documentación y Cierre | 11 - 12 | Redacción final de la memoria, manuales de administración y preparación de la defensa. |

---

## 2. Análisis de requisitos

Esta fase detalla las especificaciones técnicas y funcionales que el sistema final debe cumplir para garantizar el éxito del despliegue.

### 2.1. Requisitos Funcionales (RF)
* **RF-01 (Enrutamiento NAT):** El servidor Ubuntu debe actuar como puerta de enlace, realizando enmascaramiento de IP (*Masquerading*) para dotar de conectividad a la subred privada.
* **RF-02 (Gestión de Identidad):** Windows Server debe proporcionar servicios de autenticación y autorización mediante Active Directory.
* **RF-03 (Seguridad de Red):** El sistema debe bloquear mediante firewall todo tráfico entrante no explícitamente autorizado hacia la red interna.
* **RF-04 (Monitorización de Tráfico):** Se deben capturar y visualizar métricas de ancho de banda (entrada/salida) en la interfaz del servidor Gateway para auditar el consumo total.
* **RF-05 (Dashboard Unificado):** Grafana debe mostrar el estado de recursos (CPU, RAM, Disco) de ambos servidores en un único panel centralizado.
* **RF-06 (Resolución DNS):** La red interna debe resolver correctamente nombres de dominio locales y externos a través del Controlador de Dominio.
* **RF-07 (Gestión de Alertas):** El sistema debe detectar anomalías críticas y enviar notificaciones en tiempo real a un canal externo (Telegram/Discord). Las alertas deben incluir, como mínimo: caída del servicio Active Directory (NTDS) y agotamiento de créditos de CPU (*CPU Credit Balance*) en las instancias T2/T3.
* **RF-08 (Acceso sin Puertos):** La administración remota de los servidores debe realizarse obligatoriamente a través de AWS Systems Manager Session Manager, permitiendo el acceso a la terminal Linux y el túnel RDP hacia Windows sin necesidad de abrir puertos de entrada en el Security Group público.

### 2.2. Requisitos No Funcionales (RNF)
* **RNF-01 (Aislamiento):** La instancia de Windows Server debe residir obligatoriamente en una subred privada sin dirección IP pública asignada.
* **RNF-02 (Rendimiento):** El proceso de recolección de métricas no debe impactar significativamente el rendimiento de la red ni superar el 10% de uso de CPU de la instancia.
* **RNF-03 (Disponibilidad):** Los servicios de enrutamiento y monitorización deben iniciarse automáticamente tras el arranque del sistema (*systemd*).
* **RNF-04 (Escalabilidad):** La arquitectura debe permitir la adición de futuros clientes en la subred privada sin necesidad de reconfigurar el enrutamiento del Gateway.

### 2.3. Usuarios y Roles
* **Administrador:** Acceso total (Root/Administrator) vía SSM para configuración de infraestructura y servicios.
* **Operador:** Acceso de lectura a los paneles de monitorización.
* **Cliente de Dominio:** Usuario estándar con permisos restringidos y navegación filtrada por el Gateway.

### 2.4. Análisis de sistemas actuales
Se descarta el uso de *NAT Gateways* nativos de AWS por su elevado coste y falta de visibilidad interna del tráfico. La solución propuesta basada en una instancia Linux permite un control granular del tráfico y auditoría completa sin costes adicionales de licencia, aprovechando herramientas *Open Source*.

Adicionalmente, se descarta el uso de servidores "Bastion" o "Jump Hosts" tradicionales accesibles vía SSH público, debido a la vulnerabilidad que representa exponer el puerto 22. Se opta por **AWS Systems Manager (SSM)**, que permite gestionar las instancias mediante autenticación IAM sin abrir puertos de entrada, siguiendo el principio de *Security by Design*.

### 2.5. Documentos generados
* Documento de Análisis de Requisitos (Funcionales y No Funcionales).
