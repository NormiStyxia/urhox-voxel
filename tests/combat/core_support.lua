-- Offline Vector3 math (no engine or Runtime). Anim tests supply quaternion math.
package.path='./scripts/?.lua;./tests/combat/?.lua;'..package.path
local AnimMock=require('anim_mock')
local V={}; V.__index=V
local function New(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.__add(a,b) return New(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return New(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__unm(a) return New(-a.x,-a.y,-a.z) end
function V.__mul(a,b) if type(a)=='number' then a,b=b,a end; return New(a.x*b,a.y*b,a.z*b) end
function V.__div(a,b) return a*(1/b) end
function V:LengthSquared() return self.x^2+self.y^2+self.z^2 end
function V:Length() return math.sqrt(self:LengthSquared()) end
function V:Normalized() local n=self:Length(); return n>0 and self/n or New() end
function V:DotProduct(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function V:Lerp(b,t) return self+(b-self)*t end
_G.Vector3=setmetatable({ZERO=New(),UP=New(0,1,0),RIGHT=New(1,0,0),FORWARD=New(0,0,1)}, {__call=function(_,...) return New(...) end})
return {anim=AnimMock,near=function(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b)) end}
