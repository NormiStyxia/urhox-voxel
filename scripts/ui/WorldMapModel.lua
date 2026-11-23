-- Low-resolution orthographic mesh renderer. The colour and island ID at each
-- texel come from the same depth test, including overlapping islands.
local Model = {}
local sin, cos, pi = math.sin, math.cos, math.pi
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local width, height, scale = 372, 300, 10.1
Model.width, Model.height = width, height
local centers = {ruins=-9.6,home=9.6}
local anchors = {ruins={0,.38,-5.1},home={1.2,.18,-3.25}}
local vertices, faces, colours = {}, {}, {}
local island, offset
local function vertex(x,y,z)
    vertices[#vertices+1] = {x+offset,y,z}
    return #vertices
end
local ramps = {
    grass={'294e44','527a40','83a64d','a9c567'}, grass2={'344e42','648143','92af54','b6c96b'},
    moss={'484e40','696e4c','8f916c','b3ab7a'}, rock={'333648','535366','777889','a49996'},
    shale={'2a2f42','47495d','646578','858293'}, ochre={'574a45','776456','96816a','b59d79'},
    stone={'444d64','758298','a6abb1','d2cfbd'}, chalk={'526178','8a96a4','d6d4be','f3ead1'},
    bronze={'5a493a','8b6943','b39157','e0be7d'}, wood={'443c39','665040','866447','ab8256'},
    plaster={'6a6251','9c9277','c8ba92','e6d6aa'}, tile={'533b3c','804a41','a85e49','cf8058'},
    pine={'2b4541','395c4d','517259','789363'}, leaf={'405642','617849','839858','a8b96f'},
    pool={'27546c','367f92','60a9af','92c8c2'}, foam={'638c8c','7fb4ac','a4cfc1','c6dbbe'},
    dark={'323939','454c49','59605a','73796b'}, lamp={'9c6841','c68a4c','e1ad64','ffe1a2'},
    honey={'714622','ae7028','dfa038','f8c654'},
    sunleaf={'9a6026','ce8b32','f4bd47','ffe17d'},
    weathered={'514c59','77676a','a59283','c2af92'},
    turf={'345342','49683c','739947','98ae53'},
    masonryJoint={'677487','89949d','a2aaab','b4b8b1'},
    lichen={'384e44','5f8545','8eb75d','c8cf80'},
    teal={'22496e','386d9b','62a0cd','96cbe4'},
}
local materials={}
for name,ramp in pairs(ramps) do
    local shades={}
    for i,hex in ipairs(ramp) do
        colours[#colours+1]={tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16)}
        shades[i]=#colours
    end
    materials[name]=shades
end
local outline=#colours+1
colours[outline]={48,55,73}
Model.colours=colours
-- Winding points outward. Face lighting is fixed to the model's world space.
local function face(a,b,c,mat)
    local p,q,r=vertices[a],vertices[b],vertices[c]
    local x,y,z=q[1]-p[1],q[2]-p[2],q[3]-p[3]
    local u,v,w=r[1]-p[1],r[2]-p[2],r[3]-p[3]
    local nx,ny,nz=y*w-z*v,z*u-x*w,x*v-y*u
    local length=math.sqrt(nx*nx+ny*ny+nz*nz)
    if length<.00001 then return end
    local light=(-.53*nx+.79*ny-.32*nz)/length
    local shade=light<-.48 and 1 or light<.14 and 2 or light<.68 and 3 or 4
    faces[#faces+1]={a,b,c,materials[mat][shade],island}
end
local function quad(a,b,c,d,mat) face(a,b,c,mat); face(a,c,d,mat) end
local function box(x,y,z,w,h,d,mat,angle)
    local ca,sa=cos(angle or 0),sin(angle or 0)
    local function corner(dx,dy,dz) return vertex(x+dx*ca-dz*sa,y+dy,z+dx*sa+dz*ca) end
    w,d=w*.5,d*.5
    local a,b,c,e=corner(-w,0,-d),corner(w,0,-d),corner(w,0,d),corner(-w,0,d)
    local f,g,i,j=corner(-w,h,-d),corner(w,h,-d),corner(w,h,d),corner(-w,h,d)
    quad(a,f,g,b,mat);quad(b,g,i,c,mat);quad(c,i,j,e,mat);quad(e,j,f,a,mat);quad(f,j,i,g,mat)
end
local function rim(x,y,z,rx,rz,count,variation,phase)
    local ring={}
    for i=1,count do
        local a=(i-1)*2*pi/count
        local k=1+variation*(.55*sin(3*a+phase)+.35*cos(7*a-phase)+.2*sin(11*a+phase))
        ring[i]=vertex(x+rx*k*cos(a),y,z+rz*k*sin(a))
    end
    return ring
end
local function join(lower,upper,mat,alternate)
    for i=1,#lower do
        local j=i%#lower+1
        quad(lower[i],upper[i],upper[j],lower[j],alternate and i%5==1 and alternate or mat)
    end
end
local function disc(x,y,z,rx,rz,h,n,mat,top)
    local a,b=rim(x,y,z,rx,rz,n,0,0),rim(x,y+h,z,rx,rz,n,0,0)
    join(a,b,mat)
    local center=vertex(x,y+h,z)
    for i=1,n do face(center,b[i%n+1],b[i],top or mat) end
end
-- Build individual fault blocks around a recessed core. Consecutive crowns share
-- the coastline; their angled shoulders and broken toes part below the soil lip.
local function cliffBlocks(rx,rz,seed)
    local count=15
    for i=1,count do
        local a=(i-1)*2*pi/count
        local delta=2*pi/count
        local function shelf(y,k,spread,lean)
            local front,back={},{}
            for j=1,3 do
                local angle=a+(j-2)*delta*spread+lean
                local shore=1+.06*sin(3*angle+seed)+.035*cos(7*angle-seed)
                local r=k*shore+(j==2 and .04 or 0)
                local dy=(sin(3*a+.7*j)*.20+cos(7*a)*.13)
                front[j]=vertex(rx*r*cos(angle),y+dy,rz*r*sin(angle))
                back[j]=vertex(rx*(r-.16)*cos(angle),y+dy+.12,rz*(r-.16)*sin(angle))
            end
            return {front[1],front[2],front[3],back[3],back[2],back[1]}
        end
        local drop=.55+.45*sin(a*5+.9)
        local top=shelf(-.64,.98,.48,0)
        local ledge=shelf(-1.45-.50*drop,1.0,.48,.015)
        local knee=shelf(-1.95-.46*drop,.87,.44,-.035)
        local toe=shelf(-2.55-.73*drop,.76,.29,-.065)
        local seam=shelf(-1.64-.50*drop,.965,.47,.01)
        join(ledge,top,i%5==0 and 'rock' or 'weathered')
        join(seam,ledge,'shale')
        join(knee,seam,'rock');join(toe,knee,'shale')
        quad(top[1],top[6],top[5],top[2],'ochre');quad(top[2],top[5],top[4],top[3],'ochre')
    end
end
local function rockIsland(rx,rz,seed,brokenCliffs)
    local n=30
    -- The wide shelves fracture at the edge; their deeper beds converge on
    -- a single stone keel. Home has a softer, slightly offset foundation.
    local levels=brokenCliffs and {
        {-5.55,.23,'shale'},{-4.5,.47,'rock'},{-3.22,.70,'shale'},
        {-1.85,.83,'rock'},{-.90,.95,'ochre'},{-.36,.995,'ochre'},{0,1,'turf'}
    } or {
        {-4.95,.22,'shale'},{-3.9,.48,'shale'},{-2.64,.73,'rock'},
        {-2.34,.79,'ochre'},{-1.45,.90,'rock'},{-.81,.98,'weathered'},
        {-.39,.99,'ochre'},{0,1,'turf'}
    }
    local keelX=brokenCliffs and .10 or .56
    local keelZ=brokenCliffs and -.55 or -.31
    local tip=vertex(keelX,brokenCliffs and -7.22 or -6.13,keelZ)
    local prev
    for j,level in ipairs(levels) do
        local y,k,mat=table.unpack(level)
        local ring=rim(keelX*(1-k),y,keelZ*(1-k),rx*k,rz*k,n,.11,seed+.15*(j-1))
        for i,id in ipairs(ring) do
            local a=(i-1)*2*pi/n
            if j<#levels then
                vertices[id][2]=y+(.38*sin(3*a+seed)+.19*cos(7*a))*min(1,k*2)
            end
            local nextId=ring[i%n+1]
            if not prev then face(tip,id,nextId,'shale') end
        end
        if prev then join(prev,ring,mat) end
        prev=ring
    end
    local inner=rim(0,.03,0,rx*.78,rz*.78,n,.08,seed)
    local center=vertex(0,.03,0)
    for i=1,n do
        local j=i%n+1
        quad(prev[i],inner[i],inner[j],prev[j],i%5==1 and 'grass2' or 'grass')
        face(center,inner[j],inner[i],'grass')
    end
    if brokenCliffs then cliffBlocks(rx,rz,seed);return end
    -- Outcrops follow the dipping beds, with moss only along the damp cap.
    for i=1,10 do
        local a=i*2*pi/10+.14
        local x,z=rx*cos(a),rz*sin(a)
        local foot=-3.27-.45*sin(i*2.1+seed)
        local lower=rim(x*.64,foot,z*.64,.32,.28,5,.14,i)
        local middle=rim(x*.87,-1.77,z*.87,.70,.57,5,.14,i)
        local upper=rim(x*.93,-.53-.21*sin(i*1.3),z*.93,.46,.40,5,.14,i)
        join(lower,middle,'shale');join(middle,upper,i%4==1 and 'moss' or 'weathered')
    end
end
local function pine(x,z,h)
    local foot=rim(x,.01,z,h*.105,h*.09,5,.08,0)
    local stem=rim(x+h*.025,h*.68,z,h*.033,h*.033,5,.08,0)
    join(foot,stem,'wood')
    for j=0,2 do
        local r=h*(.31-j*.077)
        local cx=x+h*.026*j
        local bottom=h*(.28+j*.24)
        local lower=rim(cx,bottom,z,r*.71,r*.66,7,.14,j)
        local skirt=rim(cx,bottom+h*.07,z,r,r*.93,7,.14,j)
        local tip=vertex(cx+h*.033,bottom+h*(.41-j*.035),z)
        join(lower,skirt,'pine')
        for i=1,#skirt do face(skirt[i],tip,skirt[i%#skirt+1],j==2 and 'leaf' or 'pine') end
    end
end
local function crown(x,y,z,r,mat,seed)
    local low=rim(x,y,z,r*.75,r*.71,8,.17,seed)
    local mid=rim(x,y+r*.48,z,r,r*.92,8,.13,seed)
    local cap=rim(x-r*.12,y+r,z,r*.56,r*.53,8,.13,seed)
    join(low,mid,mat);join(mid,cap,mat)
    local apex=vertex(x-r*.18,y+r*1.18,z)
    for i=1,8 do face(apex,cap[i%8+1],cap[i],mat) end
end
-- Crown groups grow from the tips of the same forked trunk in every view.
local function oldTree(x,z,h)
    local function section(dx,y,dz,r)
        return rim(x+h*dx,h*y,z+h*dz,h*r,h*r*.87,6,.11,1.2)
    end
    local root=section(0,.01,0,.108)
    local crook=section(-.065,.26,.008,.089)
    local fork=section(-.025,.48,.016,.067)
    local leader=section(.072,.66,-.02,.044)
    join(root,crook,'wood');join(crook,fork,'wood');join(fork,leader,'wood')
    for i=1,4 do
        local a=i*pi*.5+.36
        local base=section(.16*cos(a),.012,.16*sin(a),.050)
        join(base,crook,'wood')
    end
    for _,limb in ipairs({{crook,-.36,.65,-.10,.23},{fork,.33,.65,-.08,.21},
        {crook,.08,.72,.31,.22},{fork,-.24,.89,.14,.20},{leader,.27,.92,.12,.22},
        {leader,-.045,1.03,-.05,.28}}) do
        local start,dx,y,dz,r=table.unpack(limb)
        local elbow=section(dx*.78,y-.19,dz*.72,.040)
        join(start,elbow,'wood');join(elbow,section(dx,y+.09,dz,.025),'wood')
        local lx,ly,lz=x+h*dx,h*y,z+h*dz
        -- A shaded skirt below each crown, with offsets at the lit shoulder.
        crown(lx,ly,lz,h*r,'honey',y*11)
        crown(lx-h*r*.48,ly+h*r*.37,lz-h*r*.18,h*r*.69,'sunleaf',dx*12)
        crown(lx+h*r*.56,ly+h*r*.18,lz-h*r*.45,h*r*.56,'honey',dz*9)
        crown(lx+h*r*.13,ly+h*r*.68,lz-h*r*.43,h*r*.45,'sunleaf',y*8)
    end
    for i=1,7 do
        local a=i*2.4
        box(x+cos(a)*h*.16,.045,z+sin(a)*h*.17,.18,.045,.12,i%3==0 and 'sunleaf' or 'honey',a)
    end
end
-- Stagger the flagstones and leave a breach through both courses.
local function flagRing(inner,outer,y,segments,stagger)
    local function point(radius,a) return vertex(radius*cos(a),y,radius*.90*sin(a)) end
    for i=0,segments-1 do
        local a=(i+stagger)*2*pi/segments
        if a<5.65 or a>5.91 then
            local b=a+2*pi/segments-.050
            quad(point(inner,a),point(inner,b),point(outer,b),point(outer,a),'chalk')
        end
    end
end
-- Continuous stone faces give the portal one legible light plane and one reveal.
local function portal(x,z,angle)
    local ca,sa=cos(angle),sin(angle)
    local function point(u,y,d) return vertex(x+u*ca-d*sa,y,z+u*sa+d*ca) end
    local inner,outer=1.04,1.54
    local spring=1.7
    local previous
    for step=-1,13 do
        local a=min(12,max(0,step))*pi/12
        local base=(step==-1 or step==13) and .04 or spring
        local function ringPoint(radius,d) return point(radius*cos(a),base+radius*sin(a),d) end
        local row={ringPoint(outer,-.33),ringPoint(inner,-.33),ringPoint(inner,.33),ringPoint(outer,.33)}
        if previous then
            for i=1,4 do
                local j=i%4+1
                quad(previous[i],previous[j],row[j],row[i],i==2 and 'stone' or 'chalk')
            end
        end
        previous=row
    end
end
local function ruins()
    rockIsland(7.35,6.05,1.3,true)
    -- Follow the curved gallery with continuous coping stones and a southern gate.
    for i=0,27 do
        local a=i*2*pi/28
        if i~=20 and i~=21 and (i<9 or i>13) then
            local x,z=4.75*cos(a),4.20*sin(a)
            local high=i>=2 and i<=9
            local h=high and 1.20 or .67
            box(x,.04,z,1.12,h,.56,'stone',pi/2-a)
            box(x,h+.04,z,1.12,.22,.68,'chalk',pi/2-a)
            if i%7==0 then box(x,.04,z,.55,h+.55,.78,'chalk',pi/2-a) end
        end
    end
    portal(-4.08,1.89,1.0)
    disc(0,.04,0,3.98,3.59,.21,40,'stone','masonryJoint')
    flagRing(2.88,3.95,.27,16,0);flagRing(1.95,2.77,.28,12,.5)
    disc(0,.28,0,1.92,1.74,.08,32,'stone','teal')
    for i,r in ipairs({1.86,1.43,.96}) do
        box(0,.36+i*.03,0,r,.03,r,i==2 and 'teal' or 'chalk',pi/4)
    end
    box(0,.49,0,.57,.03,.57,'teal',pi/4)
    -- Separate cantilevers, exposed snapped ends and masonry piers.
    for i=0,6 do
        if i~=4 then box(0,.09,-2.8-i*.56,1.4,.28,.54,'chalk') end
    end
    for _,x in ipairs({-.8,.8}) do
        box(x,-1.65,-5.92,.43,2.05,.65,'stone');box(x,.37,-4.04,.24,.67,1.98,'moss')
        box(x,.37,-6.03,.33,.68,.56,'stone')
    end
    for _,p in ipairs({{-5,1.3,2.6},{-4.5,3,2},{-5.6,-1.1,1.5}}) do pine(table.unpack(p)) end
    oldTree(4.60,2.72,4.55)
    for _,p in ipairs({{-5,-2,.68},{-4.3,-3.2,.47},{2.4,-4.55,.55},{5.5,.6,.70}}) do crown(p[1],.04,p[2],p[3],'lichen',p[1]) end
end
local function roof(x,y,z,w,d,h)
    local a,b,c,e=vertex(x-w,y,z-d),vertex(x+w,y,z-d),vertex(x+w,y,z+d),vertex(x-w,y,z+d)
    local f,g=vertex(x-w,y+h,z),vertex(x+w,y+h,z)
    quad(a,f,g,b,'tile');quad(e,c,g,f,'tile');face(a,e,f,'wood');face(b,g,c,'wood')
    box(x,y-.14,z-d,2*w,.16,.16,'wood');box(x,y-.14,z+d,2*w,.16,.16,'wood')
    box(x,y+h-.04,z,2*w+.12,.16,.21,'bronze')
    for _,side in ipairs({-1,1}) do
        for row=1,3 do
            local f=row/4
            box(x,y+h*(1-f),z+side*d*f,2*w,.07,.10,'tile')
        end
    end
end
local function storey(x,y,z,w,h,d)
    box(x,y,z,w,h,d,'plaster')
    for _,s in ipairs({-1,1}) do
        local front=z+s*(d*.5+.024)
        box(x,y+h-.2,front,w,.2,.12,'wood')
        for _,f in ipairs({-.45,0,.45}) do box(x+w*f,y,front,.16,h,.14,'wood') end
        for _,f in ipairs({-.23,.23}) do
            box(x+w*f,y+.22,front+s*.08,w*.24,h*.55,.14,'wood')
            box(x+w*f,y+.32,front+s*.15,w*.16,h*.38,.09,'lamp')
        end
    end
end
local function home()
    rockIsland(7.45,5.75,4.2)
    disc(-2.25,.04,-1.6,2.64,1.63,.09,20,'moss','stone');disc(-2.25,.13,-1.6,2.39,1.40,.045,20,'pool','pool')
    for i=0,4 do box(-3.5+i*.48,.18,-1.6+.6*sin(i*1.8),.52,.02,.11,'foam') end
    box(-3.17,.045,-3.74,.85,.035,2.65,'pool');box(-3.17,-1.83,-4.98,.85,1.9,.14,'pool')
    box(-3.3,-1.32,-5.07,.16,1.4,.06,'foam')
    disc(3.15,.04,.8,2.24,2.21,.22,20,'stone','chalk');disc(3.15,.26,.8,1.97,1.94,.06,20,'bronze','wood')
    disc(3.15,.32,.8,1.72,1.69,.04,20,'stone','stone');box(3.15,.36,.8,1.18,.04,1.18,'chalk',pi/4)
    box(3.15,.40,.8,.65,.03,.65,'teal',pi/4)
    local x,z=-2.15,1.96
    box(x,.04,z,4.22,.4,2.98,'stone');storey(x,.44,z,3.83,1.35,2.52)
    roof(x,1.77,z,2.22,1.52,.9);storey(x-.28,2.09,z+.18,2.59,1.45,1.75)
    roof(x-.28,3.54,z+.18,1.62,1.12,1.0)
    box(x+1.23,1.85,z+.59,.46,1.55,.5,'stone');box(x+1.23,3.34,z+.59,.57,.21,.61,'chalk')
    roof(x,.99,z-1.48,2.3,.48,.4)
    for j=-2,2 do box(x+j*.89,.12,z-1.77,.13,.88,.13,'wood') end
    for _,p in ipairs({{-5.3,1,2.8},{-4.9,2.75,3.5},{.14,3.97,1.96},{5.26,2.1,2.3},{5.73,-.9,1.6},{-5.8,-1.1,1.8}}) do pine(table.unpack(p)) end
    oldTree(1.30,3.59,3.55)
    for j=0,4 do box(-1.96,.24,-.82-j*.23,.81,.10,.20,'wood') end
    for i=1,8 do box(-1.35+i*.46,.055,-.08-.34*i,.46,.06,.25,'moss',.22) end
end

function Model.New()
    if #faces==0 then
        island,offset='ruins',centers.ruins;ruins()
        island,offset='home',centers.home;home()
    end
    return {yaw=-.12,pitch=.46,panX=0,panY=0,groups={},ids={},depth={},screen={}}
end
local function project(v,x,y,z)
    local side=x*v.cy-z*v.sy
    local forward=x*v.sy+z*v.cy
    return width*.5+side*v.scale,height*.5-(y*v.cp+forward*v.sp)*v.scale,y*v.sp-forward*v.cp
end
function Model.Anchor(v,id)
    local a=anchors[id]
    return project(v,centers[id]+a[1],a[2],a[3])
end
function Model.Update(v,limitW,limitH,cellSize)
    cellSize=cellSize or 1
    if v.lastYaw==v.yaw and v.lastPitch==v.pitch and v.limitW==limitW and v.limitH==limitH and v.cellSize==cellSize then return end
    v.cellSize=cellSize
    local cols,rows=width//cellSize,height//cellSize
    v.scale,v.limitW,v.limitH=scale,limitW,limitH
    v.lastYaw,v.lastPitch=v.yaw,v.pitch
    v.cy,v.sy,v.cp,v.sp=cos(v.yaw),sin(v.yaw),cos(v.pitch),sin(v.pitch)
    local points,depth,ids=v.screen,v.depth,v.ids
    local pixels=v.pixels or {};v.pixels=pixels
    for k in pairs(depth) do depth[k],ids[k],pixels[k]=nil,nil,nil end
    local x0,x1,y0,y1=width,0,height,0
    for i,p in ipairs(vertices) do
        local pt=points[i] or {};points[i]=pt
        pt[1],pt[2],pt[3]=project(v,p[1],p[2],p[3])
        x0,x1=min(x0,pt[1]),max(x1,pt[1]);y0,y1=min(y0,pt[2]),max(y1,pt[2])
    end
    local zoom=limitW and min(1,limitW/(x1-x0),limitH/(y1-y0)) or 1
    v.scale=scale*zoom
    v.centerX=width*.5+((x0+x1-width)*.5)*zoom
    v.centerY=height*.5+((y0+y1-height)*.5)*zoom
    -- Keep the camera, anchors and output rectangles in full map coordinates.
    if zoom<1 or cellSize>1 then
        for _,p in ipairs(points) do
            p[1]=(width*.5+(p[1]-width*.5)*zoom)/cellSize
            p[2]=(height*.5+(p[2]-height*.5)*zoom)/cellSize
        end
    end
    local loX,hiX,loY,hiY=cols,0,rows,0
    for _,f in ipairs(faces) do
        local a,b,c=points[f[1]],points[f[2]],points[f[3]]
        local dx,dy,bx,by=b[1]-a[1],b[2]-a[2],c[1]-a[1],c[2]-a[2]
        local det=dx*by-dy*bx
        if det>.00001 then
            local left=max(0,ceil(min(a[1],b[1],c[1])-.5));local right=min(cols-1,floor(max(a[1],b[1],c[1])-.5))
            local top=max(0,ceil(min(a[2],b[2],c[2])-.5));local bottom=min(rows-1,floor(max(a[2],b[2],c[2])-.5))
            loX,hiX,loY,hiY=min(loX,left),max(hiX,right),min(loY,top),max(hiY,bottom)
            local dz,ez=b[3]-a[3],c[3]-a[3]
            local dzdx=(dz*by-ez*dy)/det
            local dzdy=(ez*dx-dz*bx)/det
            -- Walk only the covered interval of each row. Long, thin branches
            -- and cliff facets otherwise test most of their bounding box twice.
            local high,mid,low=a,b,c
            if high[2]>mid[2] then high,mid=mid,high end
            if mid[2]>low[2] then mid,low=low,mid end
            if high[2]>mid[2] then high,mid=mid,high end
            local long=(low[1]-high[1])/(low[2]-high[2])
            local upper=mid[2]>high[2] and (mid[1]-high[1])/(mid[2]-high[2]) or 0
            local lower=low[2]>mid[2] and (low[1]-mid[1])/(low[2]-mid[2]) or 0
            local colour,owner=f[4],f[5]
            for y=top,bottom do
                local sample=y+.5
                local xA=high[1]+(sample-high[2])*long
                local xB=sample<mid[2] and high[1]+(sample-high[2])*upper or mid[1]+(sample-mid[2])*lower
                if xA>xB then xA,xB=xB,xA end
                local first=max(left,ceil(xA-.5000001));local last=min(right,floor(xB-.4999999))
                local z=a[3]+(first+.5-a[1])*dzdx+(sample-a[2])*dzdy
                for key=y*cols+first,y*cols+last do
                    if not depth[key] or z>depth[key] then depth[key],pixels[key],ids[key]=z,colour,owner end
                    z=z+dzdx
                end
            end
        end
    end
    -- Apply ink inside the silhouette: every outlined pixel still picks its owner.
    local gap=1.35*cellSize
    for y=loY,hiY do
        local first=y*cols+loX
        for k=first,first+hiX-loX do
            local z=depth[k]
            if z and (not depth[k-1] or not depth[k-cols] or not depth[k+1] or not depth[k+cols]
                or z-depth[k+1]>gap or z-depth[k+cols]>gap) then
                pixels[k]=outline
            end
        end
    end
    -- Merge equal horizontal spans vertically. Static views reuse these paths.
    local groups,last={},{}
    for y=loY,hiY do
        local nextRow={};local x=loX
        while x<=hiX do
            local ink=pixels[y*cols+x];local a=x
            repeat x=x+1 until x>hiX or pixels[y*cols+x]~=ink
            if ink then
                local key=(a*cols+x)*128+ink;local rect=last[key]
                if rect then rect[4]=rect[4]+cellSize else
                    local g=groups[ink] or {};groups[ink]=g
                    rect={a*cellSize,y*cellSize,(x-a)*cellSize,cellSize};g[#g+1]=rect
                end
                nextRow[key]=rect
            end
        end
        last=nextRow
    end
    v.groups=groups
end
function Model.Pick(v,x,y)
    x,y=floor(x),floor(y)
    if x>=0 and x<width and y>=0 and y<height and v.cellSize then
        return v.ids[(y//v.cellSize)*(width//v.cellSize)+x//v.cellSize]
    end
end
return Model
