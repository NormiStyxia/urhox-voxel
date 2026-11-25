-- Create after Terrain/Build/Puzzles and tear down before the voxel world.
-- options.training selects first-pickup receipts per kind. wasClaimed(key,trainingKind)
-- reads the saved receipt. cast(a,b) may be the scene's exact CombatCast.
-- Nearest returns {id,itemId,count,name,prompt,key,position,distance,source,trainingKind}.
-- Claim(id,feet,grant) calls grant(target) synchronously. Return true only after
-- the inventory grant commits. Pass target.trainingKind to WeaponStore.AddMaterial.
-- A site receipt can optionally be restored via wasClaimed on a later visit.
local Catalog=require('combat.MaterialCatalog')
local Terrain=require('ruins.RuinsTerrain')
local Models=require('ruins.RuinsResourceModels')
local R={}
R.__index=R

local verbs={timber='取木',crystal_ore='采矿',stone='采石'}
local mask=0xffffffff & ~2 -- same environment mask as the walking controller
local down=Vector3(0,-1,0)
local up=Vector3(0,1,0)
local directions={{1,0},{.707,.707},{0,1},{-.707,.707},{-1,0},{-.707,-.707},{0,-1},{.707,-.707}}

local function castWorld(world,origin,direction,distance)
    local nearest
    for _,hit in ipairs(world:Raycast(Ray(origin,direction),distance,mask)) do
        if hit.hit and hit.volume and (hit.volume.collisionMask & 1)~=0
            and (not nearest or hit.distance<nearest.distance) then nearest=hit end
    end
    return nearest
end

local function obstruction(self,a,b)
    local delta=b-a
    local length=delta:Length()
    if length<.001 then return end
    if self.cast then
        local fraction,hit=self.cast(a,b)
        if fraction then return hit or true end
    else
        return castWorld(self.world,a,delta/length,length)
    end
end

-- The terrain map restricts drops to permanent island surfaces. Actual voxel
-- support rejects broken floors, wall tops and ledges above the walking plane.
local function footing(world,x,z)
    if not Terrain.HasGround(x,z,1.15) then return end
    local ground=Terrain.GroundHeight(x,z)
    if not ground then return end
    local hit=castWorld(world,Vector3(x,ground+2.1,z),down,2.65)
    if hit and hit.normal.y>.65 and math.abs(hit.position.y-ground)<=.65 then
        return hit.position.y
    end
end

local function clearFloor(world,x,z,width)
    local y=footing(world,x,z)
    if not y then return end
    for i=1,8,2 do
        local d=directions[i]
        local h=footing(world,x+d[1]*width,z+d[2]*width)
        if not h or math.abs(h-y)>.40 then return end
    end
    return Vector3(x,y+.012,z)
end

local function squareDistance(a,b)
    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
    return dx*dx+dy*dy+dz*dz
end

local function hasRoom(self,pos,spacing)
    for _,item in pairs(self.entries) do
        local limit=item.source=='site' and spacing+.68 or spacing
        if squareDistance(pos,item.position)<limit*limit then return false end
    end
    return true
end

local function island(x,z)
    local main=Terrain.Edges(math.atan(z,x))
    return x*x+z*z<=main*main and 'court' or 'rim'
end

local function landing(self,anchor,reference,width,spacing)
    if not anchor then return end
    local function sample(x,z)
        if reference and island(x,z)~=reference then return end
        local pos=clearFloor(self.world,x,z,width)
        if pos and hasRoom(self,pos,spacing) then return pos end
    end
    local pos=sample(anchor.x,anchor.z)
    if pos then return pos end
    for _,radius in ipairs({1,2.3,4.3}) do
        for _,d in ipairs(directions) do
            pos=sample(anchor.x+d[1]*radius,anchor.z+d[2]*radius)
            if pos then return pos end
        end
    end
end

-- Short voxel cores keep the controller outside the resource. After harvest
-- the remaining base still supports feet, while the upper collider goes away.
local function collider(world,pos,w,h,bottom)
    local size=.25
    local v=world:CreateVolume(w,h,w,size,Vector3(pos.x-w*size*.5,pos.y+bottom,pos.z-w*size*.5))
    v:GetGrid():FillBox(0,0,0,w-1,h-1,w-1,true)
    v.destructible,v.evictable=false,false
    v.material=Terrain.HiddenMaterial()
    world:FinalizeVolume(v)
    v:RebuildGeometry()
    return v
