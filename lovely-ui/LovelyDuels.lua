--[[
    Lovely Duels
    Client UI. Put this in a LocalScript (StarterPlayerScripts).

    Layouts, switchable live from Settings > UI Style:
        Adapt Style - big centred title, tabs along the bottom
        Candy Style - avatar + title header, tabs along the top, image backdrop
        Bubble Hub Style - image title, outlined pill rows, dot toggles, pill tabs along the bottom
        Ambitious Hub Style - big image title, boxed tabs on top, glassy rows that outline when on
        VX7 Style - logo tile header with a window-scale pill, boxed section rows, Bangers font

    Elements are built with option tables:
        Tab:Toggle      { Name, Default, Callback, Flag, List }   -- List = false keeps it off the active list
        Tab:Number      { Name, Default, Min, Max, Callback, Flag }
        Tab:Slider      { Name, Min, Max, Default, Step, Suffix, Callback, Flag }
        Tab:Cycle       { Name, Options, Default, Callback, Flag }
        Tab:Segment     { Name, Options, Default, Callback, Flag }
        Tab:Keybind     { Name, Default, Callback, Changed, Flag }
        Tab:Dropdown    { Name, Options, Default, Callback, Flag }
        Tab:ColorPicker { Name, Default, Callback, Flag }
        Tab:Button      { Name, Tag, Callback }

    Current values live in Library.Flags[flag]; element objects in Library.Elements[flag].
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local TextService      = game:GetService("TextService")
local Debris           = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

-- phones and tablets: a touch screen with no keyboard
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local Theme = {
    Background = Color3.fromRGB(10, 8, 14),
    Panel      = Color3.fromRGB(16, 12, 20),
    Row        = Color3.fromRGB(21, 16, 26),
    RowHover   = Color3.fromRGB(31, 23, 37),
    Stroke     = Color3.fromRGB(56, 40, 66),
    Off        = Color3.fromRGB(54, 42, 60),
    Accent     = Color3.fromRGB(255, 105, 180),
    AccentDark = Color3.fromRGB(90, 30, 64),
    AccentGlow = Color3.fromRGB(255, 200, 230),
    Secondary  = Color3.fromRGB(170, 100, 255),
    Text       = Color3.fromRGB(245, 236, 245),
    SubText    = Color3.fromRGB(164, 142, 170),
}

-- Raw sources. Swap these ids for your own if any of them stop loading.
local SOUND_SOURCES = {
    Click = "rbxassetid://6895079853",
    Tick  = "rbxassetid://12221967",
}

-- Each cue is a stack of layers: { source, semitones, volume, delay }.
-- Pitches are in semitones so chords and arpeggios stay in tune.
-- Kept low and quiet on purpose: pitching samples up past ~+5 makes them thin and piercing.
local SFX = {
    Click  = { { "Click", -5, 0.22 } },
    On     = { { "Click", -3, 0.22 }, { "Tick", 0, 0.04, 0.03 } },
    Off    = { { "Click", -8, 0.20 } },
    Open   = { { "Tick", -12, 0.08 }, { "Tick", -8, 0.08, 0.05 }, { "Tick", -5, 0.08, 0.10 }, { "Click", -5, 0.14, 0.10 } },
    Close  = { { "Tick", -5, 0.08 }, { "Tick", -8, 0.08, 0.05 }, { "Click", -10, 0.14, 0.09 } },
    Notify = { { "Tick", -5, 0.10 }, { "Tick", 0, 0.08, 0.09 } },
    Drop   = { { "Click", -12, 0.18 } },
    Tick   = { { "Tick", -7, 0.07 } },
    Ready  = { { "Tick", -12, 0.08 }, { "Tick", -8, 0.08, 0.05 }, { "Tick", -5, 0.08, 0.10 }, { "Click", -5, 0.14, 0.15 } },
    Swap   = { { "Click", -10, 0.18 }, { "Click", -5, 0.16, 0.08 } },
    -- intro and lock screen each get their own cue so nothing repeats back to back
    Pop     = { { "Click", -9, 0.16 }, { "Tick", -5, 0.05, 0.04 } },
    Shimmer = { { "Tick", -12, 0.05 }, { "Tick", -8, 0.05, 0.06 }, { "Tick", -5, 0.05, 0.12 }, { "Tick", 0, 0.04, 0.18 } },
    Unlock  = { { "Click", -7, 0.18 }, { "Tick", -3, 0.06, 0.05 }, { "Tick", 2, 0.05, 0.11 } },
}

local Settings = {
    Sounds     = true,
    Volume     = 1,
    ToggleKey  = Enum.KeyCode.RightShift,
    Backdrop   = "Particles", -- Particles, Hearts, Leaves, Matrix, Off
    Cursor     = true,
    Intro      = true,  -- animated loading intro on start
    LockScreen = true,  -- swipe-to-unlock screen after the intro
    Rainbow    = false,
    ReduceMotion = false, -- turns off particles, border spin and the big animations
    Aurora     = true,    -- slow drifting glows behind the rows
    Snap       = true,    -- window snaps to screen edges and the centre line after a drag
    Font       = "Default", -- any Enum.Font name; Default keeps each style's own fonts
    UIScale    = 1,
    -- optional backdrops, e.g. "rbxassetid://123456"; leave empty for the built-in gradients
    CandyImage  = "",
    BubbleImage = "",
    AmbitiousImage = "",
    VX7Image    = "",
    BubbleTitle = "rbxassetid://103526312854328",
    MobileButtons = IS_MOBILE, -- on-screen buttons for the keybinds
}

local CONFIG_FILE = "LovelyDuels.json"
local CONFIG_VERSION = 3 -- bump when defaults change so stale saves aren't loaded
local WINDOW_W, WINDOW_H = 340, 520

-- on phones, shrink the window so the whole thing fits on screen
if IS_MOBILE then
    local camera = workspace.CurrentCamera
    local view = camera and camera.ViewportSize or Vector2.new(800, 600)
    Settings.UIScale = math.clamp(math.min((view.Y - 30) / WINDOW_H, (view.X - 30) / WINDOW_W), 0.55, 1)
end

local Library = {
    Flags       = {},
    Elements    = {},
    Tabs        = {},
    Rows        = {},
    Connections = {},
    Visible     = false,
    Binding     = false,
    Searching   = false,
    Style       = "Adapt",
}

------------------------------------------------------------------------
-- helpers

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if props and props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

local function tween(obj, time, props, style, direction)
    local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- tiny damped spring, stepped every frame; gives motion a slight overshoot and settle
local springs = {}

local function springTo(key, from, to, apply, freq, damping)
    local s = springs[key]
    if not s then
        s = { x = from, v = 0 }
        springs[key] = s
    end
    s.target, s.apply, s.freq, s.damp = to, apply, freq or 16, damping or 0.6
end

local function stopSpring(key)
    springs[key] = nil
end

local function stepSprings(dt)
    dt = math.min(dt, 1 / 30)
    for key, s in pairs(springs) do
        local accel = s.freq * s.freq * (s.target - s.x) - 2 * s.damp * s.freq * s.v
        s.v += accel * dt
        s.x += s.v * dt
        if math.abs(s.target - s.x) < 0.01 and math.abs(s.v) < 0.05 then
            s.x = s.target
            springs[key] = nil
        end
        s.apply(s.x)
    end
end

local function decimalsOf(n)
    local d = tostring(n):match("%.(%d+)")
    return d and #d or 0
end

-- counts a label or box from one number to another instead of jumping
local function rollText(obj, from, to, decimals, suffix, time)
    local value = obj:FindFirstChild("RollValue")
    if not value then
        value = Instance.new("NumberValue")
        value.Name = "RollValue"
        value.Parent = obj
        value.Changed:Connect(function(v)
            obj.Text = string.format("%." .. obj:GetAttribute("RollDecimals") .. "f", v) .. obj:GetAttribute("RollSuffix")
        end)
    end
    obj:SetAttribute("RollDecimals", decimals)
    obj:SetAttribute("RollSuffix", suffix or "")
    value.Value = from
    tween(value, time or 0.35, { Value = to }, Enum.EasingStyle.Quart)
end

local function corner(radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness, transparency)
    return new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function pad(top, bottom, left, right)
    return new("UIPadding", {
        PaddingTop = UDim.new(0, top),
        PaddingBottom = UDim.new(0, bottom),
        PaddingLeft = UDim.new(0, left),
        PaddingRight = UDim.new(0, right),
    })
end

-- a heart built from a rotated square and two circles; returns the holder and its three parts
local function makeHeart(parent, size, zindex)
    local heart = new("Frame", {
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local parts = {
        new("Frame", {
            Size = UDim2.fromScale(0.6, 0.6),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.62),
            Rotation = 45,
            BorderSizePixel = 0,
            ZIndex = zindex or 1,
            Parent = heart,
        }),
    }
    for _, x in ipairs({ 0.3, 0.7 }) do
        table.insert(parts, new("Frame", {
            Size = UDim2.fromScale(0.6, 0.6),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(x, 0.38),
            BorderSizePixel = 0,
            ZIndex = zindex or 1,
            Parent = heart,
        }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }))
    end
    return heart, parts
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Library.Connections, c)
    return c
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function isCandy()
    return Library.Style == "Candy"
end

local function isBubble()
    return Library.Style == "Bubble"
end

local function isAmbitious()
    return Library.Style == "Ambitious"
end

local function isVX7()
    return Library.Style == "VX7"
end

-- theme hooks: run now, and again whenever the accent colour or the style changes
local themed = {}

local function onTheme(fn)
    table.insert(themed, fn)
    fn()
end

local function accent(obj, prop, key)
    onTheme(function()
        local color = Theme[key or "Accent"]
        -- while a theme change is fading, colours blend over a third of a second instead of snapping
        if Library.Fade and obj.Parent then
            tween(obj, 0.35, { [prop] = color })
        else
            obj[prop] = color
        end
    end)
    return obj
end

local function shineSequence()
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Accent),
        ColorSequenceKeypoint.new(0.42, Theme.Accent),
        ColorSequenceKeypoint.new(0.5, Theme.AccentGlow),
        ColorSequenceKeypoint.new(0.58, Theme.Accent),
        ColorSequenceKeypoint.new(1, Theme.Secondary),
    })
end

------------------------------------------------------------------------
-- gui root

local Gui = new("ScreenGui", {
    Name = "LovelyDuels",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})

do
    local ok = pcall(function()
        local target = (gethui and gethui()) or game:GetService("CoreGui")
        local old = target:FindFirstChild(Gui.Name)
        if old then old:Destroy() end
        Gui.Parent = target
    end)
    if not ok then
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        local old = playerGui:FindFirstChild(Gui.Name)
        if old then old:Destroy() end
        Gui.Parent = playerGui
    end
end

------------------------------------------------------------------------
-- sound

-- everything runs through one group so it shares the same room and loudness
-- the group volume is the master loudness: the EQ and compressor below eat a lot of level, so it's boosted here
local SoundBus = new("SoundGroup", { Name = "LovelySFX", Volume = 2.5, Parent = Gui }, {
    -- roll off the harsh top end, which is what makes clicks hurt
    new("EqualizerSoundEffect", { LowGain = 0, MidGain = -4, HighGain = -18, Priority = 3 }),
    new("CompressorSoundEffect", { Threshold = -24, Ratio = 6, Attack = 0.002, Release = 0.1, Priority = 2 }),
    new("ReverbSoundEffect", { DecayTime = 0.5, Density = 0.9, Diffusion = 1, DryLevel = 0, WetLevel = -22, Priority = 1 }),
})

-- small pool per source so rapid clicks don't create and destroy instances
local pools = {}

local function grab(source)
    local pool = pools[source]
    if not pool then
        pool = {}
        pools[source] = pool
    end
    for _, sound in ipairs(pool) do
        if not sound.IsPlaying then return sound end
    end
    if #pool >= 8 then return pool[1] end
    local sound = new("Sound", { SoundId = SOUND_SOURCES[source], SoundGroup = SoundBus, Parent = SoundBus })
    table.insert(pool, sound)
    return sound
end

local function playLayer(source, semitones, volume)
    local sound = grab(source)
    -- a hair of random detune keeps repeated clicks from sounding robotic
    local detune = 1 + (math.random() - 0.5) * 0.025
    -- hard cap so nothing (scale runs, shifts) ever gets pitched up into shrill territory
    semitones = math.min(semitones, 2)
    sound.PlaybackSpeed = 2 ^ (semitones / 12) * detune
    sound.Volume = volume * Settings.Volume
    sound.TimePosition = 0
    sound:Play()
end

-- the same cue fired twice in a blink just sounds like a glitch, so the repeat is dropped
local lastPlayed = {}

-- shift transposes the whole cue by that many semitones
local function play(name, shift)
    if not Settings.Sounds then return end
    local cue = SFX[name]
    if not cue then return end
    local now = os.clock()
    if lastPlayed[name] and now - lastPlayed[name] < 0.06 then return end
    lastPlayed[name] = now
    shift = shift or 0
    for _, layer in ipairs(cue) do
        local source, semitones, volume, delay = layer[1], layer[2] + shift, layer[3], layer[4]
        if delay and delay > 0 then
            task.delay(delay, playLayer, source, semitones, volume)
        else
            playLayer(source, semitones, volume)
        end
    end
end

-- warm the pools so the first click isn't silent while the asset loads
task.spawn(function()
    local preload = {}
    for source in pairs(SOUND_SOURCES) do
        table.insert(preload, grab(source))
    end
    pcall(function()
        game:GetService("ContentProvider"):PreloadAsync(preload)
    end)
end)

-- hovering is silent; kept as a no-op so the hover hooks stay in place
local function hoverSound() end

------------------------------------------------------------------------
-- dragging

local function makeDraggable(handle, target, onClick, onDrop)
    local dragging, moved, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        dragging, moved = true, false
        dragStart, startPos = input.Position, target.Position

        local endConn
        endConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                endConn:Disconnect()
                if not moved and onClick then
                    onClick()
                elseif moved and onDrop then
                    task.delay(0.1, onDrop)
                end
            end
        end)
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging or not isMove(input) then return end
        local delta = input.Position - dragStart
        if delta.Magnitude > 4 then moved = true end
        if moved then
            tween(target, 0.08, {
                Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y),
            }, Enum.EasingStyle.Sine)
        end
    end)
end

------------------------------------------------------------------------
-- window

local Holder = new("Frame", {
    Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = Gui,
})
local HolderScale = new("UIScale", { Scale = 0.85, Parent = Holder })

local Shadow = new("ImageLabel", {
    Size = UDim2.new(1, 46, 1, 46),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundTransparency = 1,
    Image = "rbxassetid://6014261993",
    ImageColor3 = Color3.new(0, 0, 0),
    ImageTransparency = 1,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(49, 49, 450, 450),
    Parent = Holder,
})
-- the shadow glows faintly in the accent colour instead of being plain black
onTheme(function()
    Shadow.ImageColor3 = Theme.AccentDark
end)

-- CanvasGroup so the whole window can fade as one
local Main = new("CanvasGroup", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    GroupTransparency = 1,
    Parent = Holder,
})
local MainCorner = corner(12)
MainCorner.Parent = Main

-- animated border: a highlight that orbits the window edge
local MainStroke = stroke(Color3.new(1, 1, 1), 1.5)
MainStroke.Parent = Main
local BorderSpin = new("UIGradient", { Parent = MainStroke })
onTheme(function()
    BorderSpin.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Stroke),
        ColorSequenceKeypoint.new(0.38, Theme.Stroke),
        ColorSequenceKeypoint.new(0.46, Theme.Accent),
        ColorSequenceKeypoint.new(0.54, Theme.Secondary),
        ColorSequenceKeypoint.new(0.62, Theme.Stroke),
        ColorSequenceKeypoint.new(1, Theme.Stroke),
    })
end)

-- depth: the window gets a touch darker toward the bottom edge
new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BorderSizePixel = 0,
    Parent = Main,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0.62),
        }),
    }),
})

-- a soft accent highlight along the top edge of the window
accent(new("Frame", {
    Size = UDim2.new(1, -40, 0, 1),
    Position = UDim2.fromOffset(20, 0),
    BorderSizePixel = 0,
    Parent = Main,
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.15),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3")

-- Adapt backdrop: faint haze behind the title
local Haze = accent(new("Frame", {
    Size = UDim2.new(1, 0, 0, 160),
    BorderSizePixel = 0,
    Parent = Main,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.86),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3")

-- Candy backdrop: optional image plus two soft glows in opposite corners
local CandyBg = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Main,
})

new("ImageLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = Settings.CandyImage,
    ImageTransparency = 0.35,
    ScaleType = Enum.ScaleType.Crop,
    Parent = CandyBg,
})

accent(new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
    Parent = CandyBg,
}, {
    new("UIGradient", {
        Rotation = -40,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.72),
            NumberSequenceKeypoint.new(0.45, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3")

accent(new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
    Parent = CandyBg,
}, {
    new("UIGradient", {
        Rotation = 140,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.8),
            NumberSequenceKeypoint.new(0.4, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3", "Secondary")

-- Bubble backdrop: deep vertical gradient with soft light rays from the top
local BubbleBg = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Parent = Main,
})
local bubbleGradient = new("UIGradient", { Rotation = 90, Parent = BubbleBg })
onTheme(function()
    bubbleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentDark),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(18, 10, 24)),
        ColorSequenceKeypoint.new(1, Theme.Background),
    })
end)

new("ImageLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = Settings.BubbleImage,
    ImageTransparency = 0.3,
    ScaleType = Enum.ScaleType.Crop,
    Parent = BubbleBg,
})

for i, ray in ipairs({ { 40, 18, -14 }, { 120, 30, -6 }, { 200, 14, 8 }, { 255, 24, 16 } }) do
    new("Frame", {
        Size = UDim2.fromOffset(ray[2], 360),
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromOffset(ray[1], -40),
        Rotation = ray[3],
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = BubbleBg,
    }, {
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.86 + i * 0.015),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })
end

-- Ambitious backdrop: optional big faded image washed with the accent from the top
local AmbitiousBg = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Main,
})

new("ImageLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = Settings.AmbitiousImage,
    ImageTransparency = 0.55,
    ScaleType = Enum.ScaleType.Crop,
    Parent = AmbitiousBg,
})

accent(new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
    Parent = AmbitiousBg,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.55),
            NumberSequenceKeypoint.new(0.6, 0.92),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3", "AccentDark")

-- VX7 backdrop: optional image with an accent glow sweeping in from the top corner
local VX7Bg = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Main,
})

new("ImageLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = Settings.VX7Image,
    ImageTransparency = 0.45,
    ScaleType = Enum.ScaleType.Crop,
    Parent = VX7Bg,
})

accent(new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
    Parent = VX7Bg,
}, {
    new("UIGradient", {
        Rotation = -135,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(0.5, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3")

-- living background: three big soft glows drift slowly behind the rows, like an aurora
do
    local layer = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = Main,
    })
    Library.AuroraLayer = layer
    local blobs = {}
    for i, spec in ipairs({ { "Accent", 330, 0 }, { "Secondary", 300, 2.1 }, { "Accent", 260, 4.2 } }) do
        local blob = new("Frame", {
            Size = UDim2.fromOffset(spec[2], spec[2]),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Parent = layer,
        })
        -- stacked faint circles read as one soft radial glow
        local rings = {}
        for r = 1, 8 do
            local sc = 1 - (r - 1) * 0.11
            rings[r] = new("Frame", {
                Size = UDim2.fromScale(sc, sc),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                BackgroundTransparency = 0.965,
                BorderSizePixel = 0,
                Parent = blob,
            }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
        end
        blobs[i] = { Frame = blob, Rings = rings, Key = spec[1], Phase = spec[3] }
    end
    onTheme(function()
        for _, b in ipairs(blobs) do
            for _, ring in ipairs(b.Rings) do
                ring.BackgroundColor3 = Theme[b.Key]
            end
        end
    end)
    layer.Visible = Settings.Aurora
    connect(RunService.RenderStepped, function()
        if not Holder.Visible or not layer.Visible then return end
        local t = Settings.ReduceMotion and 0 or os.clock()
        for _, b in ipairs(blobs) do
            b.Frame.Position = UDim2.fromScale(0.5 + 0.42 * math.sin(t * 0.11 + b.Phase), 0.5 + 0.42 * math.cos(t * 0.083 + b.Phase * 1.3))
        end
    end)
end

-- floating particles sit behind everything else in the window
local SnowLayer = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Main,
})

local flakes = {}
for i = 1, 30 do
    local size = math.random(2, 3)
    local alpha = 0.45 + math.random() * 0.4
    flakes[i] = {
        X = math.random(0, WINDOW_W),
        Y = math.random(0, WINDOW_H),
        Speed = math.random(10, 26),
        Phase = math.random() * math.pi * 2,
        Sway = math.random(3, 8),
        Size = size,
        Alpha = alpha,
        Frame = new("Frame", {
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = alpha,
            BorderSizePixel = 0,
            Parent = SnowLayer,
        }, { corner(2) }),
    }
end

-- hearts: little pink and purple hearts drifting up through the window
local HeartLayer = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = Main,
})

local hearts = {}
for i = 1, 18 do
    local frame, parts = makeHeart(HeartLayer, math.random(7, 12))
    hearts[i] = {
        Frame = frame,
        Parts = parts,
        X = math.random(0, WINDOW_W),
        Y = math.random(0, WINDOW_H),
        Speed = math.random(14, 30),
        Phase = math.random() * math.pi * 2,
        Sway = math.random(4, 10),
        Purple = i % 2 == 0,
    }
