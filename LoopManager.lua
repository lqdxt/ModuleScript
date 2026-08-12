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
	signal: RBXScriptSignal,
	clientonly: boolean,
}

local LoopManager = {}

LoopManager.ProfilingEnabled = true

local loops: { [string]: LoopData } = {}
local running = false
local errorHandler: ((loopName: string, name: string, err: any) -> ())? = nil

local function reportError(loopName: string, name: string, err: any)
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
	for i = 1, #order do
		local info = meta[order[i]]
		if info and info.Priority > priority then
			return i
		end
	end
	return #order + 1
end

local function unbind(loopName: string, name: string)
	local loop = loops[loopName]
	if not loop or not loop.callbacks[name] then
		return
	end

	loop.callbacks[name] = nil
	loop.meta[name] = nil

	local order = loop.order
	for i = 1, #order do
		if order[i] == name then
			table.remove(order, i)
			break
		end
	end

	loop.orderCache = nil
end

local function bind(loopName: string, name: string, func: Callback, options: BindOptions?)
	local loop = loops[loopName]
	if not loop then
		error(string.format("[LoopManager] Unknown loop '%s'", loopName), 3)
	end

	if typeof(func) ~= "function" then
		error(string.format("[LoopManager] Cannot bind '%s': expected a function, got %s", name, typeof(func)), 3)
	end

	if loop.clientonly and not IsClient then
		warn(string.format("[LoopManager] '%s' is client-only; ignoring bind '%s' on the server", loopName, name))
		return
	end

	loop.callbacks[name] = func

	local isNew = loop.meta[name] == nil
	local info = loop.meta[name] or { Priority = 0, Once = false, Paused = false }
	loop.meta[name] = info

	local oldPriority = info.Priority

	if options then
		if options.Priority ~= nil then
			info.Priority = options.Priority
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
		local order = loop.order
		for i = 1, #order do
			if order[i] == name then
				table.remove(order, i)
				break
			end
		end
		table.insert(order, FindInsertIndex(order, loop.meta, info.Priority), name)
		loop.orderCache = nil
	end
end

local function Fire(loopName: string, ...: any)
	local loop = loops[loopName]
	if not loop then
		return
	end

	local order = loop.orderCache
	if not order then
		order = table.clone(loop.order)
		loop.orderCache = order
	end

	local meta = loop.meta
	local profiling = LoopManager.ProfilingEnabled

	for i = 1, #order do
		local name = order[i]
		local func = loop.callbacks[name]
		if func then
			local info = meta[name]
			if not (info and info.Paused) then
				if profiling then
					debug.profilebegin(name)
				end

				local ok, err = pcall(func, ...)

				if profiling then
					debug.profileend()
				end

				if not ok then
					reportError(loopName, name, err)
				end

				if info and info.Once then
					unbind(loopName, name)
				end
			end
		end
	end
end

local function ConnectLoop(loopName: string)
	local loop = loops[loopName]
	if not loop then
		return
	end
	if loop.clientonly and not IsClient then
		return
	end
	if not loop.connection then
		loop.connection = loop.signal:Connect(function(...)
			Fire(loopName, ...)
		end)
	end
end

function LoopManager.CreateLoop(loopName: string, signal: RBXScriptSignal, clientonly: boolean?): boolean
	if loops[loopName] then
		warn(string.format("[LoopManager] Loop '%s' already exists; ignoring CreateLoop", loopName))
		return false
	end

	if typeof(signal) ~= "RBXScriptSignal" then
		error(string.format("[LoopManager] Cannot create loop '%s': signal must be an RBXScriptSignal", loopName), 2)
	end

	loops[loopName] = {
		callbacks = {},
		meta = {},
		order = {},
		orderCache = nil,
		connection = nil,
		signal = signal,
		clientonly = clientonly == true,
	}

	if running then
		ConnectLoop(loopName)
	end

	return true
end

function LoopManager.OnError(handler: ((loopName: string, name: string, err: any) -> ())?)
	errorHandler = handler
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

function LoopManager.StartLoops()
	running = true
	for loopName in pairs(loops) do
		ConnectLoop(loopName)
	end
end

function LoopManager.StopLoops()
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
		table.clear(loop.callbacks)
		table.clear(loop.meta)
		table.clear(loop.order)
		loop.orderCache = nil
	end
end

function LoopManager.GetLoopNames(): { string }
	local names = {}
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

LoopManager.CreateLoop("RenderStepped", RunService.RenderStepped, true)
LoopManager.CreateLoop("Heartbeat", RunService.Heartbeat, false)
LoopManager.CreateLoop("Stepped", RunService.Stepped, false)
LoopManager.CreateLoop("PreRender", RunService.PreRender, true)
LoopManager.CreateLoop("PreAnimation", RunService.PreAnimation, true)
LoopManager.CreateLoop("PreSimulation", RunService.PreSimulation, false)
LoopManager.CreateLoop("PostSimulation", RunService.PostSimulation, false)

return LoopManager
