-- ═══════════════════════════════════════════════════════════════════
--  VidaMayor · Base de datos para "Familia conectada" (Supabase / PostgreSQL)
--
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este archivo → Run.
--  Es seguro ejecutarlo más de una vez.
--
--  Idea de seguridad (explicable en la escuela):
--   · Las 4 tablas están BLOQUEADAS: la app no puede leerlas ni escribirlas directamente.
--   · La app solo puede llamar a unas funciones (adulto_* y familiar_*), y cada función
--     pide un secreto:
--        - el ADULTO usa su "llave" (un UUID que solo vive en su teléfono),
--        - cada FAMILIAR usa su "token" (otro UUID, uno por persona).
--     El "código familiar" (8 letras) solo sirve para pedir unirse; el adulto debe autorizar.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Tablas ─────────────────────────────────────────────────────

-- Una fila por persona mayor que usa VidaMayor
create table if not exists public.familias (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique,                 -- código para que la familia se una (ej. K7M2XQ9P)
  llave         uuid not null default gen_random_uuid(), -- secreto del adulto (no se comparte)
  adulto_nombre text not null default '' check (char_length(adulto_nombre) <= 60),
  privacidad    jsonb not null default '{"meds": true, "appts": true, "location": false}',
  resumen       jsonb not null default '{}' check (octet_length(resumen::text) < 30000),
  ubicacion     jsonb,                                -- {lat, lng, acc, at}; null si no la comparte
  creada        timestamptz not null default now(),
  actualizada   timestamptz not null default now()
);

-- Familiares que pidieron conectarse (el adulto decide si los autoriza)
create table if not exists public.miembros (
  id           uuid primary key default gen_random_uuid(),
  familia_id   uuid not null references public.familias(id) on delete cascade,
  nombre       text not null check (char_length(nombre) between 1 and 60),
  relacion     text not null default '' check (char_length(relacion) <= 40),
  token        uuid not null unique default gen_random_uuid(), -- secreto del familiar
  autorizado   boolean not null default false,
  unido        timestamptz not null default now(),
  ultima_vista timestamptz
);
create index if not exists miembros_familia_idx on public.miembros (familia_id);

-- Alertas de emergencia
create table if not exists public.alertas (
  id         uuid primary key default gen_random_uuid(),
  familia_id uuid not null references public.familias(id) on delete cascade,
  creada     timestamptz not null default now(),
  ubicacion  jsonb,
  cerrada    timestamptz,                              -- null = sigue activa
  vistas     jsonb not null default '[]'               -- [{miembro, nombre, at}] quién ya la vio
);
-- Solo puede haber UNA alerta activa por familia
create unique index if not exists alertas_una_activa on public.alertas (familia_id) where cerrada is null;
create index if not exists alertas_familia_idx on public.alertas (familia_id, creada desc);

-- Mensajes del chat familiar: texto y notas de voz (el audio va como texto base64, máx. 1 minuto)
create table if not exists public.mensajes (
  seq        bigint generated always as identity,         -- orden de llegada
  id         uuid primary key default gen_random_uuid(),
  familia_id uuid not null references public.familias(id) on delete cascade,
  autor      text not null,                               -- 'adulto' o el id del familiar
  nombre     text not null check (char_length(nombre) between 1 and 60),
  tipo       text not null check (tipo in ('texto', 'voz')),
  texto      text check (char_length(texto) <= 1000),
  audio      text check (char_length(audio) <= 400000),
  mime       text,
  duracion   int check (duracion between 1 and 60),
  creada     timestamptz not null default now(),
  check ((tipo = 'texto' and texto is not null and audio is null)
      or (tipo = 'voz'   and audio is not null and texto is null))
);
create unique index if not exists mensajes_seq_idx on public.mensajes (seq);
create index if not exists mensajes_familia_idx on public.mensajes (familia_id, seq desc);

