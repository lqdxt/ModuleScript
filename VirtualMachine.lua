local VM = {
	modules = {},
	loaded_modules = {}
}
VM.__index = VM

local PyList = {}
PyList.__index = PyList

function PyList.new(items)
	return setmetatable({ _data = items or {} }, PyList)
end

function PyList:append(item)
	table.insert(self._data, item)
	return nil
end

function PyList:extend(iterable)
	if type(iterable) == "table" and iterable._data then
		for _, item in ipairs(iterable._data) do
			table.insert(self._data, item)
		end
	end
end

function PyList:pop(idx)
	idx = idx and (idx < 0 and #self._data + idx + 1 or idx + 1) or #self._data
	return table.remove(self._data, idx)
end

function PyList:insert(idx, item)
	table.insert(self._data, idx + 1, item)
end

function PyList:remove(item)
	for i, v in ipairs(self._data) do
		if v == item then
			table.remove(self._data, i)
			return
		end
	end
	error("ValueError: list.remove(x): x not in list")
end

function PyList:get(idx)
	if idx < 0 then idx = #self._data + idx end
	return self._data[idx + 1]
end

function PyList:set(idx, val)
	if idx < 0 then idx = #self._data + idx end
	self._data[idx + 1] = val
end

function PyList:slice(start_idx, stop_idx, step)
	step = step or 1
	local len = #self._data
	start_idx = start_idx or (step > 0 and 0 or len - 1)
	stop_idx = stop_idx or (step > 0 and len or -len - 1)

	if start_idx < 0 then start_idx = len + start_idx end
	if stop_idx < 0 then stop_idx = len + stop_idx end

	local res = {}
	if step > 0 then
		for i = start_idx + 1, math.min(stop_idx, len), step do
			table.insert(res, self._data[i])
		end
	else
		for i = start_idx + 1, math.max(stop_idx + 2, 1), step do
			table.insert(res, self._data[i])
		end
	end
	return PyList.new(res)
end

function PyList:__tostring()
	local parts = {}
	for _, v in ipairs(self._data) do
		table.insert(parts, type(v) == "string" and ("'" .. v .. "'") or tostring(v))
	end
	return "[" .. table.concat(parts, ", ") .. "]"
end

local PyDict = {}
PyDict.__index = PyDict

function PyDict.new(kv)
	local obj = setmetatable({ _data = {}, _keys = {} }, PyDict)
	if kv then
		for k, v in pairs(kv) do obj:set(k, v) end
	end
	return obj
end

function PyDict:get(key, default)
	local v = self._data[key]
	return v ~= nil and v or default
end

function PyDict:set(key, val)
	if self._data[key] == nil then
		table.insert(self._keys, key)
	end
	self._data[key] = val
end

function PyDict:keys()
	return PyList.new(self._keys)
end

function PyDict:values()
	local vals = {}
	for _, k in ipairs(self._keys) do table.insert(vals, self._data[k]) end
	return PyList.new(vals)
end

function PyDict:items()
	local pairs_list = {}
	for _, k in ipairs(self._keys) do
		table.insert(pairs_list, PyList.new({ k, self._data[k] }))
	end
	return PyList.new(pairs_list)
end

function PyDict:__tostring()
	local parts = {}
	for _, k in ipairs(self._keys) do
		local k_str = type(k) == "string" and ("'" .. k .. "'") or tostring(k)
		local v_str = type(self._data[k]) == "string" and ("'" .. self._data[k] .. "'") or tostring(self._data[k])
		table.insert(parts, k_str .. ": " .. v_str)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local PyTuple = {}
PyTuple.__index = PyTuple

function PyTuple.new(items)
	return setmetatable({ _data = items or {} }, PyTuple)
end

function PyTuple:get(idx)
	if idx < 0 then idx = #self._data + idx end
	return self._data[idx + 1]
end

function PyTuple:__tostring()
	local parts = {}
	for _, v in ipairs(self._data) do table.insert(parts, tostring(v)) end
	return "(" .. table.concat(parts, ", ") .. ")"
end

local PyClass = {}
PyClass.__index = PyClass

function PyClass.new(name, bases, methods)
	local cls = setmetatable({
		__name__ = name,
		__bases__ = bases or {},
		__methods__ = methods or {}
	}, PyClass)
	return cls
end

function PyClass:lookup(method_name)
	if self.__methods__[method_name] ~= nil then
		return self.__methods__[method_name]
	end
	for _, base in ipairs(self.__bases__) do
		local m = base:lookup(method_name)
		if m ~= nil then return m end
	end
	return nil
end

local PyInstance = {}
PyInstance.__index = PyInstance

function PyInstance.new(cls, args, kwargs)
	local inst = setmetatable({ __class__ = cls, __dict__ = {} }, PyInstance)
	local init = cls:lookup("__init__")
	if init then
		init(inst, (table.unpack or unpack)(args or {}))
	end
	return inst
end

function PyInstance:get_attr(name)
	if self.__dict__[name] ~= nil then
		return self.__dict__[name]
	end
	local method = self.__class__:lookup(name)
	if type(method) == "function" then
		return function(...) return method(self, ...) end
	end
	return method
end

function PyInstance:set_attr(name, val)
	self.__dict__[name] = val
end

function PyInstance:__tostring()
	local str_method = self:get_attr("__str__")
	if type(str_method) == "function" then
		return str_method()
	end
	return "<" .. self.__class__.__name__ .. " instance>"
end

local Env = {}
Env.__index = Env

function Env.new(parent)
	return setmetatable({ vars = {}, parent = parent, globals = parent and parent.globals or nil }, Env)
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

local KEYWORDS = {
	["def"]=true, ["class"]=true, ["if"]=true, ["elif"]=true, ["else"]=true,
	["while"]=true, ["for"]=true, ["in"]=true, ["not"]=true, ["and"]=true,
	["or"]=true, ["return"]=true, ["import"]=true, ["from"]=true, ["as"]=true,
	["try"]=true, ["except"]=true, ["finally"]=true, ["raise"]=true, ["pass"]=true,
	["break"]=true, ["continue"]=true, ["lambda"]=true, ["True"]=true, ["False"]=true,
	["None"]=true, ["is"]=true
}

local function tokenize(code)
	local tokens = {}
	local lines = {}
	for line in string.gmatch(code .. "\n", "(.-)\r?\n") do
		table.insert(lines, line)
	end

	local indent_stack = {0}

	for line_idx, line in ipairs(lines) do
		local content = string.match(line, "^%s*(.-)%s*$")
		if content ~= "" and string.sub(content, 1, 1) ~= "#" then
			local indent_str = string.match(line, "^(%s*)")
			local indent = #indent_str

			if indent > indent_stack[#indent_stack] then
				table.insert(indent_stack, indent)
				table.insert(tokens, { type = "INDENT", line = line_idx })
			else
				while indent < indent_stack[#indent_stack] do
					table.remove(indent_stack)
					table.insert(tokens, { type = "DEDENT", line = line_idx })
				end
			end

			local pos = 1
			local len = #line
			while pos <= len do
				local c = string.sub(line, pos, pos)

				if string.match(c, "%s") then
					pos = pos + 1
				elseif c == "#" then
					break
				elseif string.match(line, "^f[\"']", pos) then
					local quote = string.sub(line, pos + 1, pos + 1)
					local e = string.find(line, quote, pos + 2, true)
					local str_val = string.sub(line, pos + 2, (e or (len + 1)) - 1)
					table.insert(tokens, { type = "FSTRING", value = str_val, line = line_idx })
					pos = (e or len) + 1
				elseif c == '"' or c == "'" then
					local e = string.find(line, c, pos + 1, true)
					local str_val = string.sub(line, pos + 1, (e or (len + 1)) - 1)
					table.insert(tokens, { type = "STRING", value = str_val, line = line_idx })
					pos = (e or len) + 1
				elseif string.match(line, "^%d+%.?%d*", pos) then
					local num_str = string.match(line, "^%d+%.?%d*", pos)
					table.insert(tokens, { type = "NUMBER", value = tonumber(num_str), line = line_idx })
					pos = pos + #num_str
				elseif string.match(line, "^[%a_][%w_]*", pos) then
					local name = string.match(line, "^[%a_][%w_]*", pos)
					if KEYWORDS[name] then
						table.insert(tokens, { type = "KEYWORD", value = name, line = line_idx })
					else
						table.insert(tokens, { type = "NAME", value = name, line = line_idx })
					end
					pos = pos + #name
				else
					local double_op = string.sub(line, pos, pos + 1)
					if double_op == "==" or double_op == "!=" or double_op == "<=" or double_op == ">=" or
					   double_op == "+=" or double_op == "-=" or double_op == "*=" or double_op == "/=" or
					   double_op == "//" or double_op == "**" then
						table.insert(tokens, { type = "OPERATOR", value = double_op, line = line_idx })
						pos = pos + 2
					else
						table.insert(tokens, { type = "DELIMITER", value = c, line = line_idx })
						pos = pos + 1
					end
				end
			end
			table.insert(tokens, { type = "NEWLINE", line = line_idx })
		end
	end

	while #indent_stack > 1 do
		table.remove(indent_stack)
		table.insert(tokens, { type = "DEDENT" })
	end

	return tokens
end

local function parse_and_eval(tokens, env)
	local pos = 1

	local function peek(offset)
		return tokens[pos + (offset or 0)]
	end

	local function match(type, val)
		local t = peek()
		if t and t.type == type and (val == nil or t.value == val) then
			pos = pos + 1
			return t
		end
		return nil
	end

	local eval_expr
	local eval_block

	local function parse_primary()
		local t = peek()
		if not t then return nil end

		if match("NUMBER") then return t.value end
		if match("STRING") then return t.value end
		if match("FSTRING") then
			local str = t.value
			return (string.gsub(str, "{(.-)}", function(expr)
				local sub_toks = tokenize(expr)
				local res = parse_and_eval(sub_toks, env)
				return tostring(res)
			end))
		end
		if match("KEYWORD", "True") then return true end
		if match("KEYWORD", "False") then return false end
		if match("KEYWORD", "None") then return nil end

		if match("NAME") then
			local var_name = t.value
			return env:get(var_name)
		end

		if match("DELIMITER", "[") then
			local items = {}
			if not match("DELIMITER", "]") then
				repeat
					table.insert(items, eval_expr())
				until not match("DELIMITER", ",")
				match("DELIMITER", "]")
			end
			return PyList.new(items)
		end

		if match("DELIMITER", "{") then
			local dict_data = {}
			if not match("DELIMITER", "}") then
				repeat
					local k = eval_expr()
					match("DELIMITER", ":")
					local v = eval_expr()
					dict_data[k] = v
				until not match("DELIMITER", ",")
				match("DELIMITER", "}")
			end
			return PyDict.new(dict_data)
		end

		if match("DELIMITER", "(") then
			local val = eval_expr()
			match("DELIMITER", ")")
			return val
		end

		pos = pos + 1
		return nil
	end

	local function parse_postfix()
		local left = parse_primary()

		while true do
			if match("DELIMITER", "(") then
				local args = {}
				if not match("DELIMITER", ")") then
					repeat
						table.insert(args, eval_expr())
					until not match("DELIMITER", ",")
					match("DELIMITER", ")")
				end

				if type(left) == "function" then
					left = left((table.unpack or unpack)(args))
				elseif getmetatable(left) == PyClass then
					left = PyInstance.new(left, args)
				end
			elseif match("DELIMITER", ".") then
				local attr_tok = match("NAME")
				if attr_tok and left then
					local attr = attr_tok.value
					if getmetatable(left) == PyInstance then
						left = left:get_attr(attr)
					elseif getmetatable(left) == Env then
						left = left:get(attr)
					elseif type(left) == "table" and left[attr] ~= nil then
						left = left[attr]
					end
				end
			elseif match("DELIMITER", "[") then
				local idx = eval_expr()
				local stop_idx = nil
				if match("DELIMITER", ":") then
					stop_idx = eval_expr()
				end
				match("DELIMITER", "]")

				if stop_idx ~= nil or peek(-2).value == ":" then
					if left and left.slice then
						left = left:slice(idx, stop_idx)
					end
				else
					if left and left.get then
						left = left:get(idx)
					elseif type(left) == "table" then
						left = left[idx]
					end
				end
			else
				break
			end
		end

		return left
	end

	eval_expr = function()
		local left = parse_postfix()

		local op = match("OPERATOR") or match("DELIMITER") or match("KEYWORD")
		if op then
			local right = eval_expr()
			local v = op.value
			if v == "+" then return left + right end
			if v == "-" then return left - right end
			if v == "*" then return left * right end
			if v == "/" then return left / right end
			if v == "//" then return math.floor(left / right) end
			if v == "%" then return left % right end
			if v == "**" then return left ^ right end
			if v == "==" then return left == right end
			if v == "!=" then return left ~= right end
			if v == "<" then return left < right end
			if v == ">" then return left > right end
			if v == "<=" then return left <= right end
			if v == ">=" then return left >= right end
			if v == "and" then return left and right end
			if v == "or" then return left or right end
			if v == "in" then
				if right and right._data then
					for _, item in ipairs(right._data) do
						if item == left then return true end
					end
				end
				return false
			end
		end

		return left
	end

	eval_block = function()
		local block_tokens = {}
		match("NEWLINE")
		if match("INDENT") then
			local depth = 1
			while pos <= #tokens and depth > 0 do
				local t = tokens[pos]
				if t.type == "INDENT" then depth = depth + 1 end
				if t.type == "DEDENT" then depth = depth - 1 end
				if depth > 0 then
					table.insert(block_tokens, t)
				end
				pos = pos + 1
			end
		end
		return block_tokens
	end

	local last_val = nil

	while pos <= #tokens do
		local t = peek()

		if match("KEYWORD", "def") then
			local fn_name = match("NAME").value
			match("DELIMITER", "(")
			local params = {}
			if not match("DELIMITER", ")") then
				repeat
					table.insert(params, match("NAME").value)
				until not match("DELIMITER", ",")
				match("DELIMITER", ")")
			end
			match("DELIMITER", ":")
			local body = eval_block()

			env:set(fn_name, function(...)
				local args = { ... }
				local fn_env = Env.new(env)
				for i, p in ipairs(params) do
					fn_env:set(p, args[i])
				end
				return parse_and_eval(body, fn_env)
			end)

		elseif match("KEYWORD", "class") then
			local class_name = match("NAME").value
			local bases = {}
			if match("DELIMITER", "(") then
				repeat
					local base_name = match("NAME").value
					table.insert(bases, env:get(base_name))
				until not match("DELIMITER", ",")
				match("DELIMITER", ")")
			end
			match("DELIMITER", ":")
			local body = eval_block()

			local class_env = Env.new(env)
			parse_and_eval(body, class_env)

			local cls = PyClass.new(class_name, bases, class_env.vars)
			env:set(class_name, cls)

		elseif match("KEYWORD", "if") then
			local cond = eval_expr()
			match("DELIMITER", ":")
			local body = eval_block()

			if cond then
				last_val = parse_and_eval(body, env)
			end

		elseif match("KEYWORD", "while") then
			local cond_pos = pos
			local cond = eval_expr()
			match("DELIMITER", ":")
			local body = eval_block()

			while cond do
				last_val = parse_and_eval(body, env)
				pos = cond_pos
				cond = eval_expr()
				match("DELIMITER", ":")
				eval_block()
			end

		elseif match("KEYWORD", "for") then
			local var_name = match("NAME").value
			match("KEYWORD", "in")
			local iterable = eval_expr()
			match("DELIMITER", ":")
			local body = eval_block()

			if iterable and iterable._data then
				for _, item in ipairs(iterable._data) do
					env:set(var_name, item)
					last_val = parse_and_eval(body, env)
				end
			end

		elseif match("KEYWORD", "import") then
			local mod_name = match("NAME").value
			local mod_obj = VM:GetOrLoadModule(mod_name)
			env:set(mod_name, mod_obj)

		elseif match("KEYWORD", "return") then
			local res = eval_expr()
			return res

		elseif match("NAME") then
			local var_name = t.value
			if match("OPERATOR", "=") then
				local val = eval_expr()
				env:set(var_name, val)
			elseif match("OPERATOR", "+=") then
				env:set(var_name, (env:get(var_name) or 0) + eval_expr())
			elseif match("DELIMITER", ".") then
				local attr_name = match("NAME").value
				if match("OPERATOR", "=") then
					local target = env:get(var_name)
					local val = eval_expr()
					if target and target.set_attr then
						target:set_attr(attr_name, val)
					elseif type(target) == "table" then
						target[attr_name] = val
					end
				end
			else
				pos = pos - 1
				last_val = eval_expr()
			end

		else
			pos = pos + 1
		end
		match("NEWLINE")
	end

	return last_val
end

local global_env = Env.new()
global_env.globals = global_env

global_env:set("print", function(...)
	local args = { ... }
	local out = {}
	for i = 1, select("#", ...) do
		table.insert(out, tostring(args[i]))
	end
	print(table.concat(out, " "))
end)

global_env:set("len", function(obj)
	if type(obj) == "table" and obj._data then return #obj._data end
	if type(obj) == "string" or type(obj) == "table" then return #obj end
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

global_env:set("str", tostring)
global_env:set("int", tonumber)
global_env:set("float", tonumber)

function VM:GetOrLoadModule(modName)
	if self.loaded_modules[modName] then
		return self.loaded_modules[modName]
	end

	local code = self.modules[modName]
	if not code then
		error("ModuleNotFoundError: No module named '" .. tostring(modName) .. "'")
	end

	local modEnv = Env.new(global_env)
	local tokens = tokenize(code)
	parse_and_eval(tokens, modEnv)

	self.loaded_modules[modName] = modEnv
	return modEnv
end

function VM:Python(code)
	local lines = {}
	for line in string.gmatch(code .. "\n", "(.-)\r?\n") do
		table.insert(lines, line)
	end

	for _, line in ipairs(lines) do
		local trimmed = string.match(line, "^%s*(.-)%s*$")
		if trimmed ~= "" then
			local modName = string.match(trimmed, "^#%s*([%w_]+)%.py%s*$")
			if modName then
				self.modules[modName] = code
				return nil
			end
			break
		end
	end

	local tokens = tokenize(code)
	return parse_and_eval(tokens, global_env)
end

return VM
