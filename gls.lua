-- =============================================================================
-- 警告: 宏运行期间不要切屏!
-- 游戏切屏（切出游戏到其它应用）时，请 **先停止宏运行**
-- Mac 电脑上如果没把本脚本设置为 “通用配置文件”，在宏运行期间切屏会导致 GHub 崩溃，需要重启 GHub 才能恢复
-- 不推荐把本脚本文件设置为 “通用配置文件” - 其它场景根本用不到这个脚本
-- =============================================================================


-- =============================================================================
-- 游戏键位配置部分
-- =============================================================================
local Keys = {
  --- 游戏键位绑定
  -- 技能栏位
  ActionBarSkill_1 = "1",
  ActionBarSkill_2 = "2",
  ActionBarSkill_3 = "3",
  ActionBarSkill_4 = "4",
  -- 强制站立
  ForceStand       = "c",
  -- 强制移动
  ForceMove        = "z",
  -- 回城
  TownPortal       = "t",

  --- 脚本常用键位码
  Enter            = "enter",
  Esc              = "escape",
}

-- =============================================================================
-- 鼠标按键和键盘控制键
-- =============================================================================
local Mouse = {
  --- 鼠标键位码
  -- 左键
  -- ⚠️：持续按住或高频率点击左键会打断很多技能的释放以及引导技能的触发(比如 DeathNova)，
  -- ⚠️：除左键放置主要伤害技能外应尽量避免这种情况。
  Left = 1,
  -- 中键
  Middle = 2,
  -- 右键
  Right = 3,
  -- 其它 `Gx` 功能键的编码从 `4` 开始，不同型号鼠标功能键的数量有所不同
}

--- 控制键列表
-- 可在宏运行期间读取到按下状态，用于控制宏状态的按键
-- 各种取舍后只有这几个比较可用，“不要改动”
local ControlKeys = {
  -- 一般用来在宏任务运行期间按下此键，触发某个宏状态或逻辑的转换
  Ctrl = "lctrl",
  -- 一般用来在宏任务运行期间按下此键，触发某个宏状态或逻辑的转换
  Shift = "lshift",
  -- 一般用来在鼠标按键触发宏任务时，通过判断此键的按下状态动态分流要执行的任务
  -- (宏任务运行期间慎用此键，`alt` 组合其它键可能会对游戏运行造成巨大影响)
  Alt = "lalt",

  -- 鼠标中键为固定功能键，不再支持绑定其它事件
  -- MouseMiddle = Mouse.Middle,
  -- 为鼠标右键再绑定特定功能的场景很少，不再支持绑定其它事件
  -- MouseRight = Mouse.Right,
}

-- =============================================================================
--  宏脚本运行时配置 **不要随意改动**
-- =============================================================================
local Config = {
  -- D3 帧时间: 1s/60f = 16.666...ms，通常四舍五入为：`16.67`
  -- 为提高精度和兼顾效率，设定最小时钟周期按 120fps 来计算：1s/120f = 8.333...ms, 通常取值为：`8.33`
  -- 但为了保证 2 个时钟周期后能够覆盖 1f 的时间，所以最小时钟周期向上取整为: `8.34`
  -- PS: 由于 `GetRunningTime` 返回值的最大精度为 1ms, 所以帧时间和最小时钟周期的 *小数部分意义不大*
  TickTime = 8.34,
  FrameTime = 16.67,
  -- 操作系统平台，支持 `macOS` 和 `Windows` 两个值
  os = "macOS",
  -- mac 笔记本分辨率(基础分辨率)
  macResolution = {
    width = 1440,
    height = 900,
  },
  -- Windows 坐标位置
  windowsCoord = {
    endX = 65535,
    endY = 65535,
  },
  -- 是否开启 Debug 模式
  -- (Debug 模式会自动输出一些运行过程日志)
  Debug = false,
}
-- 防止误操作而意外触发脚本运行的防抖时间(时间越短越没用、越长越容易拦截正常操作)
Config.DebounceTime = Config.FrameTime * 24

-- 常见的几种 “按键保持或间隔” 时间片
local Timing = {
  -- 1f(~16ms): 最小时间间隔 - 几乎所有场景下都不用这么快
  MS_1F = Config.FrameTime,
  -- 3f(~50ms): 无缝点击，以不高于此时间间隔按技能时 “技能栏无闪烁” 约等于一直按住
  MS_3F = Config.FrameTime * 3,
  -- 6f(~100ms): 普通点击，适合所有模拟人类快速连点的情况，比如 “自动左键攻击”、”连续按下两个技能“ 等场景的时间间隔
  -- 以此频率点击左键进行走路时，人物动作也会比较顺滑不鬼畜
  MS_6F = Config.FrameTime * 6,
  -- 9f(~150ms): 比较适合模拟人的按键动作
  MS_9F = Config.FrameTime * 9,
  -- 12f(~200ms): 慢速普通点击，适合类似 6f 但希望触发频率更低或需要等待更久的场景
  -- 类似 TP 这类需要 “人物站稳” 才能正常触发的技能一般也要等 12f 才能比较稳定的触发
  MS_12F = Config.FrameTime * 12,
  -- 20f(~333ms): “长按”动作，类似野蛮人的踩这种有长动画的技能一般至少需要按住 20f 才能正常触发(不被其它动作打断)
  MS_20F = Config.FrameTime * 20,
  -- 更长的按下/等待时间，直接用毫秒数表达更方便直观
  -- 回城取消时间(～3800ms)：回城有 4s 施法时间，这里预留 12f 时间窗口供打断施法以取消回城
  TownPortal = 3800
}

-- =============================================================================
--  宏框架核心
-- =============================================================================
-- 常用类型定义，用来判断一些值是不是期望类型
local Types = {
  Number = "number",
  String = "string",
  Boolean = "boolean",
  Table = "table",
  Function = "function",
  KeyPressed = "pressed",
  KeyReleased = "released"
}

