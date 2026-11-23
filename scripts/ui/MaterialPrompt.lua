local UI = require('urhox-libs/UI')
local Draw = require('ui.PixelDraw')
local Touch = require('ui.TouchInput')
local M = {}

local active, item, caption, point, action
local bounds={x=0,y=0,w=0,h=0}
local C=Draw.colors

function M.Clear()
    active,item,caption,point,action=nil,nil,nil,nil,nil
end

function M.Set(candidate,material,verb,anchor,camera,cameraNode)
    if not active or active.id~=candidate.id then
        item=material
        caption=('%s ×%d'):format(material.name,candidate.count)
    end
    active,action=candidate,verb
    local delta=anchor-cameraNode.worldPosition
    point=delta:DotProduct(cameraNode.worldDirection)>.1 and camera:WorldToScreenPoint(anchor) or nil
end

local function Layout()
    local width,height,safe=Draw.Metrics()
    local touch=Touch.IsEnabled()
    local w=math.min(touch and 212 or 192,width-safe.left-safe.right-12)
    local h=touch and 48 or 32
    local left,right=safe.left+6,width-safe.right-6-w
    local top,bottom=safe.top+6,height-safe.bottom-6-h
    if touch then
        -- Keep the interaction chip clear of the movement and attack controls.
        left,right=math.max(left,width*.29),math.min(right,width*.71-w)
        if right<left then left,right=(width-w)*.5,(width-w)*.5 end
        top,bottom=math.max(top,height*.24),math.min(bottom,height*.63-h)
    end
    local x=point and point.x*width or width*.5
    local y=point and point.y*height-h-12 or height*.57-h
    bounds.x=Draw.Snap(math.max(left,math.min(right,x-w*.5)))
    bounds.y=Draw.Snap(math.max(top,math.min(bottom,y)))
    bounds.w,bounds.h=w,h
    return bounds
end

function M.Hit(x,y)
    if not active or not Touch.IsEnabled() then return nil end
    local b=Layout()
    if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then return active end
end

local Layer=UI.Panel:Extend('RuinsMaterialPrompt')
function Layer:Render(vg)
    if not active or not self.available() then return end
    local b=Layout()
    local x,y,w,h=b.x,b.y,b.w,b.h
    if w<116 then return end
    Draw.Begin(vg,true)
    Draw.Rect(vg,x+2,y+3,w,h,C.deep,.74)
    Draw.Rect(vg,x,y,w,h,C.gold,.95)
    Draw.Rect(vg,x+1,y+1,w-2,h-2,C.ink,.98)
    Draw.Rect(vg,x+6,y+(h-22)/2,22,22,C.deep)
    Draw.ImagePixels(vg,item.icon,x+7,y+(h-20)/2)
    Draw.Text(vg,caption,x+34,y+h*.5,12,C.white)
    local label=Touch.IsEnabled() and action or 'F '..action
    Draw.Text(vg,label,x+w-8,y+h*.5,12,C.bright,NVG_ALIGN_RIGHT)
    Draw.Finish(vg)
end

function M.Attach(root,available)
    M.Clear()
    local layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}
    layer.available=available
    root:AddChild(layer)
end

return M
