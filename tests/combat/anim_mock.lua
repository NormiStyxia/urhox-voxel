-- Offline only. Quaternion math mirrors Qyaw * Qpitch * Qroll, not engine IO.
local M={}
local Q={}
Q.__index=Q
local V={}
local function vec(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
function V.__add(a,b) return vec(a.x+b.x,a.y+b.y,a.z+b.z) end
local function q(w,x,y,z) return setmetatable({w=w,x=x,y=y,z=z},Q) end
local function euler(p,y,r)
    p,y,r=math.rad(p)*.5,math.rad(y)*.5,math.rad(r)*.5
    local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
    return q(cy*cp*cr+sy*sp*sr,cy*sp*cr+sy*cp*sr,sy*cp*cr-cy*sp*sr,cy*cp*sr-sy*sp*cr)
end
function Q:FromEulerAngles(p,y,r)
    local v=euler(p,y,r)
    self.w,self.x,self.y,self.z=v.w,v.x,v.y,v.z
end
function Q.__mul(a,b)
    if b.w==nil then
        local v=a*q(0,b.x,b.y,b.z)*q(a.w,-a.x,-a.y,-a.z)
        return vec(v.x,v.y,v.z)
    end
    return q(a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,
        a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w)
end
function Q:Slerp(b,t)
    local dot=self.w*b.w+self.x*b.x+self.y*b.y+self.z*b.z
    local sign=dot<0 and -1 or 1
    dot=math.min(1,math.abs(dot))
    local aWeight,bWeight=1-t,t
    if dot<.9995 then
        local angle=math.acos(dot)
        aWeight,bWeight=math.sin((1-t)*angle)/math.sin(angle),math.sin(t*angle)/math.sin(angle)
    end
    bWeight=bWeight*sign
    local out=q(self.w*aWeight+b.w*bWeight,self.x*aWeight+b.x*bWeight,
        self.y*aWeight+b.y*bWeight,self.z*aWeight+b.z*bWeight)
    local len=math.sqrt(out.w^2+out.x^2+out.y^2+out.z^2)
    out.w,out.x,out.y,out.z=out.w/len,out.x/len,out.y/len,out.z/len
    return out
end
rawset(_G,"Quaternion",function(p,y,r) return euler(p or 0,y or 0,r or 0) end)
rawset(_G,"Vector3",vec)
function M.rotate(rot,x,y,z)
    local out=rot*q(0,x,y,z)*q(rot.w,-rot.x,-rot.y,-rot.z)
    return out.x,out.y,out.z
end
function M.character()
    local result={bones={},basePos={},time=0}
    for _,name in ipairs({"root","body","arm_right","arm_left","head","leg_right","leg_left","cloak"}) do
        result.bones[name]={position=Vector3(0,1,0),rotation=Quaternion(0,0,0),GetChild=function() return nil end}
        result.basePos[name]=Vector3(0,1,0)
    end
    local socket={worldPosition=Vector3(1,2,3),worldRotation=Quaternion(0,0,0)}
    result.bones.arm_right.GetChild=function(_,name) return name=="SpellPalm" and socket or nil end
    return result
end
function M.reset(character)
    for _,bone in pairs(character.bones) do bone.rotation=Quaternion(0,0,0);bone.position=Vector3(0,1,0) end
end
return M
