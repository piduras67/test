--[[
    Lovely Swords
    Builds three display swords out of Parts, each floating over a glowing stone stand.

    How to use:
      1. In Roblox Studio open View > Command Bar.
      2. Paste this whole script in and press Enter.
      3. The swords appear in front of the camera, inside a folder called "Lovely Swords".
         Press Play to see them spin and float. Ctrl+Z removes them.

    Every piece is a normal Part, so you can ungroup, recolour or resize anything afterwards.
]]

local SETTINGS = {
    Scale = 1,        -- 2 makes every sword twice as big
    Stand = true,     -- false builds the swords on their own, without stands
    Animate = true,   -- swords slowly spin and float when the game runs
    Spacing = 7,      -- studs between the swords
    Distance = 16,    -- how far in front of the camera they appear
}

local V = Vector3.new
local C = Color3.fromRGB

local SWORDS = {
    {
        Name = "Royal Longsword",
        Accent = C(70, 130, 255),
        Hover = 1.7, -- how high the sword floats above its stand
        Colors = {
            Steel = C(188, 194, 204),
            Edge = C(228, 232, 240),
            Fuller = C(118, 126, 140),
            Gold = C(214, 172, 72),
            Leather = C(72, 42, 28),
            Wrap = C(44, 26, 18),
            Gem = C(70, 130, 255),
        },
        -- { shape, size, position, rotation (degrees), colour, material, transparency, effect }
        Pieces = {
            { "Ball", V(0.44, 0.44, 0.44), V(0, -0.06, 0), V(0, 0, 0), "Gold", "Metal" },
            { "Cylinder", V(0.5, 0.2, 0.2), V(0, -0.06, 0), V(0, 90, 0), "Gem", "Neon" },
            { "Cylinder", V(0.1, 0.28, 0.28), V(0, 0.2, 0), V(0, 0, 90), "Gold", "Metal" },
            { "Cylinder", V(1.2, 0.19, 0.19), V(0, 0.84, 0), V(0, 0, 90), "Leather", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 0.36, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 0.55, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 0.74, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 0.93, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 1.12, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.05, 0.215, 0.215), V(0, 1.31, 0), V(0, 0, 90), "Wrap", "Fabric" },
            { "Cylinder", V(0.08, 0.25, 0.25), V(0, 1.47, 0), V(0, 0, 90), "Gold", "Metal" },
            { "Block", V(0.5, 0.22, 0.3), V(0, 1.6, 0), V(0, 0, 0), "Gold", "Metal" },
            { "Block", V(0.82, 0.12, 0.17), V(0.62, 1.64, 0), V(0, 0, 8), "Gold", "Metal" },
            { "Ball", V(0.2, 0.2, 0.2), V(1.03, 1.7, 0), V(0, 0, 0), "Gold", "Metal" },
            { "Ball", V(0.1, 0.1, 0.1), V(1.03, 1.7, 0.09), V(0, 0, 0), "Gem", "Neon" },
            { "Block", V(0.82, 0.12, 0.17), V(-0.62, 1.64, 0), V(0, 0, -8), "Gold", "Metal" },
            { "Ball", V(0.2, 0.2, 0.2), V(-1.03, 1.7, 0), V(0, 0, 0), "Gold", "Metal" },
            { "Ball", V(0.1, 0.1, 0.1), V(-1.03, 1.7, 0.09), V(0, 0, 0), "Gem", "Neon" },
            { "Cylinder", V(0.34, 0.16, 0.16), V(0, 1.6, 0), V(0, 90, 0), "Gem", "Neon", 0, "Glow" },
            { "Block", V(0.58, 0.16, 0.13), V(0, 1.78, 0), V(0, 0, 0), "Fuller", "Metal" },
            { "Block", V(0.5, 3.6, 0.08), V(0, 3.66, 0), V(0, 0, 0), "Steel", "Metal" },
            { "Block", V(0.13, 3.1, 0.1), V(0, 3.35, 0), V(0, 0, 0), "Fuller", "Metal" },
            { "Block", V(0.05, 3.6, 0.05), V(0.255, 3.66, 0), V(0, 0, 0), "Edge", "Foil" },
            { "Block", V(0.05, 3.6, 0.05), V(-0.255, 3.66, 0), V(0, 0, 0), "Edge", "Foil" },
            { "Wedge", V(0.08, 0.72, 0.25), V(-0.125, 5.82, 0), V(0, 90, 0), "Steel", "Metal" },
            { "Wedge", V(0.08, 0.72, 0.25), V(0.125, 5.82, 0), V(0, -90, 0), "Steel", "Metal" },
        },
    },
    {
        Name = "Ember Katana",
        Accent = C(255, 110, 30),
        Hover = 1.7, -- how high the sword floats above its stand
        Colors = {
            Black = C(30, 30, 36),
            Spine = C(150, 154, 165),
            Ember = C(255, 110, 30),
            Gold = C(206, 160, 70),
            Wrap = C(150, 22, 28),
            Handle = C(20, 18, 20),
        },
        -- { shape, size, position, rotation (degrees), colour, material, transparency, effect }
        Pieces = {
            { "Cylinder", V(0.12, 0.24, 0.24), V(0, 0.02, 0), V(0, 0, 90), "Black", "Metal" },
            { "Block", V(0.21, 1.72, 0.15), V(0, 0.94, 0), V(0, 0, 0), "Handle", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.22, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.22, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.46, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.46, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.7, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.7, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.94, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 0.94, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.18, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.18, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.42, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.42, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.66, 0), V(0, 0, 32), "Wrap", "Fabric" },
            { "Block", V(0.25, 0.05, 0.17), V(0, 1.66, 0), V(0, 0, -32), "Wrap", "Fabric" },
            { "Ball", V(0.1, 0.1, 0.1), V(0, 0.95, 0.07), V(0, 0, 0), "Gold", "Metal" },
            { "Cylinder", V(0.13, 0.24, 0.24), V(0, 1.8, 0), V(0, 0, 90), "Black", "Metal" },
            { "Cylinder", V(0.05, 0.82, 0.82), V(0, 1.9, 0), V(0, 0, 90), "Gold", "Metal" },
            { "Cylinder", V(0.1, 0.74, 0.74), V(0, 1.9, 0), V(0, 0, 90), "Black", "Metal" },
            { "Block", V(0.25, 0.22, 0.13), V(0, 2.05, 0), V(0, 0, 0), "Gold", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.004, 2.31, 0), V(0, 0, -1.1), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(-0.106, 2.312, 0), V(0, 0, -1.1), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.119, 2.308, 0), V(0, 0, -1.1), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.016, 2.73, 0), V(0, 0, -2.2), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(-0.094, 2.734, 0), V(0, 0, -2.2), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.131, 2.725, 0), V(0, 0, -2.2), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.036, 3.149, 0), V(0, 0, -3.3), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(-0.074, 3.156, 0), V(0, 0, -3.3), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.151, 3.143, 0), V(0, 0, -3.3), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.064, 3.568, 0), V(0, 0, -4.4), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(-0.045, 3.577, 0), V(0, 0, -4.4), "Ember", "Neon", 0, "Embers" },
            { "Block", V(0.03, 0.45, 0.076), V(0.179, 3.559, 0), V(0, 0, -4.4), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.101, 3.987, 0), V(0, 0, -5.5), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(-0.009, 3.997, 0), V(0, 0, -5.5), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.215, 3.976, 0), V(0, 0, -5.5), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.145, 4.404, 0), V(0, 0, -6.6), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(0.036, 4.417, 0), V(0, 0, -6.6), "Ember", "Neon", 0, "Glow" },
            { "Block", V(0.03, 0.45, 0.076), V(0.259, 4.391, 0), V(0, 0, -6.6), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.197, 4.821, 0), V(0, 0, -7.7), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(0.088, 4.836, 0), V(0, 0, -7.7), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.311, 4.806, 0), V(0, 0, -7.7), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.258, 5.237, 0), V(0, 0, -8.8), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(0.149, 5.254, 0), V(0, 0, -8.8), "Ember", "Neon", 0, "Embers" },
            { "Block", V(0.03, 0.45, 0.076), V(0.371, 5.219, 0), V(0, 0, -8.8), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.326, 5.651, 0), V(0, 0, -9.9), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(0.217, 5.67, 0), V(0, 0, -9.9), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.439, 5.631, 0), V(0, 0, -9.9), "Spine", "Metal" },
            { "Block", V(0.26, 0.45, 0.07), V(0.402, 6.064, 0), V(0, 0, -11), "Black", "Metal" },
            { "Block", V(0.045, 0.45, 0.078), V(0.294, 6.085, 0), V(0, 0, -11), "Ember", "Neon" },
            { "Block", V(0.03, 0.45, 0.076), V(0.515, 6.042, 0), V(0, 0, -11), "Spine", "Metal" },
            { "Wedge", V(0.07, 0.42, 0.26), V(0.482, 6.476, 0), V(90, 79, -90), "Black", "Metal" },
            { "Block", V(0.045, 0.494, 0.078), V(0.473, 6.485, 0), V(0, 0, -42.759), "Ember", "Neon" },
        },
    },
    {
        Name = "Void Greatsword",
        Accent = C(255, 70, 200),
        Hover = 1.9, -- how high the sword floats above its stand
        Colors = {
            Obsidian = C(28, 20, 42),
            Dark = C(44, 32, 60),
            Crystal = C(170, 90, 255),
            Core = C(255, 70, 200),
            Grip = C(22, 18, 30),
        },
        -- { shape, size, position, rotation (degrees), colour, material, transparency, effect }
        Pieces = {
            { "Block", V(0.34, 0.34, 0.34), V(0, -0.12, 0), V(45, 0, 45), "Crystal", "Glass", 0.25 },
            { "Ball", V(0.16, 0.16, 0.16), V(0, -0.12, 0), V(0, 0, 0), "Core", "Neon" },
            { "Cylinder", V(0.14, 0.3, 0.3), V(0, 0.16, 0), V(0, 0, 90), "Dark", "Metal" },
            { "Cylinder", V(1.6, 0.22, 0.22), V(0, 1, 0), V(0, 0, 90), "Grip", "Fabric" },
            { "Cylinder", V(0.04, 0.24, 0.24), V(0, 0.45, 0), V(0, 0, 90), "Core", "Neon" },
            { "Cylinder", V(0.04, 0.24, 0.24), V(0, 1, 0), V(0, 0, 90), "Core", "Neon" },
            { "Cylinder", V(0.04, 0.24, 0.24), V(0, 1.55, 0), V(0, 0, 90), "Core", "Neon" },
            { "Cylinder", V(0.14, 0.32, 0.32), V(0, 1.86, 0), V(0, 0, 90), "Dark", "Metal" },
            { "Block", V(0.8, 0.34, 0.34), V(0, 2.06, 0), V(0, 0, 0), "Dark", "Metal" },
            { "Block", V(0.4, 0.4, 0.36), V(0, 2.06, 0), V(0, 0, 45), "Obsidian", "Metal" },
            { "Ball", V(0.2, 0.2, 0.2), V(0, 2.06, 0.1), V(0, 0, 0), "Core", "Neon", 0, "Glow" },
            { "Block", V(1.05, 0.18, 0.24), V(0.85, 2.24, 0), V(0, 0, 22), "Dark", "Metal" },
            { "Block", V(0.9, 0.05, 0.26), V(0.85, 2.24, 0), V(0, 0, 22), "Core", "Neon" },
            { "Wedge", V(0.24, 0.5, 0.3), V(1.45, 2.6, 0), V(0, -90, 0), "Dark", "Metal" },
            { "Block", V(1.05, 0.18, 0.24), V(-0.85, 2.24, 0), V(0, 0, -22), "Dark", "Metal" },
            { "Block", V(0.9, 0.05, 0.26), V(-0.85, 2.24, 0), V(0, 0, -22), "Core", "Neon" },
            { "Wedge", V(0.24, 0.5, 0.3), V(-1.45, 2.6, 0), V(0, 90, 0), "Dark", "Metal" },
            { "Block", V(0.9, 5, 0.12), V(0, 4.74, 0), V(0, 0, 0), "Obsidian", "Metal" },
            { "Block", V(0.09, 4.5, 0.14), V(0, 4.59, 0), V(0, 0, 0), "Core", "Neon" },
            { "Block", V(0.14, 5, 0.1), V(0.48, 4.74, 0), V(0, 0, 0), "Crystal", "Glass", 0.3 },
            { "Block", V(0.14, 5, 0.1), V(-0.48, 4.74, 0), V(0, 0, 0), "Crystal", "Glass", 0.3 },
            { "Block", V(0.1, 0.1, 0.135), V(0.24, 2.84, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(-0.24, 3.46, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(0.24, 4.08, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(-0.24, 4.7, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(0.24, 5.32, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(-0.24, 5.94, 0), V(0, 0, 45), "Core", "Neon" },
            { "Block", V(0.1, 0.1, 0.135), V(0.24, 6.56, 0), V(0, 0, 45), "Core", "Neon" },
            { "Wedge", V(0.12, 1.15, 0.45), V(-0.225, 7.815, 0), V(0, 90, 0), "Obsidian", "Metal" },
            { "Wedge", V(0.12, 1.15, 0.45), V(0.225, 7.815, 0), V(0, -90, 0), "Obsidian", "Metal" },
            { "Block", V(0.14, 0.32, 0.14), V(-0.75, 2.95, 0), V(-18.882, 41.641, 27.236), "Crystal", "Glass", 0.2, "Sparkle" },
            { "Block", V(0.14, 0.32, 0.14), V(0.8, 3.05, 0), V(29.838, 35.396, -44.719), "Crystal", "Glass", 0.2 },
            { "Block", V(0.14, 0.32, 0.14), V(-0.6, 3.6, 0), V(-40.893, 20.705, 67.792), "Crystal", "Glass", 0.2 },
            { "Block", V(0.14, 0.32, 0.14), V(0.62, 3.75, 0), V(9.851, 44.136, -14.002), "Crystal", "Glass", 0.2 },
        },
    },
}

-- the stand's colours come from the sword's Accent
local STAND = {
    { "Cylinder", V(0.4, 3.6, 3.6), V(0, 0.2, 0), V(0, 0, 90), "Stone", "Slate" },
    { "Cylinder", V(0.5, 2.8, 2.8), V(0, 0.65, 0), V(0, 0, 90), "Top", "Slate" },
    { "Cylinder", V(0.08, 2.9, 2.9), V(0, 0.62, 0), V(0, 0, 90), "Accent", "Neon" },
    { "Cylinder", V(0.12, 2.2, 2.2), V(0, 0.96, 0), V(0, 0, 90), "Stone", "Marble" },
}

------------------------------------------------------------------------

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local SPIN_SOURCE = [[
local RunService = game:GetService("RunService")
local sword = script.Parent:WaitForChild("Sword")
local base = sword:GetPivot()
local t = math.random() * 10
RunService.Heartbeat:Connect(function(dt)
    t += dt
    sword:PivotTo(base * CFrame.new(0, math.sin(t * 1.4) * 0.25, 0) * CFrame.Angles(0, t * 0.7, 0))
end)
]]

local function makePart(piece, colors, origin, scale, parent)
    local shape, size, pos, rot, colorKey, material, transparency, effect = table.unpack(piece)

    local part = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
    if shape == "Cylinder" then
        part.Shape = Enum.PartType.Cylinder
    elseif shape == "Ball" then
        part.Shape = Enum.PartType.Ball
    end
    part.Size = size * scale
    part.CFrame = origin * CFrame.new(pos * scale) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
    part.Color = colors[colorKey]
    part.Material = Enum.Material[material]
    part.Transparency = transparency or 0
    part.Reflectance = material == "Metal" and 0.05 or 0
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CastShadow = material ~= "Neon" and material ~= "Glass"
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth

    if effect == "Glow" then
        local light = Instance.new("PointLight")
        light.Color = part.Color
        light.Range = 9 * scale
        light.Brightness = 1.6
        light.Parent = part
    elseif effect == "Embers" then
        local embers = Instance.new("ParticleEmitter")
        embers.Color = ColorSequence.new(part.Color, Color3.fromRGB(255, 220, 120))
        embers.LightEmission = 1
        embers.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.07 * scale),
            NumberSequenceKeypoint.new(1, 0),
        })
        embers.Transparency = NumberSequence.new(0.1, 1)
        embers.Lifetime = NumberRange.new(0.8, 1.6)
        embers.Rate = 7
        embers.Speed = NumberRange.new(0.4, 1.2)
        embers.SpreadAngle = Vector2.new(40, 40)
        embers.Acceleration = Vector3.new(0, 1.5, 0)
        embers.Parent = part
    elseif effect == "Sparkle" then
        local sparkle = Instance.new("ParticleEmitter")
        sparkle.Color = ColorSequence.new(part.Color)
        sparkle.LightEmission = 1
        sparkle.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 0.12 * scale),
            NumberSequenceKeypoint.new(1, 0),
        })
        sparkle.Lifetime = NumberRange.new(1, 2)
        sparkle.Rate = 4
        sparkle.Speed = NumberRange.new(0.2, 0.5)
        sparkle.SpreadAngle = Vector2.new(180, 180)
        sparkle.Parent = part
    end

    part.Parent = parent
    return part
