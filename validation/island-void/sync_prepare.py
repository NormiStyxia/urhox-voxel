from pathlib import Path
import subprocess,json,hashlib,datetime,shutil
root=Path.cwd(); log=root/'validation/island-void/sync-prepare.log'
files=['assets/Shaders/BLGL/RuinsGround.shader','docs/README.md','scripts/dragon/DragonAnimationController.lua','scripts/ruins/GrassTufts.lua','scripts/ruins/NomiController.lua','scripts/ruins/RuinsBuild.lua','scripts/ruins/RuinsDragon.lua','scripts/ruins/RuinsPuzzles.lua','scripts/ruins/RuinsScene.lua','scripts/ruins/RuinsTerrain.lua']
new='docs/空岛地形改造-2026-11-13.md'
def git(*args):
 p=subprocess.run(['git',*args],capture_output=True,check=True); return p.stdout
with log.open('w') as out:
 status=git('status','--porcelain=v1','-z');out.write(repr(status)+'\n')
 changed=set(git('diff','--name-only').decode().splitlines())
 assert changed==set(files),(changed,files)
 assert not git('diff','--cached','--name-only'),'unexpected staged changes'
 head=git('rev-parse','HEAD').decode().strip();remote=git('rev-parse','origin/main').decode().strip()
 out.write('HEAD='+head+'\nREMOTE='+remote+'\n')
 stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
 backup=root.parent/('体素test-island-sync-backup-'+stamp);backup.mkdir()
 manifest={'root':str(root),'backup':str(backup),'head':head,'remote':remote,'files':files,'new':new,'sha256':{}}
 for f in files+[new]:
  data=(root/f).read_bytes(); manifest['sha256'][f]=hashlib.sha256(data).hexdigest()
  dest=backup/'local'/f;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  if f in files:
   dest=backup/'base'/f;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(git('show',head+':'+f))
   dest=backup/'remote'/f;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(git('show',remote+':'+f))
 (backup/'island-original.patch').write_bytes(git('diff','--binary','--',*files))
 (backup/'status-before.txt').write_bytes(status)
 # Existing evidence scripts will need updated assertions: retain their original versions too.
 shutil.copytree(root/'validation/island-void',backup/'validation-original',ignore=shutil.ignore_patterns('lsp'))
 worktree=Path('/tmp')/('island-integration-'+stamp);manifest['worktree']=str(worktree)
 out.write(git('worktree','add','--detach',str(worktree),remote).decode())
 conflicts=[]
 for f in files:
  p=subprocess.run(['git','merge-file','-p',str(backup/'local'/f),str(backup/'base'/f),str(backup/'remote'/f)],capture_output=True)
  assert p.returncode>=0 and p.returncode<128,p.stderr
  (worktree/f).write_bytes(p.stdout)
  if p.returncode: conflicts.append(f)
 (worktree/new).write_bytes((backup/'local'/new).read_bytes())
 manifest['conflicts']=conflicts
 (backup/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 (root/'validation/island-void/sync-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 out.write('BACKUP='+str(backup)+'\nWORKTREE='+str(worktree)+'\nCONFLICTS='+repr(conflicts)+'\n')
print('sync_prepare.py / PASS / '+str(log))
