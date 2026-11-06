--!strict
--[[
	Client UI: a balance readout, a spore picker, and the prompt handler that
	turns a tile interaction into an intent.

	Everything drawn here is advisory. The balance shown is the last one the
	server sent; the countdowns are recomputed locally only so the numbers
	tick smoothly between pushes. Nothing here decides anything.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local plantRemote = remotes:WaitForChild("Plant") :: RemoteFunction
local harvestRemote = remotes:WaitForChild("Harvest") :: RemoteFunction
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent

local selectedSpecies = Config.SPECIES[1].id
local latest: any = nil

-- -- widgets ----------------------------------------------------------- --

local gui = Instance.new("ScreenGui")
gui.Name = "LumenGroveUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function panel(name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	return frame
end

local balancePanel = panel("Balance", UDim2.new(0, 16, 0, 16), UDim2.new(0, 260, 0, 64))

local balanceLabel = Instance.new("TextLabel")
balanceLabel.Size = UDim2.new(1, -20, 1, 0)
balanceLabel.Position = UDim2.new(0, 14, 0, 0)
balanceLabel.BackgroundTransparency = 1
balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
balanceLabel.Font = Enum.Font.GothamBold
balanceLabel.TextSize = 20
balanceLabel.TextColor3 = Color3.fromRGB(236, 240, 248)
balanceLabel.Text = "Loading your grove…"
balanceLabel.Parent = balancePanel

local pickerHeight = 44 * #Config.SPECIES + 48
local picker = panel("Picker", UDim2.new(0, 16, 0, 92), UDim2.new(0, 260, 0, pickerHeight))

local pickerTitle = Instance.new("TextLabel")
pickerTitle.Size = UDim2.new(1, -20, 0, 34)
pickerTitle.Position = UDim2.new(0, 14, 0, 6)
pickerTitle.BackgroundTransparency = 1
pickerTitle.TextXAlignment = Enum.TextXAlignment.Left
pickerTitle.Font = Enum.Font.GothamMedium
pickerTitle.TextSize = 13
pickerTitle.TextColor3 = Color3.fromRGB(150, 158, 174)
pickerTitle.Text = "SPORE TO PLANT"
pickerTitle.Parent = picker

local buttons: { [string]: TextButton } = {}

local function refreshPicker()
	for id, button in buttons do
		local chosen = id == selectedSpecies
		button.BackgroundTransparency = chosen and 0 or 0.72
		button.TextColor3 = chosen and Color3.fromRGB(14, 16, 20) or Color3.fromRGB(226, 232, 242)
	end
end

for index, species in Config.SPECIES do
	local button = Instance.new("TextButton")
	button.Name = species.id
	button.Size = UDim2.new(1, -28, 0, 36)
	button.Position = UDim2.new(0, 14, 0, 34 + (index - 1) * 44)
	button.BackgroundColor3 = species.colour
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Text = ("%s  ·  %d  ·  %ds"):format(species.name, species.cost, species.growSeconds)
	button.Parent = picker

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.Activated:Connect(function()
		selectedSpecies = species.id
		refreshPicker()
	end)
	buttons[species.id] = button
end
refreshPicker()

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -40)
toast.Size = UDim2.new(0, 340, 0, 38)
toast.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
toast.BackgroundTransparency = 0.15
toast.BorderSizePixel = 0
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 15
toast.TextColor3 = Color3.fromRGB(236, 240, 248)
toast.Text = ""
toast.TextTransparency = 1
toast.Parent = gui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 9)
toastCorner.Parent = toast

local toastToken = 0
local function say(message: string, good: boolean)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.TextColor3 = good and Color3.fromRGB(150, 238, 184) or Color3.fromRGB(255, 165, 142)
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.15
	task.delay(2.2, function()
		if toastToken == token then
			toast.TextTransparency = 1
			toast.BackgroundTransparency = 1
		end
	end)
end

-- -- server state ------------------------------------------------------- --

stateRemote.OnClientEvent:Connect(function(summary)
	latest = summary
	-- Plain text, no decorative glyph: Gotham has no ✦, and Roblox draws a
	-- missing codepoint as a tofu box rather than falling back to a font
	-- that has it.
	balanceLabel.Text = ("%d lumen   ·   %d harvested"):format(summary.lumen, summary.harvested)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end
	local tileIndex = prompt:GetAttribute("TileIndex")
	if typeof(tileIndex) ~= "number" then
		return
	end

	-- Ask the server which action this is, rather than deciding here: the
	-- client's view of ripeness is a second behind and is not authoritative.
	local occupied = latest and latest.tiles[tostring(tileIndex)]
	local ok, outcome
	if occupied then
		ok, outcome = pcall(function()
			return harvestRemote:InvokeServer(tileIndex)
		end)
	else
		ok, outcome = pcall(function()
			return plantRemote:InvokeServer(tileIndex, selectedSpecies)
		end)
	end

	if not ok then
		say("Lost contact with the grove.", false)
		return
	end
	say(outcome.message, outcome.ok)
end)

print("[LumenGrove] client ready")
