#!/usr/bin/env python3
"""Alternate daw-start and Dev Containers on one backend container, with real Docker.

Dev Containers reuses whatever backend container exists, and Compose recreates a Dev Container's.
The main scenario uses the classroom layout: the environment in ~/.daw and the web code, with
its VS Code settings, in ~/html. A shorter one uses the repository layout of personal installs.
Each runs on a copy with its own project name, container names and ports, so it leaves the
user's containers alone. It needs Docker, the backend image and the Dev Containers CLI
(DEVCONTAINER_BIN, `devcontainer` by default).
"""
import json, os, pathlib, shutil, subprocess, tempfile, time

repo = pathlib.Path(__file__).resolve().parents[1]
devcontainer = os.environ.get('DEVCONTAINER_BIN', 'devcontainer')
CLASSROOM = repo / 'windows/classroom/overlay'


def override(name, ports, mounts=''):
    web, db, admin = ports
    return f'''services:
  backend:
    container_name: {name}-backend-c
    ports: !override ["127.0.0.1:{web}:80"]
{mounts}  db:
    container_name: {name}-db-c
    ports: !override ["127.0.0.1:{db}:3306"]
  db-admin:
    container_name: {name}-db-admin-c
    ports: !override ["127.0.0.1:{admin}:80"]
'''


# As in the classroom override: the web code and the task data, in the home next to ~/.daw.
CLASSROOM_MOUNTS = '''    volumes:
      - ../html:/var/www/html
      - ../html:/home/ad/html
      - ../data:/home/ad/data
'''


def run(*args, cwd=None, check=True):
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8')
    if check and result.returncode:
        raise AssertionError(f'{" ".join(map(str, args))} failed ({result.returncode}):\n{result.stdout}')
    return result.stdout


def check(name, condition, detail=''):
    if not condition:
        raise AssertionError(f'{name}: {detail}')
    print(f'PASS {name}')


def copy_repository(project):
    for rel in filter(None, run('git', '-C', str(repo), 'ls-files', '-z').split('\0')):
        source = repo / rel
        if source.is_file():
            target = project / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


class Env:
    def __init__(self, project, workspace, name):
        self.project, self.workspace, self.name = project, workspace, name
        self.compose_name = f'daw-dev-test-{name}'
        self.backend = f'{name}-backend-c'
        self.images = set()
        # Its own MariaDB volume: compose.yaml names it daw-dev_db_data unless DB_VOLUME_NAME says otherwise.
        (project / '.env').write_text(f'COMPOSE_PROJECT_NAME={self.compose_name}\nDB_VOLUME_NAME={self.compose_name}_db_data\n'
                                      f'USER_UID={os.getuid()}\nUSER_GID={os.getgid()}\n')

    def web(self):
        ids = run('docker', 'compose', '-p', self.compose_name, 'ps', '--all', '--quiet', 'backend', cwd=self.project).split()
        assert len(ids) == 1, ids
        info = json.loads(run('docker', 'inspect', ids[0]))[0]
        labels = info['Config'].get('Labels') or {}
        self.images.add(info['Image'])
        return {
            'id': info['Id'], 'running': info['State']['Running'],
            'devcontainer': bool(labels.get('devcontainer.local_folder')),
            'mounts': {m['Destination']: m['Source'] for m in info['Mounts']},
            'env': dict(e.split('=', 1) for e in info['Config']['Env']),
            'hostname': info['Config']['Hostname'],
        }

    def daw(self, action):
        return run('bash', 'scripts/daw.sh', action, cwd=self.project)

    def up(self):
        out = run(devcontainer, 'up', '--workspace-folder', str(self.workspace), cwd=self.workspace)
        assert '"outcome":"success"' in out, out
        return out

    def down(self):
        run('docker', 'compose', '-p', self.compose_name, '--profile', 'frontend', '--profile', 'doc', 'down', '-v',
            '--remove-orphans', cwd=self.project, check=False)
        # Only the images Dev Containers built on top of the project's (vsc-*), never the base one.
        for image in self.images:
            tags = run('docker', 'image', 'inspect', '-f', '{{json .RepoTags}}', image, check=False)
            if tags.startswith('[') and all(t.startswith('vsc-') for t in json.loads(tags) or ['-']):
                run('docker', 'image', 'rm', '-f', image, check=False)


