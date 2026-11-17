-- Rendered by RuinsHUD's pointer-transparent UI.Panel, in the same DPR space.
local Draw=require('ui.PixelDraw')
local H={}
-- Forge owns the visibility signal; the global survives module-cache key differences.
local forgeHiddenLogged=false
local forgeRead
function H.SetForgeVisibility(reader) forgeRead=reader end
local function ForgeHidden()
    local forge=package.loaded['ui.ForgePanel']
    local hidden=rawget(_G,'FORGE_HUD_HIDDEN')==true
        or (forgeRead and forgeRead()==true)
        or (type(forge)=='table' and forge.HudHidden and forge.HudHidden()==true)
    if hidden then
        if not forgeHiddenLogged then print('HUD: hidden by forge (layer=CombatHUD)');forgeHiddenLogged=true end
    elseif not (type(forge)=='table' and forge.IsOpen and forge.IsOpen()) then forgeHiddenLogged=false end
    return hidden
end
H.BOW_PREDICTION=true -- independently switchable; never changes actual shot direction
local bowPoint={visible=false,x=0,y=0}
local Moves=require('combat.CombatMoves')
local Perf=require('combat.SwingPerf')
local EMPTY={}
local rangePoints={}
for i=1,50 do rangePoints[i]={world=Vector3(0,0,0),visible=false,x=0,y=0} end
local rangeCount,rangeActive=0,false
-- Projection is outside Render; all point records and world vectors are reused.
function H.UpdateRange(value)
    rangeCount=0
    local moves=value and value.moves
    if not moves or not moves.StrikeZones or not value.combat or not value.camera or not value.rangeVisible then return end
    local zone,slam,active=moves:StrikeZones()
    rangeActive=active==true
    if not zone then return end
    local start=Perf.Begin()
    local total=(zone.angle==360 and 17 or 25)+(slam and (slam.angle==360 and 17 or 25) or 0)
    local budget=active and 8 or 4 -- two LOS rays per verified point, <=16/frame
    local phase=Perf.frame%total
    for pass=1,slam and 2 or 1 do
        local z=pass==1 and zone or slam
        local last=z.angle==360 and 16 or 24
        for i=0,last do
            rangeCount=rangeCount+1
            local point=rangePoints[rangeCount]
            if point.angle~=z.angle or point.radius~=z.radius or point.index~=i then
                local half=math.rad(z.angle*.5)
                local angle,radius
                if i<=16 then angle=-half+2*half*i/16;radius=z.radius
                else angle=i<=20 and -half or half;radius=z.radius*((i-17)%4)/4 end
                point.lx,point.lz=math.sin(angle)*radius,math.cos(angle)*radius
                point.angle,point.radius,point.index=z.angle,z.radius,i
            end
            local f=z.forward
            local w=point.world
            w.x,w.y,w.z=z.origin.x+point.lx*f.z+point.lz*f.x,z.origin.y+.04,z.origin.z+point.lz*f.z-point.lx*f.x
            point.world=w -- native value type: assign back
            point.visible=false -- never retain a prior frame's unverified point
            local slot=(rangeCount-1+phase)%total
            if math.floor(slot*budget/total)~=math.floor((slot+1)*budget/total) and Perf.rangeUsed<8 then
                Perf.rangeUsed=Perf.rangeUsed+1
                if value.rangeVisible(z.source,point.world) then
                    local sp=value.camera:WorldToScreenPoint(point.world)
                    point.x,point.y=sp.x,sp.y
                    point.visible=sp.x>=0 and sp.x<=1 and sp.y>=0 and sp.y<=1
                end
            end
        end
    end
    Perf.Finish('range',start)
