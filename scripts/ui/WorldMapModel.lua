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
    grass={'435a43','647748','869358','aab670'}, grass2={'535e42','77864e','9aab60','bcbd79'},
    moss={'484e40','696e4c','8f916c','b3ab7a'}, rock={'393d43','53545a','736e6d','968b7b'},
    shale={'343b41','4a5053','606465','807f75'}, ochre={'574a45','776456','96816a','b59d79'},
    stone={'535963','767e80','a1a7a2','d6cfb2'}, chalk={'646866','959784','c0bba3','e6dcbd'},
    bronze={'5a493a','8b6943','b39157','e0be7d'}, wood={'443c39','665040','866447','ab8256'},
    plaster={'6a6251','9c9277','c8ba92','e6d6aa'}, tile={'533b3c','804a41','a85e49','cf8058'},
    pine={'2b4541','395c4d','517259','789363'}, leaf={'405642','617849','839858','a8b96f'},
    pool={'355c64','427d7f','589b98','7bb8a6'}, foam={'638c8c','7fb4ac','a4cfc1','c6dbbe'},
    dark={'323939','454c49','59605a','73796b'}, lamp={'9c6841','c68a4c','e1ad64','ffe1a2'},
    teal={'325b62','447984','649b9d','8dc5b6'},
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
local function rockIsland(rx,rz,seed)
    local n=30
    local levels={{-5.95,.22,'shale'},{-4.25,.70,'shale'},{-3.25,.84,'rock'},
        {-2.86,.89,'ochre'},{-2.24,.91,'shale'},{-1.12,.97,'rock'},
        {-.76,.995,'ochre'},{-.26,.99,'rock'},{0,1,'grass'}}
    local prev
    for j,level in ipairs(levels) do
        local y,k,mat=table.unpack(level)
        local ring=rim(.35*(1-k),y,0,rx*k,rz*k,n,.11,seed+.15*(j-1))
        for i,id in ipairs(ring) do
            local a=i*2*pi/n
            if j<#levels then vertices[id][2]=y+(sin(5*a+seed)*.8+cos(9*a)*.35)*(1-.65*k) end
        end
        if prev then join(prev,ring,mat,j<6 and 'shale' or nil) end
        prev=ring
    end
    local inner=rim(0,.03,0,rx*.78,rz*.78,n,.08,seed)
    local center=vertex(0,.03,0)
    for i=1,n do
        local j=i%n+1
        quad(prev[i],inner[i],inner[j],prev[j],i%5==1 and 'grass2' or 'grass')
        face(center,inner[j],inner[i],'grass')
    end
    -- Basalt buttresses and lighter seams break up the outer cliff strata.
    for i=1,16 do
        local a=i*2*pi/16+.14
        local k=.91+.04*sin(i*2.34)
        local x,z=rx*k*cos(a),rz*k*sin(a)
        local foot=-3.75-.72*sin(i*2.1+seed)
        local lower=rim(x*.92,foot,z*.92,.30,.28,5,.14,i)
        local middle=rim(x,foot+1.25,z,.54,.48,5,.14,i)
        local upper=rim(x,-.53-.33*sin(i*1.3),z,.38,.36,5,.14,i)
        join(lower,middle,'shale');join(middle,upper,i%4==1 and 'moss' or 'rock')
    end
end
local function pine(x,z,h)
    box(x,0,z,h*.12,h*.35,h*.12,'wood')
    for j=0,2 do
        local r=h*(.31-j*.065)
        local ring=rim(x,h*(.22+j*.22),z,r,r,7,.06,j)
        local tip=vertex(x,h*(.68+j*.19),z)
        for i=1,#ring do face(ring[i],tip,ring[i%#ring+1],j==2 and 'leaf' or 'pine') end
    end
