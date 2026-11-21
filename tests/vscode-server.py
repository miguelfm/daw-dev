#!/usr/bin/env python3
"""Run wsl/vscode-server.sh on fake VS Code Server packages, with a private HOME.
The packages have the layout of the real ones: vscode-server-linux-<arch>/ with node,
bin/code-server and product.json. node only needs the ELF header that the script reads.
"""
import io, os, pathlib, platform, subprocess, tarfile, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
script = repo / 'wsl/vscode-server.sh'
commit = '0123456789abcdef0123456789abcdef01234567'
other = 'f' * 40
machine = {'x86_64': b'\x3e\x00', 'aarch64': b'\xb7\x00'}[platform.machine()]


def package(path, commit=commit, machine=machine, gzip=True):
    with tarfile.open(path, 'w:gz' if gzip else 'w') as tar:
        def add(name, data, mode=0o755):
            info = tarfile.TarInfo('vscode-server-linux-x64/' + name)
            info.size, info.mode = len(data), mode
            tar.addfile(info, io.BytesIO(data))
        add('node', b'\x7fELF' + b'\x00' * 14 + machine + b'\x00' * 32)
        add('bin/code-server', b'#!/bin/sh\n')
        add('product.json', ('{\n  "commit": "%s",\n  "quality": "stable"\n}\n' % commit).encode(), 0o644)


with tempfile.TemporaryDirectory(prefix='daw-vscode-server-') as tmp:
    base = pathlib.Path(tmp)
    home = base / 'home'; home.mkdir()
    env = dict(os.environ, HOME=str(home))
    bin_dir = home / '.vscode-server/bin'
    count = 0

    def run(*args):
        return subprocess.run(['bash', str(script), *args], env=env, capture_output=True, text=True)

    def leftovers():
        return sorted(p.name for p in bin_dir.iterdir() if p.name.startswith('.daw-servidor')) if bin_dir.exists() else []

    assert run('comprobar', commit).returncode == 3
    assert run('comprobar', 'not-a-commit').returncode == 1
    assert run('outra', commit).returncode == 2
    count += 1; print('PASS a missing server is reported; bad arguments are rejected')

    for name, kwargs in (('other commit', {'commit': other}), ('other architecture', {'machine': b'\x28\x00'}), ('not gzip', {'gzip': False})):
        bad = base / ('bad-' + name.replace(' ', '-') + '.tar.gz'); package(bad, **kwargs)
        r = run('instalar', commit, str(bad))
        assert r.returncode == 1 and not (bin_dir / commit).exists() and not leftovers(), (name, r.stdout, r.stderr)
        count += 1; print('PASS rejected without installing:', name)

    good = base / 'vscode server.tar.gz'; package(good)
    r = run('instalar', commit, str(good))
    assert r.returncode == 0, r.stderr
    assert run('comprobar', commit).returncode == 0 and os.access(bin_dir / commit / 'node', os.X_OK)
    assert not leftovers(), leftovers()
    count += 1; print('PASS installs from a path with spaces and then reports it installed')

    # Un servidor incompleto (descarga interrompida de VS Code) substitúese enteiro.
    (bin_dir / commit / 'node').unlink(); (bin_dir / commit / 'resto').write_text('vello')
    assert run('comprobar', commit).returncode == 3
    r = run('instalar', commit, str(good))
    assert r.returncode == 0 and run('comprobar', commit).returncode == 0, r.stderr
    assert not (bin_dir / commit / 'resto').exists() and not leftovers(), leftovers()
    count += 1; print('PASS a broken server is replaced and the old copy removed')

    r = run('instalar', commit, str(base / 'missing.tar.gz'))
    assert r.returncode == 0, 'an installed server needs no package'
    count += 1; print('PASS an installed server is kept without reading the package')
print(f'ALL {count} VS CODE SERVER SCENARIOS PASSED')
