-- Island-local metres. Geometry groups are committed by the same owner as the ground floor.
--
-- Massing (after the Dawn-Winery style brief): a stone ground hall, a timber-framed
-- plaster storey over the whole footprint, then an asymmetric top: the west wing
-- rises one more storey under a steep front-facing gable, the east wing is a flat
-- terrace with a stone balustrade, reached by a glazed door from the west attic.
-- Build stage 2 shows only the full-width second storey under one long roof.
local P = require('ruins.RuinsPalette').P
local Upper = { Windows = {} }

-- Shared footprint. The ground floor (HomeIsland) builds its walls on the same box.
local X0, X1, Z0, Z1 = -16, -1, 7, 15
local SPLIT = -7              -- west wing X0..SPLIT, east terrace SPLIT..X1
-- The ground hall is 5 m floor to ceiling, the second storey 4 m.
local F2, F3 = 5.75, 9.75     -- second-storey base, third-storey / terrace base
local CZ = (Z0+Z1)/2
local WEST_CX = (X0+SPLIT)/2
local KNEE = F3+2.5           -- west attic wall top
local GABLE_HALF, GABLE_EAVE, GABLE_RISE = 5, KNEE-.375, 4
-- Outer stair: 0.375 m risers and treads; the terrace's back rail opens west of STAIR_GAP.
local RISE, TREAD = .375, .375
local STAIR_GAP = X1+.5-math.floor((F3-12*RISE)/RISE)*TREAD+.25
Upper.Footprint = { x0=X0, x1=X1, z0=Z0, z1=Z1, split=SPLIT, second=F2, third=F3 }

local windowLamps={second={},third={}}
local step = .125
-- The shell stays on a 0.125 m grid. Local detail brushes below use smaller
-- cells for exposed frames without fine-subdividing the whole house.
local detailStep, trimStep = .0625, .03125
local woodX, woodY, woodZ, oakX, oakZ = 152,157,159,150,158
local abs, floor, ceil, min, max = math.abs, math.floor, math.ceil, math.min, math.max

-- Upper wall fill is deliberately a small, shared surface vocabulary: mostly
-- plaster, with sparse exposed blocks only on the outer wall skin. Interior
-- cells remain plaster so this never changes collision or window carving.
local function upperWallMaterial(x,y,z)
    local front = z <= Z0+.125
    local skin = front or x <= X0+.125 or x >= X1-.125 or z >= Z1-.125
        or (y >= F3 and abs(x-SPLIT) < .25)
    if not skin then return P.HOME_PLASTER end
    local along = (front or z >= Z1-.125) and x or z
    local row = floor((y-F2)/.75)
    local col = floor((along+16.0)/1.5)
    if row>=0 and ((col+row*(front and 5 or 3))%(front and 23 or 17))==4 then return P.HOME_EXPOSED end
    return P.HOME_PLASTER
end

