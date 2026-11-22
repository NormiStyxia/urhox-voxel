-- Weapon/environment contact only. Enemy damage and TimeObject ownership stay
-- with their existing systems. Never broadcast a carve to neighbouring volumes.
local Perf=require('combat.SwingPerf')
local VoxelDamage=require('ruins.VoxelDamage')
---@class CombatEnvironmentDamage
---@field o table
---@field marks table[]
local E={}; E.__index=E
E.POWER=3 -- same material threshold as Shatter; ancient stone stays protected
E.LIGHT_RADIUS=.24
E.HEAVY_RADIUS=.32
E.MAX_RAYS=36 -- per swing, including visibility; no delayed destruction queue
-- Contact tolerance stays small; the confirmed impact releases a broad cut.
E.CUT_RADIUS=.50
E.HEAVY_CUT_RADIUS=.50 -- finisher widens the strip, not its downward reach
E.CUT_STEP=.45 -- overlapping lobes leave a continuous central cutting band
E.CUT_FLOOR=.16
E.MAX_CUT_LIFT=.40 -- don't turn a low contact into a remote overhead cut
local LIGHT_OFFSETS={0,-1,1,-2,2,-3,3}
local HEAVY_OFFSETS={0,-1,1,-2,2,-3,3,-4,4}

function E.New(opts)
    local self=setmetatable({o=opts or {},marks={},count=0,rays=0,serial=-1,active=false,
        reported={},reportCount=0},E)
    for i=1,9 do self.marks[i]={} end
    return self
end

-- Bounded evidence, not a gameplay fallback. Each stage reports once per scene;
-- no formatting/getters when the host has not supplied the diagnostic sink.
function E:Report(kind,reason,hit,center,radius,removed,nativeReturn)
    if not self.o.trace or self.reportCount>=24 then return end
    local key=kind..':'..reason
    if self.reported[key] then return end
    self.reported[key]=true;self.reportCount=self.reportCount+1
    pcall(self.o.trace,kind,reason,hit,center,radius,removed,nativeReturn)
end

---@param hit VoxelRaycastResult|nil
function E:Eligible(hit)
    if not hit or not hit.hit or not hit.volume then return false,'no-hit' end
    local v=hit.volume
    if not v.destructible then return false,'protected' end
    if not v:IsEnabledEffective() then return false,'disabled-volume' end
    if (v.collisionLayer & 1)==0 then return false,'non-world-layer' end
    local node=v:GetNode()
    if not node or not node:IsEnabled() then return false,'disabled-node' end
    -- Includes intact objects, frozen platforms and visual rewind fragments.
    if self.o.timeObject and self.o.timeObject(v) then return false,'time-object' end
    return true
end

---@param hit VoxelRaycastResult
---@return Vector3?
---@return number? world-space minimum cell edge
function E.Cell(hit)
    local v=hit.volume
    local grid=v:GetGrid()
    local cell=hit.voxel
    local size=v.voxelSize
    if not grid or not cell or size<=0 then return nil end
    local d=grid:GetDimensions()
    local x,y,z=cell.x,cell.y,cell.z
    if x<0 or y<0 or z<0 or x>=d.x or y>=d.y or z>=d.z or not grid:IsSolid(x,y,z) then return nil end
    local node=v:GetNode()
    local scale=node.worldScale
    local edge=size*math.min(math.abs(scale.x),math.abs(scale.y),math.abs(scale.z))
    if edge<1e-6 then return nil end
    return node:LocalToWorld(Vector3((x+.5)*size,(y+.5)*size,(z+.5)*size)),edge
end

---@param hit VoxelRaycastResult
---@param center Vector3
---@param radius number
function E:Carve(hit,center,radius,kind)
    self:Report(kind,'carve-start',hit,center,radius)
    Perf.Invalidate() -- synchronous damage callbacks may split/remove volumes
    local removed,nativeReturn=VoxelDamage.Volume(self.o.world,hit.volume,center,radius,E.POWER)
    Perf.Invalidate()
    self:Report(kind,removed>0 and 'removed' or 'removed-zero',hit,center,radius,removed,nativeReturn)
    if removed~=nativeReturn then self:Report(kind,'native-return',hit,center,radius,nativeReturn) end
    return removed
