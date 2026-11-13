-- Raw Touch events own fingers; UI.Panel owns rendering/lifetime. HUD never
-- participates in hit testing and mouse emulation is deliberately ignored.
local UI = require('urhox-libs/UI')
local Input = require('ui.TouchInput')
local Draw = require('ui.PixelDraw')
local M = { menuOpen=false }
local provider, onModeChanged, onCancel
local owners, buttons = {}, {}
local joy, lookID
local state = {}
local current, previous, transition = 'foot', nil, 5
local clock, idle, frame, fullFlash, lastCharge = 0, 0, 0, 0, 0
local releasedJoy, releasedFrame
local width, height, safe = 844,390,{left=0,right=0,top=0,bottom=0}
local oldEnabled=false
local wasBlocked=false
local started=false
---@type Node?
local eventNode
local eventObject
---@type table<string, table[]>
local SETS = {
    foot={
        {name='shatter',size=80,main=true,x=-48,y=-48},
        {name='jump',x=-48,y=-148}, {name='freeze',x=-148,y=-32},
        {name='rewind',x=-124,y=-124}, {name='mount',main=true,x=-212,y=-72},
    },
    ground={
        {name='breath',size=80,main=true,x=-48,y=-48},
        {name='ascend',x=-48,y=-148}, {name='dismount',x=-148,y=-32},
        {name='breathSpecial',icon='breath',label='大招',x=-124,y=-124},
    },
    air={
        {name='breath',size=80,main=true,x=-48,y=-48},
        {name='ascend',x=-48,y=-148}, {name='descend',x=-148,y=-32},
        {name='dash',x=-124,y=-124}, {name='land',x=-212,y=-72},
        {name='breathSpecial',icon='breath',label='大招',x=-196,y=-160},
    },
}
local TOP = {{name='menu',icon='menu'},{name='farview',icon='farview'},{name='fastTime',icon='clock'}}
local AIR_TOP = {{name='menu',icon='menu'},{name='glide',icon='glide'},{name='farview',icon='farview'},{name='fastTime',icon='clock'}}
local function TopButtons() return current=='air' and AIR_TOP or TOP end
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function Cancel()
    owners,buttons={},{}
    joy,lookID=nil,nil
    Input.Clear()
    if onCancel then onCancel() end
end
function M.Cancel() Cancel() end
function M.IsBlocked() return M.menuOpen or state.blocked == true end
function M.Hint()
    if state.charging then return '松手释放碎时' end
    if current=='ground' then return '点【起飞】升空 · 摇杆控制方向' end
    if current=='air' then return '按住【上升】/【下降】· 点【滑翔】省力' end
    if state.canMount then return '靠近龙，点【上龙】' end
    return '左摇杆移动 · 右侧拖动看四周'
end
function M.Sync()
    if provider then state=provider() or {} end
    width,height,safe=Draw.Metrics()
    local nextMode=state.mounted and (state.airborne and 'air' or 'ground') or 'foot'
    if nextMode~=current then
        previous,current,transition=current,nextMode,0
        -- A held ground button must not silently become an airborne button.
        -- Preserve joystick/look fingers; retire action fingers until lifted.
        for _,o in pairs(owners) do if o.kind=='button' then o.kind='retired' end end
        buttons={}
        Input.CancelActions()
        if onCancel then onCancel() end
    end
    if state.blocked and not wasBlocked then Cancel() end
    wasBlocked=state.blocked==true
    local enabled=Input.IsEnabled()
    if enabled~=oldEnabled then
        oldEnabled=enabled; Cancel(); M.menuOpen=false
        if onModeChanged then onModeChanged(enabled) end
    end
end
local function Visible(b)
    return b.name~='mount' or state.canMount==true
end
local function Disabled(b)
    if b.name=='shatter' or b.name=='freeze' or b.name=='rewind' then return (state.cool and (state.cool[b.name] or 0)>0) or state.noSpells end
    return state.mounting==true or (state.disabled and state.disabled[b.name])