def classroom(tmp):
    # ~/.daw: the environment; ~/html: www with the classroom VS Code settings; ~/data.
    home = pathlib.Path(tmp) / 'aula/home'
    project, html = home / '.daw', home / 'html'
    copy_repository(project)
    shutil.move(project / 'www', html)
    shutil.copytree(CLASSROOM / 'html', html, dirs_exist_ok=True)
    shutil.copy(repo / '.vscode/settings.json', html / '.vscode/settings.json')
    (home / 'data').mkdir()
    env = Env(project, html, 'aula')
    (project / 'compose.override.yaml').write_text(override('aula', (18180, 13406, 18181), CLASSROOM_MOUNTS))
    try:
        # Before 27-11-2026 the service was web: its container, still running, holds the port.
        image = run('docker', 'compose', 'config', '--images', 'backend', cwd=project).split()[0]
        run('docker', 'run', '-d', '--name', 'daw-test-old-web', '--label', f'com.docker.compose.project={env.compose_name}',
            '--label', 'com.docker.compose.service=web', '-p', '127.0.0.1:18180:80', image)
        out = env.daw('start')
        gone = run('docker', 'ps', '-aq', '--filter', 'name=^daw-test-old-web$').strip()
        check('daw-start removes the container of the previous service and takes its port',
              not gone and 'servizo anterior web' in out and env.web()['running'], out)
        state = env.web()
        check('daw-start creates the Compose definition, with ~/html mounted',
              state['running'] and not state['devcontainer'] and 'XDEBUG_CONFIG' not in state['env']
              and state['mounts'].get('/var/www/html') == state['mounts'].get('/home/ad/html') == str(html), state)

        env.up()
        state = env.web()
        check('Dev Containers replaces the container daw-start created and opens ~/html',
              state['devcontainer'] and state['mounts'].get('/home/ad/html') == str(html)
              and state['env'].get('XDEBUG_CONFIG') == 'client_host=localhost' and state['hostname'] == 'backend', state)
        opened = state['id']
        out = run(devcontainer, 'exec', '--workspace-folder', str(html), 'bash', '-c', 'pwd; ls -a', cwd=html)
        check('the Dev Container opens in ~/html, with its VS Code settings', out.startswith('/home/ad/html')
              and '.vscode' in out and 'index.php' in out, out)

        out = env.daw('start')
        state = env.web()
        check('daw-start keeps an open Dev Container', state['id'] == opened and state['running'] and 'Dev Containers' in out, out)
        out = env.daw('start-db')
        db = run('docker', 'inspect', '-f', '{{.State.Health.Status}}', 'aula-db-c').strip()
        check('daw-start-db starts MariaDB and keeps the Dev Container', env.web()['id'] == opened and db == 'healthy', (out, db))
        out = env.daw('start-all')
        pma = run('docker', 'inspect', '-f', '{{.State.Running}}', 'aula-db-admin-c').strip()
        check('daw-start-all keeps the Dev Container', env.web()['id'] == opened and pma == 'true', out)

        # check.sh starts Compose itself: on 27-11-2026 it recreated an open Dev Container and
        # VS Code stayed in «Cannot reconnect». Xdebug connects inside the container there.
        out = run('bash', 'scripts/check.sh', cwd=project, check=False)
        check('check.sh keeps an open Dev Container and checks Xdebug inside it',
              env.web()['id'] == opened and 'aberto en Dev Containers' in out
              and 'Xdebug conecta' in out and 'todo correcto' in out, out)
        out = env.daw('stop')
        check('daw-stop warns that VS Code loses the Dev Container',
              'perderá a conexión' in out and not env.web()['running'], out)

        env.up()
        check('Dev Containers reuses its own current container', env.web()['id'] == opened)

        # A change in a file of the definition: here, the Dev Container's own, in ~/html.
        time.sleep(0.05)
        dev = html / '.devcontainer/compose.devcontainer.yaml'
        dev.write_text(dev.read_text() + '      DAW_TEST: "1"\n')
        env.up()
        state = env.web()
        check('Dev Containers recreates its container after a change of its definition in ~/html',
              state['id'] != opened and state['devcontainer'] and state['env'].get('DAW_TEST') == '1',
              {'id': state['id'], 'opened': opened, 'DAW_TEST': state['env'].get('DAW_TEST')})

        run('docker', 'stop', '-t', '2', state['id'])
        env.daw('start')
        state = env.web()
        check('daw-start recreates a closed Dev Container with its own definition',
              state['running'] and not state['devcontainer'] and 'XDEBUG_CONFIG' not in state['env'], state)

        # git and the classroom copy replace files: the running container keeps the old inode.
        conf = project / 'docker/apache/daw-dev.conf'
        replacement = conf.with_name('.daw-dev.conf.new')
        replacement.write_text(conf.read_text() + '# daw-test-marker\n')
        time.sleep(0.05)
        replacement.replace(conf)
        before = state['id']
        out = env.daw('start')
        seen = run('docker', 'exec', env.backend, 'cat', '/etc/apache2/conf-available/daw-dev.conf')
        check('daw-start recreates the backend when a mounted file was replaced',
              env.web()['id'] != before and 'daw-test-marker' in seen and 'Recréase' in out, out)
        out = env.daw('start')
        check('daw-start leaves a current backend alone', 'Recréase' not in out, out)
        out = env.daw('web-root')
        check('daw-web-root shows ~/html', out.split() == [str(html)], out)

        env.daw('prepare-devcontainer')
        check('prepare-devcontainer removes the Compose container',
              not run('docker', 'compose', '-p', env.compose_name, 'ps', '--all', '--quiet', 'backend', cwd=project).strip())
    finally:
        run('docker', 'rm', '-f', 'daw-test-old-web', check=False)
        env.down()


