# UrhoX UI 开发指南

> **本指南是 UrhoX UI 系统的权威参考文档。**
> 如果你是 AI 助手，在生成 UrhoX UI 代码之前，请仔细阅读本指南。
>
> **核实 API 是否存在**（写代码遇到不确定时直接读源码，30 秒可定）：
> - 顶层导出（`UI.Panel` / `UI.Label` / `UI.Init` / `UI.SetRoot` ...）：[`urhox-libs/UI/init.lua`](../../urhox-libs/UI/init.lua)
> - Widget 实例方法（`:SetText` / `:AddChild` / `:FindById` ...）：[`urhox-libs/UI/Core/Widget.lua`](../../urhox-libs/UI/Core/Widget.lua) 头部 `---@class WidgetProps` 及各 `function Widget:XXX`

## 目录

1. [快速开始](#1-快速开始)
2. [架构概述](#2-架构概述)
3. [初始化（关键）](#3-初始化关键)
4. [布局系统（Yoga）](#4-布局系统yoga)
5. [Widget 基类](#5-widget-基类)
6. [全部 Widget 参考](#6-全部-widget-参考)
7. [高级组件](#7-高级组件)
8. [主题系统](#8-主题系统)
9. [事件系统](#9-事件系统)
10. [渲染](#10-渲染)
11. [常用模式](#11-常用模式)
12. [常见陷阱与解决方案](#12-常见陷阱与解决方案)
13. [布局辅助工具](#13-布局辅助工具)

---

## 1. 快速开始

### 最小示例

```lua
local UI = require("urhox-libs/UI")

-- 第一步：初始化 UI 系统（必须）
UI.Init({
    theme = "default-dark",
    scale = UI.Scale.DEFAULT,  -- 要求默认使用，遵循 Web/CSS 像素标准：1基准像素 = 1CSS像素，小屏 UI 密度自适应
})

-- 第二步：构建 UI 树
local root = UI.Panel {
    width = "100%",
    height = "100%",
    justifyContent = "center",
    alignItems = "center",
    backgroundColor = { 245, 245, 245, 255 },
    children = {
        UI.Button {
            text = "Hello UrhoX!",
            onClick = function(self)
                print("Clicked!")
            end,
        }
    }
}

-- 第三步：设置根控件（必须——千万不要忘记！）
UI.SetRoot(root)
```

### 三个必须步骤

每个 UrhoX UI 应用**必须**遵循以下三步：

1. **`UI.Init(config)`** — 初始化 UI 系统（字体、主题、事件）
2. **构建控件树** — 使用 `UI.WidgetName { props }` 创建控件
3. **`UI.SetRoot(root)`** — 设置根控件，开始渲染

> **警告**：忘记调用 `UI.SetRoot()` 是最常见的错误。与 React/Vue 不同，UrhoX 没有隐式的根挂载机制。你**必须**调用 `UI.SetRoot(root)`，否则什么都不会渲染。

### 必须关注：安全区适配

全屏 HUD、菜单等可交互内容应放入 `UI.SafeAreaView`，避开设备刘海、圆角、Tap 胶囊和安全区；背景置于其外，以覆盖刘海区域。

当 `SafeAreaView` 无法满足布局要求时，可直接读取安全区：`UI.GetSafeAreaInsets()`；Tap 胶囊使用 [`sdk:GetNativeExitMenuRect()`](sdk.md)。见 [SafeAreaView](#safeareaview)。

---

## 2. 架构概述

### 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| 布局 | **Yoga**（React Native 布局引擎） | 不是 CSS Flexbox！默认值不同 |
| 渲染 | **NanoVG** | 矢量图形，硬件加速 |
| 脚本 | **Lua 5.4** | 所有 UI 代码均为 Lua |
| 坐标 | **基准像素（Base Pixels）** | 代码中直接使用的逻辑坐标单位 |

### 模块结构

```
UI/
├── init.lua              -- 入口，导出所有控件为 UI.XXX
├── Core/
│   ├── UI.lua            -- 主管理器（Init、SetRoot、Render、Update）
│   ├── Widget.lua        -- 控件基类（所有控件继承自此）
│   ├── Theme.lua         -- 主题系统（颜色、间距、字体）
│   ├── Style.lua         -- 样式辅助（Yoga 属性映射）
│   ├── Input.lua         -- 输入事件管理
│   ├── InputAdapter.lua  -- 平台输入适配器（鼠标/触摸）
│   ├── PointerEvent.lua  -- 统一指针事件类
│   ├── Gesture.lua       -- 手势识别器
│   ├── GestureEvent.lua  -- 手势事件类
│   ├── ImageCache.lua    -- NanoVG 图片缓存
│   └── Transition.lua    -- CSS-like 属性过渡与关键帧动画
├── Widgets/              -- 40+ 个控件类
│   ├── Panel.lua, Label.lua, Button.lua, ...
│   └── ...
├── Components/           -- 7 个高级复合组件
│   ├── VirtualList.lua, ChatWindow.lua, ...
│   └── ...
└── Examples/             -- 示例代码
    └── WidgetsGallery.lua
```

### 控件访问方式

所有控件均可通过 `UI.WidgetName` 访问：

```lua
local UI = require("urhox-libs/UI")
local panel = UI.Panel { ... }
local button = UI.Button { ... }
local modal = UI.Modal { ... }

-- 工具模块也通过 UI 访问
UI.Theme                  -- 主题系统
UI.Style                  -- 样式工具
UI.Transition             -- 过渡/动画系统（Easing、Lerp 等）
```

---

## 3. 初始化（关键）

### UI.Init(config)

**方式一：使用内置主题（推荐）**

内置主题自带字体配置，无需手动指定 fonts：

```lua
UI.Init({
    theme = "default-dark",       -- 内置主题名称（自带字体）
    scale = UI.Scale.DEFAULT,
})
```

**方式二：使用内置主题 + 自定义字体**

`fonts` 参数优先级高于主题内置字体，可覆盖：

```lua
UI.Init({
    theme = "default-dark",
    fonts = {                      -- 显式 fonts 覆盖主题字体
        { family = "sans", weights = {
            normal = "Fonts/MyFont-Regular.ttf",
            bold = "Fonts/MyFont-Bold.ttf",
        }}
    },
    scale = UI.Scale.DEFAULT,
})
```

**方式三：自定义主题 table**

```lua
local myTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    fonts = {
        { family = "sans", weights = {
            normal = "Fonts/MyFont-Regular.ttf",
            bold = "Fonts/MyFont-Bold.ttf",
        }}
    },
    colors = {...},
    components = {...}
})
UI.Init({
    theme = myTheme,               -- 直接传 table
    scale = UI.Scale.DEFAULT,
})
```

**方式四：不指定主题（默认使用废弃主题，不推荐！）**

```lua
UI.Init({
    fonts = {
        { family = "sans", weights = {
            normal = "Fonts/MiSans-Regular.ttf",
            bold = "Fonts/MiSans-Bold.ttf",
        }}
    },
    scale = UI.Scale.DEFAULT,
})
```

**参数优先级**：
- `fonts`：`options.fonts` > `theme.fonts` > 内置 MiSans 兜底
- `theme`：支持 string（注册名）或 table（直接 theme 对象）

**其他可选参数**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `scale` | `UI.Scale.DEFAULT` | **要求默认使用**。遵循 Web/CSS 像素标准：1基准像素 = 1CSS像素，小屏 UI 密度自适应（详见§10） |
| `autoEvents` | `true` | 自动订阅 input/update/render 事件 |

### UI.SetRoot(root, destroyOld)

```lua
-- 设置根控件（必须在构建 UI 树之后调用）
UI.SetRoot(root)                -- destroyOld 默认为 false
UI.SetRoot(newRoot, true)       -- 销毁旧的根控件
```

> **自动行为**：`SetRoot` 会自动将根容器的 `pointerEvents` 设为 `"box-none"`（如果未显式设置）。这防止全屏根容器拦截所有 hit test 导致游戏输入被阻断。根容器自身不接收点击事件，但其子控件正常接收。

### UI.Shutdown()

```lua
-- 清理 UI 系统（场景退出时调用）
UI.Shutdown()
```

### 手动事件模式

如果设置了 `autoEvents = false`，需要手动调用：

```lua
-- 在你的更新循环中：
UI.Update(dt)        -- 帧更新（动画、手势）
UI.Render()          -- 渲染 UI（在 NanoVG 帧内调用）
UI.Layout()          -- 重新计算布局（Render 在布局脏时会自动调用）
```

---

## 4. 布局系统（Yoga）

### 关键：Yoga 与 CSS 的默认值差异

| 属性 | CSS 默认值 | Yoga（UrhoX）默认值 | 影响 |
|------|-----------|---------------------|------|
| `flexShrink` | **1**（收缩） | **0**（不收缩） | 子元素可能溢出！ |
| `flexDirection` | **row**（水平） | **column**（垂直） | 默认纵向排列 |
| 盒模型 | content-box | **border-box** | padding 包含在 width/height 内 |

### 尺寸属性

```lua
-- 固定尺寸（基准像素）
{ width = 200, height = 100 }

-- 百分比（相对于父容器）
{ width = "50%", height = "100%" }

-- 自动尺寸（适应内容）
{ width = "auto", height = "auto" }

-- 约束
{ minWidth = 100, maxWidth = 500, minHeight = 50, maxHeight = 300 }
```

### Flex 布局

```lua
-- 方向（默认："column"）
{ flexDirection = "row" }           -- 水平
{ flexDirection = "column" }        -- 垂直（默认）
{ flexDirection = "row-reverse" }   -- 水平反向
{ flexDirection = "column-reverse" }-- 垂直反向

-- 对齐
{ justifyContent = "center" }       -- 主轴："flex-start"|"center"|"flex-end"|"space-between"|"space-around"|"space-evenly"
{ alignItems = "center" }           -- 交叉轴："flex-start"|"center"|"flex-end"|"stretch"|"baseline"
{ alignItems = "baseline" }         -- 按文字基线对齐（Label 自动设置基线值，不同字号自动对齐）
{ alignSelf = "flex-end" }          -- 覆盖父容器的 alignItems

-- Flex 尺寸
{ flexGrow = 1 }                    -- 填充可用空间
{ flexShrink = 1 }                  -- 允许收缩（Yoga 默认为 0！）
{ flexBasis = 0 }                   -- flex 计算的起始尺寸
{ flex = 1 }                        -- 简写

-- 换行
{ flexWrap = "wrap" }               -- "no-wrap"（默认）| "wrap" | "wrap-reverse"
```

### 间距

```lua
-- 子元素间距
{ gap = 8 }
{ rowGap = 8, columnGap = 16 }

-- 外边距
{ margin = 16 }                     -- 四边
{ marginTop = 8, marginBottom = 8 } -- 单边
{ marginHorizontal = 16 }           -- 左 + 右
{ marginVertical = 8 }              -- 上 + 下
{ margin = "auto" }                 -- 自动边距（居中）

-- 内边距（border-box，包含在 width/height 内）
{ padding = 16 }                    -- 四边
{ paddingHorizontal = 16 }          -- 左 + 右
{ paddingVertical = 8 }             -- 上 + 下
{ paddingTop = 8, paddingLeft = 16 }-- 单边

-- table 形式（padding 和 margin 均支持）
-- CSS shorthand 数组：
{ padding = { 10 } }               -- 四边均为 10
{ padding = { 10, 20 } }           -- 上下 10, 左右 20
{ padding = { 10, 20, 30 } }       -- 上 10, 左右 20, 下 30
{ padding = { 10, 20, 30, 40 } }   -- 上 10, 右 20, 下 30, 左 40

-- 命名键（可与数组形式混用，命名键优先）：
{ margin = { left = 16 } }
{ margin = { horizontal = 20, vertical = 10 } }
{ padding = { top = 10, bottom = 20, left = 16, right = 16 } }

-- 值类型：number（绝对像素）、"N%"（百分比）、"auto"（仅 margin）
```

### 定位

```lua
-- 相对定位（默认，参与 flex 布局）
{ position = "relative" }

-- 绝对定位（脱离 flex 流，相对于父容器定位）
{ position = "absolute", top = 10, right = 10 }

-- 溢出
{ overflow = "visible" }            -- 默认
{ overflow = "hidden" }             -- 裁剪子元素
```

### 宽高比

```lua
-- 宽高比（Yoga 自动计算另一维度）
{ aspectRatio = 16/9 }              -- 设置宽度后，高度自动 = width/(16/9)
{ aspectRatio = 1 }                 -- 正方形
```

### Border-Box 盒模型

```lua
-- width 包含 padding（border-box）
{ width = 100, paddingHorizontal = 20 }
-- 总宽度 = 100px，内容区域 = 60px

-- 不设置 width 时，padding 会增加自动计算的尺寸
{ paddingHorizontal = 20 }
-- 总宽度 = 内容宽度 + 40px
```

---

## 5. Widget 基类

所有控件通过 `Widget:Extend("WidgetName")` 继承自 Widget。

### 创建控件

```lua
-- 声明式（推荐）
local widget = UI.Panel {
    width = 200,
    height = 100,
    backgroundColor = { 255, 0, 0, 255 },
    children = { child1, child2 },
}

-- 编程式
local widget = UI.Panel {}
widget:AddChild(child1)
widget:AddChild(child2)
widget:SetStyle({ backgroundColor = { 255, 0, 0, 255 } })
```

### 子控件管理

```lua
widget:AddChild(child)              -- 添加子控件
widget:InsertChild(child, index)    -- 在指定位置插入（1-based）
widget:RemoveChild(child)           -- 移除子控件
widget:ClearChildren()              -- 移除所有子控件
widget:RemoveAllChildren()          -- ClearChildren 的别名
widget:FindById("myId")             -- 按 id 递归查找
widget:GetNumChildren()             -- 获取子控件数量
widget:GetChildAt(index)            -- 获取指定位置的子控件（1-based）
widget:GetChildren()                -- 获取子控件数组（只读，勿修改）
```

### 可见性

```lua
widget:Show()                       -- 显示
widget:Hide()                       -- 隐藏
widget:SetVisible(bool)             -- 设置可见性
widget:IsVisible()                  -- 检查可见性
```

### 布局查询

```lua
widget:GetLayout()                  -- { x, y, w, h } 相对于父容器
widget:GetAbsoluteLayout()          -- { x, y, w, h } 绝对坐标（基准像素）
widget:GetComputedSize()            -- (width, height)
widget:GetAbsolutePosition()        -- (x, y)
```

### 透明属性路由

Widget 支持直觉式属性读写。赋值会自动路由到对应的 `Set{Key}` 方法，读取会自动返回 `props` 中的值：

```lua
-- 以下两种写法等价：
widget.text = "Hello"               -- 自动路由到 widget:SetText("Hello")
widget:SetText("Hello")             -- 显式调用

-- 读取属性：
print(widget.text)                  -- 自动读取 widget.props.text
print(widget.visible)               -- 自动读取 widget.props.visible

-- 常见属性都可以这样用：
widget.visible = false              -- → widget:SetVisible(false)
widget.width = 300                  -- → widget:SetWidth(300)
widget.height = 200                 -- → widget:SetHeight(200)
widget.disabled = true              -- → widget:SetDisabled(true)
```

路由规则：属性名 `foo` → 查找 `SetFoo` 方法。如果类上存在 `SetFoo`，则写入走 setter，读取走 `props.foo`。不存在对应 setter 的属性按普通字段处理。

> **向后兼容**：所有显式 `Set*()` 调用仍然正常工作。属性路由只是一个额外的便利层。

### 过渡与动画

Widget 支持 CSS 风格的属性过渡和关键帧动画。

#### 属性过渡（Transition）

当 `transition` 属性配置后，通过 `SetStyle()` 修改可过渡属性时会自动产生平滑过渡动画。

```lua
-- 简写字符串格式
UI.Panel {
    transition = "all 0.3s easeOut",  -- 所有可过渡属性 0.3 秒 easeOut
    opacity = 1.0,
    backgroundColor = { 255, 0, 0, 255 },
}

-- 仅特定属性过渡
UI.Panel {
    transition = "opacity 0.2s easeInOut",
}

-- 逗号分隔（CSS 格式，每个属性独立 duration/easing）
UI.Panel {
    transition = "backgroundColor 0.8s easeInOut, scale 0.3s easeOutBack, opacity 0.5s linear",
}

-- 表格式
UI.Panel {
    transition = {
        properties = { "opacity", "scale", "backgroundColor" },
        duration = 0.3,
        easing = "easeOut",
    },
}
```

**可过渡属性**：`opacity`、`scale`、`rotate`、`translateX`、`translateY`、`borderRadius`、`borderWidth`、`shadowBlur`、`shadowOffsetX`、`shadowOffsetY`、`backgroundColor`、`borderColor`、`shadowColor`、`fontColor`

**可用缓动函数**：`linear`、`easeIn`、`easeOut`、`easeInOut`、`easeInCubic`、`easeOutCubic`、`easeInOutCubic`、`easeInExpo`、`easeOutExpo`、`easeInBack`、`easeOutBack`、`easeInOutBack`、`spring`

**时长格式**：`"0.3s"` | `"300ms"` | `"0.3"`

```lua
-- 触发过渡：修改已配置过渡的属性
widget:SetStyle({ opacity = 0.5 })  -- 自动从当前值平滑过渡到 0.5
```

> **Button 特殊支持**：Button 的 hover/press 背景色切换也受 `transition` 属性控制，无需手动调用 SetStyle。

#### 关键帧动画（Keyframe Animation）

```lua
-- 播放关键帧动画
widget:Animate({
    keyframes = {
        [0]   = { opacity = 0, translateY = 20 },
        [0.5] = { opacity = 1, translateY = 5 },
        [1]   = { opacity = 1, translateY = 0 },
    },
    duration = 0.5,
    easing = "easeOut",
    loop = true,           -- true = 无限循环, 数字 = 循环次数
    direction = "alternate", -- "normal" | "reverse" | "alternate"
    fillMode = "none",     -- "none"(默认) | "forwards" | "backwards" | "both"
    onComplete = function() end,
})

-- 停止动画
widget:StopAnimation()
```

**fillMode 说明**（与 CSS `animation-fill-mode` 一致）：
| 值 | 含义 |
|---|---|
| `"none"` | 默认，动画结束后回弹到 props 原始值 |
| `"forwards"` | 动画结束后保持最后一帧的值（写入 props） |
| `"backwards"` | 动画开始前立即应用第一帧的值（防止闪烁） |
| `"both"` | forwards + backwards |

**方法**：`Animate(config)`、`StopAnimation()`、`HasActiveTransitions()`、`GetRenderProp(propName)`

### 视觉属性（Transform、Opacity、Visibility）

```lua
-- 透明度（影响整个子树，NanoVG globalAlpha 是乘性的）
{ opacity = 0.5 }

-- 变换
{ scale = 1.5 }                    -- 均匀缩放（默认：1.0）
{ rotate = 45 }                    -- 旋转角度（默认：0）
{ translateX = 10, translateY = 20 }  -- 平移（基准像素）
{ transformOrigin = "center" }     -- "center"|"top-left"|"top-right"|"bottom-left"|"bottom-right"|"top"|"bottom"|"left"|"right"|{x,y}

-- 可见性
{ visibility = "hidden" }          -- 隐藏但保持布局空间（不同于 visible=false 跳过布局）

-- 混合模式
{ blendMode = "lighter" }          -- "normal"|"lighter"|"copy"|"xor"|"destination-over"|"source-in"|"source-out"|"destination-in"|"destination-out"

-- z-index 排序
{ zIndex = 10 }                    -- 同级子元素间的渲染和命中测试顺序

-- 光标样式（当前已禁用，待引擎修复）
{ cursor = "pointer" }             -- "default"|"pointer"|"text"|"move"|"not-allowed"|"crosshair"|"ew-resize"|"ns-resize"|"grab"|"wait"
```

### 增强外观属性

```lua
-- 每角圆角（可混合使用）
{ borderRadius = 8 }                        -- 统一圆角
{ borderRadius = { 8, 16, 8, 16 } }       -- {TL, TR, BR, BL}
{ borderRadiusTopLeft = 12 }               -- 单角覆盖（优先于 borderRadius）
{ borderRadiusTopRight = 0 }
{ borderRadiusBottomRight = 12 }
{ borderRadiusBottomLeft = 0 }

-- 每边边框
{ borderTopWidth = 2, borderTopColor = { 255, 0, 0, 255 } }
{ borderBottomWidth = 1, borderBottomColor = { 200, 200, 200, 255 } }
{ borderLeftWidth = 1, borderLeftColor = { 200, 200, 200, 255 } }
{ borderRightWidth = 1, borderRightColor = { 200, 200, 200, 255 } }

-- borderWidth 表格式（CSS shorthand，与 padding/margin 一致）
{ borderWidth = 2 }                        -- 四边均为 2
{ borderWidth = { 1, 3 } }                -- 上下 1, 左右 3
{ borderWidth = { 4, 1, 2 } }             -- 上 4, 左右 1, 下 2
{ borderWidth = { 1, 2, 3, 4 } }          -- 上 1, 右 2, 下 3, 左 4
{ borderWidth = { top = 3, left = 3 } }   -- 命名键：仅上和左

-- 渐变背景
{ backgroundGradient = {
    type = "linear",               -- "linear" | "radial"
    direction = "to-bottom",       -- "to-bottom"|"to-right"|"to-top"|"to-left"|"to-bottom-right"|...| 角度数字(0=to-top, 90=to-right)
    from = { 59, 130, 246, 255 },  -- 起始颜色
    to = { 147, 51, 234, 255 },    -- 结束颜色
} }

-- 径向渐变
{ backgroundGradient = {
    type = "radial",
    innerRadius = 0,
    outerRadius = 100,
    from = { 255, 255, 255, 255 },
    to = { 0, 0, 0, 255 },
} }

-- 增强阴影（boxShadow 优先于 shadowBlur）
{ boxShadow = {
    { x = 0, y = 2, blur = 8, spread = 0, color = { 0, 0, 0, 40 } },         -- 外部阴影
    { x = 0, y = 1, blur = 3, spread = 0, color = { 0, 0, 0, 20 }, inset = true },  -- 内部阴影
} }

-- 背景模糊（近似效果，非真高斯模糊）
{ backdropBlur = 10 }

-- 裁剪路径
{ clipPath = "circle" }            -- 圆形裁剪
{ clipPath = "ellipse" }           -- 椭圆裁剪
{ clipPath = { type = "circle", radius = 50 } }
{ clipPath = { type = "ellipse", rx = 80, ry = 40 } }
```

### 固定定位与粘性定位

```lua
-- 固定定位（相对于视口，脱离滚动流，渲染在普通树之上、浮层之下）
UI.Panel {
    position = "fixed",
    bottom = 20, right = 20,
    width = 60, height = 60,
    -- 也可用 top, left
}

-- 粘性定位（仅 ScrollView 内垂直方向有效）
UI.Panel {
    position = "sticky",
    stickyOffset = 0,              -- 距顶部偏移
    height = 50,
    children = { UI.Label { text = "固定表头" } },
}
```

### 样式

```lua
widget:SetStyle({                   -- 合并样式属性并更新 Yoga
    width = 300,
    backgroundColor = { 0, 0, 255, 255 },
})
widget:SetWidth(300)                -- 设置宽度
widget:SetHeight(200)               -- 设置高度
```

### 状态（有状态控件）

```lua
widget:SetState({ key = value })    -- 合并到 state
widget:GetState()                   -- 获取 state 表
widget.state                        -- 直接访问
widget.props                        -- 属性表
```

### 销毁

```lua
widget:Destroy()                    -- 销毁控件及其所有子控件
widget:Remove()                     -- 从父控件移除（可以稍后重新添加）
```

### 自定义控件类

```lua
local MyWidget = UI.Widget:Extend("MyWidget")

function MyWidget:Init(props)
    props = props or {}
    -- 在调用父类 Init 之前设置默认值
    props.height = props.height or 40
    props.backgroundColor = props.backgroundColor or { 200, 200, 200, 255 }

    UI.Widget.Init(self, props)

    -- 自定义初始化
    self.myField_ = 0
end

function MyWidget:Render(nvg)
    self:RenderFullBackground(nvg)  -- 背景 + 边框 + 阴影

    local l = self:GetAbsoluteLayout()
    -- 自定义 NanoVG 绘制
    nvgFontSize(nvg, UI.Theme.FontSize(12))
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
    nvgText(nvg, l.x + 8, l.y + l.h / 2, "Hello")
end

function MyWidget:Update(dt)
    -- 每帧调用（用于动画）
end

function MyWidget:OnClick(event)
    -- 处理点击
end

return MyWidget
```

---

## 6. 全部 Widget 参考

### 6.1 布局控件

#### Panel

容器，支持背景、边框和裁剪。

```lua
UI.Panel {
    width = 300, height = 200,
    backgroundColor = { 240, 240, 240, 255 },
    borderRadius = 8,
    borderColor = { 200, 200, 200, 255 },
    borderWidth = 1,
    padding = 16,
    flexDirection = "row",       -- 布局方向
    gap = 8,                     -- 子元素间距
    overflow = "hidden",         -- 裁剪子元素
    shadowBlur = 4,              -- 阴影
    shadowColor = { 0, 0, 0, 40 },
}
```

#### Label

文本显示控件。默认 `pointerEvents = "none"`（点击穿透）。

```lua
UI.Label {
    text = "Hello World",
    fontSize = 14,                      -- 字号（pt）
    fontColor = { 0, 0, 0, 255 },      -- 文字颜色
    fontFamily = "sans",                -- 字体
    fontWeight = "bold",                -- "normal"|"bold"
    textAlign = "center",               -- "left"|"center"|"right"
    verticalAlign = "middle",           -- "top"|"middle"|"bottom"
    maxLines = 2,                       -- 最大行数（超出显示 ...）
    -- 文本增强属性
    lineHeight = 1.4,                   -- 行高倍数（默认：1.4 用于自动高度计算，渲染默认 1.0）
    letterSpacing = 2,                  -- 字间距（像素）
    textDecoration = "underline",       -- "none"|"underline"|"line-through"
    textTransform = "uppercase",        -- "none"|"uppercase"|"lowercase"|"capitalize"
    whiteSpace = "normal",             -- "nowrap"（默认，单行）| "normal"（自动换行，使用 nvgTextBox）
    wordBreak = "break-word",          -- "normal"|"break-word"（仅 whiteSpace="normal" 时有效）
    -- 文字特效
    textStroke = { width = 2, color = "#000000" },  -- 描边（8方向偏移），颜色支持 RGBA 表或 hex 字符串
    textShadow = { offsetX = 2, offsetY = 3, blur = 4, color = {0,0,0,128} },  -- 阴影（nvgFontBlur）
}
```

**方法**：`SetText(text)`、`GetText()`、`SetFontSize(size)`、`SetFontColor(color)`

**文字特效说明**：

- `textStroke`：8 方向偏移描边，绘制在填充文字下方。适用于游戏标题、强调文字等需要描边轮廓的场景。
- `textShadow`：基于 `nvgFontBlur` 的文字阴影，绘制在描边下方。`blur=0` 时为硬阴影。
- 两者可组合使用，绘制顺序：阴影 → 描边 → 填充文字。
- 颜色支持 RGBA 表 `{r,g,b,a}` 或 hex 字符串 `"#RRGGBB"`。

#### Divider

水平或垂直分隔线。

```lua
UI.Divider {
    orientation = "horizontal",   -- "horizontal"|"vertical"
    variant = "solid",            -- "solid"|"dashed"|"dotted"
    thickness = 1,
    color = { 200, 200, 200, 255 },
    spacing = 8,                  -- 分隔线周围的间距
    label = "OR",                 -- 中间的文字标签
    labelPosition = "center",     -- "center"|"left"|"right"
}
```

**静态方法**：`Divider.Horizontal(opts)`、`Divider.Vertical(opts)`、`Divider.WithLabel(label, opts)`

#### SafeAreaView

适配设备刘海/安全区域 + TapTap 胶囊位置，横竖屏切换自动更新。可交互元素放 SafeAreaView 内，背景放外面。可并列多个，且各自采用不同布局策略。

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `edges` | `"all"` | `"all"` / `"none"` / `"horizontal"` / `"vertical"` / `{"top","bottom"}` |
| `mode` | `"padding"` | `"padding"` 或 `"margin"` |
| `nativeMenuInset` | `false` | 是否将 TapTap 胶囊合并进 top inset |

```lua
UI.Panel {
    width = "100%", height = "100%",
    backgroundImage = "bg.png",       -- 背景铺满全屏（含刘海/胶囊区域）
    children = {
        UI.SafeAreaView {
            width = "100%", height = "100%",
            children = { --[[ 需要避让的交互 UI ]] }
        }
    }
}

-- 仅避让顶部
UI.SafeAreaView { edges = { "top" }, width = "100%", children = { hudBar } }

-- 同时避让 TapTap 胶囊
UI.SafeAreaView { nativeMenuInset = true, children = { ... } }
```

`SafeAreaView` 无法满足布局时，直接读安全区。UI 布局使用 `UI.GetSafeAreaInsets()`，返回基准像素 `{ left, top, right, bottom }`。Tap 胶囊使用 [`sdk:GetNativeExitMenuRect()`](sdk.md)。

#### SimpleGrid

等宽列网格布局（基于 flex-wrap，非 CSS Grid）。适合背包、卡片列表、图标网格等。

```lua
UI.SimpleGrid {
    columns = 4,                  -- 列数（默认：4）
    gap = 8,                      -- 行列间距
    -- 或使用响应式列宽：
    -- minColumnWidth = 120,      -- 最小列宽（覆盖 columns，自动计算列数）
    children = {
        UI.Panel { height = 80, backgroundColor = { 200, 200, 200, 255 } },
        UI.Panel { height = 80, backgroundColor = { 200, 200, 200, 255 } },
        -- ...
    }
}
```

> **注意**：SimpleGrid 不是 CSS Grid。同行项目高度独立（无跨轴对齐）。适合简单等宽网格，不适合复杂二维布局。

#### ScrollView

可滚动容器，支持惯性滚动和滚动条。

```lua
UI.ScrollView {
    width = "100%",
    flexGrow = 1,
    flexBasis = 0,                -- 重要：配合 flexGrow 使用时必须设为 0
    scrollX = false,              -- 水平滚动（默认：false）
    scrollY = true,               -- 垂直滚动（默认：true）
    showScrollbar = true,         -- 显示滚动条（默认：true）
    scrollbarInteractive = true,  -- 可拖拽滚动条（默认：桌面端 true）
    bounces = true,               -- 边缘回弹效果（默认：true）
    scrollSnapType = "y mandatory", -- 滚动吸附："y mandatory"|"y proximity"|"x mandatory"|"x proximity"
    onScroll = function(self, x, y) end,
}

-- 滚动吸附：子元素设置 scrollSnapAlign
UI.ScrollView {
    scrollSnapType = "y mandatory",
    children = {
        UI.Panel { height = 300, scrollSnapAlign = "start" },  -- "start"|"center"|"end"
        UI.Panel { height = 300, scrollSnapAlign = "start" },
    }
}
-- mandatory：总是吸附到最近的 snap 点
-- proximity：仅当距离 < 40% 容器尺寸时吸附
```

**方法**：`ScrollBy(dx, dy)`、`SetScroll(x, y)`、`GetScroll()`、`ScrollToTop()`、`ScrollToBottom()`、`GetContentSize()`

> **注意**：`flexGrow = 1` 但不设置 `flexBasis = 0` 时 ScrollView 不会滚动！ScrollView 需要一个受约束的高度。

---

### 6.2 输入控件

#### Button

交互按钮，支持多种样式变体。

```lua
UI.Button {
    text = "Click Me",
    variant = "primary",           -- "primary"|"secondary"|"danger"|"success"
    disabled = false,
    fontSize = 14,
    textColor = { 255, 255, 255, 255 },
    hoverBackgroundColor = { 50, 120, 230, 255 },
    pressedBackgroundColor = { 40, 100, 200, 255 },
    onClick = function(self) end,
}
```

**方法**：`SetText(text)`、`SetDisabled(bool)`、`IsDisabled()`

> **说明**：Button 的 `variant` 包含了颜色语义（primary = 蓝色、danger = 红色等）。不需要单独的 `color` 属性。自定义颜色请使用 `backgroundColor` / `textColor`。

#### TextField

单行文本输入。

```lua
UI.TextField {
    value = "",
    placeholder = "请输入...",
    password = false,              -- 密码模式（显示圆点）
    maxLength = 100,
    disabled = false,
    fontSize = 14,
    onChange = function(self, value) end,
    onSubmit = function(self, value) end,  -- 按回车
    onFocus = function(self) end,
    onBlur = function(self) end,
}
```

**方法**：`SetValue(v)`、`GetValue()`、`SetPlaceholder(p)`、`Clear()`、`SelectAll()`、`SetDisabled(bool)`

#### Checkbox

复选框，带标签。

```lua
UI.Checkbox {
    checked = false,
    label = "同意条款",
    size = 20,                    -- 复选框大小（默认：20）
    disabled = false,
    onChange = function(self, checked) end,
}
```

**方法**：`Toggle()`、`SetChecked(bool)`、`IsChecked()`、`SetLabel(text)`、`SetDisabled(bool)`

#### Toggle

开关式切换。

```lua
UI.Toggle {
    checked = false,
    disabled = false,
    onChange = function(self, checked) end,
}
```

**方法**：`Toggle()`、`SetChecked(bool)`、`IsChecked()`、`SetDisabled(bool)`

#### Slider

范围值滑块。

```lua
UI.Slider {
    value = 50,
    min = 0, max = 100,
    step = 1,                     -- 步进增量
    disabled = false,
    trackHeight = 4,
    thumbSize = 16,
    onChange = function(self, value) end,       -- 拖动中
    onChangeEnd = function(self, value) end,   -- 拖动结束
}
```

**方法**：`SetValue(v)`、`GetValue()`、`SetRange(min, max)`、`SetDisabled(bool)`

#### Stepper

数字加减控件。

```lua
UI.Stepper {
    value = 1,
    min = 0, max = 10,
    step = 1,
    onChange = function(self, value) end,
}
```

#### Rating

星级评分控件。

```lua
UI.Rating {
    value = 3,
    max = 5,
    size = 24,                    -- 星星大小
    allowHalf = true,             -- 支持半星
    disabled = false,
    onChange = function(self, value) end,
}
```

#### FileUpload

文件上传控件。

```lua
UI.FileUpload {
    accept = ".png,.jpg",
    multiple = false,
    onSelect = function(self, files) end,
}
```

---

### 6.3 选择控件

#### Dropdown

下拉选择器（浮层渲染）。

```lua
UI.Dropdown {
    options = {
        { value = 1, label = "选项 A" },
        { value = 2, label = "选项 B" },
        { value = 3, label = "选项 C", disabled = true },
    },
    value = 1,                    -- 当前选中值
    placeholder = "请选择...",
    maxVisibleItems = 6,
    disabled = false,
    onChange = function(self, value, option) end,
}
```

**方法**：`SetValue(v)`、`GetValue()`、`GetSelected()`、`SetOptions(opts)`、`AddOption(opt)`、`RemoveOption(value)`、`Open()`、`Close()`、`Toggle()`、`IsOpen()`

#### DatePicker

日期选择器（日历弹窗）。

```lua
UI.DatePicker {
    value = { year = 2026, month = 2, day = 8 },
    format = "yyyy-mm-dd",
    placeholder = "选择日期",
    onChange = function(self, date) end,
}
```

#### TimePicker

时间选择器，支持滚轮式滚动选择（弹窗）。

```lua
UI.TimePicker {
    hour = 14,
    minute = 30,
    second = 0,
    use24Hour = true,             -- 24 小时制（默认：true）
    showSeconds = false,          -- 显示秒列
    onChange = function(self, hour, minute, second) end,
}
```

**特性**：支持鼠标滚轮和触摸拖拽滚动，带惯性和自动吸附。

#### ColorPicker

颜色选择器（弹窗）。

```lua
UI.ColorPicker {
    value = { 255, 0, 0, 255 },  -- RGBA
    showAlpha = true,
    onChange = function(self, color) end,
}
```

#### Calendar

完整日历控件。

```lua
UI.Calendar {
    selectedDate = { year = 2026, month = 2, day = 8 },
    onSelect = function(self, date) end,
}
```

#### Menu

上下文菜单/下拉菜单。

```lua
UI.Menu {
    items = {
        { label = "复制", onClick = function() end },
        { label = "粘贴", onClick = function() end },
        { type = "divider" },
        { label = "删除", onClick = function() end, variant = "danger" },
    },
}
```

#### Tree

树形层级结构。

```lua
UI.Tree {
    data = {
        { id = 1, label = "根节点", children = {
            { id = 2, label = "子节点 A" },
            { id = 3, label = "子节点 B" },
        }},
    },
    onSelect = function(self, node) end,
}
```

---

### 6.4 展示控件

#### Card

卡片容器，支持投影阴影。

```lua
UI.Card {
    variant = "elevated",         -- "elevated"|"outlined"|"filled"
    elevation = 2,                -- 阴影深度 0-5
    hoverable = true,             -- 悬停效果
    clickable = false,
    header = "卡片标题",          -- 字符串或 Widget
    coverImage = "Images/photo.png",
    coverHeight = 160,
    onClick = function(self) end,
}

-- 静态辅助方法
UI.Card.Simple("标题", "内容文本")
UI.Card.Media({ title = "照片", coverImage = "img.png" })
UI.Card.Action({ title = "确认", actions = { UI.Button { text = "OK" } } })
```

**方法**：`SetHeader(h)`、`AddBody(child)`、`ClearBody()`、`SetFooter(w)`、`AddAction(btn)`、`SetVariant(v)`、`SetElevation(n)`

#### Badge

通知徽标/指示器。

```lua
UI.Badge {
    content = 5,                  -- 数字或字符串
    variant = "error",            -- "primary"|"secondary"|"success"|"warning"|"error"
    size = "md",                  -- "sm"|"md"|"lg"
    dot = false,                  -- 仅显示圆点
    max = 99,                     -- 超过后显示 "99+"
    pulse = true,                 -- 脉冲动画
    position = "top-right",       -- "top-right"|"top-left"|"bottom-right"|"bottom-left"
}

-- 包裹其他控件
UI.Badge.Wrap(UI.Button { text = "邮件" }, 3, { variant = "error" })
```

**方法**：`SetContent(c)`、`SetCount(n)`、`Increment(n)`、`Decrement(n)`、`Clear()`

#### Chip

紧凑型标签/筛选元素。

```lua
UI.Chip {
    label = "标签",
    variant = "filled",           -- "filled"|"outlined"|"soft"
    color = "primary",            -- "default"|"primary"|"secondary"|"success"|"warning"|"error"
    size = "md",                  -- "sm"|"md"|"lg"
    deletable = true,             -- 显示删除按钮（别名：removable）
    selectable = true,
    selected = false,
    disabled = false,
    onDelete = function(self) end,  -- （别名：onRemove）
    onSelect = function(self, selected) end,
}

-- 静态辅助方法
UI.Chip.Filter("激活", { onSelect = fn })
UI.Chip.Input("tag-1", { onDelete = fn })
UI.Chip.Group({ "A", "B", "C" }, { onSelect = fn })
```

> **注意**：Chip 的 `variant` 控制外观样式（filled/outlined/soft），`color` 控制颜色方案，两者是独立的属性。

#### Avatar

用户头像，支持图片或首字母缩写。

```lua
UI.Avatar {
    src = "Images/user.png",      -- 图片路径
    name = "张三",                -- 自动生成首字母
    initials = "ZS",              -- 手动覆盖首字母
    size = "md",                  -- "xs"(24)|"sm"(32)|"md"(40)|"lg"(56)|"xl"(80) 或数字
    shape = "circle",             -- "circle"|"rounded"|"square"
    status = "online",            -- "online"|"offline"|"away"|"busy"
    showBorder = true,
}

-- 堆叠头像组
UI.Avatar.Group({
    { name = "Alice" }, { name = "Bob" }, { name = "Charlie" }
}, { max = 3 })
```

#### Alert

警告消息框，带严重级别。

```lua
UI.Alert {
    title = "警告",
    message = "出了些问题",
    severity = "warning",         -- "info"|"success"|"warning"|"error"
    closable = true,
    onClose = function(self) end,
}
```

#### Tooltip

悬停提示。

```lua
UI.Tooltip {
    content = "提示文本",
    position = "top",             -- "top"|"bottom"|"left"|"right"
    delay = 0.3,                  -- 显示延迟（秒）
    offset = 8,
    maxWidth = 250,
}
```

#### Skeleton

加载占位符，带微光动画。

```lua
UI.Skeleton {
    variant = "text",             -- "text"|"rectangular"|"circular"|"rounded"
    animation = "pulse",          -- "pulse"|"wave"|"none"
    lines = 3,                    -- 文本行数
    width = 200, height = 16,
}

-- 静态辅助方法
UI.Skeleton.Text(3)
UI.Skeleton.Circle(40)
UI.Skeleton.Card()
UI.Skeleton.ListItem()
```

#### RichText

富文本显示。

```lua
UI.RichText {
    text = "Hello **bold** and *italic*",
}
```

#### ProgressBar

进度条。

```lua
UI.ProgressBar {
    value = 0.7,                  -- 0-1
    max = 1,
    variant = "primary",          -- "primary"|"success"|"warning"|"error"
    showLabel = true,             -- 显示百分比
    indeterminate = false,        -- 加载模式
    -- 自定义填充
    fillColor = "#FF6B35",        -- 自定义填充色（覆盖 variant 主题色）
    fillGradient = {              -- 渐变填充（覆盖 fillColor 和 variant）
        direction = "to-right",   -- "to-right"（默认）|"to-left"|"to-top"|"to-bottom"
        from = "#B8E75C",
        to = "#8DC63F",
    },
    -- 动画过渡
    transition = "value 0.3s easeOut",  -- SetValue() 时自动平滑过渡
}
```

**方法**：`SetValue(v)`、`GetValue()`、`GetPercent()`、`SetVariant(v)`、`SetIndeterminate(bool)`

**进度动画**：配置 `transition = "value 0.3s easeOut"` 后，调用 `SetValue()` 会自动平滑过渡到目标值，无需手动 lerp。

**自定义进度条组合示例**（渐变填充 + 描边文字 + 动画）：

```lua
local wrapper = UI.Panel { width = 400, height = 36 }

wrapper:AddChild(UI.ProgressBar {
    value = 0.75,
    width = "100%", height = "100%",
    backgroundColor = "#EDE1CA",
    borderColor = "#D2A382", borderWidth = 3, borderRadius = 18,
    fillGradient = { direction = "to-right", from = "#B8E75C", to = "#8DC63F" },
    transition = "value 0.3s easeOut",
})

wrapper:AddChild(UI.Label {
    text = "75%",
    fontColor = "#FFFFFF",
    textStroke = { width = 2, color = "#729233" },
    textAlign = "center",
    position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
})
```

#### Spine

Spine 骨骼动画控件，支持 3.8/4.x 版本资源。

```lua
UI.Spine {
    src = "Spines/hero.skel",       -- .skel 或 .json
    animation = "idle",             -- 初始动画
    loop = true,
    width = 300, height = 400,
    -- skin = "warrior",            -- 皮肤名
    -- pma = true,                  -- PMA（3.8 atlas 无此字段需手动指定，4.x 从 atlas 读取）
    -- flipX = true,                -- 水平翻转
    -- objectFit = "contain",       -- contain | cover | fill
    -- speed = 1.5,                 -- 播放速度
}
```

**动画控制**：

```lua
spine:SetAnimation("walk", true)              -- 设置动画（track 0）
spine:SetAnimation(1, "aim", true)            -- 多轨道（track 1）
spine:AddAnimation("idle", true, 0.5)         -- 队列动画
spine:SetEmptyAnimation(1, 0.2)               -- 平滑淡出轨道
spine:Stop()                                  -- 停止所有
spine:SetSpeed(2.0)                           -- 播放速度
spine:SetTimeScale(0.5)                       -- 全局时间缩放
spine:SetTrackAlpha(1, 0.5)                   -- 轨道混合权重
```

**外观**：

```lua
spine:SetSkin("warrior")
spine:SetAttachment("weapon", "sword")
spine:SetColor(1, 0.5, 0.5, 0.8)             -- RGBA 0-1
spine:SetToSetupPose()                        -- 重置到初始姿态
```

**骨骼操作（IK）**：

```lua
local bone = spine:FindBone("crosshair")      -- 返回缓存的 SpineBone
bone:SetX(100); bone:SetY(200)
spine:UpdateWorldTransform()                   -- 重新计算 IK

-- 坐标转换
local lx, ly = bone:WorldToLocal(worldX, worldY)
local wx, wy = bone:LocalToWorld(localX, localY)
local parent = bone:GetParent()
```

**回调**：

```lua
spine:SetCompleteListener(function(track, anim) end)
spine:SetStartListener(function(track, anim) end)
spine:SetEndListener(function(track, anim) end)
spine:SetDisposeListener(function(track, anim) end)
spine:SetEventListener(function(track, eventName, intVal, floatVal, strVal) end)
```

**坐标转换**（屏幕/本地 → 骨骼空间）：

```lua
local sx, sy = spine:ScreenToSkeleton(event.x, event.y)
local lx, ly = spine:LocalToSkeleton(localX, localY)
```

**查询**：`GetAnimationNames()`、`GetSkinNames()`、`GetBoneNames()`、`GetSlotNames()`、`IsLoaded()`、`IsAnimationComplete(track)`、`GetTrackTime(track)`、`GetAnimationDuration(track)`

**IK aim + shoot 典型用法**（多轨道）：

```lua
-- Track 0: 移动动画, Track 1: aim（常驻）, Track 2: shoot（一次性叠加）
spine:SetAnimation(0, "idle", true)
spine:SetAnimation(1, "aim", true)

-- 每帧更新 crosshair 骨骼 → IK 跟随鼠标
local crosshair = spine:FindBone("crosshair")
-- 在 Update 中：
local sx, sy = spine:ScreenToSkeleton(mouseX, mouseY)
crosshair:SetX(sx); crosshair:SetY(sy)
spine:UpdateWorldTransform()

-- 点击射击：track 2 叠加，不影响 aim
spine:SetAnimation(2, "shoot", false)
```

**⚠️ 注意**：
- `event.x`/`event.y` 是屏幕坐标，用 `ScreenToSkeleton` 转换
- `UpdateWorldTransform()` 必须在设置骨骼位置后调用，否则 IK 延迟一帧
- shoot 放在比 aim 更高的轨道（如 track 2），不要替换 aim 所在的轨道

#### SVG（预览版）

`UI.Svg` 在 UI 布局中显示 SVG，自动绘制并播放动画。

```lua
local svg = UI.Svg {
    src = "Vectors/scene.svg",
    width = 240, height = 120,
    objectFit = "contain",
    onClick = function(self, event)
        local element = self:HitTestElement(event.x, event.y)
        if element and element.id == "wheel" then
            element.opacity = 0.5
        end
    end,
}
parent:AddChild(svg)
```

通过 `GetNativeInstance()` 操作原生实例；时间控制和元素查询沿用 H5 对应命名，方法采用大驼峰（PascalCase）。完整接口见 `.emmylua/Svg.d.lua`。

```lua
local instance = svg:GetNativeInstance()
instance:PauseAnimations()
instance.currentTime = 1.25 -- 秒
instance.playbackRate = 2
instance:UnpauseAnimations()

local element = instance:GetElementById("wheel")
if element then element.rotate = 30 end
```

支持常用图形、基础文字和 SVG 声明式动画（SMIL）子集；暂不支持 `mask/filter`、`animateMotion` 及浏览器 JS/CSS 动画。

**SVG 引用资源**：图片 `href` 和字体 `font-family` 支持相对 `.svg` 的路径。字体也可使用引擎资源路径（不带 `assets/` 前缀），无需调用 `nvgCreateFont`，且不支持 NanoVG 字体别名。

```xml
<text x="0" y="24" font-family="Fonts/SymbolNotes.ttf" font-size="24">♪♫</text>
```


---

### 6.5 导航控件

#### Tabs

标签页导航，带内容面板。

```lua
UI.Tabs {
    tabs = {
        { id = "tab1", label = "常规", content = generalPanel },
        { id = "tab2", label = "设置", content = settingsPanel },
        { id = "tab3", label = "关于", disabled = true },
    },
    activeTab = "tab1",
    variant = "line",             -- "line"|"enclosed"|"pills"
    orientation = "horizontal",   -- "horizontal"|"vertical"
    onChange = function(self, tabId, tab) end,
}
```

**方法**：`SetActiveTab(id)`、`GetActiveTab()`、`AddTab(tab, content)`、`RemoveTab(id)`、`SetTabContent(id, widget)`、`NextTab()`、`PrevTab()`

#### Breadcrumb

面包屑导航。

```lua
UI.Breadcrumb {
    items = {
        { label = "首页", onClick = function() end },
        { label = "产品", onClick = function() end },
        { label = "详情" },       -- 最后一项（无点击）
    },
    separator = "/",
}
```

#### Pagination

分页导航。

```lua
UI.Pagination {
    currentPage = 1,
    totalPages = 10,
    onChange = function(self, page) end,
}
```

---

### 6.6 容器控件

#### Accordion

可展开/折叠的内容区域。

```lua
UI.Accordion {
    items = {
        { id = "s1", title = "第一节", content = panel1 },
        { id = "s2", title = "第二节", content = "文本内容" },
    },
    variant = "default",          -- "default"|"outlined"|"separated"
    allowMultiple = false,
    onChange = function(self, expandedItems) end,
}

-- 静态辅助方法
UI.Accordion.FAQ({
    { question = "问题1？", answer = "答案1" },
    { question = "问题2？", answer = "答案2" },
})
```

**方法**：`ToggleItem(id)`、`ExpandItem(id)`、`CollapseItem(id)`、`ExpandAll()`、`CollapseAll()`

#### Carousel

水平轮播/滑动画廊。

```lua
UI.Carousel {
    items = { widget1, widget2, widget3 },
    autoPlay = true,
    interval = 3,                 -- 秒
    showDots = true,
    showArrows = true,
    onChange = function(self, index) end,
}
```

#### Timeline

垂直时间线。

```lua
UI.Timeline {
    items = {
        { title = "步骤 1", description = "第一步", status = "completed" },
        { title = "步骤 2", description = "当前", status = "active" },
        { title = "步骤 3", description = "待处理", status = "pending" },
    },
}
```

#### Table

数据表格。

```lua
UI.Table {
    columns = {
        { key = "name", title = "姓名", width = 200 },
        { key = "age", title = "年龄", width = 80 },
        { key = "email", title = "邮箱", flexGrow = 1 },
    },
    data = {
        { name = "Alice", age = 30, email = "alice@test.com" },
        { name = "Bob", age = 25, email = "bob@test.com" },
    },
    onRowClick = function(self, row, index) end,
}
```

#### List

简单纵向列表。

```lua
UI.List {
    items = {
        { label = "项目 1", value = 1 },
        { label = "项目 2", value = 2 },
    },
    onItemClick = function(self, item, index) end,
}
```

---

### 6.7 浮层控件

这些控件渲染在其他内容之上，使用浮层系统。

#### Modal

模态对话框，带遮罩。

```lua
local modal = UI.Modal {
    title = "确认",
    size = "md",                  -- "sm"|"md"|"lg"|"xl"|"fullscreen"
    closeOnOverlay = true,        -- 点击遮罩关闭
    closeOnEscape = true,
    showCloseButton = true,
    onClose = function(self) end,
    onOpen = function(self) end,
}

-- 添加内容
modal:AddContent(UI.Label { text = "你确定吗？" })

-- 设置底部
modal:SetFooter(UI.Panel {
    flexDirection = "row", gap = 8,
    children = {
        UI.Button { text = "取消", onClick = function() modal:Close() end },
        UI.Button { text = "确定", variant = "primary", onClick = function() modal:Close() end },
    }
})

-- 打开/关闭
modal:Open()
modal:Close()

-- 静态辅助方法
UI.Modal.Confirm({
    title = "删除？",
    message = "此操作不可撤销。",
    onConfirm = function() end,
})

UI.Modal.Alert({
    title = "成功",
    message = "操作已完成。",
})
```

**方法**：`Open()`、`Close()`、`Toggle()`、`IsOpen()`、`SetTitle(t)`、`SetSize(s)`、`AddContent(w)`、`ClearContent()`、`SetFooter(w)`

#### Drawer

侧边抽屉面板。

```lua
UI.Drawer {
    position = "left",            -- "left"|"right"|"top"|"bottom"
    size = 300,                   -- 宽度/高度
    onClose = function(self) end,
}
```

**方法**：`Open()`、`Close()`、`Toggle()`

#### Popover

浮动内容面板，锚定到某个元素。

```lua
UI.Popover {
    placement = "bottom",         -- "top"|"bottom"|"left"|"right"|"top-start"|"top-end"|"bottom-start"|"bottom-end"
    trigger = "click",            -- "click"|"hover"|"focus"|"manual"
    content = "弹出内容",         -- 字符串或 function(nvg, x, y, w, h)
    title = "标题",
    showArrow = true,
    maxWidth = 300,
    onOpen = function(self) end,
    onClose = function(self) end,
}

-- 静态辅助方法
UI.Popover.Text("提示文本", props)
UI.Popover.WithTitle("标题", "内容", props)
UI.Popover.Confirm("确定？", onConfirm)
UI.Popover.Menu(items, props)
```

**方法**：`Open(anchorBounds)`、`Close()`、`Toggle(anchorBounds)`、`IsOpen()`

#### Toast

临时通知消息。

```lua
-- 静态 API（推荐）
UI.Toast.Show("已保存！", {
    duration = 3,                 -- 秒
    variant = "success",          -- "info"|"success"|"warning"|"error"
    position = "bottom",          -- "top"|"bottom"
})
```

---

## 7. 高级组件

位于 `UI/Components/`，是更高级的复合控件。

### VirtualList

高性能滚动列表，使用对象池。仅渲染可见项。

```lua
UI.VirtualList {
    data = items,                 -- 数据数组
    itemHeight = 40,              -- 固定项高度
    createItem = function()       -- 项控件工厂
        return UI.Panel { height = 40 }
    end,
    bindItem = function(widget, data, index)  -- 数据绑定
        -- 用 data 更新 widget
    end,
    onItemClick = function(data, index) end,
}
```

### ChatWindow

聊天 UI 组件。

```lua
UI.ChatWindow {
    messages = { ... },
    onSend = function(self, text) end,
}
```

### DragDropContext

拖拽系统。

```lua
UI.DragDropContext {
    onDragStart = function(item, source) end,
    onDrop = function(item, target) end,
}
```

### ItemSlot / ItemTooltip / InventoryManager / SkillTree

游戏专用 UI 组件，用于背包系统和技能树。

---

## 8. 主题系统

### 内置主题

| 名称 | 风格 | 字体 | 说明 |
|------|------|------|------|
| `"default-dark"` | 微体积感暗色 | Noto Sans SC | 深海军蓝背景、钢蓝主色、底部描边深度效果 |
| `"default-taptap"` | 扁平圆润亮色 | Resource Han Rounded CN | 薄荷绿背景、青色主色、1px 细边框、无阴影 |

```lua
-- 使用内置主题（字体自动跟随）
UI.Init({
    theme = "default-dark",
    scale = UI.Scale.DEFAULT,
})
UI.Init({
    theme = "default-taptap",
    scale = UI.Scale.DEFAULT,
})

-- 注册自定义主题
UI.Theme.RegisterTheme("my-theme", myThemeTable)
UI.Init({
    theme = "my-theme",
    scale = UI.Scale.DEFAULT,
})
```

### 默认主题颜色

```lua
local theme = UI.Theme.GetTheme()

-- 主色
theme.colors.primary              -- 蓝色  { 59, 130, 246, 255 }
theme.colors.secondary            -- 灰色  { 100, 116, 139, 255 }
theme.colors.success              -- 绿色  { 34, 197, 94, 255 }
theme.colors.error                -- 红色  { 239, 68, 68, 255 }
theme.colors.warning              -- 琥珀  { 245, 158, 11, 255 }

-- 文字颜色
theme.colors.text                 -- 深色文字
theme.colors.textSecondary        -- 浅色文字
theme.colors.disabledText         -- 禁用文字

-- 表面颜色
theme.colors.background           -- 应用背景
theme.colors.surface              -- 卡片/面板表面
theme.colors.border               -- 默认边框
theme.colors.disabled             -- 禁用背景
```

### 主题 API

```lua
-- 获取颜色
UI.Theme.Color("primary")           -- { r, g, b, a } 表
UI.Theme.NvgColor("primary")        -- NVGcolor，可直接用于 nvgFillColor()

-- 获取间距（基准像素）
UI.Theme.Spacing("xs")    -- 4
UI.Theme.Spacing("sm")    -- 8
UI.Theme.Spacing("md")    -- 16
UI.Theme.Spacing("lg")    -- 24
UI.Theme.Spacing("xl")    -- 32
UI.Theme.Spacing("xxl")   -- 48

-- 获取圆角（基准像素）
UI.Theme.Radius("none")   -- 0
UI.Theme.Radius("sm")     -- 4
UI.Theme.Radius("md")     -- 8
UI.Theme.Radius("lg")     -- 12
UI.Theme.Radius("xl")     -- 16

-- 字号（语义名称，返回 NanoVG 可用尺寸）
UI.Theme.FontSizeOf("display")    -- 24pt
UI.Theme.FontSizeOf("headline")   -- 18pt
UI.Theme.FontSizeOf("title")      -- 15pt
UI.Theme.FontSizeOf("subtitle")   -- 14pt
UI.Theme.FontSizeOf("bodyLarge")  -- 12pt
UI.Theme.FontSizeOf("body")       -- 11pt（默认正文）
UI.Theme.FontSizeOf("bodySmall")  -- 10pt
UI.Theme.FontSizeOf("small")      -- 9pt
UI.Theme.FontSizeOf("caption")    -- 8pt

-- 字体
UI.Theme.FontFace("sans", "bold")  -- 返回 NanoVG 字体名 "sans-bold"
UI.Theme.FontFamily()              -- 默认字体 "sans"

-- 自定义主题
UI.Theme.SetTheme(myTheme)
UI.Theme.ExtendTheme(UI.Theme.defaultTheme, { colors = { primary = {255, 0, 0, 255} } })

-- 主题注册与查询
UI.Theme.RegisterTheme("my-theme", myTheme)   -- 注册自定义主题
UI.Theme.GetRegisteredTheme("default-dark")   -- 获取已注册主题

-- 组件默认值
UI.Theme.ComponentStyle("Button")  -- { height = 44, borderRadius = 8, ... }
```

---

## 9. 事件系统

### 指针事件（鼠标 + 触摸统一）

鼠标使用 `pointerId = 0`，触摸使用触摸 ID。

```lua
UI.Panel {
    -- 指针回调（签名：function(event, widget)）
    onPointerEnter = function(event, widget) end,
    onPointerLeave = function(event, widget) end,
    onPointerDown = function(event, widget) end,
    onPointerUp = function(event, widget) end,
    onPointerMove = function(event, widget) end,
    onPointerCancel = function(event, widget) end,

    -- 点击回调（签名：function(widget, event)）
    onClick = function(widget, event) end,
}
```

#### PointerEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `type` | string | 事件类型 |
| `x`, `y` | number | 基准像素坐标 |
| `pointerId` | number | 0 = 鼠标，N = 触摸手指 |
| `pointerType` | string | "mouse" 或 "touch" |
| `button` | number | 0=左键，1=中键，2=右键 |
| `buttons` | number | 已按下按钮的位掩码 |
| `isPrimary` | boolean | 是否为主指针 |
| `pressure` | number | 0.0-1.0 |

**方法**：`event:StopPropagation()`、`event:PreventDefault()`、`event:IsTouch()`、`event:IsMouse()`、`event:IsPrimaryButton()`

### 手势事件

```lua
UI.Panel {
    -- 手势回调（签名：function(event, widget)）
    onTap = function(event, widget) end,
    onDoubleTap = function(event, widget) end,
    onLongPressStart = function(event, widget) end,
    onLongPressEnd = function(event, widget) end,
    onSwipe = function(event, widget) end,
    onSwipeLeft = function(event, widget) end,
    onSwipeRight = function(event, widget) end,
    onSwipeUp = function(event, widget) end,
    onSwipeDown = function(event, widget) end,
    onPanStart = function(event, widget) end,    -- 返回 true 表示处理
    onPanMove = function(event, widget) end,
    onPanEnd = function(event, widget) end,
    onPinchStart = function(event, widget) end,  -- 多点触摸
    onPinchMove = function(event, widget) end,
    onPinchEnd = function(event, widget) end,
}
```

#### GestureEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `type` | string | 手势类型 |
| `x`, `y` | number | 坐标 |
| `target` | Widget | 触发手势的控件 |
| `direction` | string | 滑动方向（"left"/"right"/"up"/"down"） |
| `velocity` | number | 滑动速度（px/ms） |
| `deltaX`, `deltaY` | number | 拖拽帧增量 |
| `totalDeltaX`, `totalDeltaY` | number | 拖拽总增量（从起点累计） |
| `scale` | number | 缩放比例（捏合手势） |

### 焦点与键盘

```lua
UI.TextField {
    onFocus = function(widget) end,
    onBlur = function(widget) end,
}

-- 在自定义控件中重写：
function MyWidget:OnKeyDown(key) end
function MyWidget:OnKeyUp(key) end
function MyWidget:OnTextInput(text) end
```

### 命令式事件监听（OnEvent / OffEvent）

除了在构造时通过 props 传入回调外，还可以在构造后通过 `OnEvent` / `OffEvent` 命令式注册/移除事件监听器：

```lua
local btn = UI.Button { text = "Hover me" }

-- 注册事件
btn:OnEvent("pointerenter", function(event, widget)
    widget:SetStyle({ scale = 1.1 })
end)
btn:OnEvent("pointerleave", function(event, widget)
    widget:SetStyle({ scale = 1.0 })
end)

-- 移除特定处理器
local handler = function(event, widget) print("clicked") end
btn:OnEvent("click", handler)
btn:OffEvent("click", handler)  -- 移除指定处理器
btn:OffEvent("click")           -- 移除 click 的所有处理器
```

**支持的事件名**：`pointerenter`、`pointerleave`、`pointerdown`、`pointerup`、`pointermove`、`pointercancel`、`click`、`tap`、`doubletap`、`longpressstart`、`longpressend`、`swipe`、`panstart`、`panmove`、`panend`、`pinchstart`、`pinchmove`、`pinchend`、`focus`、`blur`

> **零开销设计**：不使用 OnEvent 时无任何性能影响（`eventListeners_` 默认为 nil）。

### 鼠标滚轮

```lua
-- 在自定义控件中重写：
function MyWidget:OnWheel(dx, dy) end
```

### 指针事件控制

```lua
-- 控制哪些控件接收事件
UI.Panel {
    pointerEvents = "auto",       -- 默认：接收事件
}
UI.Label {
    pointerEvents = "none",       -- 事件穿透（Label 的默认值）
}
-- "box-none"：控件自身不接收事件，但子控件可以
-- "box-only"：控件自身接收事件，子控件不接收
```

### 游戏与 UI 输入协调

```lua
-- 判断指针是否在 UI 控件上方（用于游戏层屏蔽输入）
if UI.IsPointerOverUI() then
    return  -- 指针在 UI 上，跳过游戏输入处理
end
-- 否则处理游戏输入（移动、射击等）
```

### 全局输入监听

```lua
-- 订阅全局输入事件（控件树之外）
local id = UI.Input.On("PointerDown", function(event)
    print("全局按下", event.x, event.y)
end)

UI.Input.Off("PointerDown", id)   -- 取消订阅
```

---

## 10. 渲染

### 坐标系

- **基准像素（Base Pixels）**：代码中直接使用的逻辑坐标单位
- **物理像素（Physical Pixels）**：屏幕实际像素，通过 `nvgScale(scale, scale)` 自动转换

### 分辨率缩放（scale）

`scale` 定义基准像素到物理像素的换算：**物理像素 = 基准像素 × scale**

由 `UI.Init` 的 `scale` 选项决定，支持两种形式：

- **固定值**（`number`）：缩放系数固定不变
- **函数公式**（`function`）：分辨率变化时重新计算，允许实现更复杂的缩放修正逻辑

缺省 `scale = 1`，无缩放，直接采用物理像素。

### Scale 预设

| 预设 | 说明 |
|------|------|
| **`UI.Scale.DEFAULT`**<br>`UI.Scale.DPR_DENSITY_ADAPTIVE` | **要求默认使用**。遵循 Web/CSS 像素标准，1基准像素 = 1CSS像素，小屏 UI 密度自适应 |
| `UI.Scale.DPR` | 采用DPR缩放策略，遵循 Web/CSS 像素标准，1基准像素 = 1CSS像素，跨设备视觉大小一致 |
| `UI.Scale.DESIGN_RESOLUTION(w, h)` | 设计分辨率模式，按设计稿尺寸开发。仅用户明确要求时使用 |

```lua
UI.Init({
    theme = "default-dark",
    scale = UI.Scale.DEFAULT -- 默认，即 UI.Scale.DPR_DENSITY_ADAPTIVE
})
```

### 跨平台分辨率适配

#### DPR 缩放策略

使用 DPR 作为 scale，1 基准像素 = 1 CSS 像素。遵循 Web/CSS 常识尺寸（按钮高度 40-48px、字体 14-16px、间距 8/16/24px）。

- ✅ 与 Web 开发经验一致，跨设备视觉大小一致
- ❌ 小屏设备上 UI 元素占屏比过高，视觉拥挤

```lua
UI.Scale.DPR = function()
    return graphics:GetDPR()
end
```

#### DPR_DENSITY_ADAPTIVE 缩放策略（默认）

基于 DPR，增加小屏密度适配。动态调节小屏的 UI 视觉密度，优化 DPR 的"小屏拥挤"问题：

```lua
UI.Scale.DPR_DENSITY_ADAPTIVE = function()
    local dpr = graphics:GetDPR()
    local shortSide = math.min(graphics.width, graphics.height) / dpr
    local PC_REF = 720  -- PC 参考短边 (CSS pixels)

    local densityFactor = math.sqrt(shortSide / PC_REF)
    densityFactor = math.max(0.625, math.min(densityFactor, 1.0))  -- clamp [0.625, 1.0]

    return dpr * densityFactor
end
```

- 小屏 `densityFactor < 1` → scale 减小 → 逻辑分辨率增大 → UI 元素占屏比降低
- `sqrt` 平滑过渡
- clamp 下限 0.625：48px 按钮 × 0.625 = 30px，保证最低触摸可用性

#### 自定义缩放策略

预设策略难以覆盖所有场景，可通过自定义函数进行针对性调整：

```lua
UI.Init({
    theme = "default-dark",
    scale = function()
        local dpr = graphics:GetDPR()
        -- 你的自定义逻辑
        return dpr * yourFactor
    end,
})
```

常见自定义场景：
- 特定设备的微调修正
- 横竖屏不同的缩放策略
- 特定分辨率的特化处理

### 转屏

游戏内切换横竖屏用 `common.setDeviceOrientation()`，只支持 **Android / iOS**。桌面、WASM、鸿蒙走 `onError`，`errMsg` 为 `"unsupported"`。

```lua
common.setDeviceOrientation({
    value = "landscape", -- "portrait" 或 "landscape"
    onSuccess = function() end, -- 只表示请求已被接受
    onError = function(err) end, -- err.errMsg: "invalid value" | "unsupported" | "rejected"
})
```

- `onSuccess` 不代表画面尺寸已经变化。UI 库会在实际宽高变化后自动重算 `scale` 和布局；自己缓存了宽高的逻辑，要在 `ScreenMode` 里刷新。
- `"landscape"` 允许左右两个横屏方向，遵循系统旋转锁，不能指定某一侧。
- 监听方向变化：`common.onDeviceOrientationChange(function(res) end)`。只保留一个监听，新的覆盖旧的，传 `nil` 注销。`res.value` 为 `"portrait"`、`"landscape"`、`"landscapeReverse"`（仅上报，不能设置）或 `"unknown"`。注册时不会立刻回调当前方向。
- 不要用 `graphics:SetOrientations()`，该接口已禁用；`graphics.orientations` 只读。

### 控件渲染

```lua
function MyWidget:Render(nvg)
    -- 获取基准像素坐标
    local l = self:GetAbsoluteLayout()  -- { x, y, w, h }

    -- 背景（阴影 + 颜色 + 边框）
    self:RenderFullBackground(nvg)

    -- 文字
    nvgFontFace(nvg, UI.Theme.FontFace("sans", "normal"))
    nvgFontSize(nvg, UI.Theme.FontSize(12))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, UI.Theme.NvgColor("text"))
    nvgText(nvg, l.x + 8, l.y + l.h / 2, "Hello")

    -- 图形
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 8)
    nvgFillColor(nvg, nvgRGBA(255, 0, 0, 128))
    nvgFill(nvg)

    -- 裁剪
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
    -- ... 渲染被裁剪的内容 ...
    nvgRestore(nvg)
end
```

### 颜色格式

所有颜色为 RGBA 数组：`{ r, g, b, a }`，值范围 0-255。

```lua
{ 255, 0, 0, 255 }         -- 红色，完全不透明
{ 0, 0, 0, 128 }           -- 黑色，50% 透明
{ 255, 255, 255, 0 }       -- 完全透明
```

### 图片渲染

```lua
-- 任意控件上设置背景图
UI.Panel {
    backgroundImage = "Images/bg.png",
    backgroundFit = "cover",      -- "fill"|"contain"|"cover"
}
```

> **设了 `backgroundImage` 就不要再设 `backgroundColor`（除非确有需要）。** 两者会同时生效、底色画在图片下层：图片有透明区、或 `backgroundFit = "contain"` 等比留白时，底色会从透明/留白处透出，常表现为头像/卡片周围一圈丑陋的"色块底座"。需要图片缺失时的纯色兜底，再显式加 `backgroundColor`；否则只留 `backgroundImage`。

```lua
-- 九宫格（用于可拉伸的 UI 元素）
UI.Panel {
    backgroundImage = "Images/frame.png",
    backgroundFit = "sliced",
    backgroundSlice = { top = 10, right = 10, bottom = 10, left = 10 },
}

-- 图片叠色（乘法混合，用于压暗/变色）
UI.Panel {
    backgroundImage = "Images/portrait.png",
    backgroundFit = "cover",
    imageTint = { 115, 115, 115, 255 },  -- 压暗到 ~45%
}
-- imageTint 默认 nil（不叠色），白色 {255,255,255,255} 等同于无叠色
-- 支持 hex 字符串：imageTint = "#737373"
-- 支持 transition 动画
```

---

## 11. 常用模式

### 事后更新 widget 的两种模式

urhox-libs/UI 是声明式构建（一次性 build 树 → SetRoot）。事后修改文字、可见性、样式时，有两种合法模式，按场景选用：

#### 模式 A：保留 local 引用

适合**单一/少量动态元素**（如一个 FPS Label、一个 HP 条），或元素在同一函数作用域内被创建和更新。引用保留在 local 变量里，后续直接调方法：

```lua
local fpsLabel = UI.Label { text = "FPS: --", fontSize = 14 }

local hud = UI.Panel {
    children = { fpsLabel }   -- 引用本身可以直接作为 children
}
UI.SetRoot(hud)

-- 后续直接调方法
fpsLabel:SetText("FPS: 60")
fpsLabel:SetVisible(false)
```

**优点**：LSP 知道 `fpsLabel` 是 `Label` 类型，方法补全准确；变量名拼错立刻报错。
**适用**：动态元素 ≤ 几个、创建和更新在同一文件作用域。

#### 模式 B：id 标签 + 父控件 :FindById 查找

适合**HUD 元素较多**、CreateUI 和 Update 函数分散、或跨函数访问。给控件加 `id` 字段，事后用父控件的 `:FindById(id)` 实例方法递归查找：

```lua
local uiRoot = UI.Panel {
    children = {
        UI.Label { id = "score", text = "Score: 0" },
        UI.Label { id = "fps",   text = "FPS: --" },
        UI.ProgressBar { id = "hp", value = 100, max = 100 },
    }
}
UI.SetRoot(uiRoot)

-- 跨函数访问，无需把每个引用传来传去
-- ⚠️ FindById 返回 Widget|nil：调子类方法（SetText/SetValue 等）前必须用行内 --[[@as 类型?]] 收窄，
--    否则 LSP 报 undefined-field ERROR（基类方法如 SetVisible/Hide 无需收窄）
function UpdateHUD(state)
    local score = uiRoot:FindById("score") --[[@as Label?]]
    if score then score:SetText("Score: " .. state.score) end

    local fps = uiRoot:FindById("fps") --[[@as Label?]]
    if fps then fps:SetText("FPS: " .. state.fps) end

    local hp = uiRoot:FindById("hp") --[[@as ProgressBar?]]
    if hp then hp:SetValue(state.hp) end
end
```

**优点**：跨函数访问不需要维护一堆 module-level 引用变量；扩展时只需在创建处加 `id`。
**注意**：`FindById` 返回 `Widget|nil`，LSP 不知道具体子类型（如 Label 还是 Button）。**调子类特有方法（`SetText`/`SetValue`/`SetFontColor` 等）前必须在表达式行尾加 `--[[@as 类型?]]` 收窄**（EmmyLuaLS 与 LuaLS 都支持），否则 `undefined-field` 会被静态检查报为 ERROR；只调基类 Widget 方法（`SetVisible`/`Hide`/`Show`/`SetStyle`）则无需收窄。id 字符串写错运行时返回 nil。
**适用**：HUD 元素多、跨函数/跨模块访问、动态构造场景。

> `FindById` 是 Widget 实例方法（`someWidget:FindById(id)`），从该节点向下递归查找。完整签名见 [`Widget.lua`](../../urhox-libs/UI/Core/Widget.lua) 中的 `function Widget:FindById`。脚手架 `templates/scaffold-2d.lua` 和 `scaffold-2d-physics.lua` 用模式 B，`scaffold-3d-scene.lua` 单 HUD 元素用模式 A，都可参考。

### 全屏布局

```lua
local root = UI.Panel {
    width = "100%",
    height = "100%",
    flexDirection = "column",
    children = {
        -- 顶栏
        UI.Panel {
            height = 60,
            flexDirection = "row",
            alignItems = "center",
            paddingHorizontal = 16,
            backgroundColor = UI.Theme.Color("primary"),
            children = {
                UI.Label { text = "我的应用", fontColor = {255,255,255,255}, fontWeight = "bold" },
            }
        },

        -- 内容区（填充剩余空间）
        UI.ScrollView {
            flexGrow = 1,
            flexBasis = 0,        -- 重要：ScrollView 滚动必须
            children = { contentPanel },
        },

        -- 底栏
        UI.Panel {
            height = 50,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label { text = "底栏" },
            }
        },
    }
}

UI.SetRoot(root)
```

### 水平列表

```lua
UI.Panel {
    flexDirection = "row",
    gap = 8,
    flexWrap = "wrap",            -- 自动换行
    children = {
        UI.Chip { label = "A" },
        UI.Chip { label = "B" },
        UI.Chip { label = "C" },
    }
}
```

### 表单布局

```lua
UI.Panel {
    flexDirection = "column",
    gap = 16,
    padding = 20,
    children = {
        UI.Label { text = "用户名", fontWeight = "bold" },
        UI.TextField {
            placeholder = "请输入用户名",
            onChange = function(self, v) username = v end,
        },

        UI.Label { text = "密码", fontWeight = "bold" },
        UI.TextField {
            placeholder = "请输入密码",
            password = true,
            onChange = function(self, v) password = v end,
        },

        UI.Button {
            text = "登录",
            variant = "primary",
            onClick = function() login(username, password) end,
        },
    }
}
```

### Modal 带内容

```lua
local modal = UI.Modal {
    title = "编辑资料",
    size = "md",
    onClose = function(self)
        self:Destroy()            -- 关闭时销毁
    end,
}

modal:AddContent(UI.Panel {
    flexDirection = "column",
    gap = 12,
    children = {
        UI.TextField { placeholder = "姓名" },
        UI.TextField { placeholder = "邮箱" },
    }
})

modal:SetFooter(UI.Panel {
    flexDirection = "row",
    justifyContent = "flex-end",
    gap = 8,
    children = {
        UI.Button { text = "取消", onClick = function() modal:Close() end },
        UI.Button { text = "保存", variant = "primary", onClick = function() save(); modal:Close() end },
    }
})

modal:Open()
```

### 浮层生命周期

浮层控件（Modal、Dropdown、Popover、Drawer、DatePicker、TimePicker、ColorPicker）使用浮层栈管理：

```lua
-- 框架自动处理：
-- widget:Open() → UI.PushOverlay(widget)
-- widget:Close() → UI.PopOverlay(widget)

-- 使用内置控件时，不需要手动调用 PushOverlay/PopOverlay。
```

---

## 12. 常见陷阱与解决方案

### 陷阱 1：忘记 UI.SetRoot()

```lua
-- 错误：什么都不会渲染！
local root = UI.Panel { ... }
-- 忘记了 UI.SetRoot(root)

-- 正确：
local root = UI.Panel { ... }
UI.SetRoot(root)                 -- 必须调用！
```

### 陷阱 2：子元素溢出（flexShrink 默认为 0）

```lua
-- 错误：250px 的子元素放在 200px 的容器里 → 溢出
local container = UI.Panel { height = 200 }
container:AddChild(UI.Panel { height = 150 })
container:AddChild(UI.Panel { height = 100 })

-- 正确：给子元素设置 flexShrink = 1
container:AddChild(UI.Panel { height = 150, flexShrink = 1 })
container:AddChild(UI.Panel { height = 100, flexShrink = 1 })
```

### 陷阱 3：ScrollView 不滚动

```lua
-- 错误：ScrollView 没有高度约束
UI.ScrollView {
    flexGrow = 1,
    -- 缺少 flexBasis = 0！
}

-- 正确：
UI.ScrollView {
    flexGrow = 1,
    flexBasis = 0,               -- flex 布局下滚动必须设为 0
}
-- 或使用固定高度：
UI.ScrollView {
    height = 400,
}
```

> **自动修正**：ScrollView 检测到 `flexGrow > 0` 但未设 `flexBasis` 时，会自动将 `flexBasis` 设为 0 并打印提示信息。因此即使忘记设置也不会完全不工作，但建议显式设置以消除控制台提示。

### 陷阱 4：混淆 variant 和 color

```lua
-- 错误：variant="primary"（primary 是颜色，不是样式变体！）
UI.Chip { label = "标签", variant = "primary" }

-- 正确：variant 控制外观样式，color 控制颜色
UI.Chip { label = "标签", variant = "filled", color = "primary" }

-- Button 的 variant 包含了颜色语义，这是正确的：
UI.Button { text = "确定", variant = "primary" }
```

各控件的 variant 取值：
- **Button**：`"primary"` | `"secondary"` | `"danger"` | `"success"`
- **Chip**：`"filled"` | `"outlined"` | `"soft"`（color 是独立属性）
- **Card**：`"elevated"` | `"outlined"` | `"filled"`
- **Tabs**：`"line"` | `"enclosed"` | `"pills"`
- **Accordion**：`"default"` | `"outlined"` | `"separated"`
- **Alert**：使用 `severity` 而非 `variant`
- **Badge/ProgressBar**：`"primary"` | `"success"` | `"warning"` | `"error"`

### 陷阱 5：事件回调签名错误

```lua
-- onClick 签名：function(widget, event)
onClick = function(self, event)
    print(self.props.text)
end

-- Pointer/Gesture 回调签名：function(event, widget)
onPointerDown = function(event, widget)
    print(event.x, event.y)
end
onTap = function(event, widget)
    print("点击了")
end
```

### 陷阱 6：百分比宽度无效

```lua
-- 错误：父容器没有宽度，50% 无从计算
UI.Panel {
    children = { UI.Panel { width = "50%" } }
}

-- 正确：父容器必须有明确的或可推导的宽度
UI.Panel {
    width = "100%",
    children = { UI.Panel { width = "50%" } }  -- 父容器的 50%
}
```

### 陷阱 7：Border-Box 误解

```lua
-- Yoga 使用 border-box：padding 包含在 width 内
UI.Panel { width = 100, padding = 20 }
-- 总宽度 = 100px（不是 140px）
-- 内容区域 = 60px
```

### 陷阱 8：销毁浮层控件

```lua
-- 先关闭再销毁
modal:Close()     -- 从浮层栈移除
modal:Destroy()   -- 然后销毁

-- 或在 onClose 中处理：
UI.Modal {
    onClose = function(self)
        self:Destroy()
    end
}
```

### 陷阱 9：maxHeight 导致 flexGrow 子元素坍缩为 0

```lua
-- ❌ 错误：panel 用 maxHeight，ScrollView 高度变成 0，只看到 header
UI.Panel {
    maxHeight = "85%",                          -- height 默认 auto（不确定尺寸）
    children = {
        UI.Panel { height = 56 },              -- header: 56px
        UI.ScrollView { flexGrow = 1, flexBasis = 0 },  -- 期望填满剩余 → 实际高度 = 0！
    }
}

-- ✅ 正确：用 height 替代 maxHeight
UI.Panel {
    height = "85%",                             -- 确定尺寸，flexGrow 可分配剩余空间
    children = {
        UI.Panel { height = 56 },
        UI.ScrollView { flexGrow = 1, flexBasis = 0 },  -- 得到 85% - 56px ✓
    }
}
```

**原因**：`flexGrow` 需要父容器有**确定的主轴尺寸**才能计算剩余空间。`maxHeight` 只是上界约束，不构成确定尺寸（definite size）——Yoga 无法确定可分配空间，`flexGrow` 分到 0。

**规则**：当容器内有 `flexGrow` 子元素时，父容器必须用 `height`（或 `width`），不能用 `maxHeight`（或 `maxWidth`）。

> 这是 Flexbox 布局模型的固有限制，CSS 浏览器中同样存在。Flutter/SwiftUI 使用约束传递模型，不受此限制。

---

## 13. 布局辅助工具

### UI.Row / UI.Column

```lua
-- 水平布局（flexDirection = "row"）
UI.Row {
    gap = 8,
    children = { widget1, widget2, widget3 },
}

-- 垂直布局（flexDirection = "column"）
UI.Column {
    gap = 8,
    children = { widget1, widget2, widget3 },
}
```

### UI.Spacer

```lua
-- 弹性空白（将兄弟元素推向两端）
UI.Row {
    children = {
        UI.Label { text = "左" },
        UI.Spacer(),              -- 填充可用空间
        UI.Label { text = "右" },
    }
}
```

### UI.ButtonGroup

```lua
-- 自动换行的按钮组（防止按钮文本被截断）
UI.ButtonGroup {
    UI.Button { text = "保存", variant = "primary" },
    UI.Button { text = "取消" },
    UI.Button { text = "一个很长的按钮文本" },
}
```

当按钮总宽度超出容器时自动换行，每个按钮保持完整文本显示。底层是 `flexDirection = "row"` + `flexWrap = "wrap"` 的 Panel。可通过 `gap`（默认 8）等属性自定义间距。

### UI.Box

```lua
-- 固定尺寸空盒子（用于间距或占位）
UI.Box(100, 50)                   -- 100x50 的盒子
```

---

## 附录：控件完整列表

| # | 控件 | 分类 | 访问方式 |
|---|------|------|----------|
| 1 | Panel | 布局 | `UI.Panel` |
| 2 | Label | 布局 | `UI.Label` |
| 3 | Divider | 布局 | `UI.Divider` |
| 4 | SafeAreaView | 布局 | `UI.SafeAreaView` |
| 5 | ScrollView | 布局 | `UI.ScrollView` |
| 6 | SimpleGrid | 布局 | `UI.SimpleGrid` |
| 7 | Button | 输入 | `UI.Button` |
| 8 | TextField | 输入 | `UI.TextField` |
| 9 | Checkbox | 输入 | `UI.Checkbox` |
| 10 | Toggle | 输入 | `UI.Toggle` |
| 11 | Slider | 输入 | `UI.Slider` |
| 12 | Stepper | 输入 | `UI.Stepper` |
| 13 | Rating | 输入 | `UI.Rating` |
| 14 | FileUpload | 输入 | `UI.FileUpload` |
| 15 | Dropdown | 选择 | `UI.Dropdown` |
| 16 | DatePicker | 选择 | `UI.DatePicker` |
| 17 | TimePicker | 选择 | `UI.TimePicker` |
| 18 | ColorPicker | 选择 | `UI.ColorPicker` |
| 19 | Calendar | 选择 | `UI.Calendar` |
| 20 | Menu | 选择 | `UI.Menu` |
| 21 | Tree | 选择 | `UI.Tree` |
| 22 | Card | 展示 | `UI.Card` |
| 23 | Badge | 展示 | `UI.Badge` |
| 24 | Chip | 展示 | `UI.Chip` |
| 25 | Avatar | 展示 | `UI.Avatar` |
| 26 | Alert | 展示 | `UI.Alert` |
| 27 | Tooltip | 展示 | `UI.Tooltip` |
| 28 | Skeleton | 展示 | `UI.Skeleton` |
| 29 | RichText | 展示 | `UI.RichText` |
| 30 | ProgressBar | 展示 | `UI.ProgressBar` |
| 31 | Tabs | 导航 | `UI.Tabs` |
| 32 | Breadcrumb | 导航 | `UI.Breadcrumb` |
| 33 | Pagination | 导航 | `UI.Pagination` |
| 34 | Accordion | 容器 | `UI.Accordion` |
| 35 | Carousel | 容器 | `UI.Carousel` |
| 36 | Timeline | 容器 | `UI.Timeline` |
| 37 | Table | 数据 | `UI.Table` |
| 38 | List | 数据 | `UI.List` |
| 39 | Modal | 浮层 | `UI.Modal` |
| 40 | Drawer | 浮层 | `UI.Drawer` |
| 41 | Popover | 浮层 | `UI.Popover` |
| 42 | Toast | 浮层 | `UI.Toast` |

### 高级组件

| # | 组件 | 访问方式 |
|---|------|----------|
| 1 | VirtualList | `UI.VirtualList` |
| 2 | DragDropContext | `UI.DragDropContext` |
| 3 | ItemSlot | `UI.ItemSlot` |
| 4 | ItemTooltip | `UI.ItemTooltip` |
| 5 | InventoryManager | `UI.InventoryManager` |
| 6 | SkillTree | `UI.SkillTree` |
| 7 | ChatWindow | `UI.ChatWindow` |

---

### UI 风格 Skills
引擎提供多套预置 UI 风格主题，每套包含完整的配色、字体、圆角、阴影等设计规范和代码模板。可用风格 skill 如 `ui-astroon`、`ui-brawlforge`、`ui-pixelforge` 等，创建和优化 UI 时应查阅这些 skill 选择合适的风格。

**记住**: 当用户请求带有风格特征的 UI 时，禁止自己编造，必须先查询是否有对应的 skill！

*基于 UrhoX UI Library v1.2.0 生成（含 CSS Enhancement Phase 0-3）*
