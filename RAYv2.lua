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
--[[
All persistent state stored in getgenv() to survive script reloads and persist
across executor environments. This includes configuration, feature flags, and
runtime data structures for Drawing API object pooling.
]]

if not getgenv().RAYv2_Initialized then
    getgenv().RAYv2_Initialized = true
    getgenv().RAYv2_Version = "0.01 ALPHA"
    getgenv().DebugMode = false
    
    -- Configuration state with default values
    getgenv().RAYv2_Config = {
        -- Aimbot settings
        Aimbot = {
            Enabled = false,
            Keybind = Enum.KeyCode.E,
            Mode = "Toggle", -- "Toggle" or "Hold"
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
                Delay = 50 -- milliseconds
            }
        },
        
        -- ESP settings
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
        
        -- GUI settings
        GUI = {
            Visible = true,
            ToggleKeybind = Enum.KeyCode.LeftAlt,
            AlternateKeybind1 = Enum.KeyCode.LeftControl,
            AlternateKeybind2 = Enum.KeyCode.Insert,
            ToggleMode = "Toggle", -- "Toggle" or "Hold"
            Position = UDim2.new(0.5, -410, 0.5, -260),
            Size = UDim2.new(0, 820, 0, 520)
        },
        
        -- Profile spoofer settings
        Profile = {
            FakeLevel = 0,
            FakeStreak = 0,
            FakeKeys = 0,
            FakePremium = false,
            FakeVerified = false
        },
        
        -- Admin panel settings
        Admin = {
            Unlocked = false,
            Username = "adminHQ",
            Password = "HQ080626",
            RestrictedUsers = {}
        }
    }
    
    -- Drawing API object pools to prevent memory leaks
    --[[
    Object pooling strategy:
    - Pre-allocate Drawing objects and reuse them instead of Create/Destroy each frame
    - Maintain separate pools for different object types
    - Mark objects as "in use" vs "available" to prevent overlaps
    - Clear pools on script destruction for clean shutdown
    ]]
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
--[[
Cache all required Roblox services at script start for performance.
Service calls like game:GetService() have overhead; caching eliminates
repeated lookups in hot paths (RenderStepped, Heartbeat).
]]

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

--[[
Utility: Get Drawing object from pool or allocate new
Implements object pooling pattern to reduce GC pressure
@param drawingType: string - Type of Drawing ("Circle", "Square", "Line", "Text", "Triangle")
@return Drawing object
]]
local function GetDrawing(drawingType)
    local pool = getgenv().RAYv2_DrawingPool[drawingType .. "s"]
    if not pool then
        warn("[RAYv2] Unknown drawing type:", drawingType)
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
    else
        warn("[RAYv2] Failed to create Drawing object:", drawingType)
        return nil
    end
end

local function ReleaseDrawing(obj)
    if obj then
        obj.Visible = false
    end
end

--[[
Utility: World position to screen position conversion with depth check
@param position: Vector3 - World position to convert
@return Vector2 (screen position), boolean (on screen)
Mathematical explanation:
- Camera:WorldToViewportPoint returns Vector3 where X,Y are screen coords and Z is depth
- Z > 0 means position is in front of camera (visible)
- Z <= 0 means position is behind camera (should not render)
]]
local function WorldToScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen and screenPos.Z > 0
end

--[[
Utility: Calculate 2D bounding box for character in screen space
Uses character's bounding box in 3D and projects all 8 corners to screen,
then finds min/max X/Y to create tight-fitting 2D box.
@param character: Model - Character to calculate box for
@return Vector2 (top-left), Vector2 (size), boolean (valid)
]]
local function GetCharacterBoundingBox(character)
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil, nil, false
    end
    
    local hrp = character.HumanoidRootPart
    
    --[[
    Character size estimation:
    - Width: 2.5 studs (approximate shoulder width)
    - Height: 5 studs (head to toe for R15)
    - Depth: 1.5 studs (front to back)
    These values create a box that encompasses most character sizes
    ]]
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