local function window(group, faceX, faceZ, nx, nz, bottom, width, height, flowers)
    local w = { group=group, x=faceX-nx*.3125, z=faceZ-nz*.3125, y=bottom+height/2,
        nx=nx, nz=nz, width=width, height=height, flowers=flowers }
    Upper.Windows[#Upper.Windows+1] = w
    return w
end
-- Second storey: the bay rhythm of the timber frame, three bays per side.
local secondSill, secondHeight = F2+1.0, 2.25
for _,x in ipairs({-14.5,-11.5,-8.5,-5.5,-2.5}) do
    local w=window('second',x,Z0,0,-1,secondSill,1.875,secondHeight,true)
    if x==-8.5 then windowLamps.second[1]={x=x,y=secondSill+.5,z=Z0,nx=0,nz=-1} end
    window('second',x,Z1,0,1,secondSill,1.625,secondHeight)
end
for _,z in ipairs({9,11,13}) do
    window('second',X0,z,-1,0,secondSill,1.375,secondHeight)
    window('second',X1,z,1,0,secondSill,1.375,secondHeight)
end
-- West attic: a tall gable window over a timber balcony, a small apex light,
-- and side lights in both knee walls.
window('third',WEST_CX,Z0,0,-1,F3+.75,2.5,2.25,true)
windowLamps.third[1]={x=WEST_CX,y=F3+1.25,z=Z0,nx=0,nz=-1}
window('third',WEST_CX,Z0,0,-1,F3+3.75,1.0,.875)
window('third',WEST_CX,Z1,0,1,F3+.75,1.875,1.75)
for _,z in ipairs({9.5,12.5}) do window('third',X0,z,-1,0,F3+.5,1.25,1.5) end
for _,z in ipairs({8.75,13.25}) do window('third',SPLIT,z,1,0,F3+.5,1.25,1.5) end
local terraceDoor={z0=CZ-.625,z1=CZ+.625,top=F3+2.375}

-- All window details are written in a local tangent/outward basis. The opening is
-- recessed two cells behind the wall, with a clear reveal and glazing bars.
local function drawWindow(b,w)
    local tx,tz = abs(w.nz),abs(w.nx)
    local function box(a,y0,d,c,y1,e,mat)
        b:Box(w.x+tx*a+w.nx*d,y0,w.z+tz*a+w.nz*d,
              w.x+tx*c+w.nx*e,y1,w.z+tz*c+w.nz*e,mat)
    end
    local h=w.width/2
    local sill,head=w.y-w.height/2,w.y+w.height/2
    -- The opening stays clear: HomeIsland hangs a transparent pane at d=0.
    box(-h,sill,-.0625,h,head,.4375,false)
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

-- Exposed timber on a gable face: raking rafters under the verge, a collar
-- tie at knee height and two posts that frame (never cross) the gable window.
local function gableTimber(b,z,front,opening)
    local z0,z1
    if front then z0,z1=z-.125,z-.0625 else z0,z1=z+.0625,z+.125 end
    local beam=.0625
    local half=GABLE_HALF-.625
    local function roofAt(u) return GABLE_EAVE+GABLE_RISE*(1-u/GABLE_HALF)-.25 end
    for i=0,floor(half/detailStep) do
        local u=i*detailStep
        local y=roofAt(u)
        for _,x in ipairs({WEST_CX-u,WEST_CX+u}) do b:Box(x-beam/2,y-beam,z0,x+beam/2,y,z1,woodX) end
    end
    for _,sign in ipairs({-1,1}) do
        local inner,outer=WEST_CX+sign*opening,WEST_CX+sign*half
        b:Box(math.min(inner,outer),KNEE-beam,z0,math.max(inner,outer),KNEE,z1,woodX)
        b:Box(inner-beam/2,F3+.125,z0,inner+beam/2,roofAt(opening),z1,woodY)
        -- Raking brace from the knee post foot up to the collar.
        local foot=WEST_CX+sign*(half-.25)
        local count=floor(abs(foot-inner)/detailStep)
        for i=0,count do
            local t=i/count
            local x=foot+(inner-foot)*t*.6
            local y=F3+.25+t*(KNEE-F3-.5)
            b:Box(x-beam/2,y-beam/2,z0,x+beam/2,y+beam/2,z1,woodY)
        end
    end
end

local function makeDetails(brush,finish,group,lo,hi,extra)
    local frame=brush(lo,hi,detailStep)
    for _,w in ipairs(Upper.Windows) do
        if w.group==group then drawWindowFrame(frame,w,false) end
    end
    if extra then extra(frame) end
    finish(group,frame,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..group..'-frames'})
    -- Every front window has its own plane.
    for i,w in ipairs(Upper.Windows) do
        if w.group==group and w.nz==-1 then
            local half=w.width/2+.125
            local sill=w.y-w.height/2
            local front=brush({w.x-half,sill-.375,w.z-.4375},{w.x+half,sill+w.height,w.z-.375},trimStep)
            drawWindowFrame(front,w,true)
            finish(group,front,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..group..'-mullions-'..i})
        end
    end
end

