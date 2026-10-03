# Economía familiar

Centro de control de las finanzas de la familia: ingresos, gastos, ahorro, inversiones y patrimonio, corregidos por inflación y dólar. Funciona como app instalable en el celular y como página web en la compu.

- **Frontend:** HTML, CSS y JavaScript sin compilación, publicado en Cloudflare Pages.
- **Datos y login:** Supabase (PostgreSQL con reglas de acceso por familia).
- **Sin conexión:** cada dispositivo guarda una copia; los cambios hechos sin internet se suben solos al volver la conexión.

## Estructura

| Archivo | Para qué sirve |
| --- | --- |
| `index.html` | La aplicación completa |
| `config.js` | URL y clave pública de Supabase |
| `manifest.webmanifest`, `sw.js`, `icon-*.png`, `apple-touch-icon.png` | Instalación como app (PWA) |
| `_headers` | Encabezados de seguridad para Cloudflare |
| `supabase-schema.sql` | Tablas, reglas de acceso y funciones de la base |

## Puesta en marcha (una sola vez)

### 1. Base de datos en Supabase
1. En Supabase, abrí **SQL Editor** y elegí **New query**.
2. Pegá el contenido completo de `supabase-schema.sql` y tocá **Run**. Tiene que terminar con "Success". Se puede volver a ejecutar sin perder datos.

### 2. Subir los archivos a GitHub
Opción web: en el repositorio, **Add file > Upload files** (o "uploading an existing file" si el repo está vacío), seleccioná todos los archivos de esta carpeta y confirmá con **Commit changes**. Todos van en la raíz, no hay subcarpetas.

Opción con git:
```bash
git clone https://github.com/hernanmerlino2/EconomiaFamiliar.git
# copiar todos los archivos de esta carpeta dentro de EconomiaFamiliar/
cd EconomiaFamiliar
git add .
git commit -m "Economía familiar en la nube"
git push
```

### 3. Publicar en Cloudflare Pages
1. **Workers & Pages > Create** y elegí la pestaña **Pages**, después **Connect to Git**.
2. Autorizá a Cloudflare en GitHub (podés limitarlo solo al repo `EconomiaFamiliar`) y seleccioná el repo. **Begin setup**.
3. Configuración:
   - Project name: `economia-familiar` (define la dirección `https://economia-familiar.pages.dev`)
   - Production branch: `main`
   - Framework preset: **None**
   - Build command: *vacío*
   - Build output directory: *vacío*
4. **Save and Deploy**. En uno o dos minutos queda publicada.

Si en algún momento te pide un "Deploy command", estás creando un proyecto de Workers: volvé atrás y elegí la pestaña **Pages**.

### 4. Conectar el login con la dirección publicada
En Supabase, **Authentication > URL Configuration**:
- **Site URL:** `https://economia-familiar.pages.dev` (la dirección real que te dio Cloudflare)
- **Redirect URLs:** agregá `https://economia-familiar.pages.dev/**`

Sin esto, los mails de confirmación y de recuperación de contraseña llevan a una dirección equivocada.

### 5. Crear las cuentas
1. Entrá a la dirección publicada, tocá **Crear una cuenta** y después **Crear familia**.
2. En **Configuración** vas a ver el **código de invitación**. Pasáselo a tu pareja: crea su cuenta y elige **Unirme a la familia**.
3. Cuando estén los dos adentro, en Supabase andá a **Authentication > Sign In / Providers** y desactivá **Allow new users to sign up**. Así nadie más puede registrarse.

### 6. Traer los datos de la versión anterior
En la versión vieja (el HTML o el servidor local): **Configuración > Exportar backup JSON**. En la nueva: **Configuración > Importar backup JSON**. Reemplaza los datos de la familia por los del backup.

## Instalar como app
- **Android (Chrome):** menú ⋮ > **Instalar app** o **Agregar a la pantalla principal**.
- **iPhone (Safari):** botón Compartir > **Agregar a inicio**.
- **Compu (Chrome o Edge):** ícono de instalar en la barra de direcciones, o simplemente usarla como página.

## Actualizar la app
Cada cambio que se sube a la rama `main` se publica solo. Los dispositivos toman la versión nueva la próxima vez que abren la app con conexión.

## Seguridad
- La clave de `config.js` es la clave *publishable* de Supabase: está hecha para ir en el frontend.
- Lo que protege los datos son las reglas de `supabase-schema.sql` (Row Level Security): cada cuenta solo puede leer y escribir los datos de su familia.
- Nunca pongas en este repositorio la clave *secret* / *service_role* de Supabase.
- Al cerrar sesión se borra la copia local del dispositivo.
