-- =============================================================================
-- 警告: 宏运行期间不要切屏!
-- 游戏切屏（切出游戏到其它应用）时，请 **先停止宏运行**
-- Mac 电脑上如果没把本脚本设置为 “通用配置文件”，在宏运行期间切屏会导致 GHub 崩溃，需要重启 GHub 才能恢复
-- 不推荐把本脚本文件设置为 “通用配置文件” - 其它场景根本用不到这个脚本
-- =============================================================================


-- =============================================================================
-- GHub 原生 C API 与常用全局函数局部化缓存 (提升热循环执行性能)
-- =============================================================================
local GetRunningTime = GetRunningTime
local Sleep = Sleep
local IsModifierPressed = IsModifierPressed
local IsMouseButtonPressed = IsMouseButtonPressed
local PressKey = PressKey
local ReleaseKey = ReleaseKey
local PressAndReleaseKey = PressAndReleaseKey
local PressMouseButton = PressMouseButton
local ReleaseMouseButton = ReleaseMouseButton
local PressAndReleaseMouseButton = PressAndReleaseMouseButton
local MoveMouseTo = MoveMouseTo
local MoveMouseToVirtual = MoveMouseToVirtual
local IsKeyLockOn = IsKeyLockOn
local OutputLogMessage = OutputLogMessage

