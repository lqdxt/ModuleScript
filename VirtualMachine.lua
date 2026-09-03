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
 if not str_method then str_method = self:get_attr("__repr__") end
 if type(str_method) == "function" then
  return str_method()
 end
 return "<" .. self.__class__.__name__ .. " instance>"
end

local Env = {}
Env.__index = Env

function Env.new(parent)
 return setmetatable({ vars = {}, parent = parent, globals = parent and parent.globals or nil, globals_flag = {} }, Env)
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
 if self.globals_flag and self.globals_flag[name] and self.globals then
  self.globals.vars[name] = val
 else
  self.vars[name] = val
 end
end

local KEYWORDS = {
 ["def"]=true, ["class"]=true, ["if"]=true, ["elif"]=true, ["else"]=true,
 ["while"]=true, ["for"]=true, ["in"]=true, ["not"]=true, ["and"]=true,
 ["or"]=true, ["return"]=true, ["import"]=true, ["from"]=true, ["as"]=true,
 ["try"]=true, ["except"]=true, ["finally"]=true, ["raise"]=true, ["pass"]=true,
 ["break"]=true, ["continue"]=true, ["lambda"]=true, ["True"]=true, ["False"]=true,
 ["None"]=true, ["is"]=true, ["global"]=true
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
     local str_val = ""
     pos = pos + 1
     while pos <= len do
      local ch = string.sub(line, pos, pos)
      if ch == c then
       pos = pos + 1
       break
      elseif ch == "\\" and pos < len then
       local next_ch = string.sub(line, pos + 1, pos + 1)
       if next_ch == "n" then str_val = str_val .. "\n"
       elseif next_ch == "t" then str_val = str_val .. "\t"
       elseif next_ch == "r" then str_val = str_val .. "\r"
       elseif next_ch == "\\" then str_val = str_val .. "\\"
       elseif next_ch == c then str_val = str_val .. c
       else str_val = str_val .. next_ch end
       pos = pos + 2
      else
       str_val = str_val .. ch
       pos = pos + 1
      end
     end
     table.insert(tokens, { type = "STRING", value = str_val, line = line_idx })
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
        double_op == "//" or double_op == "**" or double_op == "<<" or double_op == ">>" then
      table.insert(tokens, { type = "OPERATOR", value = double_op, line = line_idx })
      pos = pos + 2
     elseif c == "+" or c == "-" or c == "*" or c == "/" or c == "%" or c == "<" or c == ">" or c == "=" or c == "!" or c == "&" or c == "|" or c == "^" or c == "~" then
      table.insert(tokens, { type = "OPERATOR", value = c, line = line_idx })
      pos = pos + 1
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

 local BreakSignal = {}
 local ContinueSignal = {}
 local ReturnSignal = {}

 local function call_magic(obj, method, ...)
  local mt = getmetatable(obj)
  if mt == PyInstance then
   local m = obj.__class__:lookup(method)
   if m then return m(obj, ...) end
  end
  return nil
 end

 local eval_expr
 local eval_block
 local parse_expr_tokens

 local function parse_or()
  local left = parse_and()
  while match("KEYWORD", "or") do left = left or parse_and() end
  return left
 end

 local function parse_and()
  local left = parse_not()
  while match("KEYWORD", "and") do left = left and parse_not() end
  return left
 end

 local function parse_not()
  if match("KEYWORD", "not") then return not parse_not() end
  return parse_comp()
 end

 local function parse_comp()
  local left = parse_bitor()
  while true do
   if match("OPERATOR", "==") then left = (left == parse_bitor())
   elseif match("OPERATOR", "!=") then left = (left ~= parse_bitor())
   elseif match("OPERATOR", "<") then left = (left < parse_bitor())
   elseif match("OPERATOR", ">") then left = (left > parse_bitor())
   elseif match("OPERATOR", "<=") then left = (left <= parse_bitor())
   elseif match("OPERATOR", ">=") then left = (left >= parse_bitor())
   elseif match("KEYWORD", "in") then
    local right = parse_bitor()
    local found = false
    if right and right._data then
     for _, v in ipairs(right._data) do if v == left then found = true break end end
    elseif getmetatable(right) == PyDict then
     found = right._data[left] ~= nil
    elseif type(right) == "string" then
     found = string.find(right, tostring(left), 1, true) ~= nil
    end
    left = found
   elseif match("KEYWORD", "is") then
    if match("KEYWORD", "not") then left = (left ~= parse_bitor())
    else left = (left == parse_bitor()) end
   elseif match("KEYWORD", "not") and peek() and peek().value == "in" then
    match("KEYWORD", "in")
    local right = parse_bitor()
    local found = false
    if right and right._data then
     for _, v in ipairs(right._data) do if v == left then found = true break end end
    elseif getmetatable(right) == PyDict then
     found = right._data[left] ~= nil
    end
    left = not found
   else
    break
   end
  end
  return left
 end

 local function parse_bitor()
  local left = parse_bitxor()
  while match("OPERATOR", "|") do left = bit32 and bit32.bor(left, parse_bitxor()) or (left + parse_bitxor()) end
  return left
 end

 local function parse_bitxor()
  local left = parse_bitand()
  while match("OPERATOR", "^") do left = bit32 and bit32.bxor(left, parse_bitand()) or (left + parse_bitand()) end
  return left
 end

 local function parse_bitand()
  local left = parse_shift()
  while match("OPERATOR", "&") do left = bit32 and bit32.band(left, parse_shift()) or (left + parse_shift()) end
  return left
 end

 local function parse_shift()
  local left = parse_add()
  while true do
   if match("OPERATOR", "<<") then left = left * (2 ^ parse_add())
   elseif match("OPERATOR", ">>") then left = math.floor(left / (2 ^ parse_add()))
   else break end
  end
  return left
 end

 local function parse_add()
  local left = parse_mul()
  while true do
   if match("OPERATOR", "+") then
    local right = parse_mul()
    local res = call_magic(left, "__add__", right)
    if res == nil then res = call_magic(right, "__radd__", left) end
    if res ~= nil then left = res
    elseif type(left) == "string" or type(right) == "string" then left = tostring(left) .. tostring(right)
    else left = left + right end
   elseif match("OPERATOR", "-") then
    local right = parse_mul()
    local res = call_magic(left, "__sub__", right)
    if res == nil then res = call_magic(right, "__rsub__", left) end
    if res ~= nil then left = res else left = left - right end
   else break end
  end
  return left
 end

 local function parse_mul()
  local left = parse_unary()
  while true do
   if match("OPERATOR", "*") then
    local right = parse_unary()
    local res = call_magic(left, "__mul__", right)
    if res == nil then res = call_magic(right, "__rmul__", left) end
    if res ~= nil then left = res else left = left * right end
   elseif match("OPERATOR", "/") then
    local right = parse_unary()
    local res = call_magic(left, "__div__", right)
    if res == nil then res = call_magic(right, "__rdiv__", left) end
    if res ~= nil then left = res else left = left / right end
   elseif match("OPERATOR", "//") then
    local right = parse_unary()
    local res = call_magic(left, "__floordiv__", right)
    if res == nil then res = call_magic(right, "__rfloordiv__", left) end
    if res ~= nil then left = res else left = math.floor(left / right) end
   elseif match("OPERATOR", "%") then
    local right = parse_unary()
    local res = call_magic(left, "__mod__", right)
    if res == nil then res = call_magic(right, "__rmod__", left) end
    if res ~= nil then left = res else left = left % right end
   else break end
  end
  return left
 end

 local function parse_unary()
  if match("OPERATOR", "-") then return -parse_unary() end
  if match("OPERATOR", "+") then return parse_unary() end
  if match("OPERATOR", "~") then return bit32 and bit32.bnot(parse_unary()) or -parse_unary() - 1 end
  return parse_pow()
 end

 local function parse_pow()
  local left = parse_postfix()
  if match("OPERATOR", "**") then
   local right = parse_pow()
   local res = call_magic(left, "__pow__", right)
   if res == nil then res = call_magic(right, "__rpow__", left) end
   if res ~= nil then return res end
   return left ^ right
  end
  return left
 end

 local function parse_atom()
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

  if match("KEYWORD", "lambda") then
   local params = {}
   if not match("DELIMITER", ":") then
    repeat
     table.insert(params, match("NAME").value)
    until not match("DELIMITER", ",")
    match("DELIMITER", ":")
   end
   local body_toks = parse_expr_tokens()
   return function(...)
    local args = {...}
    local fn_env = Env.new(env)
    for i, p in ipairs(params) do fn_env:set(p, args[i]) end
    local ok, res = pcall(parse_and_eval, body_toks, fn_env)
    if not ok then error(res) end
    return res
   end
  end

  pos = pos + 1
  return nil
 end

 local function parse_postfix()
  local left = parse_atom()

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
     local mt = getmetatable(left)

     local is_method = false
     local method_func = nil

     if mt == PyInstance then
      local val = left:get_attr(attr)
      if type(val) == "function" and peek() and peek().type == "DELIMITER" and peek().value == "(" then
       is_method = true
       method_func = val
      else
       left = val
      end
     elseif mt == PyList or mt == PyDict or mt == PyTuple then
      if mt[attr] and type(mt[attr]) == "function" and peek() and peek().type == "DELIMITER" and peek().value == "(" then
       is_method = true
       method_func = mt[attr]
      else
       left = mt[attr] or left[attr]
      end
     elseif type(left) == "string" then
      local str_methods = {
       upper = string.upper, lower = string.lower,
       strip = function(s) return string.match(s, "^%s*(.-)%s*$") end,
       lstrip = function(s) return string.match(s, "^%s*(.-)$") end,
       rstrip = function(s) return string.match(s, "^(.-)%s*$") end,
       split = function(s, sep)
        local res = {}
        sep = sep or "%s+"
        for word in string.gmatch(s, "([^"..sep.."]+)") do table.insert(res, word) end
        return PyList.new(res)
       end,
       replace = function(s, old, new) return (string.gsub(s, old, new)) end,
       startswith = function(s, prefix) return string.sub(s, 1, #prefix) == prefix end,
       endswith = function(s, suffix) return string.sub(s, -#suffix) == suffix end,
       find = function(s, sub) local i = string.find(s, sub, 1, true) return i and i - 1 or -1 end,
       format = function(s, ...)
        local args = {...}
        local i = 0
        return (string.gsub(s, "{}", function() i = i + 1 return tostring(args[i]) end))
       end
      }
      if str_methods[attr] and peek() and peek().type == "DELIMITER" and peek().value == "(" then
       is_method = true
       method_func = function(...) return str_methods[attr](left, ...) end
      else
       left = str_methods[attr]
      end
     elseif type(left) == "table" then
      if left[attr] and type(left[attr]) == "function" and peek() and peek().type == "DELIMITER" and peek().value == "(" then
       is_method = true
       method_func = left[attr]
      else
       left = left[attr]
      end
     end

     if is_method then
      match("DELIMITER", "(")
      local args = {}
      if not match("DELIMITER", ")") then
       repeat table.insert(args, eval_expr()) until not match("DELIMITER", ",")
       match("DELIMITER", ")")
      end
      left = method_func((table.unpack or unpack)(args))
     end
    end
   elseif match("DELIMITER", "[") then
    local idx = eval_expr()
    local stop_idx = nil
    local step = nil
    if match("DELIMITER", ":") then
     if not match("DELIMITER", ":") and not (peek() and peek().value == "]") then
      stop_idx = eval_expr()
     end
     if match("DELIMITER", ":") then
      step = eval_expr()
     end
    end
    match("DELIMITER", "]")

    if stop_idx ~= nil or step ~= nil or (peek(-2) and peek(-2).value == ":") then
     if left and left.slice then
      left = left:slice(idx, stop_idx, step)
     elseif type(left) == "string" then
      idx = idx or 0
      stop_idx = stop_idx or #left
      if idx < 0 then idx = #left + idx end
      if stop_idx < 0 then stop_idx = #left + stop_idx end
      left = string.sub(left, idx + 1, stop_idx)
     end
    else
     local magic = call_magic(left, "__getitem__", idx)
     if magic ~= nil then
      left = magic
     elseif left and left.get then
      left = left:get(idx)
     elseif type(left) == "table" then
      left = left[idx]
     elseif type(left) == "string" then
      if idx < 0 then idx = #left + idx end
      left = string.sub(left, idx + 1, idx + 1)
     end
    end
   else
    break
   end
  end

  return left
 end

 parse_expr_tokens = function()
  local toks = {}
  local depth = 0
  while pos <= #tokens do
   local t = tokens[pos]
   if t.type == "DELIMITER" and (t.value == "(" or t.value == "[" or t.value == "{") then depth = depth + 1 end
   if t.type == "DELIMITER" and (t.value == ")" or t.value == "]" or t.value == "}") then
    if depth == 0 then break end
    depth = depth - 1
   end
   if depth == 0 and t.type == "DELIMITER" and (t.value == "," or t.value == ":") then break end
   table.insert(toks, t)
   pos = pos + 1
  end
  return toks
 end

 eval_expr = function()
  return parse_or()
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
    local ok, res = pcall(parse_and_eval, body, fn_env)
    if not ok then
     if type(res) == "table" and res.type == ReturnSignal then
      return res.value
     else
      error(res)
     end
    end
    return res
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

   local executed = false
   if cond then
    last_val = parse_and_eval(body, env)
    executed = true
   end

   while match("KEYWORD", "elif") do
    local elif_cond = eval_expr()
    match("DELIMITER", ":")
    local elif_body = eval_block()
    if not executed and elif_cond then
     last_val = parse_and_eval(elif_body, env)
     executed = true
    end
   end

   if match("KEYWORD", "else") then
    match("DELIMITER", ":")
    local else_body = eval_block()
    if not executed then
     last_val = parse_and_eval(else_body, env)
    end
   end

  elseif match("KEYWORD", "while") then
   local cond_toks = parse_expr_tokens()
   match("DELIMITER", ":")
   local body = eval_block()

   while true do
    local cond = parse_and_eval(cond_toks, env)
    if not cond then break end

    local ok, res = pcall(parse_and_eval, body, env)
    if not ok then
     if res == BreakSignal then break
     elseif res == ContinueSignal then
     else error(res) end
    else
     last_val = res
    end
   end

  elseif match("KEYWORD", "for") then
   local var_name = match("NAME").value
   match("KEYWORD", "in")
   local iter_toks = parse_expr_tokens()
   match("DELIMITER", ":")
   local body = eval_block()

   local iterable = parse_and_eval(iter_toks, env)
   if iterable and iterable._data then
    for _, item in ipairs(iterable._data) do
     env:set(var_name, item)
     local ok, res = pcall(parse_and_eval, body, env)
     if not ok then
      if res == BreakSignal then break
      elseif res == ContinueSignal then
      else error(res) end
     else
      last_val = res
     end
    end
   elseif type(iterable) == "string" then
    for i = 1, #iterable do
     env:set(var_name, string.sub(iterable, i, i))
     local ok, res = pcall(parse_and_eval, body, env)
     if not ok then
      if res == BreakSignal then break
      elseif res == ContinueSignal then
      else error(res) end
     else
      last_val = res
     end
    end
   end

  elseif match("KEYWORD", "try") then
   match("DELIMITER", ":")
   local try_body = eval_block()
   local except_blocks = {}
   while match("KEYWORD", "except") do
    local exc_type = nil
    local exc_var = nil
    if match("NAME") then
     exc_type = t.value
     if match("KEYWORD", "as") then
      exc_var = match("NAME").value
     end
    end
    match("DELIMITER", ":")
    local exc_body = eval_block()
    table.insert(except_blocks, {type=exc_type, var=exc_var, body=exc_body})
   end
   local finally_body = nil
   if match("KEYWORD", "finally") then
    match("DELIMITER", ":")
    finally_body = eval_block()
   end

   local ok, res = pcall(parse_and_eval, try_body, env)
   if not ok then
    local handled = false
    for _, exc in ipairs(except_blocks) do
     if exc.type == nil or (type(res) == "table" and res.value == exc.type) then
      if exc.var then env:set(exc_var, res) end
      local ok2, res2 = pcall(parse_and_eval, exc.body, env)
      if not ok2 then error(res2) end
      last_val = res2
      handled = true
      break
     end
    end
    if not handled then
     if finally_body then pcall(parse_and_eval, finally_body, env) end
     error(res)
    end
   else
    last_val = res
   end
   if finally_body then
    local ok3, res3 = pcall(parse_and_eval, finally_body, env)
    if not ok3 then error(res3) end
   end

  elseif match("KEYWORD", "import") then
   local mod_name = match("NAME").value
   local mod_obj = VM:GetOrLoadModule(mod_name)
   env:set(mod_name, mod_obj)

  elseif match("KEYWORD", "global") then
   local var_name = match("NAME").value
   env.globals_flag = env.globals_flag or {}
   env.globals_flag[var_name] = true

  elseif match("KEYWORD", "break") then
   error(BreakSignal)

  elseif match("KEYWORD", "continue") then
   error(ContinueSignal)

  elseif match("KEYWORD", "return") then
   local res = eval_expr()
   error({type=ReturnSignal, value=res})

  elseif match("KEYWORD", "raise") then
   local exc = eval_expr()
   error({type="Exception", value=exc})

  elseif match("KEYWORD", "pass") then

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
     local magic = call_magic(target, "__setattr__", attr_name, val)
     if magic == nil then
      if target and target.set_attr then
       target:set_attr(attr_name, val)
      elseif type(target) == "table" then
       target[attr_name] = val
      end
     end
    end
   elseif match("DELIMITER", "[") then
    local idx = eval_expr()
    match("DELIMITER", "]")
    if match("OPERATOR", "=") then
     local target = env:get(var_name)
     local val = eval_expr()
     local magic = call_magic(target, "__setitem__", idx, val)
     if magic == nil then
      if target and target.set then target:set(idx, val)
      elseif type(target) == "table" then target[idx] = val end
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
 local magic = call_magic(obj, "__len__")
 if magic ~= nil then return magic end
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
global_env:set("bool", function(obj)
 if obj == nil or obj == false or obj == 0 or obj == "" then return false end
 if type(obj) == "table" and obj._data then return #obj._data > 0 end
 return true
end)
global_env:set("list", function(iterable)
 if not iterable then return PyList.new() end
 if iterable._data then return PyList.new(iterable._data) end
 return PyList.new()
end)
global_env:set("dict", function(kv)
 return PyDict.new(kv)
end)
global_env:set("tuple", function(iterable)
 if not iterable then return PyTuple.new() end
 if iterable._data then return PyTuple.new(iterable._data) end
 return PyTuple.new()
end)
global_env:set("type", function(obj)
 local mt = getmetatable(obj)
 if mt == PyList then return "list"
 elseif mt == PyDict then return "dict"
 elseif mt == PyTuple then return "tuple"
 elseif mt == PyInstance then return obj.__class__.__name__
 else return type(obj) end
end)
global_env:set("assert", function(cond, msg)
 if not cond then error(msg or "AssertionError") end
end)
global_env:set("super", function(inst)
 return inst.__class__.__bases__[1]
end)

function call_magic(obj, method, ...)
 local mt = getmetatable(obj)
 if mt == PyInstance then
  local m = obj.__class__:lookup(method)
  if m then return m(obj, ...) end
 end
 return nil
end

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
