# Guía: activar "Familia conectada" con Supabase

Con esto, el celular de la persona mayor y el de su familiar se hablan de verdad:
el familiar ve las medicinas, citas, ubicación, **recibe la alerta de emergencia** y pueden **escribirse mensajes de texto y mandarse notas de voz** desde la misma app.

Tiempo: unos 15 minutos. Costo: **$0** (plan gratuito de Supabase).

> **Este paso es necesario antes de compartir o publicar la app.** Sin él, la app abre y sirve para llevar medicinas, citas y emergencias en el propio teléfono, pero *Familia conectada* no estará disponible.

---

## Paso 1 · Crear tu proyecto en Supabase

1. Entra a **https://supabase.com** → **Start your project** → inicia sesión con tu cuenta de GitHub.
2. **New project** y llena:
   - **Name:** `VidaMayor`
   - **Database password:** crea una contraseña y **guárdala** (la app no la usa, pero Supabase la pide).
   - **Region:** la más cercana (por ejemplo *East US*).
   - **Plan:** Free.
3. Pulsa **Create new project** y espera 1 o 2 minutos a que termine.

## Paso 2 · Crear las tablas (pegar el script)

1. En el menú de la izquierda abre **SQL Editor** → **New query**.
2. Abre el archivo `supabase/esquema.sql` de este proyecto en GitHub, copia **todo** su contenido y pégalo en el editor.
3. Pulsa **Run**. Debe decir **Success. No rows returned**.
4. Para comprobarlo, abre **Table Editor**: deben aparecer `familias`, `miembros`, `alertas` y `mensajes`.

> **¿Ya habías pegado el script antes de que existiera el chat?** Vuelve a pegarlo completo y pulsa **Run**: es seguro repetirlo, no borra nada y solo agrega la parte de los mensajes. Hasta que lo hagas, la app mostrará *"falta actualizar la base de datos"* al abrir **Mensajes**.

> Si Supabase muestra un aviso amarillo tipo *"RLS enabled, no policies"*, **es lo esperado**: las tablas quedan cerradas a propósito y la app solo puede usar las funciones del script.

## Paso 3 · Copiar la dirección y la clave

1. Abre **Project Settings** (el engrane) → **API Keys** (en algunas versiones: **API**), o el botón **Connect** de arriba.
2. Copia estos dos datos:
   - **Project URL** → algo como `https://abcdefghijk.supabase.co`
   - **Publishable key** (empieza con `sb_publishable_…`) **o** la clave **anon public** (empieza con `eyJ…`). Sirve cualquiera de las dos.

> **No uses** la clave `service_role` ni `secret`: esas sí son secretas y nunca deben ir en la app.
> La clave pública sí puede ir dentro de la app: está hecha para eso. Lo que protege los datos son las reglas del script del paso 2.

## Paso 4 · Pegarlas en la app

1. En tu repositorio de GitHub abre `www/nube-config.js` → lápiz ✏️ (**Edit**).
2. Pega tus datos entre las comillas:

   ```js
   window.VIDAMAYOR_NUBE = {
     url: 'https://abcdefghijk.supabase.co',
     clave: 'sb_publishable_xxxxxxxxxxxxxxxx',
   };
   ```
3. **Commit changes**. GitHub volverá a compilar el APK solo (pestaña **Actions**, 5–8 min).
4. Descarga el nuevo `VidaMayor-apk` e instálalo en **los dos teléfonos** (el de la persona y el del familiar).

## Paso 5 · Probarlo con dos teléfonos

| En el teléfono de la persona (María) | En el teléfono del familiar (Carlos) |
|---|---|
| **Mi perfil → Familia conectada → Conectar a mi familia**. Aparece un código como `K7M2-XQ9P`. | |
| | Abre VidaMayor → **Soy familiar · tengo un código** → pon su nombre y el código. Verá *"Esperando autorización"*. |
| En unos segundos aparece **Carlos quiere conectarse**. Activa el interruptor para **autorizarlo**. | En unos segundos ve el estado de María. |
| Confirma una medicina con **Ya lo tomé**. | Ve la medicina *Confirmada* sin hacer nada. |
| **Emergencia → pedir ayuda**. | Le llega *"¡Emergencia! María pidió ayuda"* con botones **Llamar** y **Ver dónde está**. Pulsa **Ya la vi**. |
| Ve **"Carlos ya vio tu alerta"**. | |
| Abre **Inicio → Mensajes**, escribe *"Hola hijo"* y pulsa enviar. | Ve el globito **1 mensaje nuevo** en su panel. Abre **Mensajes** y lo lee. |
| | Toca el **micrófono**, habla unos segundos y pulsa **Enviar** (la primera vez Android pide permiso para el micrófono: **Permitir**). |
| Le llega la nota de voz. Toca **▶** para escucharla. | |