local type = type
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local math_floor = math.floor
local math_ceil = math.ceil

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
local ModifierKeys = {
  -- 一般用来在宏任务运行期间按下此键，触发某个宏状态或逻辑的转换
  Ctrl = "lctrl",
  -- 一般用来在宏任务运行期间按下此键，触发某个宏状态或逻辑的转换
  Shift = "lshift",
  -- 一般用来在鼠标按键触发宏任务时，通过判断此键的按下状态动态分流要执行的任务
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
  -- 基准参考分辨率(基础分辨率: 1440x900)
  refResolution = {
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
-- 防止误操作而意外触发脚本运行的冷却时间(时间越短越没用、越长越容易拦截正常操作)
-- 1000 / 1.618
Config.CooldownTime = 618

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

-- =============================================================================
-- Action (并行周期触发器)
-- =============================================================================
local Action = {}
Action.__index = Action

function Action:new(params)
  local act = setmetatable({}, self)

  params = type(params) == Types.Table and params or {}

  act._isReady = false
  act._timestamp = nil

  -- `onEachTick` 会在每个帧循环中(检查是否 ready 前)被调用执行
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  act.onEachTick = type(params.onEachTick) == Types.Function and params.onEachTick or nil

  -- func 会在每次处理 `.key` 之前被调用执行
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  -- 也可替代或配合 `.key` 在里面触发各种动作
  act.func = type(params.func) == Types.Function and params.func or nil

  -- action 绑定的按键，可以是鼠标或键盘按键
  act.key = Gm:isKey(params.key) and params.key or nil

  -- 构造期规范化 interval 与 delay（消除每帧重复校验）
  local interval = params.interval
  if type(interval) ~= Types.Number or interval < Config.FrameTime then
    interval = Config.FrameTime
  end
  act.interval = interval

  local delay = params.delay
  if type(delay) ~= Types.Number or delay < 0 then
    delay = 0
  end
  act.delay = delay

  -- `shouldDeferExecution() => true` 时当前 action 进入 “稍后执行” 状态
  -- 当前 action 会以第一个参数传给它，用来访问或动态修改当前 action 的属性
  if type(params.shouldDeferExecution) == Types.Function then
    act.shouldDeferExecution = params.shouldDeferExecution
  else
    act.shouldDeferExecution = function() return false end
  end

  return act
end

-- =============================================================================
-- Sequence (串行时序流水线执行器)
-- =============================================================================
local Sequence = {}
Sequence.__index = Sequence

function Sequence:new(steps, options)
  local seq = setmetatable({}, self)

  seq.steps = type(steps) == Types.Table and steps or {}
  options = type(options) == Types.Table and options or {}

  seq.loop = options.loop == true
  seq.interval = options.interval or 0 -- 循环间隔，支持 number 或 function/iter
  seq.delay = options.delay or 0       -- 首次启动延时
  seq.onStart = options.onStart
  seq.onEnd = options.onEnd
  seq.onRoundStart = options.onRoundStart
  seq.onRoundEnd = options.onRoundEnd

  -- 内部运行状态: "idle", "delay", "step", "interval"
  seq._state = "idle"
  seq._stepIndex = 1
  seq._timestamp = 0
  seq._currentWait = 0

  return seq
end

function Sequence:isRunning()
  return self._state ~= "idle"
end

function Sequence:start()
  if self:isRunning() then
    return
  end

  self._stepIndex = 1
  self._timestamp = Gm._timestamp

  if type(self.onStart) == Types.Function then
    self.onStart(self)
  end

  if type(self.delay) == Types.Number and self.delay > 0 then
    self._state = "delay"
    self._currentWait = self.delay
  else
    self:_startRound()
  end
end

function Sequence:_startRound()
  if #self.steps == 0 then
    self:stop()
    return
  end

  self._stepIndex = 1
  self._state = "step"

  if type(self.onRoundStart) == Types.Function then
    self.onRoundStart(self)
  end

  self:_executeStep(1)
end

function Sequence:_executeStep(index)
  local step = self.steps[index]
  if not step then
    self:_finishRound()
    return
  end

  -- 执行当前 step 的动作
  if type(step.func) == Types.Function then
    step.func(step)
  end
  if Gm:isKey(step.key) then
    Gm:clickKey(step.key)
  end

  -- 计算当前 step 的等待时间
  local waitTime = step.wait
  if type(waitTime) == Types.Function then
    waitTime = waitTime()
  end
  if type(waitTime) ~= Types.Number or waitTime < 0 then
    waitTime = 0
  end

  self._currentWait = waitTime
  self._timestamp = Gm._timestamp
end

function Sequence:_finishRound()
  if type(self.onRoundEnd) == Types.Function then
    self.onRoundEnd(self)
  end

  if self.loop then
    local intVal = self.interval
    if type(intVal) == Types.Function then
      intVal = intVal()
    elseif type(intVal) == Types.Table and type(intVal.next) == Types.Function then
      intVal = intVal.next()
    end
    if type(intVal) ~= Types.Number or intVal <= 0 then
      intVal = 0
    end

    if intVal > 0 then
      self._state = "interval"
      self._currentWait = intVal
      self._timestamp = Gm._timestamp
    else
      -- 无等待，立即开启下一轮
      self:_startRound()
    end
  else
    self:stop()
  end
end

function Sequence:stop()
  if not self:isRunning() then
    return
  end

  self._state = "idle"
  self._stepIndex = 1
  self._timestamp = 0

  if type(self.onEnd) == Types.Function then
    self.onEnd(self)
  end
end

function Sequence:toggle()
  if self:isRunning() then
    self:stop()
  else
    self:start()
  end
end

-- =============================================================================
--  Gm 框架核心
-- =============================================================================
Gm = {
  -- Gm 是否处于运行中
  _running = false,
  -- Gm 运行时间戳
  _timestamp = 0,

  -- 标记因触发宏停止而需要被忽略的下一个 GHub 事件按键（keyCode）
  _ghubEventToIgnore = nil,
  -- 当前 task 监听的控制按键事件
  _modifierEvents = {},
  -- 当前 task 注册的时序执行器 (Sequences)
  _sequences = {},
  -- 当前 task 可存取的数据
  _state = {},
  -- 为鼠标按键分配的 Task 列表
  _mouseAssignments = {},
  -- 当前 task 注册的停止/清理回调列表
  _stopCallbacks = {},
  -- 当前 task 注册的 Action 列表
  _actions = {},
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
  return math_floor(num + 0.5)
end

function Gm:sleep(ms)
  if type(ms) ~= Types.Number or ms < 0 then
    ms = Config.TickTime
  end
  -- 由于 `Sleep()` 不支持小数和负数(各种 0 值除外），这里需要向上取整
  -- 向上取整可以保证 “至少 sleep 多少时间”，逻辑上也比较合理
  ms = math_ceil(ms)
  Sleep(ms)
end

-- 判断一个值是否是按键标识符 - 包括鼠标键、普通键盘键、键盘控制键等 GHub 支持的所有按键
function Gm:isKey(k)
  return type(k) == Types.String or type(k) == Types.Number
end

-- 是否鼠标键
-- (不检查是否真的可用)
function Gm:isMouseButton(k)
  return type(k) == Types.Number
end

-- 判断一个键是不是控制键
function Gm:isModifierKey(key)
  for _, k in pairs(ModifierKeys) do
    if k == key then
      return true
    end
  end

  return false
end

-- GHub 只支持获取 `ModifierKeys` 的按下状态
-- 只支持 `ModifierKeys` 中定义的键
function Gm:isModifierPressed(k)
  if Gm:isModifierKey(k) == false then
    return false
  end

  return IsModifierPressed(k)
end

-- 很适合用来做 “战斗状态切换” 等 *持续状态切换判断*
function Gm:isCapsLockOn()
  return IsKeyLockOn("capslock")
end

-- 根据相关控制按键的按下状态和 Task 状态，来确定是否需要继续运行
-- 注：长时间循环(需要手工停止)的宏脚本里，一定要调用这个方法进行宏开关的状态判断
function Gm:shouldContinue()
  if Gm._running ~= true then
    return false
  end

  if IsMouseButtonPressed(Mouse.Middle) then
    -- 记录导致停止的按键，防止后续 Release 阶段误触发关联任务
    Gm._ghubEventToIgnore = Mouse.Middle
    return false
  end

  return true
end

-- 按键操作
function Gm:pressKey(k)
  if Gm:isKey(k) == false then
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
  if Gm:isKey(k) == false then
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
  if Gm:isKey(k) == false then
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
function Gm:releaseAllKeys()
  -- 释放所有鼠标按键
  for _, k in pairs(Mouse) do
    if type(k) == Types.Number and k >= 1 and k <= 5 then
      Gm:releaseKey(k)
    end
  end
  -- 释放所有控制键
  for _, k in pairs(ModifierKeys) do
    Gm:releaseKey(k)
  end
  -- 释放所有其它绑定按键
  for _, k in pairs(Keys) do
    if Gm:isMouseButton(k) == false then
      Gm:releaseKey(k)
    end
  end
end

-- 创建并注册 Action
function Gm:createAction(params)
  local act = Action:new(params)
  table.insert(Gm._actions, act)
  return act
end

-- 批量创建并注册 Action
function Gm:createActions(actionsList)
  if type(actionsList) == Types.Table then
    for _, item in ipairs(actionsList) do
      if getmetatable(item) == Action then
        table.insert(Gm._actions, item)
      else
        Gm:createAction(item)
      end
    end
  end
  return Gm._actions
end

-- 创建并注册 Sequence
function Gm:createSequence(steps, options)
  local seq = Sequence:new(steps, options)
  table.insert(Gm._sequences, seq)
  return seq
end

-- 注册控制键事件
function Gm:onModifierClick(modifier, callback)
  if Gm:isModifierKey(modifier) == false then
    return
  end

  local evtType = Types.KeyReleased
  local evtId = string.format('_%s_%s_', evtType, modifier)
  local initPressed = Gm:isModifierPressed(modifier)

  table.insert(Gm._modifierEvents, {
    id = evtId,
    type = evtType,
    key = modifier,
    callback = callback,
    -- 用实际物理按键状态初始化，避免任务启动前已存在的控制键状态产生虚假事件
    isPressed = initPressed,
    -- 如果是按着这个 modifier 启动的，则需要过滤这次按下对应的松开事件
    initEventToIgnore = initPressed
  })
end

-- 注册当前 task 停止时的清理回调
function Gm:onStop(callback)
  if type(callback) == Types.Function then
    table.insert(Gm._stopCallbacks, callback)
  end
end

-- 处理 Modifier 按键事件
function Gm:_progressModifierEvents()
  for _, evt in ipairs(Gm._modifierEvents) do
    local isPressed = IsModifierPressed(evt.key)
    if evt.isPressed ~= isPressed then
      evt.isPressed = isPressed
      if evt.initEventToIgnore then
        -- 重置为 nil(而不是 false) 代表进行过 ignore 处理
        evt.initEventToIgnore = nil
      else
        -- 从 false 到 true 再到 false, 代表 modifier 键被按下然后松开，相当于一个 click 事件
        if evt.isPressed == true and evt.type == Types.KeyPressed then
          evt.callback()
        elseif evt.isPressed == false and evt.type == Types.KeyReleased then
          evt.callback()
        end
      end
    end
  end
end

-- 处理 Sequence 时序步进
function Gm:_progressSequences()
  local gts = Gm._timestamp
  for _, seq in ipairs(Gm._sequences) do
    if seq._state == "delay" then
      if gts - seq._timestamp >= seq._currentWait then
        seq:_startRound()
      end
    elseif seq._state == "step" then
      if gts - seq._timestamp >= seq._currentWait then
        seq._stepIndex = seq._stepIndex + 1
        if seq._stepIndex <= #seq.steps then
          seq:_executeStep(seq._stepIndex)
        else
          seq:_finishRound()
        end
      end
    elseif seq._state == "interval" then
      if gts - seq._timestamp >= seq._currentWait then
        seq:_startRound()
      end
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

  -- 防止 Pressed 阶段触发 Gm:stop() 后，Released 阶段又触发任务进入死循环
  if Gm._ghubEventToIgnore == keyCode then
    Gm._ghubEventToIgnore = nil
    return
  end
  Gm._ghubEventToIgnore = nil

  -- `Gm._running ~= false` 状态表示 Gm 运行还没结束或没有正常结束, 需要主动 `stop`
  if Gm._running ~= false then
    Gm:_stop()
  end

  -- 防止误操作而意外触发脚本运行，故丢弃在脚本执行结束后一定时间内触发的鼠标事件
  if Gm:getCurrentTime() - Gm._timestamp < Config.CooldownTime then
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
  if type(Gm._actions) ~= Types.Table then
    Gm._actions = {}
  end
  if type(Gm._state) ~= Types.Table then
    Gm._state = {}
  end
  if type(Gm._modifierEvents) ~= Types.Table then
    Gm._modifierEvents = {}
  end
  if type(Gm._sequences) ~= Types.Table then
    Gm._sequences = {}
  end
  if type(Gm._stopCallbacks) ~= Types.Table then
    Gm._stopCallbacks = {}
  end

  Gm._running = true
  Gm._timestamp = 0

  task()
  if next(Gm._actions) or next(Gm._modifierEvents) or next(Gm._sequences) then
    Gm:_tickTask()
  end
end

-- 结束任务
function Gm:_stop()
  -- 关闭轮询状态并清理运行时状态
  Gm._running = false
  -- 触发所有已注册的停止清理回调
  for _, cb in ipairs(Gm._stopCallbacks) do
    pcall(cb)
  end
  Gm._stopCallbacks = {}

  -- 停止并清理所有序列（触发 onEnd）
  for _, seq in ipairs(Gm._sequences) do
    if seq:isRunning() then
      seq:stop()
    end
  end
  Gm._sequences = {}
  Gm._actions = {}

  -- 这里不能设为 `0`，`_launchTask` 里需要它来判断离上次 stop 过去了多少时间
  Gm._timestamp = Gm:getCurrentTime()
  -- 这里也不能重置 `_ghubEventToIgnore`，`_launchTask` 需要它来判断是否是同一个事件的不同阶段
  -- Gm._ghubEventToIgnore = nil,
  Gm._modifierEvents = {}
  Gm._state = {}
  -- 这里也不能重置 `_mouseAssignments`，它是一个注册后就不再变动的静态表
  -- Gm._mouseAssignments = {}

  -- 自动释放所有绑定的按键
  Gm:releaseAllKeys()
  Gm:log("Gm stopped.")
end

-- 处理 action 是否 ready 的逻辑
function Gm:_progressAction(action)
  -- 每次帧循环先处理 action 的 onEachTick 方法（如动态计算 interval）
  if action.onEachTick then
    action.onEachTick(action)
  end

  local gts = Gm._timestamp
  -- 初始化 action 时间逻辑
  if not action._timestamp then
    -- 减去 interval 可确保第一次运行时可被立即执行
    action._timestamp = gts - action.interval + action.delay
  end

  -- 判断 action 是否 ready
  if not action._isReady and gts - action._timestamp >= action.interval then
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
  if Gm:isKey(action.key) then
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
    -- 1. 先处理监听事件 (事件回调里可能对 action/sequence 和 Gm._state 做动态调整)
    Gm:_progressModifierEvents()
    -- 2. 再处理串行时序执行器 (Sequences 步进)
    Gm:_progressSequences()
    -- 3. 然后处理并行周期任务列表
    for _, act in ipairs(Gm._actions) do
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

--- 鼠标坐标归一化转换器 (Coordinate Normalizer)
-- 将基于基准参考分辨率 (1440x900) 的逻辑坐标转换为对应 OS 平台的鼠标移动指令
-- macOS: 调用 MoveMouseToVirtual 以兼容虚拟坐标与多屏
-- Windows: 映射至 0..65535 归一化区间 (按统一比例 x/refWidth * 65535, y/refHeight * 65535 转换，修复原 42 高度比例系数 Bug)
function Gm:moveMouseRef(refX, refY)
  if Config.os ~= "macOS" then
    local normX = Gm:roundNumber((refX / Config.refResolution.width) * Config.windowsCoord.endX)
    local normY = Gm:roundNumber((refY / Config.refResolution.height) * Config.windowsCoord.endY)
    MoveMouseTo(normX, normY)
  else
    MoveMouseToVirtual(refX, refY)
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

-- TP 回城 (非阻塞动作序列)
function Gm:townPortal()
  local tpSeq = Gm:createSequence({
    {
      key = Keys.TownPortal,
      wait = Timing.MS_6F,
    },
    {
      key = Keys.TownPortal,
    },
  }, {
    delay = Timing.MS_12F, -- 等待 12f 以让人物 “站稳” 等前置动作动画完成，才能比较稳定的触发回城
  })
  tpSeq:start()
  return tpSeq
end

-- 取消 TP 回城(释放技能或进行移动可以取消 TP)
function Gm:cancelTownPortal()
  Gm:clickKey(Mouse.Left)
end

-- 强制传送(Force Teleport)
-- 强制移动 → 等待前摇 → 长按传送技能 → 松开
function Gm:forceTeleport(k)
  k = k or Keys.ActionBarSkill_3
  local prepWait = Gm:isForceMoving() and Timing.MS_3F or Timing.MS_6F

  local teleportSeq = Gm:createSequence({
    -- 步骤 1: 确保进入强制移动并等待前摇
    {
      func = function()
        if not Gm:isForceMoving() then
          Gm:startForceMove()
        end
      end,
      wait = prepWait,
    },
    -- 步骤 2: 按下传送技能并保持 9 帧
    {
      func = function()
        Gm:pressKey(k)
      end,
      wait = Timing.MS_9F,
    },
  }, {
    -- 清理 / 结束: 无论正常完成还是中途宏停止，必定释放技能键，绝不卡键
    onEnd = function()
      Gm:releaseKey(k)
    end,
  })

  teleportSeq:start()
  return teleportSeq
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
    Gm:moveMouseRef(xp + cp * w, yp + rp * h)

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
  if Gm:isModifierPressed(ModifierKeys.Alt) then
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
--- 公用基础 Buff 序列
local function wizBuffs()
  local wasForceMoving = false
  local buffSeq = Gm:createSequence({
    {
      func = function()
        -- 魔星(Familiar)
        Gm:clickKey(Mouse.Left)
        -- 风暴护甲(Storm Armor)
        Gm:clickKey(Keys.ActionBarSkill_1)
        -- 魔法武器(Magic Weapon)
        Gm:clickKey(Keys.ActionBarSkill_4)
      end,
      wait = Timing.MS_3F,
    }
  }, {
    delay = Timing.MS_3F,
    onStart = function()
      wasForceMoving = Gm:isForceMoving()
      Gm:startForceStand()
    end,
    onEnd = function()
      Gm:stopForceStand()
      if wasForceMoving then
        Gm:startForceMove()
      end
    end,
  })

  buffSeq:start()
  return buffSeq
end
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
  Gm:onModifierClick(ModifierKeys.Alt, function()
    if channeling then
      stopChanneling()
    else
      startChanneling()
    end
  end)

  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    -- 这里不能直接调用 Gm:forceTeleport，因为会打断引导
    Gm:clickKey(Keys.ActionBarSkill_3)
  end)

  Gm:createActions({
    -- 聚能爆破(Explosive Blast)
    {
      interval = Timing.MS_3F,
      func = function()
        if channeling then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end,
    },
    {
      interval = 1000 * 60 * 5,
      func = function()
        wizBuffs()
      end,
      shouldDeferExecution = function()
        return channeling == true
      end
    },
  })

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
  Gm:onModifierClick(ModifierKeys.Alt, function()
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
  Gm:onModifierClick(ModifierKeys.Shift, function()
    Gm:stopForceMove()
    stopMeteor()
  end)

  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    stopMeteor()
    Gm:forceTeleport()
  end)

  Gm:createActions({
    {
      interval = 1000 * 60 * 2.5,
      func = function()
        wizBuffs()
      end,
      shouldDeferExecution = function()
        return inMeteor == true
      end
    },
    -- Frost Nova/Black Hole
    {
      -- 随缘自动触发
      interval = 1000 * 2.5,
      key = Keys.ActionBarSkill_2,
      shouldDeferExecution = function()
        return inMeteor == false
      end
    },
  })

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
  Gm:onModifierClick(ModifierKeys.Alt, toggleStrafe)

  Gm:createActions({
    -- 战宠(Companion)
    -- 带翅膀(Shadow Power)戒律(Discipline)会不够, 宠物通用性和综合收益最好
    {
      interval = 1000,
      delay = 2000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_1)
        end
      end
    },
    -- 蓄势待发(Preparation)
    {
      interval = Timing.MS_3F,
      delay = 7500,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end
    },
    -- 烟雾(Smoke Screen)
    {
      interval = 1250,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_3)
        end
      end
    },
    -- 复仇(Vengeance)
    {
      interval = Timing.MS_3F,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    },
    -- 追踪箭(Hungering Arrow)
    {
      -- 高于 10F 在割草时容易掉动能
      interval = Timing.MS_9F,
      delay = Timing.MS_20F,
      func = function()
        if strafing then
          Gm:clickKey(Mouse.Left)
        end
      end
    }
  })

  toggleStrafe()
end

-- 三刀(扫射)
function Builds.DH:ImpaleStrafe()
  -- 扫射状态与启动序列
  local strafing = false
  local startStrafeSeq = Gm:createSequence({
    {
      func = function()
        -- 每次状态切换都重新激活一次翅膀(Shadow Power)和飞刀(Impale)
        Gm:clickKey(Keys.ActionBarSkill_1)
        Gm:clickKey(Keys.ActionBarSkill_3)
      end,
      wait = Timing.MS_6F,
    },
    {
      func = function()
        Gm:pressKey(Mouse.Right)
        strafing = true
      end,
    },
  })

  local function toggleStrafe()
    if strafing or startStrafeSeq:isRunning() then
      strafing = false
      startStrafeSeq:stop()
      Gm:releaseKey(Mouse.Right)
    else
      startStrafeSeq:start()
    end
  end
  Gm:onModifierClick(ModifierKeys.Ctrl, toggleStrafe)

  Gm:createActions({
    -- 烟雾(Smoke Screen - Vanishing Powder)
    {
      interval = 1000,
      delay = 2000,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end
    },
    -- 复仇(Vengeance)
    {
      interval = Timing.MS_3F,
      func = function()
        if strafing then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    },
    -- 左键
    {
      interval = Timing.MS_20F,
      delay = Timing.MS_12F,
      func = function()
        if strafing then
          Gm:clickKey(Mouse.Left)
        end
      end
    },
  })

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
  Gm:onModifierClick(ModifierKeys.Alt, function()
    if spikeTrapMode then
      stopSpikeTrap()
      Gm:startForceMove()
    elseif not Gm:isForceMoving() then
      Gm:startForceMove()
    else
      startSpikeTrap()
    end
  end)

  -- 拉怪连招序列
  local pullSequenceState = {}
  local pullCombo = Gm:createSequence({
    {
      func = function()
        Gm:clickKey(Mouse.Right)
        Gm:clickKey(Mouse.Right)
      end,
      wait = Timing.MS_12F
    },
    {
      func = function()
        Gm:clickKey(Mouse.Left)
        Gm:clickKey(Keys.ActionBarSkill_1)
      end,
      wait = Timing.MS_12F
    },
  }, {
    delay = Timing.MS_6F,
    onStart = function()
      pullSequenceState.isForceMoving = Gm:isForceMoving()
      pullSequenceState.isForceStanding = Gm:isForceStanding()
      pullSequenceState.isSpikeTrapMode = spikeTrapMode

      if spikeTrapMode then
        stopSpikeTrap()
      end
      Gm:startForceStand()
    end,
    onEnd = function()
      if pullSequenceState.isSpikeTrapMode then
        startSpikeTrap()
      elseif pullSequenceState.isForceMoving then
        Gm:startForceMove()
      elseif not pullSequenceState.isForceStanding then
        Gm:stopForceStand()
      end
    end
  })

  -- 拉怪
  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    pullCombo:toggle()
  end)
  -- free move
  Gm:onModifierClick(ModifierKeys.Shift, function()
    stopSpikeTrap()
    Gm:stopForceMove()
  end)

  Gm:createActions({
    -- 战宠(Companion)
    {
      interval = 1000,
      delay = 5000,
      key = Keys.ActionBarSkill_3,
    },
    -- 烟雾弹(Smoke Screen)
    {
      key = Keys.ActionBarSkill_2,
      onEachTick = function(sf)
        if spikeTrapMode then
          sf.interval = 1000
        else
          sf.interval = 2500
        end
      end
    },
    -- 复仇(Vengeance)
    {
      interval = Timing.MS_3F,
      delay = 1000,
      key = Keys.ActionBarSkill_4,
    },
    -- 闪避射击(Evasive Fire) + 铁蒺藜(Caltrops)
    {
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
    },
  })

  -- 初始铺陷阱序列 (非阻塞)
  local initTrapSeq = Gm:createSequence({
    {
      wait = 1000,
    },
  }, {
    onStart = function()
      Gm:pressKey(Mouse.Right)
    end,
    onEnd = function()
      Gm:releaseKey(Mouse.Right)
      Gm:startForceMove()
    end,
  })
  initTrapSeq:start()
