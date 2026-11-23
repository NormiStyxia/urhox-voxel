-- Island-local metres. Geometry groups are committed by the same owner as the ground floor.
local P = require('ruins.RuinsPalette').P
local Upper = { Windows = {} }
local windowLamps={second={},third={}}
local step = .125
-- The shell stays on a 0.125 m grid. Local detail brushes below use smaller
-- cells for exposed frames without fine-subdividing the whole house.
local detailStep, trimStep = .0625, .03125
local woodX, woodY, woodZ, oakX, oakZ, glass = 152,157,159,150,158,156
local abs, floor, ceil, min, max = math.abs, math.floor, math.ceil, math.min, math.max

-- Upper wall fill is deliberately a small, shared surface vocabulary: mostly
-- plaster, with sparse exposed blocks only on the outer wall skin. Interior
-- cells remain plaster so this never changes collision or window carving.
local function upperWallMaterial(x,y,z)
    local skin = x <= -15.875 or x >= -1.125 or z <= 7.125 or z >= 12.875
    if not skin then return P.HOME_PLASTER end
    local along = (abs(z-7.0) < .25 or abs(z-13.0) < .25) and x or z
    local row = floor((y-3.75)/.75)
    local col = floor((along+16.0)/1.5)
    -- Keep weathered reveals below the windows and at two gable corners;
    -- arbitrary rectangular patches behind glazing would never be visible.
    if z<=7.125 then
        local sillPatch = y>3.875 and y<4.5 and
            (abs(x+13.875)<.625-(y-3.875)*.25 or abs(x+5.875)<.5-(y-3.875)*.2)
        local gablePatch = y>7.5 and y<8.375 and abs(x+10.8125)<.375-(y-7.5)*.14
        if sillPatch or gablePatch then return P.HOME_EXPOSED end
    elseif row>=0 and ((col+row*3)%17)==4 then return P.HOME_EXPOSED end
    return P.HOME_PLASTER
end

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
    window('second',x,7,0,-1,4.625,1.875,1.5,true)
    window('second',x,13,0,1,4.625,1.625,1.5)
end
for _,z in ipairs({8.5,11.5}) do
    window('second',-16,z,-1,0,4.625,1.375,1.5)
    window('second',-1,z,1,0,4.625,1.375,1.5)
end
window('third',-8.5,6.75,0,-1,7.25,2.5,1.25,true)
window('third',-8.5,12.75,0,1,7.25,1.875,1.25)
for _,x in ipairs({-13.75,-3.25}) do window('third',x,7.125,0,-1,7.375,1.125,.75) end

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
    box(-h,sill,-.0625,h,head,.4375,false)
    box(-h,sill,-.0625,h,head,.0625,glass)
    box(-h,sill,.0625,h,sill+step,.1875,P.HOME_WINDOW_REVEAL)
    box(-h,head-step,.0625,h,head,.1875,P.HOME_WINDOW_REVEAL)
end

-- Window frames live outside the parent wall. The glass/opening remains in the
-- coarse floor brush, so a fine detail volume never hides the recessed glazing.
local function drawWindowFrame(b,w,withMullions)
    local tx,tz = abs(w.nz),abs(w.nx)
    local function box(a,y0,d,c,y1,e,mat)
        b:Box(w.x+tx*a+w.nx*d,y0,w.z+tz*a+w.nz*d,
              w.x+tx*c+w.nx*e,y1,w.z+tz*c+w.nz*e,mat)
    end
    local h=w.width/2
    local sill,head=w.y-w.height/2,w.y+w.height/2
    local rail=tx==1 and woodX or woodZ
    local d0,d1=.375,.4375
    for _,sign in ipairs({-1,1}) do
        box(sign*h,sill,d0,sign*(h+detailStep),head,d1,woodY)
    end
    box(-h,sill,d0,h,sill+detailStep,d1,rail)
    box(-h,head-detailStep,d0,h,head,d1,rail)
    if w.flowers then
        box(-h-detailStep,sill-.375,d0,h+detailStep,sill-.3125,d1,rail)
        box(-h-.125,sill-.3125,d0,h+.125,sill-.1875,d1,oakX)
        for i=0,floor(w.width/.25)-1 do
            local a=-h+i*.25
            box(a,sill-.1875,d0,a+.125,sill-.0625,d1,i%3==1 and P.LEAF_A or P.LEAF_C)
            if i%3~=2 then
                box(a,sill-.0625,d0,a+detailStep,sill,d1,i%3==1 and P.FLOWER_W or P.FLOWER_Y)
            end
        end
    end
    if not withMullions then return end
    if w.width>=1.75 then
        for _,at in ipairs({-h*.5,h*.5}) do
            box(at-trimStep/2,sill,d0,at+trimStep/2,head,d1,woodY)
        end
    end
    box(-trimStep/2,sill,d0,trimStep/2,head,d1,woodY)
    local transom=sill+floor(w.height*.56/detailStep)*detailStep
    box(-h,transom-trimStep/2,d0,h,transom+trimStep/2,d1,rail)
