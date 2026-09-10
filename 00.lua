-- ╔══════════════════════════════════════════════════════════════╗
-- ║         CDT All-in-One Controller • Client-Side Script       ║
-- ║           Car Dealership Tycoon | Menu Unificado             ║
-- ╚══════════════════════════════════════════════════════════════╝

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════
-- ▼▼▼  COLOQUE OS NICKS AQUI  ▼▼▼
-- ═══════════════════════════════════════════════════════════════
local allowedUsers = {
    "AntipathicoX",
    "mitonoanimefight",
}
-- ═══════════════════════════════════════════════════════════════
-- ▲▲▲  FIM DA LISTA DE NICKS  ▲▲▲
-- ═══════════════════════════════════════════════════════════════

local function isAllowed()
    local myName = player.Name:lower()
    for _, name in ipairs(allowedUsers) do
        if myName == name:lower() then
            return true
        end
    end
    return false
end

if not isAllowed() then
    player:Kick("Você não tem permissão para usar esse script.")
    return
end

-- ─────────────────────────────────────────────────────────────
-- Paleta ALL BLACK
-- ─────────────────────────────────────────────────────────────
local C = {
    bg         = Color3.fromRGB(8, 8, 8),
    panel      = Color3.fromRGB(16, 16, 16),
    border     = Color3.fromRGB(45, 45, 45),
    title      = Color3.fromRGB(230, 230, 230),
    text       = Color3.fromRGB(220, 220, 220),
    dim        = Color3.fromRGB(140, 140, 140),
    inputBg    = Color3.fromRGB(12, 12, 12),
    divider    = Color3.fromRGB(35, 35, 35),
    on         = Color3.fromRGB(0, 180, 70),
    off        = Color3.fromRGB(40, 40, 40),
    apply      = Color3.fromRGB(35, 35, 35),
    applyHover = Color3.fromRGB(55, 55, 55),
    green      = Color3.fromRGB(0, 170, 60),
    red        = Color3.fromRGB(170, 30, 30),
    mobileBtn  = Color3.fromRGB(25, 25, 25),
}

-- ─────────────────────────────────────────────────────────────
-- Estado global unificado
-- ─────────────────────────────────────────────────────────────
local currentCar = nil
local connections = {}
local sectionRefs = {}

local driftState = { front = { enabled = false }, rear = { enabled = false } }
local driftOriginals = { front = nil, rear = nil }
local motorState = { enabled = false, maxVel = 100, maxTorque = 50000, currentDir = "Parar" }
local steerState = { enabled = false, autoAlign = false, maxAngle = 0.4, speed = 0.5, currentSteer = 0, isA = false, isD = false }

-- ─────────────────────────────────────────────────────────────
-- Lógica Central
-- ─────────────────────────────────────────────────────────────
local function findPlayerCar()
    local folder = workspace:FindFirstChild("Cars")
    if not folder then return nil end
    for _, car in ipairs(folder:GetChildren()) do
        local stats = car:FindFirstChild("Stats")
        if stats then
            local owner = stats:FindFirstChild("Owner")
            if owner and (owner.Value == player.Name or owner.Value == player or owner.Value == player.UserId) then
                return car
            end
        end
    end
    return nil
end

local function isPlayerInCar(car)
    if not car or not player.Character then return false end
    local humanoid = player.Character:FindFirstChild("Humanoid")
    if not humanoid or not humanoid.SeatPart then return false end
    return humanoid.SeatPart:IsDescendantOf(car)
end

local function parseNum(str)
    return tonumber((str:gsub(",", ".")))
end

-- ─────────────────────────────────────────────────────────────
-- DRIFT
-- ─────────────────────────────────────────────────────────────
local WHEEL_PREFIXES = { front = { "FL", "FR" }, rear  = { "RL", "RR" } }

local function getWheels(car, group)
    local result = {}
    for _, obj in ipairs(car:GetChildren()) do
        for _, pfx in ipairs(WHEEL_PREFIXES[group]) do
            if obj.Name == pfx or obj.Name:match("^" .. pfx .. "_%d+$") then
                local w = obj:FindFirstChild("Wheel")
                if w and w:IsA("BasePart") then table.insert(result, w) end
            end
        end
    end
    return result
