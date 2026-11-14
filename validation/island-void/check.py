from pathlib import Path
import sys
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[2]
lua=LuaRuntime(unpack_returned_tuples=True)
for p in root.joinpath('scripts').rglob('*.lua'):
    lua.execute('assert(load(...))',p.read_text())
print('PASS Lua5.4 syntax: all scripts')
lua.execute("package.path='scripts/?.lua;'..package.path")
lua.execute(Path('validation/island-void/check.lua').read_text())
