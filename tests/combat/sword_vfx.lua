package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
require('sword_vfx_support').Install()
local Vfx=require('combat.SwordVfx')
local scene=Mock.Node('scene')
-- 俯视机位：挥砍平面正对镜头，扭转完全不生效，几何检查针对原始月牙
local TOP={worldRight=Vector3(1,0,0),worldUp=Vector3(0,0,-1),worldDirection=Vector3(0,-1,0)}
local fx=Vfx.New(scene,TOP)
local function nodes(n) local c=1;for _,child in ipairs(n.children) do c=c+nodes(child) end;return c end
local built=nodes(scene)
assert(fx.material.shader=='Shaders/BLGL/SwordSheet.shader' and not fx.node.enabled)
-- The geometry double appends forever; read only what the last Draw submitted.
local function drawn(target)
    local all=target.geometry.vertices;local list={}
    for i=#all-target.vertices+1,#all do list[#list+1]=all[i] end
    return list
end
-- A horizontal swing around the origin at chest height.
local function swing(target,from,to,steps)
    for i=0,steps do
        local a=math.rad(from+(to-from)*i/steps)
        target:Sample(Vector3(math.sin(a)*.2,1,math.cos(a)*.2),Vector3(math.sin(a)*1.1,1,math.cos(a)*1.1))
    end
end

-- Cause: nothing exists until the blade has actually moved through a swing.
fx:Sample(Vector3(0,1,.2),Vector3(0,1,1.1))
assert(fx:Count()==0 and fx.vertices==0,'nothing is emitted outside a swing')
fx:Begin('light');fx:Sample(Vector3(0,1,.2),Vector3(0,1,1.1))
assert(fx.vertices==0,'a blade that has not moved leaves no sheet')
swing(fx,0,90,4)
assert(fx.node.enabled and fx.vertices>0 and fx.vertices%6==0,'the sheet is visible on the frame the blade moves')
local sheet=drawn(fx)
for _,v in ipairs(sheet) do
    local p=v.position;local radius=math.sqrt(p.x^2+p.z^2)
    assert(math.abs(p.y-1)<1e-6 and radius<1.1*1.15 and radius>.2,'the sheet lies on the swept blade surface')
    assert(p.x>-1e-4 and p.z>-1e-4,'the sheet never leads the blade or leaves the swept quarter')
    assert(v.color.g==0 and v.uv.y>=0 and v.uv.y<=1)
