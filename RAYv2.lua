-- RAYv2 Roblox Cheat for RIVALS
-- Made by @ink
-- Compatible with Solara Executor (Level 7 UNC)
-- Full getgenv(), Drawing API, and advanced capabilities

-- Services and Variables
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Getgenv setup for persistence
getgenv().RAYv2 = getgenv().RAYv2 or {}
local RAYv2 = getgenv().RAYv2

-- Configuration Storage
RAYv2.Configs = RAYv2.Configs or {}
RAYv2.CurrentConfig = RAYv2.CurrentConfig or {}
RAYv2.CheatEnabled = false

-- Owner and Admin Settings
local OWNER_ID = 7143862381
local ADMIN_CREDENTIALS = {
    username = "adminHQ",
    password = "HQ080626"
}

-- Theme Colors (Cinematic Dark Theme)
local Theme = {
    Primary = Color3.fromRGB(0, 120, 255),      -- Electric Blue
    Secondary = Color3.fromRGB(15, 15, 20),       -- Deep Black
    Tertiary = Color3.fromRGB(25, 25, 35),       -- Dark Gray
    Accent = Color3.fromRGB(255, 255, 255),      -- Crisp White
    Gold = Color3.fromRGB(255, 215, 0),          -- Gold
    Success = Color3.fromRGB(0, 255, 100),       -- Neon Green
    Error = Color3.fromRGB(255, 50, 50),        -- Neon Red
    Warning = Color3.fromRGB(255, 165, 0)       -- Neon Orange
}

-- Cheat Settings
local Settings = {
    -- Aimbot Settings
    Aimbot = {
        Enabled = false,
        Key = Enum.UserInputType.MouseButton2,
        Mode = "Toggle", -- "Toggle" or "Hold"
        SilentAim = false,
        FOV = 90,
        ShowFOV = true,
        FillFOV = false,
        Smoothness = 5,
        Reach = 200,
        HeadPriority = true,
        Prediction = 0.1
    },
    
    -- Triggerbot Settings
    Triggerbot = {
        Enabled = false,
        Key = Enum.UserInputType.MouseButton1,
        Delay = 50
    },
    
    -- ESP Settings
    ESP = {
        Enabled = false,
        Boxes = true,
        Skeleton = false,
        Tracers = true,
        FillBoxes = false,
        Name = true,
        Health = true,
        MaxDistance = 300,
        Colors = {
            Boxes = Color3.fromRGB(255, 0, 0),
            Skeleton = Color3.fromRGB(0, 255, 255),
            Tracers = Color3.fromRGB(255, 255, 0),
            FillBoxes = Color3.fromRGB(255, 0, 0, 0.3),
            Name = Color3.fromRGB(255, 255, 255),
            Health = Color3.fromRGB(0, 255, 0)
        }
    },
    
    -- Spoofer Settings
    Spoofer = {
        Level = false,
        WinStreak = false,
        Keys = false,
        PremiumBadge = false,
        VerifiedBadge = false
    }
}

-- Global Variables
local GuiVisible = false
local MainScreenGui = nil
local AimbotTarget = nil
local AimbotActive = false
local ESPObjects = {}
local FOVCircle = nil

