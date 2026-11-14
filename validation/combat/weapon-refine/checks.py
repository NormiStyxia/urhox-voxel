"""Reproducible offline gates. Run from project root: checks.py tests|lsp."""
import json
import sys
import urllib.request
from pathlib import Path
from lupa.lua54 import LuaRuntime

if sys.argv[1] == 'tests':
    for path in sorted(Path('tests/combat').glob('weapon_*.lua')):
        if path.name == 'weapon_mock.lua':
            continue
        print('RUN', path, flush=True)
        LuaRuntime(unpack_returned_tuples=True).execute(path.read_text())
    print('PASS six weapon suites')
elif sys.argv[1] == 'lsp':
    files = list(Path('scripts/combat').glob('Weapon*.lua')) + [Path('scripts/ui/ForgePanel.lua')] + list(Path('tests/combat').glob('weapon_*.lua'))
    errors = 0
    for path in sorted(files):
        body = {'method':'textDocument/diagnostic','params':{'severity':1,'textDocument':{'uri':path.absolute().as_uri()}},'page_size':200,'page_max_bytes':200000}
        req = urllib.request.Request('http://127.0.0.1:19547/rpc',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        result = json.load(urllib.request.urlopen(req,timeout=90))
        print(path, json.dumps(result,ensure_ascii=False), flush=True)
        assert result.get('ok'),result
        errors += len(result.get('result',{}).get('items',[]))
    print('ERROR COUNT',errors,'FILES',len(files))
    assert errors == 0
else:
    raise ValueError('expected tests|lsp')