end

local function claimed(self,key,trainingKind)
    return key and (self.receipts[key] or (self.wasClaimed and self.wasClaimed(key,trainingKind)))
end

local function orient(node,dx,dz)
    if not Quaternion or (dx*dx+dz*dz)<1e-6 then return end
    node.rotation=Quaternion(math.deg(math.atan(dx,dz)),up)
end

local function registerSite(self,site,itemId,count,pos,tree,faceDx,faceDz)
    local key='site:'..site
    local spent=claimed(self,key)
    local node=self.root:CreateChild(site)
    node.position=pos
    if faceDx and faceDz then orient(node,faceDx,faceDz) end
    local item={id=key,key=key,source='site',itemId=itemId,count=count,position=pos,node=node,spent=spent,tree=tree}
    item.stock=Models.Site(node,itemId,self.materials,spent)
    if spent then item.remains=Models.Harvested(node,itemId,self.materials) end
    if not tree then
        item.baseCollider=collider(self.world,pos,4,1,0)
        if not spent then item.upperCollider=collider(self.world,pos,3,2,.25) end
    end
    self.entries[item.id]=item
end

local function addSite(self,def)
    local site,itemId,count,x,z,mode,faceX,faceZ=table.unpack(def)
    local wall=mode=='wall'
    local tree=mode=='tree'
    local anchor,width=Vector3(x,0,z),wall and .35 or .8
    if tree then
        local length=math.max(.001,math.sqrt(x*x+z*z))
        anchor=Vector3(x-x/length*1.55,0,z-z/length*1.55)
        width=.25
    end
    local pos=landing(self,anchor,nil,width,.9)
    if not pos then
        print('RuinsResources: no walkable ground for '..site)
        return
    end
    local fdx,fdz
    if faceX and faceZ then fdx,fdz=faceX-pos.x,faceZ-pos.z end
    registerSite(self,site,itemId,count,pos,tree,fdx,fdz)
end

-- Timber comes from every tree the ruins already grows: place a compact woodpile
-- right beside the trunk (clear of its hidden collider) and own no volume.
local function addTreeSite(self,tree)
    local tx,tz=tree.x,tree.z
    local standoff=math.max(1.25,(tree.trunk or .45)*.8+.75)
    local len=math.max(.001,math.sqrt(tx*tx+tz*tz))
    local ix,iz=-tx/len,-tz/len
    local pos
    local function tryAt(px,pz)
        local p=clearFloor(self.world,px,pz,.25)
        if p and hasRoom(self,p,.85) then return p end
    end
    pos=tryAt(tx+ix*standoff,tz+iz*standoff)
    if not pos then
        for _,d in ipairs(directions) do
            pos=tryAt(tx+d[1]*standoff,tz+d[2]*standoff)
            if pos then break end
        end
    end
    if not pos then
        print('RuinsResources: no walkable ground for '..tostring(tree.id))
        return
    end
    registerSite(self,tree.id,Catalog.TreeYield.id,Catalog.TreeYield.count,pos,true,pos.x-tx,pos.z-tz)
end

function R.New(scene,world,options)
    options=options or {}
    local self=setmetatable({root=scene:CreateChild('RuinsResources'),world=world,
        training=options.training==true,cast=options.cast,wasClaimed=options.wasClaimed,
        materials=Models.Materials(),entries={},receipts={},nextId=0},R)
    for _,def in ipairs(Catalog.Sites) do addSite(self,def) end
    if type(options.trees)=='table' then
        for _,tree in ipairs(options.trees) do addTreeSite(self,tree) end
    end
    return self
end