end
local function Position(b,top,index)
    local x,y
    if top then x,y=width-safe.right-52-(index-1)*72,safe.top+52
    else x,y=width-safe.right-20+b.x,height-safe.bottom-20+b.y end
    local half=(b.size or 64)/2
    local minX=math.ceil((safe.left+20+half)/2)*2
    local minY=math.ceil((safe.top+20+half)/2)*2
    local maxX=math.max(minX,math.floor((width-safe.right-20-half)/2)*2)
    local maxY=math.max(minY,math.floor((height-safe.bottom-20-half)/2)*2)
    return Clamp(Draw.Snap(x),minX,maxX),Clamp(Draw.Snap(y),minY,maxY)
end
local function Hit(b,x,y,top,index)
    local bx,by=Position(b,top,index)
    return (x-bx)^2+(y-by)^2<=((b.size or 64)/2)^2
end
local function JoyMove(x,y)
    if not joy then return end
    local dx,dy=x-joy.x,y-joy.y
    local len=math.sqrt(dx*dx+dy*dy)
    local k=len>40 and 40/len or 1
    joy.dx,joy.dy=Draw.Snap(dx*k),Draw.Snap(dy*k)
    local magnitude=Clamp((len/40-.15)/.85,0,1)
    Input.SetMove(len>0 and -dy/len*magnitude or 0,len>0 and dx/len*magnitude or 0)
    Input.Set('sprint',current=='foot' and len>=36)
    local atTop=current~='foot' and -dy>=36 and math.abs(dx)<18
    if atTop and not joy.atTop then joy.flash=frame end
    joy.atTop=atTop
end
function M.BeginTouch(id,x,y)
    Input.OnTouch(); M.Sync()
    if not Input.IsEnabled() or state.blocked or owners[id] then return end
    idle=0
    -- Help is modal; all fingers are consumed until dismissed.
    if M.menuOpen then M.menuOpen=false; Cancel(); owners[id]={kind='retired'}; return end
    for i,b in ipairs(TopButtons()) do
        if Hit(b,x,y,true,i) then
            if b.name=='menu' then Cancel(); M.menuOpen=true; owners[id]={kind='retired'}
            elseif not buttons[b.name] then buttons[b.name]=id; owners[id]={kind='button',name=b.name}; Input.Set(b.name,true) end
            return
        end
    end
    for _,b in ipairs(SETS[current]) do
        if Visible(b) and Hit(b,x,y) then
            owners[id]={kind='retired'}
            if not Disabled(b) and buttons[b.name]==nil then
                buttons[b.name]=id; owners[id]={kind='button',name=b.name}; Input.Set(b.name,true)
            end
            return
        end
    end
    if x<width*.45 and y>height*.3 and not joy then
        joy={id=id,x=Draw.Snap(Clamp(x,math.ceil((safe.left+84)/2)*2,math.floor(math.max(safe.left+84,width*.45-64)/2)*2)),
            y=Draw.Snap(Clamp(y,math.ceil(math.max(safe.top+84,height*.3)/2)*2,math.floor(math.max(safe.top+84,height-safe.bottom-84)/2)*2)),dx=0,dy=0}
        owners[id]={kind='joy'}; releasedJoy=nil
    elseif x>=width*.5 and not lookID then
        lookID=id; owners[id]={kind='look',x=x,y=y}
    else owners[id]={kind='retired'} end
end
function M.MoveTouch(id,x,y)
    local o=owners[id]
    if not o then return end
    idle=0
    if o.kind=='joy' then JoyMove(x,y)
    elseif o.kind=='look' then Input.AddLook(x-o.x,y-o.y); o.x,o.y=x,y end
end
function M.EndTouch(id)
    local o=owners[id]
    if not o then return end
    if o.kind=='joy' then
        releasedJoy,releasedFrame=joy,frame
        joy=nil; Input.SetMove(0,0); Input.Set('sprint',false)
    elseif o.kind=='look' then lookID=nil
    elseif o.kind=='button' then buttons[o.name]=nil; Input.Set(o.name,false) end
    owners[id]=nil; idle=0
