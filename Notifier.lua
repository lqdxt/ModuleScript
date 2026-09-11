const TweenService: TweenService = game:GetService("TweenService")
const PlayerGui: Instance = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

const W: number, H: number, PAD: number = 320, 76, 12
const SLIDE_TIME: number = 0.4
const HOLD_TIME: number = 3
const MAX_NOTIFS: number = 5
const ICON_SIZE: number = 56

const ACCENT: {
 info: Color3,
 success: Color3,
 warning: Color3,
 error: Color3,
} = {
 info = Color3.fromRGB(59, 130, 246),
 success = Color3.fromRGB(34, 197, 94),
 warning = Color3.fromRGB(234, 179, 8),
 error = Color3.fromRGB(239, 68, 68),
}

const ICONS: {
 info: string,
 success: string,
 warning: string,
 error: string,
} = {
 info = "rbxassetid://131271826879872",
 success = "rbxassetid://17829956110",
 warning = "rbxassetid://14563958666",
 error = "rbxassetid://14563958666",
}

type NOTIF_TYPES = "info" | "success" | "warning" | "error"

const gui: ScreenGui = Instance.new("ScreenGui")
gui.Name = "NotificationGui"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

const stack: {Instance} = {}

const function Target(i: number): UDim2
 return UDim2.new(1, -(W + PAD), 1, -(H + PAD) * i - PAD)
end

const function Reflow(): ()
 for i, frame in ipairs(stack) do
  TweenService:Create(
   frame,
   TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
   { Position = Target(i) }
  ):Play()
 end
end

const function Dismiss(frame: any): ()
 for i, f in ipairs(stack) do
  if f == frame then
   table.remove(stack, i)
   break
  end
 end

 const fade: Tween = TweenService:Create(
  frame,
  TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
  {
   Position = UDim2.new(1, 30, frame.Position.Y.Scale, frame.Position.Y.Offset),
   BackgroundTransparency = 1,
  }
 )
 fade:Play()

 for _, child in ipairs(frame:GetDescendants()) do
  if child:IsA("TextLabel") then
   TweenService:Create(child, TweenInfo.new(SLIDE_TIME), { TextTransparency = 1 }):Play()
  elseif child:IsA("ImageLabel") then
   TweenService:Create(child, TweenInfo.new(SLIDE_TIME), { ImageTransparency = 1 }):Play()
  elseif child:IsA("Frame") then
   TweenService:Create(child, TweenInfo.new(SLIDE_TIME), { BackgroundTransparency = 1, Transparency = 1 }):Play()
  end
 end

 task.delay(SLIDE_TIME, function()
  frame:Destroy()
 end)
 task.delay(SLIDE_TIME + 0.05, Reflow)
end

const function MakeLabel(parent: Instance?, text: string, font: Enum.Font, size: number, color3: Color3, xOffset: number, yOffset: number): TextLabel
 const lbl: TextLabel = Instance.new("TextLabel")
 lbl.Size = UDim2.new(1, -(xOffset + 14), 0, 20)
 lbl.Position = UDim2.new(0, xOffset, 0, yOffset)
 lbl.Text = text
 lbl.Font = font
 lbl.TextSize = size
 lbl.TextColor3 = color3
 lbl.TextTransparency = 0
 lbl.BackgroundTransparency = 1
 lbl.TextXAlignment = Enum.TextXAlignment.Left
 lbl.TextTruncate = Enum.TextTruncate.AtEnd
 lbl.Parent = parent
 return lbl
end

const function Notify(title: string, message: string, notifType: NOTIF_TYPES)
 if #stack >= MAX_NOTIFS then
  Dismiss(stack[#stack])
 end

 const color: Color3 = ACCENT[notifType] or ACCENT.info
 const icon: string = ICONS[notifType] or ICONS.info

 const frame: Frame = Instance.new("Frame")
 frame.Size = UDim2.new(0, W, 0, H)
 frame.Position = UDim2.new(1, 30, 1, -(H + PAD))
 frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
 frame.BorderSizePixel = 0
 frame.ClipsDescendants = false
 frame.Parent = gui

 const corner: UICorner = Instance.new("UICorner")
 corner.CornerRadius = UDim.new(0, 12)
 corner.Parent = frame

 const stroke: UIStroke = Instance.new("UIStroke")
 stroke.Color = Color3.fromRGB(255, 255, 255)
 stroke.Transparency = 0.92
 stroke.Thickness = 1
 stroke.Parent = frame

 const gradient: UIGradient = Instance.new("UIGradient")
 gradient.Color = ColorSequence.new({
  ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 34, 40)),
  ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 24)),
 })
 gradient.Rotation = 90
 gradient.Parent = frame

 const bar: Frame = Instance.new("Frame")
 bar.Size = UDim2.new(0, 3, 1, -20)
 bar.Position = UDim2.new(0, 0, 0, 10)
 bar.BackgroundColor3 = color
 bar.BorderSizePixel = 0
 bar.Parent = frame
 const barCorner: UICorner = Instance.new("UICorner")
 barCorner.CornerRadius = UDim.new(1, 0)
 barCorner.Parent = bar

 const iconPos: Frame = Instance.new("Frame")
 iconPos.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
 iconPos.Position = UDim2.new(0, 16, 0.5, -ICON_SIZE / 2)
 iconPos.BackgroundColor3 = color
 iconPos.BackgroundTransparency = 1
 iconPos.BorderSizePixel = 0
 iconPos.Parent = frame

 const iconImg: ImageLabel = Instance.new("ImageLabel")
 iconImg.Size = UDim2.new(0, ICON_SIZE - 14, 0, ICON_SIZE - 14)
 iconImg.Position = UDim2.new(0.5, -(ICON_SIZE - 14) / 2, 0.5, -(ICON_SIZE - 14) / 2)
 iconImg.BackgroundTransparency = 1
 iconImg.Image = icon
 iconImg.ImageColor3 = iconPos.BackgroundColor3
 iconImg.Parent = iconPos

 const textX: number = 16 + ICON_SIZE + 12
 MakeLabel(frame, title, Enum.Font.GothamBold, 14, Color3.new(1, 1, 1), textX, 14)
 MakeLabel(frame, message, Enum.Font.Gotham, 12, Color3.fromRGB(165, 165, 175), textX, 36)

 table.insert(stack, 1, frame)
 for i = 2, #stack do
  TweenService:Create(
   stack[i],
   TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
   { Position = Target(i) }
  ):Play()
 end

 TweenService:Create(
  frame,
  TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
  { Position = Target(1) }
 ):Play()

 task.delay(HOLD_TIME, function()
  if frame.Parent then
   Dismiss(frame)
  end
 end)
end

return Notify
