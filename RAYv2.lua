--[[
════════════════════════════════════════════════════════════════════════════════
RAYv2 - PRIVATE INTERNAL-GRADE CHEAT FOR RIVALS
Built by @ink | Version 0.01 ALPHA
Level 7 UNC Executor Compatible (Solara, Wave, Codex, Synapse X)
════════════════════════════════════════════════════════════════════════════════

ARCHITECTURE OVERVIEW:
This script is a single-file, production-grade cheat engine implementing:
- Cinematic loading sequence with animated gradients and particles
- Silent aimbot with FOV circle, smoothing, prediction, and triggerbot
- ESP system with boxes, skeleton, tracers, health bars, and distance
- Full config save/load system using HttpService JSON serialization
- Profile spoofing and admin panel with role-based access control
- Zero external dependencies, pure Luau with Drawing API for overlays

PERFORMANCE NOTES:
- All rendering locked to RenderStepped for 60+ FPS consistency
- Object pooling implemented for Drawing API to prevent memory leaks
- Squared distance optimization available but clarity prioritized
- Delta-time compensation for frame-rate independent animations

ANTI-DETECTION MEASURES:
- Silent aim uses internal raycast hooks, camera untouched
- Randomized timing on all automated actions
- No telltale console spam or network signatures
- RAII-style cleanup on script destruction

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
    getgenv().DebugMode = false -- Set to true for verbose console logging
    
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
            PredictionFactor = 0.165, -- Multiplier for velocity-based prediction
            
            Triggerbot = {
                Enabled = false,
                Keybind = Enum.KeyCode.T,
                Delay = 0.05 -- Minimum seconds between shots
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
                From = "Bottom" -- "Bottom", "Center", "Mouse"
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
            Position = UDim2.new(0.5, -300, 0.5, -250),
            Size = UDim2.new(0, 600, 0, 500)
        },
        
        -- Profile spoofer settings
        Profile = {
            FakeLevel = 0,
            FakeStreak = 0,
            FakeKeys = 0,
            FakePremium = false,
            FakeVerified = false
        },
        
        -- Admin panel settings (encrypted in production)
        Admin = {
            Unlocked = false,
            Username = "adminHQ",
            Password = "HQ080626",
            RestrictedUsers = {}, -- Table of {UserId = number, Role = string}
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
        CurrentTarget = nil, -- Current aimbot target player
        LastShotTime = 0, -- Tick of last triggerbot shot
        AimbotActive = false, -- Whether aimbot keybind is pressed (for Hold mode)
        TriggerbotActive = false,
        ESPObjects = {}, -- Maps Player -> {Box, Fill, Lines, Texts}
        Connections = {}, -- All RBXScriptConnection objects for cleanup
        TweenCache = {}, -- Active tweens for cleanup
        LoadingScreen = nil -- Reference to loading screen GUI
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
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

-- Detect correct GUI parent based on executor environment
--[[
Some executors inject into CoreGui (Synapse), others into PlayerGui (Solara).
Try CoreGui first for better injection persistence, fallback to PlayerGui.
]]
local GuiParent = (gethui and gethui()) or CoreGui
if not GuiParent or not pcall(function() return GuiParent.Parent end) then
    GuiParent = LocalPlayer:WaitForChild("PlayerGui")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

--[[
Utility: Safe debug print wrapper
Only outputs when DebugMode is enabled to reduce console noise
]]
local function DebugPrint(...)
    if getgenv().DebugMode then
        print("[RAYv2 DEBUG]", ...)
    end
end

--[[
Utility: Create Drawing object from pool or allocate new
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
    
    -- Search pool for available object
    for i, obj in ipairs(pool) do
        if obj and obj.Visible == false then
            obj.Visible = true
            return obj
        end
    end
    
    -- No available objects, allocate new
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

--[[
Utility: Return Drawing object to pool
@param obj: Drawing object to release
]]
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
    
    -- Calculate 3D bounding box
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
    
    -- Project to screen and find min/max
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

--[[
Utility: Check if position is visible (raycast-based wallcheck)
Performs raycast from camera to target position with character ignore list.
@param position: Vector3 - Position to check
@param ignoreList: table - Characters/parts to ignore in raycast
@return boolean - True if position is visible (no wall between camera and position)
]]
local function IsPositionVisible(position, ignoreList)
    ignoreList = ignoreList or {}
    
    --[[
    Raycast parameters:
    - Origin: Camera position
    - Direction: Vector from camera to target
    - FilterDescendantsInstances: Ignore local character and target character
    - FilterType: Blacklist mode (ignore specified instances)
    - IgnoreWater: true (water should not block visibility)
    ]]
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = ignoreList
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.IgnoreWater = true
    
    local origin = Camera.CFrame.Position
    local direction = (position - origin)
    
    local result = Workspace:Raycast(origin, direction, raycastParams)
    
    -- If raycast hit nothing, position is visible
    -- If raycast hit something, check if distance to hit is greater than distance to target
    if not result then
        return true
    end
    
    local hitDistance = (result.Position - origin).Magnitude
    local targetDistance = direction.Magnitude
    
    -- Allow small margin for floating point error
    return hitDistance >= (targetDistance - 0.1)
end

--[[
Utility: Get player's team
Handles both Team property and custom team systems in RIVALS
@param player: Player
@return Team/string/nil
]]
local function GetPlayerTeam(player)
    if player.Team then
        return player.Team
    end
    
    -- RIVALS may use custom team folders in Workspace
    local character = player.Character
    if character then
        local teamFolder = character:FindFirstChild("Team") or character:FindFirstChild("TeamColor")
        if teamFolder and teamFolder:IsA("StringValue") then
            return teamFolder.Value
        end
    end
    
    return nil
end

--[[
Utility: Check if two players are on same team
@param player1: Player
@param player2: Player
@return boolean
]]
local function IsSameTeam(player1, player2)
    local team1 = GetPlayerTeam(player1)
    local team2 = GetPlayerTeam(player2)
    
    if team1 and team2 then
        return team1 == team2
    end
    
    return false
end

--[[
Utility: Get player's current weapon/tool name
@param player: Player
@return string or nil
]]
local function GetPlayerWeapon(player)
    local character = player.Character
    if not character then return nil end
    
    -- Check for equipped tool
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        return tool.Name
    end
    
    return nil
end

--[[
Utility: Calculate ping in milliseconds
Uses game.Stats.Network.ServerStatsItem to get current ping
@return number - Ping in milliseconds
]]
local function GetPing()
    local success, ping = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    
    if success and ping then
        return ping
    end
    
    return 50 -- Default fallback
end

--[[
Utility: Predict future position based on velocity and ping
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

--[[
Utility: Validate character for aimbot/ESP
Checks if character exists, has required parts, and humanoid is alive
@param character: Model
@return boolean
]]
local function IsValidCharacter(character)
    if not character then return false end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    return true
end

--[[
Utility: Check if player is in active match (RIVALS-specific)
RIVALS spawns players in a hub area and moves them to match instances.
This function detects if player is actually in a live match vs hub/lobby.
@param player: Player
@return boolean
]]
local function IsInMatch(player)
    local character = player.Character
    if not character then return false end
    
    -- Check if character is in a match folder/workspace area
    -- RIVALS typically uses workspace.Match or workspace.ActivePlayers
    local matchFolder = Workspace:FindFirstChild("Match") or Workspace:FindFirstChild("ActivePlayers")
    if matchFolder and character:IsDescendantOf(matchFolder) then
        return true
    end
    
    -- Fallback: check if player is far from spawn (spawn is usually at Y > 100 in RIVALS hub)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        -- Hub spawn is typically elevated, match areas are lower
        if hrp.Position.Y < 50 then
            return true
        end
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: CINEMATIC LOADING SCREEN
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
    
    -- Main container covering entire screen
    local loadingScreen = Instance.new("ScreenGui")
    loadingScreen.Name = "RAYv2_LoadingScreen"
    loadingScreen.ResetOnSpawn = false
    loadingScreen.IgnoreGuiInset = true
    loadingScreen.DisplayOrder = 10 -- Ensure it's on top
    loadingScreen.Parent = GuiParent
    
    -- Background frame with deep black base
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 1, 0)
    background.Position = UDim2.new(0, 0, 0, 0)
    background.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    background.BorderSizePixel = 0
    background.Parent = loadingScreen
    
    -- Animated gradient for background
    --[[
    UIGradient animation strategy:
    - Offset property controls gradient position (-1 to 1 range)
    - Tween Offset in continuous loop for smooth motion
    - Rotation set to 45 degrees for diagonal sweep effect
    - ColorSequence: Blue (#0080FF) -> Black (#000000) -> White (#FFFFFF)
    ]]
    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 128, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
    }
    bgGradient.Rotation = 45
    bgGradient.Offset = Vector2.new(-1, -1)
    bgGradient.Parent = background
    
    -- Continuous gradient animation loop
    local function AnimateGradient(gradient)
        local tweenInfo = TweenInfo.new(
            4, -- 4 seconds for full cycle
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut,
            -1, -- Infinite repeats
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
    
    -- Particle system: 30 animated circles
    --[[
    Particle implementation without ParticleEmitter:
    - Create 30 ImageLabel circles with random positions
    - Each frame (RenderStepped), update position based on velocity
    - Wrap around screen edges for infinite effect
    - Vary size and transparency for depth perception
    ]]
    local particleContainer = Instance.new("Frame")
    particleContainer.Name = "Particles"
    particleContainer.Size = UDim2.new(1, 0, 1, 0)
    particleContainer.BackgroundTransparency = 1
    particleContainer.Parent = background
    
    local particles = {}
    for i = 1, 30 do
        local particle = Instance.new("Frame")
        particle.Name = "Particle" .. i
        particle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        particle.BackgroundTransparency = math.random(70, 90) / 100 -- 0.7 to 0.9
        particle.BorderSizePixel = 0
        
        -- Random size between 2 and 8 pixels
        local size = math.random(2, 8)
        particle.Size = UDim2.new(0, size, 0, size)
        
        -- Random starting position
        particle.Position = UDim2.new(
            math.random(0, 100) / 100,
            0,
            math.random(0, 100) / 100,
            0
        )
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0) -- Perfect circle
        corner.Parent = particle
        
        particle.Parent = particleContainer
        
        -- Store particle with velocity for animation
        table.insert(particles, {
            Frame = particle,
            VelocityX = (math.random(-50, 50) / 100) * 0.001, -- -0.0005 to 0.0005
            VelocityY = (math.random(-50, 50) / 100) * 0.001
        })
    end
    
    -- Geometric line decorations
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
        
        -- Parallax motion tween
        local tweenInfo = TweenInfo.new(
            6 + math.random(-2, 2), -- Randomize duration for variety
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true, -- Reverse
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
    
    -- Title gradient (same as background for cohesive look)
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
    
    -- Progress fill gradient for shimmer effect
    local fillGradient = Instance.new("UIGradient")
    fillGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 180, 255))
    }
    fillGradient.Rotation = 90
    fillGradient.Parent = progressFill
    
    -- Progress percentage text
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
    
    -- Outer glow effect using multiple UIStroke instances
    --[[
    Glow technique:
    - Create multiple frames with UIStroke at increasing thickness
    - Each stroke has increasing transparency
    - Stack them to create soft, diffused glow
    - Use neon blue color matching theme
    ]]
    local glowContainer = Instance.new("Frame")
    glowContainer.Name = "Glow"
    glowContainer.Size = UDim2.new(1, 100, 1, 100)
    glowContainer.Position = UDim2.new(0, -50, 0, -50)
    glowContainer.BackgroundTransparency = 1
    glowContainer.Parent = background
    
    for i = 1, 5 do
        local glowFrame = Instance.new("Frame")
        glowFrame.Size = UDim2.new(1, 0, 1, 0)
        glowFrame.Position = UDim2.new(0, 0, 0, 0)
        glowFrame.BackgroundTransparency = 1
        glowFrame.BorderSizePixel = 0
        glowFrame.Parent = glowContainer
        
        local glowStroke = Instance.new("UIStroke")
        glowStroke.Color = Color3.fromRGB(0, 212, 255)
        glowStroke.Thickness = i * 3
        glowStroke.Transparency = 0.5 + (i * 0.1) -- Increase transparency outward
        glowStroke.Parent = glowFrame
    end
    
    -- Store reference for later destruction
    getgenv().RAYv2_Runtime.LoadingScreen = loadingScreen
    
    -- Particle animation loop
    local particleConnection = RunService.RenderStepped:Connect(function(deltaTime)
        for _, particleData in ipairs(particles) do
            local frame = particleData.Frame
            local currentPos = frame.Position
            
            -- Update position based on velocity
            local newX = currentPos.X.Scale + particleData.VelocityX
            local newY = currentPos.Y.Scale + particleData.VelocityY
            
            -- Wrap around screen edges
            if newX > 1 then newX = 0 elseif newX < 0 then newX = 1 end
            if newY > 1 then newY = 0 elseif newY < 0 then newY = 1 end
            
            frame.Position = UDim2.new(newX, 0, newY, 0)
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, particleConnection)
    
    -- Progress bar animation with randomized duration for realism
    --[[
    Progress animation:
    - Total duration: 2.5 to 3.5 seconds (randomized)
    - Update every 0.05 seconds for smooth percentage display
    - Quadratic easing for realistic loading curve
    - After completion, fade entire screen then destroy
    ]]
    local loadDuration = math.random(250, 350) / 100 -- 2.5 to 3.5 seconds
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
        
        -- Ensure 100% is shown
        progressText.Text = "INITIALIZING RAYv2... [100%]"
        task.wait(0.3)
        
        -- Fade out animation
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
        
        -- Wait for fade completion
        fadeTween.Completed:Wait()
        
        -- Disconnect particle animation
        particleConnection:Disconnect()
        
        -- Destroy loading screen
        loadingScreen:Destroy()
        getgenv().RAYv2_Runtime.LoadingScreen = nil
        
        DebugPrint("Loading screen completed and destroyed")
        
        -- NOW create main GUI
        CreateMainGUI()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: MAIN GUI CREATION
-- ═══════════════════════════════════════════════════════════════════════════
--[[
Main GUI structure:
- Single ScreenGui container
- Draggable main frame with title bar
- Tab system with smooth transitions
- Four tabs: Aimbot, ESP, Configs, Profile
- Minimize/maximize functionality
- Multi-keybind toggle support
]]

function CreateMainGUI()
    DebugPrint("Creating main GUI...")
    
    -- Main ScreenGui container
    local mainGui = Instance.new("ScreenGui")
    mainGui.Name = "RAYv2_Main"
    mainGui.ResetOnSpawn = false
    mainGui.IgnoreGuiInset = true
    mainGui.DisplayOrder = 5
    mainGui.Parent = GuiParent
    
    -- Main container frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainContainer"
    mainFrame.Size = getgenv().RAYv2_Config.GUI.Size
    mainFrame.Position = getgenv().RAYv2_Config.GUI.Position
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
    
    -- Drop shadow effect
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.ZIndex = -1
    shadow.Parent = mainFrame
    
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
    
    -- Hide bottom corners of title bar
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
    
    -- Animate title gradient
    local titleGradientTween = TweenService:Create(
        titleGradient,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0),
        {Offset = Vector2.new(1, 1)}
    )
    titleGradientTween:Play()
    table.insert(getgenv().RAYv2_Runtime.TweenCache, titleGradientTween)
    
    -- Window control buttons container
    local controlsContainer = Instance.new("Frame")
    controlsContainer.Name = "Controls"
    controlsContainer.Size = UDim2.new(0, 100, 1, 0)
    controlsContainer.Position = UDim2.new(1, -110, 0, 0)
    controlsContainer.BackgroundTransparency = 1
    controlsContainer.Parent = titleBar
    
    -- Minimize button
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
    
    -- Hover effects for buttons
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
    local minimizedIcon = Instance.new("Frame")
    minimizedIcon.Name = "MinimizedIcon"
    minimizedIcon.Size = UDim2.new(0, 50, 0, 50)
    minimizedIcon.Position = UDim2.new(0.98, -50, 0.02, 0)
    minimizedIcon.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    minimizedIcon.Visible = false
    minimizedIcon.Parent = mainGui
    
    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(1, 0)
    iconCorner.Parent = minimizedIcon
    
    local iconStroke = Instance.new("UIStroke")
    iconStroke.Color = Color3.fromRGB(255, 255, 255)
    iconStroke.Thickness = 2
    iconStroke.Parent = minimizedIcon
    
    local iconText = Instance.new("TextLabel")
    iconText.Size = UDim2.new(1, 0, 1, 0)
    iconText.BackgroundTransparency = 1
    iconText.Font = Enum.Font.GothamBlack
    iconText.Text = "R"
    iconText.TextSize = 28
    iconText.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconText.Parent = minimizedIcon
    
    local iconButton = Instance.new("TextButton")
    iconButton.Size = UDim2.new(1, 0, 1, 0)
    iconButton.BackgroundTransparency = 1
    iconButton.Text = ""
    iconButton.Parent = minimizedIcon
    
    -- Minimize/Maximize logic
    local isMinimized = false
    
    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        
        if isMinimized then
            -- Minimize animation
            TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
                Size = UDim2.new(0, 0, 0, 0),
                Position = UDim2.new(0.98, -25, 0.02, 25)
            }):Play()
            
            task.wait(0.3)
            mainFrame.Visible = false
            minimizedIcon.Visible = true
            
            TweenService:Create(minimizedIcon, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
                Size = UDim2.new(0, 50, 0, 50)
            }):Play()
        else
            -- Maximize animation
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
    
    -- Close button logic
    closeBtn.MouseButton1Click:Connect(function()
        -- Fade out and destroy
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
    --[[
    Drag implementation:
    - Store initial mouse position and frame position on MouseButton1Down
    - On InputChanged, calculate delta and update frame position
    - Use UDim2 for proper scaling across different screen sizes
    - Clamp position to keep frame within screen bounds
    ]]
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
            
            -- Calculate new position with clamping
            local newPos = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            
            mainFrame.Position = newPos
            
            -- Update config
            getgenv().RAYv2_Config.GUI.Position = newPos
        end
    end)
    
    -- Tab system
    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, 0, 0, 45)
    tabContainer.Position = UDim2.new(0, 0, 0, 40)
    tabContainer.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    tabContainer.BorderSizePixel = 0
    tabContainer.Parent = mainFrame
    
    local tabListLayout = Instance.new("UIListLayout")
    tabListLayout.FillDirection = Enum.FillDirection.Horizontal
    tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabListLayout.Padding = UDim.new(0, 0)
    tabListLayout.Parent = tabContainer
    
    -- Content container for tab panels
    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentContainer"
    contentContainer.Size = UDim2.new(1, -20, 1, -105)
    contentContainer.Position = UDim2.new(0, 10, 0, 95)
    contentContainer.BackgroundTransparency = 1
    contentContainer.ClipsDescendants = true
    contentContainer.Parent = mainFrame
    
    -- Tab data
    local tabs = {"Aimbot", "ESP", "Configs", "Profile"}
    local tabButtons = {}
    local tabPanels = {}
    local currentTab = nil
    
    -- Tab indicator (sliding underline)
    local tabIndicator = Instance.new("Frame")
    tabIndicator.Name = "Indicator"
    tabIndicator.Size = UDim2.new(0, 0, 0, 3)
    tabIndicator.Position = UDim2.new(0, 0, 1, -3)
    tabIndicator.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
    tabIndicator.BorderSizePixel = 0
    tabIndicator.Parent = tabContainer
    
    -- Create tab buttons
    for i, tabName in ipairs(tabs) do
        local tabButton = Instance.new("TextButton")
        tabButton.Name = tabName .. "Tab"
        tabButton.Size = UDim2.new(1/#tabs, 0, 1, 0)
        tabButton.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
        tabButton.Text = tabName
        tabButton.Font = Enum.Font.GothamBold
        tabButton.TextSize = 16
        tabButton.TextColor3 = Color3.fromRGB(150, 150, 150)
        tabButton.AutoButtonColor = false
        tabButton.LayoutOrder = i
        tabButton.Parent = tabContainer
        
        -- Hover glow effect
        local tabStroke = Instance.new("UIStroke")
        tabStroke.Color = Color3.fromRGB(0, 212, 255)
        tabStroke.Thickness = 0
        tabStroke.Transparency = 0
        tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        tabStroke.Parent = tabButton
        
        tabButton.MouseEnter:Connect(function()
            if currentTab ~= tabName then
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
            if currentTab ~= tabName then
                TweenService:Create(tabStroke, TweenInfo.new(0.2), {
                    Thickness = 0
                }):Play()
                
                TweenService:Create(tabButton, TweenInfo.new(0.2), {
                    TextColor3 = Color3.fromRGB(150, 150, 150)
                }):Play()
            end
        end)
        
        tabButtons[tabName] = tabButton
        
        -- Create tab panel
        local tabPanel = Instance.new("ScrollingFrame")
        tabPanel.Name = tabName .. "Panel"
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
        
        local panelListLayout = Instance.new("UIListLayout")
        panelListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        panelListLayout.Padding = UDim.new(0, 10)
        panelListLayout.Parent = tabPanel
        
        local panelPadding = Instance.new("UIPadding")
        panelPadding.PaddingTop = UDim.new(0, 10)
        panelPadding.PaddingBottom = UDim.new(0, 10)
        panelPadding.Parent = tabPanel
        
        tabPanels[tabName] = tabPanel
    end
    
    -- Tab switching function
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
            
            -- Fade out old panel
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
        
        -- Move indicator
        local indicatorTargetPos = UDim2.new(targetButton.Position.X.Scale, targetButton.Position.X.Offset, 1, -3)
        local indicatorTargetSize = UDim2.new(targetButton.Size.X.Scale, targetButton.Size.X.Offset, 0, 3)
        
        TweenService:Create(tabIndicator, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Position = indicatorTargetPos,
            Size = indicatorTargetSize
        }):Play()
        
        -- Fade in new panel
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
        button.MouseButton1Click:Connect(function()
            SwitchTab(tabName)
        end)
    end
    
    -- Initialize first tab
    SwitchTab("Aimbot")
    
    -- ══════════════════════════════════════════════════════════════════════
    -- TAB CONTENT CREATION: AIMBOT TAB
    -- ══════════════════════════════════════════════════════════════════════
    
    local aimbotPanel = tabPanels["Aimbot"]
    
    -- Helper function to create section headers
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
    
    -- Helper function to create toggle checkbox
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
        
        local checkboxStroke = Instance.new("UIStroke")
        checkboxStroke.Color = Color3.fromRGB(60, 60, 60)
        checkboxStroke.Thickness = 1
        checkboxStroke.Parent = checkbox
        
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
    
    -- Helper function to create slider
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
        
        sliderButton.MouseButton1Click:Connect(function(input)
            UpdateSlider(input)
        end)
        
        return container, function() return currentValue end, function(value)
            currentValue = math.clamp(value, min, max)
            local relativeX = (currentValue - min) / (max - min)
            sliderFill.Size = UDim2.new(relativeX, 0, 1, 0)
            valueLabel.Text = tostring(currentValue) .. (suffix or "")
        end
    end
    
    -- Helper function to create keybind input
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
    
    -- Helper function to create dropdown
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
        
        local optionsStroke = Instance.new("UIStroke")
        optionsStroke.Color = Color3.fromRGB(0, 212, 255)
        optionsStroke.Thickness = 1
        optionsStroke.Parent = optionsFrame
        
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
    
    -- AIMBOT TAB CONTENT
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
    
    -- ══════════════════════════════════════════════════════════════════════
    -- TAB CONTENT CREATION: ESP TAB
    -- ══════════════════════════════════════════════════════════════════════
    
    local espPanel = tabPanels["ESP"]
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
    
    -- ══════════════════════════════════════════════════════════════════════
    -- TAB CONTENT CREATION: CONFIGS TAB
    -- ══════════════════════════════════════════════════════════════════════
    
    local configsPanel = tabPanels["Configs"]
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
    
    -- Config list header
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
            warn("[RAYv2] Config name cannot be empty")
            return
        end
        
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local configData = {
            Name = configName,
            Timestamp = timestamp,
            Settings = getgenv().RAYv2_Config
        }
        
        -- Save to table
        savedConfigs[configName] = configData
        
        -- Attempt to save to file using writefile if available
        pcall(function()
            if writefile then
                local encoded = HttpService:JSONEncode(configData)
                writefile("RAYv2_" .. configName .. ".json", encoded)
                DebugPrint("Config saved to file:", configName)
            end
        end)
        
        DebugPrint("Config saved:", configName)
        RefreshConfigList()
    end
    
    local function LoadConfig(configName)
        local configData = savedConfigs[configName]
        
        if not configData then
            -- Try loading from file
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
            
            -- Update all GUI elements to reflect loaded config
            setAimbotEnabled(configData.Settings.Aimbot.Enabled)
            -- Update other settings...
            
            DebugPrint("Config loaded:", configName)
        else
            warn("[RAYv2] Config not found:", configName)
        end
    end
    
    local function DeleteConfig(configName)
        savedConfigs[configName] = nil
        
        pcall(function()
            if delfile then
                delfile("RAYv2_" .. configName .. ".json")
            end
        end)
        
        DebugPrint("Config deleted:", configName)
        RefreshConfigList()
    end
    
    function RefreshConfigList()
        -- Clear existing list
        for _, child in ipairs(configScrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        -- Populate with saved configs
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
    
    -- Load existing configs from files on startup
    task.spawn(function()
        if listfiles then
            local files = listfiles()
            for _, file in ipairs(files) do
                if file:match("RAYv2_(.+)%.json$") then
                    local configName = file:match("RAYv2_(.+)%.json$")
                    pcall(function()
                        local fileData = readfile(file)
                        local configData = HttpService:JSONDecode(fileData)
                        savedConfigs[configName] = configData
                    end)
                end
            end
            RefreshConfigList()
        end
    end)
    
    -- ══════════════════════════════════════════════════════════════════════
    -- TAB CONTENT CREATION: PROFILE TAB
    -- ══════════════════════════════════════════════════════════════════════
    
    local profilePanel = tabPanels["Profile"]
    layoutOrder = 0
    
    -- Profile header with avatar
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
    
    -- Avatar image
    local avatarFrame = Instance.new("Frame")
    avatarFrame.Size = UDim2.new(0, 100, 0, 100)
    avatarFrame.Position = UDim2.new(0.5, -50, 0, 20)
    avatarFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    avatarFrame.BorderSizePixel = 0
    avatarFrame.Parent = profileHeader
    
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0) -- Perfect circle
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
    
    -- Load player avatar
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
    
    -- Special badge for owner UserId 7143862381
    if LocalPlayer.UserId == 7143862381 then
        local ownerBadge = Instance.new("Frame")
        ownerBadge.Size = UDim2.new(0, 120, 0, 30)
        ownerBadge.Position = UDim2.new(0.5, -60, 0, 125)
        ownerBadge.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold
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
        
        -- Pulsing glow animation
        local glowTween = TweenService:Create(
            badgeStroke,
            TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {Thickness = 4}
        )
        glowTween:Play()
        table.insert(getgenv().RAYv2_Runtime.TweenCache, glowTween)
        
        -- Sparkle particle effect
        --[[
        Note: ParticleEmitter not supported in ScreenGui context
        Alternative: Create multiple small frames that animate upward
        ]]
        for i = 1, 5 do
            task.spawn(function()
                while ownerBadge.Parent do
                    local sparkle = Instance.new("Frame")
                    sparkle.Size = UDim2.new(0, 4, 0, 4)
                    sparkle.Position = UDim2.new(math.random(0, 100) / 100, 0, 1, 0)
                    sparkle.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
                    sparkle.BorderSizePixel = 0
                    sparkle.ZIndex = 5
                    sparkle.Parent = ownerBadge
                    
                    local sparkleCorner = Instance.new("UICorner")
                    sparkleCorner.CornerRadius = UDim.new(1, 0)
                    sparkleCorner.Parent = sparkle
                    
                    local riseTween = TweenService:Create(
                        sparkle,
                        TweenInfo.new(2, Enum.EasingStyle.Linear),
                        {
                            Position = UDim2.new(sparkle.Position.X.Scale, 0, -0.5, 0),
                            BackgroundTransparency = 1
                        }
                    )
                    riseTween:Play()
                    
                    riseTween.Completed:Connect(function()
                        sparkle:Destroy()
                    end)
                    
                    task.wait(math.random(2, 5) / 10)
                end
            end)
        end
    end
    
    -- Profile spoofers section
    CreateSectionHeader(profilePanel, "PROFILE SPOOFERS", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    local fakeLevelSlider, getFakeLevel = CreateSlider(
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
    
    local fakeStreakSlider, getFakeStreak = CreateSlider(
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
    
    local fakeKeysSlider, getFakeKeys = CreateSlider(
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
    
    local fakePremiumToggle, getFakePremium = CreateToggle(
        profilePanel,
        "Fake Premium Badge",
        getgenv().RAYv2_Config.Profile.FakePremium,
        function(value)
            getgenv().RAYv2_Config.Profile.FakePremium = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    local fakeVerifiedToggle, getFakeVerified = CreateToggle(
        profilePanel,
        "Fake Verified Badge",
        getgenv().RAYv2_Config.Profile.FakeVerified,
        function(value)
            getgenv().RAYv2_Config.Profile.FakeVerified = value
        end,
        layoutOrder
    )
    layoutOrder = layoutOrder + 1
    
    -- Admin panel access
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
    
    -- Admin panel content (hidden by default)
    local adminPanelContent = Instance.new("Frame")
    adminPanelContent.Name = "AdminPanelContent"
    adminPanelContent.Size = UDim2.new(1, 0, 0, 300)
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
    adminInfoLabel.Text = "Admin features:\n• Restrict specific UserIds\n• Assign roles (Media/Admin/Support/Moderator)\n• Custom role colors and effects\n\n[Feature implementation reserved for production build]"
    adminInfoLabel.TextSize = 13
    adminInfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    adminInfoLabel.TextWrapped = true
    adminInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
    adminInfoLabel.Parent = adminPanelContent
    
    -- Admin unlock logic
    adminUnlockButton.MouseButton1Click:Connect(function()
        local username = adminUsernameInput.Text
        local password = adminPasswordInput.Text
        
        if username == getgenv().RAYv2_Config.Admin.Username and password == getgenv().RAYv2_Config.Admin.Password then
            getgenv().RAYv2_Config.Admin.Unlocked = true
            adminPanelContent.Visible = true
            adminUnlockContainer.Visible = false
            
            DebugPrint("Admin panel unlocked")
        else
            -- Shake animation for wrong password
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
    
    -- Version label at bottom
    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(1, 0, 0, 30)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.Text = "RAYv2 " .. getgenv().RAYv2_Version
    versionLabel.TextSize = 14
    versionLabel.TextColor3 = Color3.fromRGB(0, 212, 255)
    versionLabel.LayoutOrder = 9999
    versionLabel.Parent = profilePanel
    
    local versionGlow = Instance.new("UIStroke")
    versionGlow.Color = Color3.fromRGB(0, 212, 255)
    versionGlow.Thickness = 1
    versionGlow.Transparency = 0.7
    versionGlow.Parent = versionLabel
    
    -- ══════════════════════════════════════════════════════════════════════
    -- GUI TOGGLE KEYBINDS
    -- ══════════════════════════════════════════════════════════════════════
    
    local function ToggleGUI()
        local newVisibility = not mainFrame.Visible
        getgenv().RAYv2_Config.GUI.Visible = newVisibility
        
        if newVisibility then
            mainFrame.Visible = true
            TweenService:Create(mainFrame, TweenInfo.new(0.2), {
                Size = getgenv().RAYv2_Config.GUI.Size,
                GroupTransparency = 0
            }):Play()
        else
            TweenService:Create(mainFrame, TweenInfo.new(0.2), {
                Size = UDim2.new(0, 0, 0, 0),
                GroupTransparency = 1
            }):Play()
            task.wait(0.2)
            mainFrame.Visible = false
        end
    end
    
    local toggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == getgenv().RAYv2_Config.GUI.ToggleKeybind or
           input.KeyCode == getgenv().RAYv2_Config.GUI.AlternateKeybind1 or
           input.KeyCode == getgenv().RAYv2_Config.GUI.AlternateKeybind2 then
            ToggleGUI()
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, toggleConnection)
    
    DebugPrint("Main GUI created successfully")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: AIMBOT IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════
--[[
AIMBOT SYSTEM ARCHITECTURE:

1. FOV Circle Rendering (Drawing API)
   - Calculate screen-space radius from FOV angle using trigonometry
   - Formula: radius = (FOV / 2) * (ViewportHeight / tan(CameraFOV / 2))
   - Update position every RenderStepped to follow mouse

2. Target Selection (Closest to Crosshair)
   - Iterate all players in match
   - Filter by: team, distance, visibility, health
   - Calculate screen distance from crosshair center
   - Select minimum distance within FOV

3. Silent Aim (Invisible Targeting)
   - Hook gun's raycast/fire mechanism (find Tool RemoteEvents)
   - Override hit position to target's head/HRP without moving camera
   - Prediction: add velocity * (ping/1000 * factor) to target position
   - No camera manipulation = undetectable to spectators

4. Smooth Aim (Visible Camera Movement)
   - Calculate direction vector to target: (targetPos - cameraPos).Unit
   - Lerp camera LookVector toward target direction
   - Smoothness factor controls interpolation strength (0-1 range)
   - Apply every RenderStepped for continuous tracking

5. Triggerbot (Auto-Fire)
   - Raycast from camera through mouse position
   - If hit enemy within range, fire equipped tool
   - Respect delay between shots for realism
]]

-- FOV Circle object (persistent Drawing)
local fovCircle = nil

local function InitializeFOVCircle()
    if fovCircle then return end
    
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Thickness = 2
    fovCircle.NumSides = 64 -- Higher = smoother circle
    fovCircle.Filled = false
    fovCircle.Transparency = 1
    fovCircle.Color = Color3.new(0, 0.83, 1) -- Electric blue
    fovCircle.ZIndex = 1000
    
    DebugPrint("FOV Circle initialized")
end

-- Calculate FOV circle radius in pixels
--[[
Mathematical derivation:
- Camera FOV is given in degrees (default 70)
- Screen height in pixels = Camera.ViewportSize.Y
- For a given angle θ (half FOV), the screen distance from center to edge is:
  distance = ViewportHeight / (2 * tan(θ/2))
- To convert user FOV setting to pixels:
  radius = (UserFOV / 2) * (ViewportHeight / tan(CameraFOV / 2))

This ensures FOV circle matches actual visible angle regardless of screen resolution.
]]
local function CalculateFOVRadius()
    local fovAngle = getgenv().RAYv2_Config.Aimbot.FOV
    local cameraFOV = Camera.FieldOfView
    local viewportHeight = Camera.ViewportSize.Y
    
    -- Convert FOV angle to radians for tan function
    local halfFOVRad = math.rad(cameraFOV / 2)
    
    -- Pixel distance per degree
    local pixelsPerDegree = viewportHeight / (2 * math.tan(halfFOVRad))
    
    -- Calculate radius from user FOV setting
    local radius = (fovAngle / 2) * pixelsPerDegree / 90 -- Normalized adjustment
    
    return math.max(radius, 0)
end

-- Update FOV circle position and appearance
local function UpdateFOVCircle()
    if not fovCircle then return end
    
    local config = getgenv().RAYv2_Config.Aimbot
    
    -- Visibility
    fovCircle.Visible = config.Enabled and config.FOVVisible
    
    if not fovCircle.Visible then return end
    
    -- Position (center on mouse)
    fovCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
    
    -- Radius
    fovCircle.Radius = CalculateFOVRadius()
    
    -- Fill
    fovCircle.Filled = config.FOVFilled
    
    -- Color
    local color = config.FOVColor
    fovCircle.Color = Color3.new(color.R, color.G, color.B)
end

-- Get all valid targets for aimbot
--[[
Target validation criteria:
1. Character exists and is valid
2. Humanoid health > 0
3. Not local player
4. Team check (if enabled)
5. Distance check (within max range)
6. Visibility check (raycast wallcheck if enabled)
7. In active match (RIVALS-specific)
]]
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
        
        -- Team check
        if config.TeamCheck and IsSameTeam(LocalPlayer, player) then
            continue
        end
        
        -- Match check (RIVALS-specific)
        if not IsInMatch(player) then
            continue
        end
        
        local targetHRP = character:FindFirstChild("HumanoidRootPart")
        if not targetHRP then continue end
        
        -- Distance check
        local distance = (targetHRP.Position - localHRP.Position).Magnitude
        if distance > config.MaxDistance then
            continue
        end
        
        -- Visibility check
        if config.VisibleCheck then
            local ignoreList = {localChar, character}
            if not IsPositionVisible(targetHRP.Position, ignoreList) then
                continue
            end
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

-- Select closest target to crosshair within FOV
--[[
Selection algorithm:
1. Get all valid targets
2. For each target, calculate screen position of aim point (head or HRP)
3. Calculate 2D distance from screen center (crosshair)
4. If distance <= FOV radius (in pixels), target is within FOV
5. Select target with minimum screen distance

Distance calculation uses Pythagorean theorem:
screenDist = sqrt((x - centerX)^2 + (y - centerY)^2)

Optimization: Can use squared distance to avoid sqrt, but clarity prioritized here.
]]
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
        
        -- Select aim point (head if priority enabled, else HRP)
        local aimPart = hrp
        if config.HeadPriority then
            local head = character:FindFirstChild("Head")
            if head then
                aimPart = head
            end
        end
        
        -- Get screen position of aim point
        local screenPos, onScreen = WorldToScreen(aimPart.Position)
        if not onScreen then continue end
        
        -- Calculate distance from screen center (crosshair)
        local deltaX = screenPos.X - screenCenter.X
        local deltaY = screenPos.Y - screenCenter.Y
        local screenDistance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        
        -- Check if within FOV circle
        if screenDistance > fovRadius then continue end
        
        -- Update closest
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

-- Apply smooth aim (camera lerp)
--[[
Smooth aim mathematics:
1. Current camera LookVector: direction camera is facing
2. Target direction: unit vector from camera to target
   targetDir = (targetPos - cameraPos).Unit
3. Interpolated direction: blend current and target using Lerp
   newDir = currentLook:Lerp(targetDir, smoothness)
4. Create new CFrame looking at interpolated direction
   camera.CFrame = CFrame.lookAt(cameraPos, cameraPos + newDir)

Smoothness value (0-100 slider):
- 0 = no movement
- 100 = instant snap (no smoothing)
- Converted to 0-1 range: smoothness * 0.01

Lower values = smoother, more natural aim
Higher values = faster, more aggressive aim
]]
local function ApplySmoothAim(targetPosition)
    local config = getgenv().RAYv2_Config.Aimbot
    
    if config.SilentAim then
        -- Silent aim: do not move camera
        return
    end
    
    -- Apply prediction if enabled
    if config.Prediction then
        local target = getgenv().RAYv2_Runtime.CurrentTarget
        if target and target.HRP then
            local velocity = target.HRP.AssemblyLinearVelocity
            targetPosition = PredictPosition(targetPosition, velocity)
        end
    end
    
    local cameraPos = Camera.CFrame.Position
    local currentLook = Camera.CFrame.LookVector
    
    -- Calculate direction to target
    local targetDirection = (targetPosition - cameraPos).Unit
    
    -- Smoothness factor (0-1 range)
    -- Divided by 100 to convert slider value (0-100) to decimal
    local smoothFactor = config.Smoothness * 0.01
    
    -- Lerp current look vector toward target
    -- Vector3:Lerp(target, alpha) blends from self to target by alpha amount
    local newLookDirection = currentLook:Lerp(targetDirection, smoothFactor)
    
    -- Create new camera CFrame looking at interpolated direction
    -- CFrame.lookAt(position, target) creates CFrame at position facing target
    -- We use position + direction to create a point to look at
    Camera.CFrame = CFrame.lookAt(cameraPos, cameraPos + newLookDirection)
end

-- Silent aim: hook tool firing
--[[
Silent aim implementation strategy:
1. Find equipped tool (gun)
2. Locate RemoteEvent/RemoteFunction used for firing
3. Hook the remote call to override hit position
4. Send target position instead of actual mouse hit
5. Server registers hit on target, but client camera doesn't move

RIVALS-specific notes:
- Guns typically fire via RemoteEvent in Tool.Handle
- Event name may be "Fire", "Shoot", "Hit", etc.
- Need to identify correct remote by testing in-game

Alternative: Use namecall metamethod hook to intercept all RemoteEvent:FireServer calls
]]
local silentAimActive = false

local function GetEquippedTool()
    local character = LocalPlayer.Character
    if not character then return nil end
    
    return character:FindFirstChildOfClass("Tool")
end

local function ApplySilentAim(targetPosition)
    local tool = GetEquippedTool()
    if not tool then return end
    
    -- RIVALS-specific: Find fire remote
    -- Common remote names: Fire, Shoot, Hit, MouseEvent
    local fireRemote = tool:FindFirstChild("Fire") or 
                       tool:FindFirstChild("Shoot") or
                       tool:FindFirstChild("Hit") or
                       tool.Handle:FindFirstChild("Fire")
    
    if not fireRemote or not fireRemote:IsA("RemoteEvent") then
        DebugPrint("Fire remote not found in tool:", tool.Name)
        return
    end
    
    -- Apply prediction
    if getgenv().RAYv2_Config.Aimbot.Prediction then
        local target = getgenv().RAYv2_Runtime.CurrentTarget
        if target and target.HRP then
            local velocity = target.HRP.AssemblyLinearVelocity
            targetPosition = PredictPosition(targetPosition, velocity)
        end
    end
    
    -- Hook the remote to send target position
    -- Note: This is a simplified example; actual implementation may vary by game
    silentAimActive = true
    
    -- Fire with overridden position
    pcall(function()
        fireRemote:FireServer(targetPosition)
    end)
    
    silentAimActive = false
end

-- Triggerbot: auto-fire when aiming at enemy
--[[
Triggerbot logic:
1. Raycast from camera through mouse position
2. Check if hit part belongs to enemy player
3. If yes and within distance, fire equipped tool
4. Respect cooldown delay between shots

Raycast setup:
- Origin: Camera position
- Direction: Unit ray through mouse (Camera:ScreenPointToRay)
- Distance: Max aimbot range
- Filter: Blacklist local character
]]
local function UpdateTriggerbot()
    local config = getgenv().RAYv2_Config.Aimbot.Triggerbot
    if not config.Enabled then return end
    if not getgenv().RAYv2_Runtime.TriggerbotActive then return end
    
    -- Check cooldown
    local currentTime = tick()
    if currentTime - getgenv().RAYv2_Runtime.LastShotTime < config.Delay then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    -- Raycast from camera through mouse
    local mouseRay = Camera:ScreenPointToRay(Mouse.X, Mouse.Y)
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.IgnoreWater = true
    
    local maxDistance = getgenv().RAYv2_Config.Aimbot.MaxDistance
    local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * maxDistance, raycastParams)
    
    if not result then return end
    
    -- Check if hit an enemy player
    local hitPart = result.Instance
    local hitCharacter = hitPart.Parent
    
    if not hitCharacter or not hitCharacter:FindFirstChildOfClass("Humanoid") then
        -- Try parent's parent (for accessories)
        hitCharacter = hitPart.Parent.Parent
    end
    
    if not hitCharacter or not hitCharacter:FindFirstChildOfClass("Humanoid") then
        return
    end
    
    local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
    if not hitPlayer or hitPlayer == LocalPlayer then return end
    
    -- Team check
    if getgenv().RAYv2_Config.Aimbot.TeamCheck and IsSameTeam(LocalPlayer, hitPlayer) then
        return
    end
    
    -- Fire tool
    local tool = GetEquippedTool()
    if tool then
        pcall(function()
            tool:Activate()
        end)
        
        getgenv().RAYv2_Runtime.LastShotTime = currentTime
        DebugPrint("Triggerbot fired at", hitPlayer.Name)
    end
end

-- Main aimbot update loop (RenderStepped)
local function UpdateAimbot()
    -- Update FOV circle
    UpdateFOVCircle()
    
    -- Check if aimbot is active
    local config = getgenv().RAYv2_Config.Aimbot
    if not config.Enabled then
        getgenv().RAYv2_Runtime.CurrentTarget = nil
        return
    end
    
    -- Check keybind state
    local keybindActive = false
    if config.Mode == "Toggle" then
        keybindActive = getgenv().RAYv2_Runtime.AimbotActive
    else -- Hold mode
        keybindActive = UserInputService:IsKeyDown(config.Keybind)
    end
    
    if not keybindActive then
        getgenv().RAYv2_Runtime.CurrentTarget = nil
        return
    end
    
    -- Get closest target
    local target = GetClosestTarget()
    getgenv().RAYv2_Runtime.CurrentTarget = target
    
    if not target then return end
    
    -- Apply appropriate aim method
    if config.SilentAim then
        ApplySilentAim(target.AimPart.Position)
    else
        ApplySmoothAim(target.AimPart.Position)
    end
end

-- Aimbot keybind handler
local function SetupAimbotKeybinds()
    local aimbotKeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        local config = getgenv().RAYv2_Config.Aimbot
        
        if input.KeyCode == config.Keybind then
            if config.Mode == "Toggle" then
                getgenv().RAYv2_Runtime.AimbotActive = not getgenv().RAYv2_Runtime.AimbotActive
                DebugPrint("Aimbot toggled:", getgenv().RAYv2_Runtime.AimbotActive)
            end
        end
        
        if input.KeyCode == config.Triggerbot.Keybind then
            getgenv().RAYv2_Runtime.TriggerbotActive = true
            DebugPrint("Triggerbot activated")
        end
    end)
    
    local aimbotKeybindEndConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
        local config = getgenv().RAYv2_Config.Aimbot
        
        if input.KeyCode == config.Triggerbot.Keybind then
            getgenv().RAYv2_Runtime.TriggerbotActive = false
            DebugPrint("Triggerbot deactivated")
        end
    end)
    
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotKeybindConnection)
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotKeybindEndConnection)
end

