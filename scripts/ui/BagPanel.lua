-- Pixel-scroll backpack panel matching ForgeLayout / WorldMap (380 x 214 art grid).
-- Uses Draw.ScrollMetrics / Draw.ScrollPaper / Draw.ImagePixels (NEAREST) / ArkPixel-12px.
local Draw = require('ui.PixelDraw')
local Catalog = require('combat.WeaponCatalog')
local Preview = require('ui.ForgePreview')
local TouchInput = require('ui.TouchInput')

local M = { width = 380, height = 214 }

local P = {
    ink = {49, 62, 68}, muted = {86, 100, 98}, edge = {137, 151, 143},
    paper = {244, 241, 228}, paperDeep = {227, 224, 207}, light = {250, 244, 222},
    line = {183, 192, 180}, survey = {201, 208, 192}, green = {46, 82, 75},
    gold = {215, 177, 102}, red = {134, 69, 52}, blue = {38, 94, 153},
    rank = {158, 115, 36}, outline = {40, 48, 64}, steel = {196, 206, 218},
    wing = {78, 156, 242}, wood = {146, 98, 56}, thorn = {178, 108, 228},
}

local ROLES = {
    edge = { name = '锋位', color = {168, 58, 50}, hint = '强化进攻' },
    ['break'] = { name = '破位', color = P.blue, hint = '强化压制' },
    time = { name = '时位', color = {36, 110, 94}, hint = '同类武器共享' },
}
local CLASS_NAMES = { sword = '长剑', bow = '长弓', time = '法器' }
local ROMAN = { 'I', 'II', 'III' }
local PASSIVES = {
    stable = { '稳固', '连击第三段削韧 +20%' },
    guard = { '守门', '对失衡敌人伤害 +15%' },
    wind = { '逐风', '冲刺后首击伤害 +25%' },
    hunt = { '游猎', '对未察觉敌人伤害 +15%' },
    silver = { '银枝', '满蓄力射击削韧 +25%' },
    thorn = { '荆棘', '满蓄力射击伤害 +20%' },
    star = { '星砂', '碎时伤害 +20%' },
}
local STATS = {
    attack = '攻击', reach = '攻击范围', poise = '削韧',
    armorBreak = '破甲', move = '拉弓移速', terrainRadius = '破坏范围',
}

local COLS = 2
local GRID_X, CARD_W, COL_GAP = 20, 93, 4
local RX, RW = 220, 140

local function GetLayout(scale)
    if scale < 1.4 then
        -- Compact touch-safe layout for narrow/small screens (e.g. 568x320, 390x844):
        -- 2x2 grid (4/page) keeps every control >= 28dp without overlapping hitboxes.
        return {
            compact = true, rows = 2, pageSize = 4,
            tabY = 10, tabH = 28, tabPad = 0,
            frameT = 39, frameB = 197,
            filterY = 40, filterH = 28, filterPad = 0,
            gridY = 71, cardH = 42, rowGap = 4,
            pagerY = 163, pagerH = 30, pagerPad = 0,
            detailTop = 40,
        }
    end
    return {
        compact = false, rows = 3, pageSize = 6,
        tabY = 11, tabH = 18, tabPad = 1,
        frameT = 31, frameB = 195,
        filterY = 33, filterH = 18, filterPad = 1,
        gridY = 55, cardH = 34, rowGap = 3,
        pagerY = 168, pagerH = 22, pagerPad = 1,
        detailTop = 35,
    }
end

local function GetMaterialCatalog()
    local ok, mod = pcall(require, 'combat.MaterialCatalog')
    return ok and type(mod) == 'table' and mod or nil
end

local function Round(n) return math.floor(n + .5) end
local function Clamp(n, lo, hi) return math.min(hi, math.max(lo, n)) end
local function Rect(vg, x, y, w, h, color, alpha) Draw.Rect(vg, Round(x), Round(y), Round(w), Round(h), color, alpha) end
local function Text(vg, label, x, y, color, align, size) Draw.Text(vg, label, x, y, size or 6, color or P.ink, align) end
local function Right(vg, label, x, y, color, size) Text(vg, label, x, y, color, NVG_ALIGN_RIGHT, size) end
local function Center(vg, label, x, y, color, size) Text(vg, label, x, y, color, NVG_ALIGN_CENTER, size) end
local function Line(vg, x, y, w) Rect(vg, x, y, w, 1, P.line) end

local measureScratch = {}
local function MeasureTextWidth(vg, text, size)
    local w = Draw.TextWidth and Draw.TextWidth(vg, text, size, measureScratch) or 0
    if w > 0 then return w end
    local total = 0
    for _, code in utf8.codes(text or '') do total = total + (code < 128 and size * .55 or size) end
    return total