-- ─── 2. Candado: nadie toca las tablas directamente ────────────────
alter table public.familias enable row level security;
alter table public.miembros enable row level security;
alter table public.alertas  enable row level security;
alter table public.mensajes enable row level security;
-- (sin políticas = nadie con la clave pública puede leer ni escribir)
revoke all on public.familias from anon, authenticated;
revoke all on public.miembros from anon, authenticated;
revoke all on public.alertas  from anon, authenticated;
revoke all on public.mensajes from anon, authenticated;

-- ─── 3. Funciones auxiliares (internas, la app no puede llamarlas) ──

create or replace function public._norm_codigo(p text)
returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

-- Código de 8 símbolos (sin I, O, 0 ni 1 para no confundirlos), tomado de bytes aleatorios seguros
create or replace function public._codigo_nuevo()
returns text language plpgsql volatile as $$
declare
  alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 símbolos
  u text; res text; i int;
begin
  loop
    u := replace(gen_random_uuid()::text, '-', '');
    res := '';
    -- se saltan los bytes 6 y 8 del UUID porque tienen bits fijos (versión)
    foreach i in array array[0, 1, 2, 3, 4, 5, 10, 11] loop
      res := res || substr(alfabeto, (get_byte(decode(substr(u, 2 * i + 1, 2), 'hex'), 0) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.familias where codigo = res);
  end loop;
  return res;
end;
$$;

-- Deja solo lat/lng/acc/at válidos (o null)
create or replace function public._ubicacion_ok(p jsonb)
returns jsonb language plpgsql immutable as $$
declare v_lat numeric; v_lng numeric; v_acc numeric := 0;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  begin
    v_lat := (p ->> 'lat')::numeric;
    v_lng := (p ->> 'lng')::numeric;
  exception when others then
    return null;
  end;
  if v_lat is null or v_lng is null or v_lat not between -90 and 90 or v_lng not between -180 and 180 then
    return null;
  end if;
  if (p ->> 'acc') ~ '^[0-9]+(\.[0-9]+)?$' then v_acc := (p ->> 'acc')::numeric; end if;
  return jsonb_build_object('lat', v_lat, 'lng', v_lng, 'acc', round(v_acc),
                            'at', left(coalesce(p ->> 'at', ''), 40));
end;
$$;

-- Resuelve la llave del adulto → id de la familia (o error)
create or replace function public._familia_de_llave(p_llave uuid)
returns uuid language plpgsql stable as $$
declare v_id uuid;
begin
  select id into v_id from public.familias where llave = p_llave;
  if v_id is null then raise exception 'llave_invalida'; end if;
  return v_id;
end;
$$;

-- Resuelve el token de un familiar AUTORIZADO → su fila (o error)
create or replace function public._miembro_autorizado(p_token uuid)
returns public.miembros language plpgsql stable set search_path = public as $$
declare v_m public.miembros;
begin
  select * into v_m from public.miembros where token = p_token;
  if not found then raise exception 'token_invalido'; end if;
  if not v_m.autorizado then raise exception 'sin_permiso'; end if;
  return v_m;
end;
$$;

-- Chat: mensajes con número mayor a p_desde (sin el audio, que se pide aparte). Máximo 60.
create or replace function public._chat_leer(p_fam uuid, p_desde bigint)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'ahora', now(),
    'mensajes', coalesce((
      select jsonb_agg(jsonb_build_object('seq', t.seq, 'id', t.id, 'autor', t.autor, 'nombre', t.nombre,
                                          'tipo', t.tipo, 'texto', t.texto, 'dur', t.duracion, 'creada', t.creada)
                       order by t.seq)
      from (select * from public.mensajes
            where familia_id = p_fam and seq > coalesce(p_desde, 0)
            order by seq desc limit 60) t), '[]'::jsonb));
$$;

-- Chat: valida y guarda un mensaje (texto o voz) y limpia los más viejos
create or replace function public._chat_enviar(
  p_fam uuid, p_autor text, p_nombre text, p_tipo text, p_texto text, p_audio text, p_mime text, p_dur int)