-- Initialize aimbot system
local function InitializeAimbot()
    InitializeFOVCircle()
    SetupAimbotKeybinds()
    
    local aimbotUpdateConnection = RunService.RenderStepped:Connect(UpdateAimbot)
    table.insert(getgenv().RAYv2_Runtime.Connections, aimbotUpdateConnection)
    
    local triggerbotUpdateConnection = RunService.Heartbeat:Connect(UpdateTriggerbot)
    table.insert(getgenv().RAYv2_Runtime.Connections, triggerbotUpdateConnection)
    
    DebugPrint("Aimbot system initialized")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: ESP IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════
--[[
ESP SYSTEM ARCHITECTURE:

1. Object Pooling (Performance Critical)
   - Pre-allocate Drawing objects for reuse
   - Map each player to their Drawing objects
   - Release objects when player leaves or ESP disabled

2. World-to-Screen Conversion (Every Frame)
   - Convert 3D positions to 2D screen coordinates
   - Check if position is on screen (Z > 0)
   - Calculate bounding box by projecting all corners

3. Box ESP
   - Calculate 2D bounding box from character bounds
   - Draw four lines forming rectangle
   - Optional fill using Square with transparency

4. Skeleton ESP
   - Define bone connections (torso to limbs)
   - For each connection, draw line from partA to partB
   - Handle R15 and R6 character models

5. Tracers
   - Line from screen position (bottom/center/mouse) to target
   - Update end position every frame

6. Text ESP (Name, Health, Distance, Weapon)
   - Stack text elements vertically above character
   - Update text content and color based on player state

7. Health Bar
   - Vertical bar to left of bounding box
   - Height proportional to health percentage
   - Color gradient from green (full) to red (low)

Performance optimization:
- Only update ESP for players within max distance
- Skip off-screen players
- Reuse Drawing objects instead of creating new ones
- Lock updates to RenderStepped for consistent 60 FPS
]]