end

local function drawGableBraces(b,cx,half,z,base,eave,rise,front)
    local z0,z1
    if front then z0,z1=z-.125,z-.0625 else z0,z1=z+.0625,z+.125 end
    local beam=.0625
    b:Box(cx-beam/2,base+.125,z0,cx+beam/2,eave,z1,woodY)
    b:Box(cx-half, eave-beam, z0, cx+half, eave, z1, woodX)
    local count=math.max(1,math.floor((half-.25)/detailStep))
    for i=0,count do
        local t=i/count
        local y=base+.25+t*math.max(0,eave-base-.5)
        local left=cx-half+.25+t*(half-.25)
        local right=cx+half-.25-t*(half-.25)
        b:Box(left-beam/2,y-beam/2,z0,left+beam/2,y+beam/2,z1,woodY)
        b:Box(right-beam/2,y-beam/2,z0,right+beam/2,y+beam/2,z1,woodY)
    end
end

local function makeUpperDetails(brush,finish,name,group,withFrontMullions)
    local lo,hi
    if group=='second' then
        lo,hi={-16.5,4.25,6.8},{-.5,6.7,13.45}
    else
        lo,hi={-16.5,6.55,6.55},{-.5,9.85,13.55}
    end
    local frame=brush(lo,hi,detailStep)
    for _,w in ipairs(Upper.Windows) do
        if w.group==group then drawWindowFrame(frame,w,false) end
    end
    if group=='third' then
        drawGableBraces(frame,-8.5,2.75,6.75,7.0,8.625,2.125,true)
        drawGableBraces(frame,-8.5,2.75,12.75,7.0,8.625,2.125,false)
    for _,x in ipairs({-13.75,-3.25}) do
            drawGableBraces(frame,x,1.25,7.125,7.25,8.25,1.125,true)
            drawGableBraces(frame,x,1.25,9.625,7.25,8.25,1.125,false)
        end
    end
    finish(group,frame,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..name..'-frames'})
    if not withFrontMullions then return end
    -- Every front window has its own plane, including the projecting attic gable.
    for i,w in ipairs(Upper.Windows) do
        if w.group==group and w.nz==-1 then
            local half=w.width/2+.125
            local sill=w.y-w.height/2
            local front=brush({w.x-half,sill-.375,w.z-.4375},{w.x+half,sill+w.height,w.z-.375},trimStep)
            drawWindowFrame(front,w,true)
            finish(group,front,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..name..'-mullions-'..i})
        end
    end
end

local function makeRoofDetails(brush,finish,name)
    -- Each 16 m fascia is exactly 256 cells long. Separate the parallel strips
    -- so neither the overhang margins nor the empty roof interior need a grid.
    for i,z in ipairs({6.25,13.6875}) do
        local loZ,hiZ=z-.1875,z+.1875
        if z==6.25 then loZ,hiZ=6.0,7.25 end
        local eave=brush({-16.5,6.0,loZ},{-.5,7.25,hiZ},detailStep)
        eave:Box(-16.5,6.75,z,-.5,6.8125,z+detailStep,woodX)

        -- Six wall bays carry real medieval knee brackets. Their anchor, seat,
        -- diagonal knee, beam head and rafter tail occupy distinct depth bands
        -- so the support relationship reads from front, low underside and side.
        -- Collision remains in the coarse floor/roof brushes.
        if z==6.25 then
            local supports={-16,-13,-10,-7,-4,-1}
            local beam=.125
            for _,x in ipairs(supports) do
                -- Wall-side post and shoulder plate.
                eave:Box(x-beam/2,6.125,6.9375,x+beam/2,6.625,7.125,woodY)
                eave:Box(x-.1875,6.4375,6.875,x+.1875,6.5625,7.125,oakZ)

                -- Projecting seat and square beam head, 0.75 m ahead of wall.
                eave:Box(x-.125,6.625,6.25,x+.125,6.8125,7.0,woodX)
                eave:Box(x-.1875,6.5625,6.125,x+.1875,6.75,6.3125,oakX)

                -- Sloped brace in the Y/Z plane on the 0.0625 m detail grid.
                local y0,z0=6.125,6.9375
                local dy,dz=.625,-.625
                local len2=dy*dy+dz*dz
                eave:Shape(x-.0625,y0,6.25,x+.0625,y0+dy,z0,function(_,y,pz)
                    local t=((y-y0)*dy+(pz-z0)*dz)/len2
                    if t<0 or t>1 then return end
                    local py,zz=y0+t*dy,z0+t*dz
                    if (y-py)^2+(pz-zz)^2<=.0625*.0625 then return woodY end
                end)

                -- Rafter tail and exposed tenon/pin at the front fascia.
                eave:Box(x-.0625,6.75,6.0625,x+.0625,6.875,6.6875,woodX)
                eave:Box(x-.125,6.6875,6.0625,x+.125,6.8125,6.25,oakX)
                eave:Box(x-.0625,6.8125,6.21875,x+.0625,6.875,6.28125,oakZ)
            end
        end
        finish(name,eave,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..name..'-eaves-'..i})
    end