Gm = {
  -- Gm 是否处于运行中
  _running = false,
  -- Gm 运行时间戳
  _timestamp = 0,

  -- 记录上次触发运行状态改变的事件信息，包含事件的 `key` 和 `type`
  _lastTaskEvent = {},
  -- 当前 task 监听的控制按键事件
  _controlEvents = {},
  -- 当前 task 注册的定时器
  _timers = {},
  -- 当前 task 可存取的数据
  _state = {},
  -- 为鼠标按键分配的 Task 列表
  _mouseAssignments = {},

  -- 当前 task 的 Action 配置
  actions = {},
  -- 当 Gm 结束当前 task 之前会自动调用的一个方法，可用于清理 task 运行状态等操作
  teardown = function() end,
}

function Gm:log(...)
  if Config.Debug ~= true then
    return
  end

  local msg = "[Gm] "
  local args = table.pack(...)
  for i = 1, args.n do
    local v = args[i]
    msg = msg .. " " .. tostring(v)
  end

  msg = msg .. "\n"
  OutputLogMessage(msg)
end

function Gm:getCurrentTime()
  return GetRunningTime()
end

function Gm:roundNumber(num)
  return math.floor(num + 0.5)
end

function Gm:sleep(ms)
  if type(ms) ~= Types.Number or ms < 0 then
    ms = Config.TickTime
  end
  -- 由于 `Sleep()` 不支持小数和负数(各种 0 值除外），这里需要向上取整
  -- 向上取整可以保证 “至少 sleep 多少时间”，逻辑上也比较合理
  ms = math.ceil(ms)
  Sleep(ms)
end

-- 是否一个可用按键 - 包括鼠标键、普通键盘键、键盘控制键等 GHub 支持的所有按键
-- (不检查是否真的可用)
function Gm:isUsableKey(k)
  return type(k) == Types.String or type(k) == Types.Number
end

-- 是否鼠标键
-- (不检查是否真的可用)
function Gm:isMouseButton(k)
  return type(k) == Types.Number
end

-- 判断一个键是不是控制键
function Gm:isControlKey(key)
  for _, k in pairs(ControlKeys) do
    if k == key then
      return true
    end
  end

  return false
end

-- 注：GHub 只支持获取 `ControlKeys` 的按下状态
-- 只支持 `ControlKeys` 中定义的键
function Gm:isControlKeyPressed(k)
  if Gm:isControlKey(k) == false then
    return false
  end

  if Gm:isMouseButton(k) then
    return IsMouseButtonPressed(k)
  else
    return IsModifierPressed(k)
  end
end

-- 根据相关控制按键的按下状态和 Task 状态，来确定是否需要继续运行
-- 注：长时间循环(需要手工停止)的宏脚本里，一定要调用这个方法进行宏开关的状态判断
-- 因为会运行在长时间运行的简单脚本里，所以这里不对 `Gm.actions`,`Gm._controlEvents` 等属性做是否为空的检测
function Gm:shouldContinue()
  if Gm._running ~= true then
    return false
  end

  if IsMouseButtonPressed(Mouse.Middle) then
    -- 每次触发 `Gm:stop()` 前都要记录 `_lastTaskEvent`
    Gm:_updateLastTaskEvent(Mouse.Middle, Types.KeyPressed)
    return false
  end

  return true
end

-- 注：
-- `PressKey` 为一个异步操作，立即调用 `ReleaseKey` 可能会无法成功 Release Key
-- 最好直接使用 `PressAndReleaseKey` 或在 `PressKey` 和 `ReleaseKey` 之间加上 `Sleep` 延时
function Gm:pressKey(k)
  if Gm:isUsableKey(k) == false then
    return
  end

  if Gm:isMouseButton(k) then
    PressMouseButton(k)
  else
    PressKey(k)
  end
  Gm:log("pressKey", k)
end

function Gm:releaseKey(k)
  if Gm:isUsableKey(k) == false then
    return
  end

  if Gm:isMouseButton(k) then
    -- 只支持 `1 ~ 5` 的鼠标按键, 并且不支持一次处理多键
    ReleaseMouseButton(k)
  else
    ReleaseKey(k)
  end
end

function Gm:clickKey(k)
  if Gm:isUsableKey(k) == false then
    return
  end

  if Gm:isMouseButton(k) then
    PressAndReleaseMouseButton(k)
  else
    PressAndReleaseKey(k)
  end
  Gm:log("clickKey", k)
end

-- 释放所有可能被按下的按键
-- 不设为私有('_'), 在不依赖 action 的脚本里也会用到
function Gm:releaseAllKeys()
  -- 释放所有鼠标按键
  for _, k in pairs(Mouse) do
    if type(k) == Types.Number and k >= 1 and k <= 5 then
      Gm:releaseKey(k)
    end
  end
  -- 释放所有控制键
  for _, k in pairs(ControlKeys) do
    Gm:releaseKey(k)
  end
  -- 释放所有其它绑定按键
  for _, k in pairs(Keys) do
    if Gm:isMouseButton(k) == false then
      Gm:releaseKey(k)
    end
  end
end

-- 注册控制键事件
function Gm:addControlEvent(ctrlKey, evtType, callback)
  if evtType ~= Types.KeyPressed and evtType ~= Types.KeyReleased then
    return
  end
  if (Gm:isControlKey(ctrlKey) == false) then
    return
  end

  local evtId = string.format('_%s_%s_', evtType, ctrlKey)

  table.insert(Gm._controlEvents, {
    id = evtId,
    type = evtType,
    key = ctrlKey,
    callback = callback,
    isPressed = false
  })
end

-- 处理 ControlKey 按键事件
function Gm:_progressControlEvents()
  for _, evt in ipairs(Gm._controlEvents) do
    local isPressed = Gm:isControlKeyPressed(evt.key)
    if evt.isPressed ~= isPressed then
      evt.isPressed = isPressed
      -- 从 false 到 true , 代表 modifier 键被按下
      -- 从 false 到 true 再到 false, 代表 modifier 键被按下然后松开，相当于一个 click 事件
      if evt.isPressed == true and evt.type == Types.KeyPressed then
        evt.callback()
      elseif evt.isPressed == false and evt.type == Types.KeyReleased then
        evt.callback()
      end
    end
  end
end

-- 定时器 - 动态设置一个定时触发的动作
-- （借助 action 的 `delay` 属性来模拟定时器的到期触发效果）
function Gm:setTimeout(name, func, delay)
  name = tostring(name)
  if string.len(name) < 1 then
    return
  end
  if type(func) ~= "function" then
    return
  end
  if type(delay) ~= "number" or delay < Config.FrameTime then
    delay = Config.FrameTime
  end

  Gm._timers[name] = {
    func = func,
    delay = delay,
    interval = delay,
  }
end

function Gm:clearTimeout(name)
  name = tostring(name)
  if Gm._timers[name] ~= nil then
    Gm._timers[name] = nil
  end
end

function Gm:_progressTimers()
  for name, act in pairs(Gm._timers) do
    Gm:_progressAction(act)
    if act._isReady then
      act.func()
      Gm:clearTimeout(name)
    end
  end
end

-- 处理鼠标按键绑定的任务
-- 避免为鼠标左键和右键绑定任务
function Gm:_mouseAssignment(keyCode, task)
  if type(keyCode) ~= Types.Number or keyCode < 2 then
    return
  end
  -- 为按键绑定 task
  if type(task) == Types.Function then
    Gm._mouseAssignments[keyCode] = task
    return
  end
  -- 读取按键绑定的 task
  task = Gm._mouseAssignments[keyCode]
  return task
end

-- 为鼠标按键绑定 task
function Gm:setMouseAssignment(keyCode, task)
  Gm:_mouseAssignment(keyCode, task)
end

-- 获取鼠标按键绑定的 task
function Gm:getMouseAssignment(keyCode)
  return Gm:_mouseAssignment(keyCode)
end

-- 发送鼠标按键绑定的 task
function Gm:_launchTask(keyCode)
  Gm:log("launchTask", keyCode)

  local lteKey = Gm._lastTaskEvent.key
  local lteType = Gm._lastTaskEvent.type
  -- 每次触发 start 前都要记录 `_lastTaskEvent`
  Gm:_updateLastTaskEvent(keyCode, Types.KeyReleased)
  -- 防止 `Pressed` 阶段触发 `Gm:stop()` 后 `Released` 阶段又触发任务进入死循环
  -- 这种情况下，相当于主动忽略掉这次 `Released` 事件
  -- 根据设计，`_launchTask` 方法里 `evt.type` 一定是 `Types.ControlKeyReleased`
  if lteKey == keyCode and lteType == Types.KeyPressed then
    return
  end

  -- `Gm._running ~= false` 状态表示 Gm 运行还没结束或没有正常结束, 需要主动 `stop`
  if Gm._running ~= false then
    Gm:_stop()
  end

  -- 防止误操作而意外触发脚本运行，故丢弃在脚本执行结束后一定时间内触发的鼠标事件
  if Gm:getCurrentTime() - Gm._timestamp < Config.DebounceTime then
    return
  end

  local task = Gm:getMouseAssignment(keyCode)
  if type(task) ~= "function" then
    return
  end

  local ok, ret = pcall(Gm._start, Gm, task)
  if not ok then
    Gm:log(ret)
  end

  Gm:_stop()
end

-- 开始任务
function Gm:_start(task)
  Gm:log("Gm start")
  -- 检查主要属性字段
  if type(Gm.actions) ~= Types.Table then
    Gm.actions = {}
  end
  if type(Gm._state) ~= Types.Table then
    Gm._state = {}
  end
  if type(Gm._controlEvents) ~= Types.Table then
    Gm._controlEvents = {}
  end
  if type(Gm._timers) ~= Types.Table then
    Gm._timers = {}
  end

  Gm._running = true
  Gm._timestamp = 0

  task()
  if next(Gm.actions) or next(Gm._controlEvents) or next(Gm._timers) then
    Gm:_tickTask()
  end
end

-- 结束任务
function Gm:_stop()
  -- 关闭轮训状态并清理运行时状态
  Gm._running = false
  -- 先自动调用 `teardown`
  if type(Gm.teardown) == Types.Function then
    Gm.teardown()
  end
  -- 这里不能设为 `0`，`_launchTask` 里需要它来判断离上次 stop 过去了多少时间
  Gm._timestamp = Gm:getCurrentTime()
  -- 这里也不能重置 `_lastTaskEvent`，`_launchTask` 需要它来判断是否是同一个事件的不同阶段
  -- Gm._lastTaskEvent = {},
  Gm._controlEvents = {}
  Gm._timers = {}
  Gm._state = {}
  -- 这里也不能重置 `_mouseAssignments`，它是一个注册后就不再变动的静态表
  -- Gm._mouseAssignments = {}

  Gm.actions = {}
  Gm.teardown = function() end

  -- 自动释放所有绑定的按键
  Gm:releaseAllKeys()
  Gm:log("Gm stopped.")
end

-- 更新活动控制事件标记
function Gm:_updateLastTaskEvent(key, type)
  Gm._lastTaskEvent.key = key
  Gm._lastTaskEvent.type = type
end

-- 处理 action 是否 ready 的逻辑
function Gm:_progressAction(action)
  local now = Gm._timestamp
  -- 每次帧循环先处理 action 的 onEachTick 方法
  if type(action.onEachTick) == Types.Function then
    action.onEachTick(action)
  end

  if type(action.interval) ~= Types.Number or action.interval < Config.FrameTime then
    action.interval = Config.FrameTime
  end
  if type(action.delay) ~= Types.Number or action.delay < 0 then
    action.delay = 0
  end

  -- 初始化 action 时间戳
  if type(action._timestamp) ~= Types.Number then
    -- 减去 action.interval, 保证第一个循环一定可以触发该 action
    -- 在没有 `action.delay` 的情况下，`now - action.interval` 可确保能在首个轮次进入 ready 状态
    action._timestamp = now - action.interval

    -- delay 小于 0 时逻辑正确但没意义：其它 action 不会延后执行
    -- 当有这样的需求时，其实是需要别的 action 延后
    if action.delay > 0 then
      action._timestamp = action._timestamp + action.delay
    end
  end

  -- 判断 action 是否 ready
  if action._isReady ~= true and now - action._timestamp >= action.interval then
    -- 更新 `action._timestamp` 动作推迟到 `_handleAction` 时
    -- action._timestamp = now
    action._isReady = true
  end
end

-- 执行/处理 已经 ready 的 action
function Gm:_handleAction(action)
  -- 如果需要 “延迟执行” 当前 action，则不进行任何操作直接返回
  if action.shouldDeferExecution(action) then
    return
  end

  -- 先设置 action 运行状态相关字段
  action._timestamp = Gm._timestamp
  action._isReady = false
  -- 再执行 action 实际动作
  if type(action.func) == Types.Function then
    action.func(action)
  end
  if Gm:isUsableKey(action.key) then
    Gm:clickKey(action.key)
  end
end

-- 检测时间进度，确保任务检测循环不快于最小时钟周期
-- 初始轮次(Gm.timestamp == 0)直接触发不进行 `Config.TickTime` 最小时间片检测
function Gm:_progressTick()
  -- `Gm.timestamp + Config.TickTime`, 当前时间戳 + 时钟周期 = 下一个 tick 的时间点
  -- 再减去 `Gm:getCurrentTime()` 后如果剩余时间 > 0, 则说明还没到下一个 tick 的时间点，需要通过 sleep 来等待
  local rt = Gm._timestamp + Config.TickTime - Gm:getCurrentTime()

  -- 理论上来说，在初始轮次时 `Gm:getCurrentTime()` 可能小于 `Config.TickTime`
  -- 这会导致 `rt` 无论如何都 `> 0`，为了初始轮次能被立即触发这里需要判断处理
  if rt > 0 and Gm._timestamp > 0 then
    Gm:sleep(rt)
  end

  -- 重新获取处理完 `rt` 后的最新时间戳并记录
  Gm._timestamp = Gm:getCurrentTime()
end

-- 轮询任务动作
function Gm:_tickTask()
  while Gm:shouldContinue() do
    Gm:_progressTick()
    -- 先处理监听事件(事件回调里可能对 action 和 Gm._state 做动态调整)
    Gm:_progressControlEvents()
    -- 再处理定时器(定时器回调里也可能对 action 和 Gm._state 做动态调整)
    Gm:_progressTimers()
    -- 然后处理任务列表
    for _, act in ipairs(Gm.actions) do
      Gm:_progressAction(act)
      if (act._isReady) then
        Gm:_handleAction(act)
      end
    end
  end
end

-- 生成环形迭代器
-- (一般用于设置不能无缝 CD 技能的 `interval`)
function Gm:makeCycleIterator(tl)
  if type(tl) ~= Types.Table then
    tl = {}
  end

  local tlLength = #tl
  local curIndex = 0

  local function next()
    curIndex = curIndex + 1
    if curIndex > tlLength then
      curIndex = 1
    end

    return tl[curIndex]
  end

  local iter = {
    next = next,
    length = function()
      return tlLength
    end,
    reset = function()
      curIndex = 0
    end,
  }

  return iter
end

-- 立即将指定 action 标记为 ready，使其在下一轮被立即处理
-- 注：它是否能被立即执行还是会受到 `shouldDeferExecution` 的影响。
function Gm:makeActionReady(action)
  if type(action) ~= Types.Table then
    return
  end
  -- Only mark action ready if it has a key or a func to execute
  if action.key == nil and action.func == nil then
    return
  end

  action._isReady = true
end

--- 一些常用游戏动作
-- 移动鼠标(Mac 多屏系统)
function Gm:moveMouse(x, y)
  if Config.os ~= "macOS" then
    MoveMouseTo(x, y)
  else
    MoveMouseToVirtual(x, y)
  end
end

-- 强制移动相关
-- 不在 “强制移动” 和 “强制站立” 相关方法里进行 “sleep 延时”
-- 因为不同场景需要的 ”延时“ 值不同，类似 `Gm:TownPortal()` 跟随具体场景设置延时更合适
function Gm:isForceMoving()
  return Gm._state._forceMove__ == true
end

function Gm:startForceMove()
  if not Gm._state._forceMove__ then
    Gm:stopForceStand()
    Gm:pressKey(Keys.ForceMove)
    Gm._state._forceMove__ = true
  end
end

function Gm:stopForceMove()
  if Gm._state._forceMove__ then
    Gm:releaseKey(Keys.ForceMove)
    Gm._state._forceMove__ = false
  end
end

-- 强制站立相关
function Gm:isForceStanding()
  return Gm._state._forceStand__ == true
end

function Gm:startForceStand()
  if not Gm._state._forceStand__ then
    Gm:stopForceMove()
    Gm:pressKey(Keys.ForceStand)
    Gm._state._forceStand__ = true
  end
end

function Gm:stopForceStand()
  if Gm._state._forceStand__ then
    Gm:releaseKey(Keys.ForceStand)
    Gm._state._forceStand__ = false
  end
end

-- TP 回城
function Gm:townPortal()
  -- 等待 12f 以让人物 “站稳” 等前置动作动画完成，才能比较稳定的触发回城
  Gm:sleep(Timing.MS_12F)
  Gm:clickKey(Keys.TownPortal)
  -- 再等待 6f 再重复触发一次以提高 TP 成功率
  Gm:sleep(Timing.MS_6F)
  Gm:clickKey(Keys.TownPortal)
end

-- 取消 TP 回城(释放技能或进行移动可以取消 TP)
function Gm:cancelTownPortal()
  Gm:clickKey(Mouse.Left)
end

--- GHub 事件监听
function OnEvent(evt, arg)
  -- 修正 arg 对应的 keyCode, 跟 `Mouse` 中的定义保持一致
  if evt == "MOUSE_BUTTON_RELEASED" or evt == "MOUSE_BUTTON_PRESSED" then
    if arg == Mouse.Right then
      arg = Mouse.Middle
    elseif arg == Mouse.Middle then
      arg = Mouse.Right
    end
  end

  if evt == "PROFILE_ACTIVATED" or evt == "PROFILE_DEACTIVATED" then
    -- 配置文件切换事件(宏运行期间会阻塞消息，这些事件一般无法正常触发)
    -- 似乎，带上 `PROFILE_ACTIVATED` 会让 GHub 运行稍微稳定那么一点？😳
    Gm:_stop()
  elseif evt == "MOUSE_BUTTON_RELEASED" then
    -- 只监听鼠标按键的 `MOUSE_BUTTON_RELEASED` 事件
    Gm:_launchTask(arg)
  elseif evt == "MOUSE_BUTTON_PRESSED" then
    -- `MOUSE_BUTTON_PRESSED` 留作 “中键、右键” 等的 “按下状态” 判断
  else
    -- 其它事件
    Gm:_stop()
  end
end

-- =============================================================================
-- Action 构造器(主要用来帮助了解 Action 有哪些属性字段)
-- 虽然该构造器没啥实际作用(由于可被动态修改，字段检查等逻辑还是放在 `Gm:_progressAction` 里)
-- 但还是推荐通过 `Action.new()` 来创建 action
-- =============================================================================
local Action = {}
Action.__index = Action

function Action:new(params)
  local act = setmetatable({}, self)

  act._isReady = false
  -- `onEachTick` 会在每个帧循环中(检查是否 ready 前)被调用执行
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  act.onEachTick = params.onEachTick
  -- func 会在每次处理 `.key` 之前被调用执行
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  -- 也可替代或配合 `.key` 在里面触发各种动作
  act.func = params.func
  if type(act.func) ~= Types.Function then
    act.func = nil
  end
  -- action 绑定的按键，可以是鼠标或键盘按键
  act.key = params.key
  if Gm:isUsableKey(act.key) == false then
    act.key = nil
  end
  -- action 执行的时间间隔，单位为 ms
  act.interval = params.interval
  -- action 延迟执行的时间，单位为 ms
  act.delay = params.delay
  -- `shouldDeferExecution() => true` 时当前 action 进入 “稍后执行” 状态
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  act.shouldDeferExecution = params.shouldDeferExecution
  if type(act.shouldDeferExecution) ~= Types.Function then
    act.shouldDeferExecution = function() return false end
  end

  -- 初始化时需要设置为 nil, `0` 会导致后续运行过程中无法判断出是否初始化时的 `0`
  act._timestamp = nil

  return act
end

-- =============================================================================
--  D3 游戏脚本部分
-- =============================================================================

--- 生活脚本
-- 背包信息设置，主要用于物品拆除脚本
-- 根据物品携带习惯，可使用背包格子数量为 6行 * 8列 = 48 个
local Inventory = {
  -- 拆除物品时起始格子的 x 坐标
  StartX     = 1068,
  -- 拆除物品时起始格子的 y 坐标
  StartY     = 482,
  -- 储物箱单元格宽度
  SlotWidth  = 38,
  -- 储物箱单元格高度(一般分辨率下等于宽度)
  SlotHeight = 38,
  -- 要进行物品拆除的储物箱行数
  Rows       = 6,
  -- 要进行物品拆除的储物箱列数
  Cols       = 8,
}

-- 针对 Windows 平台背包坐标设置
if Config.os ~= "macOS" then
  local widthRatio     = Config.windowsCoord.endX / Config.macResolution.width
  local heightRatio    = Config.windowsCoord.endY / Config.macResolution.height

  Inventory.StartX     = Gm:roundNumber(widthRatio * 1068)
  Inventory.StartY     = Gm:roundNumber(heightRatio * 482)
  Inventory.SlotWidth  = Gm:roundNumber(widthRatio * 38)
  Inventory.SlotHeight = Gm:roundNumber(heightRatio * 42)
end

-- Kadala 赌博
-- 血岩碎片上限 2000，可使用背包格子数量为 6 * 8 = 48
-- 赌占用格子最少(1格)的首饰物品最大可点次数为 2000 / 50 = 40 次
-- 堵消耗血岩碎片最少(25个)的普通装备物品(平均占用 2 格)最大可点次数为 48 / 2 = 24 次
-- 所以取个中间值：32
local function KadalaGamble()
  for i = 1, 32 do
    Gm:clickKey(Mouse.Right)
    Gm:sleep()
  end
end

-- 一键分解
local function SalvageItems()
  -- x, y 起点
  local xp = Inventory.StartX
  local yp = Inventory.StartY
  local w = Inventory.SlotWidth
  local h = Inventory.SlotHeight
  -- 格子矩阵
  local rows = Inventory.Rows
  local cols = Inventory.Cols

  for i = 0, rows * cols - 1 do
    -- 计算处于第几行(yp)
    local rp = math.floor(i / cols)
    -- 计算处于第几列(xp)
    local cp = i % cols
    Gm:moveMouse(xp + cp * w, yp + rp * h)

    Gm:sleep()
    -- 触发销毁确认框
    Gm:clickKey(Mouse.Left)
    -- 确认销毁
    Gm:clickKey(Keys.Enter)
    -- 多触发一个确认循环, 防止输入框劫持 enter 键
    Gm:sleep()
    Gm:clickKey(Mouse.Left)
    Gm:clickKey(Keys.Enter)
  end

  -- 关闭聊天框/装备面板
  Gm:clickKey(Keys.Esc)
end

-- 鼠标中键独立绑定固定功能(不推荐再修改)
Gm:setMouseAssignment(Mouse.Middle, function()
  if Gm:isControlKeyPressed(ControlKeys.Alt) then
    SalvageItems()
  else
    KadalaGamble()
  end
end)


--- 战斗脚本
local Builds = {
  DH = {},
  Wiz = {},
  Monk = {},
  Crus = {},
  Nec = {},
}

--- WIZ 法师
-- 火鸟聚能爆破
function Builds.Wiz:FirebirdExplosiveBlast()
  -- 切换引导状态
  local channeling = false
  local function startChanneling()
    channeling = true
    Gm:pressKey(Mouse.Right)
  end
  local function stopChanneling()
    channeling = false
    Gm:releaseKey(Mouse.Right)
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, function()
    if channeling then
      stopChanneling()
    else
      startChanneling()
    end
  end)

  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, function()
    Gm:clickKey(Keys.ActionBarSkill_2)
  end)

  Gm.actions = {
    -- 聚能爆破(Explosive Blast)
    Action:new({
      interval = Timing.MS_3F,
      func = function()
        if channeling then
          Gm:clickKey(Keys.ActionBarSkill_3)
        end
      end,
    }),
    Action:new({
      interval = 1000 * 60 * 5,
      func = function()
        local isForceMoving = Gm:isForceMoving()
        Gm:startForceStand()
        Gm:sleep(Timing.MS_3F)
        -- 魔星(Familiar)
        Gm:clickKey(Mouse.Left)
        -- 风暴护甲(Storm Armor)
        Gm:clickKey(Keys.ActionBarSkill_1)
        -- 魔法武器(Magic Weapon)
        Gm:clickKey(Keys.ActionBarSkill_4)
        Gm:sleep(Timing.MS_3F)
        Gm:stopForceStand()
        if isForceMoving then
          Gm:startForceMove()
        end
      end,
      shouldDeferExecution = function()
        return channeling == true
      end
    }),
  }

  -- 默认开引导
  startChanneling()
