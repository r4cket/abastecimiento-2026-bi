# Publicar el tablero de Abastecimiento en internet (gratis, sin tarjeta)

Enlace público de **solo lectura** para cualquiera con la URL.

```
Visitante ──HTTPS──> Grafana (Render, capa gratis) ──SSL──> Postgres (Neon, capa gratis)
```

Grafana va "sin estado": el dashboard y la conexión se hornean en la imagen
(`Dockerfile` + `provisioning/`), con acceso **anónimo Viewer**. No hay disco
persistente, así que la capa gratis alcanza.

---

## Qué se anonimizó (importante)

La base local (`bi/postgres/init/02_data.sql`) tiene datos internos. La versión
que se sube a internet es **`sql/02_data_public.sql`**, generada con
`py loader\build_data_sql.py --public`, que pone en **NULL** estas 3 columnas de
la tabla `compra`:

| Columna | Qué contenía |
|---|---|
| `solicitante` | nombre y apellidos de quien pidió la compra |
| `ejecutivo_asignado` | nombre del ejecutivo de compras asignado |
| `actor_estado` | rol/cargo mencionado en el estado (Jefe Dpto., Dirección…) |

**Ningún panel del tablero muestra esas columnas**, así que el tablero público se
ve exactamente igual que el local. Lo que sí queda visible: montos por servicio y
por estado (agregados), días de gestión, N° de solicitud, categorías de estado y
de atribución de causa. Son datos de compras públicas de un servicio del Estado.

> Si además quieres ocultar montos individuales, dilo y agrego el filtro; hoy los
> montos solo se muestran sumados, nunca fila-por-fila junto a un nombre.

---

## Lo que tienes que hacer tú (yo no puedo crear cuentas ni aceptar términos)

Necesitas 3 cuentas gratuitas, todas con login de GitHub y **sin tarjeta**:

1. **GitHub** — para alojar el repo.
2. **Neon** (neon.tech) — Postgres gestionado.
3. **Render** (render.com) — corre la imagen de Grafana.

---

## Paso 0 — Repo en GitHub

**Esta carpeta (`bi/deploy/`) es su propio repo git**, separado del resto del
proyecto. Así el repo de GitHub nunca contiene `postgres/init/02_data.sql` ni el
Excel con los nombres reales — ni siquiera en el historial. Puede ser público o
privado, es indistinto para la privacidad (igual se recomienda privado por
prolijidad).

```bash
cd "…/cloudeABAST/TRABAJOppt/bi/deploy"
git init
git add -A
git commit -m "Deploy publico Abastecimiento 2026 (datos anonimizados)"
git branch -M main
git remote add origin https://github.com/<tu-usuario>/<tu-repo>.git
git push -u origin main
```

## Paso 1 — Postgres en Neon

1. neon.tech → **Sign up** con GitHub.
2. **Create project** → región **AWS sa-east-1 (São Paulo)** (la más cercana) →
   nombre `abastecimiento-2026`.
3. En el panel del proyecto anota: **host**, **database**, **user**, **password**
   (puerto 5432, SSL `require`). Está en *Connection Details*.
4. Abre **SQL Editor** y ejecuta, en orden:
   - todo el contenido de `bi/deploy/sql/01_schema.sql`
   - todo el contenido de `bi/deploy/sql/02_data_public.sql`
5. Verifica que cargó y que **no hay nombres**:

   ```sql
   SELECT
     (SELECT count(*) FROM compra)                                   AS compras,
     (SELECT count(*) FROM despacho_mensual)                         AS despacho,
     (SELECT count(*) FROM compra
        WHERE solicitante IS NOT NULL
           OR ejecutivo_asignado IS NOT NULL
           OR actor_estado IS NOT NULL)                              AS con_nombre;
   ```
   Esperado: `compras = 91`, `despacho = 3552`, **`con_nombre = 0`**.

## Paso 2 — Grafana en Render

1. render.com → **Sign up** con GitHub → **New → Blueprint**.
2. Elige tu repo. Render detecta `render.yaml` en la raíz.
   (Si prefieres a mano: **New → Web Service** · Runtime **Docker** · Plan
   **Free** · Root Directory en blanco, el `Dockerfile` está en la raíz del repo.)
3. En **Environment** completa lo que quedó `sync:false`:

   | Key | Value |
   |---|---|
   | `GF_SECURITY_ADMIN_PASSWORD` | una clave larga y única (para `/login`) |
   | `GF_SERVER_ROOT_URL` | `https://<nombre-que-quede>.onrender.com` |
   | `PG_HOST` | host de Neon |
   | `PG_DATABASE` | database de Neon |
   | `PG_USER` | user de Neon |
   | `PG_PASSWORD` | password de Neon |

   (`PG_PORT=5432`, `PG_SSLMODE=require` y `GF_SERVER_HTTP_PORT=10000` ya vienen
   en `render.yaml`.)
4. **Create** → primer build ~3–5 min. Abre la URL: debe cargar el tablero
   directo, **sin pedir login** (anónimo Viewer). El admin entra por `/login`.

## Paso 3 — Comprobar

- Abre la URL en una ventana de incógnito → se ve el tablero, folder
  "Abastecimiento 2026".
- Intenta editar un panel → no se puede (Viewer). *Explore* está deshabilitado.

---

## Actualizar los datos (cuando haya un Excel nuevo)

```powershell
cd "…/cloudeABAST/TRABAJOppt/bi/loader"
py build_data_sql.py --public      # regenera bi/deploy/sql/02_data_public.sql
py build_dashboard.py              # si cambiaste paneles
```
Luego en el **SQL Editor de Neon**: corre otra vez `01_schema.sql` (borra y
recrea) y el nuevo `02_data_public.sql`. Grafana lee en vivo, no hay que
redeployar. Si cambió el JSON del dashboard, haz `git push` y Render reconstruye.

---

## Límites de la capa gratis (ok para un enlace de difusión)

- **Render Free**: el servicio **duerme tras 15 min** sin visitas; la primera
  visita tarda ~50 s en despertar. 750 h/mes.
- **Neon Free**: autosuspende por inactividad (~1 s en despertar). 0,5 GB (sobra).
- Sin tarjeta, sin vencimiento.

## Seguridad

- Cambia `GF_SECURITY_ADMIN_PASSWORD`. Nunca dejes la de por defecto.
- La URL es **pública**: cualquiera con el enlace ve el tablero. No la trates
  como secreta; sí como "difusión controlada".
- No subas `bi/deploy/.env` (está en `.gitignore`).
- Si algún día agregas datos personales a alguna vista, **no** se publican por
  este camino sin volver a revisar.

## Alternativa: Hugging Face Spaces

Mismo `Dockerfile` y `provisioning/`. Crea un **Docker Space**, sube los archivos
por la web (sin git), y usa `GF_SERVER_HTTP_PORT=7860` y
`GF_SERVER_ROOT_URL=https://<user>-<space>.hf.space`. El Postgres igual va en Neon.

## Probar la imagen pública en local (opcional, requiere Docker)

Este PC no tiene Docker, pero en una máquina que sí:

```bash
cd bi/deploy
docker compose -f docker-compose.public.yml up --build
# -> http://localhost:3002
```