end
function M.Update(dt)
    if not provider then return end
    clock,idle,frame=clock+dt,idle+dt,frame+1
    transition=math.min(5,transition+1)
    if transition>=5 then previous=nil end
    M.Sync()
    -- Reconcile native owners if a backend drops cancelled touches without TouchEnd.
    if not input.focus or input.minimized then
        if next(owners) then Cancel() end
    else
        local live={}
        for i=0,input.numTouches-1 do live[input:GetTouch(i).touchID]=true end
        for id,o in pairs(owners) do
            if o.native and not live[id] then Cancel(); break end
        end
    end
    local charge=state.charge or 0
    if charge>=1 and lastCharge<1 then fullFlash=2 elseif fullFlash>0 then fullFlash=fullFlash-1 end
    lastCharge=charge
end
local function DrawSet(vg,mode,alpha,offset)
    for _,b in ipairs(SETS[mode]) do if Visible(b) then
        local x,y=Position(b)
        y=y+offset
        local down=mode==current and (Input.Down(b.name) or (b.name=='breath' and state.breathActive))
        local active=(b.name=='glide' and state.gliding) or (b.name=='dash' and down)
        local a=(down and 1 or (idle>=3 and .45 or .78))*alpha
        local cd=state.cool and state.cool[b.name] or 0
        local total=state.cooldown and state.cooldown[b.name] or 1
        local charge=b.name=='shatter' and (state.charge or 0) or 0
        Draw.Button(vg,b,x,y,a,down,active,Disabled(b),cd,total,charge)
        if b.name=='mount' or charge>0 then
            local step=math.floor(clock/.5)%2
            local r=(b.size or 64)/2+8+step*2
            Draw.Arc(vg,x,y,r,r-2,1,32,Draw.colors.bright,a*(step==1 and 1 or .5))
        end
        if charge>=1 and fullFlash>0 then Draw.Arc(vg,x,y,48,42,1,32,Draw.colors.bright,1) end
        local label=b.label or (b.name=='mount' and '上龙')
        if label then Draw.Text(vg,label,x,y+42,12,Draw.colors.gold,NVG_ALIGN_CENTER,a) end
    end end
end
local Layer=UI.Panel:Extend('RuinsTouchControls')
function Layer:Render(vg)
    if not Input.IsEnabled() or state.blocked then return end
    Draw.Begin(vg)
    local alpha=idle>=3 and .45 or .78
    if joy then
        local running=Input.Down('sprint')
        Draw.Image(vg,running and 'joy_base_run' or 'joy_base',joy.x-64,joy.y-64,1)
        Draw.Image(vg,'joy_thumb',joy.x+joy.dx-28,joy.y+joy.dy-28,1)
        if joy.flash==frame then Draw.Arc(vg,joy.x,joy.y,66,64,1,32,Draw.colors.bright,1) end
    else
        if releasedJoy and frame-releasedFrame<2 then
            Draw.Image(vg,'joy_base',releasedJoy.x-64,releasedJoy.y-64,(2-(frame-releasedFrame))*.25)
        end
        Draw.Image(vg,'joy_base',math.ceil((safe.left+20)/2)*2,math.floor((height-safe.bottom-148)/2)*2,.35)
    end
    if previous and transition<2 then DrawSet(vg,previous,transition==0 and 1 or .5,0) end
    local a=transition<2 and 0 or math.min(1,(transition-1)/3)
    if a>0 then DrawSet(vg,current,a,transition<4 and (4-transition)*2 or 0) end
    for i,b in ipairs(TopButtons()) do
        local x,y=Position(b,true,i)
        local down=Input.Down(b.name)
        Draw.Button(vg,b,x,y,down and 1 or math.min(.6,alpha),down,b.name=='glide' and state.gliding,false)
    end
    if M.menuOpen then
        local w=math.min(420,width-safe.left-safe.right-40)
        local x,y=Draw.Snap((width-w)/2),Draw.Snap(math.max(safe.top+20,(height-176)/2))
        Draw.NineSlice(vg,'panel_paper',x,y,w,176,8,1)
        local lines={'操作说明','左摇杆移动 · 右侧拖动看四周','按住碎时蓄力 · 松手释放碎时','按住【龙息】持续吐息 · 点【大招】施法','点【起飞】升空 · 摇杆控制方向','按住【上升】/【下降】· 点【滑翔】省力','轻触屏幕返回'}
        for i,line in ipairs(lines) do Draw.Text(vg,line,x+w/2,y+22+(i-1)*22,12,Draw.colors.brown,NVG_ALIGN_CENTER) end
    end
    Draw.Finish(vg)
