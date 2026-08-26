--!strict

type RegistryMap = { [string]: Instance }
type PropertiesDict = { [any]: any }

const Create = {}
Create.Objects = {} :: RegistryMap
Create.SilentWarnings = true

const function Warn(message: string): ()
	if not Create.SilentWarnings then
		warn(message)
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
						Warn(`Create: failed to set attribute '{attrName}' on {className} ({err})`)
					end
				end
			elseif key == "Parent" then
			elseif type(value) == "function" then
    const ok, err = pcall(function()
     const signal = (obj :: any)[key]
     if typeof(signal) ~= "RBXScriptSignal" then
      error(`'{key}' is not an event`)
     end
     signal:Connect(value)
    end)
    if not ok then
     Warn(`Create: failed to connect '{key}' on {className} ({err})`)
    end
			else
				const ok, err = pcall(function()
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
	const obj: Instance? = Create.Objects[name]
	if not obj then
		Warn(`Create: no object registered under '{name}'`)
	end
	return obj
end

function Create.Destroy(name: string): ()
	const obj: Instance? = Create.Objects[name]
	if not obj then
		Warn(`Create: no object registered under '{name}'`)
		return
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