-- safePosition is the player's last walkable ruins position. Use its island
-- when an airborne enemy dies over the gap, with an authored training fallback.
function R:SpawnDrop(kind,position,safePosition)
    local drop=Catalog.EnemyDrops[kind]
    if not self.root or not drop then return nil end
    local trainingKind=self.training and kind or nil
    local key=trainingKind and 'training:'..kind or nil
    if claimed(self,key,trainingKind) then return nil end
    if key and self.entries[key] then return key end -- a previous kill is still on the ground
    local fallback=safePosition or (self.training and Vector3(3,-.01,-5.4) or nil)
    local reference=fallback and Terrain.HasGround(fallback.x,fallback.z) and island(fallback.x,fallback.z) or nil
    local pos=landing(self,position,reference,.32,.55)
    -- A flyer can die behind the still-sealed gate on the very same ring.
    -- An obstructed approach from the last walking position settles on its side.
    if pos and fallback and position and position.y>pos.y+1.0 then
        local lift=Vector3(0,.95,0)
        if obstruction(self,fallback+lift,pos+lift) then pos=nil end
    end
    pos=pos or landing(self,fallback,reference,.32,.55)
    if not pos then
        local rim=reference=='rim' or (not reference and position and island(position.x,position.z)=='rim')
        pos=landing(self,rim and Vector3(0,6,-62) or Vector3(-3,0,-6),reference,.32,.22)
    end
    if not pos then return nil end
    self.nextId=self.nextId+1
    local id=key or 'drop:'..self.nextId
    local node=self.root:CreateChild(id)
    node.position=pos
    Models.Drop(node,drop.id,self.materials)
    self.entries[id]={id=id,itemId=drop.id,count=drop.count,key=key,trainingKind=trainingKind,source='drop',position=pos,node=node}
    return id
end

local function visible(self,feet,item)
    local a=feet+Vector3(0,.95,0)
    local b=item.position+Vector3(0,item.source=='site' and .65 or .27,0)
    local hit=obstruction(self,a,b)
    if not hit then return true end
    -- The target's own trunk/rock shell can be the first surface seen.
    return hit~=true and hit.volume and (hit.volume==item.baseCollider or hit.volume==item.upperCollider)
end

local function target(item,dist)
    local name=Catalog.ById[item.itemId].name
    local verb=item.source=='site' and verbs[item.itemId] or '拾取'
    return {id=item.id,key=item.key,itemId=item.itemId,count=item.count,source=item.source,trainingKind=item.trainingKind,
        position=item.position,name=name,verb=verb,distance=math.sqrt(dist)}
end

local function inRange(item,feet)
    if item.spent or item.busy or math.abs(feet.y-item.position.y)>1.25 then return end
    local dist=squareDistance(item.position,feet)
    local radius=item.source=='site' and 2.55 or 2.25
    if dist<=radius*radius then return dist end
end

function R:Nearest(feet)
    local best,distance
    for _,item in pairs(self.entries) do
        local d=inRange(item,feet)
        if d and (not best or d<distance or (d==distance and item.id<best.id)) and visible(self,feet,item) then
            best,distance=item,d
        end
    end
    if best then return target(best,distance) end
end

function R:Claim(id,feet,grant)
    local item=self.entries[id]
    local d=item and inRange(item,feet)
    if not d or not visible(self,feet,item) then return false end
    item.busy=true
    local data=target(item,d)
    local ok,accepted,message=pcall(grant,data)
    item.busy=false
    if not ok then error(accepted,0) end
    if accepted~=true then return false,message end
    if item.key then self.receipts[item.key]=true end
    if item.source=='drop' then
        self.entries[id]=nil
        item.node:Remove()
    else
        item.spent=true
        item.stock:Remove()
        item.stock=nil
        if item.tree then item.remains=Models.Harvested(item.node,item.itemId,self.materials) end
        if item.upperCollider then self.world:RemoveVolume(item.upperCollider) end
        item.upperCollider=nil
    end
    return true,message
end

function R:Refresh()
    if not self.root then return 0 end
    local ruins=rawget(_G,'RUINS')
    if ruins and ruins.world==self.world and ruins.dayNight then
        Models.SetNight(self.materials,ruins.dayNight.nightK)
    end
    if not self.wasClaimed then return 0 end
    local restored=0
    for _,item in pairs(self.entries) do
        if item.source=='site' and item.spent and not self.wasClaimed(item.key,nil) then
            self.receipts[item.key]=nil
            item.spent=false
            if item.remains then item.remains:Remove(); item.remains=nil end
            item.stock=Models.Restock(item.node,item.itemId,self.materials)
            if not item.tree and not item.upperCollider then
                item.upperCollider=collider(self.world,item.position,3,2,.25)
            end
            restored=restored+1
        end
    end
    return restored
end

function R:Destroy()
    for _,item in pairs(self.entries) do
        if item.upperCollider then self.world:RemoveVolume(item.upperCollider) end
        if item.baseCollider then self.world:RemoveVolume(item.baseCollider) end
    end
    if self.root then self.root:Remove() end
    self.root,self.world,self.materials=nil,nil,nil
    self.entries,self.receipts={},{}
end
return R
