-- Offline checks for the generated thorn-flower bow (art/weapon_gen/thornbow_*.py) and its WeaponRig wiring.
-- Shader compilation / pixels / bend look still require Web preview.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local m=require('combat.models.ThornBow').Load()
assert(m.name=='thorn_bow' and m.scale==10000 and m.nscale==1000)
assert(m.body.triangles>=3000 and m.body.triangles<=8000,'body budget '..m.body.triangles)
assert(m.string.triangles>=4 and m.string.triangles<=40)
assert(#m.body.i==m.body.triangles*3 and #m.body.v%11==0)
assert(math.abs(m.height-1.0)<.03 and m.sockets.stringZ<-.08 and m.sockets.crystalTip>.12)
local function Check(part)
    local nv=#part.v//11
    local inwards,total=0,0
    for t=0,part.triangles-1 do
        local base={}
        for k=1,3 do
            local idx=part.i[t*3+k];assert(idx>=1 and idx<=nv)
            base[k]=(idx-1)*11
        end
        local p,n={}, {0,0,0}
        for k=1,3 do
            p[k]={part.v[base[k]+1],part.v[base[k]+2],part.v[base[k]+3]}
            for a=1,3 do n[a]=n[a]+part.v[base[k]+3+a] end
            for c=7,9 do local w=part.v[base[k]+c];assert(w>=0 and w<=100) end
        end
        local ux,uy,uz=p[2][1]-p[1][1],p[2][2]-p[1][2],p[2][3]-p[1][3]
        local vx,vy,vz=p[3][1]-p[1][1],p[3][2]-p[1][2],p[3][3]-p[1][3]
        local cx,cy,cz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
        total=total+1
        if cx*n[1]+cy*n[2]+cz*n[3]<0 then inwards=inwards+1 end
    end
    assert(inwards/total<.01,'winding must follow normals: '..inwards..'/'..total)
end
Check(m.body);Check(m.string)
-- the Blender export is symmetric about the grip within the limb span; origin = grip
assert(m.sockets.top[2]>.45 and m.sockets.bottom[2]<-.45)

-- WeaponRig wiring: material missing keeps the voxel bow; present swaps visuals.
local Rig=require('combat.WeaponRig')
local function NewRig()
    local scene=Mock.Node('scene');local world=Mock.World(scene);local nomi=Mock.Nomi(scene)
    return Rig.New(scene,world,nomi)
end
rawset(_G,'THORN_MATERIAL_MISSING',true)
local rig=NewRig();rig:SetActive('bow');rig:SetPose('hand');rig:Update(.3)
assert(rig.entries.bow.thorn==nil)
rawset(_G,'THORN_MATERIAL_MISSING',false)
rig=NewRig()
local thorn=rig.entries.bow.thorn
assert(thorn and not thorn.ready,'visual created, upload is spread over frames')
rig:SetActive('bow');rig:SetPose('hand')
for _=1,40 do rig:Update(.1) end
assert(thorn.ready,'visual finished building')
assert(thorn.geometry.commits==1 and #thorn.geometry.vertices==m.body.triangles*3)
assert(thorn.node.enabled,'bow visual shown in hand')
assert(rig.entries.bow.mesh.node.scale.x<.01,'voxel bow mesh hidden')
local half=rig.bowHalfHeight
assert(math.abs(thorn.scale*m.height-(half*2+.10)*require("combat.ThornBowVisual").SCALE)<1e-6)
-- draw: voxel string follows the pulled limb tips; voxel limb stage meshes stay hidden; static string hidden
rig:SetBowDraw(.9);rig:Update(0)
assert(rig.bowStage>=1)
for _,mesh in ipairs(rig.bowDrawMeshes) do assert(not mesh.node.enabled) end
assert(not thorn.stringNode.enabled and rig.bowStrings[1].node.enabled)
assert(thorn.bendKey==math.floor((.02+rig.bowStage*.03)*100+.5))
rig:CancelBow();rig:Update(0)
assert(thorn.stringNode.enabled and thorn.bendKey==0)
-- stowed on the back: arc profile faces the camera behind the character
rig:SetPose('back');for _=1,10 do rig:Update(.1) end
assert(rig.sockets.back_bow.rotation.y==90 or rig.sockets.back_bow.rotation.angles~=nil)
-- hidden / other weapon hides the visual
rig:SetPose('hidden');rig:Update(.1);assert(not thorn.node.enabled)
rig:SetActive('sword');rig:Update(.1);assert(not thorn.node.enabled)
rig:Dispose()
print('thorn_bow OK tris='..m.body.triangles)