-- Six wall bays carry medieval knee brackets under the long second-storey eave.
-- Anchor, seat, diagonal knee, beam head and rafter tail occupy distinct depth
-- bands so the support relationship reads from front, low underside and side.
local function makeEaves(brush,finish,name)
    local oy=F3-6.75
    for i,z in ipairs({Z0-.75,Z1+.6875}) do
        local loZ,hiZ=z-.1875,z+.1875
        local front=i==1
        if front then loZ,hiZ=Z0-1,Z0+.25 end
        local eave=brush({X0-.5,F3-.75,loZ},{X1+.5,F3+.5,hiZ},detailStep)
        eave:Box(X0-.5,F3,z,X1+.5,F3+.0625,z+detailStep,woodX)
        if front then
            local beam=.125
            for x=X0,X1,3 do
                eave:Box(x-beam/2,6.125+oy,6.9375,x+beam/2,6.625+oy,7.125,woodY)
                eave:Box(x-.1875,6.4375+oy,6.875,x+.1875,6.5625+oy,7.125,oakZ)
                eave:Box(x-.125,6.625+oy,6.25,x+.125,6.8125+oy,7.0,woodX)
                eave:Box(x-.1875,6.5625+oy,6.125,x+.1875,6.75+oy,6.3125,oakX)
                local y0,z0=6.125+oy,6.9375
                local dy,dz=.625,-.625
                local len2=dy*dy+dz*dz
                eave:Shape(x-.0625,y0,6.25,x+.0625,y0+dy,z0,function(_,y,pz)
                    local t=((y-y0)*dy+(pz-z0)*dz)/len2
                    if t<0 or t>1 then return end
                    local py,zz=y0+t*dy,z0+t*dz
                    if (y-py)^2+(pz-zz)^2<=.0625*.0625 then return woodY end
                end)
                eave:Box(x-.0625,6.75+oy,6.0625,x+.0625,6.875+oy,6.6875,woodX)
                eave:Box(x-.125,6.6875+oy,6.0625,x+.125,6.8125+oy,6.25,oakX)
                eave:Box(x-.0625,6.8125+oy,6.21875,x+.0625,6.875+oy,6.28125,oakZ)
            end
        end
        finish(name,eave,{masonry='homeWindows',visual=true,nodeName='HomeHouseDetail-'..name..'-eaves-'..i})
    end
end

local function ring(b,y,height,x0,x1)
    for _,z in ipairs({Z0,Z1}) do b:Box(x0-.0625,y,z-.0625,x1+.0625,y+height,z+.0625,woodX) end
    for _,x in ipairs({x0,x1}) do b:Box(x-.0625,y,Z0+.0625,x+.0625,y+height,Z1-.0625,woodZ) end
end
local function secondFloor(b)
    b:Shape(X0,F2,Z0,X1,F3,Z1,upperWallMaterial)
    b:Carve(X0+.375,F2+.25,Z0+.375,X1-.375,F3,Z1-.375)
    b:Box(X0+.375,F2+.125,Z0+.375,X1-.375,F2+.25,Z1-.375,oakZ)
    ring(b,F2,.125,X0,X1); ring(b,F3-.25,.125,X0,X1)
    for _,z in ipairs({Z0,Z1}) do
        for x=X0,X1,3 do
            b:Box(x-.0625,F2+.125,z-.0625,x+.0625,F3-.25,z+.0625,woodY)
        end
    end
    for _,x in ipairs({X0,X1}) do
        for _,z in ipairs({CZ-2,CZ+2}) do b:Box(x-.0625,F2+.125,z-.0625,x+.0625,F3-.25,z+.0625,woodY) end
    end
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

local function stack(b,x,z,base,cap)
    b:Box(x-.5,base,z-.5,x+.5,cap,z+.5,P.HOME_ASHLAR)
    b:Box(x-.625,base,z-.625,x+.625,base+.25,z+.625,P.HOME_PLINTH)
    for y=base+.75,cap-.375,.75 do b:Box(x-.5,y,z-.5,x+.5,y+.125,z+.5,P.STONE_C) end
    b:Box(x-.625,cap-.375,z-.625,x+.625,cap-.25,z+.625,P.HOME_COPING)
    b:Box(x-.75,cap-.125,z-.75,x+.75,cap+.125,z+.75,P.HOME_COPING)
    b:Carve(x-.25,cap-.625,z-.25,x+.25,cap+.125,z+.25)
end

-- Stage 2 only: one long roof over the full second storey, closed by two side gables.
local function longRoof(b)
    local depth,rise=(Z1-Z0)/2+.625,2.375
    local eave=F3+.125
    for _,x in ipairs({X0,X1-.375}) do
        b:Shape(x,F3,Z0,x+.375,eave+rise,Z1,function(_,y,z)
            local top=eave+.125+rise*(1-abs(z-CZ)/depth)
            if y<top then
                if top-y<.25 then return woodZ end
                if abs(z-CZ)<.125 then return woodY end
                return upperWallMaterial(x,y,z)
            end
        end)
    end
    for _,z in ipairs({Z0,Z1-.375}) do b:Box(X0,F3,z,X1,F3+.5,z+.375,woodX) end
    for x=X0+.25,X1-.25,.75 do
        for _,z in ipairs({Z0-.5,Z1}) do b:Box(x,F3,z,x+.125,F3+.25,z+.5,woodZ) end
    end
    tileRoof(b,false,CZ,depth,X0-.5,X1+.5,eave,rise)
end