end

onTheme(function()
    for _, h in ipairs(hearts) do
        for _, p in ipairs(h.Parts) do
            p.BackgroundColor3 = h.Purple and Theme.Secondary or Theme.Accent
        end
    end
end)

-- matrix rain: columns of glyphs falling in the accent colour
local MatrixLayer = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = Main,
})

local MATRIX_CHARS = "01LOVE#$%&*+<>=?"

local function matrixText()
    local chars = {}
    for i = 1, 16 do
        local k = math.random(#MATRIX_CHARS)
        chars[i] = MATRIX_CHARS:sub(k, k)
    end
    return table.concat(chars, "\n")
end

local columns = {}
for i = 1, 14 do
    local label = accent(new("TextLabel", {
        Size = UDim2.fromOffset(14, 230),
        BackgroundTransparency = 1,
        Text = matrixText(),
        Font = Enum.Font.Code,
        TextSize = 11,
        TextTransparency = 0.45,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = MatrixLayer,
    }, {
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
        }),
    }), "TextColor3")
    columns[i] = {
        Label = label,
        X = (i - 0.5) * (WINDOW_W / 14) - 7,
        Y = math.random(-230, WINDOW_H),
        Speed = math.random(40, 95),
    }
end

local LEAF_COLORS = {
    Color3.fromRGB(214, 120, 40),
    Color3.fromRGB(190, 60, 40),
    Color3.fromRGB(230, 180, 60),
    Color3.fromRGB(150, 90, 40),
}

-- the same 30 particles get restyled for leaves and floating particles
local function applyBackdrop(mode)
    Settings.Backdrop = mode
    local calm = Settings.ReduceMotion
    SnowLayer.Visible = not calm and (mode == "Leaves" or mode == "Particles")
    MatrixLayer.Visible = not calm and mode == "Matrix"
    HeartLayer.Visible = not calm and mode == "Hearts"
    for i, f in ipairs(flakes) do
        local frame = f.Frame
        frame.Rotation = 0
        if mode == "Leaves" then
            frame.Size = UDim2.fromOffset(6, 3)
            frame.BackgroundColor3 = LEAF_COLORS[(i - 1) % #LEAF_COLORS + 1]
            frame.BackgroundTransparency = 0.2
        elseif mode == "Particles" then
            frame.Size = UDim2.fromOffset(3, 3)
            frame.BackgroundColor3 = Theme.Accent
        else
            frame.Size = UDim2.fromOffset(f.Size, f.Size)
            frame.BackgroundColor3 = Color3.new(1, 1, 1)
            frame.BackgroundTransparency = f.Alpha
        end
    end
end

applyBackdrop(Settings.Backdrop)

onTheme(function()
    if Settings.Backdrop ~= "Particles" then return end
    for _, f in ipairs(flakes) do
        f.Frame.BackgroundColor3 = Theme.Accent
    end
end)

local Header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 88),
    BackgroundTransparency = 1,
    Active = true,
    Parent = Main,
})

-- Adapt header -------------------------------------------------------

local AdaptHeader = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Header,
})

-- drop layer for depth
accent(new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 50),
    Position = UDim2.fromOffset(0, 18),
    BackgroundTransparency = 1,
    Text = "LOVELY",
    Font = Enum.Font.FredokaOne,
    TextSize = 48,
    Parent = AdaptHeader,
}), "TextColor3", "AccentDark")

local Title = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 50),
    Position = UDim2.fromOffset(0, 14),
    BackgroundTransparency = 1,
    Text = "LOVELY",
    Font = Enum.Font.FredokaOne,
    TextSize = 48,
    TextColor3 = Color3.new(1, 1, 1),
    Parent = AdaptHeader,
}, {
    new("UIStroke", { Color = Color3.fromRGB(24, 8, 22), Thickness = 1.5 }),
})

local TitleShine = new("UIGradient", { Rotation = 20, Parent = Title })
onTheme(function()
    TitleShine.Color = shineSequence()
end)

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.fromOffset(0, 66),
    BackgroundTransparency = 1,
    Text = "D  U  E  L  S",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = Theme.Text,
    TextTransparency = 0.25,
    Parent = AdaptHeader,
})

-- thin rule under the title that fades out at both ends
accent(new("Frame", {
    Size = UDim2.new(1, -60, 0, 1),
    Position = UDim2.fromOffset(30, 85),
    BorderSizePixel = 0,
    Parent = AdaptHeader,
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.4),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
}), "BackgroundColor3")

-- Candy header -------------------------------------------------------

local CandyHeader = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Header,
})

local CandyAvatar = new("ImageLabel", {
    Size = UDim2.fromOffset(36, 36),
    Position = UDim2.fromOffset(14, 13),
    BackgroundColor3 = Theme.Row,
    Parent = CandyHeader,
}, { corner(18) })
accent(stroke(Theme.Accent, 2), "Color").Parent = CandyAvatar

local CandyTitle = new("TextLabel", {
    Size = UDim2.new(1, -110, 0, 36),
    Position = UDim2.fromOffset(58, 13),
    BackgroundTransparency = 1,
    RichText = true,
    Font = Enum.Font.FredokaOne,
    TextSize = 24,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = CandyHeader,
}, {
    new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.3 }),
})
onTheme(function()
    CandyTitle.Text = string.format('LOVELY <font color="#%s">DUELS</font>', Theme.Accent:ToHex())
end)

accent(new("Frame", {
    Size = UDim2.new(1, -24, 0, 1),
    Position = UDim2.fromOffset(12, 61),
    BorderSizePixel = 0,
    Parent = CandyHeader,
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 0.85),
        }),
    }),
}), "BackgroundColor3")

-- Bubble header -------------------------------------------------------

local BubbleHeader = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Header,
})

new("ImageLabel", {
    Size = UDim2.new(1, -90, 0, 58),
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 8),
    BackgroundTransparency = 1,
    Image = Settings.BubbleTitle,
    ScaleType = Enum.ScaleType.Fit,
    Parent = BubbleHeader,
})

-- Ambitious header ----------------------------------------------------

local AmbitiousHeader = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Header,
})

accent(new("TextLabel", {
    Size = UDim2.fromOffset(80, 14),
    Position = UDim2.fromOffset(14, 12),
    BackgroundTransparency = 1,
    Text = "LOVELY",
    Font = Enum.Font.GothamBlack,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = AmbitiousHeader,
}), "TextColor3")

new("ImageLabel", {
    Size = UDim2.new(1, -40, 0, 70),
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 20),
    BackgroundTransparency = 1,
    Image = Settings.BubbleTitle,
    ScaleType = Enum.ScaleType.Fit,
    Parent = AmbitiousHeader,
})

-- VX7 header ----------------------------------------------------------

local VX7Header = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = Header,
})

-- dark band across the top with an accent rule underneath
new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    Parent = VX7Header,
})

accent(new("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    BorderSizePixel = 0,
    Parent = VX7Header,
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(0.5, 0.45),
            NumberSequenceKeypoint.new(1, 0.1),
        }),
    }),
}), "BackgroundColor3")

accent(new("Frame", {
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.fromOffset(14, 16),
    Parent = VX7Header,
}, {
    corner(10),
    new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 120)) }),
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "LD",
        Font = Enum.Font.Bangers,
        TextSize = 22,
        TextColor3 = Color3.new(1, 1, 1),
    }, {
        new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5 }),
    }),
}), "BackgroundColor3")

accent(new("TextLabel", {
    Size = UDim2.fromOffset(108, 22),
    Position = UDim2.fromOffset(68, 20),
    BackgroundTransparency = 1,
    Text = "LOVELY DUELS",
    Font = Enum.Font.Bangers,
    TextSize = 20,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = VX7Header,
}), "TextColor3")

accent(new("Frame", {
    Size = UDim2.fromOffset(86, 2),
    Position = UDim2.fromOffset(68, 46),
    BorderSizePixel = 0,
    Parent = VX7Header,
}, {
    corner(1),
    new("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
}), "BackgroundColor3")

-- "-  100%  +" pill that scales the whole window
-- kept narrow so it doesn't run into the title
local scalePill = new("Frame", {
    Size = UDim2.fromOffset(66, 26),
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -50, 0, 24),
    BackgroundColor3 = Theme.Panel,
    BackgroundTransparency = 0.2,
    Parent = VX7Header,
}, { corner(10), stroke(Theme.Stroke, 1) })

local scaleLabel = new("TextLabel", {
    Size = UDim2.new(1, -36, 1, 0),
    Position = UDim2.fromOffset(18, 0),
    BackgroundTransparency = 1,
    Text = "100%",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = Theme.Text,
    Parent = scalePill,
})

local function setUIScale(value)
    Settings.UIScale = math.clamp(math.floor(value * 20 + 0.5) / 20, 0.6, 1.3)
    scaleLabel.Text = math.floor(Settings.UIScale * 100 + 0.5) .. "%"
    if Library.Visible then
        springTo(HolderScale, HolderScale.Scale, Settings.UIScale, function(v)
            HolderScale.Scale = v
        end, 14, 0.5)
    end
end

for _, sign in ipairs({ -1, 1 }) do
    local b = new("TextButton", {
        Size = UDim2.fromOffset(18, 26),
        AnchorPoint = Vector2.new(sign < 0 and 0 or 1, 0),
        Position = UDim2.fromScale(sign < 0 and 0 or 1, 0),
        BackgroundTransparency = 1,
        Text = sign < 0 and "-" or "+",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.SubText,
        AutoButtonColor = false,
        Parent = scalePill,
    })
    b.MouseEnter:Connect(function()
        tween(b, 0.15, { TextColor3 = Theme.Accent })
        hoverSound()
    end)
    b.MouseLeave:Connect(function()
        tween(b, 0.2, { TextColor3 = Theme.SubText })
    end)
    b.MouseButton1Click:Connect(function()
        play("Click", sign * 2)
        setUIScale(Settings.UIScale + sign * 0.05)
    end)
end

------------------------------------------------------------------------

local MinButton = new("TextButton", {
    Size = UDim2.fromOffset(24, 24),
    AnchorPoint = Vector2.new(1, 0),
    BackgroundColor3 = Theme.Row,
    Text = "-",
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Theme.SubText,
    AutoButtonColor = false,
    Parent = Header,
}, { corner(6), stroke(Theme.Stroke, 1) })

-- search bar
local searchStroke = stroke(Theme.Stroke, 1)
local SearchBar = new("Frame", {
    Size = UDim2.new(1, -24, 0, 30),
    BackgroundColor3 = Theme.Row,
    Parent = Main,
}, { searchStroke })
local searchCorner = corner(10)
searchCorner.Parent = SearchBar

-- magnifier drawn from two frames
new("Frame", {
    Size = UDim2.fromOffset(9, 9),
    Position = UDim2.fromOffset(11, 9),
    BackgroundTransparency = 1,
    Parent = SearchBar,
}, { corner(5), stroke(Theme.SubText, 1.5) })
new("Frame", {
    Size = UDim2.fromOffset(5, 2),
    Position = UDim2.fromOffset(18, 19),
    Rotation = 45,
    BackgroundColor3 = Theme.SubText,
    BorderSizePixel = 0,
    Parent = SearchBar,
}, { corner(1) })

local SearchBox = new("TextBox", {
    Size = UDim2.new(1, -60, 1, 0),
    Position = UDim2.fromOffset(32, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "Search features",
    PlaceholderColor3 = Theme.SubText,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    Parent = SearchBar,
})

local ClearSearch = new("TextButton", {
    Size = UDim2.fromOffset(20, 20),
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -6, 0.5, 0),
    BackgroundTransparency = 1,
    Text = "x",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Theme.SubText,
    Visible = false,
    Parent = SearchBar,
})

local Pages = new("Frame", {
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Parent = Main,
})

-- player card (Adapt only; Candy shows the avatar in its header)
local Card = new("Frame", {
    Size = UDim2.new(1, -16, 0, 40),
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -52),
    BackgroundColor3 = Theme.Panel,
    Parent = Main,
}, { corner(10), stroke(Theme.Stroke, 1) })

local Avatar = new("ImageLabel", {
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.fromOffset(5, 3),
    BackgroundColor3 = Theme.Row,
    Parent = Card,
}, { corner(17) })
accent(stroke(Theme.Accent, 1, 0.5), "Color").Parent = Avatar

local OnlineDot = accent(new("Frame", {
    Size = UDim2.fromOffset(9, 9),
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, 1, 1, 1),
    Parent = Avatar,
}, { corner(5), stroke(Theme.Panel, 2) }), "BackgroundColor3")

new("TextLabel", {
    Size = UDim2.new(1, -120, 0, 14),
    Position = UDim2.fromOffset(47, 7),
    BackgroundTransparency = 1,
    Text = LocalPlayer.DisplayName,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = Card,
})

new("TextLabel", {
    Size = UDim2.new(1, -120, 0, 12),
    Position = UDim2.fromOffset(47, 21),
    BackgroundTransparency = 1,
    Text = "@" .. LocalPlayer.Name,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Theme.SubText,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = Card,
})

new("TextLabel", {
    Size = UDim2.fromOffset(70, 12),
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 0, 8),
    BackgroundTransparency = 1,
    Text = "SESSION",
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextColor3 = Theme.SubText,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Card,
})

local SessionLabel = accent(new("TextLabel", {
    Size = UDim2.fromOffset(70, 14),
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 0, 19),
    BackgroundTransparency = 1,
    Text = "00:00",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Card,
}), "TextColor3")

task.spawn(function()
    local ok, image = pcall(function()
        return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    if ok then
        Avatar.Image = image
        CandyAvatar.Image = image
    end
end)

-- a small 3D copy of your character, slowly turning, covers the flat headshot once it has loaded
task.spawn(function()
    local viewport = new("ViewportFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Ambient = Color3.fromRGB(190, 180, 205),
        LightColor = Color3.fromRGB(255, 245, 250),
        LightDirection = Vector3.new(-0.6, -0.8, 1),
        Visible = false,
        ZIndex = 2,
        Parent = Avatar,
    }, { corner(17) })
    local camera = new("Camera", { FieldOfView = 26, Parent = viewport })
    viewport.CurrentCamera = camera
    local model

    local function build()
        local character = LocalPlayer.Character
        local head = character and character:FindFirstChild("Head")
        if not (head and character:FindFirstChild("HumanoidRootPart")) then return end

        local ok, clone = pcall(function()
            character.Archivable = true
            return character:Clone()
        end)
        if not ok or not clone then return end

        -- a still copy only needs the look, not the scripts, sounds and effects
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d:Destroy()
            end
        end

        if model then model:Destroy() end
        clone:PivotTo(CFrame.new(0, 0, 0))
        clone.Parent = viewport
        model = clone

        -- the camera frames head and shoulders from the front (characters face -Z)
        local cloneHead = clone:FindFirstChild("Head")
        local target = (cloneHead and cloneHead.Position or Vector3.new(0, 1.5, 0)) - Vector3.new(0, 0.3, 0)
        camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.1, -4.6), target)
        viewport.Visible = true
        Avatar.ImageTransparency = 1
    end

    local function whenReady()
        local waited = 0
        while (not LocalPlayer.Character or not LocalPlayer:HasAppearanceLoaded()) and waited < 15 do
            task.wait(0.25)
            waited += 0.25
        end
        build()
    end

    whenReady()
    connect(LocalPlayer.CharacterAdded, function()
        task.spawn(whenReady)
    end)

    connect(RunService.RenderStepped, function()
        if not model or not Holder.Visible or not Card.Visible then return end
        local angle = Settings.ReduceMotion and 0.4 or os.clock() * 0.7
        model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, angle, 0))
    end)
end)

-- tab bar: a sliding highlight sits underneath the row of buttons
local tabBarStroke = stroke(Theme.Stroke, 1)
local TabBar = new("Frame", {
    BackgroundColor3 = Theme.Panel,
    Parent = Main,
}, { corner(12), tabBarStroke, pad(4, 4, 4, 4) })

local indicatorStroke = stroke(Theme.Stroke, 1)
local TabIndicator = new("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.RowHover,
    Parent = TabBar,
}, { indicatorStroke })
local indicatorCorner = corner(8)
indicatorCorner.Parent = TabIndicator

local indicatorLine = accent(new("Frame", {
    Size = UDim2.fromOffset(18, 2),
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, 0),
    BorderSizePixel = 0,
    Parent = TabIndicator,
}, { corner(1) }), "BackgroundColor3")

local TabList = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = TabBar,
}, {
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

------------------------------------------------------------------------
-- per-style layout

onTheme(function()
    local adapt, candy, bubble, ambitious, vx7 = Library.Style == "Adapt", isCandy(), isBubble(), isAmbitious(), isVX7()

    AdaptHeader.Visible = adapt
    CandyHeader.Visible = candy
    BubbleHeader.Visible = bubble
    AmbitiousHeader.Visible = ambitious
    VX7Header.Visible = vx7
    Haze.Visible = adapt
    CandyBg.Visible = candy
    BubbleBg.Visible = bubble
    AmbitiousBg.Visible = ambitious
    VX7Bg.Visible = vx7
    Card.Visible = adapt

    MainCorner.CornerRadius = UDim.new(0, candy and 14 or bubble and 18 or vx7 and 16 or 12)
    Header.Size = UDim2.new(1, 0, 0, candy and 62 or bubble and 70 or ambitious and 96 or vx7 and 76 or 88)
    SearchBar.Position = UDim2.fromOffset(12, candy and 112 or bubble and 74 or ambitious and 140 or vx7 and 86 or 90)
    searchCorner.CornerRadius = UDim.new(0, bubble and 15 or 10)
    indicatorCorner.CornerRadius = UDim.new(0, bubble and 15 or (ambitious or vx7) and 9 or 8)
    TabIndicator.BackgroundTransparency = vx7 and 0.35 or 0

    -- Ambitious: the minimise button is a small accent pill; VX7: a bigger square button
    MinButton.Size = ambitious and UDim2.fromOffset(22, 8) or vx7 and UDim2.fromOffset(28, 28) or UDim2.fromOffset(24, 24)
    MinButton.BackgroundColor3 = ambitious and Theme.Accent or Theme.Row
    MinButton.TextTransparency = ambitious and 1 or 0
    MinButton.Position = UDim2.new(1, -14, 0, ambitious and 14 or candy and 19 or vx7 and 24 or 8)

    local top = candy and 148 or bubble and 108 or ambitious and 176 or vx7 and 122 or 124
    local bottom = (candy or ambitious) and 12 or (bubble or vx7) and 54 or 98
    Pages.Position = UDim2.fromOffset(0, top)
    Pages.Size = UDim2.new(1, 0, 1, -(top + bottom))

    if candy or ambitious then
        TabBar.AnchorPoint = Vector2.new(0.5, 0)
        TabBar.Position = UDim2.new(0.5, 0, 0, candy and 68 or 98)
        TabBar.Size = UDim2.new(1, -16, 0, 36)
        TabBar.BackgroundTransparency = ambitious and 0.4 or 1
        tabBarStroke.Transparency = ambitious and 0.2 or 1
        TabIndicator.BackgroundColor3 = ambitious and Theme.AccentDark or Theme.Panel
        indicatorStroke.Color = Theme.Accent
        indicatorStroke.Thickness = 1.5
        indicatorLine.Visible = false
    else
        TabBar.AnchorPoint = Vector2.new(0.5, 1)
        TabBar.Position = UDim2.new(0.5, 0, 1, -8)
        TabBar.Size = UDim2.new(1, -16, 0, 38)
        -- Bubble: no bar behind the tabs, the active one is a filled pill
        TabBar.BackgroundTransparency = bubble and 1 or vx7 and 0.25 or 0
        tabBarStroke.Transparency = bubble and 1 or 0
        TabIndicator.BackgroundColor3 = (bubble or vx7) and Theme.Accent or Theme.RowHover
        indicatorStroke.Color = bubble and Color3.new(1, 1, 1) or vx7 and Theme.Accent or Theme.Stroke
        indicatorStroke.Thickness = (bubble or vx7) and 1.5 or 1
        indicatorLine.Visible = not bubble and not vx7
    end
end)

------------------------------------------------------------------------
-- show / hide

local animateRows
local closeTween

local function setVisible(state)
    Library.Visible = state
    if state then
        Holder.Visible = true
        if closeTween then closeTween:Cancel() end
        if Settings.ReduceMotion then
            HolderScale.Scale = Settings.UIScale
        else
            springTo(HolderScale, HolderScale.Scale, Settings.UIScale, function(v)
                HolderScale.Scale = v
            end, 14, 0.45)
        end
        tween(Main, 0.3, { GroupTransparency = 0 })
        tween(Shadow, 0.3, { ImageTransparency = 0.35 })
        if Library.Current and not Library.Searching then animateRows(Library.Current) end
        -- the first time the menu opens, numbers and sliders count up from zero
        if not Library.Introduced then
            Library.Introduced = true
            for _, element in pairs(Library.Elements) do
                if element.Intro then task.spawn(element.Intro, element) end
            end
        end
    else
        stopSpring(HolderScale)
        closeTween = tween(HolderScale, 0.25, { Scale = 0.85 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        tween(Shadow, 0.2, { ImageTransparency = 1 })
        local t = tween(Main, 0.25, { GroupTransparency = 1 })
        t.Completed:Once(function()
            if not Library.Visible then Holder.Visible = false end
        end)
    end
    play(state and "Open" or "Close")
end

do
    -- after a drag, nudge the window flush to a screen edge or the centre line if it's close
    local function snapWindow()
        if not Settings.Snap then return end
        local view = Gui.AbsoluteSize
        local pos, size = Holder.AbsolutePosition, Holder.AbsoluteSize
        local MARGIN, REACH = 12, 18

        local function shift(lo, len, total)
            local toStart = MARGIN - lo
            local toEnd = (total - MARGIN) - (lo + len)
            local toMid = total / 2 - (lo + len / 2)
            if math.abs(toStart) <= REACH then return toStart end
            if math.abs(toEnd) <= REACH then return toEnd end
            if math.abs(toMid) <= REACH then return toMid end
            return 0
        end

        local dx, dy = shift(pos.X, size.X, view.X), shift(pos.Y, size.Y, view.Y)
        if dx ~= 0 or dy ~= 0 then
            local goal = Holder.Position + UDim2.fromOffset(dx, dy)
            if Settings.ReduceMotion then
                Holder.Position = goal
            else
                tween(Holder, 0.3, { Position = goal }, Enum.EasingStyle.Back)
            end
        end
    end
    makeDraggable(Header, Holder, nil, snapWindow)
end

do
    -- resize handle in the bottom-right corner: drag it to scale the whole window, keeping the top-left corner put
    local handle = new("TextButton", {
        Size = UDim2.fromOffset(16, 16),
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 3, 1, 3),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 8,
        Parent = Holder,
    })
    local grips = {}
    for i = 1, 2 do
        grips[i] = new("Frame", {
            Size = UDim2.fromOffset(i == 1 and 9 or 5, 2),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, i == 1 and 1 or 3, 0.5, i == 1 and 1 or 3),
            Rotation = -45,
            BackgroundColor3 = Theme.SubText,
            BorderSizePixel = 0,
            ZIndex = 8,
            Parent = handle,
        }, { corner(1) })
    end

    local resizing, startPointer, startScale, topLeft = false, nil, 1, nil

    handle.MouseEnter:Connect(function()
        for _, g in ipairs(grips) do
            tween(g, 0.15, { BackgroundColor3 = Theme.Accent })
        end
    end)
    handle.MouseLeave:Connect(function()
        if resizing then return end
        for _, g in ipairs(grips) do
            tween(g, 0.2, { BackgroundColor3 = Theme.SubText })
        end
    end)
    handle.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        resizing = true
        startPointer, startScale, topLeft = input.Position, Settings.UIScale, Holder.AbsolutePosition
        stopSpring(HolderScale)
    end)
    connect(UserInputService.InputChanged, function(input)
        if not resizing or not isMove(input) then return end
        local d = input.Position - startPointer
        -- how far the corner was pulled along the diagonal decides the new size
        local grow = (d.X / (WINDOW_W * startScale) + d.Y / (WINDOW_H * startScale)) / 2
        local s = math.clamp(math.floor(startScale * (1 + grow) * 100 + 0.5) / 100, 0.6, 1.3)
        Settings.UIScale = s
        HolderScale.Scale = s
        scaleLabel.Text = math.floor(s * 100 + 0.5) .. "%"
        Holder.Position = UDim2.fromOffset(topLeft.X + WINDOW_W * s / 2, topLeft.Y + WINDOW_H * s / 2)
    end)
    connect(UserInputService.InputEnded, function(input)
        if resizing and isPointer(input) then
            resizing = false
            for _, g in ipairs(grips) do
                tween(g, 0.2, { BackgroundColor3 = Theme.SubText })
            end
            play("Click")
        end
    end)
