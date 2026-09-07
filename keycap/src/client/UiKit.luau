--!strict
-- Bausteine fuer die Oberflaeche. Jeder Controller baut damit, keiner baut
-- eigene Rahmen oder Knoepfe - sonst laufen die Panels optisch auseinander.
--
-- Alle Werte kommen aus Theme. In dieser Datei steht keine Farbe und keine
-- Pixelzahl, die nicht von dort kommt.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local UiKit = {}

local function round(instance: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CORNER
	corner.Parent = instance
end

-- Creme-weisse Flaeche mit runden Ecken.
function UiKit.panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.PANEL
	frame.BorderSizePixel = 0
	round(frame)
	frame.Parent = parent
	return frame
end

export type TextOptions = {
	size: UDim2,
	position: UDim2?,
	text: string?,
	textSize: number?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	wrapped: boolean?,
	layoutOrder: number?,
}

function UiKit.text(parent: Instance, options: TextOptions): TextLabel
	local element = Instance.new("TextLabel")
	element.Size = options.size
	element.Position = options.position or UDim2.new(0, 0, 0, 0)
	element.BackgroundTransparency = 1
	element.Font = Theme.FONT
	element.TextScaled = false
	element.TextSize = options.textSize or Theme.TEXT_SIZE.BODY
	element.TextColor3 = options.color or Theme.TEXT
	element.TextXAlignment = options.align or Enum.TextXAlignment.Left
	element.TextWrapped = options.wrapped or false
	element.LayoutOrder = options.layoutOrder or 0
	element.Text = options.text or ""
	element.Parent = parent
	return element
end

export type ButtonOptions = {
	size: UDim2,
	position: UDim2?,
	text: string,
	base: Color3,
	edge: Color3,
	textColor: Color3?,
	textSize: number?,
	layoutOrder: number?,
}

-- Knopf mit dunklerer Unterkante. Beim Druecken rutscht die Oberseite auf
-- die Kante - dieselbe Bewegung, die ein echter Tastenanschlag macht.
-- Ohne diese Rueckmeldung fuehlt sich auf dem Handy nichts an, weil es
-- keinen Hover-Zustand gibt.
function UiKit.button(parent: Instance, options: ButtonOptions): TextButton
	local holder = Instance.new("Frame")
	holder.Size = options.size
	holder.Position = options.position or UDim2.new(0, 0, 0, 0)
	holder.BackgroundColor3 = options.edge
	holder.BorderSizePixel = 0
	holder.LayoutOrder = options.layoutOrder or 0
	round(holder)

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, -Theme.BUTTON_EDGE_HEIGHT)
	button.Position = UDim2.new(0, 0, 0, 0)
	button.BackgroundColor3 = options.base
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- eigene Rueckmeldung statt Roblox-Graufilter
	button.Font = Theme.FONT
	button.TextScaled = false
	button.TextSize = options.textSize or Theme.TEXT_SIZE.BODY
	button.TextColor3 = options.textColor or Theme.TEXT
	button.Text = options.text
	round(button)

	local raised = UDim2.new(0, 0, 0, 0)
	local pressed = UDim2.new(0, 0, 0, Theme.BUTTON_EDGE_HEIGHT)
	button.MouseButton1Down:Connect(function()
		button.Position = pressed
	end)
	button.MouseButton1Up:Connect(function()
		button.Position = raised
	end)
	-- Wer den Finger neben dem Knopf loslaesst, bekommt kein MouseButton1Up.
	button.MouseLeave:Connect(function()
		button.Position = raised
	end)

	button.Parent = holder
	holder.Parent = parent
	return button
end

-- Untereinander-Layout mit gleichmaessigem Abstand und Innenrand.
function UiKit.stack(parent: Instance, padding: number?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or Theme.SPACE.S)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent

	local inset = Instance.new("UIPadding")
	local space = UDim.new(0, Theme.SPACE.M)
	inset.PaddingTop = space
	inset.PaddingBottom = space
	inset.PaddingLeft = space
	inset.PaddingRight = space
	inset.Parent = parent

	return layout
end

-- Skaliert das ganze HUD fuer kleine Bildschirme. Ohne das ist das HUD auf
-- dem Handy zu gross und verdeckt das Spiel.
function UiKit.autoScale(gui: ScreenGui): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local camera = workspace.CurrentCamera

	local function apply()
		local viewport = if camera then camera.ViewportSize else Vector2.new(Theme.SCALE_REFERENCE_WIDTH, 720)
		local factor = viewport.X / Theme.SCALE_REFERENCE_WIDTH
		scale.Scale = math.clamp(factor, Theme.SCALE_MIN, Theme.SCALE_MAX)
	end

	apply()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	return scale
end

return UiKit