end

local function readPhysics(wheel)
    local p = wheel.CustomPhysicalProperties
    if typeof(p) == "PhysicalProperties" then
        return { density = p.Density, friction = p.Friction, elasticity = p.Elasticity, frictionWeight = p.FrictionWeight, elasticityWeight = p.ElasticityWeight }
    end
    return { density = 0.7, friction = 0.3, elasticity = 0.5, frictionWeight = 1.0, elasticityWeight = 1.0 }
end

local function applyDrift(group, friction, frictionWeight)
    if not currentCar then return false end
    local wheels = getWheels(currentCar, group)
    if #wheels == 0 then return false end
    if not driftOriginals[group] then driftOriginals[group] = readPhysics(wheels[1]) end
    local base = driftOriginals[group]
    for _, w in ipairs(wheels) do
        w.CustomPhysicalProperties = PhysicalProperties.new(base.density, friction, base.elasticity, frictionWeight, base.elasticityWeight)
    end
    return true
end

local function revertDrift(group)
    if not currentCar or not driftOriginals[group] then return end
    local wheels = getWheels(currentCar, group)
    local o = driftOriginals[group]
    for _, w in ipairs(wheels) do
        w.CustomPhysicalProperties = PhysicalProperties.new(o.density, o.friction, o.elasticity, o.frictionWeight, o.elasticityWeight)
    end
end

-- ─────────────────────────────────────────────────────────────
-- MOTOR
-- ─────────────────────────────────────────────────────────────
local function obterConstraints()
    if not currentCar then return nil end
    local constraints = currentCar:FindFirstChild("Constraints")
    if constraints then
        for _, item in pairs(constraints:GetChildren()) do
            if item.Name == "Front" or item.Name == "Rear" then item.Name = "Rodas" end
        end
        return constraints
    end
    return nil
end

local function aplicarMotor(direcao)
    if not motorState.enabled then return end
    local constraints = obterConstraints()
    if not constraints then return end

    local velocidadeAlvo = 0
    if direcao == "Frente" then velocidadeAlvo = -math.abs(motorState.maxVel)
    elseif direcao == "Re" then velocidadeAlvo = math.abs(motorState.maxVel) end

    if direcao ~= "Parar" and not isPlayerInCar(currentCar) then
        velocidadeAlvo = 0
    end

    for _, motor in pairs(constraints:GetChildren()) do
        if motor.Name == "Rodas" and (motor:IsA("CylindricalConstraint") or motor:IsA("HingeConstraint")) then
            motor.ActuatorType = Enum.ActuatorType.Motor
            motor.MotorMaxTorque = motorState.maxTorque
            motor.AngularVelocity = velocidadeAlvo
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- GUI Helpers
-- ─────────────────────────────────────────────────────────────
local function uiCorner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = parent
end

local function uiStroke(parent, color, thick)
    local s = Instance.new("UIStroke")
    s.Color = color or C.border
    s.Thickness = thick or 1
    s.Parent = parent
end

local function makeDraggable(frame, handle)
    local dragging, dragStart, startPos = false, nil, nil
    handle = handle or frame

    local function beginDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end

    local function endDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end

    handle.InputBegan:Connect(beginDrag)
    handle.InputEnded:Connect(endDrag)

    local conn = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    table.insert(connections, conn)
end

-- ─────────────────────────────────────────────────────────────
-- Construção da GUI
-- ─────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("CDTController")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "CDTController"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

sg:GetPropertyChangedSignal("Parent"):Connect(function()
    if not sg.Parent then
        for _, c in ipairs(connections) do c:Disconnect() end
    end
end)

-- Botão do menu
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 90, 0, 26)
toggleBtn.Position = UDim2.new(0, 14, 0.5, -13)
toggleBtn.BackgroundColor3 = C.bg
toggleBtn.Text = "الانجراف"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.TextColor3 = C.text
toggleBtn.Parent = sg
uiCorner(toggleBtn, 6)
uiStroke(toggleBtn, C.border, 1)
makeDraggable(toggleBtn)

