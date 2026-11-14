from pathlib import Path
import json,subprocess,hashlib,shutil,sys
root=Path.cwd();m=json.loads(Path('validation/island-void/sync-manifest.json').read_text());w=Path(m['worktree']);backup=Path(m['backup']);logpath=root/'validation/island-void/sync-install.log'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with logpath.open('w',buffering=1) as log:
 def git(*args):
  r=subprocess.run(['git',*args],capture_output=True);log.write('git '+repr(args)+'\n'+r.stdout.decode()+r.stderr.decode());assert r.returncode==0,(args,r.returncode);return r.stdout.decode().strip()
 assert git('branch','--show-current')=='main'
 assert git('rev-parse','HEAD')==m['head']
 assert git('rev-parse','origin/main')==m['remote'],'origin moved; stop before stash'
 assert not git('diff','--cached','--name-only')
 assert set(git('diff','--name-only').splitlines())==set(m['files']),'new changes; stop before stash'
 for f,h in m['sha256'].items():assert sha(root/f)==h,'concurrent edit '+f
 log.write('PASS all 11 original fingerprints unchanged\n')
 git('diff','--check')
 # Save integrated bytes/checksums independently before touching shared main.
 for f in m['files']+[m['new']]:
  dest=backup/'integrated'/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(w/f,dest)
 (backup/'integrated.sha256.json').write_text(json.dumps({f:sha(w/f) for f in m['files']+[m['new']]},ensure_ascii=False,indent=2))
 git('stash','push','-m','island-sync-original-c9df58a-20261114','--',*m['files'])
 stash=git('rev-parse','refs/stash');m['stash_oid']=stash
 (backup/'stash-oid.txt').write_text(stash+'\n')
 (root/'validation/island-void/sync-manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2))
 assert not git('diff','--name-only'),'unexpected tracked changes after scoped stash'
 git('merge','--ff-only',m['remote'])
 assert git('rev-parse','HEAD')==m['remote']
 assert sha(root/m['new'])==m['sha256'][m['new']],'untracked doc modified concurrently'
 # Recheck each destination against remote bytes immediately before replacement.
 for f in m['files']:
  assert (root/f).read_bytes()==(backup/'remote'/f).read_bytes(),'concurrent post-ff edit '+f
 for f in m['files']+[m['new']]:
  expected=(backup/'remote'/f) if f in m['files'] else (backup/'local'/f)
  assert (root/f).read_bytes()==expected.read_bytes(),'concurrent write '+f
  tmp=(root/f).with_name((root/f).name+'.island-sync-tmp');tmp.write_bytes((w/f).read_bytes());tmp.replace(root/f)
 for f in ['check.py','check.lua','terrain-before.lua']:
  shutil.copy2(w/'validation/island-void'/f,root/'validation/island-void'/f)
 git('diff','--check')
 git('status','--short')
 git('rev-list','--left-right','--count','HEAD...origin/main')
 git('diff','--stat')
 assert set(git('diff','--name-only').splitlines())==set(m['files'])
 assert not git('diff','--cached','--name-only')
 log.write('PASS original stash retained '+stash+'\n')
 (backup/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2))
print('scoped stash + ff + integrated replay / PASS / '+str(logpath))
