--!strict
--[[
	What a planted spore looks like: a mushroom of stems and caps, shaped per
	species so a plot reads at a glance -- Glowcap a round dome, Emberbloom a
	tall bulb with a sprout, Voidlily a flat parasol, Moonpetal a cluster of
	three, Starcap a broad spotted cap.

	Pure presentation. PlotService decides what is planted and how ripe it
	is; this only turns (species, progress, colour) into parts. Nothing reads
	these parts back.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PlantModels = {}

-- One stem with a cap on it. Dimensions in studs at full ripeness; `offset`
-- places it on the tile (x, z) from the tile's centre. A tile is 7 studs.
type Stalk = {
	offset: Vector2,
	stem: number,
	width: number,
	capWidth: number,
	capHeight: number,
}

type Shape = {
	stalks: { Stalk },
	-- Glowing spots on the first cap.
	spots: number,
}

local SHAPES: { [string]: Shape } = {
	glowcap = {
		stalks = { { offset = Vector2.zero, stem = 2.2, width = 1.0, capWidth = 4.4, capHeight = 2.6 } },
		spots = 0,
	},
	emberbloom = {
		stalks = {
			{ offset = Vector2.new(-0.4, -0.3), stem = 4.4, width = 0.8, capWidth = 3.0, capHeight = 3.4 },
			{ offset = Vector2.new(1.8, 1.2), stem = 1.6, width = 0.5, capWidth = 1.5, capHeight = 1.3 },
		},
		spots = 0,
	},
	voidlily = {
		stalks = { { offset = Vector2.zero, stem = 3.4, width = 0.7, capWidth = 5.8, capHeight = 1.3 } },
		spots = 0,
	},
	moonpetal = {
		stalks = {
			{ offset = Vector2.new(0.3, 1.5), stem = 3.6, width = 0.7, capWidth = 2.8, capHeight = 1.8 },
			{ offset = Vector2.new(-1.5, -1.0), stem = 2.8, width = 0.6, capWidth = 2.6, capHeight = 1.6 },
			{ offset = Vector2.new(1.6, -0.9), stem = 2.0, width = 0.5, capWidth = 2.2, capHeight = 1.4 },
		},
		spots = 0,
	},
	starcap = {
		stalks = { { offset = Vector2.zero, stem = 5.0, width = 1.3, capWidth = 6.0, capHeight = 3.0 } },
		spots = 6,
	},
}

-- Smallest a fresh planting is drawn, as a fraction of full size.
local SEEDLING_SCALE = 0.3
local STEM_COLOUR = Color3.fromRGB(196, 190, 180)
local SPOT_COLOUR = Color3.fromRGB(255, 252, 240)

--[[
	Neon under the grove's bloom bleaches pastels toward white: the species
	colours, chosen for the UI, all came out near-identical on the plot. Caps
	get the same hue pushed to a strong saturation, so a plot still reads by
	colour as well as by shape.
]]
local function vivid(colour: Color3): Color3
	local hue, saturation = colour:ToHSV()
	return Color3.fromHSV(hue, math.min(1, saturation * 1.5 + 0.2), 0.9)
end

local function shapeOf(speciesId: string): Shape
	return SHAPES[speciesId] or SHAPES.glowcap
end

local function newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A block rendered through a sphere mesh: unlike a Ball part, it can be any
-- proportions, which is what makes a cap a dome rather than a marble.
local function newEllipsoid(name: string, parent: Instance): Part
	local part = newPart(name, parent)
	part.Material = Enum.Material.Neon
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

function PlantModels.build(species: Config.Species): Model
	local model = Instance.new("Model")
	model.Name = "Plant"
	model:SetAttribute("Species", species.id)
	local shape = shapeOf(species.id)
	for i in shape.stalks do
		local stem = newPart("Stem" .. i, model)
		stem.Shape = Enum.PartType.Cylinder
		stem.Material = Enum.Material.SmoothPlastic
		stem.Color = STEM_COLOUR:Lerp(species.colour, 0.15)
		newEllipsoid("Cap" .. i, model)
	end
	for i = 1, shape.spots do
		local spot = newEllipsoid("Spot" .. i, model)
		spot.Color = SPOT_COLOUR
	end
	-- The plant's light and (for mutations) sparkles live on its main cap.
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Shadows = false
	glow.Parent = model:FindFirstChild("Cap1")
	return model
end

function PlantModels.mainCap(model: Model): Part?
	return model:FindFirstChild("Cap1") :: Part?
end

--[[
	Size and place every part for a plant `progress` (0..1) of the way to
	ripe, standing on `ground` (the centre of the tile's top face).
]]
function PlantModels.pose(model: Model, speciesId: string, progress: number, ripe: boolean, colour: Color3, ground: Vector3)
	local shape = shapeOf(speciesId)
	local scale = SEEDLING_SCALE + (1 - SEEDLING_SCALE) * progress
	local capTransparency = ripe and 0 or 0.4 - progress * 0.3

	local main: { centre: Vector3, width: number, height: number }? = nil
	for i, stalk in shape.stalks do
		local foot = ground + Vector3.new(stalk.offset.X, 0, stalk.offset.Y) * scale
		local stemHeight = stalk.stem * scale
		local width = stalk.width * scale
		local capWidth = stalk.capWidth * scale
		local capHeight = stalk.capHeight * scale

		local stem = model:FindFirstChild("Stem" .. i) :: Part?
		if stem then
			stem.Size = Vector3.new(stemHeight, width, width)
			-- Cylinders run along X; stand it up.
			stem.CFrame = CFrame.new(foot + Vector3.new(0, stemHeight / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end

		-- The cap sits on the stem with its lower third swallowing the top
		-- of it, so no seam shows.
		local centre = foot + Vector3.new(0, stemHeight + capHeight * 0.15, 0)
		local cap = model:FindFirstChild("Cap" .. i) :: Part?
		if cap then
			cap.Size = Vector3.new(capWidth, capHeight, capWidth)
			cap.CFrame = CFrame.new(centre)
			cap.Color = vivid(colour)
			cap.Transparency = capTransparency
		end
		if i == 1 then
			main = { centre = centre, width = capWidth, height = capHeight }
		end
	end

	if main and shape.spots > 0 then
		-- Spots ring the top of the cap, on its surface.
		local reach = 0.55
		local rise = math.sqrt(1 - reach * reach) * main.height / 2 - 0.05 * scale
		for i = 1, shape.spots do
			local spot = model:FindFirstChild("Spot" .. i) :: Part?
			if spot then
				local angle = (i - 1) / shape.spots * 2 * math.pi
				local radius = reach * main.width / 2
				spot.Size = Vector3.new(0.9, 0.35, 0.9) * scale
				spot.CFrame = CFrame.new(main.centre + Vector3.new(math.sin(angle) * radius, rise, math.cos(angle) * radius))
				spot.Transparency = capTransparency
			end
		end
	end
end

return PlantModels
