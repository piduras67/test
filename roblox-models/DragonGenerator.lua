--[[
	DRAGON GENERATOR - paste this whole script into Roblox Studio's Command Bar and press Enter.

	Creates:
	  Workspace.Dragon                                  the rigged dragon (Motor6D skeleton, VFX, lights, sounds, seat)
	  ReplicatedStorage.DragonSystem                    Config + Animator ModuleScripts, Remotes, Assets
	  ServerScriptService.DragonServer                  mounting, fire breath, roar, damage
	  StarterPlayer.StarterPlayerScripts.DragonController   controls, camera, animation and effects

	Running it again removes the previous dragon and everything it made, then builds a fresh one.
]]

local SETTINGS = {
	Scale = 1,            -- 1.5 = bigger dragon (speeds, camera and effects scale with it)
	ModelName = "Dragon",
	AutoMount = true,     -- put the player on the dragon as soon as they spawn

	-- SOUND IDS: paste real ids here, e.g. "rbxassetid://1234567890".
	-- Empty strings are fine: the sounds are created but stay silent, and everything else still works.
	-- (You can also change them later in ReplicatedStorage > DragonSystem > Config.)
	Sounds = {
		DragonRoar = "",
		DragonFireCharge = "",
		DragonFire = "",          -- loops while breathing fire
		DragonFireImpact = "",    -- loops while the fire hits something
		DragonFootstep = "",
		DragonWingFlap = "",
		DragonLand = "",
	},

	-- built-in particle textures that ship with Roblox (no uploads needed)
	Textures = {
		Fire = "rbxasset://textures/particles/fire_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
		Spark = "rbxasset://textures/particles/sparkles_main.dds",
	},
}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local PhysicsService = game:GetService("PhysicsService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local function log(message)
	print("[Dragon Generator] " .. message)
end

------------------------------------------------------------------------
-- generated script sources
------------------------------------------------------------------------

local CONFIG_SOURCE = [==[
-- Dragon configuration (generated). Edit values here; they apply the next time you press Play.
local S = __SCALE__

return {
	ModelName = "__NAME__",
	Scale = S,
	AutoMount = __AUTOMOUNT__,
	RestHeight = 10.5 * S,       -- studs from the ground to the dragon's root

	-- movement (studs per second)
	WalkSpeed = 24 * S,
	RunSpeed = 50 * S,
	BackSpeed = 12 * S,
	TurnSpeed = 1.9,             -- radians per second
	JumpPower = 55 * S,
	Gravity = 115 * S,
	FlySpeed = 62 * S,
	FlyFastSpeed = 115 * S,
	ClimbSpeed = 36 * S,
	DiveSpeed = 70 * S,
	GlideFallSpeed = 9 * S,
	FrontReach = 13 * S,         -- wall detection distance in front and behind
	BackReach = 12 * S,

	-- fire breath
	FireChargeTime = 0.75,
	FireMinTime = 1.2,
	FireMaxTime = 4,
	FireCooldown = 1,
	FireRange = 120 * S,
	FirePitch = 12,              -- degrees the stream angles down toward the ground
	FireDamagePerSecond = 35,
	FireConeDegrees = 14,

	-- roar
	RoarTime = 2.4,
	RoarCooldown = 1.5,

	-- camera
	CameraDistance = 78 * S,
	CameraMinDistance = 35 * S,
	CameraMaxDistance = 190 * S,
	CameraHeight = 14 * S,

	-- SOUND IDS: paste "rbxassetid://<number>" between the quotes. Leave "" for silence.
	Sounds = {
__SOUNDS__
	},
}
]==]

local ANIMATOR_SOURCE = [==[
-- Procedural animation and visual effects for the generated dragon.
-- Required by DragonController and run on every client, so everyone sees the same motion.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Animator = {}
Animator.__index = Animator

local TAU = math.pi * 2

local LEGS = {
	{ Name = "FL", Offset = 0, Front = true },
	{ Name = "FR", Offset = 0.5, Front = true },
	{ Name = "BL", Offset = 0.5, Front = false },
	{ Name = "BR", Offset = 0, Front = false },
}

local FIRE_EMITTERS = { "FireFlame", "FireCore", "FireSmoke", "FireEmbers", "FireSparks" }
local IMPACT_EMITTERS = { "ImpactFlame", "ImpactSmoke", "ImpactSparks" }

local function approach(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

function Animator.new(model, config, assets)
	local self = setmetatable({}, Animator)
	self.Model = model
	self.Config = config
	self.Assets = assets
	self.Scale = config.Scale or 1
	self.Root = model:FindFirstChild("Root")
	self.Seat = model:FindFirstChild("DragonSeat")

	self.Joints = {}
	self.Sounds = {}
	self.Trails = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			self.Joints[d.Name] = d
		elseif d:IsA("Sound") then
			self.Sounds[d.Name] = d
		elseif d:IsA("Trail") then
			table.insert(self.Trails, d)
		end
	end
	for name, id in pairs(config.Sounds or {}) do
		local sound = self.Sounds[name]
		if sound and type(id) == "string" and id ~= "" then
			sound.SoundId = id
		end
	end

	local function find(name)
		return model:FindFirstChild(name, true)
	end
	self.Mouth = find("Mouth")
	self.Beam = find("FireBeam")
	self.Impact = find("FireImpact")
	self.ImpactLight = find("ImpactLight")
	self.MouthGlow = find("MouthGlow")
	self.MouthLight = find("MouthLight")
	self.Emitters = {}
	for _, name in ipairs({ "FireFlame", "FireCore", "FireSmoke", "FireEmbers", "FireSparks", "ChargeSuck", "ChargeGlow",
		"ImpactFlame", "ImpactSmoke", "ImpactSparks", "RoarBlast", "LandDust" }) do
		self.Emitters[name] = find(name)
	end
	self.Eyes = {}
	for _, name in ipairs({ "EyeL", "EyeR" }) do
		local eye = find(name)
		if eye then
			table.insert(self.Eyes, { Part = eye, Light = eye:FindFirstChildOfClass("PointLight"), Color = eye.Color })
		end
	end
	self.FootDust = {}
	for _, leg in ipairs(LEGS) do
		local foot = model:FindFirstChild(leg.Name .. "_Foot")
		self.FootDust[leg.Name] = foot and foot:FindFirstChild("FootDust", true)
	end

	self.Params = RaycastParams.new()
	self.Params.FilterType = Enum.RaycastFilterType.Exclude
	self.FireParams = RaycastParams.new()
	self.FireParams.FilterType = Enum.RaycastFilterType.Exclude
	self:RefreshFilter()

	local look = self.Root.CFrame.LookVector
	self.Time = 0
	self.LastPos = self.Root.Position
	self.Vel = Vector3.zero
	self.LastYaw = math.atan2(-look.X, -look.Z)
	self.YawRate = 0
	self.Air = 0
	self.Move = 0
	self.Run = 0
	self.Gait = 0
	self.Flap = 0
	self.FlapAmp = 0.35
	self.Charge = 0
	self.Fire = 0
	self.Roar = 0
	self.RoarRear = 0
	self.RoarOut = 0
	self.Action = ""
	self.ActionTime = 0
	self.Shake = 0
	self.FovKick = 0
	self.WasAirborne = false
	self.FallSpeed = 0
	self.LegPhase = {}
	self.FilterTimer = 0
	self.ImpactHit = false
	return self
end

function Animator:RefreshFilter()
	local list = { self.Model }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	self.Params.FilterDescendantsInstances = list
	-- fire can hit other players, just not the rider
	local fireList = { self.Model }
	local occupant = self.Seat and self.Seat.Occupant
	if occupant and occupant.Parent then
		table.insert(fireList, occupant.Parent)
	end
	self.FireParams.FilterDescendantsInstances = fireList
end

function Animator:Set(name, cf)
	local joint = self.Joints[name]
	if joint then
		joint.Transform = cf
	end
end

function Animator:SetEmitter(name, on)
	local emitter = self.Emitters[name]
	if emitter and emitter.Enabled ~= on then
		emitter.Enabled = on
	end
end

function Animator:Emit(name, count)
	local emitter = self.Emitters[name]
	if emitter then
		emitter:Emit(count)
	end
end

function Animator:Play(name, speed)
	local sound = self.Sounds[name]
	if sound and sound.SoundId ~= "" then
		if speed then
			sound.PlaybackSpeed = speed
		end
		sound.TimePosition = 0
		sound:Play()
	end
end

function Animator:Stop(name)
	local sound = self.Sounds[name]
	if sound and sound.IsPlaying then
		sound:Stop()
	end
end

function Animator:GroundHeight(pos)
	local result = Workspace:Raycast(pos + Vector3.new(0, 2 * self.Scale, 0), Vector3.new(0, -600, 0), self.Params)
	if result then
		return pos.Y - result.Position.Y
	end
	return math.huge
end

-- a flat ring of dust that spreads across the ground
function Animator:Ring(position, size)
	local template = self.Assets and self.Assets:FindFirstChild("DustRing")
	if not template then
		return
	end
	local ring = template:Clone()
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Size = Vector3.new(0.3, size * 0.2, size * 0.2)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.9)
end

function Animator:Footstep(legName)
	local dust = self.FootDust[legName]
	if dust then
		dust:Emit(math.floor(3 + self.Run * 8))
	end
	self:Play("DragonFootstep", 0.9 + math.random() * 0.2)
	self.Shake = math.max(self.Shake, 0.04 + 0.1 * self.Run)
end

function Animator:Land(speed)
	if speed < 14 * self.Scale then
		return
	end
	local power = math.clamp(speed / (70 * self.Scale), 0.2, 1)
	self:Emit("LandDust", math.floor(20 + 50 * power))
	self:Play("DragonLand")
	self:Ring(self.Root.Position - Vector3.new(0, self.Config.RestHeight - 0.3, 0), 55 * power * self.Scale)
	self.Shake = math.max(self.Shake, 0.15 + 0.6 * power)
end

function Animator:WingBeat(height)
	self:Play("DragonWingFlap", 0.9 + math.random() * 0.2)
	if height < 32 * self.Scale then
		self:Emit("LandDust", 10)
	end
	self.Shake = math.max(self.Shake, 0.06)
end

function Animator:RoarBlast()
	self:Emit("RoarBlast", 45)
	self.Shake = math.max(self.Shake, 0.9)
	self.FovKick = 1
	local template = self.Assets and self.Assets:FindFirstChild("Shockwave")
	if template and self.Mouth then
		local shell = template:Clone()
		shell.CFrame = CFrame.new(self.Mouth.WorldPosition)
		shell.Size = Vector3.one * 4 * self.Scale
		shell.Parent = Workspace
		TweenService:Create(shell, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.one * 75 * self.Scale,
			Transparency = 1,
		}):Play()
		Debris:AddItem(shell, 1)
	end
end

function Animator:OnAction(new, old)
	if old == "Fire" then
		self:Stop("DragonFire")
		self:Stop("DragonFireImpact")
		self:Emit("FireSmoke", 14)
	end
	if new == "Charge" then
		self:Play("DragonFireCharge")
	elseif new == "Fire" then
		self:Play("DragonFire")
		self:Emit("FireCore", 25)
		self.FovKick = math.max(self.FovKick, 0.3)
	elseif new == "Roar" then
		self:Play("DragonRoar")
		task.delay(0.35, function()
			if self.Model.Parent and self.Action == "Roar" then
				self:RoarBlast()
			end
		end)
	end
end

function Animator:UpdateImpact(firing)
	if not (self.Mouth and self.Impact) then
		return
	end
	local origin = self.Mouth.WorldPosition
	local direction = self.Mouth.WorldCFrame.UpVector
	local range = self.Config.FireRange
	local result = Workspace:Raycast(origin, direction * range, self.FireParams)
	local point = result and result.Position or origin + direction * range
	self.Impact.CFrame = CFrame.new(point)
	local hit = firing and result ~= nil
	for _, name in ipairs(IMPACT_EMITTERS) do
		self:SetEmitter(name, hit)
	end
	if self.ImpactLight then
		self.ImpactLight.Enabled = hit
	end
	if hit and not self.ImpactHit then
		self:Play("DragonFireImpact")
		self:Emit("ImpactSparks", 25)
	elseif not hit and self.ImpactHit then
		self:Stop("DragonFireImpact")
	end
	self.ImpactHit = hit
end

function Animator:Update(dt)
	local root = self.Root
	if not root or not root.Parent then
		return
	end
	dt = math.clamp(dt, 1 / 240, 0.1)
	local S = self.Scale
	local cfg = self.Config
	self.Time += dt
	local t = self.Time

	self.FilterTimer -= dt
	if self.FilterTimer <= 0 then
		self.FilterTimer = 1
		self:RefreshFilter()
	end

	-- how the dragon is moving, worked out from its position so every client agrees
	local cf = root.CFrame
	local pos = cf.Position
	local vel = (pos - self.LastPos) / dt
	self.LastPos = pos
	if vel.Magnitude > 600 then
		vel = Vector3.zero
	end
	self.Vel = self.Vel:Lerp(vel, math.min(1, dt * 8))
	local planar = Vector3.new(self.Vel.X, 0, self.Vel.Z).Magnitude
	local forward = self.Vel:Dot(cf.LookVector)

	local look = cf.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local dYaw = yaw - self.LastYaw
	if dYaw > math.pi then
		dYaw -= TAU
	elseif dYaw < -math.pi then
		dYaw += TAU
	end
	self.LastYaw = yaw
	self.YawRate = approach(self.YawRate, dYaw / dt, 6, dt)

	local height = self:GroundHeight(pos)
	local airborne = height > cfg.RestHeight + 2.5 * S
	if airborne then
		self.FallSpeed = self.Vel.Y
	end
	if self.WasAirborne and not airborne then
		self:Land(-self.FallSpeed)
	end
	self.WasAirborne = airborne
	self.Air = approach(self.Air, airborne and 1 or 0, 4, dt)
	local grounded = 1 - self.Air

	self.Move = approach(self.Move, math.clamp(planar / cfg.WalkSpeed, 0, 1) * grounded, 6, dt)
	local runTarget = math.clamp((planar - cfg.WalkSpeed) / math.max(cfg.RunSpeed - cfg.WalkSpeed, 1), 0, 1)
	self.Run = approach(self.Run, runTarget * grounded, 4, dt)
	local stride = (12 + self.Run * 10) * S
	local direction = forward < -1 and -1 or 1
	self.Gait = (self.Gait + direction * planar * dt / stride) % 1

	-- actions are set by the server as an attribute
	local action = self.Model:GetAttribute("Action") or ""
	if action ~= self.Action then
		local old = self.Action
		self.Action = action
		self.ActionTime = 0
		self:OnAction(action, old)
	end
	self.ActionTime += dt
	self.Charge = approach(self.Charge, action == "Charge" and 1 or 0, 7, dt)
	self.Fire = approach(self.Fire, action == "Fire" and 1 or 0, 9, dt)
	self.Roar = approach(self.Roar, action == "Roar" and 1 or 0, 6, dt)
	local rear, out = 0, 0
	if action == "Roar" then
		local at = self.ActionTime
		rear = math.clamp(at / 0.35, 0, 1) * (1 - math.clamp((at - 0.35) / 0.25, 0, 1))
		out = math.clamp((at - 0.3) / 0.25, 0, 1) * (1 - math.clamp((at - (cfg.RoarTime - 0.5)) / 0.5, 0, 1))
	end
	self.RoarRear = approach(self.RoarRear, rear, 12, dt)
	self.RoarOut = approach(self.RoarOut, out, 10, dt)

	local breath = math.sin(t * 1.7)
	local stepBob = math.abs(math.sin(self.Gait * TAU))

	-- body: breathing, step bob, a lean into acceleration and a little roll into turns
	local bob = (-stepBob * 0.3 * self.Move + breath * 0.1 * (1 - self.Move)) * S
	local lean = -0.05 * self.Run + 0.05 * self.Charge - 0.03 * self.Fire + 0.1 * self.RoarRear - 0.03 * self.RoarOut
	local roll = math.clamp(-self.YawRate * 0.06, -0.12, 0.12) * grounded
	self:Set("Body", CFrame.new(0, bob, 0) * CFrame.Angles(lean, math.sin(self.Gait * TAU) * 0.04 * self.Move, roll))

	-- neck and head
	local neckPitch = math.sin(t * 0.8) * 0.035 * (1 - self.Fire) - stepBob * 0.03 * self.Move - 0.08 * self.Air
		+ 0.08 * self.Charge - 0.12 * self.Fire + 0.12 * self.RoarRear + 0.16 * self.RoarOut
	local neckYaw = math.clamp(self.YawRate * 0.1, -0.1, 0.1)
		+ math.sin(t * 0.45) * 0.05 * (1 - self.Move) * (1 - self.Fire)
		+ math.sin(t * 1.6) * 0.04 * self.Fire
	for i = 1, 4 do
		self:Set("Neck" .. i, CFrame.Angles(neckPitch, neckYaw, 0))
	end
	local levelHead = -neckPitch * 4 * 0.7 + math.sin(t * 1.1 + 1) * 0.04
	local aimHead = -math.rad(cfg.FirePitch) - neckPitch * 4
	local headPitch = levelHead * (1 - self.Fire) + aimHead * self.Fire + 0.25 * self.RoarRear + 0.1 * self.RoarOut
	local headYaw = neckYaw * 0.8 + math.sin(t * 0.6) * 0.05 * (1 - self.Move) * (1 - self.Fire)
	local headRoll = math.sin(t * 31) * 0.035 * self.RoarOut
	self:Set("Head", CFrame.Angles(headPitch, headYaw, headRoll))

	local jaw = 0.05 + math.max(0, breath) * 0.03 + self.Charge * 0.2 + self.Fire * 0.95 + self.RoarRear * 0.25 + self.RoarOut
	self:Set("Jaw", CFrame.Angles(-math.min(jaw, 1.1) * 0.6, 0, 0))

	-- tail: a travelling wave that grows toward the tip and swings out of turns
	local tailAmp = (0.05 + 0.04 * self.Move + 0.03 * self.Run) * (1 - 0.6 * self.Air)
	for i = 1, 7 do
		local k = i / 7
		local sway = math.sin(t * (1.2 + self.Move) - i * 0.55) * tailAmp * (0.6 + k)
		local swish = math.clamp(-self.YawRate * 0.05, -0.08, 0.08) * k
		local pitch = -0.015 + self.Air * 0.02 + math.sin(t * 1.7 - i * 0.5) * 0.012 + self.RoarOut * 0.03
		self:Set("Tail" .. i, CFrame.Angles(pitch, sway + swish, 0))
	end

	-- legs: diagonal pairs step together; feet lift on the forward swing
	local tuck = self.Air
	for _, leg in ipairs(LEGS) do
		local p = (self.Gait + leg.Offset) % 1
		local a = p * TAU
		local swing = math.sin(a) * (0.3 + self.Run * 0.22) * self.Move
		local lift = math.max(0, math.cos(a)) * (0.5 + self.Run * 0.3) * self.Move
		local idle = math.sin(t * 0.9 + leg.Offset * 3) * 0.015 * (1 - self.Move)
		local hip = swing + idle - tuck * (leg.Front and 0.35 or 0.55) + (leg.Front and 0.08 or 0) * self.RoarOut
		local knee = (leg.Front and -lift or lift * 0.9) + tuck * (leg.Front and -0.9 or 1)
		local ankle = -(hip + knee) * 0.85 + tuck * (leg.Front and 0.5 or -0.4)
		self:Set(leg.Name .. "_Hip", CFrame.Angles(hip, 0, 0))
		self:Set(leg.Name .. "_Knee", CFrame.Angles(knee, 0, 0))
		self:Set(leg.Name .. "_Ankle", CFrame.Angles(ankle, 0, 0))
		local last = self.LegPhase[leg.Name] or p
		if self.Move > 0.25 and last < 0.25 and p >= 0.25 then
			self:Footstep(leg.Name)
		end
		self.LegPhase[leg.Name] = p
	end

	-- wings: folded on the ground, beating in the air (harder while climbing)
	local climbing = self.Vel.Y > 4 * S
	self.FlapAmp = approach(self.FlapAmp, climbing and 1 or 0.35, 3, dt)
	local lastFlap = self.Flap
	self.Flap = (self.Flap + dt * (0.9 + 0.6 * self.FlapAmp) * self.Air) % 1
	if self.Air > 0.5 and lastFlap < 0.25 and self.Flap >= 0.25 then
		self:WingBeat(height)
	end
	local flap = math.sin(self.Flap * TAU) * self.FlapAmp * self.Air
	local lag = math.sin(self.Flap * TAU - 0.9) * self.FlapAmp * self.Air
	local fold = grounded * (1 - 0.7 * self.Roar)
	for _, side in ipairs({ 1, -1 }) do
		local tag = side == 1 and "WingR" or "WingL"
		local lift = fold * 0.5 + flap * 0.7 + self.Air * 0.08 + self.Roar * 0.35 + breath * 0.02 * fold
		self:Set(tag .. "_Inner", CFrame.Angles(0, -side * fold * 0.7, side * lift))
		self:Set(tag .. "_Outer", CFrame.Angles(0, -side * fold * 1.7, side * (lag * 0.45 - fold * 0.3)))
	end
	local trails = self.Air > 0.6 and planar > 25 * S
	for _, trail in ipairs(self.Trails) do
		if trail.Enabled ~= trails then
			trail.Enabled = trails
		end
	end

	-- eyes and mouth glow while charging, breathing fire or roaring
	local intensity = math.max(self.Charge, self.Fire, self.Roar)
	for _, eye in ipairs(self.Eyes) do
		eye.Part.Color = eye.Color:Lerp(Color3.fromRGB(255, 246, 205), intensity * 0.7)
		if eye.Light then
			eye.Light.Brightness = 1.5 + intensity * 4
			eye.Light.Range = (7 + intensity * 7) * S
		end
	end
	if self.MouthGlow then
		self.MouthGlow.Transparency = 1 - 0.85 * math.max(self.Charge, self.Fire * 0.8, self.Roar * 0.4)
	end
	if self.MouthLight then
		self.MouthLight.Brightness = self.Charge * 6 + self.Fire * 5 + self.Roar * 2
	end

	-- fire breath
	local charging = action == "Charge"
	local firing = action == "Fire"
	self:SetEmitter("ChargeSuck", charging)
	self:SetEmitter("ChargeGlow", charging)
	for _, name in ipairs(FIRE_EMITTERS) do
		self:SetEmitter(name, firing)
	end
	if self.Beam then
		self.Beam.Enabled = self.Fire > 0.05
		self.Beam.Width0 = 1.5 * S * self.Fire
		self.Beam.Width1 = 8 * S * self.Fire
	end
	if self.Fire > 0.02 or self.ImpactHit then
		self:UpdateImpact(firing)
	end

	if firing then
		self.Shake = math.max(self.Shake, 0.14)
	end
	self.Shake = approach(self.Shake, 0, 4, dt)
	self.FovKick = approach(self.FovKick, 0, 2.5, dt)
end

return Animator
]==]

