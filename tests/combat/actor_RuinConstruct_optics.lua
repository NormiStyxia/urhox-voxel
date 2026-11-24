-- Shader/node contract, using actual attack updates and the normal cleanup entry points.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local H=require('combat.actor_roles_support')
Vector2=Vector2 or function(x,y) return {x=x,y=y} end
local FX=require('combat.enemies.actors.RuinConstructFX')
local target=Vector3(0,0,8)
local e=assert(H.newVisual('RuinConstruct'))
local marks=assert(e.optics.marks)
local normal=Vector3(.6,0,-.8)
e.world.RaycastSingle=function(_,ray,d)
    local denom=ray.direction.x*normal.x+ray.direction.z*normal.z
    if math.abs(denom)<.001 then return {hit=false} end
    local t=((4-ray.origin.z)*normal.z-ray.origin.x*normal.x)/denom
    return {hit=t>=0 and t<=d,distance=t,position=ray.origin+ray.direction*t,normal=normal}
end
e.aggro=true;e.lastTarget=target;e:Face(target);e.attackIndex=1;e:StartAttack()
H.T.Tick(e,.31,target);assert(marks[1].node.enabled and not marks[2].node.enabled)
H.T.Tick(e,.78,target);assert(marks[2].frame>=5 and not marks[3].node.enabled)
H.T.Tick(e,.25,target);assert(marks[3].node.enabled and marks[4].node.enabled and marks[5].node.enabled)
assert(marks[3].frame~=marks[4].frame and marks[3].runs==marks[4].runs)
local hit=e.beamWall
assert((marks[5].node.position-(hit.position+normal*.018)):Length()<.00001)
assert((marks[5].node.lookAt-marks[5].node.position-normal):Length()<.00001)
H.T.Tick(e,.56,target);assert(marks[6].node.enabled and e:PartEnabled(e.parts.core.spec))
assert(not marks[5].node.enabled and not marks[3].node.enabled)
assert(e:Stagger(.5,false));for _,m in ipairs(marks) do assert(not m.node.enabled) end
assert(not e:PartEnabled(e.parts.core.spec));e:SetActive(false);e:Destroy()
assert(marks[5].node.removed and marks[6].node.removed)

local get,new=cache.GetResource,Material.new
for _,failure in ipairs({'texture','shader','sampler'}) do
    cache.GetResource=function(c,k,p) if k=='Texture2D' and failure=='texture' then return nil end;return get(c,k,p) end
    Material.new=function(...)
        local m=new(...)
        if failure=='shader' then m.SetSurfaceShader=function() return false end end
        if failure=='sampler' then m.SetSurfaceTexture=function() return false end end
        return m
    end
    local fx=FX.New(H.scene);assert(not fx.marks)
    fx:Draw(Vector3.ZERO,Vector3.FORWARD,4,1,1,true,true,nil,.25)
    assert(fx.rings[1].enabled and fx.halo.enabled and fx.spine.enabled and fx.sparks[1].enabled)
    fx:Hide();assert(not fx.root.enabled);fx:Destroy()
end
Material.new,cache.GetResource=new,get
print('PASS construct optics: 6 painted layers, separate phases, oblique wall, vent gate, freeze, disposal, 3 fallback paths')