-- Utility Functions
local function CreateGradient(colors, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = colors or ColorSequence.new{
        ColorSequenceKeypoint.new(0, Theme.Primary),
        ColorSequenceKeypoint.new(0.5, Theme.Secondary),
        ColorSequenceKeypoint.new(1, Theme.Accent)
    }
    gradient.Rotation = rotation or 45
    return gradient
end

local function CreateCorner(element, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 5)
    corner.Parent = element
    return corner
end

local function CreateStroke(element, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.Primary
    stroke.Thickness = thickness or 1
    stroke.Parent = element
    return stroke
end

local function Tween(element, info, goal)
    local tween = TweenService:Create(element, info, goal)
    tween:Play()
    return tween
end

local function GetClosestPlayer()
    local closestPlayer = nil
    local closestDistance = Settings.Aimbot.Reach
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (player.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            if distance <= closestDistance then
                local screenPos, onScreen = Camera:WorldToViewportPoint(player.Character.HumanoidRootPart.Position)
                if onScreen then
                    closestDistance = distance
                    closestPlayer = player
                end
            end
        end
    end
    
    return closestPlayer
end

local function GetAimbotTarget()
    local target = GetClosestPlayer()
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
        local targetPart = target.Character.HumanoidRootPart
        if Settings.Aimbot.HeadPriority and target.Character:FindFirstChild("Head") then
            targetPart = target.Character.Head
        end
        return targetPart
    end
    return nil
end

local function WorldToScreenPoint(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    if onScreen then
        return Vector2.new(screenPos.X, screenPos.Y)
    end
    return nil
end

-- Loading Screen System
local function CreateLoadingScreen()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RAYv2Loading"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Main Frame
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(1, 0, 1, 0)
    MainFrame.BackgroundColor3 = Theme.Secondary
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui
    
    -- Animated Background Gradient
    local BackgroundGradient = CreateGradient()
    BackgroundGradient.Parent = MainFrame
    
    -- Particle System Background
    local ParticleContainer = Instance.new("Frame")
    ParticleContainer.Size = UDim2.new(1, 0, 1, 0)
    ParticleContainer.BackgroundTransparency = 1
    ParticleContainer.Parent = MainFrame
    
    -- Create animated particles
    local particles = {}
    for i = 1, 50 do
        local particle = Instance.new("Frame")
        particle.Size = UDim2.new(0, math.random(2, 4), 0, math.random(2, 4))
        particle.Position = UDim2.new(math.random(), 0, math.random(), 0)
        particle.BackgroundColor3 = Theme.Primary
        particle.BackgroundTransparency = math.random(0.3, 0.8)
        CreateCorner(particle, 50)
        particle.Parent = ParticleContainer
        table.insert(particles, particle)
        
        -- Animate particle
        spawn(function()
            local moveTime = math.random(5, 15)
            local targetX = math.random()
            local targetY = math.random()
            Tween(particle, TweenInfo.new(moveTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                Position = UDim2.new(targetX, 0, targetY, 0)
            })
        end)
    end
    
    -- Geometric Lines (store references)
    local lines = {}
    for i = 1, 5 do
        local line = Instance.new("Frame")
        line.Size = UDim2.new(0, math.random(100, 300), 0, 1)
        line.Position = UDim2.new(math.random(), 0, math.random(), 0)
        line.BackgroundColor3 = Theme.Primary
        line.BackgroundTransparency = 0.7
        line.Rotation = math.random(0, 360)
        line.Parent = MainFrame
        table.insert(lines, line)
        
        spawn(function()
            local rotateTime = math.random(10, 20)
            Tween(line, TweenInfo.new(rotateTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), {
                Rotation = line.Rotation + 360
            })
        end)
    end
    
    -- RAYv2 Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(0, 500, 0, 100)
    Title.Position = UDim2.new(0.5, -250, 0.5, -50)
    Title.BackgroundTransparency = 1
    Title.Text = "RAYv2"
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 80
    Title.TextColor3 = Theme.Accent
    Title.Parent = MainFrame
    
    -- Title Animated Gradient
    local TitleGradient = CreateGradient()
    TitleGradient.Parent = Title
    
    -- Animate title gradient
    local gradientRotation = 0
    spawn(function()
        while Title.Parent do
            gradientRotation = (gradientRotation + 1) % 360
            TitleGradient.Rotation = gradientRotation
            wait(0.016)
        end
    end)
    
    -- Made by text
    local MadeBy = Instance.new("TextLabel")
    MadeBy.Size = UDim2.new(0, 300, 0, 30)
    MadeBy.Position = UDim2.new(0.5, -150, 0.5, 60)
    MadeBy.BackgroundTransparency = 1
    MadeBy.Text = "made by @ink"
    MadeBy.Font = Enum.Font.Gotham
    MadeBy.TextSize = 20
    MadeBy.TextColor3 = Color3.fromRGB(120, 120, 120)
    MadeBy.TextTransparency = 0.5
    MadeBy.Parent = MainFrame
    
    -- Loading Bar
    local LoadingBar = Instance.new("Frame")
    LoadingBar.Size = UDim2.new(0, 400, 0, 6)
    LoadingBar.Position = UDim2.new(0.5, -200, 0.5, 120)
    LoadingBar.BackgroundColor3 = Theme.Tertiary
    CreateCorner(LoadingBar, 3)
    LoadingBar.Parent = MainFrame
    
    local LoadingFill = Instance.new("Frame")
    LoadingFill.Size = UDim2.new(0, 0, 1, 0)
    LoadingFill.BackgroundColor3 = Theme.Primary
    CreateCorner(LoadingFill, 3)
    LoadingFill.Parent = LoadingBar
    
    -- Loading Progress
    local loadingProgress = 0
    local loadingTime = 0
    local connection
    
    connection = RunService.Heartbeat:Connect(function(delta)
        loadingTime = loadingTime + delta
        loadingProgress = math.min((loadingTime / 3.0) * 100, 100) -- 3 second loading
        
        LoadingFill.Size = UDim2.new(loadingProgress/100, 0, 1, 0)
        
        if loadingProgress >= 100 then
            connection:Disconnect()
            wait(0.5)
            
            -- Fade out all elements
            local allElements = {MainFrame, Title, MadeBy, LoadingBar, LoadingFill, ParticleContainer}
            for _, element in pairs(allElements) do
                if element and element.Parent then
                    if element:IsA("TextLabel") then
                        Tween(element, TweenInfo.new(0.5), {
                            TextTransparency = 1
                        })
                    else
                        Tween(element, TweenInfo.new(0.5), {
                            BackgroundTransparency = 1
                        })
                    end
                end
            end
            
            -- Fade particles
            for _, particle in pairs(particles) do
                if particle.Parent then
                    Tween(particle, TweenInfo.new(0.5), {
                        BackgroundTransparency = 1
                    })
                end
            end
            
            -- Fade lines
            for _, line in pairs(lines) do
                if line.Parent then
                    Tween(line, TweenInfo.new(0.5), {
                        BackgroundTransparency = 1
                    })
                end
            end
            
            wait(0.6)
            ScreenGui:Destroy()
            
            -- Create main GUI with delay
            spawn(function()
                wait(0.1)
                CreateMainGUI()
                InitializeCheatFeatures()
            end)
        end
    end)
end

-- Main GUI Framework
local function CreateMainGUI()
    MainScreenGui = Instance.new("ScreenGui")
    MainScreenGui.Name = "RAYv2Main"
    MainScreenGui.Parent = CoreGui
    MainScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    MainScreenGui.Enabled = false
    
    -- Main Window
    local MainWindow = Instance.new("Frame")
    MainWindow.Size = UDim2.new(0, 900, 0, 650)
    MainWindow.Position = UDim2.new(0.5, -450, 0.5, -325)
    MainWindow.BackgroundColor3 = Theme.Secondary
    MainWindow.BorderSizePixel = 0
    CreateCorner(MainWindow, 10)
    MainWindow.Parent = MainScreenGui
    
    -- Window Shadow Effect
    local Shadow = Instance.new("Frame")
    Shadow.Size = UDim2.new(1, 20, 1, 20)
    Shadow.Position = UDim2.new(0, -10, 0, -10)
    Shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Shadow.BackgroundTransparency = 0.8
    Shadow.ZIndex = MainWindow.ZIndex - 1
    CreateCorner(Shadow, 10)
    Shadow.Parent = MainWindow
    
    -- Title Bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 50)
    TitleBar.Position = UDim2.new(0, 0, 0, 0)
    TitleBar.BackgroundColor3 = Theme.Tertiary
    TitleBar.BorderSizePixel = 0
    CreateCorner(TitleBar, 10)
    TitleBar.Parent = MainWindow
    
    -- Title Bar Gradient
    local TitleGradient = CreateGradient()
    TitleGradient.Parent = TitleBar
    
    -- Title Text
    local TitleText = Instance.new("TextLabel")
    TitleText.Size = UDim2.new(0, 200, 1, 0)
    TitleText.Position = UDim2.new(0, 15, 0, 0)
    TitleText.BackgroundTransparency = 1
    TitleText.Text = "RAYv2 v0.01 ALPHA"
    TitleText.Font = Enum.Font.GothamBold
    TitleText.TextSize = 20
    TitleText.TextColor3 = Theme.Accent
    TitleText.Parent = TitleBar
    
    -- Minimize Button
    local MinimizeButton = Instance.new("TextButton")
    MinimizeButton.Size = UDim2.new(0, 30, 0, 30)
    MinimizeButton.Position = UDim2.new(1, -70, 0, 10)
    MinimizeButton.BackgroundColor3 = Theme.Warning
    MinimizeButton.BorderSizePixel = 0
    MinimizeButton.Text = ""
    CreateCorner(MinimizeButton, 5)
    MinimizeButton.Parent = TitleBar
    
    -- Close Button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Position = UDim2.new(1, -35, 0, 10)
    CloseButton.BackgroundColor3 = Theme.Error
    CloseButton.BorderSizePixel = 0
    CloseButton.Text = ""
    CreateCorner(CloseButton, 5)
    CloseButton.Parent = TitleBar
    
    -- Tab Container
    local TabContainer = Instance.new("Frame")
    TabContainer.Size = UDim2.new(1, 0, 0, 60)
    TabContainer.Position = UDim2.new(0, 0, 0, 50)
    TabContainer.BackgroundColor3 = Theme.Tertiary
    TabContainer.BorderSizePixel = 0
    TabContainer.Parent = MainWindow
    
    -- Content Area
    local ContentArea = Instance.new("Frame")
    ContentArea.Size = UDim2.new(1, -20, 1, -130)
    ContentArea.Position = UDim2.new(0, 10, 0, 120)
    ContentArea.BackgroundTransparency = 1
    ContentArea.Parent = MainWindow
    
    -- Create Tabs
    local Tabs = {}
    local TabButtons = {}
    local TabContents = {}
    
    local tabNames = {"Aimbot", "ESP", "Configs", "Profile"}
    
    for i, tabName in ipairs(tabNames) do
        -- Tab Button
        local TabButton = Instance.new("TextButton")
        TabButton.Size = UDim2.new(0, 120, 0, 40)
        TabButton.Position = UDim2.new(0, 15 + (i-1) * 130, 0, 10)
        TabButton.BackgroundColor3 = Theme.Secondary
        TabButton.BorderSizePixel = 0
        TabButton.Text = tabName
        TabButton.Font = Enum.Font.GothamBold
        TabButton.TextSize = 16
        TabButton.TextColor3 = Color3.fromRGB(100, 100, 100)
        CreateCorner(TabButton, 5)
        TabButton.Parent = TabContainer
        
        -- Tab Content
        local TabContent = Instance.new("ScrollingFrame")
        TabContent.Size = UDim2.new(1, 0, 1, 0)
        TabContent.BackgroundTransparency = 1
        TabContent.BorderSizePixel = 0
        TabContent.Visible = (i == 1)
        TabContent.ScrollBarThickness = 8
        TabContent.ScrollBarImageColor3 = Theme.Primary
        TabContent.Parent = ContentArea
        
        Tabs[tabName] = TabButton
        TabContents[tabName] = TabContent
        
        -- Tab Click Handler
        TabButton.MouseEnter:Connect(function()
            if not TabContent.Visible then
                Tween(TabButton, TweenInfo.new(0.2), {
                    BackgroundColor3 = Theme.Tertiary
                })
            end
        end)
        
        TabButton.MouseLeave:Connect(function()
            if not TabContent.Visible then
                Tween(TabButton, TweenInfo.new(0.2), {
                    BackgroundColor3 = Theme.Secondary
                })
            end
        end)
        
        TabButton.MouseButton1Click:Connect(function()
            -- Hide all tabs
            for _, content in pairs(TabContents) do
                content.Visible = false
            end
            -- Reset all button colors
            for _, button in pairs(Tabs) do
                button.TextColor3 = Color3.fromRGB(100, 100, 100)
                Tween(button, TweenInfo.new(0.2), {
                    BackgroundColor3 = Theme.Secondary
                })
            end
            -- Show selected tab
            TabContents[tabName].Visible = true
            Tabs[tabName].TextColor3 = Theme.Accent
            Tween(Tabs[tabName], TweenInfo.new(0.2), {
                BackgroundColor3 = Theme.Primary
            })
        end)
    end
    
    -- Initialize Tab Contents
    CreateAimbotTab(TabContents["Aimbot"])
    CreateESPTab(TabContents["ESP"])
    CreateConfigsTab(TabContents["Configs"])
    CreateProfileTab(TabContents["Profile"])
    
    -- Make GUI Draggable
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainWindow.Position
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainWindow.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    -- Button Actions
    CloseButton.MouseButton1Click:Connect(function()
        MainScreenGui.Enabled = false
        GuiVisible = false
    end)
    
    MinimizeButton.MouseButton1Click:Connect(function()
        MainScreenGui.Enabled = not MainScreenGui.Enabled
        GuiVisible = MainScreenGui.Enabled
    end)
end

-- UI Helper Functions
local function CreateToggle(parent, text, position, defaultState, callback)
    local Toggle = Instance.new("TextButton")
    Toggle.Size = UDim2.new(0, 250, 0, 35)
    Toggle.Position = position
    Toggle.BackgroundColor3 = defaultState and Theme.Success or Theme.Error
    Toggle.BorderSizePixel = 0
    Toggle.Text = text .. ": " .. (defaultState and "ON" or "OFF")
    Toggle.Font = Enum.Font.Gotham
    Toggle.TextSize = 14
    Toggle.TextColor3 = Theme.Accent
    CreateCorner(Toggle, 5)
    Toggle.Parent = parent
    
    local state = defaultState
    
    Toggle.MouseButton1Click:Connect(function()
        state = not state
        Toggle.BackgroundColor3 = state and Theme.Success or Theme.Error
        Toggle.Text = text .. ": " .. (state and "ON" or "OFF")
        if callback then callback(state) end
    end)
    
    return Toggle, function() return state end
end

local function CreateLabel(parent, text, position, size)
    local Label = Instance.new("TextLabel")
    Label.Size = size or UDim2.new(0, 200, 0, 20)
    Label.Position = position
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 14
    Label.TextColor3 = Theme.Accent
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = parent
    
    return Label
end

local function CreateTextBox(parent, placeholder, position, size)
    local TextBox = Instance.new("TextBox")
    TextBox.Size = size
    TextBox.Position = position
    TextBox.BackgroundColor3 = Theme.Tertiary
    TextBox.BorderSizePixel = 0
    TextBox.Text = placeholder
    TextBox.Font = Enum.Font.Gotham
    TextBox.TextSize = 14
    TextBox.TextColor3 = Theme.Accent
    TextBox.PlaceholderText = placeholder
    TextBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    CreateCorner(TextBox, 5)
    TextBox.Parent = parent
    
    return TextBox
end

local function CreateButton(parent, text, position, size, color)
    local Button = Instance.new("TextButton")
    Button.Size = size
    Button.Position = position
    Button.BackgroundColor3 = color or Theme.Primary
    Button.BorderSizePixel = 0
    Button.Text = text
    Button.Font = Enum.Font.GothamBold
    Button.TextSize = 14
    Button.TextColor3 = Theme.Accent
    CreateCorner(Button, 5)
    Button.Parent = parent
    
    return Button
end

local function CreateSlider(parent, label, position, min, max, defaultValue, callback)
    local SliderFrame = Instance.new("Frame")
    SliderFrame.Size = UDim2.new(0, 350, 0, 50)
    SliderFrame.Position = position
    SliderFrame.BackgroundTransparency = 1
    SliderFrame.Parent = parent
    
    local Label = CreateLabel(SliderFrame, label .. ": " .. defaultValue, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 20))
    
    local Slider = Instance.new("TextButton")
    Slider.Size = UDim2.new(0, 250, 0, 8)
    Slider.Position = UDim2.new(0, 0, 0, 25)
    Slider.BackgroundColor3 = Theme.Tertiary
    Slider.BorderSizePixel = 0
    Slider.Text = ""
    CreateCorner(Slider, 4)
    Slider.Parent = SliderFrame
    
    local SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new((defaultValue - min) / (max - min), 0, 1, 0)
    SliderFill.BackgroundColor3 = Theme.Primary
    SliderFill.BorderSizePixel = 0
    CreateCorner(SliderFill, 4)
    SliderFill.Parent = Slider
    
    local SliderButton = Instance.new("TextButton")
    SliderButton.Size = UDim2.new(0, 20, 0, 20)
    SliderButton.Position = UDim2.new((defaultValue - min) / (max - min), -10, 0, -6)
    SliderButton.BackgroundColor3 = Theme.Accent
    SliderButton.BorderSizePixel = 0
    SliderButton.Text = ""
    CreateCorner(SliderButton, 10)
    SliderButton.Parent = Slider
    
    local dragging = false
    local currentValue = defaultValue
    
    SliderButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local relativePos = (input.Position.X - Slider.AbsolutePosition.X) / Slider.AbsoluteSize.X
            relativePos = math.clamp(relativePos, 0, 1)
            currentValue = min + (max - min) * relativePos
            
            SliderButton.Position = UDim2.new(relativePos, -10, 0, -6)
            SliderFill.Size = UDim2.new(relativePos, 0, 1, 0)
            Label.Text = label .. ": " .. math.floor(currentValue)
            
            if callback then callback(currentValue) end
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    return SliderFrame, function() return currentValue end
end

local function CreateColorPicker(parent, position, defaultColor, callback)
    local ColorPicker = Instance.new("TextButton")
    ColorPicker.Size = UDim2.new(0, 50, 0, 30)
    ColorPicker.Position = position
    ColorPicker.BackgroundColor3 = defaultColor
    ColorPicker.BorderSizePixel = 0
    ColorPicker.Text = ""
    CreateCorner(ColorPicker, 5)
    CreateStroke(ColorPicker, Theme.Accent, 1)
    ColorPicker.Parent = parent
    
    ColorPicker.MouseButton1Click:Connect(function()
        -- Simple color cycling for demo
        local colors = {Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 0, 255), Color3.fromRGB(0, 255, 255)}
        local currentIndex = 1
        for i, color in pairs(colors) do
            if (color - ColorPicker.BackgroundColor3).Magnitude < 0.1 then
                currentIndex = i % #colors + 1
                break
            end
        end
        ColorPicker.BackgroundColor3 = colors[currentIndex]
        if callback then callback(colors[currentIndex]) end
    end)
    
    return ColorPicker
end

-- Aimbot Tab Implementation
local function CreateAimbotTab(parent)
    parent.CanvasSize = UDim2.new(0, 0, 0, 900)
    
    -- Section Headers
    CreateLabel(parent, "MAIN AIMBOT", UDim2.new(0, 20, 0, 20), UDim2.new(0, 300, 0, 25))
    
    -- Aimbot Toggle
    local aimbotToggle, getAimbotState = CreateToggle(parent, "Aimbot", UDim2.new(0, 20, 0, 60), Settings.Aimbot.Enabled, function(state)
        Settings.Aimbot.Enabled = state
        if not state then
            AimbotTarget = nil
            AimbotActive = false
        end
    end)
    
    -- Keybind Input
    CreateLabel(parent, "Aimbot Key:", UDim2.new(0, 20, 0, 110), UDim2.new(0, 150, 0, 20))
    local keybindInput = CreateTextBox(parent, "Right Mouse", UDim2.new(0, 20, 0, 135), UDim2.new(0, 200, 0, 30))
    
    -- Mode Selection
    CreateLabel(parent, "Mode:", UDim2.new(0, 20, 0, 180), UDim2.new(0, 150, 0, 20))
    local toggleMode = CreateButton(parent, "Toggle", UDim2.new(0, 20, 0, 205), UDim2.new(0, 80, 0, 30), Theme.Success)
    local holdMode = CreateButton(parent, "Hold", UDim2.new(0, 110, 0, 205), UDim2.new(0, 80, 0, 30), Theme.Secondary)
    
    -- Silent Aim
    local silentAimToggle, getSilentAimState = CreateToggle(parent, "Silent Aim", UDim2.new(0, 20, 0, 250), Settings.Aimbot.SilentAim, function(state)
        Settings.Aimbot.SilentAim = state
    end)
    
    -- FOV Settings
    CreateLabel(parent, "FOV SETTINGS", UDim2.new(0, 20, 0, 300), UDim2.new(0, 300, 0, 25))
    
    local fovSlider, getFOVValue = CreateSlider(parent, "FOV", UDim2.new(0, 20, 0, 340), 30, 360, Settings.Aimbot.FOV, function(value)
        Settings.Aimbot.FOV = value
        UpdateFOVCircle()
    end)
    
    local fovCircleToggle, getFOVCircleState = CreateToggle(parent, "Show FOV Circle", UDim2.new(0, 20, 0, 400), Settings.Aimbot.ShowFOV, function(state)
        Settings.Aimbot.ShowFOV = state
        UpdateFOVCircle()
    end)
    
    local fovFillToggle, getFOVFillState = CreateToggle(parent, "Fill FOV Circle", UDim2.new(0, 20, 0, 445), Settings.Aimbot.FillFOV, function(state)
        Settings.Aimbot.FillFOV = state
        UpdateFOVCircle()
    end)
    
    -- Advanced Settings
    CreateLabel(parent, "ADVANCED", UDim2.new(0, 20, 0, 490), UDim2.new(0, 300, 0, 25))
    
    local smoothnessSlider, getSmoothnessValue = CreateSlider(parent, "Smoothness", UDim2.new(0, 20, 0, 530), 1, 20, Settings.Aimbot.Smoothness, function(value)
        Settings.Aimbot.Smoothness = value
    end)
    
    local reachSlider, getReachValue = CreateSlider(parent, "Reach Distance", UDim2.new(0, 20, 0, 590), 50, 500, Settings.Aimbot.Reach, function(value)
        Settings.Aimbot.Reach = value
    end)
    
    -- Triggerbot Section
    CreateLabel(parent, "TRIGGERBOT", UDim2.new(0, 20, 0, 640), UDim2.new(0, 300, 0, 25))
    
    local triggerbotToggle, getTriggerbotState = CreateToggle(parent, "Triggerbot", UDim2.new(0, 20, 0, 680), Settings.Triggerbot.Enabled, function(state)
        Settings.Triggerbot.Enabled = state
    end)
    
    local triggerDelaySlider, getTriggerDelayValue = CreateSlider(parent, "Trigger Delay (ms)", UDim2.new(0, 20, 0, 730), 0, 500, Settings.Triggerbot.Delay, function(value)
        Settings.Triggerbot.Delay = value
    end)
    
    -- Mode button handlers
    toggleMode.MouseButton1Click:Connect(function()
        Settings.Aimbot.Mode = "Toggle"
        toggleMode.BackgroundColor3 = Theme.Success
        holdMode.BackgroundColor3 = Theme.Secondary
    end)
    
    holdMode.MouseButton1Click:Connect(function()
        Settings.Aimbot.Mode = "Hold"
        holdMode.BackgroundColor3 = Theme.Success
        toggleMode.BackgroundColor3 = Theme.Secondary
    end)
    
    -- Keybind handler
    keybindInput.FocusLost:Connect(function()
        local keyText = keybindInput.Text:lower()
        if keyText == "right mouse" or keyText == "rmb" then
            Settings.Aimbot.Key = Enum.UserInputType.MouseButton2
        elseif keyText == "left mouse" or keyText == "lmb" then
            Settings.Aimbot.Key = Enum.UserInputType.MouseButton1
        elseif keyText == "shift" then
            Settings.Aimbot.Key = Enum.UserInputType.LeftShift
        end
    end)
end

-- ESP Tab Implementation
local function CreateESPTab(parent)
    parent.CanvasSize = UDim2.new(0, 0, 0, 800)
    
    -- Master ESP Toggle
    CreateLabel(parent, "ESP MASTER", UDim2.new(0, 20, 0, 20), UDim2.new(0, 300, 0, 25))
    
    local espToggle, getESPState = CreateToggle(parent, "ESP", UDim2.new(0, 20, 0, 60), Settings.ESP.Enabled, function(state)
        Settings.ESP.Enabled = state
        if not state then
            ClearESP()
        end
    end)
    
    -- ESP Options
    CreateLabel(parent, "ESP FEATURES", UDim2.new(0, 20, 0, 110), UDim2.new(0, 300, 0, 25))
    
    local boxESP, getBoxESPState = CreateToggle(parent, "Box ESP", UDim2.new(0, 20, 0, 150), Settings.ESP.Boxes, function(state)
        Settings.ESP.Boxes = state
    end)
    
    local skeletonESP, getSkeletonESPState = CreateToggle(parent, "Skeleton ESP", UDim2.new(0, 20, 0, 195), Settings.ESP.Skeleton, function(state)
        Settings.ESP.Skeleton = state
    end)
    
    local tracerESP, getTracerESPState = CreateToggle(parent, "Tracer ESP", UDim2.new(0, 20, 0, 240), Settings.ESP.Tracers, function(state)
        Settings.ESP.Tracers = state
    end)
    
    local fillBoxes, getFillBoxesState = CreateToggle(parent, "Fill Boxes", UDim2.new(0, 20, 0, 285), Settings.ESP.FillBoxes, function(state)
        Settings.ESP.FillBoxes = state
    end)
    
    local nameESP, getNameESPState = CreateToggle(parent, "Name ESP", UDim2.new(0, 20, 0, 330), Settings.ESP.Name, function(state)
        Settings.ESP.Name = state
    end)
    
    local healthESP, getHealthESPState = CreateToggle(parent, "Health ESP", UDim2.new(0, 20, 0, 375), Settings.ESP.Health, function(state)
        Settings.ESP.Health = state
    end)
    
    -- Color Settings
    CreateLabel(parent, "COLOR SETTINGS", UDim2.new(0, 20, 0, 420), UDim2.new(0, 300, 0, 25))
    
    CreateLabel(parent, "Box Color:", UDim2.new(0, 20, 0, 460), UDim2.new(0, 150, 0, 20))
    local boxColorPicker = CreateColorPicker(parent, UDim2.new(0, 20, 0, 485), Settings.ESP.Colors.Boxes, function(color)
        Settings.ESP.Colors.Boxes = color
    end)
    
    CreateLabel(parent, "Tracer Color:", UDim2.new(0, 100, 0, 460), UDim2.new(0, 150, 0, 20))
    local tracerColorPicker = CreateColorPicker(parent, UDim2.new(0, 100, 0, 485), Settings.ESP.Colors.Tracers, function(color)
        Settings.ESP.Colors.Tracers = color
    end)
    
    CreateLabel(parent, "Skeleton Color:", UDim2.new(0, 180, 0, 460), UDim2.new(0, 150, 0, 20))
    local skeletonColorPicker = CreateColorPicker(parent, UDim2.new(0, 180, 0, 485), Settings.ESP.Colors.Skeleton, function(color)
        Settings.ESP.Colors.Skeleton = color
    end)
    
    -- Distance Filter
    CreateLabel(parent, "DISTANCE FILTER", UDim2.new(0, 20, 0, 530), UDim2.new(0, 300, 0, 25))
    
    local distanceSlider, getDistanceValue = CreateSlider(parent, "Max Distance", UDim2.new(0, 20, 0, 570), 100, 1000, Settings.ESP.MaxDistance, function(value)
        Settings.ESP.MaxDistance = value
    end)
end

-- Configs Tab Implementation
local function CreateConfigsTab(parent)
    parent.CanvasSize = UDim2.new(0, 0, 0, 600)
    
    -- Config List Section
    CreateLabel(parent, "SAVED CONFIGS", UDim2.new(0, 20, 0, 20), UDim2.new(0, 300, 0, 25))
    
    local ConfigList = Instance.new("ScrollingFrame")
    ConfigList.Size = UDim2.new(0, 400, 0, 200)
    ConfigList.Position = UDim2.new(0, 20, 0, 50)
    ConfigList.BackgroundColor3 = Theme.Tertiary
    ConfigList.BorderSizePixel = 0
    ConfigList.ScrollBarThickness = 8
    ConfigList.ScrollBarImageColor3 = Theme.Primary
    CreateCorner(ConfigList, 5)
    ConfigList.Parent = parent
    
    -- Save Config Section
    CreateLabel(parent, "SAVE CONFIG", UDim2.new(0, 20, 0, 270), UDim2.new(0, 300, 0, 25))
    
    local configNameInput = CreateTextBox(parent, "Enter config name...", UDim2.new(0, 20, 0, 300), UDim2.new(0, 200, 0, 30))
    
    local saveButton = CreateButton(parent, "Save Config", UDim2.new(0, 230, 0, 300), UDim2.new(0, 100, 0, 30), Theme.Success)
    
    -- Load/Delete Buttons
    local loadButton = CreateButton(parent, "Load Selected", UDim2.new(0, 20, 0, 350), UDim2.new(0, 120, 0, 30), Theme.Primary)
    local deleteButton = CreateButton(parent, "Delete Selected", UDim2.new(0, 150, 0, 350), UDim2.new(0, 120, 0, 30), Theme.Error)
    
    -- Update config list
    local function UpdateConfigList()
        for _, child in pairs(ConfigList:GetChildren()) do
            child:Destroy()
        end
        
        local yOffset = 10
        for configName, configData in pairs(RAYv2.Configs) do
            local configEntry = Instance.new("TextButton")
            configEntry.Size = UDim2.new(1, -20, 0, 30)
            configEntry.Position = UDim2.new(0, 10, 0, yOffset)
            configEntry.BackgroundColor3 = Theme.Secondary
            configEntry.BorderSizePixel = 0
            configEntry.Text = configName .. " (" .. (configData.Timestamp or "Unknown") .. ")"
            configEntry.Font = Enum.Font.Gotham
            configEntry.TextSize = 14
            configEntry.TextColor3 = Theme.Accent
            configEntry.TextXAlignment = Enum.TextXAlignment.Left
            CreateCorner(configEntry, 5)
            configEntry.Parent = ConfigList
            
            configEntry.MouseButton1Click:Connect(function()
                -- Highlight selected
                for _, child in pairs(ConfigList:GetChildren()) do
                    child.BackgroundColor3 = Theme.Secondary
                end
                configEntry.BackgroundColor3 = Theme.Primary
            end)
            
            yOffset = yOffset + 35
        end
        
        ConfigList.CanvasSize = UDim2.new(0, 0, 0, yOffset)
    end
    
    -- Save config function
    saveButton.MouseButton1Click:Connect(function()
        local configName = configNameInput.Text
        if configName and configName ~= "" then
            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
            RAYv2.Configs[configName] = {
                Settings = Settings,
                Timestamp = timestamp
            }
            
            -- Save to persistent storage
            local success, error = pcall(function()
                getgenv().RAYv2_Configs = HttpService:JSONEncode(RAYv2.Configs)
            end)
            
            UpdateConfigList()
            configNameInput.Text = ""
        end
    end)
    
    -- Load config function
    loadButton.MouseButton1Click:Connect(function()
        for _, child in pairs(ConfigList:GetChildren()) do
            if child.BackgroundColor3 == Theme.Primary then
                local configName = child.Text:match("^(.+) %(")
                if configName and RAYv2.Configs[configName] then
                    Settings = RAYv2.Configs[configName].Settings
                    break
                end
            end
        end
    end)
    
    -- Delete config function
    deleteButton.MouseButton1Click:Connect(function()
        for _, child in pairs(ConfigList:GetChildren()) do
            if child.BackgroundColor3 == Theme.Primary then
                local configName = child.Text:match("^(.+) %(")
                if configName and RAYv2.Configs[configName] then
                    RAYv2.Configs[configName] = nil
                    UpdateConfigList()
                    break
                end
            end
        end
    end)
    
    -- Initial load
    UpdateConfigList()
end

-- Profile Tab Implementation
local function CreateProfileTab(parent)
    parent.CanvasSize = UDim2.new(0, 0, 0, 800)
    
    -- Avatar Display
    local AvatarFrame = Instance.new("Frame")
    AvatarFrame.Size = UDim2.new(0, 120, 0, 120)
    AvatarFrame.Position = UDim2.new(0.5, -60, 0, 20)
    AvatarFrame.BackgroundColor3 = Theme.Tertiary
    AvatarFrame.BorderSizePixel = 0
    CreateCorner(AvatarFrame, 60)
    CreateStroke(AvatarFrame, Theme.Primary, 2)
    AvatarFrame.Parent = parent
    
    local AvatarImage = Instance.new("ImageLabel")
    AvatarImage.Size = UDim2.new(1, -4, 1, -4)
    AvatarImage.Position = UDim2.new(0, 2, 0, 2)
    AvatarImage.BackgroundTransparency = 1
    CreateCorner(AvatarImage, 58)
    AvatarImage.Parent = AvatarFrame
    
    -- Load avatar image
    local success, avatarUrl = pcall(function()
        return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
    end)
    if success then
        AvatarImage.Image = avatarUrl
    end
    
    -- Username Display
    local DisplayName = Instance.new("TextLabel")
    DisplayName.Size = UDim2.new(1, 0, 0, 30)
    DisplayName.Position = UDim2.new(0, 0, 0, 150)
    DisplayName.BackgroundTransparency = 1
    DisplayName.Text = LocalPlayer.DisplayName
    DisplayName.Font = Enum.Font.GothamBold
    DisplayName.TextSize = 24
    DisplayName.TextColor3 = Theme.Accent
    DisplayName.Parent = parent
    
    local Username = Instance.new("TextLabel")
    Username.Size = UDim2.new(1, 0, 0, 20)
    Username.Position = UDim2.new(0, 0, 0, 180)
    Username.BackgroundTransparency = 1
    Username.Text = "@" .. LocalPlayer.Name
    Username.Font = Enum.Font.Gotham
    Username.TextSize = 16
    Username.TextColor3 = Color3.fromRGB(120, 120, 120)
    Username.Parent = parent
    
    -- Owner Crown Effect (for specific user)
    if LocalPlayer.UserId == OWNER_ID then
        local CrownFrame = Instance.new("Frame")
        CrownFrame.Size = UDim2.new(0, 200, 0, 40)
        CrownFrame.Position = UDim2.new(0.5, -100, 0, 210)
        CrownFrame.BackgroundTransparency = 1
        CrownFrame.Parent = parent
        
        local CrownLabel = Instance.new("TextLabel")
        CrownLabel.Size = UDim2.new(1, 0, 1, 0)
        CrownLabel.BackgroundTransparency = 1
        CrownLabel.Text = "Owner"
        CrownLabel.Font = Enum.Font.GothamBold
        CrownLabel.TextSize = 22
        CrownLabel.TextColor3 = Theme.Gold
        CrownLabel.Parent = CrownFrame
        
        -- Gold Gradient Effect
        local GoldGradient = CreateGradient()
        GoldGradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 0))
        }
        GoldGradient.Parent = CrownLabel
        
        -- Golden Particle Sparkles
        local sparkles = {}
        for i = 1, 8 do
            local sparkle = Instance.new("Frame")
            sparkle.Size = UDim2.new(0, 3, 0, 3)
            sparkle.BackgroundColor3 = Color3.fromRGB(255, 255, 200)
            sparkle.BackgroundTransparency = 0.3
            CreateCorner(sparkle, 50)
            sparkle.Parent = CrownFrame
            
            table.insert(sparkles, sparkle)
        end
        
        -- Animate sparkles
        spawn(function()
            while CrownFrame.Parent do
                for _, sparkle in pairs(sparkles) do
                    local randomX = math.random()
                    local randomY = math.random()
                    local randomSize = math.random(2, 5)
                    
                    Tween(sparkle, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        Position = UDim2.new(randomX, 0, randomY, 0),
                        Size = UDim2.new(0, randomSize, 0, randomSize),
                        BackgroundTransparency = math.random(0.2, 0.8)
                    })
                end
                wait(2)
            end
        end)
        
        -- Rotate gold gradient
        spawn(function()
            local rotation = 0
            while CrownFrame.Parent do
                rotation = (rotation + 2) % 360
                GoldGradient.Rotation = rotation
                wait(0.016)
            end
        end)
    end
    
    -- Spoofer Options
    CreateLabel(parent, "ACCOUNT SPOOFER", UDim2.new(0, 20, 0, 270), UDim2.new(0, 300, 0, 25))
    
    local levelSpoof, getLevelSpoofState = CreateToggle(parent, "Level Spoofer", UDim2.new(0, 20, 0, 310), Settings.Spoofer.Level, function(state)
        Settings.Spoofer.Level = state
    end)
    
    local winStreakSpoof, getWinStreakSpoofState = CreateToggle(parent, "Win Streak Spoofer", UDim2.new(0, 20, 0, 355), Settings.Spoofer.WinStreak, function(state)
        Settings.Spoofer.WinStreak = state
    end)
    
    local keysSpoof, getKeysSpoofState = CreateToggle(parent, "Keys Spoofer", UDim2.new(0, 20, 0, 400), Settings.Spoofer.Keys, function(state)
        Settings.Spoofer.Keys = state
    end)
    
    local premiumBadge, getPremiumBadgeState = CreateToggle(parent, "Premium Badge", UDim2.new(0, 20, 0, 445), Settings.Spoofer.PremiumBadge, function(state)
        Settings.Spoofer.PremiumBadge = state
    end)
    
    local verifiedBadge, getVerifiedBadgeState = CreateToggle(parent, "Verified Badge", UDim2.new(0, 20, 0, 490), Settings.Spoofer.VerifiedBadge, function(state)
        Settings.Spoofer.VerifiedBadge = state
    end)
    
    -- Admin Panel Button (Owner Only)
    if LocalPlayer.UserId == OWNER_ID then
        local adminButton = CreateButton(parent, "Admin Panel", UDim2.new(0, 20, 0, 550), UDim2.new(0, 150, 0, 40), Theme.Gold)
        
        adminButton.MouseButton1Click:Connect(function()
            CreateAdminPanel()
        end)
    end
    
    -- Version Info
    local versionLabel = CreateLabel(parent, "RAYv2 v0.01 ALPHA", UDim2.new(0, 20, 0, 610), UDim2.new(0, 300, 0, 20))
    versionLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
