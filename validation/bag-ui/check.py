"""BagPanel + SettingsMenu verification and offline pixel PNG renderer."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

OUT_DIR = Path(".tmp/bag-ui")
OUT_DIR.mkdir(parents=True, exist_ok=True)

lua = LuaRuntime(unpack_returned_tuples=True)
for p in Path("scripts").rglob("*.lua"):
    lua.execute("assert(load(...))", p.read_text())
print("Lua 5.4 syntax: all scripts PASS")

def from_lua(value):
    if hasattr(value, "items"):
        return {k: from_lua(v) for k, v in value.items()}
    return value

def into_lua(value):
    if isinstance(value, dict):
        return lua.table_from({k: into_lua(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([into_lua(v) for v in value])
    return value

lua.globals().encode = lambda v: json.dumps(from_lua(v))
lua.globals().decode = lambda v: into_lua(json.loads(v))

class Canvas:
    def __init__(self, width, height, dpr=1, zoom=1):
        self.w = width
        self.h = height
        self.dpr = dpr
        self.zoom = zoom
        self.img = Image.new("RGBA", (width * dpr, height * dpr), (28, 38, 48, 255))
        self.draw = ImageDraw.Draw(self.img)
        self.stack = []
        self.tx = 0.0
        self.ty = 0.0
        self.sx = 1.0
        self.sy = 1.0
        self.scissor = None
        self.font_cache = {}
        self.asset_cache = {}

    def load_asset(self, rel_path):
        if rel_path in self.asset_cache:
            return self.asset_cache[rel_path]
        p = Path("assets") / rel_path
        if p.exists():
            im = Image.open(p).convert("RGBA")
            self.asset_cache[rel_path] = im
            return im
        self.asset_cache[rel_path] = None
        return None

    def get_font(self, size_px):
        sz = max(6, int(round(size_px)))
        if sz not in self.font_cache:
            self.font_cache[sz] = ImageFont.truetype("assets/Fonts/ArkPixel-12px-zh_hans.ttf", sz)
        return self.font_cache[sz]

    def push(self):
        self.stack.append((self.tx, self.ty, self.sx, self.sy, self.scissor))

    def pop(self):
        self.tx, self.ty, self.sx, self.sy, self.scissor = self.stack.pop()

    def translate(self, dx, dy):
        self.tx += dx * self.sx
        self.ty += dy * self.sy

    def scale(self, kx, ky):
        self.sx *= kx
        self.sy *= ky

    def intersect_scissor(self, x, y, w, h):
        x0, y0 = self.tx + x * self.sx, self.ty + y * self.sy
        x1, y1 = x0 + w * self.sx, y0 + h * self.sy
        if self.scissor is None:
            self.scissor = (x0, y0, x1, y1)
        else:
            sx0, sy0, sx1, sy1 = self.scissor
            self.scissor = (max(sx0, x0), max(sy0, y0), min(sx1, x1), min(sy1, y1))

    def clip_box(self, x0, y0, x1, y1):
        if self.scissor is not None:
            sx0, sy0, sx1, sy1 = self.scissor
            x0, y0, x1, y1 = max(x0, sx0), max(y0, sy0), min(x1, sx1), min(y1, sy1)
        return int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))

    def rect(self, x, y, w, h, color, alpha=1.0):
        x0, y0 = self.tx + x * self.sx, self.ty + y * self.sy
        cx0, cy0, cx1, cy1 = self.clip_box(x0, y0, x0 + w * self.sx, y0 + h * self.sy)
        if cx1 <= cx0 or cy1 <= cy0:
            return
        r, g, b = int(color[1]), int(color[2]), int(color[3])
        a = int(round((color[4] if 4 in color and color[4] is not None else 255) * alpha))
        if a >= 255:
            self.draw.rectangle([cx0, cy0, cx1 - 1, cy1 - 1], fill=(r, g, b, 255))
        else:
            overlay = Image.new("RGBA", (cx1 - cx0, cy1 - cy0), (r, g, b, a))
            self.img.alpha_composite(overlay, (cx0, cy0))

    def image_pixels(self, path, x, y, sx=0, sy=0, w=None, h=None):
        im = self.load_asset(path)
        if im is None:
            return False
        iw, ih = im.size
        sw, sh = int(w if w is not None else iw), int(h if h is not None else ih)
        sx, sy = int(sx or 0), int(sy or 0)
        crop = im.crop((sx, sy, min(iw, sx + sw), min(ih, sy + sh)))
        dx0, dy0 = self.tx + x * self.sx, self.ty + y * self.sy
        dx1, dy1 = self.tx + (x + sw) * self.sx, self.ty + (y + sh) * self.sy
        tw, th = max(1, int(round(dx1 - dx0))), max(1, int(round(dy1 - dy0)))
        resized = crop.resize((tw, th), Image.Resampling.NEAREST)
        ix0, iy0 = int(round(dx0)), int(round(dy0))
        if self.scissor is not None:
            sx0, sy0, sx1, sy1 = [int(round(v)) for v in self.scissor]
            cx0, cy0, cx1, cy1 = max(ix0, sx0), max(iy0, sy0), min(ix0 + tw, sx1), min(iy0 + th, sy1)
            if cx1 <= cx0 or cy1 <= cy0:
                return True
            resized = resized.crop((cx0 - ix0, cy0 - iy0, cx1 - ix0, cy1 - iy0))
            ix0, iy0 = cx0, cy0
        self.img.alpha_composite(resized, (ix0, iy0))
        return True

    def text(self, label, x, y, size, color, align=1):
        if not label:
            return
        font = self.get_font(max(6, size * self.sx))
        gx, gy = self.tx + x * self.sx, self.ty + y * self.sy
        bbox = self.draw.textbbox((0, 0), label, font=font)
        tw = bbox[2] - bbox[0]
        if align == 2:
            gx -= tw / 2
        elif align == 4:
            gx -= tw
        gy -= (bbox[1] + bbox[3]) / 2
        r, g, b = int(color[1]), int(color[2]), int(color[3])
        self.draw.text((int(round(gx)), int(round(gy))), label, font=font, fill=(r, g, b, 255))

    def text_width(self, text, size):
        if not text:
            return 0.0
        font = self.get_font(size * self.sx)
        bbox = self.draw.textbbox((0, 0), text, font=font)
        return (bbox[2] - bbox[0]) / max(1e-4, self.sx)

canvas_holder = {"c": None}

def make_canvas(w, h, dpr=1, zoom=1):
    canvas_holder["c"] = Canvas(w, h, dpr, zoom)
    return canvas_holder["c"]

def save_img(filename):
    p = OUT_DIR / filename
    canvas_holder["c"].img.save(p)
    print(f"Saved {p} ({canvas_holder['c'].img.size[0]}x{canvas_holder['c'].img.size[1]})")

lua.globals().py_make_canvas = make_canvas
lua.globals()._save_img = save_img
lua.globals().py_save = lambda: canvas_holder["c"].push()
lua.globals().py_restore = lambda: canvas_holder["c"].pop()
lua.globals().py_translate = lambda x, y: canvas_holder["c"].translate(x, y)
lua.globals().py_scale = lambda x, y: canvas_holder["c"].scale(x, y)
lua.globals().py_scissor = lambda x, y, w, h: canvas_holder["c"].intersect_scissor(x, y, w, h)
lua.globals().py_rect = lambda x, y, w, h, c, a: canvas_holder["c"].rect(x, y, w, h, c, a or 1.0)
lua.globals().py_image_pixels = lambda p, x, y, sx, sy, w, h: canvas_holder["c"].image_pixels(p, x, y, sx, sy, w, h)
lua.globals().py_text = lambda t, x, y, sz, c, al: canvas_holder["c"].text(t, x, y, sz, c, al or 1)
lua.globals().py_text_width = lambda t, sz: canvas_holder["c"].text_width(t, sz)

lua.execute(r'''
package.path = 'scripts/?.lua;scripts/?/init.lua;' .. package.path
local keys = {'W','A','S','D','SHIFT','SPACE','1','2','3','4','E','R','Q','F','T','TAB','C','B','G','L','ESCAPE','PAGEUP','PAGEDOWN','LEFT','RIGHT','UP','DOWN','RETURN'}
for i, k in ipairs(keys) do _G['KEY_' .. k] = i end
MOUSEB_LEFT, MOUSEB_RIGHT, MOUSEB_MIDDLE = 1, 2, 3
NVG_ALIGN_LEFT, NVG_ALIGN_CENTER, NVG_ALIGN_RIGHT = 1, 2, 4
platform = 'Windows'
GetPlatform = function() return platform end
nowTime = 10.0
GetTime = function() return { GetElapsedTime = function() return nowTime end, GetFrameNumber = function() return 1 end } end

screenW, screenH, dpr = 1280, 720, 1
safeInsets = { left = 0, right = 0, top = 0, bottom = 0 }
graphics = {
    GetWidth = function() return screenW * dpr end,
    GetHeight = function() return screenH * dpr end,
    GetDPR = function() return dpr end,
}
input = {
    focus = true, minimized = false, numTouches = 0,
    GetKeyDown = function() return false end,
    GetMouseButtonDown = function() return false end,
}
cjson = { encode = encode, decode = decode }
FILE_READ, FILE_WRITE = 0, 1
function File() return nil end
function Node()
    return {
        CreateScriptObject = function()
            return { SubscribeToEvent = function() end, UnsubscribeFromAllEvents = function() end }
        end,
        Remove = function() end,
    }
end

local UI = { Panel = {} }
function UI.Panel:Extend()
    local class = {}
    return setmetatable(class, { __call = function(c, props) return setmetatable({ props = props }, { __index = c }) end })
end
function UI.GetScale() return 1 end
function UI.GetSafeAreaInsets()
    local z = math.max(1, math.min(3, math.floor(math.min(screenW / 960, screenH / 540))))
    local factor = dpr * z
    return { left = safeInsets.left * factor, right = safeInsets.right * factor, top = safeInsets.top * factor, bottom = safeInsets.bottom * factor }
end
package.loaded['urhox-libs/UI'] = UI

local realDraw = require('ui.PixelDraw')
function realDraw.Begin(vg, screenSpace)
    realDraw.Save(vg)
    local k = graphics:GetDPR() * realDraw.Zoom() / UI.GetScale()
    py_scale(k, k)
end
function realDraw.Finish(vg) realDraw.Restore(vg) end
function realDraw.Save(vg) py_save() end
function realDraw.Restore(vg) py_restore() end
function nvgSave() py_save() end
function nvgRestore() py_restore() end
function nvgTranslate(vg, x, y) py_translate(x, y) end
function nvgScale(vg, x, y) py_scale(x, y) end
function nvgIntersectScissor(vg, x, y, w, h) py_scissor(x, y, w, h) end
function realDraw.Rect(vg, x, y, w, h, c, alpha) py_rect(x, y, w, h, c, alpha) end
function realDraw.ImagePixels(vg, path, x, y, sx, sy, w, h) return py_image_pixels(path, x, y, sx, sy, w, h) end
function realDraw.Text(vg, text, x, y, size, color, align) py_text(text, x, y, size, color, align) end
function realDraw.TextWidth(vg, text, size) return py_text_width(text, size) end

-- Use real combat.MaterialCatalog when present in tree; otherwise test exact contract.
local okRealMC = pcall(require, 'combat.MaterialCatalog')
if not okRealMC then
    package.loaded['combat.MaterialCatalog'] = {
        Items = {
            { id = 'ore', name = '强化矿', description = '用于武器升级与锻造的矿石。', icon = 'ui/forge/imprints/zhenshi_20.png' },
            { id = 'sand', name = '淬炼砂', description = '用于强化时印阶位的结晶砂。', icon = 'ui/forge/imprints/suzhou_20.png' },
            { id = 'timber', name = '古木枝', description = '遗迹古木上采集的坚韧枝干。', icon = 'ui/forge/imprints/baiyu_20.png' },
            { id = 'amber_resin', name = '金树脂', description = '凝固的金色古树树脂。', icon = 'ui/forge/imprints/xinghui_20.png' },
            { id = 'ruin_shard', name = '碑文石片', description = '带有刻痕的古碑残片。', icon = 'ui/forge/imprints/ruishi_20.png' },
            { id = 'chrono_dew', name = '时露晶滴', description = '晨曦凝结的纯净时之露水。', icon = 'ui/forge/imprints/ningshi_20.png' },
            { id = 'moss_stone', name = '青苔圆石', description = '覆满遗迹苔藓的致密石材。', icon = 'ui/forge/imprints/liedi_20.png' },
        },
        Count = function(progress, id)
            if id == 'ore' then return progress.ore or 0 end
            if id == 'sand' then return progress.sand or 0 end
            return (progress.materials and progress.materials[id]) or 0
        end,
    }
end

local Store = require('combat.WeaponStore')
local Catalog = require('combat.WeaponCatalog')
local Settings = require('ruins.GameSettings')
local Menu = require('ui.SettingsMenu')
local Bag = require('ui.BagPanel')

local root = { children = {} }
function root:AddChild(c) self.children[#self.children + 1] = c end
function root:RemoveChild(c)
    for i, v in ipairs(self.children) do if v == c then table.remove(self.children, i); return end end
end

local progress = Store.Default().progress
progress.ore, progress.sand = 14, 6
progress.materials = {}
local mc = require('combat.MaterialCatalog')
for i, item in ipairs(mc.Items) do
    if item.id ~= 'ore' and item.id ~= 'sand' then progress.materials[item.id] = i + 1 end
end
progress.slots.sword.levels.warden = 3
progress.slots.sword.levels.wing = 4
progress.slots.bow.levels.silver = 2
progress.slots.sword.counts.ruishi = 2
progress.slots.sword.counts.ningshi = 1
progress.slots.bow.counts.manxian = 1
progress.slots.time.counts.zhenbo = 2

local safeOpen = true
local equippedWeaponCalls, equippedImprintCalls = {}, {}
Settings.Load()
Menu.Attach(root, function() end, {
    available = function() return safeOpen end,
    unavailable = function() end,
    selection = function() return 'sword' end,
    progress = function() return progress end,
    equip = function(class, id)
        if not safeOpen then return false, '自定义警戒门禁：请脱离警戒后换装' end
        progress.slots[class].weapon = id
        equippedWeaponCalls[#equippedWeaponCalls + 1] = { class, id }
        return true, '自定义成功：已切换装备'
    end,
    equipImprint = function(class, id)
        if not safeOpen then return false, '自定义警戒门禁：请脱离警戒后装配' end
        local seal = Catalog.Find(Catalog.Imprints[class], id)
        progress.slots[class].imprints[seal.role] = id
        equippedImprintCalls[#equippedImprintCalls + 1] = { class, id }
        return true, '自定义成功：时印已共鸣'
    end,
})

assert(Menu.Open('bag'))
assert(Menu.IsOpen() and Menu.IsBagOpen() and Menu.IsBlocked())
nowTime = 11.0

local function render_to(w, h, ratio, sLeft, sRight, sTop, sBottom)
    screenW, screenH, dpr = w, h, ratio or 1
    safeInsets = { left = sLeft or 0, right = sRight or 0, top = sTop or 0, bottom = sBottom or 0 }
    py_make_canvas(w, h, dpr, realDraw.Zoom())
    root.children[1]:Render(1)
end

-- 1. Materials default filter is 'all'
render_to(1280, 720, 1)
assert(Bag.GetState().filterId == 'all')
_save_img('materials_p1_1280x720.png')

-- 2. Weapons equip preserves BOTH return values (true & false gates)
assert(Menu.Key(KEY_2, false))
assert(Menu.Key(KEY_DOWN, false)) -- wing
render_to(1280, 720, 1)
safeOpen = false
assert(Menu.Key(KEY_RETURN, false))
assert(Bag.GetState().noticeOk == false and Bag.GetState().notice == '自定义警戒门禁：请脱离警戒后换装', tostring(Bag.GetState().notice))
safeOpen = true
assert(Menu.Key(KEY_RETURN, false))
assert(Bag.GetState().noticeOk == true and Bag.GetState().notice == '自定义成功：已切换装备', tostring(Bag.GetState().notice))
assert(progress.slots.sword.weapon == 'wing' and #equippedWeaponCalls == 1)
render_to(1280, 720, 1)
_save_img('weapons_wing_1280x720.png')

-- 3. Imprints equip preserves BOTH return values
assert(Menu.Key(KEY_3, false))
render_to(1280, 720, 1)
local bs = Bag.GetState()
for _, item in ipairs(bs.items) do
    if item.id == 'ruishi' then bs.selectedKey = item.key; break end
end
render_to(1280, 720, 1)
assert(Menu.Key(KEY_RETURN, false))
assert(Bag.GetState().noticeOk == true and Bag.GetState().notice == '自定义成功：时印已共鸣', tostring(Bag.GetState().notice))
assert(progress.slots.sword.imprints.edge == 'ruishi' and #equippedImprintCalls == 1)
render_to(1280, 720, 1)
_save_img('imprints_p1_1280x720.png')

-- 4. Empty state check
local savedOre, savedSand, savedMats = progress.ore, progress.sand, progress.materials
progress.ore, progress.sand, progress.materials = 0, 0, {}
assert(Menu.Key(KEY_1, false))
render_to(1280, 720, 1)
assert(#Bag.GetState().items == 0)
_save_img('materials_empty_1280x720.png')
progress.ore, progress.sand, progress.materials = savedOre, savedSand, savedMats

-- 5. Audit touch sizes + zero hitbox overlap across ALL screens including 568x320 and 390x844
assert(Menu.Key(KEY_2, false))
local auditScreens = {
    { name = '1280x720_desktop', w = 1280, h = 720, dpr = 1, l = 0, r = 0, t = 0, b = 0 },
    { name = '844x390_iphone',   w = 844,  h = 390, dpr = 3, l = 47, r = 47, t = 0, b = 21 },
    { name = '720x360_narrow',   w = 720,  h = 360, dpr = 2, l = 24, r = 24, t = 0, b = 12 },
    { name = '568x320_small',    w = 568,  h = 320, dpr = 2, l = 24, r = 24, t = 0, b = 12 },
    { name = '390x844_portrait', w = 390,  h = 844, dpr = 3, l = 0, r = 0, t = 47, b = 34 },
}
_G._touch_audit = {}
for _, sc in ipairs(auditScreens) do
    render_to(sc.w, sc.h, sc.dpr, sc.l, sc.r, sc.t, sc.b)
    if sc.name == '568x320_small' then _save_img('bag_568x320_safe.png') end
    if sc.name == '844x390_iphone' then _save_img('bag_844x390_safe.png') end
    local ox, oy, scale = realDraw.ScrollMetrics()
    local btns = Bag.GetState().buttons
    local minW, minH = 9999, 9999
    for i, a in ipairs(btns) do
        local aw, ah = a.w * scale, a.h * scale
        local ax, ay = ox + a.x * scale, oy + a.y * scale
        assert(ax >= sc.l - 0.5 and ax + aw <= sc.w - sc.r + 0.5, sc.name .. ' x out of safe area: ' .. a.id)
        assert(ay >= sc.t - 0.5 and ay + ah <= sc.h - sc.b + 0.5, sc.name .. ' y out of safe area: ' .. a.id)
        assert(ah >= 28.0, string.format('%s button %s too short: %.1fdp', sc.name, a.id, ah))
        if aw < minW then minW = aw end
        if ah < minH then minH = ah end
        for j = i + 1, #btns do
            local b = btns[j]
            local overlapX = a.x < b.x + b.w and a.x + a.w > b.x
            local overlapY = a.y < b.y + b.h and a.y + a.h > b.y
            assert(not (overlapX and overlapY), string.format('%s hitbox overlap: %s vs %s', sc.name, a.id, b.id))
        end
    end
    _touch_audit[#_touch_audit + 1] = { name = sc.name, scale = scale, minW = minW, minH = minH, count = #btns }
end

print('BagPanel: return values, compact 568x320 >=28dp touch targets, zero overlap, safe-area PASS')
''')

for entry in lua.globals()._touch_audit.values():
    print(f"TOUCH AUDIT {entry['name']}: scale={entry['scale']:.4f}, minButton={entry['minW']:.1f}x{entry['minH']:.1f}dp, buttons={entry['count']}")
