-- 60 Hz rendered sword segment vs actual voxel-part OBBs, using real Apply/IK.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('anim_mock')
local A=require('combat.CombatAnim');local Data=require('combat.AnimClips')
local Model=require('game.NomiVoxelData')
local Parts=require('combat.WeaponParts');local Builder=require('combat.WeaponBuilder')
local config=Parts.DefaultWeapon('sword');config.weapon='sword'
local bp=Builder.Compile(config);assert(bp)
local bladeMin,bladeMax=math.huge,-math.huge
for _,blade in ipairs({'blade_straight','blade_broad','blade_rapier'}) do
config.parts.blade=blade;bp=Builder.Compile(config);assert(bp)
for _,cell in ipairs(bp.geometry.cells) do if cell.slot=='blade' then
 bladeMin=math.min(bladeMin,(cell.y-.5)*Parts.VOXEL_SIZE*1.25)
 bladeMax=math.max(bladeMax,(cell.y+.5)*Parts.VOXEL_SIZE*1.25)
end end
end
local parent,pivots,boxes={},{},{}
local function shape(name,x,y,z)
 if name=='head' then return x,y,z end
 return x*.85,y,-1+(z+1)*.92
end
for _,b in ipairs(Model.bones) do parent[b.name]=b.parent;pivots[b.name]=b.pivot end
for _,name in ipairs({'body','head','leg_left','leg_right'}) do
 local lo,hi={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
 local pivot=pivots[name];local px,py,pz=shape(name,table.unpack(pivot))
 for _,q in ipairs(Model.quads[name]) do
  local axis=math.ceil(q[1]/2);local plane=q[2]+(q[1]%2==1 and 1 or 0)
  local a,b
  if axis==1 then a={plane,q[4],q[3]};b={plane,q[4]+q[6],q[3]+q[5]}
  elseif axis==2 then a={q[3],plane,q[4]};b={q[3]+q[5],plane,q[4]+q[6]}
  else a={q[3],q[4],plane};b={q[3]+q[5],q[4]+q[6],plane} end
  for _,v in ipairs({a,b}) do
   local x,y,z=shape(name,v[1]+Model.origin[1],v[2]+Model.origin[2],v[3]+Model.origin[3])
   local sc=name=='head' and .82 or 1
   local p={(x-px)*Model.unit*sc,(y-py)*Model.unit*sc*(name:find('leg_',1,true) and 1.35 or 1),(z-pz)*Model.unit*sc}
   for i=1,3 do lo[i]=math.min(lo[i],p[i]);hi[i]=math.max(hi[i],p[i]) end
  end
 end
 boxes[name]={lo=lo,hi=hi}
end
local function inv(q)return Quaternion(q.w,-q.x,-q.y,-q.z)end
local function subtract(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
local function intersects(a,b,box)
 local lo,hi=0,1
 local av,bv={a.x,a.y,a.z},{b.x,b.y,b.z}
 for i=1,3 do
  local d=bv[i]-av[i]
  if math.abs(d)<1e-9 then if av[i]<box.lo[i] or av[i]>box.hi[i] then return false end
  else local t0,t1=(box.lo[i]-av[i])/d,(box.hi[i]-av[i])/d
   if t0>t1 then t0,t1=t1,t0 end
   lo,hi=math.max(lo,t0),math.min(hi,t1);if lo>hi then return false end
  end
 end
 return true
end
local failures,frames=0,0
for _,speed in ipairs({.5,.65,.8,1}) do
for _,tuck in ipairs({0,1}) do
for _,fade in ipairs({0,.08}) do
for _,id in ipairs({'sword_light_1','sword_light_2','sword_light_3','sword_light_4','sword_light_5','sword_heavy_charge','sword_heavy_release','plunge_start','plunge_loop','plunge_land'}) do
 local character=Mock.character();local base={}
 for name,node in pairs(character.bones) do
  local p=pivots[name]
  if p then
   local owner=parent[name] or name;local px,py,pz=0,0,0
   if parent[name] then px,py,pz=shape(owner,table.unpack(pivots[parent[name]])) end
   local x,y,z=shape(owner,table.unpack(p))
   node.position=Vector3((x-px)*Model.unit,(y-py)*Model.unit,(z-pz)*Model.unit)
   if name=='root' then node.position=Vector3(0,18*.35*Model.unit,0) end
   character.basePos[name]=node.position;base[name]=node.position
  end
 end
 local anim=A.New(character,nil,{quantize=false});anim:Play(id,{fadeIn=fade,fadeOut=fade,params={plungeSpeed=speed,plungeTuck=tuck}})
 local positions,rotations={},{}
 local function world(name)
  if positions[name] then return positions[name],rotations[name] end
  local n=character.bones[name];local p,r=n.position,n.rotation
  if parent[name] then local pp,pr=world(parent[name]);p=pp+pr*p;r=pr*r end
  positions[name],rotations[name]=p,r;return p,r
 end
 local duration=Data.Clips[id].dur;local previous=0
 for frame=0,math.ceil(duration*60) do
  local t=math.min(duration,frame/60)
  anim:Update(t-previous);previous=t
  for name,node in pairs(character.bones) do node.rotation=Quaternion(0,0,0);if base[name] then node.position=base[name] end end
  anim:Apply();anim:Poll();positions,rotations={},{}
  -- Last frame after clip auto-removal is base idle, not the authored final pose.
  if t<duration then
   local p,r=world('arm_right');local grip=r*Vector3(table.unpack(Data.RigReference.rightGrip))+p
   local offset,euler=anim:GetWeaponPose()
   local rot=r*Quaternion(90,0,0)*Quaternion(euler.x,euler.y,euler.z)
   grip=grip+r*offset
   local a=grip+rot*Vector3(0,.08,0)
   local b=grip+rot*Vector3(0,bladeMax,0)
   for name,box in pairs(boxes) do
    local origin,q=world(name)
    if intersects(inv(q)*subtract(a,origin),inv(q)*subtract(b,origin),box) then
     failures=failures+1;print(string.format('PENETRATION %s t=%.4f bone=%s fade=%.2f',id,t,name,fade))
    end
   end
   frames=frames+1
  end
 end
end
end
end end
assert(failures==0,'sword/body intersections: '..failures)
print('PASS real pose/socket sword OBB clearance frames='..frames..' blade='..bladeMin..'..'..bladeMax)