end

-- Admin Panel Implementation
local function CreateAdminPanel()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RAYv2AdminPanel"
    ScreenGui.Parent = CoreGui
    
    -- Login Window
    local LoginWindow = Instance.new("Frame")
    LoginWindow.Size = UDim2.new(0, 400, 0, 350)
    LoginWindow.Position = UDim2.new(0.5, -200, 0.5, -175)
    LoginWindow.BackgroundColor3 = Theme.Secondary
    LoginWindow.BorderSizePixel = 0
    CreateCorner(LoginWindow, 10)
    CreateStroke(LoginWindow, Theme.Gold, 2)
    LoginWindow.Parent = ScreenGui
    
    -- Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 50)
    Title.BackgroundColor3 = Theme.Gold
    Title.BorderSizePixel = 0
    Title.Text = "Admin Login"
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 20
    Title.TextColor3 = Color3.fromRGB(0, 0, 0)
    CreateCorner(Title, 10)
    Title.Parent = LoginWindow
    
    -- Username Input
    CreateLabel(LoginWindow, "Username:", UDim2.new(0, 20, 0, 70), UDim2.new(0, 150, 0, 20))
    local UserInput = CreateTextBox(LoginWindow, "", UDim2.new(0, 20, 0, 95), UDim2.new(0, 360, 0, 30))
    
    -- Password Input
    CreateLabel(LoginWindow, "Password:", UDim2.new(0, 20, 0, 140), UDim2.new(0, 150, 0, 20))
    local PassInput = CreateTextBox(LoginWindow, "", UDim2.new(0, 20, 0, 165), UDim2.new(0, 360, 0, 30))
    
    -- Login Button
    local LoginButton = CreateButton(LoginWindow, "Login", UDim2.new(0.5, -50, 0, 220), UDim2.new(0, 100, 0, 40), Theme.Gold)
    
    -- Login Handler
    LoginButton.MouseButton1Click:Connect(function()
        if UserInput.Text == ADMIN_CREDENTIALS.username and PassInput.Text == ADMIN_CREDENTIALS.password then
            ScreenGui:Destroy()
            CreateAdminDashboard()
        else
            PassInput.Text = "Invalid Credentials"
            wait(1)
            PassInput.Text = ""
        end
    end)
