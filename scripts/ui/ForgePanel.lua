-- Scrollable pixel forge; UI owns the NanoVG frame and pointer dispatch.
-- Public surface: Open / Close / ForceClose / IsOpen / PreviewMode.
local UI=require('urhox-libs/UI')
local ImageCache=require('urhox-libs/UI/Core/ImageCache')
local Draw=require('ui.PixelDraw')
local Parts=require('combat.WeaponParts')
local Builder=require('combat.WeaponBuilder')
local Store=require('combat.WeaponStore')
local CombatState=require('combat.CombatState')
local TouchInput=require('ui.TouchInput')
local M={}
---@class ForgeCallbacks
---@field rig? WeaponRig
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
-- One detailed outcome per opening, and suppress repeated identical outcomes
-- for 10 seconds across reopenings. No clock capability may block the preview.
local diagnosticTimes={}
local function PreviewDiagnostic(s,outcome,detail)
    s.previewDiagnostics=s.previewDiagnostics or {}
    if s.previewDiagnostics[outcome] then return end
    s.previewDiagnostics[outcome]=true
    local p=s.preview
    local job=p and p.job
    local info=job and Builder.PreviewDiagnostic(job) or (p and p.lastDiagnostic) or 'job=none'
    local key=outcome..':'..tostring(job and job.stage or '')..':'..tostring(job and job.failureCode or '')
    local ok,now=pcall(function() return time:GetElapsedTime() end)
    if not ok or type(now)~='number' or now~=now or now<0 or now==math.huge then now=nil end
    local previous=diagnosticTimes[key]
    if previous~=nil and (not now or (type(previous)=='number' and now>=previous and now-previous<10)) then return end
    diagnosticTimes[key]=now or false
    local components=p and (' octree='..tostring(p.octree~=nil)..' zone='..tostring(p.zone~=nil)
        ..' camera='..tostring(p.camera~=nil)..' light='..tostring(p.light~=nil)) or ''
    local extra=detail and (' error='..tostring(detail):gsub('[\r\n]+',' '):sub(1,260)) or ''
    print('Forge preview mesh: '..outcome..' '..info..components..extra)
end
local SLOT_ORDER={sword={'blade','guard','grip','pommel'},bow={'limbs','grip','tip'}}
local CHANNEL_NAMES={primary='主色',secondary='副色',accent='点缀'}
local HELD_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L,KEY_ESCAPE}
local C=Draw.colors
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
local function Box(x,y,w,h) return {x=Draw.Snap(x),y=Draw.Snap(y),w=math.floor(w/2)*2,h=math.floor(h/2)*2} end
local function Message(s,text)
    s.message=text
    if s.callbacks.say then s.callbacks.say(text) end
end
local function ReleaseImage(p)
    -- A replaced UI context already released its images; never call into that pointer.
    if p.image and p.image~=0 and p.context==ImageCache.GetContext() then nvgDeleteVideo(p.context,p.image) end
    p.image,p.context=nil,nil
end
local function DestroyPreview(s)
    local p=s.preview
    if not p then return end
    ReleaseImage(p)
    if p.surface then p.surface:SetNumViewports(0) end
    Builder.CancelPreview(p.job)
    if p.mesh then Builder.DisposePreview(p.mesh) end
    if p.texture then p.texture:Dispose() end
    if p.scene then p.scene:Dispose() end
    s.preview=nil
end
local function Fallback(s,reason,detail)
    if s.fallback then return end
    PreviewDiagnostic(s,'failure_'..reason,detail)
    DestroyPreview(s)
    s.fallback=true
    s.previewMode='fallback'
    -- Failed native capability is tried again only on the next Open.
    print('Forge preview: fallback ('..reason..')')
end
local function UpdatePreview(s)
    local p=s.preview
    if not p then return end
    Builder.CancelPreview(p.job)
    p.job=Builder.BeginPreview(p.pivot,Single(s.config,s.weapon),p.mesh)
    p.state,p.age,p.rendered,p.queued='building',0,false,false
    p.dirty=true
