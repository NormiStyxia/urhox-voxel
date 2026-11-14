-- Forge (锻造库): clean dark-glass panel on the right, 3D showroom on the left.
-- UI owns the NanoVG frame and pointer dispatch; combat.ForgeShowroom owns the 3D room.
-- Public surface: Open / Close / ForceClose / IsOpen / PreviewMode.
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local G=require('ui.Glass')
local Parts=require('combat.WeaponParts')
local Builder=require('combat.WeaponBuilder')
local Store=require('combat.WeaponStore')
local CombatState=require('combat.CombatState')
local TouchInput=require('ui.TouchInput')
local M={}
---@class ForgeCallbacks
---@field rig? WeaponRig
---@field scene? Scene Scene that hosts the sky showroom (defaults to rig.scene).
---@field config? table Full WeaponStore configuration, copied on open.
---@field canOpen? fun():boolean Safe ground + no alert/mount/death/other modal.
---@field onOpen? fun()
---@field onApply? fun(config:table):boolean Single weapon; false keeps panel open.
---@field onEquip? fun(weapon:string):boolean False keeps panel open.
---@field onClose? fun(config:table,saved:boolean,keptDraft:boolean) Forced close calls immediately.
---@field say? fun(message:string)
---@type table?
local session
local drafts=setmetatable({}, {__mode='k'})
local C=G.colors
local SLOT_ORDER={sword={'blade','guard','grip','pommel'},bow={'limbs','grip','tip'}}
local CHANNEL_NAMES={primary='主色',secondary='副色',accent='点缀'}
local WEAPON_NAMES={sword='长剑',bow='长弓'}
local HELD_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L,KEY_ESCAPE}
local PAD=14
local FADE_OUT,REVEAL=.2,.3 -- seconds: to black / from black
local ROOM_TIMEOUT=6
local DARK_VOXEL={92,76,60}
local TAB_TOP,TAB_BOTTOM={70,58,34},{44,36,22}
local PANEL_TOP,PANEL_BOTTOM={19,30,50},{10,16,28}
local GOLD_TOP,GOLD_BOTTOM={244,210,128},{206,158,70}
local GOLD_DOWN_TOP,GOLD_DOWN_BOTTOM={200,156,72},{170,126,52}
local GOLD_RIM={255,236,170}
local MENU_FILL={16,24,40}
local FADE_CLEAR={10,16,28,0}
local FADE_SOLID={10,16,28,235}
local STAGE_TOP,STAGE_BOTTOM={16,26,44},{8,12,22}

-- The showroom is optional: a missing/broken module means the 2D side view.
local roomModule
local function Room()
    if roomModule==nil then
        local ok,mod=pcall(require,'combat.ForgeShowroom')
        roomModule=ok and type(mod)=='table' and mod or false
    end
    return roomModule or nil
end

local function Copy(t)
    if type(t)~='table' then return t end
    local result={}
    for k,v in pairs(t) do result[k]=Copy(v) end
    return result
end
local function Safe(callbacks)
    if CombatState.Get()~=CombatState.EXPLORE or (CombatState.HasAggro and CombatState.HasAggro()) then return false end
    if callbacks.canOpen then return callbacks.canOpen()==true end
    local controller=callbacks.rig and callbacks.rig.controller
    if not controller or not controller.cc or not controller.cc.onGround or not controller.Position then return false end
    local terrain=require('ruins.RuinsTerrain')
    local position=controller:Position()
    return terrain.IsSafeGround(position.x,position.y,position.z)==true
end
local function Single(config,weapon)
    return {weapon=weapon,parts=config[weapon].parts,colors=config[weapon].colors}
end
local function Clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function Inside(x,y,b) return x>=b.x and y>=b.y and x<b.x+b.w and y<b.y+b.h end
local function Box(x,y,w,h) return {x=math.floor(x+.5),y=math.floor(y+.5),w=math.floor(w+.5),h=math.floor(h+.5)} end
-- i-th of n equal cells in [x,x+w) with a gap; integer edges so neighbours never overlap.
local function Span(x,w,i,n,gap)
    local left=math.floor(x+(i-1)*(w+gap)/n+.5)
    local right=math.floor(x+i*(w+gap)/n-gap+.5)
    return left,right-left
end
local function Message(s,text)
    s.message=text
    if s.callbacks.say then s.callbacks.say(text) end
end

---------------------------------------------------------------- showroom glue
local function DestroyRoom(s)
    if not s.room then return end
    s.room,s.roomReady=false,false
    local room=Room()
    if room then pcall(room.Exit) end
end
local function Fallback(s,reason,detail)
    if s.fallback then return end
    DestroyRoom(s)
    s.fallback=true
    s.previewMode='fallback'
    print('Forge preview: fallback ('..reason..')'..(detail and (' '..tostring(detail):gsub('[\r\n]+',' '):sub(1,200)) or ''))
end
local function Single3D(s)
    local room=Room()
    if not room or not s.room then return end
    local ok,reason=pcall(room.SetWeapon,Single(s.config,s.weapon))
    if not ok then Fallback(s,'mesh',reason) end
end
local function EnterRoom(s)
    local room=Room()
    local scene=s.callbacks.scene or (s.callbacks.rig and s.callbacks.rig.scene)
    if not room or not scene then Fallback(s,'unavailable');return end
    local focus=(s.stage.x+s.stage.w*.5)/math.max(1,s.width)
    local ok,entered=pcall(room.Enter,scene,{focusX=focus})
    if not ok or entered~=true then Fallback(s,'enter',not ok and entered or nil);return end
    s.room,s.roomWait=true,0
    Single3D(s)
end

