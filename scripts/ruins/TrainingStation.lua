-- Independent world prop and HUD overlay. The scene owns proximity, the F key,
-- and its gameplay input gate. Optional onOpenChanged(open) also fires for taps.
local UI = require('urhox-libs/UI')
local Touch = require('ui.TouchInput')
local Station = {}
Station.__index = Station

local opponents = {
    {'WoodSpirit', '木灵', '地面小怪：顶撞、跃扑。收根时向侧面移开。'},
    {'NestWeaver', '织巢虫', '飞虫：前钩交剪、张鞘射丝。空中可用弓射，侧移躲丝线。'},
    {'RockColossus', '岩甲巨兽', '举拳时侧闪出前方红色石柱带，肩晶可用弓射。'},
    {'RuinConstruct', '遗迹构装体', '激光后露核：双臂合拢锁线，横移躲开再射核心。'},
    {'TimeWraith', '时蚀灵体', '时缓场：环内约半速，离开圈后恢复。'},
}
local timber = {
    {87,56,44,.95}, {142,91,60,.90}, {213,158,95,.77},
    {165,111,66,.84}, {201,170,112,.98}, {152,123,75,.97},
}
local function endGrain(radius, outer)
    if radius>outer-.7 then return 1 end
    if math.floor(radius*1.35)%3==0 then return 4 end
    return 3
end

-- Authored on a 7 cm grid. The forward-facing slice and both sawn ends use
-- rings in the local cutting plane. Two projecting rope turns wrap the post.
local function wood(x,y,z)
    local r=math.sqrt(x*x+z*z)
    local azimuth=math.atan(z,x)
    local edge=5.55+.35*math.sin(azimuth*5+.5)
    local band=math.floor(y+.7*math.sin(azimuth))
    if (band==6 or band==8) and r<=edge+.72 then
        return (math.floor(azimuth*8+band)%4==0) and 6 or 5
    end
    if z>=3 and z<=6.5 then
        local disk=math.sqrt(x*x+(y-15)^2)
        if disk<=4.9 then return z<5.5 and 1 or endGrain(disk,4.9) end
    end
    if y<22 and r<=edge then
        if y>21 then return endGrain(math.sqrt((x+.55)^2+(z-.35)^2),edge) end
        return (math.floor(azimuth*5+.21*math.sin(y*.31))%3==0) and 1 or 2
    end
    local arm=math.abs(x)
    if arm>4 and arm<12 then
        local d=math.sqrt((y-13.0-(arm-4)*.25)^2+(z+.5)^2)
        if d<=2.45 then
            if arm>11 then return endGrain(d,2.45) end
            if arm>8 and arm<10 then return 5 end
            return d>1.3 and 2 or 1
        end
    end
    if y<3.5 and (x*x+(z*.66)^2<44 or (x*.68)^2+z*z<40) then return 1 end
end
local faces={
    {1,0,0,{1,0,0},{1,1,0},{1,1,1},{1,0,1}}, {-1,0,0,{0,0,1},{0,1,1},{0,1,0},{0,0,0}},
    {0,1,0,{0,1,1},{1,1,1},{1,1,0},{0,1,0}}, {0,-1,0,{0,0,0},{1,0,0},{1,0,1},{0,0,1}},
    {0,0,1,{1,0,1},{1,1,1},{0,1,1},{0,0,1}}, {0,0,-1,{0,0,0},{0,1,0},{1,1,0},{1,0,0}},
}
local triangles={4,5,6,4,6,7}
local function cellKey(x,y,z) return (y*64+z)*64+x end
local function makePost(scene,position)
    local node=scene:CreateChild('TrainingStation')
    node.position=position
    local occupied,geometries={},{}
    for i=1,#timber do
        local part=node:CreateChild('Timber_'..i)
        local geom=part:CreateComponent('CustomGeometry')
        geom:BeginGeometry(0,TRIANGLE_LIST)
        geom.castShadows=true
        geometries[i]=geom
    end
    for y=0,21 do for z=-10,9 do for x=-12,11 do
        occupied[cellKey(x,y,z)]=wood(x+.5,y+.5,z+.5)
    end end end
    for y=0,21 do for z=-10,9 do for x=-12,11 do
        local material=occupied[cellKey(x,y,z)]
        if material then
            local geom=geometries[material]
            for _,f in ipairs(faces) do
                if not occupied[cellKey(x+f[1],y+f[2],z+f[3])] then
                    local n=Vector3(f[1],f[2],f[3])
                    for _,j in ipairs(triangles) do
                        local v=f[j]
                        geom:DefineVertex(Vector3((x+v[1])*.07,(y+v[2])*.07,(z+v[3])*.07))
                        geom:DefineNormal(n)
                    end
                end
            end
        end
    end end end
    local technique=cache:GetResource('Technique','Techniques/PBR/PBRNoTexture.xml')
    for i,c in ipairs(timber) do
        local mat=Material:new()
        mat:SetTechnique(0,technique)
        mat:SetShaderParameter('MatDiffColor',Variant(Color(c[1]/255,c[2]/255,c[3]/255,1)))
        mat:SetShaderParameter('Roughness',Variant(c[4]))
        mat:SetShaderParameter('Metallic',Variant(0))
        geometries[i]:Commit()
        geometries[i]:SetMaterial(mat)
    end
    return node
end

local ink={35,43,52,255}
local parchment={238,223,190,255}
local brass={181,143,85,255}
local function detach(parent,widget)
    if widget then parent:RemoveChild(widget); widget:Destroy() end
end
local function label(text,size,color)
    return UI.Label{text=text,fontSize=size,fontColor=color,whiteSpace='normal',pointerEvents='none',
        minWidth=0,flexShrink=1,flexGrow=1}
