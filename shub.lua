-- SON HUB V4 - WindUI Version
-- Single-file Auto Spawn / Auto Bring build
-- Created by SonDepTrai

local WindUI
local cloneref = (cloneref or clonereference or function(instance) return instance end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))

do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)
    if ok then
        WindUI = result
    else
        if RunService:IsStudio() or not writefile then
            WindUI = require(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init"))
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end
    end
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Player = Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local isMobile = UserInputService.TouchEnabled
local screenSize = workspace.CurrentCamera.ViewportSize
local isSmallScreen = screenSize.X < 800 or screenSize.Y < 600 or isMobile

local FarmEnabled = false
local ChestEnabled = false
local SelectedWeapon = nil
local ForceEquip = false
local HakiQuestEnabled = false
local CollectedRings = {}
local CurrentTarget = nil
local AntiAFKEnabled = true
local KillActive = false
local CurrentKillTarget = nil
local FarmMode = "Easy"
local AutoBringCompass = false
local AutoBringOldBook = false
local FlyEnabled = false
local FlySpeed = 200
local FlyConnection = nil
local NoclipEnabled = false
local NoclipConnection = nil
local ESPEnabled = false
local ESPFolder = nil
local ESPConnection = nil
local menuVisible = true
local AutoHakiEnabled = false
local TweenSpeed = 1.0

local AutoSkillEnabled = false
local SelectedSkills = {}
local AvailableSkills = {"Z", "X", "C", "V", "B", "N", "Y", "G", "H", "J", "K", "L", "Q", "T", "F", "U", "P", "E", "R"}

local AutoBringNormalFruit = false
local AutoBringDemonFruit = false

-- Auto Spawn / area farm state
local AutoSpawnEnabled = false
local AutoTeleportToSpawn = true
local AutoBringMobs = false
local AutoSelectNearestSpawn = false
local SelectedSpawnLabel = "None"
local SelectedSpawn = nil
local SpawnTargetFilter = "Selected NPC"
local SpawnScanRadius = 220
local SpawnClusterDistance = 160
local BringStackRadius = 5
local BringHeight = 0
local BringAnchorMode = "Spawn Center"
local BringPattern = "Circle"
local FreezeBroughtNPCs = true
local MaxBringMobs = 10
local BringInterval = 0.25
local FarmTickInterval = 0.08
local FarmDistance = 4
local SpawnRegistry = {}
local SpawnSerialByName = {}
local BroughtNPCs = setmetatable({}, { __mode = "k" })
local SpawnDropdown = nil
local AutoSpawnToggleObject = nil
local LastTeleportedSpawnLabel = nil
local LastSpawnRefresh = 0
local LastBringAt = 0
local MissingSpawnNotified = false

local NormalFruitNames = {
    ["apple"]=true, ["banana"]=true, ["greenapple"]=true,
    ["melon"]=true, ["pumpkin"]=true,
    ["cantaloupe"]=true, ["prickly pear"]=true
}

local RAYLEIGH_POSITION = Vector3.new(-1009.7536010742188, 4011.46484375, 10135.1171875)
local SHOP_EMOTES_POSITION = Vector3.new(1514.7469482421875, 260.38421630859375, 2163.8037109375)

local OldBookCollected = false
local AutoChestForOldBook = false
local IsSearchingOldBook = false
local OldBookMonitoringEnabled = false

local hardcoreMobs = {
    ["Lv2000 Crocodile"] = true, ["Lv20000 Whitebeard"] = true,
    ["Lv2000 Vokun"] = true, ["Lv40 Cave Demon [Weakened]"] = true,
    ["Lv8000 Gunner Captain"] = true, ["Bandits Leader"] = true,
    ["Bart Nospris"] = true, ["Demon Hunter"] = true,
    ["Fallen Captain"] = true, ["Rayleigh"] = true,
}

local easyMobs = {
    ["Lv1Crab"] = true, ["Lvl1 Boar"] = true, ["Lvl11 Boar"] = true, ["Lvl12 Boar"] = true,
    ["Lvl12 Thug"] = true, ["Lvl14 Bandit"] = true, ["Lvl14 Boar"] = true, ["Lvl15 Bandit"] = true,
    ["Lvl15 Boar"] = true, ["Lvl15 Thug"] = true, ["Lvl16 Boar"] = true, ["Lvl17 Thug"] = true,
    ["Lvl186 Cave Demon"] = true, ["Lvl188 Cave Demon"] = true, ["Lv198 Cave Demon"] = true,
    ["Lv20 Thief"] = true, ["Lv22 Thug"] = true, ["Lv23 Thug"] = true,
    ["Lv24 Thug"] = true, ["Lv24 Fred"] = true,
    ["Lv28 Fredde"] = true, ["Lv28 Freyd"] = true,
    ["Lv28 Friedrich"] = true, ["Lv29 Frued"] = true, ["Lv3 Crab"] = true,
    ["Lv30 Thug"] = true, ["Lv32 Fredric"] = true, ["Lv32 Thief"] = true,
    ["Lv34 Freddi"] = true, ["Lv360 Bruno"] = true,
    ["Lv4 Angry Freddy"] = true, ["Lv4 Boar"] = true, ["Lv4 Crab"] = true, ["Lv40 Thug"] = true,
    ["Lv440 Buster"] = true, ["Lv5 Crab"] = true, ["Lv500 Bucky"] = true, ["Lv9 Bandit Traitor"] = true,
}

local mediumMobs = {
    ["Lv219 Cave Demon"] = true, ["Lv2000 Vokun"] = true, ["Lv300 King Crab"] = true,
}

local FruitNames = {
    "Barrier Fruit", "Swim Fruit", "Spring Fruit", "String Fruit",
    "Spin Fruit", "Smelt Fruit", "Snow Fruit", "Slip Fruit",
    "Slow Fruit", "Quake Fruit", "Sand Fruit", "Rumble Fruit",
    "Plasma Fruit", "Phoenix Fruit", "Paw Fruit", "Order Fruit",
    "Magma Fruit", "Ope Fruit", "Luck Fruit", "Love Fruit",
    "Light Fruit", "Hot Fruit", "Gum Fruit", "Gravity Fruit",
    "Gas Fruit", "Float Fruit", "Flare Fruit", "Diamond Fruit",
    "Dark Fruit", "Clone Fruit", "Clear Fruit", "Chop Fruit",
    "Chilly Fruit", "Candy Fruit", "Bomb Fruit", "Buddha Fruit"
}

--[[
    SECURITY NOTE
    Anti-cheat and exploit detection must run on the server. The previous block
    replaced globals such as pcall/task/getgc and attempted to mutate Roblox
    objects, which can break the entire client script. It has intentionally been
    removed from this Studio version.
]]

local function getCharacter()
    return Player.Character or Player.CharacterAdded:Wait()
end

local function getLevelFromName(name)
    if type(name) ~= "string" then return 0 end
    local level = name:match("Lv(%d+)")
    if level then return tonumber(level) or 0 end
    level = name:match("Lvl(%d+)")
    if level then return tonumber(level) or 0 end
    return 0
end

local function isGunslinger(name)
    if type(name) ~= "string" then return false end
    return string.find(name, "Gunslinger") and true or false
end

local function IsValidMobForMode(mobName)
    if type(mobName) ~= "string" then return false end
    if isGunslinger(mobName) then return false end
    if FarmMode == "Easy" then return easyMobs[mobName] == true end
    if FarmMode == "Medium" then
        if hardcoreMobs[mobName] then return false end
        local level = getLevelFromName(mobName)
        return level > 200 or mediumMobs[mobName] == true
    end
    if FarmMode == "Hardcore" then return hardcoreMobs[mobName] == true end
    return false
end

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local DamageEvent = Remotes and Remotes:FindFirstChild("DamageEvent")
local SkillsReceiverEvent = Remotes and Remotes:FindFirstChild("SkillsReceiverEvent")
local KeyBindEvent = Remotes and Remotes:FindFirstChild("KeyBindEvent")

local function getTableKick()
    local char = getCharacter()
    if not char then return nil end
    local tool = char:FindFirstChild("Table Kick")
    if tool then return tool end
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        tool = backpack:FindFirstChild("Table Kick")
        if tool then return tool end
    end
    return nil
end

local function getToolByName(toolName)
    if not toolName then return nil end
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        local tool = backpack:FindFirstChild(toolName)
        if tool and tool:IsA("Tool") then return tool end
    end
    local char = getCharacter()
    return char and char:FindFirstChild(toolName)
end

local function equipWeapon(toolName)
    if not toolName or not ForceEquip then return false end
    local tool = getToolByName(toolName)
    if not tool then return false end
    local char = getCharacter()
    if not char then return false end
    if tool.Parent ~= char then
        pcall(function() tool.Parent = char end)
        task.wait(0.1)
    end
    return tool.Parent == char
end

local function tweenToPosition(position, offset, silent)
    silent = silent or false
    offset = offset or Vector3.new(0, 3, 0)
    local char = getCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    hrp:SetAttribute("AllowTeleport", true)
    
    local targetCFrame = CFrame.new(position + offset)
    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local baseDuration = math.min(0.3 + (distance / 1000), 2.5)
    local duration = baseDuration / TweenSpeed
    
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    
    local completed = false
    tween.Completed:Connect(function()
        completed = true
        hrp:SetAttribute("AllowTeleport", false)
    end)
    
    tween:Play()
    
    local timeout = duration + 0.5
    local start = tick()
    while not completed and tick() - start < timeout do
        task.wait(0.05)
    end
    
    if not completed then
        hrp:SetAttribute("AllowTeleport", false)
        pcall(function()
            hrp.CFrame = targetCFrame
        end)
    end
    
    return true
end

task.spawn(function()
    while task.wait(0.5) do
        if ForceEquip and SelectedWeapon then
            local char = getCharacter()
            if char then
                local currentTool = char:FindFirstChildWhichIsA("Tool")
                if not currentTool or currentTool.Name ~= SelectedWeapon then
                    equipWeapon(SelectedWeapon)
                end
            end
        end
    end
end)

task.spawn(function()
    local function pressKey(key)
        local keyCode = Enum.KeyCode[key]
        if not keyCode then return end
        pcall(function()
            VirtualInput:SendKeyEvent(true, keyCode, false, game)
            task.wait(0.05)
            VirtualInput:SendKeyEvent(false, keyCode, false, game)
        end)
    end
    
    local skillIndex = 1
    local skillKeys = {}
    
    while true do
        task.wait(0.15)
        if not AutoSkillEnabled then 
            skillIndex = 1
            continue 
        end
        
        skillKeys = {}
        for skill, selected in pairs(SelectedSkills) do
            if selected then
                table.insert(skillKeys, skill)
            end
        end
        
        if #skillKeys == 0 then continue end
        
        if skillIndex > #skillKeys then
            skillIndex = 1
        end
        
        pressKey(skillKeys[skillIndex])
        skillIndex = skillIndex + 1
    end
end)

task.spawn(function()
    while true do
        task.wait(2)
        if not AutoHakiEnabled then continue end
        local char = getCharacter()
        if char then
            local observation = char:GetAttribute("Observation")
            if not observation then
                pcall(function()
                    VirtualInput:SendKeyEvent(true, Enum.KeyCode.R, false, game)
                    task.wait(0.1)
                    VirtualInput:SendKeyEvent(false, Enum.KeyCode.R, false, game)
                end)
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.7)
        if not AutoBringNormalFruit then continue end
        local char = getCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        for _, v in pairs(workspace:GetDescendants()) do
            if not v then continue end
            local name = v.Name
            if type(name) ~= "string" then continue end
            local lowerName = string.lower(name)
            if lowerName == "coconut" then continue end
            if NormalFruitNames[lowerName] then
                local part = v:FindFirstChildWhichIsA("BasePart")
                if not part and v:IsA("BasePart") then
                    part = v
                end
                if part then
                    pcall(function()
                        local isHeld = false
                        for _, plr in pairs(Players:GetPlayers()) do
                            if plr.Character and plr.Character:FindFirstChild(v.Name) then
                                isHeld = true
                                break
                            end
                        end
                        if not isHeld then
                            part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                        end
                    end)
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.7)
        if not AutoBringDemonFruit then continue end
        local char = getCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        for _, obj in pairs(Workspace:GetChildren()) do
            if not obj or not obj:IsA("Tool") then continue end
            local name = obj.Name
            if type(name) ~= "string" then continue end
            
            local isHeld = false
            for _, plr in pairs(Players:GetPlayers()) do
                if plr.Character and plr.Character:FindFirstChild(name) then
                    isHeld = true
                    break
                end
            end
            if isHeld then continue end
            
            for _, fn in ipairs(FruitNames) do
                if name == fn then
                    local part = obj:FindFirstChildWhichIsA("BasePart")
                    if not part and obj:IsA("BasePart") then
                        part = obj
                    end
                    if part then
                        pcall(function()
                            part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                        end)
                    end
                    break
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.7)
        if not AutoBringOldBook then continue end
        local char = getCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if not obj then continue end
            local name = obj.Name
            if type(name) ~= "string" then continue end
            local lowerName = string.lower(name)
            if lowerName == "oldbook" or lowerName == "old book" or string.find(lowerName, "oldbook") then
                local isHeld = false
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr.Character and plr.Character:FindFirstChild(obj.Name) then
                        isHeld = true
                        break
                    end
                end
                if isHeld then continue end
                
                local part = obj:FindFirstChildWhichIsA("BasePart")
                if not part and obj:IsA("BasePart") then
                    part = obj
                end
                if part then
                    pcall(function()
                        part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                    end)
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.7)
        if not AutoBringCompass then continue end
        local char = getCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if not obj then continue end
            local name = obj.Name
            if type(name) ~= "string" then continue end
            local lowerName = string.lower(name)
            if lowerName == "compass" or string.find(lowerName, "compass") then
                local isHeld = false
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr.Character and plr.Character:FindFirstChild(obj.Name) then
                        isHeld = true
                        break
                    end
                end
                if isHeld then continue end
                
                local part = obj:FindFirstChildWhichIsA("BasePart")
                if not part and obj:IsA("BasePart") then
                    part = obj
                end
                if part then
                    pcall(function()
                        part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                    end)
                end
            end
        end
    end