---------------------------------------------------------------- stats
local STAT_MAIN={
    sword={{'attack','攻击',20,''},{'speed','速度',1.4,'×'},{'reach','范围',1.4,'m'}},
    bow={{'draw','拉弓速度',1.5,'×'},{'range','射程',60,'m'},{'move','移动',1,'×'}},
}
local STAT_MORE={
    sword={{'poise','失衡',12,''},{'armorBreak','破甲',2,'×'}},
    bow={{'armorBreak','破甲',2,'×'}},
}
local function Number(value,unit)
    if math.abs(value-math.floor(value+.5))<.001 then
        return unit=='×' and string.format('%.1f',value) or tostring(math.floor(value+.5))
    end
    return (string.format('%.2f',value):gsub('0+$',''):gsub('%.$',''))
end
local function StatValue(blueprint,key)
    if key=='reach' then return blueprint.hit.length*(blueprint.stats.reach or 1) end
    if key=='draw' then return Parts.BaseStats.bow.draw/blueprint.stats.draw end
    return blueprint.stats[key] or 0
end
local function StatRows(s,list)
    local rows={}
    for i,entry in ipairs(list) do
        local key,unit=entry[1],entry[4]
        local value,before=StatValue(s.blueprint,key),StatValue(s.baseline,key)
        local delta=value-before
        rows[i]={key=key,label=entry[2]..(unit~='' and (' '..unit) or ''),
            before=Number(before,unit),value=Number(value,unit),changed=math.abs(delta)>.001,
            text=math.abs(delta)>.001 and (Number(before,unit)..' → '..Number(value,unit)) or Number(value,unit),
            fraction=Clamp(value/entry[3],0,1),
            delta=math.abs(delta)>.001 and ((delta>0 and '+' or '-')..Number(math.abs(delta),unit)) or nil,
            up=delta>0}
    end
    return rows
end

---------------------------------------------------------------- state changes
local Layout
local function Rebuild(s)
    local previous=s.blueprint
    s.blueprint=assert(Builder.Compile(Single(s.config,s.weapon)))
    s.baseline=assert(Builder.Compile(Single(s.original,s.weapon)))
    s.flash={}
    s.statRows,s.moreRows=nil,nil
    s.sideview=nil
    if previous and previous.geometry.weapon==s.weapon then
        for key,value in pairs(s.blueprint.stats) do
            if previous.stats[key]~=value then s.flash[key]=.35 end
        end
        if previous.hit.length~=s.blueprint.hit.length then s.flash.reach=.35 end
    end
    Single3D(s)
end
local function Edit(s,action)
    s.undo={config=Copy(s.config),weapon=s.weapon,slot=s.slot}
    action();Rebuild(s);Layout(s)