returns jsonb language plpgsql set search_path = public as $$
declare v_texto text; v_dur int; v_row public.mensajes; v_corte bigint;
begin
  if p_tipo = 'texto' then
    v_texto := left(trim(coalesce(p_texto, '')), 1000);
    if v_texto = '' then raise exception 'mensaje_vacio'; end if;
  elsif p_tipo = 'voz' then
    if p_audio is null or p_audio = '' then raise exception 'mensaje_vacio'; end if;
    if char_length(p_audio) > 400000 then raise exception 'audio_grande'; end if;
    -- el audio debe ser base64 puro y el tipo, uno de audio conocido (nunca código)
    if p_audio !~ '^[A-Za-z0-9+/]+=*$' or coalesce(p_mime, '') !~ '^audio/(webm|ogg|mp4|mpeg|aac|wav|x-m4a)$' then
      raise exception 'audio_invalido';
    end if;
    v_dur := least(greatest(coalesce(p_dur, 1), 1), 60);
  else
    raise exception 'mensaje_invalido';
  end if;
  -- freno contra abusos: máximo 30 mensajes por minuto en cada familia
  if (select count(*) from public.mensajes where familia_id = p_fam and creada > now() - interval '1 minute') >= 30 then
    raise exception 'demasiados_mensajes';
  end if;
  insert into public.mensajes (familia_id, autor, nombre, tipo, texto, audio, mime, duracion)
  values (p_fam, p_autor, left(coalesce(nullif(trim(p_nombre), ''), 'Familia'), 60), p_tipo, v_texto,
          case when p_tipo = 'voz' then p_audio end, case when p_tipo = 'voz' then p_mime end, v_dur)
  returning * into v_row;
  -- limpieza: solo se conservan los últimos 200 mensajes y nada de más de 30 días
  select seq into v_corte from public.mensajes where familia_id = p_fam order by seq desc offset 199 limit 1;
  delete from public.mensajes
   where familia_id = p_fam and (creada < now() - interval '30 days' or seq < coalesce(v_corte, 0));
  return jsonb_build_object('id', v_row.id, 'seq', v_row.seq, 'creada', v_row.creada);
end;
$$;

-- Chat: el audio de UN mensaje de voz
create or replace function public._chat_audio(p_fam uuid, p_id uuid)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_m public.mensajes;
begin
  select * into v_m from public.mensajes where id = p_id and familia_id = p_fam and tipo = 'voz';
  if not found then raise exception 'mensaje_no_existe'; end if;
  return jsonb_build_object('audio', v_m.audio, 'mime', v_m.mime);
end;
$$;

-- ─── 4. Funciones del ADULTO (piden la llave) ──────────────────────

