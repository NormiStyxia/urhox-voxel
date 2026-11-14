import json, pathlib, urllib.request
paths=['scripts/ruins/SkyAtmosphere.lua','scripts/ruins/LightQuality.lua','scripts/ruins/DayNight.lua','scripts/ruins/RuinsTerrain.lua','scripts/ruins/GameSettings.lua', 'scripts/ruins/DebugLog.lua', 'scripts/ruins/SceneQuality.lua', 'scripts/ui/SettingsMenu.lua', 'scripts/ui/PerformanceHUD.lua', 'scripts/ui/TouchControls.lua', 'scripts/ruins/RuinsScene.lua', 'scripts/ruins/NomiController.lua', 'scripts/ruins/TimeObject.lua', 'scripts/ruins_main.lua']
errors=0
for f in paths:
    request=urllib.request.Request('http://127.0.0.1:19561/rpc',data=json.dumps({'method':'textDocument/diagnostic','params':{'severity':1,'textDocument':{'uri':pathlib.Path(f).resolve().as_uri()}},'page_size':100,'page_max_bytes':120000}).encode(),headers={'Content-Type':'application/json'})
    obj=json.load(urllib.request.urlopen(request,timeout=40))
    print(f,json.dumps(obj,ensure_ascii=False))
    assert obj.get('ok'), obj
    errors+=sum(item.get('severity')==1 for item in obj.get('result',{}).get('items',[]))

print("Error count:",errors)
raise SystemExit(1 if errors else 0)
