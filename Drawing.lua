local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local AssetService = game:GetService("AssetService")
local GuiService = game:GetService("GuiService")

local Drawing = {}
Drawing.Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 }

local FontMap = {
 [0] = Enum.Font.Arial,
 [1] = Enum.Font.SourceSans,
 [2] = Enum.Font.Ubuntu,
 [3] = Enum.Font.RobotoMono,
}

local MAX_FILL_ROWS = 2000
local TEXT_SCALE = 0.8

local function textSize(size)
 return math.max(1, math.floor(size * TEXT_SCALE + 0.5))
end
local MAX_CANVAS = 1024
local CANVAS_STEP = 32
local LINE_WEIGHT = 1

local AA_OFF = nil
do
 local ok, v = pcall(function()
  return Enum.AntiAliasing.Disabled
 end)
 if ok then
  AA_OFF = v
 end
end

local editableOk = true

local gui
local pixelScale = 1
local onScaleChanged

local function updateScale()
 if not gui then
  return
 end
 local ok, res = pcall(function()
  return GuiService:GetScreenResolution()
 end)
 local w = gui.AbsoluteSize.X
 if ok and w > 0 then
  local s = math.max(res.X / w, 1)
  if math.abs(s - pixelScale) > 0.01 then
   pixelScale = s
   if onScaleChanged then
    onScaleChanged()
   end
  end
 end
end

local function getGui()
 if gui and gui.Parent then
  return gui
 end
 gui = Instance.new("ScreenGui")
 gui.Name = "DrawingAPI"
 gui.IgnoreGuiInset = true
 gui.ResetOnSpawn = false
 gui.DisplayOrder = 10000
 gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
 gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
 updateScale()
 gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
 return gui
end

local registry = {}

local function markDirty(state)
 if not state.dead then
  state.spec.render(state, state.props)
 end
end

onScaleChanged = function()
 for _, state in registry do
  markDirty(state)
 end
end

local function newInst(class, props, parent)
 local inst = Instance.new(class)
 for k, v in props do
  inst[k] = v
 end
 inst.Parent = parent
 return inst
end

local nextSeq = 0
local function z(p)
 return math.clamp(math.floor(p.ZIndex), 0, 2000) * 1000000 + p._seq
end

local function takeFrame(state, index, p)
 local f = state.pool[index]
 if not f then
  f = newInst("Frame", {
   BorderSizePixel = 0,
   AnchorPoint = Vector2.new(0.5, 0.5),
  }, state.holder)
  state.pool[index] = f
 end
 f.Visible = true
 f.BackgroundColor3 = p.Color
 f.BackgroundTransparency = 1 - p.Transparency
 f.ZIndex = z(p)
 return f
end

local function setSegment(f, a, b, thickness)
 local d = b - a
 f.Size = UDim2.fromOffset(d.Magnitude, thickness)
 f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
 f.Rotation = math.deg(math.atan2(d.Y, d.X))
end

local function renderPoly(state, p, pts)
 state.holder.Visible = p.Visible
 local used = 0
 local n = #pts

 if p.Filled then
  local minY, maxY = math.huge, -math.huge
  for _, pt in pts do
   minY = math.min(minY, pt.Y)
   maxY = math.max(maxY, pt.Y)
  end
  minY, maxY = math.floor(minY), math.ceil(maxY)
  if maxY - minY <= MAX_FILL_ROWS then
   for y = minY, maxY - 1 do
    local sy = y + 0.5
    local xs = {}
    for i = 1, n do
     local a, b = pts[i], pts[i % n + 1]
     if (a.Y <= sy and b.Y > sy) or (b.Y <= sy and a.Y > sy) then
      table.insert(xs, a.X + (sy - a.Y) / (b.Y - a.Y) * (b.X - a.X))
     end
    end
    table.sort(xs)
    for i = 1, #xs - 1, 2 do
     used += 1
     local f = takeFrame(state, used, p)
     f.Rotation = 0
     f.Size = UDim2.fromOffset(math.max(xs[i + 1] - xs[i], 1), 1)
     f.Position = UDim2.fromOffset((xs[i] + xs[i + 1]) / 2, sy)
    end
   end
  end
 else
  for i = 1, n do
   used += 1
   setSegment(takeFrame(state, used, p), pts[i], pts[i % n + 1], p.Thickness / pixelScale)
  end
 end

 for i = used + 1, #state.pool do
  state.pool[i].Visible = false
 end
