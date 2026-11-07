--[[
	Builds the Lumen Grove world into the open place: night lighting, terrain,
	the hub's elder mushroom, scattered glowing fungi, a treeline, drifting
	spores. Send this whole file through Studio MCP's `execute_luau` against
	the **Edit** datamodel, then publish the place so it sticks.

	Idempotent: it clears the terrain and rebuilds `Workspace.Grove` from
	scratch, and only ever touches what it creates plus Lighting, the
	Baseplate (removed) and the SpawnLocation (moved). Seeded, so a rebuild
	gives the same grove.

	Plot positions come from the same `Config.plotCFrame` the server uses, so
	nothing is ever placed where a plot will stand.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- execute_luau caches modules across calls, so require a fresh clone of the
-- Shared folder rather than the original (see README, testing notes).
local sharedCopy = ReplicatedStorage.Shared:Clone()
sharedCopy.Name = "SharedWorldBuild"
sharedCopy.Parent = ReplicatedStorage
local Config = require(sharedCopy.Config)
sharedCopy:Destroy()

local rng = Random.new(20261107)
local HUB_RADIUS = 34
-- Well past the hill ring, so no camera angle finds the edge of the world.
local GROUND_RADIUS = 700
local PATH_WIDTH = 8
local PLOT_CLEARANCE = Config.GRID * Config.TILE_STUDS / 2 + 14

local plotCentres = {}
for slot = 1, Config.PLOTS_PER_RING do
	table.insert(plotCentres, Config.plotCFrame(slot).Position)
end

-- -- lighting ------------------------------------------------------------ --

Lighting.ClockTime = 21.5
-- Night, but a readable one: a player has to see their plot without the
-- glow doing all the work.
Lighting.Brightness = 2.2
Lighting.ExposureCompensation = 0.35
Lighting.Ambient = Color3.fromRGB(78, 70, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(116, 106, 170)
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.4
Lighting.GlobalShadows = true

local function effect(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = Lighting
	return made
end

local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
if sunRays then
	sunRays:Destroy() -- night: there is no sun to ray
end

local atmosphere = effect("Atmosphere", "Atmosphere")
atmosphere.Density = 0.3
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(64, 56, 120)
atmosphere.Decay = Color3.fromRGB(30, 24, 70)
atmosphere.Glare = 0
atmosphere.Haze = 0.6

local bloom = effect("BloomEffect", "Bloom")
bloom.Intensity = 0.9
bloom.Size = 28
bloom.Threshold = 1.1

local grade = effect("ColorCorrectionEffect", "Grade")
grade.Saturation = 0.12
grade.Contrast = 0.06
grade.TintColor = Color3.fromRGB(236, 236, 255)

local sky = effect("Sky", "Sky")
sky.StarCount = 6000

-- -- terrain ------------------------------------------------------------- --

local baseplate = Workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end

local terrain = Workspace.Terrain
terrain:Clear()
terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(34, 66, 60))
terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(58, 48, 66))
terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(56, 56, 74))
terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(46, 38, 54))

-- Flat ground: voxels solid up to y = 0. Smooth terrain draws and collides
-- that surface half a voxel higher, at y = 2 (measured), which is why
-- Config.GROUND_Y is 2 and every plot stands there.
terrain:FillCylinder(CFrame.new(0, -6, 0), 12, GROUND_RADIUS, Enum.Material.LeafyGrass)
-- The hub: a worn clearing round the elder mushroom.
terrain:FillCylinder(CFrame.new(0, -2, 0), 4, HUB_RADIUS, Enum.Material.Ground)
-- A path from the hub to the front edge of every plot.
for _, centre in plotCentres do
	local direction = Vector3.new(centre.X, 0, centre.Z).Unit
	local from = direction * (HUB_RADIUS - 4)
	local to = direction * (Config.PLOT_RING_RADIUS - Config.GRID * Config.TILE_STUDS / 2)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	terrain:FillBlock(
		CFrame.lookAt(Vector3.new(mid.X, -2, mid.Z), Vector3.new(to.X, -2, to.Z)),
		Vector3.new(PATH_WIDTH, 4, length),
		Enum.Material.Mud
	)
end
task.wait()

