local S=dofile('tests/combat/core_support.lua')
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local noop=function()end
local keys,pressed={},{}
for _,name in ipairs({'F7','RIGHTBRACKET','RIGHT','LEFTBRACKET','LEFT','SPACE','1','2','3','4','O','P','I','K','J','L','B','EQUALS','PLUS','KP_PLUS','MINUS','KP_MINUS','COMMA','PERIOD','E','Q'})do keys['KEY_'..name]=name end
local inCombat=false
local says,charges,casts=0,0,{}
local casterLastDown
local controls={Cancel=noop,IsBlocked=function()return false end}
local touch={IsEnabled=function()return false end,Down=function()return false end,Press=function()return false end}
local caster={charging=true,charge=.5,Say=function()says=says+1 end,
 HandleCharge=function(_,down)charges=charges+1;casterLastDown=down end,Cast=function(_,id)casts[#casts+1]=id end}
local list={{id='stance_combat',dur=1}}
local env=setmetatable({animPreview_={index=0,params={p=.5},direction='后'},
 CombatAnim={DebugList=function()return list end},
 CombatState={Enter=function()inCombat=true end,Exit=function()inCombat=false end,SetBusy=noop,GetWeapon=function()return 'sword'end,
  CanUseTime=function()return not inCombat end,InCombat=function()return inCombat end},
 combatMoves_={Cancel=noop},combatArrows_={Clear=noop},combatRig_={SetActive=noop,SetPose=noop},
 combatAnim_={Play=noop,SetParam=noop,Update=noop,Stop=noop,Poll=function()return {}end},
 CombatMoves={PreviewPhase=function()return 'recovery'end,PreviewEvents=function()return '—'end},
 TouchControls=controls,TouchInput=touch,PlatformUtils={IsMobilePlatform=function()return false end},
 Press=function(k)return pressed[k]==true end,Down=function(k)return pressed[k]==true end,
 Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,nomi_={camPitch=12},M={},caster_=caster,
 time_=10,combatNoticeAt=0,pointer={IsEnabled=function()return true end,CanAttack=function()return false end},
 input={GetMouseButtonDown=function()return false end}}, {__index=function(_,k)return keys[k]or _G[k]end})
local preview=assert(load(assert(source:match('(local function UpdateCombatPreview.-)\nlocal function UpdateCombatActions'))..'\nreturn UpdateCombatPreview','actual preview routing','t',env))()
local spells=assert(load(assert(source:match('(local function HandleSpells.-)\nfunction Ruins_HandleSceneUpdate'))..'\nreturn HandleSpells','actual spell routing','t',env))()
pressed.F7=true;preview(.016,true);pressed.F7=nil
assert(env.animPreview_.index==1 and inCombat)
for _,key in ipairs({'1','2','3','E','Q'})do
 pressed[key]=true;spells(.016,{});pressed[key]=nil
end
assert(says==0 and charges==0 and #casts==0 and not caster.charging and caster.charge==0,'preview exclusively owns shortcuts')
pressed.F7=true;preview(.016,true);pressed.F7=nil
assert(env.animPreview_.index==0 and not inCombat and env.combatInputBlocked,'exit waits for held preview keys')
pressed['2']=true;spells(.016,{});assert(#casts==0,'exit cannot immediately freeze via held preview key')
pressed['2']=nil
-- Execute Scene existing release gate, rather than handwaving its restoration.
local updateBody=assert(source:match('function Ruins_HandleUpdate.-$'))
local gate=assert(updateBody:match('(    if combatInputBlocked then.-)\n    if VoidRewind'))
local gateEnv=env;env.input.GetMouseButtonDown=function()return false end
assert(load(gate,'actual input release gate','t',gateEnv))()
assert(not env.combatInputBlocked)
for _,k in ipairs({'1','2','3'})do pressed[k]=true;spells(.016,{});pressed[k]=nil end
assert(charges==3 and casts[1]=='freeze' and casts[2]=='rewind','normal puzzle shortcuts restore')
touch.IsEnabled=function()return true end
touch.Down=function(k)return k=='shatter'end
spells(.016,{});assert(casterLastDown==true,'touch puzzle charge unaffected after exit')
assert(source:find('hud.preview=animPreview_.index>0',1,true),'Scene forwards only current F7 state, not stale debug text')
print('PASS actual F7 enter/exit, number/E/Q exclusive routing, held-key exit guard, normal keyboard/touch puzzle restore')
