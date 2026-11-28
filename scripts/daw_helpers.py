#!/usr/bin/env python3
"""Helper routines shared by the DAW Dev shell scripts (Python 3 stdlib only).

Centralizes container inspection, bind-mount resolution, .env parsing, SSH config
management, offline documentation release fetching, and local Linux setup rendering
so Bash launchers remain small, readable, and easy to unit-test.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


def _docker(*args):
    return subprocess.run(
        ('docker', *args), check=True, stdout=subprocess.PIPE, encoding='utf-8'
    ).stdout


def _nanoseconds(stamp: str) -> int:
    # Docker uses RFC 3339 UTC timestamps with up to 9 fractional digits.
    stamp = stamp.rstrip('Z')
    whole, _, fraction = stamp.partition('.')
    seconds = datetime.fromisoformat(whole).replace(tzinfo=timezone.utc).timestamp()
    return int(seconds) * 10**9 + int((fraction + '000000000')[:9])


def read_env_value(env_path: Path, key: str, default: str = '') -> str:
    """Read the last assignment to KEY from a .env file, handling quotes and comments."""
    if not env_path.is_file():
        return default
    value = default
    prefix = f'{key}='
    for raw_line in env_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:].lstrip()
        if not line.startswith(prefix):
            continue
        val = line[len(prefix):].strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            val = val[1:-1]
        elif ' #' in val:
            val = val.split(' #', 1)[0].rstrip()
        value = val
    return value


def cmd_read_env(args):
    if len(args) not in (2, 3):
        sys.exit('Uso: daw_helpers.py read-env <env_file> <key> [default]')
    env_path = Path(args[0])
    key = args[1]
    default = args[2] if len(args) == 3 else ''
    print(read_env_value(env_path, key, default))


def cmd_web_state(args):
    """Print '<id> <mode> <status> <reason>' for the backend container."""
    if len(args) < 1:
        sys.exit('Uso: daw_helpers.py web-state <project_dir> [compose_args...]')
    project = args[0]
    compose = ('compose', '--project-directory', project, *args[1:])

    ids = [i for i in _docker(*compose, 'ps', '--all', '--quiet', 'backend').split() if i]
    if not ids:
        print('- none - -')
        return
    container = json.loads(_docker('inspect', '--type', 'container', ids[0]))[0]
    labels = container['Config'].get('Labels') or {}
    mode = 'devcontainer' if labels.get('devcontainer.local_folder') else 'compose'
    running = container['State']['Running']
    reason = None

    if mode == 'devcontainer':
        # Compose checks its own changes on start; Dev Containers does not.
        created = _nanoseconds(container['Created'])
        paths = [
            f for f in labels.get('com.docker.compose.project.config_files', '').split(',')
            if f and '/devcontainercli' not in f
        ]
        paths += [labels.get('devcontainer.config_file', ''), os.path.join(project, '.env')]
        for path in dict.fromkeys(paths):
            if path and os.path.isfile(path) and os.stat(path).st_mtime_ns > created:
                name = os.path.relpath(path, project) if path.startswith(project + os.sep) else path
                reason = f'cambiou {name}'
                break
        if not reason:
            image = json.loads(_docker(*compose, 'config', '--format', 'json'))['services']['backend'].get('image')
            if image:
                try:
                    base = json.loads(_docker('image', 'inspect', image))[0]['RootFS']['Layers']
                except subprocess.CalledProcessError:
                    base = None
                used = json.loads(_docker('image', 'inspect', container['Image']))[0]['RootFS']['Layers']
                if base and used[:len(base)] != base:
                    reason = f'hai unha imaxe nova {image}'

    if running and not reason:
        # Docker bind-mounts single files by inode: replacing the host file requires recreation.
        started = _nanoseconds(container['State']['StartedAt'])
        for mount in container.get('Mounts') or []:
            source = mount.get('Source', '')
            if mount.get('Type') == 'bind' and os.path.isfile(source) and os.stat(source).st_mtime_ns > started:
                rel = os.path.relpath(source, project) if source.startswith(project + os.sep) else source
                reason = f'cambiou {rel}'
                break

    print(container['Id'][:12], mode, 'running' if running else 'stopped', reason or '-')


def cmd_web_root(args):
    """Print the host directory mounted at /var/www/html."""
    if len(args) < 1:
        sys.exit('Uso: daw_helpers.py web-root <project_dir> [compose_args...]')
    web_roots = {'/var/www/html'}
    compose = ('compose', '--project-directory', *args)

    def native_path(source: str) -> str:
        if sys.platform == 'darwin' and not os.path.isdir(source):
            for prefix in ('/host_mnt', '/run/desktop/mnt/host'):
                if source.startswith(prefix + '/'):
                    return source[len(prefix):]
        return source

    try:
        containers = _docker(*compose, 'ps', '--all', '--quiet', 'backend').split()
        mounts = []
        if containers:
            template = '{{if ne (index .Config.Labels "com.docker.compose.oneoff") "True"}}{{json .Mounts}}{{end}}'
            inspected = _docker('inspect', '--type', 'container', '--format', template, *containers)
            mounts = [json.loads(line) for line in inspected.splitlines() if line]

        if mounts:
            sources = (
                mount['Source'] for container in mounts for mount in container
                if mount['Type'] == 'bind' and mount['Destination'] in web_roots
            )
        else:
            config = json.loads(_docker(*compose, 'config', '--format', 'json', 'backend'))
            sources = (
                mount['source'] for mount in config['services']['backend'].get('volumes', [])
                if mount['type'] == 'bind' and mount['target'] in web_roots
            )
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)

    paths = dict.fromkeys(native_path(source) for source in sources)
    if not paths:
        sys.exit('Erro: a raíz web non está montada desde un cartafol do anfitrión.')
    print(*paths, sep='\n')


def cmd_fetch_doc_images(args):
    """Download missing daw-doc-*.tar.gz archives from GitHub Releases, verify and docker load."""
    if not args:
        return
    archives = {}
    for img in args:
        name = img.rsplit('/', 1)[-1].split(':', 1)[0]
        if not re.fullmatch(r'daw-doc-[a-z0-9-]+', name):
            sys.exit(f'Erro: non se puido descargar {img} desde o rexistro.')
        archives[f'{name}.tar.gz'] = img

    repo = os.environ.get('DAW_DOC_REPO', 'miguelfm/daw-doc')
    tag = os.environ.get('DAW_DOC_RELEASE_TAG', 'latest')
    api = os.environ.get('DAW_DOC_RELEASE_API')
    if not api:
        if tag == 'latest':
            api = f'https://api.github.com/repos/{repo}/releases/latest'
        else:
            api = f'https://api.github.com/repos/{repo}/releases/tags/{tag}'

    headers = {'User-Agent': 'daw-dev', 'Accept': 'application/vnd.github+json'}
    try:
        req = urllib.request.Request(api, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            release = json.loads(resp.read().decode('utf-8'))
    except Exception as err:
        sys.exit(f'Erro: non se puido consultar a release de documentación en {repo}: {err}')

    assets = {a['name']: a['browser_download_url'] for a in release.get('assets') or []}
    for required in ('SHA256SUMS', *archives.keys()):
        if required not in assets:
            sys.exit(f"Erro: a release {release.get('tag_name', '?')} de {repo} non contén {required}.")

    def download(url: str, dest: str):
        req = urllib.request.Request(url, headers={'User-Agent': 'daw-dev'})
        with urllib.request.urlopen(req, timeout=1800) as resp, open(dest, 'wb') as out:
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)

    def sha256_file(path: str) -> str:
        digest = hashlib.sha256()
        with open(path, 'rb') as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(chunk)
        return digest.hexdigest().lower()

    print(f"Descargando imaxes de documentación da release {release.get('tag_name', '?')} de {repo}...")
    with tempfile.TemporaryDirectory(prefix='daw-doc-') as tmp:
        sums_path = os.path.join(tmp, 'SHA256SUMS')
        download(assets['SHA256SUMS'], sums_path)
        sums = {}
        with open(sums_path, encoding='utf-8') as handle:
            for line in handle:
                match = re.match(r'^([0-9a-fA-F]{64})\s+\*?(\S+)$', line.strip())
                if match:
                    sums[match.group(2)] = match.group(1).lower()

        for filename, img in archives.items():
            if filename not in sums:
                sys.exit(f'Erro: SHA256SUMS non inclúe {filename}.')
            dest = os.path.join(tmp, filename)
            print(f'  {filename}...')
            download(assets[filename], dest)
            if sha256_file(dest) != sums[filename]:
                sys.exit(f'Erro: o SHA256 de {filename} non coincide con SHA256SUMS.')
            try:
                with tarfile.open(dest, 'r:*') as tar:
                    member = tar.getmember('manifest.json')
                    manifest = json.loads(tar.extractfile(member).read().decode('utf-8'))
            except Exception as err:
                sys.exit(f'Erro: {filename} non é un arquivo de imaxe Docker válido ({err}).')
            tags = [t for entry in manifest for t in (entry.get('RepoTags') or [])]
            if img not in tags:
                sys.exit(f'Erro: {filename} non contén a imaxe esperada {img}.')
            subprocess.run(['docker', 'image', 'load', '--input', dest], check=True)
            subprocess.run(['docker', 'image', 'inspect', img], check=True, stdout=subprocess.DEVNULL)


def cmd_update_ssh_config(args):
    """Manage the dwcc-angular SSH config block with HostKeyAlias and isolated known_hosts."""
    if len(args) != 3:
        sys.exit('Uso: daw_helpers.py update-ssh-config <ssh_dir> <key_path> <env_file>')
    ssh_dir, key, env_file = map(Path, args)
    config = ssh_dir / 'config'
    use_tilde = ssh_dir.resolve() == (Path.home() / '.ssh').resolve()

    def ssh_path(path: Path, rel: str) -> str:
        value = f'~/.ssh/{rel}' if use_tilde else str(path)
        return f'"{value}"' if ' ' in value else value

    raw_port = read_env_value(env_file, 'ANGULAR_SSH_PORT', '2222')
    port = raw_port.rsplit(':', 1)[-1]
    if not port.isdigit():
        sys.exit('ANGULAR_SSH_PORT non válido')

    begin = '# >>> DAW DEV ANGULAR >>>'
    end = '# <<< DAW DEV ANGULAR <<<'
    block = (
        f'{begin}\n'
        f'Host dwcc-angular\n'
        f'    HostName 127.0.0.1\n'
        f'    Port {port}\n'
        f'    User node\n'
        f'    IdentityFile {ssh_path(key, "dwcc_angular")}\n'
        f'    IdentitiesOnly yes\n'
        f'    HostKeyAlias dwcc-angular\n'
        f'    UserKnownHostsFile {ssh_path(ssh_dir / "known_hosts.d" / "dwcc-angular", "known_hosts.d/dwcc-angular")}\n'
        f'{end}\n'
    )

    old = config.read_text(encoding='utf-8') if config.exists() else ''
    marker_re = re.compile(re.escape(begin) + r'\r?\n.*?' + re.escape(end) + r'\r?\n?', re.S)

    def is_legacy_daw_block(text: str) -> bool:
        opts = {}
        for line in text.splitlines()[1:]:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            parts = stripped.split(None, 1)
            if len(parts) == 2:
                opts[parts[0].lower()] = parts[1].strip().strip('"')
        return (
            opts.get('hostname') == '127.0.0.1'
            and opts.get('user') == 'node'
            and opts.get('identityfile', '').endswith('dwcc_angular')
        )

    def replace_legacy_block(text: str):
        lines = text.splitlines(keepends=True)
        for i, line in enumerate(lines):
            if re.match(r'^\s*Host\s+dwcc-angular\s*$', line, re.I):
                j = i + 1
                while j < len(lines):
                    stripped = lines[j].strip()
                    if stripped and not stripped.startswith('#') and re.match(r'^(Host|Match)\s+', stripped, re.I):
                        break
                    j += 1
                end_idx = j
                while end_idx > i + 1 and (not lines[end_idx - 1].strip() or lines[end_idx - 1].lstrip().startswith('#')):
                    end_idx -= 1
                section = ''.join(lines[i:end_idx])
                if is_legacy_daw_block(section):
                    return ''.join(lines[:i]) + block + ''.join(lines[end_idx:])
                return text
        return None

    if marker_re.search(old):
        new = marker_re.sub(lambda _: block, old, count=1)
    else:
        upgraded = replace_legacy_block(old)
        if upgraded is not None:
            new = upgraded
        else:
            skip = False
            if use_tilde:
                resolved = subprocess.run(
                    ['ssh', '-G', 'dwcc-angular'], capture_output=True, text=True, check=True
                ).stdout
                skip = 'hostname dwcc-angular\n' not in resolved
            new = old if skip else (block + ('\n' if old and not old.startswith('\n') else '') + old)

    if new != old or not config.exists():
        config.write_text(new, encoding='utf-8')
        config.chmod(0o600)


COMMANDS = {
    'read-env': cmd_read_env,
    'web-state': cmd_web_state,
    'web-root': cmd_web_root,
    'fetch-doc-images': cmd_fetch_doc_images,
    'update-ssh-config': cmd_update_ssh_config,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"Uso: {Path(sys.argv[0]).name} <{'|'.join(COMMANDS)}> [args...]")
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == '__main__':
    main()