end
local data=EMPTY
local debugLines={}
local debugText
local feedbackDebug,feedbackMetrics='',{}
local enemyScreen={visible=false}
-- Stamina wheel beside the player's right shoulder (screen fraction).
local staminaScreen={visible=false,x=0,y=0}
local staminaPoint=Vector3(0,0,0)
local STAMINA={255,214,92}
local STAMINA_OUT={232,76,60}
local headOffset=Vector3(0,0,0)
local PART_TEXT={}
local BOW_HINT={'弱蓄 · 松手射击 · 切换取消','中蓄 · 松手射击 · 切换取消','满蓄 · 松手射击 · 切换取消'}
local C=Draw.colors
local RED={240,91,76}
local HISTORY={103,62,66}
local trails=setmetatable({}, {__mode="k"})
local notice,noticeUntil='',0
local PART_NAMES={head='头部',foreleg_l='左前腿',foreleg_r='右前腿',back_armor='背甲',core='核心',body='躯干',belly='腹部',flank='侧腹'}
for id,name in pairs(PART_NAMES) do PART_TEXT[id]=name..' · 破甲' end
function H.Say(text,seconds) notice,noticeUntil=text,GetTime():GetElapsedTime()+(seconds or 1.2) end
-- First loss anchors the hold/catch-up window. Repeated hits change the target,
-- not its deadline; recovery/respawn snaps instead of showing phantom damage.
function H.HealthTrail(record,hp,now)
    if not record.hp or hp>record.hp then
        record.hp,record.shown,record.from,record.at=hp,hp,hp,nil
    elseif hp<record.hp then
        if not record.at then record.from,record.at=record.shown,now end
        record.hp=hp
    end
    if record.at then
        local t=math.max(0,math.min(1,(now-record.at-.12)/.25))
        record.shown=math.max(hp,record.from+(hp-record.from)*t)
        if t>=1 then record.at=nil end
    end
    return record.shown