end
function M.Attach(parent,getState,changed,cancelled)
    if not parent then return end
    provider,onModeChanged,onCancel=getState,changed,cancelled
    Input.Detect()
    if not started then
        eventNode=Node()
        eventObject=eventNode:CreateScriptObject('LuaScriptObject')
        eventObject:SubscribeToEvent('TouchBegin',function(_,t,d) RuinsTouch_Begin(t,d --[[@as TouchBeginEventData]]) end)
        eventObject:SubscribeToEvent('TouchMove',function(_,t,d) RuinsTouch_Move(t,d --[[@as TouchMoveEventData]]) end)
        eventObject:SubscribeToEvent('TouchEnd',function(_,t,d) RuinsTouch_End(t,d --[[@as TouchEndEventData]]) end)
        -- Optional host cancellation signal; unlike TouchEnd this must not cast.
        eventObject:SubscribeToEvent('TouchCancel',function() Cancel() end)
        eventObject:SubscribeToEvent('InputFocus',function(_,t,d) RuinsTouch_Focus(t,d --[[@as InputFocusEventData]]) end)
        eventObject:SubscribeToEvent('KeyDown',function(_,t,d) RuinsTouch_Key(t,d --[[@as KeyDownEventData]]) end)
        eventObject:SubscribeToEvent('EndFrame',function() Input.EndFrame() end)
        started=true
    end
    M.Reattach(parent)
    M.Sync()
end
function M.Reattach(parent)
    if parent then parent:AddChild(Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}) end
end
function M.Stop()
    Cancel(); provider,onModeChanged,onCancel=nil,nil,nil; M.menuOpen=false
    if eventObject then eventObject:UnsubscribeFromAllEvents() end
    if eventNode then eventNode:Remove() end
    eventObject,eventNode=nil,nil
    started=false;oldEnabled=false;wasBlocked=false;previous=nil;transition=5
end
---@param data TouchBeginEventData
function RuinsTouch_Begin(_,data)
    if not provider then return end
    local k=Draw.PixelToHUD()
    local id=data:GetInt('TouchID')
    M.BeginTouch(id,data:GetInt('X')*k,data:GetInt('Y')*k)
    for i=0,input.numTouches-1 do
        if input:GetTouch(i).touchID==id and owners[id] then owners[id].native=true; break end
    end
end
---@param data TouchMoveEventData
function RuinsTouch_Move(_,data)
    local k=Draw.PixelToHUD()
    M.MoveTouch(data:GetInt('TouchID'),data:GetInt('X')*k,data:GetInt('Y')*k)
end
---@param data TouchEndEventData
function RuinsTouch_End(_,data) M.EndTouch(data:GetInt('TouchID')) end
---@param data InputFocusEventData
function RuinsTouch_Focus(_,data)
    if not data:GetBool('Focus') or data:GetBool('Minimized') then Cancel() end
end
---@param data KeyDownEventData
function RuinsTouch_Key(_,data)
    if provider and data:GetInt('Key')==KEY_F9 and not data:GetBool('Repeat') then Input.Toggle(); M.Sync() end
end
function RuinsTouch_EndFrame() Input.EndFrame() end
return M
