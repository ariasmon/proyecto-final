<img width="1893" height="730" alt="image" src="https://github.com/user-attachments/assets/77c68e41-d518-4499-97da-614f7babbc66" />

## 1. Resumen de lo implementado

Se ha construido una solucion web interna en IIS para consultar usuarios de Active Directory y preparar una API segura para altas de usuario.

Componentes principales:

1. Portal principal.
- Pagina principal del portal con acceso directo al directorio.
- Enlace funcional a la pagina de directorio de usuarios.

2. Directorio de usuarios (frontend).
- Carga de datos desde ad-users.json.
- Busqueda por texto.
- Filtros por departamento y estado.
- Ordenacion por nombre y usuario.
- Paginacion (10/25/50/100).
- Exportacion CSV de resultados.
- Indicadores de total, filtrados y ultima sincronizacion.

3. Exportacion desde Active Directory.
- Script PowerShell para extraer usuarios de AD y generar ad-users.json.
- Campos exportados: SamAccountName, DisplayName, Name, Mail, Department, Enabled.

4. API segura para altas de usuario AD.
- Endpoint IIS POST /api/create-user.ps1.
- Autenticacion Windows obligatoria.
- Anonymous deshabilitado.
- Restriccion por usuario/grupo autorizado.
- Validaciones de entrada (UPN, OU, password policy, duplicados).
- Auditoria en log JSONL.

<img width="1893" height="730" alt="image" src="https://github.com/user-attachments/assets/beac6a57-f947-41f1-9fae-ab130b77d9eb" />

5. Script de configuracion de API.
- Script para desplegar/configurar la aplicacion /api en IIS.
- Instalacion de dependencias de IIS (CGI y Windows Auth).

## 2. Archivos funcionales

- index.html
- directorio-usuarios.html
- ad-users.json
- scripts/exportar-usuarios-ad.ps1
- scripts/ad-user-service.ps1
- scripts/configurar-api-alta-ad.ps1
- api/create-user.ps1
- api/web.config

## 3. Flujo de operacion

1. Se ejecuta scripts/exportar-usuarios-ad.ps1.
2. El script consulta AD y actualiza ad-users.json.
3. directorio-usuarios.html consume ad-users.json y muestra resultados.
4. Para alta de usuarios, se llama por POST a /api/create-user.ps1.
5. La API valida permisos, valida datos, crea usuario en AD y audita la accion.