-- The west wing's attic storey: knee walls, a steep front-facing gable roof,
-- a chimney through the rear slope and the glazed door onto the terrace.
local function westAttic(b)
    local x0,x1=X0,SPLIT
    b:Box(x0+.375,F3+.125,Z0+.375,x1-.375,F3+.25,Z1-.375,oakZ)
    local function gableTop(x) return GABLE_EAVE+GABLE_RISE*(1-abs(x-WEST_CX)/GABLE_HALF) end
    -- Knee walls run up into the roof line so no gap opens under the tiles.
    for _,x in ipairs({x0,x1-.375}) do
        b:Shape(x,F3,Z0,x+.375,KNEE+.5,Z1,function(px,y,z)
            if y<gableTop(px)-.125 then return upperWallMaterial(px,y,z) end
        end)
    end
    for _,z in ipairs({Z0,Z1-.375}) do
        b:Shape(x0,F3,z,x1,GABLE_EAVE+GABLE_RISE,z+.375,function(x,y)
            if y<gableTop(x)-.125 then return upperWallMaterial(x,y,z) end
        end)
        b:Box(x0,F3,z,x1,F3+.25,z+.375,woodX)
        b:Box(x0,KNEE-.125,z,x1,KNEE,z+.375,woodX)
    end
    for _,x in ipairs({x0,x1}) do
        b:Box(x-.0625,F3,Z0+.0625,x+.0625,F3+.125,Z1-.0625,woodZ)
        for _,z in ipairs({Z0+.0625,CZ,Z1-.0625}) do b:Box(x-.0625,F3,z-.0625,x+.0625,KNEE,z+.0625,woodY) end
    end
    for _,w in ipairs(Upper.Windows) do if w.group=='third' then drawWindow(b,w) end end
    -- Terrace door: opening, timber jambs and a glazed transom.
    b:Carve(x1-.375,F3+.25,terraceDoor.z0,x1,terraceDoor.top,terraceDoor.z1)
    for _,z in ipairs({terraceDoor.z0-.125,terraceDoor.z1}) do
        b:Box(x1-.375,F3+.25,z,x1+.0625,terraceDoor.top+.125,z+.125,woodY)
    end
    b:Box(x1-.375,terraceDoor.top,terraceDoor.z0-.125,x1+.0625,terraceDoor.top+.125,terraceDoor.z1+.125,woodZ)
    tileRoof(b,true,WEST_CX,GABLE_HALF,Z0-.75,Z1+.75,GABLE_EAVE,GABLE_RISE)
    stack(b,X0+1.75,Z1-1.75,F3,gableTop(X0+1.75)+1.75)
end

-- Timber balcony under the big gable window, on two raking brackets.
local function westBalcony(b)
    local w0,w1,floorY=WEST_CX-1.75,WEST_CX+1.75,F3+.5
    b:Box(w0,floorY-.125,Z0-.875,w1,floorY,Z0,oakX)
    b:Box(w0,floorY-.25,Z0-.9375,w1,floorY-.125,Z0-.8125,woodX)
    for _,x in ipairs({w0+.25,w1-.25}) do
        for i=0,9 do
            local t=i/9
            b:Box(x-.0625,floorY-.875+t*.6875,Z0-.0625-t*.75,x+.0625,floorY-.8125+t*.6875,Z0-t*.75,woodY)
        end
    end
    local railY=floorY+.875
    for x=w0,w1-.01,.25 do b:Box(x,floorY,Z0-.875,x+.0625,railY,Z0-.8125,woodY) end
    for _,x in ipairs({w0,w1-.0625}) do
        for z=Z0-.875,Z0-.1,.25 do b:Box(x,floorY,z,x+.0625,railY,z+.0625,woodY) end
    end
    b:Box(w0-.0625,railY,Z0-.9375,w1+.0625,railY+.0625,Z0-.75,woodX)
    for _,x in ipairs({w0-.0625,w1-.125}) do b:Box(x,railY,Z0-.9375,x+.1875,railY+.0625,Z0,woodZ) end
    -- Flower troughs on the rail.
    for i=0,13 do
        local x=w0+.125+i*.25
        b:Box(x-.0625,railY+.0625,Z0-.9375,x+.125,railY+.1875,Z0-.8125,i%3==1 and P.LEAF_A or P.LEAF_C)
        if i%3~=2 then b:Box(x,railY+.1875,Z0-.9375,x+.0625,railY+.25,Z0-.875,i%2==0 and P.FLOWER_W or P.FLOWER_Y) end
    end
