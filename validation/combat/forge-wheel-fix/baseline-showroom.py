import subprocess
from lupa.lua54 import LuaRuntime
lua = LuaRuntime()
sources = {}
for name in ['ForgeShowroom', 'ForgeShowroomScene']:
    sources['combat.' + name] = subprocess.check_output(
        ['git', 'show', 'HEAD:scripts/combat/' + name + '.lua'], text=True)
lua.globals().baseline_sources = lua.table_from(sources)
lua.globals().baseline_test = subprocess.check_output(
    ['git', 'show', 'HEAD:tests/combat/forge_showroom.lua'], text=True)
lua.execute('''
for name, source in pairs(baseline_sources) do
    package.preload[name] = function(...)
        return assert(load(source, '@HEAD/'..name))(... )
    end
end
assert(load(baseline_test, '@HEAD/tests/combat/forge_showroom.lua'))()
''')
print('PASS committed showroom test and module sources; concurrent working-tree files not modified')