local SERVER_SOURCE = [==[
-- DragonServer (generated): mounting, fire breath, roar and damage.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local system = ReplicatedStorage:WaitForChild("DragonSystem")
local Config = require(system:WaitForChild("Config"))
local remote = system:WaitForChild("Remotes"):WaitForChild("DragonAction")
local dragon = Workspace:WaitForChild(Config.ModelName)
local root = dragon:WaitForChild("Root")
local seat = dragon:WaitForChild("DragonSeat")
local alignPosition = root:WaitForChild("AlignPosition")
local alignOrientation = root:WaitForChild("AlignOrientation")
local S = Config.Scale

dragon:SetAttribute("Action", "")
dragon:SetAttribute("Driver", 0)

pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered("DragonRider") then
		PhysicsService:RegisterCollisionGroup("DragonRider")
	end
	PhysicsService:CollisionGroupSetCollidable("DragonRider", "Default", false)
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
	local list = { dragon }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
end

local driver = nil
local busy = false
local fireHeld = false
local cooldownUntil = 0
local settleToken = nil

local function setAction(name)
	dragon:SetAttribute("Action", name)
end

local function setCollisionGroup(character, group)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

-- with nobody riding, the server owns the dragon and lowers it gently onto the ground
local function settle()
	local token = {}
	settleToken = token
	refreshFilter()
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude > 0.01 then
		alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, look.Unit)
	end
	task.spawn(function()
		while settleToken == token and not seat.Occupant and dragon.Parent do
			local current = alignPosition.Position
			local result = Workspace:Raycast(current + Vector3.new(0, 2 * S, 0), Vector3.new(0, -800, 0), params)
			if not result then
				break
			end
			local target = result.Position.Y + Config.RestHeight
			if math.abs(current.Y - target) < 0.05 then
				break
			end
			local y = current.Y > target and math.max(target, current.Y - 50 * S * 0.03) or target
			alignPosition.Position = Vector3.new(current.X, y, current.Z)
			task.wait(0.03)
		end
	end)
end

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local humanoid = seat.Occupant
	local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
	if player then
		settleToken = nil
		driver = player
		setCollisionGroup(humanoid.Parent, "DragonRider")
		pcall(function()
			root:SetNetworkOwner(player)
		end)
		dragon:SetAttribute("Driver", player.UserId)
	else
		if driver and driver.Character then
			setCollisionGroup(driver.Character, "Default")
		end
		driver = nil
		fireHeld = false
		-- the rider's client was steering, so the server picks up from where the dragon actually is
		alignPosition.Position = root.Position
		alignOrientation.CFrame = root.CFrame
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		dragon:SetAttribute("Driver", 0)
		settle()
	end
end)

