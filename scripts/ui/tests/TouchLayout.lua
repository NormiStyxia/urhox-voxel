-- Explicit UI-only fixture. This verifies pixel rendering/layout, not gameplay.
local HUD=require('ruins.RuinsHUD')
local Controls=require('ui.TouchControls')
local Input=require('ui.TouchInput')
local state={cool={},cooldown={shatter=1,freeze=5,rewind=3},canMount=true}
TOUCH_LAYOUT=state
local scene
function Start()
    scene=Scene()
    scene:CreateComponent('Octree')
    local camera=scene:CreateChild('Camera'):CreateComponent('Camera')
    renderer:SetViewport(0,Viewport:new(scene,camera))
    HUD.Build({{id='shatter',cooldown=1},{id='freeze',cooldown=5},{id='rewind',cooldown=3}})
    HUD.SetObjective('打通被封的城门','南门被碎石堵住了。准星对准碎石，按左键施放「碎时」把它打碎。')
    HUD.SetClock('黄昏 17:40')
    HUD.SetTarget('封门碎石',{})
    if not Input.IsEnabled() then Input.Toggle() end
    Controls.Attach(HUD.root,function()return state end)
    SubscribeToEvent('Update','TouchLayout_Update')
end
function TouchLayout_Update(_,data)
    Controls.Update(data:GetFloat('TimeStep'))
end
function Stop() Controls.Stop();HUD.Stop();UnsubscribeFromEvent('Update') end
