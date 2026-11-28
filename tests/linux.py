#!/usr/bin/env python3
"""Automated regression tests for Linux scripts, SSH host-key sync, doc release fallback,
command installers, local Linux setup, and Compose healthchecks / pinned tags.

Everything runs in isolated temporary directories with stubbed docker when needed, leaving
the user's real ~/.local/bin, ~/.ssh, shell rc files, and Docker containers untouched.
"""
import hashlib
import http.server
import io
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tarfile
import tempfile
import threading

repo = pathlib.Path(__file__).resolve().parents[1]
count = 0


def check(name, condition, detail=''):
    global count
    if not condition:
        raise AssertionError(f'{name}: {detail}')
    count += 1
    print(f'PASS {name}')


def run(*args, cwd=None, env=None, check_rc=True):
    r = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    if check_rc and r.returncode != 0:
        raise AssertionError(f'{" ".join(map(str, args))} failed ({r.returncode}):\nSTDOUT:\n{r.stdout}\nSTDERR:\n{r.stderr}')
    return r


def copy_repo(dest):
    for rel in filter(None, run('git', '-C', str(repo), 'ls-files', '-z').stdout.split('\0')):
        src = repo / rel
        if src.is_file():
            dst = dest / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    # Include untracked scripts created in this working tree (e.g., before git add)
    for rel in ('scripts/daw_helpers.py', 'scripts/install-linux.sh', '.github/dependabot.yml'):
        src = repo / rel
        if src.is_file():
            dst = dest / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)


def make_image_tarball(path, repo_tags):
    manifest = json.dumps([{'Config': 'cfg.json', 'RepoTags': repo_tags, 'Layers': []}]).encode('utf-8')
    with tarfile.open(path, 'w:gz') as tar:
        info = tarfile.TarInfo('manifest.json')
        info.size = len(manifest)
        tar.addfile(info, io.BytesIO(manifest))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_list_commands():
    linux_cmds = run('bash', str(repo / 'scripts/daw.sh'), '--list-commands').stdout.splitlines()
    model_cmds = run('bash', str(repo / 'scripts/daw.sh'), '--list-commands', '--model').stdout.splitlines()
    check('daw.sh --list-commands returns unique Linux commands including daw-publicar',
          len(linux_cmds) >= 15 and len(linux_cmds) == len(set(linux_cmds))
          and 'daw' in linux_cmds and 'daw-publicar' in linux_cmds and 'daw-start-frontend' in linux_cmds,
          linux_cmds)
    check('daw.sh --list-commands --model returns unique classroom model commands',
          len(model_cmds) >= 9 and len(model_cmds) == len(set(model_cmds))
          and 'daw-start' in model_cmds and 'daw-code' not in model_cmds,
          model_cmds)
    bad = run('bash', str(repo / 'scripts/daw.sh'), '--list-commands', '--unknown', check_rc=False)
    check('daw.sh --list-commands rejects unknown options', bad.returncode == 2, bad.stderr)