end

-- 陨石
function Builds.Wiz:Meteor()
  local inMeteor = false;
  local function startMeteor()
    Gm:stopForceMove()
    Gm:pressKey(Mouse.Right)
    inMeteor = true
  end
  local function stopMeteor()
    Gm:releaseKey(Mouse.Right)
    inMeteor = false
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, function()
    if inMeteor then
      stopMeteor()
      Gm:startForceMove()
    elseif not Gm:isForceMoving() then
      Gm:startForceMove()
    else
      startMeteor()
    end
  end)
  -- free move
  Gm:addControlEvent(ControlKeys.Shift, Types.KeyPressed, function()
    stopMeteor()
    Gm:stopForceMove()
  end)

  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, function()
    stopMeteor()
    Gm:startForceMove()
    Gm:sleep(Timing.MS_9F)
    Gm:pressKey(Keys.ActionBarSkill_2)
    Gm:sleep(Timing.MS_12F)
    Gm:releaseKey(Keys.ActionBarSkill_2)
  end)

  Gm.actions = {
    Action:new({
      interval = 1000 * 60 * 2.5,
      func = function()
        local isForceMoving = Gm:isForceMoving()
        Gm:startForceStand()
        Gm:sleep(Timing.MS_3F)
        -- 魔星(Familiar)
        Gm:clickKey(Mouse.Left)
        -- 风暴护甲(Storm Armor)
        Gm:clickKey(Keys.ActionBarSkill_1)
        -- 魔法武器(Magic Weapon)
        Gm:clickKey(Keys.ActionBarSkill_4)
        Gm:sleep(Timing.MS_3F)
        Gm:stopForceStand()
        if isForceMoving then
          Gm:startForceMove()
        end
      end,
      shouldDeferExecution = function()
        return inMeteor == true
      end
    }),
    -- Frost Nova/Black Hole
    Action:new({
      -- 随缘自动触发，但 4s 比较容易对齐元素戒
      interval = 1000 * 4,
      key = Keys.ActionBarSkill_3,
      shouldDeferExecution = function()
        return inMeteor == false
      end
    }),
  }

  Gm:startForceMove()
