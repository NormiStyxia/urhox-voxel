local V=_G['V']
V.atFrame(2,function()
    local s=_G['TOUCH_LAYOUT'];s.mounted=true;s.airborne=true
    require('ui.TouchControls').Sync()
end)
V.atFrame(132,function()V.finish()end)
