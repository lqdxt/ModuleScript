--!strict

type RegistryMap = { [string]: Instance }
type PropertiesDict = { [any]: any }
type ConnectionList = { RBXScriptConnection }

const Create = {}

const Objects = {} :: RegistryMap
Create.Objects = Objects

const connectionsByObject = setmetatable({}, { __mode = "k" }) :: { [Instance]: ConnectionList }
Create.Connections = {} :: { [string]: ConnectionList }

Create.SilentWarnings = true

const function console(message: string): ()
	if not Create.SilentWarnings then
		warn(message)
	end
end

const function track(obj: Instance, registryName: string?, conn: RBXScriptConnection): ()
	const list = connectionsByObject[obj] or {}
	table.insert(list, conn)
	connectionsByObject[obj] = list

	if registryName then
		const namedList = Create.Connections[registryName] or {}
		table.insert(namedList, conn)
		Create.Connections[registryName] = namedList
	end
end

const function list(list: ConnectionList?): ()
	if not list then
		return
	end
	for _, conn in list do
		const ok, err = pcall(function()
			if conn.Connected then
				conn:Disconnect()
			end
		end)
		if not ok then
			console(`Create: failed to disconnect connection ({err})`)
		end
	end
end

const function connect(obj: Instance, className: string, eventName: string, handler: (...any) -> (), registryName: string?): ()
	const ok, err = pcall(function()
		const signal = (obj :: any)[eventName]
		if typeof(signal) ~= "RBXScriptSignal" then
			error(`'{eventName}' is not an event`)
		end
		const conn = (signal :: RBXScriptSignal):Connect(handler)
		track(obj, registryName, conn)
	end)
	if not ok then
		console(`Create: failed to connect '{eventName}' on {className} ({err})`)
	end
end

const function build(className: string, registryName: string?): (properties: PropertiesDict) -> Instance
	return function(properties: PropertiesDict): Instance
		const obj = Instance.new(className)

		for key, value in properties do
			if type(key) == "number" then
				(value :: Instance).Parent = obj
			elseif key == "Attributes" then
				for attrName, attrValue in (value :: { [string]: any }) do
					const ok, err = pcall(function()
						obj:SetAttribute(attrName, attrValue)
					end)
					if not ok then
						console(`Create: failed to set attribute '{attrName}' on {className} ({err})`)
					end
				end
			elseif key == "Events" then
				for eventName, handlerOrList in (value :: { [string]: any }) do
					if type(handlerOrList) == "table" then
						for _, handler in handlerOrList :: { (...any) -> () } do
							connect(obj, className, eventName, handler, registryName)
						end
					else
						connect(obj, className, eventName, handlerOrList, registryName)
					end
				end
			elseif key == "Parent" then
			elseif type(value) == "function" then
				connect(obj, className, key :: string, value, registryName)
			else
				const ok, err = pcall(function()
					(obj :: any)[key] = value
				end)
				if not ok then
					console(`Create: failed to set '{key}' on {className} ({err})`)
				end
			end
		end

		if properties.Parent then
			obj.Parent = properties.Parent :: Instance
		end

		if registryName then
			if Objects[registryName] then
				console(`Create: '{registryName}' already exists in Objects, overwriting`)
			end
			Objects[registryName] = obj
		end

		const destroyingConn = obj.Destroying:Connect(function()
			list(connectionsByObject[obj])
			connectionsByObject[obj] = nil
			if registryName then
				Create.Connections[registryName] = nil
				if Objects[registryName] == obj then
					Objects[registryName] = nil
				end
			end
		end)
		track(obj, registryName, destroyingConn)

		return obj
	end
end

Create.new = build

function Create.Get(name: string): Instance?
	const obj: Instance? = Objects[name]
	if not obj then
		console(`Create: no object registered under '{name}'`)
	end
	return obj
end

function Create.Disconnect(target: string | Instance): ()
	if type(target) == "string" then
		list(Create.Connections[target])
		Create.Connections[target] = nil
		const obj = Objects[target]
		if obj then
			connectionsByObject[obj] = nil
		end
	else
		list(connectionsByObject[target])
		connectionsByObject[target] = nil
	end
end

function Create.GetConnections(target: string | Instance): ConnectionList?
	if type(target) == "string" then
		return Create.Connections[target]
	end
	return connectionsByObject[target]
end

function Create.Destroy(name: string): ()
	const obj: Instance? = Objects[name]
	if not obj then
		console(`Create: no object registered under '{name}'`)
		return
	end
	obj:Destroy()
end

setmetatable(Create, {
	__call = function(_: any, className: string, registryName: string?)
		return build(className, registryName)
	end,
})

return Create
