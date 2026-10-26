-- Lua, skin.lua, Roblox client; custom ScreenGui renderer.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Skin должен запускаться на клиенте")

local SERVER_URL = "http://127.0.0.1:8000"
local KEY_FILE = "skin_license.txt"
local GUI_NAME = "SkinAtelierV2"
local connections, tweens, themeBindings = {}, {}, {}
local alive, authorized, busy, waiting = true, false, false, false
local toggleKey, activeTab = Enum.KeyCode.RightControl, "catalog"
local state = {motion = true}
local savedMouse, drag, notificationId = nil, nil, 0
local refreshControls, selectTab, setVisible, refreshLayout
local equippedItems = {}

local themes = {
    {name = "Iris", color = Color3.fromRGB(155, 133, 255), bg = Color3.fromRGB(17, 19, 25), side = Color3.fromRGB(21, 23, 31)},
    {name = "Glacier", color = Color3.fromRGB(107, 200, 255), bg = Color3.fromRGB(13, 22, 30), side = Color3.fromRGB(17, 29, 40)},
    {name = "Mint", color = Color3.fromRGB(99, 220, 174), bg = Color3.fromRGB(12, 26, 22), side = Color3.fromRGB(15, 34, 28)},
    {name = "Rose", color = Color3.fromRGB(246, 139, 172), bg = Color3.fromRGB(26, 13, 18), side = Color3.fromRGB(34, 17, 24)},
    {name = "Amber", color = Color3.fromRGB(244, 192, 108), bg = Color3.fromRGB(28, 22, 12), side = Color3.fromRGB(38, 30, 16)},
    {name = "Pearl", color = Color3.fromRGB(208, 218, 235), bg = Color3.fromRGB(22, 22, 22), side = Color3.fromRGB(28, 28, 28)},
}
local palette = {
    bg = Color3.fromRGB(17, 19, 25), side = Color3.fromRGB(21, 23, 31),
    card = Color3.fromRGB(26, 29, 39), raised = Color3.fromRGB(34, 38, 50),
    border = Color3.fromRGB(48, 53, 69), text = Color3.fromRGB(237, 240, 250),
    muted = Color3.fromRGB(143, 151, 173), accent = themes[1].color,
    success = Color3.fromRGB(108, 219, 175), danger = Color3.fromRGB(255, 139, 155),
}
local function connect(signal, fn)
    local connection = signal:Connect(fn)
    table.insert(connections, connection)
    return connection
end
local function create(class, parent, properties)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function corner(object, radius)
    return create("UICorner", object, {CornerRadius = UDim.new(0, radius or 12)})
end
local function bind(object, property, token)
    object[property] = palette[token]
    table.insert(themeBindings, {object, property, token})
end
local function tween(object, properties, duration)
    if not alive then return end
    if tweens[object] then tweens[object]:Cancel() end
    local animation = TweenService:Create(object,
        TweenInfo.new(state.motion and (duration or 0.2) or 0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), properties)
    tweens[object] = animation
    animation:Play()
end
local function panel(parent, position, size, token, radius)
    local object = create("Frame", parent, {
        Position = position, Size = size, BorderSizePixel = 0,
    })
    bind(object, "BackgroundColor3", token or "card")
    corner(object, radius)
    return object
end
local function stroke(object)
    local line = create("UIStroke", object, {Thickness = 1, Transparency = 0.32})
    bind(line, "Color", "border")
    return line
end
local function label(parent, text, x, y, w, h, size, token, bold)
    local object = create("TextLabel", parent, {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
        Size = UDim2.new(w <= 1 and w or 0, w <= 1 and 0 or w, 0, h),
        Text = text, TextSize = size or 14,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    bind(object, "TextColor3", token or "text")
    return object
end
local function button(parent, text, position, size, action, accent)
    local object = create("TextButton", parent, {
        Position = position, Size = size, BorderSizePixel = 0,
        AutoButtonColor = false, Text = text, TextSize = 13, Font = Enum.Font.GothamBold,
    })
    corner(object, 9)
    bind(object, "BackgroundColor3", accent and "accent" or "raised")
    bind(object, "TextColor3", accent and "bg" or "text")
    
    local bStroke = create("UIStroke", object, {Thickness = 1, Transparency = 0.8})
    bStroke.Color = Color3.fromRGB(255, 255, 255)
    connect(object.MouseEnter, function() tween(object, {BackgroundTransparency = 0.18}) end)
    connect(object.MouseLeave, function() tween(object, {BackgroundTransparency = 0}) end)
    connect(object.Activated, action)
    return object
end

local guiParent = player:WaitForChild("PlayerGui")
pcall(function() guiParent = game:GetService("CoreGui") end)
local gui = create("ScreenGui", nil, {
    Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local parentOk = pcall(function() gui.Parent = guiParent end)
if not parentOk then gui.Parent = player:WaitForChild("PlayerGui") end
for _, old in ipairs(gui.Parent:GetChildren()) do
    if old ~= gui and old.Name == GUI_NAME then
        local oldShutdown = old:FindFirstChild("Shutdown")
        if oldShutdown and oldShutdown:IsA("BindableEvent") then oldShutdown:Fire() end
        old:Destroy()
    end
end
local shutdown = create("BindableEvent", gui, {Name = "Shutdown"})

local function icon(parent, kind, x, y, token)
    local root = create("Frame", parent, {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(22, 22),
    })
    local function line(px, py, width, height, rotation)
        local part = create("Frame", root, {
            BorderSizePixel = 0, Position = UDim2.fromOffset(px, py),
            Size = UDim2.fromOffset(width, height), Rotation = rotation or 0,
        })
        bind(part, "BackgroundColor3", token or "muted")
        corner(part, 2)
        return part
    end
    if kind == "skins" then
        local diamond = line(4, 4, 14, 14, 45)
        corner(diamond, 4)
        local cutout = line(8, 8, 6, 6, 45)
        bind(cutout, "BackgroundColor3", "side")
    elseif kind == "binds" then
        line(1, 5, 20, 2); line(1, 17, 20, 2); line(1, 5, 2, 14); line(19, 5, 2, 14)
        for j = 0, 2 do line(5 + j * 5, 9, 2, 2) end
        line(7, 13, 8, 2)
    elseif kind == "themes" then
        for j = 0, 3 do
            local dot = line(3 + (j % 2) * 10, 3 + math.floor(j / 2) * 10, 7, 7)
            corner(dot, 7)
        end
    elseif kind == "close" then
        line(3, 10, 16, 2, 45); line(3, 10, 16, 2, -45)
    elseif kind == "minus" then line(4, 10, 14, 2)
    end
    return root
end

local window = panel(gui, UDim2.fromOffset(0, 0), UDim2.fromOffset(760, 500), "bg", 16)
window.Visible = false
window.Active = true
stroke(window)
local scale = create("UIScale", window, {Scale = 1})
local glow = panel(window, UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 2), "accent", 2)
create("UIGradient", glow, {
    Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(1, 1)}),
})
local top = create("Frame", window, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Active = true})
local logo = panel(top, UDim2.fromOffset(22, 20), UDim2.fromOffset(32, 32), "raised", 10)
icon(logo, "skins", 5, 5, "accent")
label(top, "SKIN", 65, 17, 100, 24, 18, "text", true)
label(top, "ATELIER / 02", 66, 41, 130, 15, 9, "muted", true)
local rigText = label(top, "CLIENT COSMETICS", 220, 28, 250, 18, 10, "muted", true)
local hide = button(top, "", UDim2.new(1, -88, 0, 23), UDim2.fromOffset(30, 30), function() setVisible(false) end)
icon(hide, "minus", 4, 4)
local exit = button(top, "", UDim2.new(1, -50, 0, 23), UDim2.fromOffset(30, 30), function() shutdown:Fire() end)
icon(exit, "close", 4, 4)