def test_install_daw_commands(base):
    home = base / 'install-home'
    bin_dir = home / '.local/bin'
    bin_dir.mkdir(parents=True)
    (home / '.bashrc').write_text('export FOO=1\nalias daw-start="old"\n', encoding='utf-8')
    (home / '.zshrc').write_text('export ZSH=1\n', encoding='utf-8')
    (home / '.config/fish/conf.d').mkdir(parents=True)
    (home / '.config/fish/conf.d/my_aliases.fish').write_text('alias daw-stop "old"\nset -gx BAR 1\n', encoding='utf-8')
    env = dict(os.environ, HOME=str(home))

    # 1. Preflight collision: regular file daw-stop aborts BEFORE creating ANY symlink or editing rc files
    blocker = bin_dir / 'daw-stop'
    blocker.write_text('#!/bin/sh\necho custom\n', encoding='utf-8')
    bashrc_before = (home / '.bashrc').read_text(encoding='utf-8')
    r = run('bash', str(repo / 'scripts/install-daw-commands.sh'), env=env, check_rc=False)
    check('install-daw-commands.sh fails on regular file conflict without leaving partial symlinks',
          r.returncode == 1 and 'daw-stop' in r.stderr
          and [p.name for p in bin_dir.iterdir()] == ['daw-stop']
          and (home / '.bashrc').read_text(encoding='utf-8') == bashrc_before,
          (r.stderr, [p.name for p in bin_dir.iterdir()]))
    blocker.unlink()

    # 2. Personal daw-publicar is preserved while all other launchers are installed
    personal_pub = bin_dir / 'daw-publicar'
    personal_pub.write_text('#!/bin/sh\necho personal\n', encoding='utf-8')
    r = run('bash', str(repo / 'scripts/install-daw-commands.sh'), env=env)
    expected = set(run('bash', str(repo / 'scripts/daw.sh'), '--list-commands').stdout.splitlines())
    installed = {p.name for p in bin_dir.iterdir()}
    check('install-daw-commands.sh installs all commands and preserves personal daw-publicar',
          installed == expected and not personal_pub.is_symlink()
          and personal_pub.read_text(encoding='utf-8') == '#!/bin/sh\necho personal\n'
          and 'Conservouse o publicador persoal' in r.stdout,
          (r.stdout, expected ^ installed))

    bashrc = (home / '.bashrc').read_text(encoding='utf-8')
    zshrc = (home / '.zshrc').read_text(encoding='utf-8')
    fishrc = (home / '.config/fish/conf.d/my_aliases.fish').read_text(encoding='utf-8')
    check('install-daw-commands.sh updates bash, zsh and fish rc files without old aliases',
          'alias daw-start=' not in bashrc and '# >>> DAW DEV LINUX >>>' in bashrc
          and '# >>> DAW DEV LINUX >>>' in zshrc
          and 'alias daw-stop ' not in fishrc and '# >>> DAW DEV LINUX >>>' in fishrc
          and 'daw-publicar' not in bashrc,
          (bashrc, fishrc))

    # 3. Idempotent re-run does not duplicate blocks
    run('bash', str(repo / 'scripts/install-daw-commands.sh'), env=env)
    check('install-daw-commands.sh is idempotent across re-runs',
          (home / '.bashrc').read_text(encoding='utf-8').count('# >>> DAW DEV LINUX >>>') == 1)

    # 4. --uninstall removes only daw.sh symlinks and shell blocks, keeping personal files
    unrelated = bin_dir / 'daw-custom'
    unrelated.write_text('keep', encoding='utf-8')
    foreign_link = bin_dir / 'daw-other'
    foreign_link.symlink_to('/bin/true')
    r = run('bash', str(repo / 'scripts/install-daw-commands.sh'), '--uninstall', env=env)
    remaining = sorted(p.name for p in bin_dir.iterdir())
    check('install-daw-commands.sh --uninstall removes only daw.sh symlinks and shell rc blocks',
          remaining == ['daw-custom', 'daw-other', 'daw-publicar']
          and '# >>> DAW DEV LINUX >>>' not in (home / '.bashrc').read_text(encoding='utf-8')
          and 'export FOO=1' in (home / '.bashrc').read_text(encoding='utf-8')
          and '# >>> DAW DEV LINUX >>>' not in (home / '.zshrc').read_text(encoding='utf-8')
          and 'export ZSH=1' in (home / '.zshrc').read_text(encoding='utf-8')
          and '# >>> DAW DEV LINUX >>>' not in (home / '.config/fish/conf.d/my_aliases.fish').read_text(encoding='utf-8')
          and 'set -gx BAR 1' in (home / '.config/fish/conf.d/my_aliases.fish').read_text(encoding='utf-8'),
          (remaining, r.stdout))

    # 5. Without a personal daw-publicar, daw-publicar is installed as a daw.sh symlink
    personal_pub.unlink()
    run('bash', str(repo / 'scripts/install-daw-commands.sh'), '--no-shell-config', env=env)
    check('install-daw-commands.sh installs daw-publicar symlink when no personal script exists',
          personal_pub.is_symlink() and os.path.realpath(personal_pub) == os.path.realpath(repo / 'scripts/daw.sh'))