end
-- The head hugs the current blade: the newest sample is the last blade pose.
local head=fx.samples[#fx.samples]
assert(math.abs(head.dx-1)<1e-6 and math.abs(head.dz)<1e-6 and head.age==0)
-- A full crescent: pointed where the swing started and at the blade, widest in between.
local function width(v) local p=v.position;return math.sqrt(p.x^2+p.z^2) end
local lo,hi={},{}
for _,v in ipairs(sheet) do
    local a=math.floor(math.deg(math.atan(v.position.x,v.position.z))/10+.5)
    lo[a]=math.min(lo[a] or 9,width(v));hi[a]=math.max(hi[a] or 0,width(v))
end
assert(hi[0]-lo[0]<.15 and hi[9]-lo[9]<.15 and hi[4]-lo[4]>.6,'two pointed ends, wide middle')

-- No fold: along the stroke the outer edge must keep pointing the way the arc goes, even when
-- the hand also rises (translation on top of the turn) and the swing plane drifts.
local function edgeTurn(target)
    local worst=1
    for i=2,#target.samples do
        local a,b=target.samples[i-1],target.samples[i]
        if not b.stroke then
            local function outward(s,q)
                local w=math.min(s.w,.9)
                local outer=s.len*(1+s.reach*w)
                local mid=(s.len*(1-s.width*w)+outer)*.5
                local wx,wy,wz=target.bwx[q],target.bwy[q],target.bwz[q]
                return s.rx+s.dx*mid+wx*(outer-mid),s.ry+s.dy*mid+wy*(outer-mid),s.rz+s.dz*mid+wz*(outer-mid)
            end
            local ax,ay,az=outward(a,i-1)
            local bx,by,bz=outward(b,i)
            local mx,my,mz=b.rx-a.rx,b.ry-a.ry,b.rz-a.rz
            local ox,oy,oz=bx-ax,by-ay,bz-az
            local ml=math.sqrt(mx*mx+my*my+mz*mz)
            local ol=math.sqrt(ox*ox+oy*oy+oz*oz)
            if ml>1e-4 and ol>1e-4 then
                worst=math.min(worst,(mx*ox+my*oy+mz*oz)/(ml*ol))
            end
        end
    end
    return worst
end
local raise=Vfx.New(Mock.Node('raise'),{worldRight=Vector3(1,0,0),worldUp=Vector3(0,1,0),worldDirection=Vector3(0,0,1)})
raise:Begin('moon')
for i=0,12 do
    local a=math.rad(-40+i*14)
    raise:Sample(Vector3(math.sin(a)*.5,1+i*.06,math.cos(a)*.5),Vector3(math.sin(a)*1.6,1.4+i*.10,math.cos(a)*1.6))
end
assert(edgeTurn(raise)>.5,'a rising swing with translation still reads as one smooth arc')

-- Seen from inside the swing plane a flat sheet is a line. The twist turns its width toward the
-- camera, so the crescent keeps a body from behind; face-on it must not move at all.
local edge=Vfx.New(Mock.Node('edge'),{worldRight=Vector3(1,0,0),worldUp=Vector3(0,1,0),worldDirection=Vector3(0,0,1)})
edge.twist=.92
edge:Begin('light');swing(edge,0,90,4)
local mid=math.floor(#edge.samples*.5)
assert(math.abs(edge.bwz[mid])<.35,'width turns broadside to the edge-on camera')
assert(math.abs(edge.bwy[mid])>.5,'the band lifts out of the swing plane toward the viewer')
-- One tilt per stroke: neighbouring cross-sections stay nearly parallel, so the ribbon never
-- winds up like a rope or folds into a crease.
for q=2,#edge.samples do
    local a,qc= q-1,q
    local dot=edge.bwx[a]*edge.bwx[qc]+edge.bwy[a]*edge.bwy[qc]+edge.bwz[a]*edge.bwz[qc]
    assert(dot>.985,'cross-sections twist smoothly along the arc')
end
local raised=0
for _,v in ipairs(drawn(edge)) do raised=math.max(raised,math.abs(v.position.y-1)) end
assert(raised>.2,'the drawn sheet has real depth, not a line')
for _,v in ipairs(drawn(fx)) do assert(math.abs(v.position.y-1)<1e-9,'a face-on camera is left untouched') end
for _,s in ipairs(edge.samples) do assert(math.abs(s.rx^2+s.rz^2-.04)<1e-6,'the arc itself never moves') end
-- A swing that covers 90 degrees in ONE frame is still the whole round arc.
local coarse=Vfx.New(Mock.Node('coarse'));coarse:Begin('light');swing(coarse,0,90,1)
assert(#coarse.samples>=15,'fast swings stay round');assert(math.abs(coarse.travel-fx.travel)<1e-6)
for _,q in ipairs(coarse.samples) do assert(math.abs(q.rx^2+q.rz^2-.04)<1e-6 and q.dx>-1e-6 and q.dz>-1e-6) end
-- Past 100 degrees per frame the turn direction of the swing decides the side, not the shortest way.
local spin=Vfx.New(Mock.Node('spin'));swing(spin,0,30,1);spin:Begin('heavy');swing(spin,30,240,1)
for _,q in ipairs(spin.samples) do assert(q.dx>-.9 or q.dz<0,'the arc goes round the front, not back across') end
assert(spin.travel>math.rad(200))
-- Same swing, same sheet: nothing is random.
local twin=Vfx.New(Mock.Node('twin'));twin:Begin('light');swing(twin,0,90,4)
assert(#twin.samples==#fx.samples and twin.vertices==fx.vertices,'deterministic')

-- Decay: it lingers whole, then the oldest end goes first, the head last, then everything is gone.
fx:Sample(Vector3(0/0,1,0),Vector3(0/0,1,1));assert(fx.stroke and fx.travel==fx.travel,'a NaN pose is ignored')
fx:Update(.06);swing(fx,90,180,4);fx:End()
local before=#fx.samples
assert(fx.samples[1].age>fx.samples[#fx.samples].age,'tail is older than head')
fx:Update(.3);assert(#fx.samples==before,'the whole crescent is still there .3s after the swing')
fx:Update(.17)
assert(#fx.samples<before and #fx.samples>0,'the tail expires while the head is still visible')
for _,s in ipairs(fx.samples) do assert(s.dz<1e-6,'what is left is the later half of the swing') end
fx:Update(.2)
assert(fx:Count()==0 and fx.vertices==0 and not fx.node.enabled,'fully gone, node hidden')

-- Only the swing draws the crescent. Follow-through (blade nearly stops turning while the hand
-- carries it back to guard) and a reversed turn end the stroke instead of bending it.
local follow=Vfx.New(Mock.Node('follow'));follow:Begin('light');swing(follow,0,90,4)
local drawnCount,headS=#follow.samples,follow.travel
for i=1,6 do
    local a=math.rad(90+i*.8)
    follow:Sample(Vector3(math.sin(a)*.2-i*.1,1-i*.08,math.cos(a)*.2),Vector3(math.sin(a)*1.1-i*.1,1-i*.08,math.cos(a)*1.1))
end
assert(#follow.samples==drawnCount and follow.travel==headS and not follow.stroke,'recovery motion adds no fold')
local back=Vfx.New(Mock.Node('back'));back:Begin('light');swing(back,0,60,3);drawnCount=#back.samples
swing(back,60,20,2);assert(#back.samples==drawnCount and not back.stroke,'a reversed turn ends the stroke')
-- A slow start does not end the stroke before the real swing arrives.
local slow=Vfx.New(Mock.Node('slow'));slow:Begin('light');swing(slow,0,3,3);assert(slow.stroke and #slow.samples<=3)
swing(slow,3,93,3);assert(slow.stroke and #slow.samples>10)

-- A cancelled move stops the stroke and the charge slivers, but the crescent already drawn fades on its own.
local cut=Vfx.New(Mock.Node('cut'));cut:Begin('light');swing(cut,0,90,4)
cut:Charge(Vector3(0,1,0),Vector3(0,1.9,0),.5,1);local kept=#cut.samples
cut:Stop();assert(#cut.samples==kept and cut:Count('charge')==0 and not cut.stroke)
swing(cut,90,120,2);assert(#cut.samples==kept,'nothing more is drawn after the cancel')
cut:Update(.3);assert(#cut.samples==kept and cut.node.enabled);cut:Update(.3);assert(cut:Count()==0)

-- A swing after a gap in blade tracking never bridges from the stale pose.
fx:Begin('light');swing(fx,0,20,2);fx:Update(.3);fx:Begin('light')
fx:Sample(Vector3(0,1,-.2),Vector3(0,1,-1.1));swing(fx,180,200,2)
local breaks=0
for _,s in ipairs(fx.samples) do if s.stroke then breaks=breaks+1 end end
assert(breaks==2,'two strokes, no quad between them')
fx:Clear();assert(fx:Count()==0 and not fx.node.enabled)

-- Hit: flash at the contact point, a cut line along the swing, shards thrown the way the blade travels.
fx:Begin('heavy');swing(fx,0,40,3)
local tx,tz=fx.tx,fx.tz
fx:Contact(Vector3(.5,1,.9),true)
assert(fx:Count('hit')==7)
for _,it in ipairs(fx.items) do
    assert(it.px==.5 and it.py==1 and it.pz==.9,'everything starts at the contact point')
    if it.kind=='spindle' then assert(math.abs(it.ax-tx)<1e-9 and math.abs(it.az-tz)<1e-9,'cut follows the swing') end
    if it.kind=='shard' then assert(it.ax*tx+it.az*tz>.6 and math.abs(it.ay)<.3,'shards leave along the swing') end
end
-- The shards spread into a cone, so the impact is not a flat fan of paper.
local cone=0
for _,it in ipairs(fx.items) do if it.kind=='shard' and math.abs(it.ay)>.05 then cone=cone+1 end end
assert(cone>0,'at least one shard leaves the swing plane')
local weak=Vfx.New(Mock.Node('weak'));weak:Begin('light');swing(weak,0,40,3);weak:Contact(Vector3(.5,1,.9),false)
assert(weak:Count('hit')==5,'a normal hit is smaller than a strong one')
fx:ClearSword()
assert(fx:Count('arc')==0 and fx:Count('hit')==7,'hit confirmation outlives the trail')
fx:Update(.5);assert(fx:Count()==0)

-- Finisher: one flash at the landing point, one raised crescent front pushed forward only.
fx:GroundWave(Vector3(0,0,0),Vector3(0,0,1))
assert(fx:Count('wave')==2)
fx:Update(.05);local near=0
for _,v in ipairs(drawn(fx)) do if v.color.g==0 then near=math.max(near,v.position.z);assert(v.position.z>.6-.9,'front stays ahead') end end
fx:Update(.2);local far=0
for _,v in ipairs(drawn(fx)) do if v.color.g==0 then far=math.max(far,v.position.z) end end
assert(far>near+.5,'the front travels outward over time')
fx:Update(1);assert(fx:Count()==0)

-- Charge slivers ride the blade; full charge replaces them with one flash.
local root,tip=Vector3(0,1,0),Vector3(0,1.9,0)
for i=0,60 do fx:Charge(root,tip,i/60,1/60);fx:Update(1/60) end
assert(fx:Count('charge')>0 and fx:Count('charge')<=4)
for _,v in ipairs(drawn(fx)) do assert(v.position.y>.8 and v.position.y<2.1 and math.abs(v.position.x)<.2,'slivers stay on the blade') end
fx:ChargeBurst(root,tip);assert(fx:Count('charge')==2)
fx:Update(1);assert(fx:Count()==0 and not fx.node.enabled)

-- Budgets hold under abuse, and nothing is created after construction.
fx:Begin('moon');for turn=0,5 do swing(fx,turn*360,turn*360+360,24) end
assert(#fx.samples<=Vfx.MAX_SAMPLES)
for _=1,100 do fx:Contact(Vector3(0,1,1),true) end
assert(#fx.items<=Vfx.MAX_ITEMS)
fx:Clear();assert(nodes(scene)==built,'no node is created after construction')
fx:Dispose()
print('PASS sword sheet vfx: full crescent behind the blade, lingers then tail-first decay, hit follows the swing, forward ground front, budgets')