local resizeArea = create("TextButton", window, {
    Size = UDim2.fromOffset(25, 25), Position = UDim2.new(1, -25, 1, -25),
    BackgroundTransparency = 1, Text = ""
})
local resizeIcon = create("Frame", resizeArea, {
    Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(10, 10),
    BackgroundColor3 = palette.border, BorderSizePixel = 0, Rotation = 45
})
local resizing, startSize, startPos = false, nil, nil
connect(resizeArea.MouseButton1Down, function()
    resizing = true
    startSize = window.AbsoluteSize
    startPos = Input:GetMouseLocation()
end)
connect(Input.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then resizing = false end
end)
connect(Input.InputChanged, function(input)
    if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = Input:GetMouseLocation()
        local deltaX = currentPos.X - startPos.X
        local deltaY = currentPos.Y - startPos.Y
        local newWidth = math.clamp(startSize.X + deltaX, 400, 1000)
        local newHeight = math.clamp(startSize.Y + deltaY, 300, 800)
        scale.Scale = newWidth / 760
    end
end)

local sidebar = panel(window, UDim2.fromOffset(12, 74), UDim2.new(0, 164, 1, -86), "side", 12)
label(sidebar, "WORKSPACE", 16, 16, 140, 18, 9, "muted", true)
local navButtons, pages = {}, {}
local content = create("Frame", window, {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(194, 86), Size = UDim2.new(1, -216, 1, -108),
})
local navIndicator = panel(sidebar, UDim2.fromOffset(4, 53), UDim2.fromOffset(3, 18), "accent", 3)
local pageTitles = {catalog = {"Каталог", "Выбери вещи из каталога Roblox"}, binds = {"Управление", "Горячие клавиши и анимации"}, themes = {"Оформление", "Цветовые темы интерфейса"}}
local title = label(content, "Каталог", 0, 0, 1, 32, 26, "text", true)
local subtitle = label(content, "Выбери вещи из каталога Roblox", 0, 38, 1, 20, 12, "muted")
for index, info in ipairs({{"catalog", "Каталог"}, {"binds", "Управление"}, {"themes", "Оформление"}}) do
    local key = info[1]
    local btn = button(sidebar, "", UDim2.fromOffset(10, 42 + (index - 1) * 48), UDim2.fromOffset(144, 40), function() selectTab(key) end)
    btn.BackgroundTransparency = 1
    icon(btn, key == "catalog" and "skins" or key, 11, 9)
    label(btn, info[2], 42, 0, 99, 40, 12, "text", true)
    navButtons[key] = {button = btn, index = index}
    local page = create("ScrollingFrame", content, {
        BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 78),
        Size = UDim2.new(1, 0, 1, -78), ScrollBarThickness = 3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
    })
    bind(page, "ScrollBarImageColor3", "accent")
    create("UIPadding", page, {PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 1)})
    create("UIListLayout", page, {Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder})
    pages[key] = page
end
label(sidebar, "LOCAL PROFILE", 16, 0, 140, 16, 9, "muted", true).Position = UDim2.new(0, 16, 1, -77)
local username = label(sidebar, player.DisplayName, 16, 0, 132, 23, 13, "text", true)
username.Position = UDim2.new(0, 16, 1, -57)
local statusDot = panel(sidebar, UDim2.new(0, 17, 1, -24), UDim2.fromOffset(5, 5), "success", 5)
local licenseStatus = label(sidebar, "Ожидание ключа", 28, 0, 128, 16, 10, "muted")
licenseStatus.Position = UDim2.new(0, 28, 1, -30)

local toast = panel(gui, UDim2.new(0.5, -190, 1, -72), UDim2.fromOffset(380, 48), "side", 12)
stroke(toast)
toast.Visible = false
local toastText = label(toast, "", 16, 0, 348, 48, 12)
local function notify(text, errorState)
    if not alive then return end
    notificationId = notificationId + 1
    local id = notificationId
    toastText.Text = text
    toastText.TextColor3 = errorState and palette.danger or palette.text
    toast.Visible = true
    task.delay(3.5, function() if alive and notificationId == id then toast.Visible = false end end)
end

-- Lua, wear_item.lua, Roblox client; replace the original wearItem function.
-- Lua, wear_item.lua, Roblox client; replace the original wearItem function.
-- Lua, wear_item.lua, Roblox client; replace the original wearItem function.
-- Lua, wear_item.lua, Roblox client; replace the original wearItem function.
-- Lua, wear_item.lua, Roblox client; replace the original wearItem function.
local wearItem
local equippedRevision = 0
local hiddenOriginals, activeSlots, slotOrders = {}, {}, {}
local accessoryAssetSlots = {
    [8] = "Hat", [41] = "Hair", [42] = "Face", [43] = "Neck",
    [44] = "Shoulder", [45] = "Front", [46] = "Back", [47] = "Waist",
    [64] = "TShirt", [65] = "Shirt", [66] = "Pants", [67] = "Jacket",
    [68] = "Sweater", [69] = "Shorts", [70] = "LeftShoe", [71] = "RightShoe", [72] = "DressSkirt",
}
local originalAppearance = {detached = {}, properties = {}}
local function remember(object, property, value)
    local saved = originalAppearance.properties[object]
    if not saved then saved = {}; originalAppearance.properties[object] = saved end
    if saved[property] == nil then saved[property] = object[property] end
    object[property] = value
end
local function accessorySlot(item)
    local explicit = item:GetAttribute("SkinSlot")
    if explicit then return explicit end
    if item:IsA("Shirt") then return "ClassicShirt" end
    if item:IsA("Pants") then return "ClassicPants" end
    if item:IsA("ShirtGraphic") then return "ClassicTShirt" end
    if item:IsA("Decal") then return "Face" end
    local handle = item:FindFirstChild("Handle")
    if handle and handle:FindFirstChild("HairAttachment") then return "Accessory:Hair" end
    local ok, kind = pcall(function() return item.AccessoryType.Name end)
    if ok and kind and kind ~= "Unknown" then return "Accessory:" .. kind end
    local attachments = {
        HatAttachment = "Hat", HairAttachment = "Hair",
        FaceFrontAttachment = "Face", FaceCenterAttachment = "Face",
        NeckAttachment = "Neck", BodyFrontAttachment = "Front", BodyBackAttachment = "Back",
        LeftShoulderAttachment = "Shoulder", RightShoulderAttachment = "Shoulder",
        LeftCollarAttachment = "Shoulder", RightCollarAttachment = "Shoulder",
        WaistFrontAttachment = "Waist", WaistBackAttachment = "Waist", WaistCenterAttachment = "Waist",
    }
    if handle then
        for _, part in ipairs(handle:GetChildren()) do
            if part:IsA("Attachment") and attachments[part.Name] then return "Accessory:" .. attachments[part.Name] end
        end
    end
    return "Accessory:Hat"
