#!/usr/bin/env python3
"""Alternate daw-start and Dev Containers on one backend container, with real Docker.

Dev Containers reuses whatever backend container exists, and Compose recreates a Dev Container's.
The test runs on a copy of the repository with its own project name, container names and ports,
so it leaves the user's daw-* containers alone. It needs Docker, the backend image and the
Dev Containers CLI (DEVCONTAINER_BIN, `devcontainer` by default).
"""
import json, os, pathlib, shutil, subprocess, tempfile, time

repo = pathlib.Path(__file__).resolve().parents[1]
devcontainer = os.environ.get('DEVCONTAINER_BIN', 'devcontainer')
project_name = 'daw-dev-test-devcontainer'
OVERRIDE = '''services:
  backend:
    container_name: daw-test-backend-c
    ports: !override ["127.0.0.1:18180:80"]
  db:
    container_name: daw-test-db-c
    ports: !override ["127.0.0.1:13406:3306"]
  db-admin:
    container_name: daw-test-db-admin-c
    ports: !override ["127.0.0.1:18181:80"]
'''


def run(*args, cwd=None, check=True):
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8')
    if check and result.returncode:
        raise AssertionError(f'{" ".join(map(str, args))} failed ({result.returncode}):\n{result.stdout}')
    return result.stdout


def web(project):
    ids = run('docker', 'compose', '-p', project_name, 'ps', '--all', '--quiet', 'backend', cwd=project).split()
    assert len(ids) == 1, ids
    info = json.loads(run('docker', 'inspect', ids[0]))[0]
    labels = info['Config'].get('Labels') or {}
    return {
        'id': info['Id'], 'running': info['State']['Running'], 'started': info['State']['StartedAt'],
        'devcontainer': bool(labels.get('devcontainer.local_folder')),
        'mounts': {m['Destination'] for m in info['Mounts']},
        'env': dict(e.split('=', 1) for e in info['Config']['Env']),
        'image': info['Image'],
        'hostname': info['Config']['Hostname'],
    }


def daw(project, action):
    return run('bash', 'scripts/daw.sh', action, cwd=project)


def up(project):
    out = run(devcontainer, 'up', '--workspace-folder', str(project), cwd=project)
    assert '"outcome":"success"' in out, out
    return out


def check(name, condition, detail=''):
    if not condition:
        raise AssertionError(f'{name}: {detail}')
    print(f'PASS {name}')


