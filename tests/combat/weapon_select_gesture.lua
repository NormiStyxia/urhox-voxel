local S=dofile('tests/combat/core_support.lua')
local G=require('combat.WeaponSelectGesture')
local A=require('combat.CombatAnim')
local C=require('combat.CombatMoves')
local State=require('combat.CombatState')
local Pointer=require('ruins.PointerCapture')
local TouchInput=require('ui.TouchInput')
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local source=read('scripts/ruins/RuinsScene.lua')
local function chunk(code,env) return assert(load(code,'actual Scene weapon selection callbacks','t',env))() end
local rig={pose='hand',SetActive=function()end,GetStats=function()return {speed=1,draw=.7,attack=10,reach=1}end}
function rig:SetPose(p)self.pose=p end
local character=S.anim.character()
local palm={position=Vector3(.25,-.42,.03),worldPosition=Vector3(1,1,3)}
function character:HandSocket()return palm end
character.bones.body.worldRotation=Quaternion(6,10,0)
local root={worldRotation=Quaternion(0,20,0)}
local wheel={blocked=false,opened=false,selected='bow',forced=0}
function wheel.IsBlocked()return wheel.blocked end
function wheel.Open(o)wheel.options=o;wheel.blocked=true;wheel.opened=true;return true end
function wheel.Close(reason)wheel.opened=false;wheel.options.onClose(reason)end
function wheel.ForceClose(reason)
 wheel.forced=wheel.forced+1
 if wheel.opened then wheel.Close(reason)end
 wheel.blocked=false
end
function wheel.Confirm()if wheel.options.onSelect(wheel.selected)then wheel.Close('confirm')end end
function wheel.Update(dt,anchor)wheel.anchor=anchor end
local releases,requests=0,0
local pointer=Pointer.New{web=true,now=function()return 0 end,focused=function()return true end,
 captured=function()return true end,release=function()releases=releases+1 end,
 request=function()requests=requests+1 end,changed=function()end}
pointer:Resume()
pointer:Confirm()
local TC={cancelCount=0}
function TC.Attach(_,provider,mode,cancel)TC.provider,TC.cancel=provider,cancel end
-- Keep the real Clear/revision and invoke the actual Scene onCancel callback.
function TC.Cancel()TC.cancelCount=TC.cancelCount+1;assert(TC.cancelCount<100,'recursive Cancel');TouchInput.Clear();TC.cancel()end
function TC.CancelActions()TC.Cancel()end
local env=setmetatable({WeaponSelectGesture=G,WeaponWheel=wheel,CombatState=State,combatRig_=rig,
 pointer=pointer,TouchControls=TC,TouchInput=TouchInput,input={focus=true,minimized=false},
 M={ride={mode='free'},ctrl={loco={}},debugOn=false},nomi_={nomi=character,node=root},
 caster_={charging=true,charge=1,castAnim=1},drag={buttons=3},animPreview_={index=0},
 ForgePanel={IsOpen=function()return false end},SettingsMenu={IsBlocked=function()return false end,Attach=function(_,fn)env.settings=fn end},
 HUD={root={}},Spells={SPELLS={}},VoidRewind={Attach=function()end},DebugLog={RegisterProbe=function()end},
 PerformanceHUD={Attach=function()end},CombatHasAggro=function()return false end},{__index=_G})
-- Lua local initializer isn't in scope inside its table literal.
env.SettingsMenu.Attach=function(_,fn)env.settings=fn end
State.Configure{rig=rig,cancel=function(reason)if env.weaponGesture_ and reason~='weapon' then env.weaponGesture_:Interrupt(reason)end;if TC.cancel then TC.CancelActions()end end}
State.Enter();State.FinishTransition();State.Activity(true)
local moves=C.New{anim=A.New(character,nil),rig=rig,state=State,position=function()return Vector3.ZERO end,
 forward=function()return Vector3.FORWARD end,enemies=function()return {}end,
 clear=function(reason)if env.weaponGesture_ then env.weaponGesture_:Interrupt(reason)end end}