end

-- DH 猎魔人
-- 冰吞
function Builds.DH:DevouringStrafe()
  -- 先站定打追踪箭
  Gm:startForceStand()
  Gm:sleep()
  for _ = 1, 2 do
    Gm:clickKey(Mouse.Left)
    Gm:sleep(Timing.MS_20F)
  end
  Gm:stopForceStand()

  --  切换扫射状态
  local strafing = false
  local function toggleStrafe()
    if strafing then
      strafing = false
      Gm:releaseKey(Mouse.Right)
    else
      strafing = true
      Gm:pressKey(Mouse.Right)
    end
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, toggleStrafe)

  Gm.actions = {
    -- 战宠(Companion)
    -- 带翅膀(Shadow Power)戒律(Discipline)会不够, 宠物通用性和综合收益最好
    Action:new({
      interval = 1000,
      delay = 2000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_1)
        end
      end
    }),
    -- 蓄势待发(Preparation)
    Action:new({
      interval = Timing.MS_3F,
      delay = 5000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_3)
        end
      end
    }),
    -- 烟雾(Smoke Screen)
    Action:new({
      interval = 1000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end
    }),
    -- 复仇(Vengeance)
    Action:new({
      interval = Timing.MS_3F,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    }),
    -- 追踪箭(Hungering Arrow)
    Action:new({
      interval = Timing.MS_1F * 10,
      delay = Timing.MS_20F,
      func = function()
        if strafing then
          Gm:clickKey(Mouse.Left)
        end
      end
    })
  }

  toggleStrafe()
