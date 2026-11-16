-- Secondary motion: coat / cloak / skirt / back hair trail the torso with a
-- slightly under-damped spring, so fast swings drag the cloth and it swings
-- past once before settling. Apply AFTER the frame's final torso pose
-- (BlockCharacter base + CombatAnim); multiplies onto freshly written bones.
---@class ClothInertia
---@field character table
---@field init boolean
---@field p number
---@field y number
---@field vp number
---@field vy number
---@field lagP number
---@field lagY number
local C={}
C.__index=C
local CLOTH={
    {name='coat_lower',pitch=.9,yaw=.55},
    {name='cloak',pitch=.9,yaw=.55},
    {name='skirt',pitch=.6,yaw=.35},
    {name='hair_back',pitch=.7,yaw=.6},
}
local K,D=140,9 -- stiffness/damping: zeta ~.38, one visible overshoot
local MAX_PITCH,MAX_YAW=28,40
local function wrap(a) return (a+180)%360-180 end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end

---@param character table BlockCharacter (bones table)
---@return ClothInertia
function C.New(character)
    return setmetatable({character=character,init=false,p=0,y=0,vp=0,vy=0,lagP=0,lagY=0},C)
end

---@param dt number
function C:Apply(dt)
    local bones=self.character and self.character.bones
    local body=bones and bones.body
    if not body or dt<=0 then return end
    local e=body.rotation:EulerAngles()
    if not self.init then self.p,self.y,self.init=e.x,e.y,true end
    -- Substep so 20-30 FPS stays stable with the stiff spring.
    local steps=math.min(4,math.ceil(dt/(1/60)))
    local h=math.min(dt,.1)/steps
    for _=1,steps do
        self.vp=self.vp+(K*wrap(e.x-self.p)-D*self.vp)*h
        self.vy=self.vy+(K*wrap(e.y-self.y)-D*self.vy)*h
        self.p=wrap(self.p+self.vp*h);self.y=wrap(self.y+self.vy*h)
    end
    -- Teleports / snaps: never let a stale spring whip the cloth around.
    if math.abs(wrap(self.p-e.x))>60 then self.p,self.vp=e.x,0 end
    if math.abs(wrap(self.y-e.y))>90 then self.y,self.vy=e.y,0 end
    self.lagP=clamp(wrap(self.p-e.x),-MAX_PITCH,MAX_PITCH)
    self.lagY=clamp(wrap(self.y-e.y),-MAX_YAW,MAX_YAW)
    if math.abs(self.lagP)<.05 and math.abs(self.lagY)<.05 then return end
    for _,c in ipairs(CLOTH) do
        local bone=bones[c.name]
        if bone then bone.rotation=bone.rotation*Quaternion(self.lagP*c.pitch,self.lagY*c.yaw,0) end
    end
end
return C