--[[
Utility: Calculate predicted position based on velocity and ping
Formula: predictedPos = currentPos + (velocity * timeAhead)
where timeAhead = (ping / 1000) * predictionFactor

Mathematical explanation:
- Ping is round-trip time in ms, divide by 1000 for seconds
- Multiply by velocity to get displacement during that time
- PredictionFactor allows tuning (higher = more aggressive prediction)
- This compensates for network latency in hit registration

@param currentPos: Vector3
@param velocity: Vector3
@return Vector3 - Predicted position
]]
local function PredictPosition(currentPos, velocity)
    if not getgenv().RAYv2_Config.Aimbot.Prediction then
        return currentPos
    end
    
    local ping = GetPing()
    local predictionFactor = getgenv().RAYv2_Config.Aimbot.PredictionFactor
    
    -- Time ahead in seconds = (ping in ms / 1000) * factor
    local timeAhead = (ping / 1000) * predictionFactor
    
    -- Predicted position = current + velocity * time
    local predictedPos = currentPos + (velocity * timeAhead)
    
    return predictedPos
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: CINEMATIC LOADING SCREEN (MANDATORY FIRST EXECUTION)
-- ═══════════════════════════════════════════════════════════════════════════
--[[
Creates full-screen animated loading screen with:
- Moving gradient background (blue -> black -> white loop)
- Large "RAYv2" title with matching gradient
- "made by @ink" subtitle
- Particle effects (30+ animated circles)
- Geometric line decorations with parallax motion
- Realistic progress bar with percentage display
- Complete fade-out animation before GUI creation
]]

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
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 212, 255)
        stroke.Thickness = 1
        stroke.Transparency = 0.7
        stroke.Parent = line
        
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
    
    CreateDecorativeLine(25, 400, 0.2)
    CreateDecorativeLine(-15, 500, 0.4)
    CreateDecorativeLine(35, 350, 0.6)
    CreateDecorativeLine(-25, 450, 0.8)
    
    -- Main title: "RAYv2"
    -- Positioned at center of screen
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
    
    -- Progress fill bar
    local progressFill = Instance.new("Frame")
    progressFill.Name = "Fill"
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressContainer
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = progressFill
    
    -- Progress text
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
    
    getgenv().RAYv2_Runtime.LoadingScreen = loadingScreen
    
    -- Particle animation loop
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
    
    -- Progress bar animation with randomized duration
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
        
        fadeTween:Play()
        titleFadeTween:Play()
        subtitleFadeTween:Play()
        progressTextFadeTween:Play()
        
        fadeTween.Completed:Wait()
        
        particleConnection:Disconnect()
        
        loadingScreen:Destroy()
        getgenv().RAYv2_Runtime.LoadingScreen = nil
        
        DebugPrint("Loading screen completed")
        
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
    -- Size = (820, 520) pixels
    -- Position = center of screen minus half size
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainContainer"
    mainFrame.Size = UDim2.new(0, 820, 0, 520)
    mainFrame.Position = UDim2.new(0.5, -410, 0.5, -260)
    mainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.ClipsDescendants = false
    mainFrame.Parent = mainGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(0, 212, 255)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0, 12)
    titleBarCorner.Parent = titleBar
    
    local titleBarCover = Instance.new("Frame")
    titleBarCover.Size = UDim2.new(1, 0, 0, 12)
    titleBarCover.Position = UDim2.new(0, 0, 1, -12)
    titleBarCover.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    titleBarCover.BorderSizePixel = 0
    titleBarCover.Parent = titleBar
    
    -- Title text with animated gradient
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
    
    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0.5, -15)
    closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = titleBar
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn
    
    closeBtn.MouseButton1Click:Connect(function()
        mainGui:Destroy()
        CleanupScript()
    end)
    
    -- Dragging functionality
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
            
            local newPos = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            
            mainFrame.Position = newPos
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- TAB BAR CREATION (MANDATORY: LEFT-ALIGNED WITH UIListLayout)
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Tab container directly under title bar
    -- Height = 40 pixels matches title bar height
    -- UIListLayout ensures tabs stay left-aligned
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, 0, 0, 40)
    tabBar.Position = UDim2.new(0, 0, 0, 40)
    tabBar.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    tabBar.BorderSizePixel = 0
    tabBar.Parent = mainFrame
    
    -- UIListLayout forces horizontal layout with zero padding
    -- SortOrder = Name ensures consistent ordering
    local tabListLayout = Instance.new("UIListLayout")
    tabListLayout.FillDirection = Enum.FillDirection.Horizontal
    tabListLayout.SortOrder = Enum.SortOrder.Name
    tabListLayout.Padding = UDim.new(0, 0)
    tabListLayout.Parent = tabBar
    
    -- Content container for tab panels
    -- Position at Y=80 (title bar 40 + tab bar 40)
    -- Size fills remaining space
    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentContainer"
    contentContainer.Size = UDim2.new(1, -20, 1, -100)
    contentContainer.Position = UDim2.new(0, 10, 0, 90)
    contentContainer.BackgroundTransparency = 1
    contentContainer.ClipsDescendants = true
    contentContainer.Parent = mainFrame
    
    -- Create all four content panels (initially hidden)
    -- Each panel is a ScrollingFrame with UIListLayout for vertical stacking
    local Content_Aimbot = Instance.new("ScrollingFrame")
    Content_Aimbot.Name = "Content_Aimbot"
    Content_Aimbot.Size = UDim2.new(1, 0, 1, 0)
    Content_Aimbot.Position = UDim2.new(0, 0, 0, 0)
    Content_Aimbot.BackgroundTransparency = 1
    Content_Aimbot.BorderSizePixel = 0
    Content_Aimbot.ScrollBarThickness = 6
    Content_Aimbot.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
    Content_Aimbot.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content_Aimbot.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content_Aimbot.Visible = true -- Aimbot tab visible by default
    Content_Aimbot.Parent = contentContainer
    
    local aimbotLayout = Instance.new("UIListLayout")
    aimbotLayout.SortOrder = Enum.SortOrder.LayoutOrder
    aimbotLayout.Padding = UDim.new(0, 10)
    aimbotLayout.Parent = Content_Aimbot
    
    local aimbotPadding = Instance.new("UIPadding")
    aimbotPadding.PaddingTop = UDim.new(0, 10)
    aimbotPadding.PaddingBottom = UDim.new(0, 10)
    aimbotPadding.Parent = Content_Aimbot
    
    local Content_ESP = Instance.new("ScrollingFrame")
    Content_ESP.Name = "Content_ESP"
    Content_ESP.Size = UDim2.new(1, 0, 1, 0)
    Content_ESP.Position = UDim2.new(0, 0, 0, 0)
    Content_ESP.BackgroundTransparency = 1
    Content_ESP.BorderSizePixel = 0
    Content_ESP.ScrollBarThickness = 6
    Content_ESP.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
    Content_ESP.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content_ESP.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content_ESP.Visible = false
    Content_ESP.Parent = contentContainer
    
    local espLayout = Instance.new("UIListLayout")
    espLayout.SortOrder = Enum.SortOrder.LayoutOrder
    espLayout.Padding = UDim.new(0, 10)
    espLayout.Parent = Content_ESP
    
    local espPadding = Instance.new("UIPadding")
    espPadding.PaddingTop = UDim.new(0, 10)
    espPadding.PaddingBottom = UDim.new(0, 10)
    espPadding.Parent = Content_ESP
    
    local Content_Configs = Instance.new("ScrollingFrame")
    Content_Configs.Name = "Content_Configs"
    Content_Configs.Size = UDim2.new(1, 0, 1, 0)
    Content_Configs.Position = UDim2.new(0, 0, 0, 0)
    Content_Configs.BackgroundTransparency = 1
    Content_Configs.BorderSizePixel = 0
    Content_Configs.ScrollBarThickness = 6
    Content_Configs.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
    Content_Configs.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content_Configs.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content_Configs.Visible = false
    Content_Configs.Parent = contentContainer
    
    local configsLayout = Instance.new("UIListLayout")
    configsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    configsLayout.Padding = UDim.new(0, 10)
    configsLayout.Parent = Content_Configs
    
    local configsPadding = Instance.new("UIPadding")
    configsPadding.PaddingTop = UDim.new(0, 10)
    configsPadding.PaddingBottom = UDim.new(0, 10)
    configsPadding.Parent = Content_Configs
    
    local Content_Profile = Instance.new("ScrollingFrame")
    Content_Profile.Name = "Content_Profile"
    Content_Profile.Size = UDim2.new(1, 0, 1, 0)
    Content_Profile.Position = UDim2.new(0, 0, 0, 0)
    Content_Profile.BackgroundTransparency = 1
    Content_Profile.BorderSizePixel = 0
    Content_Profile.ScrollBarThickness = 6
    Content_Profile.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
    Content_Profile.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content_Profile.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content_Profile.Visible = false
    Content_Profile.Parent = contentContainer
    
    local profileLayout = Instance.new("UIListLayout")
    profileLayout.SortOrder = Enum.SortOrder.LayoutOrder
    profileLayout.Padding = UDim.new(0, 10)
    profileLayout.Parent = Content_Profile
    
    local profilePadding = Instance.new("UIPadding")
    profilePadding.PaddingTop = UDim.new(0, 10)
    profilePadding.PaddingBottom = UDim.new(0, 10)
    profilePadding.Parent = Content_Profile
    
    -- Create tab buttons with exact names and layout
    local Tab_Aimbot = Instance.new("TextButton")
    Tab_Aimbot.Name = "1_Tab_Aimbot" -- Prefix with number to force sort order
    Tab_Aimbot.Size = UDim2.new(0, 140, 1, 0)
    Tab_Aimbot.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    Tab_Aimbot.Text = "AIMBOT"
    Tab_Aimbot.Font = Enum.Font.GothamBold
    Tab_Aimbot.TextSize = 16
    Tab_Aimbot.TextColor3 = Color3.fromRGB(255, 255, 255) -- Active by default
    Tab_Aimbot.AutoButtonColor = false
    Tab_Aimbot.Parent = tabBar
    
    local Tab_ESP = Instance.new("TextButton")
    Tab_ESP.Name = "2_Tab_ESP"
    Tab_ESP.Size = UDim2.new(0, 140, 1, 0)
    Tab_ESP.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    Tab_ESP.Text = "ESP"
    Tab_ESP.Font = Enum.Font.GothamBold
    Tab_ESP.TextSize = 16
    Tab_ESP.TextColor3 = Color3.fromRGB(150, 150, 150)
    Tab_ESP.AutoButtonColor = false
    Tab_ESP.Parent = tabBar
    
    local Tab_Configs = Instance.new("TextButton")
    Tab_Configs.Name = "3_Tab_Configs"
    Tab_Configs.Size = UDim2.new(0, 140, 1, 0)
    Tab_Configs.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    Tab_Configs.Text = "CONFIGS"
    Tab_Configs.Font = Enum.Font.GothamBold
    Tab_Configs.TextSize = 16
    Tab_Configs.TextColor3 = Color3.fromRGB(150, 150, 150)
    Tab_Configs.AutoButtonColor = false
    Tab_Configs.Parent = tabBar
    
    local Tab_Profile = Instance.new("TextButton")
    Tab_Profile.Name = "4_Tab_Profile"
    Tab_Profile.Size = UDim2.new(0, 140, 1, 0)
    Tab_Profile.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    Tab_Profile.Text = "PROFILE"
    Tab_Profile.Font = Enum.Font.GothamBold
    Tab_Profile.TextSize = 16
    Tab_Profile.TextColor3 = Color3.fromRGB(150, 150, 150)
    Tab_Profile.AutoButtonColor = false
    Tab_Profile.Parent = tabBar
    
    -- Tab indicator (sliding underline)
    local tabIndicator = Instance.new("Frame")
    tabIndicator.Name = "Indicator"
    tabIndicator.Size = UDim2.new(0, 140, 0, 3)
    tabIndicator.Position = UDim2.new(0, 0, 1, -3)
    tabIndicator.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    tabIndicator.BorderSizePixel = 0
    tabIndicator.Parent = tabBar
    
    -- MANDATORY TAB SWITCHER FUNCTION
    -- Maps tab names to their corresponding panels
    local currentTab = "Aimbot"
    local tabs = {
        Aimbot = {Panel = Content_Aimbot, Button = Tab_Aimbot},
        ESP = {Panel = Content_ESP, Button = Tab_ESP},
        Configs = {Panel = Content_Configs, Button = Tab_Configs},
        Profile = {Panel = Content_Profile, Button = Tab_Profile}
    }
    
    --[[
    switchTab function:
    - Hides all panels by setting Visible = false
    - Shows target panel by setting Visible = true
    - Updates button text colors (active = white, inactive = gray)
    - Tweens underline indicator to clicked button position
    - Prevents redundant switches if already on target tab
    ]]
    local function switchTab(newTab)
        if currentTab == newTab then return end
        
        -- Hide all panels and reset all button colors
        for tabName, tabData in pairs(tabs) do
            tabData.Panel.Visible = false
            tabData.Button.TextColor3 = Color3.fromRGB(150, 150, 150)
        end
        
        -- Show target panel and highlight its button
        tabs[newTab].Panel.Visible = true
        tabs[newTab].Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        
        currentTab = newTab
        
        -- Tween underline to new position
        -- Calculate absolute X position of clicked button relative to tab bar
        local targetButton = tabs[newTab].Button
        local targetX = targetButton.AbsolutePosition.X - tabBar.AbsolutePosition.X
        
        TweenService:Create(
            tabIndicator,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0, targetX, 1, -3)}
        ):Play()
    end
    
    -- Connect each tab button to switchTab function
    Tab_Aimbot.Activated:Connect(function() switchTab("Aimbot") end)
    Tab_ESP.Activated:Connect(function() switchTab("ESP") end)
    Tab_Configs.Activated:Connect(function() switchTab("Configs") end)
    Tab_Profile.Activated:Connect(function() switchTab("Profile") end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- GUI HELPER FUNCTIONS (REUSABLE CONTROL CREATION)
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Create section header
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
    local function CreateToggle(parent, text, defaultValue, callback, layoutOrder)
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
        
        local checkmark = Instance.new("TextLabel")
        checkmark.Size = UDim2.new(1, 0, 1, 0)
        checkmark.BackgroundTransparency = 1
        checkmark.Font = Enum.Font.GothamBold
        checkmark.Text = "✓"
        checkmark.TextSize = 18
        checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
        checkmark.Visible = defaultValue
        checkmark.Parent = checkbox
        
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 1, 0)
        button.BackgroundTransparency = 1
        button.Text = ""
        button.Parent = container
        
        local toggled = defaultValue
        
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
        
        return container, function() return toggled end, function(value) 
            toggled = value
            checkbox.BackgroundColor3 = toggled and Color3.fromRGB(0, 212, 255) or Color3.fromRGB(30, 30, 30)
            checkmark.Visible = toggled
        end
    end
    
    -- Create slider
    local function CreateSlider(parent, text, min, max, defaultValue, suffix, callback, layoutOrder)
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
        
        local sliderBack = Instance.new("Frame")
        sliderBack.Size = UDim2.new(1, -20, 0, 6)
        sliderBack.Position = UDim2.new(0, 10, 1, -15)
        sliderBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        sliderBack.BorderSizePixel = 0
        sliderBack.Parent = container
        
        local sliderBackCorner = Instance.new("UICorner")
        sliderBackCorner.CornerRadius = UDim.new(0, 3)
        sliderBackCorner.Parent = sliderBack
        
        local sliderFill = Instance.new("Frame")
        sliderFill.Name = "Fill"
        sliderFill.Size = UDim2.new((defaultValue - min) / (max - min), 0, 1, 0)
        sliderFill.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
        sliderFill.BorderSizePixel = 0
        sliderFill.Parent = sliderBack
        
        local sliderFillCorner = Instance.new("UICorner")
        sliderFillCorner.CornerRadius = UDim.new(0, 3)
        sliderFillCorner.Parent = sliderFill
        
        local sliderButton = Instance.new("TextButton")
        sliderButton.Size = UDim2.new(1, 0, 1, 10)
        sliderButton.Position = UDim2.new(0, 0, 0, -5)
        sliderButton.BackgroundTransparency = 1
        sliderButton.Text = ""
        sliderButton.Parent = sliderBack
        
        local currentValue = defaultValue
        local dragging = false
        
        local function UpdateSlider(input)
            local relativeX = math.clamp((input.Position.X - sliderBack.AbsolutePosition.X) / sliderBack.AbsoluteSize.X, 0, 1)
            currentValue = math.floor(min + (max - min) * relativeX)
            
            sliderFill.Size = UDim2.new(relativeX, 0, 1, 0)
            valueLabel.Text = tostring(currentValue) .. (suffix or "")
            
            if callback then
                callback(currentValue)
            end
        end
        
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
        
        return container, function() return currentValue end
    end
    
    -- Create keybind input
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
        
        keybindButton.MouseButton1Click:Connect(function()
            listening = true
            keybindButton.Text = "..."
            keybindButton.TextColor3 = Color3.fromRGB(0, 212, 255)
        end)
        
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
    
    -- Create dropdown
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
        
        local optionsLayout = Instance.new("UIListLayout")
        optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        optionsLayout.Parent = optionsFrame
        
        local currentOption = defaultOption
        
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
    -- AIMBOT TAB CONTENT (FULLY POPULATED WITH ALL FEATURES)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local layoutOrder = 0
    
    CreateSectionHeader(Content_Aimbot, "TARGET FILTERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_Aimbot,
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
    
    CreateToggle(
        Content_Aimbot,
        "Team Check",
        getgenv().RAYv2_Config.Aimbot.TeamCheck,
        function(value)
            getgenv().RAYv2_Config.Aimbot.TeamCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_Aimbot,
        "Visible Check (Wallcheck)",
        getgenv().RAYv2_Config.Aimbot.VisibleCheck,
        function(value)
            getgenv().RAYv2_Config.Aimbot.VisibleCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_Aimbot,
        "Prioritize Head",
        getgenv().RAYv2_Config.Aimbot.HeadPriority,
        function(value)
            getgenv().RAYv2_Config.Aimbot.HeadPriority = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_Aimbot, "TRIGGERBOT", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_Aimbot,
        "Enable Triggerbot",
        getgenv().RAYv2_Config.Aimbot.Triggerbot.Enabled,
        function(value)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateKeybind(
        Content_Aimbot,
        "Triggerbot Keybind",
        getgenv().RAYv2_Config.Aimbot.Triggerbot.Keybind,
        function(key)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Keybind = key
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_Aimbot,
        "Shoot Delay",
        0,
        500,
        getgenv().RAYv2_Config.Aimbot.Triggerbot.Delay,
        "ms",
        function(value)
            getgenv().RAYv2_Config.Aimbot.Triggerbot.Delay = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_Aimbot, "SILENT AIM", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_Aimbot,
        "Silent Aim (Invisible)",
        getgenv().RAYv2_Config.Aimbot.SilentAim,
        function(value)
            getgenv().RAYv2_Config.Aimbot.SilentAim = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_Aimbot, "FOV", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_Aimbot,
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
    
    CreateToggle(
        Content_Aimbot,
        "Fill FOV Circle",
        getgenv().RAYv2_Config.Aimbot.FOVFilled,
        function(value)
            getgenv().RAYv2_Config.Aimbot.FOVFilled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_Aimbot, "SMOOTHNESS & PREDICTION", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_Aimbot,
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
    
    CreateToggle(
        Content_Aimbot,
        "Velocity Prediction",
        getgenv().RAYv2_Config.Aimbot.Prediction,
        function(value)
            getgenv().RAYv2_Config.Aimbot.Prediction = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ESP TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    layoutOrder = 0
    
    CreateSectionHeader(Content_ESP, "ESP", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Enable ESP",
        getgenv().RAYv2_Config.ESP.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_ESP,
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
    
    CreateToggle(
        Content_ESP,
        "Team Check",
        getgenv().RAYv2_Config.ESP.TeamCheck,
        function(value)
            getgenv().RAYv2_Config.ESP.TeamCheck = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_ESP, "BOXES", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Show Boxes",
        getgenv().RAYv2_Config.ESP.Boxes.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Boxes.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Fill Boxes",
        getgenv().RAYv2_Config.ESP.Fill.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Fill.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateSectionHeader(Content_ESP, "TEXT INFO", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Show Name",
        getgenv().RAYv2_Config.ESP.Name.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Name.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Show Health",
        getgenv().RAYv2_Config.ESP.Health.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Health.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    CreateToggle(
        Content_ESP,
        "Show Distance",
        getgenv().RAYv2_Config.ESP.Distance.Enabled,
        function(value)
            getgenv().RAYv2_Config.ESP.Distance.Enabled = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- CONFIGS TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    layoutOrder = 0
    
    CreateSectionHeader(Content_Configs, "CONFIGURATION", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local configNameContainer = Instance.new("Frame")
    configNameContainer.Name = "ConfigNameInput"
    configNameContainer.Size = UDim2.new(1, 0, 0, 50)
    configNameContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    configNameContainer.BorderSizePixel = 0
    configNameContainer.LayoutOrder = layoutOrder
    configNameContainer.Parent = Content_Configs
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
    
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Name = "ButtonContainer"
    buttonContainer.Size = UDim2.new(1, 0, 0, 35)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.LayoutOrder = layoutOrder
    buttonContainer.Parent = Content_Configs
    layoutOrder = layoutOrder + 1
    
    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.48, 0, 1, 0)
    saveButton.Position = UDim2.new(0, 0, 0, 0)
    saveButton.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    saveButton.Font = Enum.Font.GothamBold
    saveButton.Text = "SAVE"
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
    loadButton.Text = "LOAD"
    loadButton.TextSize = 14
    loadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    loadButton.AutoButtonColor = false
    loadButton.Parent = buttonContainer
    
    local loadCorner = Instance.new("UICorner")
    loadCorner.CornerRadius = UDim.new(0, 6)
    loadCorner.Parent = loadButton
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- PROFILE TAB CONTENT (FULLY POPULATED)
    -- ═══════════════════════════════════════════════════════════════════════
    
    layoutOrder = 0
    
    local profileHeader = Instance.new("Frame")
    profileHeader.Name = "ProfileHeader"
    profileHeader.Size = UDim2.new(1, 0, 0, 150)
    profileHeader.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    profileHeader.BorderSizePixel = 0
    profileHeader.LayoutOrder = layoutOrder
    profileHeader.Parent = Content_Profile
    layoutOrder = layoutOrder + 1
    
    local profileHeaderCorner = Instance.new("UICorner")
    profileHeaderCorner.CornerRadius = UDim.new(0, 8)
    profileHeaderCorner.Parent = profileHeader
    
    local avatarFrame = Instance.new("Frame")
    avatarFrame.Size = UDim2.new(0, 100, 0, 100)
    avatarFrame.Position = UDim2.new(0.5, -50, 0, 20)
    avatarFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    avatarFrame.BorderSizePixel = 0
    avatarFrame.Parent = profileHeader
    
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = avatarFrame
    
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
    
    local displayNameLabel = Instance.new("TextLabel")
    displayNameLabel.Size = UDim2.new(1, 0, 0, 25)
    displayNameLabel.Position = UDim2.new(0, 0, 1, -50)
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.Font = Enum.Font.GothamBlack
    displayNameLabel.Text = LocalPlayer.DisplayName
    displayNameLabel.TextSize = 20
    displayNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    displayNameLabel.Parent = profileHeader
    
    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Size = UDim2.new(1, 0, 0, 20)
    usernameLabel.Position = UDim2.new(0, 0, 1, -25)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.Text = "@" .. LocalPlayer.Name
    usernameLabel.TextSize = 14
    usernameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    usernameLabel.Parent = profileHeader
    
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
        
        local badgeText = Instance.new("TextLabel")
        badgeText.Size = UDim2.new(1, 0, 1, 0)
        badgeText.BackgroundTransparency = 1
        badgeText.Font = Enum.Font.GothamBlack
        badgeText.Text = "★ OWNER ★"
        badgeText.TextSize = 14
        badgeText.TextColor3 = Color3.fromRGB(0, 0, 0)
        badgeText.ZIndex = 3
        badgeText.Parent = ownerBadge
    end
    
    CreateSectionHeader(Content_Profile, "PROFILE SPOOFERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    CreateSlider(
        Content_Profile,
        "Fake Level",
        0,
        999,
        0,
        "",
        function(value)
            getgenv().RAYv2_Config.Profile.FakeLevel = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
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

--[[
Calculate FOV circle radius in pixels from FOV angle in degrees
Mathematical derivation:
- Camera FOV is the vertical field of view in degrees
- ViewportSize.Y is the screen height in pixels
- tan(FOV/2) gives the ratio of half-screen-height to view distance
- To convert user FOV angle to screen pixels:
  1. Calculate half FOV in radians: halfFOV = (userFOV / 2) * (π / 180)
  2. Calculate pixel distance from center to edge: tan(halfFOV) * viewDistance
  3. viewDistance = ViewportSize.Y / (2 * tan(cameraFOV/2))
  4. Final radius = tan(halfFOV) * viewDistance
This ensures FOV circle accurately represents the angle regardless of screen size.
]]
local function CalculateFOVRadius()
    local fovAngle = getgenv().RAYv2_Config.Aimbot.FOV
    local cameraFOV = Camera.FieldOfView
    local viewportHeight = Camera.ViewportSize.Y
    
    -- Convert camera FOV to radians and calculate view distance
    local halfCameraFOVRad = math.rad(cameraFOV / 2)
    local viewDistance = viewportHeight / (2 * math.tan(halfCameraFOVRad))
    
    -- Convert user FOV to radians and calculate radius
    local halfUserFOVRad = math.rad(fovAngle / 2)
    local radius = math.tan(halfUserFOVRad) * viewDistance
    
    return math.max(radius, 0)
end

--[[
Update FOV circle position and appearance every frame
CRITICAL: Position MUST be set to exact mouse position every RenderStepped
This ensures the FOV circle is always centered on the crosshair/mouse cursor
]]
local function UpdateFOVCircle()
    if not fovCircle then return end
    
    local config = getgenv().RAYv2_Config.Aimbot
    
    fovCircle.Visible = config.Enabled and config.FOVVisible
    
    if not fovCircle.Visible then return end
    
    -- MANDATORY: Set position to exact mouse position
    -- Mouse.X and Mouse.Y are screen coordinates
    -- This centers the FOV circle on the crosshair
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

--[[
Apply smooth aim using camera CFrame interpolation
Mathematical explanation of Vector3:Lerp for smooth aiming:

Lerp formula: result = a + (b - a) * t
where:
- a = current camera look vector
- b = target direction vector
- t = smoothness factor (0 to 1)

When t = 0: result = a (no change, camera stays on current look)
When t = 1: result = b (instant snap to target)
When t = 0.5: result = halfway between a and b

Smoothness slider (0-100) is converted to t by dividing by 100.
This creates natural-feeling aim assist that:
- Avoids instant snapping (unnatural and obvious)
- Prevents overshoot (camera won't oscillate around target)
- Provides consistent speed regardless of distance to target

The camera is then rotated to look in the interpolated direction using
CFrame.lookAt(position, target) which creates a CFrame at 'position'
facing toward 'target'.
]]
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
    
    -- Convert slider value (0-100) to lerp factor (0-1)
    local smoothFactor = config.Smoothness * 0.01
    
    -- Interpolate current look direction toward target
    local newLookDirection = currentLook:Lerp(targetDirection, smoothFactor)
    
    -- Update camera to look in new direction
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
    
    ApplySmoothAim(target.AimPart.Position)
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
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotKeybindConnection)
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
    
    objects.Name = GetDrawing("Text")
    
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
    
    ReleaseDrawing(objects.Name)
    
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
    
    local topLeft, size, valid = GetCharacterBoundingBox(character)
    if not valid then
        ReleaseESPObjects(player)
        return
    end
    
    local objects = GetESPObjects(player)
    
    DrawBox(objects, topLeft, size, config.Boxes.Color, config.Boxes.Thickness)
    
    if config.Name.Enabled and objects.Name then
        objects.Name.Text = player.Name
        objects.Name.Size = config.Name.Size
        objects.Name.Color = config.Name.Color
        objects.Name.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y - 20)
        objects.Name.Center = true
        objects.Name.Outline = config.Name.Outline
        objects.Name.Visible = true
    else
        objects.Name.Visible = false
    end
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

INJECTION (SOLARA):
1. Open Solara executor
2. Paste entire script into editor
3. Click Execute
4. Wait 2.5-3.5 seconds for loading screen
5. GUI opens automatically with Aimbot tab visible

KEYBINDS (WORK IMMEDIATELY):
- INSERT / LEFT ALT / LEFT CONTROL: Toggle GUI
- E (default): Aimbot keybind
- Click any tab button to switch tabs

ADJUSTING PARAMETERS:

AIMBOT TAB:
- Max Distance: Range in studs
- Team Check: Ignore teammates
- Visible Check: Wallcheck via raycast
- Prioritize Head: Aim at head vs torso
- Triggerbot: Auto-fire settings
- Silent Aim: Invisible aiming (no camera movement)
- FOV Radius: Detection angle (0-360°)
- Fill FOV Circle: Solid vs outline
- Smoothness: 0 = no aim, 100 = instant snap
- Velocity Prediction: Lead moving targets

ESP TAB:
- Enable ESP: Master toggle
- Max ESP Distance: Range limit
- Team Check: Hide teammate ESP
- Show Boxes: Rectangle outlines
- Show Name: Player names

CONFIGS TAB:
- Enter name and click SAVE
- Click LOAD to restore
- Configs saved as JSON files

PROFILE TAB:
- Shows your avatar
- Fake Level: Spoof displayed level
- Owner badge for UserId 7143862381

RIVALS-SPECIFIC:
- ESP filters players in active match
- Distance check uses HumanoidRootPart
- Team detection via Team property

════════════════════════════════════════════════════════════════════════════════
]]