end

-- 三刀(扫射)
function Builds.DH:ImpaleStrafe()
  --  切换扫射状态
  local strafing = false
  local function toggleStrafe()
    if strafing then
      strafing = false
      Gm:releaseKey(Mouse.Right)
    else
      strafing = true
      -- 每次状态切换都重新激活一次翅膀(Shadow Power)和飞刀(Impale)
      Gm:clickKey(Keys.ActionBarSkill_1)
      Gm:clickKey(Keys.ActionBarSkill_3)
      Gm:sleep(Timing.MS_6F)
      Gm:pressKey(Mouse.Right)
    end
  end
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, toggleStrafe)

  Gm.actions = {
    -- 烟雾(Smoke Screen - Vanishing Powder)
    Action:new({
      interval = 1000,
      delay = 2000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end
    }),
    -- 复仇(Vengeance)
    Action:new({
      interval = Timing.MS_3F,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    }),
    -- 左键
    Action:new({
      interval = Timing.MS_20F,
      delay = Timing.MS_12F,
      func = function()
        if strafing then
          Gm:clickKey(Mouse.Left)
        end
      end
    }),
  }

  toggleStrafe()
end

--- 娜塔亚陷阱
function Builds.DH:NatalyaSpikeTrap()
  -- 自动放陷阱
  local spikeTrapMode = false
  local function startSpikeTrap()
    Gm:startForceStand()
    Gm:pressKey(Mouse.Right)
    spikeTrapMode = true
  end
  local function stopSpikeTrap()
    Gm:stopForceStand()
    Gm:releaseKey(Mouse.Right)
    spikeTrapMode = false
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, function()
    if spikeTrapMode then
      stopSpikeTrap()
      Gm:startForceMove()
    elseif not Gm:isForceMoving() then
      Gm:startForceMove()
    else
      startSpikeTrap()
    end
  end)

  -- 拉怪
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, function()
    local isForceMoving = Gm:isForceMoving()
    local isForceStanding = Gm:isForceStanding()
    local isSpikeTrapMode = spikeTrapMode

    if isSpikeTrapMode then
      stopSpikeTrap()
    end

    Gm:startForceStand()
    Gm:sleep(Timing.MS_6F)
    Gm:clickKey(Mouse.Right)
    Gm:clickKey(Mouse.Right)
    Gm:sleep(Timing.MS_12F)
    Gm:clickKey(Mouse.Left)
    Gm:clickKey(Keys.ActionBarSkill_1)
    Gm:sleep(Timing.MS_12F)

    if isSpikeTrapMode then
      startSpikeTrap()
    elseif isForceMoving then
      Gm:startForceMove()
    elseif not isForceStanding then
      Gm:stopForceStand()
    end
  end)
  -- free move
  Gm:addControlEvent(ControlKeys.Shift, Types.KeyPressed, function()
    stopSpikeTrap()
    Gm:stopForceMove()
  end)

  Gm.actions = {
    -- 战宠(Companion)
    Action:new({
      interval = 1000,
      delay = 5000,
      key = Keys.ActionBarSkill_3,
    }),
    -- 烟雾弹(Smoke Screen)
    Action:new({
      key = Keys.ActionBarSkill_2,
      onEachTick = function(sf)
        if spikeTrapMode then
          sf.interval = 1000
        else
          sf.interval = 2500
        end
      end
    }),
    -- 复仇(Vengeance)
    Action:new({
      interval = Timing.MS_3F,
      delay = 1000,
      key = Keys.ActionBarSkill_4,
    }),
    -- 闪避射击(Evasive Fire) + 铁蒺藜(Caltrops)
    Action:new({
      interval = 1500,
      func = function()
        if spikeTrapMode then
          Gm:clickKey(Mouse.Left)
          Gm:clickKey(Keys.ActionBarSkill_1)
        end
      end,
      shouldDeferExecution = function()
        return spikeTrapMode == false
      end
    }),
  }

  -- initial
  Gm:pressKey(Mouse.Right)
  Gm:sleep(1000)
  Gm:releaseKey(Mouse.Right)
  Gm:startForceMove()