end

--- MONK 武僧
-- 散件敲钟(圣化)
function Builds.Monk:SanctLoDWoL()
  -- 74 帧敲钟连招序列
  local wolCombo = Gm:createSequence({
    -- 开禅定
    { key = Keys.ActionBarSkill_4, wait = Timing.MS_6F },
    -- 再敲两钟
    { key = Mouse.Left,            wait = Timing.MS_6F },
    { key = Mouse.Left,            wait = Timing.MS_1F * 28 },
    -- 再两飓风破
    { key = Mouse.Right,           wait = Timing.MS_1F * 28 },
    { key = Mouse.Right,           wait = Timing.MS_6F },
  }, {
    onStart = function()
      Gm:startForceStand()
    end,
    onEnd = function()
      Gm:stopForceStand()
    end,
  })

  Gm:onModifierClick(ModifierKeys.Alt, function()
    wolCombo:toggle()
  end)

  -- 幻身决动态 interval
  local allyIter = Gm:makeCycleIterator({ 3000, 1000, 1000 })
  -- 灵光悟动态 interval
  local epiphanyIter = Gm:makeCycleIterator({ 4000, 1000, 1000, 1000, 1000 })
  -- 定义动作列表, 开始循环
  Gm:createActions({
    -- 幻身诀
    {
      key = Keys.ActionBarSkill_1,
      delay = 3000,
      func = function(sf)
        sf.interval = allyIter.next()
      end
    },
    -- 黑人灵光悟
    {
      func = function(sf)
        Gm:clickKey(Keys.ActionBarSkill_3)
        sf.interval = epiphanyIter.next()
      end
    },
  })
