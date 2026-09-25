local PathFinder = {}

PathFinder.DefaultTimeout = 5

local sub = string.sub
local match = string.match
local gsub = string.gsub
local find = string.find

local rootLookup = {
 game = game,
 workspace = workspace,
}

local currentStart = nil

local rootCache = {}
local segmentCache = {}

local pathCache = {}

local function ResolveRoot(name)
 local cached = rootCache[name]
 if cached then
  return cached
 end

 local resolved = rootLookup[name]
 if not resolved then
  resolved = game:FindService(name)
 end

 if resolved then
  rootCache[name] = resolved
 end

 return resolved
end

local function CompEffectPath(path)
 if sub(path, 1, 1) ~= "@" then
  error(("invalid path %q: must start with '@'"):format(path), 4)
 end

 local afterAt = sub(path, 2)
 local rootName = match(afterAt, "^[^/]+")
 if not rootName or rootName == "" then
  error(("invalid path %q: no segments found"):format(path), 4)
 end

 local bareRootName = sub(rootName, 1, 1) == "~" and sub(rootName, 2) or rootName

 if ResolveRoot(bareRootName) then
  return path
 end

 if currentStart then
  return currentStart .. "/" .. afterAt
 end

 error(("unknown root %q in path %q (no Find.SetStart base is set)"):format(bareRootName, path), 3)
end

local function WaitForChildOfClass(parent, className, timeout)
 local existing = parent:FindFirstChildOfClass(className)
 if existing then
  return existing
 end

 local deadline = os.clock() + (timeout or PathFinder.DefaultTimeout)
 local conn = parent.ChildAdded:Connect(function() end)
 repeat
  task.wait()
  local found = parent:FindFirstChildOfClass(className)
  if found then
   conn:Disconnect()
   return found
  end
 until os.clock() >= deadline

 conn:Disconnect()
 return nil
end

local function WaitForChildWhichIsA(parent, className, timeout)
 local existing = parent:FindFirstChildWhichIsA(className)
 if existing then
  return existing
 end

 local deadline = os.clock() + (timeout or PathFinder.DefaultTimeout)
 local conn = parent.ChildAdded:Connect(function() end)
 repeat
  task.wait()
  local found = parent:FindFirstChildWhichIsA(className)
  if found then
   conn:Disconnect()
   return found
  end
 until os.clock() >= deadline

 conn:Disconnect()
 return nil
end

local function ParsePath(effectivePath)
 local segments = segmentCache[effectivePath]
 if segments then
  return segments
 end

 local names = {}
 local waits = {}
 local modes = {}
 local count = 0

 local len = #effectivePath
 local i = 2
 while i <= len do
  local slashPos = find(effectivePath, "/", i, true)
  local segEnd = slashPos and (slashPos - 1) or len

  if segEnd < i then
   error(("invalid path %q: empty segment name"):format(effectivePath), 3)
  end

  local raw = sub(effectivePath, i, segEnd)
  local wait = sub(raw, 1, 1) == "~"
  if wait then
   raw = sub(raw, 2)
  end

  local twoChar = sub(raw, 1, 2)
  local marker = sub(raw, 1, 1)
  local mode, name
  if twoChar == "^#" then
   mode, name = "ancestorClass", sub(raw, 3)
  elseif twoChar == "^*" then
   mode, name = "ancestorIsA", sub(raw, 3)
  elseif marker == "#" then
   mode, name = "class", sub(raw, 2)
  elseif marker == "*" then
   mode, name = "isa", sub(raw, 2)
  elseif marker == "^" then
   mode, name = "ancestor", sub(raw, 2)
  elseif marker == "!" then
   mode, name = "isaCheck", sub(raw, 2)
  else
   mode, name = "name", raw
  end

  if name == "" then
   error(("invalid path %q: empty segment name"):format(effectivePath), 3)
  end

  if wait and (mode == "ancestor" or mode == "ancestorClass" or mode == "ancestorIsA" or mode == "isaCheck") then
   error(("invalid path %q: '~' cannot be combined with '^' or '!'"):format(effectivePath), 3)
  end

  count += 1
  names[count] = name
  waits[count] = wait
  modes[count] = mode

  i = segEnd + 2
 end

 segments = { names = names, waits = waits, modes = modes, count = count }
 segmentCache[effectivePath] = segments
 return segments
end

function PathFinder.Find(path)
 local record = pathCache[path]
 if not record then
  record = { effectivePath = CompEffectPath(path) }
  pathCache[path] = record
 end

 local effectivePath = record.effectivePath
 local segments = ParsePath(effectivePath)
 local names, waits, count = segments.names, segments.waits, segments.count

 local modes = segments.modes
 local chain = record.chain
 if chain then
  local leaf = chain[count]
  if leaf and leaf.Parent ~= nil then
   return leaf
  end
 else
  chain = table.create(count)
  record.chain = chain
 end

 local current, startIndex

 for i = count - 1, 2, -1 do
  local inst = chain[i]
  if inst and inst.Parent ~= nil then
   current = inst
   startIndex = i + 1
   break
  end
 end

 if not current then
  current = ResolveRoot(names[1])
  if not current then
   error(("unknown root %q in path %q"):format(names[1], effectivePath), 2)
  end
  chain[1] = current
  startIndex = 2
 end

 local timeout = PathFinder.DefaultTimeout
 for i = startIndex, count do
  local name = names[i]
  local mode = modes[i]

  if mode == "class" then
   current = waits[i] and WaitForChildOfClass(current, name, timeout) or current:FindFirstChildOfClass(name)
  elseif mode == "isa" then
   current = waits[i] and WaitForChildWhichIsA(current, name, timeout) or current:FindFirstChildWhichIsA(name)
  elseif mode == "ancestor" then
   current = current:FindFirstAncestor(name)
  elseif mode == "ancestorClass" then
   current = current:FindFirstAncestorOfClass(name)
  elseif mode == "ancestorIsA" then
   current = current:FindFirstAncestorWhichIsA(name)
  elseif mode == "isaCheck" then
   current = current:IsA(name) and current or nil
  else
   current = waits[i] and current:WaitForChild(name, timeout) or current:FindFirstChild(name)
  end

  if not current then
   for j = i, count do
    chain[j] = nil
   end
   return nil
  end

  chain[i] = current
 end

 return current
end

function PathFinder.SetStart(startPath)
 if startPath == nil then
  currentStart = nil
  table.clear(pathCache)
  return
 end

 assert(type(startPath) == "string", "parameter must be a string or nil")
 if sub(startPath, 1, 1) ~= "@" then
  error("path must start with '@'", 2)
 end

 currentStart = (gsub(startPath, "/+$", ""))
 table.clear(pathCache)
end

function PathFinder.Invalidate(path)
 local record = pathCache[path]
 if record then
  record.chain = nil
 end
end

function PathFinder.ClearCache()
 table.clear(pathCache)
 table.clear(segmentCache)
 table.clear(rootCache)
end

setmetatable(PathFinder, {
 __call = function(_, path)
  return PathFinder.Find(path)
 end,
})

return PathFinder