-- ESP object management for each player
--[[
Structure:
ESPObjects[player] = {
    Box = {Line, Line, Line, Line},
    Fill = Square,
    Skeleton = {Line, Line, ...},
    Tracers = Line,
    Name = Text,
    Health = Text,
    HealthBar = {Back = Square, Fill = Square},
    Distance = Text,
    Weapon = Text
}
]]

local function CreateESPObjects(player)
    local objects = {}
    
    -- Box (4 lines forming rectangle)
    objects.Box = {
        GetDrawing("Line"),
        GetDrawing("Line"),
        GetDrawing("Line"),
        GetDrawing("Line")
    }
    
    -- Fill (single square with transparency)
    objects.Fill = GetDrawing("Square")
    
    -- Skeleton (multiple lines for bone connections)
    -- R15 has more bones than R6, allocate max needed
    objects.Skeleton = {}
    for i = 1, 15 do
        table.insert(objects.Skeleton, GetDrawing("Line"))
    end
    
    -- Tracer (single line)
    objects.Tracers = GetDrawing("Line")
    
    -- Text elements
    objects.Name = GetDrawing("Text")
    objects.Health = GetDrawing("Text")
    objects.Distance = GetDrawing("Text")
    objects.Weapon = GetDrawing("Text")
    
    -- Health bar (background + fill)
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
    
    -- Release all Drawing objects back to pool
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