end

local function ring(b,y,height)
    for _,z in ipairs({7,13}) do b:Box(-16.0625,y,z-.0625,-.9375,y+height,z+.0625,woodX) end
    for _,x in ipairs({-16,-1}) do b:Box(x-.0625,y,7.0625,x+.0625,y+height,12.9375,woodZ) end
end
local function secondFloor(b)
    b:Shape(-16,3.75,7,-1,6.75,13,upperWallMaterial)
    b:Carve(-15.625,4,7.375,-1.375,6.75,12.625)
    b:Box(-15.625,3.875,7.375,-1.375,4,12.625,oakZ)
    ring(b,3.75,.125); ring(b,6.5,.125)
    for _,z in ipairs({7,13}) do
        for x=-16,-1,3 do
            b:Box(x-.0625,4,z-.0625,x+.0625,6.5,z+.0625,woodY)
        end
    end
    for _,x in ipairs({-16,-1}) do b:Box(x-.0625,4,9.9375,x+.0625,6.5,10.0625,woodY) end
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
            -- The roof carrier is a single 0.125 m beam. Tile overlap supplies
            -- the visible second layer above it.
            box(u0,y,outer,u1,y+.125,inner,ridgeMat)
            local index=0
            local start=u0-(row%2)*.25
            while start<u1 do
                local lo,hi=max(u0,start),min(u1,start+.625)
                local mat=(index+row*3)%5==1 and P.HOME_CLAY_LIGHT or P.HOME_CLAY
                if hi>lo then
                    box(lo,y+.125,outer,hi,y+.25,inner,mat)
                    if hi-lo>=.25 then box(lo,y+.25,outer,lo+step,y+.375,inner,mat) end
                end
                index=index+1;start=start+.625
            end
        end
    end
    box(u0-.125,eave+rise,center-.125,u1+.125,eave+rise+.125,center+.125,P.HOME_CLAY)
    for i=0,ceil((u1-u0)/.625)-1 do
        local lo=u0+i*.625;box(lo,eave+rise+.125,center-.0625,min(lo+.5,u1),eave+rise+.1875,center+.0625,P.HOME_CLAY_LIGHT)
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
                return upperWallMaterial(x,y,z)
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
        b:Box(x,base,z0,x+.375,eave,z1,P.HOME_PLASTER)
        b:Box(x,eave-.25,z0,x+.375,eave,z1,woodZ)
        for at=z0+.125,z1-.125,1.875 do b:Box(x,base,at,x+.375,eave-.25,at+.25,woodY) end
    end
    for _,z in ipairs({z0,z1-.375}) do
        b:Shape(cx-half,base,z,cx+half,eave+rise,z+.375,function(x,y)
            local top=eave+rise*(1-abs(x-cx)/(half+.375))
            if y<top then
                return upperWallMaterial(x,y,z)
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
    makeUpperDetails(brush,finish,'second','second',true)
    local roof=brush({-16.75,6.75,6.125},{-.25,10.25,13.875},step)
    longRoof(roof,1.625)
    stack(roof,-7.5,11,7.5,9.75)
    finish('secondRoof',roof,{masonry='homeWindows'})
    makeRoofDetails(brush,finish,'secondRoof')
    local attic=brush({-16.75,5.375,6.125},{2.125,12.5,13.875},step)
    longRoof(attic,1.875)
    attic:Box(-16,6.75,7,-1,7,13,oakZ)
    crossGable(attic,-8.5,2.75,6.75,12.75,7.0,8.625,2.125)
    for _,x in ipairs({-13.75,-3.25}) do crossGable(attic,x,1.25,7.125,9.625,7.25,8.25,1.125) end
    for _,w in ipairs(Upper.Windows) do if w.group=='third' then drawWindow(attic,w) end end
    stack(attic,-13.25,11.125,8,11.25)
    eastHoist(attic)
    finish('third',attic,{masonry='homeWindows',windowLamps=windowLamps.third})
    makeUpperDetails(brush,finish,'third','third',true)
    makeRoofDetails(brush,finish,'third')
end
return Upper