-- Menu
local menu = Instance.new("Frame")
menu.Size = UDim2.new(0, 190, 0, 0)
menu.Position = UDim2.new(0, 110, 0.5, -13)
menu.BackgroundColor3 = C.bg
menu.AutomaticSize = Enum.AutomaticSize.Y
menu.Visible = false
menu.ClipsDescendants = true
menu.Parent = sg
uiCorner(menu, 8)
uiStroke(menu, C.border, 1)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 26)
titleBar.BackgroundColor3 = C.panel
titleBar.Parent = menu
uiCorner(titleBar, 8)

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0.5, 0)
titleFix.Position = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = C.panel
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.new(1, -10, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.Text = "الانجراف"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 12
titleLabel.TextColor3 = C.title
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar
makeDraggable(menu, titleBar)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 0, 280)
scroll.Position = UDim2.new(0, 0, 0, 26)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.Parent = menu

local contentPad = Instance.new("UIPadding")
contentPad.PaddingTop = UDim.new(0, 6)
contentPad.PaddingBottom = UDim.new(0, 8)
contentPad.PaddingLeft = UDim.new(0, 6)
contentPad.PaddingRight = UDim.new(0, 6)
contentPad.Parent = scroll

local contentInner = Instance.new("Frame")
contentInner.Size = UDim2.new(1, -4, 0, 0)
contentInner.BackgroundTransparency = 1
contentInner.AutomaticSize = Enum.AutomaticSize.Y
contentInner.Parent = scroll

local contentList = Instance.new("UIListLayout")
contentList.SortOrder = Enum.SortOrder.LayoutOrder
contentList.Padding = UDim.new(0, 5)
contentList.Parent = contentInner

