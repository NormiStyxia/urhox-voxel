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
local function Shadowed(vg,text,x,y,size,color,align,alpha)
    G.Text(vg,text,x+1,y+1,size,C.black,align,(alpha or 1)*.55)
    G.Text(vg,text,x,y,size,color,align,alpha)
end
local SLOT_ORDER={sword={'blade','guard','grip','pommel'},bow={'limbs','grip','tip'}}
local CHANNEL_NAMES={primary='主色',secondary='副色',accent='点缀'}
local WEAPON_NAMES={sword='长剑',bow='长弓'}
local HELD_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L,KEY_ESCAPE}
local PAD=14
local FADE_OUT,REVEAL=.2,.3 -- seconds: to black / from black
local ROOM_TIMEOUT=6
local DARK_VOXEL={92,76,60}
local PANEL_TOP,PANEL_BOTTOM={15,27,48},{9,17,32}
local STAGE_TOP,STAGE_BOTTOM={26,46,80},{9,16,30}
local EQUIP_TOP,EQUIP_BOTTOM={102,204,244},{48,136,196}
local EQUIP_DOWN_TOP,EQUIP_DOWN_BOTTOM={70,160,208},{34,100,150}
local EQUIP_RIM={186,236,255}
local MENU_FILL={10,19,36}
local SHADOW_CLEAR,SHADOW_SOLID={0,0,0,0},{0,0,0,110}

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
    if not ok or entered~=true then
        local detail=not ok and entered or nil
        if detail==nil and type(room.Diagnostic)=='function' then
            local good,text=pcall(room.Diagnostic)
            detail=good and text or nil
        end
        Fallback(s,'enter',detail);return
    end
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
        local suffix=(unit=='×' or unit=='m') and unit or ''
        local value,before=StatValue(s.blueprint,key),StatValue(s.baseline,key)
        local delta=value-before
        rows[i]={key=key,label=entry[2],value=Number(value,unit)..suffix,changed=math.abs(delta)>.001,
            fraction=Clamp(value/entry[3],0,1),
            delta=math.abs(delta)>.001 and ((delta>0 and '+' or '-')..Number(math.abs(delta),unit)..suffix) or nil,
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
-- Look: one flat deep-navy sheet flush with the right edge, hairline dividers,
-- text tabs with an underline, sharp square option frames. No nested rounded
-- boxes; the only filled control is the chamfered Equip button.
Layout=function(s)
    local w,h,safe=Draw.Metrics()
    s.width,s.height=w,h
    s.safeLeft,s.safeTop,s.safeRight,s.safeBottom=safe.left,safe.top,safe.right,safe.bottom
    local pw=math.min(w,Clamp(math.floor(w*.5),340,560))
    s.panel=Box(w-pw,0,pw,h)
    s.stage=Box(0,0,w-pw,h)
    local padR=math.max(16,safe.right+12)
    local cx,cw=s.panel.x+20,pw-20-padR
    local top,bottom=safe.top+8,h-safe.bottom-8
    s.content=Box(cx,top,cw,bottom-top)
    s.buttons={}
    -- header: title, weapon text tabs (with the pixel weapon icons), close
    s.titlePos={x=cx,y=top+22}
    for i,weapon in ipairs({'sword','bow'}) do
        Add(s,'tab_'..weapon,weapon=='sword' and '剑' or '弓',Box(cx+100+(i-1)*70,top,70,40),function()
            if s.weapon==weapon then return end
            s.weapon=weapon;s.slot=SLOT_ORDER[weapon][1];s.scroll=0;s.colorChannel=nil;s.moreOpen=false
            Rebuild(s);Layout(s)
        end,{kind='tab',active=s.weapon==weapon,icon=weapon..'_s'})
    end
    Add(s,'close','关闭',Box(cx+cw-40,top,44,44),function() M.Close() end,{kind='close'})
    s.headerLine=top+44
    -- footer: recommended menu / undo links, chamfered equip button
    local fy=bottom-44
    s.footerY=fy;s.footerLine=fy-6
    Add(s,'recommend','推荐方案',Box(cx,fy,96,44),function() s.menuOpen=not s.menuOpen;Layout(s) end,{kind='link',menuToggle=true,active=s.menuOpen})
    Add(s,'undo','撤销',Box(cx+104,fy,56,44),function()
        if not s.undo then return end
        s.config,s.weapon,s.slot=s.undo.config,s.undo.weapon,s.undo.slot;s.undo=nil
        Rebuild(s);Layout(s)
    end,{kind='link',disabled=not s.undo})
    Add(s,'equip','装备',Box(cx+cw-140,fy,140,44),function() M.Close() end,{kind='primary'})
    -- scrolling viewport
    local vy=top+50
    local vh=s.footerLine-6-vy
    s.view=Box(s.panel.x,vy,pw,vh)
    local cy=vy
    local slots=SLOT_ORDER[s.weapon]
    for i,slot in ipairs(slots) do
        local sx,sw=Span(cx,cw,i,#slots,0)
        Add(s,'slot_'..slot,Parts.SlotNames[slot],Box(sx,cy,sw,34),function() s.slot=slot;Layout(s) end,
            {kind='tab',area='scroll',active=s.slot==slot,slot=true})
    end
    s.slotLine=cy+34
    cy=cy+34+6
    local options=Parts.GetOptions(s.weapon,s.slot)
    for i,part in ipairs(options) do
        local x,cwid=Span(cx,cw,i,#options,12)
        local b=Add(s,'part_'..part.id,part.name,Box(x,cy,cwid,92),function()
            Edit(s,function() s.config[s.weapon].parts[s.slot]=part.id end)
        end,{kind='card',area='scroll',active=s.config[s.weapon].parts[s.slot]==part.id,part=part})
        b.frame=Box(x,cy,cwid,70)
        b.thumb=Box(x+8,cy+7,cwid-16,56)
    end
    cy=cy+92+2
    s.dividerY=cy
    cy=cy+8
    -- two columns: colours (left) / attributes (right)
    local colW=math.floor((cw-20)*.44)
    local rx=cx+colW+20
    local rw=cw-colW-20
    s.colorCol=Box(cx,cy,colW,10)
    s.attrCol=Box(rx,cy,rw,10)
    local chipY=cy+24
    for i,channel in ipairs(Parts.Channels) do
        local preset=Parts.ColorPresets[s.config[s.weapon].colors[channel]]
        local chx,chw=Span(cx,colW,i,3,4)
        Add(s,'color_'..channel,CHANNEL_NAMES[channel],Box(chx,chipY,chw,44),function()
            s.colorChannel=s.colorChannel~=channel and channel or nil;Layout(s)
            if s.colorChannel then s.scroll=s.maxScroll end
        end,{kind='chip',area='scroll',swatch=preset.rgb,active=s.colorChannel==channel})
    end
    local colBottom=chipY+44
    s.descriptionLines=G.Wrap(assert(Parts.Get(s.config[s.weapon].parts[s.slot])).desc,13,colW-2)
    s.descPos={x=cx,y=colBottom+10}
    colBottom=colBottom+4+#s.descriptionLines*18
    -- attributes (right column): label / candidate value / difference
    s.statRows=s.statRows or StatRows(s,STAT_MAIN[s.weapon])
    s.attrTitle={x=rx,y=cy+10}
    Add(s,'more',s.moreOpen and '收起' or '更多',Box(rx+rw-56,cy-6,60,34),function() s.moreOpen=not s.moreOpen;Layout(s) end,
        {kind='link',area='scroll',small=true})
    s.attrRowsY=cy+26
    local rows=#s.statRows
    s.moreBox=nil
    if s.moreOpen then
        s.moreRows=s.moreRows or StatRows(s,STAT_MORE[s.weapon])
        s.moreBox={x=rx,y=s.attrRowsY+rows*24,w=rw,h=#s.moreRows*24}
        rows=rows+#s.moreRows
    end
    local attrBottom=s.attrRowsY+rows*24
    s.attrRight={x=rx,w=rw}
    cy=math.max(colBottom,attrBottom)+8
    -- colour palette: a full-width row under both columns (big enough to tap)
    s.paletteBox=nil;s.paletteTitle=nil
    if s.colorChannel then
        local current=s.config[s.weapon].colors[s.colorChannel]
        local count=#Parts.ColorPresets
        s.dividerY2=cy
        s.paletteTitle={x=cx,y=cy+16,text=CHANNEL_NAMES[s.colorChannel]..' · '..Parts.ColorPresets[current].name}
        s.paletteBox=Box(cx,cy+28,cw,38)
        for i,preset in ipairs(Parts.ColorPresets) do
            local px,pwid=Span(cx,cw,i,count,0)
            Add(s,'swatch_'..i,preset.name,Box(px,cy+28,pwid,38),function()
                Edit(s,function() s.config[s.weapon].colors[s.colorChannel]=i end)
            end,{kind='swatch',area='scroll',swatch=preset.rgb,active=current==i})
        end
        cy=cy+72
    else s.dividerY2=nil end
    s.contentHeight=cy-vy
    s.maxScroll=math.max(0,s.contentHeight-vh)
    s.scroll=Clamp(s.scroll,0,s.maxScroll)
    s.subtitle=nil
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
        local mh=#items*40+8
        local menu=Box(cx,fy-6-mh,150,mh)
        s.menuBox=menu
        for i,item in ipairs(items) do
            Add(s,item.id,item.label,Box(menu.x,menu.y+4+(i-1)*40,menu.w,40),function()
                s.menuOpen=false
                item.action()
                Layout(s)
            end,{kind='menu',area='menu',gap=item.gap})
        end
    else s.menuBox=nil end
    s.sideBox=Box(s.stage.x+40,s.stage.y+h*.1,math.max(1,s.stage.w-80),math.max(1,h*.8))
    s.sideCells=s.blueprint.geometry.cells
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
        if not button.area and button.action and Inside(x,y,button.box) then return button end
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
local function Hairline(vg,x,y,w,alpha,diamond)
    G.Line(vg,x,y+.5,x+w,y+.5,C.line,alpha or .5,1)
    if diamond then G.Diamond(vg,x+w/2,y+.5,3,C.cyan,.8) end
end
local function Underline(vg,cx,y,w,active)
    G.Round(vg,cx-w/2,y,w,2,0,C.cyan,1)
    G.Diamond(vg,cx,y+6,2.5,C.cyan,active and 1 or .6)
end

local DrawButton={}
function DrawButton.tab(vg,s,b)
    local bx=b.box
    local pressed=Pressed(s,b)
    local color=(b.active or pressed) and C.cyan or C.sub
    if b.icon then
        Icon(vg,b.icon,bx.x+8,bx.y+(bx.h-20)/2)
        local draw=b.active and G.Bold or G.Text
        draw(vg,b.label,bx.x+36,bx.y+bx.h/2,19,color)
        if b.active then G.Round(vg,bx.x+36,bx.y+bx.h-3,22,2,0,C.cyan,1) end
    else
        local draw=b.active and G.Bold or G.Text
        draw(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2-2,17,color,NVG_ALIGN_CENTER)
        if b.active then Underline(vg,bx.x+bx.w/2,bx.y+bx.h-5,math.min(bx.w-12,G.EstimateWidth(b.label,17)+10),true) end
    end
end
function DrawButton.close(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2+4,bx.y+bx.h/2
    local a=Pressed(s,b) and 1 or .85
    G.Line(vg,cx-8,cy-8,cx+8,cy+8,C.text,a,1.6)
    G.Line(vg,cx+8,cy-8,cx-8,cy+8,C.text,a,1.6)
end
function DrawButton.link(vg,s,b)
    local bx=b.box
    local color=b.disabled and C.dim or ((b.active or Pressed(s,b)) and C.cyan or C.text)
    local size=b.small and 14 or 16
    local width=G.EstimateWidth(b.label,size)
    if b.small then
        G.Text(vg,b.label,bx.x+bx.w,bx.y+bx.h/2,size,color,NVG_ALIGN_RIGHT)
        return
    end
    local x=bx.x
    G.Text(vg,b.label,x,bx.y+bx.h/2,size,color)
    if b.menuToggle then
        local tx,ty=x+width+9,bx.y+bx.h/2+1
        nvgBeginPath(vg)
        if b.active then nvgMoveTo(vg,tx-4,ty+2.5);nvgLineTo(vg,tx+4,ty+2.5);nvgLineTo(vg,tx,ty-2.5)
        else nvgMoveTo(vg,tx-4,ty-2.5);nvgLineTo(vg,tx+4,ty-2.5);nvgLineTo(vg,tx,ty+2.5) end
        nvgClosePath(vg);nvgFillColor(vg,G.Color(color,1));nvgFill(vg)
    else
        G.Line(vg,x,bx.y+bx.h/2+11,x+width,bx.y+bx.h/2+11,color,b.disabled and .4 or .8,1)
    end
end
function DrawButton.primary(vg,s,b)
    local bx=b.box
    local pressed=Pressed(s,b)
    G.ChamferGradient(vg,bx.x,bx.y,bx.w,bx.h,7,pressed and EQUIP_DOWN_TOP or EQUIP_TOP,pressed and EQUIP_DOWN_BOTTOM or EQUIP_BOTTOM,1)
    G.ChamferStroke(vg,bx.x,bx.y,bx.w,bx.h,7,EQUIP_RIM,.9,1)
    G.Diamond(vg,bx.x+14,bx.y+bx.h/2,3,EQUIP_RIM,.95)
    G.Diamond(vg,bx.x+bx.w-14,bx.y+bx.h/2,3,EQUIP_RIM,.95)
    G.Bold(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2,22,C.white,NVG_ALIGN_CENTER)
end
function DrawButton.card(vg,s,b)
    local f=b.frame
    local pressed=Pressed(s,b)
    if b.active then
        G.Round(vg,f.x,f.y,f.w,f.h,2,C.cyan,.1)
        G.Stroke(vg,f.x,f.y,f.w,f.h,2,C.cyan,1,1.6)
    else
        G.Round(vg,f.x,f.y,f.w,f.h,2,pressed and C.cyan or C.line,pressed and .12 or .06)
        G.Stroke(vg,f.x,f.y,f.w,f.h,2,C.line,.55,1)
    end
    SidePixels(vg,s,PartCells(s,b.part),b.thumb,nil,1,10)
    G.Text(vg,G.Fit(b.label,15,f.w+8),f.x+f.w/2,f.y+f.h+12,15,b.active and C.white or C.sub,NVG_ALIGN_CENTER)
end
function DrawButton.chip(vg,s,b)
    local bx=b.box
    local sw=Box(bx.x+(bx.w-40)/2,bx.y+2,40,24)
    G.Round(vg,sw.x,sw.y,sw.w,sw.h,4,b.swatch,1)
    G.Stroke(vg,sw.x,sw.y,sw.w,sw.h,4,b.active and C.cyan or C.white,b.active and 1 or .25,b.active and 1.6 or 1)
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h-9,13,b.active and C.cyan or C.sub,NVG_ALIGN_CENTER)
end
function DrawButton.swatch(vg,s,b)
    local bx=b.box
    local sw=Box(bx.x+(bx.w-28)/2,bx.y+5,28,28)
    G.Round(vg,sw.x,sw.y,sw.w,sw.h,4,b.swatch,1)
    if b.active then G.Stroke(vg,sw.x-3,sw.y-3,sw.w+6,sw.h+6,5,C.cyan,1,1.5) end
end
function DrawButton.menu(vg,s,b)
    local bx=b.box
    if b.gap then Hairline(vg,bx.x+10,bx.y,bx.w-20,.4) end
    if Pressed(s,b) then G.Round(vg,bx.x,bx.y,bx.w,bx.h,0,C.cyan,.14) end
    G.Text(vg,b.label,bx.x+14,bx.y+bx.h/2,16,C.text)
end

local function Attributes(vg,s)
    G.Bold(vg,'武器属性',s.attrTitle.x,s.attrTitle.y,16,C.title)
    local x,w=s.attrRight.x,s.attrRight.w
    local y=s.attrRowsY
    local function Row(row)
        local flash=(s.flash[row.key] or 0)>0 and math.floor(s.clock*16)%2==0
        G.Text(vg,row.label,x,y+12,15,C.text)
        G.Text(vg,row.value,x+w*.5,y+12,17,flash and C.gold or C.white)
        if row.delta then G.Text(vg,row.delta,x+w,y+12,15,row.up and C.cyan or C.orange,NVG_ALIGN_RIGHT) end
        Hairline(vg,x,y+23,w,.2)
        y=y+24
    end
    for _,row in ipairs(s.statRows) do Row(row) end
    if s.moreBox then for _,row in ipairs(s.moreRows) do Row(row) end end
end

local function Backdrop(vg,s)
    -- No 3D room: a calm full-bleed backdrop with a tilted side-view of the weapon.
    local st=s.stage
    G.Gradient(vg,0,0,st.w,s.height,0,STAGE_TOP,STAGE_BOTTOM,1)
    local b=s.sideBox
    nvgSave(vg)
    nvgTranslate(vg,b.x+b.w/2,b.y+b.h/2);nvgRotate(vg,-.5);nvgTranslate(vg,-(b.x+b.w/2),-(b.y+b.h/2))
    SidePixels(vg,s,s.sideCells,b,s.slot,1,18)
    nvgRestore(vg)
end
local function Stage(vg,s)
    local st=s.stage
    if s.fallback then Backdrop(vg,s)
    elseif not s.roomReady then
        G.Text(vg,'正在准备展示间…',st.x+st.w/2,st.y+st.h/2,15,C.sub,NVG_ALIGN_CENTER)
    end
    local x=st.x+math.max(20,s.safeLeft+8)
    local y=s.height-s.safeBottom-22
    if s.message then Shadowed(vg,G.Fit(s.message,14,st.w-40),x,y-26,14,C.gold) end
    if s.fallback or s.roomReady then
        nvgBeginPath(vg);nvgArc(vg,x+8,y,6.5,-2.6,2.6,NVG_CW or 2)
        nvgStrokeColor(vg,G.Color(C.white,.85));nvgStrokeWidth(vg,1.5);nvgStroke(vg)
        G.Diamond(vg,x+13.5,y-4,2.4,C.white,.9)
        Shadowed(vg,'拖动旋转',x+24,y,15,C.white)
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
        Stage(vg,s)
        local p,c=s.panel,s.content
        -- one flat sheet, flush with the edge; a soft shadow and a hairline on its left rim
        G.HGradient(vg,p.x-22,0,22,h,SHADOW_CLEAR,SHADOW_SOLID,1)
        G.Gradient(vg,p.x,0,p.w,h,0,PANEL_TOP,PANEL_BOTTOM,.97)
        G.Line(vg,p.x+.5,0,p.x+.5,h,C.cyan,.35,1)
        G.Bold(vg,'锻造库',s.titlePos.x,s.titlePos.y,26,C.title)
        for _,b in ipairs(s.buttons) do
            if b.kind=='tab' and not b.area or b.kind=='close' then DrawButton[b.kind](vg,s,b) end
        end
        Hairline(vg,c.x,s.headerLine,c.w,.55)
        -- scrolling content
        local v=s.view
        nvgSave(vg);nvgIntersectScissor(vg,v.x,v.y,v.w,v.h)
        nvgTranslate(vg,0,-s.scroll)
        Hairline(vg,c.x,s.slotLine,c.w,.3)
        Hairline(vg,c.x,s.dividerY,c.w,.5,true)
        G.Bold(vg,'配色',s.colorCol.x,s.colorCol.y+10,16,C.title)
        if s.dividerY2 then Hairline(vg,c.x,s.dividerY2,c.w,.4) end
        if s.paletteTitle then G.Text(vg,s.paletteTitle.text,s.paletteTitle.x+1,s.paletteTitle.y,14,C.sub) end
        if s.descPos then
            for i,line in ipairs(s.descriptionLines) do G.Text(vg,line,s.descPos.x+1,s.descPos.y+(i-1)*18,13,C.sub) end
        end
        Attributes(vg,s)
        for _,b in ipairs(s.buttons) do if b.area=='scroll' then DrawButton[b.kind](vg,s,b) end end
        nvgRestore(vg)
        if s.maxScroll>0 then
            local thumb=math.max(24,v.h*v.h/s.contentHeight)
            G.Round(vg,p.x+p.w-4,v.y+s.scroll/s.maxScroll*(v.h-thumb),2,thumb,1,C.cyan,.5)
        end
        Hairline(vg,c.x,s.footerLine,c.w,.55)
        for _,b in ipairs(s.buttons) do
            if not b.area and (b.kind=='link' or b.kind=='primary') then DrawButton[b.kind](vg,s,b) end
        end
        if s.menuBox then
            local m=s.menuBox
            G.Round(vg,m.x-6,m.y,m.w+12,m.h,0,MENU_FILL,.99)
            G.Stroke(vg,m.x-6,m.y,m.w+12,m.h,0,C.cyan,.6,1)
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
