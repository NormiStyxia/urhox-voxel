-- Island-local metres. Geometry groups are committed by the same owner as the ground floor.
local P = require('ruins.RuinsPalette').P
local Upper = { Windows = {} }
local windowLamps={second={},third={}}
local step = .125
local woodX, woodY, woodZ, oakX, oakZ, glass = 152,157,159,150,158,156
local abs, floor, ceil, min, max = math.abs, math.floor, math.ceil, math.min, math.max

local function window(group, faceX, faceZ, nx, nz, bottom, width, height, flowers)
    local w = { group=group, x=faceX-nx*.3125, z=faceZ-nz*.3125, y=bottom+height/2,
        nx=nx, nz=nz, width=width, height=height, flowers=flowers }
    Upper.Windows[#Upper.Windows+1] = w
    -- The central pond-facing window represents each upper floor's sill light.
    if nz==-1 and faceX==-8.5 then
        windowLamps[group][1]={x=faceX,y=bottom+.5,z=faceZ,nx=nx,nz=nz}
    end
end
for _,x in ipairs({-14.5,-11.5,-8.5,-5.5,-2.5}) do
    window('second',x,7,0,-1,4.75,1.75,1.375,true)
    window('second',x,13,0,1,4.75,1.5,1.375)
end
for _,z in ipairs({8.5,11.5}) do
    window('second',-16,z,-1,0,4.75,1.25,1.375)
    window('second',-1,z,1,0,4.75,1.25,1.375)
end
window('third',-8.5,6.75,0,-1,8.0,2.5,1.625,true)
window('third',-8.5,12.75,0,1,8.0,1.75,1.5)
for _,x in ipairs({-14,-3}) do window('third',x,7.125,0,-1,7.75,1,.875) end

-- All window details are written in a local tangent/outward basis. The glass is one
-- cell thick, recessed two cells behind the wall, with a clear reveal and glazing bars.
local function drawWindow(b,w)
    local tx,tz = abs(w.nz),abs(w.nx)
    local function box(a,y0,d,c,y1,e,mat)
        b:Box(w.x+tx*a+w.nx*d,y0,w.z+tz*a+w.nz*d,
              w.x+tx*c+w.nx*e,y1,w.z+tz*c+w.nz*e,mat)
    end
    local h=w.width/2
    local sill,head=w.y-w.height/2,w.y+w.height/2
    local rail=tx==1 and woodX or woodZ
    box(-h-step,sill-step,-.0625,h+step,head+step,.3125,rail)
    box(-h,sill,-.0625,h,head,.4375,false)
    box(-h,sill,-.0625,h,head,.0625,glass)
    for _,sign in ipairs({-1,1}) do
        box(sign*h,sill,0,sign*(h+step),head,.4375,woodY)
    end
    -- Wide front windows are paired casements; small dormers use a single central mullion.
    box(0,sill,.0625,step,head,.3125,woodY)
    if w.width>=1.75 then
        for _,at in ipairs({-h*.5,h*.5}) do box(at-step/2,sill,.0625,at+step/2,head,.1875,woodY) end
    end
    local transom=sill+floor(w.height*.56/step)*step
    box(-h,transom,.0625,h,transom+step,.1875,rail)
    box(-h-.25,head,.1875,h+.25,head+step,.5625,rail)
    box(-h-.25,sill-step,.1875,h+.25,sill,.5625,rail)
    box(-h,sill-step,.0625,h,sill,.3125,P.HOME_WINDOW_REVEAL)
    if not w.flowers then return end
    box(-h-.125,sill-.375,.3125,h+.125,sill-.125,.8125,rail)
    box(-h-.25,sill-.25,.6875,h+.25,sill-.125,.9375,tx==1 and oakX or oakZ)
    for i=0,floor(w.width/.25)-1 do
        local a=-h+i*.25
        local lift=(i%3==1) and .125 or 0
        box(a,sill-.125,.4375,a+.25,sill+.125+lift,.8125,i%3==1 and P.LEAF_A or P.LEAF_C)
        if i%3~=2 then box(a,sill+.125+lift,.5625,a+step,sill+.25+lift,.6875,i%3==1 and P.FLOWER_W or P.FLOWER_Y) end
    end
end

local function ring(b,y,height)
    for _,z in ipairs({7,13}) do b:Box(-16.125,y,z-.125,-.875,y+height,z+.125,woodX) end
    for _,x in ipairs({-16,-1}) do b:Box(x-.125,y,7.125,x+.125,y+height,12.875,woodZ) end
end
local function secondFloor(b)
    b:Box(-16,3.75,7,-1,6.75,13,P.MARBLE_B)
    b:Carve(-15.625,4,7.375,-1.375,6.75,12.625)
    b:Box(-15.625,3.875,7.375,-1.375,4,12.625,oakZ)
    ring(b,3.75,.25); ring(b,6.5,.25)
    for _,z in ipairs({7,13}) do
        for x=-16,-1,3 do
            b:Box(x-.125,4,z-.125,x+.125,6.5,z+.125,woodY)
            for _,sign in ipairs({-1,1}) do
                if x+sign*.625>-16 and x+sign*.625< -1 then
                    for i=0,3 do
                        local at=x+sign*(i+1)*step
                        b:Box(at-step,6.0+i*step,z-.125,at+step,6.25+i*step,z+.125,woodY)
                    end
                end
            end
        end
    end
    for _,x in ipairs({-16,-1}) do b:Box(x-.125,4,9.875,x+.125,6.5,10.125,woodY) end
    for _,w in ipairs(Upper.Windows) do if w.group=='second' then drawWindow(b,w) end end
end

-- u runs along the ridge, v across it. Each overlapping course has a dark
-- underside, offset end joints, raised roll at each tile edge, and a capped ridge.
local function tileRoof(b,acrossX,center,depth,u0,u1,eave,rise)
    local function box(u,y,v,uu,yy,vv,mat)
        if acrossX then b:Box(v,y,u,vv,yy,uu,mat) else b:Box(u,y,v,uu,yy,vv,mat) end
    end
    local rows=ceil(depth/.375)
    local ridgeMat=acrossX and woodZ or woodX
    for row=0,rows-1 do
        local v0=row*.375
        local v1=min(depth,v0+.375)
        local y=eave+floor((1-v1/depth)*rise/step+.5)*step
        for _,sign in ipairs({-1,1}) do
            local outer=center+sign*v1
            local inner=center+sign*max(0,v0-.125)
            box(u0,y,outer,u1,y+.25,inner,ridgeMat)
            local index=0
            local start=u0-(row%2)*.25
            while start<u1 do
                local lo,hi=max(u0,start),min(u1,start+.625)
                local mat=(index+row*3)%5==1 and P.HOME_CLAY_LIGHT or P.HOME_CLAY
                if hi>lo then
                    box(lo,y+.25,outer,hi,y+.375,inner,mat)
                    if hi-lo>=.25 then box(lo,y+.375,outer,lo+step,y+.5,inner,mat) end
                end
                index=index+1;start=start+.625
            end
        end
    end
    box(u0-.125,eave+rise,center-.25,u1+.125,eave+rise+.25,center+.25,P.HOME_CLAY)
    for i=0,ceil((u1-u0)/.625)-1 do
        local lo=u0+i*.625;box(lo,eave+rise+.25,center-.125,min(lo+.5,u1),eave+rise+.375,center+.125,P.HOME_CLAY_LIGHT)
    end
end

Upper.TileRoof=tileRoof

local function longRoof(b,rise)
    -- Long side gables close the triangular attic volume without filling the interior.
    for _,x in ipairs({-16,-1.375}) do
        b:Shape(x,6.75,7,x+.375,7+rise,13,function(_,y,z)
            local top=7+rise*(1-abs(z-10)/3.625)
            if y<top then
                if top-y<.25 then return woodZ end
                if abs(z-10)<.125 then return woodY end
                return P.MARBLE_B
            end
        end)
    end
    for _,z in ipairs({7,12.625}) do b:Box(-16,6.75,z,-1,7.25,z+.375,woodX) end
    for x=-15.75,-1.25,.75 do
        for _,z in ipairs({6.5,13}) do b:Box(x,6.75,z,x+.125,7.0,z+.5,woodZ) end
    end
    tileRoof(b,false,10,3.625,-16.5,-.5,6.875,rise)
end

local function crossGable(b,cx,half,z0,z1,base,eave,rise)
    -- Clear the long roof inside this dormer's walls and remove the section of its
    -- forward overhang that would pass in front of the windows.
    b:Carve(cx-half,base,z0-.375,cx+half,eave+rise,z1)
    for _,x in ipairs({cx-half,cx+half-.375}) do
        b:Box(x,base,z0,x+.375,eave,z1,P.MARBLE_B)
        b:Box(x,eave-.25,z0,x+.375,eave,z1,woodZ)
        for at=z0+.125,z1-.125,1.875 do b:Box(x,base,at,x+.375,eave-.25,at+.25,woodY) end
    end
    for _,z in ipairs({z0,z1-.375}) do
        b:Shape(cx-half,base,z,cx+half,eave+rise,z+.375,function(x,y)
            local top=eave+rise*(1-abs(x-cx)/(half+.375))
            if y<top then
                if top-y<.25 then return woodX end
                if abs(x-cx)<step or abs(x-cx)>half-.25 then return woodY end
                if half>1 and y>eave and abs(abs(x-cx)-(y-eave)*.9)<step then return woodY end
                return P.MARBLE_B
            end
        end)
        b:Box(cx-half,base,z,cx+half,base+.25,z+.375,woodX)
        b:Box(cx-half,eave-step,z,cx+half,eave,z+.375,woodX)
    end
    tileRoof(b,true,cx,half+.375,z0-.375,z1+.375,eave,rise)
end

local function stack(b,x,z,base,cap)
    b:Box(x-.5,base,z-.5,x+.5,cap,z+.5,P.HOME_ASHLAR)
    b:Box(x-.625,base,z-.625,x+.625,base+.25,z+.625,P.HOME_PLINTH)
    for y=base+.75,cap-.375,.75 do b:Box(x-.5,y,z-.5,x+.5,y+.125,z+.5,P.STONE_C) end
    b:Box(x-.625,cap-.375,z-.625,x+.625,cap-.25,z+.625,P.HOME_COPING)
    b:Box(x-.75,cap-.125,z-.75,x+.75,cap+.125,z+.75,P.HOME_COPING)
    b:Carve(x-.25,cap-.625,z-.25,x+.25,cap+.125,z+.25)
end
local function eastHoist(b)
    local cx,cy,z=1,6.375,7.75
    for _,at in ipairs({8,9}) do
        b:Box(-1.25,7.5,at,1.5,7.75,at+.25,woodX)
        for i=0,12 do
            local x=-1+i*.125;local y=6.875+i*.0625
            b:Box(x,y,at,x+.25,y+.25,at+.25,woodX)
        end
    end
    b:Box(.875,cy,8,1.125,7.625,8.25,woodY)
    b:Box(cx-.125,cy-.125,z-.25,cx+.125,cy+.125,8.5,oakZ)
    b:Shape(cx-1,cy-1,z,cx+1,cy+1,z+.25,function(x,y)
        local dx,dy=x-cx,y-cy
        local r=math.sqrt(dx*dx+dy*dy)
        if r>1 then return end
        if r>.75 then return r>.91 and woodX or oakX end
        if r<.25 then return woodZ end
        if abs(dx)<.07 then return woodY end
        if abs(dy)<.07 or abs(abs(dx)-abs(dy))<=step then return oakX end
    end)
end

function Upper.Build(brush,finish)
    local second=brush({-16.25,3.75,6},{-.75,6.75,13.5},step)
    secondFloor(second)
    finish('second',second,{masonry='homeWindows',windowLamps=windowLamps.second})
    local roof=brush({-16.75,6.75,6.125},{-.25,10.25,13.875},step)
    longRoof(roof,1.625)
    stack(roof,-7.5,11,7.5,9.75)
    finish('secondRoof',roof,{masonry='homeWindows'})
    local attic=brush({-16.75,5.375,6.125},{2.125,12.5,13.875},step)
    longRoof(attic,1.875)
    attic:Box(-16,6.75,7,-1,7,13,oakZ)
    crossGable(attic,-8.5,2.375,6.75,12.75,7.0,9.875,1.875)
    for _,x in ipairs({-14,-3}) do crossGable(attic,x,1,7.125,9.625,7.25,8.875,.875) end
    for _,w in ipairs(Upper.Windows) do if w.group=='third' then drawWindow(attic,w) end end
    stack(attic,-14.5,11.125,8,11.25)
    eastHoist(attic)
    finish('third',attic,{masonry='homeWindows',windowLamps=windowLamps.third})
end
return Upper