def repository(tmp):
    # Personal installs: the clone, with www/ inside and the project in ~/daw in the container.
    project = pathlib.Path(tmp) / 'repo/daw-dev'
    copy_repository(project)
    env = Env(project, project, 'repo')
    (project / 'compose.override.yaml').write_text(override('repo', (18190, 13416, 18191)))
    # Only in the copy: the repository Dev Container does not read the override, which here gives
    # the test its own container names and ports.
    config = project / '.devcontainer/devcontainer.json'
    text = config.read_text()
    assert text.count('"../compose.yaml", ') == 1, 'devcontainer.json changed: update the test'
    config.write_text(text.replace('"../compose.yaml", ', '"../compose.yaml", "../compose.override.yaml", '))
    try:
        env.daw('start')
        env.up()
        state = env.web()
        check('repository layout: the Dev Container replaces the daw-start container and mounts the project in ~/daw',
              state['devcontainer'] and state['mounts'].get('/home/ad/daw') == str(project)
              and state['mounts'].get('/var/www/html') == str(project / 'www'), state)
        opened = state['id']
        time.sleep(0.05)
        (project / '.devcontainer/compose.devcontainer.yaml').touch()
        env.up()
        check('repository layout: a change in .devcontainer/ recreates the Dev Container', env.web()['id'] != opened)
    finally:
        env.down()


with tempfile.TemporaryDirectory(prefix='daw-devcontainer-') as tmp:
    classroom(tmp)
    repository(tmp)
print('ALL DEV CONTAINER TESTS PASSED')
