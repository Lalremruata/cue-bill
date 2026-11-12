<?php
/**
 * CueBill installer: copies the CueBill files into a fresh Laravel 12 project
 * that already has Filament installed (see README.md).
 *
 * Usage (from anywhere):  php path/to/cuebill-files/install.php path/to/laravel-project
 */

$source = __DIR__;
$target = rtrim($argv[1] ?? getcwd(), '/\\');

if (! is_file($target.'/artisan')) {
    fwrite(STDERR, "No Laravel project found at {$target} (artisan missing).\n");
    exit(1);
}
if (! is_dir($target.'/vendor/filament/filament')) {
    fwrite(STDERR, "Filament is not installed yet. Run: composer require filament/filament:\"^4.0\" barryvdh/laravel-dompdf bacon/bacon-qr-code openspout/openspout -W\n");
    exit(1);
}

$folders = ['app', 'bootstrap', 'database', 'design', 'public', 'resources', 'routes', 'tests'];
$copied = 0;
foreach ($folders as $folder) {
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($source.'/'.$folder, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $file) {
        $relative = substr($file->getPathname(), strlen($source) + 1);
        $dest = $target.'/'.$relative;
        if (! is_dir(dirname($dest))) {
            mkdir(dirname($dest), 0775, true);
        }
        copy($file->getPathname(), $dest);
        $copied++;
    }
}
copy($source.'/CLAUDE.md', $target.'/CLAUDE.md');
$copied++;
echo "Copied {$copied} files (including CLAUDE.md and the design/ handoff for Claude Code).\n";

// Indian time for invoices and reports.
$config = $target.'/config/app.php';
$php = file_get_contents($config);
$patched = preg_replace("/'timezone'\s*=>\s*[^,]+,/", "'timezone' => env('APP_TIMEZONE', 'Asia/Kolkata'),", $php, 1);
if ($patched !== $php) {
    file_put_contents($config, $patched);
    echo "Timezone set to Asia/Kolkata (config/app.php).\n";
}

// Make sure the Filament panel provider is registered.
$providers = $target.'/bootstrap/providers.php';
$list = file_get_contents($providers);
if (! str_contains($list, 'AdminPanelProvider')) {
    $list = str_replace('];', "    App\\Providers\\Filament\\AdminPanelProvider::class,\n];", $list);
    file_put_contents($providers, $list);
    echo "Registered AdminPanelProvider in bootstrap/providers.php.\n";
}

echo "\nNext:\n  php artisan migrate --seed\n  php artisan storage:link\n  php artisan db:seed --class=DemoSalesSeeder   (optional sample sales)\n  php artisan serve\n";
