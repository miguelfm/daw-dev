#!/usr/bin/env python3
"""Run the actual project move Bash (~/workspace to ~/daw) on private fixture trees.
docker is stubbed: it lists one running container of the old project and logs what it is asked.
"""
import os, pathlib, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
pwsh = os.environ.get('PWSH_BIN', 'pwsh')
STUB = '''#!/bin/sh
echo "$*" >> "$DAW_DOCKER_LOG"
case "$1" in
    info) exit 0 ;;
    ps) echo abc123 ;;
esac
'''

with tempfile.TemporaryDirectory(prefix='daw-move-') as tmp:
    base = pathlib.Path(tmp)
    script = base / 'move.sh'
    env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(script))
    subprocess.run([pwsh, '-NoProfile', '-Command',
        'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,(Get-DawProjectMoveScript),(New-Object Text.UTF8Encoding($false)))'],
        env=env, check=True)
    assert b'\r' not in script.read_bytes()
    bin_dir = base / 'stub'; bin_dir.mkdir()
    (bin_dir / 'docker').write_text(STUB); (bin_dir / 'docker').chmod(0o755)

    def run(root, *, check=True):
        log = root / 'docker.log'
        env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}', DAW_DOCKER_LOG=str(log), DAW_BIN_DIR=str(root / 'bin'))
        r = subprocess.run(['bash', '-c', script.read_text(), 'daw-move', str(root / 'home/ad/workspace'), str(root / 'home/ad/daw')],
                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8')
        if check:
            assert r.returncode == 0, r.stdout
        return r, (log.read_text() if log.exists() else '')

    def fixture(name):
        root = base / name
        old = root / 'home/ad/workspace'
        (old / 'www').mkdir(parents=True); (old / 'scripts').mkdir()
        (old / 'compose.yaml').write_text('name: daw-dev\n'); (old / 'www/index.php').write_text('<?php\n')
        (old / 'scripts/daw.sh').write_text('#!/bin/sh\n')
        (root / 'bin').mkdir()
        os.symlink(old / 'scripts/daw.sh', root / 'bin/daw-start')
        os.symlink('/elsewhere/daw.sh', root / 'bin/daw-other')
        return root

    root = fixture('move')
    r, log = run(root)
    new, old = root / 'home/ad/daw', root / 'home/ad/workspace'
    assert r.stdout.strip() == 'moved', r.stdout
    assert (new / 'www/index.php').is_file() and old.is_symlink() and os.readlink(old) == str(new)
    assert (old / 'www/index.php').is_file(), 'The previous path still reaches the project'
    assert os.readlink(root / 'bin/daw-start') == str(new / 'scripts/daw.sh')
    assert os.readlink(root / 'bin/daw-other') == '/elsewhere/daw.sh', 'Other links are left alone'
    assert f'label=com.docker.compose.project.working_dir={old}' in log and 'stop abc123' in log, log
    print('PASS the project moves with its containers stopped and the old path as a link')

    r, log = run(root)
    assert r.stdout.strip() == '' and log == open(root / 'docker.log').read(), 'A second run changes nothing'
    print('PASS a moved project is left alone')

    root = fixture('both'); (root / 'home/ad/daw').mkdir()
    r, _ = run(root, check=False)
    assert r.returncode != 0 and 'non se moveu' in r.stdout and (root / 'home/ad/workspace/compose.yaml').is_file(), r.stdout
    print('PASS nothing moves when both paths exist')

    root = base / 'other'; (root / 'home/ad/workspace').mkdir(parents=True)
    r, _ = run(root, check=False)
    assert r.returncode != 0 and 'non é o proxecto' in r.stdout and not (root / 'home/ad/daw').exists(), r.stdout
    print('PASS a ~/workspace that is not the project is not moved')

    root = base / 'fresh'; (root / 'home/ad/daw').mkdir(parents=True)
    r, log = run(root)
    assert r.stdout.strip() == '' and log == '', 'A model with ~/daw needs nothing'
    print('PASS a project already in ~/daw needs nothing')
print('ALL PROJECT MOVE TESTS PASSED')
