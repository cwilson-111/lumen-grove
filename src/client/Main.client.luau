--!strict
--[[
	Client UI: a balance readout, a spore picker, a skin picker, and the
	prompt handler that turns a tile interaction into an intent.

	Everything drawn here is advisory. The balance shown is the last one the
	server sent; the countdowns are recomputed locally only so the numbers
	tick smoothly between pushes. Nothing here decides anything.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local plantRemote = remotes:WaitForChild("Plant") :: RemoteFunction
local tapRemote = remotes:WaitForChild("Tap") :: RemoteFunction
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local skinRemote = remotes:WaitForChild("Skin") :: RemoteFunction

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
-- Starts fully hidden, background included. It used to start with its text
-- transparent but its background at 0.15, leaving an empty dark bar on
-- screen until the first message arrived and its timeout hid both.
toast.BackgroundTransparency = 1
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

-- -- skins --------------------------------------------------------------- --

local skinsHeight = 44 * #Config.SKINS + 48
-- Top-right, not stacked under the spore picker: stacked, the last row ran
-- off the bottom of a laptop-height viewport.
local skinsPanel = panel("Skins", UDim2.new(1, -16, 0, 16), UDim2.new(0, 260, 0, skinsHeight))
skinsPanel.AnchorPoint = Vector2.new(1, 0)

local skinsTitle = pickerTitle:Clone()
skinsTitle.Text = "PLOT SKIN"
skinsTitle.Parent = skinsPanel

-- Filled in from Roblox as each pass's price arrives; until then a locked
-- skin just reads "Unlock". The price is never kept in Config, where it
-- could disagree with what the purchase prompt charges.
local prices: { [string]: number } = {}
local skinButtons: { [string]: { button: TextButton, status: TextLabel } } = {}
-- Advisory copy of the server's last word; drawing only.
local shownSkin = Config.DEFAULT_SKIN
local ownedSkins: { [string]: boolean } = { [Config.DEFAULT_SKIN] = true }

local function refreshSkins()
	for id, parts in skinButtons do
		local equipped = id == shownSkin
		parts.button.BackgroundTransparency = equipped and 0 or 0.72
		local ink = equipped and Color3.fromRGB(14, 16, 20) or Color3.fromRGB(226, 232, 242)
		parts.button.TextColor3 = ink
		parts.status.TextColor3 = ink
		if equipped then
			parts.status.Text = "On"
		elseif ownedSkins[id] then
			parts.status.Text = "Equip"
		elseif prices[id] then
			parts.status.Text = ("R$ %d"):format(prices[id])
		else
			parts.status.Text = "Unlock"
		end
	end
end

for index, skin in Config.SKINS do
	local gamePassId = skin.gamePassId
	local button = Instance.new("TextButton")
	button.Name = skin.id
	button.Size = UDim2.new(1, -28, 0, 36)
	button.Position = UDim2.new(0, 14, 0, 34 + (index - 1) * 44)
	button.BackgroundColor3 = skin.trimColour or skin.tileColour
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = "   " .. skin.name
	button.Parent = skinsPanel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -12, 0, 0)
	status.Size = UDim2.new(0, 80, 1, 0)
	status.BackgroundTransparency = 1
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Font = Enum.Font.GothamBold
	status.TextSize = 13
	status.Parent = button

	button.Activated:Connect(function()
		if skin.id == shownSkin then
			return
		end
		if not ownedSkins[skin.id] and gamePassId then
			-- Roblox's own prompt. What happens next is reported to the
			-- server by Roblox, never by this script.
			MarketplaceService:PromptGamePassPurchase(player, gamePassId)
			return
		end
		local ok, outcome = pcall(function()
			return skinRemote:InvokeServer(skin.id)
		end)
		if ok then
			say(outcome.message, outcome.ok)
		else
			say("Lost contact with the grove.", false)
		end
	end)
	skinButtons[skin.id] = { button = button, status = status }

	if gamePassId then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
			end)
			if ok and typeof(info.PriceInRobux) == "number" then
				prices[skin.id] = info.PriceInRobux
				refreshSkins()
			end
		end)
	end
end
refreshSkins()

-- -- server state ------------------------------------------------------- --

stateRemote.OnClientEvent:Connect(function(summary)
	latest = summary
	-- Plain text, no decorative glyph: Gotham has no ✦, and Roblox draws a
	-- missing codepoint as a tofu box rather than falling back to a font
	-- that has it.
	balanceLabel.Text = ("%d lumen   ·   %d harvested"):format(summary.lumen, summary.harvested)

	shownSkin = summary.skin
	table.clear(ownedSkins)
	for _, id in summary.ownedSkins do
		ownedSkins[id] = true
	end
	refreshSkins()
end)

-- Only a toast. The skin itself arrives with the next state push, once the
-- server has heard about the purchase from Roblox.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(buyer, gamePassId, wasPurchased)
	local skin = Config.skinByGamePass(gamePassId)
	if buyer == player and wasPurchased and skin then
		say(("%s unlocked."):format(skin.name), true)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end
	local tileIndex = prompt:GetAttribute("TileIndex")
	if typeof(tileIndex) ~= "number" then
		return
	end

	-- The client only distinguishes "empty" from "occupied". For an occupied
	-- tile it sends Tap and lets the server decide harvest versus tend: its
	-- own view of ripeness is the last state push, up to a second stale.
	local occupied = latest and latest.tiles[tostring(tileIndex)]
	local ok, outcome
	if occupied then
		ok, outcome = pcall(function()
			return tapRemote:InvokeServer(tileIndex)
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