end
local function hideOriginal(item, slot)
    local saved = hiddenOriginals[item]
    if not saved then
        saved = {slot = slot, parent = item.Parent, properties = {}}
        hiddenOriginals[item] = saved
    end
    for _, part in ipairs(item:GetDescendants()) do
        local properties
        if part:IsA("BasePart") then
            properties = {Transparency = part.Transparency, LocalTransparencyModifier = part.LocalTransparencyModifier}
            part.Transparency, part.LocalTransparencyModifier = 1, 1
        elseif part:IsA("Decal") or part:IsA("Texture") then
            properties = {Transparency = part.Transparency}
            part.Transparency = 1
        elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") or part:IsA("Light") then
            properties = {Enabled = part.Enabled}
            part.Enabled = false
        end
        if properties and not saved.properties[part] then saved.properties[part] = properties end
    end
    -- Исходный Instance остаётся в памяти для сброса, но больше не рендерится в персонаже.
    item.Parent = nil
end
local function hideSlotOriginals(character, slot)
    for _, child in ipairs(character:GetChildren()) do
        if (child:IsA("Accessory") or child:IsA("Hat")) and not child:GetAttribute("SkinAssetId")
            and accessorySlot(child) == slot then
            hideOriginal(child, slot)
        end
    end
end
local function clearEquipped()
    equippedRevision = equippedRevision + 1
    table.clear(activeSlots)
    table.clear(slotOrders)
    for _, item in ipairs(equippedItems) do
        if item.Parent then item:Destroy() end
    end
    table.clear(equippedItems)
    for object, properties in pairs(originalAppearance.properties) do
        for name, value in pairs(properties) do pcall(function() object[name] = value end) end
    end
    for object, parent in pairs(originalAppearance.detached) do
        if parent.Parent then pcall(function() object.Parent = parent end) end
    end
    table.clear(originalAppearance.properties)
    table.clear(originalAppearance.detached)
    for original, saved in pairs(hiddenOriginals) do
        for part, properties in pairs(saved.properties) do
            for name, value in pairs(properties) do pcall(function() part[name] = value end) end
        end
        if saved.parent and saved.parent.Parent then pcall(function() original.Parent = saved.parent end) end
    end
    table.clear(hiddenOriginals)