def test_setup_angular(base):
    proj = base / 'angular-proj'
    copy_repo(proj)
    ssh_dir = base / 'ssh-dir'
    env = dict(os.environ, DAW_SSH_DIR=str(ssh_dir))

    # 1. Fresh run creates keypair, ssh-key.pub, and managed config block with HostKeyAlias & UserKnownHostsFile
    run('bash', str(proj / 'scripts/setup-angular.sh'), env=env)
    cfg = (ssh_dir / 'config').read_text(encoding='utf-8')
    check('setup-angular.sh creates keypair, copies public key, and writes managed SSH config block',
          (ssh_dir / 'dwcc_angular').is_file() and (proj / 'docker/angular/ssh-key.pub').is_file()
          and '# >>> DAW DEV ANGULAR >>>' in cfg
          and 'Port 2222' in cfg
          and 'HostKeyAlias dwcc-angular' in cfg
          and f'UserKnownHostsFile {ssh_dir}/known_hosts.d/dwcc-angular' in cfg
          and stat.S_IMODE((ssh_dir / 'config').stat().st_mode) == 0o600,
          cfg)

    # 2. Port change in .env updates the managed block in place without duplicating it
    (proj / '.env').write_text('ANGULAR_SSH_PORT=127.0.0.1:2299\n', encoding='utf-8')
    (ssh_dir / 'config').write_text(cfg + '\nHost deb\n    HostName 192.168.56.200\n    User ad\n', encoding='utf-8')
    run('bash', str(proj / 'scripts/setup-angular.sh'), env=env)
    cfg2 = (ssh_dir / 'config').read_text(encoding='utf-8')
    check('setup-angular.sh updates Port from .env in place and preserves other hosts',
          cfg2.count('# >>> DAW DEV ANGULAR >>>') == 1 and 'Port 2299' in cfg2
          and 'Port 2222' not in cfg2 and 'Host deb' in cfg2,
          cfg2)

    # 3. Upgrades an older unmarked daw-dev block seamlessly while preserving surrounding hosts
    legacy_cfg = (
        'Host dwcc-angular\n'
        '    HostName 127.0.0.1\n'
        '    Port 2222\n'
        '    User node\n'
        f'    IdentityFile {ssh_dir}/dwcc_angular\n'
        '    IdentitiesOnly yes\n\n'
        '# Keep me\n'
        'Host deb\n'
        '    HostName 192.168.56.200\n'
    )
    (ssh_dir / 'config').write_text(legacy_cfg, encoding='utf-8')
    run('bash', str(proj / 'scripts/setup-angular.sh'), env=env)
    cfg3 = (ssh_dir / 'config').read_text(encoding='utf-8')
    check('setup-angular.sh upgrades legacy unmarked daw-dev block and preserves comments/hosts',
          cfg3.count('Host dwcc-angular') == 1 and '# >>> DAW DEV ANGULAR >>>' in cfg3
          and 'Port 2299' in cfg3 and 'HostKeyAlias dwcc-angular' in cfg3
          and '# Keep me\nHost deb' in cfg3,
          cfg3)

    # 4. Preserves a custom user Host dwcc-angular block untouched
    custom_cfg = 'Host dwcc-angular\n    HostName 10.0.0.5\n    User custom\n    IdentityFile ~/.ssh/id_custom\n'
    (ssh_dir / 'config').write_text(custom_cfg, encoding='utf-8')
    run('bash', str(proj / 'scripts/setup-angular.sh'), env=env)
    check('setup-angular.sh preserves a custom user Host dwcc-angular block',
          (ssh_dir / 'config').read_text(encoding='utf-8') == custom_cfg)

    # 5. --sync-host-key writes isolated known_hosts.d/dwcc-angular and rotates cleanly
    key1 = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    key2 = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    run('bash', str(proj / 'scripts/setup-angular.sh'), '--sync-host-key', '--key', key1, env=env)
    kh = ssh_dir / 'known_hosts.d/dwcc-angular'
    check('setup-angular.sh --sync-host-key writes known_hosts.d/dwcc-angular with 0600 permissions',
          kh.read_text(encoding='utf-8') == f'dwcc-angular {key1}\n'
          and stat.S_IMODE(kh.stat().st_mode) == 0o600
          and stat.S_IMODE(kh.parent.stat().st_mode) == 0o700,
          kh.read_text(encoding='utf-8'))
    run('bash', str(proj / 'scripts/setup-angular.sh'), '--sync-host-key', '--key', key2, env=env)
    check('setup-angular.sh --sync-host-key rotates host key cleanly after reinstall',
          kh.read_text(encoding='utf-8') == f'dwcc-angular {key2}\n')
    bad = run('bash', str(proj / 'scripts/setup-angular.sh'), '--sync-host-key', '--key', 'not-a-key', env=env, check_rc=False)
    check('setup-angular.sh --sync-host-key rejects invalid host keys without overwriting',
          bad.returncode != 0 and kh.read_text(encoding='utf-8') == f'dwcc-angular {key2}\n')


