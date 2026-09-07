const TweenService: TweenService = game:GetService("TweenService")
const PlayerGui: Instance = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

const W: number, H: number, PAD: number = 300, 70, 10
const SLIDE_TIME: number = 0.4
const HOLD_TIME: number = 3
const MAX_NOTIFS: number = 5

const ACCENT: {
 info: Color3,
 success: Color3,
 warning: Color3,
 error: Color3
} = {
 info = Color3.fromRGB(59, 130, 246),
 success = Color3.fromRGB(34, 197, 94),
 warning = Color3.fromRGB(234, 179, 8),
 error = Color3.fromRGB(239, 68, 68),
}

const gui: ScreenGui = Instance.new("ScreenGui")
gui.Name = "NotificationGui"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

const stack: {Instance} = {}

const function reflow(): ()
 for i, frame in ipairs(stack) do
  TweenService:Create(frame,
   TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
   { Position = UDim2.new(1, -(W + 10), 1, -(H + PAD) * i) }
  ):Play()
 end
end

const function dismiss(frame: any): ()
 for i, f in ipairs(stack) do
  if f == frame then
   table.remove(stack, i)
   break
  end
 end
 TweenService:Create(frame,
  TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
  { Position = UDim2.new(1, 10, frame.Position.Y.Scale, frame.Position.Y.Offset) }
 ):Play()
 task.delay(SLIDE_TIME, function() frame:Destroy() end)
 task.delay(SLIDE_TIME + 0.05, reflow)
end

const function makelabel(parent: Instance?, text: string, font: Enum.Font, size: number, color3: Color3, yOffset: number): ()
 const lbl: TextLabel = Instance.new("TextLabel")
 lbl.Size = UDim2.new(1, -20, 0, 22)
 lbl.Position = UDim2.new(0, 14, 0, yOffset)
 lbl.Text = text
 lbl.Font = font
 lbl.TextSize = size
 lbl.TextColor3 = color3
 lbl.BackgroundTransparency = 1
 lbl.TextXAlignment = Enum.TextXAlignment.Left
 lbl.Parent = parent
end

const function notify<type>(title: string, message: string, notifType: type)
 if #stack >= MAX_NOTIFS then dismiss(stack[#stack]) end

 const color: any = ACCENT[notifType] or ACCENT.info

 const frame: Frame = Instance.new("Frame")
 frame.Size = UDim2.new(0, W, 0, H)
 frame.Position = UDim2.new(1, 10, 1, -(H + PAD))
 frame.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
 frame.BorderSizePixel = 0
 frame.Parent = gui
 Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

 const bar: Frame = Instance.new("Frame")
 bar.Size, bar.BackgroundColor3, bar.BorderSizePixel = UDim2.new(0, 4, 1, 0), color, 0
 bar.Parent = frame
 Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

 makelabel(frame, title, Enum.Font.GothamBold, 14, Color3.new(1, 1, 1), 10)
 makelabel(frame, message, Enum.Font.Gotham, 12, Color3.fromRGB(170, 170, 180), 34)

 table.insert(stack, 1, frame)
 for i = 2, #stack do
  TweenService:Create(stack[i],
   TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
   { Position = UDim2.new(1, -(W + 10), 1, -(H + PAD) * i) }
  ):Play()
 end

 TweenService:Create(frame,
  TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
  { Position = UDim2.new(1, -(W + 10), 1, -(H + PAD)) }
 ):Play()

 task.delay(HOLD_TIME, function()
  if frame.Parent then dismiss(frame) end
 end)
end

return {notify}
