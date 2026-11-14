from pathlib import Path
import json,subprocess,hashlib,datetime
root=Path.cwd();m=json.loads(Path('validation/island-void/sync-manifest.json').read_text());b=Path(m['backup']);logpath=root/'validation/island-void/sync-final.log'
with logpath.open('w') as log:
 log.write('UTC '+datetime.datetime.now(datetime.timezone.utc).isoformat()+'\n')
 def git(*args):
  r=subprocess.run(['git',*args],capture_output=True);log.write('git '+repr(args)+'\n'+r.stdout.decode()+r.stderr.decode());assert r.returncode==0;return r.stdout.decode().strip()
 head=git('rev-parse','HEAD');remote=git('rev-parse','origin/main')
 assert head==remote==m['remote']
 assert git('branch','--show-current')=='main'
 assert git('rev-list','--count',m['head']+'..HEAD')=='30'
 git('merge-base','--is-ancestor',m['head'],'HEAD')
 assert git('rev-list','--left-right','--count','HEAD...origin/main').split()==['0','0']
 assert not git('diff','--cached','--name-only')
 assert set(git('diff','--name-only').splitlines())==set(m['files'])
 for f,h in json.loads((b/'integrated.sha256.json').read_text()).items():
  assert hashlib.sha256((root/f).read_bytes()).hexdigest()==h,'post-merge concurrent change '+f
 assert m['stash_oid'] in git('stash','list','--format=%H %gs')
 git('status','--short');git('diff','--stat');git('diff','--check')
 log.write('PASS main retains all 30 remote commits; 10 tracked changes + new island doc match reviewed snapshot\n')
print('git ancestry/status/fingerprints / PASS / '+str(logpath))
