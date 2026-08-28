local function PickChar(chartype: string): string
 if chartype == "Number" then
  return string.char(math.random(0x30, 0x39))
 elseif chartype == "Unicode" then
  local roll = math.random()
  local codepoint: number

  if roll < 0.35 then
   codepoint = math.random(0x21, 0x7e)
  elseif roll < 0.9 then
   repeat
    codepoint = math.random(0x80, 0xffff)
   until not (codepoint >= 0xd800 and codepoint <= 0xdfff)
  else
   codepoint = math.random(0x10000, 0x10ffff)
  end

  local ok, result = pcall(utf8.char, codepoint)
  if ok then
   return result
  else
   return "�"
  end
 end
 return string.char(math.random(0x21, 0x7e))
end

local function RandomString(chartype: string?, min: number?, num: number?): string
 local resolvedType = chartype or "Normal"
 local length = math.random(min or 10, num or 25)
 local parts = {}
 for i = 1, length do
  table.insert(parts, PickChar(resolvedType))
 end
 return table.concat(parts)
end

return RandomString
