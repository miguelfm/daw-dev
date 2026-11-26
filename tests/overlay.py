#!/usr/bin/env python3
"""Run the actual project overlay Bash on private fixture trees.
docker is stubbed, except in the last scenario, which uses the real `docker compose config`
(it reads files only) on a copy of the repository Compose files when docker is installed.
DAW_OVERLAY_SCRIPT can point to the script already exported from the module, to run without pwsh.
"""
import hashlib, json, os, pathlib, shutil, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
pwsh = os.environ.get('PWSH_BIN', 'pwsh')
overlay = repo / 'windows/classroom/overlay'
STUB = r'''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['DAW_DOCKER_LOG'],'a') as f: f.write(json.dumps(args)+'\n')
fail=os.environ.get('DAW_DOCKER_FAIL','');pre='-f' in args
if '--images' in args:
    print(os.environ['DAW_DOCKER_IMAGE'])
loaded=pathlib.Path(os.environ['DAW_DOCKER_LOG']).with_suffix('.loaded')
if args[:2] == ['image', 'inspect']:
    sys.exit(0 if loaded.is_file() else 1)
if args[:1] == ['run'] and fail == 'legacy-image':
    sys.exit(1)
if args[:2] in (['image', 'load'], ['image', 'pull']):
    loaded.touch()
sys.exit(1 if (fail=='pre' and pre) or (fail=='post' and not pre) else 0)
'''

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot(root):
    state = {}
    for p in sorted(root.rglob('*')):
        rel = str(p.relative_to(root))
        state[rel] = ('link', os.readlink(p)) if p.is_symlink() else ('dir',) if p.is_dir() else ('file', p.read_bytes(), p.stat().st_mode & 0o777)
    return state

