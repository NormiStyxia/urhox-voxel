-- Presentation and hit boxes share the prototype's 380 x 214 art grid.
local Draw = require('ui.PixelDraw')
local Catalog = require('combat.WeaponCatalog')
local Store = require('combat.WeaponStore')
local Preview = require('ui.ForgePreview')
local M = {width=380,height=214}
local P = {
    ink={49,62,68},muted={86,100,98},edge={137,151,143},paper={244,241,228},paperDeep={227,224,207},
    light={250,244,222},line={183,192,180},survey={201,208,192},green={46,82,75},gold={215,177,102},
    red={134,69,52},blue={38,94,153},rank={158,115,36},
}
local ROLES = {
    {name='锋位',color={168,58,50},hint='强化进攻'},
    {name='破位',color=P.blue,hint='强化压制'},
    {name='时位',color={36,110,94},hint='同类武器共享'},
}
local ROMAN={'I','II','III'}
local PASSIVES={
    stable={'稳固','连击第三段削韧 +20%'}, guard={'守门','对失衡敌人伤害 +15%'},
    wind={'逐风','冲刺后首击伤害 +25%'}, hunt={'游猎','对未察觉敌人伤害 +15%'},
    silver={'银枝','满蓄力射击削韧 +25%'}, thorn={'荆棘','满蓄力射击伤害 +20%'},
    star={'星砂','碎时伤害 +20%'},
}
local STATS={attack='攻击',reach='攻击范围',poise='削韧',armorBreak='破甲',move='拉弓移速',terrainRadius='破坏范围'}
local SKILL={sword='重击 · Q',bow='蓄力射击',time='碎时 · 破坏地形'}
local RX,RW=222,136
local function Round(n) return math.floor(n+.5) end
local function Rect(vg,x,y,w,h,color) Draw.Rect(vg,Round(x),Round(y),w,h,color) end
local function Text(vg,label,x,y,color,align) Draw.Text(vg,label,x,y,6,color or P.ink,align) end
local function Right(vg,label,x,y,color) Text(vg,label,x,y,color,NVG_ALIGN_RIGHT) end
local function Center(vg,label,x,y,color) Text(vg,label,x,y,color,NVG_ALIGN_CENTER) end
local function Line(vg,y) Rect(vg,RX,y,RW,1,P.line) end
local function Hit(s,id,x,y,w,h,action)
    s.buttons[#s.buttons+1]={id=id,x=x,y=y,w=w,h=h,action=action}
end
local function Button(vg,s,id,x,y,w,h,label,active,action,disabled,color)
    local fill=active and (color or P.green) or (disabled and P.paperDeep or P.paper)
    Rect(vg,x,y,w,h,active and fill or (disabled and P.paperDeep or P.edge))
    Rect(vg,x+1,y+1,w-2,h-2,fill)
    Center(vg,label,x+w*.5,y+h*.5,active and P.light or (disabled and P.edge or color or P.ink))
    if action and not disabled then Hit(s,id,x,y,w,h,action) end
end
local function Icon(vg,id,x,y)
    local icon=Preview.Icon(id)
    if icon then Draw.ImagePixels(vg,'ui/forge/imprints/'..icon..'_20.png',x,y) end
end
local function Benefit(seal,rank)
    return (STATS[seal.stat] or seal.label)..(' +%d%%'):format(Round(seal.bonus*rank*100))
end
local function Equipment(s)
    local progress=s.config.progress
    local slot=progress.slots[s.class]
    return progress,slot,slot.imprints,Catalog.Imprints[s.class]
end
local function Header(vg,s,progress)
    Text(vg,s.mode=='forge' and '独立锻造台' or '武器整备',34,19)
    if s.mode=='forge' then
        Button(vg,s,'weapon',88,12,52,14,'← 武器整备',false,s.showWeapon)
    else
        Button(vg,s,'detail',88,12,42,14,'详情',s.tab=='detail',s.showDetail)
        Button(vg,s,'imprint',134,12,42,14,'时印',s.tab=='imprint',function() s.focus(s.focusIndex) end)
        Button(vg,s,'forge',180,12,36,14,'锻造 →',false,s.showForge)
    end
    Right(vg,('矿 %d · 砂 %d'):format(progress.ore,progress.sand),322,19,P.muted)
    Right(vg,'关闭 ×',360,19)
    Hit(s,'close',326,8,40,20,s.close)
end
local function Orbit(vg,s)
    for deg=0,356,4 do
        local angle=math.rad(deg)
        Rect(vg,114+math.cos(angle)*60,112+math.sin(angle)*20,1,1,deg%20==0 and P.edge or P.survey)
        if deg%30==0 then Rect(vg,114+math.cos(angle)*64,112+math.sin(angle)*21.5,1,1,P.gold) end
    end
    for i=0,2 do
        Rect(vg,52+i*64+math.sin(s.clock*.7+i*2)*8,56+(s.clock*6+i*42)%108,1,1,i==1 and P.gold or P.survey)
    end
end
local function Stage(vg,s,item,tier,level,equipped)
    local forge=s.mode=='forge'
    Draw.ImagePixels(vg,forge and 'ui/forge/forge_pedestal.png' or 'ui/forge/pedestal.png',22,29)
    if not forge then Orbit(vg,s) end
    Preview.Raster(s.preview,item.id,forge,equipped,Catalog.ImprintRoles,
        s.tab=='imprint' and s.focusIndex or nil,s.clock)
    Preview.Draw(vg,s.preview)
    if forge then
        Text(vg,item.name..' · 锻造',24,180)
        Text(vg,'滑动观看武器细节',24,190,P.muted)
        return
    end
    for i,role in ipairs(ROLES) do
        local center=s.preview.centers[i]
        local x,y=center.x,center.y
        local focused=s.tab=='imprint' and s.focusIndex==i
        if focused then
            for _,dir in ipairs({-1,1}) do
                local bx=x+dir*14
                Rect(vg,bx,y-8,1,17,role.color)
                Rect(vg,bx+(dir==-1 and 0 or -2),y-9,3,1,P.gold)
                Rect(vg,bx+(dir==-1 and 0 or -2),y+8,3,1,P.gold)
            end
        end
        if equipped[Catalog.ImprintRoles[i]]=='' then Rect(vg,x-1,y-1,3,3,P.edge) end
        Center(vg,role.name,x,y+(focused and 15 or 13),role.color)
        Hit(s,'orbit_'..i,x-16,y-12,32,30,function() s.focus(i) end)
    end
    Text(vg,('%s  Lv.%d/%d'):format(item.name,level,Catalog.LevelCap),24,180)
    Text(vg,(s.class=='time' and '法器' or Catalog.Tiers[tier])..' · 滑动观看',24,190,P.muted)
end
local function Detail(vg,s,progress,slot,equipped,list,item,tier,level)
    Text(vg,item.name,RX,40)
    Right(vg,('Lv.%d/%d'):format(level,Catalog.LevelCap),RX+RW,40,P.rank)
    for i=1,Catalog.LevelCap do Rect(vg,RX+(i-1)*10,49,8,3,i<=level and P.gold or P.line) end
    Right(vg,s.class=='time' and '法器' or Catalog.Tiers[tier],RX+RW,50,P.muted)
    Line(vg,57)
    Text(vg,'基础攻击',RX,66,P.muted)
    Right(vg,('%.1f'):format(item.attack*(1+(level-1)*.1)),RX+RW,66)
    Text(vg,'固有副词条',RX,78,P.muted)
    Right(vg,Benefit(item.sub,1),RX+RW,78,P.blue)
    Line(vg,86)
    local passive=PASSIVES[item.passive]
    Text(vg,'被动 · '..passive[1],RX,95,P.rank)
    Text(vg,passive[2],RX,106)
    Text(vg,SKILL[s.class],RX,117,P.muted)
    Line(vg,125)
    Text(vg,'时印加成',RX,133,P.muted)
    for i,role in ipairs(ROLES) do
        local y=144+(i-1)*11
        local seal=Catalog.Find(list,equipped[Catalog.ImprintRoles[i]])
        Rect(vg,RX,y-3,2,6,role.color)
        Text(vg,role.name,RX+5,y,role.color)
        if seal then
            local rank=slot.ranks[seal.id]
            Text(vg,seal.name,RX+21,y)
            Text(vg,ROMAN[rank],RX+60,y,P.rank)
            Right(vg,Benefit(seal,rank),RX+RW,y,role.color)
        else Text(vg,'空槽',RX+21,y,P.muted) end
        Hit(s,'bonus_'..i,RX,y-5,RW,10,function() s.focus(i) end)
    end
    local available=level<Catalog.LevelCap and progress.ore>=level
    local label=level>=Catalog.LevelCap and '已满级' or ('升级 Lv.%d · %d 矿'):format(level+1,level)
    Button(vg,s,'level',RX,177,RW,16,label,available,function() s.edit(s.class,'level',item.id) end,not available)
end
local function SealList(vg,s,slot,equipped,list)
    local role=ROLES[s.focusIndex]
    local roleKey=Catalog.ImprintRoles[s.focusIndex]
    local eq=equipped[roleKey]
    for i,option in ipairs(ROLES) do
        Button(vg,s,'role_'..i,RX+(i-1)*46,35,44,14,option.name,s.focusIndex==i,function() s.focus(i) end,false,option.color)
    end
    Line(vg,53)
    Rect(vg,RX,58,2,6,role.color)
    Text(vg,role.name..' · '..role.hint,RX+5,61,role.color)
    local index=0
    for _,seal in ipairs(list) do
        if seal.role==roleKey then
            local y=72+index*28
            local active=seal.id==eq
            local rank=slot.ranks[seal.id]
            local owned=(slot.counts[seal.id] or 0)>0
            local fill=active and P.green or P.paper
            Rect(vg,RX,y,RW,24,active and fill or P.edge)
            Rect(vg,RX+1,y+1,RW-2,22,fill)
            Icon(vg,seal.id,RX+3,y+2)
            Text(vg,seal.name,RX+25,y+7,active and P.light or P.ink)
            Text(vg,ROMAN[rank],RX+65,y+7,active and P.gold or P.rank)
            Right(vg,active and '已装' or owned and '点击装配' or '未获得',RX+RW-5,y+7,active and P.gold or P.muted)
            Text(vg,Benefit(seal,rank),RX+25,y+17,active and P.paperDeep or role.color)
            if owned and not active then Hit(s,'seal_'..seal.id,RX,y,RW,24,function() s.edit(s.class,'imprint',seal.id) end) end
            index=index+1
        end
    end
    Line(vg,165)
    local selected=Catalog.Find(list,eq)
    Button(vg,s,'enhance',RX,173,RW,16,selected and '强化 '..selected.name..' →' or '请先装配时印',selected~=nil,
        function() s.sub=true;s.fodder=nil;s.notice=nil end,not selected)
end
local function Materials(progress,target)
    local materials={}
    for _,class in ipairs(Catalog.Classes) do
        local slot=progress.slots[class]
        for _,seal in ipairs(Catalog.Imprints[class]) do
            local count=Store.FodderCount(slot,seal.id,target)
            if count>0 then materials[#materials+1]={seal=seal,class=class,count=count,rank=slot.ranks[seal.id]} end
        end
    end
    return materials
end
local FILTERS={{'all','全部'},{'sword','剑印'},{'bow','矢印'},{'time','法印'}}
local function Drawer(vg,s,materials)
    Text(vg,'挑选要消耗的闲置时印',RX,102)
    Button(vg,s,'hide_drawer',RX+RW-38,96,38,12,'收起',false,function() s.drawer=false end)
    for i,filter in ipairs(FILTERS) do
        Button(vg,s,'filter_'..filter[1],RX+(i-1)*34,111,32,12,filter[2],s.filter==filter[1],function()
            s.filter,s.scroll=filter[1],0
        end)
    end
    local filtered={}
    for _,mat in ipairs(materials) do if s.filter=='all' or s.filter==mat.class then filtered[#filtered+1]=mat end end
    local maxScroll=math.max(0,#filtered-3)
    s.scroll=math.min(maxScroll,s.scroll)
    if #filtered==0 then Text(vg,'当前筛选下没有闲置时印',RX,140,P.muted) end
    for i=s.scroll+1,math.min(#filtered,s.scroll+3) do
        local mat=filtered[i]
        local y=125+(i-s.scroll-1)*23
        local selected=s.fodder==mat.seal.id
        local fill=selected and P.green or P.paper
        Rect(vg,RX,y,RW-12,22,selected and fill or P.edge)
        Rect(vg,RX+1,y+1,RW-14,20,fill)
        Icon(vg,mat.seal.id,RX+2,y+1)
        Text(vg,mat.seal.name,RX+24,y+7,selected and P.light or P.ink)
        Text(vg,Benefit(mat.seal,mat.rank),RX+24,y+16,selected and P.paperDeep or P.blue)
        Right(vg,'×'..mat.count,RX+RW-16,y+11,selected and P.gold or P.muted)
        Hit(s,'material_'..mat.seal.id,RX,y,RW-12,22,function() s.fodder,s.drawer=mat.seal.id,false end)
    end
    Button(vg,s,'up',RX+RW-10,125,10,32,'▲',false,function() s.scroll=s.scroll-1 end,s.scroll==0)
    Button(vg,s,'down',RX+RW-10,160,10,32,'▼',false,function() s.scroll=s.scroll+1 end,s.scroll>=maxScroll)
end
local function Enhance(vg,s,progress,slot,equipped,list)
    local i=s.focusIndex
    local seal=Catalog.Find(list,equipped[Catalog.ImprintRoles[i]])
    if not seal then return SealList(vg,s,slot,equipped,list) end
    Button(vg,s,'imprint_back',RX,35,52,13,'← 返回时印',false,s.back)
    Right(vg,ROLES[i].name..'强化',RX+RW,41,ROLES[i].color)
    Line(vg,52)
    local rank=slot.ranks[seal.id]
    Icon(vg,seal.id,RX-1,54)
    Text(vg,seal.name..' · '..ROMAN[rank]..' 阶',RX+20,60)
    if rank==3 then
        Text(vg,Benefit(seal,rank)..'（已满阶）',RX+20,71,P.green)
        Button(vg,s,'refine',RX,168,RW,16,'已达最高 III 阶',false,nil,true)
        return
    end
    Text(vg,Benefit(seal,rank)..(' → +%d%%'):format(Round(seal.bonus*(rank+1)*100)),RX+20,71,P.green)
    local chance=Store.RefineChance(slot,seal.id)
    Text(vg,'阶位 '..ROMAN[rank]..' → '..ROMAN[rank+1],RX,85,P.muted)
    Right(vg,('成功率 %d%%'):format(chance),RX+RW,85,P.blue)
    Line(vg,94)
    local materials=Materials(progress,seal.id)
    if s.drawer then return Drawer(vg,s,materials) end
    local selected,total=nil,0
    for _,mat in ipairs(materials) do
        if mat.seal.id==s.fodder then selected=mat end
        total=total+mat.count
    end
    Text(vg,'消耗 1 枚闲置时印',RX,102,P.muted)
    Right(vg,'共余 '..total..' 枚',RX+RW,102,total>0 and P.ink or P.red)
    Rect(vg,RX,112,RW,26,P.edge)
    Rect(vg,RX+1,113,RW-2,24,P.paper)
    if selected then
        Icon(vg,selected.seal.id,RX+3,115)
        Text(vg,selected.seal.name..'  ×'..selected.count,RX+24,121)
        Text(vg,Benefit(selected.seal,selected.rank),RX+24,131,P.blue)
    else
        Text(vg,total>0 and '请选择一枚材料' or '暂无闲置时印',RX+6,125,total>0 and P.muted or P.red)
    end
    Button(vg,s,'show_drawer',RX+RW-42,118,38,14,selected and '更换 ▾' or '挑选 ▾',false,function() s.drawer,s.filter,s.scroll=true,'all',0 end)
    local can=selected~=nil and progress.sand>=1
    local label=progress.sand<1 and '淬炼砂不足 · 需要 1 枚' or ('强化 · 1 砂 + 1 时印 (%d%%)'):format(chance)
    Button(vg,s,'refine',RX,152,RW,16,label,can,function() s.edit(s.class,'refine',seal.id,s.fodder) end,not can)
end

local function Forge(vg,s,progress,item)
    Text(vg,'选择锻造图纸',RX,37,P.muted)
    for i,pattern in ipairs(s.blueprints) do
        local x,y=RX+((i-1)%2)*70,46+((i-1)//2)*16
        Button(vg,s,'pattern_'..pattern.id,x,y,66,14,pattern.name,pattern.id==item.id,function() s.choosePattern(i) end)
    end
    Line(vg,81)
    Text(vg,'锻造方式',RX,89,P.muted)
    Button(vg,s,'smelt',RX,97,66,14,'熔铸继承',s.method=='smelt',function() s.method,s.confirm='smelt',nil end)
    Button(vg,s,'craft',RX+70,97,66,14,'新造 Lv.1',s.method=='craft',function() s.method,s.confirm='craft',nil end)
    Line(vg,116)
    local class=s.blueprints[s.pattern].class
    local quote,reason=Store.ForgeQuote(progress,class,s.method,item.id)
    if not quote then Text(vg,reason,RX,133,P.muted);return end
    if s.method=='smelt' then
        Text(vg,'消耗 '..quote.source.name..' · 继承等级',RX,126)
        Text(vg,('继承 Lv.%d · %s'):format(quote.level,item.name),RX,138,P.green)
    else
        Text(vg,'保留原武器 · 新造 Lv.1',RX,126)
        Text(vg,item.name,RX,138,P.blue)
    end
    Text(vg,('所需材料　强化矿 ×%d'):format(quote.cost),RX,154,P.muted)
    local available=progress.ore>=quote.cost
    local label=s.confirm and '确认熔铸 · 消耗 '..quote.source.name or ('锻造 %s · %d 矿'):format(item.name,quote.cost)
    Button(vg,s,'forge_confirm',RX,173,RW,16,label,available,function()
        if s.method=='smelt' and not s.confirm then s.confirm=true;return end
        s.edit(class,s.method,item.id,quote.source and quote.source.id)
        s.confirm=nil
    end,not available)
end

function M.Draw(vg,s)
    s.buttons={}
    local progress,slot,equipped,list=Equipment(s)
    Header(vg,s,progress)
    if s.mode=='forge' then
        local pattern=s.blueprints[s.pattern]
        Stage(vg,s,pattern,nil,nil,equipped)
        Forge(vg,s,progress,pattern)
    else
        local item,tier=Catalog.Find(Catalog.Weapons[s.class],slot.weapon)
        local level=slot.levels[item.id]
        Stage(vg,s,item,tier,level,equipped)
        if s.tab=='detail' then Detail(vg,s,progress,slot,equipped,list,item,tier,level)
        elseif s.sub then Enhance(vg,s,progress,slot,equipped,list)
        else SealList(vg,s,slot,equipped,list) end
    end
    if s.notice then Text(vg,s.notice,RX,198,P.red) end
end
return M
