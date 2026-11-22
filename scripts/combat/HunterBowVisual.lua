-- Visual-only Hunter Bow. The caller retains the voxel draw string and arrow.
local V={}
V.ENABLED=true             -- kill switch: false = always show the voxel bow
V.PAD=.10                  -- visual limb length = (voxel limb span + this) * SCALE (metres)
V.SCALE=1.32               -- bows read small next to the character; Ganyu-style full-size bow
V.STEP_VERTICES=1800       -- per Step(); build is spread over frames
V.AIM_YAW=55               -- degrees, toward the shooter's right camera
V.AIM_ROLL=16              -- degrees, top leans right
local MATERIAL='model/forge-blades/HunterBow.xml'
local MASK=0xFFFFFFFF
local model
local function Model()
    model=model or require('combat.models.HunterBow').Load()
    return model
end
--- Back-slung rotation: recurve profile faces a camera behind the character.
--- Model +Z (target) -> character +X, top leans toward +X. Hand rotation is unchanged.
-- = Rz(-35)*Ry(90) written as one Euler triple (pitch,yaw,roll): Ry(90)*Rx(35). Model +Y -> (sin35,cos35,0).
function V.BackRotation() return Quaternion(35,90,0) end

local function BuildBody(g,part,from,to)
    local m=Model()
    local v,idx=part.v,part.i
    local ps,ns=1/m.scale,1/m.nscale
    for k=from,to do
        local base=(idx[k]-1)*m.vertexStride
        g:DefineVertex(Vector3(v[base+1]*ps,v[base+2]*ps,v[base+3]*ps))
        g:DefineNormal(Vector3(v[base+4]*ns,v[base+5]*ns,v[base+6]*ns))
        g:DefineColor(Color(v[base+7]*.01,v[base+8]*.01,v[base+9]*.01,v[base+10]*.01))
        g:DefineTexCoord(Vector2(v[base+12]/m.uvScale,v[base+13]/m.uvScale))
    end
end

