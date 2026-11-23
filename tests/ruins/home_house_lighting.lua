-- Exercise the staged sockets returned by the production house builders with the real clock.
dofile('validation/night-fx/fixture.lua')
local Home=require('ruins.HomeIsland')
local DayNight=require('ruins.DayNight')
local Upper=require('ruins.HomeHouseUpper')
LIGHT_SPOT=3
local root=Node()
local nodes={}
function root:CreateChild(name)
    local n=Node(); n.name=name
    function n:CreateComponent(kind) assert(kind=='Light'); self.light={}; return self.light end
    function n:SetWorldDirection(v) self.direction=v end
    nodes[#nodes+1]=n
    return n
end
local function up(f,name)
    for i=1,100 do local k,v=debug.getupvalue(f,i); if k==name then return v end end
    error('missing house builder '..name)
end
local function noop() end
local function brush() return {Shape=noop,Box=noop,Carve=noop} end
local sockets={}
local groups={second={2,3},secondRoof={2,2},third={3,3}}
local function finish(name,_,first,last,options)
    if options.windowLamps then
        assert(options.masonry=='homeWindows')
        sockets[name]=options.windowLamps
        Home.RegisterWindowLamps(root,options.windowLamps,first,last)
    end
end
local function register()
    up(up(Home.Build,'house'),'firstStorey')({brush=brush,finish=finish})
    Upper.Build(brush,function(n,b,opt) finish(n,b,groups[n][1],groups[n][2],opt) end)
    assert(#sockets['ground-floor']==2 and #sockets.second==1 and #sockets.third==1 and not sockets.secondRoof)
    for _,group in ipairs({'second','third'}) do
        local s=sockets[group][1]; local matched=false
        for _,w in ipairs(Upper.Windows) do
            if w.group==group and w.nx==s.nx and w.nz==s.nz and math.abs(w.x+w.nx*.3125-s.x)<1e-6 and
                math.abs(w.z+w.nz*.3125-s.z)<1e-6 and math.abs(w.y-w.height/2+.5-s.y)<1e-6 then matched=true end
        end
        assert(matched,'missing recessed pane behind the registered lamp')
    end
end
register()
local zone,sun,sunNode={},{},Node()
local dn=DayNight.New({scene=Node(),zone=zone,zoneNode=Node(),sun=sun,sunNode=sunNode,hour=12})
local writes=0
local function material()
    return {SetShaderParameter=function(self,key,value) assert(key=='window_light'); self.light=value; writes=writes+1 end}
end
local mat,other=material(),material(); Home.BindWindowMaterial(mat); Home.BindWindowMaterial(other)
local hearth={}; Home.hearth=hearth
local function hour(h) dn:SetHour(h); Home.Update(1/60,nil,dn) end
local function count()
    local n=0
    for _,node in ipairs(nodes) do if node.enabled and not node.disposed then n=n+1 end end
    return n
end
local function snapshot(h)
    print(('clock %02d pane=%.4f spots=%d hearth=%.3f'):format(h,mat.light,count(),hearth.brightness))
    -- Optional observer used by the fixed-exposure offscreen fixture.
    if recordHouseLight then recordHouseLight(Home.GetHouseStage(),h,mat.light,dn,nodes) end
end
Home.SetWindowLightingActive(true,'medium'); assert(Home.SetHouseStage(3))
hour(12); assert(count()==0 and mat.light<=.05); snapshot(12); local noon=mat.light
hour(18); assert(count()==2 and mat.light>noon); snapshot(18); local dusk=mat.light
hour(0); assert(count()==2 and mat.light>dusk and mat.light<1 and mat.light==other.light); snapshot(0)
local fire=hearth.brightness
local maxReach=0
for _,node in ipairs(nodes) do
    local l,d=node.light,node.direction; assert(l.lightType==LIGHT_SPOT and l.castShadows==false and l.affectVolumetricFog==false)
    assert(l.fadeDistance<l.drawDistance and l.drawDistance<=28 and l.range<=1.05)
    local toward=math.atan(-d.z,-d.y)
    -- Conservative frustum bound, including the outer corner at full axial range.
    local reach=l.range*(math.sin(toward)+math.cos(toward)*math.tan(math.rad(l.fov*.5)))-.125
    assert(d.z<0 and d.y<0 and reach>0 and reach<.7);maxReach=math.max(maxReach,reach)
end
print(('PASS %d registered lamps maximum, %.3f m outer reach, %.0f..%.0f m draw fade'):format(#nodes,maxReach,nodes[1].light.fadeDistance,nodes[1].light.drawDistance))
for _,stage in ipairs({0,1,2,3,2,0,3}) do
    assert(Home.SetHouseStage(stage)); assert(count()==(stage==0 and 0 or 2)); assert((mat.light==0)==(stage==0))
    if stage>0 then
        local s=stage==1 and sockets['ground-floor'][2] or sockets[stage==2 and 'second' or 'third'][1]
        assert(math.abs(nodes[2].worldPosition.y-Home.base-s.y-.13)<1e-8)
    end
    assert(hearth.brightness==fire)
    if recordHouseLight then recordHouseLight(stage,0,mat.light,dn,nodes) end
end
Home.SetWindowLightingActive(true,'low'); assert(count()==1); local n=#nodes
Home.SetWindowLightingActive(false); assert(count()==0 and mat.light==0 and other.light==0 and hearth.brightness==fire)
Home.SetWindowLightingActive(true,'low'); assert(count()==1 and mat.light>dusk and hearth.brightness==fire)
Home.SetWindowLightingActive(true,'high'); assert(count()==2 and #nodes==n)
Home.BindWindowMaterial(mat); local initial=writes; local start=os.clock()
for i=1,10000 do Home.SetWindowLightingActive(true,'high'); Home.Update(1/60,nil,dn) end
assert(writes==initial and #nodes==n)
print(('PASS 10000 steady-clock frames, %d additional uploads, %d allocations, %.3f ms Lua CPU total'):format(writes-initial,#nodes-n,(os.clock()-start)*1000))
Home.Stop(); Home.Stop(); assert(count()==0 and mat.light==0 and nodes[1].disposed and nodes[2].disposed)
Home.BindWindowMaterial(mat); assert(mat.light==0); register(); assert(Home.SetHouseStage(1)); Home.SetWindowLightingActive(true,'low'); hour(0)
assert(count()==1 and #nodes==3 and not nodes[3].disposed and other.light==0); Home.Stop()
print('PASS four stages, both cached materials, quality changes, round trip, independent hearth, idempotent teardown and rebuild')