def test_install_linux(base):
    proj = base / 'linux-install/daw-dev'
    home = base / 'linux-install/home'
    html = home / 'html'
    data = home / 'data'
    copy_repo(proj)
    env = dict(os.environ, HOME=str(home))

    run('bash', str(proj / 'scripts/install-linux.sh'), '--html-dir', str(html), '--data-dir', str(data), '--no-commands', env=env)
    dev_json = (html / '.devcontainer/devcontainer.json').read_text(encoding='utf-8')
    override = (proj / 'compose.override.yaml').read_text(encoding='utf-8')
    dot_env = (proj / '.env').read_text(encoding='utf-8')
    check('install-linux.sh creates home layout, .env (0600), override, Dev Container and VS Code files',
          (html / 'index.php').is_file() and (html / 'info.php').is_file()
          and (data / 'README.txt').is_file()
          and (html / '.devcontainer/compose.devcontainer.yaml').is_file()
          and (html / '.vscode/launch.json').is_file()
          and (html / '.vscode/settings.json').is_file()
          and str(proj.resolve()) in dev_json and '../../.daw' not in dev_json
          and str(data.resolve()) in override
          and f'WWW_DIR={html.resolve()}' in dot_env
          and stat.S_IMODE((proj / '.env').stat().st_mode) == 0o600,
          (dev_json, override, dot_env))

    # User files and .env are preserved even with --force
    (html / 'index.php').write_text('<?php echo "custom";', encoding='utf-8')
    (html / 'app.php').write_text('<?php echo "app";', encoding='utf-8')
    (data / 'README.txt').write_text('my data\n', encoding='utf-8')
    (proj / '.env').write_text(dot_env + 'XDEBUG_MODE=off\n', encoding='utf-8')
    run('bash', str(proj / 'scripts/install-linux.sh'), '--html-dir', str(html), '--data-dir', str(data), '--no-commands', '--force', env=env)
    check('install-linux.sh --force never overwrites user web files, data files or .env',
          (html / 'index.php').read_text(encoding='utf-8') == '<?php echo "custom";'
          and (html / 'app.php').read_text(encoding='utf-8') == '<?php echo "app";'
          and (data / 'README.txt').read_text(encoding='utf-8') == 'my data\n'
          and 'XDEBUG_MODE=off' in (proj / '.env').read_text(encoding='utf-8'))


def test_doc_fallback_and_pinned_aliases(base):
    proj = base / 'doc-proj'
    copy_repo(proj)
    serve_dir = base / 'release-assets'
    serve_dir.mkdir()
    doc_images = {
        'daw-doc-php.tar.gz': 'ghcr.io/miguelfm/daw-doc-php:en',
        'daw-doc-devdocs.tar.gz': 'ghcr.io/miguelfm/daw-doc-devdocs:latest',
        'daw-doc-laravel.tar.gz': 'ghcr.io/miguelfm/daw-doc-laravel:13.x',
    }
    sums = {}
    for filename, tag in doc_images.items():
        sums[filename] = make_image_tarball(serve_dir / filename, [tag])
    (serve_dir / 'SHA256SUMS').write_text(''.join(f'{h}  {name}\n' for name, h in sums.items()), encoding='utf-8')

    hits = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            hits.append(self.path)
            if self.path == '/release.json':
                base_url = f'http://127.0.0.1:{self.server.server_address[1]}'
                payload = {
                    'tag_name': 'docs-test',
                    'assets': [
                        {'name': name, 'browser_download_url': f'{base_url}/{name}'}
                        for name in ('SHA256SUMS', *doc_images.keys())
                    ],
                }
                body = json.dumps(payload).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(body)
                return
            target = serve_dir / self.path.lstrip('/')
            if target.is_file():
                self.send_response(200)
                self.end_headers()
                self.wfile.write(target.read_bytes())
                return
            self.send_response(404)
            self.end_headers()

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    stub_bin = base / 'stub-bin'
    stub_bin.mkdir()
    docker_stub = stub_bin / 'docker'
    docker_stub.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, sys, tarfile

