--!strict
--[[
  ModuleScript: LoopManager
  require it: require(path.LoopManager)
  or loadstring()
]]
local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

export type Callback = (...any) -> ()

export type BindOptions = {
 Priority: number?,
 Once: boolean?,
 Paused: boolean?,
}

export type CallbackMeta = {
 Priority: number,
 Once: boolean,
 Paused: boolean,
}

type LoopData = {
 callbacks: { [string]: Callback },
 meta: { [string]: CallbackMeta },
 order: { string },
 orderCache: { string }?,
 connection: RBXScriptConnection?,
 signal: RBXScriptSignal?,
 clientonly: boolean,
 firing: boolean,
 generation: number,
 pendingFire: any?,
}

type PlanEntry = {
 name: string,
 func: Callback,
 meta: CallbackMeta,
}

local LoopManager = {}

LoopManager.ProfilingEnabled = true
LoopManager.WarnOnOverwrite = false
LoopManager.WarnOnClientOnlyServerBind = false
LoopManager.YieldCheckEnabled = false
LoopManager.QueueReentrantFires = false

local loops: { [string]: LoopData } = {}
local running = false
local errorHandler: ((loopName: string, name: string, err: any) -> ())? = nil

local function SanitizePriority(priority: any): number
 if typeof(priority) ~= "number" or priority ~= priority then
  return 0
 end
 return priority
end

local function ReportError(loopName: string, name: string, err: any)
 if errorHandler then
  local ok, handlerErr = pcall(errorHandler, loopName, name, err)
  if not ok then
   warn(string.format("[LoopManager] OnError handler itself errored: %s", tostring(handlerErr)))
  end
 else
  warn(string.format("[LoopManager] '%s' errored in %s: %s", name, loopName, tostring(err)))
 end
end

local function FindInsertIndex(order: { string }, meta: { [string]: CallbackMeta }, priority: number): number
 local low = 1
 local high = #order

 while low <= high do
  local mid = math.floor((low + high) / 2)
  local midMeta = meta[order[mid]]
  local midPriority = midMeta and midMeta.Priority or 0

  if midPriority > priority then
   high = mid - 1
  else
   low = mid + 1
  end
 end

 return low
end

local function unbind(loopName: string, name: string)
 local loop = loops[loopName]
 if not loop or not loop.callbacks[name] then
  return
 end

 loop.callbacks[name] = nil
 loop.meta[name] = nil

 local order = loop.order
 local index = table.find(order, name)
 if index then
  table.remove(order, index)
 end

 loop.orderCache = nil
end

local function bind(loopName: string, name: string, func: Callback, options: BindOptions?)
 if name == "" then
  error("[LoopManager] Cannot bind: callback name must be a non-empty string.", 3)
 end

 if typeof(loopName) ~= "string" then
  error(string.format("[LoopManager] Cannot bind: expected 'loopName' to be a string, got %s", typeof(loopName)), 3)
 end

 if typeof(name) ~= "string" then
  error(string.format("[LoopManager] Cannot bind: expected 'name' to be a string, got %s", typeof(name)), 3)
 end

 local loop = loops[loopName]
 if not loop then
  error(string.format("[LoopManager] Unknown loop '%s'", loopName), 3)
 end

 if typeof(func) ~= "function" then
  error(string.format("[LoopManager] Cannot bind '%s': expected a function, got %s", name, typeof(func)), 3)
 end

 if loop.clientonly and not IsClient then
  if LoopManager.WarnOnClientOnlyServerBind then
   warn(string.format("[LoopManager] '%s' is client-only; ignoring bind '%s' on server", loopName, name))
  end
  return
 end

 local isNew = loop.callbacks[name] == nil
 if not isNew and LoopManager.WarnOnOverwrite then
  warn(string.format("[LoopManager] Overwriting existing callback '%s' in loop '%s'", name, loopName))
 end

 loop.callbacks[name] = func

 local info = loop.meta[name] or { Priority = 0, Once = false, Paused = false }
 loop.meta[name] = info

 local oldPriority = info.Priority

 if options then
  if options.Priority ~= nil then
   info.Priority = SanitizePriority(options.Priority)
  end
  if options.Once ~= nil then
   info.Once = options.Once
  end
  if options.Paused ~= nil then
   info.Paused = options.Paused
  end
 end

 if isNew then
  table.insert(loop.order, FindInsertIndex(loop.order, loop.meta, info.Priority), name)
  loop.orderCache = nil
 elseif info.Priority ~= oldPriority then
  local index = table.find(loop.order, name)
  if index then
   table.remove(loop.order, index)
  end
  table.insert(loop.order, FindInsertIndex(loop.order, loop.meta, info.Priority), name)
  loop.orderCache = nil
 end
