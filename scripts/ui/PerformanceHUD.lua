local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Settings=require('ruins.GameSettings')
local M={}
-- Forge owns the visibility signal; the global survives module-cache key differences.
local forgeHiddenLogged=false
local forgeRead
function M.SetForgeVisibility(reader) forgeRead=reader end
local function ForgeHidden()
    local forge=package.loaded['ui.ForgePanel']
    local hidden=rawget(_G,'FORGE_HUD_HIDDEN')==true
        or (forgeRead and forgeRead()==true)
        or (type(forge)=='table' and forge.HudHidden and forge.HudHidden()==true)
    if hidden then
        if not forgeHiddenLogged then print('HUD: hidden by forge (layer=PerformanceHUD)');forgeHiddenLogged=true end
    elseif not (type(forge)=='table' and forge.IsOpen and forge.IsOpen()) then forgeHiddenLogged=false end
    return hidden
end
---@type Widget?
local parent
---@type Widget?
local layer
---@type Node?
local node
---@type LuaScriptObject?
local receiver
---@type fun()?
local disconnect
local elapsed,frames=0,0
local text='FPS -- · -- ms'
local Layer=UI.Panel:Extend('RuinsPerformanceHUD')
function Layer:Render(vg)
    if ForgeHidden() then return end
    local w,_,safe=Draw.Metrics()
    Draw.Begin(vg,true)
    Draw.Rect(vg,w-safe.right-196,safe.top+94,176,24,Draw.colors.ink,.85)
    Draw.Text(vg,text,w-safe.right-188,safe.top+106,12,Draw.colors.paper)
    Draw.Finish(vg)
end
local function Disable()
    if receiver then receiver:UnsubscribeFromAllEvents() end
    if node then node:Remove() end
    if layer and parent then parent:RemoveChild(layer) end
    receiver,node,layer=nil,nil,nil
end
local function Sync()
    if not Settings.Get('perfHud') then Disable(); return end
    if layer or not parent then return end
    elapsed,frames=0,0
    layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}
    parent:AddChild(layer)
    node=Node(); receiver=node:CreateScriptObject('LuaScriptObject')
    receiver:SubscribeToEvent('Update',function(_,_,data)
        elapsed,frames=elapsed+data:GetFloat('TimeStep'),frames+1
        if elapsed>=.5 then
            text=string.format('FPS %.0f · %.1f ms',frames/elapsed,elapsed*1000/frames)
            elapsed,frames=0,0
        end
    end)
end
function M.Attach(root)
    Disable(); parent=root
    if not disconnect then disconnect=Settings.OnChange(function(key) if key=='perfHud' then Sync() end end) end
    Sync()
end
function M.Stop()
    Disable(); parent=nil
    if disconnect then disconnect(); disconnect=nil end
end
return M