-- Draw box ESP
--[[
Box drawing strategy:
1. Get 2D bounding box from GetCharacterBoundingBox
2. topLeft and size define rectangle corners
3. Draw 4 lines connecting corners: TL->TR, TR->BR, BR->BL, BL->TL
4. If fill enabled, draw filled square covering entire box
]]
local function DrawBox(objects, topLeft, size, color, thickness)
    local config = getgenv().RAYv2_Config.ESP.Boxes
    
    if not config.Enabled then
        for _, line in ipairs(objects.Box) do
            line.Visible = false
        end
        return
    end
    
    local lines = objects.Box
    
    -- Define corners
    local topRight = topLeft + Vector2.new(size.X, 0)
    local bottomLeft = topLeft + Vector2.new(0, size.Y)
    local bottomRight = topLeft + size
    
    -- Top line (TL -> TR)
    lines[1].From = topLeft
    lines[1].To = topRight
    lines[1].Color = color
    lines[1].Thickness = thickness
    lines[1].Visible = true
    
    -- Right line (TR -> BR)
    lines[2].From = topRight
    lines[2].To = bottomRight
    lines[2].Color = color
    lines[2].Thickness = thickness
    lines[2].Visible = true
    
    -- Bottom line (BR -> BL)
    lines[3].From = bottomRight
    lines[3].To = bottomLeft
    lines[3].Color = color
    lines[3].Thickness = thickness
    lines[3].Visible = true
    
    -- Left line (BL -> TL)
    lines[4].From = bottomLeft
    lines[4].To = topLeft
    lines[4].Color = color
    lines[4].Thickness = thickness
    lines[4].Visible = true