-- Crea la familia. Devuelve el código (para compartir) y la llave (para guardar en el teléfono).
create or replace function public.crear_familia(p_nombre text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_codigo text; v_llave uuid; v_id uuid;
begin
  v_codigo := public._codigo_nuevo();
  insert into public.familias (codigo, adulto_nombre)
  values (v_codigo, left(coalesce(nullif(trim(p_nombre), ''), ''), 60))
  returning id, llave into v_id, v_llave;
  return jsonb_build_object('codigo', v_codigo, 'llave', v_llave);
end;
$$;

-- Se llama cada pocos segundos: sube el resumen del día y devuelve familiares y alertas.
create or replace function public.adulto_sincronizar(
  p_llave uuid, p_nombre text, p_privacidad jsonb, p_resumen jsonb, p_ubicacion jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_priv jsonb; v_res jsonb; v_codigo text;
begin
  v_id := public._familia_de_llave(p_llave);
  v_priv := jsonb_build_object(
    'meds',     coalesce((p_privacidad ->> 'meds')::boolean, true),
    'appts',    coalesce((p_privacidad ->> 'appts')::boolean, true),
    'location', coalesce((p_privacidad ->> 'location')::boolean, false));
  v_res := case when p_resumen is not null and jsonb_typeof(p_resumen) = 'object' then p_resumen else '{}'::jsonb end;
  if octet_length(v_res::text) >= 30000 then raise exception 'resumen_grande'; end if;

  update public.familias set
    adulto_nombre = left(coalesce(nullif(trim(p_nombre), ''), 'Tu familiar'), 60),
    privacidad    = v_priv,
    resumen       = v_res,
    -- si el adulto no comparte la ubicación, se borra también de la nube
    ubicacion     = case when (v_priv ->> 'location')::boolean then public._ubicacion_ok(p_ubicacion) else null end,
    actualizada   = now()
  where id = v_id
  returning codigo into v_codigo;

  return jsonb_build_object(
    'ahora', now(),
    'codigo', v_codigo,
    'miembros', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'nombre', m.nombre, 'relacion', m.relacion,
                                          'autorizado', m.autorizado, 'unido', m.unido, 'ultima_vista', m.ultima_vista)
                       order by m.unido)
      from public.miembros m where m.familia_id = v_id), '[]'::jsonb),
    'alertas', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'creada', a.creada, 'cerrada', a.cerrada, 'vistas', a.vistas)
                       order by a.creada desc)
      from (select * from public.alertas where familia_id = v_id order by creada desc limit 5) a), '[]'::jsonb));
end;
$$;

