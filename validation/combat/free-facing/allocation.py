from lupa.lua54 import LuaRuntime
for case in ['pc','touch','boss','range']:
    lua=LuaRuntime()
    lua.globals().UI_CASE=case
    lua.execute("dofile('tests/combat/core_ui_alloc.lua')")
