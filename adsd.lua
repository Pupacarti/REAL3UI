local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==========================================
-- [1] ระบบ Anti-AFK (กันหลุดตอนพับจอแบบ Windowed)
-- ==========================================
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
end)
if setfpscap then setfpscap(60) end

-- ==========================================
-- [2] ตัวแปรควบคุม & สถิติ (Stats)
-- ==========================================
local scriptActive = false 
local isRightClicking = false
local isEngaging = false

local requiredZombieCount = 2 
local lastShootTime = 0
local shootCooldown = 0.8
local currentTarget = nil 

local startTime = tick()
local totalKills = 0
local startMoney = 0

-- ดึงค่าเงินเริ่มต้นของผู้เล่น (หากเกมใช้ชื่ออื่นเช่น Credits, Tokens ให้เติมในวงเล็บด้านล่าง)
local leaderstats = LocalPlayer:WaitForChild("leaderstats", 5)
if leaderstats then
    local stat = leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Coins") or leaderstats:FindFirstChild("Points")
    if stat then startMoney = stat.Value end
end

-- ==========================================
-- [3] สร้างหน้าต่าง UI (Dark Theme)
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieFarm_StatsUI"
ScreenGui.ResetOnSpawn = false
local success = pcall(function() ScreenGui.Parent = CoreGui end)
if not success then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 300, 0, 260) -- ขยายขนาดเฟรมรองรับข้อมูลใหม่
MainFrame.Position = UDim2.new(0.5, -150, 0.8, -280)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 25, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true 
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local function createLabel(text, yPos, color, font)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -40, 0, 30)
    label.Position = UDim2.new(0, 20, 0, yPos)
    label.BackgroundTransparency = 1
    label.TextColor3 = color or Color3.fromRGB(220, 220, 220)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = font or Enum.Font.GothamSemibold
    label.TextSize = 14
    label.Text = text
    label.Parent = MainFrame
    return label
end

-- หัวข้อข้อมูล UI
local TitleLabel = createLabel("✨ AUTO FARM STATUS", 10, Color3.fromRGB(255, 200, 100), Enum.Font.GothamBold)
local TimeLabel = createLabel("⏱️ Time Elapsed: 00:00", 85)
local KillLabel = createLabel("💀 Zombies Killed: 0", 115)
local EarnedLabel = createLabel("💵 Total Earned: 0", 145)
local MoneyLabel = createLabel("💰 Money/Min: 0", 175)

local HideHint = createLabel("Press [Right Shift] to Toggle Menu", 225, Color3.fromRGB(100, 120, 100), Enum.Font.Gotham)
HideHint.TextSize = 11
HideHint.TextXAlignment = Enum.TextXAlignment.Center

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -40, 0, 35)
ToggleBtn.Position = UDim2.new(0, 20, 0, 45)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Text = "สคริปต์: OFF (คลิกเพื่อเปิด)"
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 14
ToggleBtn.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 6)
BtnCorner.Parent = ToggleBtn

-- ฟังก์ชันเปิด/ปิด การฟาร์ม
local function toggleScript()
    scriptActive = not scriptActive
    if scriptActive then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
        ToggleBtn.Text = "สคริปต์: ON"
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        ToggleBtn.Text = "สคริปต์: OFF"
        isEngaging = false
        currentTarget = nil
        if isRightClicking then
            isRightClicking = false
            local mousePos = UserInputService:GetMouseLocation()
            VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 1, false, game, 0)
        end
    end
end
ToggleBtn.MouseButton1Click:Connect(toggleScript)

-- กด Right Shift เพื่อซ่อน/โชว์ หน้าต่าง
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible 
    end
end)

-- ลูปอัปเดตตัวเลขสถิติบนหน้าจอ
task.spawn(function()
    while task.wait(1) do
        local elapsed = tick() - startTime
        local mins = math.floor(elapsed / 60)
        local secs = math.floor(elapsed % 60)
        TimeLabel.Text = string.format("⏱️ Time Elapsed: %02d:%02d", mins, secs)
        KillLabel.Text = "💀 Zombies Killed: " .. tostring(totalKills)
        
        -- ดึงเงินปัจจุบัน
        local currentMoney = startMoney
        if leaderstats then
            local stat = leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Coins") or leaderstats:FindFirstChild("Points")
            if stat then currentMoney = stat.Value end
        else
            currentMoney = startMoney + (totalKills * 50) -- ตัวเลขจำลองกรณีดึงเงินจากเกมไม่ได้
        end
        
        -- คำนวณเงิน
        local earned = currentMoney - startMoney
        EarnedLabel.Text = "💵 Total Earned: " .. tostring(earned)
        
        local moneyPerMin = mins > 0 and math.floor(earned / (elapsed / 60)) or earned
        MoneyLabel.Text = "💰 Money/Min: " .. tostring(moneyPerMin)
    end
end)

-- ==========================================
-- [4] ระบบยิง ล็อกเป้า และเช็กกำแพง (สคริปต์เดิมของคุณ)
-- ==========================================
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function isTargetVisible(targetHead)
    if not targetHead then return false end
    if LocalPlayer.Character then
        raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    end

    local origin = Camera.CFrame.Position
    local direction = targetHead.Position - origin
    local result = Workspace:Raycast(origin, direction, raycastParams)
    
    if not result or result.Instance:IsDescendantOf(targetHead.Parent) then return true end
    return false
end

local function getVisibleNPCs()
    local visibleList = {}
    for _, obj in pairs(Workspace:GetChildren()) do
        local modelCandidates = {}
        if obj:IsA("Model") then table.insert(modelCandidates, obj)
        elseif obj:IsA("Folder") then
            for _, child in pairs(obj:GetChildren()) do
                if child:IsA("Model") then table.insert(modelCandidates, child) end
            end
        end

        for _, model in pairs(modelCandidates) do
            local head = model:FindFirstChild("Head")
            local humanoid = model:FindFirstChild("Humanoid")
            if head and humanoid and humanoid.Health > 0 then
                if not Players:GetPlayerFromCharacter(model) and model ~= LocalPlayer.Character then
                    local headPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                    if onScreen and isTargetVisible(head) then
                        table.insert(visibleList, model)
                    end
                end
            end
        end
    end
    return visibleList
end

RunService.Heartbeat:Connect(function()
    -- ระบบเช็กซอมบี้ตายเพื่อบวกเลขคิล
    if currentTarget then
        local hum = currentTarget:FindFirstChild("Humanoid")
        if not currentTarget:IsDescendantOf(Workspace) or (hum and hum.Health <= 0) then
            totalKills = totalKills + 1
            currentTarget = nil
        end
    end

    if not scriptActive then return end

    local visibleZombies = getVisibleNPCs()
    local mousePos = UserInputService:GetMouse