end

MinButton.MouseEnter:Connect(function()
    tween(MinButton, 0.15, { TextColor3 = Theme.Accent })
    hoverSound()
end)
MinButton.MouseLeave:Connect(function()
    tween(MinButton, 0.2, { TextColor3 = Theme.SubText })
end)
MinButton.MouseButton1Click:Connect(function()
    setVisible(false)
end)

-- small floating button, mainly so mobile players can reopen the menu
local Mini = accent(new("TextButton", {
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 16, 0.35, 0),
    BackgroundColor3 = Theme.Panel,
    Text = "LD",
    Font = Enum.Font.FredokaOne,
    TextSize = 18,
    AutoButtonColor = false,
    Visible = false,
    Parent = Gui,
}, {
    corner(22),
    new("UIStroke", { Color = Color3.fromRGB(24, 8, 22), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }),
}), "TextColor3")
accent(stroke(Theme.Accent, 1.5, 0.55), "Color").Parent = Mini

makeDraggable(Mini, Mini, function()
    setVisible(not Library.Visible)
end)

-- games often bind Shift to shift-lock, which marks the press as processed, so only skip while typing
connect(UserInputService.InputBegan, function(input)
    if UserInputService:GetFocusedTextBox() or Library.Binding or Library.LastBindInput == input then return end
    if Library.Loaded and Settings.ToggleKey and input.KeyCode == Settings.ToggleKey then
        setVisible(not Library.Visible)
    end
end)

------------------------------------------------------------------------
-- watermark

local Watermark = new("Frame", {
    Size = UDim2.fromOffset(0, 26),
    AutomaticSize = Enum.AutomaticSize.X,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 12),
    BackgroundColor3 = Theme.Panel,
    BackgroundTransparency = 0.08,
    Visible = false,
    Parent = Gui,
}, {
    corner(7),
    stroke(Theme.Stroke, 1),
    pad(0, 0, 12, 12),
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local function wmLabel(text, order, color, font)
    return new("TextLabel", {
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = text,
        Font = font or Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = color or Theme.Text,
        LayoutOrder = order,
        Parent = Watermark,
    })
end

accent(wmLabel("LOVELY", 1, nil, Enum.Font.GothamBlack), "TextColor3")
wmLabel("DUELS", 2, Theme.Text, Enum.Font.GothamBold)
wmLabel("|", 3, Theme.Stroke)
local WmFps = wmLabel("60 fps", 4)
wmLabel("|", 5, Theme.Stroke)
local WmPing = wmLabel("0 ms", 6)
wmLabel("|", 7, Theme.Stroke)
local WmTime = wmLabel("00:00", 8)

local function getPing()
    local ok, ping = pcall(function()
        return LocalPlayer:GetNetworkPing() * 1000
    end)
    if ok and ping then return ping end
    ok, ping = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ok and ping or 0
end

------------------------------------------------------------------------
-- active features list

local ActiveList = new("Frame", {
    Size = UDim2.fromOffset(220, 500),
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 52),
    BackgroundTransparency = 1,
    Parent = Gui,
}, {
    new("UIListLayout", {
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local activeEntries = {}

onTheme(function()
    for _, entry in pairs(activeEntries) do
        entry.Bar.BackgroundColor3 = Theme.Accent
    end
end)

function Library:SetActive(name, on)
    local entry = activeEntries[name]
    if on and not entry then
        local frame = new("Frame", {
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 1,
            LayoutOrder = -#name,
            Parent = ActiveList,
        }, { corner(5), pad(0, 0, 10, 12) })

        local label = new("TextLabel", {
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTransparency = 1,
            Parent = frame,
        })

        local bar = new("Frame", {
            Size = UDim2.new(0, 2, 1, -8),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 8, 0.5, 0),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = frame,
        }, { corner(1) })

        tween(frame, 0.25, { BackgroundTransparency = 0.15 })
        tween(label, 0.25, { TextTransparency = 0 })
        tween(bar, 0.25, { BackgroundTransparency = 0 })
        activeEntries[name] = { Frame = frame, Label = label, Bar = bar }
    elseif not on and entry then
        activeEntries[name] = nil
        tween(entry.Frame, 0.2, { BackgroundTransparency = 1 })
        tween(entry.Label, 0.2, { TextTransparency = 1 })
        tween(entry.Bar, 0.2, { BackgroundTransparency = 1 })
        task.delay(0.2, function()
            entry.Frame:Destroy()
        end)
    end
end

------------------------------------------------------------------------
-- steal progress bar: shown centred, a little below the middle, while Auto Steal is on.
-- it only displays a value; feed it from your own code with Library:SetStealProgress(0..1)

local StealBar = new("CanvasGroup", {
    Size = UDim2.fromOffset(460, 62),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.87),
    BackgroundColor3 = Color3.fromRGB(14, 6, 14),
    BackgroundTransparency = 0.1,
    GroupTransparency = 1,
    Visible = false,
    Parent = Gui,
}, { corner(10) })
local stealScale = new("UIScale", { Scale = 0.7, Parent = StealBar })
local stealBorder = stroke(Theme.Accent, 2, 0.1)
stealBorder.Parent = StealBar
local stealVersion = "V1"

-- soft pink wash behind everything
accent(new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BorderSizePixel = 0,
    Parent = StealBar,
}, {
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.82),
            NumberSequenceKeypoint.new(1, 0.94),
        }),
    }),
}), "BackgroundColor3")

-- auto steal icon on the left of the bar
new("ImageLabel", {
    Size = UDim2.fromOffset(30, 30),
    Position = UDim2.fromOffset(12, 5),
    BackgroundTransparency = 1,
    Image = "rbxassetid://102178026098491",
    ScaleType = Enum.ScaleType.Fit,
    Parent = StealBar,
}, { corner(8) })

local StealPercent = new("TextLabel", {
    Size = UDim2.fromOffset(70, 30),
    Position = UDim2.fromOffset(50, 5),
    BackgroundTransparency = 1,
    Text = "0%",
    Font = Enum.Font.GothamBlack,
    TextSize = 24,
    TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = StealBar,
})

-- three dots that bob in turn, like it's working
local stealDots = {}
for i = 1, 3 do
    stealDots[i] = accent(new("Frame", {
        Size = UDim2.fromOffset(4, 4),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(114 + i * 9, 20),
        BorderSizePixel = 0,
        Parent = StealBar,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }), "BackgroundColor3")
end

