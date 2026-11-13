-- 首次进入无存档：Load 不得对不存在的文件调用 File()（否则引擎打印 "Could not open file" ERROR）。
package.path = "scripts/?.lua;" .. package.path
_G.FILE_READ, _G.FILE_WRITE = 0, 1
_G.cjson = { encode=function() return "x" end, decode=function() error("should not decode") end }
local opened = 0
_G.File = function() opened = opened + 1; return nil end
_G.fileSystem = { FileExists = function() return false end }
local Store = require("combat.WeaponStore")
local cfg = Store.Load()
assert(opened == 0, "Load must not open a missing save file")
assert(cfg.version == 1 and cfg.active == "sword", "falls back to default config")
print("weapon_store_missing PASS")
