-- The 184 x 154 orthographic stage from the HTML prototype, in art pixels.
local data = require('ui.ForgePreviewMeshes')
local Preview = {}
local W,H,OFFSET_X,OFFSET_Y = 184,154,22,29
local OUTLINE = {40,48,64}
local STRINGS = {field={118,88,62},silver={92,134,178},thorn={188,92,242}}
local BOB_FREQUENCY,BOB_PHASE = {2.35,1.95,2.75},{1.3,3.1,4.7}
local ICON_ID = {
    edge='fengmang',ruishi='ruishi',impact='zhenren',reach='changfeng',jiying='jiying',ningshi='ningshi',
    feather='baiyu',manxian='manxian',awl='zaojia',anchor='zhenshi',xunbu='xunbu',liuxing='liuxing',
    xinghui='xinghui',yuzhen='yuzhen',rift='liedi',zhenbo='zhenbo',zhanshi='zhanshi',echo='suzhou',
}
function Preview.Icon(id) return ICON_ID[id] end
local function round(x) return math.floor(x+.5) end

function Preview.New()
    return {depth={},color={},px={},py={},pz={},centers={},angle=math.pi/6,yaw=-.45,pitch=.16}
end
function Preview.Home(v,id)
    v.yaw,v.pitch=STRINGS[id] and -1.15 or -.45,.16
end

local function Projector(v,scale,tx,ty,tz,ry,rx,weapon)
    local cy,sy,cx,sx=math.cos(ry),math.sin(ry),math.cos(rx),math.sin(rx)
    local ca,sa=math.cos(v.yaw),math.sin(v.yaw)
    local cp,sp=math.cos(v.pitch),math.sin(v.pitch)
    return function(x,y,z)
        x,y,z=x*scale,y*scale,z*scale
        local wx=x*cy-z*sy+tx
        local z1=x*sy+z*cy
        local wy,wz=y*cx-z1*sx+ty,y*sx+z1*cx+tz
        if weapon then
            local f=wx*sa+wz*ca
            wx,wy,wz=wx*ca-wz*sa,wy*cp+f*sp,wy*sp-f*cp
        end
        return W*.5+wx*v.scale,v.centerY-wy*v.scale,wz
    end
end
local function Shade(rampId,triangle,nx,ny,nz)
    local ramp=data.ramps[rampId]
    local light=-.42*nx+.72*ny+.55*nz
    local band
    if #ramp==6 then
        local bounce=math.abs(.45*nx-.78*ny+.42*nz)
        local hash=(triangle*37%11)/11
        local score=math.max(light*.68+.32,bounce*.66)+(hash-.5)*.36+(triangle%2==0 and .18 or -.16)
        if light>.62 and hash>.45 then score=.98
        elseif nx>.35 and ny<-.25 and hash>.55 then score=.78 end
        band=score<.24 and 1 or score<.42 and 2 or score<.58 and 3 or score<.74 and 4 or score<.90 and 5 or 6
    else
        light=light+(rampId==2 and .28 or .14)
        band=light<-.22 and 1 or light<.14 and 2 or light<.48 and 3 or 4
    end
    return ramp[band]
