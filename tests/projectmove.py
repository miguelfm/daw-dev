#!/usr/bin/env python3
"""Run the actual project move Bash on private fixture trees.

Before 27-11-2026 the project was ~/daw (and before, ~/workspace), with www, data and angular
inside. Now the environment is ~/.daw and the student's directories go to the home: ~/html,
~/data and ~/angular. docker is stubbed: it lists one running container and logs its calls.
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


def export(name, output):
    env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(output))
    subprocess.run([pwsh, '-NoProfile', '-Command',
        f'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,({name}),(New-Object Text.UTF8Encoding($false)))'],
        env=env, check=True)
    assert b'\r' not in output.read_bytes()


with tempfile.TemporaryDirectory(prefix='daw-move-') as tmp:
    base = pathlib.Path(tmp)
    move, links = base / 'move.sh', base / 'links.sh'
    export('Get-DawProjectMoveScript', move)
    export('Get-DawPreviousLinksScript', links)
    bin_dir = base / 'stub'; bin_dir.mkdir()
    (bin_dir / 'docker').write_text(STUB); (bin_dir / 'docker').chmod(0o755)

    def home(root):
        return root / 'home/ad'

    def run(root, script=move, *, check=True):
        h = home(root)
        log = root / 'docker.log'
        env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}', DAW_DOCKER_LOG=str(log), DAW_BIN_DIR=str(root / 'bin'))
        args = [str(h / '.daw'), str(h / 'html'), str(h / 'data'), str(h / 'angular')] if script == move else [str(h / '.daw')]
        args += [str(h / 'daw'), str(h / 'workspace')]
        r = subprocess.run(['bash', '-c', script.read_text(), 'daw', *args],
                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8')
        if check:
            assert r.returncode == 0, r.stdout
        return r, (log.read_text() if log.exists() else '')

    def project(path):
        for d in ('www', 'data', 'angular', 'scripts'):
            (path / d).mkdir(parents=True)
        (path / 'compose.yaml').write_text('name: daw-dev\n')
        (path / 'www/index.php').write_text('<?php\n')
        (path / 'data/usuarios.txt').write_text('ana\n')
        (path / 'angular/README.txt').write_text('angular\n')
        (path / 'scripts/daw.sh').write_text('#!/bin/sh\n')

    def snapshot(root):
        return sorted((str(p.relative_to(root)), os.readlink(p) if p.is_symlink() else None)
                      for p in root.rglob('*'))

    def fixture(name, previous='daw'):
        root = base / name
        h = home(root)
        project(h / previous)
        (root / 'bin').mkdir()
        os.symlink(h / previous / 'scripts/daw.sh', root / 'bin/daw-start')
        os.symlink('/elsewhere/daw.sh', root / 'bin/daw-other')
        return root

    # ~/daw, the layout from 27-11-2026, with the ~/workspace link of the move before it.
    root = fixture('from-daw')
    h = home(root)
    os.symlink(h / 'daw', h / 'workspace')
    os.symlink(h / 'workspace/scripts/daw.sh', root / 'bin/daw-shell')
    r, log = run(root)
    env = h / '.daw'
    assert r.stdout.strip() == 'moved', r.stdout
    assert (env / 'compose.yaml').is_file() and (h / 'html/index.php').is_file() and (h / 'data/usuarios.txt').is_file()
    assert (h / 'angular/README.txt').is_file() and not (h / 'html').is_symlink()
    for name, target in (('www', 'html'), ('data', 'data'), ('angular', 'angular')):
        assert os.readlink(env / name) == str(h / target), name
    assert os.readlink(h / 'daw') == str(env) and (h / 'workspace/compose.yaml').is_file(), 'Previous paths still reach the environment'
    assert (h / 'daw/www/index.php').is_file(), 'A previous shortcut to ~/daw/www still reaches the code'
    for link in ('daw-start', 'daw-shell'):
        assert os.readlink(root / 'bin' / link) == str(env / 'scripts/daw.sh'), link
    assert os.readlink(root / 'bin/daw-other') == '/elsewhere/daw.sh', 'Other links are left alone'
    for d in (h / 'daw', h / 'workspace'):
        assert f'label=com.docker.compose.project.working_dir={d}' in log, log
    assert 'stop abc123' in log, log
    print('PASS ~/daw moves to ~/.daw, and www, data and angular to ~/html, ~/data and ~/angular')

    before = snapshot(root)
    r, log2 = run(root)
    assert r.stdout.strip() == '' and snapshot(root) == before and log2 == log, 'A second run changes nothing'
    print('PASS a moved environment is left alone')

    r, _ = run(root, links)
    assert sorted(r.stdout.splitlines()) == [f'removed {h / "daw"}', f'removed {h / "workspace"}'], r.stdout
    assert not (h / 'daw').exists() and not (h / 'workspace').is_symlink() and env.is_dir()
    print('PASS the activation removes the links of the previous paths')

    root = fixture('from-workspace', 'workspace')
    h = home(root)
    r, _ = run(root)
    assert r.stdout.strip() == 'moved' and (h / '.daw/compose.yaml').is_file() and (h / 'html/index.php').is_file(), r.stdout
    assert os.readlink(h / 'workspace') == str(h / '.daw') and not (h / 'daw').exists()
    print('PASS an account still in ~/workspace moves straight to the current layout')

    root = fixture('both')
    h = home(root)
    (h / '.daw').mkdir()
    before = snapshot(root)
    r, _ = run(root, check=False)
    assert r.returncode != 0 and 'non se moveu' in r.stdout and snapshot(root) == before, r.stdout
    print('PASS nothing moves when ~/daw and ~/.daw both exist')

    root = fixture('html-taken')
    h = home(root)
    (h / 'html').mkdir(); (h / 'html/mine.php').write_text('x')
    before = snapshot(root)
    r, _ = run(root, check=False)
    assert r.returncode != 0 and 'non se moveu' in r.stdout and snapshot(root) == before, r.stdout
    print('PASS nothing moves when ~/html already has files')

    root = fixture('html-empty')
    h = home(root)
    (h / 'html').mkdir()
    r, _ = run(root)
    assert r.stdout.strip() == 'moved' and (h / 'html/index.php').is_file(), r.stdout
    print('PASS an empty ~/html takes the code')

    root = base / 'other'; h = home(root); (h / 'daw').mkdir(parents=True); (root / 'bin').mkdir()
    r, _ = run(root, check=False)
    assert r.returncode != 0 and 'non é o proxecto' in r.stdout and not (h / '.daw').exists(), r.stdout
    print('PASS a ~/daw that is not the project is not moved')

    root = base / 'split'; h = home(root); project(h / '.daw'); (root / 'bin').mkdir()
    r, _ = run(root)
    assert r.stdout.strip() == 'moved' and (h / 'html/index.php').is_file() and os.readlink(h / '.daw/www') == str(h / 'html'), r.stdout
    print('PASS an environment with www, data or angular inside still splits them out')

    root = base / 'fresh'; h = home(root); (h / '.daw').mkdir(parents=True); (h / 'html').mkdir(); (root / 'bin').mkdir()
    (h / '.daw/compose.yaml').write_text('name: daw-dev\n')
    r, log = run(root)
    assert r.stdout.strip() == '' and log == '', 'The current layout needs nothing'
    print('PASS the current layout needs nothing')

    root = base / 'empty-angular'; h = home(root)
    (h / '.daw/angular').mkdir(parents=True); (h / 'angular').mkdir(parents=True); (root / 'bin').mkdir()
    (h / '.daw/compose.yaml').write_text('name: daw-dev\n')
    (h / 'angular/README.txt').write_text('angular\n')
    r, log = run(root)
    assert r.stdout.strip() == '' and log == '' and not (h / '.daw/angular').exists() and (h / 'angular/README.txt').is_file(), r.stdout
    print('PASS an empty spurious ~/.daw/angular is removed without touching ~/angular')
print('ALL PROJECT MOVE TESTS PASSED')