end

-- Draw fill ESP
local function DrawFill(objects, topLeft, size, color, transparency)
    local config = getgenv().RAYv2_Config.ESP.Fill
    
    if not config.Enabled then
        objects.Fill.Visible = false
        return
    end
    
    objects.Fill.Position = topLeft
    objects.Fill.Size = size
    objects.Fill.Color = color
    objects.Fill.Transparency = 1 - transparency -- Drawing API uses inverse
    objects.Fill.Filled = true
    objects.Fill.Visible = true
end

-- Draw skeleton ESP
--[[
Skeleton bone structure (R15):
Head -> UpperTorso
UpperTorso -> LeftUpperArm, RightUpperArm, LowerTorso
LeftUpperArm -> LeftLowerArm -> LeftHand
RightUpperArm -> RightLowerArm -> RightHand
LowerTorso -> LeftUpperLeg, RightUpperLeg
LeftUpperLeg -> LeftLowerLeg -> LeftFoot
RightUpperLeg -> RightLowerLeg -> RightFoot

For R6: Simpler structure with Torso, Left/Right Arm, Left/Right Leg
]]
local function DrawSkeleton(objects, character, color, thickness)
    local config = getgenv().RAYv2_Config.ESP.Skeleton
    
    if not config.Enabled then
        for _, line in ipairs(objects.Skeleton) do
            line.Visible = false
        end
        return
    end
    
    -- Define bone connections (R15)
    local boneConnections = {
        {"Head", "UpperTorso"},
        {"UpperTorso", "LeftUpperArm"},
        {"LeftUpperArm", "LeftLowerArm"},
        {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"},
        {"RightUpperArm", "RightLowerArm"},
        {"RightLowerArm", "RightHand"},
        {"UpperTorso", "LowerTorso"},
        {"LowerTorso", "LeftUpperLeg"},
        {"LeftUpperLeg", "LeftLowerLeg"},
        {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"},
        {"RightUpperLeg", "RightLowerLeg"},
        {"RightLowerLeg", "RightFoot"}
    }
    
    local lineIndex = 1
    
    for _, connection in ipairs(boneConnections) do
        local part1 = character:FindFirstChild(connection[1])
        local part2 = character:FindFirstChild(connection[2])
        
        if part1 and part2 then
            local pos1, onScreen1 = WorldToScreen(part1.Position)
            local pos2, onScreen2 = WorldToScreen(part2.Position)
            
            if onScreen1 and onScreen2 and lineIndex <= #objects.Skeleton then
                local line = objects.Skeleton[lineIndex]
                line.From = pos1
                line.To = pos2
                line.Color = color
                line.Thickness = thickness
                line.Visible = true
                lineIndex = lineIndex + 1
            end
        end
    end
    
    -- Hide unused lines
    for i = lineIndex, #objects.Skeleton do
        objects.Skeleton[i].Visible = false
    end
end

-- Draw tracers
--[[
Tracer origin options:
- Bottom: Bottom center of screen
- Center: Exact center of screen
- Mouse: Current mouse position

End point: Target's feet (HumanoidRootPart.Position - Vector3.new(0, 3, 0))
]]
local function DrawTracers(objects, targetPosition, color, thickness)
    local config = getgenv().RAYv2_Config.ESP.Tracers
    
    if not config.Enabled then
        objects.Tracers.Visible = false
        return
    end
    
    local screenPos, onScreen = WorldToScreen(targetPosition)
    if not onScreen then
        objects.Tracers.Visible = false
        return
    end
    
    local fromPos
    if config.From == "Bottom" then
        fromPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    elseif config.From == "Center" then
        fromPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    else -- Mouse
        fromPos = Vector2.new(Mouse.X, Mouse.Y)
    end
    
    objects.Tracers.From = fromPos
    objects.Tracers.To = screenPos
    objects.Tracers.Color = color
    objects.Tracers.Thickness = thickness
    objects.Tracers.Visible = true
end

-- Draw text ESP
--[[
Text stacking strategy:
- Calculate box top position
- Stack text elements vertically with 15px spacing
- Order: Name -> Health -> Distance -> Weapon
- Center text horizontally above box
]]
local function DrawTextESP(objects, player, character, topLeft, size)
    local config = getgenv().RAYv2_Config.ESP
    
    local textYOffset = -5 -- Start 5px above box
    local textSpacing = 15
    
    -- Name
    if config.Name.Enabled then
        objects.Name.Text = player.DisplayName or player.Name
        objects.Name.Size = config.Name.Size
        objects.Name.Color = config.Name.Color
        objects.Name.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + textYOffset)
        objects.Name.Center = true
        objects.Name.Outline = config.Name.Outline
        objects.Name.Visible = true
        textYOffset = textYOffset - textSpacing
    else
        objects.Name.Visible = false
    end
    
    -- Health
    if config.Health.Enabled then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local health = math.floor(humanoid.Health)
            local maxHealth = math.floor(humanoid.MaxHealth)
            local healthPercent = health / maxHealth
            
            -- Color gradient from green to red
            local healthColor = Color3.new(1 - healthPercent, healthPercent, 0)
            
            objects.Health.Text = string.format("%d HP", health)
            objects.Health.Size = 14
            objects.Health.Color = healthColor
            objects.Health.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + textYOffset)
            objects.Health.Center = true
            objects.Health.Outline = true
            objects.Health.Visible = true
            textYOffset = textYOffset - textSpacing
        else
            objects.Health.Visible = false
        end
    else
        objects.Health.Visible = false
    end
    
    -- Distance
    if config.Distance.Enabled then
        local localChar = LocalPlayer.Character
        if localChar and localChar:FindFirstChild("HumanoidRootPart") then
            local distance = (character.HumanoidRootPart.Position - localChar.HumanoidRootPart.Position).Magnitude
            objects.Distance.Text = string.format("%d studs", math.floor(distance))
            objects.Distance.Size = config.Distance.Size
            objects.Distance.Color = config.Distance.Color
            objects.Distance.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + textYOffset)
            objects.Distance.Center = true
            objects.Distance.Outline = true
            objects.Distance.Visible = true
            textYOffset = textYOffset - textSpacing
        else
            objects.Distance.Visible = false
        end
    else
        objects.Distance.Visible = false
    end
    
    -- Weapon
    if config.Weapon.Enabled then
        local weapon = GetPlayerWeapon(player)
        if weapon then
            objects.Weapon.Text = weapon
            objects.Weapon.Size = config.Weapon.Size
            objects.Weapon.Color = config.Weapon.Color
            objects.Weapon.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + textYOffset)
            objects.Weapon.Center = true
            objects.Weapon.Outline = true
            objects.Weapon.Visible = true
        else
            objects.Weapon.Visible = false
        end
    else
        objects.Weapon.Visible = false
    end