env.combatMoves_=moves
chunk(assert(source:match('(local function AttachTouchControls.-)\nend'))..'\nend\nAttachTouchControls()',env)
chunk(assert(source:match('(    weaponGesture_=WeaponSelectGesture.New.-)\n    local tailMaterial')),env)
local gesture=assert(env.weaponGesture_)
local function ResetPose()character.bones.arm_right.rotation=Quaternion();if character.bones.forearm_right then character.bones.forearm_right.rotation=Quaternion()end end
assert(gesture:Open(false) and gesture:IsOpen(),'actual takeInput/Cancel must not self-close')
assert(not pointer.blocked and pointer:IsCaptured() and env.drag.buttons==0)
assert(releases==0 and requests==0 and not pointer:CanAttack(),'selection keeps lock and gates actions without recapture')
assert(not env.caster_.charging and env.caster_.charge==0 and env.caster_.castAnim==0)
TC.Cancel();assert(gesture:IsOpen(),'own TouchControls.Sync takeover must preserve wheel')
for _=1,10 do moves:Update(.02,{allowed=false,selecting=true});ResetPose();gesture:Apply(.02)end
assert(gesture.weight==1 and State.InCombat(),'blocked simulation retains gesture and combat')
local dir=character.bones.body.worldRotation*(character.bones.arm_right.rotation*gesture.grip)
local aim=root.worldRotation*Vector3(.80,.02,.60)
local function norm(v)return Vector3(v.x,v.y,v.z):Normalized()end
assert(norm(dir):DotProduct(norm(aim))>.99999,'actual palm reach is horizontal in world, including torso lean')
local camera={node={worldPosition=Vector3.ZERO,worldDirection=Vector3.FORWARD},WorldToScreenPoint=function(_,p)return {x=.73,y=.41}end}
gesture:Update(.016,camera);assert(wheel.anchor.anchorX==.73 and wheel.anchor.anchorY==.41,'Vector2 projection, no z access')
wheel.selected='bow';gesture:Confirm()
assert(not gesture:IsOpen() and State.GetWeapon()=='bow')
assert(moves.clip=='weapon_swap_sword_to_bow','actual releaseInput/Cancel must not erase confirmed swap')
assert(not pointer.blocked and pointer:IsEnabled(),'pointer resumes after wheel releases it')
assert(releases==0 and requests==0 and pointer:IsCaptured(),'Q release never unlocks or re-requests pointer lock')
assert(gesture.weight==1,'normal close retains pose for smooth release')
ResetPose();gesture:Apply(.06);assert(gesture.weight>0 and gesture.weight<1)
ResetPose();gesture:Apply(.07);assert(gesture.weight==0)
for _=1,30 do moves:Update(.02,{allowed=false})end
assert(not moves.clip and State.TransitionRemaining()==0,'swap advances during closing input latch')
wheel.blocked=false;State.Activity(true);moves:Cancel('test')
assert(gesture:Open(true));wheel.selected='bow';gesture:Confirm()
assert(not moves.clip and State.GetWeapon()=='bow','same weapon confirmation has no swap')
wheel.blocked=false
assert(gesture:Open(false));gesture:Apply(.2)
moves:ApplyHit{dmg=10,dir=Vector3(1,0,0)}
assert(not gesture:IsOpen() and gesture.weight==0 and moves.clip=='hit_light','hit immediately owns pose')
wheel.blocked=false;local calls=wheel.forced;gesture:ForceClose('stop');assert(wheel.forced==calls+1,'inactive close clears stale UI release guard')
-- The first open cannot bypass the authored lock on a strike/hit.
moves:Cancel('test');moves:Play('sword_light_1');assert(not gesture:Open(false) and moves.clip=='sword_light_1')
moves:Cancel('test');moves:Play('hit_light');assert(not gesture:Open(false))
moves:Cancel('test');moves:Play('bow_draw');assert(gesture:Open(false) and moves.charge==0 and not moves.pendingFire,'selection cancels bow charge, never fires')
gesture:ForceClose('test')
-- Existing Swap() toggles; targeted invalid/same selections make no state mutation.
moves:Cancel('test');State.FinishTransition();State.SetBusy(false)
local old=State.GetWeapon();assert(not moves:Swap('future') and State.GetWeapon()==old)
assert(moves:Swap(old) and not moves.clip)
assert(moves:Swap() and State.GetWeapon()~=old)
-- Separate elbow skeleton preserves every pivot/socket position and bends forearm.
local forearm={position=Vector3(.12,-.15,0),rotation=Quaternion()}
character.bones.forearm_right=forearm
local upperPosition=character.bones.arm_right.position
local palmPosition=palm.position
local elbowGesture=G.New{character=character,root=root,wheel=wheel,moves=moves,rig=rig,state=State}
elbowGesture.active=true;ResetPose();elbowGesture:Apply(.2)
assert(math.abs(forearm.rotation.x)>.01)
assert(character.bones.arm_right.position==upperPosition and forearm.position.y==-.15 and palm.position==palmPosition,'gesture never edits rig pivots/socket')
-- Execute the actual focus and action handlers; own blocked flag must not close.
local actions=chunk(assert(source:match('(local function UpdateCombatActions.-)\nend'))..'\nend\nreturn UpdateCombatActions',env)
moves:Cancel('test');State.FinishTransition();moves.invuln=0;env.combatInputBlocked=false;wheel.blocked=false
assert(gesture:Open(false));env.Down=function()return true end;actions(false);assert(gesture:IsOpen(),'wheel own blocker cannot trigger external interruption')
env.Down=function()return false end;wheel.selected=State.GetWeapon();actions(false);assert(not gesture:IsOpen(),'Q release confirms even while UI blocks combatAllowed')
wheel.blocked=false;assert(gesture:Open(false));env.input.focus=false;actions(false);assert(not gesture:IsOpen(),'lost focus interrupts before confirmation')
print('PASS weapon selection: real Scene take/release/onCancel callbacks, pointer restore, Q hold/release, palm projection, smooth pose, hard hit, bow cancellation, lock windows, Swap target and legacy, elbow pivots')
-- Exercise actual UI delayed retirement together with the actual Scene callbacks.
-- Reuse only the colleague's offline UI adapter setup, without changing that file.
local wheelTests=read('tests/combat/weapon_wheel.lua')
local adapter=assert(wheelTests:match('^(.-)\n%-%- Hollow ring geometry'))
local live=chunk(adapter..'\nreturn {wheel=Wheel,reset=Reset,slot=SlotEvent,ui=UI}',_G)
live.reset();gesture.o.wheel=live.wheel;env.WeaponWheel=live.wheel;env.input=input
character.bones.forearm_right=nil
moves:Cancel('test');State.FinishTransition();State.SetBusy(false);State.Activity(true)
assert(gesture:Open(true),'real overlay opens with actual takeInput Cancel')
for _=1,10 do moves:Update(.02,{allowed=false,selecting=true});ResetPose();gesture:Apply(.02);gesture:Update(.02,camera)end
local other=State.GetWeapon()=='sword' and 2 or 1
local event=live.slot(other,7,true)
local overlay=live.ui.GetTopOverlay()
overlay.props.onPointerDown(event);overlay.props.onPointerUp(event)
assert(live.wheel.DebugState().closing and gesture:IsOpen(),'UI retains visible fade before onClose')
local swapClip=moves.clip;assert(swapClip and swapClip:find('weapon_swap_',1,true))
TC.Cancel();assert(moves.clip==swapClip,'own blocker cannot erase accepted swap while retiring')
for _=1,8 do
 moves:Update(.02,{allowed=false,selecting=gesture:IsOpen()});ResetPose();gesture:Apply(.02);gesture:Update(.02,camera)