end)

local function checkOldBookInWorkspace()
    for _, obj in pairs(Workspace:GetDescendants()) do
        if not obj then continue end
        local name = obj.Name
        if type(name) ~= "string" then continue end
        local lowerName = string.lower(name)
        if lowerName == "oldbook" or lowerName == "old book" or string.find(lowerName, "oldbook") then
            local isHeld = false
            for _, plr in pairs(Players:GetPlayers()) do
                if plr.Character and plr.Character:FindFirstChild(obj.Name) then
                    isHeld = true
                    break
                end
            end
            if not isHeld then
                return true
            end
        end
    end
    return false
end

local function checkOldBookInInventory()
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        for _, obj in pairs(backpack:GetChildren()) do
            if obj:IsA("Tool") then
                local name = obj.Name
                if type(name) ~= "string" then continue end
                local lowerName = string.lower(name)
                if lowerName == "oldbook" or lowerName == "old book" or string.find(lowerName, "oldbook") then
                    return true
                end
            end
        end
    end
    local char = getCharacter()
    if char then
        for _, obj in pairs(char:GetChildren()) do
            if obj:IsA("Tool") then
                local name = obj.Name
                if type(name) ~= "string" then continue end
                local lowerName = string.lower(name)
                if lowerName == "oldbook" or lowerName == "old book" or string.find(lowerName, "oldbook") then
                    return true
                end
            end
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.5)
        
        if not AutoBringOldBook then 
            if OldBookMonitoringEnabled then
                OldBookMonitoringEnabled = false
                if AutoChestForOldBook then
                    ChestEnabled = false
                    AutoChestForOldBook = false
                end
            end
            continue 
        end
        
        OldBookMonitoringEnabled = true
        
        if checkOldBookInInventory() then
            if AutoChestForOldBook then
                ChestEnabled = false
                AutoChestForOldBook = false
            end
            if HakiQuestEnabled then
                tweenToPosition(RAYLEIGH_POSITION, nil, true)
                HakiQuestEnabled = false
                WindUI:Notify({ Title = "OldBook", Content = "Found! Teleported to Rayleigh", Duration = 2 })
            end
            continue
        end
        
        if checkOldBookInWorkspace() then
            continue
        else
            if not ChestEnabled and not AutoChestForOldBook then
                ChestEnabled = true
                AutoChestForOldBook = true
                WindUI:Notify({ Title = "OldBook", Content = "No OldBook found! Auto Chest enabled", Duration = 2 })
            end
        end
    end
end)

local function getAliveFolder()
    return Workspace:FindFirstChild("Alive")
end

local function getNPCParts(model)
    if not model or not model:IsA("Model") then return nil, nil end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    return humanoid, root
end

local function isPlayerCharacter(model)
    if not model or not model:IsA("Model") then return false end
    if model == Player.Character then return true end
    return Players:GetPlayerFromCharacter(model) ~= nil
end

local function isAliveNPC(model)
    if not model or not model:IsA("Model") then return false end
    if isPlayerCharacter(model) then return false end

    local humanoid, root = getNPCParts(model)
    return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function getPlayerRoot()
    local character = Player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function roundPosition(position, step)
    step = step or 10
    return Vector3.new(
        math.floor(position.X / step + 0.5) * step,
        math.floor(position.Y / step + 0.5) * step,
        math.floor(position.Z / step + 0.5) * step
    )
end

local function buildLiveClusters()
    local alive = getAliveFolder()
    if not alive then return {} end

    local clusters = {}
    for _, npc in ipairs(alive:GetChildren()) do
        if not isAliveNPC(npc) then continue end

        local _, root = getNPCParts(npc)
        local selectedCluster = nil

        for _, cluster in ipairs(clusters) do
            if cluster.MobName == npc.Name
                and (cluster.Center - root.Position).Magnitude <= SpawnClusterDistance then
                selectedCluster = cluster
                break
            end
        end

        if selectedCluster then
            selectedCluster.Count += 1
            selectedCluster.Center = selectedCluster.Center:Lerp(root.Position, 1 / selectedCluster.Count)
        else
            table.insert(clusters, {
                MobName = npc.Name,
                Center = root.Position,
                Count = 1,
            })
        end
    end

    table.sort(clusters, function(a, b)
        if a.MobName == b.MobName then
            if math.abs(a.Center.X - b.Center.X) > 1 then
                return a.Center.X < b.Center.X
            end
            return a.Center.Z < b.Center.Z
        end
        return a.MobName < b.MobName
    end)

    return clusters
end

local function mergeSpawnRegistry(liveClusters)
    for _, entry in pairs(SpawnRegistry) do
        entry.LiveCount = 0
        entry.SeenThisScan = false
    end

    for _, cluster in ipairs(liveClusters) do
        local bestEntry = nil
        local bestDistance = math.huge

        for _, entry in pairs(SpawnRegistry) do
            if entry.MobName == cluster.MobName then
                local distance = (entry.Center - cluster.Center).Magnitude
                if distance <= math.max(SpawnClusterDistance, 100) and distance < bestDistance then
                    bestEntry = entry
                    bestDistance = distance
                end
            end
        end

        if bestEntry then
            bestEntry.Center = bestEntry.Center:Lerp(cluster.Center, 0.35)
            bestEntry.LiveCount = cluster.Count
            bestEntry.SeenThisScan = true
            bestEntry.MissedScans = 0
        else
            local serial = (SpawnSerialByName[cluster.MobName] or 0) + 1
            SpawnSerialByName[cluster.MobName] = serial

            local label = string.format("%s | Spawn %d", cluster.MobName, serial)
            SpawnRegistry[label] = {
                Label = label,
                MobName = cluster.MobName,
                Center = roundPosition(cluster.Center, 5),
                LiveCount = cluster.Count,
                SeenThisScan = true,
                MissedScans = 0,
            }
        end
    end

    for label, entry in pairs(SpawnRegistry) do
        if not entry.SeenThisScan then
            entry.MissedScans = (entry.MissedScans or 0) + 1
            if entry.MissedScans >= 5 then
                SpawnRegistry[label] = nil
            end
        end
    end
end

local function getSpawnLabels()
    local labels = { "None" }
    for label in pairs(SpawnRegistry) do
        table.insert(labels, label)
    end
    table.sort(labels, function(a, b)
        if a == "None" then return b ~= "None" end
        if b == "None" then return false end
        return a < b
    end)
    return labels
end