-- little pill saying which auto steal version is running
local stealBadge = new("TextLabel", {
    Size = UDim2.fromOffset(28, 16),
    Position = UDim2.fromOffset(152, 12),
    BackgroundColor3 = Theme.Accent,
    BackgroundTransparency = 0.75,
    Text = "V1",
    Font = Enum.Font.GothamBlack,
    TextSize = 10,
    TextColor3 = Color3.new(1, 1, 1),
    Parent = StealBar,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
local stealBadgeStroke = stroke(Theme.Accent, 1, 0.3)
stealBadgeStroke.Parent = stealBadge

local stealStats = new("Frame", {
    Size = UDim2.fromOffset(0, 30),
    AutomaticSize = Enum.AutomaticSize.X,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 5),
    BackgroundTransparency = 1,
    Parent = StealBar,
}, {
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local function stealDivider(order)
    accent(new("Frame", {
        Size = UDim2.fromOffset(2, 18),
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = stealStats,
    }), "BackgroundColor3")
end

local function stealText(order)
    return new("TextLabel", {
        Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Text,
        LayoutOrder = order,
        Parent = stealStats,
    })
end

stealDivider(1)
local StealFps = stealText(2)
stealDivider(3)
local StealPing = stealText(4)
StealFps.Text, StealPing.Text = "FPS 60", "PING 0 ms"

local stealTrack = new("Frame", {
    Size = UDim2.new(1, -24, 0, 12),
    Position = UDim2.new(0, 12, 1, -20),
    BackgroundColor3 = Color3.fromRGB(30, 12, 28),
    Parent = StealBar,
}, { corner(6) })
local stealTrackStroke = stroke(Theme.Accent, 1, 0.45)
stealTrackStroke.Parent = stealTrack

local stealFill = new("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    Parent = stealTrack,
}, { corner(6) })
local stealFillGradient = new("UIGradient", { Parent = stealFill })

-- V1 is the pink bar; V2 swaps to purple with a solid badge, a pink-led fill and a slimmer track
local function paintStealBar()
    local v2 = stealVersion == "V2"
    local main = v2 and Theme.Secondary or Theme.Accent
    local other = v2 and Theme.Accent or Theme.Secondary
    stealBorder.Color = main
    stealTrackStroke.Color = main
    stealBadgeStroke.Color = main
    stealBadge.Text = stealVersion
    stealBadge.BackgroundColor3 = main
    stealBadge.BackgroundTransparency = v2 and 0.1 or 0.75
    stealFillGradient.Color = ColorSequence.new(other, main)
    stealTrack.Size = UDim2.new(1, -24, 0, v2 and 8 or 12)
    stealTrack.Position = UDim2.new(0, 12, 1, v2 and -17 or -20)
    for _, dot in ipairs(stealDots) do
        dot.BackgroundColor3 = main
    end
end
onTheme(paintStealBar)

local function setStealVersion(version)
    stealVersion = version
    paintStealBar()
end

function Library:SetStealProgress(alpha)
    alpha = math.clamp(tonumber(alpha) or 0, 0, 1)
    tween(stealFill, 0.15, { Size = UDim2.fromScale(alpha, 1) })
    StealPercent.Text = math.floor(alpha * 100 + 0.5) .. "%"
end

local stealHideToken
local function showStealBar(state)
    local token = {}
    stealHideToken = token
    if state then
        StealBar.Visible = true
        tween(StealBar, 0.3, { GroupTransparency = 0 })
        tween(stealScale, 0.35, { Scale = 0.8 }, Enum.EasingStyle.Back)
    else
        tween(StealBar, 0.25, { GroupTransparency = 1 })
        tween(stealScale, 0.25, { Scale = 0.7 })
        task.delay(0.25, function()
            if stealHideToken == token then StealBar.Visible = false end
        end)
    end
end

------------------------------------------------------------------------
-- custom cursor: accent dot plus a ring that trails behind it

local Cursor = accent(new("Frame", {
    Size = UDim2.fromOffset(8, 8),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Visible = false,
    ZIndex = 100,
    Parent = Gui,
}, { corner(4) }), "BackgroundColor3")

local CursorRing = new("Frame", {
    Size = UDim2.fromOffset(22, 22),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    Visible = false,
    ZIndex = 100,
    Parent = Gui,
}, { corner(11) })
accent(stroke(Theme.Accent, 1.5, 0.4), "Color").Parent = CursorRing

-- the cursor sits right under the mouse, so make sure it never eats clicks meant for buttons
for _, c in ipairs({ Cursor, CursorRing }) do
    pcall(function() c.Interactable = false end)
end

local ringPos = Vector2.zero
local hidIcon = false

------------------------------------------------------------------------
-- mascot: a little heart with a face, perched on the window's top edge (off by default)

local Mascot = new("Frame", {
    Size = UDim2.fromOffset(40, 38),
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 14, 0, 10),
    BackgroundTransparency = 1,
    ZIndex = 6,
    Visible = false,
    Parent = Holder,
})

local MascotBody = new("Frame", {
    Size = UDim2.fromOffset(36, 36),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(20, 19),
    BackgroundTransparency = 1,
    ZIndex = 7,
    Parent = Mascot,
})
local mascotHeart, mascotParts = makeHeart(MascotBody, 36, 7)
mascotHeart.Size = UDim2.fromScale(1, 1)
onTheme(function()
    for _, p in ipairs(mascotParts) do
        p.BackgroundColor3 = Theme.Accent
    end
end)

-- a glossy highlight on the upper-left lobe
new("Frame", {
    Size = UDim2.fromOffset(6, 4),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(9, 10),
    Rotation = -30,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
    ZIndex = 8,
    Parent = MascotBody,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

-- rosy cheeks
for _, x in ipairs({ 9, 27 }) do
    accent(new("Frame", {
        Size = UDim2.fromOffset(6, 3),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(x, 21),
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = MascotBody,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }), "BackgroundColor3", "AccentGlow")
end

local eyes, pupils = {}, {}
for i, x in ipairs({ 13, 23 }) do
    local eye = new("Frame", {
        Size = UDim2.fromOffset(7, 8),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(x, 16),
        BackgroundColor3 = Color3.new(1, 1, 1),
        ClipsDescendants = true,
        ZIndex = 8,
        Parent = MascotBody,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    pupils[i] = new("Frame", {
        Size = UDim2.fromOffset(4, 4),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(24, 8, 22),
        ZIndex = 9,
        Parent = eye,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    eyes[i] = eye
end

local mouth = new("Frame", {
    Size = UDim2.fromOffset(6, 2),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(18, 23),
    BackgroundColor3 = Color3.fromRGB(24, 8, 22),
    BorderSizePixel = 0,
    ZIndex = 8,
    Parent = MascotBody,
}, { corner(1) })

local function blink()
    for _, eye in ipairs(eyes) do
        tween(eye, 0.06, { Size = UDim2.fromOffset(7, 1) }).Completed:Once(function()
            tween(eye, 0.1, { Size = UDim2.fromOffset(7, 8) })
        end)
    end
end

task.spawn(function()
    while Gui.Parent do
        task.wait(2 + math.random() * 3)
        if Mascot.Visible and Holder.Visible then
            blink()
            -- every so often a quick double blink
            if math.random() < 0.2 then
                task.wait(0.2)
                blink()
            end
        end
    end
end)

-- three tiny hearts float up out of the mascot and fade
local function popHearts()
    for i = 1, 3 do
        local heart, parts = makeHeart(Holder, 8 + i % 2 * 2, 11)
        heart.AnchorPoint = Vector2.new(0.5, 0.5)
        heart.Position = UDim2.new(0, 34 + (i - 2) * 8, 0, -14)
        for _, p in ipairs(parts) do
            p.BackgroundColor3 = i == 2 and Theme.Secondary or Theme.Accent
            tween(p, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        end
        tween(heart, 0.9, { Position = UDim2.new(0, 34 + (i - 2) * 18, 0, -44 - i * 6) }, Enum.EasingStyle.Quart)
        Debris:AddItem(heart, 1)
    end
end

local mouthToken
-- hops, grins and puffs out hearts when something turns on; squashes a little when it turns off
local function mascotReact(happy)
    if not Mascot.Visible then return end
    if happy then popHearts() end
    stopSpring(Mascot)
    springTo(Mascot, happy and -9 or 4, 0, function(v)
        Mascot.Position = UDim2.new(0, 14, 0, 10 + v)
    end, 15, 0.32)
    tween(mouth, 0.12, { Size = happy and UDim2.fromOffset(10, 4) or UDim2.fromOffset(4, 2) })
    local token = {}
    mouthToken = token
    task.delay(0.7, function()
        if mouthToken == token then
            tween(mouth, 0.2, { Size = UDim2.fromOffset(6, 2) })
        end
    end)
end

-- clicking the mascot gives it a pat
local pet = new("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    ZIndex = 10,
    Parent = Mascot,
})
pet.MouseButton1Click:Connect(function()
    play("On")
    mascotReact(true)
    blink()
end)

------------------------------------------------------------------------
-- mobile buttons: big on-screen buttons for the keybinds, since phones have no keyboard

local MobilePad = new("Frame", {
    Size = UDim2.fromOffset(66, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.5, 0),
    BackgroundColor3 = Theme.Panel,
    BackgroundTransparency = 0.25,
    Visible = false,
    Parent = Gui,
}, {
    corner(14),
    stroke(Theme.Stroke, 1),
    pad(6, 8, 7, 7),
    new("UIListLayout", {
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

-- grip at the top of the pad so it can be dragged out of the way
do
    local padGrip = new("Frame", {
        Size = UDim2.fromOffset(52, 14),
        BackgroundTransparency = 1,
        Active = true,
        LayoutOrder = 0,
        Parent = MobilePad,
    })
    accent(new("Frame", {
        Size = UDim2.fromOffset(24, 4),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BorderSizePixel = 0,
        Parent = padGrip,
    }, { corner(2) }), "BackgroundColor3")
    makeDraggable(padGrip, MobilePad)
end

local padCount = 0

local function padButton(text)
    padCount += 1
    local b = new("TextButton", {
        Size = UDim2.fromOffset(52, 52),
        BackgroundColor3 = Theme.Row,
        Text = text,
        Font = Enum.Font.GothamBlack,
        TextScaled = true,
        TextWrapped = true,
        TextColor3 = Theme.Text,
        AutoButtonColor = false,
        LayoutOrder = padCount,
        Parent = MobilePad,
    }, {
        corner(12),
        stroke(Theme.Stroke, 1),
        pad(6, 6, 4, 4),
        new("UITextSizeConstraint", { MaxTextSize = 11 }),
    })
    -- squish on press so taps feel physical
    b.MouseButton1Down:Connect(function()
        tween(b, 0.08, { Size = UDim2.fromOffset(46, 46) })
    end)
    b.MouseButton1Up:Connect(function()
        tween(b, 0.25, { Size = UDim2.fromOffset(52, 52) }, Enum.EasingStyle.Back)
    end)
    return b
end

-- re-run paint whenever the element changes, whoever changed it (menu, keybind or pad)
local function watch(element, paint)
    local set = element.Set
    function element:Set(...)
        set(self, ...)
        paint()
    end
    paint()
end

-- toggle: lights up pink while it's on
local function addMobileToggle(name)
    local element = Library.Elements[name]
    if not element then return end
    local b = padButton(string.upper(name))
    b.MouseButton1Click:Connect(function()
        element:Set(not element:Get())
        play(element:Get() and "On" or "Off")
        mascotReact(element:Get())
    end)
    watch(element, function()
        local on = element:Get()
        b.BackgroundColor3 = on and Theme.Accent or Theme.Row
        b.TextColor3 = on and Theme.Background or Theme.Text
    end)
end

-- cycle: shows the current option under the label; each tap moves to the next one
local function addMobileCycle(name, label)
    local element = Library.Elements[name]
    if not element then return end
    local b = padButton("")
    b.MouseButton1Click:Connect(function()
        element:Next()
    end)
    watch(element, function()
        b.Text = label .. "\n" .. tostring(element:Get())
        b.TextColor3 = Theme.Accent
    end)
end

-- action: a one-shot press that flashes pink
local function addMobileAction(label, fn)
    local b = padButton(label)
    b.MouseButton1Click:Connect(function()
        play("Click")
        b.BackgroundColor3 = Theme.Accent
        tween(b, 0.35, { BackgroundColor3 = Theme.Row })
        task.spawn(fn)
    end)
end

------------------------------------------------------------------------
-- per-frame work: title shine, border, backdrop, springs, cursor, mascot, rainbow, stats

local frames, lastStat, lastRainbow, sessionStart = 0, os.clock(), 0, os.clock()

-- rolling fps / ping samples for the live stats graph
local GRAPH_POINTS = 30
local statHistory = { fps = {}, ping = {} }
local statListeners = {}

local function pushStat(list, value)
    table.insert(list, value)
    if #list > GRAPH_POINTS then table.remove(list, 1) end
end

connect(RunService.RenderStepped, function(dt)
    local now = os.clock()
    stepSprings(dt)

    -- only hide the system cursor while ours is showing, and only give it back if we took it
    local showCursor = Settings.Cursor and Library.Visible and UserInputService.MouseEnabled
    Cursor.Visible, CursorRing.Visible = showCursor, showCursor
    if showCursor then
        local mouse = UserInputService:GetMouseLocation()
        Cursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
        ringPos = ringPos:Lerp(mouse, math.clamp(dt * 18, 0, 1))
        CursorRing.Position = UDim2.fromOffset(ringPos.X, ringPos.Y)
    end
    if showCursor and not hidIcon then
        hidIcon = true
        UserInputService.MouseIconEnabled = false
    elseif not showCursor and hidIcon then
        hidIcon = false
        UserInputService.MouseIconEnabled = true
    end

    -- mascot's pupils follow the cursor
    if Holder.Visible and Mascot.Visible and UserInputService.MouseEnabled then
        local d = UserInputService:GetMouseLocation() - (MascotBody.AbsolutePosition + MascotBody.AbsoluteSize / 2)
        local look = d.Magnitude > 1 and d.Unit * math.min(d.Magnitude / 60, 1) * 1.6 or Vector2.zero
        for _, p in ipairs(pupils) do
            p.Position = UDim2.new(0.5, look.X, 0.5, look.Y)
        end
    end

    local calm = Settings.ReduceMotion
    local t = now % 4.5
    local x = t < 1.6 and (t / 1.6) * 2.4 - 1.2 or 1.2
    TitleShine.Offset = Vector2.new(calm and 1.2 or x, 0)
    BorderSpin.Rotation = calm and 45 or (now * 45) % 360

    if Holder.Visible and not calm then
        local mode = Settings.Backdrop
        if mode == "Leaves" then
            for _, f in ipairs(flakes) do
                f.Y += f.Speed * 1.3 * dt
                if f.Y > WINDOW_H then
                    f.Y = -6
                    f.X = math.random(0, WINDOW_W)
                end
                local sway = math.sin(now * 1.4 + f.Phase) * f.Sway * 2.5
                f.Frame.Position = UDim2.fromOffset(f.X + sway, f.Y)
                f.Frame.Rotation = math.sin(now * 2 + f.Phase) * 70
            end
        elseif mode == "Particles" then
            for _, f in ipairs(flakes) do
                f.Y -= f.Speed * 0.6 * dt
                if f.Y < -6 then
                    f.Y = WINDOW_H + 4
                    f.X = math.random(0, WINDOW_W)
                end
                f.Frame.Position = UDim2.fromOffset(f.X + math.sin(now * 0.6 + f.Phase) * f.Sway, f.Y)
                f.Frame.BackgroundTransparency = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(now * 2 + f.Phase))
            end
        elseif mode == "Hearts" then
            for _, h in ipairs(hearts) do
                h.Y -= h.Speed * dt
                if h.Y < -14 then
                    h.Y = WINDOW_H + 6
                    h.X = math.random(0, WINDOW_W)
                end
                h.Frame.Position = UDim2.fromOffset(h.X + math.sin(now * 0.9 + h.Phase) * h.Sway, h.Y)
                local alpha = 0.3 + 0.4 * (0.5 + 0.5 * math.sin(now * 1.8 + h.Phase))
                for _, p in ipairs(h.Parts) do
                    p.BackgroundTransparency = alpha
                end
            end
        elseif mode == "Matrix" then
            for _, c in ipairs(columns) do
                c.Y += c.Speed * dt
                if c.Y > WINDOW_H then
                    c.Y = -230
                    c.Label.Text = matrixText()
                end
                c.Label.Position = UDim2.fromOffset(c.X, c.Y)
            end
        end
    end

    if StealBar.Visible then
        for i, dot in ipairs(stealDots) do
            dot.Position = UDim2.fromOffset(114 + i * 9, 20 + math.sin(now * 6 - i * 0.9) * 3)
        end
    end

    -- rainbow rebuilds every themed element, so it runs a few times a second rather than every few frames
    if Settings.Rainbow and now - lastRainbow > 0.3 then
        lastRainbow = now
        Library:SetAccent(Color3.fromHSV((now * 0.08) % 1, 0.62, 0.92), true)
    end

    frames += 1
    if now - lastStat >= 0.5 then
        local elapsed = math.floor(now - sessionStart)
        local fpsNow = math.floor(frames / (now - lastStat) + 0.5)
        local pingNow = math.floor(getPing() + 0.5)
        WmFps.Text = fpsNow .. " fps"
        WmPing.Text = pingNow .. " ms"
        StealFps.Text = "FPS " .. fpsNow
        StealPing.Text = "PING " .. pingNow .. " ms"
        pushStat(statHistory.fps, fpsNow)
        pushStat(statHistory.ping, pingNow)
        for _, fn in ipairs(statListeners) do
            fn()
        end
        WmTime.Text = os.date("%H:%M")
        SessionLabel.Text = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)
        OnlineDot.BackgroundTransparency = OnlineDot.BackgroundTransparency == 0 and 0.35 or 0
        frames, lastStat = 0, now
    end
end)

------------------------------------------------------------------------
-- notifications: toasts were removed; Notify stays as a no-op so existing calls are harmless

function Library:Notify() end

------------------------------------------------------------------------
-- tabs

local Tab = {}
Tab.__index = Tab

do
    -- one loop turns the gradient on every row border that's currently glowing
    Library.Spin = Library.Spin or {}
    connect(RunService.RenderStepped, function()
        if not Holder.Visible then return end
        local angle = Settings.ReduceMotion and 45 or (os.clock() * 140) % 360
        for gradient in pairs(Library.Spin) do
            gradient.Rotation = angle
        end
    end)
end

local function makePage()
    local page = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Visible = false,
        Parent = Pages,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
        pad(6, 10, 12, 12),
    })
    accent(page, "ScrollBarImageColor3")
    return page
end

local Results = makePage()
local NoResults = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundTransparency = 1,
    Text = "No matches",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = Theme.SubText,
    LayoutOrder = -1,
    Visible = false,
    Parent = Results,
})

-- rows slide in one after another
function animateRows(tab)
    if Settings.ReduceMotion then return end
    for i, item in ipairs(tab.Holders) do
        if i > 16 then break end
        item.Body.Position = UDim2.fromOffset(24, 0)
        task.delay((i - 1) * 0.03, function()
            tween(item.Body, 0.45, { Position = UDim2.fromOffset(0, 0) })
        end)
    end
end

-- the highlight is tracked by its two edges so they can move at different speeds
local tabL, tabR = 0, 0

local function applyIndicator()
    TabIndicator.Position = UDim2.fromOffset(tabL, 0)
    TabIndicator.Size = UDim2.new(0, math.max(tabR - tabL, 4), 1, 0)
end

function Library:MoveIndicator(instant)
    local n = #self.Tabs
    if n == 0 or not self.Current then return end
    local inner = WINDOW_W - 16 - 8
    local width = (inner - 4 * (n - 1)) / n
    local left = (self.Current.Index - 1) * (width + 4)
    local right = left + width
    if instant then
        stopSpring("tabL")
        stopSpring("tabR")
        tabL, tabR = left, right
        applyIndicator()
    else
        -- liquid: the leading edge races ahead and overshoots, the trailing edge lags behind,
        -- so the pill stretches like jelly toward the new tab and then snaps back into shape
        local forward = left > tabL
        springTo("tabL", tabL, left, function(v)
            tabL = v
            applyIndicator()
        end, forward and 10 or 26, forward and 0.8 or 0.38)
        springTo("tabR", tabR, right, function(v)
            tabR = v
            applyIndicator()
        end, forward and 26 or 10, forward and 0.38 or 0.8)
    end
end

local function tabTextColor(active)
    if isVX7() then
        return active and Theme.Text or Theme.SubText
    end
    if isBubble() then
        return active and Theme.Background or Theme.Text
    end
    return active and Theme.Accent or Theme.SubText
end

function Library:Select(tab, instant)
    local previous = self.Current
    self.Current = tab
    for _, t in ipairs(self.Tabs) do
        local active = t == tab
        t.Page.Visible = active and not self.Searching
        if t.Icon then
            t.Icon.Set(tabTextColor(active), not instant)
            t.Icon.Glow(active and not isBubble(), not instant)
        end
        -- in Bubble the active button clears its own fill/outline so the green pill shows through
        if instant then
            t.TabButton.TextColor3 = tabTextColor(active)
            if isBubble() then
                t.TabButton.BackgroundTransparency = active and 1 or 0.35
                t.Stroke.Transparency = active and 1 or 0.55
            end
        else
            tween(t.TabButton, 0.2, { TextColor3 = tabTextColor(active) })
            if isBubble() then
                tween(t.TabButton, 0.2, { BackgroundTransparency = active and 1 or 0.35 })
                tween(t.Stroke, 0.2, { Transparency = active and 1 or 0.55 })
            end
        end
    end
    self:MoveIndicator(instant)
    -- the new page slides in from the side the highlight is travelling toward
    if not instant and previous and previous ~= tab and not Settings.ReduceMotion then
        local dir = tab.Index > previous.Index and 1 or -1
        tab.Page.Position = UDim2.fromOffset(dir * 70, 0)
        tween(tab.Page, 0.45, { Position = UDim2.fromOffset(0, 0) })
    end
    if not instant then animateRows(tab) end
end

function Library:Search(query)
    query = string.lower((query:gsub("^%s+", ""):gsub("%s+$", "")))
    self.Searching = query ~= ""
    ClearSearch.Visible = self.Searching

    -- rich text needs <, > and & escaped
    local function esc(str)
        return (str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    local found = 0
    for _, row in ipairs(self.Rows) do
        local from, to
        if self.Searching then
            from, to = string.find(string.lower(row.Name), query, 1, true)
        end
        if from then
            found += 1
            row.Frame.Parent = Results
            row.Frame.LayoutOrder = row.TabIndex * 1000 + row.Order
            row.Frame.Visible = true
            -- matched letters in the accent colour, and the tab the result lives in
            if row.Label then
                local upper = isBubble()
                local function cased(part)
                    return esc(upper and string.upper(part) or part)
                end
                row.Label.RichText = true
                row.Label.Text = cased(row.Name:sub(1, from - 1))
                    .. string.format('<font color="#%s"><b>%s</b></font>', Theme.Accent:ToHex(), cased(row.Name:sub(from, to)))
                    .. cased(row.Name:sub(to + 1))
                    .. string.format('  <font size="9" color="#%s">%s</font>', Theme.SubText:ToHex(), esc(row.Tab.Name or ""))
            end
        else
            row.Frame.Parent = row.Tab.Page
            row.Frame.LayoutOrder = row.Order
            -- rows inside a folded section stay hidden once the search is cleared
            row.Frame.Visible = not row.Section or row.Section.Open
            if row.Plain then row.Plain() end
        end
    end

    NoResults.Visible = self.Searching and found == 0
    Results.Visible = self.Searching
    for _, t in ipairs(self.Tabs) do
        t.Page.Visible = not self.Searching and t == self.Current
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    Library:Search(SearchBox.Text)
end)
SearchBox.Focused:Connect(function()
    tween(searchStroke, 0.2, { Color = Theme.Accent })
    play("Click")
end)
SearchBox.FocusLost:Connect(function()
    tween(searchStroke, 0.2, { Color = Theme.Stroke })
end)
ClearSearch.MouseButton1Click:Connect(function()
    play("Click")
    SearchBox.Text = ""
end)

-- recent searches: a short list under the search bar while it's focused and empty
do
    Library.Recent = Library.Recent or {}
    local panel = new("Frame", {
        BackgroundColor3 = Theme.Panel,
        Visible = false,
        ZIndex = 30,
        ClipsDescendants = true,
        Parent = Main,
    }, { corner(10), stroke(Theme.Stroke, 1) })

    local function rebuild()
        for _, child in ipairs(panel:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        local list = Library.Recent
        if #list == 0 then return 0 end

        new("TextLabel", {
            Size = UDim2.new(1, -80, 0, 20),
            Position = UDim2.fromOffset(12, 3),
            BackgroundTransparency = 1,
            Text = "RECENT",
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 31,
            Parent = panel,
        })
        local clear = new("TextButton", {
            Size = UDim2.fromOffset(50, 20),
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, 3),
            BackgroundTransparency = 1,
            Text = "Clear",
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            AutoButtonColor = false,
            ZIndex = 31,
            Parent = panel,
        })
        clear.MouseButton1Click:Connect(function()
            play("Click")
            Library.Recent = {}
            panel.Visible = false
        end)

        for i, query in ipairs(list) do
            local b = new("TextButton", {
                Size = UDim2.new(1, -16, 0, 24),
                Position = UDim2.fromOffset(8, 24 + (i - 1) * 24),
                BackgroundColor3 = Theme.RowHover,
                BackgroundTransparency = 1,
                Text = query,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                AutoButtonColor = false,
                ZIndex = 31,
                Parent = panel,
            }, { corner(6), pad(0, 0, 8, 0) })
            b.MouseEnter:Connect(function()
                tween(b, 0.15, { BackgroundTransparency = 0 })
            end)
            b.MouseLeave:Connect(function()
                tween(b, 0.2, { BackgroundTransparency = 1 })
            end)
            b.MouseButton1Click:Connect(function()
                play("Click")
                panel.Visible = false
                SearchBox.Text = query
            end)
        end
        return #list
    end

    local function show()
        if SearchBox.Text ~= "" then
            panel.Visible = false
            return
        end
        local count = rebuild()
        if count == 0 then
            panel.Visible = false
            return
        end
        panel.Position = UDim2.fromOffset(12, SearchBar.Position.Y.Offset + 34)
        panel.Size = UDim2.new(1, -24, 0, 24 + count * 24 + 6)
        panel.Visible = true
    end

    SearchBox.Focused:Connect(show)
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if SearchBox.Text ~= "" then
            panel.Visible = false
        elseif SearchBox:IsFocused() then
            show()
        end
    end)
    SearchBox.FocusLost:Connect(function()
        local query = (SearchBox.Text:gsub("^%s+", ""):gsub("%s+$", ""))
        if #query >= 2 then
            local list = Library.Recent
            for i = #list, 1, -1 do
                if string.lower(list[i]) == string.lower(query) then table.remove(list, i) end
            end
            table.insert(list, 1, query)
            while #list > 5 do table.remove(list) end
        end
        -- a short delay so clicking an entry still registers before the list closes
        task.delay(0.25, function()
            panel.Visible = false
        end)
    end)
end

-- tiny vector icons drawn from frames, so there are no image ids to go missing.
-- kind: move, target, keyboard, gamepad, eye or sliders. An "rbxassetid://..." string uses that image instead.
function Library:MakeIcon(kind, parent, px)
    local k = px / 14
    local holder = new("Frame", {
        Size = UDim2.fromOffset(px, px),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    -- soft glow behind the icon, lit while its tab is active (made first so it sits underneath)
    local glow = new("Frame", {
        Size = UDim2.fromOffset(px + 10, px + 10),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = holder,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local fills, strokes, images = {}, {}, {}

    -- a filled bar or dot centred on (cx, cy); round = true makes it a pill, a number is a corner radius
    local function bar(cx, cy, w, h, rot, round)
        local f = new("Frame", {
            Size = UDim2.fromOffset(w * k, h * k),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(cx * k, cy * k),
            Rotation = rot or 0,
            BorderSizePixel = 0,
            Parent = holder,
        }, { new("UICorner", { CornerRadius = round == true and UDim.new(1, 0) or UDim.new(0, (round or 0) * k) }) })
        table.insert(fills, f)
    end

    -- an outlined shape
    local function ring(cx, cy, w, h, thick, round)
        local f = new("Frame", {
            Size = UDim2.fromOffset(w * k, h * k),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(cx * k, cy * k),
            BackgroundTransparency = 1,
            Parent = holder,
        }, {
            new("UICorner", { CornerRadius = round == true and UDim.new(1, 0) or UDim.new(0, (round or 0) * k) }),
            new("UIStroke", { Thickness = math.max(thick * k, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
        })
        table.insert(strokes, f:FindFirstChildOfClass("UIStroke"))
    end

    if type(kind) == "string" and string.find(kind, "rbxassetid", 1, true) then
        table.insert(images, new("ImageLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Image = kind,
            ScaleType = Enum.ScaleType.Fit,
            Parent = holder,
        }))
    elseif kind == "move" then
        for _, ox in ipairs({ 1, 6.5 }) do
            bar(ox + 3, 4, 7, 2, 45, 1)
            bar(ox + 3, 10, 7, 2, -45, 1)
        end
    elseif kind == "target" then
        ring(7, 7, 10, 10, 1.5, true)
        bar(7, 1.2, 1.6, 3, 0, 0.8)
        bar(7, 12.8, 1.6, 3, 0, 0.8)
        bar(1.2, 7, 3, 1.6, 0, 0.8)
        bar(12.8, 7, 3, 1.6, 0, 0.8)
        bar(7, 7, 2.4, 2.4, 0, true)
    elseif kind == "keyboard" then
        ring(7, 7, 14, 9, 1.5, 2.5)
        for _, x in ipairs({ 3.8, 7, 10.2 }) do
            bar(x, 5.3, 1.8, 1.8, 0, 0.5)
        end
        bar(7, 8.6, 6, 1.5, 0, 0.7)
    elseif kind == "gamepad" then
        ring(7, 7.5, 14, 9, 1.5, 4.5)
        bar(4.5, 7.5, 4, 1.5, 0, 0.5)
        bar(4.5, 7.5, 1.5, 4, 0, 0.5)
        bar(9.8, 6.4, 2, 2, 0, true)
        bar(11.6, 8.6, 2, 2, 0, true)
    elseif kind == "eye" then
        ring(7, 7, 14, 8.5, 1.5, true)
        bar(7, 7, 4.2, 4.2, 0, true)
    else -- sliders
        local knobs = { 4, 9.5, 5.5 }
        for i, y in ipairs({ 2.5, 7, 11.5 }) do
            bar(7, y, 12, 1.4, 0, 0.7)
            bar(knobs[i], y, 3.6, 3.6, 0, true)
        end
    end

    local icon = { Holder = holder }

    function icon.Set(color, animated)
        for _, f in ipairs(fills) do
            if animated then tween(f, 0.2, { BackgroundColor3 = color }) else f.BackgroundColor3 = color end
        end
        for _, st in ipairs(strokes) do
            if animated then tween(st, 0.2, { Color = color }) else st.Color = color end
        end
        for _, im in ipairs(images) do
            if animated then tween(im, 0.2, { ImageColor3 = color }) else im.ImageColor3 = color end
        end
    end

    function icon.Glow(on, animated)
        glow.BackgroundColor3 = Theme.Accent
        local goal = on and 0.82 or 1
        if animated then tween(glow, 0.25, { BackgroundTransparency = goal }) else glow.BackgroundTransparency = goal end
    end

    icon.Set(Theme.SubText, false)
    return icon
end

-- iconKind is optional: pass "move", "target", "keyboard", "gamepad", "eye", "sliders" or an "rbxassetid://..." image
function Library:Tab(name, iconKind)
    local page = makePage()
    local kind = iconKind or ({ MOVEMENT = "move", COMBAT = "target", KBM = "keyboard", CTRL = "gamepad", VISUAL = "eye", SETTINGS = "sliders" })[name]

    local btnStroke = stroke(Theme.Stroke, 1, 1)
    local button = new("TextButton", {
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 1,
        Text = name,
        Font = Enum.Font.GothamBold,
        TextScaled = true,
        TextColor3 = Theme.SubText,
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = TabList,
    }, {
        btnStroke,
        pad(kind and 14 or 0, 0, 2, 2),
        new("UITextSizeConstraint", { MaxTextSize = 11, MinTextSize = 7 }),
    })
    local btnCorner = corner(8)
    btnCorner.Parent = button

    -- the icon sits above the label; the button's top padding shifts children down, so it's offset back up
    local icon = kind and Library:MakeIcon(kind, button, 12)
    if icon then
        icon.Holder.AnchorPoint = Vector2.new(0.5, 0)
        icon.Holder.Position = UDim2.new(0.5, 0, 0, 3 - 14)
    end

    -- Candy draws every tab as a little box, Bubble as an outlined pill
    onTheme(function()
        local candy, bubble = isCandy(), isBubble()
        -- the active Bubble tab stays clear so refreshes (e.g. rainbow) don't flash its fill back in
        local activeBubble = bubble and Library.Current and Library.Current.TabButton == button
        button.BackgroundColor3 = bubble and Theme.Background or Theme.Panel
        button.BackgroundTransparency = activeBubble and 1 or (candy or bubble) and 0.35 or 1
        btnStroke.Color = bubble and Color3.new(1, 1, 1) or Theme.Stroke
        btnStroke.Transparency = activeBubble and 1 or candy and 0.2 or bubble and 0.55 or 1
        btnCorner.CornerRadius = UDim.new(0, bubble and 15 or 8)
    end)

    -- named TabButton so it doesn't shadow the Tab:Button method
    local tab = setmetatable({
        Page = page,
        TabButton = button,
        Stroke = btnStroke,
        Holders = {},
        Order = 0,
        Index = #self.Tabs + 1,
        Name = name,
        Icon = icon,
        IconKind = kind,
    }, Tab)
    table.insert(self.Tabs, tab)

    local count = #self.Tabs
    for _, t in ipairs(self.Tabs) do
        t.TabButton.Size = UDim2.new(1 / count, -4 * (count - 1) / count, 1, 0)
    end

    button.MouseEnter:Connect(function()
        if self.Current ~= tab then
            tween(button, 0.15, { TextColor3 = Theme.Text })
            if icon then icon.Set(Theme.Text, true) end
        end
        hoverSound()
    end)
    button.MouseLeave:Connect(function()
        if self.Current ~= tab then
            tween(button, 0.2, { TextColor3 = tabTextColor(false) })
            if icon then icon.Set(tabTextColor(false), true) end
        end
    end)
    button.MouseButton1Click:Connect(function()
        if self.Searching then
            SearchBox.Text = ""
        elseif self.Current == tab then
            return
        end
        play("Click")
        self:Select(tab)
    end)

    if count == 1 then
        self:Select(tab, true)
    else
        self:MoveIndicator(true)
    end
    return tab
end

-- every row lives in a holder so its body can slide without upsetting the list layout
function Tab:_holder(height)
    self.Order += 1
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        LayoutOrder = self.Order,
        Parent = self.Page,
    })
    local body = new("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = holder,
    })
    -- AutomaticSize would count hidden dropdown options, so mirror the body's height instead
    body:GetPropertyChangedSignal("Size"):Connect(function()
        holder.Size = UDim2.new(1, 0, 0, body.Size.Y.Offset)
    end)
    table.insert(self.Holders, { Holder = holder, Body = body })
    -- everything after a section header belongs to it, so the header can fold it away
    if self.CurrentSection and not self.BuildingSection then
        table.insert(self.CurrentSection.Members, { Holder = holder, Body = body })
    end
    return holder, body
end

function Tab:_row(height, name)
    height = height or 38
    local holder, frame = self:_holder(height)
    frame.BackgroundColor3 = Theme.Row
    -- keeps ripples and glows inside the row
    frame.ClipsDescendants = true

    local rowCorner = corner(10)
    rowCorner.Parent = frame
    local rowStroke = stroke(Theme.Stroke, 1, 0.35)
    rowStroke.Parent = frame

    -- a faint highlight along the top edge gives each row a little glass depth
    new("Frame", {
        Name = "Sheen",
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.fromOffset(12, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
        Parent = frame,
    }, {
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    -- a slim accent bar grows out of the left edge while the row is hovered
    local hoverBar = accent(new("Frame", {
        Name = "HoverBar",
        Size = UDim2.fromOffset(2, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(0, height / 2),
        BorderSizePixel = 0,
        Parent = frame,
    }, { corner(1) }), "BackgroundColor3")

    -- a bright arc travels around the row's edge while it's hovered (and stays on for toggles that are on)
    local glowStroke = stroke(Color3.new(1, 1, 1), 1.5, 1)
    glowStroke.Parent = frame
    local glowGradient = new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 1),
            NumberSequenceKeypoint.new(0.42, 0.1),
            NumberSequenceKeypoint.new(0.58, 0.1),
            NumberSequenceKeypoint.new(0.72, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = glowStroke,
    })
    onTheme(function()
        glowGradient.Color = ColorSequence.new(Theme.Accent, Theme.Secondary)
    end)
    local glowState = { Hover = false, On = false }
    local glowCtl = {}
    function glowCtl.Set(key, value)
        glowState[key] = value
        local active = glowState.Hover or glowState.On
        tween(glowStroke, 0.25, { Transparency = active and 0.05 or 1 })
        Library.Spin[glowGradient] = active or nil
    end

    -- Bubble rows are white-outlined pills; Ambitious rows are dark glass over the backdrop
    onTheme(function()
        -- VX7 rows are glassy with a faint accent edge
        local candy, bubble, ambitious, vx7 = isCandy(), isBubble(), isAmbitious(), isVX7()
        frame.BackgroundTransparency = candy and 0.3 or bubble and 0.35 or ambitious and 0.15 or vx7 and 0.25 or 0.1
        rowCorner.CornerRadius = UDim.new(0, bubble and math.floor(height / 2) or 10)
        rowStroke.Color = bubble and Color3.new(1, 1, 1) or vx7 and Theme.Accent or Theme.Stroke
        rowStroke.Transparency = (candy or ambitious) and 0.05 or bubble and 0.4 or vx7 and 0.7 or 0.35
        rowStroke.Thickness = bubble and 1.5 or 1
        hoverBar.Visible = not bubble
    end)

    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })

    hit.MouseEnter:Connect(function()
        tween(frame, 0.15, { BackgroundColor3 = Theme.RowHover })
        tween(hoverBar, 0.2, { Size = UDim2.fromOffset(2, math.floor(height * 0.5)) })
        glowCtl.Set("Hover", true)
        hoverSound()
    end)
    hit.MouseLeave:Connect(function()
        tween(frame, 0.25, { BackgroundColor3 = Theme.Row })
        tween(hoverBar, 0.25, { Size = UDim2.fromOffset(2, 0) })
        glowCtl.Set("Hover", false)
    end)

    -- clicking sends a soft ripple outward from exactly where the pointer landed
    hit.InputBegan:Connect(function(input)
        if not isPointer(input) or Settings.ReduceMotion then return end
        local scale = math.max(HolderScale.Scale, 0.01)
        local center
        if input.UserInputType == Enum.UserInputType.Touch then
            center = Vector2.new(input.Position.X, frame.AbsolutePosition.Y + frame.AbsoluteSize.Y / 2)
        else
            center = UserInputService:GetMouseLocation()
        end
        local at = (center - frame.AbsolutePosition) / scale
        local reach = math.max(frame.AbsoluteSize.X, 120) / scale * 1.7
        local dot = new("Frame", {
            Size = UDim2.fromOffset(0, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(at.X, at.Y),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
            ZIndex = 0,
            Parent = frame,
        }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
        tween(dot, 0.6, { Size = UDim2.fromOffset(reach, reach), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
        Debris:AddItem(dot, 0.65)
    end)

    -- pressing a row nudges it in a hair (about 2%), then it springs back.
    -- this uses a UIScale and never touches Size, because dropdowns and the colour picker animate Size themselves
    local pressScale = new("UIScale", { Parent = frame })
    local pressed = false
    local function release()
        if not pressed then return end
        pressed = false
        tween(pressScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
        tween(frame, 0.3, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
    end
    hit.MouseButton1Down:Connect(function()
        if Settings.ReduceMotion then return end
        pressed = true
        tween(pressScale, 0.08, { Scale = 0.98 })
        tween(frame, 0.08, { Position = UDim2.fromOffset(3, 0) })
    end)
    hit.MouseButton1Up:Connect(release)
    hit.MouseLeave:Connect(release)

    if name then
        table.insert(Library.Rows, {
            Name = name,
            Body = frame,
            Frame = holder,
            Tab = self,
            TabIndex = self.Index,
            Order = self.Order,
            Section = self.CurrentSection,
        })
    end

    return frame, hit, glowCtl
end

function Tab:_label(parent, text, height)
    local label = new("TextLabel", {
        Size = UDim2.new(1, -130, 0, height or 38),
        BackgroundTransparency = 1,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = parent,
    })
    -- Bubble labels are heavy and uppercase
    onTheme(function()
        local bubble = isBubble()
        label.Text = bubble and string.upper(text) or text
        label.Font = bubble and Enum.Font.GothamBlack or isAmbitious() and Enum.Font.GothamBold or Enum.Font.GothamMedium
        label.Position = UDim2.fromOffset(bubble and 16 or 14, 0)
    end)

    -- search restyles the label (highlight + tab tag), so it keeps a way to put it back
    local row = Library.Rows[#Library.Rows]
    if row and row.Frame == parent.Parent and not row.Label then
        row.Label = label
        row.Plain = function()
            label.RichText = false
            label.Text = isBubble() and string.upper(text) or text
        end
    end
    return label
end

function Tab:Section(text)
    self.BuildingSection = true
    local _, frame = self:_holder(30)
    self.BuildingSection = false

    -- stored as CurrentSection so it doesn't shadow the Tab:Section method
    local section = { Members = {}, Open = true }
    self.CurrentSection = section

    local arrow = new("TextLabel", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -4, 1, -9),
        BackgroundTransparency = 1,
        Text = ">",
        Rotation = 90,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        Parent = frame,
    })

    local toggle = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        Parent = frame,
    })

    toggle.MouseEnter:Connect(function()
        tween(arrow, 0.15, { TextColor3 = Theme.Accent })
        hoverSound()
    end)
    toggle.MouseLeave:Connect(function()
        tween(arrow, 0.2, { TextColor3 = Theme.SubText })
    end)
    toggle.MouseButton1Click:Connect(function()
        section.Open = not section.Open
        play(section.Open and "On" or "Off")
        springTo(arrow, arrow.Rotation, section.Open and 90 or 0, function(v)
            arrow.Rotation = v
        end, 18, 0.5)
        for i, member in ipairs(section.Members) do
            -- searched rows live in the results page; leave those alone
            if not Library.Searching then
                member.Holder.Visible = section.Open
                if section.Open then
                    member.Body.Position = UDim2.fromOffset(20, 0)
                    task.delay((i - 1) * 0.025, function()
                        tween(member.Body, 0.4, { Position = UDim2.fromOffset(0, 0) })
                    end)
                end
            end
        end
    end)

    local bar = new("Frame", {
        Size = UDim2.fromOffset(2, 10),
        Position = UDim2.new(0, 2, 1, -9),
        AnchorPoint = Vector2.new(0, 0.5),
        BorderSizePixel = 0,
        Parent = frame,
    }, { corner(1) })
    local label = new("TextLabel", {
        Size = UDim2.new(1, -10, 1, 0),
        BackgroundTransparency = 1,
        Text = string.upper(text),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Bottom,
        Parent = frame,
    })
    -- each section wears a small copy of its tab's icon
    local sectionIcon = self.IconKind and Library:MakeIcon(self.IconKind, frame, 9)

    -- VX7 draws the header as its own boxed row with a rule on the right
    local sectionStroke = stroke(Theme.Accent, 1, 1)
    sectionStroke.Parent = frame
    corner(10).Parent = frame
    local rule = new("Frame", {
        Size = UDim2.fromOffset(60, 2),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -26, 0.5, 0),
        BorderSizePixel = 0,
        Parent = frame,
    }, { corner(1) })

    -- a thin rule under the header that fades out to the right
    local underline = new("Frame", {
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 1, -1),
        BorderSizePixel = 0,
        Parent = frame,
    }, {
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.55),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    -- Adapt: muted label with an accent tick; Candy: bold accent heading; Bubble: plain white caps
    -- the header sits low in its row, so every group gets some breathing room above it
    onTheme(function()
        local candy, bubble, ambitious, vx7 = isCandy(), isBubble(), isAmbitious(), isVX7()
        frame.Size = UDim2.new(1, 0, 0, vx7 and 34 or 30)
        frame.BackgroundColor3 = Theme.Row
        frame.BackgroundTransparency = vx7 and 0.25 or 1
        sectionStroke.Color = Theme.Accent
        sectionStroke.Transparency = vx7 and 0.7 or 1
        rule.Visible = vx7
        rule.BackgroundColor3 = Theme.Accent
        underline.Visible = not vx7
        underline.BackgroundColor3 = Theme.Accent
        bar.BackgroundColor3 = Theme.Accent
        bar.Visible = not candy and not bubble and not ambitious
        bar.Size = UDim2.fromOffset(vx7 and 3 or 2, vx7 and 16 or 10)
        bar.Position = vx7 and UDim2.new(0, 10, 0.5, 0) or UDim2.new(0, 2, 1, -9)
        arrow.Position = vx7 and UDim2.new(1, -8, 0.5, 0) or UDim2.new(1, -4, 1, -9)
        label.TextYAlignment = vx7 and Enum.TextYAlignment.Center or Enum.TextYAlignment.Bottom
        local lx = (candy or ambitious) and 2 or bubble and 6 or vx7 and 20 or 10
        label.Position = UDim2.fromOffset(lx + (sectionIcon and 13 or 0), vx7 and 0 or -4)
        label.Font = (candy or ambitious or vx7) and Enum.Font.GothamBlack or Enum.Font.GothamBold
        label.TextSize = (candy or vx7) and 11 or 10
        label.TextColor3 = candy and Theme.Accent or (bubble or ambitious or vx7) and Theme.Text or Theme.SubText
        if sectionIcon then
            sectionIcon.Holder.AnchorPoint = vx7 and Vector2.new(0, 0.5) or Vector2.new(0, 1)
            sectionIcon.Holder.Position = vx7 and UDim2.new(0, lx, 0.5, 0) or UDim2.new(0, lx, 1, -5)
            sectionIcon.Set(label.TextColor3, false)
        end
    end)
end

function Tab:Toggle(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local frame, hit, glowCtl = self:_row(38, o.Name)
    self:_label(frame, o.Name)
    local rowStroke = frame:FindFirstChildOfClass("UIStroke")
    -- keeps the shockwave ring inside the row
    frame.ClipsDescendants = true

    -- a faint accent glow spreads in from the left while the toggle is on
    local wash = new("Frame", {
        Size = UDim2.fromScale(0.75, 1),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = frame,
    }, {
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    local track = new("Frame", {
        Size = UDim2.fromOffset(34, 18),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        BackgroundColor3 = Theme.Off,
        Parent = frame,
    }, { corner(9) })
    -- when on, the track fills with an accent-to-secondary gradient instead of a flat colour
    local trackFill = new("UIGradient", { Enabled = false, Parent = track })
    local glow = stroke(Theme.Accent, 2, 1)
    glow.Parent = track

    -- accent strip on the left edge while enabled
    local strip = new("Frame", {
        Size = UDim2.fromOffset(3, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = frame,
    }, { corner(2) })

    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        BackgroundColor3 = Theme.Text,
        Parent = track,
    }, { corner(6) })

    -- a ring bursts out of the switch when it turns on
    local function shockwave()
        local center = track.AbsolutePosition + track.AbsoluteSize / 2 - frame.AbsolutePosition
        local ring = new("Frame", {
            Size = UDim2.fromOffset(10, 10),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(center.X, center.Y),
            BackgroundTransparency = 1,
            ZIndex = 3,
            Parent = frame,
        }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
        local ringStroke = stroke(Theme.Accent, 2.5)
        ringStroke.Parent = ring
        tween(ring, 0.6, { Size = UDim2.fromOffset(340, 340) }, Enum.EasingStyle.Quart)
        tween(ringStroke, 0.6, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quart)
        Debris:AddItem(ring, 0.65)
    end

    local element = { Value = false }

    function element:Set(value, silent)
        self.Value = value and true or false
        Library.Flags[flag] = self.Value
        local on = self.Value
        glow.Color = Theme.Accent
        strip.BackgroundColor3 = Theme.Accent
        trackFill.Color = ColorSequence.new(Theme.Accent, Theme.Secondary)
        trackFill.Enabled = on
        wash.BackgroundColor3 = Theme.Accent
        tween(wash, 0.35, { BackgroundTransparency = on and 0.86 or 1 })
        glowCtl.Set("On", on)

        -- Bubble swaps the switch for a single dot that lights up
        local bubble = isBubble()
        knob.Visible = not bubble
        strip.Visible = not bubble
        track.Size = bubble and UDim2.fromOffset(18, 18) or UDim2.fromOffset(34, 18)
        track.Position = UDim2.new(1, bubble and -16 or -12, 0.5, 0)

        tween(track, 0.25, { BackgroundColor3 = on and Color3.new(1, 1, 1) or Theme.Off })
        tween(glow, 0.3, { Transparency = on and 0.7 or 1 })
        tween(strip, 0.3, { Size = UDim2.fromOffset(3, on and 18 or 0) })
        tween(knob, 0.3, { BackgroundColor3 = on and Theme.Background or Theme.Text })
        -- the knob springs across and settles with a little overshoot
        local goal = on and 19 or 3
        if silent then
            stopSpring(knob)
            knob.Position = UDim2.new(0, goal, 0.5, 0)
        else
            springTo(knob, knob.Position.X.Offset, goal, function(v)
                knob.Position = UDim2.new(0, v, 0.5, 0)
            end, 20, 0.42)
        end
        -- Ambitious outlines the whole row in the accent while it's on
        if isAmbitious() then
            strip.Visible = false
            tween(rowStroke, 0.25, { Color = on and Theme.Accent or Theme.Stroke })
        end

        if o.List ~= false then Library:SetActive(o.Name, on) end
        if not silent then task.spawn(callback, on) end
    end

    function element:Get()
        return self.Value
    end

    function element:Refresh()
        self:Set(self.Value, true)
    end

    hit.MouseButton1Click:Connect(function()
        element:Set(not element.Value)
        play(element.Value and "On" or "Off")
        if element.Value and not Settings.ReduceMotion then shockwave() end
        mascotReact(element.Value)
    end)

    element:Set(o.Default == true, o.Default ~= true)
    Library.Elements[flag] = element
    return element
end

function Tab:Number(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local frame = self:_row(38, o.Name)
    self:_label(frame, o.Name)

    local boxStroke = stroke(Theme.Stroke, 1)
    local box = new("TextBox", {
        Size = UDim2.fromOffset(62, 26),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        BackgroundColor3 = Theme.Background,
        Text = "",
        PlaceholderText = "0",
        PlaceholderColor3 = Theme.SubText,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = frame,
    }, { corner(8), boxStroke })

    -- Candy shows the number in the accent colour; Bubble shows it as bare text
    onTheme(function()
        local bubble = isBubble()
        box.TextColor3 = isCandy() and Theme.Accent or Theme.Text
        box.BackgroundTransparency = bubble and 1 or 0
        boxStroke.Transparency = bubble and 1 or 0
        box.TextXAlignment = bubble and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center
        box.Font = bubble and Enum.Font.GothamBlack or Enum.Font.GothamBold
        box.Position = UDim2.new(1, bubble and -18 or -10, 0.5, 0)
    end)

    local element = { Value = o.Default or 0 }

    function element:Set(value, silent)
        local n = tonumber(value)
        if not n then
            box.Text = tostring(self.Value)
            return
        end
        if o.Min then n = math.max(n, o.Min) end
        if o.Max then n = math.min(n, o.Max) end
        local old = self.Value
        self.Value = n
        if not silent and old ~= n and not box:IsFocused() then
            rollText(box, old, n, decimalsOf(n), "")
        else
            box.Text = tostring(n)
        end
        Library.Flags[flag] = n
        if not silent then task.spawn(callback, n) end
    end

    function element:Get()
        return self.Value
    end

    -- counts up from zero the first time the menu opens
    function element:Intro()
        if self.Value == 0 or box:IsFocused() then return end
        rollText(box, 0, self.Value, decimalsOf(self.Value), "", 0.9)
    end

    box.Focused:Connect(function()
        tween(boxStroke, 0.2, { Color = Theme.Accent })
        play("Click")
    end)
    box.FocusLost:Connect(function()
        tween(boxStroke, 0.2, { Color = Theme.Stroke })
        element:Set(box.Text)
    end)

    element:Set(element.Value, true)
    Library.Elements[flag] = element
    return element
end

function Tab:Slider(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
    local suffix = o.Suffix or ""
    local decimals = tostring(step):match("%.(%d+)")
    decimals = decimals and #decimals or 0

    local frame = self:_row(52, o.Name)
    self:_label(frame, o.Name, 32)

    -- the value sits in a small rounded pill
    local valueLabel = accent(new("TextLabel", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0, 16),
        BackgroundTransparency = 0.45,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = frame,
    }, { corner(9), pad(0, 0, 9, 9) }), "TextColor3")
    accent(valueLabel, "BackgroundColor3", "AccentDark")

    local bar = new("Frame", {
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 1, -17),
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
        Parent = frame,
    }, { corner(3) })

    -- the fill is a gradient from the accent to the secondary colour
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = bar,
    }, { corner(3) })
    local fillGradient = new("UIGradient", { Parent = fill })
    onTheme(function()
        fillGradient.Color = ColorSequence.new(Theme.Accent, Theme.Secondary)
    end)

    -- while dragging, the fill leaves a short glowing trail behind the knob
    local trail = new("Frame", {
        Size = UDim2.fromOffset(0, 10),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Visible = false,
        Parent = bar,
    }, { corner(5) })
    local trailGradient = new("UIGradient", { Parent = trail })
    onTheme(function()
        trailGradient.Color = ColorSequence.new(Theme.AccentGlow, Theme.Accent)
        trailGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0.2),
        })
    end)
    local trailLen, trailDir, lastAlpha = 0, 1, nil

    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Theme.Text,
        Parent = bar,
    }, { corner(7) })
    accent(stroke(Theme.Accent, 2), "Color").Parent = knob

    -- value bubble shown while dragging
    local bubble = accent(new("Frame", {
        Size = UDim2.fromOffset(38, 18),
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 0, -6),
        BackgroundTransparency = 1,
        Parent = knob,
    }, { corner(5) }), "BackgroundColor3")
    local pointer = accent(new("Frame", {
        Size = UDim2.fromOffset(6, 6),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 1, 0),
        Rotation = 45,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = bubble,
    }), "BackgroundColor3")
    local bubbleText = new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.Background,
        TextTransparency = 1,
        ZIndex = 2,
        Parent = bubble,
    })

    local function showBubble(state)
        local t = state and 0 or 1
        tween(bubble, 0.15, { BackgroundTransparency = t, Position = UDim2.new(0.5, 0, 0, state and -8 or -4) })
        tween(pointer, 0.15, { BackgroundTransparency = t })
        tween(bubbleText, 0.15, { TextTransparency = t })
    end

    local grab = new("TextButton", {
        Size = UDim2.new(1, -12, 0, 22),
        Position = UDim2.new(0, 6, 1, -25),
        BackgroundTransparency = 1,
        Text = "",
        Parent = frame,
    })

    local element = { Value = nil }

    function element:Set(value, silent)
        value = math.clamp(tonumber(value) or min, min, max)
        value = math.clamp(math.floor((value - min) / step + 0.5) * step + min, min, max)
        local old = self.Value
        local changed = value ~= old
        self.Value = value
        Library.Flags[flag] = value

        local alpha = (max - min) == 0 and 0 or (value - min) / (max - min)
        local text = string.format("%." .. decimals .. "f", value) .. suffix
        tween(fill, 0.12, { Size = UDim2.fromScale(alpha, 1) })
        tween(knob, 0.12, { Position = UDim2.fromScale(alpha, 0.5) })
        if silent or not changed or not old then
            valueLabel.Text = text
        else
            rollText(valueLabel, old, value, decimals, suffix, 0.18)
        end
        bubbleText.Text = text

        if changed and not silent then task.spawn(callback, value) end
    end

    function element:Get()
        return self.Value
    end

    -- the fill sweeps across and the value counts up the first time the menu opens
    function element:Intro()
        local alpha = (max - min) == 0 and 0 or (self.Value - min) / (max - min)
        fill.Size = UDim2.fromScale(0, 1)
        knob.Position = UDim2.fromScale(0, 0.5)
        tween(fill, 0.9, { Size = UDim2.fromScale(alpha, 1) }, Enum.EasingStyle.Quart)
        tween(knob, 0.9, { Position = UDim2.fromScale(alpha, 0.5) }, Enum.EasingStyle.Quart)
        rollText(valueLabel, min, self.Value, decimals, suffix, 0.9)
    end

    local sliding = false
    local function fromInput(input)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        -- the faster the knob moves, the longer the trail
        if lastAlpha and not Settings.ReduceMotion then
            local dx = (alpha - lastAlpha) * bar.AbsoluteSize.X / math.max(HolderScale.Scale, 0.01)
            if dx ~= 0 then
                trailDir = dx > 0 and 1 or -1
                trailLen = math.min(70, trailLen + math.abs(dx) * 2.5)
            end
        end
        lastAlpha = alpha
        element:Set(min + (max - min) * alpha)
    end

    grab.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        sliding = true
        tween(knob, 0.15, { Size = UDim2.fromOffset(18, 18) })
        showBubble(true)
        fromInput(input)
    end)
    connect(UserInputService.InputChanged, function(input)
        if sliding and isMove(input) then fromInput(input) end
    end)
    connect(UserInputService.InputEnded, function(input)
        if sliding and isPointer(input) then
            sliding = false
            tween(knob, 0.15, { Size = UDim2.fromOffset(14, 14) })
            showBubble(false)
            play("Click")
        end
    end)

    -- the trail shrinks away on its own once the knob stops
    connect(RunService.RenderStepped, function(dt)
        if trailLen <= 0.5 then
            trailLen = 0
            if trail.Visible then trail.Visible = false end
            return
        end
        trailLen *= math.exp(-dt * 7)
        local alphaNow = (max - min) == 0 and 0 or ((element.Value or min) - min) / (max - min)
        trail.Visible = true
        trail.AnchorPoint = Vector2.new(trailDir > 0 and 1 or 0, 0.5)
        trail.Position = UDim2.fromScale(alphaNow, 0.5)
        trail.Size = UDim2.fromOffset(trailLen, 10)
        trailGradient.Rotation = trailDir > 0 and 0 or 180
    end)

    element:Set(o.Default or min, true)
    Library.Elements[flag] = element
    return element
