-- New five-role acceptance. PENDING is used for mechanics that are not present
-- yet; PASS only when the real code path is exercised. Old named attacks are
-- covered by actor_integration.lua, which skips stale names.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local H=require('combat.actor_roles_support')
local T=H.T
local S=require('combat.enemies.EnemyBase').State
local function pose() return {x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1} end
local function force(e,idx,target)
    local a=e.config.attacks[idx]
    if not a then return nil end
    e:SetActive(true); e.aggro=true; e.attackIndex=idx-1; e.attack=a; e:Face(target)
    e:SetState(S.TELEGRAPH)
    T.Tick(e,a.telegraph-.02,target); T.Tick(e,.04,target)
    return a
end
local function bodyShape(e)
    for _,h in ipairs(e:GetHurtShapes()) do if h.id=='body' then return h end end
end

-- ---------------------------------------------------------------- 1 WoodSpirit: ground melee
local e,mod,combat=H.newLogic('WoodSpirit')
if e then
    local cfg=mod.Config
    H.check(cfg.ranged~=true and cfg.flight==nil and cfg.fly==nil,'WoodSpirit must stay ground melee')
    H.check(cfg.height<=2.0,'WoodSpirit height is not ground-scale')
    H.check(#cfg.attacks>=2,'WoodSpirit needs normal + pounce')
    for i,a in ipairs(cfg.attacks) do
        H.check(a.warning~='ring','WoodSpirit attack '..i..' should not be an aerial/ring move')
        H.check(a.range<=5.0,'WoodSpirit attack '..i..' range is not melee')
    end
    e:SetActive(true); T.Tick(e,1.0,Vector3(0,0,2))
    H.check(e.position.y==0,'WoodSpirit left the ground while idle/chasing')
    local a=force(e,1,Vector3(0,0,1.2))
    H.check(a~=nil and e.position.y==0,'WoodSpirit left the ground during a ground attack')
    print('PASS WoodSpirit ground melee: y=0, two melee moves')
    e:Destroy()
end

-- ---------------------------------------------------------------- 2 NestWeaver: flight + wing flap + air hit
e,mod,combat=H.newLogic('NestWeaver')
if e then
    local cfg=mod.Config
    local alt=e.position.y-(e.floorY or 0)
    H.check(alt>=1.2,'NestWeaver root is not airborne (alt '..tostring(alt)..')')
    e:SetActive(true); T.Tick(e,.1,Vector3(0,0,3))
    local sh=bodyShape(e)
    H.check(sh and sh.center.y>(e.floorY or 0)+1.0,'NestWeaver airborne body hurt shape is not elevated')
    local p1,p2=pose(),pose()
    e.poseAge=.1; mod.Config.posePart(e,'wing_r',p1)
    e.poseAge=.28; mod.Config.posePart(e,'wing_r',p2)
    H.check(p1.roll~=p2.roll or p1.pitch~=p2.pitch or p1.yaw~=p2.yaw,'NestWeaver wing pose does not flap')
    local hit=e:ApplyHit({dmg=1,part='body',kind='arrow',dir=Vector3(0,0,-1)})
    H.check(hit.hit,'NestWeaver cannot be hit by an arrow while airborne')
    H.check(e.thread~=nil,'NestWeaver silk 3D thread missing')
    print(string.format('PASS NestWeaver flight: root alt %.2fm, wing beat, airborne body arrow hit',alt))
    -- death/cleanup drops the flyer and hides the thread
    e:SetActive(true); e:ApplyHit({dmg=99999,part='body',kind='arrow'})
    T.Tick(e,1.3,Vector3(0,0,3))
    H.check(e.deathFinished,'NestWeaver death did not finish')
    H.check(not e.thread.active and (not e.thread.node or not e.thread.node.enabled),'NestWeaver thread not cleared on death')
    H.check(e.position.y<=(e.floorY or 0)+.25,'NestWeaver did not fall back to the ground on death')
    e:Destroy()
end

-- ---------------------------------------------------------------- 3 RockColossus: size, parts, HP, sequential fault pillars
e,mod,combat=H.newVisual('RockColossus')
if e then
    local cfg=mod.Config
    H.check(cfg.height>=2.6,'RockColossus height below colossus scale: '..tostring(cfg.height))
    H.check(cfg.radius>=.8,'RockColossus footprint below colossus scale: '..tostring(cfg.radius))
    H.check(cfg.hp>=100,'RockColossus HP is not elite-scale: '..tostring(cfg.hp))
    local specs=cfg.parts or {}
    H.check(#specs>=4,'RockColossus needs real multiple hurt parts')
    local centers={}
    for _,spec in ipairs(specs) do
        e:Reset(); e:SetActive(true)
        local before=e.hp
        local r=e:ApplyHit({dmg=1,part=spec.id,kind='arrow',dir=Vector3(0,0,-1)})
        H.check(r.hit and e.hp<before,'RockColossus arrow part '..spec.id..' did not damage')
        local h
        for _,x in ipairs(e:GetHurtShapes()) do if x.id==spec.id then h=x end end
        H.check(h and h.radius>0,'RockColossus part '..spec.id..' has no hurt shape')
        if h then centers[#centers+1]=h.center end
    end
    H.check(#centers>=4,'RockColossus parts collapsed into fewer hurt centers')
    -- Real per-part arrow scaling: armor .55x, crystal 1.85x weak.
    e:Reset(); e:SetActive(true); local before=e.hp
    e:ApplyHit({dmg=10,part='fist_r',kind='arrow',dir=Vector3(0,0,-1)})
    H.check(math.abs((before-e.hp)-5.5)<1e-6,'RockColossus armored fist arrow scale is not 0.55x')
    e:Reset(); e:SetActive(true); before=e.hp
    local weak=e:ApplyHit({dmg=10,part='crystal',kind='arrow',dir=Vector3(0,0,-1)})
    H.check(weak.hit and weak.weak and math.abs((before-e.hp)-18.5)<1e-6,'RockColossus crystal weak arrow scale is not 1.85x')
    print(string.format('PASS RockColossus size/parts/HP: height=%.2f radius=%.2f hp=%d parts=%d armor=.55x crystal=1.85x',cfg.height,cfg.radius,cfg.hp,#specs))

    local slam
    for _,a in ipairs(cfg.attacks) do if a.name=='quarry_slam' or a.warning~='fan' and a.range>=4 then slam=a end end
    H.check(slam~=nil,'RockColossus fault/slam attack missing')
    if slam and e.fault then
        local far=Vector3(0,0,8)
        e:Reset(); e:SetActive(true); e.aggro=true; e.attack=slam; e.attackIndex=2; e:Face(Vector3(0,0,1)); e:SetState(S.TELEGRAPH)
        T.Tick(e,slam.telegraph*.8,far)
        H.check(e.fault.active,'RockColossus fault did not lock')
        H.check(e.warning.kind=='fault_strip','RockColossus ground marker is not a fault strip')
        local sections=e.fault.sections
        H.check(#sections==5,'RockColossus fault sections '..#sections..' (expected 5)')
        for i,s in ipairs(sections) do
            H.check(s.warn and s.valid,'RockColossus fault section '..i..' not warned/valid')
            if s.marker then H.check(s.marker.enabled,'RockColossus red footprint '..i..' hidden') end
        end
        local seen={}; local order={}
        for _=1,40 do
            T.Tick(e,.05,far)
            for i,s in ipairs(sections) do
                if s.erupted and not seen[i] then seen[i]=true; order[#order+1]=i end
            end
        end
        H.check(#order==5,'RockColossus fault eruption count '..#order..' (expected 5)')
        for i=1,5 do H.check(order[i]==i,'RockColossus fault order at '..i..'='..tostring(order[i])) end
        e:Stagger(1.5,false)
        H.check(not e.fault.active,'RockColossus fault stayed active after freeze')
        e:SetActive(false); e:SetActive(true)
        H.check(not e.fault.active,'RockColossus fault stayed active after switch')
        print('PASS RockColossus five sequential red fault pillars + freeze/switch cleanup')
        -- One real contact on the third footprint; geometry is the same authored box.
        e:Reset(); e:SetActive(true); e.aggro=true; e.attack=slam; e.attackIndex=2; e:Face(Vector3(0,0,1)); e:SetState(S.TELEGRAPH)
        T.Tick(e,slam.telegraph*.8,far)
        local s3=e.fault.sections[3]; local spot=Vector3(s3.x,0,s3.z)
        for _=1,20 do T.Tick(e,.05,spot) end
        H.check(combat.hits>=1,'RockColossus fault footprint did not damage a player at its centre')
        e:ApplyHit({dmg=99999,part='torso',kind='arrow',dir=Vector3(0,0,-1)}); T.Tick(e,1.3,Vector3(0,0,1))
        H.check(not e.fault.active and not e.fault.root.enabled,'RockColossus fault stayed alive after death')
    else
        H.pending('RockColossus sequential fault pillars unavailable')
    end
    e:Destroy()
end

-- ---------------------------------------------------------------- 4 RuinConstruct: thick circle beam + timed weak core
e,mod,combat=H.newVisual('RuinConstruct')
if e then
    local cfg=mod.Config
    local beam
    for _,a in ipairs(cfg.attacks) do if a.name=='locked_beam' or a.name:find('beam') then beam=a end end
    H.check(beam~=nil and beam.name=='locked_beam','RuinConstruct locked beam missing')
    if not beam then H.pending('RuinConstruct beam missing') else
        H.check(e.optics~=nil and e.optics.radius>=.25,'RuinConstruct thick optics/beam not present')
        if e.optics then
            H.check(#e.optics.rings>=1 and #e.optics.root.children>=6,'RuinConstruct magic circle layers incomplete')
        end
        local target=Vector3(0,0,1.6)
        e:SetActive(true); e.aggro=true; e.attackIndex=1; e.attack=beam; e:Face(target); e:SetState(S.TELEGRAPH)
        T.Tick(e,beam.telegraph-.02,target)
        H.check(e.beamOrigin~=nil and e.beamLength>0,'RuinConstruct beam did not lock/trace')
        if e.optics then H.check(e.optics.root.enabled,'RuinConstruct circle/beam root not visible on telegraph') end
        T.Tick(e,.04,target); T.Tick(e,.10,target)
        H.check(combat.hits==1,'RuinConstruct beam did not hit on its visible line')
        -- Same locked beam, target one radius outside: must miss.
        local off=Vector3(1.0,0,1.6); local aim=Vector3(0,0,1.6); combat.hits=0; e:Reset(); e:SetActive(true); e.aggro=true; e.attack=beam; e.attackIndex=1; e:Face(aim); e:SetState(S.TELEGRAPH)
        T.Tick(e,beam.telegraph-.02,aim); T.Tick(e,.04,off); T.Tick(e,.10,off)
        H.check(combat.hits==0,'RuinConstruct off-line target took beam damage (geometry mismatch)')
        e:Reset(); e:SetActive(true); e.aggro=true; e.attack=beam; e.attackIndex=1; e:Face(target); e:SetState(S.TELEGRAPH)
        T.Tick(e,beam.telegraph-.02,target); T.Tick(e,.04,target)
        T.Tick(e,beam.duration,target)
        H.check(e.state==S.RECOVER and e.venting,'RuinConstruct did not enter timed vent/recover')
        T.Tick(e,.20,Vector3(0,0,1.6))
        local coreOpen=e:PartEnabled({id='core'})
        H.check(coreOpen,'RuinConstruct weak core did not open after the beam')
        local before=e.hp
        local r=e:ApplyHit({dmg=1,part='core',kind='arrow',dir=Vector3(0,0,-1)})
        H.check(r.hit and r.weak and e.hp<before,'RuinConstruct opened core did not take weak arrow damage')
        T.Tick(e,beam.recover,Vector3(0,0,1.6))
        H.check(not e:PartEnabled({id='core'}),'RuinConstruct core stayed open past its window')
        -- freeze/switch clears optics, beam and weak window
        e:SetActive(true); e.attack=beam; e.attackIndex=1; e:Face(target); e:SetState(S.TELEGRAPH)
        T.Tick(e,beam.telegraph-.02,target); T.Tick(e,.04,target)
        e:Stagger(1.5,false)
        H.check(not e:PartEnabled({id='core'}) and e.beamOrigin==nil,'RuinConstruct freeze did not close beam/core')
        if e.optics then H.check(not e.optics.root.enabled,'RuinConstruct optics stayed visible after freeze') end
        e:SetActive(false); e:SetActive(true)
        H.check(e.beamOrigin==nil,'RuinConstruct switch left beam state dirty')
        e:ApplyHit({dmg=99999,part='torso',kind='arrow',dir=Vector3(0,0,-1)}); T.Tick(e,1.3,target)
        H.check(e.beamOrigin==nil and (not e.optics or not e.optics.root.enabled),'RuinConstruct beam/optics stayed after death')
        print('PASS RuinConstruct thick beam/circle, same warning-hit line, timed weak core, freeze/switch/death cleanup')
    end
    e:Destroy()
end

-- ---------------------------------------------------------------- 5 TimeWraith: field scale inside/outside + recovery/cleanup
e,mod,combat=H.newVisual('TimeWraith')
if e then
    local fieldOk,Field=pcall(require,'combat.enemies.actors.TimeWraithField')
    H.check(fieldOk,'TimeWraithField module missing')
    local domain
    for _,a in ipairs(e.config.attacks) do if a.name=='hourglass_field' or a.warning=='ring' and a.range==Field.radius then domain=a end end
    H.check(domain~=nil and type(e.GetPlayerTimeScale)=='function','TimeWraith domain attack/scale API missing')
    if domain and type(e.GetPlayerTimeScale)=='function' then
        local player=Vector3(0,0,2)
        e:Reset(); e:SetActive(true); e.aggro=true; e.attack=domain; e.attackIndex=2; e:Face(player); e:SetState(S.TELEGRAPH)
        T.Tick(e,Field.warning,player)
        H.check(e.fieldStage=='active','TimeWraith field did not activate at its warning end')
        if e.fieldFx then
            H.check(e.fieldFx.root.enabled and #e.fieldFx.root.children>=6,'TimeWraith field visual layers missing')
        end
        local c=e.fieldCenter
        local inside=e:GetPlayerTimeScale(Vector3(c.x,c.y,c.z))
        local outside=e:GetPlayerTimeScale(Vector3(c.x+Field.radius+1,c.y,c.z))
        H.check(inside==.5,'TimeWraith inside-field scale '..tostring(inside)..' (expected .5)')
        H.check(outside==1,'TimeWraith outside-field scale '..tostring(outside)..' (expected 1)')
        H.check(e:GetPlayerTimeScale(nil)==1,'TimeWraith nil-feet scale must be 1')
        T.Tick(e,Field.duration,player)
        H.check(e.fieldStage=='release','TimeWraith field did not enter release')
        T.Tick(e,Field.release,player)
        H.check(not e.fieldStage and e:GetPlayerTimeScale(Vector3(c.x,c.y,c.z))==1,'TimeWraith field did not recover/clear')
        print(string.format('PASS TimeWraith field: inside .5 / outside 1 / recovery 1 (radius %.1f, %.1fs)',Field.radius,Field.duration))
        -- freeze/switch cleanup
        e:SetActive(true); e.attack=domain; e.attackIndex=2; e:Face(player); e:SetState(S.TELEGRAPH); T.Tick(e,Field.warning,player)
        e:Stagger(1.5,false)
        H.check(not e.fieldStage and e:GetPlayerTimeScale(Vector3(c.x,c.y,c.z))==1,'TimeWraith freeze left field scale active')
        if e.fieldFx then H.check(not e.fieldFx.root.enabled,'TimeWraith field visual stayed visible after freeze') end
        e:SetActive(false); e:SetActive(true)
        H.check(not e.fieldStage,'TimeWraith switch left field state dirty')
        e:ApplyHit({dmg=99999,part='mantle',kind='arrow',dir=Vector3(0,0,-1)}); T.Tick(e,1.3,player)
        H.check(not e.fieldStage and (not e.fieldFx or not e.fieldFx.root.enabled),'TimeWraith field stayed after death')
        local function read(path)
            local f=io.open(path,'r'); if not f then return '' end
            local src=f:read('*a'); f:close(); return src
        end
        local sceneSrc=read('scripts/ruins/RuinsScene.lua')
        local nomiSrc=read('scripts/ruins/NomiController.lua')
        local movesSrc=read('scripts/combat/CombatMoves.lua')
        H.check(sceneSrc:find('GetPlayerTimeScale',1,true)~=nil,'RuinsScene has no field scale consumer')
        H.check(sceneSrc:find('SetPlayerTimeScale(playerTimeScale,dt)',1,true)~=nil,'RuinsScene does not feed the scale to Nomi')
        H.check(nomiSrc:find('gravityFactor=self.baseGravityFactor*scale',1,true)~=nil,'Nomi fall gravity does not consume field scale')
        H.check(nomiSrc:find('self.playerTimeScale',1,true)~=nil,'Nomi run speed does not consume field scale')
        H.check(nomiSrc:find('*(combat.scale or 1)*(self.playerTimeScale or 1)',1,true)~=nil,'Nomi run-speed multiplier does not include playerTimeScale')
        H.check(movesSrc:find('animDt=animDt*playerTimeScale',1,true)~=nil,'Combat attack clock does not consume field scale')
        H.check(movesSrc:find('drawElapsed=self.drawElapsed+dt*playerTimeScale',1,true)~=nil,'Bow draw clock does not consume field scale')
        local i=nomiSrc:find('function N:SetPlayerTimeScale',1,true)
        local j=i and nomiSrc:find('-- 右手掌心',i,true)
        if i and j then
            local body=nomiSrc:sub(i,j-1)
            local env={math=math,tonumber=tonumber,type=type,Vector3=Vector3,N={}}
            local chunk=load(body,'NomiScale','t',env)
            H.check(chunk~=nil,'Nomi SetPlayerTimeScale extraction failed')
            if chunk then
                chunk()
                local fake={baseGravityFactor=2,playerTimeScale=1,timeSlowGravityDebt=0,
                    cc={gravityFactor=2,onGround=false,
                        GetLinearVelocity=function() return Vector3(0,-5,0) end,
                        SetLinearVelocity=function(self,v) self.velocity=v end}}
                env.N.SetPlayerTimeScale(fake,.5,.016)
                H.check(math.abs(fake.cc.gravityFactor-1)<1e-6,'Nomi gravity did not halve inside field')
                H.check(fake.timeSlowGravityDebt>0,'Nomi exit debt was not accumulated')
                fake.cc.onGround=true; env.N.SetPlayerTimeScale(fake,1,.016)
                H.check(math.abs(fake.cc.gravityFactor-2)<1e-6,'Nomi gravity did not restore on exit')
                H.check(fake.timeSlowGravityDebt==0,'Nomi gravity debt did not clear on ground')
            end
        end
        print('PASS TimeWraith field wiring: actor scale .5/1 -> Nomi gravity/run and CombatMoves anim/draw clocks (source-verified)')
    else H.pending('TimeWraith domain actor integration missing') end
    e:Destroy()
end

-- ---------------------------------------------------------------- generic cleanup, visibility, budget
for _,name in ipairs({'WoodSpirit','NestWeaver','RockColossus','RuinConstruct','TimeWraith'}) do
    local ev,m,cv,w=H.newVisual(name)
    if ev then
        local mn,data=H.modelFor(m)
        local cells=0; local set={}
        for _,part in ipairs(data.parts) do
            for _,cell in ipairs(part.cells) do
                local k=cell[1]..','..cell[2]..','..cell[3]
                H.check(not set[k],name..' duplicate model cell '..k)
                set[k]=true; cells=cells+1
            end
        end
        H.check(cells<=3000,name..' model cells over budget: '..cells)
        H.check(#data.parts<=24,name..' model part count over budget: '..#data.parts)
        H.check(#data.palette<=6,name..' palette over six colours')
        H.check(ev.visual and ev.visual.root and #(ev.visual.parts or {})>0,name..' model visual not wired')
        ev:SetActive(true); ev.aggro=true
        local a=ev.config.attacks[1]
        ev.attack=a; ev.attackIndex=0; ev:Face(Vector3(0,0,1)); ev:SetState(S.TELEGRAPH)
        T.Tick(ev,a.telegraph*.5,Vector3(0,0,1))
        H.check(ev.warning.visible,name..' warning invisible at telegraph')
        ev:SetActive(false); ev:SetActive(true)
        H.check(not ev.warning.visible,name..' warning survived switch-off/on')
        if ev.thread then H.check(not ev.thread.active and (not ev.thread.node or not ev.thread.node.enabled),name..' thread dirty after switch') end
        if ev.optics then H.check(not ev.optics.root.enabled,name..' optics dirty after switch') end
        if ev.fault then H.check(not ev.fault.active,name..' fault dirty after switch') end
        if ev.fieldFx then H.check(not ev.fieldFx.root.enabled,name..' field dirty after switch') end
        H.check(w.created==w.rebuilt,name..' model rebuild count diverged at init')
        print(string.format('PASS %-13s budget/visibility: cells=%d parts=%d palette=%d',name,cells,#data.parts,#data.palette))
        ev:Destroy()
    end
end

H.finish('five role assertions')
