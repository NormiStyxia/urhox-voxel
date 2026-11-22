-- Static fallback for devices without GrassField. Each six-metre tile is a single mesh.
local Noise = require("ruins.Noise")
local M = {}
local BLOCK = 6
local sin, cos = math.sin, math.cos

local function emit(geo,x,y,z,uv,col)
    geo:DefineVertex(Vector3(x,y,z))
    geo:DefineNormal(Vector3.UP)
    geo:DefineColor(col)
    geo:DefineTexCoord(uv)
end

local function tuftMaterial()
    local mat=Material:new()
    if not mat:SetSurfaceShader("Shaders/BLGL/RuinsGrassTuft.shader") then
        mat:SetTechnique(0,cache:GetResource("Technique","Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor",Variant(Color(.36,.55,.24)))
        mat.cullMode=CULL_NONE
    end
    return mat
end

function M.Build(scene,field,checkpoint,sharedMaterial)
    local mat=sharedMaterial or tuftMaterial()
    local root=scene:CreateChild("GrassTufts")
    local rng=Noise.Rng(5150)
    local inner=field.COURT_R and field.COURT_R+6.5 or 0
    local extent=field.grassExtent or 68
    local originX,originZ=field.x or 0,field.z or 0
    local left,right,tip=Vector2(0,0),Vector2(1,0),Vector2(.5,1)
    local tiles={}
    local tufts=0
    for bx=-extent,extent-BLOCK,BLOCK do
        for bz=-extent,extent-BLOCK,BLOCK do
            local cx,cz=bx+BLOCK*.5,bz+BLOCK*.5
            local r=math.sqrt(cx*cx+cz*cz)
            if r>inner-5 and r<extent+4 then
                local geo,node
                for _=1,70 do
                    local x,z=originX+bx+rng:Next()*BLOCK,originZ+bz+rng:Next()*BLOCK
                    local w=field.GrassAt(x,z)
                    if w>.25 and rng:Next()<w and field.HasGround(x,z,1) then
                        local y=field.Height(x,z)
                        -- A blade base fits in a 20 cm square. Keep the tuft on one tread.
                        if not field.grassExtent or (field.Height(x-.1,z-.1)==y and field.Height(x+.1,z-.1)==y
                            and field.Height(x-.1,z+.1)==y and field.Height(x+.1,z+.1)==y) then
                            if not geo then
                                node=root:CreateChild("Tufts")
                                node.position=Vector3(originX+cx,y,originZ+cz)
                                geo=node:CreateComponent("CustomGeometry")
                                geo:BeginGeometry(0,TRIANGLE_LIST)
                            end
                            local blades=rng:Int(5,7)
                            local tint=.85+rng:Next()*.3
                            local col=rng:Next()<.12 and Color(1.35*tint,1.15*tint,.7*tint) or Color(tint,tint,tint)
                            local lx,ly,lz=x-originX-cx,y-node.position.y-.02,z-originZ-cz
                            for _=1,blades do
                                local a=rng:Next()*6.2832
                                local dx,dz=cos(a),sin(a)
                                local lean,h,wdt=.08+rng:Next()*.18,.22+rng:Next()*.3,.025+rng:Next()*.02
                                local px,pz=lx+dx*.06,lz+dz*.06
                                emit(geo,px-dz*wdt,ly,pz+dx*wdt,left,col)
                                emit(geo,px+dz*wdt,ly,pz-dx*wdt,right,col)
                                emit(geo,px+dx*lean,ly+h,pz+dz*lean,tip,col)
                            end
                            tufts=tufts+1
                        end
                    end
                end
                if geo then
                    geo:Commit();geo:SetMaterial(mat);geo.castShadows=false
                    tiles[#tiles+1]={node=node,drawable=geo}
                    if checkpoint and #tiles%3==0 then checkpoint() end
                end
            end
        end
    end
    print(string.format("GrassTufts: %d tufts in %d blocks",tufts,#tiles))
    return {root=root,material=mat,tiles=tiles}
end

return M