with tempfile.TemporaryDirectory(prefix='daw-overlay-') as tmp:
    base = pathlib.Path(tmp)
    script = base / 'overlay.sh'
    if os.environ.get('DAW_OVERLAY_SCRIPT'):
        shutil.copy(os.environ['DAW_OVERLAY_SCRIPT'], script)
    else:
        env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(script))
        subprocess.run([pwsh, '-NoProfile', '-Command',
            'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,(Get-DawProjectOverlayScript),(New-Object Text.UTF8Encoding($false)))'],
            env=env, check=True)
    assert b'\r' not in script.read_bytes()
    subprocess.run(['bash', '-n', str(script)], check=True)
    bin_dir = base / 'bin'; bin_dir.mkdir()
    (bin_dir / 'docker').write_text(STUB); (bin_dir / 'docker').chmod(0o755)
    count = 0

    def fixture(name):
        root = base / name
        src = root / 'src'; shutil.copytree(overlay, src)
        # As in New-DawProjectStage, the stage also carries the repository Compose and Angular files.
        shutil.copy(repo / 'compose.yaml', src / 'compose.yaml'); shutil.copytree(repo / 'docker/angular', src / 'docker/angular')
        project = root / 'home/ad/workspace'
        (project / 'www').mkdir(parents=True); (project / '.devcontainer').mkdir()
        (project / 'compose.yaml').write_text('services: {}\n')
        (project / 'www/work.php').write_text('student work')
        shutil.copy(repo / '.devcontainer/devcontainer.json', project / '.devcontainer/devcontainer.json')
        return root, src, project

    def triples(src):
        out = []
        for p in sorted(x for x in src.rglob('*') if x.is_file()):
            rel = str(p.relative_to(src))
            out += [rel, digest(p), 'CreateOnly' if rel.startswith('data/') else 'Replace']
        return out

    def run(root, src, project, args=None, fail='', path=None, image='', archive=('-', '-')):
        log = root / 'docker.log'
        log.unlink(missing_ok=True)
        env = dict(os.environ, PATH=path or (str(bin_dir) + os.pathsep + os.environ['PATH']), DAW_DOCKER_LOG=str(log), DAW_DOCKER_FAIL=fail, DAW_DOCKER_IMAGE=image)
        r = subprocess.run(['bash', str(script), str(src), *archive] + (triples(src) if args is None else args), cwd=project, env=env, capture_output=True, text=True)
        calls = [json.loads(l) for l in log.read_text().splitlines()] if log.exists() else []
        return r, calls

    def backups(project):
        b = project / '.daw-backup'
        return sorted(p.name for p in b.iterdir()) if b.exists() else []

    root, src, project = fixture('fresh')
    r, calls = run(root, src, project); assert r.returncode == 0, r.stderr
    lines = {path: action for action, path in (l.split(' ', 1) for l in r.stdout.splitlines() if not l.startswith('copia '))}
    assert lines['.devcontainer/devcontainer.json'] == 'substituido' and lines['compose.override.yaml'] == 'creado' and lines['data/README.txt'] == 'creado', r.stdout
    for rel in lines:
        assert digest(project / rel) == digest(src / rel) and (project / rel).stat().st_mode & 0o777 == 0o644, rel
    saved = project / '.daw-backup' / backups(project)[0] / '.devcontainer/devcontainer.json'
    assert saved.read_bytes() == (repo / '.devcontainer/devcontainer.json').read_bytes()
    assert (project / 'www/work.php').read_text() == 'student work'
    assert calls[0][:4] == ['compose', '--project-directory', str(project), '-f'] and calls[-1] == ['compose', 'config', '--quiet'], calls
    count += 1; print('PASS copies, keeps a backup of replaced files and validates Compose before and after')

    before = backups(project)
    r, calls = run(root, src, project); assert r.returncode == 0, r.stderr
    assert all(l.startswith('igual ') for l in r.stdout.splitlines()), r.stdout
    assert backups(project) == before
    count += 1; print('PASS second run changes nothing')

    root86, src86, project86 = fixture('php86-offline')
    env_file = project86 / '.env'
    env = 'DAW_DEV_IMAGE=ghcr.io/miguelfm/dwcs-php\nWEB_PORT=127.0.0.1:80\n'
    env_file.write_text(env)
    env_file.chmod(0o600)
    archive = root86 / 'daw-dev-php86.tar.gz'
    archive.write_bytes(b'docker image archive')
    image = 'ghcr.io/miguelfm/dwcs-php:8.6-ad'
    before86 = snapshot(project86)
    r, calls = run(root86, src86, project86, image=image, archive=(str(archive), '0' * 64))
    assert r.returncode != 0 and 'SHA256' in r.stderr and snapshot(project86) == before86, r.stderr
    r, calls = run(root86, src86, project86, image=image, archive=(str(archive), digest(archive)))
    assert r.returncode == 0 and ['image', 'load', '--input', str(archive)] in calls, r.stderr
    assert calls[0][4] == str(src86 / 'compose.yaml') and '--env-file' not in calls[0], calls
    assert any(call[:1] == ['run'] and image in call for call in calls), calls
    # The .env belongs to the account: the copy never changes it.
    assert env_file.read_text() == env and env_file.stat().st_mode & 0o777 == 0o600
    r, calls = run(root86, src86, project86, image=image)
    assert r.returncode == 0 and not any(call[:2] in (['image', 'load'], ['image', 'pull']) for call in calls), calls
    count += 1; print('PASS PHP 8.6 is loaded once from the verified archive and .env is kept')

    root, src, project = fixture('vscode-settings')
    (src / '.vscode').mkdir(exist_ok=True)
    shutil.copy(repo / '.vscode/settings.json', src / '.vscode/settings.json')
    (src / 'scripts').mkdir()
    shutil.copy(repo / 'scripts/daw.sh', src / 'scripts/daw.sh')
    before = snapshot(project)
    r, calls = run(root, src, project, image=image, fail='legacy-image')
    assert r.returncode != 0 and 'conta ad' in r.stderr and snapshot(project) == before, r.stderr
    r, calls = run(root, src, project)
    assert r.returncode == 0, r.stderr
    settings = (project / '.vscode/settings.json').read_text()
    distro = os.environ.get('WSL_DISTRO_NAME', 'linux')
    assert settings == (repo / '.vscode/settings.json').read_text().replace('"Debian"', f'"{distro}"')
    assert os.access(project / 'scripts/daw.sh', os.X_OK)
    before = backups(project)
    r, calls = run(root, src, project)
    assert r.returncode == 0 and all(line.startswith('igual ') for line in r.stdout.splitlines()), r.stderr
    assert backups(project) == before
    count += 1; print('PASS rejects mislabeled images, sets the WSL profile and preserves executable launchers')

    root, src, project = fixture('data-update')
    r, calls = run(root, src, project); assert r.returncode == 0, r.stderr
    (project / 'data/README.txt').write_text('notas do alumno')
    (project / 'compose.override.yaml').write_text('services: {}\n')
    r, calls = run(root, src, project); assert r.returncode == 0, r.stderr
    assert 'conservado data/README.txt' in r.stdout and 'substituido compose.override.yaml' in r.stdout, r.stdout
    assert (project / 'data/README.txt').read_text() == 'notas do alumno'
    count += 1; print('PASS data files are never replaced; changed project files are')

    def rejected(name, prepare, expected, fail='', args=None):
        global count
        root, src, project = fixture(name)
        outside = root / 'outside'; outside.mkdir(); (outside / 'keep').write_text('keep')
        extra = prepare(root, src, project)
        before, outside_before = snapshot(project), snapshot(outside)
        r, calls = run(root, src, project, args=extra if args is None and isinstance(extra, list) else args, fail=fail)
        assert r.returncode != 0 and expected in r.stderr, (name, r.stdout, r.stderr)
        assert snapshot(project) == before and snapshot(outside) == outside_before, name
        count += 1; print('PASS rejected without changes:', name)

    def www(root, src, project):
        (src / 'www').mkdir(); (src / 'www/x.php').write_text('x')
        return triples(src)
    rejected('www', www, 'Non se cambia www')
    rejected('traversal', lambda r, s, p: ['../escape', 'a' * 64, 'Replace'], 'Ruta non válida')
    def bad_sha(root, src, project):
        t = triples(src); t[1] = 'b' * 64; return t
    rejected('sha', bad_sha, 'SHA256 non coincide')
    def link(root, src, project):
        (project / 'docker').symlink_to(root / 'outside', target_is_directory=True)
    rejected('symlink', link, 'ligazón')
    def file_parent(root, src, project):
        (project / 'data').write_text('not a directory')
    rejected('file-parent', file_parent, 'non é un directorio')
    rejected('compose-invalid', lambda r, s, p: None, 'non se cambiou nada', fail='pre')
    rejected('arguments', lambda r, s, p: ['compose.override.yaml', 'a' * 64], 'incorrecta')
    def no_project(root, src, project):
        (project / 'compose.yaml').unlink()
    rejected('no-project', no_project, 'Falta o proxecto')

    root, src, project = fixture('post-failure')
    r, calls = run(root, src, project, fail='post')
    assert r.returncode != 0 and '.daw-backup' in r.stderr, r.stderr
    assert backups(project) and (project / 'www/work.php').read_text() == 'student work'
    count += 1; print('PASS failed final validation reports where the replaced files are')

    docker = shutil.which('docker')
    if docker and subprocess.run([docker, 'compose', 'version'], capture_output=True).returncode == 0:
        root = base / 'real'; project = root / 'home/ad/workspace'
        project.mkdir(parents=True)
        for name in ('compose.yaml', '.env.example', '.devcontainer'):
            (shutil.copytree if (repo / name).is_dir() else shutil.copy)(repo / name, project / name)
        # Use a custom tag to exercise real Compose without downloading the web image.
        (project / '.env').write_text('DAW_DEV_IMAGE=example.invalid/dwcs-php\n')
        r, calls = run(root, overlay, project, path=os.environ['PATH'])
        assert r.returncode == 0, r.stderr
        config = subprocess.run([docker, 'compose', 'config', '--format', 'json'], cwd=project, capture_output=True, text=True, check=True)
        web = json.loads(config.stdout)['services']['web']
        assert web['image'] == 'example.invalid/dwcs-php:8.6-ad' and web['build']['args']['PHP_VERSION'] == '8.6', web
        targets = [v['target'] for v in web['volumes']]
        assert '/home/ad/data' in targets and '/var/www/html' in targets and '/home/ad/html' not in targets and '/usr/local/etc/php/conf.d/zz-classroom.ini' in targets, targets
        assert web['environment']['APACHE_RUN_USER'] == 'www-data', web['environment']
        count += 1; print('PASS real docker compose accepts the classroom project files')
    else:
        print('SKIP real docker compose: docker is not installed')
print(f'ALL {count} PROJECT OVERLAY SCENARIOS PASSED')