state = pathlib.Path(os.environ['DAW_STUB_STATE'])
data = json.loads(state.read_text()) if state.exists() else {'images': {}, 'log': []}
args = sys.argv[1:]
data['log'].append(args)

def save():
    state.write_text(json.dumps(data))

if args[:1] == ['compose']:
    if '--images' in args:
        if 'db' in args or 'db-admin' in args:
            for img in os.environ.get('DAW_STUB_DB_IMAGES', 'mariadb:12.3\nphpmyadmin:5.2.3').splitlines():
                if img:
                    print(img)
        else:
            for img in ('ghcr.io/miguelfm/daw-doc-php:en', 'ghcr.io/miguelfm/daw-doc-devdocs:latest', 'ghcr.io/miguelfm/daw-doc-laravel:13.x'):
                print(img)
        save(); sys.exit(0)
    if 'config' in args:
        print('name: daw-dev')
        save(); sys.exit(0)
    if 'port' in args:
        idx = args.index('port')
        svc = args[idx + 1]
        ports = {'doc-php': '127.0.0.1:8080', 'doc-web': '127.0.0.1:5042', 'doc-laravel': '127.0.0.1:8088'}
        print(ports.get(svc, ''))
        save(); sys.exit(0)
    if 'up' in args:
        save(); sys.exit(0)
if args[:2] == ['ps', '-aq'] or args[:2] == ['ps', '-q']:
    save(); sys.exit(0)
if args[:2] == ['image', 'inspect']:
    img = args[-1]
    if img not in data['images']:
        save(); sys.exit(1)
    if '-f' in args:
        for line in data['images'][img].get('env', []):
            print(line)
    save(); sys.exit(0)
if args[:2] == ['image', 'pull']:
    img = args[-1]
    if os.environ.get('DAW_STUB_PULL_OK') == '1':
        data['images'][img] = {'env': []}
        save(); sys.exit(0)
    save(); sys.exit(1)
if args[:2] == ['image', 'load']:
    tar_path = args[args.index('--input') + 1]
    with tarfile.open(tar_path, 'r:*') as tar:
        manifest = json.loads(tar.extractfile('manifest.json').read().decode('utf-8'))
    for entry in manifest:
        for tag in entry.get('RepoTags') or []:
            data['images'][tag] = {'env': []}
    save(); sys.exit(0)
if args[:2] == ['image', 'tag']:
    src, dst = args[2], args[3]
    if src not in data['images']:
        save(); sys.exit(1)
    data['images'][dst] = data['images'][src]
    save(); sys.exit(0)
