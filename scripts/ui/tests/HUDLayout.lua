-- 独立像素 HUD 可视化入口，不运行玩法。默认显示截图中的最长任务；
-- HUDLayoutAcceptance 用于渲染时检查任务排版回归。
local HUD=require('ruins.RuinsHUD')
---@type Scene
local scene
local CASES={
    {'打通被封的城门','南门被碎石堵住了。准星对准碎石，按左键施放「碎时」把它打碎。'},
    {'修复断桥','古桥碎落在峡谷里。对准任意一块带金色符脉的桥体碎片，按 Q 施放「回溯」。'},
    {'取得时之钥','时之碑被封印了。西侧塔台顶上有「时之钥」：打碎悬石，趁碎块下落时按 E「冻结」，踩着碎块爬上塔台。'},
    {'复原四座时之碑','带着时之钥回到内环，对倒塌的时之碑按 Q 施放「回溯」。（4 / 4）'},
    {'遗迹看守者已苏醒','巨龙认可了你。走近它按 F 骑乘，Space 起飞。时之物件仍可以随意碎时 / 冻结 / 回溯。'},
    {'长任务标题 Long objective title 需要多行完整呈现','第一段 English LongUnbrokenIdentifier01234567890123456789\r\n\r\n第二段：按 E 冻结，踩着碎块爬上塔台。\n'},
    {'',''},
}
local M={cases=CASES}
_G['HUD_LAYOUT']=M
function M.Show(index)
    local c=CASES[index]
    HUD.SetObjective(c[1],c[2])
end
function Start()
    scene=Scene()
    scene:CreateComponent('Octree')
    local camera=scene:CreateChild('Camera'):CreateComponent('Camera')
    renderer:SetViewport(0,Viewport:new(scene,camera))
    HUD.Build({{id='shatter',cooldown=1},{id='freeze',cooldown=5},{id='rewind',cooldown=3}})
    M.Show(3)
    HUD.SetClock('白昼 16:00')
    HUD.SetTarget('')
    HUD.SetHint('')
    HUD.SetMessage('')
    HUD.SetCrossVisible(false)
end
function Stop() HUD.Stop() end
return M