end

-- Admin Dashboard Implementation
local function CreateAdminDashboard()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RAYv2AdminDashboard"
    ScreenGui.Parent = CoreGui
    
    -- Main Window
    local MainWindow = Instance.new("Frame")
    MainWindow.Size = UDim2.new(0, 700, 0, 600)
    MainWindow.Position = UDim2.new(0.5, -350, 0.5, -300)
    MainWindow.BackgroundColor3 = Theme.Secondary
    MainWindow.BorderSizePixel = 0
    CreateCorner(MainWindow, 10)
    CreateStroke(MainWindow, Theme.Gold, 2)
    MainWindow.Parent = ScreenGui
    
    -- Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 50)
    Title.BackgroundColor3 = Theme.Gold
    Title.BorderSizePixel = 0
    Title.Text = "Admin Dashboard"
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 20
    Title.TextColor3 = Color3.fromRGB(0, 0, 0)
    CreateCorner(Title, 10)
    Title.Parent = MainWindow
    
    -- Restrict Access Section
    CreateLabel(MainWindow, "RESTRICT ACCESS", UDim2.new(0, 20, 0, 70), UDim2.new(0, 300, 0, 25))
    
    CreateLabel(MainWindow, "User ID to Restrict:", UDim2.new(0, 20, 0, 110), UDim2.new(0, 200, 0, 20))
    local RestrictInput = CreateTextBox(MainWindow, "Enter UserID...", UDim2.new(0, 20, 0, 135), UDim2.new(0, 200, 0, 30))
    local RestrictButton = CreateButton(MainWindow, "Restrict Access", UDim2.new(0, 230, 0, 135), UDim2.new(0, 120, 0, 30), Theme.Error)
    
    -- Role Management Section
    CreateLabel(MainWindow, "ROLE MANAGEMENT", UDim2.new(0, 20, 0, 190), UDim2.new(0, 300, 0, 25))
    
    local roles = {
        {name = "Media", color = Color3.fromRGB(255, 0, 255)},
        {name = "Admin", color = Color3.fromRGB(255, 0, 0)},
        {name = "Support", color = Color3.fromRGB(0, 255, 0)},
        {name = "Moderator", color = Color3.fromRGB(0, 100, 255)}
    }
    
    for i, role in ipairs(roles) do
        CreateLabel(MainWindow, "Assign " .. role.name .. ":", UDim2.new(0, 20, 0, 230 + (i-1) * 50), UDim2.new(0, 150, 0, 20))
        local RoleInput = CreateTextBox(MainWindow, "Enter UserID...", UDim2.new(0, 20, 0, 255 + (i-1) * 50), UDim2.new(0, 200, 0, 30))
        local RoleButton = CreateButton(MainWindow, "Assign Role", UDim2.new(0, 230, 0, 255 + (i-1) * 50), UDim2.new(0, 100, 0, 30), role.color)
        
        RoleButton.MouseButton1Click:Connect(function()
            local userId = tonumber(RoleInput.Text)
            if userId then
                print("Assigned " .. role.name .. " role to UserID: " .. userId)
                RoleInput.Text = ""
            end
        end)
    end
    
    -- Close Button
    local CloseButton = CreateButton(MainWindow, "Close Dashboard", UDim2.new(0.5, -75, 0, 520), UDim2.new(0, 150, 0, 40), Theme.Error)
    
    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
    end)