end

-- Called once at the actual swept arrow impact, never by the aim predictor.
-- A small sphere at the exact cell centre cannot reach adjacent cell centres,
-- even with maximum boundary noise. Native connectivity may detach supports.
function E:Arrow(event)
    local hit=event.worldHit
    local eligible,reason=self:Eligible(hit)
    if not eligible then self:Report('arrow',reason,hit);return 0 end
    local center,edge=E.Cell(hit)
    if not center or not edge then self:Report('arrow','invalid-cell',hit);return 0 end
    local start=Perf.Begin()
    local removed=self:Carve(hit,center,edge*.2,'arrow')
    Perf.Finish('VoxelArrow',start)
    return removed
end

---@param a Vector3
---@param b Vector3
function E:Cast(a,b)
    if self.rays>=E.MAX_RAYS or (b-a):LengthSquared()<1e-8 then return nil,nil end
    self.rays=self.rays+1
    return self.o.cast(a,b)
end

-- One horizontal capsule-like strip per swing, built from overlapping spheres
-- on the ORIGINAL surface plane. Native capsule/box APIs broadcast to other
-- volumes, so keep specified-volume damage and fresh player LOS per lobe.
---@param hit VoxelRaycastResult
---@param center Vector3
---@param feet Vector3
---@param heavy boolean
function E:WideCut(hit,center,feet,heavy)
    self.cutDone=true -- reserve before synchronous callbacks/reentrant pose ticks
    local id=hit.volume.volumeId
    local normal=Vector3(hit.normal.x,0,hit.normal.z)
    if normal:LengthSquared()<.1 then normal=feet-center;normal=Vector3(normal.x,0,normal.z) end
    if normal:LengthSquared()<1e-8 then return end
    normal=normal:Normalized()
    local tangent=Vector3(-normal.z,0,normal.x)
    local origin=feet+Vector3(0,.9,0)
    local offsets=heavy and HEAVY_OFFSETS or LIGHT_OFFSETS
    local radius=heavy and E.HEAVY_CUT_RADIUS or E.CUT_RADIUS
    -- Clip the lower envelope by raising the shallow strip, never by shrinking
    -- all three axes. Even the conservative 2x ragged boundary clears the feet.
    local lift=math.max(0,feet.y+E.CUT_FLOOR+radius*2-center.y)
    if lift>E.MAX_CUT_LIFT then self:Report('sword','cut-too-low',hit,center,radius);return end
    local base=center+Vector3(0,lift,0)
    local total=0
    local impact,impactNormal=hit.position,hit.normal
    for _,offset in ipairs(offsets) do
        local point=base+tangent*(offset*E.CUT_STEP)
        local surface=point-normal*((point-impact):DotProduct(normal))
        local sight=surface-origin
        local depth=-sight:DotProduct(normal)
        if depth>.02 then
            -- Extend along the same sightline AFTER the chosen surface point.
            -- Adding a normal offset to the target instead shrinks its lateral
            -- intersection toward the player, scattering/compressing the cut.
            -- End at the original shallow band; never chase a hole backwards.
            local _,front=self:Cast(origin,surface+sight*(.40/depth))
            if self:Eligible(front) and front.volume.volumeId==id and front.normal.y<=.55 then
                local cell=E.Cell(front)
                if cell and math.abs((cell-center):DotProduct(normal))<=.40
                    and (cell-point):LengthSquared()<=radius*radius then
                    self.count=self.count+1
                    self.marks[self.count].position=point -- scalars/positions only survive damage
                    total=total+self:Carve(front,point,radius,'sword')
                end
            end
        end
    end
    if total>0 and self.o.feedback then
        self.o.feedback({kind='hit',material='stone',tier='environment',pos=impact,
            normal=impactNormal,dir=-normal,removed=total})
    end
end

