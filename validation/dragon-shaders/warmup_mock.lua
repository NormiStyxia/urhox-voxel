-- Pure Lua mock only. Does NOT launch UrhoX or test rendering/compilation.
package.path = 'scripts/?.lua;' .. package.path
local Vec = {}; Vec.__index=Vec
Vec.__add=function(a,b) return setmetatable({x=a.x+b.x,y=a.y+b.y,z=a.z+b.z},Vec) end
Vec.__mul=function(a,b) return setmetatable({x=a.x*b,y=a.y*b,z=a.z*b},Vec) end
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},Vec) end})
Vector3.ZERO=Vector3(0,0,0); Vector3.ONE=Vector3(1,1,1)
Vector2=function(x,y) return {x=x,y=y} end
Rect=function(a,b,c,d) return {a,b,c,d} end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end
Variant=function(x) return x end
LOCAL=0
local Mat={}; Mat.__index=Mat
function Mat:Clone()
    local m=setmetatable({params={}},Mat)
    for k,v in pairs(self.params) do m.params[k]=v end
    return m
end
function Mat:SetShaderParameter(k,v) self.params[k]=v end
local function material() return setmetatable({params={strength=.7,alpha_scale=1}},Mat) end
local Draw={}; Draw.__index=Draw
function Draw:GetMaterial() return self.mat end
function Draw:SetMaterial(m) self.mat=m end
function Draw:SetRelative(x) self.relative=x end
function Draw:SetSorted(x) self.sorted=x end
function Draw:SetNumBillboards(x) self.n=x end
function Draw:GetBillboard(i) assert(i==0); return self.billboard end
function Draw:Commit() end
local Node={}; Node.__index=Node
local nodes={}
local function node(parent,name)
    local n=setmetatable({parent=parent,name=name,scene=parent and parent.scene or {},enabled=false},Node)
    nodes[#nodes+1]=n
    return n
end
function Node:CreateChild(name) return node(self,name) end
function Node:CreateComponent(kind)
    local d=setmetatable({node=self,kind=kind,mat=material(),inView=false,billboard={}},Draw)
    self.component=d; return d
end
function Node:GetComponent(kind) assert(self.component.kind==kind);return self.component end
function Node:Clone(mode)
    assert(mode==LOCAL)
    local n=node(self.parent,self.name)
    n:CreateComponent(self.component.kind):SetMaterial(self.component.mat)
    return n
end
function Node:SetParent(p) self.parent=p;self.scene=p.scene end
function Node:Remove() assert(not self.removed);self.removed=true;self.enabled=false end
local cam={nearClip=.1,node={worldPosition=Vector3.ZERO,worldDirection=Vector3(0,0,1),worldRotation={}}}
local vp={camera=cam}
renderer={GetViewportForScene=function(_,scene,i) assert(i==0);return vp end}
local Warmup=require('dragon.DragonShaderWarmup')
local function setup(withRing)
    local root=node(nil,'root')
    local ribbon=root:CreateChild('ribbon'); ribbon:CreateComponent('CustomGeometry')
    local mote=root:CreateChild('motes'):CreateComponent('BillboardSet')
    local ring=root:CreateChild('ring');ring:CreateComponent('CustomGeometry')
    return Warmup.New(root,ribbon,mote,withRing and ring or nil),ribbon,mote,ring
end
local function tick(w,busy,visible,dt)
    if w.drawable then w.drawable.inView=visible end -- simulate a completed render
    w:Update(dt or 1/60,busy or false)
    local count=0
    for _,n in ipairs(nodes) do
        if n.name:find('DragonWarmup') and n.enabled and not n.removed then count=count+1 end
    end
    assert(count<=1,'more than one shader warmup draw per frame')
end
local w,ribbon,mote,ring=setup(true)
for _=1,20 do tick(w) end
assert(not w.node,'created during initial busy scene frames')
for _=1,30 do tick(w,true) end
assert(not w.node,'created during held attack')
for _=1,30 do tick(w,false,false,.1) end
assert(not w.node,'created on slow frame')
vp=nil
for _=1,60 do tick(w) end
assert(not w.node,'created without matching viewport')
vp={camera=cam}
tick(w)
assert(w.node and w.stage==1 and w.drawable.mat.params.strength==0)
assert(w.node.worldPosition.z>cam.nearClip)
assert(w.node.scale.x>0 and not w.drawable.occludee and not w.drawable.castShadows)
tick(w,true,true)
assert(not w.node.enabled and w.stage==1,'attack did not pause warmup')
for _=1,50 do tick(w,false,true) end
assert(w.stage==2)
for _=1,45 do tick(w) end
assert(w.stage==2 and w.node)
assert(w.drawable.kind=='BillboardSet' and w.drawable.n==1)
assert(w.drawable.mat==mote.mat and w.drawable.billboard.color.a==0)
assert(w.drawable.billboard.uv[1]==0 and w.drawable.billboard.uv[4]==0)
for _=1,5 do tick(w,false,true) end
assert(w.stage==3)
for _=1,45 do tick(w) end
assert(w.drawable.mat.params.alpha_scale==0)
assert(ribbon.component.mat.params.strength==.7 and ring.component.mat.params.alpha_scale==1)
for _=1,5 do tick(w,false,true) end
assert(w.stage==4 and not w.node)
local created=#nodes
for _=1,1000 do tick(w,false,true) end
assert(#nodes==created,'warmup repeats after completion')
w:Destroy()
print('PASS warmup: idle gate, missing viewport, busy pause, three actual geometry variants, invisible materials, bounded draw count, source isolation, one-shot cleanup')
local timeout=setup(true)
for _=1,180 do tick(timeout,false,false) end
assert(timeout.stage==4 and not timeout.node,'unconfirmed warmup did not time out')
local cancelled=setup(true)
for _=1,50 do tick(cancelled) end
local proxy=cancelled.node
cancelled:Destroy()
assert(proxy.removed and not cancelled.node)
local noRing=setup(false)
for _=1,200 do tick(noRing,false,true) end
assert(noRing.stage==4 and not noRing.node)
print('PASS timeout, Destroy during active warmup, absent ring source')
