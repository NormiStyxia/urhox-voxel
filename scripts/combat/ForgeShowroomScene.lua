-- Same main scene/masks; no physics/RTT. Six persistent scene batches.
-- RGB from RuinsPalette.DEF. Coordinates are 0.1m cells; stone jitter is
-- correlated over 0.4m patches (+/-4% per cell), preserving greedy rectangles.
-- Coroutine slices include voxelization, merging and emission. Native Commit
-- remains indivisible; a cooperative 2ms budget cannot promise GPU upload time.
local M={}
local P={stone={.86,.86,.84},stoneB={.82,.82,.81},stoneC={.74,.75,.75},
    marble={.90,.90,.88},blue={.55,.66,.84},dark={.30,.36,.50},moss={.62,.70,.54},
    gold={.95,.74,.32},darkGold={.70,.50,.20},rune={.35,.55,1},runeGold={1,.80,.38},
    crystal={.45,.65,1},grass={.42,.62,.30},grassB={.50,.68,.33},
    tileA={.89,.89,.87},tileB={.84,.84,.83},tileC={.76,.77,.78},
    flower={.96,.95,.90},flowerB={.45,.62,1},flowerY={1,.85,.40},
    bark={.40,.30,.22},leaf={.38,.60,.30},roof={.38,.45,.62},cloud={.95,.96,.98}}
local function Pause(j)
    j.operations=j.operations+1
    if j.operations%64==0 then coroutine.yield() end
