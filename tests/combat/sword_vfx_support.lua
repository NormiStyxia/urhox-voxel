-- Lets the production SwordVfx run on weapon_mock: StaticModel cubes, the
-- surface-shader material and the one quaternion call the mock lacks.
local Mock=require('weapon_mock')
local S={}
function S.Install()
    local newNode=Mock.Node
    Mock.Node=function(...)
        local n=newNode(...)
        local create=n.CreateComponent
        function n:CreateComponent(kind)
            if kind~='StaticModel' then return create(self,kind) end
            return {SetModel=function(self,m) self.model=m end,SetMaterial=function(self,m) self.material=m end}
        end
        return n
    end
    local newMaterial=Material.new
    Material.new=function(...)
        local m=newMaterial(...)
        m.SetSurfaceShader=function(self,path) self.shader=path;return true end
        return m
    end
    local getResource=cache.GetResource
    cache.GetResource=function(self,kind,path,...)
        if kind=='Model' then return {path=path} end
        return getResource(self,kind,path,...)
    end
    local Q=getmetatable(Quaternion())
    function Q:FromRotationTo(a,b)
        local c=a:CrossProduct(b)
        local w=1+a.x*b.x+a.y*b.y+a.z*b.z
        local l=math.sqrt(w*w+c:LengthSquared())
        if l<1e-9 then self.w,self.x,self.y,self.z=0,1,0,0
        else self.w,self.x,self.y,self.z=w/l,c.x/l,c.y/l,c.z/l end
    end
end
return S
