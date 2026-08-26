local Create = {}
Create.Objects = {}

local function build(className, registryName)
	return function(properties)
		local obj = Instance.new(className)

		for key, value in pairs(properties) do
			if type(key) == "number" then
				value.Parent = obj
			elseif key == "Attributes" then
				for attrName, attrValue in pairs(value) do
					local ok, err = pcall(function()
						obj:SetAttribute(attrName, attrValue)
					end)
					if not ok then
						warn(("Create: failed to set attribute '%s' on %s (%s)"):format(attrName, className, err))
					end
				end
			else
				local ok, err = pcall(function()
					obj[key] = value
				end)
				if not ok then
					warn(("Create: failed to set '%s' on %s (%s)"):format(key, className, err))
				end
			end
		end

		if properties.Parent then
			obj.Parent = properties.Parent
		end

		if registryName then
			if Create.Objects[registryName] then
				warn(("Create: '%s' already exists in Objects, overwriting"):format(registryName))
			end
			Create.Objects[registryName] = obj
		end

		return obj
	end
end

Create.new = build

function Create.Get(name)
	local obj = Create.Objects[name]
	if not obj then
		warn(("Create: no object registered under '%s'"):format(name))
	end
	return obj
end

function Create.Remove(name)
	local obj = Create.Objects[name]
	if not obj then
		warn(("Create: no object registered under '%s'"):format(name))
		return
	end
	obj:Destroy()
	Create.Objects[name] = nil
end

setmetatable(Create, {
	__call = function(_, className, registryName)
		return build(className, registryName)
	end,
})

return Create