end

-- "<  V2  >" selector
function Tab:Cycle(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local options = o.Options or {}
    local frame = self:_row(38, o.Name)
    self:_label(frame, o.Name)

    local holder = new("Frame", {
        Size = UDim2.fromOffset(122, 26),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        BackgroundTransparency = 1,
        Parent = frame,
    })

    local function arrowButton(text, xScale, anchor)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(26, 26),
            AnchorPoint = Vector2.new(anchor, 0),
            Position = UDim2.fromScale(xScale, 0),
            BackgroundColor3 = Theme.Background,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.Text,
            AutoButtonColor = false,
            Parent = holder,
        }, { corner(8), stroke(Theme.Stroke, 1) })
        b.MouseEnter:Connect(function()
            tween(b, 0.15, { TextColor3 = Theme.Accent })
            hoverSound()
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.2, { TextColor3 = Theme.Text })
        end)
        return b
    end

    local left = arrowButton("<", 0, 0)
    local right = arrowButton(">", 1, 1)

    local valueBox = new("Frame", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.fromOffset(30, 0),
        BackgroundColor3 = Theme.Background,
        ClipsDescendants = true,
        Parent = holder,
    }, { corner(8), stroke(Theme.Stroke, 1) })

    local valueLabel = accent(new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        Parent = valueBox,
    }), "TextColor3")

    local element = { Value = nil, Index = 1 }

    function element:Set(value, silent, direction)
        local index = table.find(options, value)
        if not index then return end
        self.Index, self.Value = index, value
        Library.Flags[flag] = value
        valueLabel.Text = value
        if direction then
            valueLabel.Position = UDim2.fromOffset(direction * 14, 0)
            valueLabel.TextTransparency = 0.6
            tween(valueLabel, 0.25, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 })
        end
        if not silent then task.spawn(callback, value) end
    end

    function element:Get()
        return self.Value
    end

    local function step(direction)
        if #options == 0 then return end
        local index = (element.Index - 1 + direction) % #options + 1
        play("Click", direction > 0 and 2 or -2)
        element:Set(options[index], false, direction)
    end

    left.MouseButton1Click:Connect(function() step(-1) end)
    right.MouseButton1Click:Connect(function() step(1) end)

    -- moves to the next option, wrapping round; used by the mobile pad
    function element:Next()
        step(1)
    end

    element:Set(o.Default or options[1], true)
    Library.Elements[flag] = element
    return element