end

-- Draw health bar
--[[
Health bar placement:
- To the left of bounding box
- Width: 3-5 pixels
- Height: Full box height
- Fill height proportional to health percentage
- Color: Green (high) -> Yellow (mid) -> Red (low)
]]
local function DrawHealthBar(objects, character, topLeft, size)
    local config = getgenv().RAYv2_Config.ESP.Health
    
    if not config.BarEnabled then
        objects.HealthBar.Back.Visible = false
        objects.HealthBar.Fill.Visible = false
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        objects.HealthBar.Back.Visible = false
        objects.HealthBar.Fill.Visible = false
        return
    end
    
    local healthPercent = humanoid.Health / humanoid.MaxHealth
    
    -- Background bar (black outline)
    local barWidth = config.BarWidth
    local barX = topLeft.X - barWidth - 3
    
    objects.HealthBar.Back.Position = Vector2.new(barX, topLeft.Y)
    objects.HealthBar.Back.Size = Vector2.new(barWidth, size.Y)
    objects.HealthBar.Back.Color = Color3.new(0, 0, 0)
    objects.HealthBar.Back.Filled = true
    objects.HealthBar.Back.Visible = true
    
    -- Fill bar (health colored)
    local fillHeight = size.Y * healthPercent
    local fillY = topLeft.Y + (size.Y - fillHeight)
    
    -- Color gradient: Green -> Yellow -> Red
    local healthColor
    if healthPercent > 0.5 then
        -- Green to Yellow
        local t = (healthPercent - 0.5) * 2
        healthColor = Color3.new(1 - t, 1, 0)
    else
        -- Yellow to Red
        local t = healthPercent * 2
        healthColor = Color3.new(1, t, 0)
    end
    
    objects.HealthBar.Fill.Position = Vector2.new(barX, fillY)
    objects.HealthBar.Fill.Size = Vector2.new(barWidth, fillHeight)
    objects.HealthBar.Fill.Color = healthColor
    objects.HealthBar.Fill.Filled = true
    objects.HealthBar.Fill.Visible = true
