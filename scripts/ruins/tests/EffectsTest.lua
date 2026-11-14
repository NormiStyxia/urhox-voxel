-- 实际公告板/立方体池与秒预算回归，不替换引擎对象。
local V = _G["V"]
local VoxelFX = require("dragon.VoxelFX")
local Spells = require("ruins.TimeSpells")
V.atFrame(5, function()
    local game = _G["RUINS"]
    V.assert(game.atmosphere.motes == nil and game.scene:GetChild("AmbientFloatingMotes", true) == nil,
        "不创建跟随头顶的环境浮光")
    V.assert(game.scene:GetChild("CombatHandMotes", true) ~= nil and game.fx.handLight ~= nil,
        "保留独立手部粒子与掌心灯光")
    local root = game.scene:CreateChild("EffectsRegression")
    local pool = VoxelFX.Motes(root,"Pool",8,"square",true)
    local function Spawn(life)
        return pool:Spawn({pos=Vector3.ZERO,life=life,size=.1,colors={Color.WHITE}})
    end
    for i=1,8 do Spawn(.1) end
    pool:Update(.05)
    V.assert(pool:Count()==8 and #pool.free==0,"粒子池满时容量守恒")
    pool:Update(.1)
    local hidden=true
    for i=0,7 do if pool.bb:GetBillboard(i).enabled then hidden=false end end
    V.assert(hidden and pool:Count()==0 and #pool.free==8,"最后死亡帧关闭所有公告板")
    local live,free=pool.list,pool.free
    pool:Update(.1); pool:Clear(); pool:Clear()
    V.assert(live==pool.list and free==pool.free and #free==8,"空池与重复清理不分配或重复归还")
    for i=1,8 do Spawn(1) end
    local seen,unique={},true
    for _,p in ipairs(pool.list) do if seen[p.idx] then unique=false end; seen[p.idx]=true end
    V.assert(unique and Spawn(1)==nil,"重新填满后索引唯一且不会超容量")
    pool:Clear()

    local quads=VoxelFX.WorldMotes(root,"WorldPool",8,"square",true,game.nomiCtl:CameraNode())
    root.position=Vector3(3,2,1); root.scale=Vector3(2,3,4)
    local point=Vector3(10,80,20)
    for i=1,8 do quads:Spawn({pos=point,life=.1,size=.06,colors={Color.WHITE}}) end
    quads:Update(.05); quads:Draw()
    V.assert(quads:Count()==8 and quads.geometry:GetNumVertices(0)==48,"世界粒子满池只提交48个顶点")
    local vertex=quads.geometry:GetVertex(0,0).position
    local worldVertex=quads.node:LocalToWorld(vertex)
    V.assert(math.abs((worldVertex-point):Length()-math.sqrt(2)*.06)<.0001,"父节点位移与非均匀缩放不改变粒子米制尺寸")
    quads:Update(.1)
    V.assert(not quads.node.enabled and #quads.free==8,"世界粒子最后死亡帧立即隐藏并回收")
    quads:Clear(); quads:Clear()
    V.assert(#quads.free==8,"世界粒子重复清理不重复归还")
    root.position=Vector3.ZERO; root.scale=Vector3.ONE

    local debris=VoxelFX.Debris(root,4,true)
    V.assert(not debris.initialized and #debris.items==0,"闲置碎屑池不创建模型")
    for i=1,4 do debris:Spawn({pos=Vector3.ZERO,life=.1,color=Color.WHITE}) end
    debris:Update(.2); debris:Clear(); debris:Clear()
    V.assert(#debris.free==4 and #debris.live==0,"碎屑死亡和重复清理容量守恒")

    local fx=Spells.NewFX(game.scene)
    local blue,gold=0,0
    local oldBlue,oldGold=fx.motesB.Spawn,fx.motesG.Spawn
    fx.motesB.Spawn=function(self,p) blue=blue+1; return oldBlue(self,p) end
    fx.motesG.Spawn=function(self,p) gold=gold+1; return oldGold(self,p) end
    local pieces={}
    for i=1,90 do
        local node=root:CreateChild("Sample"..i)
        node.position=Vector3(i,80,0)
        pieces[i]={node=node,nx=1,ny=1,nz=1}
    end
    local object={state="REWIND",pieces=pieces,size=.25,center=Vector3(0,80,0),radius=2}
    for _,fps in ipairs({30,60,120}) do
        fx.rewinds={}; blue,gold=0,0
        fx:StartRewind(object); fx:StartRewind(object)
        for i=1,fps do
            fx:Update(1/fps,nil,nil,0)
            fx.motesB:Clear(); fx.motesG:Clear()
        end
        V.assert(blue==300 and gold==72,"回溯粒子按秒预算，fps="..fps)
        V.assert(#fx.rewinds==1,"重复回溯不增加单物件发射器")
    end
    blue,gold=0,0
    fx:Update(5,nil,nil,0)
    V.assert(blue<=30 and gold<=8,"长卡顿丢弃发射欠账")
    fx.motesB:Clear(); fx.motesG:Clear(); blue,gold=0,0
    fx:Update(1/60,nil,nil,0)
    V.assert(blue<=5 and gold<=2,"卡顿后没有追赶爆发")
    fx.motesB:Clear(); fx.motesG:Clear()
    fx.root:Dispose(); root:Dispose()
    print("RuinsEffectsTest: real pools and time budgets passed")
end)