end

-- row with a label on top and a segmented picker underneath
function Tab:Segment(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local options = o.Options or {}
    local count = math.max(#options, 1)
    local frame = self:_row(66, o.Name)
    self:_label(frame, o.Name, 34)

    local barCorner = corner(8)
    local bar = new("Frame", {
        Size = UDim2.new(1, -24, 0, 22),
        Position = UDim2.fromOffset(12, 34),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.3,
        Parent = frame,
    }, { barCorner, stroke(Theme.Stroke, 1) })

    local pillCorner = corner(8)
    local pill = accent(new("Frame", {
        Size = UDim2.fromScale(1 / count, 1),
        Parent = bar,
    }, { pillCorner }), "BackgroundColor3")

    -- VX7 shades the selected pill from bright to deep accent
    local pillGradient = new("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
        Parent = pill,
    })
    onTheme(function()
        pillGradient.Enabled = isVX7()
    end)

    local list = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = bar,
    }, {
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }),
    })

    onTheme(function()
        local radius = UDim.new(0, isBubble() and 11 or 8)
        barCorner.CornerRadius = radius
        pillCorner.CornerRadius = radius
    end)

    local element = { Value = nil }
    local buttons = {}

    function element:Set(value, silent)
        local index = table.find(options, value)
        if not index then return end
        self.Value = value
        Library.Flags[flag] = value
        tween(pill, 0.3, { Position = UDim2.fromScale((index - 1) / count, 0) })
        for option, b in pairs(buttons) do
            tween(b, 0.2, { TextColor3 = option == value and Theme.Background or Theme.SubText })
        end
        if not silent then task.spawn(callback, value) end
    end

    function element:Get()
        return self.Value
    end

    function element:Refresh()
        self:Set(self.Value, true)
    end

    for i, option in ipairs(options) do
        local b = new("TextButton", {
            Size = UDim2.fromScale(1 / count, 1),
            BackgroundTransparency = 1,
            Text = string.upper(option),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            AutoButtonColor = false,
            LayoutOrder = i,
            Parent = list,
        })
        b.MouseEnter:Connect(hoverSound)
        b.MouseButton1Click:Connect(function()
            if element.Value == option then return end
            play("Click")
            element:Set(option)
        end)
        buttons[option] = b
    end

    element:Set(o.Default or options[1], true)
    Library.Elements[flag] = element
    return element
end

function Tab:Keybind(o)
    local flag = o.Flag or ("Bind: " .. o.Name)
    local callback = o.Callback or function() end
    local changed = o.Changed or function() end
    local frame = self:_row(38, o.Name)
    self:_label(frame, o.Name)

    -- shorter, keycap-style names for the long ones
    local KEY_NAMES = {
        RightShift = "R SHIFT", LeftShift = "L SHIFT",
        RightControl = "R CTRL", LeftControl = "L CTRL",
        RightAlt = "R ALT", LeftAlt = "L ALT",
        Return = "ENTER", Backspace = "BKSP", Escape = "ESC",
    }
    local function prettyKey(key)
        return KEY_NAMES[key.Name] or string.upper(key.Name)
    end

    local keyStroke = stroke(Theme.Stroke, 1)
    local button = new("TextButton", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        BackgroundColor3 = Theme.Background,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.Text,
        AutoButtonColor = false,
        Parent = frame,
    }, {
        corner(8),
        keyStroke,
        pad(0, 0, 10, 10),
        new("UISizeConstraint", { MinSize = Vector2.new(46, 24) }),
    })

    -- a thicker lower edge makes it read as a key
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -2),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = button,
    }, { corner(1) })

    local element = { Value = nil, Listening = false }

    function element:Set(key, silent)
        self.Value = key
        button.Text = key and prettyKey(key) or "NONE"
        Library.Flags[flag] = key
        if not silent then task.spawn(changed, key) end
    end

    function element:Get()
        return self.Value
    end

    button.MouseButton1Click:Connect(function()
        if element.Listening then return end
        element.Listening = true
        Library.Binding = true
        button.Text = "..."
        tween(keyStroke, 0.2, { Color = Theme.Accent })
        play("Click")
    end)

    connect(UserInputService.InputBegan, function(input, processed)
        if element.Listening then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            element.Listening = false
            Library.Binding = false
            -- Roblox reuses the same InputObject for every press of a key, so only ignore this one press
            Library.LastBindInput = input
            task.delay(0.1, function()
                if Library.LastBindInput == input then Library.LastBindInput = nil end
            end)
            tween(keyStroke, 0.2, { Color = Theme.Stroke })
            element:Set(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil)
            play("On")
            return
        end
        if UserInputService:GetFocusedTextBox() or Library.Binding or Library.LastBindInput == input then return end
        if element.Value and input.KeyCode == element.Value then
            task.spawn(callback, element.Value)
        end
    end)

    element:Set(o.Default, true)
    Library.Elements[flag] = element
    return element
end

function Tab:Dropdown(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local options = o.Options or {}
    local frame, hit = self:_row(38, o.Name)
    frame.ClipsDescendants = true
    self:_label(frame, o.Name)

    -- long lists scroll instead of stretching the whole row
    local visibleOptions = math.min(#options, 5)

    local valueLabel = accent(new("TextLabel", {
        Size = UDim2.fromOffset(110, 38),
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -30, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    }), "TextColor3")

    local arrow = new("TextLabel", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0, 19),
        BackgroundTransparency = 1,
        Text = ">",
        Rotation = 90,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        Parent = frame,
    })

    local list = new("ScrollingFrame", {
        Size = UDim2.new(1, -16, 0, visibleOptions * 28 - 2),
        Position = UDim2.fromOffset(8, 40),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = frame,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    accent(list, "ScrollBarImageColor3")

    local element = { Value = nil, Open = false }
    local buttons = {}

    function element:Toggle(state)
        if state == nil then state = not self.Open end
        self.Open = state
        tween(frame, 0.3, { Size = UDim2.new(1, 0, 0, state and (44 + visibleOptions * 28) or 38) })
        tween(arrow, 0.3, { Rotation = state and 270 or 90, TextColor3 = state and Theme.Accent or Theme.SubText })
    end

    function element:Set(value, silent)
        if not table.find(options, value) then return end
        self.Value = value
        valueLabel.Text = value
        Library.Flags[flag] = value
        for option, b in pairs(buttons) do
            local selected = option == value
            tween(b, 0.2, { TextColor3 = selected and Theme.Accent or Theme.SubText })
            tween(b.Mark, 0.2, { BackgroundTransparency = selected and 0 or 1 })
        end
        if not silent then task.spawn(callback, value) end
    end

    function element:Get()
        return self.Value
    end

    function element:Refresh()
        self:Set(self.Value, true)
        if self.Open then arrow.TextColor3 = Theme.Accent end
    end

    for i, option in ipairs(options) do
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = Theme.Background,
            BackgroundTransparency = 1,
            Text = option,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
            LayoutOrder = i,
            Parent = list,
        }, { corner(8), pad(0, 0, 10, 0) })

        -- a small dot marks the option that's currently selected
        accent(new("Frame", {
            Name = "Mark",
            Size = UDim2.fromOffset(6, 6),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = b,
        }, { corner(3) }), "BackgroundColor3")

        b.MouseEnter:Connect(function()
            tween(b, 0.15, { BackgroundTransparency = 0 })
            hoverSound()
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.2, { BackgroundTransparency = 1 })
        end)
        b.MouseButton1Click:Connect(function()
            play("Click")
            element:Set(option)
            element:Toggle(false)
        end)
        buttons[option] = b
    end

    hit.MouseButton1Click:Connect(function()
        play("Click")
        element:Toggle()
    end)

    element:Set(o.Default or options[1], true)
    Library.Elements[flag] = element
    return element
end

local PRESETS = {
    Color3.fromRGB(255, 110, 199),
    Color3.fromRGB(90, 170, 255),
    Color3.fromRGB(200, 130, 255),
    Color3.fromRGB(70, 190, 240),
    Color3.fromRGB(150, 110, 245),
    Color3.fromRGB(240, 80, 110),
    Color3.fromRGB(245, 160, 60),
    Color3.fromRGB(235, 235, 235),
}

function Tab:ColorPicker(o)
    local flag = o.Flag or o.Name
    local callback = o.Callback or function() end
    local frame, hit = self:_row(38, o.Name)
    frame.ClipsDescendants = true
    self:_label(frame, o.Name)

    local preview = new("Frame", {
        Size = UDim2.fromOffset(34, 18),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0, 19),
        Parent = frame,
    }, { corner(6), stroke(Theme.Stroke, 1) })

    local hueBar = new("Frame", {
        Size = UDim2.new(1, -24, 0, 10),
        Position = UDim2.fromOffset(12, 46),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Parent = frame,
    }, {
        corner(5),
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,     Color3.fromHSV(0, 1, 1)),
                ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
                ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
                ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
                ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
                ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
                ColorSequenceKeypoint.new(1,     Color3.fromHSV(1, 1, 1)),
            }),
        }),
    })

    local hueKnob = new("Frame", {
        Size = UDim2.fromOffset(6, 16),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Parent = hueBar,
    }, { corner(3), stroke(Theme.Background, 2) })

    local swatches = new("Frame", {
        Size = UDim2.new(1, -24, 0, 20),
        Position = UDim2.fromOffset(12, 66),
        BackgroundTransparency = 1,
        Parent = frame,
    }, {
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local element = { Value = o.Default or Theme.Accent, Open = false }

    function element:Set(color, silent)
        self.Value = color
        Library.Flags[flag] = color
        preview.BackgroundColor3 = color
        local h = color:ToHSV()
        tween(hueKnob, 0.12, { Position = UDim2.fromScale(h, 0.5) })
        if not silent then task.spawn(callback, color) end
    end

    function element:Get()
        return self.Value
    end

    for i, color in ipairs(PRESETS) do
        local swatch = new("TextButton", {
            Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = color,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = i,
            Parent = swatches,
        }, { corner(10), stroke(Theme.Background, 2) })
        swatch.MouseEnter:Connect(hoverSound)
        swatch.MouseButton1Click:Connect(function()
            play("Click")
            element:Set(color)
        end)
    end

    local sliding = false
    local function fromInput(input)
        local h = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
        element:Set(Color3.fromHSV(h, 0.66, 0.84))
    end

    hueBar.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        sliding = true
        fromInput(input)
    end)
    connect(UserInputService.InputChanged, function(input)
        if sliding and isMove(input) then fromInput(input) end
    end)
    connect(UserInputService.InputEnded, function(input)
        if sliding and isPointer(input) then
            sliding = false
            play("Click")
        end
    end)

    hit.MouseButton1Click:Connect(function()
        play("Click")
        element.Open = not element.Open
        tween(frame, 0.3, { Size = UDim2.new(1, 0, 0, element.Open and 96 or 38) })
    end)

    element:Set(element.Value, true)
    Library.Elements[flag] = element
    return element
end

function Tab:Button(o)
    local callback = o.Callback or function() end
    local frame, hit = self:_row(38, o.Name)
    self:_label(frame, o.Name)

    accent(new("TextLabel", {
        Size = UDim2.fromOffset(60, 38),
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 0),
        BackgroundTransparency = 1,
        Text = o.Tag or "RUN",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    }), "TextColor3")

    hit.MouseButton1Click:Connect(function()
        play("Click")
        frame.BackgroundColor3 = Theme.AccentDark
        tween(frame, 0.45, { BackgroundColor3 = Theme.RowHover })
        task.spawn(callback)
    end)
end

