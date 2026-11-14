from pathlib import Path
import json,shutil
m=json.loads(Path('validation/island-void/sync-manifest.json').read_text());w=Path(m['worktree']);v=w/'validation/island-void';v.mkdir(parents=True,exist_ok=True)
for f in ['check.py','check.lua','lsp_check.py']:shutil.copy2(Path('validation/island-void')/f,v/f)
shutil.copy2(Path(m['backup'])/'remote/scripts/ruins/RuinsTerrain.lua',v/'terrain-before.lua')
p=v/'check.lua';s=p.read_text()
s=s.replace("package.loaded['game.BlockCharacter']={SLENDER={},CreateVoxel=function() return {bones={},Update=noop} end}","package.loaded['game.BlockCharacter']={SLENDER={widen=Vector3(1,1,1)},CreateVoxel=function() return {bones={arm_right={CreateChild=function() return {} end}},Update=noop} end}")
s=s.replace("package.loaded['game.NomiVoxelData']={}","package.loaded['game.NomiVoxelData']={unit=.05}")
s=s.replace("local pa=assert(puzzle:find('local function BridgeVoxels(world)',1,true))","local pa=assert(puzzle:find('local BRIDGE_D',1,true))")
s=s.replace("abs=math.abs,Build={Marble=function() return 'MARBLE' end}","abs=math.abs,min=math.min,max=math.max,floor=math.floor,Hash3=require('ruins.Noise').Hash3,Build={DETAIL={column=.125},Marble=function() return 'MARBLE' end}")
a=s.index('local vox={}\nfor i=0,19');b=s.index("local realTO=",a)
s=s[:a]+'''local vox={}
local bs=bridge.bounds.size
local origin=Vector3(table.unpack(bridge.bounds.min))
local dims={}
for i=1,3 do dims[i]=math.floor((bridge.bounds.max[i]-bridge.bounds.min[i])/bs+.5) end
for i=0,dims[1]-1 do for j=0,dims[2]-1 do for k=0,dims[3]-1 do
    local m=MaterialAt(origin.x+(i+.5)*bs,origin.y+(j+.5)*bs,origin.z+(k+.5)*bs)
    if m then vox[#vox+1]={i,j,k,m} end
end end end
local previous=6
for z=-49.6875,-38.3125,bs do
    local edge=math.min(z+49.75,-38.25-z)
    local height=edge<.5 and 6.125 or 6.25
    assert(math.abs(height-previous)<=.125,'new bridge entry too high'); previous=height
    for x=-1.5,1.5,bs do
        assert(MaterialAt(x,height-bs*.5,z),'hole in new bridge walkway')
        assert(not MaterialAt(x,height+bs*.5,z),'blocked walkway')
    end
end
assert(math.abs(previous-6)<=.125)
assert(T.HeightAt(0,-49.75)==6 and T.HeightAt(0,-38.25)==6)
''' +s[b:]
s=s.replace("dims={20,15,46},size=.25,origin=Vector3(-2.5,3.5,-49.75)","dims=dims,size=bs,origin=origin")
s=s.replace("obj:Partition(2,{10,7.5,23})","obj:Partition(2,{dims[1]*.5,dims[2]*.5,dims[3]*.5})")
s=s.replace("Vector3(p.nx*.125,p.ny*.125,p.nz*.125)","Vector3(p.nx*bs*.5,p.ny*bs*.5,p.nz*bs*.5)")
s=s.replace("        assert(center.y-half:Length()>=9.49,'rune anchor reachable by jumping')",'''        assert(center.y-half:Length()>=9.49,'rune anchor reachable by jumping')
        local bank=i==1 and Vector3(0,7.65,-50.5) or Vector3(0,7.65,-37)
        assert((center-bank):Length()<15,'new fine shard anchor too far')
        local lip=i==1 and -49 or -39.25
        local t=(lip-bank.z)/(center.z-bank.z)
        assert(bank.y+(center.y-bank.y)*t>6.05,'fine shard anchor occluded by lip')''')
s=s.replace("continuous 3m walkway, y=6 both ends; ","continuous 3m walkway, .125 entry / .25 deck preserved; ")
p.write_text(s)
