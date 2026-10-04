<?php
// Páxina de comprobación da contorna. Pódela borrar cando todo funcione.
declare(strict_types=1);

$checks = [];

$checks['PHP'] = [true, PHP_VERSION];

$xdebug = extension_loaded('xdebug');
$checks['Xdebug'] = [$xdebug, $xdebug ? phpversion('xdebug') . ' · modo: ' . implode(',', xdebug_info('mode')) : 'non cargado'];

foreach (['bcmath', 'pdo_mysql', 'mysqli', 'intl', 'zip', 'gd'] as $ext) {
    $checks["ext/$ext"] = [extension_loaded($ext), extension_loaded($ext) ? 'ok' : 'falta'];
}

try {
    $dsn = sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', getenv('DB_HOST'), getenv('DB_NAME'));
    $pdo = new PDO($dsn, getenv('DB_USER'), getenv('DB_PASSWORD'), [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $version = $pdo->query('SELECT VERSION()')->fetchColumn();
    $filas = $pdo->query('SELECT COUNT(*) FROM alumnado')->fetchColumn();
    $checks['Base de datos'] = [true, "$version · táboa alumnado: $filas filas"];
} catch (PDOException $e) {
    $checks['Base de datos'] = [false, $e->getMessage()];
}

$checks['Servidor web'] = [true, ($_SERVER['SERVER_SOFTWARE'] ?? PHP_SAPI) . ' · ' . ($_SERVER['REQUEST_SCHEME'] ?? 'http')];

$usuario = posix_getpwuid(posix_geteuid())['name'] ?? '?';
$checks['Usuario PHP'] = [true, $usuario . ' (uid ' . posix_geteuid() . ')'];
?>
<!doctype html>
<html lang="gl">
<head>
    <meta charset="utf-8">
    <title>DWCS · contorna PHP</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; }
        td { padding: .35rem .75rem; border-bottom: 1px solid #ddd; }
        .ok { color: #1a7f37; } .ko { color: #cf222e; }
    </style>
</head>
<body>
    <h1>Contorna DWCS</h1>
    <table>
        <?php foreach ($checks as $nome => [$ok, $detalle]): ?>
            <tr>
                <td class="<?= $ok ? 'ok' : 'ko' ?>"><?= $ok ? '✔' : '✘' ?></td>
                <td><?= htmlspecialchars($nome) ?></td>
                <td><?= htmlspecialchars((string) $detalle) ?></td>
            </tr>
        <?php endforeach ?>
    </table>
    <p>
        <a href="info.php">phpinfo()</a> ·
        <a href="http://localhost:8081" target="_blank">phpMyAdmin</a>
    </p>
</body>
</html>
