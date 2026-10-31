local Regex = {}
Regex.__index = Regex

local Compiled = {}
Compiled.__index = Compiled

do
 local byte, sub, char, lower, upper = string.byte, string.sub, string.char, string.lower, string.upper
 local floor = math.floor
 local concat = table.concat
 local unpack = table.unpack or unpack

 local function decode(s, i)
  local b = byte(s, i)
  if not b then return nil end
  if b < 0x80 then return b, 1 end
  if b >= 0xC2 and b <= 0xDF then
   local b2 = byte(s, i + 1)
   if b2 and b2 >= 0x80 and b2 <= 0xBF then return (b - 0xC0) * 64 + (b2 - 0x80), 2 end
  elseif b >= 0xE0 and b <= 0xEF then
   local b2, b3 = byte(s, i + 1, i + 2)
   if b2 and b3 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
    local cp = (b - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
    if cp >= 0x800 then return cp, 3 end
   end
  elseif b >= 0xF0 and b <= 0xF4 then
   local b2, b3, b4 = byte(s, i + 1, i + 3)
   if b2 and b3 and b4 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF and b4 >= 0x80 and b4 <= 0xBF then
    local cp = (b - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
    if cp >= 0x10000 and cp <= 0x10FFFF then return cp, 4 end
   end
  end
  return b, 1
 end

 local function encode(cp)
  if cp < 0x80 then return char(cp)
  elseif cp < 0x800 then return char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then return char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
  else return char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64, 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64) end
 end

 local function prev_cp(s, pos)
  if pos <= 1 then return nil end
  local i, lim = pos - 1, math.max(1, pos - 4)
  while i > lim do
   local b = byte(s, i)
   if b < 0x80 or b >= 0xC0 then break end
   i = i - 1
  end
  local cp, len = decode(s, i)
  if i + len == pos then return cp, i end
  return byte(s, pos - 1), pos - 1
 end

 local function to_lower(c)
  if c < 128 then
   if c >= 65 and c <= 90 then return c + 32 end
   return c
  end
  if c >= 0xC0 and c <= 0xDE and c ~= 0xD7 then return c + 32 end
  if ((c >= 0x100 and c <= 0x137) or (c >= 0x14A and c <= 0x177)) and c % 2 == 0 then return c + 1 end
  if c >= 0x391 and c <= 0x3A9 and c ~= 0x3A2 then return c + 32 end
  if c >= 0x410 and c <= 0x42F then return c + 32 end
  if c >= 0x400 and c <= 0x40F then return c + 80 end
  return c
 end

 local function to_upper(c)
  if c < 128 then
   if c >= 97 and c <= 122 then return c - 32 end
   return c
  end
  if c >= 0xE0 and c <= 0xFE and c ~= 0xF7 then return c - 32 end
  if ((c >= 0x101 and c <= 0x137) or (c >= 0x14B and c <= 0x177)) and c % 2 == 1 then return c - 1 end
  if c >= 0x3B1 and c <= 0x3C9 and c ~= 0x3C2 then return c - 32 end
  if c >= 0x430 and c <= 0x44F then return c - 32 end
  if c >= 0x450 and c <= 0x45F then return c - 80 end
  return c
 end

 local function fold(c)
  c = to_lower(c)
  if c == 0x3C2 then return 0x3C3 end
  return c
 end

 local function fold_str(s)
  if not s:find("[\128-\255]") then return lower(s) end
  local out, i = {}, 1
  while i <= #s do
   local c, len = decode(s, i)
   out[#out + 1] = encode(fold(c))
   i = i + len
  end
  return concat(out)
 end

 local function in_ranges(cp, r)
  for i = 1, #r, 2 do
   if cp >= r[i] and cp <= r[i + 1] then return true end
  end
  return false
 end

 local R_SCRIPT = {
  latin = { 65,90, 97,122, 0xAA,0xAA, 0xB5,0xB5, 0xBA,0xBA, 0xC0,0xD6, 0xD8,0xF6, 0xF8,0x2B8, 0x1E00,0x1EFF, 0x2C60,0x2C7F, 0xA720,0xA7FF, 0xFF21,0xFF3A, 0xFF41,0xFF5A },
  greek = { 0x370,0x3FF, 0x1F00,0x1FFF },
  cyrillic = { 0x400,0x52F, 0x1C80,0x1C8F, 0x2DE0,0x2DFF, 0xA640,0xA69F },
  armenian = { 0x531,0x556, 0x561,0x587 },
  hebrew = { 0x5D0,0x5EA, 0x5EF,0x5F4 },
  arabic = { 0x620,0x64A, 0x66E,0x6D3, 0x6FA,0x6FC, 0x750,0x77F },
  devanagari = { 0x904,0x939, 0x958,0x961 },
  thai = { 0xE01,0xE30, 0xE32,0xE33, 0xE40,0xE46 },
  hangul = { 0x1100,0x11FF, 0x3131,0x318E, 0xAC00,0xD7A3 },
  hiragana = { 0x3041,0x3096, 0x309D,0x309F },
  katakana = { 0x30A1,0x30FA, 0x30FD,0x30FF, 0x31F0,0x31FF, 0xFF66,0xFF9F },
  han = { 0x2E80,0x2FDF, 0x3005,0x3007, 0x3021,0x3029, 0x3038,0x303B, 0x3400,0x4DBF, 0x4E00,0x9FFF, 0xF900,0xFAFF, 0x20000,0x2FA1F },
 }
 local R_LETTER = {}
 for _, r in pairs(R_SCRIPT) do
  for i = 1, #r do R_LETTER[#R_LETTER + 1] = r[i] end
 end

 local R_ND = { 48,57, 0x660,0x669, 0x6F0,0x6F9, 0x966,0x96F, 0xE50,0xE59, 0xFF10,0xFF19 }
 local R_N = { 48,57, 0xB2,0xB3, 0xB9,0xB9, 0xBC,0xBE, 0x660,0x669, 0x6F0,0x6F9, 0x966,0x96F, 0xE50,0xE59, 0x2070,0x2079, 0x2080,0x2089, 0x2150,0x218B, 0x2460,0x249B, 0x3007,0x3007, 0xFF10,0xFF19 }
 local R_P = { 33,35, 37,42, 44,47, 58,59, 63,64, 91,93, 95,95, 123,123, 125,125, 0xA1,0xA1, 0xA7,0xA7, 0xAB,0xAB, 0xB6,0xB7, 0xBB,0xBB, 0xBF,0xBF, 0x2010,0x2027, 0x2030,0x205E, 0x3001,0x3003, 0x3008,0x3011, 0xFF01,0xFF03, 0xFF05,0xFF0A, 0xFF0C,0xFF0F }
 local R_S = { 36,36, 43,43, 60,62, 94,94, 96,96, 124,124, 126,126, 0xA2,0xA6, 0xA8,0xA9, 0xAC,0xAC, 0xAE,0xB1, 0xB4,0xB4, 0xB8,0xB8, 0xD7,0xD7, 0xF7,0xF7, 0x20A0,0x20CF, 0x2190,0x23FF, 0x2500,0x27BF, 0x2900,0x2BFF, 0x1F000,0x1FAFF }
 local R_Z = { 0x20,0x20, 0xA0,0xA0, 0x1680,0x1680, 0x2000,0x200A, 0x2028,0x2029, 0x202F,0x202F, 0x205F,0x205F, 0x3000,0x3000 }
 local R_ZS = { 0x20,0x20, 0xA0,0xA0, 0x1680,0x1680, 0x2000,0x200A, 0x202F,0x202F, 0x205F,0x205F, 0x3000,0x3000 }
 local R_CC = { 0,0x1F, 0x7F,0x9F }
 local R_M = { 0x300,0x36F, 0x483,0x489, 0x591,0x5BD, 0x610,0x61A, 0x64B,0x65F, 0x900,0x903, 0x93A,0x94F, 0x1AB0,0x1AFF, 0x1DC0,0x1DFF, 0x20D0,0x20FF, 0xFE00,0xFE0F, 0xFE20,0xFE2F }
 local R_EMOJI = { 0x231A,0x231B, 0x2600,0x27BF, 0x2B50,0x2B55, 0x1F000,0x1F2FF, 0x1F300,0x1FAFF }
 local R_SPACE = { 9,13, 32,32, 0xA0,0xA0, 0x1680,0x1680, 0x2000,0x200A, 0x2028,0x2029, 0x202F,0x202F, 0x205F,0x205F, 0x3000,0x3000, 0xFEFF,0xFEFF }
 local R_HSPACE = { 9,9, 32,32, 0xA0,0xA0, 0x1680,0x1680, 0x180E,0x180E, 0x2000,0x200A, 0x202F,0x202F, 0x205F,0x205F, 0x3000,0x3000 }

 local function rf(r) return function(c) return in_ranges(c, r) end end

 local prop_defs = {
  l = rf(R_LETTER),
  lu = function(c) return to_lower(c) ~= c end,
  ll = function(c) return to_upper(c) ~= c or c == 0xDF end,
  n = rf(R_N), nd = rf(R_ND), p = rf(R_P), s = rf(R_S),
  z = rf(R_Z), zs = rf(R_ZS), cc = rf(R_CC), m = rf(R_M),
  emoji = rf(R_EMOJI), space = rf(R_SPACE),
  any = function() return true end,
  ascii = function(c) return c < 128 end,
 }
 prop_defs.c = prop_defs.cc
 prop_defs.alnum = function(c) return prop_defs.l(c) or prop_defs.nd(c) end
 prop_defs.word = function(c) return c == 95 or prop_defs.l(c) or prop_defs.nd(c) or prop_defs.m(c) end
 prop_defs.punct = function(c) return prop_defs.p(c) or (c < 128 and prop_defs.s(c)) end
 for name, r in pairs(R_SCRIPT) do prop_defs[name] = rf(r) end

 local prop_aliases = {
  letter = "l", uppercaseletter = "lu", lowercaseletter = "ll", number = "n",
  decimalnumber = "nd", punctuation = "p", symbol = "s", separator = "z",
  spaceseparator = "zs", mark = "m", control = "cc", alphabetic = "l", alpha = "l",
  uppercase = "lu", upper = "lu", lowercase = "ll", lower = "ll", digit = "nd",
  whitespace = "space", latn = "latin", grek = "greek", cyrl = "cyrillic",
  hani = "han", hira = "hiragana", kana = "katakana", hang = "hangul",
  arab = "arabic", hebr = "hebrew", deva = "devanagari",
 }
 for k, v in pairs(prop_aliases) do prop_defs[k] = prop_defs[v] end

 local function lookup_prop(name)
  local n = lower(name)
  n = (n:gsub("[%s_%-]", ""))
  n = (n:gsub("^%a+=", ""))
  local f = prop_defs[n]
  if f then return f end
  local pre = sub(n, 1, 2)
  if pre == "is" or pre == "in" then return prop_defs[sub(n, 3)] end
  return nil
 end

 local function word_cp(c, unicode)
  if c < 128 then return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 end
  return (unicode and (prop_defs.l(c) or prop_defs.nd(c) or prop_defs.m(c))) or false
 end

 local function shortcut_test(name, c, u)
  local l, r = lower(name), nil
  if l == "d" then r = (c >= 48 and c <= 57) or (u and c >= 128 and prop_defs.nd(c)) or false
  elseif l == "w" then r = word_cp(c, u)
  elseif l == "s" then r = in_ranges(c, R_SPACE)
  else r = in_ranges(c, R_HSPACE) end
  if name ~= l then return not r end
  return r
 end

 local function a_alpha(c) return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) end
 local function a_digit(c) return c >= 48 and c <= 57 end
 local posix_defs = {
  alpha = function(c, u) return a_alpha(c) or (u and c >= 128 and prop_defs.l(c)) or false end,
  digit = function(c, u) return a_digit(c) or (u and c >= 128 and prop_defs.nd(c)) or false end,
  alnum = function(c, u) return a_alpha(c) or a_digit(c) or (u and c >= 128 and (prop_defs.l(c) or prop_defs.nd(c))) or false end,
  upper = function(c, u) return (c >= 65 and c <= 90) or (u and c >= 128 and prop_defs.lu(c)) or false end,
  lower = function(c, u) return (c >= 97 and c <= 122) or (u and c >= 128 and prop_defs.ll(c)) or false end,
  space = function(c) return in_ranges(c, R_SPACE) end,
  blank = function(c) return c == 32 or c == 9 end,
  punct = function(c) return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126) end,
  print = function(c) return c >= 32 and c <= 126 end,
  graph = function(c) return c >= 33 and c <= 126 end,
  cntrl = function(c) return c < 32 or c == 127 end,
  xdigit = function(c) return a_digit(c) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102) end,
  word = function(c, u) return word_cp(c, u) end,
  ascii = function(c) return c < 128 end,
 }

 local SINGLE = { char = true, any = true, shortcut = true, class = true }
 local simple_escapes = { n = 10, t = 9, r = 13, f = 12, v = 11, a = 7, e = 27 }

 local function copy_flags(F) return { i = F.i, m = F.m, s = F.s, x = F.x, u = F.u } end

 local function char_node(cp, icase)
  local n = { type = "char", cp = cp }
  if icase then n.icase = true; n.fcp = fold(cp) end
  return n
 end

 local function linebreak()
  return { type = "atomic", node = { type = "alt", options = {
   { type = "seq", children = { char_node(13), char_node(10) } },
   { type = "class", negate = false, icase = false, items = {
    { kind = "range", lo = 10, hi = 13 }, { kind = "char", cp = 0x85 }, { kind = "range", lo = 0x2028, hi = 0x2029 },
   } },
  } } }
 end

 local function grapheme()
  return { type = "atomic", node = { type = "alt", options = {
   { type = "seq", children = { char_node(13), char_node(10) } },
   { type = "seq", children = {
    { type = "any", dotall = true },
    { type = "repeat", min = 0, max = nil, greedy = true, simple = true, node = {
     type = "class", negate = false, icase = false, items = {
      { kind = "prop", fn = prop_defs.m, negate = false }, { kind = "char", cp = 0x200D },
     } } },
   } },
  } } }
 end

 local function parse(pattern, flags)
  local pos, group_count, plen = 1, 0, #pattern
  local F = copy_flags(flags)
  local names, groups, pending = {}, {}, {}
  local quote = false

  local parse_alt, parse_seq, parse_quant, parse_atom, parse_group, parse_class, parse_escape, parse_conditional

  local function peek() return sub(pattern, pos, pos) end
  local function advance() local c = peek(); pos = pos + 1; return c end
  local function fail(msg) error(msg .. " at position " .. pos, 0) end

  local function read_cp()
   local cp, len = decode(pattern, pos)
   if not cp then fail("unexpected end of pattern") end
   pos = pos + len
   return cp
  end

  local function read_digits(pat, maxn)
   local s = pos
   while pos - s < maxn and sub(pattern, pos, pos):match(pat) do pos = pos + 1 end
   return sub(pattern, s, pos - 1)
  end

  local function read_until(close)
   local e = pattern:find(close, pos, true)
   if not e then fail("missing '" .. close .. "'") end
   local s = sub(pattern, pos, e - 1)
   pos = e + 1
   return s
  end

  local function read_name(close)
   local s = read_until(close)
   if not s:match("^[%a_][%w_]*$") then fail("invalid group name '" .. s .. "'") end
   return s
  end

  local function skip_space()
   while pos <= plen do
    local c = peek()
    if c == " " or c == "\t" or c == "\n" or c == "\r" or c == "\f" or c == "\v" then
     pos = pos + 1
    elseif c == "#" then
     local e = pattern:find("\n", pos, true)
     pos = e and e + 1 or plen + 1
    else
     break
    end
   end
  end

  local function ref_target(s)
   if s:match("^[%+%-]?%d+$") then
    local n, first = tonumber(s), sub(s, 1, 1)
    if first == "-" then return group_count + 1 + n end
    if first == "+" then return group_count + n end
    return n
   end
   return nil, s
  end

  local function make_backref(idx, name)
   if idx and idx < 1 then fail("invalid group reference") end
   local node = { type = "backref", index = idx, name = name, icase = F.i }
   pending[#pending + 1] = node
   return node
  end

  local function make_call(idx, name)
   local node = { type = "call", index = idx, name = name }
   pending[#pending + 1] = node
   return node
  end

  local function braced_hex()
   advance()
   local h = read_digits("%x", 8)
   if h == "" or peek() ~= "}" then fail("bad hex escape") end
   advance()
   local cp = tonumber(h, 16)
   if cp > 0x10FFFF then fail("code point out of range") end
   return cp
  end

  local function make_prop(negate)
   local name
   if peek() == "{" then
    advance()
    name = read_until("}")
   else
    name = advance()
    if name == "" then fail("missing property name") end
   end
   if sub(name, 1, 1) == "^" then negate = not negate; name = sub(name, 2) end
   local fn = lookup_prop(name)
   if not fn then fail("unknown property '" .. name .. "'") end
   return { kind = "prop", fn = fn, negate = negate }
  end

  local function common_escape(e)
   if e == "d" or e == "w" or e == "s" or e == "D" or e == "W" or e == "S" then
    return { kind = "shortcut", name = e, unicode = F.u }
   elseif e == "h" or e == "H" then
    return { kind = "shortcut", name = e }
   elseif e == "p" or e == "P" then
    return make_prop(e == "P")
   elseif simple_escapes[e] then
    return { kind = "char", cp = simple_escapes[e] }
   elseif e == "x" then
    if peek() == "{" then return { kind = "char", cp = braced_hex() } end
    local h = read_digits("%x", 2)
    return { kind = "char", cp = (h == "") and 0 or tonumber(h, 16) }
   elseif e == "u" then
    if peek() == "{" then return { kind = "char", cp = braced_hex() } end
    local h = read_digits("%x", 4)
    if #h < 4 then fail("bad \\u escape") end
    local cp = tonumber(h, 16)
    if cp >= 0xD800 and cp <= 0xDBFF then
     local lo = pattern:match("^\\u(%x%x%x%x)", pos)
     lo = lo and tonumber(lo, 16)
     if lo and lo >= 0xDC00 and lo <= 0xDFFF then
      pos = pos + 6
      cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
     end
    end
    return { kind = "char", cp = cp }
   elseif e == "c" then
    local ch = advance()
    if ch == "" then fail("missing control character") end
    local b = byte(upper(ch))
    return { kind = "char", cp = (b >= 64) and b - 64 or b + 64 }
   elseif e == "0" then
    local o = read_digits("[0-7]", 2)
    return { kind = "char", cp = tonumber("0" .. o, 8) }
   end
   return nil
  end

  local function item_node(item)
   local k = item.kind
   if k == "char" then return char_node(item.cp, F.i)
   elseif k == "shortcut" then return { type = "shortcut", name = item.name, unicode = item.unicode }
   end
   return { type = "class", negate = false, icase = false, items = { item } }
  end

  local function class_atom()
   local c = peek()
   if c == "[" and sub(pattern, pos + 1, pos + 1) == ":" then
    local neg, name, after = pattern:match("^%[:(%^?)(%a+):%]()", pos)
    if name then
     if not posix_defs[name] then fail("unknown POSIX class '" .. name .. "'") end
     pos = after
     return { kind = "posix", name = name, negate = (neg == "^"), unicode = F.u }
    end
   end
   if c == "\\" then
    advance()
    if pos > plen then fail("trailing backslash") end
    local e = advance()
    if e == "b" then return { kind = "char", cp = 8 } end
    if e:match("^[1-7]$") then
     return { kind = "char", cp = tonumber(e .. read_digits("[0-7]", 2), 8) }
    end
    local item = common_escape(e)
    if item then return item end
    pos = pos - 1
    return { kind = "char", cp = read_cp() }
   end
   return { kind = "char", cp = read_cp() }
  end

  local function capture_group(name)
   group_count = group_count + 1
   local idx = group_count
   local node = { type = "group", capture = true, index = idx, name = name }
   groups[idx] = node
   if name then
    names[name] = names[name] or {}
    table.insert(names[name], idx)
   end
   node.children = parse_alt()
   return node
  end

  parse_alt = function()
   local options = { parse_seq() }
   while peek() == "|" do
    advance()
    table.insert(options, parse_seq())
   end
   if #options == 1 then return options[1] end
   return { type = "alt", options = options }
  end

  parse_seq = function()
   local children = {}
   while pos <= plen and (quote or (peek() ~= "|" and peek() ~= ")")) do
    if F.x and not quote then
     skip_space()
     if pos > plen or peek() == "|" or peek() == ")" then break end
    end
    local atom = parse_quant()
    if atom then table.insert(children, atom) end
   end
   return { type = "seq", children = children }
  end

  parse_quant = function()
   local atom = parse_atom()
   if not atom then return nil end
   if quote then
    if sub(pattern, pos, pos + 1) == "\\E" then pos = pos + 2; quote = false
    else return atom end
   end
   while true do
    if F.x then skip_space() end
    local c = peek()
    local mn, mx
    if c == "*" then advance(); mn, mx = 0, nil
    elseif c == "+" then advance(); mn, mx = 1, nil
    elseif c == "?" then advance(); mn, mx = 0, 1
    elseif c == "{" then
     local start = pos
     advance()
     local n1 = read_digits("%d", 9)
     if n1 == "" then pos = start; break end
     if peek() == "}" then
      advance(); mn = tonumber(n1); mx = mn
     elseif peek() == "," then
      advance()
      local n2 = read_digits("%d", 9)
      if peek() ~= "}" then pos = start; break end
      advance()
      mn = tonumber(n1)
      if n2 == "" then mx = nil else mx = tonumber(n2) end
      if mx and mx < mn then fail("numbers out of order in {} quantifier") end
     else
      pos = start; break
     end
    else
     break
    end
    local greedy, possessive = true, false
    local s = peek()
    if s == "?" then advance(); greedy = false
    elseif s == "+" then advance(); possessive = true end
    atom = { type = "repeat", node = atom, min = mn, max = mx, greedy = greedy, simple = SINGLE[atom.type] or false }
    if possessive then atom = { type = "atomic", node = atom } end
   end
   return atom
  end

  parse_atom = function()
   if quote then
    if sub(pattern, pos, pos + 1) == "\\E" then
     pos = pos + 2; quote = false
    else
     return char_node(read_cp(), F.i)
    end
   end
   local c = peek()
   if c == "" then return nil end
   if c == "(" then return parse_group() end
   if c == "[" then return parse_class() end
   if c == "." then advance(); return { type = "any", dotall = F.s } end
   if c == "^" then advance(); return { type = "anchor", kind = "^", multiline = F.m } end
   if c == "$" then advance(); return { type = "anchor", kind = "$", multiline = F.m } end
   if c == ")" then fail("unmatched )") end
   if c == "*" or c == "+" or c == "?" then fail("nothing to repeat") end
   if c == "\\" then advance(); return parse_escape() end
   return char_node(read_cp(), F.i)
  end

  parse_class = function()
   advance()
   local negate = false
   if peek() == "^" then advance(); negate = true end
   local items, first = {}, true
   while pos <= plen and (peek() ~= "]" or first) do
    first = false
    local item = class_atom()
    if item.kind == "char" and peek() == "-" and pos + 1 <= plen and sub(pattern, pos + 1, pos + 1) ~= "]" then
     advance()
     local hi = class_atom()
     if hi.kind == "char" then
      if hi.cp < item.cp then fail("range out of order in character class") end
      items[#items + 1] = { kind = "range", lo = item.cp, hi = hi.cp }
     else
      items[#items + 1] = item
      items[#items + 1] = { kind = "char", cp = 45 }
      items[#items + 1] = hi
     end
    else
     items[#items + 1] = item
    end
   end
   if peek() ~= "]" then fail("unclosed class") end
   advance()
   return { type = "class", negate = negate, items = items, icase = F.i }
  end

  parse_escape = function()
   if pos > plen then fail("trailing backslash") end
   local e = advance()
   local item = common_escape(e)
   if item then return item_node(item) end
   if e == "b" or e == "B" then return { type = "anchor", kind = "\\" .. e, unicode = F.u }
   elseif e == "A" or e == "z" or e == "Z" or e == "G" then return { type = "anchor", kind = e }
   elseif e == "K" then return { type = "keep" }
   elseif e == "R" then return linebreak()
   elseif e == "X" then return grapheme()
   elseif e == "N" then return { type = "any", dotall = false }
   elseif e == "Q" then quote = true; return parse_atom()
   elseif e == "E" then return nil
   elseif e == "k" then
    local close = ({ ["<"] = ">", ["'"] = "'", ["{"] = "}" })[advance()]
    if not close then fail("\\k must be followed by <name>, 'name' or {name}") end
    local idx, name = ref_target(read_until(close))
    return make_backref(idx, name)
   elseif e == "g" then
    local o = peek()
    if o == "<" or o == "'" then
     advance()
     local idx, name = ref_target(read_until(o == "<" and ">" or "'"))
     return make_call(idx, name)
    elseif o == "{" then
     advance()
     local idx, name = ref_target(read_until("}"))
     return make_backref(idx, name)
    end
    local s = pattern:match("^[%+%-]?%d+", pos)
    if not s then fail("bad \\g reference") end
    pos = pos + #s
    local idx = ref_target(s)
    return make_backref(idx)
   elseif e:match("^[1-9]$") then
    local ds = e .. read_digits("%d", 3)
    local n = tonumber(ds)
    if n < 10 or n <= group_count then return make_backref(n) end
    pos = pos - #ds
    if e >= "8" then pos = pos + 1; return char_node(byte(e), F.i) end
    return char_node(tonumber(read_digits("[0-7]", 3), 8), F.i)
   end
   pos = pos - 1
   return char_node(read_cp(), F.i)
  end

  parse_conditional = function()
   advance()
   local test
   local nx = peek()
   if nx == "?" then
    pos = pos - 1
    test = parse_atom()
    if not test or test.type ~= "look" then fail("assertion expected as condition") end
   else
    local ref
    if nx == "<" or nx == "'" then
     advance()
     ref = read_until(nx == "<" and ">" or "'")
     if peek() ~= ")" then fail("bad condition") end
     advance()
    else
     ref = read_until(")")
    end
    local idx, name = ref_target(ref)
    test = { type = "condref", index = idx, name = name }
    pending[#pending + 1] = test
   end
   local yes = parse_seq()
   local no = { type = "seq", children = {} }
   if peek() == "|" then advance(); no = parse_seq() end
   if peek() == "|" then fail("conditional group contains more than two branches") end
   return { type = "cond", test = test, yes = yes, no = no }
  end

  parse_group = function()
   advance()
   local saved = copy_flags(F)
   local node
   if peek() == "?" then
    advance()
    local d = peek()
    local d2 = sub(pattern, pos + 1, pos + 1)
    if d == ":" then
     advance(); node = { type = "group", children = parse_alt(), capture = false }
    elseif d == "=" or d == "!" then
     advance(); node = { type = "look", ahead = true, negate = (d == "!"), node = parse_alt() }
    elseif d == ">" then
     advance(); node = { type = "atomic", node = parse_alt() }
    elseif d == "#" then
     read_until(")")
     return nil
    elseif d == "<" and (d2 == "=" or d2 == "!") then
     pos = pos + 2
     node = { type = "look", ahead = false, negate = (d2 == "!"), node = parse_alt() }
    elseif d == "<" then
     advance(); node = capture_group(read_name(">"))
    elseif d == "'" then
     advance(); node = capture_group(read_name("'"))
    elseif d == "P" then
     advance()
     local k = advance()
     if k == "<" then node = capture_group(read_name(">"))
     elseif k == "=" then return make_backref(nil, read_name(")"))
     elseif k == ">" then return make_call(nil, read_name(")"))
     else fail("unsupported group modifier") end
    elseif d == "&" then
     advance(); return make_call(nil, read_name(")"))
    elseif d == "R" then
     advance()
     if peek() ~= ")" then fail("bad (?R)") end
     advance()
     return make_call(0)
    elseif d:match("^%d$") or ((d == "+" or d == "-") and d2:match("^%d$")) then
     local idx, name = ref_target(read_until(")"))
     return make_call(idx, name)
    elseif d == "(" then
     node = parse_conditional()
    else
     local newF, on = copy_flags(F), true
     while true do
      local f = peek()
      if f == "-" then on = false; advance()
      elseif f ~= "" and ("imsxu"):find(f, 1, true) then newF[f] = on; advance()
      else break end
     end
     local term = advance()
     if term == ")" then
      F = newF
      return nil
     elseif term == ":" then
      F = newF
      node = { type = "group", children = parse_alt(), capture = false }
     else
      fail("unsupported group modifier")
     end
    end
   else
    node = capture_group(nil)
   end
   if peek() ~= ")" then fail("unclosed group") end
   advance()
   F = saved
   return node
  end

  local ast = parse_alt()
  if pos <= plen then fail("unmatched )") end
  groups[0] = ast

  local rid = 0
  for _, n in ipairs(pending) do
   if n.type == "backref" or n.type == "condref" then
    if n.name then
     n.indices = names[n.name]
     if not n.indices then error("reference to unknown group '" .. n.name .. "'", 0) end
    elseif n.index < 1 or n.index > group_count then
     error("reference to non-existent group " .. tostring(n.index), 0)
    end
   else
    local target
    if n.name then
     local l = names[n.name]
     if not l then error("call to unknown group '" .. n.name .. "'", 0) end
     target = groups[l[1]]
    else
     target = groups[n.index]
    end
    if not target then error("call to non-existent group " .. tostring(n.index), 0) end
    if not target.rid then rid = rid + 1; target.rid = rid end
    n.target = target
   end
  end
  return ast, group_count, names
 end

 local function snap(caps)
  local s = {}
  for k, v in pairs(caps) do s[k] = v end
  return s
 end

 local function restore(caps, s)
  for k in pairs(caps) do caps[k] = nil end
  for k, v in pairs(s) do caps[k] = v end
 end

 local function item_test(item, c)
  local k = item.kind
  if k == "char" then return c == item.cp
  elseif k == "range" then return c >= item.lo and c <= item.hi
  elseif k == "shortcut" then return shortcut_test(item.name, c, item.unicode)
  elseif k == "prop" then return (item.fn(c) and true or false) ~= item.negate
  elseif k == "posix" then return (posix_defs[item.name](c, item.unicode) and true or false) ~= item.negate
  end
  return false
 end

 local function items_test(items, c)
  for i = 1, #items do
   if item_test(items[i], c) then return true end
  end
  return false
 end

 local function class_test(node, c)
  local r = items_test(node.items, c)
  if not r and node.icase then
   local l, u = to_lower(c), to_upper(c)
   if l ~= c and items_test(node.items, l) then r = true
   elseif u ~= c and items_test(node.items, u) then r = true end
  end
  return r ~= node.negate
 end

 local function step(node, str, pos)
  local c, len = decode(str, pos)
  if not c then return nil end
  local t, ok = node.type, nil
  if t == "char" then ok = (c == node.cp) or (node.icase and fold(c) == node.fcp)
  elseif t == "any" then ok = node.dotall or c ~= 10
  elseif t == "shortcut" then ok = shortcut_test(node.name, c, node.unicode)
  else ok = class_test(node, c) end
  if ok then return pos + len end
  return nil
 end

 local match_node, match_seq, match_repeat

 local function match_simple_repeat(node, str, pos, caps, cont)
  local inner, mn, mx = node.node, node.min, node.max
  local count, p = 0, pos
  if node.greedy then
   local stack = { pos }
   while mx == nil or count < mx do
    local np = step(inner, str, p)
    if not np then break end
    count = count + 1
    p = np
    stack[count + 1] = p
   end
   while count >= mn do
    local r = cont(stack[count + 1], caps)
    if r ~= nil then return r end
    count = count - 1
   end
   return nil
  end
  while count < mn do
   local np = step(inner, str, p)
   if not np then return nil end
   count = count + 1
   p = np
  end
  while true do
   local r = cont(p, caps)
   if r ~= nil then return r end
   if mx ~= nil and count >= mx then return nil end
   local np = step(inner, str, p)
   if not np then return nil end
   count = count + 1
   p = np
  end
 end

 match_seq = function(children, i, str, pos, caps, cont)
  local n = children[i]
  if not n then return cont(pos, caps) end
  return match_node(n, str, pos, caps, function(np, nc)
   return match_seq(children, i + 1, str, np, nc, cont)
  end)
 end

 match_repeat = function(node, str, pos, caps, cont, count)
  local can_more = (node.max == nil or count < node.max)
  local must_more = (count < node.min)

  local function try_more()
   if not can_more then return nil end
   return match_node(node.node, str, pos, caps, function(np, nc)
    if np == pos then
     if count < node.min then return cont(np, nc) end
     return nil
    end
    return match_repeat(node, str, np, nc, cont, count + 1)
   end)
  end

  local function try_done()
   if must_more then return nil end
   return cont(pos, caps)
  end

  if must_more then return try_more() end
  if node.greedy then
   local r = try_more()
   if r ~= nil then return r end
   return try_done()
  end
  local r = try_done()
  if r ~= nil then return r end
  return try_more()
 end

 match_node = function(node, str, pos, caps, cont)
  local t = node.type
  if SINGLE[t] then
   local np = step(node, str, pos)
   if np then return cont(np, caps) end
   return nil
  elseif t == "seq" then
   return match_seq(node.children, 1, str, pos, caps, cont)
  elseif t == "alt" then
   for _, option in ipairs(node.options) do
    local r = match_node(option, str, pos, caps, cont)
    if r ~= nil then return r end
   end
   return nil
  elseif t == "group" then
   if not node.capture then return match_node(node.children, str, pos, caps, cont) end
   local idx = node.index
   return match_node(node.children, str, pos, caps, function(np, nc)
    local before = nc[idx]
    nc[idx] = { pos, np }
    local r = cont(np, nc)
    if r == nil then nc[idx] = before end
    return r
   end)
  elseif t == "repeat" then
   if node.simple then return match_simple_repeat(node, str, pos, caps, cont) end
   return match_repeat(node, str, pos, caps, cont, 0)
  elseif t == "anchor" then
   local k, ok = node.kind, false
   if k == "^" then ok = pos == 1 or (node.multiline and byte(str, pos - 1) == 10)
   elseif k == "$" then ok = pos > #str or (node.multiline and byte(str, pos) == 10)
   elseif k == "A" then ok = pos == 1
   elseif k == "z" then ok = pos > #str
   elseif k == "Z" then ok = pos > #str or (pos == #str and byte(str, pos) == 10)
   elseif k == "G" then ok = pos == caps.init
   else
    local pc = prev_cp(str, pos)
    local nc = decode(str, pos)
    local a = (pc ~= nil) and word_cp(pc, node.unicode) or false
    local b = (nc ~= nil) and word_cp(nc, node.unicode) or false
    ok = ((k == "\\b") == (a ~= b))
   end
   if ok then return cont(pos, caps) end
   return nil
  elseif t == "look" then
   local saved = snap(caps)
   local ok
   if node.ahead then
    ok = match_node(node.node, str, pos, caps, function(p) return p end)
   else
    local j = pos
    while j >= 1 do
     local b = byte(str, j)
     if b == nil or b < 0x80 or b >= 0xC0 then
      ok = match_node(node.node, str, j, caps, function(p)
       if p == pos then return p end
       return nil
      end)
      if ok then break end
     end
     j = j - 1
    end
   end
   if node.negate then
    restore(caps, saved)
    if ok then return nil end
    return cont(pos, caps)
   end
   if not ok then return nil end
   local r = cont(pos, caps)
   if r == nil then restore(caps, saved) end
   return r
  elseif t == "atomic" then
   local saved = snap(caps)
   local np = match_node(node.node, str, pos, caps, function(p) return p end)
   if np == nil then return nil end
   local r = cont(np, caps)
   if r == nil then restore(caps, saved) end
   return r
  elseif t == "backref" then
   local idx = node.index
   if node.indices then
    idx = nil
    for _, i in ipairs(node.indices) do
     if caps[i] then idx = i; break end
    end
   end
   local span = idx and caps[idx]
   if not span then return nil end
   local text = sub(str, span[1], span[2] - 1)
   local seg = sub(str, pos, pos + #text - 1)
   if seg == text or (node.icase and fold_str(seg) == fold_str(text)) then
    return cont(pos + #text, caps)
   end
   return nil
  elseif t == "call" then
   local target, rec = node.target, caps.rec
   local key = target.rid .. ":" .. pos
   if rec[key] then return nil end
   rec[key] = true
   local saved = snap(caps)
   local r = match_node(target, str, pos, caps, function(np, nc)
    rec[key] = nil
    local inner = snap(nc)
    restore(nc, saved)
    local res = cont(np, nc)
    if res == nil then restore(nc, inner); rec[key] = true end
    return res
   end)
   rec[key] = nil
   if r == nil then restore(caps, saved) end
   return r
  elseif t == "cond" then
   local test, truth, saved = node.test, false, nil
   if test.type == "condref" then
    if test.indices then
     for _, i in ipairs(test.indices) do
      if caps[i] then truth = true; break end
     end
    else
     truth = caps[test.index] ~= nil
    end
   else
    saved = snap(caps)
    truth = match_node(test, str, pos, caps, function(p) return p end) ~= nil
   end
   local r = match_node(truth and node.yes or node.no, str, pos, caps, cont)
   if r == nil and saved then restore(caps, saved) end
   return r
  elseif t == "keep" then
   local prev = caps.K
   caps.K = pos
   local r = cont(pos, caps)
   if r == nil then caps.K = prev end
   return r
  end
  return nil
 end

 local function parse_flags(flags)
  local f = { i = false, m = false, s = false, x = false, u = false }
  if flags then
   for ch in flags:gmatch(".") do
    if f[ch] == nil then error("unknown flag '" .. ch .. "'", 0) end
    f[ch] = true
   end
  end
  return f
 end

 local cache, cache_n = {}, 0
 local function compile(pattern, flags)
  local key = (flags or "") .. "/" .. pattern
  local prog = cache[key]
  if not prog then
   local ast, n, names = parse(pattern, parse_flags(flags))
   prog = { ast = ast, ngroups = n, names = names, pattern = pattern, flags = flags or "" }
   if cache_n >= 256 then cache, cache_n = {}, 0 end
   cache[key] = prog
   cache_n = cache_n + 1
  end
  return prog
 end

 local function build_result(prog, str, start, finish, caps)
  local s = caps.K or start
  local captures, spans, named = {}, {}, {}
  for i = 1, prog.ngroups do
   local sp = caps[i]
   if sp then
    captures[i] = sub(str, sp[1], sp[2] - 1)
    spans[i] = { start = sp[1], finish = sp[2] }
   end
  end
  for name, list in pairs(prog.names) do
   for _, i in ipairs(list) do
    if captures[i] then named[name] = captures[i]; break end
   end
  end
  return {
   start = s, finish = finish, text = sub(str, s, finish - 1),
   captures = captures, named = named, spans = spans, groups = prog.ngroups,
  }
 end

 local function exec(prog, str, init)
  local n, start = #str, init
  while start <= n + 1 do
   local caps = { init = init, rec = {} }
   local finish = match_node(prog.ast, str, start, caps, function(p) return p end)
   if finish then return build_result(prog, str, start, finish, caps) end
   local _, len = decode(str, start)
   start = start + (len or 1)
  end
  return nil
 end

 local function norm_init(str, init)
  if not init then return 1 end
  if init < 0 then init = #str + init + 1 end
  if init < 1 then init = 1 end
  return init
 end

 local function each_match(prog, str, init, fn)
  local pos, n = init, #str
  while pos <= n + 1 do
   local m = exec(prog, str, pos)
   if not m then return end
   if fn(m) then return end
   if m.finish > m.start then
    pos = m.finish
   else
    local _, len = decode(str, m.finish)
    pos = m.finish + (len or 1)
   end
  end
 end

 local function expand(tpl, m)
  local out, i, n = {}, 1, #tpl
  while i <= n do
   if sub(tpl, i, i) == "$" then
    local nx = sub(tpl, i + 1, i + 1)
    if nx == "$" then out[#out + 1] = "$"; i = i + 2
    elseif nx == "&" then out[#out + 1] = m.text; i = i + 2
    elseif nx == "{" or nx == "<" then
     local e = tpl:find(nx == "{" and "}" or ">", i + 2, true)
     if e then
      local ref = sub(tpl, i + 2, e - 1)
      local v
      if ref:match("^%d+$") then
       v = (ref == "0") and m.text or m.captures[tonumber(ref)]
      else
       v = m.named[ref]
      end
      out[#out + 1] = v or ""
      i = e + 1
     else
      out[#out + 1] = "$"; i = i + 1
     end
    elseif nx:match("^%d$") then
     local digits = tpl:match("^%d%d?", i + 1)
     local idx = tonumber(digits)
     if #digits == 2 and idx > m.groups then digits = sub(digits, 1, 1); idx = tonumber(digits) end
     out[#out + 1] = (idx == 0) and m.text or (m.captures[idx] or "")
     i = i + 1 + #digits
    else
     out[#out + 1] = "$"; i = i + 1
    end
   else
    local e = tpl:find("$", i, true) or (n + 1)
    out[#out + 1] = sub(tpl, i, e - 1)
    i = e
   end
  end
  return concat(out)
 end

 local function gsub_prog(prog, str, repl, limit)
  local rt = type(repl)
  if rt ~= "string" and rt ~= "function" and rt ~= "table" then
   error("replacement must be a string, function or table", 3)
  end
  local out, last, count = {}, 1, 0
  each_match(prog, str, 1, function(m)
   if limit and count >= limit then return true end
   local r
   if rt == "string" then
    r = expand(repl, m)
   elseif rt == "function" then
    r = repl(m)
   else
    r = repl[m.captures[1] or m.text]
   end
   if r == nil or r == false then r = m.text end
   out[#out + 1] = sub(str, last, m.start - 1)
   out[#out + 1] = tostring(r)
   last = m.finish
   count = count + 1
  end)
  out[#out + 1] = sub(str, last)
  return concat(out), count
 end

 local function split_prog(prog, str, limit)
  local parts, last, splits, n = {}, 1, 0, #str
  each_match(prog, str, 1, function(m)
   if m.finish == m.start and (m.start == 1 or m.start > n) then return false end
   if limit and splits >= limit then return true end
   parts[#parts + 1] = sub(str, last, m.start - 1)
   for i = 1, m.groups do
    if m.captures[i] then parts[#parts + 1] = m.captures[i] end
   end
   last = m.finish
   splits = splits + 1
  end)
  parts[#parts + 1] = sub(str, last)
  return parts
 end

 local function findall_prog(prog, str, init)
  local list = {}
  each_match(prog, str, init, function(m) list[#list + 1] = m end)
  return list
 end

 local function gmatch_prog(prog, str, init)
  local pos, n = init, #str
  return function()
   if pos > n + 1 then return nil end
   local m = exec(prog, str, pos)
   if not m then pos = n + 2; return nil end
   if m.finish > m.start then
    pos = m.finish
   else
    local _, len = decode(str, m.finish)
    pos = m.finish + (len or 1)
   end
   return m
  end
 end

 local function match_values(m)
  if not m then return nil end
  if m.groups == 0 then return m.text end
  return unpack(m.captures, 1, m.groups)
 end

 local function prep(str, pattern, flags)
  if type(str) ~= "string" or type(pattern) ~= "string" then return nil, "str and pattern must be strings" end
  local ok, prog = pcall(compile, pattern, flags)
  if not ok then return nil, prog end
  return prog
 end

 function Regex.find(str, pattern, flags, init)
  local prog, err = prep(str, pattern, flags)
  if not prog then return nil, err end
  return exec(prog, str, norm_init(str, init))
 end

 function Regex.test(str, pattern, flags)
  return Regex.find(str, pattern, flags) ~= nil
 end

 function Regex.match(str, pattern, flags, init)
  local m, err = Regex.find(str, pattern, flags, init)
  if not m then return nil, err end
  return match_values(m)
 end

 function Regex.findall(str, pattern, flags, init)
  local prog, err = prep(str, pattern, flags)
  if not prog then return nil, err end
  return findall_prog(prog, str, norm_init(str, init))
 end

 function Regex.gmatch(str, pattern, flags, init)
  local prog, err = prep(str, pattern, flags)
  if not prog then error(err, 2) end
  return gmatch_prog(prog, str, norm_init(str, init))
 end

 function Regex.gsub(str, pattern, repl, flags, limit)
  local prog, err = prep(str, pattern, flags)
  if not prog then return nil, err end
  return gsub_prog(prog, str, repl, limit)
 end

 function Regex.split(str, pattern, flags, limit)
  local prog, err = prep(str, pattern, flags)
  if not prog then return nil, err end
  return split_prog(prog, str, limit)
 end

 function Regex.validate(pattern, flags)
  if type(pattern) ~= "string" then return false, "pattern must be a string" end
  local ok, err = pcall(compile, pattern, flags)
  if ok then return true end
  return false, err
 end

 function Regex.escape(s)
  return (s:gsub("[%^%$%.%|%?%*%+%(%)%[%]%{%}\\%-%s#]", "\\%0"))
 end

 function Regex.compile(pattern, flags)
  if type(pattern) ~= "string" then return nil, "pattern must be a string" end
  local ok, prog = pcall(compile, pattern, flags)
  if not ok then return nil, prog end
  return setmetatable({ prog = prog, pattern = pattern, flags = flags or "", groups = prog.ngroups }, Compiled)
 end

 function Compiled:find(str, init) return exec(self.prog, str, norm_init(str, init)) end
 function Compiled:test(str, init) return exec(self.prog, str, norm_init(str, init)) ~= nil end
 function Compiled:match(str, init) return match_values(exec(self.prog, str, norm_init(str, init))) end
 function Compiled:findall(str, init) return findall_prog(self.prog, str, norm_init(str, init)) end
 function Compiled:gmatch(str, init) return gmatch_prog(self.prog, str, norm_init(str, init)) end
 function Compiled:gsub(str, repl, limit) return gsub_prog(self.prog, str, repl, limit) end
 function Compiled:split(str, limit) return split_prog(self.prog, str, limit) end
end

return Regex