-- live line graph: fps in the accent colour, ping in the secondary, redrawn every stats tick
function Tab:Graph(o)
    local frame = self:_row(100, o.Name)
    self:_label(frame, o.Name, 30)

    local fpsLabel = accent(new("TextLabel", {
        Size = UDim2.fromOffset(60, 30),
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 0),
        BackgroundTransparency = 1,
        Text = "0 FPS",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    }), "TextColor3")
    local pingLabel = accent(new("TextLabel", {
        Size = UDim2.fromOffset(60, 30),
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -76, 0, 0),
        BackgroundTransparency = 1,
        Text = "0 MS",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    }), "TextColor3", "Secondary")

    local area = new("Frame", {
        Size = UDim2.new(1, -24, 0, 58),
        Position = UDim2.fromOffset(12, 32),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.3,
        ClipsDescendants = true,
        Parent = frame,
    }, { corner(8) })

    for i = 1, 3 do
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.fromScale(0, i / 4),
            BackgroundColor3 = Theme.Stroke,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Parent = area,
        })
    end

    local function makeLine()
        local segments = {}
        for i = 1, GRAPH_POINTS - 1 do
            segments[i] = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BorderSizePixel = 0,
                Visible = false,
                Parent = area,
            }, { corner(1) })
        end
        return segments
    end
    local fpsLine, pingLine = makeLine(), makeLine()

    local function peak(list, floor)
        local m = floor
        for _, v in ipairs(list) do
            m = math.max(m, v)
        end
        return m
    end

    -- each segment is a thin frame rotated to join two neighbouring samples; newest sample sits on the right
    local function draw(segments, data, top, color)
        local w, h = area.AbsoluteSize.X, area.AbsoluteSize.Y
        if w <= 0 then return end
        local n = #data
        local function point(i, v)
            return (i - 1) / (GRAPH_POINTS - 1) * w, h - 5 - (v / top) * (h - 10)
        end
        for i, seg in ipairs(segments) do
            local a, b = data[n - GRAPH_POINTS + i], data[n - GRAPH_POINTS + i + 1]
            if a and b then
                local x1, y1 = point(i, a)
                local x2, y2 = point(i + 1, b)
                local dx, dy = x2 - x1, y2 - y1
                seg.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, 2)
                seg.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
                seg.Rotation = math.deg(math.atan2(dy, dx))
                seg.BackgroundColor3 = color
                seg.Visible = true
            else
                seg.Visible = false
            end
        end
    end

    table.insert(statListeners, function()
        local fps, ping = statHistory.fps, statHistory.ping
        fpsLabel.Text = (fps[#fps] or 0) .. " FPS"
        pingLabel.Text = (ping[#ping] or 0) .. " MS"
        draw(fpsLine, fps, peak(fps, 60) * 1.1, Theme.Accent)
        draw(pingLine, ping, peak(ping, 100) * 1.1, Theme.Secondary)
    end)
end

------------------------------------------------------------------------
-- accent colour and style

-- custom font: overrides every text object, remembering each one's own font so Default can restore it.
-- VX7 brings Bangers along unless a font has been picked.
local fontsOverridden = false

local function effectiveFont()
    if Settings.Font ~= "Default" then return Settings.Font end
    if isVX7() then return "Bangers" end
end

local function isText(obj)
    return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
end

local function overrideFont(obj, font)
    if obj:GetAttribute("BaseFont") == nil then
        obj:SetAttribute("BaseFont", obj.Font.Name)
    end
    obj.Font = font
end

local function syncFonts()
    local name = effectiveFont()
    if name then
        local font = Enum.Font[name]
        for _, d in ipairs(Gui:GetDescendants()) do
            if isText(d) then overrideFont(d, font) end
        end
        fontsOverridden = true
    elseif fontsOverridden then
        fontsOverridden = false
        for _, d in ipairs(Gui:GetDescendants()) do
            local base = isText(d) and d:GetAttribute("BaseFont")
            if base then d.Font = Enum.Font[base] end
        end
    end
end

-- notifications and other late text pick up the font as they appear
connect(Gui.DescendantAdded, function(d)
    if fontsOverridden and isText(d) then
        overrideFont(d, Enum.Font[effectiveFont()])
    end
end)

local function refreshAll()
    -- restore base fonts first so each style's own fonts win when no override is active
    if not effectiveFont() then syncFonts() end
    for _, fn in ipairs(themed) do
        fn()
    end
    for _, element in pairs(Library.Elements) do
        if element.Refresh then element:Refresh() end
    end
    if Library.Current then Library:Select(Library.Current, true) end
    if effectiveFont() then syncFonts() end
end

function Library:SetAccent(color, smooth)
    local h, s, v = color:ToHSV()
    Theme.Accent = color
    Theme.AccentDark = Color3.fromHSV(h, s, v * 0.35)
    Theme.AccentGlow = Color3.fromHSV(h, s * 0.3, 1)
    self.Fade = (smooth and not Settings.ReduceMotion) or false
    refreshAll()
    self.Fade = false
end

function Library:SetStyle(name)
    if name == self.Style then return end
    self.Style = name

    -- dip the window out, swap layouts while it's hidden, bring it back
    local wasVisible = self.Visible
    if wasVisible then
        tween(Main, 0.15, { GroupTransparency = 1 })
        task.wait(0.15)
    end
    refreshAll()
    if wasVisible then
        tween(Main, 0.25, { GroupTransparency = 0 })
        if not self.Searching and self.Current then animateRows(self.Current) end
    end
    play("Swap")
end

------------------------------------------------------------------------
-- config

local canFile = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"

local function encodeConfig()
    local data = {}
    for flag, element in pairs(Library.Elements) do
        local value = element:Get()
        if typeof(value) == "EnumItem" then
            value = { key = value.Name }
        elseif typeof(value) == "Color3" then
            value = { color = value:ToHex() }
        end
        data[flag] = value
    end
    -- things that aren't menu elements: window scale and where the window / pad / LD button sit
    local function fromUDim(u)
        return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
    end
    data._ui = {
        scale = Settings.UIScale,
        window = fromUDim(Holder.Position),
        pad = fromUDim(MobilePad.Position),
        mini = fromUDim(Mini.Position),
    }
    data._recent = Library.Recent or {}
    data._version = CONFIG_VERSION
    return HttpService:JSONEncode(data)
end

-- silent skips the notification, used by auto save and the startup load
function Library:SaveConfig(silent)
    if not canFile then
        if not silent then self:Notify("Config", "File saving isn't supported here.") end
        return
    end
    local json = encodeConfig()
    writefile(CONFIG_FILE, json)
    self.LastSaved = json
    if not silent then self:Notify("Config", "Saved to " .. CONFIG_FILE) end
end

function Library:LoadConfig(silent)
    if not canFile or not isfile(CONFIG_FILE) then
        if not silent then self:Notify("Config", "No saved config found.") end
        return
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(data) ~= "table" then
        if not silent then self:Notify("Config", "Config file is corrupted.") end
        return
    end
    -- configs from before the blue/pink palette still carry the old green accent
    if data._version ~= CONFIG_VERSION then
        if not silent then self:Notify("Config", "Old config ignored, it's from a previous version.") end
        return
    end

    local function apply(flag, value)
        local element = self.Elements[flag]
        if not element then return end
        if type(value) == "table" and value.key then
            value = Enum.KeyCode[value.key]
        elseif type(value) == "table" and value.color then
            value = Color3.fromHex(value.color)
        end
        pcall(element.Set, element, value)
    end

    -- the preset resets the accent, so it goes first and the saved accent wins
    apply("Theme Preset", data["Theme Preset"])
    for flag, value in pairs(data) do
        if flag ~= "Theme Preset" then apply(flag, value) end
    end

    if type(data._recent) == "table" then
        Library.Recent = {}
        for _, query in ipairs(data._recent) do
            if type(query) == "string" and #Library.Recent < 5 then table.insert(Library.Recent, query) end
        end
    end

    local ui = data._ui
    if type(ui) == "table" then
        local function toUDim(t)
            return type(t) == "table" and #t == 4 and UDim2.new(t[1], t[2], t[3], t[4]) or nil
        end
        if tonumber(ui.scale) then setUIScale(ui.scale) end
        Holder.Position = toUDim(ui.window) or Holder.Position
        MobilePad.Position = toUDim(ui.pad) or MobilePad.Position
        Mini.Position = toUDim(ui.mini) or Mini.Position
    end
    self.LastSaved = encodeConfig()
    if not silent then self:Notify("Config", "Config loaded.") end
end

-- always saving: every couple of seconds, write the config if anything changed
task.spawn(function()
    while Gui.Parent do
        task.wait(2)
        if canFile and Library.Loaded then
            local ok, json = pcall(encodeConfig)
            if ok and json ~= Library.LastSaved then
                if pcall(writefile, CONFIG_FILE, json) then
                    Library.LastSaved = json
                end
            end
        end
    end
end)

function Library:Unload()
    for _, c in ipairs(self.Connections) do
        c:Disconnect()
    end
    if hidIcon then UserInputService.MouseIconEnabled = true end
    Gui:Destroy()
end

------------------------------------------------------------------------
-- layout

local Movement = Library:Tab("MOVEMENT")
local Combat   = Library:Tab("COMBAT")
local KBM      = Library:Tab("KBM")
local Ctrl     = Library:Tab("CTRL")
local Visual   = Library:Tab("VISUAL")
local Config   = Library:Tab("SETTINGS")

Movement:Section("Speed Cycle")
Movement:Cycle({ Name = "Speed Mode", Options = { "V1", "V2", "V3" }, Default = "V2" })
Movement:Toggle({ Name = "Auto Switch Speed" })
Movement:Cycle({ Name = "Lagger Mode", Options = { "V1", "V2", "V3" }, Default = "V1" })
Movement:Section("Normal Mode")
Movement:Number({ Name = "Normal Speed", Default = 50, Min = 0 })
Movement:Number({ Name = "Carry Speed", Default = 43, Min = 0 })
Movement:Section("Jump")
Movement:Toggle({ Name = "Infinite Jump" })
Movement:Slider({ Name = "Jump Power", Min = 50, Max = 150, Default = 50 })

Combat:Section("Bat Controls")
Combat:Segment({ Name = "Bat Aimbot", Options = { "Regular", "Bypass", "Custom" } })
Combat:Number({ Name = "TP Swing Delay", Default = 0.007, Min = 0 })
Combat:Toggle({ Name = "Auto Bat" })

-- one-shot actions; the menu button and the mobile pad button both call these.
-- they do nothing on their own: hook your own code in here.
local Actions = {
    ["Drop Brainrot"] = function() end,
    ["TP Down"] = function() end,
}

Combat:Section("Actions")
Combat:Button({ Name = "Drop Brainrot", Tag = "DROP", Callback = function() Actions["Drop Brainrot"]() end })
Combat:Button({ Name = "TP Down", Tag = "TP", Callback = function() Actions["TP Down"]() end })
Combat:Section("Steal")
Combat:Toggle({
    Name = "Auto Steal",
    Callback = function(state)
        showStealBar(state)
        if state then Library:SetStealProgress(0) end
    end,
})
Combat:Dropdown({
    Name = "Auto Steal Mode",
    Options = { "V1", "V2" },
    Default = "V1",
    Callback = function(value)
        setStealVersion(value)
    end,
})
Combat:Section("Auto Path")
Combat:Toggle({ Name = "Auto Left" })
Combat:Toggle({ Name = "Auto Right" })
Combat:Toggle({ Name = "Match Speed", Default = true })
Combat:Section("Counters")
Combat:Toggle({ Name = "Bat Counter", Default = true })
Combat:Toggle({ Name = "Medusa Counter", Default = true })
Combat:Toggle({ Name = "Confuser" })
Combat:Toggle({ Name = "Auto Confuser" })

-- binds that flip their matching combat toggle
local function bindToggle(name, key)
    KBM:Keybind({
        Name = name,
        Default = key,
        Callback = function()
            local toggle = Library.Elements[name]
            if not toggle then return end
            toggle:Set(not toggle:Get())
            play(toggle:Get() and "On" or "Off")
            Library:Notify(name, toggle:Get() and "Enabled" or "Disabled", 1.5)
        end,
    })
end

KBM:Section("Auto Path")
bindToggle("Auto Left", Enum.KeyCode.Q)
bindToggle("Auto Right", Enum.KeyCode.E)
KBM:Section("Counters")
bindToggle("Bat Counter", Enum.KeyCode.F)
bindToggle("Medusa Counter", Enum.KeyCode.G)
bindToggle("Confuser", Enum.KeyCode.C)

-- the mobile pad only carries what you need mid-fight
addMobileToggle("Auto Left")
addMobileToggle("Auto Right")
addMobileCycle("Speed Mode", "SPEED")
addMobileCycle("Lagger Mode", "LAGGER")
addMobileToggle("Auto Bat")
addMobileAction("DROP\nBRAINROT", function() Actions["Drop Brainrot"]() end)
addMobileAction("TP\nDOWN", function() Actions["TP Down"]() end)

Ctrl:Section("Input")
Ctrl:Dropdown({ Name = "Control Mode", Options = { "Mouse", "Touch", "Controller" } })
Ctrl:Toggle({ Name = "Shift Lock" })
Ctrl:Slider({ Name = "Sensitivity", Min = 0.1, Max = 3, Default = 1, Step = 0.1, Suffix = "x" })

Visual:Section("World")
Visual:Toggle({ Name = "Player Highlight" })
Visual:Dropdown({ Name = "Highlight Color", Options = { "Pink", "Blue", "White", "Red" } })
Visual:Slider({ Name = "Field of View", Min = 70, Max = 120, Default = 70 })
Visual:Section("Hud")
Visual:Toggle({
    Name = "Watermark",
    Default = true,
    List = false,
    Callback = function(state)
        Watermark.Visible = state
    end,
})
Visual:Toggle({
    Name = "Active List",
    Default = true,
    List = false,
    Callback = function(state)
        ActiveList.Visible = state
    end,
})
Visual:Toggle({
    Name = "Custom Cursor",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.Cursor = state
    end,
})
Visual:Section("Effects")
Visual:Toggle({
    Name = "Mascot",
    Default = false,
    List = false,
    Callback = function(state)
        Mascot.Visible = state
    end,
})
Visual:Section("Performance")
Visual:Graph({ Name = "Live Stats" })
Visual:Section("Backdrop")
Visual:Toggle({
    Name = "Living Background",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.Aurora = state
        if Library.AuroraLayer then Library.AuroraLayer.Visible = state end
    end,
})
Visual:Dropdown({
    Name = "Backdrop FX",
    Options = { "Particles", "Hearts", "Leaves", "Matrix", "Off" },
    Default = "Particles",
    Callback = function(value)
        applyBackdrop(value)
    end,
})

Config:Section("Interface")
Config:Dropdown({
    Name = "UI Style",
    Options = { "Adapt Style", "Candy Style", "Bubble Hub Style", "Ambitious Hub Style", "VX7 Style" },
    Default = "Adapt Style",
    Callback = function(value)
        Library:SetStyle(value:match("^%w+"))
    end,
})
Config:Dropdown({
    Name = "UI Font",
    Options = { "Default", "Bangers", "Luckiest Guy", "Michroma", "Oswald", "Fredoka One", "Arcade", "Permanent Marker", "Special Elite" },
    Default = "Default",
    Callback = function(value)
        Settings.Font = (value:gsub(" ", ""))
        refreshAll()
        play("Swap")
    end,
})
Config:Toggle({
    Name = "Mobile Buttons",
    Default = IS_MOBILE,
    List = false,
    Callback = function(state)
        Settings.MobileButtons = state
        MobilePad.Visible = state and Library.Loaded == true
    end,
})
Config:Toggle({
    Name = "Loading Intro",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.Intro = state
    end,
})
Config:Toggle({
    Name = "Lock Screen Intro",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.LockScreen = state
    end,
})
Config:Toggle({
    Name = "Reduce Motion",
    List = false,
    Callback = function(state)
        Settings.ReduceMotion = state
        applyBackdrop(Settings.Backdrop)
    end,
})
Config:Toggle({
    Name = "Window Snapping",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.Snap = state
    end,
})
Config:Keybind({
    Name = "Toggle UI",
    Default = Settings.ToggleKey,
    Flag = "ToggleKey",
    Changed = function(key)
        Settings.ToggleKey = key
    end,
})
local AccentPicker = Config:ColorPicker({
    Name = "Accent Colour",
    Default = Theme.Accent,
    Callback = function(color)
        if not Settings.Rainbow then Library:SetAccent(color) end
    end,
})
-- each preset swaps the whole palette: every surface still using an old theme colour gets remapped
local THEME_PRESETS = {
    ["Classic"] = {
        Background = Color3.fromRGB(10, 8, 14),   Panel = Color3.fromRGB(16, 12, 20),
        Row = Color3.fromRGB(21, 16, 26),         RowHover = Color3.fromRGB(31, 23, 37),
        Stroke = Color3.fromRGB(56, 40, 66),      Off = Color3.fromRGB(54, 42, 60),
        Text = Color3.fromRGB(245, 236, 245),     SubText = Color3.fromRGB(164, 142, 170),
        Accent = Color3.fromRGB(255, 105, 180),
    },
    ["Crimson"] = {
        Background = Color3.fromRGB(14, 8, 9),    Panel = Color3.fromRGB(22, 12, 14),
        Row = Color3.fromRGB(26, 15, 17),         RowHover = Color3.fromRGB(36, 20, 23),
        Stroke = Color3.fromRGB(58, 32, 36),      Off = Color3.fromRGB(54, 36, 39),
        Text = Color3.fromRGB(245, 236, 237),     SubText = Color3.fromRGB(160, 128, 132),
        Accent = Color3.fromRGB(235, 60, 72),
    },
    ["Frost"] = {
        Background = Color3.fromRGB(6, 10, 16),   Panel = Color3.fromRGB(10, 16, 24),
        Row = Color3.fromRGB(13, 20, 30),         RowHover = Color3.fromRGB(19, 29, 42),
        Stroke = Color3.fromRGB(32, 48, 66),      Off = Color3.fromRGB(34, 46, 60),
        Text = Color3.fromRGB(232, 240, 248),     SubText = Color3.fromRGB(120, 140, 160),
        Accent = Color3.fromRGB(110, 200, 255),
    },
    ["Sky"] = {
        Background = Color3.fromRGB(8, 9, 18),    Panel = Color3.fromRGB(13, 15, 28),
        Row = Color3.fromRGB(16, 19, 34),         RowHover = Color3.fromRGB(23, 27, 46),
        Stroke = Color3.fromRGB(38, 44, 76),      Off = Color3.fromRGB(40, 45, 72),
        Text = Color3.fromRGB(236, 238, 250),     SubText = Color3.fromRGB(128, 136, 172),
        Accent = Color3.fromRGB(90, 170, 255),
    },
    ["Midnight"] = {
        Background = Color3.fromRGB(9, 7, 16),    Panel = Color3.fromRGB(14, 11, 24),
        Row = Color3.fromRGB(18, 14, 30),         RowHover = Color3.fromRGB(26, 20, 42),
        Stroke = Color3.fromRGB(44, 34, 68),      Off = Color3.fromRGB(40, 32, 58),
        Text = Color3.fromRGB(236, 232, 248),     SubText = Color3.fromRGB(132, 120, 160),
        Accent = Color3.fromRGB(160, 110, 255),
    },
}

local BASE_KEYS = { "Background", "Panel", "Row", "RowHover", "Stroke", "Off", "Text", "SubText" }

local function sameColor(a, b)
    return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

function Library:ApplyPreset(name)
    local preset = THEME_PRESETS[name]
    if not preset then return end

    -- a preset change fades over about half a second; a second change in that window waits its turn
    if self.PresetBusy then
        self.PresetQueued = name
        return
    end
    self.PresetBusy = true
    task.delay(0.55, function()
        self.PresetBusy = false
        local queued = self.PresetQueued
        self.PresetQueued = nil
        if queued then self:ApplyPreset(queued) end
    end)
    local smooth = not Settings.ReduceMotion

    local function remap(obj, prop)
        local color = obj[prop]
        for _, key in ipairs(BASE_KEYS) do
            if sameColor(color, Theme[key]) then
                if smooth then
                    tween(obj, 0.45, { [prop] = preset[key] })
                else
                    obj[prop] = preset[key]
                end
                return
            end
        end
    end

    for _, d in ipairs(Gui:GetDescendants()) do
        if d:IsA("GuiObject") then
            remap(d, "BackgroundColor3")
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                remap(d, "TextColor3")
                if d:IsA("TextBox") then remap(d, "PlaceholderColor3") end
            end
        elseif d:IsA("UIStroke") then
            remap(d, "Color")
        end
    end

    for _, key in ipairs(BASE_KEYS) do
        Theme[key] = preset[key]
    end
    AccentPicker:Set(preset.Accent, true)
    if Settings.Rainbow then refreshAll() else self:SetAccent(preset.Accent, true) end
    play("Swap")
end

Config:Dropdown({
    Name = "Theme Preset",
    Options = { "Classic", "Sky", "Crimson", "Frost", "Midnight" },
    Default = "Classic",
    Callback = function(value)
        Library:ApplyPreset(value)
    end,
})
Config:Toggle({
    Name = "Rainbow Mode",
    List = false,
    Callback = function(state)
        Settings.Rainbow = state
        if not state then Library:SetAccent(AccentPicker:Get()) end
    end,
})
Config:Section("Sound")
Config:Toggle({
    Name = "UI Sounds",
    Default = true,
    List = false,
    Callback = function(state)
        Settings.Sounds = state
    end,
})
Config:Slider({
    Name = "Volume",
    Min = 0,
    Max = 200,
    Default = 100,
    Suffix = "%",
    Callback = function(value)
        Settings.Volume = value / 100
    end,
})
-- pick up where the last session left off
Library:LoadConfig(true)

-- the intro, lock screen and startup live in their own function: Luau caps a single scope
-- at 200 locals and the top level of this file is already close to that
local function runStartup()

-- teardown for whatever the intro / lock screen has on screen, run if the player skips them
local introCleanup = {}

------------------------------------------------------------------------
-- shared intro pieces: a soft blur over the game, glows, rings, and hearts drifting up

local Lighting = game:GetService("Lighting")
local introBlurEffect

local function blurIn(size)
    if not introBlurEffect then
        local ok, blur = pcall(new, "BlurEffect", { Name = "LovelyBlur", Size = 0, Parent = Lighting })
        if not ok then return end
        introBlurEffect = blur
    end
    tween(introBlurEffect, 0.6, { Size = size }, Enum.EasingStyle.Sine)
end

local function blurOut()
    local blur = introBlurEffect
    introBlurEffect = nil
    if not blur then return end
    tween(blur, 0.5, { Size = 0 }, Enum.EasingStyle.Sine)
    Debris:AddItem(blur, 0.55)
end

-- stacked translucent circles read as a soft radial glow, brightest in the middle
local function makeGlow(parent, size, color, zindex)
    local glow = new("Frame", {
        Size = UDim2.fromOffset(size, size),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        ZIndex = zindex,
        Parent = parent,
    })
    local rings = {}
    for i = 1, 6 do
        local s = 1 - (i - 1) * 0.15
        rings[i] = new("Frame", {
            Size = UDim2.fromScale(s, s),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = color,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = zindex,
            Parent = glow,
        }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    end
    return glow, rings
end

local function setGlow(rings, strength, time)
    for _, ring in ipairs(rings) do
        tween(ring, time or 0.6, { BackgroundTransparency = 1 - 0.07 * strength }, Enum.EasingStyle.Sine)
    end
end

local function ringBurst(parent, position, from, to, color, zindex, time)
    local ring = new("Frame", {
        Size = UDim2.fromOffset(from, from),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position,
        BackgroundTransparency = 1,
        ZIndex = zindex,
        Parent = parent,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local ringStroke = stroke(color, 2, 0.15)
    ringStroke.Parent = ring
    tween(ring, time, { Size = UDim2.fromOffset(to, to) }, Enum.EasingStyle.Quart)
    tween(ringStroke, time, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quart)
    Debris:AddItem(ring, time + 0.05)
end

-- pink and purple hearts floating up the whole screen; Target 0 shows them, 1 hides them
local function heartField(parent, count, zindex)
    local field = { Fade = 1, Target = 1, Hearts = {} }
    for i = 1, count do
        local frame, parts = makeHeart(parent, math.random(8, 20), zindex)
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        for _, p in ipairs(parts) do
            p.BackgroundColor3 = i % 3 == 0 and Theme.Secondary or Theme.Accent
            p.BackgroundTransparency = 1
        end
        field.Hearts[i] = {
            Frame = frame,
            Parts = parts,
            X = math.random(),
            Y = math.random() * 1.1,
            Speed = 0.025 + math.random() * 0.045,
            Phase = math.random() * math.pi * 2,
            Alpha = 0.55 + math.random() * 0.35,
        }
    end
    function field.step(dt, now)
        field.Fade += (field.Target - field.Fade) * math.min(dt * 3, 1)
        for _, h in ipairs(field.Hearts) do
            h.Y -= h.Speed * dt
            if h.Y < -0.08 then
                h.Y = 1.08
                h.X = math.random()
            end
            h.Frame.Position = UDim2.fromScale(h.X + math.sin(now * 0.7 + h.Phase) * 0.012, h.Y)
            h.Frame.Rotation = math.sin(now * 0.9 + h.Phase) * 14
            local t = h.Alpha + (1 - h.Alpha) * field.Fade
            for _, p in ipairs(h.Parts) do
                p.BackgroundTransparency = t
            end
        end
    end
    return field
end

------------------------------------------------------------------------
-- lock screen: blurred game behind drifting glows, a big clock, and a heart knob to slide across

local function runLockScreen()
    local unlocked = false
    local conns, inputConns = {}, {}
    blurIn(22)

    local screen = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        ZIndex = 60,
        Parent = Gui,
    })

    local blobA, blobARings = makeGlow(screen, 620, Theme.Accent, 60)
    local blobB, blobBRings = makeGlow(screen, 540, Theme.Secondary, 60)
    local field = heartField(screen, 14, 60)

    -- everything in front fades and lifts as one when unlocking
    local content = new("CanvasGroup", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        ZIndex = 61,
        Parent = screen,
    })

    local function label(props)
        props.AnchorPoint = Vector2.new(0.5, 0.5)
        props.BackgroundTransparency = 1
        props.ZIndex = 62
        props.Parent = content
        return new("TextLabel", props)
    end

    local date = label({
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0.5, 0, 0.22, -72),
        Text = string.upper(os.date("%A  %d %B")),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.SubText,
    })

    local clock = label({
        Size = UDim2.new(1, 0, 0, 110),
        Position = UDim2.fromScale(0.5, 0.22),
        RichText = true,
        Text = os.date("%H:%M"),
        Font = Enum.Font.GothamBold,
        TextSize = 104,
        TextColor3 = Color3.new(1, 1, 1),
    }, nil)
    new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.new(1, 1, 1), Theme.AccentGlow),
        Parent = clock,
    })

    local hour = tonumber(os.date("%H"))
    local greeting = label({
        Size = UDim2.new(1, 0, 0, 22),
        Position = UDim2.new(0.5, 0, 0.22, 66),
        RichText = true,
        Text = string.format('%s, <font color="#%s">%s</font>',
            hour < 12 and "Good morning" or hour < 18 and "Good afternoon" or "Good evening",
            Theme.Accent:ToHex(), LocalPlayer.DisplayName),
        Font = Enum.Font.GothamMedium,
        TextSize = 16,
        TextColor3 = Theme.Text,
    })

    -- profile: avatar inside a slowly spinning pink-to-purple ring
    local profile = new("Frame", {
        Size = UDim2.fromOffset(160, 140),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.52, 0),
        BackgroundTransparency = 1,
        ZIndex = 62,
        Parent = content,
    })
    local ring = new("Frame", {
        Size = UDim2.fromOffset(88, 88),
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0),
        BackgroundTransparency = 1,
        ZIndex = 62,
        Parent = profile,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local ringStroke = stroke(Color3.new(1, 1, 1), 2.5)
    ringStroke.Parent = ring
    local ringSpin = new("UIGradient", {
        Color = ColorSequence.new(Theme.Accent, Theme.Secondary),
        Parent = ringStroke,
    })
    local avatar = new("ImageLabel", {
        Size = UDim2.fromOffset(76, 76),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Theme.Row,
        Image = Avatar.Image,
        ZIndex = 63,
        Parent = ring,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    table.insert(conns, Avatar:GetPropertyChangedSignal("Image"):Connect(function()
        avatar.Image = Avatar.Image
    end))
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.fromOffset(0, 100),
        BackgroundTransparency = 1,
        Text = "L O V E L Y   D U E L S",
        Font = Enum.Font.GothamBlack,
        TextSize = 11,
        TextColor3 = Theme.Accent,
        ZIndex = 62,
        Parent = profile,
    })
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.fromOffset(0, 118),
        BackgroundTransparency = 1,
        Text = "@" .. LocalPlayer.Name,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.SubText,
        ZIndex = 62,
        Parent = profile,
    })

    -- slider: glassy pill with a white knob carrying a little heart
    local TRACK_W, KNOB = 300, 50
    local maxX = TRACK_W - KNOB - 4

    local track = new("Frame", {
        Size = UDim2.fromOffset(TRACK_W, KNOB + 8),
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -76),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.25,
        ZIndex = 62,
        Parent = content,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local trackStroke = stroke(Theme.Accent, 1, 0.55)
    trackStroke.Parent = track

    local fill = new("Frame", {
        Size = UDim2.new(0, KNOB + 8, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.35,
        ZIndex = 62,
        Parent = track,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.Secondary) }),
    })

    local hint = new("TextLabel", {
        Size = UDim2.new(1, -KNOB, 1, 0),
        Position = UDim2.fromOffset(KNOB, 0),
        BackgroundTransparency = 1,
        Text = "slide to unlock",
        Font = Enum.Font.GothamMedium,
        TextSize = 15,
        TextColor3 = Theme.Text,
        ZIndex = 63,
        Parent = track,
    })
    local hintShine = new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.65),
            NumberSequenceKeypoint.new(0.42, 0.65),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.58, 0.65),
            NumberSequenceKeypoint.new(1, 0.65),
        }),
        Parent = hint,
    })

    -- Modal frees the mouse in first-person / shift-lock games so the knob can be dragged
    local knob = new("TextButton", {
        Size = UDim2.fromOffset(KNOB, KNOB),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Text = "",
        AutoButtonColor = false,
        Modal = true,
        ZIndex = 64,
        Parent = track,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local knobHeart, knobParts = makeHeart(knob, 22, 65)
    knobHeart.AnchorPoint = Vector2.new(0.5, 0.5)
    knobHeart.Position = UDim2.fromScale(0.5, 0.52)
    for _, p in ipairs(knobParts) do
        p.BackgroundColor3 = Theme.Accent
    end

    local enterHint = label({
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0.5, 0, 1, -54),
        Text = IS_MOBILE and "double tap to skip" or "or press Enter",
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextTransparency = 0.3,
    })

    table.insert(introCleanup, function()
        unlocked = true
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        for _, c in ipairs(inputConns) do
            c:Disconnect()
        end
        stopSpring(knob)
        knob.Modal = false
        screen:Destroy()
    end)

    -- fade the backdrop in, then lift each piece into place one after another
    tween(screen, 0.5, { BackgroundTransparency = 0.3 })
    setGlow(blobARings, 1.2, 0.9)
    setGlow(blobBRings, 1.1, 0.9)
    field.Target = 0
    tween(content, 0.45, { GroupTransparency = 0 })
    for i, obj in ipairs({ date, clock, greeting, profile, track, enterHint }) do
        local goal = obj.Position
        obj.Position = goal + UDim2.fromOffset(0, 28)
        task.delay(i * 0.06, function()
            tween(obj, 0.7, { Position = goal })
        end)
    end

    local function setKnob(x)
        knob.Position = UDim2.new(0, x, 0.5, 0)
        fill.Size = UDim2.new(0, x + KNOB + 4, 1, 0)
        hint.TextTransparency = math.clamp((x - 4) / (maxX * 0.5), 0, 1)
    end

    local function unlock()
        if unlocked then return end
        unlocked = true
        for _, c in ipairs(inputConns) do
            c:Disconnect()
        end
        knob.Modal = false
        stopSpring(knob)
        setKnob(maxX)
        play("Unlock")

        -- hearts ring out from the knob, then the whole screen lifts away
        local center = knob.AbsolutePosition + knob.AbsoluteSize / 2 - screen.AbsolutePosition
        for k = 0, 2 do
            task.delay(k * 0.08, ringBurst, screen, UDim2.fromOffset(center.X, center.Y), 50, 320,
                k == 1 and Theme.Secondary or Theme.Accent, 66, 0.8)
        end
        tween(content, 0.5, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -40) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        setGlow(blobARings, 0, 0.6)
        setGlow(blobBRings, 0, 0.6)
        field.Target = 1
        tween(screen, 0.6, { BackgroundTransparency = 1 })
    end

    local dragging, startX, startOff = false, 0, 4
    knob.InputBegan:Connect(function(input)
        if unlocked or not isPointer(input) then return end
        dragging, startX, startOff = true, input.Position.X, knob.Position.X.Offset
        stopSpring(knob)
        play("Click")
    end)
    table.insert(inputConns, UserInputService.InputChanged:Connect(function(input)
        if dragging and isMove(input) then
            setKnob(math.clamp(startOff + input.Position.X - startX, 4, maxX))
        end
    end))
    table.insert(inputConns, UserInputService.InputEnded:Connect(function(input)
        if not dragging or not isPointer(input) then return end
        dragging = false
        if knob.Position.X.Offset >= maxX - 8 then
            unlock()
        else
            -- not far enough: spring back to the start
            play("Off")
            springTo(knob, knob.Position.X.Offset, 4, setKnob, 16, 0.55)
        end
    end))
    table.insert(inputConns, UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Return or (Settings.ToggleKey and input.KeyCode == Settings.ToggleKey) then
            unlock()
        end
    end))

    table.insert(conns, RunService.RenderStepped:Connect(function(dt)
        local now = os.clock()
        field.step(dt, now)
        blobA.Position = UDim2.fromScale(0.3 + math.sin(now * 0.25) * 0.08, 0.35 + math.cos(now * 0.2) * 0.06)
        blobB.Position = UDim2.fromScale(0.72 + math.cos(now * 0.22) * 0.08, 0.62 + math.sin(now * 0.27) * 0.06)
        ringSpin.Rotation = (now * 90) % 360
        hintShine.Offset = Vector2.new(((now * 0.5) % 1) * 2 - 1, 0)
        -- the colon breathes once a second
        local colon = (0.5 + 0.5 * math.cos(now * math.pi * 2)) * 0.7
        clock.Text = string.format('%s<font transparency="%.2f">:</font>%s', os.date("%H"), colon, os.date("%M"))
    end))

    while not unlocked do
        task.wait()
    end
    task.wait(0.65)
    for _, c in ipairs(conns) do
        c:Disconnect()
    end
    screen:Destroy()