local function createSection(name, titleTxt, order)
    local sec = Instance.new("Frame")
    sec.BackgroundColor3 = C.panel
    sec.AutomaticSize = Enum.AutomaticSize.Y
    sec.Size = UDim2.new(1, 0, 0, 0)
    sec.LayoutOrder = order
    sec.Parent = contentInner
    uiCorner(sec, 6)
    uiStroke(sec, C.divider, 1)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 7)
    pad.PaddingRight = UDim.new(0, 7)
    pad.Parent = sec

    local secList = Instance.new("UIListLayout")
    secList.SortOrder = Enum.SortOrder.LayoutOrder
    secList.Padding = UDim.new(0, 5)
    secList.Parent = sec

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 16)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = sec

    local secLabel = Instance.new("TextLabel")
    secLabel.BackgroundTransparency = 1
    secLabel.Size = UDim2.new(0.65, 0, 1, 0)
    secLabel.Text = titleTxt
    secLabel.Font = Enum.Font.GothamBold
    secLabel.TextSize = 11
    secLabel.TextColor3 = C.text
    secLabel.TextXAlignment = Enum.TextXAlignment.Left
    secLabel.Parent = header
    
    local togBtn = Instance.new("TextButton")
    togBtn.Size = UDim2.new(0, 34, 0, 14)
    togBtn.Position = UDim2.new(1, -34, 0.5, -7)
    togBtn.BackgroundColor3 = C.off
    togBtn.Text = "OFF"
    togBtn.Font = Enum.Font.GothamBold
    togBtn.TextSize = 9
    togBtn.TextColor3 = C.text
    togBtn.AutoButtonColor = false
    togBtn.Parent = header
    uiCorner(togBtn, 10)

    local function makeRow(lOrder, lblTxt, defaultVal)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 18)
        row.BackgroundTransparency = 1
        row.LayoutOrder = lOrder
        row.Parent = sec

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0.58, 0, 1, 0)
        lbl.Text = lblTxt
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = C.dim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.4, 0, 0.85, 0)
        box.Position = UDim2.new(0.59, 0, 0.075, 0)
        box.BackgroundColor3 = C.inputBg
        box.Text = defaultVal
        box.Font = Enum.Font.GothamMedium
        box.TextSize = 10
        box.TextColor3 = C.text
        box.ClearTextOnFocus = true
        box.Parent = row
        uiCorner(box, 4)
        uiStroke(box, C.border, 1)
        return box
    end

    local function makeSubToggle(lOrder, lblTxt, defaultState, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 18)
        row.BackgroundTransparency = 1
        row.LayoutOrder = lOrder
        row.Parent = sec

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0.58, 0, 1, 0)
        lbl.Text = lblTxt
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = C.dim
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.4, 0, 0.85, 0)
        btn.Position = UDim2.new(0.59, 0, 0.075, 0)
        btn.BackgroundColor3 = defaultState and C.on or C.off
        btn.Text = defaultState and "ON" or "OFF"
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 9
        btn.TextColor3 = C.text
        btn.Parent = row
        uiCorner(btn, 4)
        
        local currentState = defaultState
        btn.MouseButton1Click:Connect(function()
            currentState = not currentState
            btn.Text = currentState and "ON" or "OFF"
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = currentState and C.on or C.off }):Play()
            if callback then callback(currentState) end
        end)
    end

    local applyBtn = Instance.new("TextButton")
    applyBtn.Size = UDim2.new(1, 0, 0, 16)
    applyBtn.BackgroundColor3 = C.apply
    applyBtn.Text = "Aplicar"
    applyBtn.Font = Enum.Font.GothamBold
    applyBtn.TextSize = 10
    applyBtn.TextColor3 = C.text
    applyBtn.LayoutOrder = 10
    applyBtn.Parent = sec
    uiCorner(applyBtn, 4)
    
    local function flash(color)
        TweenService:Create(applyBtn, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
        task.delay(0.4, function()
            TweenService:Create(applyBtn, TweenInfo.new(0.2), { BackgroundColor3 = C.apply }):Play()
        end)
    end

    return sec, togBtn, makeRow, makeSubToggle, applyBtn, flash
end

-- Seções
local _, driftTog, makeDriftRow, _, driftApply, driftFlash = createSection("Drift", "الانجراف (Drift)", 1)
local frictionBox = makeDriftRow(2, "Friction", "0.30")
local fwBox       = makeDriftRow(3, "Weight", "1.00")

local function updateDriftToggle(val)
    driftState.front.enabled, driftState.rear.enabled = val, val
    driftTog.Text = val and "ON" or "OFF"
    TweenService:Create(driftTog, TweenInfo.new(0.2), { BackgroundColor3 = val and C.on or C.off }):Play()
end

driftTog.MouseButton1Click:Connect(function()
    local newVal = not driftState.front.enabled
    updateDriftToggle(newVal)
    if newVal then
        local f, fw = parseNum(frictionBox.Text), parseNum(fwBox.Text)
        if f and fw then applyDrift("front", f, fw) applyDrift("rear", f, fw) end
    else
        revertDrift("front") revertDrift("rear")
    end
end)

driftApply.MouseButton1Click:Connect(function()
    local f, fw = parseNum(frictionBox.Text), parseNum(fwBox.Text)
    if not f or not fw or not currentCar then driftFlash(C.red) return end
    if not driftState.front.enabled then updateDriftToggle(true) end
    local ok1, ok2 = applyDrift("front", f, fw), applyDrift("rear", f, fw)
    driftFlash((ok1 and ok2) and C.green or C.red)
end)
sectionRefs.drift = { setToggle = updateDriftToggle }

local _, motorTog, makeMotorRow, _, motorApply, motorFlash = createSection("Motor", "المحرك (Motor)", 2)
local velBox = makeMotorRow(2, "Velocidade", "100")
local torqueBox = makeMotorRow(3, "Torque", "50000")

local function updateMotorToggle(val)
    motorState.enabled = val
    motorTog.Text = val and "ON" or "OFF"
    TweenService:Create(motorTog, TweenInfo.new(0.2), { BackgroundColor3 = val and C.on or C.off }):Play()
end

motorTog.MouseButton1Click:Connect(function() updateMotorToggle(not motorState.enabled) end)
motorApply.MouseButton1Click:Connect(function()
    local v, t = parseNum(velBox.Text), parseNum(torqueBox.Text)
    if not v or not t then motorFlash(C.red) return end
    motorState.maxVel, motorState.maxTorque = v, t
    if not motorState.enabled then updateMotorToggle(true) end
    motorFlash(C.green)
end)
sectionRefs.motor = { setToggle = updateMotorToggle }

local _, steerTog, makeSteerRow, makeSteerToggle, steerApply, steerFlash = createSection("Steer", "التوجيه (Direção)", 3)
local angleBox = makeSteerRow(2, "Max Angle", "0.40")
local speedBox = makeSteerRow(3, "Speed", "0.50")
makeSteerToggle(4, "Auto-Alinhar", false, function(state) steerState.autoAlign = state end)

local function updateSteerToggle(val)
    steerState.enabled = val
    steerTog.Text = val and "ON" or "OFF"
    TweenService:Create(steerTog, TweenInfo.new(0.2), { BackgroundColor3 = val and C.on or C.off }):Play()
end

steerTog.MouseButton1Click:Connect(function() updateSteerToggle(not steerState.enabled) end)
steerApply.MouseButton1Click:Connect(function()
    local a, s = parseNum(angleBox.Text), parseNum(speedBox.Text)
    if not a or not s then steerFlash(C.red) return end
    steerState.maxAngle, steerState.speed = a, s
    if not steerState.enabled then updateSteerToggle(true) end
    steerFlash(C.green)
end)
sectionRefs.steer = { setToggle = updateSteerToggle }

-- ─────────────────────────────────────────────────────────────
-- BOTÕES MOBILE - DIVIDIDOS EM 2 GRUPOS (maiores + arrastáveis)
-- ─────────────────────────────────────────────────────────────
local isMobile = UserInputService.TouchEnabled

local function createMobileBtn(parent, text, pos, size)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = C.mobileBtn
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 26
    btn.TextColor3 = C.text
    btn.AutoButtonColor = false
    btn.Parent = parent
    uiCorner(btn, 12)
    uiStroke(btn, C.border, 1.5)
    return btn
end

local function bindHold(btn, onPress, onRelease)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            onPress()
            btn.BackgroundColor3 = C.on
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            onRelease()
            btn.BackgroundColor3 = C.mobileBtn
        end
    end)