end

-- East terrace on the second storey: stone deck, balusters, pedestals and planters.
local function terrace(b)
    local x0,x1=SPLIT,X1
    b:Box(x0,F3,Z0-.25,x1+.25,F3+.125,Z1+.25,P.HOME_COPING)
    b:Box(x0,F3+.125,Z0,x1,F3+.25,Z1,P.HOME_PAVING)
    local top=F3+1.25
    local function rail(a0,a1,fixed,alongX)
        local function box(u0,y0,u1,y1,d0,d1,mat)
            if alongX then b:Box(u0,y0,fixed+d0,u1,y1,fixed+d1,mat) else b:Box(fixed+d0,y0,u0,fixed+d1,y1,u1,mat) end
        end
        box(a0,F3+.25,a1,F3+.375,-.25,.25,P.HOME_PLINTH)
        for u=a0+.25,a1-.25,.375 do box(u,F3+.375,u+.125,top-.125,-.0625,.0625,P.HOME_COPING) end
        box(a0,top-.125,a1,top,-.1875,.1875,P.HOME_COPING)
        local n=math.max(1,floor((a1-a0)/2+.5))
        for i=0,n do
            local u=a0+(a1-a0)*i/n
            box(u-.1875,F3+.25,u+.1875,top+.125,-.1875,.1875,P.HOME_PLINTH)
            box(u-.25,top+.125,u+.25,top+.25,-.25,.25,P.HOME_COPING)
        end
    end
    rail(x0+.25,x1,Z0+.0625,true)
    -- The rear rail stops short of the attic wall: the outer stair lands there.
    rail(STAIR_GAP,x1,Z1-.0625,true)
    rail(Z0+.25,Z1-.25,x1-.0625,false)
    -- Potted bay trees and a planter keep clear of the path from the stair to the door.
    for _,c in ipairs({{x0+.875,Z0+.875},{x1-.875,Z1-.875}}) do
        local x,z=c[1],c[2]
        b:Box(x-.3125,F3+.25,z-.3125,x+.3125,F3+.75,z+.3125,P.HOME_PLINTH)
        b:Box(x-.0625,F3+.75,z-.0625,x+.0625,F3+1.25,z+.0625,P.BARK)
        b:Box(x-.375,F3+1.25,z-.375,x+.375,F3+1.875,z+.375,P.LEAF_A)
        b:Box(x-.25,F3+1.875,z-.25,x+.25,F3+2.125,z+.25,P.LEAF_C)
    end
    b:Box(x1-.75,F3+.25,CZ-1.0,x1-.25,F3+.625,CZ+1.0,oakX)
    for z=CZ-.875,CZ+.75,.25 do
        b:Box(x1-.6875,F3+.625,z,x1-.3125,F3+.8125,z+.1875,(floor(z*4)%3==1) and P.LEAF_A or P.LEAF_C)
    end
end

-- Hoist on the east gable, hanging just under the terrace deck.
local HOIST_Y=F3-7.75
local function eastHoist(b)
    local oy=HOIST_Y
    local cx,cy,z=1,6.375+oy,7.75
    for _,at in ipairs({8,9}) do
        b:Box(-1.25,7.5+oy,at,1.5,7.75+oy,at+.25,woodX)
        for i=0,12 do
            local x=-1+i*.125;local y=6.875+oy+i*.0625
            b:Box(x,y,at,x+.25,y+.25,at+.25,woodX)
        end
    end
    b:Box(.875,cy,8,1.125,7.625+oy,8.25,woodY)
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