---@param parent Node
---@param scale number
---@param mask integer?
---@param shadows boolean?
---@return table visual
local function Create(parent,scale,mask,shadows)
    mask=mask or MASK
    local visual={cursor=1,ready=false,bendKey=-1,scale=scale}
    local ok,err=pcall(function()
        local m=Model()
        local source=assert(cache:GetResource('Material',MATERIAL),'hunter bow material unavailable')
        visual.material=assert(source:Clone('HunterBowMat'),'hunter bow material clone failed')
        local node=parent:CreateChild('hunter_bow_visual')
        node.temporary=true
        visual.node=node
        node.scale=Vector3(scale,scale,scale)
        visual.stringZ=m.sockets.stringZ*scale
        local lo,hi=math.huge,-math.huge
        for k=2,#m.string.v,m.vertexStride do lo=math.min(lo,m.string.v[k]);hi=math.max(hi,m.string.v[k]) end
        visual.stringHalf=(hi-lo)*.5/m.scale*scale
        local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
        g.viewMask=mask;g.lightMask=mask;g.zoneMask=mask;g.castShadows=shadows==true
        g:BeginGeometry(0,TRIANGLE_LIST)
        visual.geometry=g
        visual.total=m.body.triangles*3
        -- Static string lives on its own node: hidden while the voxel string takes over (draw/release).
        visual.stringNode=node:CreateChild('hunter_bow_string')
        local sg=assert(visual.stringNode:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
        sg.viewMask=mask;sg.lightMask=mask;sg.zoneMask=mask;sg.castShadows=false
        sg:BeginGeometry(0,TRIANGLE_LIST)
        BuildBody(sg,m.string,1,m.string.triangles*3)
        sg:Commit()
        assert(sg:SetMaterial(0,visual.material)~=false,'hunter bow string binding failed')
    end)
    if not ok then
        V.Dispose(visual)
        return nil,tostring(err)
    end
    return visual
end

---@param pivot Node weapon_grip_bow pivot (hand / back follow it)
---@param halfHeight number voxel limb half span in pivot space (metres)
---@return table? visual
---@return string? err
function V.New(pivot,halfHeight)
    if not V.ENABLED then return nil,'disabled' end
    local ok,m=pcall(Model)
    if not ok then return nil,tostring(m) end
    local visual,err=Create(pivot,(halfHeight*2+V.PAD)*V.SCALE/m.height)
    if not visual then return nil,err end
    visual.node.enabled=false
    visual.stringNode.enabled=false
    return visual
end

--- Forge showroom: unscaled model under `parent`, uploaded by Step() like the blade jobs.
--- Returned job has the fields ForgeShowroom expects (node, material, blueprint, step).
---@param parent Node
---@param mask integer
---@param low boolean
---@return table? job
---@return string? err
function V.BeginShowroom(parent,mask,low)
    if not V.ENABLED then return nil,'disabled' end
    local visual,err=Create(parent,1,mask,not low)
    if not visual then return nil,err end
    local m=Model()
    local job={hunter=visual,node=visual.node,material=visual.material,
        blueprint={bounds={min={table.unpack(m.bounds.min)},max={table.unpack(m.bounds.max)}}}}
    job.step=function(j)
        local done=V.Step(j.hunter)
        assert(not j.hunter.failed,'hunter bow upload failed')
        return done
    end
    return job
end
---@param job table
function V.DisposeShowroom(job)
    if job and job.hunter then V.Dispose(job.hunter);job.hunter=nil;job.material=nil end
end

--- Upload complete triangles over successive frames. Returns true when the visual is usable.
---@param visual table?
---@return boolean
function V.Step(visual)
    if not visual then return false end
    if visual.ready then return true end
    if visual.failed then return false end
    local ok,err=pcall(function()
        local m=Model()
        local last=math.min(visual.total,visual.cursor+V.STEP_VERTICES-1)
        BuildBody(visual.geometry,m.body,visual.cursor,last)
        visual.cursor=last+1
        if last>=visual.total then
            visual.geometry:Commit()
            assert(visual.geometry:SetMaterial(0,visual.material)~=false,'hunter bow material binding failed')
            visual.ready=true
        end
    end)
    if not ok then
        V.Dispose(visual)
        visual.failed=true
        print('HunterBowVisual: build failed, voxel bow kept: '..tostring(err))
        return false
    end
    return visual.ready
end

---@param visual table?
---@param visible boolean
function V.SetVisible(visual,visible)
    if not (visual and visual.node) then return end
    visible=visible and visual.ready==true
    if visual.shown==visible then return end
    visual.shown=visible
    -- Node:SetEnabled is NOT recursive: child nodes keep rendering at the old place unless toggled too.
    visual.node.enabled=visible
    if visual.stringNode then visual.stringNode.enabled=visible and not visual.stringHidden end
end

local finishes={{.385,.267,.220},{.44,.30,.23},{.50,.36,.27}}
function V.SetGrade(visual,grade)
    if not (visual and visual.material) or visual.grade==grade then return end
    local c=finishes[grade]
    if not c then return end
    visual.material:SetShaderParameter('wood_color',Variant(Color(c[1],c[2],c[3],1)))
    visual.grade=grade
end

---@param visual table?
---@param visible boolean
function V.SetStringVisible(visual,visible)
    if not (visual and visual.stringNode) then return end
    visual.stringHidden=not visible
    visual.stringNode.enabled=visual.shown==true and visible
end

--- Aim stance (0..1): the bow turns a little toward the camera and cants so its profile is visible.
---@param visual table?
---@param k number
function V.SetAim(visual,k)
    if not (visual and visual.node) then return end
    local q=math.floor(math.max(0,math.min(1,k))*16+.5)
    if visual.aimStep==q then return end
    visual.aimStep=q
    local u=q/16
    visual.node.rotation=Quaternion(0,V.AIM_YAW*u,-V.AIM_ROLL*u)
end

--- Limb tips pull toward the archer by `meters` (pivot space); cached Variants, no per-frame allocation.
---@param visual table?
---@param meters number
function V.SetBend(visual,meters)
    if not (visual and visual.material) then return end
    local key=math.floor(meters*100+.5)
    if visual.bendKey==key then return end
    visual.bendKey=key
    visual.bendValues=visual.bendValues or {}
    local value=visual.bendValues[key]
    if not value then value=Variant(key*.01/visual.scale);visual.bendValues[key]=value end
    visual.material:SetShaderParameter('bend',value)
end

---@param visual table?
---@return number? z string plane in pivot space (negative = archer side)
function V.StringZ(visual)
    return visual and visual.stringZ or nil
end

---@param visual table?
---@return number? y half distance between the two string nocks in pivot space
function V.StringHalf(visual)
    return visual and visual.stringHalf or nil
end

---@param visual table?
function V.Dispose(visual)
    if not visual then return end
    if visual.node then pcall(visual.node.Remove,visual.node);visual.node=nil end
    if visual.material then pcall(visual.material.Dispose,visual.material);visual.material=nil end
end
return V
