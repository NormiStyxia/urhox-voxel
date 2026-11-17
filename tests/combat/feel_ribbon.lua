-- Continuous crescent trail: shape, fade and steady-state allocation.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock');local Ribbon=require('combat.SlashRibbon')
local scene=Mock.Node('scene')
local r=Ribbon.New(scene)
local children=#scene.children
local root,tip=Vector3(0,1,0),Vector3(1,1,0)
-- Half-moon: 180 degrees of blade rotation in 6 frames at 30 Hz.
r:Begin('moon')
for i=0,6 do
    local a=i*math.pi/6
    tip.x,tip.z=math.cos(a),math.sin(a)
    r:Sample(root,tip);r:Update(1/30)
end
local g=r.geometry
assert(r.node.enabled and #g.vertices>0,'ribbon draws while swinging')
-- Interpolated samples: 30 degree frames split into <=12 degree steps.
assert(r.count>=6*3,'fast swing is subdivided into a smooth arc: '..r.count)
-- Tip edge brighter than inner edge; inner edge fully transparent.
local tipAlpha,innerAlpha=0,1
for _,v in ipairs(g.vertices) do
    local d=math.sqrt((v.position.x)^2+(v.position.z)^2)
    if d>.99 then tipAlpha=math.max(tipAlpha,v.color.a) end
    if d<.2 then innerAlpha=math.min(innerAlpha,v.color.a) end
end
assert(tipAlpha>.9 and innerAlpha==0,'hot tip, transparent hilt side')
-- Fades out after the swing ends.
r:End()
for _=1,30 do r:Update(1/30) end
assert(not r.node.enabled,'trail dissolves after its life')
-- Long steady swing: bounded ring, no new nodes.
r:Begin('light')
for i=1,300 do
    local a=i*.15;tip.x,tip.z=math.cos(a),math.sin(a)
    r:Sample(root,tip);r.geometry.vertices={};r:Update(1/60)
end
assert(r.count<=Ribbon.CAPACITY)
assert(#scene.children==children,'no nodes created after New')
r:Clear();assert(not r.node.enabled and r.count==0)
-- Cross slash: two strokes stay visible together and are never bridged.
r:Begin('cross')
local function stroke(x0,y0,x1,y1)
    for i=0,6 do
        local u=i/6;tip.x,tip.y,tip.z=x0+(x1-x0)*u,y0+(y1-y0)*u,1
        r:Sample(Vector3(0,1,0),tip);r.geometry.vertices={};r:Update(1/60)
    end
end
stroke(1,2,-1,0)      -- upper right -> lower left
r:End();for _=1,8 do r.geometry.vertices={};r:Update(1/60) end
r:Begin('cross');stroke(-1,2,1,0) -- upper left -> lower right
assert(r.node.enabled,'both diagonals visible at once')
local bridged=false
local vs=r.geometry.vertices
for i=1,#vs-2,3 do
    -- A bridge triangle joins the first stroke's end tip (-1,0) to the second's start tip (-1,2).
    local low,high=false,false
    for j=i,i+2 do
        local q=vs[j].position
        if q.x<-.9 and q.y<.3 then low=true end
        if q.x<-.9 and q.y>1.7 then high=true end
    end
    if low and high then bridged=true end
end
assert(not bridged,'second stroke never connects back to the first')
r:Dispose()
print('PASS slash ribbon: subdivided crescent, bright tip/transparent hilt, fades out, fixed node, crossed strokes stay separate')