-- Outer stair hung on the house: one flight up the east wall, a stone pier landing
-- at the rear corner, a second flight west along the back wall to a pier landing
-- that bridges onto the terrace. Treads are slabs on wall brackets, open beneath,
-- so the hall windows behind stay clear. Risers 0.375 m fit the 0.55 m step height.
local function outerStair(b)
    local lane0,lane1=X1+.5,X1+1.875            -- flight A, along the east wall
    local back0,back1=Z1+.5,Z1+1.875            -- flight B, along the back wall
    local startZ=Z1-12*TREAD
    local landA=12*RISE
    local flightB=floor((F3-landA)/RISE)
    local landB=landA+flightB*RISE
    local endX=lane0-flightB*TREAD
    local stone,slab=P.HOME_ASHLAR,P.HOME_COPING
    local function tread(x0,y,z0,x1,z1,alongX)
        b:Box(x0,y-.25,z0,x1,y,z1,slab)
        b:Box(x0,y-.375,z0,x1,y-.25,z1,stone)
        -- Outer rail post and stepped cap.
        if alongX then
            b:Box(x0,y,back1-.125,x0+.125,y+.875,back1,woodY)
            b:Box(x0,y+.875,back1-.1875,x1,y+1.0,back1,woodX)
        else
            b:Box(lane1-.125,y,z0,lane1,y+.875,z0+.125,woodY)
            b:Box(lane1-.1875,y+.875,z0,lane1,y+1.0,z1,woodZ)
        end
    end
    for i=1,12 do
        local z=startZ+(i-1)*TREAD
        tread(lane0,i*RISE,z,lane1,z+TREAD,false)
        if i%4==2 then
            -- Knee bracket from the wall into the tread underside.
            for k=0,3 do b:Box(X1,i*RISE-.75-k*.125,z+.125,X1+.25+k*.125+.25,i*RISE-.625-k*.125,z+.25,woodX) end
        end
    end
    for i=1,flightB do
        local x=lane0-i*TREAD
        tread(x,landA+i*RISE,back0,x+TREAD,back1,true)
        if i%4==2 then
            for k=0,3 do b:Box(x+.125,landA+i*RISE-.75-k*.125,Z1,x+.25,landA+i*RISE-.625-k*.125,Z1+.25+k*.125+.25,woodZ) end
        end
    end
    -- Corner pier landing, then the upper pier landing which bridges onto the deck.
    b:Box(lane0,0,Z1,lane1,landA,back1,stone)
    b:Box(lane0-.125,landA-.25,Z1-.125,lane1+.125,landA,back1+.125,slab)
    b:Box(endX-1.5,0,back0,endX,landB-.25,back1,stone)
    b:Box(endX-1.625,landB-.25,Z1,endX+.125,landB,back1+.125,slab)
    for y=1.0,landB-1.0,1.25 do
        b:Box(endX-1.625,y,back0-.125,endX+.125,y+.125,back1+.125,P.HOME_PLINTH)
    end
    -- Rails on the open sides of both landings.
    b:Box(lane1-.1875,landA,Z1,lane1,landA+1.0,back1,woodZ)
    b:Box(lane0,landA,back1-.1875,lane1,landA+1.0,back1,woodX)
    b:Box(endX-1.625,landB,back1-.1875,endX,landB+1.0,back1,woodX)
    b:Box(endX-1.625,landB,Z1,endX-1.4375,landB+1.0,back1,woodZ)
end
function Upper.Build(brush,finish)
    local second=brush({X0-.25,F2,Z0-1},{X1+.25,F3,Z1+.5},step)
    secondFloor(second)
    finish('second',second,{masonry='homeWindows',windowLamps=windowLamps.second})
    makeDetails(brush,finish,'second',{X0-.5,F2+.25,Z0-.2},{X1+.5,F3-.25,Z1+.45})

    local roof=brush({X0-.75,F3,Z0-.875},{X1+.75,F3+3.25,Z1+.875},step)
    longRoof(roof)
    stack(roof,-7.5,CZ+1,F3+.5,F3+3.0)
    finish('secondRoof',roof,{masonry='homeWindows'})
    makeEaves(brush,finish,'secondRoof')

    local attic=brush({X0-.75,F3,Z0-.875},{SPLIT+.75,GABLE_EAVE+GABLE_RISE+.5,Z1+.875},step)
    westAttic(attic)
    finish('third',attic,{masonry='homeWindows',windowLamps=windowLamps.third})
    local deck=brush({SPLIT,F3,Z0-.5},{X1+.5,F3+2.25,Z1+.5},step)
    terrace(deck)
    finish('terrace',deck,{masonry='homeWindows'})
    local hoist=brush({-1.5,5.25+HOIST_Y,7.5},{2.25,F3,9.5},step)
    eastHoist(hoist)
    finish('terrace',hoist,{masonry='homeWindows'})
    local stair=brush({SPLIT-1.5,0,Z1-4.75},{X1+2.0,F3+1.25,Z1+2.0},step)
    outerStair(stair)
    finish('terrace',stair,{masonry='homeWindows'})
    makeDetails(brush,finish,'third',{X0-.5,F3-.5,Z0-1.0},{SPLIT+.5,GABLE_EAVE+GABLE_RISE-.5,Z1+.45},function(frame)
        gableTimber(frame,Z0,true,1.5)
        gableTimber(frame,Z1,false,1.125)
        westBalcony(frame)
    end)
end
return Upper
