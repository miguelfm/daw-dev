#!/usr/bin/env python3
"""Run the actual web root backup and restore Bash on private fixture trees.
wslpath is stubbed: C:\\a\\b maps to <fixture>/c/a/b.
DAW_WEBROOT_SCRIPTS can point to a directory with backup.sh and restore.sh already exported
from the module, to run without pwsh.
"""
import os, pathlib, shutil, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
pwsh = os.environ.get('PWSH_BIN', 'pwsh')
WSLPATH = r'''#!/usr/bin/env bash
[[ $1 == -u ]] && shift
p=${1//\\//}
[[ $p =~ ^([A-Za-z]):(.*)$ ]] && p="$DAW_FIXTURE/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
printf '%s\n' "$p"
'''

with tempfile.TemporaryDirectory(prefix='daw-webroot-') as tmp:
    base = pathlib.Path(tmp)
    backup, restore = base / 'backup.sh', base / 'restore.sh'
    if os.environ.get('DAW_WEBROOT_SCRIPTS'):
        source = pathlib.Path(os.environ['DAW_WEBROOT_SCRIPTS'])
        shutil.copy(source / 'backup.sh', backup); shutil.copy(source / 'restore.sh', restore)
    else:
        env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(base))
        subprocess.run([pwsh, '-NoProfile', '-Command',
            'Import-Module $env:DAW_TEST_MODULE -Force; $e=New-Object Text.UTF8Encoding($false);'
            '[IO.File]::WriteAllText((Join-Path $env:DAW_TEST_OUTPUT backup.sh),(Get-DawWebRootBackupScript),$e);'
            '[IO.File]::WriteAllText((Join-Path $env:DAW_TEST_OUTPUT restore.sh),(Get-DawWebRootRestoreScript),$e)'],
            env=env, check=True)
    for script in (backup, restore):
        assert b'\r' not in script.read_bytes()
        subprocess.run(['bash', '-n', str(script)], check=True)
    count = 0

    def fixture(name):
        root = base / name
        (root / 'bin').mkdir(parents=True)
        (root / 'bin/wslpath').write_text(WSLPATH); (root / 'bin/wslpath').chmod(0o755)
        (root / 'c/Users/a/Documents').mkdir(parents=True)
        return root

    def run(root, script, *args):
        env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'], DAW_FIXTURE=str(root))
        return subprocess.run(['bash', str(script), *args], env=env, capture_output=True, text=True)

    def project(root, www='www', env=None):
        p = root / 'home/ad/proxectos/daw-dev'
        (p / www).mkdir(parents=True)
        (p / 'compose.yaml').write_text('services: {}\n')
        if env is not None:
            (p / '.env').write_text(env)
        return p

    def tree(path):
        return {str(f.relative_to(path)): f.read_bytes() for f in sorted(path.rglob('*')) if f.is_file()}

    dest = r'C:\Users\a\Documents\DAW-Dev-www-1-Debian'

    root = fixture('default')
    p = project(root)
    (p / 'www/u3/t1').mkdir(parents=True)
    (p / 'www/u3/t1/index.php').write_text('<?php echo 1;')
    (p / 'www/.htaccess').write_text('Options -Indexes')
    r = run(root, backup, dest, str(root / 'home/ad/daw'), str(p))
    assert r.returncode == 0 and r.stdout.split() == ['copied'], r.stderr
    copy = root / 'c/Users/a/Documents/DAW-Dev-www-1-Debian'
    assert tree(copy) == tree(p / 'www')
    count += 1; print('PASS copies the default web root of the first project found, hidden files included')

    r = run(root, backup, dest, str(p))
    assert r.returncode != 0 and 'non se sobrescribe' in r.stderr and tree(copy) == tree(p / 'www'), r.stderr
    count += 1; print('PASS an existing copy is never overwritten')

    root = fixture('www-dir')
    p = project(root, 'web', 'WEB_PORT=80\nWWW_DIR="./web"\n')
    (p / 'web/a.php').write_text('a')
    (p / 'www').mkdir(); (p / 'www/ignored.php').write_text('x')
    r = run(root, backup, dest, str(p))
    assert r.returncode == 0, r.stderr
    assert tree(root / 'c/Users/a/Documents/DAW-Dev-www-1-Debian') == {'a.php': b'a'}
    count += 1; print('PASS follows WWW_DIR from .env')

    for name, make in (('empty', lambda root: project(root)), ('no-project', lambda root: None)):
        root = fixture(name)
        make(root)
        r = run(root, backup, dest, str(root / 'home/ad/proxectos/daw-dev'))
        assert r.returncode == 0 and r.stdout == '' and not (root / 'c/Users/a/Documents/DAW-Dev-www-1-Debian').exists(), r.stderr
        count += 1; print(f'PASS nothing to copy: {name}')

    root = fixture('restore')
    src = root / 'c/Users/a/Documents/DAW-Dev-www-1-Debian'
    (src / 'u3').mkdir(parents=True)
    (src / 'index.php').write_text('student version')
    (src / 'u3/t1.php').write_text('t1')
    for f in (src / 'index.php', src / 'u3/t1.php', src / 'u3'):
        f.chmod(0o777)
    os.utime(src / 'u3/t1.php', (1_000_000_000, 1_000_000_000))
    www = root / 'home/ad/daw/www'
    www.mkdir(parents=True)
    (www / 'index.php').write_text('repository version'); (www / 'info.php').write_text('info')
    old = os.umask(0o022)
    try:
        r = run(root, restore, dest, str(www))
    finally:
        os.umask(old)
    assert r.returncode == 0, r.stderr
    assert (www / 'index.php').read_text() == 'student version' and (www / 'info.php').read_text() == 'info'
    assert (www / 'u3/t1.php').stat().st_mode & 0o777 == 0o644 and (www / 'u3').stat().st_mode & 0o777 == 0o755
    assert int((www / 'u3/t1.php').stat().st_mtime) == 1_000_000_000
    assert (src / 'index.php').exists(), 'The copy in Documents must be kept'
    count += 1; print('PASS restores over the new www with default permissions and the original dates')

    r = run(root, restore, r'C:\Users\a\Documents\missing', str(www))
    assert r.returncode != 0 and 'Falta a copia' in r.stderr, r.stderr
    count += 1; print('PASS a missing copy is an error')
print(f'ALL {count} WEB ROOT SCENARIOS PASSED')
