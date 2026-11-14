import json,pathlib,urllib.request,os
paths=['SkyClouds','SkyAtmosphere','GameSettings']
port=os.environ.get('SKY_LSP_PORT','19552')
errors=0
for name in paths:
 p=pathlib.Path('scripts/ruins/'+name+'.lua').resolve()
 req=urllib.request.Request('http://127.0.0.1:'+port+'/rpc',data=json.dumps({'method':'textDocument/diagnostic','params':{'severity':2,'textDocument':{'uri':p.as_uri()}},'page_size':100,'page_max_bytes':120000}).encode(),headers={'Content-Type':'application/json'})
 obj=json.load(urllib.request.urlopen(req,timeout=40)); print(name,json.dumps(obj,ensure_ascii=False)); assert obj.get('ok'),obj
 errors+=sum(i.get('severity')==1 for i in obj.get('result',{}).get('items',[]))
print('Error count:',errors)
raise SystemExit(bool(errors))