save(); sys.exit(0)
''', encoding='utf-8')
    docker_stub.chmod(0o755)

    try:
        def run_daw(action, state_file, pull_ok='0', db_images=None):
            env = dict(
                os.environ,
                PATH=f'{stub_bin}:{os.environ["PATH"]}',
                DAW_STUB_STATE=str(state_file),
                DAW_STUB_PULL_OK=pull_ok,
                DAW_DOC_RELEASE_API=f'http://127.0.0.1:{port}/release.json',
            )
            if db_images is not None:
                env['DAW_STUB_DB_IMAGES'] = db_images
            return run('bash', str(proj / 'scripts/daw.sh'), action, env=env, check_rc=False)

        # 1. Missing images + failing pull -> downloads release, verifies SHA256SUMS, loads all 3 images
        st = base / 'st1.json'
        hits.clear()
        r = run_daw('start-doc', st, pull_ok='0')
        loaded = set(json.loads(st.read_text())['images'].keys())
        check('daw-start-doc falls back to GitHub release, verifies SHA256SUMS and loads missing doc images',
              r.returncode == 0 and loaded == set(doc_images.values()) and '/SHA256SUMS' in hits,
              (r.stdout, r.stderr, loaded, hits))

        # 2. Second run with all 3 images already local -> zero HTTP hits and zero pull calls
        hits.clear()
        r = run_daw('start-doc', st, pull_ok='0')
        log = json.loads(st.read_text())['log']
        check('daw-start-doc skips network completely when doc images are already present locally',
              r.returncode == 0 and hits == [],
              (hits, log))

        # 3. Registry pull succeeds -> does not touch GitHub release
        st2 = base / 'st2.json'
        hits.clear()
        r = run_daw('start-doc', st2, pull_ok='1')
        check('daw-start-doc uses registry pull first when available without hitting GitHub release',
              r.returncode == 0 and hits == [] and set(json.loads(st2.read_text())['images'].keys()) == set(doc_images.values()),
              (hits, r.stderr))

        # 4. Tampered archive -> rejected BEFORE docker image load
        st3 = base / 'st3.json'
        orig_bytes = (serve_dir / 'daw-doc-php.tar.gz').read_bytes()
        (serve_dir / 'daw-doc-php.tar.gz').write_bytes(orig_bytes + b'tampered')
        r = run_daw('start-doc', st3, pull_ok='0')
        (serve_dir / 'daw-doc-php.tar.gz').write_bytes(orig_bytes)
        check('daw-start-doc rejects tampered doc archive before docker load',
              r.returncode != 0 and 'SHA256' in r.stderr and not json.loads(st3.read_text())['images'],
              r.stderr)

        # 5. Wrong RepoTags inside valid SHA256 tarball -> rejected BEFORE docker image load
        st4 = base / 'st4.json'
        bad_hash = make_image_tarball(serve_dir / 'daw-doc-php.tar.gz', ['evil/other:latest'])
        sums_bad = dict(sums, **{'daw-doc-php.tar.gz': bad_hash})
        (serve_dir / 'SHA256SUMS').write_text(''.join(f'{h}  {name}\n' for name, h in sums_bad.items()), encoding='utf-8')
        r = run_daw('start-doc', st4, pull_ok='0')
        check('daw-start-doc rejects doc archive with unexpected RepoTags',
              r.returncode != 0 and 'non contén a imaxe esperada' in r.stderr and not json.loads(st4.read_text())['images'],
              r.stderr)

        # 6. Offline pinned image aliasing for MariaDB 12.3 and phpMyAdmin 5.2.3
        st5 = base / 'st5.json'
        st5.write_text(json.dumps({
            'images': {
                'mariadb:lts': {'env': ['MARIADB_VERSION=1:12.3.4+maria~ubu2404']},
                'phpmyadmin:latest': {'env': ['VERSION=5.2.3']},
            },
            'log': [],
        }))
        r = run_daw('remove-old-services', st5)
        imgs5 = json.loads(st5.read_text())['images']
        check('daw.sh aliases matching local mariadb:lts (12.3.x) and phpmyadmin:latest (5.2.3) offline',
              r.returncode == 0 and 'mariadb:12.3' in imgs5 and 'phpmyadmin:5.2.3' in imgs5,
              imgs5)

        st6 = base / 'st6.json'
        st6.write_text(json.dumps({
            'images': {
                'mariadb:lts': {'env': ['MARIADB_VERSION=1:11.8.2+maria~ubu2404']},
                'phpmyadmin:latest': {'env': ['VERSION=5.2.1']},
            },
            'log': [],
        }))
        r = run_daw('remove-old-services', st6)
        imgs6 = json.loads(st6.read_text())['images']
        check('daw.sh does not mis-tag mismatched local mariadb:lts or phpmyadmin:latest versions',
              r.returncode == 0 and 'mariadb:12.3' not in imgs6 and 'phpmyadmin:5.2.3' not in imgs6,
              imgs6)

        # 7. Dynamic version matching (e.g. after a Dependabot bump in compose.yaml)
        st7 = base / 'st7.json'
        st7.write_text(json.dumps({
            'images': {
                'mariadb:lts': {'env': ['MARIADB_VERSION=1:12.4.1+maria~ubu2404']},
                'phpmyadmin:latest': {'env': ['VERSION=5.2.4']},
            },
            'log': [],
        }))
        r = run_daw('remove-old-services', st7, db_images='mariadb:12.4\nphpmyadmin:5.2.4')
        imgs7 = json.loads(st7.read_text())['images']
        check('daw.sh dynamically aliases updated pinned versions from compose.yaml',
              r.returncode == 0 and 'mariadb:12.4' in imgs7 and 'phpmyadmin:5.2.4' in imgs7,
              imgs7)
    finally:
        server.shutdown()
        server.server_close()


def test_helpers_and_keepalive(base):
    env_file = base / 'sample.env'
    env_file.write_text(
        '# comment\n'
        'export WWW_DIR="/home/demo/html"\n'
        'ANGULAR_SSH_PORT=127.0.0.1:2222 # inline comment\n'
        "ANGULAR_SSH_PORT='127.0.0.1:2299'\n",
        encoding='utf-8',
    )
    www = run('python3', str(repo / 'scripts/daw_helpers.py'), 'read-env', str(env_file), 'WWW_DIR').stdout.strip()
    port = run('python3', str(repo / 'scripts/daw_helpers.py'), 'read-env', str(env_file), 'ANGULAR_SSH_PORT').stdout.strip()
    missing = run('python3', str(repo / 'scripts/daw_helpers.py'), 'read-env', str(env_file), 'NO_SUCH', 'fallback').stdout.strip()
    check('daw_helpers.py read-env handles export, quotes, inline comments, last-wins and defaults',
          www == '/home/demo/html' and port == '127.0.0.1:2299' and missing == 'fallback',
          (www, port, missing))

    keep = (repo / 'scripts/keep-alive.sh').read_text(encoding='utf-8')
    check('keep-alive.sh uses per-user/project lock and checks profiled containers',
          '/tmp/daw-dev-keep-alive.lock' not in keep
          and 'XDG_RUNTIME_DIR' in keep
          and '--profile frontend --profile doc' in keep)


def test_compose_and_dockerfile():
    dockerfile = (repo / 'Dockerfile').read_text(encoding='utf-8')
    check('Dockerfile pins mlocati/php-extension-installer instead of :latest',
          'mlocati/php-extension-installer:latest' not in dockerfile
          and 'mlocati/php-extension-installer:2.' in dockerfile)
    angular_df = (repo / 'docker/angular/Dockerfile').read_text(encoding='utf-8')
    check('docker/angular/Dockerfile pins exact Node and Angular CLI versions',
          'FROM node:26.13.1-bookworm' in angular_df and 'ANGULAR_CLI_VERSION=22.3.0' in angular_df)
    check('.gitignore ignores root /compose.override.yaml without ignoring classroom overlay',
          run('git', '-C', str(repo), 'check-ignore', 'compose.override.yaml', check_rc=False).returncode == 0
          and run('git', '-C', str(repo), 'check-ignore', 'windows/classroom/overlay/compose.override.yaml', check_rc=False).returncode != 0)
    if shutil.which('docker') and run('docker', 'compose', 'version', check_rc=False).returncode == 0:
        cfg = json.loads(run('docker', 'compose', '-f', str(repo / 'compose.yaml'),
                             '--profile', 'frontend', '--profile', 'doc', 'config', '--format', 'json').stdout)
        svcs = cfg['services']
        for name in ('backend', 'db', 'db-admin', 'frontend'):
            check(f'compose.yaml defines healthcheck on {name}', bool(svcs[name].get('healthcheck')), svcs[name])
        check('compose.yaml pins mariadb and phpmyadmin versions',
              svcs['db']['image'] == 'mariadb:12.3' and svcs['db-admin']['image'] == 'phpmyadmin:5.2.3',
              (svcs['db']['image'], svcs['db-admin']['image']))


with tempfile.TemporaryDirectory(prefix='daw-linux-tests-') as tmp:
    base = pathlib.Path(tmp)
    test_list_commands()
    test_install_daw_commands(base)
    test_setup_angular(base)
    test_install_linux(base)
    test_doc_fallback_and_pinned_aliases(base)
    test_helpers_and_keepalive(base)
    test_compose_and_dockerfile()
print(f'ALL {count} LINUX TESTS PASSED')
