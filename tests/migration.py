#!/usr/bin/env python3
"""Exercise the actual migration text in a private tree with account tools stubbed.
Never executes real usermod/groupmod/pgrep/id or writes /etc or /home.
"""
import json, os, pathlib, shutil, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
pwsh = os.environ.get('PWSH_BIN', 'pwsh')
STUB = r'''#!/usr/bin/env python3
import json,os,pathlib,sys,shutil
root=pathlib.Path(os.environ['DAW_MIGRATION_FIXTURE'])
assert (root/'fixture.json').is_file()
p=root/'fixture.json';s=json.loads(p.read_text());name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:]
if name=='id':
 user=a[-1];exists=s.get(user,False)
 if not exists:sys.exit(1)
 if a[0]=='-u':print(s.get('uid',1000))
 elif a[0]=='-g':print(1000)
 sys.exit(0)
if name=='pgrep':sys.exit(s.get('pgrep_exit',0 if s.get('active',False) else 1))
if name=='getent':
 if a[0]=='passwd':
  user=a[-1];home=root/'home'/('elsewhere' if s.get('home_other') else user)
  print(user+':x:1000:1000::'+str(home)+':/bin/bash');sys.exit(0)
 group=a[-1]
 if not s.get('group_'+group,False):sys.exit(2)
 print(group+':x:1000:');sys.exit(0)
if name=='usermod':
 assert a==['-l','ad','-d',str(root/'home/ad'),'-m','alumno'],a
 if s.get('fail_usermod'):sys.exit(7)
 shutil.move(str(root/'home/alumno'),str(root/'home/ad'));s['alumno']=False;s['ad']=True
elif name=='groupmod':
 assert a==['-n','ad','alumno'],a
 s['group_alumno']=False;s['group_ad']=True
else:raise AssertionError(name)
p.write_text(json.dumps(s))
'''
with tempfile.TemporaryDirectory(prefix='daw-migration-') as tmp:
    base=pathlib.Path(tmp);source=base/'migration.sh'
    env=dict(os.environ,DAW_TEST_MODULE=str(repo/'wsl/aula/daw-aula.psm1'),DAW_TEST_OUTPUT=str(source))
    subprocess.run([pwsh,'-NoProfile','-Command',
      'Import-Module $env:DAW_TEST_MODULE -Force; [IO.File]::WriteAllText($env:DAW_TEST_OUTPUT,(Get-DawMigration),(New-Object Text.UTF8Encoding($false)))'],env=env,check=True)
    original=source.read_text()
    subprocess.run(['bash','-n',str(source)],check=True)
    def fixture(name, **state):
        root=base/name; (root/'etc').mkdir(parents=True);(root/'home').mkdir();(root/'bin').mkdir();(root/'usr/local/bin').mkdir(parents=True)
        state={'alumno':True,'ad':False,'group_alumno':True,'group_ad':False,**state}
        (root/'fixture.json').write_text(json.dumps(state))
        home=root/'home'/('alumno' if state['alumno'] else 'ad')
        project=home/'proxectos/daw-dev';(project/'www').mkdir(parents=True)
        (project/'compose.yaml').write_text('services: {}\n');(project/'www/work.php').write_text('student work')
        (root/'etc/wsl.conf').write_text('[boot]\nsystemd=true\ndefault=preserve\n[user] # user comment\ndefault=alumno\n[automount]\ndefault=also-preserve\n')
        for tool in ('id','pgrep','getent','usermod','groupmod'):
            p=root/'bin'/tool;p.write_text(STUB);p.chmod(0o755)
        text=original.replace('/usr/local/',str(root/'usr/local')+'/').replace('/home/',str(root/'home')+'/').replace('/etc/',str(root/'etc')+'/')
        script=root/'migration.sh';script.write_text(text)
        return root,script,project
    def run(root,script):
        return subprocess.run(['bash',str(script)],env=dict(os.environ,PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],DAW_MIGRATION_FIXTURE=str(root)),capture_output=True,text=True)
    root,script,project=fixture('migrate')
    launcher=root/'usr/local/bin/daw-aula-command'
    launcher.write_text(f'#!/usr/bin/env bash\ncd {root}/home/alumno/proxectos/daw-dev\n')
    r=run(root,script);assert r.returncode==0,r.stderr
    assert launcher.read_text().splitlines()[-1] == f'cd {root}/home/ad/proxectos/daw-dev'
    config=(root/'etc/wsl.conf').read_text()
    assert 'default=ad\n' in config and 'default=preserve' in config and 'default=also-preserve' in config
    assert (root/'home/ad/proxectos/daw-dev/www/work.php').read_text()=='student work'
    assert not (root/'home/alumno').exists() and (root/'home/ad/www').is_symlink()
    before=sorted(p.name for p in (root/'etc').iterdir());r=run(root,script);assert r.returncode==0,r.stderr
    assert before==sorted(p.name for p in (root/'etc').iterdir()),'retry rewrote unchanged config'
    (root/'home/alumno').symlink_to(root/'home/ad')
    r=run(root,script);assert r.returncode==0 and not (root/'home/alumno').is_symlink(),r.stderr
    print('PASS actual migration preserves project/config sections and is idempotent')
    env=root/'home/ad/proxectos/daw-dev/.env'
    env.write_text('WEB_PORT=127.0.0.1:80\nDB_PASSWORD=abc123.\nDB_ROOT_PASSWORD=abc123.\n')
    r=run(root,script);assert r.returncode==0,r.stderr
    assert env.read_text()=='WEB_PORT=127.0.0.1:80\nDB_PASSWORD=abc123..\nDB_ROOT_PASSWORD=abc123..\n',env.read_text()
    backups=list(env.parent.glob('.env.daw-backup-*'));assert len(backups)==1 and 'abc123.\n' in backups[0].read_text()
    r=run(root,script);assert r.returncode==0 and len(list(env.parent.glob('.env.daw-backup-*')))==1,r.stderr
    env.write_text('DB_PASSWORD=persoal\nDB_ROOT_PASSWORD=abc123..\n')
    r=run(root,script);assert r.returncode==0 and env.read_text()=='DB_PASSWORD=persoal\nDB_ROOT_PASSWORD=abc123..\n'
    print('PASS old default MariaDB password in .env replaced once, custom values kept')
    for name,opts in [('active',{'active':True}),('process-check-error',{'pgrep_exit':2}),('collision',{'ad':True}),('uid',{'uid':1001}),('home',{'home_other':True}),('usermod-error',{'fail_usermod':True})]:
        root,script,project=fixture(name,**opts);before=(root/'etc/wsl.conf').read_bytes()
        r=run(root,script);assert r.returncode!=0,(name,r.stdout)
        assert (project/'www/work.php').read_text()=='student work'
        assert (root/'etc/wsl.conf').read_bytes()==before
        assert not (root/'home/ad').exists()
        print('PASS rejected without data loss:',name)
    root,script,project=fixture('www-collision');(root/'home/alumno/www').mkdir();(root/'home/alumno/www/personal').write_text('personal')
    r=run(root,script);assert r.returncode!=0
    assert (root/'home/alumno/www/personal').read_text()=='personal';assert not (root/'home/ad').exists()
    print('PASS existing www data preserved')
    root,script,project=fixture('duplicate-user');(root/'etc/wsl.conf').write_text('[user]\ndefault=alumno\n[user]\ndefault=other\n')
    r=run(root,script);assert r.returncode!=0 and (root/'home/alumno').is_dir() and not(root/'home/ad').exists()
    print('PASS ambiguous config rejected before user rename')
    root,script,project=fixture('foreign-home',alumno=False,ad=True,group_alumno=False,group_ad=True)
    (root/'home/alumno').mkdir();(root/'home/alumno/personal').write_text('personal')
    r=run(root,script);assert r.returncode!=0
    assert (root/'home/alumno/personal').read_text()=='personal'
    print('PASS an existing unrelated home is preserved')
print('ALL 11 MIGRATION SCENARIOS PASSED')
