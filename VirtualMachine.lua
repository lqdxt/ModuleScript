local VM = {}
VM.__index = VM

local PyList = {}
PyList.__index = PyList

function PyList.new(items)
	local self = setmetatable({}, PyList)
	self._data = items or {}
	return self
end

function PyList:append(item)
	table.insert(self._data, item)
	return nil
end

function PyList:pop(idx)
	idx = idx and (idx + 1) or #self._data
	return table.remove(self._data, idx)
end

function PyList:get(idx)
	return self._data[idx + 1]
end

function PyList:set(idx, val)
	self._data[idx + 1] = val
end

function PyList:__tostring()
	local parts = {}
	for _, v in ipairs(self._data) do
		table.insert(parts, tostring(v))
	end
	return "[" .. table.concat(parts, ", ") .. "]"
end

local Env = {}
Env.__index = Env

function Env.new(parent)
	return setmetatable({ vars = {}, parent = parent }, Env)
end

function Env:get(name)
	if self.vars[name] ~= nil then
		return self.vars[name]
	elseif self.parent then
		return self.parent:get(name)
	end
	return nil
end

function Env:set(name, val)
	self.vars[name] = val
end

local function getindent(line)
	local s = string.match(line, "^(%s*)")
	return s and #s or 0
end

local function splitlines(str)
	local lines = {}
	for line in string.gmatch(str .. "\n", "(.-)\r?\n") do
		table.insert(lines, line)
	end
	return lines
end

local function expression(expr, env)
	if not expr then return nil end
	expr = string.match(expr, "^%s*(.-)%s*$")
	if expr == "" then return nil end

	if expr == "True" then return true end
	if expr == "False" then return false end
	if expr == "None" then return nil end

	local s1 = string.match(expr, '^"(.*)"$')
	local s2 = string.match(expr, "^'(.*)'$")
	if s1 then return s1 end
	if s2 then return s2 end

	local num = tonumber(expr)
	if num then return num end

	if string.sub(expr, 1, 1) == "[" and string.sub(expr, -1) == "]" then
		local inner = string.sub(expr, 2, -2)
		local items = {}
		if string.match(inner, "%S") then
			local cleaned = string.gsub(inner, "(%d+)%.%s+(%d+)", "%1, %2")
			for item in string.gmatch(cleaned, "[^,]+") do
				table.insert(items, expression(item, env))
			end
		end
		return PyList.new(items)
	end

	local lhs, op, rhs = string.match(expr, "^(.-)%s*([%+%-*%/%==%!%<%>]+)%s*(.+)$")
	if lhs and op and rhs and not string.find(lhs, "[%[%(]") then
		local v1 = expression(lhs, env)
		local v2 = expression(rhs, env)
		if v1 ~= nil and v2 ~= nil then
			if op == "+" then return v1 + v2 end
			if op == "-" then return v1 - v2 end
			if op == "*" then return v1 * v2 end
			if op == "/" then return v1 / v2 end
			if op == "==" then return v1 == v2 end
			if op == "!=" then return v1 ~= v2 end
			if op == "<" then return v1 < v2 end
			if op == ">" then return v1 > v2 end
		end
	end

	local objName, method, argsStr = string.match(expr, "^([%w_]+)%.([%w_]+)%s*%((.*)%)$")
	if objName and method then
		local obj = env:get(objName)
		if obj and type(obj[method]) == "function" then
			local args = {}
			if argsStr and string.match(argsStr, "%S") then
				for arg in string.gmatch(argsStr, "[^,]+") do
					table.insert(args, expression(arg, env))
				end
			end
			return obj[method](obj, (table.unpack or unpack)(args))
		end
	end

	local funcName, argsStr = string.match(expr, "^([%w_]+)%s*%((.*)%)$")
	if funcName then
		local fn = env:get(funcName)
		if fn then
			local args = {}
			if argsStr and string.match(argsStr, "%S") then
				for arg in string.gmatch(argsStr, "[^,]+") do
					table.insert(args, expression(arg, env))
				end
			end
			return fn((table.unpack or unpack)(args))
		end
	end

	local arrName, idxStr = string.match(expr, "^([%w_]+)%s*%[(.+)%]$")
	if arrName and idxStr then
		local arr = env:get(arrName)
		local idx = expression(idxStr, env)
		if arr and type(arr.get) == "function" then
			return arr:get(idx)
		end
	end

	if string.match(expr, "^[%a_][%w_]*$") then
		return env:get(expr)
	end

	return nil