end

local Classes = {}

Classes.Line = {
 defaults = {
  From = Vector2.zero,
  To = Vector2.zero,
  Thickness = 1,
 },
 build = function(state)
  state.instances = {}
  state.cap = Vector2.zero
  state.used = Vector2.zero
 end,
 render = function(state, p)
  local S = pixelScale
  local a, b = p.From, p.To
  local ax, ay, bx, by = a.X * S, a.Y * S, b.X * S, b.Y * S
  local minX = math.floor(math.min(ax, bx)) - 1
  local minY = math.floor(math.min(ay, by)) - 1
  local cw = math.ceil(math.max(ax, bx)) - minX + 2
  local ch = math.ceil(math.max(ay, by)) - minY + 2

  local useImage = editableOk and p.Thickness <= 1 and cw <= MAX_CANVAS and ch <= MAX_CANVAS

  if useImage then
   if not state.canvas or state.cap.X < cw or state.cap.Y < ch then
    local capW = math.min(math.ceil(math.max(cw, state.cap.X) / CANVAS_STEP) * CANVAS_STEP, MAX_CANVAS)
    local capH = math.min(math.ceil(math.max(ch, state.cap.Y) / CANVAS_STEP) * CANVAS_STEP, MAX_CANVAS)
    local ok, img = pcall(function()
     return AssetService:CreateEditableImage({ Size = Vector2.new(capW, capH) })
    end)
    if ok and img then
     if state.canvas then
      state.canvas:Destroy()
     end
     state.canvas = img
     state.cap = Vector2.new(capW, capH)
     state.used = Vector2.zero
     if not state.image then
      state.image = newInst("ImageLabel", {
       BackgroundTransparency = 1,
       BorderSizePixel = 0,
       ResampleMode = Enum.ResamplerMode.Pixelated,
      }, getGui())
      table.insert(state.instances, state.image)
     end
     state.image.ImageContent = Content.fromObject(img)
    else
     editableOk = false
     useImage = false
    end
   end
  end

  if useImage then
   local canvas, image = state.canvas, state.image
   local clear = Vector2.new(math.max(state.used.X, cw), math.max(state.used.Y, ch))
   canvas:DrawRectangle(Vector2.zero, clear, p.Color, 1, Enum.ImageCombineType.Overwrite)

   local A = Vector2.new(ax - minX, ay - minY)
   local B = Vector2.new(bx - minX, by - minY)
   local d = B - A
   local normal = if d.Magnitude > 1e-3 then Vector2.new(-d.Y, d.X) / d.Magnitude else Vector2.new(0, 1)
   local alpha = 1 - p.Transparency
   for i = 0, LINE_WEIGHT - 1 do
    local off = normal * (i - (LINE_WEIGHT - 1) / 2)
    if AA_OFF then
     canvas:DrawLine(A + off, B + off, p.Color, alpha, Enum.ImageCombineType.Overwrite, AA_OFF)
    else
     canvas:DrawLine(A + off, B + off, p.Color, alpha, Enum.ImageCombineType.AlphaBlend)
    end
   end
   state.used = Vector2.new(cw, ch)

   image.Visible = p.Visible
   image.ZIndex = z(p)
   image.Position = UDim2.fromOffset(minX / S, minY / S)
   image.Size = UDim2.fromOffset(cw / S, ch / S)
   image.ImageRectOffset = Vector2.zero
   image.ImageRectSize = Vector2.new(cw, ch)
   if state.frame then
    state.frame.Visible = false
   end
  else
   if not state.frame then
    state.frame = newInst("Frame", {
     BorderSizePixel = 0,
     AnchorPoint = Vector2.new(0.5, 0.5),
    }, getGui())
    table.insert(state.instances, state.frame)
   end
   local f = state.frame
   f.Visible = p.Visible
   f.BackgroundColor3 = p.Color
   f.BackgroundTransparency = 1 - p.Transparency
   f.ZIndex = z(p)
   setSegment(f, a, b, p.Thickness / S)
   if state.image then
    state.image.Visible = false
   end
  end
 end,
 destroy = function(state)
  if state.canvas then
   state.canvas:Destroy()
   state.canvas = nil
  end
 end,
}

