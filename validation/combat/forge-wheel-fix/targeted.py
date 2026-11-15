from lupa.lua54 import LuaRuntime
for case in ['pc', 'touch', 'boss', 'range']:
    lua = LuaRuntime()
    lua.globals().UI_CASE = case
    lua.execute("dofile('tests/combat/core_ui_alloc.lua')")
for test in ['weapon_wheel', 'weapon_select_gesture', 'core_touch']:
    LuaRuntime().execute("dofile('tests/combat/" + test + ".lua')")
print('PASS targeted HUD phases, dual signals, exact-source binding, relative selection, Scene camera and pointer gates, touch')