end

------------------------------------------------------------------------
-- intro: a heart pops in and beats, the name drops in letter by letter, a loading line fills

local function runIntro()
    -- with the intro turned off, go straight to the lock screen (if that's still on)
    if not Settings.Intro or Settings.ReduceMotion then
        if Settings.LockScreen and not Settings.ReduceMotion then
            runLockScreen()
        end
        return
    end

    local alive = true
    local conns = {}
    blurIn(18)

    local overlay = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        ZIndex = 50,
        Parent = Gui,
    })

    -- deep accent wash rising from the bottom of the screen
    local wash = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.AccentDark,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 50,
        Parent = overlay,
    }, {
        new("UIGradient", {
            Rotation = -90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.15),
                NumberSequenceKeypoint.new(0.6, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    local field = heartField(overlay, 22, 51)
    table.insert(conns, RunService.RenderStepped:Connect(function(dt)
        field.step(dt, os.clock())
    end))

    table.insert(introCleanup, function()
        alive = false
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        overlay:Destroy()
    end)

    tween(overlay, 0.5, { BackgroundTransparency = 0.08 })
    tween(wash, 0.8, { BackgroundTransparency = 0 })
    field.Target = 0

    local skipHint = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -24),
        BackgroundTransparency = 1,
        Text = IS_MOBILE and "double tap to skip" or "double click to skip",
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextTransparency = 1,
        ZIndex = 53,
        Parent = overlay,
    })
    tween(skipHint, 0.6, { TextTransparency = 0.4 })

    -- one canvas so the whole logo can fade and grow away at the end
    local STAGE_W, HEART_Y = 520, 150
    local stage = new("CanvasGroup", {
        Size = UDim2.fromOffset(STAGE_W, 440),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
        ZIndex = 52,
        Parent = overlay,
    })
    local stageScale = new("UIScale", { Parent = stage })

    local glow, glowRings = makeGlow(stage, 300, Theme.Accent, 52)
    glow.Position = UDim2.fromOffset(STAGE_W / 2, HEART_Y)

    local heart, heartParts = makeHeart(stage, 92, 54)
    heart.AnchorPoint = Vector2.new(0.5, 0.5)
    heart.Position = UDim2.fromOffset(STAGE_W / 2, HEART_Y)
    local heartScale = new("UIScale", { Scale = 0, Parent = heart })
    for i, p in ipairs(heartParts) do
        p.BackgroundColor3 = Theme.Accent
        -- the diamond is already turned 45 degrees, so its shading is turned back to match
        new("UIGradient", {
            Rotation = i == 1 and 45 or 90,
            Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(175, 165, 195)),
            Parent = p,
        })
    end
    new("Frame", {
        Size = UDim2.fromScale(0.16, 0.1),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.28, 0.3),
        Rotation = -35,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 55,
        Parent = heart,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    -- LOVELY, each letter shaded a step further from pink toward purple
    local word, size, gap = "LOVELY", 64, 2
    local widths, total = {}, 0
    for i = 1, #word do
        local w = TextService:GetTextSize(word:sub(i, i), size, Enum.Font.FredokaOne, Vector2.new(500, 500)).X
        widths[i] = w
        total += w + (i > 1 and gap or 0)
    end

    local LETTER_Y = 206
    local letters = {}
    local x = (STAGE_W - total) / 2
    for i = 1, #word do
        letters[i] = new("TextLabel", {
            Size = UDim2.fromOffset(widths[i], 70),
            Position = UDim2.fromOffset(x, LETTER_Y + 30),
            BackgroundTransparency = 1,
            Text = word:sub(i, i),
            Font = Enum.Font.FredokaOne,
            TextSize = size,
            TextColor3 = Theme.Accent:Lerp(Theme.Secondary, (i - 1) / (#word - 1)),
            TextTransparency = 1,
            ZIndex = 54,
            Parent = stage,
        }, {
            new("UIStroke", { Color = Color3.fromRGB(24, 8, 22), Thickness = 2, Transparency = 1 }),
        })
        x += widths[i] + gap
    end

    local duels = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.fromOffset(0, 280),
        BackgroundTransparency = 1,
        Text = "DUELS",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextTransparency = 1,
        ZIndex = 54,
        Parent = stage,
    })

    -- loading line with a glowing head, a status on the left and a percentage on the right
    local track = new("Frame", {
        Size = UDim2.fromOffset(260, 3),
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromOffset(STAGE_W / 2, 330),
        BackgroundColor3 = Theme.Off,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 54,
        Parent = stage,
    }, { corner(2) })
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 55,
        Parent = track,
    }, {
        corner(2),
        new("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.Secondary) }),
    })
    local head = new("Frame", {
        Size = UDim2.fromOffset(9, 9),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        BackgroundColor3 = Theme.AccentGlow,
        BackgroundTransparency = 1,
        ZIndex = 56,
        Parent = fill,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local status = new("TextLabel", {
        Size = UDim2.fromOffset(200, 14),
        Position = UDim2.fromOffset(STAGE_W / 2 - 130, 342),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 54,
        Parent = stage,
    })
    local percent = new("TextLabel", {
        Size = UDim2.fromOffset(60, 14),
        Position = UDim2.fromOffset(STAGE_W / 2 + 70, 342),
        BackgroundTransparency = 1,
        Text = "0%",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.Accent,
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 54,
        Parent = stage,
    })

    local function setHeart(target, freq, damp)
        springTo(heartScale, heartScale.Scale, target, function(v)
            heartScale.Scale = v
        end, freq, damp)
    end

    task.wait(0.3)

    -- the heart pops in with a wobble and starts beating: lub-dub, pause
    setGlow(glowRings, 1, 0.8)
    play("Pop")
    setHeart(1, 9, 0.42)
    task.spawn(function()
        task.wait(0.7)
        while alive do
            for _, peak in ipairs({ 1.14, 1.07 }) do
                if not alive then return end
                setHeart(peak, 22, 0.5)
                if peak > 1.1 then
                    ringBurst(stage, heart.Position, 90, 240, Theme.Accent, 53, 0.9)
                end
                task.wait(0.09)
                if not alive then return end
                setHeart(1, 14, 0.45)
                task.wait(0.16)
            end
            task.wait(0.6)
        end
    end)

    -- one rising shimmer covers the whole word instead of a click per letter
    task.wait(0.45)
    play("Shimmer")
    for _, letter in ipairs(letters) do
        tween(letter, 0.6, { Position = UDim2.fromOffset(letter.Position.X.Offset, LETTER_Y), TextTransparency = 0 }, Enum.EasingStyle.Back)
        tween(letter.UIStroke, 0.45, { Transparency = 0 })
        task.wait(0.08)
    end

    -- DUELS spreads its letters apart as it fades in
    task.wait(0.2)
    tween(duels, 0.5, { TextTransparency = 0.15 })
    local spacing = Instance.new("NumberValue")
    spacing.Changed:Connect(function(v)
        duels.Text = table.concat({ "D", "U", "E", "L", "S" }, string.rep(" ", math.floor(v + 0.5)))
    end)
    tween(spacing, 0.8, { Value = 4 })
    Debris:AddItem(spacing, 1)

    task.wait(0.35)
    tween(track, 0.3, { BackgroundTransparency = 0.3 })
    tween(head, 0.3, { BackgroundTransparency = 0 })
    tween(status, 0.3, { TextTransparency = 0.1 })
    tween(percent, 0.3, { TextTransparency = 0 })

    local steps = {
        { "Loading interface", 0.3 },
        { "Building tabs", 0.55 },
        { "Fetching profile", 0.8 },
        { "Ready", 1 },
    }
    -- the loading line fills quietly; the finale is where the sound lands
    local last = 0
    for _, step in ipairs(steps) do
        status.Text = step[1]
        tween(fill, 0.4, { Size = UDim2.fromScale(step[2], 1) })
        rollText(percent, last * 100, step[2] * 100, 0, "%", 0.4)
        last = step[2]
        task.wait(0.42)
    end

    -- finale: one big beat, rings burst out, and the logo grows and dissolves
    alive = false
    play("Ready")
    setHeart(1.3, 16, 0.4)
    setGlow(glowRings, 1.6, 0.2)
    for k = 0, 2 do
        task.delay(k * 0.08, ringBurst, stage, heart.Position, 100, 420, k == 1 and Theme.Secondary or Theme.Accent, 53, 1)
    end
    task.wait(0.35)
    tween(stage, 0.5, { GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(stageScale, 0.5, { Scale = 1.12 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(skipHint, 0.3, { TextTransparency = 1 })
    task.wait(0.4)

    field.Target = 1
    tween(wash, 0.5, { BackgroundTransparency = 1 })
    tween(overlay, 0.5, { BackgroundTransparency = 1 })
    if Settings.LockScreen then
        task.wait(0.1)
        runLockScreen()
    else
        task.wait(0.5)
    end
    for _, c in ipairs(conns) do
        c:Disconnect()
    end
    overlay:Destroy()
end

task.spawn(function()
    -- double click / double tap anywhere while the intro or lock screen is up to jump straight in
    local skipped, lastTap = false, 0
    local skipConn = UserInputService.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        local now = os.clock()
        if now - lastTap < 0.35 then skipped = true end
        lastTap = now
    end)

    local intro = task.spawn(runIntro)
    repeat
        task.wait()
    until skipped or coroutine.status(intro) == "dead"
    skipConn:Disconnect()

    if skipped then
        task.cancel(intro)
        -- the menu's own open sound plays right after, so skipping adds nothing on top
        for _, fn in ipairs(introCleanup) do
            pcall(fn)
        end
    end
    blurOut()

    Library.Loaded = true
    Mini.Visible = true
    MobilePad.Visible = Settings.MobileButtons
    setVisible(true)
    task.wait(0.2)
    Library:Notify("Lovely Duels", IS_MOBILE and "Loaded. Tap the LD button to hide." or "Loaded. Press " .. Settings.ToggleKey.Name .. " to hide.", 4)
end)

end

runStartup()

return Library
