-- Small world-space pillar fires. No particle pool, textures, shadows or screen reads.
---@class RuinsNightBraziers
local M={}
M.__index=M

-- Build exports zero-based pillar IDs, not a Lua array. Return a 1-based anchor list.
function M.Anchors(build,baseY)
    local anchors={}
    if not build.colBroken then return anchors end
    local priority={17,5,1,13,9,21,0,12,8,20,4,16,2,14,10,22,6,18,3,15,11,23,7,19}
    for _,id in ipairs(priority) do
        if build.colBroken[id]==nil then
            local a=build.ColAngle(id)
            -- Cap half-width 1.25m, beam radius +/-0.75m. Basin radius .21m:
            -- radial offset 1m leaves .04m beam clearance, stays inside the cap.
            local radius=build.COLONNADE_R+1.0
            anchors[#anchors+1]=Vector3(math.cos(a)*radius,baseY+7.9,math.sin(a)*radius)
            if #anchors==6 then break end
        end
    end
    return anchors
end

---@param scene Scene
---@param anchors Vector3[]
function M.New(scene,anchors,count,lights,detail)
    local self=setmetatable({},M)
    self:Init(scene,anchors,count,lights,detail)
    return self
end

---@param scene Scene
---@param anchors Vector3[]
function M:Init(scene,anchors,count,lights,detail)
    self.count=math.max(0,math.min(6,#anchors,math.floor(count)))
    self.lightCount=math.max(0,math.min(3,self.count,math.floor(lights)))
    self.available,self.disposed,self.level=false,false,0
    self.detail=math.max(0,math.min(1,detail or 1))
    self.sparkCount=self.detail>=0.9 and 4 or 2
    self.fallback=false
    self.batchCount,self.triangleCount=0,0
    ---@type Node|nil
    self.root=nil
    ---@type Material|nil
    self.material=nil
    ---@type Material|nil
    self.basinMaterial=nil
    ---@type Light[]
    self.lights={}
    ---@type Color[]
    self.lightColors={}
    if self.count==0 then return end
    -- Async material loading is required on cold DWP caches too. Nothing visible
    -- or illuminating until the SurfaceShader resource has really arrived.
    self.loading=true
    self.pendingNight,self.pendingClock,self.pendingFog=0,0,false
    local function Build(source)
        ---@cast source Material|nil
        if self.disposed or not self.loading then return end
        self.loading=false
        if not source then return end
        self.material=source:Clone()
        self.root=scene:CreateChild("NightPillarBraziers")
        self.root.enabled=false
        self.basinMaterial=Material:new()
        self.basinMaterial:SetTechnique(0,cache:GetResource("Technique","Techniques/PBR/PBRNoTexture.xml"))
        self.basinMaterial:SetShaderParameter("MatDiffColor",Variant(Color(0.16,0.095,0.045)))
        self.basinMaterial:SetShaderParameter("Roughness",Variant(0.8))
        local basinNode=self.root:CreateChild("BronzeBasins")
        local basin=basinNode:CreateComponent("CustomGeometry")
        basin:BeginGeometry(0,TRIANGLE_LIST)
        local order={1,2,3,1,3,4}
        for i=1,self.count do
            local at=anchors[i]
            local node=self.root:CreateChild("PillarFlame"..i)
            node.position=Vector3(at.x,at.y+0.12,at.z)
            local g=node:CreateComponent("CustomGeometry")
            g:BeginGeometry(0,TRIANGLE_LIST)
            -- Two fixed world planes give the flame thickness. Only the faint
            -- halo faces the camera; unlike sky clouds it is a local sprite.
            for plane=1,3 do
                local halo=plane==3
                local width=halo and 1.6 or 0.45
                local bottom,top=halo and -0.8 or 0,halo and 2.4 or 1.65
                local corners={{-width,bottom},{width,bottom},{width,top},{-width,top}}
                local uv={Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)}
                for _,k in ipairs(order) do
                    local v=corners[k]
                    g:DefineVertex(Vector3(plane==2 and 0 or v[1],v[2],plane==2 and v[1] or 0))
                    g:DefineNormal(Vector3.UP)
                    g:DefineColor(Color(self.fallback and i/7 or i/255,halo and 1 or 0,0,1));g:DefineTexCoord(uv[k])
                end
            end
            if not self.fallback then
                for spark=1,self.sparkCount do
                    for _,k in ipairs(order) do
                        g:DefineVertex(Vector3(0,0.8,0));g:DefineNormal(Vector3.UP)
                        g:DefineColor(Color(i/255,1,spark/5,1))
                        g:DefineTexCoord(Vector2((k==2 or k==3) and 1 or 0,k>=3 and 1 or 0))
                    end
                end
            end
            -- Conservative symmetric bounds for the camera-facing halo.
            for _,s in ipairs({-1,1}) do
                for k=1,3 do
                    g:DefineVertex(Vector3(s*3,s*3,s*3));g:DefineNormal(Vector3.UP)
                    g:DefineColor(Color(0,0,0,0));g:DefineTexCoord(Vector2(0,0))
                end
            end
            g:Commit();g:SetMaterial(self.material)
            g.castShadows,g.occluder,g.occludee=false,false,false
            g.drawDistance=110
            -- Low polygon bronze rim + dark hearth, .21m radius.
            for segment=1,12 do
                local a,b=(segment-1)*math.pi/6,segment*math.pi/6
                local points={Vector3(at.x+math.cos(a)*0.15,at.y,at.z+math.sin(a)*0.15),
                    Vector3(at.x+math.cos(b)*0.15,at.y,at.z+math.sin(b)*0.15),
                    Vector3(at.x+math.cos(b)*0.21,at.y+0.12,at.z+math.sin(b)*0.21),
                    Vector3(at.x+math.cos(a)*0.21,at.y+0.12,at.z+math.sin(a)*0.21)}
                local normal=Vector3(math.cos((a+b)*0.5),-0.5,math.sin((a+b)*0.5)):Normalized()
                for _,k in ipairs({1,3,2,1,4,3}) do basin:DefineVertex(points[k]);basin:DefineNormal(normal) end
                for _,v in ipairs({points[3],points[4],Vector3(at.x,at.y+0.06,at.z)}) do
                    basin:DefineVertex(v);basin:DefineNormal(Vector3.UP)
                end
            end
            if i<=self.lightCount then
                local lampNode=node:CreateChild("WarmPointLight")
                -- Slightly above the flame so the pillar cap is not blown out while the
                -- warm pool still reaches the floor ~6m below (exposure is locked at 1).
                lampNode.position=Vector3(0,0.9,0)
                local light=lampNode:CreateComponent("Light")
                self.lightColors[i]=Color(1,0.50,0.18)
                light.lightType=LIGHT_POINT;light.color=self.lightColors[i]
                light.range,light.brightness,light.castShadows=15,0,false
                light.useTemperature=false;light.affectVolumetricFog=false
                self.lights[#self.lights+1]=light
            end
        end
        basin:Commit();basin:SetMaterial(self.basinMaterial)
        basin.castShadows,basin.occluder=false,false
        self.batchCount,self.triangleCount=self.count+1,self.count*(8+36+(self.fallback and 0 or self.sparkCount*2))
        if not self.fallback then self.material:SetShaderParameter("flame_detail",Variant(self.detail)) end
        self.available=true
        self:Update(self.pendingNight,self.pendingClock,self.pendingFog)
    end
    cache:GetResourceAsync("Material","Materials/RuinsPillarFlameDynamic.xml",function(source)
        if self.disposed or not self.loading then return end
        if source then Build(source);return end
        -- Preserve the approved old material and geometry as an independent
        -- fallback. If both fail, stay hidden rather than bind a white default.
        self.fallback=true
        cache:GetResourceAsync("Material","Materials/RuinsPillarFlame.xml",Build)
    end)
end

function M:Update(night,clock,realFog)
    if self.disposed then return end
    if self.loading then self.pendingNight,self.pendingClock,self.pendingFog=night,clock,realFog;return end
    if not self.available then return end
    local n=math.max(0,math.min(1,night or 0))
    -- DayNight nightK already eases from elevation -.04 to -.22; no sharp dusk switch.
    self.level=n*n*(3-2*n)
    self.root.enabled=self.level>0.002
    if not self.root.enabled then
        for _,light in ipairs(self.lights) do light.brightness=0 end
        return
    end
    self.material:SetShaderParameter("night_strength",Variant(self.level))
    if not self.fallback then self.material:SetShaderParameter("flame_time",Variant(clock)) end
    for i,light in ipairs(self.lights) do
        local phase=i*2.1
        local flicker=0.94+0.04*math.sin(clock*7+phase)+0.02*math.sin(clock*13+phase*1.7)
        light.brightness=self.level*13.0*flicker
        local color=self.lightColors[i]
        color.g=0.48+(flicker-0.88)*0.3
        color.b=0.16+(flicker-0.88)*0.2
        light.color=color
        light.affectVolumetricFog=realFog==true
        light.volumetricFogIntensity=0.35
    end
end

function M:Dispose()
    if self.disposed then return end
    self.disposed,self.loading,self.available=true,false,false
    if self.root then self.root:Dispose() end
    if self.material then self.material:Dispose() end
    if self.basinMaterial then self.basinMaterial:Dispose() end
    self.lights={}
    self.lightColors={}
    self.root,self.material,self.basinMaterial=nil,nil,nil
end
return M
