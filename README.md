# API de Consulta - Proyecto Bases de Datos (Pyme de Velas)

API desarrollada con **FastAPI** y **PostgreSQL** (en DBeaver y `psycopg` 3) para consultar el catálogo de velas, boletas y detalle de ventas del sistema.

---

## 1. Configuración previa en PostgreSQL

Antes de levantar la API, crea el usuario y la base de datos con las credenciales configuradas en `main.py`:

* **Usuario:** `admin`
* **Contraseña:** `1234`
* **Base de datos:** `proyecto`

Puedes crearlos ejecutando en PostgreSQL (como superusuario `postgres`):

```sql
CREATE USER admin WITH PASSWORD '1234' SUPERUSER;
CREATE DATABASE proyecto OWNER admin;
```

Luego, conéctate a la base de datos `proyecto` usando el usuario `admin` y ejecuta el script `.sql` principal (creación de tablas, triggers, procedimientos almacenados y poblamiento).

## 2. Instalación y ejecución

Abre una terminal dentro de esta carpeta (`api-bd`) y sigue los pasos según tu sistema operativo:

### En Windows

```
# 1. Crear y activar entorno virtual
python -m venv .venv
.venv\Scripts\activate

# 2. Instalar dependencias
pip install "fastapi[standard]" "psycopg[binary]"

# 3. Iniciar el servidor
fastapi dev main.py
```

### Linux/MacOS

```
# 1. Crear y activar entorno virtual
python3 -m venv .venv
source .venv/bin/activate

# 2. Instalar dependencias
pip install "fastapi[standard]" "psycopg[binary]"

# 3. Iniciar el servidor
fastapi dev main.py
```

## 3. Endpoints disponibles

Con el servidor activo en http://127.0.0.1:8000, puedes probar las rutas directamente en el navegador o desde la documentación interactiva:
- Documentación interactiva (Swagger UI): http://127.0.0.1:8000/docs
- Estado de la API: GET /
- Listado de velas y stock actual: GET /velas
- Listado de boletas emitidas: GET /boletas
- Detalle consolidado de ventas: GET /ventas