end

-- FOV Circle Management
local function CreateFOVCircle()
    if FOVCircle then
        FOVCircle:Remove()
    end
    
    if not Settings.Aimbot.ShowFOV then
        return
    end
    
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = true
    FOVCircle.Radius = (Settings.Aimbot.FOV / 360) * Camera.ViewportSize.X
    FOVCircle.Color = Settings.ESP.Colors.Tracers
    FOVCircle.Thickness = 2
    FOVCircle.Filled = Settings.Aimbot.FillFOV
    FOVCircle.Transparency = Settings.Aimbot.FillFOV and 0.3 or 0.8
end

local function UpdateFOVCircle()
    if FOVCircle then
        FOVCircle.Visible = Settings.Aimbot.ShowFOV
        FOVCircle.Radius = (Settings.Aimbot.FOV / 360) * Camera.ViewportSize.X
        FOVCircle.Color = Settings.ESP.Colors.Tracers
        FOVCircle.Thickness = 2
        FOVCircle.Filled = Settings.Aimbot.FillFOV
        FOVCircle.Transparency = Settings.Aimbot.FillFOV and 0.3 or 0.8
    else
        CreateFOVCircle()
    end
end

-- ESP Functions
local function ClearESP()
    for _, obj in pairs(ESPObjects) do
        if obj and obj.Remove then
            obj:Remove()
        end
    end
    ESPObjects = {}