local function selectNearestSpawn()
    local playerRoot = getPlayerRoot()
    if not playerRoot then return nil end

    local nearestLabel = nil
    local nearestDistance = math.huge
    for label, entry in pairs(SpawnRegistry) do
        local distance = (entry.Center - playerRoot.Position).Magnitude
        if distance < nearestDistance then
            nearestLabel = label
            nearestDistance = distance
        end
    end

    if nearestLabel then
        SelectedSpawnLabel = nearestLabel
        SelectedSpawn = SpawnRegistry[nearestLabel]
        if SpawnDropdown then
            pcall(function() SpawnDropdown:Select(nearestLabel) end)
        end
    end

    return nearestLabel
end

local function refreshSpawnList(showNotification)
    mergeSpawnRegistry(buildLiveClusters())
    local labels = getSpawnLabels()

    if SpawnDropdown then
        pcall(function()
            SpawnDropdown:Refresh(labels)
        end)
    end

    if SelectedSpawnLabel ~= "None" and SpawnRegistry[SelectedSpawnLabel] then
        SelectedSpawn = SpawnRegistry[SelectedSpawnLabel]
        if SpawnDropdown then
            pcall(function() SpawnDropdown:Select(SelectedSpawnLabel) end)
        end
    elseif AutoSelectNearestSpawn then
        selectNearestSpawn()
    else
        SelectedSpawnLabel = "None"
        SelectedSpawn = nil
    end

    LastSpawnRefresh = os.clock()

    if showNotification then
        WindUI:Notify({
            Title = "Spawn Scanner",
            Content = string.format("Found %d spawn area(s)", math.max(#labels - 1, 0)),
            Duration = 2,
        })
    end
end

local function getSelectedSpawnNPCs()
    local result = {}
    local spawn = SelectedSpawn
    local alive = getAliveFolder()
    if not spawn or not alive then return result end

    for _, npc in ipairs(alive:GetChildren()) do
        if not isAliveNPC(npc) then continue end

        local _, root = getNPCParts(npc)
        local distanceToSpawn = (root.Position - spawn.Center).Magnitude
        if distanceToSpawn > SpawnScanRadius then continue end

        local accepted = false
        if SpawnTargetFilter == "All NPCs in area" then
            accepted = true
        elseif SpawnTargetFilter == "Farm mode filter" then
            accepted = IsValidMobForMode(npc.Name)
        else
            accepted = npc.Name == spawn.MobName
        end

        if accepted then
            table.insert(result, npc)
        end
    end

    table.sort(result, function(a, b)
        local _, rootA = getNPCParts(a)
        local _, rootB = getNPCParts(b)
        if not rootA then return false end
        if not rootB then return true end
        return (rootA.Position - spawn.Center).Magnitude < (rootB.Position - spawn.Center).Magnitude
    end)

    return result
end

local function freezeNPC(npc)
    local humanoid, root = getNPCParts(npc)

    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    if humanoid then
        if humanoid:GetAttribute("SonHubWalkSpeed") == nil then
            humanoid:SetAttribute("SonHubWalkSpeed", humanoid.WalkSpeed)
            humanoid:SetAttribute("SonHubJumpPower", humanoid.JumpPower)
            humanoid:SetAttribute("SonHubAutoRotate", humanoid.AutoRotate)
            humanoid:SetAttribute("SonHubPlatformStand", humanoid.PlatformStand)
        end

        pcall(function()
            humanoid.AutoRotate = false
            humanoid.PlatformStand = true
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
        end)
    end
end

local function unfreezeNPC(npc)
    local humanoid = npc and npc:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        local walkSpeed = humanoid:GetAttribute("SonHubWalkSpeed")
        local jumpPower = humanoid:GetAttribute("SonHubJumpPower")
        local autoRotate = humanoid:GetAttribute("SonHubAutoRotate")
        local platformStand = humanoid:GetAttribute("SonHubPlatformStand")

        humanoid.WalkSpeed = walkSpeed ~= nil and walkSpeed or 16
        humanoid.JumpPower = jumpPower ~= nil and jumpPower or 50
        humanoid.AutoRotate = autoRotate ~= nil and autoRotate or true
        humanoid.PlatformStand = platformStand ~= nil and platformStand or false

        humanoid:SetAttribute("SonHubWalkSpeed", nil)
        humanoid:SetAttribute("SonHubJumpPower", nil)
        humanoid:SetAttribute("SonHubAutoRotate", nil)
        humanoid:SetAttribute("SonHubPlatformStand", nil)
    end)
end

local function releaseBroughtNPCs()
    for npc in pairs(BroughtNPCs) do
        if npc and npc.Parent then
            unfreezeNPC(npc)
        end
        BroughtNPCs[npc] = nil
    end
end

local function getBringAnchorCFrame()
    if BringAnchorMode == "Player Position" then
        local playerRoot = getPlayerRoot()
        if not playerRoot then return nil end
        return CFrame.new(playerRoot.Position + Vector3.new(0, BringHeight, 0))
    end

    if not SelectedSpawn then return nil end
    return CFrame.new(SelectedSpawn.Center + Vector3.new(0, BringHeight, 0))
end

local function bringSpawnNPCs()
    if not AutoBringMobs or not SelectedSpawn then return end

    local mobs = getSelectedSpawnNPCs()
    if #mobs == 0 then return end

    local limited = {}
    for index = 1, math.min(#mobs, MaxBringMobs) do
        limited[index] = mobs[index]
    end

    local anchor = getBringAnchorCFrame()
    if not anchor then return end

    local activeSet = {}
    for index, npc in ipairs(limited) do
        activeSet[npc] = true

        local offset = Vector3.zero
        if BringPattern == "Circle" and BringStackRadius > 0 then
            local angle = ((index - 1) / math.max(#limited, 1)) * math.pi * 2
            offset = Vector3.new(
                math.cos(angle) * BringStackRadius,
                0,
                math.sin(angle) * BringStackRadius
            )
        elseif BringPattern == "Line" then
            offset = Vector3.new((index - 1) * math.max(BringStackRadius, 1), 0, 0)
        end

        local targetCFrame = anchor + offset

        if FreezeBroughtNPCs then
            freezeNPC(npc)
        else
            local _, root = getNPCParts(npc)
            if root then
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end

        BroughtNPCs[npc] = true
        pcall(function()
            npc:PivotTo(targetCFrame)
        end)
    end

    for npc in pairs(BroughtNPCs) do
        if not activeSet[npc] or not npc.Parent then
            if npc and npc.Parent then
                unfreezeNPC(npc)
            end
            BroughtNPCs[npc] = nil
        end
    end
end

local function teleportToSelectedSpawn()
    if not SelectedSpawn then
        WindUI:Notify({ Title = "Auto Spawn", Content = "Select a spawn first", Duration = 2 })
        return false
    end

    LastTeleportedSpawnLabel = SelectedSpawnLabel
    return tweenToPosition(
        SelectedSpawn.Center,
        Vector3.new(0, 3, FarmDistance + BringStackRadius),
        true
    )
end

local function findMob()
    local alive = getAliveFolder()
    if not alive then return nil, nil, nil end

    local candidates
    if AutoSpawnEnabled and SelectedSpawn then
        candidates = getSelectedSpawnNPCs()
    else
        candidates = alive:GetChildren()
    end

    local playerRoot = getPlayerRoot()
    if not playerRoot then return nil, nil, nil end

    local bestMob, bestHumanoid, bestRoot = nil, nil, nil
    local bestDistance = math.huge
    local lowestLevel = math.huge

    for _, npc in ipairs(candidates) do
        if not isAliveNPC(npc) then continue end
        if not AutoSpawnEnabled and not IsValidMobForMode(npc.Name) then continue end

        local humanoid, root = getNPCParts(npc)
        local level = getLevelFromName(npc.Name)
        local referencePosition = SelectedSpawn and SelectedSpawn.Center or playerRoot.Position
        local distance = (root.Position - referencePosition).Magnitude

        if AutoSpawnEnabled then
            if distance < bestDistance then
                bestDistance = distance
                bestMob, bestHumanoid, bestRoot = npc, humanoid, root
            end
        elseif level < lowestLevel or (level == lowestLevel and distance < bestDistance) then
            lowestLevel = level
            bestDistance = distance
            bestMob, bestHumanoid, bestRoot = npc, humanoid, root
        end
    end

    return bestMob, bestHumanoid, bestRoot
end

local attackCooldown = 0
local function attack()
    local now = os.clock()
    if now - attackCooldown < 0.08 then return end
    attackCooldown = now

    local character = Player.Character
    local tool = character and character:FindFirstChildWhichIsA("Tool")

    if tool then
        pcall(function() tool:Activate() end)
    end

    -- Keep only the known call shape. Do not spam several incompatible signatures.
    if DamageEvent and tool then
        pcall(function()
            DamageEvent:FireServer("Click", tool, CFrame.new())
        end)
    end
end

local function stopFarmTarget()
    if CurrentTarget then
        unfreezeNPC(CurrentTarget)
        CurrentTarget = nil
    end
    releaseBroughtNPCs()
end

task.spawn(function()
    while task.wait(FarmTickInterval) do
        if os.clock() - LastSpawnRefresh >= 3 then
            refreshSpawnList(false)
        end

        if not FarmEnabled then
            if CurrentTarget or next(BroughtNPCs) then
                stopFarmTarget()
            end
            continue
        end

        if AutoSpawnEnabled then
            if not SelectedSpawn then
                if AutoSelectNearestSpawn then
                    selectNearestSpawn()
                end

                if not SelectedSpawn then
                    if not MissingSpawnNotified then
                        MissingSpawnNotified = true
                        WindUI:Notify({
                            Title = "Auto Spawn",
                            Content = "No spawn selected. Open Farm > Spawn Scanner.",
                            Duration = 3,
                        })
                    end
                    continue
                end
            end

            MissingSpawnNotified = false

            if AutoTeleportToSpawn and LastTeleportedSpawnLabel ~= SelectedSpawnLabel then
                task.spawn(teleportToSelectedSpawn)
            end

            if AutoBringMobs and os.clock() - LastBringAt >= BringInterval then
                LastBringAt = os.clock()
                bringSpawnNPCs()
            end
        end

        local mob, humanoid, root = findMob()
        if not mob or not humanoid or not root then
            if CurrentTarget then
                unfreezeNPC(CurrentTarget)
                CurrentTarget = nil
            end
            continue
        end

        if CurrentTarget ~= mob then
            if CurrentTarget and not BroughtNPCs[CurrentTarget] then
                unfreezeNPC(CurrentTarget)
            end
            CurrentTarget = mob
        end

        freezeNPC(CurrentTarget)

        local playerRoot = getPlayerRoot()
        if playerRoot then
            pcall(function()
                local targetPosition = root.Position + Vector3.new(0, 0, FarmDistance)
                playerRoot.CFrame = CFrame.lookAt(targetPosition, root.Position)
            end)
        end

        attack()

        if humanoid.Health <= 0 then
            BroughtNPCs[CurrentTarget] = nil
            unfreezeNPC(CurrentTarget)
            CurrentTarget = nil
        end
    end
end)

task.spawn(function()
    while task.wait(0.2) do
        if not ChestEnabled then continue end
        for _, v in ipairs(workspace:GetDescendants()) do
            if not ChestEnabled then break end
            if v and v.Name == "TreasureChest" and v:IsA("Model") then
                local pos = v:FindFirstChild("Pos1", true) or v:FindFirstChild("PrimaryPart")
                if pos then
                    local char = getCharacter()
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        pcall(function()
                            hrp.CFrame = pos.CFrame + Vector3.new(0, 3, 0)
                        end)
                    end
                    task.wait(0.5)
                end
            end
        end
    end
end)

local function getAllRings()
    local rings = {}
    local mapFolder = workspace:FindFirstChild("MapFolder")
    if not mapFolder then return rings end
    local ringsFolder = mapFolder:FindFirstChild("Rings")
    if not ringsFolder then return rings end
    for i = 1, 8 do
        local ringName = "Rayleigh Ring " .. i
        for _, v in pairs(ringsFolder:GetChildren()) do
            if v and v.Name == ringName then
                local primary = v:FindFirstChild("PrimaryPart") or v:FindFirstChild("HumanoidRootPart") or v:FindFirstChildWhichIsA("Part")
                if primary then
                    table.insert(rings, {Name = ringName, Order = i, CFrame = primary.CFrame, Object = v, Primary = primary})
                else
                    table.insert(rings, {Name = ringName, Order = i, CFrame = v.CFrame, Object = v, Primary = v})
                end
                break
            end
        end
    end
    table.sort(rings, function(a, b) return a.Order < b.Order end)
    return rings
end

local function teleportToRayleigh()
    tweenToPosition(RAYLEIGH_POSITION, nil, true)
end

local function teleportToShopEmotes()
    tweenToPosition(SHOP_EMOTES_POSITION, nil, true)
end

local currentRingIndex = 1
local RingTweenActive = false
local RingCollecting = false

task.spawn(function()
    while true do
        task.wait(0.5)
        if not HakiQuestEnabled then 
            currentRingIndex = 1
            RingCollecting = false
            continue 
        end
        
        if RingCollecting then
            task.wait(0.2)
            continue
        end
        
        local rings = getAllRings()
        if #rings == 0 then
            task.wait(1)
            continue
        end
        
        local allCollected = true
        for _, ring in ipairs(rings) do
            if not CollectedRings[ring.Name] then
                allCollected = false
                break
            end
        end
        
        if allCollected then
            teleportToRayleigh()
            HakiQuestEnabled = false
            CollectedRings = {}
            currentRingIndex = 1
            RingCollecting = false
            WindUI:Notify({ Title = "Haki Quest", Content = "Completed!", Duration = 3 })
            continue
        end
        
        local targetRing = nil
        for _, ring in ipairs(rings) do
            if not CollectedRings[ring.Name] then
                targetRing = ring
                break
            end
        end
        
        if not targetRing then
            task.wait(0.5)
            continue
        end
        
        if targetRing.Object and targetRing.Object.Parent and targetRing.CFrame and not RingTweenActive then
            RingCollecting = true
            local char = getCharacter()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                RingTweenActive = true
                
                local targetPos = targetRing.CFrame.Position + Vector3.new(0, 2.5, 0)
                local duration = 0.4 / TweenSpeed
                local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(targetPos)})
                pcall(function() tween:Play() end)
                task.wait(duration + 0.1)
                
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    for i = 1, 3 do
                        pcall(function()
                            hum.Jump = true
                            task.wait(0.08)
                            hum.Jump = false
                            task.wait(0.08)
                        end)
                    end
                end
                
                task.wait(0.2)
                CollectedRings[targetRing.Name] = true
                local ringNum = 0
                for i, r in ipairs(rings) do
                    if r.Name == targetRing.Name then
                        ringNum = i
                        break
                    end
                end
                WindUI:Notify({ Title = "Ring", Content = "Collected " .. targetRing.Name .. " (" .. ringNum .. "/" .. #rings .. ")", Duration = 2 })
                RingTweenActive = false
                RingCollecting = false
                task.wait(0.3)
            else
                RingCollecting = false
            end
        end
    end
end)

local afkConnection = nil
local function setupAntiAFK()
    if afkConnection then afkConnection:Disconnect() end
    if AntiAFKEnabled then
        afkConnection = Player.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end
setupAntiAFK()

local FlyAttachment = nil
local FlyLinearVelocity = nil
local FlyBodyGyro = nil

local function toggleFly()
    FlyEnabled = not FlyEnabled
    if FlyEnabled then
        local char = getCharacter()
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        
        local animate = char:FindFirstChild("Animate")
        if animate then pcall(function() animate.Disabled = true end) end
        
        pcall(function()
            char.Humanoid.PlatformStand = true
            char.Humanoid.AutoRotate = false
            char.Humanoid.WalkSpeed = 0
            char.Humanoid.JumpPower = 0
        end)
        
        if FlyLinearVelocity then pcall(function() FlyLinearVelocity:Destroy() end) end
        if FlyBodyGyro then pcall(function() FlyBodyGyro:Destroy() end) end
        if FlyAttachment then pcall(function() FlyAttachment:Destroy() end) end
        
        FlyAttachment = Instance.new("Attachment")
        FlyAttachment.Parent = root
        
        FlyLinearVelocity = Instance.new("LinearVelocity")
        FlyLinearVelocity.Parent = root
        FlyLinearVelocity.Attachment0 = FlyAttachment
        FlyLinearVelocity.MaxForce = math.huge
        FlyLinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        FlyLinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
        FlyLinearVelocity.VectorVelocity = Vector3.new(0, 0, 0)
        
        FlyBodyGyro = Instance.new("BodyGyro")
        FlyBodyGyro.Parent = root
        FlyBodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        FlyBodyGyro.D = 5000
        FlyBodyGyro.P = 50000
        FlyBodyGyro.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 1, 0))
        
        if FlyConnection then FlyConnection:Disconnect() end
        FlyConnection = RunService.Heartbeat:Connect(function()
            if not FlyEnabled then return end
            local currentRoot = char:FindFirstChild("HumanoidRootPart")
            if not currentRoot then return end
            
            local moveX = 0
            local moveZ = 0
            local moveY = 0
            local cam = workspace.CurrentCamera
            
            if isMobile then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    local dir = hum.MoveDirection
                    if dir.Magnitude > 0.1 then
                        local flatLook = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
                        local flatRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
                        moveX = dir:Dot(flatRight)
                        moveZ = dir:Dot(flatLook)
                    end
                    if hum.Jump then moveY = 1 end
                end
            else
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveZ = moveZ + 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveZ = moveZ - 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveX = moveX - 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveX = moveX + 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveY = moveY + 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveY = moveY - 1 end
            end
            
            local look = cam.CFrame.LookVector
            local right = cam.CFrame.RightVector
            local up = cam.CFrame.UpVector
            
            local velocity = (right * moveX + look * moveZ + up * moveY) * FlySpeed
            FlyLinearVelocity.VectorVelocity = velocity
            
            FlyBodyGyro.CFrame = CFrame.new(currentRoot.Position, currentRoot.Position + Vector3.new(0, 1, 0))
        end)
    else
        if FlyConnection then FlyConnection:Disconnect(); FlyConnection = nil end
        if FlyLinearVelocity then pcall(function() FlyLinearVelocity:Destroy() end) end
        if FlyBodyGyro then pcall(function() FlyBodyGyro:Destroy() end) end
        if FlyAttachment then pcall(function() FlyAttachment:Destroy() end) end
        
        local char = getCharacter()
        if char then
            local animate = char:FindFirstChild("Animate")
            if animate then pcall(function() animate.Disabled = false end) end
            pcall(function()
                char.Humanoid.PlatformStand = false
                char.Humanoid.AutoRotate = true
                char.Humanoid.WalkSpeed = 16
                char.Humanoid.JumpPower = 50
            end)
        end
    end
end

local function toggleNoclip()
    NoclipEnabled = not NoclipEnabled
    if NoclipEnabled then
        if NoclipConnection then NoclipConnection:Disconnect() end
        NoclipConnection = RunService.Stepped:Connect(function()
            if not NoclipEnabled then return end
            local char = getCharacter()
            if not char then return end
            for _, v in pairs(char:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide then
                    pcall(function() v.CanCollide = false end)
                end
            end
        end)
    else
        if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
        local char = getCharacter()
        if char then
            for _, v in pairs(char:GetDescendants()) do
                if v:IsA("BasePart") then
                    pcall(function() v.CanCollide = true end)
                end
            end
        end
    end
end

local function toggleESP()
    ESPEnabled = not ESPEnabled
    if ESPEnabled then
        if ESPFolder then pcall(function() ESPFolder:Destroy() end) end
        ESPFolder = Instance.new("Folder")
        ESPFolder.Name = "ESP_Players"
        ESPFolder.Parent = workspace
        if ESPConnection then ESPConnection:Disconnect() end
        ESPConnection = RunService.RenderStepped:Connect(function()
            if not ESPEnabled then return end
            for _, obj in pairs(ESPFolder:GetChildren()) do
                pcall(function() obj:Destroy() end)
            end
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= Player and player.Character then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    if root and hum then
                        pcall(function()
                            local bill = Instance.new("BillboardGui")
                            bill.Name = "ESP_" .. player.Name
                            bill.Parent = ESPFolder
                            bill.Adornee = root
                            bill.Size = UDim2.new(0, 150, 0, 40)
                            bill.StudsOffset = Vector3.new(0, 3, 0)
                            bill.AlwaysOnTop = true
                            local label = Instance.new("TextLabel")
                            label.Parent = bill
                            label.Size = UDim2.new(1, 0, 1, 0)
                            label.BackgroundTransparency = 1
                            label.Text = player.Name .. " ❤️" .. math.floor(hum.Health)
                            label.TextColor3 = Color3.new(1, 0, 0)
                            label.TextScaled = true
                            label.Font = Enum.Font.GothamBold
                            label.TextStrokeTransparency = 0.3
                        end)
                    end
                end
            end
        end)
    else
        if ESPConnection then ESPConnection:Disconnect(); ESPConnection = nil end
        if ESPFolder then pcall(function() ESPFolder:Destroy() end) end
    end
end

local function GetPlayerList()
    local list = {"None"}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Player then
            table.insert(list, plr.Name)
        end
    end
    return list
end

local Camera = workspace.CurrentCamera
local Spectating = false
local CurrentSpectatePlayer = nil
local OriginalCameraSubject = nil
local OriginalCameraType = nil
local SelectedPlayerName = "None"

local function StartSpectate(playerName)
    local target = Players:FindFirstChild(playerName)
    if not target or not target.Character then
        WindUI:Notify({ Title = "Spectator", Content = "Player not found!", Duration = 2 })
        return false
    end
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hum then
        WindUI:Notify({ Title = "Spectator", Content = "No humanoid!", Duration = 2 })
        return false
    end
    Spectating = true
    CurrentSpectatePlayer = target
    OriginalCameraSubject = Camera.CameraSubject
    OriginalCameraType = Camera.CameraType
    pcall(function()
        Camera.CameraType = Enum.CameraType.Custom
        Camera.CameraSubject = hum
    end)
    WindUI:Notify({ Title = "Spectator", Content = "Watching " .. target.Name, Duration = 2 })
    return true
end

local function StopSpectate()
    if not Spectating then return end
    Spectating = false
    CurrentSpectatePlayer = nil
    pcall(function()
        if OriginalCameraSubject then
            Camera.CameraType = OriginalCameraType
            Camera.CameraSubject = OriginalCameraSubject
        else
            local char = getCharacter()
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                Camera.CameraType = Enum.CameraType.Custom
                Camera.CameraSubject = hum
            end
        end
    end)
    WindUI:Notify({ Title = "Spectator", Content = "Stopped", Duration = 2 })
end

local function TeleportToPlayer(playerName)
    local target = Players:FindFirstChild(playerName)
    if not target or not target.Character then
        WindUI:Notify({ Title = "Teleport", Content = "Player not found!", Duration = 2 })
        return
    end
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        WindUI:Notify({ Title = "Teleport", Content = "No root part!", Duration = 2 })
        return
    end
    tweenToPosition(targetRoot.Position, Vector3.new(0, 1.5, 1.5), true)
    WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. target.Name, Duration = 2 })
end

local KillLoopConnection = nil

local function StartKill(playerName)
    local target = Players:FindFirstChild(playerName)
    if not target then
        WindUI:Notify({ Title = "Kill", Content = "Player not found!", Duration = 2 })
        return false
    end
    if not target.Character then
        WindUI:Notify({ Title = "Kill", Content = "Target has no character!", Duration = 2 })
        return false
    end
    CurrentKillTarget = target
    KillActive = true
    WindUI:Notify({ Title = "Kill", Content = "Targeting " .. target.Name, Duration = 2 })
    
    if KillLoopConnection then KillLoopConnection:Disconnect() end
    KillLoopConnection = RunService.Heartbeat:Connect(function()
        if not KillActive or not CurrentKillTarget then
            if KillLoopConnection then KillLoopConnection:Disconnect(); KillLoopConnection = nil end
            return
        end
        
        local target = CurrentKillTarget
        if not target or not target.Character then
            WindUI:Notify({ Title = "Kill", Content = "Target lost!", Duration = 2 })
            KillActive = false
            if killToggleObj then killToggleObj:SetValue(false) end
            if KillLoopConnection then KillLoopConnection:Disconnect(); KillLoopConnection = nil end
            return
        end
        
        local targetHum = target.Character:FindFirstChildOfClass("Humanoid")
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
        
        if not targetHum or not targetRoot or targetHum.Health <= 0 then
            WindUI:Notify({ Title = "Kill", Content = "Target eliminated!", Duration = 2 })
            KillActive = false
            if killToggleObj then killToggleObj:SetValue(false) end
            CurrentKillTarget = nil
            if KillLoopConnection then KillLoopConnection:Disconnect(); KillLoopConnection = nil end
            return
        end
        
        local myChar = getCharacter()
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        
        if myRoot and targetRoot then
            pcall(function()
                myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 1.5)
            end)
        end
        
        attack()
    end)
    
    return true
