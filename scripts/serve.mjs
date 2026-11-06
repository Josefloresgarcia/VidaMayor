// Servidor mínimo para ver la app en el navegador mientras la programas.
//   npm run dev   ->   http://localhost:5173
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../www/', import.meta.url));
const port = Number(process.env.PORT) || 5173;
const tipos = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
};

http
  .createServer(async (req, res) => {
    try {
      let ruta = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      if (ruta.endsWith('/')) ruta += 'index.html';
      const archivo = join(root, normalize(ruta));
      if (!archivo.startsWith(root.endsWith(sep) ? root : root + sep)) {
        res.writeHead(403).end('Prohibido');
        return;
      }
      const datos = await readFile(archivo);
      res.writeHead(200, {
        'Content-Type': tipos[extname(archivo)] || 'application/octet-stream',
        'Cache-Control': 'no-store',
      });
      res.end(datos);
    } catch {
      res.writeHead(404).end('No encontrado');
    }
  })
  .listen(port, () => console.log(`VidaMayor en http://localhost:${port}`));