Classes.Square = {
 defaults = {
  Position = Vector2.zero,
  Size = Vector2.zero,
  Thickness = 1,
  Filled = false,
 },
 build = function(state)
  state.frame = newInst("Frame", { BorderSizePixel = 0 }, getGui())
  state.edges = {}
  for i = 1, 4 do
   state.edges[i] = newInst("Frame", { BorderSizePixel = 0, Visible = false }, state.frame)
  end
  state.instances = { state.frame }
 end,
 render = function(state, p)
  local f, e = state.frame, state.edges
  f.Visible = p.Visible
  f.ZIndex = z(p)
  f.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
  f.Size = UDim2.fromOffset(p.Size.X, p.Size.Y)
  f.BackgroundColor3 = p.Color
  if p.Filled then
   f.BackgroundTransparency = 1 - p.Transparency
   for i = 1, 4 do
    e[i].Visible = false
   end
  else
   f.BackgroundTransparency = 1
   local t = p.Thickness / pixelScale
   e[1].Position, e[1].Size = UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, t)
   e[2].Position, e[2].Size = UDim2.new(0, 0, 1, -t), UDim2.new(1, 0, 0, t)
   e[3].Position, e[3].Size = UDim2.new(0, 0, 0, t), UDim2.new(0, t, 1, -2 * t)
   e[4].Position, e[4].Size = UDim2.new(1, -t, 0, t), UDim2.new(0, t, 1, -2 * t)
   for i = 1, 4 do
    local ed = e[i]
    ed.Visible = true
    ed.ZIndex = z(p)
    ed.BackgroundColor3 = p.Color
    ed.BackgroundTransparency = 1 - p.Transparency
   end
  end
 end,
}