create or replace function public.adulto_autorizar(p_llave uuid, p_miembro uuid, p_autorizado boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._familia_de_llave(p_llave);
  update public.miembros set autorizado = coalesce(p_autorizado, false)
  where id = p_miembro and familia_id = v_id;
  return jsonb_build_object('ok', found);
end;
$$;

create or replace function public.adulto_quitar_miembro(p_llave uuid, p_miembro uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._familia_de_llave(p_llave);
  delete from public.miembros where id = p_miembro and familia_id = v_id;
  return jsonb_build_object('ok', found);
end;
$$;

-- Cambia el código (los que ya están conectados siguen conectados; los nuevos usan el nuevo)
create or replace function public.adulto_nuevo_codigo(p_llave uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_codigo text;
begin
  v_id := public._familia_de_llave(p_llave);
  v_codigo := public._codigo_nuevo();
  update public.familias set codigo = v_codigo where id = v_id;
  return jsonb_build_object('codigo', v_codigo);
end;
$$;

-- Emergencia. Si ya hay una alerta activa devuelve esa misma (así reintentar no duplica).
create or replace function public.adulto_pedir_ayuda(p_llave uuid, p_ubicacion jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_alerta uuid; v_priv boolean;
begin
  v_id := public._familia_de_llave(p_llave);
  select (privacidad ->> 'location')::boolean into v_priv from public.familias where id = v_id;
  insert into public.alertas (familia_id, ubicacion)
  values (v_id, case when v_priv then public._ubicacion_ok(p_ubicacion) else null end)
  on conflict (familia_id) where cerrada is null do nothing
  returning id into v_alerta;
  if v_alerta is null then
    select id into v_alerta from public.alertas where familia_id = v_id and cerrada is null;
  end if;
  return jsonb_build_object('alerta', v_alerta);
end;
$$;

-- La ubicación suele llegar unos segundos después de pedir ayuda
create or replace function public.adulto_alerta_ubicacion(p_llave uuid, p_alerta uuid, p_ubicacion jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_priv boolean;
begin
  v_id := public._familia_de_llave(p_llave);
  select (privacidad ->> 'location')::boolean into v_priv from public.familias where id = v_id;
  if v_priv then
    update public.alertas set ubicacion = public._ubicacion_ok(p_ubicacion)
    where id = p_alerta and familia_id = v_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.adulto_cerrar_alerta(p_llave uuid, p_alerta uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._familia_de_llave(p_llave);
  update public.alertas set cerrada = now()
  where id = p_alerta and familia_id = v_id and cerrada is null;
  return jsonb_build_object('ok', true);
end;
$$;

-- Borra todo lo de esta familia de la nube
create or replace function public.adulto_borrar_familia(p_llave uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._familia_de_llave(p_llave);
  delete from public.familias where id = v_id;   -- miembros, alertas y mensajes se borran en cascada
  return jsonb_build_object('ok', true);
end;
$$;

-- Chat del adulto: leer, enviar y pedir el audio de un mensaje de voz
create or replace function public.adulto_chat_leer(p_llave uuid, p_desde bigint default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public._chat_leer(public._familia_de_llave(p_llave), p_desde);
end;
$$;

create or replace function public.adulto_chat_enviar(
  p_llave uuid, p_tipo text, p_texto text default null, p_audio text default null, p_mime text default null, p_dur int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_nombre text;
begin
  v_id := public._familia_de_llave(p_llave);
  select adulto_nombre into v_nombre from public.familias where id = v_id;
  return public._chat_enviar(v_id, 'adulto', coalesce(nullif(v_nombre, ''), 'Tu familiar'), p_tipo, p_texto, p_audio, p_mime, p_dur);
end;
$$;

create or replace function public.adulto_chat_audio(p_llave uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public._chat_audio(public._familia_de_llave(p_llave), p_id);
end;
$$;

-- ─── 5. Funciones del FAMILIAR ─────────────────────────────────────

-- Pide unirse con el código. Queda "pendiente" hasta que el adulto lo autorice.
create or replace function public.unirse(p_codigo text, p_nombre text, p_relacion text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_fam public.familias; v_miembro public.miembros; v_nombre text;
begin
  v_nombre := left(trim(coalesce(p_nombre, '')), 60);
  if v_nombre = '' then raise exception 'nombre_requerido'; end if;
  select * into v_fam from public.familias where codigo = public._norm_codigo(p_codigo);
  if not found then raise exception 'codigo_invalido'; end if;
  if (select count(*) from public.miembros where familia_id = v_fam.id) >= 8 then
    raise exception 'familia_llena';
  end if;
  insert into public.miembros (familia_id, nombre, relacion)
  values (v_fam.id, v_nombre, left(trim(coalesce(p_relacion, '')), 40))
  returning * into v_miembro;
  return jsonb_build_object('token', v_miembro.token, 'miembro', v_miembro.id, 'adulto', v_fam.adulto_nombre);
end;
$$;

-- Lo que ve el familiar. El filtro de privacidad se aplica AQUÍ, en el servidor.
create or replace function public.familiar_leer(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m public.miembros; v_f public.familias; v_res jsonb;
begin
  select * into v_m from public.miembros where token = p_token;
  if not found then raise exception 'token_invalido'; end if;
  select * into v_f from public.familias where id = v_m.familia_id;
  update public.miembros set ultima_vista = now() where id = v_m.id;

  if not v_m.autorizado then
    return jsonb_build_object('autorizado', false, 'adulto', v_f.adulto_nombre, 'ahora', now());
  end if;

  v_res := v_f.resumen;
  if not coalesce((v_f.privacidad ->> 'meds')::boolean, true)  then v_res := v_res - 'meds';  end if;
  if not coalesce((v_f.privacidad ->> 'appts')::boolean, true) then v_res := v_res - 'appts'; end if;

  return jsonb_build_object(
    'autorizado', true,
    'ahora', now(),
    'adulto', v_f.adulto_nombre,
    'privacidad', v_f.privacidad,
    'resumen', v_res,
    'ubicacion', case when coalesce((v_f.privacidad ->> 'location')::boolean, false) then v_f.ubicacion else null end,
    'actualizada', v_f.actualizada,
    'alertas', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'creada', a.creada, 'cerrada', a.cerrada,
                                          'ubicacion', a.ubicacion, 'vistas', a.vistas)
                       order by a.creada desc)
      from (select * from public.alertas where familia_id = v_f.id order by creada desc limit 3) a), '[]'::jsonb));
end;
$$;

-- "Ya la vi": el adulto lo ve en su pantalla de emergencia
create or replace function public.familiar_atender_alerta(p_token uuid, p_alerta uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m public.miembros;
begin
  select * into v_m from public.miembros where token = p_token and autorizado;
  if not found then raise exception 'token_invalido'; end if;
  update public.alertas
     set vistas = vistas || jsonb_build_array(jsonb_build_object('miembro', v_m.id::text, 'nombre', v_m.nombre, 'at', now()))
   where id = p_alerta and familia_id = v_m.familia_id
     and not (vistas @> jsonb_build_array(jsonb_build_object('miembro', v_m.id::text)));
  return jsonb_build_object('ok', true);
end;
$$;

-- El familiar se desconecta
create or replace function public.familiar_salir(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from public.miembros where token = p_token;
  return jsonb_build_object('ok', true);
end;
$$;

-- Chat del familiar (solo si el adulto ya lo autorizó): leer, enviar y pedir el audio
create or replace function public.familiar_chat_leer(p_token uuid, p_desde bigint default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m public.miembros;
begin
  v_m := public._miembro_autorizado(p_token);
  return public._chat_leer(v_m.familia_id, p_desde);
end;
$$;

create or replace function public.familiar_chat_enviar(
  p_token uuid, p_tipo text, p_texto text default null, p_audio text default null, p_mime text default null, p_dur int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m public.miembros;
begin
  v_m := public._miembro_autorizado(p_token);
  return public._chat_enviar(v_m.familia_id, v_m.id::text, v_m.nombre, p_tipo, p_texto, p_audio, p_mime, p_dur);
end;
$$;

create or replace function public.familiar_chat_audio(p_token uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m public.miembros;
begin
  v_m := public._miembro_autorizado(p_token);
  return public._chat_audio(v_m.familia_id, p_id);
end;
$$;

-- ─── 6. Permisos: la app solo puede llamar a las funciones públicas ─
revoke all on function public._norm_codigo(text)                  from public, anon, authenticated;
revoke all on function public._codigo_nuevo()                     from public, anon, authenticated;
revoke all on function public._ubicacion_ok(jsonb)                from public, anon, authenticated;
revoke all on function public._familia_de_llave(uuid)             from public, anon, authenticated;
revoke all on function public._miembro_autorizado(uuid)           from public, anon, authenticated;
revoke all on function public._chat_leer(uuid, bigint)            from public, anon, authenticated;
revoke all on function public._chat_enviar(uuid, text, text, text, text, text, text, int) from public, anon, authenticated;
revoke all on function public._chat_audio(uuid, uuid)             from public, anon, authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'crear_familia(text)',
    'adulto_sincronizar(uuid,text,jsonb,jsonb,jsonb)',
    'adulto_autorizar(uuid,uuid,boolean)',
    'adulto_quitar_miembro(uuid,uuid)',
    'adulto_nuevo_codigo(uuid)',
    'adulto_pedir_ayuda(uuid,jsonb)',
    'adulto_alerta_ubicacion(uuid,uuid,jsonb)',
    'adulto_cerrar_alerta(uuid,uuid)',
    'adulto_borrar_familia(uuid)',
    'adulto_chat_leer(uuid,bigint)',
    'adulto_chat_enviar(uuid,text,text,text,text,int)',
    'adulto_chat_audio(uuid,uuid)',
    'unirse(text,text,text)',
    'familiar_leer(uuid)',
    'familiar_atender_alerta(uuid,uuid)',
    'familiar_salir(uuid)',
    'familiar_chat_leer(uuid,bigint)',
    'familiar_chat_enviar(uuid,text,text,text,text,int)',
    'familiar_chat_audio(uuid,uuid)']
  loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;