end

-- === GRUPO 1: Frente e Ré (lado a lado) ===
local motorFrame = Instance.new("Frame")
motorFrame.Size = UDim2.new(0, 180, 0, 70)
motorFrame.Position = UDim2.new(0.5, -90, 1, -160)
motorFrame.BackgroundTransparency = 1
motorFrame.Visible = isMobile
motorFrame.Parent = sg
makeDraggable(motorFrame)

local btnFrente = createMobileBtn(motorFrame, "▲", UDim2.new(0, 0, 0, 0), UDim2.new(0, 85, 0, 70))
local btnRe    = createMobileBtn(motorFrame, "▼", UDim2.new(0, 95, 0, 0), UDim2.new(0, 85, 0, 70))

bindHold(btnFrente, function()
    if isPlayerInCar(currentCar) then
        motorState.currentDir = "Frente"
        aplicarMotor("Frente")
    end
end, function()
    motorState.currentDir = "Parar"
    aplicarMotor("Parar")
end)

bindHold(btnRe, function()
    if isPlayerInCar(currentCar) then
        motorState.currentDir = "Re"
        aplicarMotor("Re")
    end
end, function()
    motorState.currentDir = "Parar"
    aplicarMotor("Parar")
end)

-- === GRUPO 2: Esquerda e Direita (lado a lado) ===
local steerFrame = Instance.new("Frame")
steerFrame.Size = UDim2.new(0, 180, 0, 70)
steerFrame.Position = UDim2.new(0.5, -90, 1, -80)
steerFrame.BackgroundTransparency = 1
steerFrame.Visible = isMobile
steerFrame.Parent = sg
makeDraggable(steerFrame)

local btnEsq = createMobileBtn(steerFrame, "◀", UDim2.new(0, 0, 0, 0), UDim2.new(0, 85, 0, 70))
local btnDir = createMobileBtn(steerFrame, "▶", UDim2.new(0, 95, 0, 0), UDim2.new(0, 85, 0, 70))

bindHold(btnEsq, function()
    if isPlayerInCar(currentCar) then
        steerState.isA = true
    end
end, function()
    steerState.isA = false
end)