end
local function DrawMesh(v,mesh,project,doubleSided)
    local px,py,pz=v.px,v.py,v.pz
    for i=1,#mesh.vertices,3 do
        local index=(i+2)//3
        px[index],py[index],pz[index]=project(mesh.vertices[i]*.0001,mesh.vertices[i+1]*.0001,mesh.vertices[i+2]*.0001)
    end
    local faces,depth,color=mesh.faces,v.depth,v.color
    for i=1,#faces,4 do
        local a,b,c=faces[i],faces[i+1],faces[i+2]
        local x,y,z=px[a],py[a],pz[a]
        local ux,uy=px[b]-x,py[b]-y
        local vx,vy=px[c]-x,py[c]-y
        local det=ux*vy-uy*vx
        if det>1e-4 or (doubleSided and det< -1e-4) then
            if det<0 then b,c=c,b;ux,uy,vx,vy=vx,vy,ux,uy;det=-det end
            local uz,vz=pz[b]-z,pz[c]-z
            local dx,dy=(uz*vy-vz*uy)/det,(vz*ux-uz*vx)/det
            -- The normal in the prototype is computed before projection flips Y.
            local nx,ny,nz=dx*v.scale,-dy*v.scale,-1
            local norm=math.sqrt(nx*nx+ny*ny+1)
            local shade=Shade(faces[i+3],(i-1)//4,nx/norm,ny/norm,nz/norm)
            local x1,x2=math.max(1,math.ceil(math.min(x,px[b],px[c])-.5)),math.min(W-2,math.floor(math.max(x,px[b],px[c])-.5))
            local y1,y2=math.max(1,math.ceil(math.min(y,py[b],py[c])-.5)),math.min(H-2,math.floor(math.max(y,py[b],py[c])-.5))
            for row=y1,y2 do
                local v0=row+.5-y
                for col=x1,x2 do
                    local u0=col+.5-x
                    local e0=u0*uy-v0*ux
                    local e1=(u0-ux)*(vy-uy)-(v0-uy)*(vx-ux)
                    local e2=v0*vx-u0*vy
                    if e0<=0 and e1<=0 and e2<=0 then
                        local index=row*W+col
                        local d=z+u0*dx+v0*dy
                        if not depth[index] or d>depth[index] then depth[index],color[index]=d,shade end
                    end
                end
            end
        end
    end
end
local function DrawString(v,line,project,color,bob)
    local x,y,z=project(line[1],line[2]+bob,line[3])
    local ex,ey,ez=project(line[4],line[5]+bob,line[6])
    x,y,ex,ey=round(x),round(y),round(ex),round(ey)
    local dx,dy=math.abs(ex-x),-math.abs(ey-y)
    local sx,sy=x<ex and 1 or -1,y<ey and 1 or -1
    local error,step,steps=dx+dy,0,math.max(dx,-dy,1)
    while true do
        local index=y*W+x
        local d=z+(ez-z)*step/steps
        if x>=1 and x<W-1 and y>=1 and y<H-1 and d+.03>(v.depth[index] or -math.huge) then
            v.color[index]=color
        end
        if x==ex and y==ey then break end
        local e=2*error
        if e>=dy then error=error+dy;x=x+sx end
        if e<=dx then error=error+dx;y=y+sy end
        step=step+1
    end
end

local function Slot(v,index,clock,focus,id)
    local angle=v.angle+(index-1)*math.pi*2/3+math.pi*.5
    local radius=id=='clock' and 1.34 or 1.08
    local x,z=math.cos(angle)*radius,math.sin(angle)*radius
    local y=-math.sin(angle)*.34-.42+round(math.sin(clock*BOB_FREQUENCY[index]+BOB_PHASE[index]))/v.scale
    local front=focus==index and math.max(0,math.sin(angle)) or 0
    local center=v.centers[index] or {}
    v.centers[index]=center
    center.x,center.y=round(OFFSET_X+W*.5+x*v.scale),round(OFFSET_Y+v.centerY-y*v.scale)
    return x,y,z,front
end
function Preview.Raster(v,id,forge,equipped,roles,focus,clock)
    local mesh=data.meshes[id]
    if not mesh then return end
    local sway=round(math.sin(clock*1.65))
    local bob1,bob2,bob3=round(math.sin(clock*2.35+1.3)),round(math.sin(clock*1.95+3.1)),round(math.sin(clock*2.75+4.7))
    local key=table.concat({id,forge and 1 or 0,v.yaw,v.pitch,v.angle,focus or 0,sway,bob1,bob2,bob3,
        equipped.edge or '',equipped['break'] or '',equipped.time or ''},':')
    if key==v.key then return end
    v.key=key
    for index in pairs(v.depth) do v.depth[index]=nil;v.color[index]=nil end
    -- The string can cover transparent pixels and therefore has no depth entry.
    for index in pairs(v.color) do v.color[index]=nil end
    v.scale,v.centerY=forge and 62 or 54,H*(forge and .40 or .39)
    local bow=STRINGS[id]~=nil
    local tilt=id=='clock' and 0 or bow and -.18 or -.28
    local scale=id=='clock' and (forge and .90 or .82) or 1
    local bob=.05+sway/v.scale
    DrawMesh(v,mesh,Projector(v,scale,0,bob,0,tilt,.08,true),bow)
    if not forge then
        for i,role in ipairs(roles) do
            local x,y,z,front=Slot(v,i,clock,focus,id)
            local seal=data.meshes[ICON_ID[equipped[role]]]
            if seal then
                local project=Projector(v,.98+.38*front,x,y,z,-x*.52,.08*(1-front),false)
                DrawMesh(v,seal,project,true)
            end
        end
    end
    local depth=v.depth
    for k,z in pairs(depth) do
        if not (depth[k-1] and depth[k+1] and depth[k-W] and depth[k+W])
            or z-depth[k+1]>.10 or z-depth[k+W]>.10 then v.color[k]=OUTLINE end
    end
    if mesh.stringLine then
        DrawString(v,mesh.stringLine,Projector(v,1,0,0,0,tilt,.08,true),STRINGS[id],bob)
    end
    local batches={}
    for y=1,H-2 do
        local x=1
        while x<W-1 do
            local color=v.color[y*W+x]
            if color then
                local start=x
                repeat x=x+1 until x>=W-1 or v.color[y*W+x]~=color
                local spans=batches[color] or {}
                batches[color]=spans
                spans[#spans+1],spans[#spans+2],spans[#spans+3]=OFFSET_X+start,OFFSET_Y+y,x-start
            else x=x+1 end
        end
    end
    v.batches=batches
end

function Preview.Draw(vg,v)
    for color,spans in pairs(v.batches or {}) do
        nvgBeginPath(vg)
        for i=1,#spans,3 do nvgRect(vg,spans[i],spans[i+1],spans[i+2],1) end
        nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255)); nvgFill(vg)
    end
end
return Preview