end
assert(not gesture:IsOpen() and not live.wheel.IsOpen(),'actual delayed onClose restores pointer without recursion')
assert(moves.clip==swapClip and pointer:IsEnabled(),'swap survives actual onClose/releaseInput Cancel')
for _=1,20 do moves:Update(.02,{allowed=false});gesture:Update(.02,camera)end
assert(not moves.clip,'swap ready event remains reachable after real UI closes')
-- Mount/death state owns hidden equipment even when selection started in hand.
live.reset();State.Activity(true);moves:Cancel('test');assert(gesture:Open(false))
State.SetMounted(true)
assert(not gesture:IsOpen() and rig.pose=='hidden' and gesture.weight==0,'mount must not restore a saved hand weapon')
State.SetMounted(false)
print('PASS actual WeaponWheel + Scene callback integration: pointer tap, deferred fade/onClose, blocker takeover, swap ready, mounted hidden pose')
-- New Scene opts use three items without changing the wheel renderer. Exercise
-- the real delayed close in both directions across the old mode boundary.
live.reset();moves:Cancel('test')
State.Configure{rig=rig,explicitSelection=true,aggro=function()return true end,
 cancel=function(reason)
  if env.weaponGesture_ and reason~='weapon' then env.weaponGesture_:Interrupt(reason)end
  if TC.cancel then TC.CancelActions()end
 end}
env.combatInputBlocked=false
env.KEY_Q,env.KEY_C,env.KEY_G='Q','C','G'
local qEdge=true
env.Press=function(key)if key=='Q' and qEdge then qEdge=false;return true end;return false end
env.Down=function(key)return key=='Q' end
actions(true,.016)
assert(gesture.pending and not gesture:IsOpen(),'short press must not open wheel')
actions(true,.12);assert(not gesture:IsOpen())
actions(true,.2)
assert(gesture:IsOpen() and live.wheel.DebugState().selected=='time' and #live.wheel.DebugLayout().slots==3,
 'Q opens the actual three-slot wheel from time mode')
State.OnEnemyAggro('guard');assert(gesture:IsOpen() and State.GetSelection()=='time')
live.wheel.Cancel()
local function drain()
 for _=1,50 do moves:Update(.01,{allowed=false,selecting=gesture:IsOpen()});State.Update(.01);gesture:Update(.01,camera)end