bindHold(btnDir, function()
    if isPlayerInCar(currentCar) then
        steerState.isD = true
    end
end, function()
    steerState.isD = false
end)

-- ─────────────────────────────────────────────────────────────
-- Eventos
-- ─────────────────────────────────────────────────────────────
local menuOpen = false
toggleBtn.MouseButton1Click:Connect(function()
    menuOpen = not menuOpen
    menu.Visible = menuOpen
    toggleBtn.Text = menuOpen and "✕" or "الانجراف"
end)

-- Teclado (PC)
local conn1 = UserInputService.InputBegan:Connect(function(input, gp)
    if gp or not isPlayerInCar(currentCar) then return end
    if input.KeyCode == Enum.KeyCode.W then
        motorState.currentDir = "Frente"
        aplicarMotor("Frente")
    elseif input.KeyCode == Enum.KeyCode.S then
        motorState.currentDir = "Re"
        aplicarMotor("Re")
    elseif input.KeyCode == Enum.KeyCode.A then
        steerState.isA = true
    elseif input.KeyCode == Enum.KeyCode.D then
        steerState.isD = true
    end
end)
table.insert(connections, conn1)

local conn2 = UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then
        motorState.currentDir = "Parar"
        aplicarMotor("Parar")
    elseif input.KeyCode == Enum.KeyCode.A then
        steerState.isA = false
    elseif input.KeyCode == Enum.KeyCode.D then
        steerState.isD = false
    end
end)
table.insert(connections, conn2)

-- Loop principal
local updateTick = 0
local wasInCar = false

local conn3 = RunService.RenderStepped:Connect(function(deltaTime)
    updateTick = updateTick + deltaTime
    if updateTick >= 0.75 then
        updateTick = 0
        local found = findPlayerCar()
        if found ~= currentCar then
            currentCar = found
            driftOriginals = { front = nil, rear = nil }
            for _, ref in pairs(sectionRefs) do ref.setToggle(false) end
        end
    end

    local inCar = isPlayerInCar(currentCar)
    
    if wasInCar and not inCar then
        steerState.isA = false
        steerState.isD = false
        if motorState.enabled then aplicarMotor("Parar") end
    end
    wasInCar = inCar

    if steerState.enabled and currentCar then
        local steerDirection = 0
        if inCar then
            if steerState.isA and not steerState.isD then steerDirection = -1
            elseif steerState.isD and not steerState.isA then steerDirection = 1 end
        end

        local slipAngle = 0
        if steerState.autoAlign and inCar then
            local root = currentCar:FindFirstChild("DriveSeat") or currentCar.PrimaryPart or currentCar:FindFirstChildWhichIsA("BasePart", true)
            if root then
                local vel = root.AssemblyLinearVelocity
                if vel.Magnitude > 5 then
                    local localVel = root.CFrame:VectorToObjectSpace(vel)
                    slipAngle = math.atan2(localVel.X, -localVel.Z)
                    slipAngle = math.clamp(slipAngle, -steerState.maxAngle, steerState.maxAngle)
                end
            end
        end

        if steerDirection ~= 0 then
            steerState.currentSteer = math.clamp(steerState.currentSteer + (steerDirection * steerState.speed * deltaTime), -steerState.maxAngle, steerState.maxAngle)
        else
            local target = (steerState.autoAlign and inCar) and slipAngle or 0
            if steerState.currentSteer < target then
                steerState.currentSteer = math.min(target, steerState.currentSteer + (steerState.speed * deltaTime))
            elseif steerState.currentSteer > target then
                steerState.currentSteer = math.max(target, steerState.currentSteer - (steerState.speed * deltaTime))
            end
        end

        local wheels = {currentCar:FindFirstChild("FR"), currentCar:FindFirstChild("FL")}
        for _, wheel in pairs(wheels) do
            if wheel then
                local axel = wheel:FindFirstChild("Axel")
                if axel then
                    local attachment = axel:FindFirstChild("Attachment0")
                    if attachment then
                        local currentAxis = attachment.Axis
                        attachment.Axis = Vector3.new(currentAxis.X, currentAxis.Y, steerState.currentSteer)
                    end
                end
            end
        end
    end
end)
table.insert(connections, conn3)
