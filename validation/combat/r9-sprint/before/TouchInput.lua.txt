-- Virtual input shared by the ruins and dragon controllers. Touch ownership lives
-- in TouchControls; this module never synthesizes mouse/keyboard events.
local M = { enabled = false, revision = 0 }
local held, pressed = {}, {}
local forward, right, lookX, lookY = 0, 0, 0, 0
local detected, override = false, nil

function M.IsEnabled() return M.enabled end
function M.Clear()
    held, pressed = {}, {}
    forward, right, lookX, lookY = 0, 0, 0, 0
    M.revision = M.revision + 1
end
function M.SetEnabled(on)
    if M.enabled == on then return end
    M.Clear()
    M.enabled = on
end
function M.Detect()
    local platform = GetPlatform()
    detected = detected or platform == 'Android' or platform == 'iOS'
    M.SetEnabled(override == nil and detected or override == true)
end
function M.OnTouch()
    local platform = GetPlatform()
    if platform == 'Web' or platform == 'HTML5' or platform == 'Emscripten' or platform == 'Android' or platform == 'iOS' then
        detected = true
    end
    M.Detect()
end
function M.Toggle() override = not M.enabled; M.SetEnabled(override) end
---@param name string
---@param down boolean
function M.Set(name, down)
    if down and not held[name] then pressed[name] = true end
    held[name] = down or nil
end
---@param name string
function M.Down(name) return M.enabled and held[name] == true end
---@param name string
function M.Press(name)
    if not M.enabled or not pressed[name] then return false end
    pressed[name] = nil
    return true
end
function M.CancelAction(name) held[name],pressed[name]=nil,nil end
-- Mode changes cancel every action edge while preserving joystick/look ownership.
function M.CancelActions()
    held,pressed={},{}
    M.revision=M.revision+1
end
function M.EndFrame() for key in pairs(pressed) do pressed[key]=nil end end
function M.SetMove(f, r) forward, right = f, r end
function M.MoveAxis()
    if not M.enabled then return 0, 0 end
    return forward, right
end
function M.AddLook(x, y) lookX, lookY = lookX + x, lookY + y end
function M.ConsumeLook()
    local x, y = lookX, lookY
    lookX, lookY = 0, 0
    return x, y
end
local function Actions(key)
    if key == KEY_SPACE then return 'jump', 'ascend' end
    if key == KEY_SHIFT then return 'sprint', 'dash' end
    if key == KEY_F then return 'mount', 'dismount' end
    if key == KEY_E then return 'freeze' end
    if key == KEY_Q then return 'rewind' end
    if key == KEY_C then return 'descend' end
    if key == KEY_G then return 'glide' end
    if key == KEY_L then return 'land' end
    if key == KEY_B then return 'breathSpecial' end
    if key == KEY_TAB then return 'farview' end
    if key == KEY_T then return 'fastTime' end
end
function M.KeyDown(key)
    local a, b = Actions(key)
    return (a ~= nil and M.Down(a)) or (b ~= nil and M.Down(b))
end
function M.KeyPress(key)
    local a, b = Actions(key)
    return (a ~= nil and M.Press(a)) or (b ~= nil and M.Press(b))
end
return M