with tempfile.TemporaryDirectory(prefix='daw-devcontainer-') as tmp:
    project = pathlib.Path(tmp) / 'daw-dev'
    files = run('git', '-C', str(repo), 'ls-files', '-z').split('\0')
    for rel in filter(None, files):
        source = repo / rel
        # www/ only with the repository's index.php and info.php, which check.sh uses.
        if source.is_file():
            target = project / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    (project / 'www').mkdir(exist_ok=True)
    # The classroom layout: devcontainer.json also names compose.override.yaml, here the test's.
    shutil.copy(repo / 'windows/classroom/overlay/.devcontainer/devcontainer.json', project / '.devcontainer/devcontainer.json')
    (project / 'compose.override.yaml').write_text(OVERRIDE)
    # Its own MariaDB volume: compose.yaml names it daw-dev_db_data unless DB_VOLUME_NAME says otherwise.
    (project / '.env').write_text(f'COMPOSE_PROJECT_NAME={project_name}\nDB_VOLUME_NAME={project_name}_db_data\n'
                                  f'USER_UID={os.getuid()}\nUSER_GID={os.getgid()}\n')
    images = set()
    try:
        # Before 27-11-2026 the service was web: its container, still running, holds the port.
        image = run('docker', 'compose', 'config', '--images', 'backend', cwd=project).split()[0]
        run('docker', 'run', '-d', '--name', 'daw-test-old-web', '--label', f'com.docker.compose.project={project_name}',
            '--label', 'com.docker.compose.service=web', '-p', '127.0.0.1:18180:80', image)
        out = daw(project, 'start')
        gone = run('docker', 'ps', '-aq', '--filter', 'name=^daw-test-old-web$').strip()
        check('daw-start removes the container of the previous service and takes its port',
              not gone and 'servizo anterior web' in out and web(project)['running'], out)
        state = web(project)
        check('daw-start creates the Compose definition', state['running'] and not state['devcontainer'] and '/home/ad/daw' not in state['mounts'], state)

        up(project)
        state = web(project)
        images.add(state['image'])
        check('Dev Containers replaces the container daw-start created',
              state['devcontainer'] and '/home/ad/daw' in state['mounts'] and state['env'].get('XDEBUG_CONFIG') == 'client_host=localhost'
              and state['hostname'] == 'backend', state)
        opened = state['id']

        out = daw(project, 'start')
        state = web(project)
        check('daw-start keeps an open Dev Container', state['id'] == opened and state['running'] and 'Dev Containers' in out, out)
        out = daw(project, 'start-db')
        state = web(project)
        db = run('docker', 'inspect', '-f', '{{.State.Health.Status}}', 'daw-test-db-c').strip()
        check('daw-start-db starts MariaDB and keeps the Dev Container', state['id'] == opened and db == 'healthy', (out, db))
        out = daw(project, 'start-all')
        pma = run('docker', 'inspect', '-f', '{{.State.Running}}', 'daw-test-db-admin-c').strip()
        check('daw-start-all keeps the Dev Container', web(project)['id'] == opened and pma == 'true', out)

        # check.sh starts Compose itself: on 27-11-2026 it recreated an open Dev Container and
        # VS Code stayed in «Cannot reconnect». Xdebug connects inside the container there.
        out = run('bash', 'scripts/check.sh', cwd=project, check=False)
        check('check.sh keeps an open Dev Container and checks Xdebug inside it',
              web(project)['id'] == opened and 'aberto en Dev Containers' in out
              and 'Xdebug conecta' in out and 'todo correcto' in out, out)
        out = daw(project, 'stop')
        check('daw-stop warns that VS Code loses the Dev Container',
              'perderá a conexión' in out and not web(project)['running'], out)

        up(project)
        check('Dev Containers reuses its own current container', web(project)['id'] == opened)

        time.sleep(0.05)
        web_block = '    container_name: daw-test-backend-c\n'
        (project / 'compose.override.yaml').write_text(
            OVERRIDE.replace(web_block, web_block + '    environment:\n      DAW_TEST: "1"\n'))
        out = up(project)
        state = web(project)
        images.add(state['image'])
        check('Dev Containers recreates its container after a project change',
              state['id'] != opened and state['devcontainer'] and state['env'].get('DAW_TEST') == '1',
              {'id': state['id'], 'opened': opened, 'DAW_TEST': state['env'].get('DAW_TEST')})

        run('docker', 'stop', '-t', '2', state['id'])
        daw(project, 'start')
        state = web(project)
        check('daw-start recreates a closed Dev Container with its own definition',
              state['running'] and not state['devcontainer'] and '/home/ad/daw' not in state['mounts'], state)

        # git and the classroom copy replace files: the running container keeps the old inode.
        conf = project / 'docker/apache/daw-dev.conf'
        replacement = conf.with_name('.daw-dev.conf.new')
        replacement.write_text(conf.read_text() + '# daw-test-marker\n')
        time.sleep(0.05)
        replacement.replace(conf)
        before = state['id']
        out = daw(project, 'start')
        seen = run('docker', 'exec', 'daw-test-backend-c', 'cat', '/etc/apache2/conf-available/daw-dev.conf')
        check('daw-start recreates web when a mounted file was replaced',
              web(project)['id'] != before and 'daw-test-marker' in seen and 'Recréase' in out, out)
        out = daw(project, 'start')
        check('daw-start leaves a current web container alone', 'Recréase' not in out, out)

        run('bash', 'scripts/daw.sh', 'prepare-devcontainer', cwd=project)
        check('prepare-devcontainer removes the Compose container',
              not run('docker', 'compose', '-p', project_name, 'ps', '--all', '--quiet', 'backend', cwd=project).strip())
    finally:
        run('docker', 'rm', '-f', 'daw-test-old-web', check=False)
        run('docker', 'compose', '-p', project_name, '--profile', 'frontend', '--profile', 'doc', 'down', '-v', '--remove-orphans', cwd=project, check=False)
        # Only the images Dev Containers built on top of the project's (vsc-*), never the base one.
        for image in images:
            tags = run('docker', 'image', 'inspect', '-f', '{{json .RepoTags}}', image, check=False)
            if tags.startswith('[') and all(t.startswith('vsc-') for t in json.loads(tags) or ['-']):
                run('docker', 'image', 'rm', '-f', image, check=False)
print('ALL DEV CONTAINER TESTS PASSED')