end

local function StopKill()
    KillActive = false
    CurrentKillTarget = nil
    if KillLoopConnection then 
        KillLoopConnection:Disconnect()
        KillLoopConnection = nil
    end
    WindUI:Notify({ Title = "Kill", Content = "Stopped", Duration = 2 })
end

local AutoFishingEnabled = false
local AutoMinigameEnabled = false
local FishingState = "IDLE"
local CurrentBobber = nil
local MinigameActive = false
local FishingEvent = nil

local function GetCurrentRod()
    local char = getCharacter()
    if char then
        for _, tool in pairs(char:GetChildren()) do
            if tool:IsA("Tool") and (tool.Name:find("Rod") or tool.Name:find("Fishing") or tool.Name:find("Super Rod") or tool.Name:find("Sturdy Rod") or tool.Name:find("Wood Rod")) then
                return tool
            end
        end
    end
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in pairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and (tool.Name:find("Rod") or tool.Name:find("Fishing") or tool.Name:find("Super Rod") or tool.Name:find("Sturdy Rod") or tool.Name:find("Wood Rod")) then
                return tool
            end
        end
    end
    return nil
end

local function EquipRod()
    local rod = GetCurrentRod()
    if rod and rod.Parent == Player.Backpack then
        pcall(function() Player.Character.Humanoid:EquipTool(rod) end)
        task.wait(0.3)
        return true
    end
    return rod ~= nil
