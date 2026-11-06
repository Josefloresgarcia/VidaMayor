// Ajusta el proyecto Android que crea `cap add android`:
//  1) permisos que necesita VidaMayor (avisos, alarmas exactas, ubicación)
//  2) pantalla siempre vertical
//  3) ícono blanco para las notificaciones (ic_stat_vidamayor)
// Es seguro ejecutarlo más de una vez.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../android/app/src/main/', import.meta.url));
const manifestPath = join(root, 'AndroidManifest.xml');

if (!existsSync(manifestPath)) {
  console.error('No encuentro android/app/src/main/AndroidManifest.xml. Ejecuta primero: npx cap add android');
  process.exit(1);
}

let xml = await readFile(manifestPath, 'utf8');

const permisos = [
  'android.permission.INTERNET',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.SCHEDULE_EXACT_ALARM',
  'android.permission.USE_EXACT_ALARM',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'android.permission.VIBRATE',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
];

const faltan = permisos.filter((p) => !xml.includes(`"${p}"`));
if (faltan.length) {
  const lineas = faltan.map((p) => `    <uses-permission android:name="${p}" />`).join('\n');
  xml = xml.replace('</manifest>', `\n    <!-- VidaMayor -->\n${lineas}\n</manifest>`);
  console.log('Permisos agregados:', faltan.length);
}

if (!/android:screenOrientation=/.test(xml)) {
  xml = xml.replace(/<activity\b/, '<activity\n            android:screenOrientation="portrait"');
  console.log('Orientación vertical activada');
}

await writeFile(manifestPath, xml);

// Ícono de notificación: corazón blanco (Android lo tiñe con iconColor)
const drawableDir = join(root, 'res', 'drawable');
await mkdir(drawableDir, { recursive: true });
const icono = `<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z" />
</vector>
`;
await writeFile(join(drawableDir, 'ic_stat_vidamayor.xml'), icono);
console.log('Ícono de notificación creado');