Classes.Circle = {
 defaults = {
  Position = Vector2.zero,
  Radius = 0,
  Thickness = 1,
  NumSides = 0,
  Filled = false,
 },
 build = function(state)
  state.frame = newInst("Frame", {
   BorderSizePixel = 0,
   AnchorPoint = Vector2.new(0.5, 0.5),
  }, getGui())
  newInst("UICorner", { CornerRadius = UDim.new(1, 0) }, state.frame)
  state.stroke = newInst("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, state.frame)
  state.instances = { state.frame }
 end,
 render = function(state, p)
  local f, s = state.frame, state.stroke
  f.Visible = p.Visible
  f.ZIndex = z(p)
  f.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
  f.Size = UDim2.fromOffset(p.Radius * 2, p.Radius * 2)
  f.BackgroundColor3 = p.Color
  if p.Filled then
   f.BackgroundTransparency = 1 - p.Transparency
   s.Enabled = false
  else
   f.BackgroundTransparency = 1
   s.Enabled = true
   s.Thickness = p.Thickness / pixelScale
   s.Color = p.Color
   s.Transparency = 1 - p.Transparency
  end
 end,
}

Classes.Text = {
 defaults = {
  Text = "",
  Size = 14,
  Center = false,
  Outline = false,
  OutlineColor = Color3.new(0, 0, 0),
  Position = Vector2.zero,
  Font = 0,
 },
 build = function(state)
  state.label = newInst("TextLabel", {
   BackgroundTransparency = 1,
   BorderSizePixel = 0,
   AutomaticSize = Enum.AutomaticSize.XY,
   Size = UDim2.fromOffset(0, 0),
   TextXAlignment = Enum.TextXAlignment.Left,
   TextYAlignment = Enum.TextYAlignment.Top,
  }, getGui())
  state.instances = { state.label }
 end,
 render = function(state, p)
  local l = state.label
  l.Visible = p.Visible
  l.ZIndex = z(p)
  l.Text = p.Text
  l.TextSize = textSize(p.Size)
  l.Font = FontMap[p.Font] or Enum.Font.Arial
  l.TextColor3 = p.Color
  l.TextTransparency = 1 - p.Transparency
  l.TextStrokeColor3 = p.OutlineColor
  l.TextStrokeTransparency = p.Outline and (1 - 0.2 * p.Transparency) or 1
  l.AnchorPoint = Vector2.new(p.Center and 0.5 or 0, 0)
  l.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
 end,
 getters = {
  TextBounds = function(p)
   return TextService:GetTextSize(
    p.Text,
    textSize(p.Size),
    FontMap[p.Font] or Enum.Font.Arial,
    Vector2.new(1e5, 1e5)
   )
  end,
 },
}

Classes.Image = {
 defaults = {
  Image = "",
  Position = Vector2.zero,
  Size = Vector2.zero,
  Rounding = 0,
 },
 build = function(state)
  state.image = newInst("ImageLabel", {
   BackgroundTransparency = 1,
   BorderSizePixel = 0,
  }, getGui())
  state.corner = newInst("UICorner", {}, state.image)
  state.instances = { state.image }
 end,
 render = function(state, p)
  local i = state.image
  i.Visible = p.Visible
  i.ZIndex = z(p)
  i.Image = p.Image
  i.ImageColor3 = p.Color
  i.ImageTransparency = 1 - p.Transparency
  i.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
  i.Size = UDim2.fromOffset(p.Size.X, p.Size.Y)
  state.corner.CornerRadius = UDim.new(0, p.Rounding)
 end,
}

local function polyBuild(state)
 state.holder = newInst("Frame", {
  BackgroundTransparency = 1,
  BorderSizePixel = 0,
  Size = UDim2.fromScale(1, 1),
 }, getGui())
 state.pool = {}
 state.instances = { state.holder }
end

Classes.Triangle = {
 defaults = {
  PointA = Vector2.zero,
  PointB = Vector2.zero,
  PointC = Vector2.zero,
  Thickness = 1,
  Filled = false,
 },
 build = polyBuild,
 render = function(state, p)
  renderPoly(state, p, { p.PointA, p.PointB, p.PointC })
 end,
}

Classes.Quad = {
 defaults = {
  PointA = Vector2.zero,
  PointB = Vector2.zero,
  PointC = Vector2.zero,
  PointD = Vector2.zero,
  Thickness = 1,
  Filled = false,
 },
 build = polyBuild,
 render = function(state, p)
  renderPoly(state, p, { p.PointA, p.PointB, p.PointC, p.PointD })
 end,
}

local function destroyState(state)
 if state.dead then
  return
 end
 state.dead = true
 if state.spec.destroy then
  state.spec.destroy(state)
 end
 for _, inst in state.instances do
  inst:Destroy()
 end
 registry[state.proxy] = nil
end

function Drawing.new(class)
 local spec = Classes[class]
 if not spec then
  error(("Invalid drawing type '%s'"):format(tostring(class)), 2)
 end

 nextSeq = nextSeq % 999999 + 1
 local props = {
  _seq = nextSeq,
  Visible = false,
  Color = Color3.new(0, 0, 0),
  Transparency = 1,
  ZIndex = 0,
 }
 for k, v in spec.defaults do
  props[k] = v
 end

 local state = { spec = spec, props = props, dead = false }
 spec.build(state)

 local proxy = setmetatable({}, {
  __index = function(_, k)
   if k == "Remove" or k == "Destroy" then
    return function()
     destroyState(state)
    end
   end
   val = spec.getters and spec.getters[k]
   if val then
    return val(props)
   end
   return props[k]
  end,
  __newindex = function(_, k, v)
   if props[k] == nil then
    error(("'%s' is not a valid property of %s"):format(tostring(k), class), 2)
   end
   if state.dead or props[k] == v then
    return
   end
   props[k] = v
   markDirty(state)
  end,
  __tostring = function()
   return "Drawing<" .. class .. ">"
  end,
 })

 state.proxy = proxy
 registry[proxy] = state
 markDirty(state)
 return proxy
end

function Drawing.clear()
 for _, state in registry do
  destroyState(state)
 end
end

function Drawing.isrenderobject(obj)
 return registry[obj] ~= nil
end

function Drawing.install(env)
 env.Drawing = Drawing
 env.cleardrawcache = Drawing.clear
 env.isrenderobject = Drawing.isrenderobject
end

return Drawing
