# Proxecto con cliente e servidor en DAW Dev

Para un proxecto que combina Angular no cliente e PHP no servidor (Laravel,
por exemplo), DAW Dev xunta os tres contedores nunha mesma rede:

| Contedor | Que ten | Os teus ficheiros |
|---|---|---|
| `daw-dev-web` | Apache, PHP 8.5, Composer | `www`, en `http://localhost` |
| `daw-dev-db` | MariaDB | base de datos `dwcs` |
| `daw-dev-angular` | Node.js 26, npm, Angular CLI 22 | `angular` e tamén `www`, en `~/www` |

Desde Angular, o servidor web é `http://web` e a base de datos é `db`. O
contedor de Angular ve tamén `www`: alí compila con Node os recursos dun
proxecto Laravel.

## Abrir o proxecto

Nun terminal de PowerShell:

```powershell
daw-code-proxecto
```

A orde arranca os tres contedores e abre VS Code en Debian co espazo de
traballo **DAW-Proxecto**. Ten dous cartafoles, **Angular** e **Web
(www)**, e un terminal en cada contedor:

- **Angular no contedor**, co usuario `node`: `ng`, `npm` e `node`.
- **PHP no contedor web**, co usuario `dev`: `php`, `composer` e
  `mariadb`.

A primeira vez, acepta a confianza nos autores e as tarefas automáticas,
como na guía de Angular. Se VS Code pregunta en que cartafol abrir un
terminal novo, escolle calquera: os dous entran no seu contedor.

## Crear un proxecto Laravel

No terminal **PHP no contedor web**:

```bash
composer create-project laravel/laravel proxecto
cd proxecto
sed -i '1i DirectoryIndex index.php' public/.htaccess
```

`composer create-project` tarda uns 20 segundos. DAW Dev amosa a listaxe
de ficheiros de cada cartafol en vez do seu `index.php`. A liña
`DirectoryIndex index.php` volve activar o índice só no `public` de
Laravel. Sen ela, a páxina principal dá o erro 403.

A aplicación está en `http://localhost/proxecto/public/`.

### Permisos na aula

Na aula, Apache executa PHP como `www-data`, igual ca na VM de DWCS, e
Laravel ten que escribir en `storage` e `bootstrap/cache`. Sen este paso,
a páxina dá o erro 500:

```bash
sudo chgrp -R www-data storage bootstrap/cache
sudo chmod -R g+w storage bootstrap/cache
find storage bootstrap/cache -type d -exec sudo chmod g+s {} +
```

Fóra da aula, Apache executa PHP co usuario `dev`, o mesmo que crea os
ficheiros, e non fai falta.

### Base de datos

En `.env` do proxecto, cambia a conexión a MariaDB:

```ini
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dwcs
DB_USERNAME=dwcs
DB_PASSWORD=abc123.
```

Despois, no mesmo terminal, `php artisan migrate`.

## Recursos de Laravel con Node

No terminal **Angular no contedor**, o proxecto Laravel está en
`~/www/proxecto`:

```bash
cd ~/www/proxecto
npm install
npm run build
```

A páxina carga os recursos compilados de `public/build` sen máis cambios.

Para traballar con Vite en modo desenvolvemento, o servidor de Vite ten que
atender fóra do contedor. En `vite.config.js`, engade `host` e `hmr` ao
bloque `server` que trae Laravel:

```js
    server: {
        host: '0.0.0.0',
        hmr: { host: 'localhost' },
        watch: {
            ignored: ['**/storage/framework/views/**'],
        },
    },
```

Logo, no terminal de Angular, `npm run dev`. A páxina de Laravel carga os
recursos desde `http://localhost:5173` e recárgase ao gardar unha vista
Blade. `Ctrl+C` para Vite; con `npm run build` volve usar os recursos
compilados.

## Angular contra o PHP

Unha aplicación Angular en `angular` chama ao PHP de `www` co *proxy* de
`ng serve`, sen problemas de CORS. Se a ruta do *proxy* é a mesma ca en
Apache, non hai que reescribila. Para o proxecto Laravel anterior, en
`proxy.conf.json` da aplicación Angular:

```json
{ "/proxecto": { "target": "http://web", "changeOrigin": true } }
```

No terminal de Angular, desde o cartafol da aplicación:

```bash
ng serve --host 0.0.0.0 --proxy-config proxy.conf.json
```

Desde `http://localhost:4200`, unha petición a
`/proxecto/public/api/...` chega a Laravel. As rutas `api` engádense ao
proxecto con `php artisan install:api`.

## Ao rematar

`Ctrl+C` nos terminais onde se executan `ng serve` ou `npm run dev`,
pecha VS Code e, en PowerShell, `daw-stop`. Os ficheiros e a base de
datos consérvanse.
