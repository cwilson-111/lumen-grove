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
local Format = require(ReplicatedStorage.Shared:WaitForChild("Format"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local plantRemote = remotes:WaitForChild("Plant") :: RemoteFunction
local tapRemote = remotes:WaitForChild("Tap") :: RemoteFunction
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local skinRemote = remotes:WaitForChild("Skin") :: RemoteFunction
local expandRemote = remotes:WaitForChild("Expand") :: RemoteFunction
local announceRemote = remotes:WaitForChild("Announce") :: RemoteEvent
local dewRemote = remotes:WaitForChild("CollectDew") :: RemoteFunction
local helpRemote = remotes:WaitForChild("Help") :: RemoteFunction
local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

local selectedSpecies = Config.SPECIES[1].id
local latest: any = nil
-- Declared here, defined with the toast below, so handlers built before
-- the toast exists can still call it.
local say: (message: string, good: boolean) -> ()

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

local balancePanel = panel("Balance", UDim2.new(0, 16, 0, 16), UDim2.new(0, 260, 0, 84))

local balanceLabel = Instance.new("TextLabel")
balanceLabel.Size = UDim2.new(1, -20, 0, 50)
balanceLabel.Position = UDim2.new(0, 14, 0, 4)
balanceLabel.BackgroundTransparency = 1
balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
balanceLabel.Font = Enum.Font.GothamBold
balanceLabel.TextSize = 20
balanceLabel.TextColor3 = Color3.fromRGB(236, 240, 248)
balanceLabel.Text = "Loading your grove…"
balanceLabel.Parent = balancePanel

-- The daily dew's status: ready, how long until the next, or (on day one)
-- the promise of tomorrow's.
local dewLabel = Instance.new("TextLabel")
dewLabel.Name = "Dew"
dewLabel.Size = UDim2.new(1, -20, 0, 22)
dewLabel.Position = UDim2.new(0, 14, 0, 52)
dewLabel.BackgroundTransparency = 1
dewLabel.TextXAlignment = Enum.TextXAlignment.Left
dewLabel.Font = Enum.Font.GothamMedium
dewLabel.TextSize = 13
dewLabel.TextColor3 = Color3.fromRGB(150, 230, 255)
dewLabel.Text = ""
dewLabel.Parent = balancePanel

local ROW = 52
local pickerHeight = ROW * #Config.SPECIES + 40
local picker = panel("Picker", UDim2.new(0, 16, 0, 112), UDim2.new(0, 260, 0, pickerHeight))

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

local function harvestedSoFar(): number
	return latest and latest.harvested or 0
end

-- What a species does for its neighbours, in a few words.
local function auraText(species: Config.Species): string
	local percent = math.floor(species.aura.bonus * 100 + 0.5)
	local target = species.aura.target and Config.speciesById(species.aura.target)
	if target then
		return ("+%d%% to %s beside it"):format(percent, target.name)
	end
	return ("+%d%% to anything beside it"):format(percent)
end

local function refreshPicker()
	for _, species in Config.SPECIES do
		local button = buttons[species.id]
		local locked = harvestedSoFar() < species.unlockHarvests
		local chosen = species.id == selectedSpecies
		button.BackgroundColor3 = locked and Color3.fromRGB(60, 64, 76) or species.colour
		button.BackgroundTransparency = chosen and 0 or 0.72
		button.TextColor3 = chosen and Color3.fromRGB(14, 16, 20)
			or locked and Color3.fromRGB(140, 146, 160)
			or Color3.fromRGB(226, 232, 242)
		local headline = locked and ("%s  ·  at %d harvests"):format(species.name, species.unlockHarvests)
			or ("%s  ·  %d  ·  %s"):format(species.name, species.cost, Format.duration(species.growSeconds))
		button.Text = ('%s\n<font size="11">%s</font>'):format(headline, auraText(species))
	end
end

for index, species in Config.SPECIES do
	local button = Instance.new("TextButton")
	button.Name = species.id
	button.Size = UDim2.new(1, -28, 0, ROW - 8)
	button.Position = UDim2.new(0, 14, 0, 34 + (index - 1) * ROW)
	button.RichText = true
	button.LineHeight = 1.05
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Parent = picker

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.Activated:Connect(function()
		local remaining = species.unlockHarvests - harvestedSoFar()
		if remaining > 0 then
			-- Advisory: the server checks the same thing on Plant.
			say(("%d more harvests to unlock %s."):format(remaining, species.name), false)
			return
		end
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
say = function(message: string, good: boolean)
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

-- Server-wide news: someone found something rare. Top-centre and longer
-- lived than the toast, so it reads as an event, not feedback on a click.
local banner = toast:Clone()
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 16)
banner.Size = UDim2.new(0, 460, 0, 44)
banner.TextSize = 17
banner.Font = Enum.Font.GothamBold
banner.Parent = gui

local bannerToken = 0
announceRemote.OnClientEvent:Connect(function(text: string)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = Color3.fromRGB(255, 222, 140)
	banner.TextTransparency = 0
	banner.BackgroundTransparency = 0.15
	task.delay(5, function()
		if bannerToken == token then
			banner.TextTransparency = 1
			banner.BackgroundTransparency = 1
		end
	end)
end)

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
	local dew = summary.dew
	if dew.ready then
		dewLabel.Text = ("Morning dew waiting on your plot (+%d)"):format(dew.amount)
	elseif dew.firstDay then
		dewLabel.Text = ("Your first dew falls in %s"):format(Format.duration(dew.nextIn))
	else
		dewLabel.Text = ("Next dew in %s"):format(Format.duration(dew.nextIn))
	end
	refreshPicker()

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

-- Something happened to this player that they did not cause: a friend
-- tended one of their plants.
noticeRemote.OnClientEvent:Connect(function(text: string)
	say(text, true)
end)

-- -- prompts ------------------------------------------------------------ --

--[[
	Each plot carries prompts for its owner (plant, tend, harvest, unlock,
	collect dew) and for visitors (help tend). The server marks which are
	`Active`; this client turns on only the active ones meant for it. Enabled
	is a local property here -- the server never writes it -- so what one
	player sees never changes what another does.
]]
local plotsFolder = workspace:WaitForChild("Plots")

local function plotOf(instance: Instance): Model?
	local plot = instance:FindFirstAncestorWhichIsA("Model")
	return plot and plot.Parent == plotsFolder and plot or nil
end

local function applyPrompt(prompt: ProximityPrompt)
	local role = prompt:GetAttribute("Role")
	if role == nil then
		return
	end
	local plot = plotOf(prompt)
	local mine = plot ~= nil and plot:GetAttribute("OwnerUserId") == player.UserId
	local owned = plot ~= nil and (plot:GetAttribute("OwnerUserId") or 0) ~= 0
	local wanted = prompt:GetAttribute("Active") == true
		and owned
		and ((role == "owner") == mine)
	if prompt.Enabled ~= wanted then
		prompt.Enabled = wanted
	end
end

local function watchPrompt(prompt: ProximityPrompt)
	applyPrompt(prompt)
	prompt:GetAttributeChangedSignal("Active"):Connect(function()
		applyPrompt(prompt)
	end)
end

local function watchPlot(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		for _, descendant in plot:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				applyPrompt(descendant)
			end
		end
	end)
end

for _, plot in plotsFolder:GetChildren() do
	watchPlot(plot)
end
plotsFolder.ChildAdded:Connect(watchPlot)
for _, descendant in plotsFolder:GetDescendants() do
	if descendant:IsA("ProximityPrompt") then
		watchPrompt(descendant)
	end
end
plotsFolder.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		watchPrompt(descendant)
	end
end)

local function invoke(remote: RemoteFunction, ...: any)
	local args = table.pack(...)
	local ok, outcome = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		say("Lost contact with the grove.", false)
		return
	end
	say(outcome.message, outcome.ok)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end
	local plot = plotOf(prompt)
	if not plot then
		return
	end

	if prompt.Name == "DewPrompt" then
		invoke(dewRemote)
		return
	end

	local tileIndex = prompt:GetAttribute("TileIndex")
	if typeof(tileIndex) ~= "number" then
		return
	end
	if prompt.Name == "HelpPrompt" then
		invoke(helpRemote, plot:GetAttribute("OwnerUserId"), tileIndex)
		return
	end
	-- The owner prompt is only ever enabled on this player's own plot (see
	-- applyPrompt), and the server applies it to the sender's own plot.
	if plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end

	-- The client only distinguishes locked, empty and occupied. For an
	-- occupied tile it sends Tap and lets the server decide harvest versus
	-- tend: its own view of ripeness is the last state push, up to a second
	-- stale.
	local tileCount = latest and latest.tileCount or Config.STARTING_TILES
	local occupied = latest and latest.tiles[tostring(tileIndex)]
	if tileIndex > tileCount then
		invoke(expandRemote)
	elseif occupied then
		invoke(tapRemote, tileIndex)
	else
		invoke(plantRemote, tileIndex, selectedSpecies)
	end
end)

print("[LumenGrove] client ready")