---@param a Vector3
---@param b Vector3
---@param feet Vector3
---@param radius number
function E:Slice(a,b,feet,radius)
    if self.cutDone then return end
    local _,hit=self:Cast(a,b)
    local eligible,reason=self:Eligible(hit)
    if not eligible then self:Report('sword',reason,hit);return end
    local center=E.Cell(hit)
    if not center then self:Report('sword','invalid-cell',hit);return end
    -- Never cut an upward-facing support surface, nor the band below the feet.
    -- Extra clearance covers the engine's ragged damage boundary. Melee only
    -- accepts the five ordinary light stages and the cross slash.
    if hit.normal.y>.55 or center.y-radius*2<feet.y+.15 then
        self:Report('sword','floor-guard',hit,center,radius);return
    end
    -- A blade pose can visually cross a wall; never carve its hidden far side.
    if self.rays>=E.MAX_RAYS then return end
    local target=hit.position+hit.normal*.02
    local sightOrigin=feet+Vector3(0,.9,0)
    if (target-sightOrigin):LengthSquared()<1e-8 then
        self:Report('sword','occluded',hit,center,radius);return
    end
    local wall,front=self:Cast(sightOrigin,target)
    if wall and wall<1-1e-5 then
        -- A sampled blade can start INSIDE the struck stone (zero DDA normal),
        -- especially at low FPS. Its own exposed surface is not a separate wall.
        -- Resolve only that same volume's first surface, within this blade
        -- segment's existing cut radius; never reach through another volume or
        -- drill the hidden cell behind the surface.
        local exposed=front and front.volume==hit.volume and self:Eligible(front) and E.Cell(front)
        local segment=b-a
        local length2=segment:LengthSquared()
        local t=exposed and length2>1e-8 and math.max(0,math.min(1,(exposed-a):DotProduct(segment)/length2)) or 0
        if not exposed or (exposed-(a+segment*t)):LengthSquared()>radius*radius
            or front.normal:LengthSquared()<.5 then
            self:Report('sword','occluded',hit,center,radius);return
        end
        hit,center=front,exposed
        if hit.normal.y>.55 or center.y-radius*2<feet.y+.15 then
            self:Report('sword','floor-guard',hit,center,radius);return
        end
        self:Report('sword','surface-contact',hit,center,radius)
    end
    self:WideCut(hit,center,feet,radius==E.HEAVY_RADIUS)
end

-- Actual blade endpoints after the pose/rig update; independent of trail quality.
-- Enemy sector/reach contracts are not used to excavate the entire attack area.
---@param root Vector3|nil
---@param tip Vector3|nil
---@param feet Vector3
function E:Melee(root,tip,feet,serial,clip,active,clock)
    local sword=clip and (clip:match('^sword_light_[1-5]$') or clip=='sword_heavy_release')
    if sword and active and (not root or not tip) then self:Report('sword','no-held-blade') end
    if not root or not tip or not sword then self.active=false;self.root,self.tip=nil,nil;return end
    if self.serial~=serial then
        self.serial,self.count,self.rays=serial,0,0
        self.cutDone=false
        self.active=false;self.root,self.tip=nil,nil;self.nextAt=0
    end
    if not active then self.active=false;self.root,self.tip=root,tip;return end
    if (root-feet):LengthSquared()>16 or (tip-feet):LengthSquared()>16 then self.active=false;return end
    local swept=self.active and self.root and self.tip
    local distance=swept and math.max((root-self.root):Length(),(tip-self.tip):Length()) or 0
    -- Repeated AfterPose/hitstop frames cannot deepen one hole. A teleport never
    -- joins two positions into a destructive ray through the intervening world.
    if swept and (distance<.10 or clock<(self.nextAt or 0)) then return end
    if distance>2 then swept=false end
    local oldRoot,oldTip=self.root,self.tip
    self.root,self.tip,self.active,self.nextAt=root,tip,true,clock+.025
    local heavy=clip=='sword_heavy_release' or clip=='sword_light_5'
    local radius=heavy and E.HEAVY_RADIUS or E.LIGHT_RADIUS
    if self.cutDone or self.rays>=E.MAX_RAYS then return end
    local start=Perf.Begin()
    self:Slice(root,tip,feet,radius)
    if swept then
        self:Slice(oldTip,tip,feet,radius)
        self:Slice((oldRoot+oldTip)*.5,(root+tip)*.5,feet,radius)
    end
    Perf.Finish('VoxelSlash',start)
end
return E