end

local function ActivateRod()
    local rod = GetCurrentRod()
    if rod and rod.Parent == Player.Character then
        pcall(function() rod:Activate() end)
        return true
    end
    return false
end

local function ClickSelectedButton()
    if not AutoMinigameEnabled or not MinigameActive then return end
    local selected = GuiService.SelectedObject
    if selected and selected:IsA("TextButton") and selected.Visible then
        pcall(function()
            selected:Fire()
            selected:Activate()
        end)
    end
end

local function SetupMinigameListener()
    local minigameGui = Player.PlayerGui:FindFirstChild("FishingMinigame")
    if not minigameGui or not minigameGui.Enabled then return false end
    if MinigameActive then return true end
    MinigameActive = true
    minigameGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not minigameGui.Enabled then MinigameActive = false end
    end)
    minigameGui.AncestryChanged:Connect(function(_, parent)
        if parent == nil then MinigameActive = false end
    end)
    return true
end

local function SetupSparklesListener(bobber)
    if CurrentBobber == bobber then return end
    CurrentBobber = bobber
    bobber.ChildAdded:Connect(function(child)
        if child.Name == "Sparkles" and FishingState == "WAIT_BOBBER" then
            FishingState = "REELING"
            ActivateRod()
            task.wait(0.5)
            FishingState = "IDLE"
        end
    end)
end

task.spawn(function()
    FishingEvent = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("FishingEvent")
    if FishingEvent then
        FishingEvent.OnClientEvent:Connect(function(action, ...)
            if action == "FishingLaunched" then
                FishingState = "WAIT_BOBBER"
            elseif action == "FishingReeled" then
                FishingState = "IDLE"
            elseif action == "FishingMinigame" then
                FishingState = "MINIGAME"
                task.wait(0.3)
                SetupMinigameListener()
            end
        end)
    end
    Workspace.ChildAdded:Connect(function(child)
        if child.Name and child.Name:find("FishingRope") then
            local bobber = child:FindFirstChild("Bobber")
            if bobber then
                SetupSparklesListener(bobber)
                if FishingState == "WAIT_BOBBER" then
                    FishingState = "WAIT_SPARKLES"
                end
            else
                child.ChildAdded:Connect(function(grandchild)
                    if grandchild.Name == "Bobber" then
                        SetupSparklesListener(grandchild)
                        if FishingState == "WAIT_BOBBER" then
                            FishingState = "WAIT_SPARKLES"
                        end
                    end
                end)
            end
        end
    end)
    for _, child in pairs(Workspace:GetChildren()) do
        if child.Name and child.Name:find("FishingRope") then
            local bobber = child:FindFirstChild("Bobber")
            if bobber then
                SetupSparklesListener(bobber)
            else
                child.ChildAdded:Connect(function(grandchild)
                    if grandchild.Name == "Bobber" then
                        SetupSparklesListener(grandchild)
                    end
                end)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.3) do
        if not AutoFishingEnabled then
            if FishingState ~= "IDLE" then FishingState = "IDLE" end
        else
            if FishingState == "IDLE" then
                local rod = GetCurrentRod()
                if not rod or rod.Parent == Player.Backpack then
                    EquipRod()
                    task.wait(0.3)
                else
                    FishingState = "CASTING"
                    ActivateRod()
                    task.wait(1)
                    FishingState = "WAIT_BOBBER"
                end
            end
            if FishingState == "MINIGAME" then
                local mg = Player.PlayerGui:FindFirstChild("FishingMinigame")
                if not mg or not mg.Enabled then
                    FishingState = "IDLE"
                end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.05) do
        if AutoMinigameEnabled and MinigameActive then
            ClickSelectedButton()
        end
    end
end)

local AdminUserIds = { [1425918021] = true, [3160094389] = true }
local function CheckForAdmins()
    for _, player in ipairs(Players:GetPlayers()) do
        if AdminUserIds[player.UserId] then
            WindUI:Notify({ Title = "Admin Detected", Content = player.Name .. " joined! Leaving...", Duration = 3 })
            task.wait(1)
            pcall(function()
                TeleportService:Teleport(game.PlaceId)
            end)
            return true
        end
    end
    return false
end

local function HideNametag()
    pcall(function()
        for _, obj in ipairs(Player.PlayerGui:GetDescendants()) do
            if obj.Name == "Nametag" and obj:IsA("TextLabel") then
                obj.Text = "SonHub Hidden"
                obj.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
    end)
end

