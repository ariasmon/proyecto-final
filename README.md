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