end

--- MONK 武僧
-- 散件敲钟(圣化)
function Builds.Monk:SanctLoDWoL()
  Gm:addControlEvent(
    ControlKeys.Alt,
    Types.KeyPressed,
    function()
      Gm:startForceStand()
      -- 开禅定
      Gm:clickKey(Keys.ActionBarSkill_4)
      Gm:sleep(Timing.MS_6F)
      -- 再敲两钟
      Gm:clickKey(Mouse.Left)
      Gm:sleep(Timing.MS_6F)
      Gm:clickKey(Mouse.Left)
      Gm:sleep(Timing.MS_1F * 28)
      -- 再两飓风破
      Gm:clickKey(Mouse.Right)
      Gm:sleep(Timing.MS_1F * 28)
      Gm:clickKey(Mouse.Right)
      Gm:sleep(Timing.MS_6F)

      Gm:stopForceStand()
    end
  )

  -- 幻身决动态 interval
  local allyIter = Gm:makeCycleIterator({ 3000, 1000, 1000 })
  -- 灵光悟动态 interval
  local epiphanyIter = Gm:makeCycleIterator({ 4000, 1000, 1000, 1000, 1000 })
  -- 定义动作列表, 开始循环
  Gm.actions = {
    -- 幻身诀
    Action:new({
      key = Keys.ActionBarSkill_1,
      delay = 3000,
      func = function(sf)
        sf.interval = allyIter.next()
      end
    }),
    -- 黑人灵光悟
    Action:new({
      func = function(sf)
        Gm:clickKey(Keys.ActionBarSkill_3)
        sf.interval = epiphanyIter.next()
      end
    }),
  }
