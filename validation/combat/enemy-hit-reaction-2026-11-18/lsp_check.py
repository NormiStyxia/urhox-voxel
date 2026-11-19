import json,pathlib,subprocess,threading,queue,time
root=pathlib.Path.cwd(); config=json.loads((root/'scripts/.luarc.json').read_text()); config['workspace']['library']=[str(root/'.emmylua'),str(root/'urhox-libs')]; config['diagnostics']['severity']={k:v.lower() for k,v in config['diagnostics']['severity'].items()}; q=queue.Queue(); serial=0
server='/var/folders/hd/xtv81s8s2dvbdgdp2kd8nz7m0000gn/T/maker-lua-lsp/0.22.2/emmylua_ls'
p=subprocess.Popen([server,'--communication','stdio','--log-level','warn','--log-path','none','--resources-path','none'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=open('/Users/xd/Desktop/体素test/validation/combat/leg-gait-lead-2026-11-18/lsp-native-server.log','w'))
def read():
 while True:
  headers={}
  while True:
   line=p.stdout.readline()
   if not line:return
   if line==b'\r\n':break
   k,v=line.decode().split(':',1);headers[k.lower()]=v.strip()
  q.put(json.loads(p.stdout.read(int(headers['content-length']))))
threading.Thread(target=read,daemon=True).start()
def send(obj):
 b=json.dumps(obj).encode();p.stdin.write(('Content-Length: %d\r\n\r\n'%len(b)).encode()+b);p.stdin.flush()
def request(method,params):
 global serial
 serial+=1; ident=serial;send({'jsonrpc':'2.0','id':ident,'method':method,'params':params})
 while True:
  obj=q.get(timeout=90)
  if obj.get('id')==ident and 'method' not in obj:return obj
  if 'id' in obj and 'method' in obj:
   result=[config for _ in obj['params'].get('items',[])] if obj['method']=='workspace/configuration' else None
   send({'jsonrpc':'2.0','id':obj['id'],'result':result})
try:
 print(json.dumps(request('initialize',{'processId':None,'rootUri':(root/'scripts').as_uri(),'capabilities':{'textDocument':{'diagnostic':{}},'workspace':{'configuration':True}},'workspaceFolders':[{'uri':(root/'scripts').as_uri(),'name':'island'}]})),flush=True)
 send({'jsonrpc':'2.0','method':'initialized','params':{}})
 print('Configuration handshake',request('workspace/symbol',{'query':'__r10_handshake__'}),flush=True)
 time.sleep(5)
 files=[str(p.relative_to(root)) for p in sorted((root/'scripts').rglob('*.lua'))]
 files+=['tests/combat/environment_damage.lua','tests/combat/voxel_damage_result.lua','tests/ruins/interaction.lua']
 count=0
 for f in files:
  path=root/f
  send({'jsonrpc':'2.0','method':'textDocument/didOpen','params':{'textDocument':{'uri':path.as_uri(),'languageId':'lua','version':1,'text':path.read_text()}}})
 time.sleep(5)
 for f in files:
  path=root/f
  obj=request('textDocument/diagnostic',{'textDocument':{'uri':path.as_uri()}})
  errors=[i for i in obj.get('result',{}).get('items',[]) if i.get('severity')==1]
  print(f,json.dumps(errors,ensure_ascii=False),flush=True);count+=len(errors)
 print('ERRORS',count);raise SystemExit(bool(count))
finally:
 p.terminate();p.wait(timeout=5)