Si lo pruebas con **un solo teléfono**, puedes usar un navegador en la computadora como segundo teléfono.

---

## Cómo funciona (para explicarlo en la escuela)

```
 Teléfono de María ──(cada ~12 s, o al instante si hay alerta)──►  Supabase  ◄──(cada ~6 s)── Teléfono de Carlos
   "Mi resumen de hoy"                                         (PostgreSQL)           "¿Cómo está María?"
```

**Tablas**

| Tabla | Qué guarda |
|---|---|
| `familias` | Una fila por persona: código, su resumen del día (medicinas y citas), privacidad y última ubicación |
| `miembros` | Los familiares que pidieron conectarse y si están autorizados |
| `alertas` | Las emergencias (y quién ya las vio). Solo puede haber una activa por familia |
| `mensajes` | El chat de la familia: textos y notas de voz (el audio se guarda como texto base64, máximo 60 s) |

**Seguridad**
- Las tablas están **bloqueadas** (RLS): la app no puede leerlas ni escribirlas directamente.
- La app solo puede llamar a funciones (`adulto_*`, `familiar_*`, `unirse`, `crear_familia`) y cada una pide un **secreto**:
  la persona usa su *llave* (que solo vive en su teléfono) y cada familiar su propio *token*.
- El **código de 8 letras** solo sirve para *pedir* unirse: la persona debe autorizar.
- La **privacidad se aplica en el servidor**: si María desactiva "Mis medicinas", Carlos ya no las recibe, aunque modifique la app.
- Si María deja de compartir su ubicación, esta **se borra de la nube**.
- **Solo quien está autorizado puede leer o escribir en el chat.** Un familiar pendiente, rechazado o quitado no puede leer ni mandar mensajes, y el chat de una familia nunca se mezcla con el de otra.
- Puede quitar a un familiar o **desconectar y borrar todo** desde Mi perfil: eso también borra los mensajes de la nube.

---

## Límites (conviene decirlos con honestidad en la presentación)

- **Avisos con la app cerrada:** el familiar recibe la alerta mientras su app está abierta o recién usada. Para avisarle con la app totalmente cerrada hace falta *push* (Firebase Cloud Messaging): es la siguiente fase.
- **Chat:** es **un solo chat compartido** por la persona y todos sus familiares autorizados (no hay chats privados entre dos). Se actualiza cada ~6 s con el chat abierto y cada ~18 s con la app abierta en otra pantalla; **no hay avisos con la app cerrada** (también requiere push). Se conservan los últimos 200 mensajes y nada de más de 30 días, para no llenar el plan gratuito. Los mensajes **no van cifrados de punta a punta** (están en tu proyecto de Supabase); no son para datos muy delicados.
- **Plan gratuito:** Supabase **pausa** los proyectos gratuitos con poca actividad durante 7 días (te avisa por correo antes). Si la app dice que no se puede conectar, entra a supabase.com, abre tu proyecto y pulsa **Resume project**: vuelve igual que estaba, con sus datos. Úsala al menos una vez por semana para que no se pause.
- **Es un proyecto escolar:** no hay cuentas con correo ni límites contra abusos. Antes de publicarla de verdad harían falta cuentas (Supabase Auth), un aviso de privacidad y consentimiento, porque son datos de salud.
- **Sin internet:** la app sigue funcionando en el teléfono. Si se pide ayuda sin internet, la alerta espera y se envía sola al volver la conexión.

## Si algo falla

| Mensaje en la app | Qué hacer |
|---|---|
| *"La conexión con la nube aún no está configurada"* | Falta llenar `www/nube-config.js` (paso 4) o volver a compilar el APK. |
| *"La clave de la nube no es correcta"* | Copiaste mal la clave o usaste la `secret`. Usa la *Publishable* o *anon public* (paso 3). |
| *"Ese código no existe"* | El código cambió o tiene un error. Pídelo de nuevo (Mi perfil → Familia conectada). |
| *"No hay conexión con internet"* | Revisa el internet del teléfono. Si sí hay, el proyecto puede estar pausado (ver arriba). |
| *"Los mensajes aún no están activados en la nube: falta actualizar la base de datos"* | El script del paso 2 es de una versión anterior. Pégalo completo otra vez y pulsa **Run**. |
| *"Para grabar necesitas permitir el micrófono…"* | En el teléfono: Ajustes → Apps → VidaMayor → Permisos → **Micrófono → Permitir**. |
| *"No se pudo conectar con la nube"* | Casi siempre es que el script del paso 2 no se ejecutó completo. Vuelve a pegarlo y pulsa **Run** (es seguro repetirlo). |