end
drain();assert(State.GetSelection()=='time' and rig.pose=='hidden' and not live.wheel.IsBlocked())
for _,slot in ipairs({1,2,3}) do
 assert(gesture:Open(true))
 local overlay=live.ui.GetTopOverlay()
 local event=live.slot(slot,40+slot,true)
 overlay.props.onPointerDown(event);overlay.props.onPointerUp(event)
 assert(live.wheel.DebugState().closing and gesture:IsOpen(),'selection preserves the visible close')
 drain()
 local expected=({'sword','bow','time'})[slot]
 assert(State.GetSelection()==expected and not gesture:IsOpen() and not live.wheel.IsBlocked())
 assert(not moves.pendingFire and not env.caster_.charging,'selection never inherits a held attack/spell')
 State.Update(20);State.OnEnemyAggro('guard')
 assert(State.GetSelection()==expected,'idle and aggro retain player selection')
end
assert(State.CanUseTime() and rig.pose=='hidden' and pointer:IsEnabled())
print('PASS real Scene + three-slot wheel: explore Q, cancel, sword/bow/time, deferred close, aggro/idle, input restoration')
-- Execute the actual relative-camera routing, including the first Q-down frame
-- before the wheel is constructed, and the invisible release-guard frame.
local cameraBlock=assert(source:match('(    if not WeaponWheel.IsBlocked%(%) and not Down%(KEY_Q%).-)\n    %-%- 龙'))
local lookCalls,held,blocked,combat=0,false,false,true
local ce=setmetatable({WeaponWheel={IsBlocked=function()return blocked end},
 CombatState={InCombat=function()return combat end},Down=function()return held end,
 TouchInput={IsEnabled=function()return false end},pointer={CanLook=function()return true end},
 mouseLocked=true,input={mouseMove={x=15,y=-5}},animPreview_={index=0},combatLookScale_=1,
 nomi_={Look=function()lookCalls=lookCalls+1 end}}, {__index=_G})
local route=assert(load(cameraBlock,'actual wheel camera gate','t',ce))
held=true;route();assert(lookCalls==0,'first Q-down cannot rotate camera')
held=false;blocked=true;route();assert(lookCalls==0,'selection/closing/release guard freeze camera')
blocked=false;route();assert(lookCalls==1,'normal camera resumes')
held=true;combat=false;route();assert(lookCalls==1,'exploration Q also owns the first camera frame')
held=false;route();assert(lookCalls==2,'exploration camera resumes on release')
print('PASS actual camera gate: first Q frame, selection/fade/release latch, normal and exploration restoration')
-- Tap cycle uses actual SelectLoadout, Scene cleanup and animation completion.
live.reset();moves:Cancel('test');State.FinishTransition();State.SetBusy(false)
local function tap()
 env.combatInputBlocked=false
 qEdge=true;env.Down=function(key)return key=='Q'end
 actions(true,.016);assert(gesture.pending and not gesture:IsOpen())
 env.Down=function()return false end
 actions(true,.05);assert(not gesture.pending and not gesture:IsOpen())
 assert(not live.wheel.IsBlocked(),'tap creates no overlay/release guard')
end
for _,expected in ipairs({'sword','bow','time','sword'}) do
 tap();assert(State.GetSelection()==expected,'tap order sword bow time')
 if expected=='bow' then assert(moves.clip=='weapon_swap_sword_to_bow','quick swap survives cleanup') end
 drain()
 assert(pointer:IsEnabled() and not moves.pendingFire and not env.caster_.charging)
end
for _,reason in ipairs({'hit','mount','focus','settings','stop'}) do
 assert(gesture:BeginPress());gesture:Interrupt(reason)
 gesture:UpdatePress(.05,false,true);assert(State.GetSelection()=='sword' and not gesture.pending)
end
assert(gesture:BeginPress());gesture:UpdatePress(.05,false,false)
assert(State.GetSelection()=='sword' and not gesture.pending,'unavailable input cancels tap')
moves:Play('sword_light_1');assert(not gesture:BeginPress(),'active strike cannot queue a tap');moves:Cancel('test')
assert(gesture:BeginPress());gesture:UpdatePress(.3,false,true)
assert(not gesture:IsOpen() and State.GetSelection()=='sword','slow release of long hold never cycles')
assert(gesture:BeginPress());gesture:UpdatePress(.31,true,true)
assert(gesture:IsOpen() and not gesture.pending);live.wheel.Cancel();drain()
gesture:UpdatePress(.01,false,true);assert(State.GetSelection()=='sword','long hold never also cycles')
print('PASS quick Q cycle, real cleanup and swap animation, cancelled pending, held threshold, no double-switch')