end

local ExecuteBlock

local function MakeFunction(params, bodyLines, parentEnv)
	return function(...)
		local args = { ... }
		local fnEnv = Env.new(parentEnv)
		for i, paramName in ipairs(params) do
			fnEnv:set(paramName, args[i])
		end
		return ExecuteBlock(bodyLines, fnEnv)
	end
end

ExecuteBlock = function(lines, env)
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local trimmed = string.match(line, "^%s*(.-)%s*$")

		if trimmed == "" or string.sub(trimmed, 1, 1) == "#" then
			i = i + 1
		elseif string.match(trimmed, "^def%s+") then
			local fnName, paramStr = string.match(trimmed, "^def%s+([%w_]+)%s*%((.*)%):")
			local params = {}
			if paramStr and string.match(paramStr, "%S") then
				for p in string.gmatch(paramStr, "[^,%s]+") do
					table.insert(params, p)
				end
			end

			local baseIndent = getindent(line)
			local bodyLines = {}
			i = i + 1
			while i <= #lines do
				local curLine = lines[i]
				local curTrimmed = string.match(curLine, "^%s*(.-)%s*$")
				if curTrimmed ~= "" and string.sub(curTrimmed, 1, 1) ~= "#" then
					if getindent(curLine) <= baseIndent then break end
				end
				table.insert(bodyLines, curLine)
				i = i + 1
			end

			env:set(fnName, MakeFunction(params, bodyLines, env))

		elseif string.match(trimmed, "^for%s+") then
			local varName, exprStr = string.match(trimmed, "^for%s+([%w_]+)%s+in%s+(.+):%s*$")
			local iterable = expression(exprStr, env)

			local baseIndent = getindent(line)
			local bodyLines = {}
			i = i + 1
			while i <= #lines do
				local curLine = lines[i]
				local curTrimmed = string.match(curLine, "^%s*(.-)%s*$")
				if curTrimmed ~= "" and string.sub(curTrimmed, 1, 1) ~= "#" then
					if getindent(curLine) <= baseIndent then break end
				end
				table.insert(bodyLines, curLine)
				i = i + 1
			end

			if iterable and iterable._data then
				for _, item in ipairs(iterable._data) do
					env:set(varName, item)
					local ret = ExecuteBlock(bodyLines, env)
					if ret ~= nil then return ret end
				end
			end

		elseif string.match(trimmed, "^if%s+") then
			local condStr = string.match(trimmed, "^if%s+(.+):%s*$")
			local condVal = expression(condStr, env)

			local baseIndent = getindent(line)
			local bodyLines = {}
			i = i + 1
			while i <= #lines do
				local curLine = lines[i]
				local curTrimmed = string.match(curLine, "^%s*(.-)%s*$")
				if curTrimmed ~= "" and string.sub(curTrimmed, 1, 1) ~= "#" then
					if getindent(curLine) <= baseIndent then break end
				end
				table.insert(bodyLines, curLine)
				i = i + 1
			end

			if condVal then
				local ret = ExecuteBlock(bodyLines, env)
				if ret ~= nil then return ret end
			end

		elseif string.match(trimmed, "^return%s*") then
			local exprStr = string.match(trimmed, "^return%s*(.*)$")
			if exprStr and exprStr ~= "" then
				return expression(exprStr, env)
			end
			return nil

		elseif string.match(trimmed, "^[%w_]+%s*=") then
			local varName, exprStr = string.match(trimmed, "^([%w_]+)%s*=%s*(.+)$")
			env:set(varName, expression(exprStr, env))
			i = i + 1

		else
			expression(trimmed, env)
			i = i + 1
		end
	end
	return nil
end

local global_env = Env.new()

global_env:set("print", function(...)
	local args = { ... }
	local out = {}
	for i = 1, select("#", ...) do
		table.insert(out, tostring(args[i]))
	end
	print(table.concat(out, " "))
end)

global_env:set("len", function(obj)
	if type(obj) == "table" and obj._data then
		return #obj._data
	elseif type(obj) == "string" or type(obj) == "table" then
		return #obj
	end
	return 0
end)

global_env:set("range", function(a, b, step)
	step = step or 1
	local start = b and a or 0
	local stop = b and b or a
	local list = {}
	for val = start, stop - 1, step do
		table.insert(list, val)
	end
	return PyList.new(list)
end)

function VM:Python(code)
	local lines = splitlines(code)
	return ExecuteBlock(lines, global_env)
end

return VM