end

--- Crus 圣教军
-- 正义天拳
function Builds.Crus:AoVFist()
  -- 强制移动切换
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyReleased, function()
    if Gm:isForceMoving() then
      Gm:stopForceMove()
      Gm:clearTimeout('tp')
    else
      Gm:startForceMove()
    end
  end)
  -- 回城减伤
  local function townPortal()
    Gm:stopForceMove()
    Gm:townPortal()
    Gm:setTimeout('tp', function()
      Gm:startForceMove()
    end, Timing.TownPortal)
  end
  Gm:addControlEvent(ControlKeys.Shift, Types.KeyPressed, townPortal)

  -- 跑马
  local function beforeSteedCharge()
    Gm:stopForceMove()
    Gm:clickKey(Keys.ActionBarSkill_1)
    Gm:clickKey(Keys.ActionBarSkill_3)
    Gm:clickKey(Keys.ActionBarSkill_4)
    Gm:sleep(Timing.MS_3F)
  end
  local function steedCharge()
    Gm:clickKey(Keys.ActionBarSkill_2)
    Gm:sleep(Timing.MS_3F)
    Gm:startForceMove()
  end
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, beforeSteedCharge)
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyReleased, steedCharge)

  -- 宏停止时，清理可能存在回城状态
  Gm.teardown = function()
    Gm:cancelTownPortal()
  end

  beforeSteedCharge()
  steedCharge()