end
local function ruins()
    rockIsland(7.35,6.05,1.3)
    -- Split annular stone galleries leave the broken southern approach open.
    for i=0,27 do
        local a=i*2*pi/28
        if i~=20 and i~=21 then
            local x,z=4.35*cos(a),3.85*sin(a)
            box(x,.05,z,1.13,.28,.92,i%4==0 and 'moss' or 'stone',a+pi/2)
            if i%2==0 then
                local h=(i>=1 and i<=12) and (2.25+i%3*.3) or (.54+i%4*.35)
                box(x,.3,z,.81,.24,.8,'chalk',a)
                box(x,.54,z,.52,h,.55,'stone',a)
                box(x,h+.54,z,.81,.26,.78,'chalk',a)
                if i>=2 and i<=10 then
                    local mid=a+pi/14
                    box(4.35*cos(mid),3.09,3.85*sin(mid),2.03,.48,.77,'chalk',mid+pi/2)
                end
            end
        end
    end
    disc(0,.04,0,2.75,2.7,.27,24,'stone','chalk');disc(0,.31,0,2.31,2.26,.07,24,'bronze','wood')
    disc(0,.38,0,2.12,2.08,.06,24,'stone','stone');disc(0,.44,0,1.15,1.14,.1,12,'bronze','chalk')
    -- A stepped plinth and an upright hourglass cut a recognisable silhouette.
    box(0,.53,0,1.35,.32,1.35,'chalk');box(0,.85,0,1.12,.2,1.12,'bronze')
    local belt=rim(0,2,0,.24,.24,4,0,0)
    join(rim(0,1.05,0,.58,.58,4,0,0),belt,'teal');join(belt,rim(0,2.94,0,.58,.58,4,0,0),'teal')
    box(0,2.94,0,1.25,.21,1.25,'bronze')
    for _,x in ipairs({-.6,.6}) do box(x,1.04,.27,.12,1.92,.12,'bronze') end
    -- Separate cantilevers, exposed snapped ends and masonry piers.
    for i=0,6 do
        if i~=4 then box(0,.09,-2.8-i*.56,1.4,.28,.54,'chalk') end
    end
    for _,x in ipairs({-.8,.8}) do
        box(x,-1.65,-5.92,.43,2.05,.65,'stone');box(x,.37,-4.04,.24,.67,1.98,'moss')
        box(x,.37,-6.03,.33,.68,.56,'stone')
    end
    for _,p in ipairs({{-5,1.3,2.6},{-4.5,3,2},{3.9,3.2,2.2},{4.95,2.1,2.8},{-5.6,-1.1,1.5}}) do pine(table.unpack(p)) end
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
    for _,p in ipairs({{-5.3,1,2.8},{-4.9,2.75,3.5},{.3,3.6,2.5},{5.26,2.1,2.3},{5.73,-.9,1.6},{-5.8,-1.1,1.8}}) do pine(table.unpack(p)) end
    for i=1,8 do box(-1.35+i*.46,.055,-.08-.34*i,.46,.06,.25,'moss',.22) end
end

function Model.New()
    if #faces==0 then
        island,offset='ruins',centers.ruins;ruins()
        island,offset='home',centers.home;home()
    end
    return {yaw=-.12,pitch=.67,panX=0,panY=0,groups={},ids={},depth={},screen={}}
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
    -- During orbit each depth sample covers a 2x2 patch of that same image.
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
            local du,dv=by/det,-dy/det
            for y=top,bottom do
                local yy,xx=y+.5-a[2],left+.5-a[1]
                local u,vv=(xx*by-yy*bx)/det,(dx*yy-dy*xx)/det
                local key=y*cols+left
                for _=left,right do
                    if u>=-1e-7 and vv>=-1e-7 and u+vv<=1.0000001 then
                        local z=a[3]+u*dz+vv*ez
                        if not depth[key] or z>depth[key] then depth[key],pixels[key],ids[key]=z,f[4],f[5] end
                    end
                    key,u,vv=key+1,u+du,vv+dv
                end
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
