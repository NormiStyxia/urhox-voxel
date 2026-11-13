-- Rendered by RuinsHUD's pointer-transparent UI.Panel, in the same DPR space.
local Draw=require('ui.PixelDraw')
local H={}
local data={}
local C=Draw.colors
local RED={240,91,76}
local HISTORY={103,62,66}
local trails=setmetatable({}, {__mode="k"})
local notice,noticeUntil='',0
local PART_NAMES={head='头部',foreleg_l='左前腿',foreleg_r='右前腿',back_armor='背甲',core='核心',body='躯干',belly='腹部',flank='侧腹'}
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
    data=value or {}
    if not value then trails=setmetatable({}, {__mode="k"}); return end
    local moves=data.moves
    if not moves then return end
    trails[moves]=trails[moves] or {}
    H.HealthTrail(trails[moves],moves.hp,moves.age)
    for _,enemy in ipairs(data.enemies or {}) do
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
    local distance,weak=H.HitPulse(data.moves)
    if not distance then return end
    local color=weak and C.gold or C.paper
    for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do
        local px,py=Draw.Snap(x+sx*distance),Draw.Snap(y+sy*distance)
        Draw.Rect(vg,px-(sx>0 and 4 or 0),py,6,2,color)
        Draw.Rect(vg,px,py-(sy>0 and 4 or 0),2,6,color)
    end end
end
function H.Active() return data.combat==true end
function H.Aimed() return data.aimed~=nil end
function H.Weapon() return data.weapon or 'sword' end
function H.Charge() return data.charge or 0 end
function H.Mounted() return data.mounted==true end
-- Only RuinsHUD renders this text: combat and pointer hints share one slot.
function H.Hint()
    local moves=data.moves
    if moves and (moves.clip=='bow_draw' or moves.clip=='bow_hold') then
        return (moves.charge>=.8 and '满蓄' or (moves.charge>=.3 and '中蓄' or '弱蓄'))..' · 松手射击 · 闪避取消'
    end
    if moves and moves.cancelUntil and moves.age<moves.cancelUntil then return '已取消拉弓' end
    return noticeUntil>GetTime():GetElapsedTime() and notice or nil
end
function H.HasBoss()
    for _,enemy in ipairs(data.enemies or {}) do if enemy.boss and enemy.aggro and not enemy.dead then return true end end
    return false
end
function H.Render(vg,w,h,s,objective)
    if not data.moves then return end
    local moves=data.moves
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
    local enemy=data.aimed or (moves.age-(moves.targetAt or -100)<3 and moves.target)
    if enemy and not enemy.boss and not enemy.dead and enemy.active and data.camera then
        local pos=enemy.position+Vector3(0,(enemy.config and enemy.config.height or 1.5)+.5,0)
        local delta=pos-data.cameraNode.worldPosition --[[@as Vector3]]
        if delta:DotProduct(data.cameraNode.worldDirection)>0 then
            local screen=data.camera:WorldToScreenPoint(pos)
            if screen.x>0 and screen.x<1 and screen.y>0 and screen.y<1 then
                local bx,by=Draw.Snap(screen.x*w-40),Draw.Snap(screen.y*h)
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
        end
    end
    for _,boss in ipairs(data.enemies or {}) do if boss.boss and boss.aggro and not boss.dead then
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
        Draw.Text(vg,(PART_NAMES[partNotice.part] or partNotice.part)..' · 破甲',px+48,py+20,12,flash and C.bright or C.paper)
    elseif moves.weakUntil and moves.age<moves.weakUntil then Draw.Text(vg,'弱点命中',w/2,h*.3,12,C.gold,NVG_ALIGN_CENTER) end
    for _,number in ipairs(moves.numbers or {}) do
        if number.untilTime>moves.age and data.camera and (number.pos-data.cameraNode.worldPosition):DotProduct(data.cameraNode.worldDirection)>0 then
            local sp=data.camera:WorldToScreenPoint(number.pos)
            Draw.Text(vg,tostring(number.value),Draw.Snap(sp.x*w),Draw.Snap(sp.y*h-((number.duration or .7)-number.untilTime+moves.age)*24),12,C.gold,NVG_ALIGN_CENTER)
        end
    end
    if data.debug then
        local lines={}
        for line in data.debug:gmatch('[^\n]+') do lines[#lines+1]=line end
        Draw.NineSlice(vg,'plaque_ink',s.left+16,s.top+16,math.min(500,w-s.left-s.right-32),32+#lines*16,8,1)
        for i,line in ipairs(lines) do Draw.Text(vg,line,s.left+32,s.top+32+(i-1)*16,12,C.gold) end
    end
end
return H
