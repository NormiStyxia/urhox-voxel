local Base=require('combat.enemies.EnemyBase')
---@class MossBeetle: EnemyBase
local Beetle=setmetatable({}, {__index=Base})
Beetle.__index=Beetle
Beetle.Config={kind='moss_beetle',enemy='beetle',name='苔壳虫',hp=30,poise=100,radius=.5,height=1,
    speed=2.1,aggro=9,leash=25,attackDistance=2,defaultPart='shell',voxelSize=.09,
    parts={
        {id='shell',material='armor',x=0,y=.48,z=-.05,radius=.51,armor=18},
        {id='side_l',material='soft',bone='belly',x=-.46,y=.30,z=.03,radius=.19,weak=true,weakMultiplier=1.4},
        {id='side_r',material='soft',bone='belly',x=.46,y=.30,z=.03,radius=.19,weak=true,weakMultiplier=1.4},
        {id='belly',material='soft',x=0,y=.16,z=.19,radius=.30,weak=true,weakMultiplier=1.4,recoveryOnly=true},
    },
    attacks={{name='pounce',telegraph=.6,duration=.2,recover=.8,travel=1.8,
        range=1.8,hitRange=.75,warning='ring',damage=10,poise=8,cosine=-.2}},
    -- name, center XYZ, radii XYZ, base / light / detail palette slots
    sculpt={
        {'body',0,.38,-.05,.48,.32,.58,200,201,202},
        {'shell',0,.57,-.1,.50,.23,.52,203,204,200},
        {'head',0,.35,.54,.25,.21,.24,202,201,205},
        {'belly',0,.18,.19,.35,.12,.36,206,201,206},
        {'leg_l',-.51,.17,.32,.22,.10,.12,202,204,202},
        {'leg_r',.51,.17,.32,.22,.10,.12,202,204,202},
        {'rear_l',-.48,.16,-.36,.23,.09,.12,202,204,202},
        {'rear_r',.48,.16,-.36,.23,.09,.12,202,204,202},
    }}
function Beetle.New(scene,world,terrain,combat,position,id)
    return setmetatable(Base.Create(scene,world,terrain,combat,Beetle.Config,position,id),Beetle)
end
function Beetle:Chase(dt,target,distance)
    self:Face(target)
    if distance<=self.config.attackDistance then
        self:StartAttack()
    else
        -- Orbit into bite distance, then commit to the readable straight lunge.
        local side=math.sin(self.age*.7)>.0 and 1 or -1
        self:Move((self.fx*.92+self.fz*.38*side)*self.config.speed*dt,
            (self.fz*.92-self.fx*.38*side)*self.config.speed*dt)
    end
end
---@return boolean
function Beetle:PartEnabled(spec)
    if spec.recoveryOnly then return self.state==Base.State.RECOVER and self.attack.name=='pounce' end
    return Base.PartEnabled(self,spec)
end
function Beetle:UpdatePose()
    Base.UpdatePose(self)
    -- Fixed roll exposes the underside for the entire advertised .8s window.
    if self.state==Base.State.RECOVER and self.attack.name=='pounce' then self.poseRoll=180 end
end
function Beetle:DamageScale(_,part)
    if part.spec.id=='shell' and self.state~=Base.State.RECOVER then return .7 end
    return 1
end
return Beetle
