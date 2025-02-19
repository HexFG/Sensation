if not LPH_OBFUSCATED then
    getfenv().LPH_NO_VIRTUALIZE = function(f) return f end;
end

-- services
local runService = game:GetService("RunService");
local players = game:GetService("Players");
local workspace = game:GetService("Workspace");

-- variables
local localPlayer = players.LocalPlayer;
local camera = workspace.CurrentCamera;
local viewportSize = camera.ViewportSize;
local container = Instance.new("Folder",
	gethui and gethui() or game:GetService("CoreGui"));

-- locals
local floor = math.floor;
local round = math.round;
local sin = math.sin;
local cos = math.cos;
local clear = table.clear;
local unpack = table.unpack;
local find = table.find;
local create = table.create;
local fromMatrix = CFrame.fromMatrix;

-- methods
local wtvp = camera.WorldToViewportPoint;
local isA = workspace.IsA;
local getPivot = workspace.GetPivot;
local getChildren = workspace.GetChildren;
local toOrientation = CFrame.identity.ToOrientation;
local pointToObjectSpace = CFrame.identity.PointToObjectSpace;
local lerpColor = Color3.new().Lerp;
local min2 = Vector2.zero.Min;
local max2 = Vector2.zero.Max;
local lerp2 = Vector2.zero.Lerp;
local min3 = Vector3.zero.Min;
local max3 = Vector3.zero.Max;

-- constants
local HEALTH_BAR_OFFSET = Vector2.new(5, 0);
local HEALTH_TEXT_OFFSET = Vector2.new(3, 0);
local HEALTH_BAR_OUTLINE_OFFSET = Vector2.new(0, 1);
local NAME_OFFSET = Vector2.new(0, 2);
local DISTANCE_OFFSET = Vector2.new(0, 2);

-- functions
local function rotateVector(vector, radians)
	local x, y = vector.X, vector.Y
	local c, s = cos(radians), sin(radians)
	return Vector2.new(x * c - y * s, x * s + y * c)
end

local function parseColor(self, color, isOutline)
	if color == "Team Color" or (self.interface.sharedSettings.useTeamColor and not isOutline) then
		return self.interface.getTeamColor(self.player) or Color3.new(1,1,1);
	end
	return color;
end

local function getDistance(pos)
    local char = players.LocalPlayer.Character

    if char then
        if not char:FindFirstChild("HumanoidRootPart") then return 0 end
        return (pos - char:FindFirstChild("HumanoidRootPart").CFrame.Position).Magnitude
    end
end

-- esp object
local objects = {}
local esp = {}
esp.__index = esp

function esp.new(player, interface)
	local self = setmetatable({}, esp)
	self.player = assert(player, "Missing argument #1 (Player expected)")
	self.interface = assert(interface, "Missing argument #2 (table expected)")
	self:Create()

    objects[self.player] = self
	return self
end