local function mount(player)
	if seat.Occupant then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	character:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
	seat:Sit(humanoid)
end

local function dismount()
	local humanoid = seat.Occupant
	if not humanoid then
		return
	end
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	local character = humanoid.Parent
	task.defer(function()
		if character and character.Parent then
			local spot = root.CFrame * CFrame.new(13 * S, 0, 0)
			character:PivotTo(CFrame.new(spot.Position - Vector3.new(0, Config.RestHeight - 4, 0)))
		end
	end)
end

local function damageTick(dt)
	-- where the animated mouth sits while breathing fire (the server doesn't run the animation)
	local origin = root.CFrame:PointToWorldSpace(Vector3.new(0, 4, -30) * S)
	local direction = (root.CFrame * CFrame.Angles(-math.rad(Config.FirePitch), 0, 0)).LookVector
	local cone = math.cos(math.rad(Config.FireConeDegrees))
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and model ~= dragon and not (driver and model == driver.Character) then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local target = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and target then
				local offset = target.Position - origin
				local distance = offset.Magnitude
				if distance > 0 and distance < Config.FireRange and (offset.Unit:Dot(direction) > cone or distance < 10 * S) then
					humanoid:TakeDamage(Config.FireDamagePerSecond * dt)
				end
			end
		end
	end
end

local function startFire()
	if busy or os.clock() < cooldownUntil then
		return
	end
	busy = true
	fireHeld = true
	task.spawn(function()
		setAction("Charge")
		task.wait(Config.FireChargeTime)
		local elapsed = 0
		if driver then
			setAction("Fire")
			while dragon.Parent and driver and elapsed < Config.FireMaxTime and (fireHeld or elapsed < Config.FireMinTime) do
				local dt = task.wait(0.1)
				elapsed += dt
				damageTick(dt)
			end
		end
		setAction("")
		busy = false
		cooldownUntil = os.clock() + Config.FireCooldown
	end)
end

local function roar()
	if busy or os.clock() < cooldownUntil then
		return
	end
	busy = true
	setAction("Roar")
	task.delay(Config.RoarTime, function()
		setAction("")
		busy = false
		cooldownUntil = os.clock() + Config.RoarCooldown
	end)
end

remote.OnServerEvent:Connect(function(player, kind, value)
	if type(kind) ~= "string" then
		return
	end
	if kind == "Mount" then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - root.Position).Magnitude < 70 * S then
			mount(player)
		end
		return
	end
	if player ~= driver then
		return
	end
	if kind == "Dismount" then
		dismount()
	elseif kind == "Fire" then
		if value == true then
			startFire()
		else
			fireHeld = false
		end
	elseif kind == "Roar" then
		roar()
	end
end)

local function onPlayer(player)
	player.CharacterAdded:Connect(function()
		if Config.AutoMount then
			task.wait(1.2)
			mount(player)
		end
	end)
	if player.Character and Config.AutoMount then
		task.defer(mount, player)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	if player == driver then
		fireHeld = false
	end
end)

settle()
]==]