end

function Station.New(scene,position,onSelect,onClear)
    return setmetatable({node=makePost(scene,position),onSelect=onSelect,onClear=onClear,near=false},Station)
end
function Station:IsOpen() return self.layer~=nil end

function Station:SetNear(near)
    if self.destroyed then return end
    self.near=near==true
    local root=UI.GetRoot()
    if self.layer and (not self.near or root~=self.root) then self:Close() end
    local show=self.near and not self.layer and root~=nil
    if self.prompt and (not show or self.promptRoot~=root) then
        detach(self.promptRoot,self.prompt); self.prompt,self.promptRoot=nil,nil
    end
    if show and not self.prompt then
        local safe=UI.GetSafeAreaInsets()
        local prompt=UI.Button{id='training_station_open',position='absolute',right=20+safe.right,bottom=128+safe.bottom,
            text=Touch.IsEnabled() and '训练木桩' or '训练木桩  [F]',fontSize=15,height=46,minWidth=150,
            backgroundColor=ink,fontColor=parchment,borderWidth=1,borderColor=brass,
            onClick=function() self:Interact() end}
        root:AddChild(prompt); self.promptRoot,self.prompt=root,prompt
    end
end

-- Retired widgets can still receive the rest of a pointer dispatch. The
-- session token also guards against callbacks which close or destroy us.
function Station:Choose(session,index)
    if self.layer~=session or not session or self.choosing then return false end
    self.choosing=true
    local ok,err
    if index then ok,err=pcall(self.onSelect,opponents[index][1])
    else ok,err=pcall(self.onClear) end
    if self.layer==session then self:Close() end
    self.choosing=false
    if not ok then error(err,0) end
    return true
end

function Station:Interact()
    if self.destroyed or self.layer or not self.near then return false end
    local root=UI.GetRoot()
    if not root or UI.GetTopOverlay() then return false end
    local safe=UI.GetSafeAreaInsets()
    local layer=UI.Panel{id='training_station_panel',position='absolute',left=0,top=0,width='100%',height='100%',
        pointerEvents='auto',alignItems='center',justifyContent='center',backgroundColor={16,21,28,182},
        paddingTop=8+safe.top,paddingBottom=8+safe.bottom,paddingLeft=12+safe.left,paddingRight=12+safe.right}
    local rows={}
    local touch=Touch.IsEnabled()
    for i,option in ipairs(opponents) do
        local function pick() self:Choose(layer,i) end
        local row=UI.Panel{flexDirection='row',alignItems='center',width='100%',minHeight=49,flexShrink=0,
            gap=10,paddingRight=6,borderBottomWidth=1,borderColor=brass,pointerEvents='auto',onClick=pick,
            children={UI.Button{text=touch and option[2] or (i..'  '..option[2]),fontSize=14,width=112,minHeight=44,flexShrink=0,
                backgroundColor=ink,fontColor=parchment,onClick=pick},label(option[3],14,ink)}}
        rows[#rows+1]=row
    end
    local function close() if self.layer==layer then self:Close() end end
    local card=UI.Panel{width='100%',maxWidth=530,height='100%',maxHeight=428,padding=12,gap=8,
        backgroundColor=parchment,borderWidth=2,borderColor=brass,children={
            UI.Label{text='选择训练对手',fontSize=22,fontColor=ink,flexShrink=0,pointerEvents='none'},
            UI.ScrollView{width='100%',flexGrow=1,flexBasis=0,flexShrink=1,minHeight=0,scrollY=true,
                children={UI.Panel{width='100%',gap=4,children=rows}}},
            UI.Panel{flexDirection='row',gap=8,flexShrink=0,children={
                UI.Button{text='清场',height=44,flexGrow=1,variant='secondary',onClick=function() self:Choose(layer,nil) end},
                UI.Button{text=touch and '关闭' or '关闭  [Esc]',height=44,flexGrow=1,variant='secondary',onClick=close},
            }},
        }}
    layer:AddChild(card)
    self.root,self.layer=root,layer
    self:SetNear(true)
    root:AddChild(layer); UI.PushOverlay(layer)
    Touch.Clear()
    if self.onOpenChanged then
        self.onOpenChanged(true)
    elseif input then
        self.savedMouseMode=input.mouseMode
        input.mouseMode=MM_ABSOLUTE
    end
    return true
end

-- Let the scene dispatch keys before gameplay hotkeys. UI buttons handle the
-- same choices via mouse, touch and ordinary focused-button activation.
function Station:HandleKey(key,repeated)
    local session=self.layer
    if not session then return false end
    if repeated then return true end
    if key==KEY_ESCAPE then self:Close()
    elseif key>=KEY_1 and key<=KEY_5 then self:Choose(session,key-KEY_1+1) end
    return true
end
function Station:Close()
    local layer,root=self.layer,self.root
    if not layer then return end
    self.layer,self.root=nil,nil
    UI.PopOverlay(layer); detach(root,layer)
    Touch.Clear()
    self:SetNear(self.near)
    if self.savedMouseMode~=nil then
        if input.mouseMode==MM_ABSOLUTE then input.mouseMode=self.savedMouseMode end
        self.savedMouseMode=nil
    end
    if self.onOpenChanged then self.onOpenChanged(false) end
end
function Station:Destroy()
    if self.destroyed then return end
    self.destroyed,self.near=true,false
    self:Close()
    detach(self.promptRoot,self.prompt); self.prompt,self.promptRoot=nil,nil
    self.node:Remove(); self.node=nil
    self.onSelect,self.onClear,self.onOpenChanged=nil,nil,nil
end
return Station