-- A ring of hills closes the grove in, so the world has an edge that is
-- not a cliff into the void.
for _ = 1, 70 do
	local angle = rng:NextNumber(0, 2 * math.pi)
	local radius = rng:NextNumber(270, 320)
	local size = rng:NextNumber(26, 60)
	terrain:FillBall(
		Vector3.new(math.sin(angle) * radius, rng:NextNumber(-size * 0.5, 0), math.cos(angle) * radius),
		size,
		rng:NextNumber() < 0.3 and Enum.Material.Rock or Enum.Material.LeafyGrass
	)
end
task.wait()

-- -- decoration ---------------------------------------------------------- --

local old = Workspace:FindFirstChild("Grove")
if old then
	old:Destroy()
end
local grove = Instance.new("Folder")
grove.Name = "Grove"

local function part(props: { [string]: any }): Part
	local made = Instance.new("Part")
	made.Anchored = true
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(made :: any)[key] = value
	end
	return made
end

-- An ellipsoid: a block part rendered through a sphere mesh, which (unlike
-- a Ball part) can take any proportions.
local function ellipsoid(size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material, parent: Instance): Part
	local made = part({
		Size = size,
		CFrame = cframe,
		Color = colour,
		Material = material,
		CanCollide = false,
		CastShadow = material ~= Enum.Material.Neon,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = made
	made.Parent = parent
	return made
end

local function stem(height: number, width: number, at: Vector3, colour: Color3, parent: Instance)
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, width),
		CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = colour,
		Material = Enum.Material.SmoothPlastic,
	}).Parent = parent
end

local CAP_COLOURS = {
	Color3.fromRGB(96, 236, 210),
	Color3.fromRGB(176, 128, 255),
	Color3.fromRGB(255, 120, 196),
	Color3.fromRGB(255, 196, 110),
	Color3.fromRGB(120, 190, 255),
}