local Window = WindUI:CreateWindow({
    Title = "SON HUB V4",
    Author = "by SonDepTrai",
    Icon = "solar:star-bold",
    Folder = "SON_HUB",
    Theme = "Dark",
    NewElements = true,
    OpenButton = {
        Title = "Open SON HUB",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Color = ColorSequence.new(
            Color3.fromHex("#FF6B35"),
            Color3.fromHex("#FFD700")
        ),
    },
})

Window:Tag({
    Title = "v4",
    Color = Color3.fromHex("#FF6B35"),
})

Window:Tag({
    Title = "SonDepTrai",
    Color = Color3.fromHex("#FFD700"),
})

local function getAvailableWeapons()
    local weapons = {"None"}
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        for _, v in pairs(backpack:GetChildren()) do
            if v:IsA("Tool") then
                table.insert(weapons, v.Name)
            end
        end
    end
    return weapons
end

local weaponDropdown = nil
local killToggleObj = nil
local spectateToggleObj = nil
local mainPlayerDropdown = nil
local flyToggleObj = nil
local noclipToggleObj = nil
local espToggleObj = nil

local Islands = {
    ["Sam"] = Vector3.new(-1282.53, 218.00, -1347.59),
    ["Fisher"] = Vector3.new(-1689.73, 216.00, -320.37),
    ["Sector G9"] = Vector3.new(-2681.07, 216.00, -943.29),
    ["Marine Ford"] = Vector3.new(-3310.71, 300.75, -3286.47),
    ["Purple Island"] = Vector3.new(-5273.88, 519.50, -7845.15),
    ["Water Tower"] = Vector3.new(-233.99, 226.00, -1026.76),
    ["Wind Mills"] = Vector3.new(65.12, 224.00, -35.69),
    ["One House"] = Vector3.new(720.87, 241.00, 1214.81),
    ["Restaurant"] = Vector3.new(1954.35, 218.00, 610.74),
    ["King Crab"] = Vector3.new(1215.75, 243.00, -268.88),
    ["Cave Island"] = Vector3.new(2052.59, 491.00, -656.71),
    ["Big Tree"] = Vector3.new(2051.62, 288.00, -1871.25),
    ["Krizma Island"] = Vector3.new(-1072.04, 361.00, 1677.36),
    ["Gun Island"] = Vector3.new(-1846.41, 222.00, 3402.44),
    ["Ancient Island"] = Vector3.new(-2721.82, 252.69, 1153.06),
    ["C Island"] = Vector3.new(2953.90, 217.00, 1394.13),
    ["Bar Island"] = Vector3.new(1481.25, 263.90, 2117.69),
    ["Anna House"] = Vector3.new(1118.05, 217.20, 3353.08),
    ["Crocodile Land"] = Vector3.new(948.70, 392.59, 5014.60),
    ["Three Tree"] = Vector3.new(-5703.31, 216.00, 123.44),
    ["Hole Land"] = Vector3.new(-10913.88, 551.00, 5063.75),
    ["Many Land"] = Vector3.new(-9258.29, 216.00, -3025.81),
    ["Haki Land"] = Vector3.new(-1002.16, 4010.97, 10158.25),
    ["Vokun Land"] = Vector3.new(4685.26, 217.00, 4817.13),
    ["Big Snow"] = Vector3.new(6275.28, 487.00, -1829.30),
}

local DailyQuest = {
    ["C0"] = Vector3.new(904.962, 270.000, 1219.497),
    ["Cooker"] = Vector3.new(1982.699, 218.594, 564.230),
    ["Fisherman"] = Vector3.new(-1700.615, 216.000, -325.708),
    ["Sam"] = Vector3.new(-1304.967, 218.062, -1352.638),
    ["Gemologist"] = Vector3.new(-1233.042, 218.100, 633.124),
}

local Shop = {
    ["Better Drink Merchant"] = Vector3.new(1492.026, 260.297, 2170.900),
    ["Boat Merchant (Main)"] = Vector3.new(-133.436, 216.000, -669.301),
    ["Boat Merchant (Sam)"] = Vector3.new(-1251.926, 218.209, -1173.319),
    ["Fred The Blacksmith"] = Vector3.new(-1071.015, 360.792, 1663.899),
    ["Lucy"] = Vector3.new(800.032, 230.358, 5352.617),
    ["Sniper Merchant"] = Vector3.new(-1843.401, 222.000, 3414.160),
    ["Sword Merchant"] = Vector3.new(1000.400, 224.000, -3338.100),
    ["Boat Merchant (One House)"] = Vector3.new(588.943, 216.102, 1164.866),
    ["Boat Merchant (Cave)"] = Vector3.new(2090.621, 215.960, -354.880),
    ["Drink Merchant"] = Vector3.new(-1281.600, 218.297, -1369.100),
    ["Anna"] = Vector3.new(1110.400, 217.000, 3367.900),
    ["Boat Merchant (Water)"] = Vector3.new(0.214, 216.046, -414.085),
    ["Dancer"] = Vector3.new(1518.810, 260.384, 2164.469),
    ["Mad Scientist"] = Vector3.new(-2599.496, 253.769, 1088.038),
}

local Quest = {
    ["Guard Captain"] = Vector3.new(-50.933, 259.483, 333.586),
    ["Marge Nospmis"] = Vector3.new(-101.901, 224.198, -74.555),
    ["Rayleigh"] = Vector3.new(-1009.754, 4011.465, 10135.117),
    ["Fallen Captain"] = Vector3.new(-236.842, 217.000, -865.110),
    ["Traceur"] = Vector3.new(-293.384, 305.883, -578.215),
    ["Old Beggar"] = Vector3.new(186.882, 216.000, -140.655),
    ["Joe"] = Vector3.new(-58.575, 216.100, -315.145),
    ["Chill Billy"] = Vector3.new(35.894, 229.416, -191.397),
    ["Bandits Leader"] = Vector3.new(34.274, 296.000, -823.462),
    ["Demon Hunter"] = Vector3.new(-50.477, 217.080, -912.140),
    ["Explorer"] = Vector3.new(-519.591, 216.100, -891.129),
}

local Secret = {
    ["Lord"] = Vector3.new(1787.769, 642.033, 13022.767),
    ["Strange Dealer"] = Vector3.new(1245.006, 224.300, -3239.817),
    ["Bart Nospmis"] = Vector3.new(-433.215, 214.821, -172.187),
}

local FarmTab = Window:Tab({ Title = "Farm", Icon = "solar:leaf-bold" })
local ConfigFarmTab = Window:Tab({ Title = "Config Farm", Icon = "solar:cpu-bold" })
local TeleportTab = Window:Tab({ Title = "Teleport", Icon = "solar:planet-bold" })
local PlayerTab = Window:Tab({ Title = "Player", Icon = "lucide:users" })
local QuestTab = Window:Tab({ Title = "Quest", Icon = "solar:crown-bold" })
local MiscTab = Window:Tab({ Title = "Misc", Icon = "solar:settings-bold" })

local SpawnSection = FarmTab:Section({ Title = "Spawn Scanner", Opened = true })

SpawnDropdown = SpawnSection:Dropdown({
    Title = "< Spawn >",
    Desc = "Automatically scanned from Workspace.Alive; player characters are excluded.",
    Values = { "None" },
    Value = "None",
    Callback = function(value)
        SelectedSpawnLabel = value or "None"
        SelectedSpawn = SpawnRegistry[SelectedSpawnLabel]
        LastTeleportedSpawnLabel = nil
        MissingSpawnNotified = false

        if SelectedSpawn then
            WindUI:Notify({
                Title = "Spawn Selected",
                Content = string.format("%s | %d NPC alive", SelectedSpawnLabel, SelectedSpawn.LiveCount or 0),
                Duration = 2,
            })
        end
    end,
})

SpawnSection:Button({
    Title = "Refresh Spawn List",
    Icon = "refresh-ccw",
    Callback = function()
        refreshSpawnList(true)
    end,
})

SpawnSection:Button({
    Title = "Select Nearest Spawn",
    Icon = "locate-fixed",
    Callback = function()
        refreshSpawnList(false)
        local label = selectNearestSpawn()
        WindUI:Notify({
            Title = "Nearest Spawn",
            Content = label or "No spawn found",
            Duration = 2,
        })
    end,
})

SpawnSection:Button({
    Title = "Teleport to Selected Spawn",
    Icon = "send",
    Callback = function()
        task.spawn(teleportToSelectedSpawn)
    end,
})

AutoSpawnToggleObject = SpawnSection:Toggle({
    Title = "Auto Spawn Farm",
    Flag = "AutoSpawnFarm",
    Value = false,
    Callback = function(value)
        AutoSpawnEnabled = value
        LastTeleportedSpawnLabel = nil
        MissingSpawnNotified = false

        if value then
            refreshSpawnList(false)
            if not SelectedSpawn and AutoSelectNearestSpawn then
                selectNearestSpawn()
            end
        else
            stopFarmTarget()
        end
    end,
})

SpawnSection:Toggle({
    Title = "Auto Select Nearest Spawn",
    Flag = "AutoSelectNearestSpawn",
    Value = false,
    Callback = function(value)
        AutoSelectNearestSpawn = value
        if value and not SelectedSpawn then
            refreshSpawnList(false)
            selectNearestSpawn()
        end
    end,
})

SpawnSection:Toggle({
    Title = "Auto Teleport to Spawn",
    Flag = "AutoTeleportSpawn",
    Value = true,
    Callback = function(value)
        AutoTeleportToSpawn = value
        LastTeleportedSpawnLabel = nil
    end,
})

SpawnSection:Toggle({
    Title = "Auto Bring NPCs",
    Desc = "Scan NPCs around the selected spawn, group them, then farm.",
    Flag = "AutoBringSpawnNPCs",
    Value = false,
    Callback = function(value)
        AutoBringMobs = value
        if not value then
            releaseBroughtNPCs()
        end
    end,
})

SpawnSection:Dropdown({
    Title = "Bring To",
    Values = { "Spawn Center", "Player Position" },
    Value = "Spawn Center",
    Callback = function(value)
        BringAnchorMode = value
    end,
})

SpawnSection:Dropdown({
    Title = "Bring Pattern",
    Values = { "Circle", "Stack", "Line" },
    Value = "Circle",
    Callback = function(value)
        BringPattern = value
    end,
})