end

local function DrawESP()
    if not Settings.ESP.Enabled then
        ClearESP()
        return
    end
    
    ClearESP()
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (player.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            if distance <= Settings.ESP.MaxDistance then
                local screenPos = WorldToScreenPoint(player.Character.HumanoidRootPart.Position)
                if screenPos then
                    -- Box ESP
                    if Settings.ESP.Boxes then
                        local box = Drawing.new("Square")
                        box.Visible = true
                        box.Size = Vector2.new(40, 60)
                        box.Position = screenPos - Vector2.new(20, 30)
                        box.Color = Settings.ESP.Colors.Boxes
                        box.Thickness = 2
                        box.Filled = Settings.ESP.FillBoxes
                        box.Transparency = Settings.ESP.FillBoxes and 0.3 or 1
                        table.insert(ESPObjects, box)
                    end
                    
                    -- Name ESP
                    if Settings.ESP.Name then
                        local name = Drawing.new("Text")
                        name.Visible = true
                        name.Text = player.Name
                        name.Position = screenPos - Vector2.new(20, 40)
                        name.Color = Settings.ESP.Colors.Name
                        name.Size = 14
                        name.Font = 2
                        table.insert(ESPObjects, name)
                    end
                    
                    -- Health ESP
                    if Settings.ESP.Health and player.Character:FindFirstChild("Humanoid") then
                        local health = player.Character.Humanoid.Health
                        local maxHealth = player.Character.Humanoid.MaxHealth
                        local healthPercent = health / maxHealth
                        
                        local healthBar = Drawing.new("Square")
                        healthBar.Visible = true
                        healthBar.Size = Vector2.new(40, 4)
                        healthBar.Position = screenPos - Vector2.new(20, 35)
                        healthBar.Color = Color3.fromRGB(255, 0, 0)
                        healthBar.Filled = true
                        healthBar.Transparency = 0.8
                        table.insert(ESPObjects, healthBar)
                        
                        local healthFill = Drawing.new("Square")
                        healthFill.Visible = true
                        healthFill.Size = Vector2.new(40 * healthPercent, 4)
                        healthFill.Position = screenPos - Vector2.new(20, 35)
                        healthFill.Color = Settings.ESP.Colors.Health
                        healthFill.Filled = true
                        table.insert(ESPObjects, healthFill)
                    end
                    
                    -- Tracer ESP
                    if Settings.ESP.Tracers then
                        local tracer = Drawing.new("Line")
                        tracer.Visible = true
                        tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        tracer.To = screenPos
                        tracer.Color = Settings.ESP.Colors.Tracers
                        tracer.Thickness = 2
                        table.insert(ESPObjects, tracer)
                    end
                end
            end
        end
    end
end

-- Cheat Feature Initialization
local function InitializeCheatFeatures()
    -- Create FOV Circle
    CreateFOVCircle()
    
    -- Aimbot Logic
    RunService.Heartbeat:Connect(function()
        if Settings.Aimbot.Enabled and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            AimbotTarget = GetAimbotTarget()
            
            if AimbotTarget then
                if Settings.Aimbot.SilentAim then
                    -- Silent aim - modify camera CFrame without visible movement
                    local targetPos = AimbotTarget.Position
                    local currentPos = Camera.CFrame.Position
                    local lookAt = CFrame.new(currentPos, targetPos)
                    
                    -- Apply prediction
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                        local velocity = AimbotTarget.Velocity
                        targetPos = targetPos + velocity * Settings.Aimbot.Prediction
                        lookAt = CFrame.new(currentPos, targetPos)
                    end
                    
                    -- Apply smoothness
                    local smoothedCFrame = Camera.CFrame:lerp(lookAt, 1 / Settings.Aimbot.Smoothness)
                    Camera.CFrame = smoothedCFrame
                else
                    -- Regular aimbot - visible camera movement
                    local targetPos = AimbotTarget.Position
                    local currentPos = Camera.CFrame.Position
                    local lookAt = CFrame.new(currentPos, targetPos)
                    
                    -- Apply prediction
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                        local velocity = AimbotTarget.Velocity
                        targetPos = targetPos + velocity * Settings.Aimbot.Prediction
                        lookAt = CFrame.new(currentPos, targetPos)
                    end
                    
                    -- Apply smoothness
                    local smoothedCFrame = Camera.CFrame:lerp(lookAt, 1 / Settings.Aimbot.Smoothness)
                    Camera.CFrame = smoothedCFrame
                end
            end
        end
    end)
    
    -- Triggerbot Logic
    local lastTriggerTime = 0
    RunService.Heartbeat:Connect(function()
        if Settings.Triggerbot.Enabled and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local target = GetClosestPlayer()
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                local screenPos = WorldToScreenPoint(target.Character.HumanoidRootPart.Position)
                if screenPos then
                    local distance = (screenPos - Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)).Magnitude
                    if distance < 50 then -- Within crosshair range
                        local currentTime = tick()
                        if currentTime - lastTriggerTime >= (Settings.Triggerbot.Delay / 1000) then
                            -- Trigger shot
                            mouse1press()
                            wait(0.05)
                            mouse1release()
                            lastTriggerTime = currentTime
                        end
                    end
                end
            end
        end
    end)
    
    -- ESP Render Loop
    RunService.Heartbeat:Connect(function()
        DrawESP()
        UpdateFOVCircle()
    end)
    
    -- GUI Toggle with INSERT key
    UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Insert then
            GuiVisible = not GuiVisible
            if MainScreenGui then
                MainScreenGui.Enabled = GuiVisible
            end
        end
    end)
    
    -- Aimbot Keybind Handler
    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Settings.Aimbot.Key then
            if Settings.Aimbot.Mode == "Toggle" then
                AimbotActive = not AimbotActive
            elseif Settings.Aimbot.Mode == "Hold" then
                AimbotActive = true
            end
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Settings.Aimbot.Key and Settings.Aimbot.Mode == "Hold" then
            AimbotActive = false
        end
    end)
end

-- Initialize Cheat
CreateLoadingScreen()

-- Return for external access
return RAYv2