end

--- Nec 死灵
-- 拉斯玛亡者大军
function Builds.Nec:RathmaAotD()
  -- Siphon Blood
  local siphoning = false;
  local function startSiphon()
    Gm:stopForceMove()
    Gm:pressKey(Mouse.Right)
    siphoning = true
  end
  local function stopSiphon()
    Gm:releaseKey(Mouse.Right)
    siphoning = false
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, function()
    if siphoning then
      stopSiphon()
      Gm:startForceMove()
    elseif not Gm:isForceMoving() then
      Gm:startForceMove()
    else
      startSiphon()
    end
  end)
  -- free move
  Gm:addControlEvent(ControlKeys.Shift, Types.KeyPressed, function()
    Gm:stopForceMove()
    stopSiphon()
  end)

  -- Blood Rush
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, function()
    stopSiphon()
    Gm:startForceMove()
    Gm:sleep(Timing.MS_9F)
    Gm:pressKey(Keys.ActionBarSkill_2)
    Gm:sleep(Timing.MS_12F)
    Gm:releaseKey(Keys.ActionBarSkill_2)
  end)

  Gm.actions = {
    -- Command Skeletons
    Action:new({
      key = Keys.ActionBarSkill_3,
      onEachTick = function(sf)
        if siphoning then
          sf.interval = 1000
        else
          sf.interval = 2000
        end
      end
    }),
    -- Army of the Dead
    Action:new({
      delay = 200,
      interval = Timing.MS_1F * 40,
      func = function()
        if siphoning then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    }),
    -- Bone Armor
    Action:new({
      delay = 100,
      interval = 1000,
      func = function()
        if siphoning then
          Gm:clickKey(Mouse.Left)
        end
      end
    }),
  }

  -- initial
  startSiphon()
end

-- 死亡新星
function Builds.Nec:DeathNova()
  -- Siphon Blood
  local siphoning = false;
  local function startSiphon()
    Gm:stopForceMove()
    Gm:pressKey(Mouse.Right)
    siphoning = true
  end
  local function stopSiphon()
    Gm:releaseKey(Mouse.Right)
    siphoning = false
  end
  Gm:addControlEvent(ControlKeys.Alt, Types.KeyPressed, function()
    if siphoning then
      stopSiphon()
      Gm:startForceMove()
    elseif not Gm:isForceMoving() then
      Gm:startForceMove()
    else
      startSiphon()
    end
  end)
  -- free move
  Gm:addControlEvent(ControlKeys.Shift, Types.KeyPressed, function()
    Gm:stopForceMove()
    stopSiphon()
  end)

  -- Blood Rush
  Gm:addControlEvent(ControlKeys.Ctrl, Types.KeyPressed, function()
    stopSiphon()
    Gm:startForceMove()
    Gm:sleep(Timing.MS_9F)
    Gm:pressKey(Keys.ActionBarSkill_2)
    Gm:sleep(Timing.MS_12F)
    Gm:releaseKey(Keys.ActionBarSkill_2)
  end)

  Gm.actions = {
    -- Bone Armor
    Action:new({
      delay = 100,
      interval = Timing.MS_1F * 40,
      func = function()
        if siphoning then
          Gm:clickKey(Keys.ActionBarSkill_3)
        end
      end
    }),
  }

  -- initial
  Gm:startForceMove()
end

-- =============================================================================
-- #鼠标按键功能绑定#
-- =============================================================================
-- DPI 切换键
Gm:setMouseAssignment(6, function()
  Builds.DH:DevouringStrafe()
end)

-- 侧后键
Gm:setMouseAssignment(4, function()
  Builds.Wiz:Meteor()
end)

-- 侧前键
Gm:setMouseAssignment(5, function()
  Builds.Nec:RathmaAotD()
end)