end
local function Key(x,y,z) return (x+512)*1048576+(y+512)*1024+z+512 end
local function Grid() return {cells={},list={}} end
local function Put(j,g,x,y,z,color,emissive,faceShade)
    local k=Key(x,y,z)
    if not g.cells[k] then g.list[#g.list+1]={x,y,z} end
    g.cells[k]={color=color,emissive=emissive,faceShade=faceShade}
    Pause(j)
end
local function Box(j,g,x,y,z,w,h,d,c,emissive)
    for a=x,x+w-1 do for b=y,y+h-1 do for t=z,z+d-1 do Put(j,g,a,b,t,c,emissive) end end end
end
local function Disc(j,g,r,y,h,c)
    for x=-r,r-1 do for z=-r,r-1 do
        if (x+.5)^2+(z+.5)^2<=r*r then Box(j,g,x,y,z,1,h,1,c) end
    end end
end
local function Podium(j,g)
    Disc(j,g,24,0,3,'stone');Disc(j,g,19,3,2,'stoneB');Disc(j,g,14,5,2,'marble')
    for x=-17,16 do for z=-17,16 do
        local r=math.sqrt((x+.5)^2+(z+.5)^2)
        if r>=15.5 and r<=16.5 then Put(j,g,x,4,z,'gold') end
        if r<10 then Put(j,g,x,6,z,(math.abs(x)==math.abs(z) or x==0 or z==0) and 'runeGold' or 'rune',true) end
    end end
end
local function Arch(j,g)
    for _,x in ipairs({-26,26}) do
        Box(j,g,x-5,0,17,10,3,10,'stoneC');Box(j,g,x-3,3,19,7,39,7,'marble')
        for _,y in ipairs({10,36}) do Box(j,g,x-4,y,18,9,2,9,'gold') end
        Box(j,g,x-5,40,17,11,3,11,'marble')
    end
    for x=-30,30 do for y=42,71 do
        local r=math.sqrt(x*x+(y-42)^2)
        if r>=23 and r<=29 and not (x>17 and y>56 and (x+y)%11<4) then
            Box(j,g,x,y,19,1,1,7,math.abs(x)<3 and 'gold' or (r<24.5 and 'blue' or 'marble'))
        end
    end end
    for i=0,8 do Box(j,g,-30+i%3,i*3,18,2,2,1,'moss') end
    for i=0,7 do Box(j,g,20+i*2,0,12+i%3*3,2,1+i%3,3,'stoneB') end
    for x=-30,-22 do for y=15,36 do
        if y>16 or (x+30)%3~=0 then
            local c=(x==-30 or x==-22 or y==36) and 'gold' or 'blue'
            if math.abs(x+26)+math.abs(y-27)<=3 then c='marble' end
            Put(j,g,x,y,16,c)
        end
    end end
end
local function Details(j,g,glow)
    for _,cx in ipairs({-19,19}) do
        Box(j,g,cx-4,0,-19,8,2,8,'darkGold');Box(j,g,cx-3,2,-18,6,1,6,'gold')
        for i=1,4 do
            local x,z=cx-3+(i%2)*4,-17+math.floor((i-1)/2)*4
            local h=6+i*2
            for y=0,h do
                local r=math.max(0,2-math.floor(y/(h+1)*3))
                Box(j,glow,x-r,y+3,z-r,r*2+1,1,r*2+1,'crystal',true)
            end
        end
    end
    Box(j,g,16,0,9,9,3,7,'stoneC');Box(j,g,18,3,11,4,5,4,'dark')
    Box(j,g,15,8,9,11,3,7,'dark');Box(j,g,12,9,11,3,1,3,'dark')
    Box(j,glow,19,11,11,3,1,3,'rune',true)
    local tiles={'tileA','tileB','tileC'}
    for x=-45,44 do for z=-45,44 do
        local r=math.sqrt((x+.5)^2+(z+.5)^2)
        if r<44-(math.floor(x/6)+math.floor(z/6))%3 and r>24 and x%6~=0 and z%6~=0 then
            Put(j,g,x,-1,z,tiles[(math.floor(x/6)+math.floor(z/6))%3+1])
        end
    end end
    local flowers={'flower','flowerB','flowerY'}
    for i=1,26 do
        local a=i*2.39996;local x,z=math.floor(math.cos(a)*42),math.floor(math.sin(a)*42)
        Box(j,g,x,0,z,1,2+i%3,1,i%2==0 and 'grass' or 'grassB')
        if i%3==0 then Put(j,g,x,4,z,flowers[(i//3)%3+1]) end
    end
end
local function Islands(j,g)
    for i=1,4 do
        local x=({-95,-45,65,115})[i];local y=({45,90,55,100})[i];local z=({160,230,180,240})[i]
        local radius=({18,22,17,27})[i]
        for level=0,7 do
            local r=math.max(2,math.floor(radius*(1-level/9)))
            for a=-r,r do for b=-r,r do
                if a*a+b*b<=r*r then Box(j,g,x+a,y-level*3,z+b,1,3,1,level==0 and 'grass' or 'stoneC') end
            end end
        end
        if i==1 then
            Box(j,g,x-4,y+3,z-4,8,18,8,'marble');Box(j,g,x-5,y+14,z-5,10,2,10,'gold')
            for h=0,7 do Box(j,g,x-8+h,y+21+h,z-8+h,16-2*h,1,16-2*h,'roof') end
        elseif i==3 then
            Box(j,g,x-2,y+3,z-2,4,17,4,'bark')
            Box(j,g,x-11,y+16,z-9,22,9,18,'leaf');Box(j,g,x-7,y+25,z-6,14,4,12,'grassB')
        end
    end
end
local function Clouds(j,g)
    for i=1,6 do
        local x=-220+i*67;local y=110+i%3*23;local z=260+i%2*80
        Box(j,g,x,y,z,48+i%3*9,5,18,'cloud');Box(j,g,x+9,y+5,z+3,29,6,13,'cloud')
    end
end
local function Jitter(x,y,z)
    local patch=z>140 and 8 or 4 -- distant island stone patches need less contrast frequency
    return ((math.floor(x/patch)*73856093 ~ math.floor(y/patch)*19349663 ~ math.floor(z/patch)*83492791)&0x7fffffff)%3
end
-- Visible face masks -> maximal equal-color rectangles. Sparse cell fields:
-- x/y/z (grid coordinates), color (palette key), emissive, faceShade multiplier.
local function Greedy(j,g,emit,emissionLift)
    local planes={}
    for _,p in ipairs(g.list) do
        local cell=g.cells[Key(p[1],p[2],p[3])]
        for axis=1,3 do for _,sign in ipairs({-1,1}) do
            local n={p[1],p[2],p[3]};n[axis]=n[axis]+sign
            if not g.cells[Key(n[1],n[2],n[3])] then
                local u,v=axis%3+1,(axis+1)%3+1
                local depth=p[axis]+(sign==1 and 1 or 0)
                local key=axis..':'..sign..':'..depth
                local plane=planes[key]
                if not plane then plane={axis=axis,sign=sign,depth=depth,rows={}};planes[key]=plane end
                local row=plane.rows[p[v]];if not row then row={};plane.rows[p[v]]=row end
                row[p[u]]=cell.color..':'..((cell.emissive or cell.color=='cloud') and 1 or Jitter(p[1],p[2],p[3]))..':'..(cell.emissive and 1 or cell.faceShade or 0)
            end
        end end
        Pause(j)
    end
    for _,plane in pairs(planes) do
        local rows=plane.rows
        for v,row in pairs(rows) do for u,token in pairs(row) do
            if token then
                local w,h=1,1
                while row[u+w]==token do w=w+1;Pause(j) end
                while rows[v+h] do
                    local same=true
                    for t=0,w-1 do if rows[v+h][u+t]~=token then same=false;break end end
                    if not same then break end
                    h=h+1;Pause(j)
                end
                for b=v,v+h-1 do for a=u,u+w-1 do rows[b][a]=nil;Pause(j) end end
                local name,jitter,shade=token:match('([^:]+):([^:]+):([^:]+)')
                local base=P[name];local factor=tonumber(shade)
                if factor==0 then factor=plane.axis==2 and (plane.sign==1 and 1 or .6) or (plane.axis==1 and .82 or .74) end
                factor=factor*(.96+tonumber(jitter)*.04)
                local color={base[1]*factor,base[2]*factor,base[3]*factor,1}
                local a,b,c,d={0,0,0},{0,0,0},{0,0,0},{0,0,0}
                local ua,va=plane.axis%3+1,(plane.axis+1)%3+1
                for _,q in ipairs({a,b,c,d}) do q[plane.axis]=plane.depth*.1 end
                a[ua],a[va]=u*.1,v*.1;b[ua],b[va]=(u+w)*.1,v*.1
                c[ua],c[va]=(u+w)*.1,(v+h)*.1;d[ua],d[va]=u*.1,(v+h)*.1
                -- The podium's last two courses are trimmed to a 0.15m cap.
                for _,q in ipairs({a,b,c,d}) do
                    if math.abs(q[1])<=1.4+1e-6 and math.abs(q[3])<=1.4+1e-6 and q[2]>.5 and q[2]<=.7+1e-6 then q[2]=.5+(q[2]-.5)*.75 end
                end
                if emissionLift then for _,q in ipairs({a,b,c,d}) do q[2]=q[2]+.002 end end
                local normal={0,0,0};normal[plane.axis]=plane.sign
                emit(a,b,c,d,color,normal);Pause(j)
            end
        end end
    end
end
local function Clock()
    local ok,t=pcall(function() return time:GetElapsedTime() end)
    if ok and type(t)=='number' and t==t then return t end
    return nil
end
local function MaterialFor(j,kind)
    if j.materials[kind] then return j.materials[kind] end
    local mat=Material:new();j.materials[kind]=mat
    local path=kind=='stone' and 'Techniques/PBR/PBRNoTexture.xml' or 'Techniques/NoTextureUnlit.xml'
    local tech=cache:GetResource('Technique',path);assert(tech,'missing '..path)
    if kind=='halo' then
        tech=tech:Clone('ForgeShowroomAdditive');assert(tech,'missing additive clone');j.technique=tech
        local pass=tech:GetPass('base');assert(pass,'missing additive base pass')
        pass.blendMode=BLEND_ADDALPHA;pass.depthWrite=false
    end
    mat:SetTechnique(0,tech)
    mat.vertexShaderDefines='VERTEXCOLOR';mat.pixelShaderDefines='VERTEXCOLOR';mat.cullMode=CULL_NONE
    mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
    if kind=='stone' then mat:SetShaderParameter('Roughness',Variant(.9));mat:SetShaderParameter('Metallic',Variant(0)) end
    return mat
end
local function Publish(j,kind,produce)
    j.stage=kind
    local node=j.root:CreateChild('RuinsShowroom_'..kind);assert(node,'missing scene mesh node');j.pending=node;node.enabled=false
    local g=node:CreateComponent('CustomGeometry');assert(g,'missing CustomGeometry')
    g.viewMask=j.mask;g.lightMask=j.mask;g.zoneMask=j.mask;g.castShadows=false;g.occluder=false
    local mat=MaterialFor(j,kind)
    g:BeginGeometry(0,TRIANGLE_LIST)
    local triangles=0
    local function Quad(a,b,c,d,color,normal,upperColor)
        local points={a,b,c,a,c,d}
        for index,p in ipairs(points) do
            local rgb=upperColor and (index==3 or index==5 or index==6) and upperColor or color
            g:DefineVertex(Vector3(p[1],p[2],p[3]));g:DefineNormal(Vector3(normal[1],normal[2],normal[3]))
            g:DefineColor(Color(rgb[1],rgb[2],rgb[3],rgb[4] or 1))
        end
        triangles=triangles+2;Pause(j)
        if triangles%16==0 then coroutine.yield() end
    end
    produce(Quad)
    local total=j.triangles-(j.counts[kind] or 0)+triangles
    assert(total+(j.baseCount or 0)<=28000,'scene triangle budget exceeded: '..total)
    coroutine.yield()
    assert(g:Commit()~=false,'scene Commit failed')
    assert(g:SetMaterial(0,mat)~=false,'scene SetMaterial failed')
    local old=j.nodes[kind];if old then old:Remove() end
    j.nodes[kind]=node;j.counts[kind]=triangles;j.triangles=total
    node.enabled=true;j.pending=nil
    if kind=='stone' and j.base then j.base.enabled=false end
    coroutine.yield()
end
local function Sky(j,emit)
    for y=0,11 do for x=0,23 do
        local function Point(a,b)
            local lat=-math.pi/2+b*math.pi/12;local lon=a*math.pi/12
            return {math.cos(lat)*math.cos(lon)*90,math.sin(lat)*90,math.cos(lat)*math.sin(lon)*90}
        end
        local function RGB(b)
            local t=math.max(0,math.sin(-math.pi/2+b*math.pi/12))
            return {.93-.49*t,.90-.25*t,.82+.09*t,1}
        end
        emit(Point(x,y),Point(x+1,y),Point(x+1,y+1),Point(x,y+1),RGB(y),{0,1,0},RGB(y+1));Pause(j)
    end end
end
local function Halo(j,emit)
    for _,sun in ipairs({false,true}) do for band=0,3 do for i=0,31 do
        local function Point(r,a)
            if sun then return {-16+math.cos(a)*r,18+math.sin(a)*r,38} end
            return {math.cos(a)*r,.72,math.sin(a)*r}
        end
        local r0=sun and band*.65 or .72+band*.07
        local r1=sun and (band+1)*.65 or .79+band*.07
        local a,b=i*math.pi/16,(i+1)*math.pi/16
        emit(Point(r0,a),Point(r1,a),Point(r1,b),Point(r0,b),{1,.80,.38,(4-band)*.035},{0,1,0});Pause(j)
    end end end
end
local function Build(j)
    Publish(j,'sky',function(emit) Sky(j,emit) end)
    local base=Grid();Podium(j,base)
    Publish(j,'stone',function(emit) Greedy(j,base,emit) end)
    j.baseReady=true
    -- Hidden base-only mesh permits immediate reliable fallback without rebuild.
    j.base=j.nodes.stone;j.nodes.stone=nil;j.baseCount=j.counts.stone;j.counts.stone=0;j.triangles=j.triangles-j.baseCount
    local g=Grid();Podium(j,g);j.stage='arch';Arch(j,g)
    Publish(j,'stone',function(emit) Greedy(j,g,emit) end);j.base.enabled=false
    local glow=Grid();j.stage='details';Details(j,g,glow)
    -- Unlit blue/gold plate overlays the stone top by 2mm (no coincident faces).
    for x=-10,9 do for z=-10,9 do
        if (x+.5)^2+(z+.5)^2<100 then
            Put(j,glow,x,6,z,(math.abs(x)==math.abs(z) or x==0 or z==0) and 'runeGold' or 'rune',true)
        end
    end end
    Publish(j,'stone',function(emit) Greedy(j,g,emit) end)
    Publish(j,'emission',function(emit) Greedy(j,glow,emit,true) end)
    Publish(j,'halo',function(emit) Halo(j,emit) end)
    local islands=Grid();j.stage='islands';Islands(j,islands)
    Publish(j,'islands',function(emit) Greedy(j,islands,emit) end)
    local clouds=Grid();j.stage='clouds';Clouds(j,clouds)
    Publish(j,'clouds',function(emit) Greedy(j,clouds,emit) end)
    j.complete=true
end
---@param root Node
---@param mask integer
---@return table
function M.Begin(root,mask)
    local j={root=root,mask=mask,nodes={},counts={},materials={},triangles=0,operations=0,elapsed=0,stage='sky'}
    j.thread=coroutine.create(function() Build(j) end)
    return j
end
local function Fallback(j)
    if j.pending then j.pending:Remove();j.pending=nil end
    if j.base then
        for kind,node in pairs(j.nodes) do if kind~='sky' then node:Remove();j.nodes[kind]=nil;j.counts[kind]=nil end end
        j.nodes.stone=j.base;j.base.enabled=true;j.base=nil
        j.counts.stone=j.baseCount;j.triangles=(j.counts.sky or 0)+j.baseCount
    end
end
---@param j table
---@param budgetMs number
---@return string? error
function M.Step(j,budgetMs)
    if j.complete or j.failed then return nil end
    local start=Clock()
    for _=1,32 do
        local ok,err=coroutine.resume(j.thread)
        if not ok then
            j.failed=true;j.thread=nil;Fallback(j)
            return 'scene '..j.stage..': '..tostring(err)
        end
        if coroutine.status(j.thread)=='dead' then j.thread=nil;return nil end
        local now=Clock()
        if not start or not now or now-start>=budgetMs/1000 then break end
    end
    return nil
end
---@param j table
---@param dt number
local function Animate(j,dt)
    j.elapsed=j.elapsed+dt
    local islands,clouds=j.nodes.islands,j.nodes.clouds
    -- One moving batch per group: shared phase saves draw calls, no mesh edits.
    if islands then islands.position=Vector3(0,math.sin(j.elapsed*math.pi*2/7)*.12,0) end
    if clouds then clouds.position=Vector3((j.elapsed*.075+16)%32-16,0,0) end
    if j.nodes.emission then
        local k=.92+.08*math.sin(j.elapsed*math.pi/2)
        j.materials.emission:SetShaderParameter('MatDiffColor',Variant(Color(k,k,k,1)))
    end
end
---@param j table
---@param dt number
---@return string?
function M.Animate(j,dt)
    if j.failed then return nil end
    local ok,err=pcall(Animate,j,dt)
    if not ok then j.failed=true;j.thread=nil;Fallback(j);return 'animation: '..tostring(err) end
end
---@param j table?
function M.Dispose(j)
    if not j or j.disposed then return end
    j.disposed=true;j.thread=nil
    if j.pending then j.pending:Remove();j.pending=nil end
    for _,node in pairs(j.nodes) do node:Remove() end
    if j.base then j.base:Remove();j.base=nil end
    for _,mat in pairs(j.materials) do mat:Dispose() end
    if j.technique then j.technique:Dispose();j.technique=nil end
    j.nodes={};j.materials={};j.counts={};j.triangles=0
end
return M