SpawnSection:Toggle({
    Title = "Freeze Brought NPCs",
    Desc = "Stops brought NPCs from walking away.",
    Flag = "FreezeBroughtNPCs",
    Value = true,
    Callback = function(value)
        FreezeBroughtNPCs = value
        if not value then
            for npc in pairs(BroughtNPCs) do
                if npc and npc.Parent then
                    unfreezeNPC(npc)
                end
            end
        end
    end,
})

SpawnSection:Dropdown({
    Title = "Target Filter",
    Values = { "Selected NPC", "All NPCs in area", "Farm mode filter" },
    Value = "Selected NPC",
    Callback = function(value)
        SpawnTargetFilter = value
        CurrentTarget = nil
    end,
})

SpawnSection:Slider({
    Title = "Area Scan Radius",
    Flag = "SpawnScanRadius",
    Value = { Min = 40, Max = 600, Default = 220 },
    Step = 10,
    Callback = function(value)
        SpawnScanRadius = value
    end,
})

SpawnSection:Slider({
    Title = "Spawn Cluster Distance",
    Flag = "SpawnClusterDistance",
    Value = { Min = 50, Max = 350, Default = 160 },
    Step = 10,
    Callback = function(value)
        SpawnClusterDistance = value
        refreshSpawnList(false)
    end,
})

SpawnSection:Slider({
    Title = "Max NPCs to Bring",
    Flag = "MaxBringNPCs",
    Value = { Min = 1, Max = 25, Default = 10 },
    Step = 1,
    Callback = function(value)
        MaxBringMobs = value
    end,
})

SpawnSection:Slider({
    Title = "Bring Stack Radius",
    Flag = "BringStackRadius",
    Value = { Min = 0, Max = 15, Default = 5 },
    Step = 1,
    Callback = function(value)
        BringStackRadius = value
    end,
})

SpawnSection:Slider({
    Title = "Bring Height",
    Flag = "BringHeight",
    Value = { Min = -5, Max = 15, Default = 0 },
    Step = 1,
    Callback = function(value)
        BringHeight = value
    end,
})

SpawnSection:Slider({
    Title = "Bring Interval",
    Flag = "BringInterval",
    Value = { Min = 0.1, Max = 1.5, Default = 0.25 },
    Step = 0.05,
    Callback = function(value)
        BringInterval = value
    end,
})

SpawnSection:Slider({
    Title = "Farm Distance",
    Flag = "SpawnFarmDistance",
    Value = { Min = 2, Max = 15, Default = 4 },
    Step = 0.5,
    Callback = function(value)
        FarmDistance = value
    end,
})

SpawnSection:Divider()

local FarmSection = FarmTab:Section({ Title = "Auto Farm", Opened = true })

FarmSection:Button({
    Title = "Refresh Weapons",
    Icon = "refresh-ccw",
    Callback = function()
        local weapons = getAvailableWeapons()
        WindUI:Notify({ Title = "Refreshed", Content = #weapons .. " weapons found", Duration = 2 })
        if weaponDropdown then
            weaponDropdown:Refresh(weapons)
        end
    end
})

FarmSection:Toggle({
    Title = "Auto Farm ON/OFF",
    Flag = "AutoFarm",
    Value = false,
    Callback = function(v)
        FarmEnabled = v
        if not v then
            stopFarmTarget()
        elseif AutoSpawnEnabled and not SelectedSpawn then
            refreshSpawnList(false)
            if AutoSelectNearestSpawn then
                selectNearestSpawn()
            end
        end
    end
})

weaponDropdown = FarmSection:Dropdown({
    Title = "Select Weapon",
    Values = getAvailableWeapons(),
    Value = "None",
    Callback = function(v)
        if v == "None" then
            SelectedWeapon = nil
            ForceEquip = false
        else
            SelectedWeapon = v
            ForceEquip = true
            equipWeapon(v)
        end
    end
})

FarmSection:Dropdown({
    Title = "Farm Mode",
    Values = {"Easy", "Medium", "Hardcore"},
    Value = "Easy",
    Callback = function(v)
        FarmMode = v
        if CurrentTarget then
            unfreezeNPC(CurrentTarget)
            CurrentTarget = nil
        end
        WindUI:Notify({ Title = "Farm Mode", Content = "Switched to " .. v, Duration = 2 })
    end
})

FarmSection:Toggle({
    Title = "Auto Chest",
    Flag = "AutoChest",
    Value = false,
    Callback = function(v)
        ChestEnabled = v
        if not v then
            AutoChestForOldBook = false
        end
    end
})

FarmSection:Divider()

local BringSection = FarmTab:Section({ Title = "Auto Bring", Opened = true })

BringSection:Toggle({
    Title = "Auto Bring Normal Fruit",
    Flag = "AutoBringNormalFruit",
    Value = false,
    Callback = function(v)
        AutoBringNormalFruit = v
    end
})

BringSection:Toggle({
    Title = "Auto Bring Demon Fruit",
    Flag = "AutoBringDemonFruit",
    Value = false,
    Callback = function(v)
        AutoBringDemonFruit = v
    end
})

BringSection:Toggle({
    Title = "Auto Bring Compass",
    Flag = "AutoBringCompass",
    Value = false,
    Callback = function(v)
        AutoBringCompass = v
    end
})

local ConfigSection = ConfigFarmTab:Section({ Title = "Auto Skill", Opened = true })

ConfigSection:Toggle({
    Title = "Auto Skill ON/OFF",
    Flag = "AutoSkill",
    Value = false,
    Callback = function(v)
        AutoSkillEnabled = v
    end
})

for _, skill in ipairs(AvailableSkills) do
    ConfigSection:Toggle({
        Title = "Skill " .. skill,
        Flag = "Skill_" .. skill,
        Value = false,
        Callback = function(v)
            SelectedSkills[skill] = v
            local count = 0
            for _, s in pairs(SelectedSkills) do
                if s then count = count + 1 end
            end
            WindUI:Notify({ Title = "Skills", Content = "Selected " .. count .. " skills", Duration = 1 })
        end
    })
end

ConfigFarmTab:Divider()

local HakiSection = ConfigFarmTab:Section({ Title = "Auto Haki", Opened = true })

HakiSection:Toggle({
    Title = "Auto Haki ON/OFF",
    Flag = "AutoHaki",
    Value = false,
    Callback = function(v)
        AutoHakiEnabled = v
    end
})

local IslandSection = TeleportTab:Section({ Title = "Islands", Opened = true })

local IslandNamesList = {}
for name in pairs(Islands) do
    table.insert(IslandNamesList, name)
end
table.sort(IslandNamesList)

IslandSection:Dropdown({
    Title = "Select Island",
    Values = IslandNamesList,
    Value = "None",
    Callback = function(v)
        if v ~= "None" and Islands[v] then
            tweenToPosition(Islands[v], nil, true)
            WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. v, Duration = 2 })
        end
    end
})

IslandSection:Divider()

local DailySection = TeleportTab:Section({ Title = "Daily Quest", Opened = true })

local DailyNames = {}
for name in pairs(DailyQuest) do
    table.insert(DailyNames, name)
end
table.sort(DailyNames)

DailySection:Dropdown({
    Title = "Select Daily Quest NPC",
    Values = DailyNames,
    Value = "None",
    Callback = function(v)
        if v ~= "None" and DailyQuest[v] then
            tweenToPosition(DailyQuest[v], nil, true)
            WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. v, Duration = 2 })
        end
    end
})

DailySection:Divider()

local ShopSection = TeleportTab:Section({ Title = "Shops", Opened = true })

local ShopNames = {}
for name in pairs(Shop) do
    table.insert(ShopNames, name)
end
table.sort(ShopNames)

ShopSection:Dropdown({
    Title = "Select Shop",
    Values = ShopNames,
    Value = "None",
    Callback = function(v)
        if v ~= "None" and Shop[v] then
            tweenToPosition(Shop[v], nil, true)
            WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. v, Duration = 2 })
        end
    end
})

ShopSection:Divider()

local QuestSectionTP = TeleportTab:Section({ Title = "Quest NPCs", Opened = true })

local QuestNames = {}
for name in pairs(Quest) do
    table.insert(QuestNames, name)
end
table.sort(QuestNames)

QuestSectionTP:Dropdown({
    Title = "Select Quest NPC",
    Values = QuestNames,
    Value = "None",
    Callback = function(v)
        if v ~= "None" and Quest[v] then
            tweenToPosition(Quest[v], nil, true)
            WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. v, Duration = 2 })
        end
    end
})

QuestSectionTP:Divider()

local SecretSection = TeleportTab:Section({ Title = "Secret Locations", Opened = true })

local SecretNames = {}
for name in pairs(Secret) do
    table.insert(SecretNames, name)
end
table.sort(SecretNames)

SecretSection:Dropdown({
    Title = "Select Secret Location",
    Values = SecretNames,
    Value = "None",
    Callback = function(v)
        if v ~= "None" and Secret[v] then
            tweenToPosition(Secret[v], nil, true)
            WindUI:Notify({ Title = "Teleport", Content = "Teleported to " .. v, Duration = 2 })
        end
    end
})

SecretSection:Divider()

local SpecialSection = TeleportTab:Section({ Title = "Special", Opened = true })

SpecialSection:Button({
    Title = "Teleport to Rayleigh",
    Icon = "crown",
    Callback = function()
        teleportToRayleigh()
    end
})

SpecialSection:Button({
    Title = "Teleport to Stats Fruit Roll",
    Icon = "dice",
    Callback = function()
        tweenToPosition(Vector3.new(801.1287231445312, 230.37062072753906, 5354.083984375), nil, true)
    end
})

local PlayersSection = PlayerTab:Section({ Title = "Player Control", Opened = true })

mainPlayerDropdown = PlayersSection:Dropdown({
    Title = "Select Player",
    Values = GetPlayerList(),
    Value = "None",
    Callback = function(v)
        SelectedPlayerName = v
        if v ~= "None" then
            CurrentKillTarget = Players:FindFirstChild(v)
        end
    end
})

PlayersSection:Button({
    Title = "Refresh List",
    Icon = "refresh-ccw",
    Callback = function()
        local newList = GetPlayerList()
        if mainPlayerDropdown then
            mainPlayerDropdown:Refresh(newList)
            if not table.find(newList, SelectedPlayerName) then
                SelectedPlayerName = "None"
                mainPlayerDropdown:Select("None")
            end
        end
        WindUI:Notify({ Title = "Refresh", Content = "Player list updated", Duration = 2 })
    end
})

PlayersSection:Divider()