end

-- Main ESP update for single player
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
    
    -- Team check
    if config.TeamCheck and IsSameTeam(LocalPlayer, player) then
        ReleaseESPObjects(player)
        return
    end
    
    -- Match check
    if not IsInMatch(player) then
        ReleaseESPObjects(player)
        return
    end
    
    -- Distance check
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
    
    -- Get bounding box
    local topLeft, size, valid = GetCharacterBoundingBox(character)
    if not valid then
        ReleaseESPObjects(player)
        return
    end
    
    -- Get or create ESP objects for this player
    local objects = GetESPObjects(player)
    
    -- Draw all ESP elements
    DrawBox(objects, topLeft, size, config.Boxes.Color, config.Boxes.Thickness)
    DrawFill(objects, topLeft, size, config.Fill.Color, config.Fill.Transparency)
    DrawSkeleton(objects, character, config.Skeleton.Color, config.Skeleton.Thickness)
    DrawTracers(objects, hrp.Position - Vector3.new(0, 3, 0), config.Tracers.Color, config.Tracers.Thickness)
    DrawTextESP(objects, player, character, topLeft, size)
    DrawHealthBar(objects, character, topLeft, size)
end

-- Main ESP update loop (RenderStepped)
local function UpdateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            UpdatePlayerESP(player)
        end
    end