end

local function FireInner(loop: LoopData, loopName: string, generation: number, ...: any)
 local names = loop.orderCache
 if not names then
  names = table.clone(loop.order)
  loop.orderCache = names
 end

 local callbacks = loop.callbacks
 local metaByName = loop.meta
 local profiling = LoopManager.ProfilingEnabled
 local checkYields = LoopManager.YieldCheckEnabled

 local plan = table.create(#names) :: { PlanEntry }
 local planCount = 0

 for i = 1, #names do
  local name = names[i]
  local func = callbacks[name]
  local meta = metaByName[name]

  if func and meta then
   planCount += 1
   plan[planCount] = {
    name = name,
    func = func,
    meta = {
     Priority = meta.Priority,
     Once = meta.Once,
     Paused = meta.Paused,
    },
   }
  end
 end

 for i = 1, planCount do
  if loop.generation ~= generation then
   break
  end

  local entry = plan[i]
  local meta = entry.meta

  if not meta.Paused then
   local name = entry.name
   local func = entry.func

   if profiling then
    debug.profilebegin(name)
   end

   local ok, err

   if checkYields then
    local co = coroutine.create(func)
    ok, err = coroutine.resume(co, ...)

    if coroutine.status(co) ~= "dead" then
     warn(string.format(
      "[LoopManager] Callback '%s' in '%s' yielded! Avoid yielding inside frame loops. The rest of this invocation has been aborted.",
      name,
      loopName
     ))
     local closed, closeErr = coroutine.close(co)
     if not closed then
      warn(string.format(
       "[LoopManager] Failed to close yielded coroutine for '%s' in '%s': %s",
       name,
       loopName,
       tostring(closeErr)
      ))
     end
    end
   else
    ok, err = pcall(func, ...)
   end

   if profiling then
    debug.profileend()
   end

   if not ok then
    ReportError(loopName, name, err)
   end

   if loop.generation == generation and loop.callbacks[name] == func and meta.Once then
    unbind(loopName, name)
   end
  end
 end
end

local function Fire(loopName: string, ...: any)
 local loop = loops[loopName]
 if not loop then
  return
 end

 if loop.firing then
  if LoopManager.QueueReentrantFires then
   if not loop.pendingFire then
    loop.pendingFire = {}
   end
   table.insert(loop.pendingFire, table.pack(...))
  else
   warn(string.format(
    "[LoopManager] '%s' fired again before its previous tick finished (a bound callback likely yielded without YieldCheckEnabled); skipping this tick. Set LoopManager.QueueReentrantFires = true to coalesce reentrant fires.",
    loopName
   ))
  end
  return
 end

 loop.firing = true

 local args: any = table.pack(...)
 repeat
  local generation = loop.generation
  local ok, err = pcall(FireInner, loop, loopName, generation, table.unpack(args, 1, args.n))
  if not ok then
   warn(string.format("[LoopManager] Internal error while firing '%s': %s", loopName, tostring(err)))
  end

  local nextArgs = nil
  if loop.pendingFire and #loop.pendingFire > 0 then
   nextArgs = table.remove(loop.pendingFire, 1)
  else
   nextArgs = nil
   loop.pendingFire = nil
  end
  args = nextArgs
 until args == nil

 loop.firing = false
end

local function ConnectLoop(loopName: string)
 local loop = loops[loopName]
 if not loop or (loop.clientonly and not IsClient) then
  return
 end
 if not loop.connection and loop.signal then
  loop.connection = loop.signal:Connect(function(...)
   Fire(loopName, ...)
  end)
 end
end

function LoopManager.CreateLoop(loopName: string, signal: RBXScriptSignal?, clientonly: boolean?): boolean
 if typeof(loopName) ~= "string" or loopName == "" then
  error(string.format("[LoopManager] Cannot create loop: expected a non-empty string name, got %s", typeof(loopName)), 2)
 end

 if loops[loopName] then
  warn(string.format("[LoopManager] Loop '%s' already exists; ignoring CreateLoop", loopName))
  return false
 end

 if signal ~= nil and typeof(signal) ~= "RBXScriptSignal" then
  error(string.format(
   "[LoopManager] Cannot create loop '%s': signal must be an RBXScriptSignal or nil (pass nil to defer, then call AssignSignal later)",
   loopName
  ), 2)
 end

 loops[loopName] = {
  callbacks = {},
  meta = {},
  order = {},
  orderCache = nil,
  connection = nil,
  signal = signal,
  clientonly = clientonly == true,
  firing = false,
  generation = 0,
  pendingFire = nil,
 }

 if running then
  ConnectLoop(loopName)
 end

 return true
end

function LoopManager.AssignSignal(loopName: string, signal: RBXScriptSignal): boolean
 local loop = loops[loopName]
 if not loop then
  error(string.format("[LoopManager] Cannot assign signal: unknown loop '%s'", loopName), 2)
 end

 if typeof(signal) ~= "RBXScriptSignal" then
  error(string.format("[LoopManager] Cannot assign signal to '%s': expected an RBXScriptSignal, got %s", loopName, typeof(signal)), 2)
 end

 if loop.signal then
  warn(string.format("[LoopManager] Loop '%s' already has a signal; ignoring AssignSignal", loopName))
  return false
 end

 loop.signal = signal
 if running then
  ConnectLoop(loopName)
 end

 return true
end

function LoopManager.DestroyLoop(loopName: string): boolean
 local loop = loops[loopName]
 if not loop then
  return false
 end

 loops[loopName] = nil
 loop.pendingFire = nil
 loop.generation += 1

 if loop.connection then
  loop.connection:Disconnect()
  loop.connection = nil
 end

 return true
end

function LoopManager.OnError(handler: ((loopName: string, name: string, err: any) -> ())?)
 errorHandler = handler
end

function LoopManager.Fire(loopName: string, ...: any)
 if typeof(loopName) ~= "string" then
  error(string.format("[LoopManager] Cannot fire: expected 'loopName' to be a string, got %s", typeof(loopName)), 2)
 end
 if not loops[loopName] then
  warn(string.format("[LoopManager] Cannot fire: unknown loop '%s'", loopName))
  return
 end
 Fire(loopName, ...)
end

function LoopManager.Pause(loopName: string, name: string)
 local loop = loops[loopName]
 local info = loop and loop.meta[name]
 if info then
  info.Paused = true
 end
end

function LoopManager.Resume(loopName: string, name: string)
 local loop = loops[loopName]
 local info = loop and loop.meta[name]
 if info then
  info.Paused = false
 end
end

function LoopManager.RenderStepped(name: string, func: Callback, options: BindOptions?)
 bind("RenderStepped", name, func, options)
end
function LoopManager.unRenderStepped(name: string)
 unbind("RenderStepped", name)
end

function LoopManager.Heartbeat(name: string, func: Callback, options: BindOptions?)
 bind("Heartbeat", name, func, options)
end
function LoopManager.unHeartbeat(name: string)
 unbind("Heartbeat", name)
end

function LoopManager.Stepped(name: string, func: Callback, options: BindOptions?)
 bind("Stepped", name, func, options)
end
function LoopManager.unStepped(name: string)
 unbind("Stepped", name)
end

function LoopManager.PreRender(name: string, func: Callback, options: BindOptions?)
 bind("PreRender", name, func, options)
end
function LoopManager.unPreRender(name: string)
 unbind("PreRender", name)
end

function LoopManager.PreAnimation(name: string, func: Callback, options: BindOptions?)
 bind("PreAnimation", name, func, options)
end
function LoopManager.unPreAnimation(name: string)
 unbind("PreAnimation", name)
end

function LoopManager.PreSimulation(name: string, func: Callback, options: BindOptions?)
 bind("PreSimulation", name, func, options)
end
function LoopManager.unPreSimulation(name: string)
 unbind("PreSimulation", name)
end

function LoopManager.PostSimulation(name: string, func: Callback, options: BindOptions?)
 bind("PostSimulation", name, func, options)
end
function LoopManager.unPostSimulation(name: string)
 unbind("PostSimulation", name)
end

function LoopManager.Bind(loopName: string, name: string, func: Callback, options: BindOptions?)
 bind(loopName, name, func, options)
end

function LoopManager.BindOnce(loopName: string, name: string, func: Callback, priority: number?)
 bind(loopName, name, func, { Priority = priority, Once = true })
end

function LoopManager.Unbind(loopName: string, name: string)
 unbind(loopName, name)
end

function LoopManager.UnbindAll(name: string)
 for loopName in pairs(loops) do
  unbind(loopName, name)
 end
end

function LoopManager:StartLoops()
 running = true
 for loopName in pairs(loops) do
  ConnectLoop(loopName)
 end
end

function LoopManager:StopLoops()
 running = false
 for _, loop in pairs(loops) do
  if loop.connection then
   loop.connection:Disconnect()
   loop.connection = nil
  end
 end
end

function LoopManager.IsRunning(): boolean
 return running
end

function LoopManager.Reset()
 LoopManager.StopLoops()
 for _, loop in pairs(loops) do
  loop.generation += 1
  loop.callbacks = {}
  loop.meta = {}
  loop.order = {}
  loop.orderCache = nil
  loop.pendingFire = nil
 end
end

function LoopManager.GetLoopNames(): { string }
 local names: { string } = {}
 for loopName in pairs(loops) do
  table.insert(names, loopName)
 end
 return names
end

function LoopManager.GetBoundNames(loopName: string): { string }
 local loop = loops[loopName]
 if not loop then
  return {}
 end
 return table.clone(loop.order)
end

function LoopManager.IsBound(loopName: string, name: string): boolean
 local loop = loops[loopName]
 return loop ~= nil and loop.callbacks[name] ~= nil
end

function LoopManager.IsPaused(loopName: string, name: string): boolean
 local loop = loops[loopName]
 local info = loop and loop.meta[name]
 return info ~= nil and info.Paused == true
end

function LoopManager.GetInfo(loopName: string, name: string): CallbackMeta?
 local loop = loops[loopName]
 local info = loop and loop.meta[name]
 if not info then
  return nil
 end
 return {
  Priority = info.Priority,
  Once = info.Once,
  Paused = info.Paused,
 }
end

if IsClient then
 LoopManager.CreateLoop("RenderStepped", RunService.RenderStepped, true)
 LoopManager.CreateLoop("PreRender", RunService.PreRender, true)
 LoopManager.CreateLoop("PreAnimation", RunService.PreAnimation, true)
else
 LoopManager.CreateLoop("RenderStepped", nil, true)
 LoopManager.CreateLoop("PreRender", nil, true)
 LoopManager.CreateLoop("PreAnimation", nil, true)
end

LoopManager.CreateLoop("Heartbeat", RunService.Heartbeat, false)
LoopManager.CreateLoop("Stepped", RunService.Stepped, false)
LoopManager.CreateLoop("PreSimulation", RunService.PreSimulation, false)
LoopManager.CreateLoop("PostSimulation", RunService.PostSimulation, false)

return LoopManager
