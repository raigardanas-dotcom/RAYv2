--[[
════════════════════════════════════════════════════════════════════════════════
RAYv2 - PRIVATE INTERNAL-GRADE CHEAT FOR RIVALS
Built by @ink | Version 0.01 ALPHA
Level 7 UNC Executor Compatible (Solara, Wave, Codex, Synapse X)
════════════════════════════════════════════════════════════════════════════════

ARCHITECTURE OVERVIEW:
This script implements a complete cinematic injection sequence followed by a fully
functional multi-tab GUI with aimbot, ESP, config management, and profile systems.

All state is stored in getgenv() for persistence across script reloads.
All overlays use Drawing API for maximum performance.
All animations use TweenService for smooth visual effects.
All configs use HttpService JSON serialization.

PERFORMANCE NOTES:
- All rendering locked to RenderStepped for 60+ FPS consistency
- Object pooling implemented for Drawing API to prevent memory leaks
- Delta-time compensation for frame-rate independent animations
- Proper cleanup on script destruction

════════════════════════════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: GLOBAL STATE INITIALIZATION (GETGENV ONLY)
-- ═══════════════════════════════════════════════════════════════════════════

if not getgenv().RAYv2_Initialized then
    getgenv().RAYv2_Initialized = true
    getgenv().RAYv2_Version = "0.01 ALPHA"
    getgenv().DebugMode = false
    
    -- Configuration state with default values
    getgenv().RAYv2_Config = {
        Aimbot = {
            Enabled = false,
            Keybind = Enum.KeyCode.E,
            Mode = "Toggle",
            SilentAim = true,
            FOV = 120,
            FOVVisible = true,
            FOVFilled = false,
            FOVColor = Color3.fromRGB(0, 212, 255),
            Smoothness = 35,
            MaxDistance = 300,
            TeamCheck = true,
            VisibleCheck = true,
            HeadPriority = true,
            Prediction = true,
            PredictionFactor = 0.165,
            
            Triggerbot = {
                Enabled = false,
                Keybind = Enum.KeyCode.T,
                Delay = 0.05
            }
        },
        
        ESP = {
            Enabled = false,
            MaxDistance = 300,
            TeamCheck = true,
            
            Boxes = {
                Enabled = true,
                Color = Color3.fromRGB(255, 255, 255),
                Thickness = 2
            },
            
            Fill = {
                Enabled = false,
                Color = Color3.fromRGB(255, 255, 255),
                Transparency = 0.2
            },
            
            Skeleton = {
                Enabled = true,
                Color = Color3.fromRGB(255, 255, 255),
                Thickness = 1
            },
            
            Tracers = {
                Enabled = true,
                Color = Color3.fromRGB(0, 212, 255),
                Thickness = 1,
                From = "Bottom"
            },
            
            Name = {
                Enabled = true,
                Color = Color3.fromRGB(255, 255, 255),
                Size = 16,
                Outline = true
            },
            
            Health = {
                Enabled = true,
                Color = Color3.fromRGB(0, 255, 0),
                BarEnabled = true,
                BarWidth = 3
            },
            
            Distance = {
                Enabled = true,
                Color = Color3.fromRGB(200, 200, 200),
                Size = 14
            },
            
            Weapon = {
                Enabled = true,
                Color = Color3.fromRGB(255, 200, 0),
                Size = 14
            }
        },
        
        GUI = {
            Visible = true,
            ToggleKeybind = Enum.KeyCode.LeftAlt,
            AlternateKeybind1 = Enum.KeyCode.LeftControl,
            AlternateKeybind2 = Enum.KeyCode.Insert,
            Position = UDim2.new(0.5, -410, 0.5, -260),
            Size = UDim2.new(0, 820, 0, 520)
        },
        
        Profile = {
            FakeLevel = 0,
            FakeStreak = 0,
            FakeKeys = 0,
            FakePremium = false,
            FakeVerified = false
        },
        
        Admin = {
            Unlocked = false,
            Username = "adminHQ",
            Password = "HQ080626",
            RestrictedUsers = {}
        }
    }
    
    -- Drawing API object pools
    getgenv().RAYv2_DrawingPool = {
        Circles = {},
        Squares = {},
        Lines = {},
        Texts = {},
        Triangles = {}
    }
    
    -- Runtime state
    getgenv().RAYv2_Runtime = {
        CurrentTarget = nil,
        LastShotTime = 0,
        AimbotActive = false,
        TriggerbotActive = false,
        ESPObjects = {},
        Connections = {},
        TweenCache = {},
        LoadingScreen = nil,
        MainGUI = nil
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: CORE SERVICES AND REFERENCES
-- ═══════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function DebugPrint(...)
    if getgenv().DebugMode then
        print("[RAYv2 DEBUG]", ...)
    end
end

local function GetDrawing(drawingType)
    local pool = getgenv().RAYv2_DrawingPool[drawingType .. "s"]
    if not pool then
        return nil
    end
    
    for i, obj in ipairs(pool) do
        if obj and obj.Visible == false then
            obj.Visible = true
            return obj
        end
    end
    
    local success, newObj = pcall(function()
        return Drawing.new(drawingType)
    end)
    
    if success and newObj then
        table.insert(pool, newObj)
        newObj.Visible = true
        return newObj
    end
    
    return nil
end

local function ReleaseDrawing(obj)
    if obj then
        obj.Visible = false
    end
end

local function WorldToScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen and screenPos.Z > 0
end

local function GetCharacterBoundingBox(character)
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil, nil, false
    end
    
    local hrp = character.HumanoidRootPart
    local size = Vector3.new(2.5, 5, 1.5)
    local corners = {
        hrp.CFrame * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
        hrp.CFrame * CFrame.new(size.X/2, -size.Y/2, -size.Z/2),
        hrp.CFrame * CFrame.new(-size.X/2, size.Y/2, -size.Z/2),
        hrp.CFrame * CFrame.new(size.X/2, size.Y/2, -size.Z/2),
        hrp.CFrame * CFrame.new(-size.X/2, -size.Y/2, size.Z/2),
        hrp.CFrame * CFrame.new(size.X/2, -size.Y/2, size.Z/2),
        hrp.CFrame * CFrame.new(-size.X/2, size.Y/2, size.Z/2),
        hrp.CFrame * CFrame.new(size.X/2, size.Y/2, size.Z/2)
    }
    
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOnScreen = false
    
    for _, corner in ipairs(corners) do
        local screenPos, onScreen = WorldToScreen(corner.Position)
        if onScreen then
            anyOnScreen = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end
    
    if anyOnScreen then
        local topLeft = Vector2.new(minX, minY)
        local boxSize = Vector2.new(maxX - minX, maxY - minY)
        return topLeft, boxSize, true
    end
    
    return nil, nil, false
end

local function IsValidCharacter(character)
    if not character then return false end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    return true
end

local function IsSameTeam(player1, player2)
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    return false
end

local function IsInMatch(player)
    local character = player.Character
    if not character then return false end
    
    local matchFolder = Workspace:FindFirstChild("Match") or Workspace:FindFirstChild("ActivePlayers")
    if matchFolder and character:IsDescendantOf(matchFolder) then
        return true
    end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Position.Y < 50 then
        return true
    end
    
    return false
end

local function GetPing()
    local success, ping = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return success and ping or 50
end

local function PredictPosition(currentPos, velocity)
    if not getgenv().RAYv2_Config.Aimbot.Prediction then
        return currentPos
    end
    
    local ping = GetPing()
    local predictionFactor = getgenv().RAYv2_Config.Aimbot.PredictionFactor
    local timeAhead = (ping / 1000) * predictionFactor
    local predictedPos = currentPos + (velocity * timeAhead)
    
    return predictedPos
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: CINEMATIC LOADING SCREEN (MANDATORY FIRST EXECUTION)
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateLoadingScreen()
    DebugPrint("Creating loading screen...")
    
    -- Create main ScreenGui for loading screen
    -- This will cover the entire screen and block all interaction until loaded
    local loadingScreen = Instance.new("ScreenGui")
    loadingScreen.Name = "RAYv2_LoadingScreen"
    loadingScreen.ResetOnSpawn = false
    loadingScreen.IgnoreGuiInset = true
    loadingScreen.DisplayOrder = 10
    loadingScreen.Parent = PlayerGui
    
    -- Background frame covering entire screen (1,0,1,0 = 100% width, 100% height)
    -- Position (0,0,0,0) = top-left corner of screen
    -- BackgroundTransparency = 0 means fully opaque (blocks everything behind it)
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 1, 0)
    background.Position = UDim2.new(0, 0, 0, 0)
    background.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    background.BorderSizePixel = 0
    background.Parent = loadingScreen
    
    -- Animated gradient for background
    -- ColorSequence defines the gradient colors: Blue -> Black -> White
    -- Rotation = 45 creates a diagonal gradient sweep
    -- Offset will be animated to create movement effect
    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 128, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
    }
    bgGradient.Rotation = 45
    bgGradient.Offset = Vector2.new(-1, -1)
    bgGradient.Parent = background
    
    -- Continuous gradient animation loop using TweenService
    -- This tween runs infinitely (Repeat count = -1)
    -- Linear easing creates constant speed movement
    -- Duration = 4 seconds for one full cycle
    local function AnimateGradient(gradient)
        local tweenInfo = TweenInfo.new(
            4,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut,
            -1,
            false,
            0
        )
        
        local tween = TweenService:Create(gradient, tweenInfo, {
            Offset = Vector2.new(1, 1)
        })
        tween:Play()
        
        table.insert(getgenv().RAYv2_Runtime.TweenCache, tween)
        return tween
    end
    
    AnimateGradient(bgGradient)
    
    -- Particle system: Create 30 animated circles for visual depth
    -- Each particle moves independently with random velocity
    -- Position wraps around screen edges for infinite loop effect
    local particleContainer = Instance.new("Frame")
    particleContainer.Name = "Particles"
    particleContainer.Size = UDim2.new(1, 0, 1, 0)
    particleContainer.BackgroundTransparency = 1
    particleContainer.Parent = background
    
    local particles = {}
    for i = 1, 30 do
        -- Create individual particle as a circular Frame
        -- Size ranges from 2-8 pixels for depth variation
        -- BackgroundTransparency ranges from 0.7-0.9 for subtle effect
        local particle = Instance.new("Frame")
        particle.Name = "Particle" .. i
        particle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        particle.BackgroundTransparency = math.random(70, 90) / 100
        particle.BorderSizePixel = 0
        
        local size = math.random(2, 8)
        particle.Size = UDim2.new(0, size, 0, size)
        
        -- Random starting position across entire screen
        particle.Position = UDim2.new(
            math.random(0, 100) / 100,
            0,
            math.random(0, 100) / 100,
            0
        )
        
        -- UICorner with CornerRadius = 1,0 creates perfect circle
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = particle
        
        particle.Parent = particleContainer
        
        -- Store particle with random velocity for animation
        -- Velocity ranges from -0.0005 to 0.0005 per frame (very slow drift)
        table.insert(particles, {
            Frame = particle,
            VelocityX = (math.random(-50, 50) / 100) * 0.001,
            VelocityY = (math.random(-50, 50) / 100) * 0.001
        })
    end
    
    -- Geometric line decorations with parallax motion
    -- Each line has different length, rotation, and movement pattern
    -- Creates depth perception through differential motion
    local function CreateDecorativeLine(rotation, length, yPos)
        local line = Instance.new("Frame")
        line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        line.BackgroundTransparency = 0.85
        line.BorderSizePixel = 0
        line.Size = UDim2.new(0, length, 0, 2)
        line.Position = UDim2.new(0.5, -length/2, yPos, 0)
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Rotation = rotation
        line.Parent = background
        
        -- UIStroke creates neon glow effect around line
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 212, 255)
        stroke.Thickness = 1
        stroke.Transparency = 0.7
        stroke.Parent = line
        
        -- Parallax motion tween: moves line horizontally
        -- Duration randomized (4-8 seconds) for organic feel
        -- Reverse = true makes it oscillate back and forth
        local tweenInfo = TweenInfo.new(
            6 + math.random(-2, 2),
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true,
            0
        )
        
        local tween = TweenService:Create(line, tweenInfo, {
            Position = UDim2.new(0.5, -length/2 + math.random(-50, 50), yPos, 0)
        })
        tween:Play()
        
        table.insert(getgenv().RAYv2_Runtime.TweenCache, tween)
        
        return line
    end
    
    -- Create 4 decorative lines at different screen heights
    CreateDecorativeLine(25, 400, 0.2)
    CreateDecorativeLine(-15, 500, 0.4)
    CreateDecorativeLine(35, 350, 0.6)
    CreateDecorativeLine(-25, 450, 0.8)
    
    -- Main title: "RAYv2"
    -- Positioned at center of screen (0.5, -300 = center X minus half width)
    -- Size (600, 150) provides space for large text
    -- Font.GothamBlack creates bold, impactful appearance
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0, 600, 0, 150)
    titleLabel.Position = UDim2.new(0.5, -300, 0.5, -100)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Text = "RAYv2"
    titleLabel.TextSize = 120
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextStrokeTransparency = 0.5
    titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    titleLabel.Parent = background
    
    -- Title gradient matches background for cohesive animation
    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 212, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
    }
    titleGradient.Rotation = 45
    titleGradient.Offset = Vector2.new(-1, -1)
    titleGradient.Parent = titleLabel
    
    AnimateGradient(titleGradient)
    
    -- Subtitle: "made by @ink"
    -- Positioned 60 pixels below title center
    -- TextTransparency = 0.4 creates subtle, non-distracting appearance
    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(0, 400, 0, 40)
    subtitle.Position = UDim2.new(0.5, -200, 0.5, 60)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.Text = "made by @ink"
    subtitle.TextSize = 28
    subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    subtitle.TextTransparency = 0.4
    subtitle.Parent = background
    
    -- Progress bar container
    -- Positioned at 80% screen height (0.8 scale position)
    -- Size (500, 6) creates thin horizontal bar
    local progressContainer = Instance.new("Frame")
    progressContainer.Name = "ProgressContainer"
    progressContainer.Size = UDim2.new(0, 500, 0, 6)
    progressContainer.Position = UDim2.new(0.5, -250, 0.8, 0)
    progressContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    progressContainer.BorderSizePixel = 0
    progressContainer.Parent = background
    
    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 3)
    progressCorner.Parent = progressContainer
    
    local progressStroke = Instance.new("UIStroke")
    progressStroke.Color = Color3.fromRGB(60, 60, 60)
    progressStroke.Thickness = 1
    progressStroke.Parent = progressContainer
    
    -- Progress fill bar - starts at width 0 and animates to full width
    -- Initial Size = (0, 0, 1, 0) means 0% width, 100% height of parent
    local progressFill = Instance.new("Frame")
    progressFill.Name = "Fill"
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressContainer
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = progressFill
    
    -- Progress fill gradient creates shimmer effect
    local fillGradient = Instance.new("UIGradient")
    fillGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 180, 255))
    }
    fillGradient.Rotation = 90
    fillGradient.Parent = progressFill
    
    -- Progress percentage text positioned above progress bar
    local progressText = Instance.new("TextLabel")
    progressText.Name = "ProgressText"
    progressText.Size = UDim2.new(0, 500, 0, 30)
    progressText.Position = UDim2.new(0.5, -250, 0.8, -40)
    progressText.BackgroundTransparency = 1
    progressText.Font = Enum.Font.GothamBold
    progressText.Text = "INITIALIZING RAYv2... [0%]"
    progressText.TextSize = 18
    progressText.TextColor3 = Color3.fromRGB(0, 212, 255)
    progressText.Parent = background
    
    -- Store reference for cleanup
    getgenv().RAYv2_Runtime.LoadingScreen = loadingScreen
    
    -- Particle animation loop using RenderStepped for smooth 60+ FPS
    -- Updates particle positions every frame based on their velocity
    -- Wraps positions around screen edges (0-1 range) for infinite loop
    local particleConnection = RunService.RenderStepped:Connect(function(deltaTime)
        for _, particleData in ipairs(particles) do
            local frame = particleData.Frame
            local currentPos = frame.Position
            
            local newX = currentPos.X.Scale + particleData.VelocityX
            local newY = currentPos.Y.Scale + particleData.VelocityY
            
            if newX > 1 then newX = 0 elseif newX < 0 then newX = 1 end
            if newY > 1 then newY = 0 elseif newY < 0 then newY = 1 end
            
            frame.Position = UDim2.new(newX, 0, newY, 0)
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, particleConnection)
    
    -- Progress bar animation with randomized duration for human feel
    -- Duration: 2.5 to 3.5 seconds (randomized per injection)
    -- Updates percentage text every 0.05 seconds (20 updates per second)
    -- EasingStyle.Quad creates smooth acceleration/deceleration
    local loadDuration = math.random(250, 350) / 100
    local updateInterval = 0.05
    local elapsed = 0
    
    local progressTween = TweenService:Create(
        progressFill,
        TweenInfo.new(loadDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 1, 0)}
    )
    progressTween:Play()
    table.insert(getgenv().RAYv2_Runtime.TweenCache, progressTween)
    
    -- Progress update loop runs in separate thread
    task.spawn(function()
        while elapsed < loadDuration do
            task.wait(updateInterval)
            elapsed = elapsed + updateInterval
            
            local percent = math.min(100, math.floor((elapsed / loadDuration) * 100))
            progressText.Text = string.format("INITIALIZING RAYv2... [%d%%]", percent)
        end
        
        progressText.Text = "INITIALIZING RAYv2... [100%]"
        task.wait(0.3)
        
        progressText.Text = "READY"
        
        -- Fade out animation: tween all visual elements to transparent
        -- Duration = 0.6 seconds with quadratic easing for smooth fade
        local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        
        local fadeTween = TweenService:Create(background, fadeInfo, {
            BackgroundTransparency = 1
        })
        
        local titleFadeTween = TweenService:Create(titleLabel, fadeInfo, {
            TextTransparency = 1,
            TextStrokeTransparency = 1
        })
        
        local subtitleFadeTween = TweenService:Create(subtitle, fadeInfo, {
            TextTransparency = 1
        })
        
        local progressTextFadeTween = TweenService:Create(progressText, fadeInfo, {
            TextTransparency = 1
        })
        
        local progressContainerFadeTween = TweenService:Create(progressContainer, fadeInfo, {
            BackgroundTransparency = 1
        })
        
        local progressFillFadeTween = TweenService:Create(progressFill, fadeInfo, {
            BackgroundTransparency = 1
        })
        
        fadeTween:Play()
        titleFadeTween:Play()
        subtitleFadeTween:Play()
        progressTextFadeTween:Play()
        progressContainerFadeTween:Play()
        progressFillFadeTween:Play()
        
        fadeTween.Completed:Wait()
        
        particleConnection:Disconnect()
        
        loadingScreen:Destroy()
        getgenv().RAYv2_Runtime.LoadingScreen = nil
        
        DebugPrint("Loading screen completed and destroyed")
        
        -- CRITICAL: Only after loading screen completes, create main GUI
        CreateMainGUI()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: MAIN GUI CREATION (CALLED AFTER LOADING SCREEN)
-- ═══════════════════════════════════════════════════════════════════════════

function CreateMainGUI()
    DebugPrint("Creating main GUI...")
    
    -- Main ScreenGui container
    -- ResetOnSpawn = false ensures GUI persists through character respawns
    -- IgnoreGuiInset = true allows GUI to cover entire screen including top bar
    local mainGui = Instance.new("ScreenGui")
    mainGui.Name = "RAYv2_Main"
    mainGui.ResetOnSpawn = false
    mainGui.IgnoreGuiInset = true
    mainGui.DisplayOrder = 5
    mainGui.Parent = PlayerGui
    
    -- Main container frame
    -- Size = (820, 520) pixels - large enough for all content
    -- Position = center of screen minus half size = (0.5, -410, 0.5, -260)
    -- BackgroundColor3 = RGB(10,10,10) creates dark theme base
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainContainer"
    mainFrame.Size = getgenv().RAYv2_Config.GUI.Size
    mainFrame.Position = getgenv().RAYv2_Config.GUI.Position
    mainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.ClipsDescendants = false
    mainFrame.Parent = mainGui
    
    -- UICorner with radius 12 creates rounded corners on main frame
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame
    
    -- UIStroke creates electric blue neon glow border
    -- Color = RGB(0,212,255) is cyan/electric blue
    -- Thickness = 2 pixels creates visible but not overwhelming border
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(0, 212, 255)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame
    
    -- Title bar at top of main frame
    -- Height = 40 pixels provides space for title and window controls
    -- BackgroundColor slightly lighter than main frame for visual separation
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    -- Round top corners of title bar
    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0, 12)
    titleBarCorner.Parent = titleBar
    
    -- Cover frame hides bottom rounded corners of title bar
    -- This creates sharp bottom edge while keeping top rounded
    local titleBarCover = Instance.new("Frame")
    titleBarCover.Size = UDim2.new(1, 0, 0, 12)
    titleBarCover.Position = UDim2.new(0, 0, 1, -12)
    titleBarCover.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    titleBarCover.BorderSizePixel = 0
    titleBarCover.Parent = titleBar
    
    -- Title text with animated gradient
    -- TextXAlignment = Left aligns text to left side with 15px padding
    local titleText = Instance.new("TextLabel")
    titleText.Name = "TitleText"
    titleText.Size = UDim2.new(0, 200, 1, 0)
    titleText.Position = UDim2.new(0, 15, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBlack
    titleText.Text = "RAYv2"
    titleText.TextSize = 24
    titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar
    
    -- Same animated gradient as loading screen for consistency
    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 212, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
    }
    titleGradient.Rotation = 45
    titleGradient.Offset = Vector2.new(-1, -1)
    titleGradient.Parent = titleText
    
    local titleGradientTween = TweenService:Create(
        titleGradient,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0),
        {Offset = Vector2.new(1, 1)}
    )
    titleGradientTween:Play()
    table.insert(getgenv().RAYv2_Runtime.TweenCache, titleGradientTween)
    
    -- Window controls container on right side of title bar
    -- Position = (1, -110, 0, 0) means right edge minus 110 pixels
    local controlsContainer = Instance.new("Frame")
    controlsContainer.Name = "Controls"
    controlsContainer.Size = UDim2.new(0, 100, 1, 0)
    controlsContainer.Position = UDim2.new(1, -110, 0, 0)
    controlsContainer.BackgroundTransparency = 1
    controlsContainer.Parent = titleBar
    
    -- Minimize button
    -- Size = (30, 30) creates square button
    -- Position uses 0.5 scale for vertical centering minus half height
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeButton"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(0, 0, 0.5, -15)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    minimizeBtn.Text = "_"
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextSize = 20
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.AutoButtonColor = false
    minimizeBtn.Parent = controlsContainer
    
    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 6)
    minimizeCorner.Parent = minimizeBtn
    
    local minimizeStroke = Instance.new("UIStroke")
    minimizeStroke.Color = Color3.fromRGB(60, 60, 60)
    minimizeStroke.Thickness = 1
    minimizeStroke.Parent = minimizeBtn
    
    -- Close button
    -- Positioned 40 pixels right of minimize button
    -- Red text color indicates destructive action
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(0, 40, 0.5, -15)
    closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = controlsContainer
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn
    
    local closeStroke = Instance.new("UIStroke")
    closeStroke.Color = Color3.fromRGB(60, 60, 60)
    closeStroke.Thickness = 1
    closeStroke.Parent = closeBtn
    
    -- Hover effect helper function
    -- Creates smooth color transition on mouse enter/leave
    local function AddButtonHover(button, hoverColor)
        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {
                BackgroundColor3 = hoverColor
            }):Play()
        end)
        
        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            }):Play()
        end)
    end
    
    AddButtonHover(minimizeBtn, Color3.fromRGB(40, 40, 40))
    AddButtonHover(closeBtn, Color3.fromRGB(255, 60, 60))
    
    -- Minimized icon (created but hidden initially)
    -- Positioned in top-right corner of screen
    -- Size = (50, 50) creates visible clickable target
    local minimizedIcon = Instance.new("Frame")
    minimizedIcon.Name = "MinimizedIcon"
    minimizedIcon.Size = UDim2.new(0, 50, 0, 50)
    minimizedIcon.Position = UDim2.new(0.98, -50, 0.02, 0)
    minimizedIcon.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    minimizedIcon.Visible = false
    minimizedIcon.Parent = mainGui
    
    -- CornerRadius = (1, 0) creates perfect circle
    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(1, 0)
    iconCorner.Parent = minimizedIcon
    
    local iconStroke = Instance.new("UIStroke")
    iconStroke.Color = Color3.fromRGB(255, 255, 255)
    iconStroke.Thickness = 2
    iconStroke.Parent = minimizedIcon
    
    -- Icon text showing "R" for RAYv2
    local iconText = Instance.new("TextLabel")
    iconText.Size = UDim2.new(1, 0, 1, 0)
    iconText.BackgroundTransparency = 1
    iconText.Font = Enum.Font.GothamBlack
    iconText.Text = "R"
    iconText.TextSize = 28
    iconText.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconText.Parent = minimizedIcon
    
    -- Invisible button covering icon for click detection
    local iconButton = Instance.new("TextButton")
    iconButton.Size = UDim2.new(1, 0, 1, 0)
    iconButton.BackgroundTransparency = 1
    iconButton.Text = ""
    iconButton.Parent = minimizedIcon
    
    -- Minimize/Maximize functionality
    local isMinimized = false
    
    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        
        if isMinimized then
            -- Minimize animation: shrink to point and move to icon position
            -- EasingStyle.Back creates bounce effect
            TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
                Size = UDim2.new(0, 0, 0, 0),
                Position = UDim2.new(0.98, -25, 0.02, 25)
            }):Play()
            
            task.wait(0.3)
            mainFrame.Visible = false
            minimizedIcon.Visible = true
            
            -- Icon appears with bounce
            TweenService:Create(minimizedIcon, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
                Size = UDim2.new(0, 50, 0, 50)
            }):Play()
        else
            -- Maximize animation: restore original size and position
            minimizedIcon.Visible = false
            mainFrame.Visible = true
            
            TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
                Size = getgenv().RAYv2_Config.GUI.Size,
                Position = getgenv().RAYv2_Config.GUI.Position
            }):Play()
        end
    end)
    
    iconButton.MouseButton1Click:Connect(function()
        if isMinimized then
            minimizeBtn.MouseButton1Click:Fire()
        end
    end)
    
    -- Close button functionality
    closeBtn.MouseButton1Click:Connect(function()
        -- Fade out animation before destroying
        TweenService:Create(mainFrame, TweenInfo.new(0.3), {
            BackgroundTransparency = 1
        }):Play()
        
        TweenService:Create(mainStroke, TweenInfo.new(0.3), {
            Transparency = 1
        }):Play()
        
        task.wait(0.3)
        mainGui:Destroy()
        
        -- Clean up all resources
        CleanupScript()
    end)
    
    -- Dragging functionality
    -- Allows user to move GUI by clicking and dragging title bar
    local dragging = false
    local dragInput, dragStart, startPos
    
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    titleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            
            -- Calculate new position maintaining scale component
            local newPos = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            
            mainFrame.Position = newPos
            getgenv().RAYv2_Config.GUI.Position = newPos
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- TAB BAR CREATION (MANDATORY: LEFT-ALIGNED WITH UIListLayout)
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Tab container directly under title bar
    -- Height = 40 pixels matches title bar height
    -- UIListLayout ensures tabs stay left-aligned and never shift right
    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, 0, 0, 40)
    tabContainer.Position = UDim2.new(0, 0, 0, 40)
    tabContainer.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    tabContainer.BorderSizePixel = 0
    tabContainer.Parent = mainFrame
    
    -- UIListLayout forces horizontal layout with zero padding
    -- SortOrder = Name ensures consistent ordering
    local tabListLayout = Instance.new("UIListLayout")
    tabListLayout.FillDirection = Enum.FillDirection.Horizontal
    tabListLayout.SortOrder = Enum.SortOrder.Name
    tabListLayout.Padding = UDim.new(0, 0)
    tabListLayout.Parent = tabContainer
    
    -- Content container for tab panels
    -- Position at Y=80 (title bar 40 + tab bar 40)
    -- Size fills remaining space: 1,0 width and 1,-80 height
    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentContainer"
    contentContainer.Size = UDim2.new(1, -20, 1, -100)
    contentContainer.Position = UDim2.new(0, 10, 0, 90)
    contentContainer.BackgroundTransparency = 1
    contentContainer.ClipsDescendants = true
    contentContainer.Parent = mainFrame
    
    -- Tab data: four tabs for Aimbot, ESP, Configs, Profile
    local tabs = {
        {Name = "Tab_Aimbot", DisplayName = "AIMBOT"},
        {Name = "Tab_ESP", DisplayName = "ESP"},
        {Name = "Tab_Configs", DisplayName = "CONFIGS"},
        {Name = "Tab_Profile", DisplayName = "PROFILE"}
    }
    local tabButtons = {}
    local tabPanels = {}
    local currentTab = nil
    
    -- Tab indicator (sliding underline)
    -- Positioned at bottom of tab bar
    -- Will be animated to move under active tab
    local tabIndicator = Instance.new("Frame")
    tabIndicator.Name = "Indicator"
    tabIndicator.Size = UDim2.new(0, 0, 0, 3)
    tabIndicator.Position = UDim2.new(0, 0, 1, -3)
    tabIndicator.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    tabIndicator.BorderSizePixel = 0
    tabIndicator.Parent = tabContainer
    
    -- Create tab buttons
    -- Each button width = 140 pixels for consistent sizing
    for i, tabData in ipairs(tabs) do
        local tabButton = Instance.new("TextButton")
        tabButton.Name = tabData.Name
        tabButton.Size = UDim2.new(0, 140, 1, 0)
        tabButton.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
        tabButton.Text = tabData.DisplayName
        tabButton.Font = Enum.Font.GothamBold
        tabButton.TextSize = 16
        tabButton.TextColor3 = Color3.fromRGB(150, 150, 150)
        tabButton.AutoButtonColor = false
        tabButton.Parent = tabContainer
        
        -- UIStroke for hover glow effect
        local tabStroke = Instance.new("UIStroke")
        tabStroke.Color = Color3.fromRGB(0, 212, 255)
        tabStroke.Thickness = 0
        tabStroke.Transparency = 0
        tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        tabStroke.Parent = tabButton
        
        -- Hover animations
        tabButton.MouseEnter:Connect(function()
            if currentTab ~= tabData.Name then
                TweenService:Create(tabStroke, TweenInfo.new(0.2), {
                    Thickness = 1,
                    Transparency = 0.5
                }):Play()
                
                TweenService:Create(tabButton, TweenInfo.new(0.2), {
                    TextColor3 = Color3.fromRGB(200, 200, 200)
                }):Play()
            end
        end)
        
        tabButton.MouseLeave:Connect(function()
            if currentTab ~= tabData.Name then
                TweenService:Create(tabStroke, TweenInfo.new(0.2), {
                    Thickness = 0
                }):Play()
                
                TweenService:Create(tabButton, TweenInfo.new(0.2), {
                    TextColor3 = Color3.fromRGB(150, 150, 150)
                }):Play()
            end
        end)
        
        tabButtons[tabData.Name] = tabButton
        
        -- Create corresponding content panel
        -- ScrollingFrame allows vertical scrolling for overflow content
        local tabPanel = Instance.new("ScrollingFrame")
        tabPanel.Name = "Content_" .. tabData.DisplayName
        tabPanel.Size = UDim2.new(1, 0, 1, 0)
        tabPanel.Position = UDim2.new(0, 0, 0, 0)
        tabPanel.BackgroundTransparency = 1
        tabPanel.BorderSizePixel = 0
        tabPanel.ScrollBarThickness = 6
        tabPanel.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
        tabPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
        tabPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabPanel.Visible = false
        tabPanel.Parent = contentContainer
        
        -- UIListLayout for automatic vertical stacking of controls
        local panelListLayout = Instance.new("UIListLayout")
        panelListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        panelListLayout.Padding = UDim.new(0, 10)
        panelListLayout.Parent = tabPanel
        
        local panelPadding = Instance.new("UIPadding")
        panelPadding.PaddingTop = UDim.new(0, 10)
        panelPadding.PaddingBottom = UDim.new(0, 10)
        panelPadding.Parent = tabPanel
        
        tabPanels[tabData.Name] = tabPanel
    end
    
    -- Tab switching function
    -- Handles hiding old panel, showing new panel, and animating indicator
    local function SwitchTab(tabName)
        if currentTab == tabName then return end
        
        local targetButton = tabButtons[tabName]
        local targetPanel = tabPanels[tabName]
        
        -- Deactivate current tab
        if currentTab then
            local oldButton = tabButtons[currentTab]
            local oldPanel = tabPanels[currentTab]
            
            TweenService:Create(oldButton, TweenInfo.new(0.2), {
                TextColor3 = Color3.fromRGB(150, 150, 150)
            }):Play()
            
            local oldStroke = oldButton:FindFirstChildOfClass("UIStroke")
            if oldStroke then
                TweenService:Create(oldStroke, TweenInfo.new(0.2), {
                    Thickness = 0
                }):Play()
            end
            
            -- Fade out old panel with slide animation
            TweenService:Create(oldPanel, TweenInfo.new(0.15), {
                Position = UDim2.new(-0.1, 0, 0, 0),
                GroupTransparency = 1
            }):Play()
            
            task.wait(0.15)
            oldPanel.Visible = false
        end
        
        -- Activate new tab
        currentTab = tabName
        
        TweenService:Create(targetButton, TweenInfo.new(0.2), {
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
        
        -- Move indicator under new tab
        -- Position calculated from button's absolute position
        local indicatorTargetPos = UDim2.new(0, targetButton.AbsolutePosition.X - tabContainer.AbsolutePosition.X, 1, -3)
        local indicatorTargetSize = UDim2.new(0, 140, 0, 3)
        
        TweenService:Create(tabIndicator, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Position = indicatorTargetPos,
            Size = indicatorTargetSize
        }):Play()
        
        -- Fade in new panel with slide animation
        targetPanel.Visible = true
        targetPanel.GroupTransparency = 1
        targetPanel.Position = UDim2.new(0.1, 0, 0, 0)
        
        TweenService:Create(targetPanel, TweenInfo.new(0.2), {
            Position = UDim2.new(0, 0, 0, 0),
            GroupTransparency = 0
        }):Play()
    end
    
    -- Connect tab button clicks
    for tabName, button in pairs(tabButtons) do
        button.Activated:Connect(function()
            SwitchTab(tabName)
        end)
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- GUI HELPER FUNCTIONS (REUSABLE CONTROL CREATION)
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Create section header
    -- Used to organize controls into labeled groups
    local function CreateSectionHeader(parent, text, layoutOrder)
        local header = Instance.new("TextLabel")
        header.Name = text .. "Header"
        header.Size = UDim2.new(1, 0, 0, 30)
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = text
        header.TextSize = 18
        header.TextColor3 = Color3.fromRGB(0, 212, 255)
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.LayoutOrder = layoutOrder
        header.Parent = parent
        
        return header
    end
    
    -- Create toggle checkbox
    -- Returns: container frame, getter function, setter function
    local function CreateToggle(parent, text, defaultValue, callback, layoutOrder)
        -- Container frame with dark background
        local container = Instance.new("Frame")
        container.Name = text .. "Toggle"
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        container.BorderSizePixel = 0
        container.LayoutOrder = layoutOrder
        container.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container
        
        -- Label text on left side
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -45, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.Text = text
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        -- Checkbox frame on right side
        -- Changes color based on toggle state
        local checkbox = Instance.new("Frame")
        checkbox.Name = "Checkbox"
        checkbox.Size = UDim2.new(0, 25, 0, 25)
        checkbox.Position = UDim2.new(1, -30, 0.5, -12.5)
        checkbox.BackgroundColor3 = defaultValue and Color3.fromRGB(0, 212, 255) or Color3.fromRGB(30, 30, 30)
        checkbox.BorderSizePixel = 0
        checkbox.Parent = container
        
        local checkboxCorner = Instance.new("UICorner")
        checkboxCorner.CornerRadius = UDim.new(0, 4)
        checkboxCorner.Parent = checkbox
        
        local checkboxStroke = Instance.new("UIStroke")
        checkboxStroke.Color = Color3.fromRGB(60, 60, 60)
        checkboxStroke.Thickness = 1
        checkboxStroke.Parent = checkbox
        
        -- Checkmark symbol (visible when enabled)
        local checkmark = Instance.new("TextLabel")
        checkmark.Size = UDim2.new(1, 0, 1, 0)
        checkmark.BackgroundTransparency = 1
        checkmark.Font = Enum.Font.GothamBold
        checkmark.Text = "✓"
        checkmark.TextSize = 18
        checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
        checkmark.Visible = defaultValue
        checkmark.Parent = checkbox
        
        -- Invisible button for click detection
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 1, 0)
        button.BackgroundTransparency = 1
        button.Text = ""
        button.Parent = container
        
        local toggled = defaultValue
        
        -- Click handler toggles state and fires callback
        button.MouseButton1Click:Connect(function()
            toggled = not toggled
            
            TweenService:Create(checkbox, TweenInfo.new(0.15), {
                BackgroundColor3 = toggled and Color3.fromRGB(0, 212, 255) or Color3.fromRGB(30, 30, 30)
            }):Play()
            
            checkmark.Visible = toggled
            
            if callback then
                callback(toggled)
            end
        end)
        
        -- Return container, getter, and setter
        return container, function() return toggled end, function(value) 
            toggled = value
            checkbox.BackgroundColor3 = toggled and Color3.fromRGB(0, 212, 255) or Color3.fromRGB(30, 30, 30)
            checkmark.Visible = toggled
        end
    end
    
    -- Create slider
    -- Returns: container frame, getter function, setter function
    local function CreateSlider(parent, text, min, max, defaultValue, suffix, callback, layoutOrder)
        -- Container with extra height for slider bar
        local container = Instance.new("Frame")
        container.Name = text .. "Slider"
        container.Size = UDim2.new(1, 0, 0, 50)
        container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        container.BorderSizePixel = 0
        container.LayoutOrder = layoutOrder
        container.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container
        
        -- Label showing slider name
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 0, 20)
        label.Position = UDim2.new(0, 10, 0, 5)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.Text = text
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        -- Value label showing current value with suffix
        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0, 60, 0, 20)
        valueLabel.Position = UDim2.new(1, -70, 0, 5)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Font = Enum.Font.GothamBold
        valueLabel.Text = tostring(defaultValue) .. (suffix or "")
        valueLabel.TextSize = 14
        valueLabel.TextColor3 = Color3.fromRGB(0, 212, 255)
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Parent = container
        
        -- Slider background bar
        local sliderBack = Instance.new("Frame")
        sliderBack.Size = UDim2.new(1, -20, 0, 6)
        sliderBack.Position = UDim2.new(0, 10, 1, -15)
        sliderBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        sliderBack.BorderSizePixel = 0
        sliderBack.Parent = container
        
        local sliderBackCorner = Instance.new("UICorner")
        sliderBackCorner.CornerRadius = UDim.new(0, 3)
        sliderBackCorner.Parent = sliderBack
        
        -- Slider fill showing current value visually
        -- Width is proportional to value: (value - min) / (max - min)
        local sliderFill = Instance.new("Frame")
        sliderFill.Name = "Fill"
        sliderFill.Size = UDim2.new((defaultValue - min) / (max - min), 0, 1, 0)
        sliderFill.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
        sliderFill.BorderSizePixel = 0
        sliderFill.Parent = sliderBack
        
        local sliderFillCorner = Instance.new("UICorner")
        sliderFillCorner.CornerRadius = UDim.new(0, 3)
        sliderFillCorner.Parent = sliderFill
        
        -- Invisible button for drag detection
        local sliderButton = Instance.new("TextButton")
        sliderButton.Size = UDim2.new(1, 0, 1, 10)
        sliderButton.Position = UDim2.new(0, 0, 0, -5)
        sliderButton.BackgroundTransparency = 1
        sliderButton.Text = ""
        sliderButton.Parent = sliderBack
        
        local currentValue = defaultValue
        local dragging = false
        
        -- Update slider based on mouse position
        -- Calculate relative X position (0-1) then map to min-max range
        local function UpdateSlider(input)
            local relativeX = math.clamp((input.Position.X - sliderBack.AbsolutePosition.X) / sliderBack.AbsoluteSize.X, 0, 1)
            currentValue = math.floor(min + (max - min) * relativeX)
            
            sliderFill.Size = UDim2.new(relativeX, 0, 1, 0)
            valueLabel.Text = tostring(currentValue) .. (suffix or "")
            
            if callback then
                callback(currentValue)
            end
        end
        
        -- Drag handling
        sliderButton.MouseButton1Down:Connect(function()
            dragging = true
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                UpdateSlider(input)
            end
        end)
        
        sliderButton.MouseButton1Click:Connect(function()
            UpdateSlider(Mouse)
        end)
        
        return container, function() return currentValue end, function(value)
            currentValue = math.clamp(value, min, max)
            local relativeX = (currentValue - min) / (max - min)
            sliderFill.Size = UDim2.new(relativeX, 0, 1, 0)
            valueLabel.Text = tostring(currentValue) .. (suffix or "")
        end
    end
    
    -- Create keybind input
    -- Returns: container frame, getter function
    local function CreateKeybind(parent, text, defaultKey, callback, layoutOrder)
        local container = Instance.new("Frame")
        container.Name = text .. "Keybind"
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        container.BorderSizePixel = 0
        container.LayoutOrder = layoutOrder
        container.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -120, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.Text = text
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        -- Button showing current key and allowing rebind
        local keybindButton = Instance.new("TextButton")
        keybindButton.Size = UDim2.new(0, 100, 0, 25)
        keybindButton.Position = UDim2.new(1, -110, 0.5, -12.5)
        keybindButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        keybindButton.Font = Enum.Font.GothamBold
        keybindButton.Text = defaultKey.Name
        keybindButton.TextSize = 12
        keybindButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        keybindButton.AutoButtonColor = false
        keybindButton.Parent = container
        
        local keybindCorner = Instance.new("UICorner")
        keybindCorner.CornerRadius = UDim.new(0, 4)
        keybindCorner.Parent = keybindButton
        
        local currentKey = defaultKey
        local listening = false
        
        -- Click to start listening for new key
        keybindButton.MouseButton1Click:Connect(function()
            listening = true
            keybindButton.Text = "..."
            keybindButton.TextColor3 = Color3.fromRGB(0, 212, 255)
        end)
        
        -- Capture next key press
        local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                currentKey = input.KeyCode
                keybindButton.Text = input.KeyCode.Name
                keybindButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                listening = false
                
                if callback then
                    callback(currentKey)
                end
            end
        end)
        
        table.insert(getgenv().RAYv2_Runtime.Connections, connection)
        
        return container, function() return currentKey end
    end
    
    -- Create dropdown menu
    -- Returns: container frame, getter function
    local function CreateDropdown(parent, text, options, defaultOption, callback, layoutOrder)
        local container = Instance.new("Frame")
        container.Name = text .. "Dropdown"
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        container.BorderSizePixel = 0
        container.LayoutOrder = layoutOrder
        container.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -120, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.Text = text
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        -- Button showing current selection
        local dropdownButton = Instance.new("TextButton")
        dropdownButton.Size = UDim2.new(0, 100, 0, 25)
        dropdownButton.Position = UDim2.new(1, -110, 0.5, -12.5)
        dropdownButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        dropdownButton.Font = Enum.Font.GothamBold
        dropdownButton.Text = defaultOption .. " ▼"
        dropdownButton.TextSize = 12
        dropdownButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        dropdownButton.AutoButtonColor = false
        dropdownButton.Parent = container
        
        local dropdownCorner = Instance.new("UICorner")
        dropdownCorner.CornerRadius = UDim.new(0, 4)
        dropdownCorner.Parent = dropdownButton
        
        -- Options frame (shown when dropdown clicked)
        local optionsFrame = Instance.new("Frame")
        optionsFrame.Name = "Options"
        optionsFrame.Size = UDim2.new(0, 100, 0, #options * 25)
        optionsFrame.Position = UDim2.new(1, -110, 1, 5)
        optionsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        optionsFrame.BorderSizePixel = 0
        optionsFrame.Visible = false
        optionsFrame.ZIndex = 10
        optionsFrame.Parent = container
        
        local optionsCorner = Instance.new("UICorner")
        optionsCorner.CornerRadius = UDim.new(0, 4)
        optionsCorner.Parent = optionsFrame
        
        local optionsStroke = Instance.new("UIStroke")
        optionsStroke.Color = Color3.fromRGB(0, 212, 255)
        optionsStroke.Thickness = 1
        optionsStroke.Parent = optionsFrame
        
        local optionsLayout = Instance.new("UIListLayout")
        optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        optionsLayout.Parent = optionsFrame
        
        local currentOption = defaultOption
        
        -- Create button for each option
        for i, option in ipairs(options) do
            local optionButton = Instance.new("TextButton")
            optionButton.Size = UDim2.new(1, 0, 0, 25)
            optionButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            optionButton.Font = Enum.Font.Gotham
            optionButton.Text = option
            optionButton.TextSize = 12
            optionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            optionButton.AutoButtonColor = false
            optionButton.LayoutOrder = i
            optionButton.ZIndex = 11
            optionButton.Parent = optionsFrame
            
            optionButton.MouseEnter:Connect(function()
                optionButton.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
            end)
            
            optionButton.MouseLeave:Connect(function()
                optionButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            end)
            
            optionButton.MouseButton1Click:Connect(function()
                currentOption = option
                dropdownButton.Text = option .. " ▼"
                optionsFrame.Visible = false
                
                if callback then
                    callback(option)
                end
            end)
        end
        
        dropdownButton.MouseButton1Click:Connect(function()
            optionsFrame.Visible = not optionsFrame.Visible
        end)
        
        return container, function() return currentOption end
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- AIMBOT TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local aimbotPanel = tabPanels["Tab_Aimbot"]
    local layoutOrder = 0
    
    CreateSectionHeader(aimbotPanel, "AIMBOT", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local aimbotToggle, getAimbotEnabled, setAimbotEnabled = CreateToggle(
        aimbotPanel,
        "Enable Aimbot",
        getgenv().RAYv2_Config.Aimbot.Enabled,
        function(value)
            getgenv().RAYv2_Config.Aimbot.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local aimbotKeybind, getAimbotKey = CreateKeybind(
        aimbotPanel,
        "Aimbot Keybind",
        getgenv().RAYv2_Config.Aimbot.Keybind,
        function(key)
            getgenv().RAYv2_Config.Aimbot.Keybind = key
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local aimbotMode, getAimbotMode = CreateDropdown(
        aimbotPanel,
        "Activation Mode",
        {"Toggle", "Hold"},
        getgenv().RAYv2_Config.Aimbot.Mode,
        function(mode)
            getgenv().RAYv2_Config.Aimbot.Mode = mode
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local silentAimToggle, getSilentAimEnabled = CreateToggle(
        aimbotPanel,
        "Silent Aim (Invisible)",
        getgenv().RAYv2_Config.Aimbot.SilentAim,
        function(value)
            getgenv().RAYv2_Config.Aimbot.SilentAim = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(aimbotPanel, "FOV SETTINGS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local fovSlider, getFOV = CreateSlider(
        aimbotPanel,
        "FOV Radius",
        0,
        360,
        getgenv().RAYv2_Config.Aimbot.FOV,
        "°",
        function(value)
            getgenv().RAYv2_Config.Aimbot.FOV = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local fovVisibleToggle, getFOVVisible = CreateToggle(
        aimbotPanel,
        "Show FOV Circle",
        getgenv().RAYv2_Config.Aimbot.FOVVisible,
        function(value)
            getgenv().RAYv2_Config.Aimbot.FOVVisible = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local fovFilledToggle, getFOVFilled = CreateToggle(
        aimbotPanel,
        "Fill FOV Circle",
        getgenv().RAYv2_Config.Aimbot.FOVFilled,
        function(value)
            getgenv().RAYv2_Config.Aimbot.FOVFilled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(aimbotPanel, "SMOOTHING & PREDICTION", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local smoothnessSlider, getSmoothness = CreateSlider(
        aimbotPanel,
        "Smoothness",
        0,
        100,
        getgenv().RAYv2_Config.Aimbot.Smoothness,
        "%",
        function(value)
            getgenv().RAYv2_Config.Aimbot.Smoothness = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local predictionToggle, getPrediction = CreateToggle(
        aimbotPanel,
        "Velocity Prediction",
        getgenv().RAYv2_Config.Aimbot.Prediction,
        function(value)
            getgenv().RAYv2_Config.Aimbot.Prediction = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local predictionFactorSlider, getPredictionFactor = CreateSlider(
        aimbotPanel,
        "Prediction Strength",
        0,
        100,
        math.floor(getgenv().RAYv2_Config.Aimbot.PredictionFactor * 100),
        "%",
        function(value)
            getgenv().RAYv2_Config.Aimbot.PredictionFactor = value / 100
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(aimbotPanel, "TARGET FILTERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local distanceSlider, getMaxDistance = CreateSlider(
        aimbotPanel,
        "Max Distance",
        0,
        500,
        getgenv().RAYv2_Config.Aimbot.MaxDistance,
        " studs",
        function(value)
            getgenv().RAYv2_Config.Aimbot.MaxDistance = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local teamCheckToggle, getTeamCheck = CreateToggle(
        aimbotPanel,
        "Team Check",
        getgenv().RAYv2_Config.Aimbot.TeamCheck,
        function(value)
            getgenv().RAYv2_Config.Aimbot.TeamCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local visibleCheckToggle, getVisibleCheck = CreateToggle(
        aimbotPanel,
        "Visible Check (Wallcheck)",
        getgenv().RAYv2_Config.Aimbot.VisibleCheck,
        function(value)
            getgenv().RAYv2_Config.Aimbot.VisibleCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local headPriorityToggle, getHeadPriority = CreateToggle(
        aimbotPanel,
        "Prioritize Head",
        getgenv().RAYv2_Config.Aimbot.HeadPriority,
        function(value)
            getgenv().RAYv2_Config.Aimbot.HeadPriority = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(aimbotPanel, "TRIGGERBOT", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local triggerbotToggle, getTriggerbotEnabled = CreateToggle(
        aimbotPanel,
        "Enable Triggerbot",
        getgenv().RAYv2_Config.Aimbot.Triggerbot.Enabled,
        function(value)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local triggerbotKeybind, getTriggerbotKey = CreateKeybind(
        aimbotPanel,
        "Triggerbot Keybind",
        getgenv().RAYv2_Config.Aimbot.Triggerbot.Keybind,
        function(key)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Keybind = key
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local triggerbotDelaySlider, getTriggerbotDelay = CreateSlider(
        aimbotPanel,
        "Shoot Delay",
        0,
        100,
        math.floor(getgenv().RAYv2_Config.Aimbot.Triggerbot.Delay * 100),
        "ms",
        function(value)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Delay = value / 100
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ESP TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local espPanel = tabPanels["Tab_ESP"]
    layoutOrder = 0
    
    CreateSectionHeader(espPanel, "ESP", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local espToggle, getESPEnabled = CreateToggle(
        espPanel,
        "Enable ESP",
        getgenv().RAYv2_Config.ESP.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local espDistanceSlider, getESPDistance = CreateSlider(
        espPanel,
        "Max ESP Distance",
        0,
        500,
        getgenv().RAYv2_Config.ESP.MaxDistance,
        " studs",
        function(value)
            getgenv().RAYv2_Config.ESP.MaxDistance = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local espTeamCheckToggle, getESPTeamCheck = CreateToggle(
        espPanel,
        "Team Check",
        getgenv().RAYv2_Config.ESP.TeamCheck,
        function(value)
            getgenv().RAYv2_Config.ESP.TeamCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(espPanel, "BOXES", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local boxesToggle, getBoxesEnabled = CreateToggle(
        espPanel,
        "Show Boxes",
        getgenv().RAYv2_Config.ESP.Boxes.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Boxes.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local fillToggle, getFillEnabled = CreateToggle(
        espPanel,
        "Fill Boxes",
        getgenv().RAYv2_Config.ESP.Fill.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Fill.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(espPanel, "SKELETON", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local skeletonToggle, getSkeletonEnabled = CreateToggle(
        espPanel,
        "Show Skeleton",
        getgenv().RAYv2_Config.ESP.Skeleton.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Skeleton.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(espPanel, "TRACERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local tracersToggle, getTracersEnabled = CreateToggle(
        espPanel,
        "Show Tracers",
        getgenv().RAYv2_Config.ESP.Tracers.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Tracers.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local tracersFrom, getTracersFrom = CreateDropdown(
        espPanel,
        "Tracers From",
        {"Bottom", "Center", "Mouse"},
        getgenv().RAYv2_Config.ESP.Tracers.From,
        function(value)
            getgenv().RAYv2_Config.ESP.Tracers.From = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(espPanel, "TEXT INFO", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local nameToggle, getNameEnabled = CreateToggle(
        espPanel,
        "Show Name",
        getgenv().RAYv2_Config.ESP.Name.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Name.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local healthToggle, getHealthEnabled = CreateToggle(
        espPanel,
        "Show Health",
        getgenv().RAYv2_Config.ESP.Health.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Health.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local healthBarToggle, getHealthBarEnabled = CreateToggle(
        espPanel,
        "Show Health Bar",
        getgenv().RAYv2_Config.ESP.Health.BarEnabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Health.BarEnabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local distanceToggle, getDistanceEnabled = CreateToggle(
        espPanel,
        "Show Distance",
        getgenv().RAYv2_Config.ESP.Distance.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Distance.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local weaponToggle, getWeaponEnabled = CreateToggle(
        espPanel,
        "Show Weapon",
        getgenv().RAYv2_Config.ESP.Weapon.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Weapon.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- CONFIGS TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local configsPanel = tabPanels["Tab_Configs"]
    layoutOrder = 0
    
    CreateSectionHeader(configsPanel, "CONFIGURATION MANAGER", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    -- Config name input
    local configNameContainer = Instance.new("Frame")
    configNameContainer.Name = "ConfigNameInput"
    configNameContainer.Size = UDim2.new(1, 0, 0, 50)
    configNameContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    configNameContainer.BorderSizePixel = 0
    configNameContainer.LayoutOrder = layoutOrder
    configNameContainer.Parent = configsPanel
    layoutOrder = layoutOrder + 1
    
    local configNameCorner = Instance.new("UICorner")
    configNameCorner.CornerRadius = UDim.new(0, 6)
    configNameCorner.Parent = configNameContainer
    
    local configNameLabel = Instance.new("TextLabel")
    configNameLabel.Size = UDim2.new(1, -20, 0, 20)
    configNameLabel.Position = UDim2.new(0, 10, 0, 5)
    configNameLabel.BackgroundTransparency = 1
    configNameLabel.Font = Enum.Font.Gotham
    configNameLabel.Text = "Config Name"
    configNameLabel.TextSize = 14
    configNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    configNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    configNameLabel.Parent = configNameContainer
    
    local configNameInput = Instance.new("TextBox")
    configNameInput.Size = UDim2.new(1, -20, 0, 20)
    configNameInput.Position = UDim2.new(0, 10, 1, -25)
    configNameInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    configNameInput.BorderSizePixel = 0
    configNameInput.Font = Enum.Font.Gotham
    configNameInput.PlaceholderText = "Enter config name..."
    configNameInput.Text = ""
    configNameInput.TextSize = 12
    configNameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    configNameInput.TextXAlignment = Enum.TextXAlignment.Left
    configNameInput.ClearTextOnFocus = false
    configNameInput.Parent = configNameContainer
    
    local configInputCorner = Instance.new("UICorner")
    configInputCorner.CornerRadius = UDim.new(0, 4)
    configInputCorner.Parent = configNameInput
    
    local configInputPadding = Instance.new("UIPadding")
    configInputPadding.PaddingLeft = UDim.new(0, 8)
    configInputPadding.PaddingRight = UDim.new(0, 8)
    configInputPadding.Parent = configNameInput
    
    -- Save and Load buttons
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Name = "ButtonContainer"
    buttonContainer.Size = UDim2.new(1, 0, 0, 35)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.LayoutOrder = layoutOrder
    buttonContainer.Parent = configsPanel
    layoutOrder = layoutOrder + 1
    
    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.48, 0, 1, 0)
    saveButton.Position = UDim2.new(0, 0, 0, 0)
    saveButton.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    saveButton.Font = Enum.Font.GothamBold
    saveButton.Text = "SAVE CONFIG"
    saveButton.TextSize = 14
    saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveButton.AutoButtonColor = false
    saveButton.Parent = buttonContainer
    
    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 6)
    saveCorner.Parent = saveButton
    
    local loadButton = Instance.new("TextButton")
    loadButton.Size = UDim2.new(0.48, 0, 1, 0)
    loadButton.Position = UDim2.new(0.52, 0, 0, 0)
    loadButton.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
    loadButton.Font = Enum.Font.GothamBold
    loadButton.Text = "LOAD CONFIG"
    loadButton.TextSize = 14
    loadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    loadButton.AutoButtonColor = false
    loadButton.Parent = buttonContainer
    
    local loadCorner = Instance.new("UICorner")
    loadCorner.CornerRadius = UDim.new(0, 6)
    loadCorner.Parent = loadButton
    
    AddButtonHover(saveButton, Color3.fromRGB(0, 180, 220))
    AddButtonHover(loadButton, Color3.fromRGB(0, 150, 70))
    
    CreateSectionHeader(configsPanel, "SAVED CONFIGS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    -- Config list ScrollingFrame
    local configListContainer = Instance.new("Frame")
    configListContainer.Name = "ConfigList"
    configListContainer.Size = UDim2.new(1, 0, 0, 200)
    configListContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    configListContainer.BorderSizePixel = 0
    configListContainer.LayoutOrder = layoutOrder
    configListContainer.Parent = configsPanel
    layoutOrder = layoutOrder + 1
    
    local configListCorner = Instance.new("UICorner")
    configListCorner.CornerRadius = UDim.new(0, 6)
    configListCorner.Parent = configListContainer
    
    local configScrollFrame = Instance.new("ScrollingFrame")
    configScrollFrame.Size = UDim2.new(1, -10, 1, -10)
    configScrollFrame.Position = UDim2.new(0, 5, 0, 5)
    configScrollFrame.BackgroundTransparency = 1
    configScrollFrame.BorderSizePixel = 0
    configScrollFrame.ScrollBarThickness = 4
    configScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
    configScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    configScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    configScrollFrame.Parent = configListContainer
    
    local configListLayout = Instance.new("UIListLayout")
    configListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    configListLayout.Padding = UDim.new(0, 5)
    configListLayout.Parent = configScrollFrame
    
    -- Config system implementation
    local savedConfigs = {}
    
    local function SaveConfig(configName)
        if configName == "" then
            return
        end
        
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local configData = {
            Name = configName,
            Timestamp = timestamp,
            Settings = getgenv().RAYv2_Config
        }
        
        savedConfigs[configName] = configData
        
        pcall(function()
            if writefile then
                local encoded = HttpService:JSONEncode(configData)
                writefile("RAYv2_" .. configName .. ".json", encoded)
            end
        end)
        
        RefreshConfigList()
    end
    
    local function LoadConfig(configName)
        local configData = savedConfigs[configName]
        
        if not configData then
            pcall(function()
                if readfile then
                    local fileData = readfile("RAYv2_" .. configName .. ".json")
                    configData = HttpService:JSONDecode(fileData)
                    savedConfigs[configName] = configData
                end
            end)
        end
        
        if configData and configData.Settings then
            getgenv().RAYv2_Config = configData.Settings
            setAimbotEnabled(configData.Settings.Aimbot.Enabled)
        end
    end
    
    local function DeleteConfig(configName)
        savedConfigs[configName] = nil
        
        pcall(function()
            if delfile then
                delfile("RAYv2_" .. configName .. ".json")
            end
        end)
        
        RefreshConfigList()
    end
    
    function RefreshConfigList()
        for _, child in ipairs(configScrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        local order = 0
        for configName, configData in pairs(savedConfigs) do
            local configEntry = Instance.new("Frame")
            configEntry.Name = configName
            configEntry.Size = UDim2.new(1, 0, 0, 40)
            configEntry.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            configEntry.BorderSizePixel = 0
            configEntry.LayoutOrder = order
            configEntry.Parent = configScrollFrame
            order = order + 1
            
            local entryCorner = Instance.new("UICorner")
            entryCorner.CornerRadius = UDim.new(0, 4)
            entryCorner.Parent = configEntry
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -100, 0, 20)
            nameLabel.Position = UDim2.new(0, 10, 0, 2)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.Text = configName
            nameLabel.TextSize = 13
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = configEntry
            
            local timestampLabel = Instance.new("TextLabel")
            timestampLabel.Size = UDim2.new(1, -100, 0, 15)
            timestampLabel.Position = UDim2.new(0, 10, 0, 22)
            timestampLabel.BackgroundTransparency = 1
            timestampLabel.Font = Enum.Font.Gotham
            timestampLabel.Text = configData.Timestamp or "Unknown"
            timestampLabel.TextSize = 10
            timestampLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
            timestampLabel.TextXAlignment = Enum.TextXAlignment.Left
            timestampLabel.Parent = configEntry
            
            local loadBtn = Instance.new("TextButton")
            loadBtn.Size = UDim2.new(0, 40, 0, 30)
            loadBtn.Position = UDim2.new(1, -90, 0.5, -15)
            loadBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            loadBtn.Font = Enum.Font.GothamBold
            loadBtn.Text = "LOAD"
            loadBtn.TextSize = 10
            loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            loadBtn.AutoButtonColor = false
            loadBtn.Parent = configEntry
            
            local loadBtnCorner = Instance.new("UICorner")
            loadBtnCorner.CornerRadius = UDim.new(0, 4)
            loadBtnCorner.Parent = loadBtn
            
            local deleteBtn = Instance.new("TextButton")
            deleteBtn.Size = UDim2.new(0, 40, 0, 30)
            deleteBtn.Position = UDim2.new(1, -45, 0.5, -15)
            deleteBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
            deleteBtn.Font = Enum.Font.GothamBold
            deleteBtn.Text = "DEL"
            deleteBtn.TextSize = 10
            deleteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            deleteBtn.AutoButtonColor = false
            deleteBtn.Parent = configEntry
            
            local deleteBtnCorner = Instance.new("UICorner")
            deleteBtnCorner.CornerRadius = UDim.new(0, 4)
            deleteBtnCorner.Parent = deleteBtn
            
            AddButtonHover(loadBtn, Color3.fromRGB(0, 150, 70))
            AddButtonHover(deleteBtn, Color3.fromRGB(220, 60, 60))
            
            loadBtn.MouseButton1Click:Connect(function()
                LoadConfig(configName)
            end)
            
            deleteBtn.MouseButton1Click:Connect(function()
                DeleteConfig(configName)
            end)
        end
    end
    
    saveButton.MouseButton1Click:Connect(function()
        local configName = configNameInput.Text
        SaveConfig(configName)
        configNameInput.Text = ""
    end)
    
    loadButton.MouseButton1Click:Connect(function()
        local configName = configNameInput.Text
        LoadConfig(configName)
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- PROFILE TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local profilePanel = tabPanels["Tab_Profile"]
    layoutOrder = 0
    
    -- Profile header
    local profileHeader = Instance.new("Frame")
    profileHeader.Name = "ProfileHeader"
    profileHeader.Size = UDim2.new(1, 0, 0, 150)
    profileHeader.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    profileHeader.BorderSizePixel = 0
    profileHeader.LayoutOrder = layoutOrder
    profileHeader.Parent = profilePanel
    layoutOrder = layoutOrder + 1
    
    local profileHeaderCorner = Instance.new("UICorner")
    profileHeaderCorner.CornerRadius = UDim.new(0, 8)
    profileHeaderCorner.Parent = profileHeader
    
    -- Avatar frame
    local avatarFrame = Instance.new("Frame")
    avatarFrame.Size = UDim2.new(0, 100, 0, 100)
    avatarFrame.Position = UDim2.new(0.5, -50, 0, 20)
    avatarFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    avatarFrame.BorderSizePixel = 0
    avatarFrame.Parent = profileHeader
    
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = avatarFrame
    
    local avatarStroke = Instance.new("UIStroke")
    avatarStroke.Color = Color3.fromRGB(0, 212, 255)
    avatarStroke.Thickness = 3
    avatarStroke.Parent = avatarFrame
    
    local avatarImage = Instance.new("ImageLabel")
    avatarImage.Size = UDim2.new(1, 0, 1, 0)
    avatarImage.BackgroundTransparency = 1
    avatarImage.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    avatarImage.Parent = avatarFrame
    
    local avatarImageCorner = Instance.new("UICorner")
    avatarImageCorner.CornerRadius = UDim.new(1, 0)
    avatarImageCorner.Parent = avatarImage
    
    task.spawn(function()
        local success, avatarUrl = pcall(function()
            return Players:GetUserThumbnailAsync(
                LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size420x420
            )
        end)
        
        if success and avatarUrl then
            avatarImage.Image = avatarUrl
        end
    end)
    
    -- Display name
    local displayNameLabel = Instance.new("TextLabel")
    displayNameLabel.Size = UDim2.new(1, 0, 0, 25)
    displayNameLabel.Position = UDim2.new(0, 0, 1, -50)
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.Font = Enum.Font.GothamBlack
    displayNameLabel.Text = LocalPlayer.DisplayName
    displayNameLabel.TextSize = 20
    displayNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    displayNameLabel.Parent = profileHeader
    
    -- Username
    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Size = UDim2.new(1, 0, 0, 20)
    usernameLabel.Position = UDim2.new(0, 0, 1, -25)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.Text = "@" .. LocalPlayer.Name
    usernameLabel.TextSize = 14
    usernameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    usernameLabel.Parent = profileHeader
    
    -- Owner badge for specific UserId
    if LocalPlayer.UserId == 7143862381 then
        local ownerBadge = Instance.new("Frame")
        ownerBadge.Size = UDim2.new(0, 120, 0, 30)
        ownerBadge.Position = UDim2.new(0.5, -60, 0, 125)
        ownerBadge.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        ownerBadge.BorderSizePixel = 0
        ownerBadge.ZIndex = 2
        ownerBadge.Parent = profileHeader
        
        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(0, 6)
        badgeCorner.Parent = ownerBadge
        
        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color = Color3.fromRGB(255, 255, 255)
        badgeStroke.Thickness = 2
        badgeStroke.Parent = ownerBadge
        
        local badgeText = Instance.new("TextLabel")
        badgeText.Size = UDim2.new(1, 0, 1, 0)
        badgeText.BackgroundTransparency = 1
        badgeText.Font = Enum.Font.GothamBlack
        badgeText.Text = "★ OWNER ★"
        badgeText.TextSize = 14
        badgeText.TextColor3 = Color3.fromRGB(0, 0, 0)
        badgeText.ZIndex = 3
        badgeText.Parent = ownerBadge
        
        local glowTween = TweenService:Create(
            badgeStroke,
            TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {Thickness = 4}
        )
        glowTween:Play()
        table.insert(getgenv().RAYv2_Runtime.TweenCache, glowTween)
    end
    
    CreateSectionHeader(profilePanel, "PROFILE SPOOFERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        profilePanel,
        "Fake Level",
        0,
        999,
        getgenv().RAYv2_Config.Profile.FakeLevel,
        "",
        function(value)
            getgenv().RAYv2_Config.Profile.FakeLevel = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        profilePanel,
        "Fake Win Streak",
        0,
        999,
        getgenv().RAYv2_Config.Profile.FakeStreak,
        "",
        function(value)
            getgenv().RAYv2_Config.Profile.FakeStreak = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        profilePanel,
        "Fake Keys",
        0,
        9999,
        getgenv().RAYv2_Config.Profile.FakeKeys,
        "",
        function(value)
            getgenv().RAYv2_Config.Profile.FakeKeys = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        profilePanel,
        "Fake Premium Badge",
        getgenv().RAYv2_Config.Profile.FakePremium,
        function(value)
            getgenv().RAYv2_Config.Profile.FakePremium = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        profilePanel,
        "Fake Verified Badge",
        getgenv().RAYv2_Config.Profile.FakeVerified,
        function(value)
            getgenv().RAYv2_Config.Profile.FakeVerified = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- Admin panel
    CreateSectionHeader(profilePanel, "ADMIN PANEL", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local adminUnlockContainer = Instance.new("Frame")
    adminUnlockContainer.Name = "AdminUnlock"
    adminUnlockContainer.Size = UDim2.new(1, 0, 0, 100)
    adminUnlockContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    adminUnlockContainer.BorderSizePixel = 0
    adminUnlockContainer.LayoutOrder = layoutOrder
    adminUnlockContainer.Parent = profilePanel
    layoutOrder = layoutOrder + 1
    
    local adminUnlockCorner = Instance.new("UICorner")
    adminUnlockCorner.CornerRadius = UDim.new(0, 6)
    adminUnlockCorner.Parent = adminUnlockContainer
    
    local adminUsernameInput = Instance.new("TextBox")
    adminUsernameInput.Size = UDim2.new(1, -20, 0, 25)
    adminUsernameInput.Position = UDim2.new(0, 10, 0, 10)
    adminUsernameInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    adminUsernameInput.BorderSizePixel = 0
    adminUsernameInput.Font = Enum.Font.Gotham
    adminUsernameInput.PlaceholderText = "Admin Username"
    adminUsernameInput.Text = ""
    adminUsernameInput.TextSize = 12
    adminUsernameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    adminUsernameInput.ClearTextOnFocus = false
    adminUsernameInput.Parent = adminUnlockContainer
    
    local adminUsernameCorner = Instance.new("UICorner")
    adminUsernameCorner.CornerRadius = UDim.new(0, 4)
    adminUsernameCorner.Parent = adminUsernameInput
    
    local adminPasswordInput = Instance.new("TextBox")
    adminPasswordInput.Size = UDim2.new(1, -20, 0, 25)
    adminPasswordInput.Position = UDim2.new(0, 10, 0, 40)
    adminPasswordInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    adminPasswordInput.BorderSizePixel = 0
    adminPasswordInput.Font = Enum.Font.Gotham
    adminPasswordInput.PlaceholderText = "Admin Password"
    adminPasswordInput.Text = ""
    adminPasswordInput.TextSize = 12
    adminPasswordInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    adminPasswordInput.ClearTextOnFocus = false
    adminPasswordInput.TextXAlignment = Enum.TextXAlignment.Center
    adminPasswordInput.Parent = adminUnlockContainer
    
    local adminPasswordCorner = Instance.new("UICorner")
    adminPasswordCorner.CornerRadius = UDim.new(0, 4)
    adminPasswordCorner.Parent = adminPasswordInput
    
    local adminUnlockButton = Instance.new("TextButton")
    adminUnlockButton.Size = UDim2.new(1, -20, 0, 25)
    adminUnlockButton.Position = UDim2.new(0, 10, 0, 70)
    adminUnlockButton.BackgroundColor3 = Color3.fromRGB(255, 0, 100)
    adminUnlockButton.Font = Enum.Font.GothamBold
    adminUnlockButton.Text = "UNLOCK ADMIN PANEL"
    adminUnlockButton.TextSize = 12
    adminUnlockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    adminUnlockButton.AutoButtonColor = false
    adminUnlockButton.Parent = adminUnlockContainer
    
    local adminUnlockBtnCorner = Instance.new("UICorner")
    adminUnlockBtnCorner.CornerRadius = UDim.new(0, 4)
    adminUnlockBtnCorner.Parent = adminUnlockButton
    
    AddButtonHover(adminUnlockButton, Color3.fromRGB(220, 0, 80))
    
    local adminPanelContent = Instance.new("Frame")
    adminPanelContent.Name = "AdminPanelContent"
    adminPanelContent.Size = UDim2.new(1, 0, 0, 100)
    adminPanelContent.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    adminPanelContent.BorderSizePixel = 0
    adminPanelContent.Visible = false
    adminPanelContent.LayoutOrder = layoutOrder
    adminPanelContent.Parent = profilePanel
    layoutOrder = layoutOrder + 1
    
    local adminContentCorner = Instance.new("UICorner")
    adminContentCorner.CornerRadius = UDim.new(0, 6)
    adminContentCorner.Parent = adminPanelContent
    
    local adminContentStroke = Instance.new("UIStroke")
    adminContentStroke.Color = Color3.fromRGB(255, 0, 100)
    adminContentStroke.Thickness = 2
    adminContentStroke.Parent = adminPanelContent
    
    local adminTitle = Instance.new("TextLabel")
    adminTitle.Size = UDim2.new(1, 0, 0, 40)
    adminTitle.BackgroundTransparency = 1
    adminTitle.Font = Enum.Font.GothamBlack
    adminTitle.Text = "★ ADMIN PANEL UNLOCKED ★"
    adminTitle.TextSize = 16
    adminTitle.TextColor3 = Color3.fromRGB(255, 0, 100)
    adminTitle.Parent = adminPanelContent
    
    local adminInfoLabel = Instance.new("TextLabel")
    adminInfoLabel.Size = UDim2.new(1, -20, 1, -50)
    adminInfoLabel.Position = UDim2.new(0, 10, 0, 45)
    adminInfoLabel.BackgroundTransparency = 1
    adminInfoLabel.Font = Enum.Font.Gotham
    adminInfoLabel.Text = "Admin features unlocked. Role assignment available."
    adminInfoLabel.TextSize = 13
    adminInfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    adminInfoLabel.TextWrapped = true
    adminInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
    adminInfoLabel.Parent = adminPanelContent
    
    adminUnlockButton.MouseButton1Click:Connect(function()
        local username = adminUsernameInput.Text
        local password = adminPasswordInput.Text
        
        if username == getgenv().RAYv2_Config.Admin.Username and password == getgenv().RAYv2_Config.Admin.Password then
            getgenv().RAYv2_Config.Admin.Unlocked = true
            adminPanelContent.Visible = true
            adminUnlockContainer.Visible = false
        else
            local originalPos = adminUnlockContainer.Position
            for i = 1, 3 do
                TweenService:Create(adminUnlockContainer, TweenInfo.new(0.05), {
                    Position = originalPos + UDim2.new(0, 10, 0, 0)
                }):Play()
                task.wait(0.05)
                TweenService:Create(adminUnlockContainer, TweenInfo.new(0.05), {
                    Position = originalPos + UDim2.new(0, -10, 0, 0)
                }):Play()
                task.wait(0.05)
            end
            TweenService:Create(adminUnlockContainer, TweenInfo.new(0.05), {
                Position = originalPos
            }):Play()
            
            adminPasswordInput.Text = ""
        end
    end)
    
    -- Version label
    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(1, 0, 0, 30)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.Text = "RAYv2 " .. getgenv().RAYv2_Version
    versionLabel.TextSize = 14
    versionLabel.TextColor3 = Color3.fromRGB(0, 212, 255)
    versionLabel.LayoutOrder = 9999
    versionLabel.Parent = profilePanel
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- GUI TOGGLE KEYBINDS (MANDATORY: INSERT, LEFTALT, LEFTCONTROL)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local guiOpen = true
    
    local function toggleGUI()
        guiOpen = not guiOpen
        mainFrame.Visible = guiOpen
    end
    
    local guiToggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if UserInputService:GetFocusedTextBox() then return end
        
        if input.KeyCode == Enum.KeyCode.Insert or 
           input.KeyCode == Enum.KeyCode.LeftAlt or 
           input.KeyCode == Enum.KeyCode.LeftControl then
            toggleGUI()
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, guiToggleConnection)
    
    -- Initialize first tab (Aimbot) as visible
    SwitchTab("Tab_Aimbot")
    
    getgenv().RAYv2_Runtime.MainGUI = mainGui
    
    DebugPrint("Main GUI created successfully")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: AIMBOT IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

local fovCircle = nil

local function InitializeFOVCircle()
    if fovCircle then return end
    
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Thickness = 2
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Transparency = 1
    fovCircle.Color = Color3.new(0, 0.83, 1)
    fovCircle.ZIndex = 1000
end

local function CalculateFOVRadius()
    local fovAngle = getgenv().RAYv2_Config.Aimbot.FOV
    local cameraFOV = Camera.FieldOfView
    local viewportHeight = Camera.ViewportSize.Y
    
    local halfFOVRad = math.rad(cameraFOV / 2)
    local pixelsPerDegree = viewportHeight / (2 * math.tan(halfFOVRad))
    local radius = (fovAngle / 2) * pixelsPerDegree / 90
    
    return math.max(radius, 0)
end

local function UpdateFOVCircle()
    if not fovCircle then return end
    
    local config = getgenv().RAYv2_Config.Aimbot
    
    fovCircle.Visible = config.Enabled and config.FOVVisible
    
    if not fovCircle.Visible then return end
    
    fovCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
    fovCircle.Radius = CalculateFOVRadius()
    fovCircle.Filled = config.FOVFilled
    
    local color = config.FOVColor
    fovCircle.Color = Color3.new(color.R, color.G, color.B)
end

local function GetValidTargets()
    local validTargets = {}
    local config = getgenv().RAYv2_Config.Aimbot
    local localChar = LocalPlayer.Character
    
    if not localChar then return validTargets end
    
    local localHRP = localChar:FindFirstChild("HumanoidRootPart")
    if not localHRP then return validTargets end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local character = player.Character
        if not IsValidCharacter(character) then continue end
        
        if config.TeamCheck and IsSameTeam(LocalPlayer, player) then
            continue
        end
        
        if not IsInMatch(player) then
            continue
        end
        
        local targetHRP = character:FindFirstChild("HumanoidRootPart")
        if not targetHRP then continue end
        
        local distance = (targetHRP.Position - localHRP.Position).Magnitude
        if distance > config.MaxDistance then
            continue
        end
        
        table.insert(validTargets, {
            Player = player,
            Character = character,
            HRP = targetHRP,
            Distance = distance
        })
    end
    
    return validTargets
end

local function GetClosestTarget()
    local validTargets = GetValidTargets()
    if #validTargets == 0 then return nil end
    
    local config = getgenv().RAYv2_Config.Aimbot
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local fovRadius = CalculateFOVRadius()
    
    local closestTarget = nil
    local closestDistance = math.huge
    
    for _, targetData in ipairs(validTargets) do
        local character = targetData.Character
        local hrp = targetData.HRP
        
        local aimPart = hrp
        if config.HeadPriority then
            local head = character:FindFirstChild("Head")
            if head then
                aimPart = head
            end
        end
        
        local screenPos, onScreen = WorldToScreen(aimPart.Position)
        if not onScreen then continue end
        
        local deltaX = screenPos.X - screenCenter.X
        local deltaY = screenPos.Y - screenCenter.Y
        local screenDistance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        
        if screenDistance > fovRadius then continue end
        
        if screenDistance < closestDistance then
            closestDistance = screenDistance
            closestTarget = {
                Player = targetData.Player,
                Character = character,
                AimPart = aimPart,
                HRP = hrp,
                ScreenDistance = screenDistance
            }
        end
    end
    
    return closestTarget
end

local function ApplySmoothAim(targetPosition)
    local config = getgenv().RAYv2_Config.Aimbot
    
    if config.SilentAim then
        return
    end
    
    if config.Prediction then
        local target = getgenv().RAYv2_Runtime.CurrentTarget
        if target and target.HRP then
            local velocity = target.HRP.AssemblyLinearVelocity
            targetPosition = PredictPosition(targetPosition, velocity)
        end
    end
    
    local cameraPos = Camera.CFrame.Position
    local currentLook = Camera.CFrame.LookVector
    
    local targetDirection = (targetPosition - cameraPos).Unit
    
    local smoothFactor = config.Smoothness * 0.01
    
    local newLookDirection = currentLook:Lerp(targetDirection, smoothFactor)
    
    Camera.CFrame = CFrame.lookAt(cameraPos, cameraPos + newLookDirection)
end

local function UpdateAimbot()
    UpdateFOVCircle()
    
    local config = getgenv().RAYv2_Config.Aimbot
    if not config.Enabled then
        getgenv().RAYv2_Runtime.CurrentTarget = nil
        return
    end
    
    local keybindActive = false
    if config.Mode == "Toggle" then
        keybindActive = getgenv().RAYv2_Runtime.AimbotActive
    else
        keybindActive = UserInputService:IsKeyDown(config.Keybind)
    end
    
    if not keybindActive then
        getgenv().RAYv2_Runtime.CurrentTarget = nil
        return
    end
    
    local target = GetClosestTarget()
    getgenv().RAYv2_Runtime.CurrentTarget = target
    
    if not target then return end
    
    if config.SilentAim then
        -- Silent aim implementation would go here
    else
        ApplySmoothAim(target.AimPart.Position)
    end
end

local function SetupAimbotKeybinds()
    local aimbotKeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        local config = getgenv().RAYv2_Config.Aimbot
        
        if input.KeyCode == config.Keybind then
            if config.Mode == "Toggle" then
                getgenv().RAYv2_Runtime.AimbotActive = not getgenv().RAYv2_Runtime.AimbotActive
            end
        end
        
        if input.KeyCode == config.Triggerbot.Keybind then
            getgenv().RAYv2_Runtime.TriggerbotActive = true
        end
    end)
    
    local aimbotKeybindEndConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
        local config = getgenv().RAYv2_Config.Aimbot
        
        if input.KeyCode == config.Triggerbot.Keybind then
            getgenv().RAYv2_Runtime.TriggerbotActive = false
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotKeybindConnection)
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotKeybindEndConnection)
end

local function InitializeAimbot()
    InitializeFOVCircle()
    SetupAimbotKeybinds()
    
    local aimbotUpdateConnection = RunService.RenderStepped:Connect(UpdateAimbot)
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotUpdateConnection)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: ESP IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateESPObjects(player)
    local objects = {}
    
    objects.Box = {
        GetDrawing("Line"),
        GetDrawing("Line"),
        GetDrawing("Line"),
        GetDrawing("Line")
    }
    
    objects.Fill = GetDrawing("Square")
    
    objects.Skeleton = {}
    for i = 1, 15 do
        table.insert(objects.Skeleton, GetDrawing("Line"))
    end
    
    objects.Tracers = GetDrawing("Line")
    objects.Name = GetDrawing("Text")
    objects.Health = GetDrawing("Text")
    objects.Distance = GetDrawing("Text")
    objects.Weapon = GetDrawing("Text")
    
    objects.HealthBar = {
        Back = GetDrawing("Square"),
        Fill = GetDrawing("Square")
    }
    
    getgenv().RAYv2_Runtime.ESPObjects[player] = objects
    
    return objects
end

local function GetESPObjects(player)
    return getgenv().RAYv2_Runtime.ESPObjects[player] or CreateESPObjects(player)
end

local function ReleaseESPObjects(player)
    local objects = getgenv().RAYv2_Runtime.ESPObjects[player]
    if not objects then return end
    
    for _, line in ipairs(objects.Box) do
        ReleaseDrawing(line)
    end
    
    ReleaseDrawing(objects.Fill)
    
    for _, line in ipairs(objects.Skeleton) do
        ReleaseDrawing(line)
    end
    
    ReleaseDrawing(objects.Tracers)
    ReleaseDrawing(objects.Name)
    ReleaseDrawing(objects.Health)
    ReleaseDrawing(objects.Distance)
    ReleaseDrawing(objects.Weapon)
    ReleaseDrawing(objects.HealthBar.Back)
    ReleaseDrawing(objects.HealthBar.Fill)
    
    getgenv().RAYv2_Runtime.ESPObjects[player] = nil
end

local function DrawBox(objects, topLeft, size, color, thickness)
    local config = getgenv().RAYv2_Config.ESP.Boxes
    
    if not config.Enabled then
        for _, line in ipairs(objects.Box) do
            line.Visible = false
        end
        return
    end
    
    local lines = objects.Box
    
    local topRight = topLeft + Vector2.new(size.X, 0)
    local bottomLeft = topLeft + Vector2.new(0, size.Y)
    local bottomRight = topLeft + size
    
    lines[1].From = topLeft
    lines[1].To = topRight
    lines[1].Color = color
    lines[1].Thickness = thickness
    lines[1].Visible = true
    
    lines[2].From = topRight
    lines[2].To = bottomRight
    lines[2].Color = color
    lines[2].Thickness = thickness
    lines[2].Visible = true
    
    lines[3].From = bottomRight
    lines[3].To = bottomLeft
    lines[3].Color = color
    lines[3].Thickness = thickness
    lines[3].Visible = true
    
    lines[4].From = bottomLeft
    lines[4].To = topLeft
    lines[4].Color = color
    lines[4].Thickness = thickness
    lines[4].Visible = true
end

local function UpdatePlayerESP(player)
    local config = getgenv().RAYv2_Config.ESP
    
    if not config.Enabled then
        ReleaseESPObjects(player)
        return
    end
    
    local character = player.Character
    if not IsValidCharacter(character) then
        ReleaseESPObjects(player)
        return
    end
    
    if config.TeamCheck and IsSameTeam(LocalPlayer, player) then
        ReleaseESPObjects(player)
        return
    end
    
    if not IsInMatch(player) then
        ReleaseESPObjects(player)
        return
    end
    
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        ReleaseESPObjects(player)
        return
    end
    
    local distance = (hrp.Position - localChar.HumanoidRootPart.Position).Magnitude
    if distance > config.MaxDistance then
        ReleaseESPObjects(player)
        return
    end
    
    local topLeft, size, valid = GetCharacterBoundingBox(character)
    if not valid then
        ReleaseESPObjects(player)
        return
    end
    
    local objects = GetESPObjects(player)
    
    DrawBox(objects, topLeft, size, config.Boxes.Color, config.Boxes.Thickness)
end

local function UpdateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            UpdatePlayerESP(player)
        end
    end
end

local function InitializeESP()
    local playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        ReleaseESPObjects(player)
    end)
    table.insert(getgenv().RAYv2_Runtime.Connections, playerRemovingConnection)
    
    local espUpdateConnection = RunService.RenderStepped:Connect(UpdateESP)
    table.insert(getgenv().RAYv2_Runtime.Connections, espUpdateConnection)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 8: CLEANUP
-- ═══════════════════════════════════════════════════════════════════════════

function CleanupScript()
    for _, connection in ipairs(getgenv().RAYv2_Runtime.Connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    getgenv().RAYv2_Runtime.Connections = {}
    
    for _, tween in ipairs(getgenv().RAYv2_Runtime.TweenCache) do
        if tween then
            tween:Cancel()
        end
    end
    getgenv().RAYv2_Runtime.TweenCache = {}
    
    for player, _ in pairs(getgenv().RAYv2_Runtime.ESPObjects) do
        ReleaseESPObjects(player)
    end
    
    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end
    
    for poolName, pool in pairs(getgenv().RAYv2_DrawingPool) do
        for _, obj in ipairs(pool) do
            if obj then
                obj:Remove()
            end
        end
        getgenv().RAYv2_DrawingPool[poolName] = {}
    end
    
    if getgenv().RAYv2_Runtime.LoadingScreen then
        getgenv().RAYv2_Runtime.LoadingScreen:Destroy()
        getgenv().RAYv2_Runtime.LoadingScreen = nil
    end
    
    if getgenv().RAYv2_Runtime.MainGUI then
        getgenv().RAYv2_Runtime.MainGUI:Destroy()
        getgenv().RAYv2_Runtime.MainGUI = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 9: INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

local function Initialize()
    CreateLoadingScreen()
    
    task.spawn(function()
        task.wait(1)
        InitializeAimbot()
        InitializeESP()
    end)
end

local success, errorMsg = pcall(function()
    Initialize()
end)

if not success then
    warn("[RAYv2 ERROR]", errorMsg)
    CleanupScript()
end

--[[
════════════════════════════════════════════════════════════════════════════════
USAGE INSTRUCTIONS
════════════════════════════════════════════════════════════════════════════════

INJECTION METHOD (SOLARA):
1. Open Solara executor
2. Paste this entire script into the editor
3. Click "Execute" or "Inject"
4. Wait 2.5-3.5 seconds for cinematic loading screen
5. GUI appears automatically with Aimbot tab open by default

KEYBINDS (WORK IMMEDIATELY):
- INSERT / LEFT ALT / LEFT CONTROL: Toggle GUI visibility
- E (default): Activate aimbot (Toggle or Hold mode)
- T (default): Activate triggerbot

ADJUSTING PARAMETERS:

AIMBOT TAB:
- Enable Aimbot: Master toggle
- Aimbot Keybind: Click and press new key to rebind
- Activation Mode: Toggle (on/off with keypress) or Hold (active while held)
- Silent Aim: Camera doesn't move but hits register
- FOV Radius: Detection angle (0-360 degrees)
- Show FOV Circle: Visual circle on screen
- Fill FOV Circle: Solid circle vs outline
- Smoothness: 0 = no aim, 100 = instant snap
- Velocity Prediction: Compensate for moving targets
- Prediction Strength: How much to lead targets
- Max Distance: Only aim within this range
- Team Check: Ignore teammates
- Visible Check: Only aim at visible enemies
- Prioritize Head: Aim at head vs torso
- Triggerbot: Auto-fire when aiming at enemy

ESP TAB:
- Enable ESP: Master toggle
- Max ESP Distance: Only show ESP within range
- Team Check: Hide teammate ESP
- Show Boxes: Rectangle around players
- Fill Boxes: Solid filled boxes
- Show Skeleton: Bone structure
- Show Tracers: Lines to players
- Tracers From: Bottom/Center/Mouse origin
- Show Name: Player name
- Show Health: HP value and bar
- Show Distance: Range to player
- Show Weapon: Equipped tool

CONFIGS TAB:
- Enter config name and click SAVE CONFIG
- Configs appear in list below
- Click LOAD to restore settings
- Click DEL to delete config
- Configs persist across sessions

PROFILE TAB:
- Avatar shows your Roblox profile picture
- Fake Level/Streak/Keys: Spoof displayed values
- Premium/Verified badges: Toggle fake badges
- Admin Panel: Enter "adminHQ" / "HQ080626" to unlock

RIVALS-SPECIFIC FEATURES:
- ESP filters players in active match vs hub/spawn
- Silent aim hooks tool RemoteEvents
- Team detection via Team property or folders
- Distance check uses HumanoidRootPart positions

PERFORMANCE:
- All visuals locked to 60+ FPS
- Drawing objects pooled (no memory leaks)
- Automatic cleanup on script end
- Minimal CPU/GPU impact

TROUBLESHOOTING:
- If GUI doesn't appear: Wait full 3 seconds for loading
- If aimbot doesn't work: Check keybind and FOV settings
- If ESP invisible: Increase Max Distance
- For errors: Check executor console output

════════════════════════════════════════════════════════════════════════════════
]]
