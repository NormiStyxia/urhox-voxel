# Q 点按切换与可见轮盘指针 — 2026-11-17

用户反馈：原轮盘鼠标难控制，随便划就过头；要求点按 Q 按剑→弓→法器循环。

## 改动
- WeaponSelectGesture：Q 松开前等待 0.22 秒；短按复用 SelectLoadout，长按展开原轮盘。长按松键不再附加快速切换。
- RuinsScene：输入边沿/持续时长接线、快速切换期间保护 TouchControls 清理回调，保留新换装动画。UI、受击、骑乘、失焦等取消待定请求；不可取消攻击不排队切换。
- WeaponWheel：绘制浅色深边箭头指针，保留 Web pointer lock；打开即位于当前武器图标，不再从不可见中心依赖细小位移判断方向。忽略打开当帧旧相机位移，移动增益 0.65，按布局和 DPR 换算；共享扇区边缘 4° 防抖。空白方向仍可取消。
- 仍是原手旁环弧与触摸点击选择，不抢占 Tab 远景，也未改锻造/武器模型/天空。
- HUD、训练提示及装备就绪提示说明 Q 点按/长按。

## 验证
PASS focused Lua (lupa.lua54, weapon_wheel + weapon_select_gesture) — focused.log。
包含真实 Scene 回调 + CombatMoves/CombatState/PointerCapture 接线，三件循环、换装动画不被清理、长按不额外切换、打断不延迟触发、三槽指针/DPR/末帧位移/只采样一次/边缘防抖/实际指针绘制路径及触摸回归。
FAIL python3 tests/nomi/run_offline.py — offline.log；72 PASS / 1 既有 FAIL：tests/ruins/time_object_lifecycle.lua:35，Dispose leaves world-owned render nodes; use RemoveVolume。
FAIL python3 validation/combat/q-wheel-2026-11-17/lsp_check.py — lsp.log；5 项既有 Error（RuinsBuild/RuinsTerrain 的 world/scene 注释、TimeLifecycleTest 重复 before）。本次修改文件无 Error。
PASS git diff --check — diff-check.log。

以上是离线逻辑/绘制调用验证；没有将它当作真实 Web 鼠标手感或渲染验收。最终需 Web 试点按循环、长按可见指针、松开确认、右键取消及恢复视角。

## 并行与交付
本机 SkyAtmosphere 和 sky-fx 等他人修改全部保留，未纳入提交。
云端正在更新动作/体力等内容，最近 cloud-status 显示 AnimClips.lua、tests/combat/anim_spec.lua 尚未提交。构建工具会自动提交云端脏改动，因此暂不触发构建；本次先独立本地提交，等待云端工作区干净后再合并构建。