local function mushroom(at: Vector3, scale: number, colour: Color3, lit: boolean, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Glowshroom"
	local height = 3.2 * scale
	stem(height, 0.9 * scale, at, Color3.fromRGB(226, 220, 204), model)
	local tilt = CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
	ellipsoid(
		Vector3.new(4 * scale, 1.7 * scale, 4 * scale),
		CFrame.new(at + Vector3.new(0, height, 0)) * tilt,
		colour,
		Enum.Material.Neon,
		model
	)
	if lit then
		local light = Instance.new("PointLight")
		light.Color = colour
		light.Range = 10 + scale * 4
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = model:FindFirstChildWhichIsA("Part")
	end
	model.Parent = parent
end

-- The elder mushroom: the landmark you spawn beside and can see from every
-- plot.
do
	local elder = Instance.new("Model")
	elder.Name = "ElderMushroom"
	stem(36, 9, Vector3.new(0, 0, 0), Color3.fromRGB(232, 224, 206), elder)
	local cap = ellipsoid(
		Vector3.new(62, 22, 62),
		CFrame.new(0, 38, 0),
		Color3.fromRGB(70, 196, 186),
		Enum.Material.SmoothPlastic,
		elder
	)
	cap.CanCollide = true
	-- Underside glow, lighting the hub like a lantern.
	local underside = Instance.new("Attachment")
	underside.Position = Vector3.new(0, -12, 0)
	underside.Parent = cap
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 255, 236)
	light.Range = 60
	light.Brightness = 2.4
	light.Shadows = false
	light.Parent = underside
	-- Glowing spots across the top of the cap.
	for _ = 1, 22 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local reach = rng:NextNumber(0, 0.85)
		local x, z = math.sin(angle) * reach * 31, math.cos(angle) * reach * 31
		local y = 38 + 11 * math.sqrt(math.max(1 - reach * reach, 0)) - 0.4
		local spot = rng:NextNumber(2.5, 5.5)
		ellipsoid(Vector3.new(spot, 1, spot), CFrame.new(x, y, z), Color3.fromRGB(220, 255, 246), Enum.Material.Neon, elder)
	end
	elder.Parent = grove

	-- A ring of small ones round its foot.
	for i = 1, 12 do
		local angle = i / 12 * 2 * math.pi + rng:NextNumber(-0.1, 0.1)
		local radius = rng:NextNumber(9, 13)
		mushroom(
			Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius),
			rng:NextNumber(0.6, 1.1),
			CAP_COLOURS[rng:NextInteger(1, #CAP_COLOURS)],
			i % 3 == 0,
			grove
		)
	end
end
task.wait()

-- True when a point is clear of the hub, every plot and every path.
local function clear(point: Vector3): boolean
	local flat = Vector3.new(point.X, 0, point.Z)
	if flat.Magnitude < HUB_RADIUS + 4 then
		return false
	end
	for _, centre in plotCentres do
		local plotFlat = Vector3.new(centre.X, 0, centre.Z)
		if (flat - plotFlat).Magnitude < PLOT_CLEARANCE then
			return false
		end
		-- Distance from the path line hub -> plot.
		local direction = plotFlat.Unit
		local along = flat:Dot(direction)
		if along > 0 and along < plotFlat.Magnitude then
			if (flat - direction * along).Magnitude < PATH_WIDTH / 2 + 3 then
				return false
			end
		end
	end
	return true
end

local function scatter(count: number, minRadius: number, maxRadius: number, place: (Vector3) -> ())
	local placed, attempts = 0, 0
	while placed < count and attempts < count * 30 do
		attempts += 1
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = math.sqrt(rng:NextNumber(minRadius ^ 2, maxRadius ^ 2))
		local point = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		if clear(point) then
			place(point)
			placed += 1
		end
	end
end

local shrooms = Instance.new("Folder")
shrooms.Name = "Glowshrooms"
shrooms.Parent = grove
scatter(90, HUB_RADIUS + 6, 250, function(point)
	-- Clusters of one to four, so the fungi read as growing, not sprinkled.
	local colour = CAP_COLOURS[rng:NextInteger(1, #CAP_COLOURS)]
	for i = 1, rng:NextInteger(1, 4) do
		local offset = i == 1 and Vector3.zero or Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		mushroom(point + offset, rng:NextNumber(0.5, 1.6), colour, i == 1 and rng:NextNumber() < 0.35, shrooms)
	end
end)
task.wait()

local trees = Instance.new("Folder")
trees.Name = "Trees"
trees.Parent = grove
scatter(70, 175, 285, function(point)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local height = rng:NextNumber(18, 34)
	stem(height, rng:NextNumber(2.2, 3.6), point, Color3.fromRGB(52, 40, 46), model)
	local leaf = Color3.fromRGB(rng:NextInteger(26, 40), rng:NextInteger(58, 78), rng:NextInteger(64, 84))
	for _ = 1, rng:NextInteger(2, 4) do
		local size = rng:NextNumber(12, 20)
		ellipsoid(
			Vector3.new(size, size * 0.8, size),
			CFrame.new(point + Vector3.new(rng:NextNumber(-4, 4), height + rng:NextNumber(-3, 4), rng:NextNumber(-4, 4))),
			leaf,
			Enum.Material.LeafyGrass,
			model
		)
	end
	model.Parent = trees
end)
task.wait()

local rocks = Instance.new("Folder")
rocks.Name = "Rocks"
rocks.Parent = grove
scatter(40, HUB_RADIUS + 8, 260, function(point)
	local size = Vector3.new(rng:NextNumber(2, 6), rng:NextNumber(1.5, 4), rng:NextNumber(2, 6))
	part({
		Size = size,
		CFrame = CFrame.new(point + Vector3.new(0, size.Y * 0.3, 0))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
		Color = Color3.fromRGB(70, 70, 88),
		Material = Enum.Material.Slate,
	}).Parent = rocks
end)

-- Spores drifting up through the whole grove: emitters on invisible slabs.
local spores = Instance.new("Folder")
spores.Name = "Spores"
spores.Parent = grove
for _, at in { Vector3.new(0, 4, 0), table.unpack(plotCentres) } do
	local slab = part({
		Size = Vector3.new(70, 1, 70),
		CFrame = CFrame.new(Vector3.new(at.X, 4, at.Z)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 7
	emitter.Lifetime = NumberRange.new(8, 14)
	emitter.Speed = NumberRange.new(0.4, 1.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.35, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 255, 230), Color3.fromRGB(200, 160, 255))
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = slab
	slab.Parent = spores
end

grove.Parent = Workspace

-- -- spawn --------------------------------------------------------------- --

-- Under the elder mushroom's glow; the server moves each player to their
-- own plot as soon as it has assigned one.
local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
if spawnLocation then
	spawnLocation.CFrame = CFrame.new(0, 0.5, HUB_RADIUS - 12) * CFrame.Angles(0, math.pi, 0)
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	local decal = spawnLocation:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
end

local count = 0
for _, d in grove:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
return ("grove built: %d parts, %d plot slots kept clear"):format(count, #plotCentres)
