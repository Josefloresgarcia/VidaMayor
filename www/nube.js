/* VidaMayor — conexión con la nube (Supabase)
   Solo hace una cosa: llamar a las funciones de la base de datos (supabase/esquema.sql)
   con `fetch`, sin librerías. Si nube-config.js está vacío, la app funciona pero
   "Familia conectada" no está disponible. */
(() => {
  'use strict';
  const cfg = () => window.VIDAMAYOR_NUBE || {};
  const base = () => String(cfg().url || '').trim().replace(/\/+$/, '');
  const clave = () => String(cfg().clave || '').trim();

  /** ¿Hay una dirección y una clave puestas en nube-config.js? */
  const configured = () => /^https?:\/\/[^\s/]+/.test(base()) && clave().length > 20;

  // Mensajes de error de la base de datos → texto para personas
  const MENSAJES = {
    codigo_invalido: 'Ese código no existe. Revísalo con tu familiar.',
    nombre_requerido: 'Escribe tu nombre.',
    familia_llena: 'Esa familia ya tiene el máximo de familiares conectados.',
    token_invalido: 'Esta conexión ya no es válida.',
    llave_invalida: 'Esta conexión ya no es válida.',
    resumen_grande: 'Hay demasiada información para sincronizar.',
  };

  class NubeError extends Error {
    constructor(code, status) { super(code); this.name = 'NubeError'; this.code = code; this.status = status || 0; }
  }

  /** Llama a una función de la base de datos. Devuelve el JSON que responde. */
  async function rpc(fn, args = {}, { timeout = 12000 } = {}) {
    if (!configured()) throw new NubeError('sin_configurar');
    const ctl = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = ctl ? setTimeout(() => ctl.abort(), timeout) : null;
    const headers = { 'Content-Type': 'application/json', apikey: clave() };
    // La clave anónima clásica es un JWT (empieza con "eyJ"); las claves nuevas ("sb_publishable_…") no se mandan como Bearer
    if (/^eyJ/.test(clave())) headers.Authorization = `Bearer ${clave()}`;
    let res;
    try {
      res = await fetch(`${base()}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args), signal: ctl ? ctl.signal : undefined });
    } catch (e) {
      throw new NubeError(ctl && ctl.signal.aborted ? 'tiempo' : 'red');
    } finally { if (timer) clearTimeout(timer); }
    let body = null;
    try { body = await res.json(); } catch (e) { /* sin cuerpo */ }
    if (!res.ok) {
      const msg = body && typeof body.message === 'string' ? body.message : '';
      throw new NubeError(MENSAJES[msg] ? msg : (res.status === 401 || res.status === 403 ? 'clave' : 'servidor'), res.status);
    }
    return body;
  }

  /** Texto en español para mostrar al usuario */
  function errMsg(e) {
    const c = e && e.code;
    if (MENSAJES[c]) return MENSAJES[c];
    if (c === 'sin_configurar') return 'La conexión con la nube aún no está configurada en esta app.';
    if (c === 'red' || c === 'tiempo') return 'No hay conexión con internet. Inténtalo de nuevo en un momento.';
    if (c === 'clave') return 'La clave de la nube no es correcta (revisa nube-config.js).';
    return 'No se pudo conectar con la nube. Inténtalo de nuevo.';
  }

  window.VMNube = { configured, rpc, errMsg };
})();