end
do
    local pending = {}
    local requestOrder = 0
    local scheduleReconcile
    local function destroyRoots(roots)
        for _, root in ipairs(roots) do
            if typeof(root) == "Instance" then root:Destroy() end
        end
    end
    local function extract(roots, assetType)
        local accessory
        local function accepts(object)
            if assetType == 2 then return object:IsA("ShirtGraphic") end
            if assetType == 11 then return object:IsA("Shirt") end
            if assetType == 12 then return object:IsA("Pants") end
            if assetType == 18 then return object:IsA("Decal") end
            if assetType == 17 then return object:IsA("SpecialMesh") or (object:IsA("BasePart") and object.Name == "Head") end
            return object:IsA("Accessory") or object:IsA("Hat")
        end
        for _, root in ipairs(roots) do
            if typeof(root) == "Instance" then
                if accepts(root) then
                    accessory = root
                else
                    for _, child in ipairs(root:GetDescendants()) do
                        if accepts(child) then
                            accessory = child
                            break
                        end
                    end
                end
            end
            if accessory then break end
        end
        if accessory then
            accessory.Parent = nil
            for _, child in ipairs(accessory:GetDescendants()) do
                if child:IsA("LuaSourceContainer") then child:Destroy() end
            end
        end
        for _, root in ipairs(roots) do
            if typeof(root) == "Instance" and root ~= accessory then root:Destroy() end
        end
        return accessory
    end
    local function attempt(callback, assetType)
        local done, ok, result, abandoned = false, false, nil, false
        local worker = task.spawn(function()
            local success, roots = pcall(callback)
            if abandoned then
                if success and type(roots) == "table" then destroyRoots(roots) end
                return
            end
            ok, result, done = success, roots, true
        end)
        local deadline = os.clock() + 15
        while alive and not done and os.clock() < deadline do task.wait(0.05) end
        if not done then
            abandoned = true
            pcall(task.cancel, worker)
            return nil, "тайм-аут или выгрузка меню"
        end
        if not ok then return nil, tostring(result) end
        if type(result) ~= "table" then return nil, "загрузчик не вернул список объектов" end
        local accessory = extract(result, assetType)
        if not accessory then return nil, "asset не содержит объект выбранной категории" end
        return accessory
    end
    local function loadAccessory(id, assetType)
        local item, firstError = attempt(function()
            return game:GetObjects("rbxassetid://" .. id)
        end, assetType)
        if item then return item end
        if not alive then return nil, firstError end
        local secondError
        item, secondError = attempt(function()
            return {game:GetService("InsertService"):LoadAsset(tonumber(id))}
        end, assetType)
        if item then return item end
        return nil, "GetObjects: " .. tostring(firstError)
            .. " | LoadAsset: " .. tostring(secondError)
    end
    local function attach(character, humanoid, accessory)
        local handle = accessory:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then error("у аксессуара нет Handle", 0) end
        for _, child in ipairs(accessory:GetDescendants()) do
            if child:IsA("BasePart") then
                child.Anchored, child.CanCollide, child.CanTouch = false, false, false
                child.Massless = true
            end
        end
        pcall(function() humanoid:AddAccessory(accessory) end)
        local existing = handle:FindFirstChild("AccessoryWeld")
        if existing and existing:IsA("Weld") and existing.Part0 and existing.Part1 then
            if existing.Part0:IsDescendantOf(character) and existing.Part1:IsDescendantOf(character) then return end
        end
        if existing then existing:Destroy() end

        -- На клиенте AddAccessory может не создать weld: совмещаем локальные Attachment.
        local bodyPart, bodyFrame, itemFrame
        for _, attachment in ipairs(handle:GetChildren()) do
            if attachment:IsA("Attachment") then
                for _, part in ipairs(character:GetChildren()) do
                    if part:IsA("BasePart") then
                        local target = part:FindFirstChild(attachment.Name)
                        if target and target:IsA("Attachment") then
                            bodyPart, bodyFrame, itemFrame = part, target.CFrame, attachment.CFrame
                            break
                        end
                    end
                end
            end
            if bodyPart then break end
        end
        if not bodyPart then
            local hasAttachment = handle:FindFirstChildWhichIsA("Attachment") ~= nil
            if hasAttachment then error("на персонаже нет подходящего Attachment", 0) end
            bodyPart = character:FindFirstChild("Head")
            if not bodyPart then error("у персонажа нет Head", 0) end
            bodyFrame, itemFrame = CFrame.new(0, 0.5, 0), accessory.AttachmentPoint
        end
        if accessory:FindFirstChildWhichIsA("WrapLayer", true) then
            error("для этого layered-аксессуара не создано крепление движком", 0)
        end
        handle.CFrame = bodyPart.CFrame * bodyFrame * itemFrame:Inverse()
        local weld = Instance.new("Weld")
        weld.Name, weld.Part0, weld.Part1 = "AccessoryWeld", bodyPart, handle
        weld.C0, weld.C1 = bodyFrame, itemFrame
        weld.Parent = handle
        accessory.Parent = character
    end
    local function hideHeadDecals(head)
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and not child:GetAttribute("SkinAssetId") then remember(child, "Transparency", 1) end
        end
    end
    local function applyWearable(character, humanoid, item, assetType)
        if item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") then
            for _, child in ipairs(character:GetChildren()) do
                if child.ClassName == item.ClassName and not child:GetAttribute("SkinAssetId") then
                    if not originalAppearance.detached[child] then originalAppearance.detached[child] = character end
                    child.Parent = nil
                end
            end
            item.Parent = character
            return
        end
        local head = character:FindFirstChild("Head")
        if assetType == 18 then
            if not head then error("у персонажа нет Head", 0) end
            local destination = activeSlots.Head or head
            hideHeadDecals(head)
            if destination ~= head then
                for _, decal in ipairs(destination:GetChildren()) do
                    if decal:GetAttribute("SkinDefaultFace") then decal:Destroy() end
                end
            end
            item.Name = "face"
            item.Parent = destination
            return
        end
        if assetType == 17 then
            if not head then error("у персонажа нет Head", 0) end
            error("голова должна быть подготовлена до применения", 0)
        end
        attach(character, humanoid, item)
    end
    local function prepareHead(character, payload)
        local head = character:FindFirstChild("Head")
        if not head then error("у персонажа нет Head", 0) end
        local visual
        if payload:IsA("BasePart") then
            visual = payload:Clone()
            for _, child in ipairs(visual:GetDescendants()) do
                if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("Decal") then child:Destroy() end
            end
        else
            visual = Instance.new("Part")
            visual.Size = head.Size
            visual.TopSurface, visual.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
            payload:Clone().Parent = visual
        end
        visual.Name, visual.Color, visual.Material = "SkinVisualHead", head.Color, head.Material
        visual.Anchored, visual.CanCollide, visual.CanTouch, visual.CanQuery, visual.Massless = false, false, false, false, true
        visual.CFrame = head.CFrame
        visual:SetAttribute("SkinSlot", "Head")
        return visual
    end
    local function applyHead(character, visual)
        local head = character:FindFirstChild("Head")
        if not head then error("у персонажа нет Head", 0) end
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and not child:GetAttribute("SkinAssetId") then
                if not activeSlots.Face then
                    local copy = child:Clone()
                    local saved = originalAppearance.properties[child]
                    copy.Transparency = saved and saved.Transparency or child.Transparency
                    copy:SetAttribute("SkinDefaultFace", true)
                    copy.Parent = visual
                end
            end
        end
        local weld = Instance.new("Weld")
        weld.Name, weld.Part0, weld.Part1 = "SkinHeadWeld", head, visual
        weld.Parent = visual
        visual.Parent = character
        if activeSlots.Face then activeSlots.Face.Parent = visual end
        remember(head, "Transparency", 1)
        remember(head, "LocalTransparencyModifier", 1)
        hideHeadDecals(head)
    end
    wearItem = function(assetId, itemName, assetType)
        local id = tostring(assetId):match("^%s*(%d+)%s*$")
        if not id or tonumber(id) <= 0 then notify("Неверный ID аксессуара", true); return end
        if not alive or not authorized then return end
        if pending[id] and pending[id].revision == equippedRevision then notify("Этот предмет уже загружается"); return end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then notify("Дождись появления персонажа", true); return end
        for _, item in ipairs(equippedItems) do
            if item.Parent == character and item:GetAttribute("SkinAssetId") == id then
                notify("Этот предмет уже надет"); return
            end
        end
        local revision = equippedRevision
        requestOrder = requestOrder + 1
        local token = {revision = revision, order = requestOrder}
        pending[id] = token
        notify("Загрузка: " .. (itemName or id))
        task.spawn(function()
            local item
            local ok, message = pcall(function()
                local err
                item, err = loadAccessory(id, assetType)
                if not item then error(err, 0) end
                if not alive or player.Character ~= character or revision ~= equippedRevision then
                    item:Destroy(); item = nil
                    return
                end
                if assetType == 17 then
                    local payload = item
                    item = prepareHead(character, payload)
                    payload:Destroy()
                end
                if (item:IsA("Accessory") or item:IsA("Hat")) and accessoryAssetSlots[assetType] then
                    item:SetAttribute("SkinSlot", "Accessory:" .. accessoryAssetSlots[assetType])
                end
                local slot = accessorySlot(item)
                if token.order < (slotOrders[slot] or 0) then
                    item:Destroy(); item = nil
                    return
                end
                item:SetAttribute("SkinAssetId", id)
                if assetType == 17 then applyHead(character, item)
                else applyWearable(character, humanoid, item, assetType) end
                -- Сначала успешно крепим новую вещь; затем скрываем оригиналы и снимаем прежнюю замену.
                if item:IsA("Accessory") or item:IsA("Hat") then hideSlotOriginals(character, slot) end
                for i = #equippedItems, 1, -1 do
                    local previous = equippedItems[i]
                    if accessorySlot(previous) == slot then
                        previous:Destroy()
                        table.remove(equippedItems, i)
                    end
                end
                activeSlots[slot], slotOrders[slot] = item, token.order
                table.insert(equippedItems, item)
                if scheduleReconcile then scheduleReconcile() end
            end)
            if pending[id] == token then pending[id] = nil end
            if not ok then
                if item then item:Destroy() end
                if alive then
                    local detail = tostring(message)
                    warn("[Skin/Wear] ID " .. id .. " | " .. detail)
                    notify("Не удалось надеть ID " .. id .. ": " .. detail:sub(1, 100), true)
                end
            elseif alive and item then
                notify("Надет: " .. (itemName or id))
            end
        end)
    end
    local watchConnections, watchedItems = {}, {}
    local watchedCharacter, queued = nil, false
    local function stopWatching()
        for _, connection in ipairs(watchConnections) do connection:Disconnect() end
        table.clear(watchConnections)
        table.clear(watchedItems)
        watchedCharacter, queued = nil, false
    end
    local function reconcile(character)
        if not alive or character ~= player.Character then return end
        for slot, item in pairs(activeSlots) do
            if item:IsDescendantOf(character) then
                if slot:sub(1, 10) == "Accessory:" then
                    hideSlotOriginals(character, slot)
                elseif slot == "ClassicShirt" or slot == "ClassicPants" or slot == "ClassicTShirt" then
                    for _, original in ipairs(character:GetChildren()) do
                        if original.ClassName == item.ClassName and original ~= item and not original:GetAttribute("SkinAssetId") then
                            if not originalAppearance.detached[original] then originalAppearance.detached[original] = character end
                            original.Parent = nil
                        end
                    end
                elseif slot == "Face" then
                    local head = character:FindFirstChild("Head")
                    if head then hideHeadDecals(head) end
                elseif slot == "Head" then
                    local head = character:FindFirstChild("Head")
                    if head then
                        remember(head, "Transparency", 1)
                        remember(head, "LocalTransparencyModifier", 1)
                        hideHeadDecals(head)
                    end
                end
            end
        end
    end
    scheduleReconcile = function()
        if queued or not alive or not watchedCharacter then return end
        queued = true
        local character, revision = watchedCharacter, equippedRevision
        task.defer(function()
            if watchedCharacter ~= character then return end
            queued = false
            if equippedRevision == revision then reconcile(character) end
        end)
    end
    local function watchItem(item)
        if watchedItems[item] or not (item:IsA("Accessory") or item:IsA("Hat")) then return end
        watchedItems[item] = true
        local ok, signal = pcall(function() return item:GetPropertyChangedSignal("AccessoryType") end)
        if ok then table.insert(watchConnections, signal:Connect(scheduleReconcile)) end
    end
    local function watchCharacter(character)
        stopWatching()
        watchedCharacter = character
        for _, child in ipairs(character:GetChildren()) do watchItem(child) end
        table.insert(watchConnections, character.ChildAdded:Connect(function(child)
            watchItem(child)
            scheduleReconcile()
        end))
        table.insert(watchConnections, character.DescendantAdded:Connect(scheduleReconcile))
        scheduleReconcile()
    end
    connect(player.CharacterAdded, watchCharacter)
    connect(player.CharacterAppearanceLoaded, function(character)
        if character == watchedCharacter then scheduleReconcile() end
    end)
    connect(shutdown.Event, stopWatching)
    connect(gui.Destroying, stopWatching)
    if player.Character then watchCharacter(player.Character) end
