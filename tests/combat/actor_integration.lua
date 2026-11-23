-- Independent acceptance for the five model-driven enemy actors.
-- Pure Lua 5.4: no Runtime, Spawner edit, remote build or physics finalize.
package.path='scripts/?.lua;tests/?.lua;'..package.path

local T=require('combat.enemy_support')
local Names={'WoodSpirit','NestWeaver','RockColossus','RuinConstruct','TimeWraith'}
local failures={}
local function fail(msg) failures[#failures+1]=msg; print('FAIL '..msg) end
local function check(ok,msg) if not ok then fail(msg); return false end return true end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function pcallCheck(msg,fn)
    local ok,a,b=pcall(fn)
    if not ok then fail(msg..': '..tostring(a)); return nil end
    return a,b
end

-- ---------------------------------------------------------------- mock visual world
local nodeMethods={}
local createdVolumes,rebuiltVolumes=0,0
local function node(name)
    return setmetatable({name=name,position=Vector3.ZERO,scale=Vector3(1,1,1),
        rotation=Quaternion(),children={},enabled=true}, {__index=nodeMethods})
end
function nodeMethods:CreateChild(name)
    local child=node(name); self.children[#self.children+1]=child; return child
end
function nodeMethods:SetParent(parent) self.parent=parent end
function nodeMethods:SetScale(scale) self.scale=scale end
function nodeMethods:LookAt(point) self.lookAt=point end
function nodeMethods:Remove()
    if self.removed then error('double node remove') end
    self.removed=true
end
local noop=function() end
function nodeMethods:CreateComponent(kind)
    if kind=='CustomGeometry' then
        return {BeginGeometry=noop,DefineVertex=noop,DefineNormal=noop,Commit=noop,SetMaterial=noop}
    elseif kind=='StaticModel' then
        return {SetModel=noop,SetMaterial=noop}
    end
    error('unexpected component '..tostring(kind))
end

Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end
Variant=function(value) return value end
VariantMap=function() return {} end
Quaternion=function(a,b,c) return {angle=a or 0,axis=b,yaw=b,roll=c} end
TRIANGLE_LIST=0; CULL_NONE=0
local surface={GetName=function() return 'Shaders/BLGL/EnemyVoxelHit.shader' end}
local function material()
    return {SetTechnique=noop,SetCullMode=noop,
        SetShaderParameter=function(self,key,value) self[key]=value end,
        GetShaderParameter=function() return {IsEmpty=function() return false end,
            GetVector4=function() return {x=1,y=1,z=1,w=1} end} end,
        GetSurfaceShader=function() return surface end,
        GetName=function() return 'mock_palette_material' end,
        SetSurfaceTexture=function(self,name,texture) self.paletteTexture=texture; return true end,
        Clone=function() return material() end}
end
Material={new=material}
local template=material()
cache={GetResource=function(_,kind,path)
    if kind=='Material' and path=='Shaders/BLGL/EnemyVoxelHit.xml' then return template end
    if kind=='Technique' and path=='Techniques/NoTextureUnlit.xml' then return {} end
    if kind=='Model' and path=='Models/Box.mdl' then return {} end
    return {}
end}

local function newWorld()
    local w={created=0,rebuilt=0,removed=0,rayBlocked=false}
    function w:GetPaletteTexture() return {} end
    function w:GetPaletteBankCount() return 1 end
    function w:GetPaletteBankLimit() return 8 end
    function w:SetPaletteEntry(index,color,priority) end
    function w:SetPaletteEntryPBR(index,rough,metal,spec,color) end
    function w:FinalizeVolume() error('enemy must not enter physics world') end
    function w:FinalizeVolumeAsDynamic() error('enemy must not enter physics world') end
    function w:CreateVolume(nx,ny,nz,size,pos,rot)
        self.created=self.created+1
        local n=node('voxel')
        local grid={SetSolid=noop,SetVoxelMaterial=noop,FillBox=noop,PaintBox=noop}
        local volume={rebuilds=0,GetGrid=function() return grid end,GetNode=function() return n end,
            SetPaletteBank=noop,
            SetMaterial=function(self,mat) self.material=mat end,
            RebuildGeometry=function(self) self.rebuilds=self.rebuilds+1; w.rebuilt=w.rebuilt+1 end,
            GetMaterial=function(self) return self.material or template end,
            GetPaletteDomain=function() return 0 end,
            GetPaletteBank=function() return 0 end}
        w.volumes=w.volumes or {}; w.volumes[#w.volumes+1]=volume
        return volume
    end
    function w:RemoveVolume(volume)
        if volume.removed then error('double volume remove') end
        volume.removed=true; self.removed=self.removed+1
    end
    function w:RaycastSingle(ray,length) return {hit=self.rayBlocked,distance=.3} end
    return w
end

local scene=node('scene')
function scene:SendEvent() end

-- ---------------------------------------------------------------- actor/combat helpers
local function newLogic(name)
    local ok,mod=pcall(require,'combat.enemies.actors.'..name)
    if not ok then fail(name..' require: '..tostring(mod)); return nil end
    local terrain,combat=T.Fixture()
    local ok2,e=pcall(mod.New,nil,nil,terrain,combat,Vector3.ZERO,name)
    if not ok2 then fail(name..' New(nil scene/world): '..tostring(e)); return nil,mod end
    return e,mod,combat,terrain
end
local function newVisual(name)
    local ok,mod=pcall(require,'combat.enemies.actors.'..name)
    if not ok then fail(name..' require: '..tostring(mod)); return nil end
    local terrain,combat=T.Fixture()
    local w=newWorld()
    local ok2,e=pcall(mod.New,scene,w,terrain,combat,Vector3.ZERO,name)
    if not ok2 then fail(name..' New(mock scene/world): '..tostring(e)); return nil,mod,combat,w end
    return e,mod,combat,w
end
local function modelFor(mod)
    local name=type(mod.Config.model)=='string' and mod.Config.model or nil
    if not name then fail(mod.Config.kind..' has no string config.model'); return nil end
    local ok,model=pcall(require,'combat.enemies.models.'..name)
    if not ok or type(model.Build)~='function' then fail(mod.Config.kind..' model '..tostring(name)..' unloadable'); return nil end
    local ok2,data=pcall(model.Build)
    if not ok2 or not data.parts or #data.parts==0 then fail(mod.Config.kind..' model Build invalid'); return nil end
    return name,data
end

local S=nil
local function state() if not S then S=require('combat.enemies.EnemyBase').State end return S end

-- Attack scenarios: positive target, then a post-lock evade target for the dodge pass.
local Scenarios={
    WoodSpirit={ {idx=1,hit=Vector3(0,0,1.0),evade=Vector3(0,0,-1.0)},
        {idx=2,hit=Vector3(0,0,1.5),evade=Vector3(1.2,0,1.5)} },
    NestWeaver={ {idx=1,hit=Vector3(0,0,1.0),evade=Vector3(1.4,0,0)},
        {idx=2,hit=Vector3(0,0,5.0),evade=Vector3(.65,0,5.0)} },
    RockColossus={ {idx=1,hit=Vector3(0,0,1.5),evade=Vector3(0,0,-1.2)},
        {idx=2,hit=Vector3(0,0,1.6),evade=Vector3(0,1.2,1.6)} },
    RuinConstruct={ {idx=1,hit=Vector3(0,0,1.5),evade=Vector3(1.2,0,1.5)},
        {idx=2,hit=Vector3(0,0,1.5),evade=Vector3(1.2,0,1.5)} },
    TimeWraith={ {idx=1,hit=Vector3(0,0,1.2),evade=Vector3(1.3,0,-.25)},
        {idx=2,hit=Vector3(0,0,3.4),evade=Vector3(0,1.2,3.4)} },
}
local function runAttack(e,combat,idx,hit,evade)
    e:Reset(); e:SetActive(true); e.aggro=true
    local a=e.config.attacks[idx]
    if not a then return nil,'no attack '..idx end
    e.attackIndex=idx-1; e.attack=a
    e:Face(hit)
    e:SetState(state().TELEGRAPH)
    -- Finish the wind-up with the aimed target, then commit the dodge before
    -- the first active frame so the attack cannot hit on the transition tick.
    T.Tick(e,a.telegraph-.02,hit)
    local target=hit
    if evade then target=evade end
    T.Tick(e,.04,target)
    if e.state~=state().ATTACK then return nil,'did not enter ATTACK' end
    T.Tick(e,a.duration+.30,target)
    return combat.hits,combat.damage,e
end

-- ---------------------------------------------------------------- per-actor contract
for _,name in ipairs(Names) do
    local e,mod,combat,terrain=newLogic(name)
    if e then
        local cfg=mod.Config
        check(type(cfg.model)=='string',name..' config.model missing')
        check(type(cfg.posePart)=='function',name..' config.posePart missing')
        check(type(cfg.attacks)=='table' and #cfg.attacks>=2,name..' needs normal + dodgeable attacks')
        check(cfg.hp and cfg.hp>0 and cfg.radius and cfg.radius>0 and cfg.height and cfg.height>0,
            name..' config hp/radius/height invalid')
        for i,a in ipairs(cfg.attacks or {}) do
            check(a.telegraph and a.telegraph>0 and a.duration and a.duration>0 and a.recover and a.recover>0,
                name..' attack '..i..' telegraph/duration/recover missing')
            check(a.damage and a.damage>0 and a.range and a.range>0,name..' attack '..i..' damage/range missing')
        end
        local mname,data=modelFor(mod)
        if data then
            local ids={}
            for _,p in ipairs(data.parts) do ids[p.id]=true end
            local cover=0
            for _,p in ipairs(cfg.parts or {}) do if ids[p.id] then cover=cover+1 end end
            check(cover>0,name..' config.parts do not reference model part ids')
        end
        -- Hit feedback contract (material role retained on the hit snapshot).
        e:SetActive(true)
        local beforePresented=e.presentedHits or 0
        local firstPart=(cfg.parts or {})[1]
        if firstPart then
            local r=e:ApplyHit({dmg=1,part=firstPart.id,kind='arrow',dir=Vector3(1,0,0)})
            check(r.hit and e.presentedHits==beforePresented+1,name..' hit feedback did not present exactly once')
            check(e.impact.material==(firstPart.material or 'stone'),name..' hit material role not retained')
        end

        -- Front/back/telegraph/death pose function must stay numeric for every model part.
        for _,stateName in ipairs({state().IDLE,state().TELEGRAPH,state().ATTACK,state().RECOVER}) do
            e.state=stateName; e.stateTime=.2; e.attack=(cfg.attacks or {})[1]
            for _,part in ipairs((data and data.parts) or cfg.parts or {}) do
                local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
                local ok=pcall(cfg.posePart,e,part.id,p)
                if not ok then fail(name..' posePart('..tostring(part.id)..') error in '..stateName); break end
                for k,v in pairs(p) do if type(v)~='number' or v~=v then fail(name..' posePart('..part.id..').'..k..' non-finite'); break end end
            end
        end
        e.state=state().DEAD; e.dead=true; e.deathTime=.8
        for _,part in ipairs((data and data.parts) or cfg.parts or {}) do
            local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
            local ok=pcall(cfg.posePart,e,part.id,p)
            if not ok then fail(name..' death posePart('..tostring(part.id)..') error'); break end
        end
        e:Destroy()
    end
end

-- ---------------------------------------------------------------- hit / dodge for both attacks
for _,name in ipairs(Names) do
    local scenarios=Scenarios[name]
    if scenarios then
        for _,sc in ipairs(scenarios) do
            local e,mod,combat=newLogic(name)
            if e then
                local hits,damage,why=runAttack(e,combat,sc.idx,sc.hit,nil)
                if hits==nil then fail(name..' attack '..sc.idx..' positive: '..tostring(why))
                else check(hits==1,name..' attack '..sc.idx..' positive expected 1 hit, got '..tostring(hits))
                    check(damage==e.config.attacks[sc.idx].damage,name..' attack '..sc.idx..' damage mismatch')
                end
                e:Destroy()
            end
            e,mod,combat=newLogic(name)
            if e then
                local hits,_,why=runAttack(e,combat,sc.idx,sc.hit,sc.evade)
                if hits==nil then fail(name..' attack '..sc.idx..' dodge: '..tostring(why))
                else check(hits==0,name..' attack '..sc.idx..' evade expected 0 hits, got '..tostring(hits)) end
                e:Destroy()
            end
        end
    end
end

-- ---------------------------------------------------------------- freeze / interrupt (Stagger is the freeze control)
for _,name in ipairs(Names) do
    for _,phase in ipairs({'telegraph','active'}) do
        local e,mod,combat=newLogic(name)
        if e then
            e:SetActive(true); e.aggro=true
            local a=e.config.attacks[1]
            e.attack=a; e.attackIndex=0; e:Face(Vector3(0,0,1.0))
            e:SetState(state().TELEGRAPH)
            if phase=='telegraph' then T.Tick(e,a.telegraph*.55,Vector3(0,0,1.0))
            else T.Tick(e,a.telegraph+.02,Vector3(0,0,1.0)); T.Tick(e,.08,Vector3(0,0,1.0)) end
            local before=combat.hits
            check(e:Stagger(1.5,false),name..' freeze/Stagger rejected in '..phase)
            check(not e.warning.visible,name..' warning stayed visible while frozen')
            if e.thread then check(not e.thread.active,name..' silk/projectile stayed active while frozen') end
            if e.boltPos then check(e.boltPos==nil,name..' bolt stayed active while frozen') end
            T.Tick(e,1.2,Vector3(0,0,1.0))
            check(combat.hits==before,name..' dealt damage while frozen ('..phase..')')
            e:Destroy()
        end
    end
end

-- ---------------------------------------------------------------- death / one drop / no reset
for _,name in ipairs(Names) do
    local e,mod,combat=newLogic(name)
    if e then
        local deaths=0
        combat.OnEnemyDead=function() deaths=deaths+1 end
        e:SetActive(true)
        local part=mod.Config.parts[1].id
        local r=e:ApplyHit({dmg=99999,part=part,kind='arrow',dir=Vector3(0,0,-1)})
        check(r.hit and r.killed and e.dead and e.defeated,name..' lethal hit did not kill/defeat')
        check(deaths==1,name..' death callback count '..deaths..' (expected 1)')
        T.Tick(e,1.3,Vector3(0,0,1))
        check(e.deathFinished,name..' death cleanup did not finish')
        check(deaths==1,name..' death callback repeated after cleanup')
        check(not e:Reset(),name..' defeated actor accepted Reset (would respawn)')
        local again=e:ApplyHit({dmg=1,part=part,kind='arrow'})
        check(not again.hit and deaths==1,name..' dead actor accepted another hit/drop')
        e:Destroy()
    end
end

-- ---------------------------------------------------------------- model visual bind + no rebuild
for _,name in ipairs(Names) do
    local e,mod,combat,w=newVisual(name)
    if e then
        local mname,data=modelFor(mod)
        check(w.created>0,name..' visual created no volumes')
        local visual=e.visual
        check(visual and not visual.removed,name..' visual missing after spawn')
        if visual then
            local found=0
            if visual.parts then for _,p in ipairs(visual.parts) do if p.id then found=found+1 end end end
            if visual.bones then for id in pairs(visual.bones) do found=found+1 end end
            if data then check(found>0,name..' visual exposes no model part ids (config.model not wired)') end
            local handles={}
            if visual.parts then for _,p in ipairs(visual.parts) do if p.id then handles[p.id]=p.pivot or p.node end end end
            if visual.bones then for id,node in pairs(visual.bones) do handles[id]=handles[id] or node end end
            local restOK=true
            if data then
                for _,dp in ipairs(data.parts) do
                    local pivot=handles[dp.id]
                    if not pivot then restOK=false; fail(name..' visual exposes no pivot for model part '..tostring(dp.id)); break end
                    local rp=dp.pivot or {0,0,0}
                    if math.abs(pivot.position.x-rp[1])>1e-5 or math.abs(pivot.position.y-rp[2])>1e-5
                        or math.abs(pivot.position.z-rp[3])>1e-5 then
                        restOK=false; fail(name..' pivot rest mismatch for '..dp.id..' (model pivot not preserved)')
                        break
                    end
                end
            end
            if restOK then
                local before={}
                for id,pivot in pairs(handles) do
                    before[id]={pivot.position.x,pivot.position.y,pivot.position.z,
                        pivot.rotation and pivot.rotation.angle or 0,
                        pivot.rotation and pivot.rotation.yaw or 0,
                        pivot.rotation and pivot.rotation.roll or 0}
                end
                e.attack=e.config.attacks[1]; e.attackIndex=0; e:Face(Vector3(0,0,1))
                e:SetState(state().TELEGRAPH); T.Tick(e,.2,Vector3(0,0,1))
                local moved=false
                for id,pivot in pairs(handles) do
                    local b=before[id]
                    if math.abs(pivot.position.x-b[1])+math.abs(pivot.position.y-b[2])+math.abs(pivot.position.z-b[3])>1e-5
                        or (pivot.rotation and pivot.rotation.angle or 0)~=b[4]
                        or (pivot.rotation and pivot.rotation.yaw or 0)~=b[5]
                        or (pivot.rotation and pivot.rotation.roll or 0)~=b[6] then moved=true; break end
                end
                check(moved,name..' posePart did not move any model pivot')
                local handleCount=0; for _ in pairs(handles) do handleCount=handleCount+1 end
                print(string.format('MODEL-PIVOT %-13s rest=ok pose=ok parts=%d',name,handleCount))
            end
        end
        local c0,r0=w.created,w.rebuilt
        e:SetActive(true); e.aggro=true
        e.attack=e.config.attacks[1]; e.attackIndex=0; e:Face(Vector3(0,0,1))
        e:SetState(state().TELEGRAPH); T.Tick(e,.2,Vector3(0,0,1))
        e:ApplyHit({dmg=1,dir=Vector3(1,0,0)})
        e:Stagger(.8,false); T.Tick(e,.9,Vector3(0,0,1))
        e:ApplyHit({dmg=99999,dir=Vector3(0,0,-1)}); T.Tick(e,1.3,Vector3(0,0,1))
        check(w.created==c0,name..' model volumes were rebuilt/created after init ('..c0..'->'..w.created..')')
        check(w.rebuilt==r0,name..' RebuildGeometry called after init ('..r0..'->'..w.rebuilt..')')
        print(string.format('MODEL-VISUAL %-13s parts=%d created=%d rebuilt=%d stable',name,(visual.parts and #visual.parts) or 0,w.created,w.rebuilt))
        e:Destroy()
    end
end

-- ---------------------------------------------------------------- scene entry
local okTerrain,Terrain=pcall(require,'ruins.RuinsTerrain')
if okTerrain then
    local okSpawn,Spawner=pcall(require,'combat.enemies.Spawner')
    if okSpawn then
        local terrain,combat=T.Fixture()
        local w=newWorld()
        local ok,sp=pcall(Spawner.New,nil,w,Terrain,combat)
        if not ok then fail('Spawner.New: '..tostring(sp))
        else
            local enabled,added=pcall(sp.EnableModelEncounters,sp)
            check(enabled,'Spawner.EnableModelEncounters failed')
            check(enabled and added==5,'Spawner model encounters added '..tostring(added)..'/5 (terrain rejected seeds)')
            local kinds={}
            for _,enemy in ipairs(sp:GetEnemies() or {}) do kinds[enemy.kind or enemy.config.kind]=true end
            local byKind={}
            for _,enemy in ipairs(sp:GetEnemies() or {}) do byKind[enemy.kind or enemy.config.kind]=enemy end
            for _,name in ipairs(Names) do
                local mod=require('combat.enemies.actors.'..name)
                check(kinds[mod.Config.kind]==true,name..' is not in the ruins Spawner encounter')
                local actor=byKind[mod.Config.kind]
                if actor then
                    check(sp.boss and not sp.boss.dead,'Boss is missing/dead during model encounter check')
                    if sp.boss and not sp.boss.dead then
                        local p=actor.home
                        local dx,dz=p.x-sp.boss.home.x,p.z-sp.boss.home.z
                        local dist=math.sqrt(dx*dx+dz*dz)
                        sp:Update(.01,p)
                        local okActive=check(actor.active,name..' inactive with live Boss at its own spawn (Boss distance '
                            ..string.format('%.1f',dist)..'m, ARENA_DISTANCE '..tostring(Spawner.ARENA_DISTANCE)..'m)')
                        local okSelected=check(actor.selected,name..' not selected with player at its own spawn')
                        if okActive and okSelected then
                            print(string.format('BOSS-ALIVE %-13s spawn=(%.1f,%.1f) bossDist=%.1fm active=yes selected=yes',
                                name,p.x,p.z,dist))
                        end
                    end
                end
            end
            sp:Destroy()
        end
    else fail('Spawner require: '..tostring(Spawner)) end
else fail('RuinsTerrain require: '..tostring(Terrain)) end

if #failures>0 then
    error(#failures..' actor integration failure(s):\n'..table.concat(failures,'\n'),0)
end
print('PASS five actors: config/model/posePart, hit+evade, freeze/no sneaky hit, one death/drop, no rebuild, Spawner entry')