end
local function Add(s,id,label,box,action,options)
    local button=options or {}
    button.id,button.label,button.box,button.action=id,label,box,action
    s.buttons[#s.buttons+1]=button
    return button
end
local function CloseMenu(s) if s.menuOpen then s.menuOpen=false;Layout(s) end end

---------------------------------------------------------------- layout
Layout=function(s)
    local w,h,safe=Draw.Metrics()
    s.width,s.height=w,h
    s.safeLeft,s.safeTop,s.safeRight,s.safeBottom=safe.left,safe.top,safe.right,safe.bottom
    local x0,y0=safe.left+10,safe.top+8
    local x1,y1=w-safe.right-10,h-safe.bottom-8
    local aw,ah=x1-x0,y1-y0
    local pw=math.min(aw,Clamp(math.floor(aw*.44),300,360))
    local panel=Box(x1-pw,y0,pw,ah)
    s.panel=panel
    s.stage=Box(x0,y0,math.max(0,aw-pw-12),ah)
    local ix,iw=panel.x+PAD,panel.w-2*PAD
    s.ix,s.iw=ix,iw
    s.buttons={}
    -- header: title, weapon segmented control, close
    local hy=panel.y+10
    s.titlePos={x=ix,y=hy+20}
    local tabW=math.min(70,math.floor((iw-84-48)/2))
    s.tabsBox=Box(ix+84,hy+2,tabW*2,36)
    for i,weapon in ipairs({'sword','bow'}) do
        Add(s,'tab_'..weapon,weapon=='sword' and '剑' or '弓',Box(ix+84+(i-1)*tabW,hy+2,tabW,36),function()
            if s.weapon==weapon then return end
            s.weapon=weapon;s.slot=SLOT_ORDER[weapon][1];s.scroll=0;s.colorChannel=nil;s.moreOpen=false
            Rebuild(s);Layout(s)
        end,{kind='tab',active=s.weapon==weapon,icon=weapon..'_s'})
    end
    Add(s,'close','关闭',Box(ix+iw-34,hy-2,44,44),function() M.Close() end,{kind='close'})
    -- footer: recommended menu / undo / equip
    local fy=panel.y+panel.h-PAD-44
    local equipW,undoW=104,64
    local recW=iw-equipW-undoW-16
    s.footerY=fy
    Add(s,'recommend','推荐方案',Box(ix,fy,recW,44),function() s.menuOpen=not s.menuOpen;Layout(s) end,{kind='plain',menuToggle=true,active=s.menuOpen})
    Add(s,'undo','撤销',Box(ix+recW+8,fy,undoW,44),function()
        if not s.undo then return end
        s.config,s.weapon,s.slot=s.undo.config,s.undo.weapon,s.undo.slot;s.undo=nil
        Rebuild(s);Layout(s)
    end,{kind='plain',disabled=not s.undo})
    Add(s,'equip','装备',Box(ix+iw-equipW,fy,equipW,44),function() M.Close() end,{kind='primary'})
    -- scrolling viewport
    local vy=hy+46
    local vh=fy-8-vy
    s.view=Box(panel.x+2,vy,panel.w-4,vh)
    local cy=vy
    local slots=SLOT_ORDER[s.weapon]
    for i,slot in ipairs(slots) do
        local sx,sw=Span(ix,iw,i,#slots,6)
        Add(s,'slot_'..slot,Parts.SlotNames[slot],Box(sx,cy,sw,34),function() s.slot=slot;Layout(s) end,
            {kind='slot',area='scroll',active=s.slot==slot})
    end
    cy=cy+34+8
    local options=Parts.GetOptions(s.weapon,s.slot)
    for i,part in ipairs(options) do
        local cx,cw=Span(ix,iw,i,#options,8)
        local card=Box(cx,cy,cw,84)
        local b=Add(s,'part_'..part.id,part.name,card,function()
            Edit(s,function() s.config[s.weapon].parts[s.slot]=part.id end)
        end,{kind='card',area='scroll',active=s.config[s.weapon].parts[s.slot]==part.id,part=part})
        b.thumb=Box(card.x+8,card.y+8,card.w-16,46)
    end
    cy=cy+84+8
    s.statsBox=Box(ix,cy,iw,58)
    cy=cy+58+8
    for i,channel in ipairs(Parts.Channels) do
        local preset=Parts.ColorPresets[s.config[s.weapon].colors[channel]]
        local chx,chw=Span(ix,iw,i,3,8)
        Add(s,'color_'..channel,CHANNEL_NAMES[channel],Box(chx,cy,chw,38),function()
            s.colorChannel=s.colorChannel~=channel and channel or nil;Layout(s)
            if s.colorChannel then s.scroll=s.maxScroll end
        end,{kind='chip',area='scroll',swatch=preset.rgb,active=s.colorChannel==channel})
    end
    cy=cy+38+8
    s.paletteBox=nil
    if s.colorChannel then
        local current=s.config[s.weapon].colors[s.colorChannel]
        s.paletteTitle={x=ix,y=cy+10,text=CHANNEL_NAMES[s.colorChannel]..' · '..Parts.ColorPresets[current].name}
        cy=cy+22
        local count=#Parts.ColorPresets
        s.paletteBox=Box(ix,cy,iw,44)
        for i,preset in ipairs(Parts.ColorPresets) do
            local px,pw=Span(ix,iw,i,count,0)
            Add(s,'swatch_'..i,preset.name,Box(px,cy,pw,44),function()
                Edit(s,function() s.config[s.weapon].colors[s.colorChannel]=i end)
            end,{kind='swatch',area='scroll',swatch=preset.rgb,active=current==i})
        end
        cy=cy+44+8
    end
    Add(s,'more',s.moreOpen and '收起数值' or '更多数值',Box(ix,cy,iw,36),function() s.moreOpen=not s.moreOpen;Layout(s) end,
        {kind='link',area='scroll'})
    cy=cy+36
    s.moreBox=nil
    if s.moreOpen then
        s.moreRows=s.moreRows or StatRows(s,STAT_MORE[s.weapon])
        s.moreBox=Box(ix,cy,iw,#s.moreRows*24+4)
        cy=cy+s.moreBox.h
    end
    cy=cy+6
    s.descriptionLines=G.Wrap(assert(Parts.Get(s.config[s.weapon].parts[s.slot])).desc,13,iw-4)
    s.descriptionBox=Box(ix,cy,iw,#s.descriptionLines*19)
    cy=cy+s.descriptionBox.h+6
    s.contentHeight=cy-vy
    s.maxScroll=math.max(0,s.contentHeight-vh)
    s.scroll=Clamp(s.scroll,0,s.maxScroll)
    -- recommended menu (drop-up above the footer)
    if s.menuOpen then
        local items={}
        for _,preset in ipairs(Parts.Presets) do
            items[#items+1]={id='preset_'..preset.id,label=preset.name,action=function()
                Edit(s,function() s.config[s.weapon]=assert(Parts.Preset(s.weapon,preset.id)) end)
            end}
        end
        items[#items+1]={id='slot_reset',label='单槽复原',gap=true,action=function()
            Edit(s,function() s.config[s.weapon].parts[s.slot]=s.original[s.weapon].parts[s.slot] end)
        end}
        items[#items+1]={id='reset',label='恢复默认',action=function()
            Edit(s,function() s.config[s.weapon]=Parts.DefaultWeapon(s.weapon) end)
        end}
        local mh=#items*40+12
        local menu=Box(ix,fy-8-mh,math.min(170,iw),mh)
        s.menuBox=menu
        for i,item in ipairs(items) do
            Add(s,item.id,item.label,Box(menu.x+6,menu.y+6+(i-1)*40,menu.w-12,40),function()
                s.menuOpen=false
                item.action()
                Layout(s)
            end,{kind='menu',area='menu',gap=item.gap})
        end
    else s.menuBox=nil end
    s.statRows=s.statRows or StatRows(s,STAT_MAIN[s.weapon])
    local previewing=s.blueprint.geometry.cells
    s.sideBox=Box(s.stage.x+16,s.stage.y+60,math.max(1,s.stage.w-32),math.max(1,s.stage.h-110))
    s.sideCells=previewing
    local part=Parts.Get(s.config[s.weapon].parts[s.slot])
    s.subtitle='正在编辑 · '..Parts.SlotNames[s.slot]..' · '..part.name
end

---------------------------------------------------------------- pointer
local function At(s,x,y)
    if s.menuOpen then
        for _,button in ipairs(s.buttons) do
            if button.area=='menu' and Inside(x,y,button.box) then return button end
        end
        return nil
    end
    for _,button in ipairs(s.buttons) do
        if not button.area and Inside(x,y,button.box) then return button end
    end
    if Inside(x,y,s.view) then
        for _,button in ipairs(s.buttons) do
            if button.area=='scroll' and Inside(x,y+s.scroll,button.box) then return button end
        end
    end
end
local function Coordinates(event)
    local k=UI.GetScale()*Draw.PixelToHUD()
    return event.x*k,event.y*k
end
local function Consume(event) event:StopPropagation(); event:PreventDefault() end
local function Home(s)
    local room=Room()
    if s.room and room then pcall(room.Home) end
end
local function Down(event)
    Consume(event)
    local s=session
    if not s or s.closing or s.pointer or s.phase~='open' then return end
    if event.pointerType=='mouse' and not event:IsPrimaryButton() then return end
    local x,y=Coordinates(event)
    local button=At(s,x,y)
    if s.menuOpen and not button then CloseMenu(s);return end
    s.pointer={id=event.pointerId,x=x,y=y,startX=x,startY=y,button=button,t=s.clock,vx=0,
        stage=not button and x<s.panel.x and not s.menuOpen,view=Inside(x,y,s.view)}
end
local function Move(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not s or not p or event.pointerId~=p.id then return end
    local x,y=Coordinates(event)
    if math.abs(x-p.startX)+math.abs(y-p.startY)>8 then p.moved=true end
    if p.moved then
        local dx=x-p.x
        if p.stage then
            local room=Room()
            if s.room and room then
                if not p.dragging then p.dragging=true;pcall(room.DragBegin) end
                pcall(room.DragBy,dx)
                local dt=s.clock-p.t
                if dt>0 then p.vx=p.vx*.6+(dx/dt)*.4 end
            end
        elseif p.view then
            s.scroll=Clamp(s.scroll-(y-p.y),0,s.maxScroll)
        end
    end
    p.t=s.clock
    p.x,p.y=x,y
end
local function Up(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not s or not p or event.pointerId~=p.id then return end
    s.pointer=nil
    local x,y=Coordinates(event)
    local room=Room()
    if p.dragging and room then pcall(room.DragEnd,p.vx) end
    if not p.moved and p.button then
        if At(s,x,y)==p.button and not p.button.disabled then p.button.action() end
    elseif not p.moved and p.stage then
        if s.lastTap and s.clock-s.lastTap<.35 then Home(s);s.lastTap=nil
        else s.lastTap=s.clock end
    end
end
local function Cancel(event)
    Consume(event)
    local s=session
    if s and s.pointer and s.pointer.id==event.pointerId then
        local room=Room()
        if s.pointer.dragging and room then pcall(room.DragEnd,0) end
        s.pointer=nil
    end
end

---------------------------------------------------------------- drawing
local function ChannelColor(s,channel)
    if channel=='dark' then return DARK_VOXEL end
    return Parts.ColorPresets[s.config[s.weapon].colors[channel]].rgb
end
-- Front-most Z cell per (x,y), grouped by channel/slot so a whole thumbnail is a
-- handful of NanoVG fills instead of one fill per voxel.
local function SideLayout(cells,b,maxStep)
    if b.cells==cells and b.fitW==b.w and b.fitH==b.h then return end
    b.cells,b.fitW,b.fitH=cells,b.w,b.h
    b.groups={}
    if #cells==0 then return end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local front={}
    for _,cell in ipairs(cells) do
        minX=math.min(minX,cell.x);maxX=math.max(maxX,cell.x)
        minY=math.min(minY,cell.y);maxY=math.max(maxY,cell.y)
        local k=cell.x..':'..cell.y
        if not front[k] or cell.z>front[k].z then front[k]=cell end
    end
    local spanX,spanY=maxX-minX+1,maxY-minY+1
    local step=math.min(b.w/spanX,b.h/spanY,maxStep or 14)
    local ox,oy=b.x+(b.w-spanX*step)/2,b.y+(b.h-spanY*step)/2
    b.step=step
    local index={}
    for _,cell in pairs(front) do
        local key=cell.channel..'|'..tostring(cell.slot)
        local group=index[key]
        if not group then group={channel=cell.channel,slot=cell.slot,rects={}};index[key]=group;b.groups[#b.groups+1]=group end
        local rects=group.rects
        rects[#rects+1]=ox+(cell.x-minX)*step
        rects[#rects+1]=oy+(maxY-cell.y)*step
    end
    table.sort(b.groups,function(a,c) return (a.channel..tostring(a.slot))<(c.channel..tostring(c.slot)) end)
end
local function SidePixels(vg,s,cells,b,highlight,alpha,maxStep)
    SideLayout(cells,b,maxStep)
    local size=(b.step or 0)+.5
    if size<=.5 then return end
    for _,group in ipairs(b.groups) do
        local a=(alpha or 1)*((highlight and group.slot~=highlight) and .4 or 1)
        nvgBeginPath(vg)
        local rects=group.rects
        for i=1,#rects,2 do nvgRect(vg,rects[i],rects[i+1],size,size) end
        nvgFillColor(vg,G.Color(ChannelColor(s,group.channel),a))
        nvgFill(vg)
    end
end
local function PartCells(s,part)
    local cached=s.thumbnails[part.id]
    if cached then return cached end
    cached={}
    for iy,layer in ipairs(part.voxels) do for iz,row in ipairs(layer) do for ix=1,#row do
        local ch=row:sub(ix,ix)
        if ch~='.' then cached[#cached+1]={x=ix,y=iy,z=iz,channel=part.palette[ch],slot=part.slot} end
    end end end
    s.thumbnails[part.id]=cached
    return cached
end
local function Icon(vg,name,x,y)
    nvgSave(vg);nvgTranslate(vg,x,y);nvgScale(vg,.5,.5)
    Draw.Image(vg,name,0,0)
    nvgRestore(vg)
end
local function Pressed(s,button)
    return s.pointer and not s.pointer.moved and s.pointer.button==button
end
local function Shadowed(vg,text,x,y,size,color,align,alpha)
    G.Text(vg,text,x+1,y+1,size,C.black,align,(alpha or 1)*.55)
    G.Text(vg,text,x,y,size,color,align,alpha)
end

local DrawButton={}
function DrawButton.tab(vg,s,b)
    local pressed=Pressed(s,b)
    local bx=b.box
    if b.active then
        G.Gradient(vg,bx.x+1,bx.y+1,bx.w-2,bx.h-2,17,TAB_TOP,TAB_BOTTOM,1)
        G.Stroke(vg,bx.x+1,bx.y+1,bx.w-2,bx.h-2,17,C.gold,.9,1.5)
    elseif pressed then G.Round(vg,bx.x+2,bx.y+2,bx.w-4,bx.h-4,16,C.cardHi,.8) end
    Icon(vg,b.icon,bx.x+10,bx.y+8)
    G.Text(vg,b.label,bx.x+38,bx.y+bx.h/2,16,b.active and C.gold or C.sub)
end
function DrawButton.close(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2,bx.y+bx.h/2
    G.Circle(vg,cx,cy,15,Pressed(s,b) and C.cardHi or C.card,.9)
    G.Line(vg,cx-5,cy-5,cx+5,cy+5,C.text,.9,1.8)
    G.Line(vg,cx+5,cy-5,cx-5,cy+5,C.text,.9,1.8)
end
function DrawButton.plain(vg,s,b)
    local bx=b.box
    local a=b.disabled and .4 or 1
    G.Round(vg,bx.x,bx.y,bx.w,bx.h,12,Pressed(s,b) and C.cardHi or C.card,.95*a)
    G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,12,b.active and C.gold or C.ice,b.active and .8 or .22*a,1)
    G.Text(vg,b.label,bx.x+bx.w/2-(b.menuToggle and 8 or 0),bx.y+bx.h/2,15,b.disabled and C.dim or C.text,NVG_ALIGN_CENTER)
    if b.menuToggle then
        local tx,ty=bx.x+bx.w/2+G.EstimateWidth(b.label,15)/2+10,bx.y+bx.h/2
        nvgBeginPath(vg)
        if b.active then nvgMoveTo(vg,tx-5,ty+3);nvgLineTo(vg,tx+5,ty+3);nvgLineTo(vg,tx,ty-3)
        else nvgMoveTo(vg,tx-5,ty-3);nvgLineTo(vg,tx+5,ty-3);nvgLineTo(vg,tx,ty+3) end
        nvgClosePath(vg);nvgFillColor(vg,G.Color(C.sub,1));nvgFill(vg)
    end
end
function DrawButton.primary(vg,s,b)
    local bx=b.box
    local pressed=Pressed(s,b)
    G.Gradient(vg,bx.x,bx.y,bx.w,bx.h,12,pressed and GOLD_DOWN_TOP or GOLD_TOP,pressed and GOLD_DOWN_BOTTOM or GOLD_BOTTOM,1)
    G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,12,GOLD_RIM,.5,1)
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2,18,C.ink,NVG_ALIGN_CENTER)
end
function DrawButton.slot(vg,s,b)
    local bx=b.box
    G.Round(vg,bx.x,bx.y,bx.w,bx.h,10,Pressed(s,b) and C.cardHi or (b.active and C.cardSel or C.card),b.active and 1 or .7)
    if b.active then
        G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,10,C.gold,.75,1.2)
        G.Round(vg,bx.x+bx.w/2-10,bx.y+bx.h-4,20,2.5,1.2,C.gold,1)
    end
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2-1,15,b.active and C.gold or C.sub,NVG_ALIGN_CENTER)
end
function DrawButton.card(vg,s,b)
    local bx=b.box
    G.Round(vg,bx.x,bx.y,bx.w,bx.h,12,Pressed(s,b) and C.cardHi or (b.active and C.cardSel or C.card),.95)
    G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,12,b.active and C.gold or C.ice,b.active and .95 or .16,b.active and 1.6 or 1)
    SidePixels(vg,s,PartCells(s,b.part),b.thumb,nil,1,10)
    G.Text(vg,G.Fit(b.label,14,bx.w-12),bx.x+bx.w/2,bx.y+bx.h-16,14,b.active and C.gold or C.text,NVG_ALIGN_CENTER)
end
function DrawButton.chip(vg,s,b)
    local bx=b.box
    G.Round(vg,bx.x,bx.y,bx.w,bx.h,10,Pressed(s,b) and C.cardHi or C.card,.95)
    G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,10,b.active and C.gold or C.ice,b.active and .9 or .16,b.active and 1.5 or 1)
    G.Circle(vg,bx.x+20,bx.y+bx.h/2,9,b.swatch,1)
    G.Ring(vg,bx.x+20,bx.y+bx.h/2,10.5,C.text,.35,1)
    G.Text(vg,b.label,bx.x+38,bx.y+bx.h/2,14,b.active and C.gold or C.text)
end
function DrawButton.swatch(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2,bx.y+bx.h/2
    G.Circle(vg,cx,cy,Pressed(s,b) and 13 or 15,b.swatch,1)
    if b.active then G.Ring(vg,cx,cy,19,C.gold,1,2) end
end
function DrawButton.link(vg,s,b)
    local bx=b.box
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2,14,Pressed(s,b) and C.gold or C.ice,NVG_ALIGN_CENTER)
end
function DrawButton.menu(vg,s,b)
    local bx=b.box
    if b.gap then G.Line(vg,bx.x+8,bx.y-.5,bx.x+bx.w-8,bx.y-.5,C.ice,.2,1) end
    if Pressed(s,b) then G.Round(vg,bx.x,bx.y,bx.w,bx.h,8,C.cardHi,1) end
    G.Text(vg,b.label,bx.x+12,bx.y+bx.h/2,15,C.text)
end

local function StatChips(vg,s)
    local b=s.statsBox
    local n=#s.statRows
    local cw=(b.w-8*(n-1))/n
    for i,row in ipairs(s.statRows) do
        local x=b.x+(i-1)*(cw+8)
        local flash=(s.flash[row.key] or 0)>0 and math.floor(s.clock*16)%2==0
        G.Round(vg,x,b.y,cw,b.h,10,C.card,.95)
        G.Stroke(vg,x,b.y,cw,b.h,10,row.changed and (row.up and C.good or C.bad) or C.ice,row.changed and .4 or .16,1)
        G.Text(vg,row.label,x+9,b.y+14,13,C.sub)
        if row.delta then G.Text(vg,row.delta,x+cw-8,b.y+14,13,row.up and C.good or C.bad,NVG_ALIGN_RIGHT) end
        G.Text(vg,row.text,x+9,b.y+33,row.changed and 16 or 18,flash and C.gold or C.text)
        G.Round(vg,x+9,b.y+b.h-9,cw-18,3,1.5,C.dim,.5)
        G.Round(vg,x+9,b.y+b.h-9,math.max(3,(cw-18)*row.fraction),3,1.5,C.gold,1)
    end
end
local function MoreRows(vg,s)
    local b=s.moreBox
    if not b then return end
    G.Round(vg,b.x,b.y,b.w,b.h,10,C.card,.7)
    for i,row in ipairs(s.moreRows) do
        local y=b.y+2+(i-1)*24+12
        G.Text(vg,row.label,b.x+10,y,14,C.sub)
        G.Text(vg,row.text..(row.delta and ('   '..row.delta) or ''),b.x+b.w-10,y,14,row.changed and (row.up and C.good or C.bad) or C.text,NVG_ALIGN_RIGHT)
    end
end

local function Backdrop(vg,s)
    -- Only needed when the 3D room is not showing: dim the world and give the
    -- 2D side view a calm surface.
    local st=s.stage
    G.Round(vg,0,0,s.width,s.height,0,C.black,.5)
    G.Gradient(vg,st.x,st.y,st.w,st.h,16,STAGE_TOP,STAGE_BOTTOM,.94)
    G.Stroke(vg,st.x,st.y,st.w,st.h,16,C.ice,.18,1)
end
local function Stage(vg,s,alpha)
    local st=s.stage
    if s.fallback then
        Backdrop(vg,s)
        local cells=s.sideCells
        SidePixels(vg,s,cells,s.sideBox,s.slot,alpha,18)
        G.Text(vg,'3D 展示间不可用 · 侧视图',st.x+st.w/2,st.y+st.h-20,13,C.sub,NVG_ALIGN_CENTER,alpha)
    elseif not s.roomReady then
        G.Text(vg,'正在准备展示间…',st.x+st.w/2,st.y+st.h/2,15,C.sub,NVG_ALIGN_CENTER,alpha)
    end
    local tx,ty=st.x+8,st.y+30
    Shadowed(vg,WEAPON_NAMES[s.weapon],tx,ty,26,C.text,nil,alpha)
    Shadowed(vg,s.subtitle,tx,ty+28,14,C.sub,nil,alpha)
    local hint=s.message
    if hint then Shadowed(vg,G.Fit(hint,13,st.w-16),tx,st.y+st.h-44,13,C.gold,nil,alpha) end
    if s.roomReady or not s.fallback then
        Shadowed(vg,'拖动旋转 · 双击回正',tx,st.y+st.h-20,13,C.sub,nil,alpha)
    end
    if not s.fallback and not s.message then
        Shadowed(vg,'Web 刷新后配置会恢复默认',tx,st.y+st.h-44,12,C.dim,nil,alpha)
    end
end

local function PhaseValues(s)
    local phase,t=s.phase,s.phaseT
    if s.closing then
        if s.closeStage==1 then
            local black=Clamp(s.closeT/FADE_OUT,0,1)
            return black,1-black
        end
        return Clamp(1-s.closeT/REVEAL,0,1),0
    end
    if phase=='opening' then return Clamp(t/FADE_OUT,0,1),0 end
    if phase=='revealing' then
        local k=Clamp(t/REVEAL,0,1)
        return 1-k,k
    end
    return 0,1
end
local function Render(vg,s)
    if session~=s or s.finished then return end
    local w,h,safe=Draw.Metrics()
    if w~=s.width or h~=s.height or safe.left~=s.safeLeft or safe.top~=s.safeTop
        or safe.right~=s.safeRight or safe.bottom~=s.safeBottom then
        s.pointer=nil;Layout(s)
        local room=Room()
        if s.room and room and room.SetFocus then pcall(room.SetFocus,(s.stage.x+s.stage.w*.5)/math.max(1,w),.5) end
    end
    local black,alpha=PhaseValues(s)
    G.Begin(vg)
    if alpha>0 then
        nvgGlobalAlpha(vg,alpha)
        Stage(vg,s,1)
        local p=s.panel
        G.Gradient(vg,p.x,p.y,p.w,p.h,16,PANEL_TOP,PANEL_BOTTOM,.94)
        G.Stroke(vg,p.x,p.y,p.w,p.h,16,C.panelEdge,.55,1)
        G.Line(vg,p.x+18,p.y+1.5,p.x+p.w-18,p.y+1.5,C.ice,.35,1)
        G.Text(vg,'锻造库',s.titlePos.x,s.titlePos.y,22,C.text)
        local tb=s.tabsBox
        G.Round(vg,tb.x,tb.y,tb.w,tb.h,18,C.card,.95)
        for _,b in ipairs(s.buttons) do
            if b.kind=='tab' or b.kind=='close' then DrawButton[b.kind](vg,s,b) end
        end
        -- scrolling content
        local v=s.view
        nvgSave(vg);nvgIntersectScissor(vg,v.x,v.y,v.w,v.h)
        nvgTranslate(vg,0,-s.scroll)
        StatChips(vg,s)
        if s.paletteTitle then G.Text(vg,s.paletteTitle.text,s.paletteTitle.x,s.paletteTitle.y,13,C.sub) end
        MoreRows(vg,s)
        for i,line in ipairs(s.descriptionLines) do
            G.Text(vg,line,s.descriptionBox.x+2,s.descriptionBox.y+(i-1)*19+9,13,C.sub)
        end
        for _,b in ipairs(s.buttons) do if b.area=='scroll' then DrawButton[b.kind](vg,s,b) end end
        nvgRestore(vg)
        if s.maxScroll>0 then
            local thumb=math.max(24,v.h*v.h/s.contentHeight)
            G.Round(vg,v.x+v.w-3,v.y+s.scroll/s.maxScroll*(v.h-thumb),3,thumb,1.5,C.gold,.55)
            if s.scroll<s.maxScroll-2 then
                G.Gradient(vg,v.x,v.y+v.h-22,v.w,22,0,FADE_CLEAR,FADE_SOLID,1)
            end
        end
        for _,b in ipairs(s.buttons) do if not b.area and b.kind~='tab' and b.kind~='close' then DrawButton[b.kind](vg,s,b) end end
        if s.menuBox then
            local m=s.menuBox
            G.Round(vg,m.x,m.y,m.w,m.h,14,MENU_FILL,.99)
            G.Stroke(vg,m.x,m.y,m.w,m.h,14,C.panelEdge,.6,1)
            for _,b in ipairs(s.buttons) do if b.area=='menu' then DrawButton.menu(vg,s,b) end end
        end
        nvgGlobalAlpha(vg,1)
    end
    if black>0 then G.Round(vg,0,0,w,h,0,C.black,black) end
    G.Finish(vg)
end

---------------------------------------------------------------- lifecycle
local Layer=UI.Panel:Extend('RuinsForgePanel')
function Layer:Render(_)
    local s=session
    if s and not s.finished then UI.QueueOverlay(s.renderOverlay) end
end
local function Released()
    if input.numTouches>0 or input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetMouseButtonDown(MOUSEB_MIDDLE) then return false end
    for _,key in ipairs(HELD_KEYS) do if input:GetKeyDown(key) then return false end end
    return true
end
local function FinishClose(s)
    if s.finished then return end
    s.finished=true
    DestroyRoom(s)
    -- Scene.Stop may have no next Update. Never schedule cleanup onto a receiver
    -- that should already be gone; the detached Lua widget can finish dispatch.
    local retired=s.layer
    UI.PopOverlay(retired);s.root:RemoveChild(retired)
    -- UI may still hold this Lua widget until an already-pressed pointer is
    -- released. Retire its geometry and callbacks so stale events cannot act
    -- on a newly opened forge session.
    retired.absoluteLayout={x=0,y=0,w=0,h=0}
    retired.props.onPointerDown=Consume;retired.props.onPointerMove=Consume
    retired.props.onPointerUp=Consume;retired.props.onPointerCancel=Consume
    s.layer=nil
    s.receiver:UnsubscribeFromAllEvents()
    retired:Destroy();s.eventNode:Remove()
    if input.mouseMode==MM_ABSOLUTE then input.mouseMode=s.mouseMode end
    TouchInput.Clear()
    session=nil
    if s.callbacks.onClose then s.callbacks.onClose(Copy(s.config),s.saved,s.keptDraft==true) end
end
---@param data VariantMap
local function Update(_,_,data)
    local s=session
    if not s then return end
    local rawDt=math.max(0,data:GetFloat('TimeStep'))
    local dt=math.min(.1,rawDt)
    if s.closing then
        s.closeT=s.closeT+dt
        s.releaseFrames=s.releaseFrames+1
        if s.closeStage==1 then
            if s.closeT>=FADE_OUT and s.releaseFrames>=2 and Released() then
                DestroyRoom(s);s.closeStage,s.closeT=2,0
            end
        elseif s.closeT>=REVEAL then FinishClose(s) end
        return
    end
    if not Safe(s.callbacks) then M.Close(true);return end
    s.updateFrame=s.updateFrame+1
    s.clock=s.clock+dt
    for key,value in pairs(s.flash) do s.flash[key]=math.max(0,value-dt) end
    s.phaseT=s.phaseT+dt
    if s.phase=='opening' and s.phaseT>=FADE_OUT then
        EnterRoom(s);s.phase,s.phaseT='revealing',0
    elseif s.phase=='revealing' and s.phaseT>=REVEAL then
        s.phase,s.phaseT='open',0
    end
    local room=Room()
    if s.room and room then
        local ok,reason=pcall(room.Update,dt)
        if not ok then Fallback(s,'update',reason);return end
        local state=room.State and room.State() or nil
        if state=='failed' then Fallback(s,'failed');return end
        local ready=room.IsReady()==true
        if ready and not s.roomReady then
            s.roomReady=true;s.previewMode='3d';print('Forge preview: 3d')
        elseif not ready and s.roomReady then s.roomReady=false end
        if not ready then
            s.roomWait=s.roomWait+rawDt
            if s.roomWait>=ROOM_TIMEOUT then Fallback(s,'timeout') end
        else s.roomWait=0 end
    end
end
--- Open only outside combat; no root replacement and no world pause.
---@param rigOrCallbacks WeaponRig|ForgeCallbacks|nil
---@return boolean
function M.Open(rigOrCallbacks)
    if session then return not session.closing end
    ---@type ForgeCallbacks
    local callbacks
    if rigOrCallbacks and rigOrCallbacks.Apply then callbacks={rig=rigOrCallbacks --[[@as WeaponRig]]}
    else callbacks=(rigOrCallbacks or {}) --[[@as ForgeCallbacks]] end
    if not Safe(callbacks) then return false end
    local root=UI.GetRoot()
    if not root then return false end
    local config=Copy(callbacks.config or (callbacks.rig and callbacks.rig.config) or Store.Load())
    if type(config)~='table' or config.version~=1 or not Parts.ValidateWeapon('sword',config.sword)
        or not Parts.ValidateWeapon('bow',config.bow) then config=Store.Default() end
    if config.active~='sword' and config.active~='bow' then config.active='sword' end
    local baseline=Copy(config)
    local owner=callbacks.rig or M
    local draft=drafts[owner]
    if draft then config=Copy(draft.config) end
    local weapon=draft and draft.weapon or config.active
    local s={callbacks=callbacks,config=config,original=baseline,weapon=weapon,slot=draft and draft.slot or SLOT_ORDER[weapon][1],
        undo=draft and Copy(draft.undo),owner=owner,scroll=0,clock=0,phase='opening',phaseT=0,closeT=0,
        thumbnails={},flash={},root=root,updateFrame=0,mouseMode=input.mouseMode,
        message=draft and '已恢复草稿' or nil}
    session=s
    s.renderOverlay=function(context) Render(context,s) end
    Rebuild(s);Layout(s)
    s.layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',
        onPointerDown=Down,onPointerMove=Move,onPointerUp=Up,onPointerCancel=Cancel,
        onClick=function(_,event) if event then Consume(event) end end}
    s.layer.focusable=false
    root:AddChild(s.layer);UI.PushOverlay(s.layer)
    s.eventNode=Node()
    s.receiver=s.eventNode:CreateScriptObject('LuaScriptObject')
    s.receiver:SubscribeToEvent('Update',Update)
    s.receiver:SubscribeToEvent('KeyDown',function(_,_,data)
        if not s.closing and data:GetInt('Key')==KEY_ESCAPE then
            if s.menuOpen then CloseMenu(s) else M.Close() end
        end
    end)
    s.receiver:SubscribeToEvent('MouseWheel',function(_,_,data)
        if not s.closing then s.pointer=nil;s.scroll=Clamp(s.scroll-data:GetInt('Wheel')*48,0,s.maxScroll) end
    end)
    input.mouseMode=MM_ABSOLUTE
    TouchInput.Clear()
    if callbacks.onOpen then callbacks.onOpen() end
    return true
end
--- Normal close applies. Safety close never applies/saves and retains the draft.
---@param keepDraft boolean?
---@return boolean
function M.Close(keepDraft)
    local s=session
    if not s then return true end
    if s.closing then
        if keepDraft==true then FinishClose(s) end
        return true
    end
    if keepDraft==true or not Safe(s.callbacks) then
        drafts[s.owner]={config=Copy(s.config),weapon=s.weapon,slot=s.slot,undo=Copy(s.undo)}
        s.keptDraft,s.saved,s.closing,s.pointer=true,false,true,nil
        FinishClose(s)
        return true
    end
    for _,weapon in ipairs({'sword','bow'}) do
        local now=assert(Builder.Compile(Single(s.config,weapon)))
        local before=assert(Builder.Compile(Single(s.original,weapon)))
        if now.key~=before.key then
            local applied=true
            if s.callbacks.rig then applied=s.callbacks.rig:Apply(Copy(now.config))
            elseif s.callbacks.onApply then applied=s.callbacks.onApply(Copy(now.config)) end
            if applied==false then Message(s,'装备未能应用，请重试');return false end
        end
    end
    if s.callbacks.onEquip then
        if s.callbacks.onEquip(s.weapon)==false then Message(s,'暂时无法切换武器，请稍后关闭');return false end
    elseif CombatState.GetWeapon()~=s.weapon and not CombatState.SetWeapon(s.weapon) then
        Message(s,'暂时无法切换武器，请稍后关闭');return false
    end
    s.config.active=s.weapon
    if s.callbacks.rig then
        s.callbacks.rig:SetActive(s.weapon)
        s.callbacks.rig:SetPose(CombatState.GetPose())
    end
    s.saved=Store.Save(s.config)
    if not s.saved then Message(s,'配置已应用，本次未能保存') end
    s.closing,s.releaseFrames,s.pointer=true,0,nil
    s.closeStage,s.closeT,s.menuOpen=1,0,false
    drafts[s.owner]=nil
    TouchInput.Clear()
    return true
end
--- Includes the short release latch: callers must gate game input on this.
function M.IsOpen() return session~=nil end
--- Idempotent scene teardown / danger close, including the normal release latch.
---@return boolean
function M.ForceClose() return M.Close(true) end
--- nil while closed/closing or while the showroom is still preparing.
---@return '3d'|'fallback'|nil
function M.PreviewMode()
    if not session or session.closing then return nil end
    if session.fallback then return 'fallback' end
    if session.roomReady then return '3d' end
    return nil
end
return M
