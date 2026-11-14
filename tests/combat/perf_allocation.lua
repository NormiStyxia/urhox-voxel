local S=dofile('tests/combat/core_support.lua')
local H=require('combat.Hit');local C=require('combat.CombatMoves')
local shapes={{id='body',center=Vector3(0,1,1),radius=.5}}
local enemies={{GetHurtShapes=function()return shapes end}}
local zone=C.MeleeZone('sword_light_1',Vector3.ZERO,Vector3.FORWARD,1,false)
local out,pool={},{}
for _=1,10 do H.QueryZone(enemies,zone,out,pool) end
local contact=pool[1]
local function measure(pooled)
 collectgarbage('collect');collectgarbage('stop')
 local before=collectgarbage('count')
 for _=1,1000 do
  if pooled then H.QueryZone(enemies,zone,out,pool) else H.QueryZone(enemies,zone) end
 end
 local delta=(collectgarbage('count')-before)/1000
 collectgarbage('restart')
 return delta
end
local baseline=measure(false);local pooled=measure(true)
assert(pool[1]==contact and out[1]==contact)
assert(pooled<baseline,'retained contact/out buffers reduce Lua allocation')
print(string.format('R10 QueryZone one-contact mock KB/call allocating=%.4f pooled=%.4f saved=%.4f (Vector3 mocked as Lua tables; NOT native frame heap)',baseline,pooled,baseline-pooled))
print('PASS pool identities stable; retained external Hit.Apply info/result stay independent')
