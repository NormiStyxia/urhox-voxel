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
local function Shadowed(vg,text,x,y,size,color,align,alpha,spacing)
    G.Text(vg,text,x+1,y+1,size,C.black,align,(alpha or 1)*.55,spacing)
    G.Text(vg,text,x,y,size,color,align,alpha,spacing)
end
local SLOT_ORDER={sword={'blade','guard','grip','pommel'},bow={'limbs','grip','tip'}}
local CHANNEL_NAMES={primary='主色',secondary='副色',accent='点缀'}
local WEAPON_NAMES={sword='长剑',bow='长弓'}
local HELD_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L,KEY_ESCAPE}
local PAD=14
local FADE_OUT,REVEAL=.2,.3 -- seconds: to black / from black
local ROOM_TIMEOUT=6
local DARK_VOXEL={92,76,60}
local MENU_FILL={16,22,40}
local SHADE_TOP,SHADE_CLEAR,SHADE_BOTTOM={8,12,24,120},{8,12,24,0},{8,12,24,170}
local LINE_CLEAR,LINE_SOLID={190,196,222,0},{190,196,222,150}
local CREAM_TOP,CREAM_BOTTOM={252,242,214},{228,204,146}
local CREAM_DOWN_TOP,CREAM_DOWN_BOTTOM={236,222,186},{206,180,120}
local CREAM_LINE={150,112,50}
local SCRIM_CLEAR,SCRIM_MID,SCRIM_SOLID={20,28,50,0},{20,28,50,140},{20,28,50,206}

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
    bow={{'draw','拉速',1.5,'×'},{'range','射程',60,'m'},{'move','移动',1,'×'}},
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
-- Look: Genshin-leaning forge sheet. A translucent ink scrim that fades in from the
-- left, serif title + sans body, round weapon badges with the pixel icons, text tabs
-- with a gliding diamond, parts as glowing pedestals (no frames), round dye swatches,
-- fading hairlines with a diamond, one cream confirm button. Nothing is boxed.
local ROW_H=32
local SLOT_EN={blade='BLADE',guard='GUARD',grip='GRIP',pommel='POMMEL',limbs='LIMBS',tip='TIP'}
local WEAPON_EN={sword='LONGSWORD',bow='LONGBOW'}
Layout=function(s)
    local w,h,safe=Draw.Metrics()
    s.width,s.height=w,h
    s.safeLeft,s.safeTop,s.safeRight,s.safeBottom=safe.left,safe.top,safe.right,safe.bottom
    local pw=math.min(w,Clamp(math.floor(w*.52),360,600))
    s.panel=Box(w-pw,0,pw,h)
    s.stage=Box(0,0,w-pw,h)
    local padR=math.max(22,safe.right+16)
    local cx,cw=s.panel.x+40,pw-40-padR
    local top,bottom=safe.top+12,h-safe.bottom-10
    s.content=Box(cx,top,cw,bottom-top)
    s.buttons={}
    -- header: caps + serif title, round weapon badges, close
    s.titlePos={x=cx,y=top+38}
    local closeX=cx+cw-36
    local bowX=closeX-58
    for i,weapon in ipairs({'sword','bow'}) do
        local x=bowX-(2-i)*54
        Add(s,'tab_'..weapon,weapon=='sword' and '剑' or '弓',Box(x,top+4,48,48),function()
            if s.weapon==weapon then return end
            s.weapon=weapon;s.slot=SLOT_ORDER[weapon][1];s.scroll=0;s.colorChannel=nil;s.moreOpen=false
            Rebuild(s);Layout(s)
        end,{kind='badge',active=s.weapon==weapon,icon=weapon})
    end
    Add(s,'close','关闭',Box(closeX,top+6,44,44),function() M.Close() end,{kind='close'})
    -- temporary blade-route comparison chips on the stage (sword only)
    if s.weapon=='sword' then
        local rx=math.max(26,safe.left+14)
        local ry=h-safe.bottom-78
        local rw=math.max(40,math.min(70,((w-pw)-rx-12-18)/4))
        for i,r in ipairs({{'original','体素'},{'A','A硬边'},{'B','B方块'},{'flow','流光'}}) do
            Add(s,'route_'..r[1],r[2],Box(rx+(i-1)*(rw+6),ry,rw,34),function()
                local room=Room()
                if not (s.room and room) then return end
                if r[1]=='flow' then
                    local cur=room.GetFlowStrength and room.GetFlowStrength() or 0
                    pcall(room.SetFlowStrength,cur>0 and 0 or .7)
                else pcall(room.SetModelRoute,r[1]) end
            end,{kind='route',route=r[1]})
        end
    end
    s.headerLine=top+58
    -- slot tabs (fixed under the header): text with a diamond that glides
    local slots=SLOT_ORDER[s.weapon]
    local tabY=top+62
    s.slotCenters={}
    for i,slot in ipairs(slots) do
        local sx,sw=Span(cx,cw,i,#slots,0)
        s.slotCenters[slot]=sx+sw/2
        Add(s,'slot_'..slot,Parts.SlotNames[slot],Box(sx,tabY,sw,36),function() s.slot=slot;Layout(s) end,
            {kind='tab',active=s.slot==slot,slot=slot})
    end
    s.tabY=tabY
    -- footer: recommended menu / undo links, cream confirm button
    local fy=bottom-46
    s.footerY=fy;s.footerLine=fy-8
    Add(s,'recommend','推荐方案',Box(cx,fy,100,46),function() s.menuOpen=not s.menuOpen;Layout(s) end,{kind='link',menuToggle=true,active=s.menuOpen})
    Add(s,'undo','撤销',Box(cx+110,fy,52,46),function()
        if not s.undo then return end
        s.config,s.weapon,s.slot=s.undo.config,s.undo.weapon,s.undo.slot;s.undo=nil
        Rebuild(s);Layout(s)
    end,{kind='link',disabled=not s.undo})
    local equipW=Clamp(cw-184,104,150)
    Add(s,'equip','装备',Box(cx+cw-equipW,fy,equipW,46),function() M.Close() end,{kind='primary'})
    -- scrolling viewport
    local vy=tabY+42
    local vh=s.footerLine-4-vy
    s.view=Box(s.panel.x,vy,pw,vh)
    local cy=vy
    local options=Parts.GetOptions(s.weapon,s.slot)
    for i,part in ipairs(options) do
        local x,cwid=Span(cx,cw,i,#options,6)
        local b=Add(s,'part_'..part.id,part.name,Box(x,cy,cwid,92),function()
            Edit(s,function() s.config[s.weapon].parts[s.slot]=part.id end)
        end,{kind='card',area='scroll',active=s.config[s.weapon].parts[s.slot]==part.id,part=part})
        b.thumb=Box(x+6,cy+3,cwid-12,58)
        b.glow={x=x+cwid/2,y=cy+32}
    end
    cy=cy+92
    s.descPart=assert(Parts.Get(s.config[s.weapon].parts[s.slot]))
    s.descPos={x=cx+cw/2,y=cy+10}
    cy=cy+24
    s.dividerY=cy
    cy=cy+12
    -- dye swatches: one row, label left, round swatches right
    s.colorCol=Box(cx,cy,cw,10)
    local chipW=Clamp(math.floor((cw-80)/3),50,76)
    for i,channel in ipairs(Parts.Channels) do
        local preset=Parts.ColorPresets[s.config[s.weapon].colors[channel]]
        local chx=cx+cw-(4-i)*chipW
        Add(s,'color_'..channel,CHANNEL_NAMES[channel],Box(chx,cy,chipW,58),function()
            s.colorChannel=s.colorChannel~=channel and channel or nil;Layout(s)
            if s.colorChannel then s.scroll=s.maxScroll end
        end,{kind='chip',area='scroll',swatch=preset.rgb,active=s.colorChannel==channel})
    end
    cy=cy+58
    -- dye palette: a full-width row of round swatches
    s.paletteBox=nil;s.paletteTitle=nil
    if s.colorChannel then
        local current=s.config[s.weapon].colors[s.colorChannel]
        local count=#Parts.ColorPresets
        s.dividerY2=cy+2
        s.paletteTitle={x=cx,y=cy+20,text=CHANNEL_NAMES[s.colorChannel]..'  ·  '..Parts.ColorPresets[current].name}
        s.paletteBox=Box(cx,cy+34,cw,44)
        for i,preset in ipairs(Parts.ColorPresets) do
            local px,pwid=Span(cx,cw,i,count,0)
            Add(s,'swatch_'..i,preset.name,Box(px,cy+34,pwid,44),function()
                Edit(s,function() s.config[s.weapon].colors[s.colorChannel]=i end)
            end,{kind='swatch',area='scroll',swatch=preset.rgb,active=current==i})
        end
        cy=cy+86
    else s.dividerY2=nil end
    cy=cy+6
    s.contentHeight=cy-vy
    s.maxScroll=math.max(0,s.contentHeight-vh)
    s.scroll=Clamp(s.scroll,0,s.maxScroll)
    -- attributes live on the stage, bottom-left, next to the weapon
    s.statRows=s.statRows or StatRows(s,STAT_MAIN[s.weapon])
    local sx=math.max(26,safe.left+14)
    local sw=Clamp(s.stage.w-sx-28,140,300)
    local rows=#s.statRows
    s.moreBox=nil
    if s.moreOpen then
        s.moreRows=s.moreRows or StatRows(s,STAT_MORE[s.weapon])
        rows=rows+#s.moreRows
    end
    local statsH=30+rows*ROW_H
    local sy=h-safe.bottom-66-statsH
    s.attrTitle={x=sx,y=sy+12}
    s.attrRowsY=sy+30
    s.attrRight={x=sx,w=sw}
    Add(s,'more',s.moreOpen and '收起' or '更多',Box(sx+sw-56,sy-4,60,36),function() s.moreOpen=not s.moreOpen;Layout(s) end,{kind='link',small=true})
    if s.moreOpen then s.moreBox={x=sx,y=s.attrRowsY+#s.statRows*ROW_H,w=sw,h=#s.moreRows*ROW_H} end
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
        local mh=#items*36+28
        local menu=Box(cx-8,fy-14-mh,176,mh)
        s.menuBox=menu
        for i,item in ipairs(items) do
            Add(s,item.id,item.label,Box(menu.x+8,menu.y+14+(i-1)*36,menu.w-16,36),function()
                s.menuOpen=false
                item.action()
                Layout(s)
            end,{kind='menu',area='menu',gap=item.gap})
        end
    else s.menuBox=nil end
    s.sideBox=Box(s.stage.x+60,s.stage.y+h*.2,math.max(1,s.stage.w-120),math.max(1,h*.52))
    s.sideCells=s.blueprint.geometry.cells
    s.stageTitle=WEAPON_NAMES[s.weapon]
    s.stageCaption=WEAPON_EN[s.weapon]
    s.stageSub=string.format('%02d / %s  ·  %s',(function() for i,v in ipairs(SLOT_ORDER[s.weapon]) do if v==s.slot then return i end end return 1 end)(),
        SLOT_EN[s.slot],s.descPart.name)
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
-- Front-most cell per (u,v), grouped by channel/slot so a whole thumbnail is a
-- handful of NanoVG fills instead of one fill per voxel. Swords read best from
-- the front (x,y); a bow's curve lives in depth, so it is shown from the side (z,y).
local function SideLayout(cells,b,maxStep,side)
    if b.cells==cells and b.fitW==b.w and b.fitH==b.h and b.side==side then return end
    b.cells,b.fitW,b.fitH,b.side=cells,b.w,b.h,side
    b.groups={}
    if #cells==0 then return end
    local hk,dk='x','z'
    if side then hk,dk='z','x' end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local front={}
    for _,cell in ipairs(cells) do
        local u=cell[hk]
        minX=math.min(minX,u);maxX=math.max(maxX,u)
        minY=math.min(minY,cell.y);maxY=math.max(maxY,cell.y)
        local k=u..':'..cell.y
        if not front[k] or cell[dk]>front[k][dk] then front[k]=cell end
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
        rects[#rects+1]=ox+(cell[hk]-minX)*step
        rects[#rects+1]=oy+(maxY-cell.y)*step
    end
    table.sort(b.groups,function(a,c) return (a.channel..tostring(a.slot))<(c.channel..tostring(c.slot)) end)
end
local function SidePixels(vg,s,cells,b,highlight,alpha,maxStep)
    SideLayout(cells,b,maxStep,s.weapon=='bow')
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
-- Fading hairline with a small diamond in the middle.
local function Ornament(vg,x,y,w,alpha,diamond)
    G.HGradient(vg,x,y,w/2,1,LINE_CLEAR,LINE_SOLID,alpha or 1)
    G.HGradient(vg,x+w/2,y,w/2,1,LINE_SOLID,LINE_CLEAR,alpha or 1)
    if diamond~=false then G.Diamond(vg,x+w/2,y+.5,3,C.gold,.9*(alpha or 1)) end
end
local function Caps(vg,text,x,y,size,color,alpha,align)
    G.Text(vg,text,x,y,size,color or C.sub,align,alpha,2.5)
end
local function Ease(current,target,dt)
    return current+(target-current)*math.min(1,dt*14)
end

local DrawButton={}
function DrawButton.badge(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2,bx.y+bx.h/2
    local a=s.anim[b.id] or 0
    -- ruins medallion (generated art): quiet disc, crossfading to the lit one
    if G.Picture(vg,'ui/forge/medal_idle.png',cx-24,cy-24,48,48,1-a*.6) then
        if a>.01 then G.Picture(vg,'ui/forge/medal_active.png',cx-29,cy-29,58,58,a) end
    else
        G.Circle(vg,cx,cy,22,C.plate,.55+.3*a)
        G.Ring(vg,cx,cy,22,b.active and C.gold or C.line,b.active and .95 or .35,b.active and 1.6 or 1)
    end
    local icon=b.icon=='sword' and 'ui/forge/icon_sword.png' or 'ui/forge/icon_bow.png'
    nvgSave(vg);nvgTranslate(vg,cx,cy);nvgRotate(vg,math.pi/4)
    local drawn=G.Picture(vg,icon,b.icon=='sword' and -6.2 or -5.2,-19,b.icon=='sword' and 12.4 or 9.8,38,.95)
    nvgRestore(vg)
    if not drawn then Icon(vg,b.icon,cx-16,cy-16) end
end
function DrawButton.close(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2+4,bx.y+bx.h/2
    local a=Pressed(s,b) and 1 or .75
    G.Line(vg,cx-6,cy-6,cx+6,cy+6,C.ivory,a,1.3)
    G.Line(vg,cx+6,cy-6,cx-6,cy+6,C.ivory,a,1.3)
end
function DrawButton.route(vg,s,b)
    local bx=b.box
    local room=Room()
    local active=false
    if room then
        if b.route=='flow' then active=(room.GetFlowStrength and room.GetFlowStrength() or 0)>0
        else active=(room.GetModelRoute and room.GetModelRoute())==b.route end
    end
    local color=(active or Pressed(s,b)) and C.gold or C.ivory
    G.Round(vg,bx.x,bx.y,bx.w,bx.h,0,C.black,active and .5 or .32)
    G.Stroke(vg,bx.x,bx.y,bx.w,bx.h,0,color,active and .9 or .35,1)
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2,14,color,NVG_ALIGN_CENTER,nil,1)
end
function DrawButton.tab(vg,s,b)
    local bx=b.box
    local color=(b.active or Pressed(s,b)) and C.gold or C.sub
    G.Text(vg,b.label,bx.x+bx.w/2,bx.y+bx.h/2-3,17,color,NVG_ALIGN_CENTER,nil,1,b.active and 'medium' or 'sans')
end
function DrawButton.link(vg,s,b)
    local bx=b.box
    local color=b.disabled and C.dim or ((b.active or Pressed(s,b)) and C.gold or C.ivory)
    local size=b.small and 14 or 16
    local width=G.EstimateWidth(b.label,size)
    if b.small then
        Shadowed(vg,b.label,bx.x+bx.w,bx.y+bx.h/2,size,(Pressed(s,b) and C.gold or C.ivory),NVG_ALIGN_RIGHT,nil,1)
        return
    end
    G.Text(vg,b.label,bx.x,bx.y+bx.h/2,size,color,nil,nil,1)
    if b.menuToggle then
        local tx,ty=bx.x+width+12,bx.y+bx.h/2+1
        nvgBeginPath(vg)
        if b.active then nvgMoveTo(vg,tx-4,ty+2.5);nvgLineTo(vg,tx+4,ty+2.5);nvgLineTo(vg,tx,ty-2.5)
        else nvgMoveTo(vg,tx-4,ty-2.5);nvgLineTo(vg,tx+4,ty-2.5);nvgLineTo(vg,tx,ty+2.5) end
        nvgClosePath(vg);nvgFillColor(vg,G.Color(color,1));nvgFill(vg)
    end
end
function DrawButton.primary(vg,s,b)
    local bx=b.box
    local pressed=Pressed(s,b)
    local dy=pressed and 1 or 0
    G.Round(vg,bx.x+2,bx.y+4,bx.w-4,bx.h-4,0,C.black,.28)
    if G.NineSlice(vg,'ui/forge/plate_button.png',bx.x,bx.y+dy,bx.w,bx.h,64,bx.h/145,1) then
        if pressed then G.Round(vg,bx.x+3,bx.y+3+dy,bx.w-6,bx.h-6,0,C.black,.14) end
    else
        G.Gradient(vg,bx.x,bx.y+dy,bx.w,bx.h,9,pressed and CREAM_DOWN_TOP or CREAM_TOP,pressed and CREAM_DOWN_BOTTOM or CREAM_BOTTOM,1)
    end
    G.Text(vg,'装 备',bx.x+bx.w/2+1,bx.y+bx.h/2+dy,19,C.ink,NVG_ALIGN_CENTER,nil,3,'serif')
end
function DrawButton.card(vg,s,b)
    local f=b.thumb
    local a=s.anim[b.id] or (b.active and 1 or 0)
    if a>.01 then
        for i=1,5 do G.Circle(vg,b.glow.x,b.glow.y,22+i*8,C.gold,a*.065) end
    end
    SidePixels(vg,s,PartCells(s,b.part),f,nil,.62+.38*a,10)
    local bx=b.box
    G.Text(vg,G.Fit(b.label,16,bx.w+4),bx.x+bx.w/2,bx.y+bx.h-24,16,a>.5 and C.gold or C.sub,NVG_ALIGN_CENTER,nil,1,a>.5 and 'medium' or 'sans')
    if a>.01 then G.Diamond(vg,bx.x+bx.w/2,bx.y+bx.h-8,3*a,C.gold,a) end
end
function DrawButton.chip(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2,bx.y+16
    if b.active then
        G.Ring(vg,cx,cy,19,C.gold,1,1.6)
        for i=1,3 do G.Circle(vg,cx,cy,19+i*4,C.gold,.06) end
    end
    G.Circle(vg,cx,cy,14,b.swatch,1)
    G.Ring(vg,cx,cy,14,C.ivory,.35,1)
    G.Text(vg,b.label,cx,bx.y+bx.h-14,13,b.active and C.gold or C.sub,NVG_ALIGN_CENTER,nil,1)
end
function DrawButton.swatch(vg,s,b)
    local bx=b.box
    local cx,cy=bx.x+bx.w/2,bx.y+bx.h/2
    G.Circle(vg,cx,cy,Pressed(s,b) and 12 or 13,b.swatch,1)
    G.Ring(vg,cx,cy,13,C.ivory,.3,1)
    if b.active then G.Ring(vg,cx,cy,18,C.gold,1,1.6) end
end
function DrawButton.menu(vg,s,b)
    local bx=b.box
    if b.gap then Ornament(vg,bx.x+14,bx.y,bx.w-28,.5,false) end
    if Pressed(s,b) then G.Round(vg,bx.x+8,bx.y+3,bx.w-16,bx.h-6,0,C.gold,.18) end
    G.Text(vg,b.label,bx.x+20,bx.y+bx.h/2,16,Pressed(s,b) and C.gold or C.ivory,nil,nil,1)
end

local function Attributes(vg,s)
    Shadowed(vg,'属性',s.attrTitle.x,s.attrTitle.y,17,C.ivory,nil,nil,3,'serif')
    local x,w=s.attrRight.x,s.attrRight.w
    local y=s.attrRowsY
    local function Row(row)
        local flash=(s.flash[row.key] or 0)>0 and math.floor(s.clock*16)%2==0
        Shadowed(vg,row.label,x,y+ROW_H/2-1,15,C.ivory,nil,.85,1)
        Shadowed(vg,row.value,x+w*.42,y+ROW_H/2-1,20,flash and C.gold or C.ivory,nil,nil,0,'medium')
        if row.delta then
            local col=row.up and C.leaf or C.coral
            Shadowed(vg,row.delta,x+w,y+ROW_H/2,13,col,NVG_ALIGN_RIGHT)
            local tx=x+w-G.EstimateWidth(row.delta,13)-9
            if row.up then G.Poly(vg,col,1,tx-4,y+ROW_H/2+3,tx+4,y+ROW_H/2+3,tx,y+ROW_H/2-3)
            else G.Poly(vg,col,1,tx-4,y+ROW_H/2-3,tx+4,y+ROW_H/2-3,tx,y+ROW_H/2+3) end
        end
        Ornament(vg,x,y+ROW_H-1,w,.28,false)
        y=y+ROW_H
    end
    for _,row in ipairs(s.statRows) do Row(row) end
    if s.moreBox then for _,row in ipairs(s.moreRows) do Row(row) end end
    for _,b in ipairs(s.buttons) do if b.id=='more' then DrawButton.link(vg,s,b) end end
end

local CLOUDS={{-.38,.28,64},{.22,.18,80},{.52,.34,58}}
local ISLETS={{-.34,.44,34},{.4,.5,26}}
local function Backdrop(vg,s)
    -- No 3D room: a flat 2D take on the same showroom (ruins palette) so the
    -- fallback still looks like part of the world.
    local st=s.stage
    local h=s.height
    local cx=math.floor(st.w*.5)
    local floorY=math.floor(h*.8)
    G.Gradient(vg,0,0,s.width,h,0,C.skyTop,C.skyLow,1)
    for i=1,4 do G.Circle(vg,cx-st.w*.3,h*.16,22+i*16,C.ivory,.07) end
    for _,c in ipairs(CLOUDS) do
        local x,y,w=cx+st.w*c[1],h*c[2],c[3]
        G.Round(vg,x,y,w,10,0,C.ivory,.85);G.Round(vg,x+10,y-8,w*.55,10,0,C.ivory,.85)
    end
    for _,o in ipairs(ISLETS) do
        local x,y,w=cx+st.w*o[1],h*o[2],o[3]
        G.Round(vg,x,y,w,6,0,C.grass,1)
        G.Round(vg,x+3,y+6,w-6,6,0,C.stone,1)
        G.Round(vg,x+8,y+12,w-16,6,0,C.stoneDark,1)
        G.Round(vg,x+13,y+18,w-26,5,0,C.stoneDark,1)
    end
    local pillarX=st.w*.42
    local top=h*.1
    for sx=-1,1,2 do
        local x=cx+sx*pillarX-12
        G.Round(vg,x,top+34,24,floorY-top-34,0,C.marble,1)
        G.Round(vg,x+17,top+34,7,floorY-top-34,0,C.marbleShade,1)
        G.Round(vg,x-2,top+88,28,5,0,C.gold,1)
        G.Round(vg,x-2,floorY-60,28,5,0,C.gold,1)
    end
    nvgBeginPath(vg);nvgArc(vg,cx,top+36,pillarX,math.pi,math.pi*2,2)
    nvgStrokeColor(vg,G.Color(C.marble,1));nvgStrokeWidth(vg,16);nvgStroke(vg)
    nvgBeginPath(vg);nvgArc(vg,cx,top+36,pillarX-11,math.pi,math.pi*2,2)
    nvgStrokeColor(vg,G.Color(C.blueMarble,1));nvgStrokeWidth(vg,5);nvgStroke(vg)
    G.Round(vg,cx-7,top+36-pillarX-9,14,18,0,C.gold,1)
    G.Ellipse(vg,cx,floorY+10,st.w*.5,34,C.stoneDark,.55)
    G.Ellipse(vg,cx,floorY+4,st.w*.42,30,C.stone,1)
    G.Ellipse(vg,cx,floorY-4,st.w*.3,24,C.marbleShade,1)
    G.Ellipse(vg,cx,floorY-12,st.w*.3,24,C.marble,1)
    G.EllipseStroke(vg,cx,floorY-12,st.w*.255,19,C.gold,1,3)
    G.Ellipse(vg,cx,floorY-14,st.w*.2,14,C.rune,1)
    G.EllipseStroke(vg,cx,floorY-14,st.w*.13,9,C.gold,.9,1.5)
    for sx=-1,1,2 do
        local x=cx+sx*st.w*.34
        G.Round(vg,x-12,floorY-10,24,8,0,C.gold,1)
        G.Poly(vg,C.crystal,1,x-8,floorY-10,x-2,floorY-44,x+3,floorY-10)
        G.Poly(vg,C.rune,1,x+1,floorY-10,x+8,floorY-30,x+12,floorY-10)
    end
    local b=s.sideBox
    G.Ellipse(vg,cx,floorY-16,st.w*.1,7,C.gold,.28)
    nvgSave(vg)
    nvgTranslate(vg,b.x+b.w/2,b.y+b.h/2);nvgRotate(vg,s.weapon=='sword' and -.22 or 0);nvgTranslate(vg,-(b.x+b.w/2),-(b.y+b.h/2))
    SidePixels(vg,s,s.sideCells,b,s.slot,1,18)
    nvgRestore(vg)
end
local function Stage(vg,s)
    local st=s.stage
    if s.fallback then Backdrop(vg,s)
    elseif not s.roomReady then
        G.Text(vg,'正在准备展示间…',st.x+st.w/2,st.y+st.h/2,15,C.sub,NVG_ALIGN_CENTER)
    end
    G.Gradient(vg,0,0,st.w,130,0,SHADE_TOP,SHADE_CLEAR,1)
    G.Gradient(vg,0,s.height-230,st.w,230,0,SHADE_CLEAR,SHADE_BOTTOM,1)
    local x=math.max(26,s.safeLeft+14)
    local y=s.safeTop+30
    Shadowed(vg,s.stageCaption,x,y,11,C.gold,nil,nil,3)
    Shadowed(vg,s.stageTitle,x,y+32,32,C.ivory,nil,nil,5,'serif')
    Shadowed(vg,s.stageSub,x,y+62,14,C.ivory,nil,.8,1)
    Attributes(vg,s)
    local by=s.height-s.safeBottom-22
    if s.message then Shadowed(vg,G.Fit(s.message,14,st.w-40),x,by-26,14,C.gold) end
    if s.fallback or s.roomReady then
        nvgBeginPath(vg);nvgArc(vg,x+8,by,6.5,-2.6,2.6,NVG_CW or 2)
        nvgStrokeColor(vg,G.Color(C.ivory,.85));nvgStrokeWidth(vg,1.5);nvgStroke(vg)
        Shadowed(vg,'拖动旋转',x+24,by,14,C.ivory,nil,nil,1)
        if s.roomReady and s.weapon=='sword' then
            for _,b in ipairs(s.buttons) do if b.kind=='route' then DrawButton.route(vg,s,b) end end
        end
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
        -- borderless: an ink scrim that fades in from the left, no outline
        G.HGradient(vg,p.x-200,0,200,h,SCRIM_CLEAR,SCRIM_MID,1)
        G.HGradient(vg,p.x-90,0,90,h,SCRIM_CLEAR,SCRIM_MID,1)
        G.Round(vg,p.x,0,p.w,h,0,SCRIM_SOLID,1)
        -- the sheet's content eases in from the right while it fades up
        nvgSave(vg);nvgTranslate(vg,(1-alpha)*28,0)
        Caps(vg,'WEAPON FORGE',s.titlePos.x,s.titlePos.y-30,10,C.gold)
        G.Text(vg,'锻造库',s.titlePos.x,s.titlePos.y,31,C.ivory,nil,nil,5,'serif')
        for _,b in ipairs(s.buttons) do
            if b.kind=='badge' or b.kind=='close' then DrawButton[b.kind](vg,s,b) end
        end
        Ornament(vg,c.x,s.headerLine,c.w,.9)
        -- slot tabs + the gliding diamond
        for _,b in ipairs(s.buttons) do if b.kind=='tab' then DrawButton.tab(vg,s,b) end end
        local ix=s.slotX or s.slotCenters[s.slot]
        G.Round(vg,ix-12,s.tabY+33,24,1.5,0,C.gold,.9)
        G.Diamond(vg,ix,s.tabY+34,3,C.gold,1)
        -- scrolling content
        local v=s.view
        nvgSave(vg);nvgIntersectScissor(vg,v.x,v.y,v.w,v.h)
        nvgTranslate(vg,0,-s.scroll)
        G.Text(vg,G.Fit(s.descPart.desc,13,c.w),s.descPos.x,s.descPos.y,13,C.sub,NVG_ALIGN_CENTER,nil,1)
        Ornament(vg,c.x,s.dividerY,c.w,.55)
        G.Text(vg,'配色',s.colorCol.x,s.colorCol.y+16,17,C.ivory,nil,nil,3,'serif')
        Caps(vg,'DYE',s.colorCol.x,s.colorCol.y+38,10,C.dim)
        if s.dividerY2 then Ornament(vg,c.x,s.dividerY2,c.w,.4,false) end
        if s.paletteTitle then G.Text(vg,s.paletteTitle.text,s.paletteTitle.x+1,s.paletteTitle.y,14,C.sub,nil,nil,1) end
        for _,b in ipairs(s.buttons) do if b.area=='scroll' then DrawButton[b.kind](vg,s,b) end end
        nvgRestore(vg)
        if s.maxScroll>0 then
            local thumb=math.max(24,v.h*v.h/s.contentHeight)
            G.Round(vg,p.x+p.w-5,v.y+s.scroll/s.maxScroll*(v.h-thumb),2,thumb,1,C.gold,.45)
        end
        Ornament(vg,c.x,s.footerLine,c.w,.6,false)
        for _,b in ipairs(s.buttons) do
            if not b.area and b.id~='more' and (b.kind=='link' or b.kind=='primary') then DrawButton[b.kind](vg,s,b) end
        end
        if s.menuBox then
            local m=s.menuBox
            G.Round(vg,m.x-2,m.y+3,m.w+4,m.h+2,0,C.black,.3)
            if not G.NineSlice(vg,'ui/forge/plate_menu.png',m.x-8,m.y-8,m.w+16,m.h+16,64,.42,1) then
                G.Round(vg,m.x,m.y,m.w,m.h,0,MENU_FILL,.98)
            end
            for _,b in ipairs(s.buttons) do if b.area=='menu' then DrawButton.menu(vg,s,b) end end
        end
        nvgRestore(vg)
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
-- The HUD layers read this (plus HudHidden()); published as soon as the phase moves,
-- before the HUD draws, and cleared on every close path.
local hudPublished=false
rawset(_G,'FORGE_HUD_HIDDEN',false)
local function PublishHud(hidden)
    if hudPublished==hidden then return end
    hudPublished=hidden
    rawset(_G,'FORGE_HUD_HIDDEN',hidden)
    print('Forge: hudHidden='..tostring(hidden))
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
    PublishHud(false)
    if s.callbacks.onClose then s.callbacks.onClose(Copy(s.config),s.saved,s.keptDraft==true) end
end
---@param data VariantMap
local function UpdateInner(_,_,data)
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
    for _,b in ipairs(s.buttons) do
        if b.kind=='card' or b.kind=='badge' then
            s.anim[b.id]=Ease(s.anim[b.id] or (b.active and 1 or 0),b.active and 1 or 0,dt)
        end
    end
    local center=s.slotCenters and s.slotCenters[s.slot]
    if center then s.slotX=Ease(s.slotX or center,center,dt) end
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
local function Update(a,b,data)
    UpdateInner(a,b,data)
    PublishHud(session~=nil and M.HudHidden() or false)
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
        thumbnails={},flash={},anim={},root=root,updateFrame=0,mouseMode=input.mouseMode,
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
--- True while the forge covers the screen (opening fade past black ... closing fade
--- back to black). Gameplay HUD layers must not draw during this time.
---@return boolean
function M.HudHidden()
    local s=session
    if not s or s.finished then return false end
    local black,alpha=PhaseValues(s)
    return alpha>0 or black>=.6
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