local CONTROLLER_SOURCE = [==[
-- DragonController (generated): drives the dragon you ride, runs the camera, and animates the dragon for everyone.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local system = ReplicatedStorage:WaitForChild("DragonSystem")
local Config = require(system:WaitForChild("Config"))
local Animator = require(system:WaitForChild("Animator"))
local remote = system:WaitForChild("Remotes"):WaitForChild("DragonAction")
local dragon = Workspace:WaitForChild(Config.ModelName)

-- wait until every part of the dragon has replicated
local expected = dragon:GetAttribute("PartCount") or 0
local waited = 0
while waited < 15 do
	local count = 0
	for _, d in ipairs(dragon:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	if count >= expected then
		break
	end
	waited += task.wait(0.2)
end

local root = dragon:WaitForChild("Root")
local seat = dragon:WaitForChild("DragonSeat")
local alignPosition = root:WaitForChild("AlignPosition")
local alignOrientation = root:WaitForChild("AlignOrientation")
local camera = Workspace.CurrentCamera
local S = Config.Scale

local anim = Animator.new(dragon, Config, system:FindFirstChild("Assets"))

local function approach(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

------------------------------------------------------------------------
-- on-screen hints

local gui = Instance.new("ScreenGui")
gui.Name = "DragonHints"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -18)
hint.Size = UDim2.fromOffset(760, 30)
hint.BackgroundColor3 = Color3.fromRGB(15, 10, 12)
hint.BackgroundTransparency = 0.35
hint.TextColor3 = Color3.fromRGB(255, 225, 190)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.Visible = false
hint.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = hint

------------------------------------------------------------------------
-- state

local driving = false
local controls = nil
local spaceHeld = false
local spaceTime = 0
local jumpQueued = false
local baseFov = camera.FieldOfView

local state = {
	Pos = root.Position,
	Yaw = 0,
	Speed = 0,
	YawVel = 0,
	Vy = 0,
	Pitch = 0,
	Roll = 0,
	Airborne = false,
	Flying = false,
}

local cam = {
	Yaw = 0,
	Pitch = -0.33,
	Dist = Config.CameraDistance,
	Dragging = false,
	Pos = nil,
	Focus = nil,
}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local filterTimer = 0

local function refreshFilter()
	local list = { dragon }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
end
refreshFilter()

local function groundAt(position)
	local result = Workspace:Raycast(position + Vector3.new(0, 4 * S, 0), Vector3.new(0, -800, 0), params)
	return result and result.Position.Y or nil
end

local function myHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getControls()
	local ok, result = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return module and require(module):GetControls()
	end)
	return ok and result or nil
end

local function onSpace(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		spaceHeld = true
		jumpQueued = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		spaceHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function startDriving(humanoid)
	driving = true
	local cf = root.CFrame
	local look = cf.LookVector
	state.Pos = cf.Position
	state.Yaw = math.atan2(-look.X, -look.Z)
	state.Speed, state.YawVel, state.Vy, state.Pitch, state.Roll = 0, 0, 0, 0, 0
	local ground = groundAt(state.Pos)
	state.Airborne = ground == nil or state.Pos.Y > ground + Config.RestHeight + 2 * S
	state.Flying = state.Airborne

	controls = controls or getControls()
	if controls then
		controls:Disable()
	end
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	ContextActionService:BindActionAtPriority("DragonSpace", onSpace, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	camera.CameraType = Enum.CameraType.Scriptable
	cam.Pos = camera.CFrame.Position
	cam.Focus = root.Position
	cam.Yaw = 0
end

local function stopDriving()
	driving = false
	spaceHeld = false
	cam.Dragging = false
	ContextActionService:UnbindAction("DragonSpace")
	if controls then
		controls:Enable()
	end
	local humanoid = myHumanoid()
	if humanoid then
		pcall(function()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end)
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = baseFov
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	remote:FireServer("Fire", false)
end

------------------------------------------------------------------------
-- input

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.E then
		remote:FireServer(driving and "Dismount" or "Mount")
	end
	if not driving then
		return
	end
	if key == Enum.KeyCode.F then
		remote:FireServer("Fire", true)
	elseif key == Enum.KeyCode.R then
		remote:FireServer("Roar")
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		cam.Dragging = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F and driving then
		remote:FireServer("Fire", false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		cam.Dragging = false
		if driving then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not driving then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement and cam.Dragging then
		cam.Yaw -= input.Delta.X * 0.006
		cam.Pitch = math.clamp(cam.Pitch - input.Delta.Y * 0.005, -1.25, 0.3)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		cam.Dist = math.clamp(cam.Dist * (1 - input.Position.Z * 0.12), Config.CameraMinDistance, Config.CameraMaxDistance)
	end
end)

------------------------------------------------------------------------
-- movement: the rider's client steers the dragon through its AlignPosition / AlignOrientation

local function drive(dt)
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local function down(...)
		if typing then
			return false
		end
		for _, key in ipairs({ ... }) do
			if UserInputService:IsKeyDown(key) then
				return true
			end
		end
		return false
	end
	local K = Enum.KeyCode
	local throttle = (down(K.W, K.Up) and 1 or 0) - (down(K.S, K.Down) and 1 or 0)
	local turn = (down(K.A, K.Left) and 1 or 0) - (down(K.D, K.Right) and 1 or 0)
	local running = down(K.LeftShift, K.RightShift)
	local diving = down(K.LeftControl, K.Q)
	local action = dragon:GetAttribute("Action") or ""
	local busy = action ~= ""

	-- forward speed
	local target
	if state.Airborne then
		if throttle > 0 then
			target = running and Config.FlyFastSpeed or Config.FlySpeed
		elseif throttle < 0 then
			target = Config.FlySpeed * 0.2
		else
			target = state.Speed
		end
	else
		target = throttle > 0 and (running and Config.RunSpeed or Config.WalkSpeed) or (throttle < 0 and -Config.BackSpeed or 0)
	end
	if busy then
		target *= 0.3
	end
	local accel = state.Airborne and 1.4 or (math.abs(target) < math.abs(state.Speed) and 6 or 3)
	state.Speed = approach(state.Speed, target, accel, dt)

	-- turning
	local speedFactor = math.clamp(math.abs(state.Speed) / Config.RunSpeed, 0, 1)
	local turnRate = Config.TurnSpeed * (state.Airborne and 0.8 or (1 - 0.3 * speedFactor))
	state.YawVel = approach(state.YawVel, turn * turnRate, 6, dt)
	state.Yaw += state.YawVel * dt
	local dir = Vector3.new(-math.sin(state.Yaw), 0, -math.cos(state.Yaw))

	-- horizontal move with wall sliding
	local move = dir * state.Speed * dt
	if move.Magnitude > 1e-3 then
		filterTimer -= dt
		if filterTimer <= 0 then
			filterTimer = 1
			refreshFilter()
		end
		local reach = state.Speed >= 0 and Config.FrontReach or Config.BackReach
		local origin = state.Pos + Vector3.new(0, 1 * S, 0)
		local hit = Workspace:Raycast(origin, move.Unit * (reach + move.Magnitude), params)
		if hit and hit.Normal.Y < 0.6 then
			local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
			if normal.Magnitude > 1e-3 then
				normal = normal.Unit
				local into = move:Dot(normal)
				if into < 0 then
					move -= normal * into
				end
			end
		end
	end
	state.Pos += move

	-- vertical: walk on the ground, jump, take off, glide, dive, land
	local ground = groundAt(state.Pos)
	local standY = ground and ground + Config.RestHeight
	if not state.Airborne then
		if standY and standY >= state.Pos.Y - 4 * S then
			state.Pos = Vector3.new(state.Pos.X, approach(state.Pos.Y, standY, 14, dt), state.Pos.Z)
		else
			state.Airborne = true
			state.Vy = 0
		end
		if jumpQueued and not busy then
			state.Airborne = true
			state.Vy = Config.JumpPower
			spaceTime = 0
		end
	else
		if spaceHeld then
			spaceTime += dt
		else
			spaceTime = 0
		end
		if spaceTime > 0.3 then
			state.Flying = true
		end
		if spaceHeld and state.Flying then
			state.Vy = approach(state.Vy, Config.ClimbSpeed, 3, dt)
		elseif diving then
			state.Vy = approach(state.Vy, -Config.DiveSpeed, 2, dt)
		else
			state.Vy -= Config.Gravity * dt
			if state.Flying and state.Vy < -Config.GlideFallSpeed then
				state.Vy = approach(state.Vy, -Config.GlideFallSpeed, 4, dt)
			end
		end
		state.Pos += Vector3.new(0, state.Vy * dt, 0)
		if standY and state.Pos.Y <= standY and state.Vy <= 0 then
			state.Pos = Vector3.new(state.Pos.X, standY, state.Pos.Z)
			state.Airborne = false
			state.Flying = false
			state.Vy = 0
		end
		local floor = Workspace.FallenPartsDestroyHeight + 80
		if state.Pos.Y < floor then
			state.Pos = Vector3.new(state.Pos.X, floor, state.Pos.Z)
			state.Vy = 0
		end
	end
	jumpQueued = false

	-- tilt with the slope on the ground, pitch and bank in the air
	local targetPitch, targetRoll = 0, 0
	if state.Airborne then
		targetPitch = math.clamp(state.Vy * 0.006 / S, -0.45, 0.35)
		targetRoll = math.clamp(state.YawVel * 0.35, -0.5, 0.5) * math.clamp(math.abs(state.Speed) / (30 * S), 0.3, 1)
	elseif ground then
		local front = groundAt(state.Pos + dir * 10 * S)
		local back = groundAt(state.Pos - dir * 10 * S)
		if front and back then
			targetPitch = math.clamp(math.atan((front - back) / (20 * S)), -0.4, 0.4)
		end
	end
	state.Pitch = approach(state.Pitch, targetPitch, 5, dt)
	state.Roll = approach(state.Roll, targetRoll, 4, dt)

	alignPosition.Position = state.Pos
	alignOrientation.CFrame = CFrame.Angles(0, state.Yaw, 0) * CFrame.Angles(state.Pitch, 0, state.Roll)
end

------------------------------------------------------------------------
-- camera: behind and above the dragon, right mouse drags it around, scroll zooms

local function shakeOffset(amount)
	if amount < 0.01 then
		return CFrame.identity
	end
	local t = os.clock() * 22
	return CFrame.Angles(math.noise(t, 1.3) * amount * 0.035, math.noise(t, 7.1) * amount * 0.035, math.noise(t, 4.7) * amount * 0.02)
end

local function nearbyShake()
	local distance = (camera.CFrame.Position - root.Position).Magnitude
	return anim.Shake * math.clamp(1 - distance / (220 * S), 0, 1)
end

local function cameraStep(dt)
	if driving then
		local rootCf = root.CFrame
		local look = rootCf.LookVector
		local dragonYaw = math.atan2(-look.X, -look.Z)
		if not cam.Dragging and math.abs(state.Speed) > 2 then
			cam.Yaw = approach(cam.Yaw, 0, 1.2, dt)
		end
		local focus = rootCf.Position + Vector3.new(0, Config.CameraHeight, 0)
		local rotation = CFrame.Angles(0, dragonYaw + cam.Yaw, 0) * CFrame.Angles(cam.Pitch, 0, 0)
		local desired = focus + rotation:VectorToWorldSpace(Vector3.new(0, 0, cam.Dist))
		local hit = Workspace:Raycast(focus, desired - focus, params)
		if hit then
			desired = hit.Position + hit.Normal * 2
		end
		cam.Pos = cam.Pos and cam.Pos:Lerp(desired, 1 - math.exp(-9 * dt)) or desired
		cam.Focus = cam.Focus and cam.Focus:Lerp(focus, 1 - math.exp(-14 * dt)) or focus
		camera.CFrame = CFrame.lookAt(cam.Pos, cam.Focus) * shakeOffset(anim.Shake)
		camera.Focus = CFrame.new(cam.Focus)
		camera.FieldOfView = baseFov + anim.FovKick * 12 + math.clamp(math.abs(state.Speed) / Config.FlyFastSpeed, 0, 1) * 8
	else
		local amount = nearbyShake()
		if amount > 0.01 then
			camera.CFrame = camera.CFrame * shakeOffset(amount)
		end
		if anim.FovKick > 0.01 and amount > 0.01 then
			camera.FieldOfView = baseFov + anim.FovKick * 8 * math.min(1, amount * 2)
		elseif camera.FieldOfView ~= baseFov and math.abs(camera.FieldOfView - baseFov) < 15 then
			camera.FieldOfView = baseFov
		end
	end
end

local function updateHint()
	if driving then
		hint.Text = "WASD move  |  Shift run  |  Space jump / hold to fly  |  Ctrl dive  |  F fire  |  R roar  |  Right mouse camera  |  E dismount"
		hint.Visible = true
	elseif not seat.Occupant and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		and (player.Character.HumanoidRootPart.Position - root.Position).Magnitude < 60 * S then
		hint.Text = "Press E to ride the dragon"
		hint.Visible = true
	else
		hint.Visible = false
	end
end

RunService:BindToRenderStep("DragonUpdate", Enum.RenderPriority.Input.Value + 1, function(dt)
	dt = math.clamp(dt, 1 / 240, 0.1)
	local humanoid = myHumanoid()
	local riding = humanoid ~= nil and seat.Occupant == humanoid
	if riding ~= driving then
		if riding then
			startDriving(humanoid)
		else
			stopDriving()
		end
	end
	if driving then
		drive(dt)
	end
	anim:Update(dt)
	updateHint()
end)

RunService:BindToRenderStep("DragonCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	cameraStep(math.clamp(dt, 1 / 240, 0.1))
end)
]==]

------------------------------------------------------------------------
-- generator
------------------------------------------------------------------------

local ok, err = pcall(function()
	local S = SETTINGS.Scale
	local REST = 10.5 * S
	local v3 = Vector3.new
	local MAT = Enum.Material
	local TEX = SETTINGS.Textures

	local C = {
		Body = Color3.fromRGB(122, 22, 32),
		BodyDark = Color3.fromRGB(74, 12, 22),
		Scale = Color3.fromRGB(100, 17, 27),
		Belly = Color3.fromRGB(214, 142, 72),
		BellyDark = Color3.fromRGB(176, 104, 52),
		Horn = Color3.fromRGB(44, 34, 36),
		HornTip = Color3.fromRGB(214, 200, 172),
		Spike = Color3.fromRGB(34, 24, 28),
		Membrane = Color3.fromRGB(96, 16, 28),
		Eye = Color3.fromRGB(255, 186, 40),
		Mouth = Color3.fromRGB(110, 18, 22),
		Tongue = Color3.fromRGB(176, 46, 56),
		Tooth = Color3.fromRGB(242, 234, 212),
		Claw = Color3.fromRGB(28, 24, 26),
		Leather = Color3.fromRGB(78, 46, 28),
		Gold = Color3.fromRGB(212, 168, 70),
		Fire = Color3.fromRGB(255, 140, 40),
	}

	--------------------------------------------------------------------
	log("Removing previous version...")
	local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	if not starterScripts then
		starterScripts = Instance.new("StarterPlayerScripts")
		starterScripts.Parent = StarterPlayer
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:GetAttribute("DragonGenerator") then
			child:Destroy()
		end
	end
	for _, pair in ipairs({ { ReplicatedStorage, "DragonSystem" }, { ServerScriptService, "DragonServer" }, { starterScripts, "DragonController" } }) do
		local old = pair[1]:FindFirstChild(pair[2])
		while old do
			old:Destroy()
			old = pair[1]:FindFirstChild(pair[2])
		end
	end
	local modelName = SETTINGS.ModelName
	if Workspace:FindFirstChild(modelName) then
		modelName = modelName .. "_Generated"
		warn("[Dragon Generator] Workspace already has your own '" .. SETTINGS.ModelName .. "', so this one is named '" .. modelName .. "'.")
	end

	--------------------------------------------------------------------
	-- placement: on the ground in front of the camera, facing away from it
	local camera = Workspace.CurrentCamera
	local camCf = camera and camera.CFrame or CFrame.new(0, 40, 80)
	local look = camCf.LookVector * v3(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = v3(0, 0, -1)
	end
	look = look.Unit
	local spot = camCf.Position + look * 75 * S
	local groundHit = Workspace:Raycast(spot + v3(0, 250, 0), v3(0, -1500, 0))
	local groundY = groundHit and groundHit.Position.Y or 0
	local origin = v3(spot.X, groundY + REST, spot.Z)
	local BASE = CFrame.lookAt(origin, origin + look)

	--------------------------------------------------------------------
	-- building helpers (positions are in dragon units: x right, y up, -z forward)

	local model = Instance.new("Model")
	model.Name = modelName
	model:SetAttribute("DragonGenerator", true)

	local function at(pos)
		return BASE * CFrame.new(pos * S)
	end

	local function world(pos)
		return BASE:PointToWorldSpace(pos * S)
	end

	local function newPart(name, size, cf, color, material, class)
		local p = Instance.new(class or "Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or MAT.SmoothPlastic
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- ellipsoid: a part with a sphere mesh that stretches to the part's size
	local function blob(name, size, cf, color, material)
		local p = newPart(name, size * S, cf, color, material)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	local function weld(part, bone)
		local w = Instance.new("Weld")
		w.Part0 = bone
		w.Part1 = part
		w.C0 = bone.CFrame:Inverse() * part.CFrame
		w.Parent = part
		return part
	end

	-- Motor6D with an axis-aligned pivot, so the animator's rotations read naturally
	local function joint(name, parent, child, pivot)
		local cf = at(pivot)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parent
		m.Part1 = child
		m.C0 = parent.CFrame:Inverse() * cf
		m.C1 = child.CFrame:Inverse() * cf
		m.Parent = child
		return m
	end

	local function segCF(a, b)
		local dir = (b - a).Unit
		local up = math.abs(dir.Y) > 0.92 and Vector3.zAxis or Vector3.yAxis
		return BASE * CFrame.lookAt((a + b) * 0.5 * S, b * S, up)
	end

	local function segment(name, a, b, w, h, color, material, stretch)
		local length = (b - a).Magnitude * (stretch or 1.3)
		return blob(name, v3(w, h, length), segCF(a, b), color, material)
	end

	-- a back spike: vertical front edge, sloping down toward the tail
	local function spike(bone, pos, height, length, color)
		local cf = at(pos + v3(0, height / 2, 0)) * CFrame.Angles(0, math.pi, 0)
		return weld(newPart("Spike", v3(0.35, height, length) * S, cf, color or C.Spike, MAT.SmoothPlastic, "WedgePart"), bone)
	end

	local function tooth(bone, pos, height, down)
		local cf = at(pos) * (down and CFrame.Angles(0, 0, math.pi) or CFrame.identity)
		return weld(newPart("Tooth", v3(0.22, height, 0.42) * S, cf, C.Tooth, MAT.SmoothPlastic, "WedgePart"), bone)
	end

	-- any triangle from two wedges (wing membranes, tail blade)
	local function triangle(bone, a, b, c, color, thickness, name)
		a, b, c = world(a), world(b), world(c)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local t = (thickness or 0.2) * S
		local w1 = newPart(name or "Membrane", v3(t, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back), color, MAT.SmoothPlastic, "WedgePart")
		local w2 = newPart(name or "Membrane", v3(t, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back), color, MAT.SmoothPlastic, "WedgePart")
		weld(w1, bone)
		weld(w2, bone)
	end

	local function chain(bone, points, widths, colors, name)
		for i = 1, #points - 1 do
			weld(segment(name, points[i], points[i + 1], widths[i], widths[i], colors[i] or colors[#colors], nil, 1.6), bone)
		end
	end

	-- property sets that ignore anything an older Studio build doesn't know about
	local function make(class, name, parent, props)
		local obj = Instance.new(class)
		obj.Name = name
		for key, value in pairs(props) do
			local okSet, problem = pcall(function()
				obj[key] = value
			end)
			if not okSet then
				warn("[Dragon Generator] skipped " .. class .. "." .. key .. ": " .. tostring(problem))
			end
		end
		obj.Parent = parent
		return obj
	end

	local function NS(...)
		local args = { ... }
		local points = {}
		for i = 1, #args, 2 do
			table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1]))
		end
		return NumberSequence.new(points)
	end

	local function CS(...)
		local args = { ... }
		local points = {}
		for i = 1, #args, 2 do
			table.insert(points, ColorSequenceKeypoint.new(args[i], args[i + 1]))
		end
		return ColorSequence.new(points)
	end

	local function attachment(name, part, cf)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = part.CFrame:Inverse() * cf
		a.Parent = part
		return a
	end

	--------------------------------------------------------------------
	log("Creating model...")

	local root = newPart("Root", v3(6, 6, 12) * S, BASE, Color3.new(1, 1, 1))
	root.Transparency = 1
	root.Massless = false
	model.PrimaryPart = root

	local body = blob("Body", v3(10.5, 9.5, 13), at(v3(0, 0.8, -4)), C.Body)
	joint("Body", root, body, v3(0, 0, 0))
	weld(blob("Belly", v3(9.5, 8.5, 12), at(v3(0, 0.2, 5)), C.Body), body)
	weld(blob("Hips", v3(9, 8, 7.5), at(v3(0, 0.6, 9.5)), C.Body), body)
	weld(blob("BellyPlate", v3(7.5, 2.6, 19), at(v3(0, -3.5, 0.5)), C.Belly), body)
	for i = 0, 6 do
		weld(blob("BellyRidge", v3(7.2, 1, 1.1), at(v3(0, -4.25, -7.5 + i * 2.6)), C.BellyDark), body)
	end
	-- rows of darker scales along the flanks
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 4 do
			local z = -8 + i * 3.6
			weld(blob("Scale", v3(0.6, 2.2, 3.2), at(v3(side * (5.0 - i * 0.08), 1.8, z)) * CFrame.Angles(0, 0, side * 0.25), C.Scale), body)
			weld(blob("Scale", v3(0.6, 1.8, 2.8), at(v3(side * (4.8 - i * 0.08), -1.2, z + 1.6)) * CFrame.Angles(0, 0, -side * 0.2), C.Scale), body)
		end
		weld(blob("Shoulder", v3(3, 2.6, 3.6), at(v3(side * 3.6, 3.6, -4.6)), C.Body), body)
	end
	-- back spikes, leaving room for the saddle
	for _, s in ipairs({ { -9.6, 3.0, 1.6 }, { 0.5, 3.8, 2.4 }, { 3.5, 3.9, 2.6 }, { 6.5, 3.9, 2.4 }, { 9.5, 4.2, 2.1 }, { 12, 3.2, 1.8 } }) do
		spike(body, v3(0, s[2], s[1]), s[3], s[3] * 1.15)
	end

	-- saddle
	weld(blob("Saddle", v3(3.8, 1.0, 4.4), at(v3(0, 5.5, -4)), C.Leather, MAT.Fabric), body)
	weld(blob("SaddleTrim", v3(4.0, 0.45, 4.6), at(v3(0, 5.15, -4)), C.Gold, MAT.Metal), body)
	weld(blob("SaddleStrap", v3(10.9, 9.9, 0.9), at(v3(0, 0.8, -4)), C.Leather, MAT.Fabric), body)
	weld(segment("SaddleHorn", v3(0, 5.8, -5.9), v3(0, 6.9, -6.3), 0.5, 0.5, C.Gold, MAT.Metal), body)
	local seat = newPart("DragonSeat", v3(2, 0.4, 2) * S, at(v3(0, 6.0, -4)), C.Leather, MAT.Fabric, "Seat")
	seat.Transparency = 1
	weld(seat, body)

	--------------------------------------------------------------------
	log("Creating neck and head...")

	local NECK = { v3(0, 3.2, -9.5), v3(0, 5.8, -12.3), v3(0, 8.4, -14.6), v3(0, 10.6, -17), v3(0, 12, -19.6) }
	local NECK_W = { 5.2, 4.6, 4.0, 3.6 }
	local previous = body
	for i = 1, 4 do
		local a, b = NECK[i], NECK[i + 1]
		local w = NECK_W[i]
		local seg = segment("Neck" .. i, a, b, w, w * 1.05, C.Body, nil, 1.7)
		joint("Neck" .. i, previous, seg, a)
		weld(blob("ThroatPlate", v3(w * 0.72, w * 0.45, (b - a).Magnitude * 1.7), segCF(a, b) * CFrame.new(0, -w * 0.33 * S, 0), C.Belly), seg)
		spike(seg, (a + b) / 2 + v3(0, w * 0.42, 0.3), 1.7 - i * 0.15, 2)
		previous = seg
	end

	local H = NECK[5]
	local function hp(x, y, z)
		return H + v3(x, y, z)
	end

	local head = blob("Head", v3(5.2, 4.4, 6.2), at(hp(0, 0.6, -1.8)), C.Body)
	joint("Head", previous, head, H)
	weld(blob("Snout", v3(3.8, 2.8, 6.4), at(hp(0, -0.2, -6)), C.Body), head)
	weld(blob("SnoutRidge", v3(2.6, 1.2, 5), at(hp(0, 1.0, -5.4)), C.BodyDark), head)
	weld(blob("NoseTip", v3(3.0, 2.2, 1.6), at(hp(0, -0.1, -8.9)), C.Body), head)
	weld(blob("Palate", v3(3.0, 0.4, 6.0), at(hp(0, -1.5, -5.4)), C.Mouth), head)
	weld(blob("HeadCrest", v3(2.2, 1.6, 4.4), at(hp(0, 2.4, -0.6)), C.BodyDark), head)
	spike(head, hp(0, 2.9, 0.4), 1.1, 1.4)
	for _, side in ipairs({ -1, 1 }) do
		local tag = side < 0 and "L" or "R"
		weld(blob("Nostril", v3(0.55, 0.45, 0.6), at(hp(side * 0.75, 0.75, -9.25)), C.Spike), head)
		weld(blob("Brow", v3(1.6, 0.9, 3.0), at(hp(side * 1.9, 1.95, -3.0)) * CFrame.Angles(0, side * 0.25, side * -0.2), C.BodyDark), head)
		weld(blob("Cheek", v3(1.2, 2.2, 3), at(hp(side * 2.3, -0.3, -1.2)), C.BodyDark), head)

		local eye = blob("Eye" .. tag, v3(0.8, 0.75, 1.3), at(hp(side * 2.15, 1.2, -3.4)), C.Eye, MAT.Neon)
		weld(eye, head)
		make("PointLight", "EyeLight", eye, { Color = C.Eye, Range = 7 * S, Brightness = 1.5, Shadows = false })
		weld(newPart("Pupil", v3(0.12, 0.6, 0.18) * S, at(hp(side * 2.55, 1.2, -3.4)), Color3.new(0, 0, 0)), head)

		-- big swept horns and a smaller pair beneath them
		local o = hp(side * 1.8, 2.0, 0.6)
		chain(head, { o, o + v3(side * 0.5, 1.2, 2.0), o + v3(side * 0.9, 1.9, 4.2), o + v3(side * 1.0, 1.5, 6.3), o + v3(side * 1.0, 0.6, 7.8) },
			{ 1.3, 1.0, 0.75, 0.42 }, { C.Horn, C.Horn, C.HornTip, C.HornTip }, "Horn")
		local o2 = hp(side * 2.3, 0.6, 0.6)
		chain(head, { o2, o2 + v3(side * 0.9, 0.3, 1.6), o2 + v3(side * 1.3, 0, 3.0) }, { 0.7, 0.42 }, { C.Horn, C.HornTip }, "Horn")
		-- frill spikes along the jaw line
		for k = 0, 2 do
			local s0 = hp(side * 2.2, -0.9 - k * 0.45, -1.6 + k * 0.9)
			weld(segment("Frill", s0, s0 + v3(side * 0.9, -0.2, 1.7 - k * 0.3), 0.45, 0.45, C.Horn, nil, 1.2), head)
		end
		-- upper teeth with a fang near the front
		for i = 0, 5 do
			local h = i == 4 and 1.25 or 0.8
			tooth(head, hp(side * (1.75 - i * 0.06), -1.5 - h / 2, -3.6 - i * 0.95), h, true)
		end
		tooth(head, hp(side * 0.55, -1.25 - 0.35, -9.35), 0.7, true)
	end

	-- the jaw hinges just under the skull
	local jaw = blob("Jaw", v3(3.4, 1.6, 7.4), at(hp(0, -1.9, -4.8)), C.Body)
	joint("Jaw", head, jaw, hp(0, -1.0, -0.8))
	weld(blob("Chin", v3(2.4, 1.4, 1.4), at(hp(0, -1.8, -8.4)), C.Body), jaw)
	weld(blob("JawPlate", v3(2.6, 0.7, 6.6), at(hp(0, -2.5, -4.6)), C.Belly), jaw)
	weld(blob("MouthFloor", v3(2.8, 0.4, 6.4), at(hp(0, -1.15, -4.6)), C.Mouth), jaw)
	weld(blob("Tongue", v3(1.6, 0.5, 5), at(hp(0, -1.0, -4.3)), C.Tongue), jaw)
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 4 do
			tooth(jaw, hp(side * 1.4, -1.1 + 0.35, -4.4 - i * 0.95), 0.7, false)
		end
	end

	-- mouth: the fire comes out of an attachment whose +Y points forward
	local mouthCf = at(hp(0, -1.7, -9.8)) * CFrame.Angles(-math.pi / 2, 0, 0)
	local mouth = attachment("Mouth", head, mouthCf)
	local mouthGlow = blob("MouthGlow", v3(1.6, 1.2, 2.4), at(hp(0, -1.6, -8)), C.Fire, MAT.Neon)
	mouthGlow.Transparency = 1
	weld(mouthGlow, head)
	make("PointLight", "MouthLight", mouthGlow, { Color = C.Fire, Range = 16 * S, Brightness = 0, Shadows = false })
	local chargeCore = newPart("ChargeCore", v3(6, 6, 6) * S, at(hp(0, -1.7, -10)), C.Fire)
	chargeCore.Shape = Enum.PartType.Ball
	chargeCore.Transparency = 1
	weld(chargeCore, head)

	--------------------------------------------------------------------
	log("Creating legs...")

	local function makeLeg(tag, side, hip, knee, ankle, w1, w2, hind)
		local upper = segment(tag .. "_Upper", hip, knee, w1, w1 * 1.1, C.Body, nil, 1.35)
		joint(tag .. "_Hip", body, upper, hip)
		if hind then
			weld(blob(tag .. "_Thigh", v3(4.0, 6.0, 5.4), at(hip + v3(side * 0.3, -1.6, 0.2)), C.Body), upper)
		else
			weld(blob(tag .. "_ShoulderMuscle", v3(3.4, 4.4, 4.0), at(hip + v3(side * 0.2, -1.2, 0)), C.Body), upper)
		end
		local lower = segment(tag .. "_Lower", knee, ankle, w2, w2 * 1.1, C.Body, nil, 1.3)
		joint(tag .. "_Knee", upper, lower, knee)
		weld(blob(tag .. "_KneePlate", v3(1.4, 1.6, 1.4), at(knee + v3(side * 0.6, 0, hind and -0.6 or 0.5)), C.BodyDark), lower)
		local foot = blob(tag .. "_Foot", v3(2.8, 1.2, 3.6), at(ankle + v3(0, -0.35, -1.0)), C.BodyDark)
		joint(tag .. "_Ankle", lower, foot, ankle)
		for i = -1, 1 do
			local claw = newPart("Claw", v3(0.42, 0.6, 1.4) * S, at(ankle + v3(i * 0.8, -0.65, -3.25)) * CFrame.Angles(-0.2, i * 0.15, 0), C.Claw, MAT.SmoothPlastic, "WedgePart")
			weld(claw, foot)
		end
		weld(newPart("Claw", v3(0.35, 0.5, 0.9) * S, at(ankle + v3(0, -0.7, 1.0)) * CFrame.Angles(0, math.pi, 0), C.Claw, MAT.SmoothPlastic, "WedgePart"), foot)
		local dust = attachment("Dust", foot, at(ankle + v3(0, -0.9, -1.0)))
		return dust
	end

	local dustPoints = {}
	for _, side in ipairs({ -1, 1 }) do
		local f = side < 0 and "FL" or "FR"
		local b = side < 0 and "BL" or "BR"
		dustPoints[f] = makeLeg(f, side, v3(side * 4.3, -1.0, -6.0), v3(side * 4.9, -5.6, -5.2), v3(side * 4.9, -9.55, -6.6), 3.2, 2.4, false)
		dustPoints[b] = makeLeg(b, side, v3(side * 4.4, -0.5, 8.5), v3(side * 5.0, -5.2, 6.3), v3(side * 5.0, -9.55, 9.3), 3.6, 2.6, true)
	end

	--------------------------------------------------------------------
	log("Creating wings...")

	local wingTrails = {}
	for _, side in ipairs({ -1, 1 }) do
		local tag = side < 0 and "WingL" or "WingR"
		local sh = v3(side * 3.6, 4.0, -4.6)
		local el = v3(side * 12, 7.5, -2.5)
		local wr = v3(side * 21, 8.5, 1.5)
		local f1 = v3(side * 29, 5.5, 6)
		local f2 = v3(side * 26.5, 2.8, 11.5)
		local f3 = v3(side * 20, 2.2, 14)
		local f4 = v3(side * 11.5, 2.8, 12.5)
		local trailing = v3(side * 4.2, 3.2, 8.5)

		local inner = segment(tag .. "_Inner", sh, el, 1.6, 1.4, C.Body, nil, 1.15)
		joint(tag .. "_Inner", body, inner, sh)
		local outer = segment(tag .. "_Outer", el, wr, 1.2, 1.05, C.Body, nil, 1.12)
		joint(tag .. "_Outer", inner, outer, el)
		weld(blob(tag .. "_Elbow", v3(1.7, 1.7, 1.7), at(el), C.BodyDark), outer)
		weld(blob(tag .. "_Wrist", v3(1.3, 1.3, 1.3), at(wr), C.BodyDark), outer)

		weld(segment("WingFinger", el, f4, 0.55, 0.5, C.BodyDark, nil, 1.05), inner)
		local tip = segment("WingFinger", wr, f1, 0.75, 0.6, C.BodyDark, nil, 1.05)
		weld(tip, outer)
		weld(segment("WingFinger", wr, f2, 0.65, 0.55, C.BodyDark, nil, 1.05), outer)
		weld(segment("WingFinger", wr, f3, 0.6, 0.5, C.BodyDark, nil, 1.05), outer)
		weld(segment("WingClaw", wr, wr + v3(side * 0.5, 1.4, -1.6), 0.45, 0.45, C.Claw, nil, 1.1), outer)

		triangle(inner, sh, el, trailing, C.Membrane, 0.2)
		triangle(inner, el, f4, trailing, C.Membrane, 0.2)
		triangle(outer, el, wr, f3, C.Membrane, 0.2)
		triangle(outer, el, f3, f4, C.Membrane, 0.2)
		triangle(outer, wr, f1, f2, C.Membrane, 0.2)
		triangle(outer, wr, f2, f3, C.Membrane, 0.2)

		-- wingtip vapour trails, switched on during fast flight
		local a0 = attachment("TrailTop", tip, at(f1 + v3(0, 0.3, 0)))
		local a1 = attachment("TrailBottom", tip, at(f1 + v3(0, -0.3, 1.2)))
		local trail = make("Trail", tag .. "Trail", tip, {
			Attachment0 = a0,
			Attachment1 = a1,
			Lifetime = 0.5,
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 200), C.Membrane),
			Transparency = NS(0, 0.55, 1, 1),
			LightEmission = 0.4,
			FaceCamera = true,
			MinLength = 0.1,
			Enabled = false,
		})
		table.insert(wingTrails, trail)
	end

	--------------------------------------------------------------------
	log("Creating tail...")

	local TAIL = { v3(0, 0.8, 11), v3(0, 0.2, 16), v3(0, -0.6, 21), v3(0, -1.6, 26), v3(0, -2.6, 31), v3(0, -3.4, 36), v3(0, -4, 40), v3(0, -4.3, 44) }
	local TAIL_W = { 6.2, 5.2, 4.3, 3.5, 2.7, 2.0, 1.4 }
	previous = body
	local tailTip
	for i = 1, 7 do
		local a, b = TAIL[i], TAIL[i + 1]
		local w = TAIL_W[i]
		local seg = segment("Tail" .. i, a, b, w, w * 0.95, C.Body, nil, 1.45)
		joint("Tail" .. i, previous, seg, a)
		weld(blob("TailPlate", v3(w * 0.7, w * 0.4, (b - a).Magnitude * 1.6), segCF(a, b) * CFrame.new(0, -w * 0.32 * S, 0), C.Belly), seg)
		spike(seg, (a + b) / 2 + v3(0, w * 0.4, 0), 1.9 - i * 0.16, 2.2 - i * 0.12)
		previous = seg
		tailTip = seg
	end
	-- spade-shaped tail blade
	local tipPoint = TAIL[8]
	triangle(tailTip, tipPoint + v3(0, 0, -1.2), tipPoint + v3(-2.3, 0, 0.6), tipPoint + v3(0, 0, 3.6), C.Spike, 0.3, "TailBlade")
	triangle(tailTip, tipPoint + v3(0, 0, -1.2), tipPoint + v3(2.3, 0, 0.6), tipPoint + v3(0, 0, 3.6), C.Spike, 0.3, "TailBlade")

	--------------------------------------------------------------------
	log("Creating controller...")

	local rootAttachment = attachment("RootAttachment", root, BASE)
	make("AlignPosition", "AlignPosition", root, {
		Attachment0 = rootAttachment,
		Mode = Enum.PositionAlignmentMode.OneAttachment,
		Position = BASE.Position,
		RigidityEnabled = true,
		ApplyAtCenterOfMass = true,
	})
	make("AlignOrientation", "AlignOrientation", root, {
		Attachment0 = rootAttachment,
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		CFrame = BASE.Rotation,
		RigidityEnabled = true,
	})

	--------------------------------------------------------------------
	log("Creating VFX...")

	-- fire breath, all from the mouth attachment (emitting along its +Y, out of the mouth)
	make("ParticleEmitter", "FireFlame", mouth, {
		Texture = TEX.Fire,
		Color = CS(0, Color3.fromRGB(255, 244, 190), 0.25, Color3.fromRGB(255, 166, 50), 0.6, Color3.fromRGB(222, 64, 22), 1, Color3.fromRGB(70, 22, 12)),
		Size = NS(0, 1.2 * S, 0.3, 5 * S, 1, 9.5 * S),
		Transparency = NS(0, 0.45, 0.12, 0.05, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.75),
		Rate = 220,
		Speed = NumberRange.new(95 * S, 120 * S),
		SpreadAngle = Vector2.new(6, 6),
		Drag = 1.6,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-220, 220),
		Acceleration = v3(0, 10 * S, 0),
		LightEmission = 1,
		LightInfluence = 0,
		ZOffset = 1,
		Enabled = false,
	})
	make("ParticleEmitter", "FireCore", mouth, {
		Texture = TEX.Fire,
		Color = CS(0, Color3.fromRGB(255, 255, 240), 0.5, Color3.fromRGB(255, 226, 120), 1, Color3.fromRGB(255, 150, 40)),
		Size = NS(0, 0.6 * S, 0.4, 2.2 * S, 1, 3 * S),
		Transparency = NS(0, 0.1, 0.6, 0.4, 1, 1),
		Lifetime = NumberRange.new(0.3, 0.4),
		Rate = 140,
		Speed = NumberRange.new(115 * S, 135 * S),
		SpreadAngle = Vector2.new(2, 2),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 1,
		LightInfluence = 0,
		ZOffset = 2,
		Enabled = false,
	})
	make("ParticleEmitter", "FireSmoke", mouth, {
		Texture = TEX.Smoke,
		Color = CS(0, Color3.fromRGB(70, 56, 50), 1, Color3.fromRGB(28, 26, 26)),
		Size = NS(0, 3 * S, 1, 15 * S),
		Transparency = NS(0, 1, 0.2, 0.55, 1, 1),
		Lifetime = NumberRange.new(1.6, 2.4),
		Rate = 30,
		Speed = NumberRange.new(48 * S, 68 * S),
		SpreadAngle = Vector2.new(12, 12),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Acceleration = v3(0, 7 * S, 0),
		LightInfluence = 0.6,
		Enabled = false,
	})
	make("ParticleEmitter", "FireEmbers", mouth, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 20)),
		Size = NS(0, 0.3 * S, 1, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 60,
		Speed = NumberRange.new(60 * S, 100 * S),
		SpreadAngle = Vector2.new(18, 18),
		Drag = 1,
		Acceleration = v3(0, -14 * S, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})
	make("ParticleEmitter", "FireSparks", mouth, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)),
		Size = NS(0, 0.18 * S, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.5),
		Rate = 70,
		Speed = NumberRange.new(110 * S, 145 * S),
		SpreadAngle = Vector2.new(10, 10),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})
	make("ParticleEmitter", "ChargeGlow", mouth, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), C.Fire),
		Size = NS(0, 2.5 * S, 1, 0),
		Transparency = NS(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.25, 0.35),
		Rate = 40,
		Speed = NumberRange.new(0, 1),
		LightEmission = 1,
		LightInfluence = 0,
		ZOffset = 1,
		Enabled = false,
	})
	-- charge: sparks drawn inward from a sphere around the mouth
	make("ParticleEmitter", "ChargeSuck", chargeCore, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), C.Fire),
		Size = NS(0, 0.45 * S, 1, 0),
		Lifetime = NumberRange.new(0.35, 0.45),
		Rate = 90,
		Speed = NumberRange.new(9 * S, 13 * S),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})
	make("ParticleEmitter", "RoarBlast", mouth, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 190), Color3.fromRGB(255, 160, 110)),
		Size = NS(0, 1 * S, 1, 7 * S),
		Transparency = NS(0, 0.55, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.8),
		Rate = 0,
		Speed = NumberRange.new(35 * S, 55 * S),
		SpreadAngle = Vector2.new(28, 28),
		Drag = 3,
		LightEmission = 0.6,
		Enabled = false,
	})

	-- the far end of the fire: moved by each client to wherever the stream lands
	local impact = newPart("FireImpact", v3(1, 1, 1) * S, at(v3(0, -REST, -60)), C.Fire)
	impact.Anchored = true
	impact.Transparency = 1
	local impactPoint = attachment("ImpactPoint", impact, impact.CFrame)
	make("ParticleEmitter", "ImpactFlame", impactPoint, {
		Texture = TEX.Fire,
		Color = CS(0, Color3.fromRGB(255, 230, 160), 0.4, Color3.fromRGB(255, 120, 30), 1, Color3.fromRGB(90, 30, 10)),
		Size = NS(0, 3 * S, 0.5, 7 * S, 1, 2 * S),
		Transparency = NS(0, 0.3, 0.7, 0.4, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.85),
		Rate = 90,
		Speed = NumberRange.new(14 * S, 30 * S),
		SpreadAngle = Vector2.new(70, 70),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Acceleration = v3(0, 18 * S, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})
	make("ParticleEmitter", "ImpactSmoke", impactPoint, {
		Texture = TEX.Smoke,
		Color = CS(0, Color3.fromRGB(60, 48, 42), 1, Color3.fromRGB(25, 24, 24)),
		Size = NS(0, 5 * S, 1, 18 * S),
		Transparency = NS(0, 1, 0.25, 0.5, 1, 1),
		Lifetime = NumberRange.new(2, 3),
		Rate = 22,
		Speed = NumberRange.new(8 * S, 14 * S),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Acceleration = v3(0, 6 * S, 0),
		Enabled = false,
	})
	make("ParticleEmitter", "ImpactSparks", impactPoint, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 110, 20)),
		Size = NS(0, 0.3 * S, 1, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Rate = 80,
		Speed = NumberRange.new(30 * S, 52 * S),
		SpreadAngle = Vector2.new(80, 80),
		Acceleration = v3(0, -45 * S, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})
	make("PointLight", "ImpactLight", impact, { Color = C.Fire, Range = 32 * S, Brightness = 4, Shadows = false, Enabled = false })

	-- a glowing heat ribbon from the mouth to the impact point
	make("Beam", "FireBeam", head, {
		Attachment0 = mouth,
		Attachment1 = impactPoint,
		Texture = TEX.Fire,
		TextureMode = Enum.TextureMode.Stretch,
		TextureSpeed = 1.6,
		Color = CS(0, Color3.fromRGB(255, 240, 180), 0.5, Color3.fromRGB(255, 140, 40), 1, Color3.fromRGB(200, 50, 20)),
		Transparency = NS(0, 0.2, 0.6, 0.55, 1, 1),
		Width0 = 1.5 * S,
		Width1 = 8 * S,
		Segments = 12,
		FaceCamera = true,
		LightEmission = 1,
		LightInfluence = 0,
		Enabled = false,
	})

	-- dust: footsteps, landing and wing gusts
	for _, point in pairs(dustPoints) do
		make("ParticleEmitter", "FootDust", point, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(Color3.fromRGB(160, 140, 115), Color3.fromRGB(120, 105, 90)),
			Size = NS(0, 1.5 * S, 1, 5.5 * S),
			Transparency = NS(0, 0.45, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = 0,
			Speed = NumberRange.new(5 * S, 12 * S),
			SpreadAngle = Vector2.new(80, 80),
			Drag = 3,
			Rotation = NumberRange.new(0, 360),
			Acceleration = v3(0, 2 * S, 0),
			Enabled = false,
		})
	end
	local landPoint = attachment("LandPoint", root, BASE * CFrame.new(0, -REST + 0.3 * S, 0))
	make("ParticleEmitter", "LandDust", landPoint, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(165, 145, 120), Color3.fromRGB(115, 100, 85)),
		Size = NS(0, 4 * S, 1, 13 * S),
		Transparency = NS(0, 0.4, 1, 1),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 0,
		Speed = NumberRange.new(30 * S, 55 * S),
		SpreadAngle = Vector2.new(88, 88),
		Drag = 2.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Acceleration = v3(0, 3 * S, 0),
		Enabled = false,
	})

	--------------------------------------------------------------------
	log("Creating sounds...")

	local function sound(name, parent, props)
		local id = SETTINGS.Sounds[name] or ""
		props.SoundId = id
		props.RollOffMaxDistance = props.RollOffMaxDistance or 500 * S
		props.RollOffMinDistance = props.RollOffMinDistance or 25 * S
		local s = make("Sound", name, parent, props)
		-- PLACEHOLDER: set the id in SETTINGS.Sounds at the top, or later in DragonSystem > Config
		s:SetAttribute("Placeholder", id == "")
		return s
	end
	sound("DragonRoar", head, { Volume = 1 })
	sound("DragonFireCharge", head, { Volume = 0.8 })
	sound("DragonFire", head, { Volume = 0.9, Looped = true })
	sound("DragonFireImpact", impact, { Volume = 0.8, Looped = true })
	sound("DragonFootstep", body, { Volume = 0.7 })
	sound("DragonWingFlap", body, { Volume = 0.8 })
	sound("DragonLand", body, { Volume = 1 })

	--------------------------------------------------------------------
	log("Creating fire system...")

	local system = Instance.new("Folder")
	system.Name = "DragonSystem"

	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = system
	local remote = Instance.new("RemoteEvent")
	remote.Name = "DragonAction"
	remote.Parent = remotes

	local assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = system
	local shockwave = Instance.new("Part")
	shockwave.Name = "Shockwave"
	shockwave.Shape = Enum.PartType.Ball
	shockwave.Material = MAT.Neon
	shockwave.Color = Color3.fromRGB(255, 190, 140)
	shockwave.Transparency = 0.75
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.CanQuery = false
	shockwave.CanTouch = false
	shockwave.CastShadow = false
	shockwave.Parent = assets
	local dustRing = Instance.new("Part")
	dustRing.Name = "DustRing"
	dustRing.Shape = Enum.PartType.Cylinder
	dustRing.Color = Color3.fromRGB(170, 150, 125)
	dustRing.Transparency = 0.45
	dustRing.Anchored = true
	dustRing.CanCollide = false
	dustRing.CanQuery = false
	dustRing.CanTouch = false
	dustRing.CastShadow = false
	dustRing.Parent = assets

	local soundLines = {}
	for _, name in ipairs({ "DragonRoar", "DragonFireCharge", "DragonFire", "DragonFireImpact", "DragonFootstep", "DragonWingFlap", "DragonLand" }) do
		table.insert(soundLines, string.format("\t\t%s = %q,", name, SETTINGS.Sounds[name] or ""))
	end
	local configSource = CONFIG_SOURCE
	configSource = configSource:gsub("__SCALE__", tostring(S))
	configSource = configSource:gsub("__NAME__", modelName)
	configSource = configSource:gsub("__AUTOMOUNT__", tostring(SETTINGS.AutoMount))
	configSource = configSource:gsub("__SOUNDS__", function()
		return table.concat(soundLines, "\n")
	end)

	local config = Instance.new("ModuleScript")
	config.Name = "Config"
	config.Source = configSource
	config.Parent = system

	local animator = Instance.new("ModuleScript")
	animator.Name = "Animator"
	animator.Source = ANIMATOR_SOURCE
	animator.Parent = system

	--------------------------------------------------------------------
	log("Creating controls...")

	local server = Instance.new("Script")
	server.Name = "DragonServer"
	server.Source = SERVER_SOURCE

	local controller = Instance.new("LocalScript")
	controller.Name = "DragonController"
	controller.Source = CONTROLLER_SOURCE

	--------------------------------------------------------------------
	log("Placing everything...")

	local partCount = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	model:SetAttribute("PartCount", partCount)
	model:SetAttribute("Action", "")
	model:SetAttribute("Driver", 0)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered("DragonRider") then
			PhysicsService:RegisterCollisionGroup("DragonRider")
		end
		PhysicsService:CollisionGroupSetCollidable("DragonRider", "Default", false)
	end)
	-- Shift is the run key, so it can't also toggle shift-lock
	StarterPlayer.EnableMouseLockOption = false

	model.Parent = Workspace
	system.Parent = ReplicatedStorage
	server.Parent = ServerScriptService
	controller.Parent = starterScripts

	Selection:Set({ model })
	pcall(function()
		ChangeHistoryService:SetWaypoint("Dragon Generator")
	end)
	log(string.format("Built '%s' from %d parts.", modelName, partCount))
end)

if ok then
	log("COMPLETE! Press Play to ride the dragon.")
else
	warn("[Dragon Generator] FAILED: " .. tostring(err))
end