end

local function FitText(vg, text, maxWidth, size)
    text = tostring(text or '')
    if MeasureTextWidth(vg, text, size) <= maxWidth then return text end
    local ew = MeasureTextWidth(vg, '..', size)
    local out = ''
    for _, code in utf8.codes(text) do
        local candidate = out .. utf8.char(code)
        if MeasureTextWidth(vg, candidate, size) + ew > maxWidth then return out .. '..' end
        out = candidate
    end
    return out
end

local function WrapText(vg, text, maxWidth, size, maxLines)
    local lines = {}
    text = tostring(text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
    for rawLine in (text .. '\n'):gmatch('(.-)\n') do
        if rawLine == '' then
            if #lines < maxLines then lines[#lines + 1] = '' end
        else
            local cur = ''
            for _, code in utf8.codes(rawLine) do
                local ch = utf8.char(code)
                local nextText = cur .. ch
                if cur ~= '' and MeasureTextWidth(vg, nextText, size) > maxWidth then
                    lines[#lines + 1] = cur
                    if #lines >= maxLines then return lines end
                    cur = ch
                else
                    cur = nextText
                end
            end
            if cur ~= '' then
                lines[#lines + 1] = cur
                if #lines >= maxLines then return lines end
            end
        end
        if #lines >= maxLines then break end
    end
    return lines
end

local function Benefit(seal, rank)
    return (STATS[seal.stat] or seal.label) .. (' +%d%%'):format(Round(seal.bonus * rank * 100))
end

local function AddHit(s, id, x, y, w, h, action, pad)
    local p = pad or 0
    s.buttons[#s.buttons + 1] = { id = id, x = x - p, y = y - p, w = w + p * 2, h = h + p * 2, action = action }
end

local function Button(vg, s, id, x, y, w, h, label, active, action, disabled, color, pad)
    local fill = active and (color or P.green) or (disabled and P.paperDeep or P.paper)
    local border = active and fill or (disabled and P.paperDeep or P.edge)
    Rect(vg, x, y, w, h, border)
    Rect(vg, x + 1, y + 1, w - 2, h - 2, fill)
    local textColor = active and P.light or (disabled and P.edge or (color or P.ink))
    Center(vg, label, x + w * .5, y + h * .5, textColor, 6)
    if action and not disabled then AddHit(s, id, x, y, w, h, action, pad or 0) end
end

local function DrawWeaponSprite(vg, id, class, x, y)
    if class == 'sword' then
        local blade = id == 'wing' and P.wing or (id == 'warden' and P.muted or P.steel)
        local guard = id == 'iron' and P.edge or P.gold
        for i = 0, 9 do
            local px, py = x + 14 - i, y + 3 + i
            Rect(vg, px - 1, py - 1, 4, 4, P.outline)
        end
        for i = 0, 9 do
            local px, py = x + 14 - i, y + 3 + i
            Rect(vg, px, py, 2, 2, blade)
        end
        Rect(vg, x + 15, y + 2, 2, 2, P.light)
        Rect(vg, x + 3, y + 10, 7, 2, guard)
        Rect(vg, x + 7, y + 12, 2, 5, guard)
        if id == 'wing' then
            Rect(vg, x + 4, y + 9, 2, 2, P.gold); Rect(vg, x + 9, y + 14, 2, 2, P.gold)
        end
        Rect(vg, x + 3, y + 14, 3, 3, P.outline)
        Rect(vg, x + 4, y + 15, 1, 1, P.wood)
        Rect(vg, x + 2, y + 16, 2, 2, guard)
    elseif class == 'bow' then
        local limb = id == 'thorn' and P.thorn or (id == 'silver' and P.steel or P.wood)
        local str = id == 'thorn' and P.thorn or (id == 'silver' and P.blue or P.muted)
        Rect(vg, x + 4, y + 3, 2, 14, str)
        local pts = { {5,2},{7,3},{9,4},{11,6},{12,8},{12,10},{11,12},{9,14},{7,15},{5,16} }
        for _, pt in ipairs(pts) do Rect(vg, x + pt[1] - 1, y + pt[2] - 1, 4, 4, P.outline) end
        for _, pt in ipairs(pts) do Rect(vg, x + pt[1], y + pt[2], 2, 2, limb) end
        if id == 'thorn' then
            Rect(vg, x + 13, y + 6, 2, 2, P.gold); Rect(vg, x + 13, y + 12, 2, 2, P.gold)
        end
    else
        Rect(vg, x + 4, y + 2, 12, 16, P.outline)
        Rect(vg, x + 2, y + 4, 16, 12, P.outline)
        Rect(vg, x + 5, y + 3, 10, 14, P.blue)
        Rect(vg, x + 3, y + 5, 14, 10, P.blue)
        Rect(vg, x + 6, y + 5, 8, 10, P.paperDeep)
        Rect(vg, x + 7, y + 7, 6, 6, P.wing)
        Rect(vg, x + 8, y + 8, 4, 4, P.light)
        Rect(vg, x + 9, y + 2, 2, 2, P.gold); Rect(vg, x + 9, y + 16, 2, 2, P.gold)
    end
end

local function DrawItemIcon(vg, item, x, y, pad20, useDetail)
    local path = useDetail and item.detailIconPath or item.iconPath
    local offset = (not useDetail and item.kind ~= 'weapon' and pad20) and pad20 or 0
    if path and path ~= '' and Draw.ImagePixels(vg, path, x + offset, y + offset) then return end
    if item.kind == 'weapon' then
        DrawWeaponSprite(vg, item.id, item.class, x + (useDetail and 4 or 1), y + (useDetail and 4 or 1))
    elseif item.drawIcon then
        item.drawIcon(vg, x + offset, y + offset)
    else
        Rect(vg, x + offset + 4, y + offset + 4, 12, 12, P.outline)
        Rect(vg, x + offset + 5, y + offset + 5, 10, 10, item.roleColor or P.gold)
        Rect(vg, x + offset + 7, y + offset + 7, 4, 4, P.light)
    end
end

local categories = {}

local function CollectMaterials(progress)
    local out = {}
    local mc = GetMaterialCatalog()
    if not mc or type(mc.Items) ~= 'table' then return out end
    for _, item in ipairs(mc.Items) do
        local count = mc.Count and (mc.Count(progress, item.id) or 0)
            or (progress.materials and progress.materials[item.id]) or 0
        if count > 0 then
            out[#out + 1] = {
                key = 'mat:' .. tostring(item.id),
                kind = 'material',
                id = item.id,
                name = item.name or tostring(item.id),
                subtitle = item.subtitle or '材料',
                description = item.description or '',
                iconPath = item.icon or '',
                count = count,
                equipped = false,
                canAction = false,
                raw = item,
            }
        end
    end
    return out
end

local WEAPON_FILTERS = {
    { id = 'all', name = '全部' }, { id = 'sword', name = '长剑' },
    { id = 'bow', name = '长弓' }, { id = 'time', name = '法器' },
}

local function CollectWeapons(progress, filterId, bag)
    local out = {}
    for _, class in ipairs(Catalog.Classes) do
        if filterId == 'all' or filterId == class then
            local slot = progress.slots and progress.slots[class]
            if slot then
                for tier, item in ipairs(Catalog.Weapons[class]) do
                    local level = slot.levels and slot.levels[item.id]
                    if level then
                        local equipped = slot.weapon == item.id
                        local tierLabel = class == 'time' and '法器' or (Catalog.Tiers[tier] or '武器')
                        local passive = PASSIVES[item.passive]
                        local names = {}
                        for _, roleKey in ipairs(Catalog.ImprintRoles) do
                            local eqId = slot.imprints and slot.imprints[roleKey]
                            local seal = eqId and eqId ~= '' and Catalog.Find(Catalog.Imprints[class], eqId) or nil
                            names[#names + 1] = ROLES[roleKey].name .. ':' .. (seal and seal.name or '空')
                        end
                        local captureClass, captureId = class, item.id
                        out[#out + 1] = {
                            key = 'wpn:' .. class .. ':' .. item.id,
                            kind = 'weapon',
                            class = class,
                            id = item.id,
                            name = item.name,
                            level = level,
                            attack = item.attack * (1 + (level - 1) * .1),
                            subStat = item.sub and ((STATS[item.sub.stat] or item.sub.stat) .. (' +%d%%'):format(Round(item.sub.bonus * 100))) or '',
                            iconPath = 'ui/forge/weapons/' .. item.id .. '_22.png',
                            detailIconPath = 'ui/forge/weapons/' .. item.id .. '_28.png',
                            subtitle = ('%s · %s · Lv.%d/%d'):format(CLASS_NAMES[class], tierLabel, level, Catalog.LevelCap),
                            description = (passive and ('被动[' .. passive[1] .. '] ' .. passive[2]) or '') .. '\n时印：' .. table.concat(names, ' / '),
                            count = 1,
                            equipped = equipped,
                            canAction = not equipped and bag ~= nil and bag.equip ~= nil,
                            actionLabel = equipped and '当前已装备' or '装备武器',
                            action = function()
                                if bag and bag.equip then return bag.equip(captureClass, captureId) end
                                return false, '暂不可换装'
                            end,
                            raw = item,
                        }
                    end
                end
            end
        end
    end
    return out
end

local function CollectImprints(progress, filterId, bag)
    local out = {}
    for _, class in ipairs(Catalog.Classes) do
        if filterId == 'all' or filterId == class then
            local slot = progress.slots and progress.slots[class]
            if slot then
                for _, seal in ipairs(Catalog.Imprints[class]) do
                    local count = slot.counts and slot.counts[seal.id] or 0
                    if count > 0 then
                        local rank = slot.ranks and slot.ranks[seal.id] or 1
                        local equipped = slot.imprints and slot.imprints[seal.role] == seal.id
                        local idleCount = math.max(0, count - (equipped and 1 or 0))
                        local roleInfo = ROLES[seal.role]
                        local iconKey = Preview.Icon(seal.id) or seal.id
                        local captureClass, captureId = class, seal.id
                        out[#out + 1] = {
                            key = 'imp:' .. class .. ':' .. seal.id,
                            kind = 'imprint',
                            class = class,
                            id = seal.id,
                            name = seal.name,
                            rank = rank,
                            roleName = roleInfo.name,
                            roleColor = roleInfo.color,
                            benefit = Benefit(seal, rank),
                            iconPath = 'ui/forge/imprints/' .. iconKey .. '_20.png',
                            subtitle = ('%s · %s · %s阶'):format(CLASS_NAMES[class], roleInfo.name, ROMAN[rank] or 'I'),
                            description = ('%s（%s）\n当前加成：%s\n满阶加成：%s\n空闲可用：%d 枚')
                                :format(roleInfo.name, roleInfo.hint, Benefit(seal, rank), Benefit(seal, 3), idleCount),
                            count = count,
                            idleCount = idleCount,
                            equipped = equipped,
                            canAction = not equipped and bag ~= nil and bag.equipImprint ~= nil,
                            actionLabel = equipped and ('已装 · ' .. CLASS_NAMES[class])
                                or (bag and bag.equipImprint and ('装配 · ' .. CLASS_NAMES[class]) or '前往锻造台装配'),
                            action = function()
                                if bag and bag.equipImprint then return bag.equipImprint(captureClass, captureId) end
                                return false, '暂不可装配时印'
                            end,
                            raw = seal,
                        }
                    end
                end
            end
        end
    end
    return out
end

function M.RegisterCategory(def)
    assert(type(def) == 'table' and type(def.id) == 'string' and type(def.name) == 'string', 'invalid category')
    for i, existing in ipairs(categories) do
        if existing.id == def.id then categories[i] = def; return end
    end
    categories[#categories + 1] = def
end

M.Categories = categories
M.RegisterCategory({ id = 'materials', name = '材料',
    filters = function() return { { id = 'all', name = '全部' } } end,
    collect = CollectMaterials,
    emptyTitle = '暂无材料', emptyHint = '采集遗迹矿木或击败敌人后可在此查看材料。' })
M.RegisterCategory({ id = 'weapons', name = '武器', filters = function() return WEAPON_FILTERS end, collect = CollectWeapons,
    emptyTitle = '暂无此类武器', emptyHint = '可在锻造台打造新武器后在此切换装备。' })
M.RegisterCategory({ id = 'imprints', name = '石印', filters = function() return WEAPON_FILTERS end, collect = CollectImprints,
    emptyTitle = '暂无此类石印', emptyHint = '击败遗迹敌人获得石印后可在此查看并装配。' })

local state = {
    categoryIndex = 1, filterId = 'all', page = 1, focusPos = 1, pageSize = 6,
    selectedKey = nil, notice = nil, noticeOk = true, openedAt = nil,
    buttons = {}, items = {}, pages = 1, filters = {},
}

function M.Reset(initialCategory)
    state.categoryIndex = 1
    if initialCategory then
        for i, cat in ipairs(categories) do if cat.id == initialCategory then state.categoryIndex = i; break end end
    end
    state.filterId, state.page, state.focusPos = 'all', 1, 1
    state.selectedKey, state.notice, state.noticeOk = nil, nil, true
    state.openedAt = GetTime():GetElapsedTime() - .03
    state.buttons = {}
end

function M.OnClose() state.notice = nil; state.buttons = {} end
function M.GetState() return state end

local function CurrentCategory()
    if state.categoryIndex < 1 or state.categoryIndex > #categories then state.categoryIndex = 1 end
    return categories[state.categoryIndex]
end

local function SyncData(bag, pageSize)
    pageSize = pageSize or state.pageSize or 6
    state.pageSize = pageSize
    local cat = CurrentCategory()
    local filters = cat.filters and cat.filters() or { { id = 'all', name = '全部' } }
    local validFilter = false
    for _, f in ipairs(filters) do if f.id == state.filterId then validFilter = true; break end end
    if not validFilter then state.filterId = filters[1] and filters[1].id or 'all' end
    state.filters = filters

    local progress = (bag and bag.progress and bag.progress()) or { ore = 0, sand = 0, slots = {} }
    local items = cat.collect(progress, state.filterId, bag) or {}
    state.items = items

    local total = #items
    local pages = math.max(1, math.ceil(total / pageSize))
    state.pages = pages
    state.page = Clamp(state.page, 1, pages)

    if state.selectedKey then
        local foundIndex
        for idx, item in ipairs(items) do if item.key == state.selectedKey then foundIndex = idx; break end end
        if foundIndex then
            state.page = math.floor((foundIndex - 1) / pageSize) + 1
            state.focusPos = foundIndex - (state.page - 1) * pageSize
        else
            state.selectedKey = nil
        end
    end

    local startIdx = (state.page - 1) * pageSize + 1
    local endIdx = math.min(total, state.page * pageSize)
    local pageCount = math.max(0, endIdx - startIdx + 1)
    if pageCount == 0 then
        state.focusPos, state.selectedKey = 1, nil
    else
        state.focusPos = Clamp(state.focusPos, 1, pageCount)
        if not state.selectedKey then state.selectedKey = items[startIdx + state.focusPos - 1].key end
    end
    return cat, filters, items, startIdx, endIdx, (pageCount > 0 and items[startIdx + state.focusPos - 1] or nil)
end

local function SelectCategory(index)
    state.categoryIndex = Clamp(index, 1, #categories)
    state.filterId, state.page, state.focusPos, state.selectedKey, state.notice = 'all', 1, 1, nil, nil
end
local function SelectFilter(filterId)
    state.filterId, state.page, state.focusPos, state.selectedKey, state.notice = filterId, 1, 1, nil, nil
end
local function SelectPage(p)
    state.page, state.focusPos = Clamp(p, 1, state.pages), 1
    local idx = (state.page - 1) * (state.pageSize or 6) + 1
    state.selectedKey = state.items[idx] and state.items[idx].key or nil
end
local function ActivateSelected(bag)
    local _, _, _, startIdx, endIdx, item = SyncData(bag)
    if not item or startIdx > endIdx or not item.canAction or not item.action then return false end
    local ok, msg = item.action()
    state.noticeOk = ok == true
    state.notice = msg or (ok and '已装备' or '操作未完成')
    return ok
end

local function DrawEmptyState(vg, cat, L)
    local boxH = L.rows * L.cardH + (L.rows - 1) * L.rowGap
    Rect(vg, GRID_X + 2, L.gridY + 2, 186, boxH - 4, P.edge)
    Rect(vg, GRID_X + 3, L.gridY + 3, 184, boxH - 6, P.paper)
    local cx, cy = GRID_X + 95, L.gridY + math.floor(boxH * .38)
    Rect(vg, GRID_X + 12, cy, 166, 1, P.survey)
    Rect(vg, cx, L.gridY + 10, 1, boxH - 20, P.survey)
    Rect(vg, cx - 10, cy - 8, 20, 16, P.edge)
    Rect(vg, cx - 9, cy - 7, 18, 14, P.paperDeep)
    Rect(vg, cx - 6, cy - 4, 12, 2, P.muted)
    Rect(vg, cx - 2, cy - 4, 4, 4, P.gold)
    Center(vg, cat.emptyTitle or '暂无物品', cx, cy + 24, P.ink, 6)
    for i, line in ipairs(WrapText(vg, cat.emptyHint or '探索遗迹后可在此查看。', 164, 5, 2)) do
        Center(vg, line, cx, cy + 36 + (i - 1) * 9, P.muted, 5)
    end
end

local function DrawCard(vg, item, x, y, h, selected)
    Rect(vg, x, y, CARD_W, h, selected and P.ink or (item.equipped and P.green or P.edge))
    Rect(vg, x + 1, y + 1, CARD_W - 2, h - 2, selected and P.light or P.paper)
    if selected then
        Rect(vg, x + 1, y + 1, CARD_W - 2, 1, P.gold)
        Rect(vg, x + 1, y + h - 2, CARD_W - 2, 1, P.gold)
        Rect(vg, x, y, 3, 2, P.gold); Rect(vg, x + CARD_W - 3, y, 3, 2, P.gold)
        Rect(vg, x, y + h - 2, 3, 2, P.gold); Rect(vg, x + CARD_W - 3, y + h - 2, 3, 2, P.gold)
    elseif item.equipped then
        Rect(vg, x + 1, y + 1, 2, h - 2, P.green)
    end
    local iconY = y + math.floor((h - 22) * .5)
    Rect(vg, x + 4, iconY - 1, 24, 24, P.line)
    Rect(vg, x + 5, iconY, 22, 22, P.paperDeep)
    DrawItemIcon(vg, item, x + 5, iconY, 1, false)
    local textX, textRight = x + 31, x + CARD_W - 4
    local y1 = y + math.floor(h * .34)
    local y2 = y + math.floor(h * .71)
    Text(vg, FitText(vg, item.name, textRight - textX, 6), textX, y1, P.ink, NVG_ALIGN_LEFT, 6)
    if item.kind == 'material' then
        Text(vg, '×' .. tostring(item.count), textX, y2, P.blue, NVG_ALIGN_LEFT, 6)
    elseif item.kind == 'weapon' then
        Text(vg, ('Lv.%d/%d'):format(item.level or 1, Catalog.LevelCap), textX, y2, P.rank, NVG_ALIGN_LEFT, 5)
        Right(vg, item.equipped and '已装' or '背包', textRight, y2, item.equipped and P.green or P.muted, 5)
    elseif item.kind == 'imprint' then
        Text(vg, (item.roleName or '') .. ' ' .. (ROMAN[item.rank or 1] or 'I'), textX, y2, item.roleColor or P.blue, NVG_ALIGN_LEFT, 5)
        Right(vg, item.equipped and '已装' or ('×' .. tostring(item.count)), textRight, y2, item.equipped and P.green or P.muted, 5)
    else
        Text(vg, '×' .. tostring(item.count or 1), textX, y2, P.blue, NVG_ALIGN_LEFT, 5)
    end
end

local function DrawDetail(vg, s, item, bag, L)
    if not item then
        Center(vg, '未选中物品', RX + RW * .5, 88, P.muted, 6)
        for i, line in ipairs(WrapText(vg, '在左侧选择分类或翻页查看已收集的材料、武器与石印。', RW - 8, 5, 4)) do
            Center(vg, line, RX + RW * .5, 106 + (i - 1) * 10, P.muted, 5)
        end
        return
    end
    local top = L.detailTop
    local boxSize = item.detailIconPath and 32 or 26
    Rect(vg, RX, top, boxSize, boxSize, P.edge); Rect(vg, RX + 1, top + 1, boxSize - 2, boxSize - 2, P.paper)
    DrawItemIcon(vg, item, RX + (item.detailIconPath and 2 or 3), top + (item.detailIconPath and 2 or 3), 0, true)
    Text(vg, FitText(vg, item.name, RW - boxSize - 6, 6), RX + boxSize + 4, top + (item.detailIconPath and 9 or 7), P.ink, NVG_ALIGN_LEFT, 6)
    Text(vg, FitText(vg, item.subtitle or '', RW - boxSize - 6, 5), RX + boxSize + 4, top + (item.detailIconPath and 22 or 19), item.roleColor or P.muted, NVG_ALIGN_LEFT, 5)
    local lineY = top + boxSize + 4
    Line(vg, RX, lineY, RW)
    local row1 = lineY + 9
    local row2 = lineY + 21
    if item.kind == 'material' then
        Text(vg, '持有数量', RX, row1, P.muted); Right(vg, '×' .. tostring(item.count), RX + RW, row1, P.blue)
        Line(vg, RX, lineY + 18, RW)
        local maxLines = L.compact and 5 or 7
        for i, line in ipairs(WrapText(vg, item.description, RW, 6, maxLines)) do
            Text(vg, line, RX, lineY + 28 + (i - 1) * 11, P.ink)
        end
        return
    elseif item.kind == 'weapon' then
        Text(vg, '基础攻击', RX, row1, P.muted); Right(vg, ('%.1f'):format(item.attack or 0), RX + RW, row1, P.ink)
        Text(vg, '固有词条', RX, row2, P.muted, NVG_ALIGN_LEFT, 5); Right(vg, item.subStat or '-', RX + RW, row2, P.blue, 5)
        Line(vg, RX, lineY + 28, RW)
        local maxLines = L.compact and 4 or 5
        for i, line in ipairs(WrapText(vg, item.description, RW, 5, maxLines)) do
            Text(vg, line, RX, lineY + 37 + (i - 1) * 10, i == 1 and P.rank or P.ink, NVG_ALIGN_LEFT, 5)
        end
    elseif item.kind == 'imprint' then
        Text(vg, '持有数量', RX, row1, P.muted)
        Right(vg, ('×%d（闲置 %d）'):format(item.count, item.idleCount or 0), RX + RW, row1, P.blue, 5)
        Text(vg, '词条加成', RX, row2, P.muted, NVG_ALIGN_LEFT, 5)
        Right(vg, item.benefit or '-', RX + RW, row2, item.roleColor or P.green, 5)
        Line(vg, RX, lineY + 28, RW)
        local maxLines = L.compact and 4 or 5
        for i, line in ipairs(WrapText(vg, item.description, RW, 5, maxLines)) do
            Text(vg, line, RX, lineY + 37 + (i - 1) * 10, P.ink, NVG_ALIGN_LEFT, 5)
        end
    end
    if state.notice then
        Text(vg, FitText(vg, state.notice, RW, 5), RX, L.pagerY - 8, state.noticeOk and P.green or P.red, NVG_ALIGN_LEFT, 5)
    end
    local actionable = item.canAction == true
    Button(vg, s, 'detail_action', RX, L.pagerY, RW, L.pagerH, item.actionLabel or '操作',
        actionable, function() ActivateSelected(bag) end, not actionable, (actionable or item.equipped) and P.green or nil, L.pagerPad)
end

function M.Render(vg, opts)
    opts = opts or {}
    local bag = opts.bag
    local x, y, scale, W, H = Draw.ScrollMetrics()
    local L = GetLayout(scale)
    local elapsed = state.openedAt and math.max(0, GetTime():GetElapsedTime() - state.openedAt) or 1
    local openness = Draw.ScrollProgress(elapsed, false)
    local left, right = Draw.ScrollBounds(W, openness)

    state.buttons = {}
    local cat, filters, items, startIdx, endIdx, selectedItem = SyncData(bag, L.pageSize)

    Draw.Begin(vg, true)
    if openness > 0 then
        Draw.Save(vg)
        nvgTranslate(vg, x, y); nvgScale(vg, scale, scale)
        Draw.ScrollPaper(vg, W, H, left, right)
        Draw.Save(vg)
        nvgIntersectScissor(vg, left + 12, 0, math.max(0, right - left - 24), H)

        local l, r, t, b = 17, W - 17, L.frameT, L.frameB
        Rect(vg, l, t, r - l + 1, 1, P.edge); Rect(vg, l, b, r - l + 1, 1, P.edge)
        Rect(vg, l, t, 1, b - t, P.edge); Rect(vg, r, t, 1, b - t, P.edge)
        Rect(vg, 214, t + 2, 1, b - t - 4, P.line)
        local titleY = L.tabY + math.floor(L.tabH * .5)
        Rect(vg, 19, titleY, 7, 1, P.edge); Rect(vg, 22, titleY - 3, 1, 7, P.edge); Rect(vg, 21, titleY - 1, 3, 3, P.gold)
        Text(vg, '行囊背包', 31, titleY)

        local tabW = math.min(40, math.floor((192 - (#categories - 1) * 4) / math.max(1, #categories)))
        for i, c in ipairs(categories) do
            Button(vg, state, 'cat_' .. c.id, 82 + (i - 1) * (tabW + 4), L.tabY, tabW, L.tabH, c.name,
                i == state.categoryIndex, function() SelectCategory(i) end, false, nil, L.tabPad)
        end
        if opts.onSettings then
            Button(vg, state, 'to_settings', 278, L.tabY, 36, L.tabH, '设置', false, opts.onSettings, false, nil, L.tabPad)
        end
        Button(vg, state, 'close', 318, L.tabY, 44, L.tabH, '关闭 ×', false, opts.onClose, false, nil, L.tabPad)

        local fx, filterW = GRID_X, #filters > 4 and 28 or 34
        if L.compact then filterW = #filters > 4 and 28 or 36 end
        local filterGap = L.compact and 2 or 3
        for _, f in ipairs(filters) do
            if fx + filterW <= 178 then
                local fid = f.id
                Button(vg, state, 'filter_' .. fid, fx, L.filterY, filterW, L.filterH, FitText(vg, f.name, filterW - 4, 5),
                    state.filterId == fid, function() SelectFilter(fid) end, false, nil, L.filterPad)
                fx = fx + filterW + filterGap
            end
        end
        Right(vg, ('共%d项'):format(#items), GRID_X + 190, L.filterY + math.floor(L.filterH * .5), P.muted, 5)

        if #items == 0 then
            DrawEmptyState(vg, cat, L)
        else
            for idx = startIdx, endIdx do
                local pos = idx - startIdx + 1
                local cx = GRID_X + ((pos - 1) % COLS) * (CARD_W + COL_GAP)
                local cy = L.gridY + math.floor((pos - 1) / COLS) * (L.cardH + L.rowGap)
                local item = items[idx]
                DrawCard(vg, item, cx, cy, L.cardH, pos == state.focusPos)
                AddHit(state, 'card_' .. pos, cx, cy, CARD_W, L.cardH, function()
                    state.focusPos, state.selectedKey, state.notice = pos, item.key, nil
                end, 0)
            end
        end

        Button(vg, state, 'prev_page', GRID_X, L.pagerY, 58, L.pagerH, '◀ 上页', false,
            function() SelectPage(state.page - 1) end, state.page <= 1, nil, L.pagerPad)
        Center(vg, ('%d / %d'):format(state.page, state.pages), GRID_X + 95, L.pagerY + math.floor(L.pagerH * .5), P.ink, 6)
        Button(vg, state, 'next_page', GRID_X + 132, L.pagerY, 58, L.pagerH, '下页 ▶', false,
            function() SelectPage(state.page + 1) end, state.page >= state.pages, nil, L.pagerPad)

        DrawDetail(vg, state, selectedItem, bag, L)
        Center(vg, TouchInput.IsEnabled()
            and '点选页签与物品卡 · 左右翻页 · 右侧操作'
            or '方向键/WASD 选格 · Q/E 切类 · [ ] 翻页 · Enter 装备 · Esc 关闭', W * .5, 200, P.muted, 5)

        Draw.Restore(vg); Draw.Restore(vg)
    end
    Draw.Finish(vg)
end

function M.Click(hudX, hudY)
    local ox, oy, scale = Draw.ScrollMetrics()
    local ax, ay = (hudX - ox) / scale, (hudY - oy) / scale
    if ax < 0 or ay < 0 or ax > M.width or ay > M.height then return false end
    for i = #state.buttons, 1, -1 do
        local b = state.buttons[i]
        if ax >= b.x and ay >= b.y and ax < b.x + b.w and ay < b.y + b.h then
            if b.action then b.action() end
            return true
        end
    end
    return true
end

function M.Wheel(delta)
    if not delta or delta == 0 then return false end
    if delta > 0 and state.page > 1 then SelectPage(state.page - 1)
    elseif delta < 0 and state.page < state.pages then SelectPage(state.page + 1) end
    return true
end

function M.Key(key, repeatKey, opts)
    opts = opts or {}
    local bag = opts.bag
    local _, _, items, startIdx, endIdx = SyncData(bag)
    local pageCount = math.max(0, endIdx - startIdx + 1)
    local pageSize = state.pageSize or 6
    if key == KEY_ESCAPE or (key == KEY_B and not repeatKey) then
        if not repeatKey and opts.onClose then opts.onClose() end
        return true
    elseif key == KEY_Q then
        if not repeatKey then SelectCategory((state.categoryIndex - 2) % #categories + 1) end
        return true
    elseif key == KEY_E or key == KEY_TAB then
        if not repeatKey then SelectCategory(state.categoryIndex % #categories + 1) end
        return true
    elseif key == KEY_1 or key == KEY_2 or key == KEY_3 then
        local idx = key == KEY_1 and 1 or (key == KEY_2 and 2 or 3)
        if not repeatKey and idx <= #categories then SelectCategory(idx) end
        return true
    elseif key == rawget(_G, 'KEY_PAGEUP') or key == rawget(_G, 'KEY_LEFTBRACKET') then
        if state.page > 1 then SelectPage(state.page - 1) end
        return true
    elseif key == rawget(_G, 'KEY_PAGEDOWN') or key == rawget(_G, 'KEY_RIGHTBRACKET') then
        if state.page < state.pages then SelectPage(state.page + 1) end
        return true
    elseif pageCount > 0 then
        local globalIdx = startIdx + state.focusPos - 1
        local nextGlobal
        if key == KEY_LEFT or key == KEY_A then
            nextGlobal = globalIdx > 1 and (globalIdx - 1) or #items
        elseif key == KEY_RIGHT or key == KEY_D then
            nextGlobal = globalIdx < #items and (globalIdx + 1) or 1
        elseif key == KEY_UP or key == KEY_W then
            nextGlobal = globalIdx - COLS >= 1 and (globalIdx - COLS) or math.min(#items, math.max(1, #items - ((#items - 1) % COLS) + ((globalIdx - 1) % COLS)))
        elseif key == KEY_DOWN or key == KEY_S then
            nextGlobal = globalIdx + COLS <= #items and (globalIdx + COLS) or math.min(#items, ((globalIdx - 1) % COLS) + 1)
        elseif (key == KEY_RETURN or key == KEY_SPACE) and not repeatKey then
            ActivateSelected(bag); return true
        end
        if nextGlobal then
            state.page = math.floor((nextGlobal - 1) / pageSize) + 1
            state.focusPos = nextGlobal - (state.page - 1) * pageSize
            state.selectedKey, state.notice = items[nextGlobal].key, nil
            return true
        end
    end
    return false
end

return M