end
function H.Set(value)
    data=value or EMPTY
    bowPoint.visible=false
    H.UpdateRange(value)
    if not value then trails=setmetatable({}, {__mode="k"}); enemyScreen.visible=false;enemyScreen.enemy=nil;debugText=nil;for i=#debugLines,1,-1 do debugLines[i]=nil end;return end
    if debugText~=data.debug then
        debugText=data.debug
        for i=#debugLines,1,-1 do debugLines[i]=nil end
        if debugText then for line in debugText:gmatch('[^\n]+') do debugLines[#debugLines+1]=line end end
    end
    local moves=data.moves
    if not moves then return end
    if data.debug then
        local d=feedbackMetrics
        if d.profile~=moves.lastProfile or d.stop~=moves.lastStop or d.flash~=moves.lastFlash
            or d.ready~=data.audioReady or d.kernels~=data.hitKernels or d.dropped~=data.hitDropped then
            d.profile,d.stop,d.flash=moves.lastProfile,moves.lastStop,moves.lastFlash
            d.ready,d.kernels,d.dropped=data.audioReady,data.hitKernels,data.hitDropped
            feedbackDebug=string.format('%s stop %.0fms flash %.0fms 核 %d ready %s dropped %d',
                d.profile or '-',(d.stop or 0)*1000,(d.flash or 0)*1000,d.kernels or 0,tostring(d.ready==true),d.dropped or 0)
        end
    end
    bowPoint.visible=false
    local predicted=data.bowPrediction
    if H.BOW_PREDICTION and predicted and predicted.valid and data.camera
        and (predicted.contact-data.cameraNode.worldPosition):DotProduct(data.cameraNode.worldDirection)>0 then
        local sp=data.camera:WorldToScreenPoint(predicted.contact)
        bowPoint.x,bowPoint.y=sp.x,sp.y
        bowPoint.visible=sp.x>0 and sp.x<1 and sp.y>0 and sp.y<1
    end
    staminaScreen.visible=false
    if data.combat and moves.stamina and moves.o and moves.o.position and data.camera then
        local p=moves.o.position()
        local right=data.cameraNode.worldRight
        staminaPoint.x,staminaPoint.y,staminaPoint.z=p.x+right.x*.55,p.y+1.35,p.z+right.z*.55
        if (staminaPoint-data.cameraNode.worldPosition):DotProduct(data.cameraNode.worldDirection)>0 then
            local sp=data.camera:WorldToScreenPoint(staminaPoint)
            staminaScreen.x,staminaScreen.y=sp.x,sp.y
            staminaScreen.visible=sp.x>0 and sp.x<1 and sp.y>0 and sp.y<1
        end
    end
    local aimedEnemy=data.aimed or (moves.age-(moves.targetAt or -100)<3 and moves.target)
    enemyScreen.visible=false
    if aimedEnemy and not aimedEnemy.boss and not aimedEnemy.dead and aimedEnemy.active and data.camera then
        headOffset.x,headOffset.y,headOffset.z=aimedEnemy.position.x,aimedEnemy.position.y+(aimedEnemy.config and aimedEnemy.config.height or 1.5)+.5,aimedEnemy.position.z
        if (headOffset-data.cameraNode.worldPosition):DotProduct(data.cameraNode.worldDirection)>0 then
            local sp=data.camera:WorldToScreenPoint(headOffset)
            enemyScreen.x,enemyScreen.y,enemyScreen.enemy=sp.x,sp.y,aimedEnemy
            enemyScreen.visible=sp.x>0 and sp.x<1 and sp.y>0 and sp.y<1
        end
    end
    for _,number in ipairs(moves.numbers or EMPTY) do
        if number.cachedValue~=number.value then number.cachedValue,number.text=number.value,Draw.Number(number.value) end
        number.screenVisible=false
        if number.untilTime>moves.age and data.camera and (number.pos-data.cameraNode.worldPosition):DotProduct(data.cameraNode.worldDirection)>0 then
            local sp=data.camera:WorldToScreenPoint(number.pos)
            number.screenX,number.screenY,number.screenVisible=sp.x,sp.y,true
        end
    end
    trails[moves]=trails[moves] or {}
    H.HealthTrail(trails[moves],moves.hp,moves.age)
    for _,enemy in ipairs(data.enemies or EMPTY) do
        trails[enemy]=trails[enemy] or {}
        H.HealthTrail(trails[enemy],enemy.hp,moves.age)
    end
end
-- Pure hit-clock output, used by the existing central crosshair renderer.
function H.HitPulse(moves)
    if not moves or not moves.lastHitAt then return nil end
    local age=moves.age-moves.lastHitAt
    if age<0 or age>= (moves.lastHitWeak and .18 or .08) then return nil end
    return age<.04 and 10 or 8,moves.lastHitWeak==true
end
function H.RenderHit(vg,x,y)
    if ForgeHidden() then return end
    local distance,weak=H.HitPulse(data.moves)
    if not distance then return end
    local color=weak and C.gold or C.paper
    for sx=-1,1,2 do for sy=-1,1,2 do
        local px,py=Draw.Snap(x+sx*distance),Draw.Snap(y+sy*distance)
        Draw.Rect(vg,px-(sx>0 and 4 or 0),py,6,2,color)
        Draw.Rect(vg,px,py-(sy>0 and 4 or 0),2,6,color)
    end end
end
function H.Active() return data.combat==true end
function H.Aimed() return data.aimed~=nil end
function H.Weapon() return data.weapon or 'sword' end
function H.Charge() return data.charge or 0 end
function H.CrossGap()
    local p=math.max(0,math.min(1,data.bowCameraCharge or 0))
    return 7-2*math.floor(p*2+.5) -- integer two-pixel steps; centre never moves
end
function H.Mounted() return data.mounted==true end
-- Only RuinsHUD renders this text: combat and pointer hints share one slot.
function H.Hint()
    local moves=data.moves
    if moves and moves.bowFailedUntil and moves.age<moves.bowFailedUntil then return '未发出' end
    if moves and (moves.clip=='bow_draw' or moves.clip=='bow_hold') then
        if moves.autoFire then return '自动蓄力中' end
        return BOW_HINT[moves.charge>=1 and 3 or (moves.charge>=.65 and 2 or 1)]
    end
    if moves and moves.cancelUntil and moves.age<moves.cancelUntil then return '已取消拉弓' end
    return noticeUntil>GetTime():GetElapsedTime() and notice or nil
end
function H.HasBoss()
    for _,enemy in ipairs(data.enemies or EMPTY) do if enemy.boss and enemy.aggro and not enemy.dead then return true end end
    return false
end
function H.Preview() return data.preview==true end
function H.Render(vg,w,h,s,objective)
    if ForgeHidden() then return end
    if not data.moves then return end
    local moves=data.moves
    for i=1,rangeCount do
        local point=rangePoints[i]
        if point.visible then
            local size=rangeActive and 4 or 2
            Draw.Rect(vg,Draw.Snap(point.x*w)-size/2,Draw.Snap(point.y*h)-size/2,size,size,C.gold,rangeActive and 1 or .55)
        end
    end
    local x,y=objective.x,objective.y+objective.h+8
    local columns=math.min(5,math.max(1,math.floor((w-s.right-x-32)/32)))
    local rows=math.ceil(10/columns)
    local shake=moves.invuln>.76 and (math.floor(moves.age*30)%2==0 and 2 or -2) or 0
    x=Draw.Snap(x+shake)
    Draw.NineSlice(vg,'plaque_ink',x,y,columns*32+24,rows*32+24,8,.9)
    for i=1,10 do
        local hp=moves.hp-(i-1)*10
        local icon=hp>=10 and 'heart_16' or (hp>0 and 'heart_half_16' or 'heart_empty_16')
        Draw.Image(vg,icon,x+12+((i-1)%columns)*32,y+12+math.floor((i-1)/columns)*32,1)
    end
    local trail=trails[moves]
    local barY=y+rows*32+16
    Draw.Rect(vg,x+12,barY,columns*32,4,C.deep)
    Draw.Rect(vg,x+12,barY,Draw.Snap(columns*32*(trail and trail.shown or moves.hp)/moves.maxHP),4,HISTORY)
    Draw.Rect(vg,x+12,barY,Draw.Snap(columns*32*moves.hp/moves.maxHP),4,RED)
    if moves.bowFullAt and moves.age-moves.bowFullAt>=0 and moves.age-moves.bowFullAt<.18
        and (moves.clip=='bow_hold' or moves.clip=='bow_draw') then
        Draw.Text(vg,'满蓄',Draw.Snap(w/2),Draw.Snap(h/2-34),12,C.gold,NVG_ALIGN_CENTER)
    end
    if bowPoint.visible then
        local px,py=Draw.Snap(bowPoint.x*w),Draw.Snap(bowPoint.y*h)
        -- Hollow 4dp contact marker, separate from the straight-ray reticle.
        Draw.Rect(vg,px-4,py-4,8,2,C.gold);Draw.Rect(vg,px-4,py+2,8,2,C.gold)
        Draw.Rect(vg,px-4,py-2,2,4,C.gold);Draw.Rect(vg,px+2,py-2,2,4,C.gold)
    end
    local stamina=moves.stamina
    if staminaScreen.visible and stamina then
        -- Fades out once full and untouched; red while exhausted or refused.
        local since=stamina.clock-stamina.shownAt
        local alpha=stamina.value<stamina.max and 1 or math.max(0,1-(since-1.2)/.4)
        if alpha>0 then
            local denied=stamina.clock-stamina.denyAt<.45 and math.floor((stamina.clock-stamina.denyAt)*12)%2==0
            local color=(stamina.exhausted or denied) and STAMINA_OUT or STAMINA
            local cx,cy=staminaScreen.x*w,staminaScreen.y*h
            Draw.Arc(vg,cx,cy,14,9,1,40,C.deep,.65*alpha)
            Draw.Arc(vg,cx,cy,14,9,stamina.value/stamina.max,40,color,alpha)
        end
    end
    if enemyScreen.visible then
        local enemy=enemyScreen.enemy
        local bx,by=Draw.Snap(enemyScreen.x*w-40),Draw.Snap(enemyScreen.y*h)
        Draw.Rect(vg,bx-2,by-2,84,10,C.deep)
        Draw.Rect(vg,bx,by,Draw.Snap(80*(trails[enemy] and trails[enemy].shown or enemy.hp)/enemy.maxHP),6,HISTORY)
        Draw.Rect(vg,bx,by,Draw.Snap(80*enemy.hp/enemy.maxHP),6,RED)
        local index=0
        for _,p in pairs(enemy.parts) do if p.maxArmor>0 then
            local ax=bx+index*12
            Draw.Rect(vg,ax,by+12,8,8,p.broken and RED or C.gold)
            if not p.broken then Draw.Rect(vg,ax,by+12+Draw.Snap(8*(1-p.armor/p.maxArmor)),8,Draw.Snap(8*p.armor/p.maxArmor),C.paper) end
            index=index+1
        end end
    end
    for _,boss in ipairs(data.enemies or EMPTY) do if boss.boss and boss.aggro and not boss.dead then
        local bw=math.min(320,w-s.left-s.right-32)
        local bx,by=Draw.Snap((w-bw)/2),Draw.Snap(s.top+24)
        Draw.NineSlice(vg,'bar_frame',bx,by,bw,36,6,1)
        Draw.Text(vg,'石甲兽',bx+bw/2,by-8,12,C.paper,NVG_ALIGN_CENTER)
        Draw.Rect(vg,bx+12,by+12,Draw.Snap((bw-24)*(trails[boss] and trails[boss].shown or boss.hp)/boss.maxHP),6,HISTORY)
        Draw.NineSlice(vg,'bar_fill_red',bx+12,by+12,Draw.Snap((bw-24)*boss.hp/boss.maxHP),6,0,1)
        Draw.NineSlice(vg,'bar_fill_blue',bx+12,by+20,Draw.Snap((bw-24)*(boss.poise or 0)/(boss.maxPoise or 100)),4,0,1)
        break
    end end
    local partNotice=moves.partNotice --[[@as {part:string,untilTime:number}|nil]]
    if partNotice and moves.age<partNotice.untilTime then
        local px,py=Draw.Snap(w/2-90),Draw.Snap(h*.3)
        local flash=math.floor(moves.age*16)%2==0
        Draw.Image(vg,'armor_break_s',px,py,1)
        if not PART_TEXT[partNotice.part] then PART_TEXT[partNotice.part]=partNotice.part..' · 破甲' end
        Draw.Text(vg,PART_TEXT[partNotice.part],px+48,py+20,12,flash and C.bright or C.paper)
    elseif moves.weakUntil and moves.age<moves.weakUntil then Draw.Text(vg,'弱点命中',w/2,h*.3,12,C.gold,NVG_ALIGN_CENTER) end
    for _,number in ipairs(moves.numbers or EMPTY) do
        if number.screenVisible then
            Draw.Text(vg,number.text,Draw.Snap(number.screenX*w),Draw.Snap(number.screenY*h-((number.duration or .7)-number.untilTime+moves.age)*24),12,C.gold,NVG_ALIGN_CENTER)
        end
    end
    if data.debug then
        local lines=debugLines
        Draw.NineSlice(vg,'plaque_ink',s.left+16,s.top+16,math.min(500,w-s.left-s.right-32),48+#lines*16,8,1)
        for i,line in ipairs(lines) do Draw.Text(vg,line,s.left+32,s.top+32+(i-1)*16,12,C.gold) end
        Draw.Text(vg,feedbackDebug,s.left+32,s.top+32+#lines*16,12,C.gold)
    end
end
return H
