# VidaMayor

App Android para acompañar a adultos mayores: **medicinas, citas, familia, emergencia y ubicación**, con un panel para que la familia vea cómo va el día. Proyecto escolar.

Está hecha con **HTML, CSS y JavaScript** y se empaqueta como **APK** con [Capacitor](https://capacitorjs.com). Los avisos de medicinas y citas son notificaciones locales del teléfono, así que llegan aunque la app esté cerrada.

---

## 1. ¿Qué trae?

| Pantalla | Qué hace |
|---|---|
| **Inicio** | Saludo, próximo medicamento (con botón *Ya lo tomé*), próxima cita, estado del día, llamada rápida y botón de emergencia |
| **Agenda** | Calendario sencillo con citas, actividades y recordatorios |
| **Medicinas** | Nombre, dosis, hora, confirmar toma, deshacer y pendientes |
| **Familia** | Contactos de emergencia con foto, teléfono y botón *Llamar* |
| **SOS / Emergencia** | Botón grande, confirmación antes de enviar, llamar al 911, mensaje/WhatsApp a los contactos con la ubicación y aviso automático a la familia conectada |
| **Ubicación** | Compartir ubicación (GPS del teléfono), última ubicación y quién puede verla (la familia conectada que autorizaste) |
| **Mi perfil** | Datos, médico de confianza, información médica, **privacidad y permisos**, notificaciones y tamaño de letra |
| **Avisos** | Lista de lo pendiente: *"Hora de tomar medicamento"*, *"No se ha confirmado tu medicamento de las 10:00 a. m."* |
| **Familia conectada** | Un código une el celular de la persona con el de su familiar, que lo escribe en su propio teléfono con *Soy familiar*. La persona decide a quién autoriza. |
| **Panel familiar** | Lo que ve el familiar en su celular: medicinas confirmadas/pendientes, citas, ubicación y emergencias (según lo que la persona permita). Requiere la nube: ver [GUIA-SUPABASE.md](GUIA-SUPABASE.md) |

Diseño *Soft & Friendly*: letra grande (con 3 tamaños), alto contraste, botones amplios y pocos colores.

---

## 2. Probar cambios en el navegador (para quien programa)

Necesitas [Node.js 22](https://nodejs.org) o más nuevo.

```bash
npm run dev
```

Abre <http://localhost:5173>. Para verla como celular: en Chrome pulsa `F12` y luego el ícono de celular.

> En el navegador los avisos solo funcionan con la app abierta y la ubicación pide permiso al navegador. En el APK funcionan con el sistema de Android.

---

## 3. Conseguir el APK

### Ruta A (recomendada): GitHub lo compila por ti

No necesitas instalar Android Studio.

1. Crea un repositorio **vacío** en GitHub.
2. Sube esta carpeta completa (incluida la carpeta oculta `.github`):
   ```bash
   git init
   git add .
   git commit -m "VidaMayor"
   git branch -M main
   git remote add origin https://github.com/TU-USUARIO/vidamayor.git
   git push -u origin main
   ```
3. En GitHub entra a la pestaña **Actions**. Verás *Compilar APK* trabajando (tarda unos 6 a 10 minutos). También puedes lanzarlo a mano con **Run workflow**.
4. Cuando termine con ✅, abre esa ejecución y baja hasta **Artifacts**. Descarga **VidaMayor-apk**, descomprímelo y tendrás `app-debug.apk`.
5. Pásalo al celular (cable USB, Drive, WhatsApp…) y ábrelo. Android te pedirá permitir **instalar apps de origen desconocido** para la app desde la que lo abres. Acepta y listo.

### Ruta B: compilarlo en tu computadora

Necesitas: **Node 22+**, **JDK 21** y **Android Studio (Otter 2025.2.1 o más nuevo)** con el SDK de Android 36.

```bash
npm install
npm run android:add     # crea android/, agrega permisos, íconos y pantalla de inicio
npm run apk             # compila
```

El APK queda en `android/app/build/outputs/apk/debug/app-debug.apk`.
Para abrirlo en Android Studio y probarlo en un emulador: `npm run android:open`.
(En Windows, si `./gradlew` falla, usa `cd android` y `gradlew.bat assembleDebug`.)

### Si algo falla

> La interfaz y la lógica tienen más de 130 pruebas automáticas. El APK se compila en GitHub Actions: si el flujo falla, abre el paso en rojo, copia el error y con eso se corrige rápido.

| Mensaje | Qué hacer |
|---|---|
| `invalid source release: 21` | Estás usando Java 17 o menor. Instala JDK 21. |
| `The current Node.js version ... requires >=22` | Actualiza Node a la versión 22 o más nueva. |
| `Failed to install the following SDK components` o licencias | Abre Android Studio una vez y acepta las licencias del SDK (en GitHub Actions ya se aceptan solas). |
| Los avisos llegan con minutos de retraso | Ajustes del teléfono → Apps → VidaMayor → *Alarmas y recordatorios* → permitir. |

---

## 4. Cómo funciona

**En el teléfono de la persona**
- Medicinas, citas, contactos de emergencia y ajustes se guardan en el teléfono.
- Avisos de medicinas (a la hora y otro a los 30 min si no confirma) y de citas (1 hora antes), aunque la app esté cerrada.
- GPS para la ubicación, llamadas (`tel:`), mensajes (`sms:`) y WhatsApp con un toque, y mapa.

**Entre dos celulares (con la nube de [GUIA-SUPABASE.md](GUIA-SUPABASE.md))**
- La persona crea un código; su familiar lo escribe en su propio teléfono y la persona decide si lo autoriza.
- El familiar ve, casi al instante, las medicinas confirmadas, las citas del día, la ubicación (si se comparte) y las alertas de emergencia.
- El filtro de privacidad se aplica **en el servidor**: lo que la persona no comparte nunca sale de la base de datos.
- Si no hay internet al pedir ayuda, la alerta espera y se envía sola cuando vuelve la conexión.

**Todavía no incluye**
- Avisar al familiar cuando **su app está cerrada** (necesita notificaciones *push*): hoy se entera mientras la app está abierta o recién usada.
- Cuentas con correo o teléfono: hoy la conexión es por código y autorización.

### Antes de publicarla en una tienda
1. Notificaciones *push* (Firebase Cloud Messaging) para avisar al familiar aunque su app esté cerrada.
2. Cuentas reales con Supabase Auth y límites contra abusos.
3. Política de privacidad y consentimiento: son datos de salud y ubicación.

---

## 5. Permisos que pide la app

| Permiso | Para qué |
|---|---|
| Notificaciones | Avisos de medicinas y citas |
| Alarmas exactas | Que el aviso llegue justo a la hora |
| Ubicación | Compartir ubicación y adjuntarla a la emergencia (solo si la activas) |
| Iniciar con el teléfono | Volver a programar los avisos después de reiniciar |

> Nota: `USE_EXACT_ALARM` está pensado para apps de alarmas/calendario. Para un APK escolar no hay problema; si algún día la publicas en Google Play, tendrás que justificarlo o quitarlo de `scripts/patch-android.mjs`.

---

## 6. Estructura del proyecto

```
vidamayor/
├── www/                     La app (lo que se empaqueta en el APK)
│   ├── index.html
│   ├── style.css
│   ├── logo.png             Logo de la app (los abuelitos entre las manos)
│   ├── nube.js              Habla con Supabase (sin librerías)
│   ├── nube-config.js       Aquí pegas la dirección y la clave de tu proyecto de Supabase
│   └── script.js            Toda la lógica, comentada por secciones
├── supabase/
│   └── esquema.sql          Tablas y funciones seguras de la base de datos
├── design/                  Logo original recortado (de aquí salen el ícono y la pantalla de inicio)
├── assets/                  Ícono y pantalla de inicio (se generan con scripts/make-icons.py)
├── scripts/
│   ├── patch-android.mjs    Permisos, orientación vertical e ícono de notificación
│   ├── make-icons.py        Crea el ícono y la pantalla de inicio a partir de design/
│   └── serve.mjs            Servidor para verla en el navegador
├── .github/workflows/build-apk.yml   Compila el APK en GitHub
├── capacitor.config.json    ID de la app (mx.vidamayor.app) y ajustes de plugins
└── package.json
```

Para cambiar el nombre o el ID de la app edita `capacitor.config.json` **antes** de ejecutar `npm run android:add`.

---

*Versiones: Capacitor 8 (Node 22+, JDK 21, Android SDK 36).*
