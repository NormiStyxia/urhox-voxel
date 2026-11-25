-- Lets the production SwordVfx run on weapon_mock: the mock material lacks SetSurfaceShader.
local S={}
function S.Install()
    local newMaterial=Material.new
    Material.new=function(...)
        local m=newMaterial(...)
        m.SetSurfaceShader=function(self,path) self.shader=path;return true end
        return m
    end
end
return S