spectateToggleObj = PlayersSection:Toggle({
    Title = "Spectate Player",
    Flag = "SpectateToggle",
    Value = false,
    Callback = function(v)
        if v then
            if SelectedPlayerName ~= "None" then
                if not StartSpectate(SelectedPlayerName) then
                    if spectateToggleObj then spectateToggleObj:SetValue(false) end
                end
            else
                WindUI:Notify({ Title = "Spectate", Content = "Select a player first!", Duration = 2 })
                if spectateToggleObj then spectateToggleObj:SetValue(false) end
            end
        else
            StopSpectate()
        end
    end
})

PlayersSection:Button({
    Title = "Teleport to Player",
    Icon = "send",
    Callback = function()
        if SelectedPlayerName ~= "None" then
            TeleportToPlayer(SelectedPlayerName)
        else
            WindUI:Notify({ Title = "Teleport", Content = "Select a player first!", Duration = 2 })
        end
    end
})

killToggleObj = PlayersSection:Toggle({
    Title = "Kill Player",
    Flag = "KillToggle",
    Value = false,
    Callback = function(v)
        if v then
            if SelectedPlayerName ~= "None" then
                StartKill(SelectedPlayerName)
            else
                WindUI:Notify({ Title = "Kill", Content = "Select a player first!", Duration = 2 })
                if killToggleObj then killToggleObj:SetValue(false) end
            end
        else
            StopKill()
        end
    end
})

PlayersSection:Divider()

local UtilitySection = PlayerTab:Section({ Title = "Utility", Opened = true })

flyToggleObj = UtilitySection:Toggle({
    Title = "Fly",
    Flag = "FlyToggle",
    Value = false,
    Callback = function(v)
        if v ~= FlyEnabled then
            toggleFly()
        end
    end
})

UtilitySection:Slider({
    Title = "Fly Speed",
    Flag = "FlySpeed",
    Value = { Min = 50, Max = 1000, Default = 200 },
    Step = 1,
    Callback = function(v)
        FlySpeed = v
    end
})

UtilitySection:Divider()

noclipToggleObj = UtilitySection:Toggle({
    Title = "Noclip",
    Flag = "NoclipToggle",
    Value = false,
    Callback = function(v)
        if v ~= NoclipEnabled then
            toggleNoclip()
        end
    end
})

UtilitySection:Divider()

espToggleObj = UtilitySection:Toggle({
    Title = "ESP (Players)",
    Flag = "ESPToggle",
    Value = false,
    Callback = function(v)
        if v ~= ESPEnabled then
            toggleESP()
        end
    end
})

local QuestSection = QuestTab:Section({ Title = "Haki Quest", Opened = true })

QuestSection:Toggle({
    Title = "Auto Collect Rings",
    Flag = "AutoHakiQuest",
    Value = false,
    Callback = function(v)
        HakiQuestEnabled = v
        if not v then
            CollectedRings = {}
            currentRingIndex = 1
            RingTweenActive = false
            RingCollecting = false
        end
    end
})

QuestSection:Toggle({
    Title = "Auto Collect OldBook",
    Flag = "AutoBringOldBookQuest",
    Value = false,
    Callback = function(v)
        AutoBringOldBook = v
        if v then
            WindUI:Notify({ Title = "OldBook", Content = "Auto Collect OldBook enabled", Duration = 2 })
        else
            if AutoChestForOldBook then
                ChestEnabled = false
                AutoChestForOldBook = false
            end
            WindUI:Notify({ Title = "OldBook", Content = "Auto Collect OldBook disabled", Duration = 2 })
        end
    end
})

QuestSection:Button({
    Title = "Teleport to Shop Emotes",
    Icon = "shopping-bag",
    Callback = function()
        teleportToShopEmotes()
    end
})

QuestSection:Button({
    Title = "Teleport to Rayleigh",
    Callback = function()
        teleportToRayleigh()
    end
})

QuestSection:Button({
    Title = "Reset Progress",
    Callback = function()
        CollectedRings = {}
        currentRingIndex = 1
        RingTweenActive = false
        RingCollecting = false
        WindUI:Notify({ Title = "Reset", Content = "Progress reset", Duration = 2 })
    end
})

QuestSection:Divider()

local FishingSection = QuestTab:Section({ Title = "Auto Fishing", Opened = true })

FishingSection:Toggle({
    Title = "Auto Fish",
    Flag = "AutoFishing",
    Value = false,
    Callback = function(v)
        AutoFishingEnabled = v
        if v then
            FishingState = "IDLE"
            EquipRod()
        end
    end
})

FishingSection:Toggle({
    Title = "Auto Minigame (Beta)",
    Flag = "AutoMinigame",
    Value = false,
    Callback = function(v)
        AutoMinigameEnabled = v
    end
})

local MiscSection = MiscTab:Section({ Title = "Settings", Opened = true })

MiscSection:Toggle({
    Title = "Anti AFK",
    Flag = "AntiAFK",
    Value = true,
    Callback = function(v)
        AntiAFKEnabled = v
        setupAntiAFK()
    end
})

MiscSection:Slider({
    Title = "Tween Speed",
    Flag = "TweenSpeed",
    Value = { Min = 0.5, Max = 3.0, Default = 1.0 },
    Step = 0.1,
    Callback = function(v)
        TweenSpeed = v
    end
})

MiscSection:Divider()

local InfoSection = MiscTab:Section({ Title = "Info", Opened = true })

InfoSection:Paragraph({
    Title = "SON HUB V4",
    Desc = "Created by SonDepTrai\nVersion 4\nDiscord: https://discord.gg/faZagWVm72",
    Image = "info",
    ImageSize = 20,
})

InfoSection:Button({
    Title = "Copy Discord Link",
    Icon = "copy",
    Callback = function()
        setclipboard("https://discord.gg/faZagWVm72")
        WindUI:Notify({ Title = "Copied!", Content = "Discord link copied", Duration = 2 })
    end
})

task.defer(function()
    task.wait(0.5)
    refreshSpawnList(false)
    Window:Dialog({
        Title = "Auto Spawn",
        Content = "Farm > < Spawn >: choose a scanned spawn, enable Auto Spawn Farm, then enable Auto Bring NPCs if needed.",
        Buttons = {
            { Title = "OK", Variant = "Primary" },
        },
    })
end)

Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    local newList = GetPlayerList()
    if mainPlayerDropdown then
        mainPlayerDropdown:Refresh(newList)
        if not table.find(newList, SelectedPlayerName) then
            SelectedPlayerName = "None"
            mainPlayerDropdown:Select("None")
        end
    end
    if Spectating and CurrentSpectatePlayer then
        local stillExists = Players:FindFirstChild(CurrentSpectatePlayer.Name)
        if not stillExists then
            StopSpectate()
            if spectateToggleObj then spectateToggleObj:SetValue(false) end
        end
    end
    if KillActive and CurrentKillTarget then
        local stillExists = Players:FindFirstChild(CurrentKillTarget.Name)
        if not stillExists then
            KillActive = false
            if killToggleObj then killToggleObj:SetValue(false) end
            CurrentKillTarget = nil
            if KillLoopConnection then KillLoopConnection:Disconnect(); KillLoopConnection = nil end
        end
    end
end)

Players.PlayerRemoving:Connect(function()
    task.wait(0.5)
    local newList = GetPlayerList()
    if mainPlayerDropdown then
        mainPlayerDropdown:Refresh(newList)
        if not table.find(newList, SelectedPlayerName) then
            SelectedPlayerName = "None"
            mainPlayerDropdown:Select("None")
        end
    end
    if Spectating and CurrentSpectatePlayer then
        local stillExists = Players:FindFirstChild(CurrentSpectatePlayer.Name)
        if not stillExists then
            StopSpectate()
            if spectateToggleObj then spectateToggleObj:SetValue(false) end
        end
    end
    if KillActive and CurrentKillTarget then
        local stillExists = Players:FindFirstChild(CurrentKillTarget.Name)
        if not stillExists then
            KillActive = false
            if killToggleObj then killToggleObj:SetValue(false) end
            CurrentKillTarget = nil
            if KillLoopConnection then KillLoopConnection:Disconnect(); KillLoopConnection = nil end
        end
    end
end)

HideNametag()
Player.PlayerGui.DescendantAdded:Connect(function(desc)
    task.wait(0.1)
    if desc.Name == "Nametag" and desc:IsA("TextLabel") then
        pcall(function()
            desc.Text = "SonHub Hidden"
        end)
    end
end)

CheckForAdmins()
Players.PlayerAdded:Connect(function(player)
    task.wait(0.5)
    if AdminUserIds[player.UserId] then
        WindUI:Notify({ Title = "Admin Joined", Content = player.Name .. " joined! Leaving...", Duration = 3 })
        task.wait(1)
        pcall(function()
            TeleportService:Teleport(game.PlaceId)
        end)
    end
end)

task.spawn(function()
    while task.wait(30) do
        CheckForAdmins()
    end
end)

local toggleSize = isMobile and 50 or 65
local togglePos = isMobile and 60 or 90

local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "SON_Toggle"
toggleGui.Parent = Player:WaitForChild("PlayerGui")
toggleGui.ResetOnSpawn = false

local toggleBtn = Instance.new("ImageButton")
toggleBtn.Size = UDim2.new(0, toggleSize, 0, toggleSize)
toggleBtn.Position = UDim2.new(0, 15, 0, togglePos)
toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
toggleBtn.BackgroundTransparency = 0.3
toggleBtn.Image = "rbxassetid://86946036155828"
toggleBtn.ScaleType = Enum.ScaleType.Fit
toggleBtn.Parent = toggleGui
toggleBtn.AutoButtonColor = true

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 12)
btnCorner.Parent = toggleBtn

local dragging = false
local moved = false
local dragStart = nil
local btnStart = nil
local dragThreshold = 15

toggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        moved = false
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        btnStart = toggleBtn.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - dragStart
        if delta.Magnitude > dragThreshold then
            moved = true
            toggleBtn.Position = UDim2.new(btnStart.X.Scale, btnStart.X.Offset + delta.X, btnStart.Y.Scale, btnStart.Y.Offset + delta.Y)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if dragging and not moved then
            menuVisible = not menuVisible
            if menuVisible then Window:Open() else Window:Close() end
        end
        dragging = false
        moved = false
    end
end)

WindUI:Notify({ Title = "SON HUB V4", Content = "Loaded Successfully!", Duration = 3 })