end


-- Lua, catalog.lua, Roblox; replace from «-- Поиск по ID» through loadCatalog().
do
    local TARGET_COUNT, PAGE_SIZE, MAX_PAGES = 100, 30, 8
    local REQUEST_TIMEOUT = 10
    local ERROR_TEXT = "Ошибка загрузки каталога. Проверьте соединение"
    local SOURCES = {
        "http://127.0.0.1:8001",
        "https://catalog.roblox.com",
        "https://catalog.roproxy.com",
    }
    local categories = {
        {key = "accessories", name = "Аксессуары", category = 11, subcategory = 19},
        {key = "hair", name = "Волосы", category = 18, subcategory = 20, assetType = 41},
        {key = "tshirts", name = "Футболки", category = 3, subcategory = 55, assetType = 2},
        {key = "shirts", name = "Рубашки", category = 3, subcategory = 56, assetType = 11},
        {key = "pants", name = "Штаны", category = 3, subcategory = 57, assetType = 12},
        {key = "heads", name = "Головы", category = 18, subcategory = 15, assetType = 17},
        {key = "faces", name = "Лица", category = 18, subcategory = 10, assetType = 18},
    }
    local selected, generation, categoryCache = categories[1], 0, {}
    local chooseCategory
    local fallback = {
        {name = "Dominus Frigidus", id = "21070012"},
        {name = "Sparkle Time Fedora", id = "1029025"},
        {name = "Clockwork's Shades", id = "1031274"},
        {name = "Red Valkyrie", id = "1029044"},
        {name = "Wanwood Antlers", id = "243741536"},
        {name = "Batwing", id = "1031058"},
        {name = "Classic ROBLOX Cap", id = "1029012"},
        {name = "Dominus Vespertilio", id = "1029069"},
        {name = "Pal Hair", id = "1040053"},
        {name = "Korblox Deathspeaker", id = "1051412"},
        {name = "Super Super Happy Face", id = "1029043"},
        {name = "Pink Sparkle Time Fedora", id = "1029039"},
        {name = "Blackvalk", id = "1040001"},
        {name = "Man Face", id = "1032930"},
        {name = "Manga Girl Hair", id = "1061387"},
    }

    local page = pages.catalog
    local disposed, loading = false, false
    local cardConnections = {}
    local function valid()
        return alive and not disposed and page.Parent ~= nil
    end
    local function requestFunction()
        if type(request) == "function" then return request end
        if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
        if type(http_request) == "function" then return http_request end
        if type(http) == "table" and type(http.request) == "function" then return http.request end
    end
    local function get(url)
        local fn = requestFunction()
        if not fn then return nil, "request недоступен" end
        local finished, success, response = false, false, nil
        local worker = task.spawn(function()
            success, response = pcall(fn, {
                Url = url, Method = "GET", Headers = {Accept = "application/json"},
                Timeout = REQUEST_TIMEOUT,
            })
            finished = true
        end)
        local deadline = os.clock() + REQUEST_TIMEOUT
        while not finished and valid() and os.clock() < deadline do task.wait(0.05) end
        if not finished then
            pcall(task.cancel, worker)
            return nil, "Тайм-аут запроса"
        end
        if not success then return nil, "Ошибка request: " .. tostring(response):sub(1, 120) end
        if type(response) ~= "table" then return nil, "request вернул " .. type(response) end
        return response
    end
    local function getPage(url)
        for attempt = 1, 2 do
            if not valid() then return nil, "Каталог закрыт" end
            local response, err = get(url)
            if not response then return nil, err end
            local status = tonumber(response.StatusCode or response.Status)
            if status and status >= 200 and status < 300 then
                local ok, data = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
                if ok and type(data) == "table" and type(data.data) == "table" then return data end
                return nil, "Некорректный JSON каталога"
            end
            if attempt == 1 and (status == 429 or (status and status >= 500 and status <= 599)) then
                local headers = type(response.Headers) == "table" and response.Headers or {}
                local pause = math.clamp(tonumber(headers["Retry-After"] or headers["retry-after"]) or 1, 1, 5)
                task.wait(pause)
            else
                local detail = ""
                local ok, body = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
                if ok and type(body) == "table" and body.error_code then
                    detail = " / " .. tostring(body.error_code)
                end
                return nil, "HTTP " .. tostring(status or "?") .. detail
            end
        end
    end
    local function normalize(item)
        if type(item) ~= "table" then return nil end
        if item.itemType ~= nil and item.itemType ~= "Asset" and item.itemType ~= 1 then return nil end
        local id = tonumber(item.id)
        if not id or id ~= id or id <= 0 or id > 9007199254740991 or id ~= math.floor(id) then return nil end
        if type(item.name) ~= "string" or not item.name:find("%S") then return nil end
        return {id = string.format("%.0f", id), name = item.name, assetType = tonumber(item.assetType)}
    end

    local function fetchCatalog(category, ticket, onProgress)
        local items, seenIds, seenCursors, unavailable, errors = {}, {}, {}, {}, {}
        local cursor, preferredSource, lastError = nil, 1, nil
        for _ = 1, MAX_PAGES do
            if not valid() or ticket ~= generation then return items, "Загрузка отменена" end
            local query = "/v1/search/items/details?Category=" .. category.category .. "&Subcategory=" .. category.subcategory .. "&Limit=" .. PAGE_SIZE
                .. "&SortType=0&IncludeNotForSale=true"
            if cursor then query = query .. "&Cursor=" .. HttpService:UrlEncode(cursor) end
            local data
            for offset = 0, #SOURCES - 1 do
                local index = ((preferredSource - 1 + offset) % #SOURCES) + 1
                if not unavailable[index] then
                    local result, err = getPage(SOURCES[index] .. query)
                    if not valid() or ticket ~= generation then return items, "Загрузка отменена" end
                    if result then
                        data, preferredSource = result, index
                        break
                    end
                    unavailable[index], lastError = true, err
                    table.insert(errors, SOURCES[index] .. ": " .. tostring(err))
                end
            end
            if not data then return items, #errors > 0 and table.concat(errors, " | ") or lastError or "Нет доступных источников" end
            for _, raw in ipairs(data.data) do
                local item = normalize(raw)
                if item and (not category.assetType or item.assetType == category.assetType) and not seenIds[item.id] then
                    seenIds[item.id] = true
                    table.insert(items, item)
                    if #items == TARGET_COUNT then break end
                end
            end
            if onProgress then onProgress(#items) end
            if #items >= TARGET_COUNT then return items end
            local nextCursor = data.nextPageCursor
            if nextCursor == nil or nextCursor == "" then
                return items, #items == 0 and "Пустой каталог" or nil
            end
            if type(nextCursor) ~= "string" or #nextCursor > 4096 or seenCursors[nextCursor] then
                return items, "Некорректный или повторяющийся cursor"
            end
            seenCursors[nextCursor], cursor = true, nextCursor
            task.wait(0.2)
        end
        return items, "Достигнут предел страниц"
    end

    local searchFrame = panel(page, UDim2.new(), UDim2.new(1, 0, 0, 50), "card", 12)
    searchFrame.LayoutOrder = 1
    stroke(searchFrame)
    local searchBox = create("TextBox", searchFrame, {
        Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -120, 0, 30),
        BackgroundColor3 = palette.raised, BorderSizePixel = 0, Text = "",
        PlaceholderText = "Вставь ID вещи (например: 1029025)", PlaceholderColor3 = palette.muted,
        TextColor3 = palette.text, TextSize = 13, Font = Enum.Font.Gotham, ClearTextOnFocus = false,
    })
    corner(searchBox, 6)
    create("UIPadding", searchBox, {PaddingLeft = UDim.new(0, 10)})
    button(searchFrame, "Надеть ID", UDim2.new(1, -100, 0, 10), UDim2.fromOffset(90, 30), function()
        local id = searchBox.Text:match("^%s*(%d+)%s*$")
        if id then wearItem(id, nil, selected.assetType) else notify("Введи числовой ID вещи", true) end
    end, true)

    local categoryFrame = create("Frame", page, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 68), LayoutOrder = 2})
    create("UIGridLayout", categoryFrame, {CellSize = UDim2.new(0.235, 0, 0, 28), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder})
    local categoryButtons = {}
    for index, category in ipairs(categories) do
        local entry = category
        local tab = button(categoryFrame, entry.name, UDim2.new(), UDim2.fromOffset(100, 28), function() chooseCategory(entry) end)
        tab.LayoutOrder, tab.TextSize = index, 10
        categoryButtons[entry.key] = tab
    end

    local statusFrame = panel(page, UDim2.new(), UDim2.new(1, 0, 0, 106), "card", 12)
    statusFrame.LayoutOrder = 3
    stroke(statusFrame)
    local statusLabel = label(statusFrame, "", 12, 5, 1, 96, 11, "muted")
    statusLabel.Size = UDim2.new(1, -120, 0, 96)
    statusLabel.TextWrapped = true
    statusLabel.TextTruncate = Enum.TextTruncate.None

    -- UIListLayout остаётся на странице; UIGridLayout управляет только карточками.
    local grid = create("Frame", page, {
        Name = "CatalogGrid", BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 4,
    })
    local layout = create("UIGridLayout", grid, {
        CellSize = UDim2.new(0.31, 0, 0, 130), CellPadding = UDim2.fromOffset(10, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if valid() then grid.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y) end
    end)
    local function clearCards()
        for _, connection in ipairs(cardConnections) do connection:Disconnect() end
        table.clear(cardConnections)
        for i = #themeBindings, 1, -1 do
            if themeBindings[i][1]:IsDescendantOf(grid) then table.remove(themeBindings, i) end
        end
        for _, child in ipairs(grid:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
    end
    local function render(items)
        if not valid() then return end
        clearCards()
        for i, item in ipairs(items) do
            local btn = create("TextButton", grid, {
                Name = "Asset_" .. item.id, LayoutOrder = i,
                BackgroundColor3 = palette.raised, BorderSizePixel = 0,
                Text = "", AutoButtonColor = false,
            })
            bind(btn, "BackgroundColor3", "raised")
            corner(btn, 10)
            stroke(btn)
            local img = create("ImageLabel", btn, {
                Size = UDim2.new(1, -10, 0.7, 0), Position = UDim2.fromOffset(5, 5),
                BackgroundColor3 = palette.card, BackgroundTransparency = 0.5, BorderSizePixel = 0,
                Image = "rbxthumb://type=Asset&id=" .. item.id .. "&w=150&h=150",
                ScaleType = Enum.ScaleType.Fit,
            })
            bind(img, "BackgroundColor3", "card")
            corner(img, 8)
            local nameLabel = label(btn, item.name, 5, 5, 1, 24, 11, "text", true)
            nameLabel.Position, nameLabel.Size = UDim2.new(0, 5, 0.75, 0), UDim2.new(1, -10, 0, 24)
            nameLabel.TextWrapped, nameLabel.TextSize = true, 10
            local assetId, assetName, assetType = item.id, item.name, item.assetType
            table.insert(cardConnections, btn.Activated:Connect(function()
                if valid() then wearItem(assetId, assetName, assetType) end
            end))
        end
        page.CanvasPosition = Vector2.new(0, 0)
    end
    local reloadButton, resetButton
    local function statusHeight(height)
        statusFrame.Size = UDim2.new(1, 0, 0, height)
        statusLabel.Size = UDim2.new(1, -120, 0, height - 10)
        reloadButton.Position = UDim2.new(1, -102, 0, 6)
        resetButton.Position = UDim2.new(1, -102, 0, height - 30)
        reloadButton.Size, resetButton.Size = UDim2.fromOffset(90, 23), UDim2.fromOffset(90, 23)
    end
    local function loadCatalog()
        if loading or not valid() then return end
        generation = generation + 1
        local ticket, category = generation, selected
        loading = true
        statusHeight(60)
        reloadButton.Text = "Загрузка…"
        statusLabel.Text = category.name .. ": загрузка каталога…"
        statusLabel.TextColor3 = palette.muted
        task.spawn(function()
            local ok, items, err = pcall(fetchCatalog, category, ticket, function(count)
                if valid() and ticket == generation then statusLabel.Text = category.name .. ": " .. count .. " / " .. TARGET_COUNT end
            end)
            if not valid() or ticket ~= generation then return end
            if not ok then err, items = tostring(items), {} end
            loading = false
            reloadButton.Text = "Обновить"
            if err then
                local merged, seen = {}, {}
                -- При частичной ошибке сохраняем загруженные предметы и весь fallback.
                local backup = categoryCache[category.key] or (category.key == "accessories" and fallback or {})
                for _, item in ipairs(backup) do
                    if not seen[item.id] then table.insert(merged, item); seen[item.id] = true end
                end
                for _, item in ipairs(items) do
                    if not seen[item.id] then table.insert(merged, item); seen[item.id] = true end
                end
                render(merged)
                statusHeight(106)
                statusLabel.Text = ERROR_TEXT .. "\n" .. tostring(err)
                statusLabel.TextColor3 = palette.danger
                notify(ERROR_TEXT, true)
                warn("[Skin/Catalog] " .. tostring(err))
            else
                categoryCache[category.key] = items
                render(items)
                statusLabel.Text = category.name .. ": загружено " .. #items
                statusLabel.TextColor3 = palette.success
            end
        end)
    end
    reloadButton = button(statusFrame, "Обновить", UDim2.new(1, -102, 0, 14), UDim2.fromOffset(90, 30), loadCatalog)
    resetButton = button(statusFrame, "Сбросить", UDim2.new(1, -102, 0, 62), UDim2.fromOffset(90, 30), function()
        clearEquipped()
        notify("Исходный скин восстановлен")
    end)
    chooseCategory = function(category)
        generation = generation + 1
        loading, selected = false, category
        for key, tab in pairs(categoryButtons) do
            tab.TextColor3 = key == category.key and palette.accent or palette.text
        end
        render(categoryCache[category.key] or (category.key == "accessories" and fallback or {}))
        loadCatalog()
    end
    page.Destroying:Connect(function()
        disposed = true
        for _, connection in ipairs(cardConnections) do connection:Disconnect() end
        table.clear(cardConnections)
    end)
    chooseCategory(selected)
end


-- Вкладка биндов
local bindCard = panel(pages.binds, UDim2.new(), UDim2.new(1, 0, 0, 112), "card", 12)
stroke(bindCard)
label(bindCard, "Показать / скрыть меню", 16, 14, 320, 24, 14, "text", true)
local keyButton
keyButton = button(bindCard, "RightControl", UDim2.fromOffset(16, 52), UDim2.new(1, -32, 0, 40), function()
    waiting = true
    keyButton.Text = "Нажми клавишу · Esc — отмена"
end)

local clearBtn = button(pages.binds, "Вернуть исходный скин", UDim2.new(), UDim2.new(1, 0, 0, 42), function()
    clearEquipped()
    notify("Исходный скин восстановлен")
end)

-- Вкладка тем
local themeButtons = {}
for index, theme in ipairs(themes) do
    local themeButton
    themeButton = button(pages.themes, "", UDim2.new(), UDim2.new(1, 0, 0, 46), function()
        palette.accent = theme.color
        palette.bg = theme.bg
        palette.side = theme.side
        for _, binding in ipairs(themeBindings) do
            if binding[1].Parent then binding[1][binding[2]] = palette[binding[3]] end
        end
        for i, entry in ipairs(themeButtons) do entry.mark.Text = i == index and "ACTIVE" or "" end
        refreshControls()
    end)
    themeButton.BackgroundColor3 = palette.card
    local swatch = panel(themeButton, UDim2.fromOffset(14, 12), UDim2.fromOffset(22, 22), "accent", 7)
    swatch.BackgroundColor3 = theme.color
    table.remove(themeBindings)
    label(themeButton, theme.name, 50, 0, 140, 46, 13, "text", true)
    local mark = label(themeButton, index == 1 and "ACTIVE" or "", 0, 0, 70, 46, 9, "accent", true)
    mark.Position = UDim2.new(1, -84, 0, 0)
    table.insert(themeButtons, {mark = mark})
end

refreshControls = function()
    keyButton.Text = waiting and "Нажми клавишу · Esc — отмена" or toggleKey.Name
    rigText.Text = "CLIENT COSMETICS  /  " .. ((player.Character and player.Character:FindFirstChild("RightLowerLeg")) and "R15" or "R6")
end
selectTab = function(key)
    activeTab = key
    title.Text, subtitle.Text = pageTitles[key][1], pageTitles[key][2]
    for name, page in pairs(pages) do page.Visible = name == key end
    for name, entry in pairs(navButtons) do tween(entry.button, {BackgroundTransparency = name == key and 0 or 1}) end
    tween(navIndicator, {Position = UDim2.fromOffset(4, 53 + (navButtons[key].index - 1) * 48)})
end

local reopen = button(gui, "SK / Открыть", UDim2.fromOffset(18, 140), UDim2.fromOffset(128, 38), function() setVisible(true) end, true)
reopen.Visible = false
local function releaseMouse()
    if savedMouse then
        Input.MouseBehavior = savedMouse.behavior
        Input.MouseIconEnabled = savedMouse.icon
        savedMouse = nil
    end
end
setVisible = function(visible)
    if not alive then return end
    window.Visible, reopen.Visible = visible, not visible and authorized
    if visible then
        if not savedMouse then savedMouse = {behavior = Input.MouseBehavior, icon = Input.MouseIconEnabled} end
        Input.MouseBehavior = Enum.MouseBehavior.Default
        Input.MouseIconEnabled = true
    else
        waiting, drag = false, nil
        releaseMouse()
        refreshControls()
    end
end

local auth = panel(gui, UDim2.new(0.5, -210, 0.5, -184), UDim2.fromOffset(420, 368), "bg", 16)
stroke(auth)
local authScale = create("UIScale", auth, {Scale = 1})
icon(auth, "skins", 28, 26, "accent")
label(auth, "SKIN / ACCESS", 64, 24, 300, 26, 12, "muted", true)
label(auth, "Твой стиль начинается здесь.", 28, 79, 364, 32, 21, "text", true)
label(auth, "Введи лицензионный ключ для продолжения.", 28, 120, 364, 24, 12, "muted")
local keyInput = create("TextBox", auth, {
    Position = UDim2.fromOffset(28, 168), Size = UDim2.fromOffset(364, 46),
    BackgroundColor3 = palette.card, BorderSizePixel = 0, Text = "",
    PlaceholderText = "XXXX-XXXX-XXXX-XXXX", PlaceholderColor3 = palette.muted,
    TextColor3 = palette.text, TextSize = 14, Font = Enum.Font.Code,
    ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
})
corner(keyInput, 10)
stroke(keyInput)
create("UIPadding", keyInput, {PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)})
local authMessage = label(auth, "Проверка сохранённого ключа…", 28, 224, 364, 36, 11, "muted")
authMessage.TextWrapped = true
local activateButton
local function readKey()
    local ok, value = pcall(function()
        if isfile and readfile and isfile(KEY_FILE) then return readfile(KEY_FILE) end
    end)
    return ok and type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
end
local function hwid()
    local ok, result = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    return ok and type(result) == "string" and result ~= "" and result or tostring(player.UserId)
end
local clientId = hwid()
local function makeRequest(endpoint, key)
    local requestFunction = (syn and syn.request) or (http and http.request) or http_request or request
    if type(requestFunction) ~= "function" then return {ok = false, msg = "HTTP request недоступен в этой среде"} end
    local success, response = pcall(requestFunction, {
        Url = SERVER_URL .. endpoint, Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({key = key, hwid = clientId}),
    })
    if not success or type(response) ~= "table" then return {ok = false, msg = "Сервер 127.0.0.1:8000 недоступен"} end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
    if not decodedOk or type(data) ~= "table" then return {ok = false, msg = "Сервер вернул неверный JSON"} end
    local status = tonumber(response.StatusCode or response.Status)
    if not status or status < 200 or status >= 300 then return {ok = false, msg = tostring(data.msg or "Ошибка HTTP " .. tostring(status))} end
    return {ok = data.ok == true, msg = tostring(data.msg or "Ключ не принят")}
end
local function unlock()
    if not alive then return end
    authorized, busy = true, false
    keyInput.Text = ""
    auth:Destroy()
    licenseStatus.Text = "Лицензия активна"
    selectTab("catalog"); refreshControls(); setVisible(true)
    notify("Готово. Настрой внешность под себя.")
end
local function activate()
    if busy or authorized then return end
    local key = keyInput.Text:match("^%s*(.-)%s*$")
    if key == "" then authMessage.Text = "Введи ключ"; authMessage.TextColor3 = palette.danger; return end
    busy = true
    activateButton.Text = "Проверяем…"
    authMessage.Text, authMessage.TextColor3 = "Соединение с сервером…", palette.muted
    task.spawn(function()
        local result = makeRequest("/activate", key)
        if not alive then return end
        if result.ok then
            local saved = pcall(function()
                assert(type(writefile) == "function", "writefile unavailable")
                writefile(KEY_FILE, key)
            end)
            unlock()
            if not saved then notify("Ключ принят, но сохранить его не удалось", true) end
        else
            busy = false
            activateButton.Text = "Активировать"
            authMessage.Text, authMessage.TextColor3 = result.msg, palette.danger
        end
    end)
end
activateButton = button(auth, "Активировать", UDim2.fromOffset(28, 278), UDim2.fromOffset(364, 44), activate, true)
label(auth, "SKIN ATELIER   /   LOCAL LICENSE SERVER", 28, 337, 364, 14, 9, "muted")
connect(keyInput.FocusLost, function(enter) if enter then activate() end end)
local authClose = button(auth, "×", UDim2.new(1, -44, 0, 18), UDim2.fromOffset(26, 26), function() shutdown:Fire() end)

local function viewport()
    return gui.AbsoluteSize
end
local function clampWindow()
    local size = viewport()
    local width, height = window.AbsoluteSize.X, window.AbsoluteSize.Y
    local x = math.clamp(window.Position.X.Offset, 8, math.max(8, size.X - width - 8))
    local y = math.clamp(window.Position.Y.Offset, 8, math.max(8, size.Y - height - 8))
    window.Position = UDim2.fromOffset(x, y)
end
local centered = false
refreshLayout = function()
    if not alive then return end
    local size = viewport()
    if size.X < 1 or size.Y < 1 then return end
    scale.Scale = math.min(1, (size.X - 16) / 760, (size.Y - 16) / 500)
    if not authorized then
        authScale.Scale = math.min(1, (size.X - 24) / 420, (size.Y - 24) / 368)
        auth.Position = UDim2.fromOffset((size.X - 420 * authScale.Scale) / 2, (size.Y - 368 * authScale.Scale) / 2)
    end
    if not centered then
        window.Position = UDim2.fromOffset((size.X - 760 * scale.Scale) / 2, (size.Y - 500 * scale.Scale) / 2)
        centered = true
    end
    toast.Size = UDim2.fromOffset(math.min(380, size.X - 24), 48)
    toast.Position = UDim2.new(0.5, -toast.Size.X.Offset / 2, 1, -72)
    toastText.Size = UDim2.new(1, -32, 1, 0)
    toastText.TextWrapped = true
    clampWindow()
end
connect(top.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if input.Position.X > top.AbsolutePosition.X + top.AbsoluteSize.X - 100 * scale.Scale then return end
    drag = {input = input, point = Vector2.new(input.Position.X, input.Position.Y), origin = window.Position}
end)
connect(Input.InputChanged, function(input)
    if not drag then return end
    local touch = drag.input.UserInputType == Enum.UserInputType.Touch
    if (touch and input ~= drag.input) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.point
    window.Position = UDim2.fromOffset(drag.origin.X.Offset + delta.X, drag.origin.Y.Offset + delta.Y)
    clampWindow()
end)
connect(Input.InputEnded, function(input)
    if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then drag = nil end
end)
connect(Input.WindowFocusReleased, function() drag = nil end)
connect(Input.InputBegan, function(input, processed)
    if not authorized or Input:GetFocusedTextBox() then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode == Enum.KeyCode.Unknown then return end
    if waiting then
        if input.KeyCode ~= Enum.KeyCode.Escape then toggleKey = input.KeyCode end
        waiting = false; refreshControls(); return
    end
    if not processed and input.KeyCode == toggleKey then setVisible(not window.Visible) end
end)
local function onCharacter(character)
    clearEquipped()
    task.spawn(function()
        character:WaitForChild("Humanoid", 10)
        if not alive or player.Character ~= character then return end
        refreshControls()
    end)
end
connect(player.CharacterAdded, onCharacter)
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), refreshLayout)
local function cleanup()
    if not alive then return end
    alive = false
    clearEquipped()
    releaseMouse()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, animation in pairs(tweens) do animation:Cancel() end
    table.clear(connections); table.clear(tweens)
    gui:Destroy()
end
connect(shutdown.Event, cleanup)
connect(gui.Destroying, cleanup)
selectTab("catalog"); refreshControls(); refreshLayout()
savedMouse = {behavior = Input.MouseBehavior, icon = Input.MouseIconEnabled}
Input.MouseBehavior, Input.MouseIconEnabled = Enum.MouseBehavior.Default, true
task.spawn(function()
    local saved = readKey()
    if saved and saved ~= "" then
        busy = true
        activateButton.Text = "Проверяем…"
        local result = makeRequest("/validate", saved)
        if not alive then return end
        if result.ok then unlock(); return end
        busy = false
        activateButton.Text = "Активировать"
        authMessage.Text, authMessage.TextColor3 = result.msg, palette.danger
    else
        authMessage.Text = "Ключ привязывается к этому устройству."
    end
end)
