-- Same main scene/masks; no physics/RTT. Eight scene batches (seven on low).
-- RGB from RuinsPalette.DEF. Authoring boxes use 10cm units; high foreground
-- refines to 5cm before masonry/chips/AO. Greedy faces interpolate +/-2% lattice
-- vertex noise inside a brick; mortar, cracks and corner chips retain 5cm detail.
-- Coroutine slices include voxelization, merging and emission. Native Commit
-- remains indivisible; a cooperative 2ms budget cannot promise GPU upload time.
local M={}
-- High: 5cm foreground; low: 10cm, fewer islands/clouds and no atmospheric cards.
local P={stone={.86,.86,.84},stoneB={.82,.82,.81},stoneC={.74,.75,.75},stoneD={.66,.67,.68},marbleB={.85,.85,.84},
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
local function Grid(cell) return {cells={},list={},cell=cell or .1} end
local function Put(j,g,x,y,z,color,emissive,faceShade)
    local k=Key(x,y,z)
    if not g.cells[k] then g.list[#g.list+1]={x,y,z} end
    g.cells[k]={color=color,emissive=emissive,faceShade=faceShade,feature=g.feature}
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
    g.hasPodium=true;g.feature='podium'
    Disc(j,g,24,0,3,'stone');Disc(j,g,19,3,2,'stoneB');Disc(j,g,14,5,2,'marble')
    for x=-17,16 do for z=-17,16 do
        local r=math.sqrt((x+.5)^2+(z+.5)^2)
        if r>=15.5 and r<=16.5 then Put(j,g,x,4,z,'gold') end
        if r<10 then Put(j,g,x,6,z,(math.abs(x)==math.abs(z) or x==0 or z==0) and 'runeGold' or 'rune',true) end
    end end
    g.feature=nil
end
local function Arch(j,g)
    for _,x in ipairs({-26,26}) do
        Box(j,g,x-5,0,17,10,3,10,'stoneC');Box(j,g,x-3,3,19,7,39,7,'marble')
        for _,y in ipairs({10,36}) do Box(j,g,x-4,y,18,9,2,9,'gold') end
        Box(j,g,x-5,40,17,11,3,11,'marble')
    end
    g.hasArch=true;g.feature='archCurve'
    for x=-30,30 do for y=42,71 do
        local r=math.sqrt(x*x+(y-42)^2)
        if r>=23 and r<=29 and not (x>17 and y>56 and (x+y)%11<4) then
            Box(j,g,x,y,19,1,1,7,math.abs(x)<3 and 'gold' or (r<24.5 and 'blue' or 'marble'))
        end
    end end
    g.feature=nil
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
            glow.crystals=glow.crystals or {};glow.crystals[#glow.crystals+1]={x=x,z=z,h=h}
            glow.feature='crystal'
            for y=0,h do
                local r=math.max(0,2-math.floor(y/(h+1)*3))
                Box(j,glow,x-r,y+3,z-r,r*2+1,1,r*2+1,'crystal',true)
            end
            glow.feature=nil
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
    for i=1,(j.low and 3 or 4) do
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
    for i=1,(j.low and 4 or 6) do
        local x=-220+i*67;local y=110+i%3*23;local z=260+i%2*80
        Box(j,g,x,y,z,48+i%3*9,5,18,'cloud');Box(j,g,x+9,y+5,z+3,29,6,13,'cloud')
    end
end
local function Hash(seed,x,y,z)
    return ((x*73856093 ~ y*19349663 ~ z*83492791 ~ seed*2654435761)&0x7fffffff)
end
local STONE={stone=true,stoneB=true,stoneC=true,stoneD=true,marble=true,marbleB=true}
local function Occupied(g,x,y,z) return g.cells[Key(x,y,z)]~=nil end
local function Surface(g,p)
    local x,y,z=p[1],p[2],p[3]
    return not Occupied(g,x+1,y,z) or not Occupied(g,x-1,y,z) or not Occupied(g,x,y+1,z)
        or not Occupied(g,x,y-1,z) or not Occupied(g,x,y,z+1) or not Occupied(g,x,y,z-1)
end
-- Staggered 20/30cm courses and 30/40/60cm brick widths, 20cm depths.
-- Mortar is a real 5cm-wide dark course. Corner chips remove only exposed cells.
local function Masonry(j,g)
    local seed=j.seed
    local missing={}
    for _,p in ipairs(g.list) do
        local x,y,z=p[1],p[2],p[3];local cell=g.cells[Key(x,y,z)]
        if cell and STONE[cell.color] and Surface(g,p) then
            local yy=y%14;local row=y//14*3+(yy<4 and 0 or yy<8 and 1 or 2)
            local rowY=yy<4 and yy or yy<8 and yy-4 or yy-8
            local rowH=yy<8 and 4 or 6
            local width=({8,12,6})[row%3+1]
            local bx=(x+row%2*(width//2))//width;local bz=(z+row%2*2)//4
            local lx=(x+row%2*(width//2))%width;local lz=(z+row%2*2)%4
            local h=Hash(seed,bx,row,bz)
            local mortar=rowY==0 or lx==0 or lz==0
            local corner=(rowY==0 or rowY==rowH-1) and (lx==0 or lx==width-1) and (lz==0 or lz==3)
            if (corner and h%10==0) or (h%41==0 and (lx==2 or lx==3) and (rowY==2 or rowY==3)) then
                missing[#missing+1]={x,y,z};j.chips=j.chips+1
            else
                local marble=cell.color=='marble' or cell.color=='marbleB'
                local palette=marble and (h%2==0 and 'marble' or 'marbleB') or ({'stone','stoneB','stoneC','stoneD'})[h%4+1]
                local factor=.95+(h%11)*.01
                local style='plain'
                if mortar then factor=factor*.86;style='joint';j.joints=j.joints+1
                elseif not Occupied(g,x,y+1,z) and (not Occupied(g,x+1,y,z) or not Occupied(g,x-1,y,z)
                    or not Occupied(g,x,y,z+1) or not Occupied(g,x,y,z-1)) then factor=factor*1.06;style='rim'
                elseif rowY==rowH-1 then factor=factor*1.06;style='edge'
                elseif rowY==1 then factor=factor*.95;style='lower' end
                -- A bounded random walk in brick-local coordinates, seeded per brick.
                local walk=h%math.max(1,width-2)+1
                for step=1,rowY do walk=math.max(1,math.min(width-2,walk+Hash(seed,bx,step,bz)%3-1)) end
                if h%7==0 and lx==walk and not mortar then factor=factor*.64;style='crack';j.cracks=j.cracks+1 end
                -- Patch centers fade across 3 voxels on top/shaded surfaces.
                local mh=Hash(seed,x//9,y//9,z//9)
                local distance=math.max(math.abs(x%9-4),math.abs(y%9-4),math.abs(z%9-4))
                local moss=(mh%9==0 and distance<=3 and (not Occupied(g,x,y+1,z) or not Occupied(g,x-1,y,z)))
                    and (4-distance)/4*.65 or 0
                local name=palette..'_'..(h%11)..'_'..style..'_'..math.floor(moss*100)
                if not P[name] then
                    local rgb=P[palette];local green=P.moss
                    P[name]={rgb[1]*factor*(1-moss)+green[1]*moss,rgb[2]*factor*(1-moss)+green[2]*moss,rgb[3]*factor*(1-moss)+green[3]*moss}
                end
                cell.color=name;cell.stone=true;cell.noise=true
                if moss>0 then j.moss=j.moss+1 end
            end
        elseif cell and (cell.color=='gold' or cell.color=='darkGold') then
            if y%4==0 then cell.color='darkGold' end -- two-tone lower course + engraved line
        end
        Pause(j)
    end
    -- Remove after surface classification, so a chip cannot recursively tunnel
    -- through the solid. Its newly exposed inner stone is intentionally darker.
    local directions={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
    P.stoneCore={.66*.78,.67*.78,.68*.78}
    for _,p in ipairs(missing) do g.cells[Key(p[1],p[2],p[3])]=nil;Pause(j) end
    for _,p in ipairs(missing) do
        for _,d in ipairs(directions) do
            local cell=g.cells[Key(p[1]+d[1],p[2]+d[2],p[3]+d[3])]
            if cell and (cell.stone or STONE[cell.color]) then cell.color='stone_core';cell.stone=true end
        end
        Pause(j)
    end
    P.stone_core=P.stoneCore
end
-- Re-evaluate curved silhouettes on the 5cm lattice; subdivision alone would
-- retain the previous 10cm stair steps. Preserve independently authored props.
local function Profiles(j,g,source)
    for _,p in ipairs(g.list) do
        local c=g.cells[Key(p[1],p[2],p[3])]
        if c then
            local x,y,z=p[1],p[2],p[3]
            local remove=false
            if c.feature=='podium' then
                local r=y<6 and 48 or y<10 and 38 or 28
                remove=(x+.5)^2+(z+.5)^2>r*r or y>=13
            elseif c.feature=='archCurve' then
                local r=math.sqrt((x+.5)^2+(y-84+.5)^2)
                remove=r<46 or r>58
            elseif c.feature=='crystal' then remove=true end
            if remove then g.cells[Key(x,y,z)]=nil end
        end
        Pause(j)
    end
    if source.hasPodium then
        for x=-48,47 do for z=-48,47 do
            local r=math.sqrt((x+.5)^2+(z+.5)^2)
            local h=r<=28 and 13 or r<=38 and 10 or r<=48 and 6 or 0
            for y=0,h-1 do
                if not g.cells[Key(x,y,z)] then
                    local c=y<6 and 'stone' or y<10 and 'stoneB' or 'marble'
                    if (y==8 or y==9) and r>=31 and r<=33 then c='gold' end
                    if y==12 and r<20 then c=(x==0 or z==0 or math.abs(x)==math.abs(z)) and 'runeGold' or 'rune' end
                    Put(j,g,x,y,z,c,c=='rune' or c=='runeGold')
                end
                Pause(j)
            end
        end end
    end
    if source.hasArch then
        for x=-58,58 do for y=84,142 do
            local r=math.sqrt((x+.5)^2+(y-84+.5)^2)
            local missing=x>34 and y>112 and (x//2+y//2)%11<4
            if r>=46 and r<=58 and not missing then
                local c=math.abs(x)<6 and 'gold' or r<49 and 'blue' or 'marble'
                for z=38,51 do if not g.cells[Key(x,y,z)] then Put(j,g,x,y,z,c) end end
            end
            Pause(j)
        end end
    end
    for _,c in ipairs(source.crystals or {}) do
        for y=0,c.h*2 do
            local r=math.max(0,4-math.floor(y/(c.h*2+1)*5))
            Box(j,g,c.x*2-r,y+6,c.z*2-r,r*2+1,1,r*2+1,'crystal',true)
        end
    end
end

local function Refine(j,source)
    if j.low then return source,Grid() end
    local fine,coarse=Grid(.05),Grid(.1)
    for _,p in ipairs(source.list) do
        local cell=source.cells[Key(p[1],p[2],p[3])]
        if cell then
            fine.feature=cell.feature
            -- Plaza/grass remain 10cm; all architecture/metal/crystal is 5cm.
            if p[2]<0 or math.abs(p[1])>35 or math.abs(p[3])>30 then
                Put(j,coarse,p[1],p[2],p[3],cell.color,cell.emissive,cell.faceShade)
            else
                for a=0,1 do for b=0,1 do for c=0,1 do
                    local x,y,z=p[1]*2+a,p[2]*2+b,p[3]*2+c
                    if not (y==13 and math.abs(x)<28 and math.abs(z)<28) then
                        local color=cell.color
                        if (color=='rune' or color=='runeGold') and y==12 and x*x+z*z<400 then
                            color=(x==0 or z==0 or math.abs(x)==math.abs(z)) and 'runeGold' or 'rune'
                        end
                        Put(j,fine,x,y,z,color,cell.emissive,cell.faceShade)
                    end
                end end end
            end
        end
    end
    fine.feature=nil
    Profiles(j,fine,source)
    Masonry(j,fine)
    return fine,coarse
end
local function VertexShade(j,g,plane,u,v,w,h,rgb,stone)
    local colors={}
    for i,corner in ipairs({{0,0},{1,0},{1,1},{0,1}}) do
        local cu,cv=u+corner[1]*w,v+corner[2]*h
        local owner={0,0,0};local ua,va=plane.axis%3+1,(plane.axis+1)%3+1
        owner[plane.axis]=plane.depth-(plane.sign==1 and 1 or 0)
        owner[ua]=cu-corner[1];owner[va]=cv-corner[2]
        local outside={owner[1],owner[2],owner[3]};outside[plane.axis]=outside[plane.axis]+plane.sign
        local su,sv=corner[1]==1 and 1 or -1,corner[2]==1 and 1 or -1
        local function Sample(a,b)
            local q={outside[1],outside[2],outside[3]};q[ua]=q[ua]+a;q[va]=q[va]+b
            return Occupied(g,q[1],q[2],q[3]) and 1 or 0
        end
        local count=Sample(su,0)+Sample(0,sv)+Sample(su,sv)
        if owner[2]*g.cell<.12 then count=math.max(count,1) end
        local ao=stone and (1-.35*count/3) or 1
        local noise=stone and (.98+Hash(j.seed,owner[1],owner[2],owner[3])%5*.01) or 1
        local k=ao*noise
        if ao<1 then j.aoVertices=j.aoVertices+1 end
        colors[i]={rgb[1]*k,rgb[2]*k,rgb[3]*k,1}
    end
    return colors
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
        if cell then
        for axis=1,3 do for _,sign in ipairs({-1,1}) do
            local n={p[1],p[2],p[3]};n[axis]=n[axis]+sign
            if not g.cells[Key(n[1],n[2],n[3])] then
                local u,v=axis%3+1,(axis+1)%3+1
                local depth=p[axis]+(sign==1 and 1 or 0)
                local key=axis..':'..sign..':'..depth
                local plane=planes[key]
                if not plane then plane={axis=axis,sign=sign,depth=depth,rows={}};planes[key]=plane end
                local row=plane.rows[p[v]];if not row then row={};plane.rows[p[v]]=row end
                row[p[u]]=cell.color..':'..((cell.emissive or cell.stone or cell.color=='cloud') and 1 or Jitter(p[1],p[2],p[3]))..':'..(cell.emissive and 1 or cell.faceShade or 0)
            end
        end end
        end
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
                for _,q in ipairs({a,b,c,d}) do q[plane.axis]=plane.depth*g.cell end
                a[ua],a[va]=u*g.cell,v*g.cell;b[ua],b[va]=(u+w)*g.cell,v*g.cell
                c[ua],c[va]=(u+w)*g.cell,(v+h)*g.cell;d[ua],d[va]=u*g.cell,(v+h)*g.cell
                -- The podium's last two courses are trimmed to a 0.15m cap.
                for _,q in ipairs({a,b,c,d}) do
                    if g.cell==.1 and math.abs(q[1])<=1.4+1e-6 and math.abs(q[3])<=1.4+1e-6 and q[2]>.5 and q[2]<=.7+1e-6 then q[2]=.5+(q[2]-.5)*.75 end
                end
                if emissionLift then for _,q in ipairs({a,b,c,d}) do q[2]=q[2]+.002 end end
                local normal={0,0,0};normal[plane.axis]=plane.sign
                local stone=name:find('_',1,true)~=nil
                local corners=VertexShade(j,g,plane,u,v,w,h,color,stone)
                emit(a,b,c,d,color,normal,nil,corners);Pause(j)
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
    local path=(kind=='stone' or kind=='arch') and 'Techniques/PBR/PBRNoTexture.xml' or 'Techniques/NoTextureUnlit.xml'
    local tech=cache:GetResource('Technique',path);assert(tech,'missing '..path)
    if kind=='halo' or kind=='atmosphere' then
        tech=tech:Clone('ForgeShowroomAdditive');assert(tech,'missing additive clone');j.techniques[#j.techniques+1]=tech
        local pass=tech:GetPass('base');assert(pass,'missing additive base pass')
        pass.blendMode=BLEND_ADDALPHA;pass.depthWrite=false
    end
    mat:SetTechnique(0,tech)
    mat.vertexShaderDefines='VERTEXCOLOR';mat.pixelShaderDefines='VERTEXCOLOR';mat.cullMode=CULL_NONE
    mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
    if kind=='stone' or kind=='arch' then mat:SetShaderParameter('Roughness',Variant(.9));mat:SetShaderParameter('Metallic',Variant(0)) end
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
    local function Quad(a,b,c,d,color,normal,upperColor,cornerColors)
        local points={a,b,c,a,c,d}
        for index,p in ipairs(points) do
            local rgb=cornerColors and cornerColors[({1,2,3,1,3,4})[index]] or upperColor and (index==3 or index==5 or index==6) and upperColor or color
            g:DefineVertex(Vector3(p[1],p[2],p[3]));g:DefineNormal(Vector3(normal[1],normal[2],normal[3]))
            if kind=='arch' or kind=='islands' or kind=='clouds' then
                local grey=rgb[1]*.2126+rgb[2]*.7152+rgb[3]*.0722
                g:DefineColor(Color((rgb[1]*.90+grey*.10)*1.04,(rgb[2]*.90+grey*.10)*1.04,(rgb[3]*.90+grey*.10)*1.04,rgb[4] or 1))
            else g:DefineColor(Color(rgb[1],rgb[2],rgb[3],rgb[4] or 1)) end
        end
        triangles=triangles+2;Pause(j)
        if triangles%16==0 then coroutine.yield() end
    end
    produce(Quad)
    local total=j.triangles-(j.counts[kind] or 0)+triangles
    assert(total<=55000,'scene triangle budget exceeded: '..total)
    coroutine.yield()
    assert(g:Commit()~=false,'scene Commit failed')
    assert(g:SetMaterial(0,mat)~=false,'scene SetMaterial failed')
    local old=j.nodes[kind];if old then old:Remove() end
    j.nodes[kind]=node;j.counts[kind]=triangles;j.triangles=total
    node.enabled=true;j.pending=nil
    if (kind=='stone' or kind=='arch') and j.base then j.base.enabled=false end
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
    for layer=1,3 do
        local r=1+layer*.06
        for i=0,31 do
            local a,b=i*math.pi/16,(i+1)*math.pi/16
            emit({math.cos(a),.656,math.sin(a)},{math.cos(a)*r,.656,math.sin(a)*r},
                {math.cos(b)*r,.656,math.sin(b)*r},{math.cos(b),.656,math.sin(b)},
                {.35,.55,1,(4-layer)*.012},{0,1,0})
        end
    end
    for _,x in ipairs({-1.9,1.9}) do for layer=1,3 do
        local r=.3+layer*.11
        emit({x-r,.9-r,-1.92},{x+r,.9-r,-1.92},{x+r,.9+r,-1.92},{x-r,.9+r,-1.92},
            {.45,.65,1,(4-layer)*.018},{0,0,-1})
    end end
    if not j.low then
        for beam=1,2 do for layer=1,3 do
            local x=-2.6+(beam-1)*.6;local w=layer*.09
            emit({x-w,6.8,1.6},{x+w,6.8,1.6},{x+2+w,.75,-.6},{x+2-w,.75,-.6},
                {1,.80,.38,(4-layer)*.006},{0,0,-1})
        end end
    end
end
local function Vines(j,g)
    local step=g.cell
    for i=1,(j.low and 2 or 5) do
        local x=-2.2+(i-1)*.95
        local y=4.2+math.sqrt(math.max(0,2.6^2-x*x))
        local cx,cy,cz=math.floor(x/step),math.floor(y/step),math.floor(1.8/step)
        local length=math.floor((.4+(Hash(j.seed,i,0,0)%9)*.1)/step)
        for n=0,length do
            local dx=math.floor(n/5)%3-1
            Put(j,g,cx+dx,cy-n,cz,'moss')
            if n%5==0 then Put(j,g,cx+dx+1,cy-n,cz,'leaf') end
        end
    end
end
local function Atmosphere(j,emit)
    -- A single pooled batch: 24 small additive squares rise together; no re-emission.
    for i=1,24 do
        local x=(Hash(j.seed,i,1,1)%100)/100*5-2.5
        local y=.8+(Hash(j.seed,i,2,1)%100)/100*3.6
        local z=(Hash(j.seed,i,3,1)%100)/100*2
        local r=.012+(i%3)*.006
        emit({x-r,y-r,z},{x+r,y-r,z},{x+r,y+r,z},{x-r,y+r,z},{1,.80,.38,.18},{0,0,-1})
    end
end
local function Stage(j,name,fn)
    j.stage=name
    local ok,err=pcall(fn) -- Lua 5.4 permits yielding through pcall
    if not ok then
        if j.pending then j.pending:Remove();j.pending=nil end
        -- A failed first material setup must never become the cached material
        -- of a later successful stage (e.g. the base and detail stone passes).
        local kind=j.stage
        if not j.nodes[kind] and j.materials[kind] then
            pcall(function() j.materials[kind]:Dispose() end);j.materials[kind]=nil
        end
        j.skipped[name]=true
        j.errors[#j.errors+1]='scene '..name..': '..tostring(err)
        coroutine.yield() -- report this stage before advancing to another
    end
end
local function Build(j)
    Stage(j,'sky',function() Publish(j,'sky',function(emit) Sky(j,emit) end) end)
    local base=Grid();Podium(j,base)
    Stage(j,'stone',function()
        local fine,coarse=Refine(j,base)
        Publish(j,'stone',function(emit) Greedy(j,fine,emit);Greedy(j,coarse,emit) end)
        j.baseReady=true
    end)
    Stage(j,'arch',function()
        local arch=Grid();Arch(j,arch)
        local fine,coarse=Refine(j,arch);Vines(j,fine)
        Publish(j,'arch',function(emit) Greedy(j,fine,emit);Greedy(j,coarse,emit) end)
    end)
    local glow=Grid()
    Stage(j,'details',function()
        Details(j,base,glow)
        local fine,coarse=Refine(j,base)
        Publish(j,'stone',function(emit) Greedy(j,fine,emit);Greedy(j,coarse,emit) end)
    end)
    Stage(j,'emission',function()
        for x=-10,9 do for z=-10,9 do
            if (x+.5)^2+(z+.5)^2<100 then
                Put(j,glow,x,6,z,(math.abs(x)==math.abs(z) or x==0 or z==0) and 'runeGold' or 'rune',true)
            end
        end end
        local fine,coarse=Refine(j,glow)
        Publish(j,'emission',function(emit) Greedy(j,fine,emit,true);Greedy(j,coarse,emit,true) end)
    end)
    Stage(j,'halo',function() Publish(j,'halo',function(emit) Halo(j,emit) end) end)
    Stage(j,'islands',function()
        local g=Grid();Islands(j,g);Publish(j,'islands',function(emit) Greedy(j,g,emit) end)
    end)
    Stage(j,'clouds',function()
        local g=Grid();Clouds(j,g);Publish(j,'clouds',function(emit) Greedy(j,g,emit) end)
    end)
    if not j.low then Stage(j,'atmosphere',function() Publish(j,'atmosphere',function(emit) Atmosphere(j,emit) end) end) end
    j.complete=true
end

---@param root Node
---@param mask integer
---@param opts table? quality=low|high; fixed integer seed for reproducibility
---@return table
function M.Begin(root,mask,opts)
    local j={root=root,mask=mask,nodes={},counts={},materials={},techniques={},triangles=0,operations=0,elapsed=0,stage='sky',
        low=opts and opts.quality=='low' or false,seed=opts and opts.seed or 71115,
        joints=0,chips=0,cracks=0,moss=0,aoVertices=0,errors={},skipped={}}
    assert(type(j.seed)=='number' and j.seed%1==0,'integer scene seed required')
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
    if #j.errors>0 then return table.remove(j.errors,1) end
    if j.complete or j.failed then return nil end
    local start=Clock()
    for _=1,32 do
        local ok,err=coroutine.resume(j.thread)
        if not ok then
            j.failed=true;j.thread=nil;Fallback(j)
            return 'scene '..j.stage..': '..tostring(err)
        end
        if coroutine.status(j.thread)=='dead' then j.thread=nil;return table.remove(j.errors,1) end
        if #j.errors>0 then return table.remove(j.errors,1) end
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
    if j.nodes.halo then
        local k=.88+.12*math.sin(j.elapsed*.8)
        j.materials.halo:SetShaderParameter('MatDiffColor',Variant(Color(k,k,k,1)))
    end
    if j.nodes.atmosphere then j.nodes.atmosphere.position=Vector3(0,(j.elapsed*.08)%1.2,0) end
    if j.nodes.emission then
        local k=.92+.08*math.sin(j.elapsed*math.pi/2)
        j.materials.emission:SetShaderParameter('MatDiffColor',Variant(Color(k,k,k,1)))
    end
end
---@param j table
---@param dt number
---@return string?
function M.Animate(j,dt)
    if j.failed or j.animationFailed then return nil end
    local ok,err=pcall(Animate,j,dt)
    if not ok then j.animationFailed=true;return 'animation: '..tostring(err) end
end
---@param j table?
function M.Dispose(j)
    if not j or j.disposed then return end
    j.disposed=true;j.thread=nil
    if j.pending then j.pending:Remove();j.pending=nil end
    for _,node in pairs(j.nodes) do node:Remove() end
    if j.base then j.base:Remove();j.base=nil end
    for _,mat in pairs(j.materials) do mat:Dispose() end
    for _,tech in ipairs(j.techniques) do tech:Dispose() end;j.techniques={}
    j.nodes={};j.materials={};j.counts={};j.triangles=0
end
return M
