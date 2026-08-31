--[[
 ModuleScript: 'Create' or your namings. put it in ReplicatedStorage

 usage:

 local x = Create("Folder") {
  Name = "MyFolder",
  Parent = workspace
 }

 if you dont want locals:

 Create("Folder", "MyFolder) {...}

 then use the Object table to access it

 nested children:

 Create("ScreenGui", "MainGui") {
  Parent = playerGui,
  Create("Frame", "MainFrame") {
   Size = UDim2.new(0, 300, 0, 200),
   BackgroundColor3 = Color3.new(1, 1, 1),
   Create("UICorner") { CornerRadius = UDim.new(0, 8) },
   Create("TextLabel", "Title") {
    Text = "Hello",
    Size = UDim2.new(1, 0, 0, 40),
   },
  },
 }
]]

--!strict

type RegistryMap = { [string]: Instance }
type PropertiesDict = { [any]: any }
type ConnectionMap = { [string]: RBXScriptConnection }

local Create = {}
Create.Objects = {} :: RegistryMap
Create.Connections = {} :: { [Instance]: ConnectionMap }
Create.SilentWarnings = true

local function Warn(message: string): ()
	if not Create.SilentWarnings then
		warn(message)
	end
end

local function build(className: string, registryName: string?): (properties: PropertiesDict) -> Instance
	return function(properties: PropertiesDict): Instance
		local obj = Instance.new(className)

		for key, value in properties do
			if type(key) == "number" then
				(value :: Instance).Parent = obj
			elseif key == "Attributes" then
				for attrName, attrValue in (value :: { [string]: any }) do
					local ok, err = pcall(function()
						obj:SetAttribute(attrName, attrValue)
					end)
					if not ok then
						Warn(`Create: failed to set attribute '{attrName}' on {className} ({err})`)
					end
				end
			elseif key == "Events" then
				for eventName, handler in (value :: { [string]: (...any) -> () }) do
					local ok, connOrErr = pcall(function()
						return (obj :: any)[eventName]:Connect(handler)
					end)
					if ok then
						if not Create.Connections[obj] then
							Create.Connections[obj] = {}
						end
						(Create.Connections[obj] :: ConnectionMap)[eventName] = connOrErr :: RBXScriptConnection
					else
						Warn(`Create: failed to connect event '{eventName}' on {className} ({connOrErr})`)
					end
				end
			else
				local ok, err = pcall(function()
					(obj :: any)[key] = value
				end)
				if not ok then
					Warn(`Create: failed to set '{key}' on {className} ({err})`)
				end
			end
		end

		if properties.Parent then
			obj.Parent = properties.Parent :: Instance
		end

		if registryName then
			if Create.Objects[registryName] then
				Warn(`Create: '{registryName}' already exists in Objects, overwriting`)
			end
			Create.Objects[registryName] = obj
		end

		return obj
	end
end

Create.new = build

function Create.Get(name: string): Instance?
	local obj: Instance? = Create.Objects[name]
	if not obj then
		Warn(`Create: no object registered under '{name}'`)
	end
	return obj
end

function Create.Disconnect(name: string, eventName: string?): ()
	local obj: Instance? = Create.Objects[name]
	if not obj then
		Warn(`Create: no object registered under '{name}'`)
		return
	end

	local conns = Create.Connections[obj :: Instance]
	if not conns then
		Warn(`Create: no tracked connections for '{name}'`)
		return
	end

	if eventName then
		local conn = conns[eventName]
		if conn then
			conn:Disconnect()
			conns[eventName] = nil
		else
			Warn(`Create: no tracked connection for event '{eventName}' on '{name}'`)
		end
	else
		for evName, conn in conns do
			conn:Disconnect()
			conns[evName] = nil
		end
		Create.Connections[obj :: Instance] = nil
	end
end

function Create.Destroy(name: string): ()
	local obj: Instance? = Create.Objects[name]
	if not obj then
		Warn(`Create: no object registered under '{name}'`)
		return
	end

	local conns = Create.Connections[obj]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		Create.Connections[obj] = nil
	end

	obj:Destroy()
	Create.Objects[name] = nil
end

setmetatable(Create, {
	__call = function(_: any, className: string, registryName: string?)
		return build(className, registryName)
	end,
})

return Create