end

--- Crus 圣教军
-- 正义天拳
function Builds.Crus:AoVFist()
  -- 回城减伤序列 (停止移动 -> 站稳 12F -> 按 T -> 6F 补按 T -> 保持减伤读条 -> 恢复移动)
  local tpSequence = Gm:createSequence({
    {
      key = Keys.TownPortal,
      wait = Timing.MS_6F,
    },
    {
      key = Keys.TownPortal,
      wait = Timing.TownPortal,
    },
  }, {
    delay = Timing.MS_12F,
    onStart = function()
      Gm:stopForceMove()
    end,
    onEnd = function()
      Gm:startForceMove()
    end,
  })
  Gm:onModifierClick(ModifierKeys.Shift, function()
    tpSequence:toggle()
  end)

  -- 强制移动切换
  Gm:onModifierClick(ModifierKeys.Alt, function()
    if Gm:isForceMoving() then
      Gm:stopForceMove()
      tpSequence:stop()
    else
      Gm:startForceMove()
    end
  end)

  -- 跑马序列
  local steedSequence = Gm:createSequence({
    {
      func = function()
        Gm:clickKey(Keys.ActionBarSkill_1)
        Gm:clickKey(Keys.ActionBarSkill_2)
        Gm:clickKey(Keys.ActionBarSkill_4)
      end,
      wait = Timing.MS_6F
    },
    {
      key = Keys.ActionBarSkill_3,
      wait = Timing.MS_3F
    },
  }, {
    onStart = function()
      Gm:stopForceMove()
    end,
    onEnd = function()
      Gm:startForceMove()
    end
  })
  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    steedSequence:start()
  end)

  -- 宏停止时，清理可能存在回城状态
  Gm:onStop(function()
    Gm:cancelTownPortal()
  end)

  steedSequence:start()
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
  Gm:onModifierClick(ModifierKeys.Alt, function()
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
  Gm:onModifierClick(ModifierKeys.Shift, function()
    stopSiphon()
    Gm:stopForceMove()
  end)

  -- Blood Rush
  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    stopSiphon()
    Gm:forceTeleport()
  end)

  Gm:createActions({
    -- Command Skeletons
    {
      key = Keys.ActionBarSkill_1,
      onEachTick = function(sf)
        if siphoning then
          sf.interval = 1500
        else
          sf.interval = 2500
        end
      end
    },
    -- Army of the Dead
    {
      delay = 200,
      interval = Timing.MS_1F * 40,
      func = function()
        if siphoning then
          Gm:clickKey(Keys.ActionBarSkill_4)
        end
      end
    },
    -- Bone Armor
    {
      delay = 100,
      interval = 1000,
      func = function()
        if siphoning then
          Gm:clickKey(Mouse.Left)
        end
      end
    },
  })

  -- initial
  Gm:startForceMove()
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
  Gm:onModifierClick(ModifierKeys.Alt, function()
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
  Gm:onModifierClick(ModifierKeys.Shift, function()
    Gm:stopForceMove()
    stopSiphon()
  end)

  -- Blood Rush
  Gm:onModifierClick(ModifierKeys.Ctrl, function()
    stopSiphon()
    Gm:forceTeleport()
  end)

  Gm:createActions({
    -- Bone Armor
    {
      delay = 100,
      interval = 1000,
      func = function()
        if siphoning then
          Gm:clickKey(Keys.ActionBarSkill_2)
        end
      end
    },
  })

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
  Builds.DH:NatalyaSpikeTrap()
end)

-- 侧前键
Gm:setMouseAssignment(5, function()
  Builds.Nec:DeathNova()
end)