function esp:_draw(class, properties)
	local drawing = Drawing.new(class)
	for property, value in next, properties do
		pcall(function() drawing[property] = value; end)
	end
	self.bin[#self.bin + 1] = drawing
	return drawing
end

function esp:Create()
	self.bin = {}
	self.drawings = {
		visible = {
			tracerOutline = self:_draw("Line", { Thickness = 3, Visible = false }),
			tracer = self:_draw("Line", { Thickness = 1, Visible = false }),
			boxFill = self:_draw("Square", { Filled = true, Visible = false }),
			boxOutline = self:_draw("Square", { Thickness = 3, Visible = false }),
			box = self:_draw("Square", { Thickness = 1, Visible = false }),
			healthBarOutline = self:_draw("Line", { Thickness = 3, Visible = false }),
			healthBar = self:_draw("Line", { Thickness = 1, Visible = false }),
			healthText = self:_draw("Text", { Center = true, Visible = false }),
			name = self:_draw("Text", { Text = self.player.DisplayName, Center = true, Visible = false }),
			distance = self:_draw("Text", { Center = true, Visible = false }),
			weapon = self:_draw("Text", { Center = true, Visible = false }),
		},
		hidden = {
			arrowOutline = self:_draw("Triangle", { Thickness = 3, Visible = false }),
			arrow = self:_draw("Triangle", { Filled = true, Visible = false })
		}
	};

	self.renderConnection = runService.PreRender:Connect(LPH_NO_VIRTUALIZE(function()
		self:Update()
		self:Render()
	end))
end

function esp:Destroy()
	self.renderConnection:Disconnect();

	for i = 1, #self.bin do
		self.bin[i]:Remove();
	end

	clear(self);
end

function esp:Update()
	local interface = self.interface;

	self.options = interface.teamSettings[interface.isFriendly(self.player) and "friendly" or "enemy"];
	self.character = interface.getCharacter(self.player)
	self.health, self.maxHealth = interface.getHealth(self.player)
	self.weapon = interface.getWeapon(self.player)
	self.enabled = self.options.enabled and self.character and self.health > 0
	if not self.character then return end
	
	local head = self.character:FindFirstChild("Head")
	local root = self.character:FindFirstChild("HumanoidRootPart")
	if not head or not root or not self.enabled then
        self.enabled = false
		return
	end

    local screenPosition, visible = camera:WorldToViewportPoint(root.Position)

    local distance = getDistance(root.Position)
	self.onScreen = visible
	self.distance = distance

	if interface.sharedSettings.limitDistance and distance > interface.sharedSettings.maxDistance then
		self.enabled = false
        return
	end

	if self.onScreen then
        local scale_factor = 1 / (screenPosition.Z * math.tan(math.rad(camera.FieldOfView * 0.5)) * 2) * 100
        self.width, self.height = math.floor(35 * scale_factor), math.floor(50 * scale_factor)
        self.x, self.y = math.floor(screenPosition.X), math.floor(screenPosition.Y)

        self.top_left = Vector2.new(self.x - (0.5 * self.width), self.y - (0.5 * self.height))
        self.top_right = Vector2.new(self.x + (0.5 * self.width), self.y - (0.5 * self.height))
        self.bottom_left = Vector2.new(self.x - (0.5 * self.width), self.y + (0.5 * self.height))
        self.bottom_right = Vector2.new(self.x + (0.5 * self.width), self.y + (0.5 * self.height))
        self.center = Vector2.new(math.floor(self.x - self.width * 0.5), math.floor(self.y - self.height * 0.5))

	elseif self.options.offScreenArrow then
		local cframe = camera.CFrame;
		local flat = fromMatrix(cframe.Position, cframe.RightVector, Vector3.yAxis);
		local objectSpace = pointToObjectSpace(flat, head.Position);
		self.direction = Vector2.new(objectSpace.X, objectSpace.Z).Unit;
	end
end

function esp:Render()
	local onScreen = self.onScreen or false;
	local enabled = self.enabled or false;
	local visible = self.drawings.visible;
	local hidden = self.drawings.hidden;
	local box3d = self.drawings.box3d;
	local interface = self.interface;
	local options = self.options;

	visible.box.Visible = enabled and onScreen and options.box
	visible.boxOutline.Visible = visible.box.Visible and options.boxOutline
	if visible.box.Visible then
        local box = visible.box
        box.Position =self.center
        box.Size = Vector2.new(self.width, self.height)
        box.Color = parseColor(self, options.boxColor[1])
		box.Transparency = options.boxColor[2]

        local boxOutline = visible.boxOutline
        boxOutline.Position = self.center
        boxOutline.Size = Vector2.new(self.width, self.height)
        boxOutline.Color = parseColor(self, options.boxOutlineColor[1], true)
		boxOutline.Transparency = options.boxOutlineColor[2]
	end

	visible.boxFill.Visible = enabled and onScreen and options.boxFill
	if visible.boxFill.Visible then
        local boxFill = visible.boxFill
        boxFill.Position = self.center
        boxFill.Size = Vector2.new(self.width, self.height)
		boxFill.Color = parseColor(self, options.boxFillColor[1])
		boxFill.Transparency = options.boxFillColor[2]
	end

	visible.healthBar.Visible = enabled and onScreen and options.healthBar
	visible.healthBarOutline.Visible = visible.healthBar.Visible and options.healthBarOutline
	if visible.healthBar.Visible then
		local barFrom = self.top_left - HEALTH_BAR_OFFSET
		local barTo = self.bottom_left - HEALTH_BAR_OFFSET

		local healthBar = visible.healthBar
		healthBar.To = barTo
		healthBar.From = lerp2(barTo, barFrom, self.health/self.maxHealth)
		healthBar.Color = lerpColor(options.dyingColor, options.healthyColor, self.health/self.maxHealth)

		local healthBarOutline = visible.healthBarOutline
		healthBarOutline.To = barTo + HEALTH_BAR_OUTLINE_OFFSET
		healthBarOutline.From = barFrom - HEALTH_BAR_OUTLINE_OFFSET
		healthBarOutline.Color = parseColor(self, options.healthBarOutlineColor[1], true)
		healthBarOutline.Transparency = options.healthBarOutlineColor[2]
    end

	visible.healthText.Visible = enabled and onScreen and options.healthText
	if visible.healthText.Visible then
		local barFrom = self.top_left - HEALTH_BAR_OFFSET
		local barTo = self.bottom_left - HEALTH_BAR_OFFSET

		local healthText = visible.healthText
		healthText.Text = round(self.health) .. "hp"
		healthText.Size = interface.sharedSettings.textSize
		healthText.Font = interface.sharedSettings.textFont
		healthText.Color = parseColor(self, options.healthTextColor[1])
		healthText.Transparency = options.healthTextColor[2]
		healthText.Outline = options.healthTextOutline
		healthText.OutlineColor = parseColor(self, options.healthTextOutlineColor, true)
		healthText.Position = lerp2(barTo, barFrom, self.health/self.maxHealth) - healthText.TextBounds*0.5 - HEALTH_TEXT_OFFSET
	end

	visible.name.Visible = enabled and onScreen and options.name
	if visible.name.Visible then
		local name = visible.name
		name.Size = interface.sharedSettings.textSize
		name.Font = interface.sharedSettings.textFont
		name.Color = parseColor(self, options.nameColor[1])
		name.Transparency = options.nameColor[2]
		name.Outline = options.nameOutline
		name.OutlineColor = parseColor(self, options.nameOutlineColor, true)
		name.Position = (self.top_left + self.top_right)*0.5 - Vector2.yAxis * name.TextBounds.Y - NAME_OFFSET
	end

	visible.distance.Visible = enabled and onScreen and self.distance and options.distance;
	if visible.distance.Visible then
		local distance = visible.distance;
		distance.Text = round(self.distance) .. " studs";
		distance.Size = interface.sharedSettings.textSize;
		distance.Font = interface.sharedSettings.textFont;
		distance.Color = parseColor(self, options.distanceColor[1]);
		distance.Transparency = options.distanceColor[2];
		distance.Outline = options.distanceOutline;
		distance.OutlineColor = parseColor(self, options.distanceOutlineColor, true);
		distance.Position = (self.bottom_left + self.bottom_right) *0.5 + DISTANCE_OFFSET;
	end

	visible.weapon.Visible = enabled and onScreen and options.weapon;
	if visible.weapon.Visible then
		local weapon = visible.weapon;
		weapon.Text = self.weapon;
		weapon.Size = interface.sharedSettings.textSize;
		weapon.Font = interface.sharedSettings.textFont;
		weapon.Color = parseColor(self, options.weaponColor[1]);
		weapon.Transparency = options.weaponColor[2];
		weapon.Outline = options.weaponOutline;
		weapon.OutlineColor = parseColor(self, options.weaponOutlineColor, true);
		weapon.Position =
			(self.bottom_left + self.bottom_right)*0.5 +
			(visible.distance.Visible and DISTANCE_OFFSET + Vector2.yAxis*visible.distance.TextBounds.Y or Vector2.zero);
	end

	visible.tracer.Visible = enabled and onScreen and options.tracer;
	visible.tracerOutline.Visible = visible.tracer.Visible and options.tracerOutline;
	if visible.tracer.Visible then
		local tracer = visible.tracer;
		tracer.Color = parseColor(self, options.tracerColor[1]);
		tracer.Transparency = options.tracerColor[2];
		tracer.To = (self.bottom_left + self.bottom_right)*0.5;
		tracer.From =
			options.tracerOrigin == "Middle" and viewportSize * 0.5 or
			options.tracerOrigin == "Top" and viewportSize * Vector2.new(0.5, 0) or
			options.tracerOrigin == "Bottom" and viewportSize * Vector2.new(0.5, 1);

		local tracerOutline = visible.tracerOutline;
		tracerOutline.Color = parseColor(self, options.tracerOutlineColor[1], true);
		tracerOutline.Transparency = options.tracerOutlineColor[2];
		tracerOutline.To = tracer.To;
		tracerOutline.From = tracer.From;
	end

	hidden.arrow.Visible = enabled and (not onScreen) and options.offScreenArrow;
	hidden.arrowOutline.Visible = hidden.arrow.Visible and options.offScreenArrowOutline;
	if hidden.arrow.Visible and self.direction then
		local arrow = hidden.arrow;
		arrow.PointA = min2(max2(viewportSize*0.5 + self.direction*options.offScreenArrowRadius, Vector2.one*25), viewportSize - Vector2.one*25);
		arrow.PointB = arrow.PointA - rotateVector(self.direction, 0.45)*options.offScreenArrowSize;
		arrow.PointC = arrow.PointA - rotateVector(self.direction, -0.45)*options.offScreenArrowSize;
		arrow.Color = parseColor(self, options.offScreenArrowColor[1]);
		arrow.Transparency = options.offScreenArrowColor[2];

		local arrowOutline = hidden.arrowOutline;
		arrowOutline.PointA = arrow.PointA;
		arrowOutline.PointB = arrow.PointB;
		arrowOutline.PointC = arrow.PointC;
		arrowOutline.Color = parseColor(self, options.offScreenArrowOutlineColor[1], true);
		arrowOutline.Transparency = options.offScreenArrowOutlineColor[2];
	end
end


-- interface
local EspInterface = {
	_hasLoaded = false,
	sharedSettings = {
		textSize = 13,
		textFont = 2,
		limitDistance = false,
		maxDistance = 150,
		useTeamColor = false
	},
	teamSettings = {
		enemy = {
			enabled = false,
			box = false,
			boxColor = { Color3.new(1,0,0), 1 },
			boxOutline = true,
			boxOutlineColor = { Color3.new(), 1 },
			boxFill = false,
			boxFillColor = { Color3.new(1,0,0), 0.5 },
			healthBar = false,
			healthyColor = Color3.new(0,1,0),
			dyingColor = Color3.new(1,0,0),
			healthBarOutline = true,
			healthBarOutlineColor = { Color3.new(), 0.5 },
			healthText = false,
			healthTextColor = { Color3.new(1,1,1), 1 },
			healthTextOutline = true,
			healthTextOutlineColor = Color3.new(),
			box3d = false,
			box3dColor = { Color3.new(1,0,0), 1 },
			name = false,
			nameColor = { Color3.new(1,1,1), 1 },
			nameOutline = true,
			nameOutlineColor = Color3.new(),
			weapon = false,
			weaponColor = { Color3.new(1,1,1), 1 },
			weaponOutline = true,
			weaponOutlineColor = Color3.new(),
			distance = false,
			distanceColor = { Color3.new(1,1,1), 1 },
			distanceOutline = true,
			distanceOutlineColor = Color3.new(),
			tracer = false,
			tracerOrigin = "Bottom",
			tracerColor = { Color3.new(1,0,0), 1 },
			tracerOutline = true,
			tracerOutlineColor = { Color3.new(), 1 },
			offScreenArrow = false,
			offScreenArrowColor = { Color3.new(1,1,1), 1 },
			offScreenArrowSize = 15,
			offScreenArrowRadius = 150,
			offScreenArrowOutline = true,
			offScreenArrowOutlineColor = { Color3.new(), 1 },
			chams = false,
			chamsVisibleOnly = false,
			chamsFillColor = { Color3.new(0.2, 0.2, 0.2), 0.5 },
			chamsOutlineColor = { Color3.new(1,0,0), 0 },
		},
		friendly = {
			enabled = false,
			box = false,
			boxColor = { Color3.new(0,1,0), 1 },
			boxOutline = true,
			boxOutlineColor = { Color3.new(), 1 },
			boxFill = false,
			boxFillColor = { Color3.new(0,1,0), 0.5 },
			healthBar = false,
			healthyColor = Color3.new(0,1,0),
			dyingColor = Color3.new(1,0,0),
			healthBarOutline = true,
			healthBarOutlineColor = { Color3.new(), 0.5 },
			healthText = false,
			healthTextColor = { Color3.new(1,1,1), 1 },
			healthTextOutline = true,
			healthTextOutlineColor = Color3.new(),
			box3d = false,
			box3dColor = { Color3.new(0,1,0), 1 },
			name = false,
			nameColor = { Color3.new(1,1,1), 1 },
			nameOutline = true,
			nameOutlineColor = Color3.new(),
			weapon = false,
			weaponColor = { Color3.new(1,1,1), 1 },
			weaponOutline = true,
			weaponOutlineColor = Color3.new(),
			distance = false,
			distanceColor = { Color3.new(1,1,1), 1 },
			distanceOutline = true,
			distanceOutlineColor = Color3.new(),
			tracer = false,
			tracerOrigin = "Bottom",
			tracerColor = { Color3.new(0,1,0), 1 },
			tracerOutline = true,
			tracerOutlineColor = { Color3.new(), 1 },
			offScreenArrow = false,
			offScreenArrowColor = { Color3.new(1,1,1), 1 },
			offScreenArrowSize = 15,
			offScreenArrowRadius = 150,
			offScreenArrowOutline = true,
			offScreenArrowOutlineColor = { Color3.new(), 1 },
			chams = false,
			chamsVisibleOnly = false,
			chamsFillColor = { Color3.new(0.2, 0.2, 0.2), 0.5 },
			chamsOutlineColor = { Color3.new(0,1,0), 0 }
		}
	}
};

function EspInterface.Load()
	assert(not EspInterface._hasLoaded, "Esp has already been loaded.");

    for i, plr in next, players:GetPlayers() do
        if plr ~= players.LocalPlayer then
            esp.new(plr, EspInterface)
        end
    end

    players.PlayerAdded:Connect(function(plr) 
        if plr ~= players.LocalPlayer then
            esp.new(plr, EspInterface)
        end
    end)

    players.PlayerRemoving:Connect(function(plr) 
        if objects[plr] then
            objects[plr]:Destroy()
        end
    end)

	EspInterface._hasLoaded = true
end

-- game specific functions
function EspInterface.getWeapon(player)
	return "Unknown"
end

function EspInterface.isFriendly(player)
	return player.Team and player.Team == localPlayer.Team
end

function EspInterface.getTeamColor(player)
	return player.Team and player.Team.TeamColor and player.Team.TeamColor.Color
end

function EspInterface.getCharacter(player)
	return player.Character
end

function EspInterface.getHealth(player)
	local character = player and EspInterface.getCharacter(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth
	end
	return 100, 100
end

return EspInterface