end
local function CreatePreview(s)
    -- Keep every native resource reachable until teardown, including partial failures.
    local p={failureReason='scene'}
    s.preview=p
    p.scene=Scene()
    p.octree=assert(p.scene:CreateComponent('Octree'),'Octree nil')
    local zone=assert(p.scene:CreateComponent('Zone'),'Zone nil');p.zone=zone
    zone:SetBoundingBox(BoundingBox(Vector3(-10,-10,-10),Vector3(10,10,10)))
    zone:SetAmbientColor(Color(.65,.65,.65))
    local lamp=p.scene:CreateChild('ForgeLight')
    lamp.rotation=Quaternion(35,-30,0)
    local light=assert(lamp:CreateComponent('Light'),'Light nil');p.light=light
    light:SetLightType(LIGHT_DIRECTIONAL)
    light:SetBrightness(1.1)
    p.turn=p.scene:CreateChild('ForgeTurntable')
    p.pivot=p.turn:CreateChild('ForgeWeapon')
    p.cameraNode=p.scene:CreateChild('ForgeCamera')
    -- One fixed grip origin and scale across all parts, including long limbs.
    p.cameraNode.position=Vector3(0,.3,3)
    p.cameraNode:LookAt(Vector3(0,.3,0))
    p.camera=assert(p.cameraNode:CreateComponent('Camera'),'Camera nil')
    p.camera.orthographic=true
    p.camera.orthoSize=1.9
    p.camera.nearClip=.01
    p.camera.farClip=10
    p.failureReason='rendertexture'
    p.texture=Texture2D:new()
    p.texture:SetNumLevels(1)
    assert(p.texture:SetSize(512,512,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET),'render target')
    p.texture:SetFilterMode(FILTER_NEAREST)
    p.viewport=Viewport:new(p.scene,p.camera)
    -- Binding has both overloads; the generated LSP stub only selects RenderPath.
    ---@diagnostic disable-next-line: param-type-mismatch
    p.viewport:SetRenderPath(assert(cache:GetResource('XMLFile','RenderPaths/Forward.xml')))
    local path=p.viewport:GetRenderPath()
    for i=0,path:GetNumCommands()-1 do
        local command=path:GetCommand(i)
        if command.type==CMD_CLEAR then command.useFogColor=false; command.clearColor=Color(0,0,0,0) end
    end
    p.surface=p.texture:GetRenderSurface()
    p.surface:SetViewport(0,p.viewport)
    p.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    UpdatePreview(s)
end
local function Rebuild(s)
    local previous=s.blueprint
    s.blueprint=assert(Builder.Compile(Single(s.config,s.weapon)))
    s.baseline=assert(Builder.Compile(Single(s.original,s.weapon)))
    s.flash={}
    if previous and previous.geometry.weapon==s.weapon then
        for key,value in pairs(s.blueprint.stats) do
            if previous.stats[key]~=value then s.flash[key]=.35 end
        end
        if previous.hit.length~=s.blueprint.hit.length then s.flash.reach=.35 end
    end
    if s.preview then
        local ok,reason=pcall(UpdatePreview,s)
        if not ok then Fallback(s,'mesh',reason) end
    end
end
local Layout
local function Edit(s,action)
    s.undo={config=Copy(s.config),weapon=s.weapon,slot=s.slot}
    action();Rebuild(s);Layout(s)
end
local function Home(s)
    s.yaw=25;s.autoSpin=true;s.pauseSpin=1.5
    if s.preview then s.preview.dirty=true end