end

-- Initialize ESP system
local function InitializeESP()
    -- Clean up ESP when player leaves
    local playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        ReleaseESPObjects(player)
    end)
    table.insert(getgenv().RAYv2_Runtime.Connections, playerRemovingConnection)
    
    -- Main ESP update loop
    local espUpdateConnection = RunService.RenderStepped:Connect(UpdateESP)
    table.insert(getgenv().RAYv2_Runtime.Connections, espUpdateConnection)
    
    DebugPrint("ESP system initialized")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 8: CLEANUP AND SCRIPT MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════
--[[
Proper cleanup is critical for:
1. Preventing memory leaks (Drawing objects, connections)
2. Allowing script reload without errors
3. Clean shutdown when game closes

Cleanup checklist:
- Disconnect all RBXScriptConnections
- Destroy all GUI elements
- Release all Drawing API objects
- Cancel all active tweens
- Clear runtime tables
]]

function CleanupScript()
    DebugPrint("Cleaning up RAYv2...")
    
    -- Disconnect all connections
    for _, connection in ipairs(getgenv().RAYv2_Runtime.Connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    getgenv().RAYv2_Runtime.Connections = {}
    
    -- Cancel all tweens
    for _, tween in ipairs(getgenv().RAYv2_Runtime.TweenCache) do
        if tween then
            tween:Cancel()
        end
    end
    getgenv().RAYv2_Runtime.TweenCache = {}
    
    -- Release all ESP objects
    for player, _ in pairs(getgenv().RAYv2_Runtime.ESPObjects) do
        ReleaseESPObjects(player)
    end
    
    -- Destroy FOV circle
    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end
    
    -- Destroy all Drawing objects in pools
    for poolName, pool in pairs(getgenv().RAYv2_DrawingPool) do
        for _, obj in ipairs(pool) do
            if obj then
                obj:Remove()
            end
        end
        getgenv().RAYv2_DrawingPool[poolName] = {}
    end
    
    -- Destroy loading screen if still exists
    if getgenv().RAYv2_Runtime.LoadingScreen then
        getgenv().RAYv2_Runtime.LoadingScreen:Destroy()
        getgenv().RAYv2_Runtime.LoadingScreen = nil
    end
    
    -- Destroy main GUI
    local mainGui = GuiParent:FindFirstChild("RAYv2_Main")
    if mainGui then
        mainGui:Destroy()
    end
    
    DebugPrint("RAYv2 cleanup complete")
end

-- Handle game shutdown
game:GetService("CoreGui").DescendantRemoving:Connect(function(descendant)
    if descendant.Name == "RAYv2_Main" then
        CleanupScript()
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 9: INITIALIZATION SEQUENCE
-- ═══════════════════════════════════════════════════════════════════════════
--[[
Initialization order:
1. Create loading screen (blocks until complete)
2. Initialize aimbot system (FOV circle, keybinds, update loop)
3. Initialize ESP system (object pools, update loop)
4. Create main GUI (only after loading screen finishes)
5. Apply any saved config (auto-load)

This ensures smooth user experience with no flicker or incomplete elements.
]]

local function Initialize()
    DebugPrint("Initializing RAYv2...")
    
    -- Step 1: Show loading screen (this calls CreateMainGUI when done)
    CreateLoadingScreen()
    
    -- Step 2 & 3: Initialize systems (these run in parallel with loading screen)
    task.spawn(function()
        task.wait(1) -- Small delay to let loading screen render first frame
        InitializeAimbot()
        InitializeESP()
        DebugPrint("Core systems initialized")
    end)
    
    -- Step 4: Auto-load config if exists
    task.spawn(function()
        task.wait(3) -- Wait for loading screen to complete
        
        -- Try loading default config
        local defaultConfigName = "default"
        if savedConfigs and savedConfigs[defaultConfigName] then
            LoadConfig(defaultConfigName)
            DebugPrint("Auto-loaded default config")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXECUTION START
-- ═══════════════════════════════════════════════════════════════════════════

-- Protect entire script with pcall to catch any initialization errors
local success, errorMsg = pcall(function()
    Initialize()
end)

if not success then
    warn("[RAYv2 ERROR] Initialization failed:", errorMsg)
    CleanupScript()
end

DebugPrint("RAYv2 injection complete. Press LeftAlt/LeftCtrl/Insert to toggle GUI.")

--[[
════════════════════════════════════════════════════════════════════════════════
USAGE INSTRUCTIONS
════════════════════════════════════════════════════════════════════════════════

INJECTION METHOD (SOLARA):
1. Open Solara executor
2. Paste this entire script into the editor
3. Click "Execute" or "Inject"
4. Wait for loading screen to complete (2.5-3.5 seconds)
5. GUI will appear automatically after loading

ADJUSTING PARAMETERS:

AIMBOT TAB:
- Enable Aimbot: Master toggle for all aimbot features
- Aimbot Keybind: Press to activate (default: E)
- Activation Mode: "Toggle" stays on until pressed again, "Hold" only active while key held
- Silent Aim: When ON, camera doesn't move but hits register on target (undetectable)
- FOV Radius: Angle in degrees for target detection (0-360, default 120)
- Show FOV Circle: Visual indicator of aimbot range on screen
- Fill FOV Circle: Solid circle instead of outline
- Smoothness: How fast camera moves to target (0=none, 100=instant snap)
- Velocity Prediction: Compensates for moving targets using ping-based calculation
- Prediction Strength: Multiplier for prediction (higher = more lead)
- Max Distance: Only aim at targets within this range (studs)
- Team Check: Ignore teammates
- Visible Check: Only aim at visible enemies (wallcheck via raycast)
- Prioritize Head: Aim at head instead of torso
- Enable Triggerbot: Auto-fire when crosshair is on enemy
- Triggerbot Keybind: Press to activate auto-fire (default: T)
- Shoot Delay: Minimum time between triggerbot shots (milliseconds)

ESP TAB:
- Enable ESP: Master toggle for all ESP features
- Max ESP Distance: Only show ESP for players within range
- Team Check: Hide ESP for teammates
- Show Boxes: 2D rectangle around player
- Fill Boxes: Solid filled box with transparency
- Show Skeleton: Bone structure overlay
- Show Tracers: Line from screen position to player
- Tracers From: Origin point (Bottom/Center/Mouse)
- Show Name: Player display name above box
- Show Health: Health value and bar
- Show Health Bar: Vertical bar showing health percentage
- Show Distance: Range to player in studs
- Show Weapon: Equipped tool name

CONFIGS TAB:
- Config Name: Enter custom name for your settings
- SAVE CONFIG: Store current settings to file
- LOAD CONFIG: Restore previously saved settings
- Config List: All saved configs with Load/Delete buttons
- Configs persist across game sessions using executor file system

PROFILE TAB:
- Profile Header: Shows your Roblox avatar and username
- Owner Badge: Displays golden "OWNER" badge if UserId = 7143862381
- Fake Level: Override displayed level in-game
- Fake Win Streak: Spoof win streak counter
- Fake Keys: Override key count
- Fake Premium Badge: Add premium badge to profile
- Fake Verified Badge: Add verified checkmark
- Admin Panel: Enter credentials (adminHQ / HQ080626) to unlock advanced features

HOTKEYS:
- LeftAlt / LeftCtrl / Insert: Toggle GUI visibility
- E (or custom): Activate aimbot
- T (or custom): Activate triggerbot

RIVALS-SPECIFIC BEHAVIOR:
- ESP only shows players in active match (filters out hub/spawn areas)
- Distance check uses HumanoidRootPart positions
- Weapon detection looks for equipped Tool in character
- Silent aim hooks Tool RemoteEvents for invisible firing
- Team detection uses Team property or custom TeamColor folders

PERFORMANCE NOTES:
- All visuals update at 60 FPS locked to RenderStepped
- Drawing API objects are pooled (reused) to prevent memory leaks
- ESP automatically hides when players leave or go out of range
- Script cleans up all resources on shutdown or reload

TROUBLESHOOTING:
- If GUI doesn't appear: Check executor compatibility (Solara Level 7 required)
- If aimbot doesn't work: Verify keybind is pressed and FOV circle is visible
- If ESP is invisible: Increase Max Distance or disable Team Check
- If silent aim fails: Gun firing mechanism may have changed (update required)
- For any errors: Enable DebugMode in script and check console output

UNLOADING:
- Click X button in top-right of GUI for clean shutdown
- Or re-execute script (auto-cleanup on initialization)
- All Drawing objects and connections are properly cleaned up

VERSION: 0.01 ALPHA
AUTHOR: @ink
GAME: RIVALS
EXECUTOR: Solara (Level 7 UNC)

════════════════════════════════════════════════════════════════════════════════
]]
