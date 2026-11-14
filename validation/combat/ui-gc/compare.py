from lupa.lua54 import LuaRuntime
for label,base in [('before','validation/combat/ui-gc/before'),('after',None)]:
 for case in ['touch','pc','boss']:
  print(label,case,flush=True)
  vm=LuaRuntime();vm.globals().UI_BASELINE=base;vm.globals().UI_CASE=case
  vm.execute("dofile('tests/combat/core_ui_alloc.lua')")