end

local function build(pieces, colors, origin, scale, parent)
    for _, piece in ipairs(pieces) do
        makePart(piece, colors, origin, scale, parent)
    end
end

-- place everything on the ground in front of the camera, facing it
local camera = workspace.CurrentCamera
local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
local right = look:Cross(Vector3.yAxis)
local center = camera.CFrame.Position + look * SETTINGS.Distance

local folder = Instance.new("Folder")
folder.Name = "Lovely Swords"

local scale = SETTINGS.Scale
for i, sword in ipairs(SWORDS) do
    local spot = center + right * (i - (#SWORDS + 1) / 2) * SETTINGS.Spacing * scale
    local hit = workspace:Raycast(spot + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0))
    local ground = hit and hit.Position.Y or spot.Y - 4
    -- the blade's flat side faces the camera
    local base = CFrame.lookAt(Vector3.new(spot.X, ground, spot.Z), Vector3.new(spot.X, ground, spot.Z) + look)

    local display = Instance.new("Model")
    display.Name = sword.Name

    local swordModel = Instance.new("Model")
    swordModel.Name = "Sword"
    local swordOrigin = base * CFrame.new(0, SETTINGS.Stand and (1.02 + sword.Hover) * scale or 0.3 * scale, 0)
    build(sword.Pieces, sword.Colors, swordOrigin, scale, swordModel)
    -- pivot on the blade's centre line so it spins in place
    swordModel.WorldPivot = swordOrigin
    swordModel.Parent = display

    if SETTINGS.Stand then
        local standModel = Instance.new("Model")
        standModel.Name = "Stand"
        local standColors = {
            Stone = C(52, 50, 58),
            Top = C(70, 68, 78),
            Accent = sword.Accent,
        }
        build(STAND, standColors, base, scale, standModel)
        standModel.Parent = display
    end

    if SETTINGS.Animate then
        local spin = Instance.new("Script")
        spin.Name = "Spin"
        spin.Source = SPIN_SOURCE
        spin.Parent = display
    end

    display.Parent = folder
end

folder.Parent = workspace
Selection:Set({ folder })
pcall(function()
    ChangeHistoryService:SetWaypoint("Lovely Swords")
end)
print("Lovely Swords: built " .. #SWORDS .. " swords in workspace > Lovely Swords")
