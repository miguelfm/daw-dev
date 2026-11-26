#!/usr/bin/env python3
"""Run the actual VS Code Server install Bash on a private HOME with a fake server archive.
wslpath is stubbed: C:\\a\\b maps to <fixture>/c/a/b.
DAW_CODE_SERVER_SCRIPT can point to the script already exported from the module, to run without pwsh.
"""
import io, os, pathlib, shutil, subprocess, tarfile, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
pwsh = os.environ.get('PWSH_BIN', 'pwsh')
COMMIT = '0123456789abcdef0123456789abcdef01234567'
WSLPATH = r'''#!/usr/bin/env bash
[[ $1 == -u ]] && shift
p=${1//\\//}
[[ $p =~ ^([A-Za-z]):(.*)$ ]] && p="$DAW_FIXTURE/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
printf '%s\n' "$p"
'''

def archive(path, with_node=True):
    with tarfile.open(path, 'w:gz') as tar:
        files = {'vscode-server-linux-x64/bin/code-server': b'#!/bin/sh\n', 'vscode-server-linux-x64/product.json': b'{}'}
        if with_node:
            files['vscode-server-linux-x64/node'] = b'#!/bin/sh\n'
        for name, data in files.items():
            info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))

with tempfile.TemporaryDirectory(prefix='daw-code-server-') as tmp:
    base = pathlib.Path(tmp)
    script = base / 'install.sh'
    if os.environ.get('DAW_CODE_SERVER_SCRIPT'):
        shutil.copy(os.environ['DAW_CODE_SERVER_SCRIPT'], script)
    else:
        env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(script))
        subprocess.run([pwsh, '-NoProfile', '-Command',
            'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,(Get-DawCodeServerInstallScript),(New-Object Text.UTF8Encoding($false)))'],
            env=env, check=True)
    assert b'\r' not in script.read_bytes()
    subprocess.run(['bash', '-n', str(script)], check=True)
    if not os.environ.get('DAW_CODE_SERVER_SCRIPT'):
        extensions = base / 'extensions.sh'
        env = dict(os.environ, DAW_TEST_MODULE=str(repo / 'windows/classroom/daw-classroom.psm1'), DAW_TEST_OUTPUT=str(extensions))
        subprocess.run([pwsh, '-NoProfile', '-Command',
            'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,(Get-DawCodeExtensionsInstallScript),(New-Object Text.UTF8Encoding($false)))'],
            env=env, check=True)
        subprocess.run(['bash', '-n', str(extensions)], check=True)
    count = 0

    def fixture(name, with_node=True):
        root = base / name
        (root / 'bin').mkdir(parents=True); (root / 'home').mkdir()
        (root / 'bin/wslpath').write_text(WSLPATH); (root / 'bin/wslpath').chmod(0o755)
        (root / 'c/DAW-Dev').mkdir(parents=True)
        archive(root / f'c/DAW-Dev/vscode-server-{COMMIT}.tar.gz', with_node)
        return root

    def run(root, commit=COMMIT):
        env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'], DAW_FIXTURE=str(root), HOME=str(root / 'home'))
        return subprocess.run(['bash', str(script), rf'C:\DAW-Dev\vscode-server-{COMMIT}.tar.gz', commit], env=env, capture_output=True, text=True)

    root = fixture('install')
    r = run(root)
    assert r.returncode == 0 and r.stdout.split() == ['ready', COMMIT], r.stderr
    destinations = [root / f'home/.vscode-server/bin/{COMMIT}', root / f'home/.vscode-server/cli/servers/Stable-{COMMIT}/server']
    for dest in destinations:
        assert os.access(dest / 'node', os.X_OK) and (dest / 'bin/code-server').exists(), dest
    assert not list((root / 'home/.vscode-server/bin').glob('.daw-server-*'))
    count += 1; print('PASS extracts the server for Remote - WSL and for the VS Code CLI')

    (destinations[0] / 'marker').write_text('kept')
    r = run(root)
    assert r.returncode == 0 and (destinations[0] / 'marker').read_text() == 'kept', r.stderr
    count += 1; print('PASS an installed server is kept')

    r = run(root, 'not-a-commit')
    assert r.returncode != 0 and 'Commit non válido' in r.stderr, r.stderr
    count += 1; print('PASS rejects an invalid commit')

    root = fixture('not-a-server', with_node=False)
    r = run(root)
    assert r.returncode != 0 and 'non contén VS Code Server' in r.stderr, r.stderr
    assert not (root / f'home/.vscode-server/bin/{COMMIT}').exists()
    assert not list((root / 'home/.vscode-server/bin').glob('.daw-server-*'))
    count += 1; print('PASS an archive without the server changes nothing')
print(f'ALL {count} VS CODE SERVER SCENARIOS PASSED')