end
local function Add(s,id,label,b,action,options)
    local button=options or {}
    button.id,button.label,button.box,button.action=id,label,b,action
    s.buttons[#s.buttons+1]=button
end
Layout=function(s)
    local w,h,safe=Draw.Metrics()
    s.width,s.height=w,h
    s.safeKey=table.concat({safe.left,safe.top,safe.right,safe.bottom},':')
    local b=Box(safe.left+8,safe.top+4,w-safe.left-safe.right-16,h-safe.top-safe.bottom-8)
    s.box=b
    s.body=Box(b.x+4,b.y+60,b.w-8,math.max(56,b.h-136))
    s.buttons={}
    for i,weapon in ipairs({'sword','bow'}) do
        Add(s,'tab_'..weapon,weapon=='sword' and '剑' or '弓',Box(b.x+(i-1)*56,b.y,56,56),function()
            s.weapon=weapon;s.slot=SLOT_ORDER[weapon][1];s.scroll=0;s.colorChannel=nil
            Rebuild(s);Layout(s)
        end,{active=s.weapon==weapon,icon=weapon..'_s'})
    end
    Add(s,'close','关闭',Box(b.x+b.w-56,b.y,56,56),function() M.Close() end)
    local x,y,bw=s.body.x,s.body.y,s.body.w
    local wide=w>=720 and bw>=620
    s.wide=wide
    local left,preview,stats,cards,colors,extrasY
    if wide then
        local lw,rw=136,200
        local mw=bw-lw-rw-16
        left=Box(x,y,lw,224)
        preview=Box(x+lw+8,y,mw,144)
        cards=Box(preview.x,y+144,mw,80)
        stats=Box(x+bw-rw,y,rw,160)
        colors=Box(stats.x,y+168,rw,56)
        extrasY=y+232
        s.contentHeight=288
    else
        left=Box(x,y,bw,112)
        preview=Box(x,y+120,bw,168)
        Add(s,'stats_toggle',s.statsExpanded and '数值对比 · 收起' or '数值对比 · 展开',Box(x,y+288,bw,56),function()
            s.statsExpanded=not s.statsExpanded;Layout(s)
        end,{body=true,active=s.statsExpanded})
        local shift=s.statsExpanded and 192 or 0
        if s.statsExpanded then stats=Box(x,y+344,bw,184) end
        cards=Box(x,y+344+shift,bw,80)
        colors=Box(x,y+432+shift,bw,56)
        extrasY=y+496+shift
        s.contentHeight=616+shift
    end
    s.descriptionLines={}
    local description=assert(Parts.Get(s.config[s.weapon].parts[s.slot])).desc
    local count,limit=utf8.len(description) or 0,math.max(1,math.floor((bw-8)/12))
    for first=1,count,limit do
        local start=utf8.offset(description,first)
        local finish=utf8.offset(description,math.min(count+1,first+limit)) or (#description+1)
        s.descriptionLines[#s.descriptionLines+1]=description:sub(start,finish-1)
    end
    local descriptionHeight=#s.descriptionLines*16+8
    s.descriptionBox=Box(x,extrasY,bw,descriptionHeight)
    extrasY=extrasY+descriptionHeight;s.contentHeight=s.contentHeight+descriptionHeight
    s.previewBox,s.statsBox=preview,stats
    Add(s,'home','回正',Box(preview.x+preview.w-56,preview.y,56,56),function() Home(s) end,{body=true})
    for i,slot in ipairs(SLOT_ORDER[s.weapon]) do
        local sx,sy,sw=left.x,left.y+(i-1)*56,left.w
        if not wide then sw=math.floor(left.w/4)*2;sx=left.x+((i-1)%2)*sw;sy=left.y+((i-1)//2)*56 end
        local part=Parts.Get(s.config[s.weapon].parts[slot])
        Add(s,'slot_'..slot,Parts.SlotNames[slot],Box(sx,sy,sw,56),function() s.slot=slot;Layout(s) end,
            {body=true,active=s.slot==slot,sub=part.name})
    end
    local options=Parts.GetOptions(s.weapon,s.slot)
    local cardWidth=math.floor((cards.w-4*(#options-1))/#options/2)*2
    for i,part in ipairs(options) do
        Add(s,'part_'..part.id,part.name,Box(cards.x+(i-1)*(cardWidth+4),cards.y,cardWidth,80),function()
            Edit(s,function() s.config[s.weapon].parts[s.slot]=part.id end)
        end,{body=true,active=s.config[s.weapon].parts[s.slot]==part.id,part=part,sub=part.desc})
    end
    local colorWidth=math.floor((colors.w-8)/3/2)*2
    for i,channel in ipairs(Parts.Channels) do
        local preset=Parts.ColorPresets[s.config[s.weapon].colors[channel]]
        Add(s,'color_'..channel,CHANNEL_NAMES[channel],Box(colors.x+(i-1)*(colorWidth+4),colors.y,colorWidth,56),function()
            s.colorChannel=s.colorChannel~=channel and channel or nil;Layout(s)
            if s.colorChannel then s.scroll=s.maxScroll end
        end,{body=true,swatch=preset.rgb,sub=preset.name,active=s.colorChannel==channel})
    end
    local count=wide and 5 or 3
    local ew=math.floor((bw-(count-1)*4)/count/2)*2
    for i,preset in ipairs(Parts.Presets) do
        Add(s,'preset_'..preset.id,preset.name,Box(x+(i-1)*(ew+4),extrasY,ew,56),function()
            Edit(s,function() s.config[s.weapon]=assert(Parts.Preset(s.weapon,preset.id)) end)
        end,{body=true})
    end
    local toolsY=wide and extrasY or extrasY+64
    local tw=wide and ew or math.floor((bw-4)/4)*2
    local toolsX=wide and x+3*(ew+4) or x
    Add(s,'slot_reset','单槽复原',Box(toolsX,toolsY,tw,56),function()
        Edit(s,function() s.config[s.weapon].parts[s.slot]=s.original[s.weapon].parts[s.slot] end)
    end,{body=true})
    Add(s,'undo','撤销一步',Box(toolsX+tw+4,toolsY,tw,56),function()
        if not s.undo then return end
        s.config,s.weapon,s.slot=s.undo.config,s.undo.weapon,s.undo.slot;s.undo=nil
        Rebuild(s);Layout(s)
    end,{body=true,disabled=not s.undo})
    if s.colorChannel then
        local columns=wide and 6 or 3
        local pw=math.floor((bw-(columns-1)*4)/columns/2)*2
        local paletteY=y+s.contentHeight+8
        for i,preset in ipairs(Parts.ColorPresets) do
            Add(s,'swatch_'..i,preset.name,Box(x+((i-1)%columns)*(pw+4),paletteY+((i-1)//columns)*60,pw,56),function()
                Edit(s,function() s.config[s.weapon].colors[s.colorChannel]=i end)
            end,{body=true,swatch=preset.rgb,sub=s.config[s.weapon].colors[s.colorChannel]==i and '已选' or '选用',
                active=s.config[s.weapon].colors[s.colorChannel]==i})
        end
        s.contentHeight=s.contentHeight+8+math.ceil(6/columns)*60
    end
    s.maxScroll=math.max(0,s.contentHeight-s.body.h)
    s.scroll=Clamp(Draw.Snap(s.scroll),0,s.maxScroll)
    local footerY=b.y+b.h-72
    Add(s,'reset','恢复默认',Box(b.x,footerY,112,56),function()
        Edit(s,function() s.config[s.weapon]=Parts.DefaultWeapon(s.weapon) end)
    end)
    Add(s,'equip','装备并关闭',Box(b.x+120,footerY,b.w-120,56),function() M.Close() end,{active=true})
end
local function At(s,x,y)
    for _,button in ipairs(s.buttons) do
        if button.body then
            if Inside(x,y,s.body) and Inside(x,y+s.scroll,button.box) then return button end
        elseif Inside(x,y,button.box) then return button end
    end
end
local function Coordinates(event)
    local k=UI.GetScale()*Draw.PixelToHUD()
    return event.x*k,event.y*k
end
local function Consume(event) event:StopPropagation(); event:PreventDefault() end
local function Down(event)
    Consume(event)
    local s=session
    if not s or s.closing or s.pointer then return end
    if event.pointerType=='mouse' and not event:IsPrimaryButton() then return end
    local x,y=Coordinates(event)
    local button=At(s,x,y)
    s.pointer={id=event.pointerId,x=x,y=y,startX=x,startY=y,button=button,
        preview=not button and Inside(x,y,s.body) and Inside(x,y+s.scroll,s.previewBox),body=Inside(x,y,s.body)}
end
local function Move(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not s or not p or event.pointerId~=p.id then return end
    local x,y=Coordinates(event)
    if math.abs(x-p.startX)+math.abs(y-p.startY)>8 then p.moved=true end
    if p.moved then
        if p.preview and math.abs(x-p.startX)>=math.abs(y-p.startY) then
            s.yaw=(s.yaw+(x-p.x)*.8)%360;s.autoSpin=false;if s.preview then s.preview.dirty=true end
        elseif p.body then s.scroll=Clamp(Draw.Snap(s.scroll-(y-p.y)),0,s.maxScroll) end
    end
    p.x,p.y=x,y
end
local function Up(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not s or not p or event.pointerId~=p.id then return end
    s.pointer=nil
    local x,y=Coordinates(event)
    if not p.moved and p.button and At(s,x,y)==p.button then p.button.action()
    elseif not p.moved and p.preview then
        if s.lastTap and s.clock-s.lastTap<.35 then Home(s);s.lastTap=nil
        else s.lastTap=s.clock end
    end
end
local function Cancel(event)
    Consume(event)
    if session and session.pointer and session.pointer.id==event.pointerId then session.pointer=nil end
end
local function ChannelColor(s,channel)
    if channel=='dark' then return C.brown end
    return Parts.ColorPresets[s.config[s.weapon].colors[channel]].rgb
end
-- Front-most Z cell wins. Used for option thumbnails and native-preview fallback.
local function Pixels(vg,s,cells,b,highlight,fixedGrip)
    if #cells==0 then return end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local front={}
    for _,cell in ipairs(cells) do
        minX=math.min(minX,cell.x);maxX=math.max(maxX,cell.x)
        minY=math.min(minY,cell.y);maxY=math.max(maxY,cell.y)
        local k=cell.x..':'..cell.y
        if not front[k] or cell.z>front[k].z then front[k]=cell end
    end
    local fit=math.min(b.w/(maxX-minX+1),b.h/(maxY-minY+1))
    local pixel=math.max(2,math.floor(fit/2)*2)
    -- Small silhouettes are sampled onto a 2dp grid; never crop tall bow limbs.
    local step=math.min(pixel,fit)
    local x=Draw.Snap(b.x+(b.w-(maxX-minX+1)*step)/2)
    local y=Draw.Snap(b.y+(b.h-(maxY-minY+1)*step)/2)
    if fixedGrip then
        pixel,step=2,2
        x=Draw.Snap(b.x+b.w/2+minX*2)
        y=Draw.Snap(b.y+b.h*.64-maxY*2)
    end
    nvgSave(vg); nvgIntersectScissor(vg,b.x,b.y,b.w,b.h)
    for _,cell in pairs(front) do
        Draw.Rect(vg,x+math.floor((cell.x-minX)*step/2)*2,y+math.floor((maxY-cell.y)*step/2)*2,pixel,pixel,
            ChannelColor(s,cell.channel),highlight and cell.slot~=highlight and .4 or 1)
    end
    nvgRestore(vg)
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
-- Require a receipt for this RTT view, not just texture/mesh allocation.
-- GPU pixels/material appearance still require Web visual validation.
local function DrawNativePreview(vg,s)
    local p=s.preview
    if not p then return false end
    if p.context and p.context~=vg then ReleaseImage(p) end
    if not p.image then
        local handle=nvgCreateVideo(vg,p.texture)
        if type(handle)~='number' or handle<=0 then error('bridge') end
        p.image,p.context=handle,vg
    end
    if p.job or not p.mesh or not p.rendered or p.mesh.vertexCount<=0 or not p.mesh.materialReady then return false end
    local b=s.previewBox
    local size=math.floor(math.min(b.w,b.h-24)/2)*2
    local x,y=Draw.Snap(b.x+(b.w-size)/2),b.y+2
    nvgBeginPath(vg);nvgRect(vg,x,y,size,size)
    nvgFillPaint(vg,nvgImagePattern(vg,x,y,size,size,0,p.image,1));nvgFill(vg)
    p.state='ready'
    if s.previewMode~='3d' then s.previewMode='3d';print('Forge preview: 3d') end
    return true
end
local function Preview(vg,s)
    local b=s.previewBox
    Draw.Rect(vg,b.x,b.y,b.w,b.h-4,C.ink)
    local ok,drawn=pcall(DrawNativePreview,vg,s)
    if not ok then Fallback(s,'bridge',drawn);drawn=false end
    if not drawn then
        -- Useful pixels during creation AND after any failure/timeout.
        Pixels(vg,s,s.blueprint.geometry.cells,Box(b.x,b.y+4,b.w*.5,b.h-28),s.slot,true)
        local slots=SLOT_ORDER[s.weapon]
        local cellHeight=(b.h-28)/#slots
        for i,slot in ipairs(slots) do
            local part=Parts.Get(s.config[s.weapon].parts[slot])
            local box=Box(b.x+b.w*.5,b.y+4+(i-1)*cellHeight,b.w*.5-2,cellHeight-2)
            Pixels(vg,s,PartCells(s,part),Box(box.x,box.y,box.w-26,box.h))
            Draw.Text(vg,Parts.SlotNames[slot],box.x+box.w-24,box.y+box.h/2,12,C.paper)
        end
    end
    local label=drawn and '拖转 · 双击回正' or (s.preview and '准备3D · 部件拆解预览' or '部件拆解预览')
    Draw.Text(vg,label,b.x+b.w/2,b.y+b.h-16,12,C.muted,NVG_ALIGN_CENTER)
end
local STAT_SWORD={{'attack','攻击',20,'点'},{'speed','速度',1.4,'×'},{'reach','范围',1.4,'m'},{'poise','失衡',12,'点'}}
local STAT_BOW={{'draw','拉弓速度',1.5,'×'},{'range','射程',60,'m'},{'move','移动',1,'×'},{'armorBreak','破甲',2,'×'}}
local function Number(value,unit)
    local text
    if math.abs(value-math.floor(value+.5))<.001 then text=unit=='×' and string.format('%.1f',value) or tostring(math.floor(value+.5))
    else text=string.format('%.2f',value):gsub('0+$',''):gsub('%.$','') end
    return text..(unit or '')
end
local function StatValue(blueprint,key)
    if key=='reach' then return blueprint.hit.length*(blueprint.stats.reach or 1) end
    if key=='draw' then return Parts.BaseStats.bow.draw/blueprint.stats.draw end
    return blueprint.stats[key] or 0
end
local function Stats(vg,s)
    local b=s.statsBox
    if not b then return end
    Draw.Text(vg,'当前装备 → 候选',b.x+4,b.y+10,12,C.brown)
    for i,entry in ipairs(s.weapon=='sword' and STAT_SWORD or STAT_BOW) do
        local key,unit=entry[1],entry[4]
        local value,before=StatValue(s.blueprint,key),StatValue(s.baseline,key)
        local delta=value-before
        local y=b.y+28+(i-1)*32
        local flash=(s.flash[key] or 0)>0 and math.floor(s.clock*16)%2==0
        Draw.Text(vg,entry[2],b.x+4,y,12,C.brown)
        Draw.Text(vg,Number(before,unit)..' → '..Number(value,unit),b.x+b.w-4,y,12,flash and C.gold or C.brown,NVG_ALIGN_RIGHT)
        local filled=Clamp(math.floor(value/entry[3]*5+.5),0,5)
        for j=1,5 do Draw.Rect(vg,b.x+4+(j-1)*12,y+10,8,6,j<=filled and C.gold or C.muted) end
        if math.abs(delta)>.001 then Draw.Text(vg,(delta>0 and '+' or '')..Number(delta,unit),b.x+b.w-4,y+14,12,C.brown,NVG_ALIGN_RIGHT) end
    end
    if s.weapon=='sword' then
        Draw.Text(vg,'破甲 '..Number(s.baseline.stats.armorBreak,'×')..' → '..Number(s.blueprint.stats.armorBreak,'×'),b.x+4,b.y+152,12,C.brown)
    end
end
local function Truncate(text,limit)
    if (utf8.len(text) or 0)<=limit then return text end
    return text:sub(1,(utf8.offset(text,math.max(1,limit)) or 1)-1)..'…'
end
local function Button(vg,s,button)
    local b=button.box
    local pressed=s.pointer and not s.pointer.moved and s.pointer.button==button
    Draw.Rect(vg,b.x+2,b.y+2,b.w-2,b.h-2,C.deep)
    Draw.NineSlice(vg,button.part and 'panel_paper' or 'plaque_ink',b.x,b.y,b.w-2,b.h-4,button.part and 8 or 12)
    if button.active then Draw.Rect(vg,b.x+4,b.y+b.h-8,b.w-10,2,C.gold) end
    if pressed then Draw.Rect(vg,b.x+4,b.y+4,b.w-10,b.h-12,C.gold,.18) end
    local color=button.disabled and C.muted or (button.part and C.brown or C.paper)
    if button.icon then
        Draw.Image(vg,button.icon,b.x+(b.w-40)/2,b.y)
        Draw.Text(vg,button.label,b.x+b.w/2,b.y+44,12,color,NVG_ALIGN_CENTER)
    elseif button.part then
        Pixels(vg,s,PartCells(s,button.part),Box(b.x+4,b.y+4,32,44))
        Draw.Text(vg,button.label,b.x+40,b.y+20,12,color)
        Draw.Text(vg,Truncate(button.sub,math.floor((b.w-12)/12)),b.x+6,b.y+62,12,color)
    elseif button.swatch then
        Draw.Rect(vg,b.x+6,b.y+8,10,10,button.swatch)
        Draw.Text(vg,button.label,b.x+20,b.y+14,12,color)
        Draw.Text(vg,button.sub,b.x+b.w/2,b.y+36,12,button.swatch,NVG_ALIGN_CENTER)
    else
        Draw.Text(vg,button.label,b.x+b.w/2,b.y+(button.sub and 18 or 26),12,color,NVG_ALIGN_CENTER)
        if button.sub then Draw.Text(vg,button.sub,b.x+b.w/2,b.y+36,12,C.gold,NVG_ALIGN_CENTER) end
    end
end
local function Render(vg,s)
    if session~=s or s.closing then return end
    local w,h,safe=Draw.Metrics()
    local safeKey=table.concat({safe.left,safe.top,safe.right,safe.bottom},':')
    if w~=s.width or h~=s.height or safeKey~=s.safeKey then s.pointer=nil; Layout(s) end
    local b=s.box
    Draw.Begin(vg,true)
    Draw.Rect(vg,0,0,w,h,C.deep,.8)
    Draw.NineSlice(vg,'panel_paper',b.x,b.y,b.w,b.h,8)
    Draw.NineSlice(vg,'plaque_ink',b.x,b.y,b.w,56,12)
    Draw.Text(vg,'锻造库',b.x+(b.w+56)/2,b.y+26,24,C.paper,NVG_ALIGN_CENTER)
    nvgSave(vg);nvgIntersectScissor(vg,s.body.x,s.body.y,s.body.w,s.body.h)
    nvgTranslate(vg,0,-Draw.Snap(s.scroll))
    Preview(vg,s);Stats(vg,s)
    for i,line in ipairs(s.descriptionLines) do Draw.Text(vg,line,s.descriptionBox.x+4,s.descriptionBox.y+8+(i-1)*16,12,C.brown) end
    for _,button in ipairs(s.buttons) do if button.body then Button(vg,s,button) end end
    nvgRestore(vg)
    if s.maxScroll>0 then
        local thumb=math.max(12,s.body.h*s.body.h/s.contentHeight)
        Draw.Rect(vg,s.body.x+s.body.w-2,s.body.y+s.scroll/s.maxScroll*(s.body.h-thumb),2,thumb,C.gold)
    end
    for _,button in ipairs(s.buttons) do if not button.body then Button(vg,s,button) end end
    Draw.Text(vg,Truncate(s.message or 'Web 刷新后配置会恢复默认',math.floor((b.w-8)/12)),b.x+4,b.y+b.h-8,12,C.brown)
    Draw.Finish(vg)
end
local Layer=UI.Panel:Extend('RuinsForgePanel')
function Layer:Render(vg)
    local s=session
    if s and not s.closing then UI.QueueOverlay(function(context) Render(context,s) end) end
end
local function Released()
    if input.numTouches>0 or input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetMouseButtonDown(MOUSEB_MIDDLE) then return false end
    for _,key in ipairs(HELD_KEYS) do if input:GetKeyDown(key) then return false end end
    return true
end
local function FinishClose(s)
    if s.finished then return end
    s.finished=true
    -- Scene.Stop may have no next Update. Never schedule cleanup onto a receiver
    -- that should already be gone; the detached Lua widget can finish dispatch.
    local retired=s.layer
    UI.PopOverlay(retired);s.root:RemoveChild(retired)
    -- UI may still hold this Lua widget until an already-pressed pointer is
    -- released. Retire its geometry and callbacks without keeping native nodes
    -- or letting stale events act on a newly opened forge session.
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
    if s.closing then
        s.releaseFrames=s.releaseFrames+1
        if s.releaseFrames>=2 and Released() then FinishClose(s) end
        return
    end
    if not Safe(s.callbacks) then M.Close(true);return end
    s.updateFrame=s.updateFrame+1
    local dt=math.max(0,math.min(.1,data:GetFloat('TimeStep')))
    s.clock=s.clock+dt
    for key,value in pairs(s.flash) do s.flash[key]=math.max(0,value-dt) end
    s.pauseSpin=math.max(0,s.pauseSpin-dt)
    if s.autoSpin and s.pauseSpin==0 and not s.pointer then s.yaw=(s.yaw+dt*12)%360 end
    if s.preview then
        local p=s.preview
        -- Watchdog uses full event time, not the animation clamp or native Time.
        p.age=p.age+math.max(0,data:GetFloat('TimeStep'))
        if p.state~='ready' and p.age>=5 then Fallback(s,'timeout');return end
        local ok,reason=pcall(function()
            if p.job then
                local done,mesh=Builder.StepPreview(p.job,2,nil)
                if done then
                    s.buildMetrics={totalMs=p.job.totalMs,maxStepMs=p.job.maxStepMs,nativeMs=p.job.nativeMs,
                        overBudget=p.job.overBudget,slowestPhase=p.job.slowestPhase,clockUnavailable=p.job.clockUnavailable}
                    if not mesh then Fallback(s,'mesh');return end
                    p.lastDiagnostic=Builder.PreviewDiagnostic(p.job)
                    PreviewDiagnostic(s,'submitted')
                    p.job=nil
                    p.mesh=mesh;p.dirty=true;p.state='awaiting_render'
                    if s.buildMetrics.overBudget then print('[ForgePanel] preview build step exceeded 2ms: '..s.buildMetrics.maxStepMs..'ms / '..tostring(s.buildMetrics.slowestPhase)) end
                end
            end
            local rotated=p.yaw~=s.yaw
            if rotated then p.turn.rotation=Quaternion(0,s.yaw,0);p.yaw=s.yaw end
            if p.dirty or rotated then
                p.surface:QueueUpdate();p.dirty=false
                if p.mesh and not p.job then p.queued=true end
            end
        end)
        if not ok then Fallback(s,'render',reason) end
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
        undo=draft and Copy(draft.undo),owner=owner,scroll=0,clock=0,pauseSpin=0,yaw=25,autoSpin=true,
        thumbnails={},flash={},root=root,updateFrame=0,mouseMode=input.mouseMode,message=draft and '已恢复草稿 · Web刷新后配置会恢复默认' or nil}
    session=s
    Rebuild(s);Layout(s)
    local ok,reason=pcall(CreatePreview,s)
    if not ok then Fallback(s,s.preview and s.preview.failureReason or 'scene',reason) end
    s.layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',
        onPointerDown=Down,onPointerMove=Move,onPointerUp=Up,onPointerCancel=Cancel,
        onClick=function(_,event) if event then Consume(event) end end}
    s.layer.focusable=false
    root:AddChild(s.layer);UI.PushOverlay(s.layer)
    s.eventNode=Node()
    s.receiver=s.eventNode:CreateScriptObject('LuaScriptObject')
    s.receiver:SubscribeToEvent('Update',Update)
    s.receiver:SubscribeToEvent('EndViewRender',function(_,_,data)
        local p=s.preview
        if not p or not p.queued or p.job then return end
        -- Failed/missing pointer bindings leave the timeout armed. Never claim
        -- that another view (such as the main scene) rendered this preview.
        local ok,ours=pcall(function() return data:GetPtr('Scene')==p.scene and data:GetPtr('Surface')==p.surface end)
        if ok and ours then p.rendered=true end
    end)
    s.receiver:SubscribeToEvent('KeyDown',function(_,_,data)
        if not s.closing and data:GetInt('Key')==KEY_ESCAPE then M.Close() end
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
        DestroyPreview(s);FinishClose(s)
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
    drafts[s.owner]=nil
    DestroyPreview(s)
    TouchInput.Clear()
    return true
end
--- Includes the short release latch: callers must gate game input on this.
function M.IsOpen() return session~=nil end
--- Idempotent scene teardown / danger close, including the normal release latch.
---@return boolean
function M.ForceClose() return M.Close(true) end
--- nil while closed/closing or preparing a candidate preview.
---@return '3d'|'fallback'|nil
function M.PreviewMode()
    if not session or session.closing then return nil end
    if session.fallback then return 'fallback' end
    if session.preview and session.preview.state=='ready' then return '3d' end
    return nil
end
return M
