--[[
    SON HUB v3
    Target snapshot: PlaceId 118635363908336
    UI: ZyronX UI Library
    make by hongson

    Clean architecture:
      Core
      RuntimeIndex
      PlayerState
      QuestService
      HotbarService
      TargetService
      TweenController
      BringService
      InteractionService
      CombatService
      FarmService
      LifeSkillService
      ESPService
      UI

    Design rules:
      - No print/warn/console spam.
      - No guessed RemoteEvent / RemoteFunction argument calls.
      - Large Explorer is indexed once and updated incrementally.
      - One movement controller owns Tween/Noclip movement.
      - Auto Farm can run fully automatic from live Level + Quest state.
]]

-- ============================================================
-- Bootstrap
-- ============================================================

local ENV = (getgenv and getgenv()) or _G

if ENV.__SON_HUB_UNLOAD then
    pcall(ENV.__SON_HUB_UNLOAD)
end

local Library = loadstring(game:HttpGetAsync("https://pastefy.app/YoX4PJmf/raw"))()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local EXPECTED_PLACE_ID = 118635363908336
local VERSION = "3.0.0"

-- ============================================================
-- Core
-- ============================================================

local Core = {
    Running = true,
    Connections = {},
    Instances = {},
    CollisionBackup = setmetatable({}, {__mode = "k"}),
}

local Config = {
    -- Farm
    AutoFarm = false,
    FarmMode = "Smart Quest",
    SelectedMob = "Nearest Hostile",
    SelectedWeapon = "Auto",
    AutoAttack = true,
    AutoSkill = false,
    AutoSkillDelay = 2.5,
    AttackRate = 8,
    BringMobs = false,
    BringRadius = 90,
    BringLimit = 10,
    BringDistance = 4,
    BringBosses = false,
    AutoLootAfterFarm = true,

    -- Combat
    AutoAim = true,
    AutoBoss = false,
    AutoBlock = false,
    BlockHealthPercent = 40,
    CombatDistance = 7,
    FarmHeight = 4,
    FarmBack = 3,

    -- Tween / movement
    TweenEnabled = true,
    TweenSpeed = 175,
    ArrivalDistance = 7,
    TweenNoclip = true,
    SpeedOverride = false,
    WalkSpeed = 24,
    JumpOverride = false,
    JumpPower = 55,
    InfiniteJump = false,
    Noclip = false,

    -- Quest
    AutoQuest = true,
    AutoAcceptRecommended = true,
    AutoTurnIn = true,
    AutoDialogue = true,
    AutoClaim = true,

    -- Player / collection / lifeskill
    AutoPickup = false,
    AutoChest = false,
    AutoWorldBossChest = false,
    AutoFruitChest = false,
    AutoQuestItems = false,
    AutoMining = false,
    AutoFarming = false,
    AutoFishing = false,
    AntiAFK = true,

    -- ESP
    QuestTargetESP = true,
    MobESP = false,
    BossESP = false,
    LootESP = false,
    ESPDistance = 1200,
    QuestColor = Color3.fromRGB(95, 200, 255),
    MobColor = Color3.fromRGB(255, 205, 80),
    BossColor = Color3.fromRGB(255, 75, 95),
    LootColor = Color3.fromRGB(115, 255, 145),
}

local Runtime = {
    Prompts = setmetatable({}, {__mode = "k"}),
    Entities = setmetatable({}, {__mode = "k"}),
    DialogueNPCs = setmetatable({}, {__mode = "k"}),
    DialogueQuestNames = setmetatable({}, {__mode = "k"}),

    IndexReady = false,

    CurrentTween = nil,
    CurrentTweenTarget = nil,
    CurrentTarget = nil,
    CurrentTargetReason = nil,

    LastAttack = 0,
    LastSkill = 0,
    LastWeaponEquip = 0,
    LastWeaponTitle = nil,
    LastFishingCast = 0,

    BlockHeld = false,

    WorkerState = "Idle",
    WorkerDetail = "Waiting",
    LastLevel = nil,
    LastQuestKey = nil,
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Core.Connections, connection)
    return connection
end

local function track(instance)
    table.insert(Core.Instances, instance)
    return instance
end

local function notify(title, description, duration)
    pcall(function()
        Library:Notify({
            Title = title,
            Description = description,
            Duration = duration or 3,
        })
    end)
end

local function normalize(value)
    local text = tostring(value or "")
    text = text:gsub("<.->", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function lower(value)
    return string.lower(normalize(value))
end

local function stripRuntimeSuffix(name)
    return (normalize(name):gsub("%s+%d+$", ""))
end

local function character()
    return LocalPlayer.Character
end

local function humanoid()
    local char = character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function rootPart()
    local char = character()

    return char and (
        char:FindFirstChild("HumanoidRootPart")
        or char.PrimaryPart
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
    )
end

local function objectRoot(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object
    end

    if object:IsA("Attachment") then
        return object.Parent and object.Parent:IsA("BasePart") and object.Parent or nil
    end

    if object:IsA("ProximityPrompt") then
        return objectRoot(object.Parent)
    end

    if object:IsA("Model") then
        return object:FindFirstChild("HumanoidRootPart")
            or object.PrimaryPart
            or object:FindFirstChild("UpperTorso")
            or object:FindFirstChild("Torso")
            or object:FindFirstChildWhichIsA("BasePart", true)
    end

    local model = object:FindFirstAncestorWhichIsA("Model")
    return model and objectRoot(model) or nil
end

local function distanceTo(object)
    local ownRoot = rootPart()
    local targetRoot = objectRoot(object)

    if not ownRoot or not targetRoot then
        return math.huge
    end

    return (ownRoot.Position - targetRoot.Position).Magnitude
end

local function isGuiVisible(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") then
        return false
    end

    local current = guiObject
    while current and current:IsA("GuiObject") do
        if current.Visible == false then
            return false
        end
        current = current.Parent
    end

    local screen = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
    return not screen or screen.Enabled
end

local function textOf(object)
    if not object then
        return ""
    end

    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        return normalize(object.Text)
    end

    local label = object:FindFirstChildWhichIsA("TextLabel", true)
    return label and normalize(label.Text) or ""
end

local function findText(root, name)
    if not root then
        return nil
    end

    local object = root:FindFirstChild(name, true)
    if object and (
        object:IsA("TextLabel")
        or object:IsA("TextButton")
        or object:IsA("TextBox")
    ) then
        return object
    end

    return nil
end

-- ============================================================
-- RuntimeIndex
-- ============================================================

local RuntimeIndex = {}

local function entitiesFolder()
    return Workspace:FindFirstChild("Entities")
end

local function dialogueRoot()
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    return important and important:FindFirstChild("DialogueNPCs")
end

function RuntimeIndex.Register(instance)
    if not instance then
        return
    end

    if instance:IsA("ProximityPrompt") then
        Runtime.Prompts[instance] = true
        return
    end

    if not instance:IsA("Model") then
        return
    end

    local entities = entitiesFolder()
    if entities and instance.Parent == entities then
        Runtime.Entities[instance] = true
    end

    local dialogues = dialogueRoot()
    if dialogues and instance:IsDescendantOf(dialogues) then
        local parent = instance.Parent
        if parent and parent.Parent == dialogues then
            Runtime.DialogueNPCs[instance] = true
        end
    end
end

function RuntimeIndex.Unregister(instance)
    Runtime.Prompts[instance] = nil
    Runtime.Entities[instance] = nil
    Runtime.DialogueNPCs[instance] = nil
    Runtime.DialogueQuestNames[instance] = nil
end

function RuntimeIndex.Rebuild()
    table.clear(Runtime.Prompts)
    table.clear(Runtime.Entities)
    table.clear(Runtime.DialogueNPCs)
    table.clear(Runtime.DialogueQuestNames)

    Runtime.IndexReady = false

    local descendants = Workspace:GetDescendants()

    for index, instance in ipairs(descendants) do
        RuntimeIndex.Register(instance)

        if index % 5000 == 0 then
            task.wait()
        end
    end

    Runtime.IndexReady = true
end

connect(Workspace.DescendantAdded, RuntimeIndex.Register)
connect(Workspace.DescendantRemoving, RuntimeIndex.Unregister)

task.spawn(RuntimeIndex.Rebuild)

-- ============================================================
-- PlayerState
-- ============================================================

local PlayerState = {}

function PlayerState.GetLevel()
    local direct = tonumber(LocalPlayer:GetAttribute("Level"))
    if direct then
        return direct
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local value = leaderstats:FindFirstChild("Level") or leaderstats:FindFirstChild("Lvl")
        if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
            return tonumber(value.Value) or 0
        end
    end

    return 0
end

function PlayerState.GetWorld()
    return tostring(LocalPlayer:GetAttribute("WorldType") or Workspace:GetAttribute("WorldType") or "Unknown")
end

function PlayerState.GetFruit()
    return tostring(LocalPlayer:GetAttribute("Fruit") or "None")
end

function PlayerState.GetFruitLevel()
    return tonumber(LocalPlayer:GetAttribute("FruitLevel")) or 0
end

function PlayerState.GetBounty()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local bounty = leaderstats and leaderstats:FindFirstChild("Bounty")
    return bounty and tonumber(bounty.Value) or 0
end

function PlayerState.GetLeaderString(name)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local value = leaderstats and leaderstats:FindFirstChild(name)
    return value and tostring(value.Value) or ""
end

function PlayerState.GetEntity()
    local entities = entitiesFolder()
    return entities and entities:FindFirstChild(LocalPlayer.Name)
end

function PlayerState.GetWeaponTypes()
    local entity = PlayerState.GetEntity()
    if not entity then
        return "Unknown"
    end

    local values = {}
    for index = 1, 3 do
        local value = entity:GetAttribute("WeaponType" .. index)
        if value and tostring(value) ~= "" then
            table.insert(values, tostring(value))
        end
    end

    return #values > 0 and table.concat(values, " / ") or "Unknown"
end

function PlayerState.GetHealthPercent()
    local hum = humanoid()
    if not hum or hum.MaxHealth <= 0 then
        return 100
    end

    return math.clamp((hum.Health / hum.MaxHealth) * 100, 0, 100)
end

function PlayerState.IsReady()
    local loaded = LocalPlayer:GetAttribute("Loaded")
    local playerLoaded = LocalPlayer:GetAttribute("PlayerLoaded")

    if loaded == nil and playerLoaded == nil then
        return true
    end

    return loaded ~= false and playerLoaded ~= false
end

-- ============================================================
-- QuestService
-- ============================================================

local QuestService = {}

local function questScreen()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Quests")
end

local function questScrollingFrame()
    local gui = questScreen()
    local quest = gui and gui:FindFirstChild("Quest")
    return quest and quest:FindFirstChild("ScrollingFrame")
end

local function questStorage()
    local gui = questScreen()
    local quest = gui and gui:FindFirstChild("Quest")
    local questLocal = quest and quest:FindFirstChild("QuestLocal")
    return questLocal and questLocal:FindFirstChild("Storage")
end

local function taskComplete(frame, rawText)
    if rawText:find("<s>", 1, true) then
        return true
    end

    local checkbox = frame:FindFirstChild("Checkbox")
    if checkbox and checkbox:IsA("GuiObject") and checkbox.Visible then
        return true
    end

    local current, required = rawText:match("%((%d+)%s*/%s*(%d+)%)")
    if current and required and tonumber(current) >= tonumber(required) then
        return true
    end

    return false
end

local function parseTask(raw)
    local clean = normalize(raw)
    clean = clean:gsub("^[-•]%s*", "")
    clean = clean:gsub("%s*%(%d+%s*/%s*%d+%)%.?$", "")
    clean = normalize(clean)

    local patterns = {
        {"Defeat", "^Defeat%s+(.+)$"},
        {"Defeat", "^Kill%s+(.+)$"},
        {"Talk", "^Talk%s+[Tt]o%s+(.+)$"},
        {"Talk", "^Speak%s+[Tt]o%s+(.+)$"},
        {"Collect", "^Collect%s+(.+)$"},
        {"Collect", "^Gather%s+(.+)$"},
        {"Collect", "^Get%s+(.+)$"},
        {"Deliver", "^Deliver%s+(.+)$"},
        {"Return", "^Return%s+[Tt]o%s+(.+)$"},
        {"Find", "^Find%s+(.+)$"},
    }

    for _, entry in ipairs(patterns) do
        local target = clean:match(entry[2])

        if target then
            target = normalize(target:gsub("^['\"]", ""):gsub("['\"]$", ""))
            return entry[1], target
        end
    end

    return "Unknown", clean
end

function QuestService.GetActiveQuests()
    local scrolling = questScrollingFrame()
    if not scrolling then
        return {}
    end

    local byId = {}

    for _, child in ipairs(scrolling:GetChildren()) do
        if child.Name == "QuestTitle" then
            local questId = child:GetAttribute("QuestId")
            if questId ~= nil then
                byId[questId] = {
                    Id = questId,
                    Name = tostring(
                        child:GetAttribute("QuestName")
                        or textOf(findText(child, "QuestName"))
                        or ""
                    ),
                    Tasks = {},
                    Complete = false,
                }
            end
        end
    end

    for _, child in ipairs(scrolling:GetChildren()) do
        if child.Name == "Task" then
            local questId = child:GetAttribute("QuestId")
            local quest = questId ~= nil and byId[questId]

            if quest then
                local info = child:FindFirstChild("Info1", true)
                local rawText = info and tostring(info.Text) or ""
                local kind, target = parseTask(rawText)

                table.insert(quest.Tasks, {
                    Frame = child,
                    Text = normalize(rawText),
                    RawText = rawText,
                    Kind = kind,
                    Target = target,
                    Complete = taskComplete(child, rawText),
                    LayoutOrder = child.LayoutOrder,
                })
            end
        end
    end

    local result = {}

    for _, quest in pairs(byId) do
        table.sort(quest.Tasks, function(a, b)
            return a.LayoutOrder < b.LayoutOrder
        end)

        local complete = #quest.Tasks > 0

        for _, taskData in ipairs(quest.Tasks) do
            if not taskData.Complete then
                complete = false
                break
            end
        end

        quest.Complete = complete
        table.insert(result, quest)
    end

    table.sort(result, function(a, b)
        return tonumber(a.Id) < tonumber(b.Id)
    end)

    return result
end

function QuestService.GetNextTask()
    for _, quest in ipairs(QuestService.GetActiveQuests()) do
        for _, taskData in ipairs(quest.Tasks) do
            if not taskData.Complete then
                return quest, taskData
            end
        end
    end

    return nil, nil
end

function QuestService.GetCompletedQuest()
    for _, quest in ipairs(QuestService.GetActiveQuests()) do
        if quest.Complete then
            return quest
        end
    end

    return nil
end

function QuestService.GetRecommended()
    local storage = questStorage()
    local recommended = storage and storage:FindFirstChild("RecommendedQuest")

    if not recommended then
        return nil
    end

    local info = recommended:FindFirstChild("Info1", true)
    local text = info and normalize(info.Text) or ""
    local name = text:match("[Rr]ecommended:%s*(.+)$")

    if not name or name == "" then
        return nil
    end

    return {
        Id = recommended:GetAttribute("QuestId"),
        Name = normalize(name),
    }
end

local function npcMatches(model, targetName)
    if not model or not targetName or targetName == "" then
        return false
    end

    local wanted = lower(targetName)

    local candidates = {
        model.Name,
        stripRuntimeSuffix(model.Name),
        model:GetAttribute("NPCName"),
        model:GetAttribute("NPCType"),
        model:GetAttribute("OriginalName"),
    }

    for _, candidate in ipairs(candidates) do
        if candidate then
            local value = lower(candidate)

            if value == wanted
                or value:find(wanted, 1, true)
                or wanted:find(value, 1, true) then
                return true
            end
        end
    end

    return false
end

local function dialogueQuestNames(model)
    if not model then
        return {}
    end

    local cached = Runtime.DialogueQuestNames[model]
    if cached then
        return cached
    end

    local names = {}

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("StringValue")
            and descendant.Name == "QuestName"
            and descendant.Value ~= "" then

            names[normalize(descendant.Value)] = true
        end

        local questNode = descendant:GetAttribute("QuestNode")
        if type(questNode) == "string" and questNode ~= "" then
            names[normalize(questNode)] = true
        end

        if descendant:IsA("TextLabel") and descendant.Name == "QuestLabel" then
            local value = normalize(descendant.Text)
            if value ~= "" then
                names[value] = true
            end
        end
    end

    Runtime.DialogueQuestNames[model] = names
    return names
end

function QuestService.FindDialogueNPC(questName, preferredName)
    local wantedQuest = lower(questName)
    local ownRoot = rootPart()
    local candidates = {}

    for model in pairs(Runtime.DialogueNPCs) do
        if model and model.Parent then
            candidates[model] = true
        end
    end

    local dialogues = dialogueRoot()
    if dialogues then
        for _, island in ipairs(dialogues:GetChildren()) do
            for _, child in ipairs(island:GetChildren()) do
                if child:IsA("Model") then
                    candidates[child] = true
                end
            end
        end
    end

    local best
    local bestDistance

    for model in pairs(candidates) do
        local matched = preferredName and preferredName ~= "" and npcMatches(model, preferredName)

        if not matched and wantedQuest ~= "" then
            for name in pairs(dialogueQuestNames(model)) do
                if lower(name) == wantedQuest then
                    matched = true
                    break
                end
            end
        end

        if matched then
            local part = objectRoot(model)

            if part then
                local distance = ownRoot and (ownRoot.Position - part.Position).Magnitude or 0

                if not bestDistance or distance < bestDistance then
                    best = model
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

function QuestService.StateKey()
    local quest, taskData = QuestService.GetNextTask()
    if quest and taskData then
        return "active|" .. tostring(quest.Id) .. "|" .. quest.Name .. "|" .. taskData.Text
    end

    local complete = QuestService.GetCompletedQuest()
    if complete then
        return "complete|" .. tostring(complete.Id) .. "|" .. complete.Name
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "recommended|" .. tostring(recommended.Id) .. "|" .. recommended.Name
    end

    return "idle"
end

-- ============================================================
-- HotbarService
-- Uses the custom Backpack/Hotbar confirmed in the dump
-- ============================================================

local HotbarService = {
    Slots = {},
    TitleToSlot = {},
}

local KEY_BY_SLOT = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven,
    ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine,
    ["0"] = Enum.KeyCode.Zero,
}

local NON_COMBAT_WORDS = {
    "key",
    "fragment",
    "rock",
    "ink",
    "pickaxe",
    "bait",
    "food",
    "map",
    "pouch",
    "shovel",
    "watering",
    "fertilizer",
}

local COMBAT_PRIORITY = {
    "sword",
    "slash",
    "punch",
    "gun",
    "shot",
    "cannon",
    "fist",
    "claw",
    "axe",
    "kick",
}

local function findHotbar()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local backpackGui = playerGui and playerGui:FindFirstChild("Backpack")

    if not backpackGui then
        return nil
    end

    for _, descendant in ipairs(backpackGui:GetDescendants()) do
        if descendant.Name == "Hotbar" and descendant:IsA("GuiObject") then
            return descendant
        end
    end

    return nil
end

function HotbarService.Refresh()
    table.clear(HotbarService.Slots)
    table.clear(HotbarService.TitleToSlot)

    local hotbar = findHotbar()
    if not hotbar then
        return
    end

    for _, slot in ipairs(hotbar:GetChildren()) do
        if KEY_BY_SLOT[slot.Name] then
            local toolFrame = slot:FindFirstChild("ToolFrame")
            local title = toolFrame and toolFrame:FindFirstChild("Title", true)

            if title and title:IsA("TextLabel") then
                local name = normalize(title.Text)

                if name ~= "" then
                    local data = {
                        Slot = slot.Name,
                        Key = KEY_BY_SLOT[slot.Name],
                        Title = name,
                        Frame = slot,
                    }

                    HotbarService.Slots[slot.Name] = data
                    HotbarService.TitleToSlot[name] = data
                end
            end
        end
    end
end

local function isUtilityTitle(title)
    local value = lower(title)

    for _, word in ipairs(NON_COMBAT_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    return false
end

function HotbarService.AutoCombatSlot()
    local best
    local bestScore = -math.huge

    for _, data in pairs(HotbarService.Slots) do
        if not isUtilityTitle(data.Title) then
            local title = lower(data.Title)
            local score = 10

            for index, word in ipairs(COMBAT_PRIORITY) do
                if title:find(word, 1, true) then
                    score += 100 - index
                    break
                end
            end

            local numericSlot = tonumber(data.Slot)
            if numericSlot then
                score -= numericSlot * 0.01
            end

            if score > bestScore then
                best = data
                bestScore = score
            end
        end
    end

    return best
end

function HotbarService.Resolve(title)
    if title == "Auto" then
        return HotbarService.AutoCombatSlot()
    end

    return HotbarService.TitleToSlot[title]
end

function HotbarService.Press(data)
    if not data or not data.Key then
        return false
    end

    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, data.Key, false, game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false, data.Key, false, game)
    end)
end

function HotbarService.SelectConfigured()
    if next(HotbarService.Slots) == nil then
        HotbarService.Refresh()
    end

    local data = HotbarService.Resolve(Config.SelectedWeapon)
    if not data then
        return nil
    end

    local now = os.clock()

    if Runtime.LastWeaponTitle ~= data.Title
        or now - Runtime.LastWeaponEquip > 8 then

        Runtime.LastWeaponTitle = data.Title
        Runtime.LastWeaponEquip = now
        HotbarService.Press(data)
    end

    return data
end

function HotbarService.GetOptions()
    HotbarService.Refresh()

    local options = {"Auto"}
    local list = {}

    for _, data in pairs(HotbarService.Slots) do
        table.insert(list, data)
    end

    table.sort(list, function(a, b)
        local an = tonumber(a.Slot) or 99
        local bn = tonumber(b.Slot) or 99
        return an < bn
    end)

    for _, data in ipairs(list) do
        table.insert(options, data.Title)
    end

    return options
end

function HotbarService.GetSnapshot()
    HotbarService.Refresh()

    local rows = {}

    for slot, data in pairs(HotbarService.Slots) do
        table.insert(rows, slot .. ": " .. data.Title)
    end

    table.sort(rows)
    return #rows > 0 and table.concat(rows, " | ") or "Hotbar unavailable"
end

-- ============================================================
-- TargetService
-- ============================================================

local TargetService = {}

local function isPlayerEntity(model)
    return model
        and (
            model:GetAttribute("PlayerCharacter") == true
            or Players:FindFirstChild(model.Name) ~= nil
        )
end

function TargetService.IsAliveNPC(model)
    if not model or not model.Parent or not model:IsA("Model") or isPlayerEntity(model) then
        return false
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    return objectRoot(model) ~= nil and (not hum or hum.Health > 0)
end

function TargetService.IsBoss(model)
    if not TargetService.IsAliveNPC(model) then
        return false
    end

    if model:GetAttribute("BossCombat") == true
        or model:GetAttribute("WorldBoss") == true
        or model:GetAttribute("Boss") == true then
        return true
    end

    local text = lower(
        model.Name
        .. " "
        .. tostring(model:GetAttribute("NPCType") or "")
        .. " "
        .. tostring(model:GetAttribute("NPCName") or "")
    )

    return text:find("boss", 1, true) ~= nil
end

function TargetService.IsHostile(model)
    if not TargetService.IsAliveNPC(model) then
        return false
    end

    if TargetService.IsBoss(model) then
        return true
    end

    if model:GetAttribute("Combat") == true
        or model:GetAttribute("NPCCombat") == true then
        return true
    end

    local party = lower(model:GetAttribute("Party") or model:GetAttribute("DefaultParty") or "")

    return party:find("enemy", 1, true) ~= nil
        or party:find("corrupt", 1, true) ~= nil
        or party:find("hostile", 1, true) ~= nil
end

function TargetService.Matches(model, wanted)
    if not TargetService.IsAliveNPC(model) then
        return false
    end

    if wanted == "Any NPC" then
        return true
    elseif wanted == "Nearest Hostile" then
        return TargetService.IsHostile(model)
    elseif wanted == "Boss Only" then
        return TargetService.IsBoss(model)
    end

    return npcMatches(model, wanted)
end

function TargetService.Find(wanted)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model and model.Parent and TargetService.Matches(model, wanted) then
            local distance = distanceTo(model)

            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

function TargetService.FindBoss()
    return TargetService.Find("Boss Only")
end

function TargetService.GetMobOptions()
    local set = {
        ["Nearest Hostile"] = true,
        ["Any NPC"] = true,
        ["Boss Only"] = true,
    }

    local entities = entitiesFolder()

    if entities then
        for _, model in ipairs(entities:GetChildren()) do
            if model:IsA("Model") and not isPlayerEntity(model) then
                local value = tostring(
                    model:GetAttribute("NPCType")
                    or model:GetAttribute("NPCName")
                    or stripRuntimeSuffix(model.Name)
                )

                if value ~= "" then
                    set[value] = true
                end
            end
        end
    end

    local options = {}

    for value in pairs(set) do
        table.insert(options, value)
    end

    table.sort(options)
    return options
end

-- ============================================================
-- TweenController
-- ============================================================

local TweenController = {}

function TweenController.Cancel()
    if Runtime.CurrentTween then
        pcall(function()
            Runtime.CurrentTween:Cancel()
        end)
    end

    Runtime.CurrentTween = nil
    Runtime.CurrentTweenTarget = nil
end

local function movementGoal(targetPart, height, back)
    local position = (
        targetPart.CFrame
        * CFrame.new(0, height or Config.FarmHeight, back or Config.FarmBack)
    ).Position

    return CFrame.lookAt(position, targetPart.Position)
end

function TweenController.MoveTo(object, height, back)
    local ownRoot = rootPart()
    local targetPart = objectRoot(object)

    if not ownRoot or not targetPart then
        return false, "missing"
    end

    local distance = (ownRoot.Position - targetPart.Position).Magnitude

    if distance <= Config.ArrivalDistance then
        TweenController.Cancel()
        return true, "arrived"
    end

    if not Config.TweenEnabled then
        return false, "disabled"
    end

    if Runtime.CurrentTweenTarget == targetPart and Runtime.CurrentTween then
        return false, "moving"
    end

    TweenController.Cancel()

    local duration = math.clamp(
        distance / math.max(40, Config.TweenSpeed),
        0.08,
        12
    )

    local tween = TweenService:Create(
        ownRoot,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {
            CFrame = movementGoal(targetPart, height, back),
        }
    )

    Runtime.CurrentTween = tween
    Runtime.CurrentTweenTarget = targetPart

    tween.Completed:Connect(function()
        if Runtime.CurrentTween == tween then
            Runtime.CurrentTween = nil
            Runtime.CurrentTweenTarget = nil
        end
    end)

    tween:Play()
    return false, "started"
end

-- ============================================================
-- BringService
-- Best-effort client-side stacking; no network ownership bypass
-- ============================================================

local BringService = {}

function BringService.Step(wanted)
    if not Config.BringMobs then
        return
    end

    local ownRoot = rootPart()
    if not ownRoot then
        return
    end

    local stackBase = ownRoot.CFrame * CFrame.new(0, 0, -Config.BringDistance)
    local count = 0

    for model in pairs(Runtime.Entities) do
        if count >= Config.BringLimit then
            break
        end

        if model and model.Parent
            and TargetService.Matches(model, wanted)
            and (Config.BringBosses or not TargetService.IsBoss(model)) then

            local part = objectRoot(model)
            local hum = model:FindFirstChildOfClass("Humanoid")

            if part
                and not part.Anchored
                and (not hum or hum.Health > 0)
                and (part.Position - ownRoot.Position).Magnitude <= Config.BringRadius then

                count += 1

                local row = math.floor((count - 1) / 3)
                local column = (count - 1) % 3
                local offset = CFrame.new((column - 1) * 1.2, 0, row * 1.1)

                pcall(function()
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                    part.CFrame = stackBase * offset
                end)
            end
        end
    end
end

-- ============================================================
-- InteractionService
-- ============================================================

local InteractionService = {}

local firePromptFunction = type(fireproximityprompt) == "function" and fireproximityprompt or nil

function InteractionService.FirePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    if firePromptFunction then
        return pcall(function()
            firePromptFunction(prompt, math.max(0, prompt.HoldDuration or 0))
        end)
    end

    local key = prompt.KeyboardKeyCode
    if not key or key == Enum.KeyCode.Unknown then
        return false
    end

    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(math.max(0.06, (prompt.HoldDuration or 0) + 0.03))
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

function InteractionService.Click(button)
    if not button or not button:IsA("GuiButton") or not isGuiVisible(button) then
        return false
    end

    if type(firesignal) == "function" then
        local ok = pcall(function()
            firesignal(button.Activated)
        end)

        if ok then
            return true
        end
    end

    local position = button.AbsolutePosition
    local size = button.AbsoluteSize

    return pcall(function()
        local x = position.X + size.X / 2
        local y = position.Y + size.Y / 2

        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.025)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

function InteractionService.ProcessDialogue()
    if not Config.AutoDialogue then
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local dialogue = playerGui and playerGui:FindFirstChild("DialogueUI")

    if not dialogue then
        return
    end

    local words = {
        "accept",
        "continue",
        "next",
        "yes",
        "start quest",
        "take quest",
        "complete",
        "finish",
    }

    for _, object in ipairs(dialogue:GetDescendants()) do
        if object:IsA("GuiButton") and isGuiVisible(object) then
            local text = lower(object.Name .. " " .. textOf(object))

            for _, word in ipairs(words) do
                if text:find(word, 1, true) then
                    InteractionService.Click(object)
                    return
                end
            end
        end
    end
end

function InteractionService.ProcessClaims()
    if not Config.AutoClaim then
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("GuiButton")
            and isGuiVisible(object)
            and lower(object.Name .. " " .. textOf(object)):find("claim", 1, true) then

            InteractionService.Click(object)
            return
        end
    end
end

local function promptKind(prompt)
    local name = lower(prompt.Name)
    local fullName = lower(prompt:GetFullName())

    if name:find("fruit chest", 1, true) then
        return "FruitChest"
    elseif name:find("world boss chest", 1, true) then
        return "WorldBossChest"
    elseif name == "chest" or name:find("chest", 1, true) then
        return "Chest"
    elseif name:find("ore", 1, true)
        or fullName:find(".ores.", 1, true) then
        return "Ore"
    elseif fullName:find(".crops.", 1, true)
        or fullName:find(".farmgear.", 1, true)
        or fullName:find(".pests.", 1, true) then
        return "Farm"
    elseif name:find("quest", 1, true)
        or name:find("mission", 1, true)
        or name == "trash bag" then
        return "QuestItem"
    elseif name == "pickup"
        or name == "money bag"
        or name == "steal"
        or name == "grab" then
        return "Pickup"
    elseif name:find("dialogue", 1, true) then
        return "Dialogue"
    end

    return "Other"
end

function InteractionService.FindNearestPrompt(filter, maxDistance)
    local best
    local bestDistance = maxDistance or math.huge

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local accepted = not filter or filter(prompt, promptKind(prompt))

            if accepted then
                local distance = distanceTo(prompt)

                if distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best, bestDistance
end

function InteractionService.FindPromptNear(object, preferredKind)
    local targetPart = objectRoot(object)
    if not targetPart then
        return nil
    end

    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local part = objectRoot(prompt)

            if part then
                local distance = (part.Position - targetPart.Position).Magnitude
                local accepted = not preferredKind or promptKind(prompt) == preferredKind

                if accepted
                    and distance <= 30
                    and (not bestDistance or distance < bestDistance) then

                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

function InteractionService.FindPromptByText(targetName)
    local wanted = lower(targetName)

    return InteractionService.FindNearestPrompt(function(prompt)
        local model = prompt:FindFirstAncestorWhichIsA("Model")

        local text = lower(
            prompt.Name
            .. " "
            .. tostring(prompt.ActionText or "")
            .. " "
            .. tostring(prompt.ObjectText or "")
            .. " "
            .. tostring(model and model.Name or "")
        )

        return text:find(wanted, 1, true) ~= nil
    end)
end

-- ============================================================
-- CombatService
-- ============================================================

local CombatService = {}

local function setBlock(held)
    if Runtime.BlockHeld == held then
        return
    end

    Runtime.BlockHeld = held

    pcall(function()
        VirtualInputManager:SendKeyEvent(held, Enum.KeyCode.F, false, game)
    end)
end

function CombatService.AimAt(model)
    if not Config.AutoAim then
        return
    end

    local ownRoot = rootPart()
    local targetPart = objectRoot(model)

    if ownRoot and targetPart then
        local position = ownRoot.Position

        pcall(function()
            ownRoot.CFrame = CFrame.lookAt(
                position,
                Vector3.new(targetPart.Position.X, position.Y, targetPart.Position.Z)
            )
        end)
    end
end

function CombatService.Attack()
    if not Config.AutoAttack then
        return
    end

    local now = os.clock()
    local delay = 1 / math.max(1, Config.AttackRate)

    if now - Runtime.LastAttack < delay then
        return
    end

    Runtime.LastAttack = now

    local selected = HotbarService.SelectConfigured()

    local camera = Workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(800, 600)

    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(
            size.X / 2,
            size.Y / 2,
            0,
            true,
            game,
            0
        )

        task.wait(0.02)

        VirtualInputManager:SendMouseButtonEvent(
            size.X / 2,
            size.Y / 2,
            0,
            false,
            game,
            0
        )
    end)

    if Config.AutoSkill
        and selected
        and now - Runtime.LastSkill >= Config.AutoSkillDelay then

        Runtime.LastSkill = now
        HotbarService.Press(selected)
    end
end

function CombatService.UpdateBlock()
    if not Config.AutoBlock then
        setBlock(false)
        return
    end

    local target = Runtime.CurrentTarget
    local shouldBlock = target
        and target.Parent
        and distanceTo(target) <= 20
        and PlayerState.GetHealthPercent() <= Config.BlockHealthPercent

    setBlock(shouldBlock == true)
end

-- ============================================================
-- Quest automation helpers
-- ============================================================

local function findQuestEntity(targetName)
    return TargetService.Find(targetName)
end

local function moveAndInteract(object, stateName, detail, promptType)
    if not object then
        Runtime.WorkerState = "Searching"
        Runtime.WorkerDetail = detail
        return false
    end

    Runtime.CurrentTarget = object
    Runtime.CurrentTargetReason = detail

    if distanceTo(object) > Config.ArrivalDistance then
        TweenController.MoveTo(object)
        Runtime.WorkerState = "Tweening"
        Runtime.WorkerDetail = detail
        return false
    end

    TweenController.Cancel()
    Runtime.WorkerState = stateName
    Runtime.WorkerDetail = detail

    local prompt = InteractionService.FindPromptNear(object, promptType)
        or InteractionService.FindPromptByText(detail)

    if prompt then
        InteractionService.FirePrompt(prompt)
    end

    return true
end

local function handleQuestNonCombat()
    if not Config.AutoQuest then
        return false
    end

    local completed = QuestService.GetCompletedQuest()

    if completed and Config.AutoTurnIn then
        local npc = QuestService.FindDialogueNPC(completed.Name)

        if moveAndInteract(
            npc,
            "Quest Turn In",
            completed.Name,
            "Dialogue"
        ) then
            InteractionService.ProcessDialogue()
        end

        return true
    end

    local quest, taskData = QuestService.GetNextTask()

    if quest and taskData and taskData.Kind ~= "Defeat" then
        if taskData.Kind == "Talk"
            or taskData.Kind == "Return"
            or taskData.Kind == "Deliver" then

            local npc = QuestService.FindDialogueNPC(quest.Name, taskData.Target)
                or TargetService.Find(taskData.Target)

            if moveAndInteract(
                npc,
                "Quest Dialogue",
                taskData.Target,
                "Dialogue"
            ) then
                InteractionService.ProcessDialogue()
            end

            return true
        end

        if taskData.Kind == "Collect" or taskData.Kind == "Find" then
            local prompt = InteractionService.FindPromptByText(taskData.Target)

            if prompt then
                if distanceTo(prompt) > Config.ArrivalDistance then
                    Runtime.CurrentTarget = prompt
                    Runtime.CurrentTargetReason = taskData.Text
                    TweenController.MoveTo(prompt)
                else
                    TweenController.Cancel()
                    InteractionService.FirePrompt(prompt)
                end
            else
                local target = TargetService.Find(taskData.Target)
                moveAndInteract(target, "Quest Collect", taskData.Target)
            end

            return true
        end

        local prompt = InteractionService.FindPromptByText(taskData.Target)
        local target = prompt or TargetService.Find(taskData.Target)

        if target then
            if distanceTo(target) > Config.ArrivalDistance then
                Runtime.CurrentTarget = target
                Runtime.CurrentTargetReason = taskData.Text
                TweenController.MoveTo(target)
            elseif prompt then
                InteractionService.FirePrompt(prompt)
            end
        end

        return true
    end

    if not quest then
        local recommended = QuestService.GetRecommended()

        if recommended and Config.AutoAcceptRecommended then
            local npc = QuestService.FindDialogueNPC(recommended.Name)

            if moveAndInteract(
                npc,
                "Accept Quest",
                recommended.Name,
                "Dialogue"
            ) then
                InteractionService.ProcessDialogue()
            end

            return true
        end
    end

    return false
end

-- ============================================================
-- FarmService
-- ============================================================

local FarmService = {}

function FarmService.ResolveWanted()
    if Config.FarmMode == "Boss" or Config.AutoBoss then
        return "Boss Only", "Boss"
    end

    if Config.FarmMode == "Selected Mob" then
        return Config.SelectedMob, "Selected Mob"
    end

    local quest, taskData = QuestService.GetNextTask()

    if quest and taskData and taskData.Kind == "Defeat" then
        return taskData.Target, "Quest: " .. quest.Name
    end

    return Config.SelectedMob, "Fallback"
end

function FarmService.Step()
    if not Config.AutoFarm then
        if Runtime.CurrentTargetReason and Runtime.CurrentTargetReason:find("Farm", 1, true) then
            Runtime.CurrentTarget = nil
            Runtime.CurrentTargetReason = nil
        end

        return
    end

    if not PlayerState.IsReady() then
        Runtime.WorkerState = "Waiting"
        Runtime.WorkerDetail = "Player data loading"
        return
    end

    if Config.FarmMode == "Smart Quest" and handleQuestNonCombat() then
        return
    end

    local wanted, reason = FarmService.ResolveWanted()
    local target = TargetService.Find(wanted)

    if not target then
        Runtime.CurrentTarget = nil
        Runtime.WorkerState = "Searching"
        Runtime.WorkerDetail = wanted
        return
    end

    Runtime.CurrentTarget = target
    Runtime.CurrentTargetReason = "Farm • " .. reason

    BringService.Step(wanted)

    if distanceTo(target) > Config.CombatDistance then
        TweenController.MoveTo(target, Config.FarmHeight, Config.FarmBack)
        Runtime.WorkerState = "Tweening"
        Runtime.WorkerDetail = wanted
        return
    end

    TweenController.Cancel()
    Runtime.WorkerState = "Farming"
    Runtime.WorkerDetail = wanted

    CombatService.AimAt(target)
    CombatService.Attack()
end

-- ============================================================
-- LifeSkillService / collection
-- ============================================================

local LifeSkillService = {}

local function manualPromptEnabled(kind)
    return kind == "Pickup" and Config.AutoPickup
        or kind == "Chest" and Config.AutoChest
        or kind == "WorldBossChest" and Config.AutoWorldBossChest
        or kind == "FruitChest" and Config.AutoFruitChest
        or kind == "QuestItem" and Config.AutoQuestItems
        or kind == "Ore" and Config.AutoMining
        or kind == "Farm" and Config.AutoFarming
end

function LifeSkillService.ProcessPrompts()
    if Config.AutoFarm then
        -- Farm owns movement. Only collect close prompts while farming.
        local prompt = InteractionService.FindNearestPrompt(function(_, kind)
            return manualPromptEnabled(kind)
        end, 12)

        if prompt then
            InteractionService.FirePrompt(prompt)
        end

        return
    end

    local prompt = InteractionService.FindNearestPrompt(function(_, kind)
        return manualPromptEnabled(kind)
    end)

    if not prompt then
        return
    end

    if promptKind(prompt) == "Ore" then
        local pickaxe = HotbarService.TitleToSlot["Rusty Pickaxe"]

        if not pickaxe then
            for title, data in pairs(HotbarService.TitleToSlot) do
                if lower(title):find("pickaxe", 1, true) then
                    pickaxe = data
                    break
                end
            end
        end

        if pickaxe then
            HotbarService.Press(pickaxe)
        end
    end

    Runtime.CurrentTarget = prompt
    Runtime.CurrentTargetReason = "Lifeskill • " .. promptKind(prompt)

    if distanceTo(prompt) > Config.ArrivalDistance then
        TweenController.MoveTo(prompt, 2.5, 2)
    else
        TweenController.Cancel()
        InteractionService.FirePrompt(prompt)
    end
end

local function fishingGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Fishing")
end

function LifeSkillService.ProcessFishing()
    if not Config.AutoFishing or Config.AutoFarm then
        return
    end

    local gui = fishingGui()
    local main = gui and gui:FindFirstChild("Main")
    local active = gui
        and (not gui:IsA("ScreenGui") or gui.Enabled)
        and main
        and main.Visible

    local rod

    for title, data in pairs(HotbarService.TitleToSlot) do
        if lower(title):find("rod", 1, true) then
            rod = data
            break
        end
    end

    if active then
        local move = main:FindFirstChild("Move")
        local fish = main:FindFirstChild("Fish")

        if move and fish
            and move:IsA("GuiObject")
            and fish:IsA("GuiObject") then

            local moveX = move.AbsolutePosition.X + move.AbsoluteSize.X / 2
            local fishX = fish.AbsolutePosition.X + fish.AbsoluteSize.X / 2
            local delta = fishX - moveX

            if math.abs(delta) > 15 then
                local key = delta > 0 and Enum.KeyCode.D or Enum.KeyCode.A

                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, key, false, game)
                    task.wait(0.03)
                    VirtualInputManager:SendKeyEvent(false, key, false, game)
                end)
            end
        end

        return
    end

    if rod and os.clock() - Runtime.LastFishingCast > 3 then
        Runtime.LastFishingCast = os.clock()
        HotbarService.Press(rod)
    end
end

function LifeSkillService.TweenNearestDigSpot()
    local islands = Workspace:FindFirstChild("Islands")
    local ownRoot = rootPart()

    if not islands or not ownRoot then
        return
    end

    local best
    local bestDistance

    for _, descendant in ipairs(islands:GetDescendants()) do
        if descendant:IsA("BasePart")
            and descendant.Parent
            and descendant.Parent.Name == "DigSpots" then

            local distance = (ownRoot.Position - descendant.Position).Magnitude

            if not bestDistance or distance < bestDistance then
                best = descendant
                bestDistance = distance
            end
        end
    end

    if best then
        TweenController.MoveTo(best, 3, 0)
    else
        notify("Treasure", "Không tìm thấy DigSpot client-visible.", 3)
    end
end

-- ============================================================
-- Character modifiers
-- ============================================================

local function restoreCollision()
    for part, original in pairs(Core.CollisionBackup) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(Core.CollisionBackup)
end

local function processCharacter()
    local hum = humanoid()
    local char = character()

    if hum then
        if Config.SpeedOverride then
            hum.WalkSpeed = Config.WalkSpeed
        end

        if Config.JumpOverride then
            if hum.UseJumpPower then
                hum.JumpPower = Config.JumpPower
            else
                hum.JumpHeight = math.max(7.2, Config.JumpPower / 7)
            end
        end
    end

    local shouldNoclip = Config.Noclip
        or (Config.TweenNoclip and Runtime.CurrentTween ~= nil)

    if shouldNoclip and char then
        for _, object in ipairs(char:GetDescendants()) do
            if object:IsA("BasePart") then
                if Core.CollisionBackup[object] == nil then
                    Core.CollisionBackup[object] = object.CanCollide
                end

                object.CanCollide = false
            end
        end
    elseif next(Core.CollisionBackup) ~= nil then
        restoreCollision()
    end
end

connect(RunService.Stepped, function()
    if Core.Running then
        processCharacter()
    end
end)

connect(UserInputService.JumpRequest, function()
    if Core.Running and Config.InfiniteJump then
        local hum = humanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ============================================================
-- ESPService
-- ============================================================

local ESPService = {
    Folder = track(Instance.new("Folder")),
    Map = setmetatable({}, {__mode = "k"}),
}

ESPService.Folder.Name = "SON_HUB_ESP"

pcall(function()
    ESPService.Folder.Parent = CoreGui
end)

if not ESPService.Folder.Parent then
    ESPService.Folder.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

function ESPService.Clear(object)
    local highlight = ESPService.Map[object]

    if highlight then
        pcall(function()
            highlight:Destroy()
        end)

        ESPService.Map[object] = nil
    end
end

function ESPService.Set(object, color)
    if not object or not object.Parent or distanceTo(object) > Config.ESPDistance then
        ESPService.Clear(object)
        return
    end

    local adornee

    if object:IsA("Model") or object:IsA("BasePart") then
        adornee = object
    else
        adornee = object:FindFirstAncestorWhichIsA("Model") or objectRoot(object)
    end

    if not adornee then
        return
    end

    local highlight = ESPService.Map[object]

    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.05
        highlight.Parent = ESPService.Folder
        ESPService.Map[object] = highlight
    end

    highlight.Adornee = adornee
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.Enabled = true
end

function ESPService.Step()
    local active = {}

    if Config.QuestTargetESP and Runtime.CurrentTarget then
        active[Runtime.CurrentTarget] = true
        ESPService.Set(Runtime.CurrentTarget, Config.QuestColor)
    end

    if Config.MobESP or Config.BossESP then
        for model in pairs(Runtime.Entities) do
            if TargetService.IsAliveNPC(model) then
                if Config.BossESP and TargetService.IsBoss(model) then
                    active[model] = true
                    ESPService.Set(model, Config.BossColor)
                elseif Config.MobESP and not TargetService.IsBoss(model) then
                    active[model] = true
                    ESPService.Set(model, Config.MobColor)
                end
            end
        end
    end

    if Config.LootESP then
        for prompt in pairs(Runtime.Prompts) do
            if prompt and prompt.Parent then
                local kind = promptKind(prompt)

                if kind == "Pickup"
                    or kind == "Chest"
                    or kind == "WorldBossChest"
                    or kind == "FruitChest"
                    or kind == "QuestItem" then

                    active[prompt] = true
                    ESPService.Set(prompt, Config.LootColor)
                end
            end
        end
    end

    for object in pairs(ESPService.Map) do
        if not active[object] or not object.Parent then
            ESPService.Clear(object)
        end
    end
end

-- ============================================================
-- Progress monitor
-- ============================================================

local function monitorProgress()
    local level = PlayerState.GetLevel()

    if Runtime.LastLevel == nil then
        Runtime.LastLevel = level
    elseif Runtime.LastLevel ~= level then
        local oldLevel = Runtime.LastLevel
        Runtime.LastLevel = level

        notify(
            "Level Up",
            string.format("Lv.%d → Lv.%d • Auto Farm recalculating", oldLevel, level),
            4
        )

        TweenController.Cancel()
    end

    local questKey = QuestService.StateKey()

    if Runtime.LastQuestKey == nil then
        Runtime.LastQuestKey = questKey
    elseif Runtime.LastQuestKey ~= questKey then
        Runtime.LastQuestKey = questKey
        TweenController.Cancel()
    end
end

-- ============================================================
-- Main loops
-- ============================================================

task.spawn(function()
    while Core.Running do
        monitorProgress()
        FarmService.Step()
        CombatService.UpdateBlock()
        task.wait(0.10)
    end
end)

task.spawn(function()
    while Core.Running do
        LifeSkillService.ProcessPrompts()
        task.wait(0.18)
    end
end)

task.spawn(function()
    while Core.Running do
        InteractionService.ProcessDialogue()
        InteractionService.ProcessClaims()
        LifeSkillService.ProcessFishing()
        task.wait(0.10)
    end
end)

task.spawn(function()
    while Core.Running do
        ESPService.Step()
        task.wait(0.65)
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end

        task.wait(55)
    end
end)

-- ============================================================
-- Runtime info
-- ============================================================

local function currentQuestText()
    local quest, taskData = QuestService.GetNextTask()

    if quest and taskData then
        return quest.Name .. " → " .. taskData.Text
    end

    local complete = QuestService.GetCompletedQuest()
    if complete then
        return complete.Name .. " → Ready to turn in"
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "Recommended → " .. recommended.Name
    end

    return "None"
end

local function homeStatus()
    local hum = humanoid()
    local health = hum and string.format("%.0f/%.0f", hum.Health, hum.MaxHealth) or "Unknown"

    return table.concat({
        "SON HUB v" .. VERSION,
        "Level: " .. PlayerState.GetLevel(),
        "World: " .. PlayerState.GetWorld(),
        "Fruit: " .. PlayerState.GetFruit() .. " (Lv." .. PlayerState.GetFruitLevel() .. ")",
        "Bounty: " .. PlayerState.GetBounty(),
        "Faction: " .. PlayerState.GetLeaderString("Faction"),
        "Crew: " .. (PlayerState.GetLeaderString("Crew") ~= "" and PlayerState.GetLeaderString("Crew") or "None"),
        "Health: " .. health,
        "Weapon Types: " .. PlayerState.GetWeaponTypes(),
        "Quest: " .. currentQuestText(),
        "Worker: " .. Runtime.WorkerState .. " • " .. Runtime.WorkerDetail,
        "Hotbar: " .. HotbarService.GetSnapshot(),
    }, "\n")
end

local function detectedSystems()
    return table.concat({
        "Quest + RecommendedQuest",
        "Entities / NPC Combat / BossCombat",
        "Custom Backpack + 0-9 Hotbar",
        "Fruit + Fruit Level",
        "Bounty / Faction / Crew",
        "Pickup / Money Bag / Quest Item",
        "Fruit Chest / World Boss Chest",
        "Fishing",
        "Mining / Ores",
        "Farming / Crops / FarmGear / Pests",
        "Treasure Map DigSpots",
        "Crafting / Blacksmith UI",
        "Ships / Ship Spawn",
        "Trade / Crews",
        "Logbook achievements + Claim",
        "Block (F) / Dash systems",
    }, "\n")
end

-- ============================================================
-- UI — exact requested tab structure
-- ============================================================

local Window = Library:CreateWindow({
    Title = "SON HUB",
    Subtitle = "Automatic Progress • make by hongson",
    SubtitleColor = Color3.fromRGB(100, 190, 255),

    -- Uses the library's own example asset instead of random external icons.
    Logo = "rbxassetid://82367817676382",
    LogoSize = 32,

    SphereText = true,
    SphereWords = "S",
    SphereImage = "rbxassetid://82367817676382",
    SphereIconSize = 38,
})

-- ============================================================
-- 🏠 Home
-- ============================================================

local HomeTab = Window:CreateTab("🏠 Trang Chủ", true, false)
local HomePage = HomeTab:CreatePage("Dashboard")

local HomeStatusCard = HomePage:CreateSection("Player Status")

HomeStatusCard:AddButton("Refresh Player Status", function()
    notify("SON HUB • Status", homeStatus(), 8)
end, {
    Title = "Live Player Status",
    Description = "Đọc trực tiếp Level, World, Fruit, Bounty, Faction, Crew, Health, Weapon và Quest hiện tại.",
})

HomeStatusCard:AddButton("Refresh Hotbar / Weapons", function()
    HotbarService.Refresh()
    notify("Hotbar", HotbarService.GetSnapshot(), 6)
end)

local QuickCard = HomePage:CreateSection("Quick Automation")

QuickCard:AddToggle("Full Auto Farm", false, function(value)
    Config.AutoFarm = value

    if value then
        Config.FarmMode = "Smart Quest"
        Config.AutoQuest = true
        notify("Auto Farm", "Smart Quest mode activated.", 3)
    else
        TweenController.Cancel()
        Runtime.CurrentTarget = nil
    end
end, {
    Title = "One Toggle Progress",
    Description = "Tự đọc level + quest, nhận quest phù hợp, Tween, đánh mob, làm task và turn-in.",
})

QuickCard:AddToggle("Auto Claim Rewards", true, function(value)
    Config.AutoClaim = value
end)

-- ============================================================
-- ⚔️ Farm
-- ============================================================

local FarmTab = Window:CreateTab("⚔️ Farm", false, false)
local FarmMainPage = FarmTab:CreatePage("Auto Farm")
local FarmAdvancedPage = FarmTab:CreatePage("Bring / Weapon")

local FarmCard = FarmMainPage:CreateSection("Farm Worker")

FarmCard:AddToggle("Auto Farm", false, function(value)
    Config.AutoFarm = value

    if not value then
        TweenController.Cancel()
        Runtime.CurrentTarget = nil
    end
end, {
    Title = "Auto Farm Master",
    Description = "Smart Quest mặc định tự check Level + Quest; cũng có thể farm mob hoặc boss thủ công.",
})

FarmCard:AddDropdown(
    "Farm Mode",
    {"Smart Quest", "Selected Mob", "Boss"},
    false,
    function(selected)
        Config.FarmMode = selected
        TweenController.Cancel()
    end,
    {
        Title = "Farm Mode",
        Description = "Smart Quest = full automatic. Selected Mob = farm loại mob chọn. Boss = ưu tiên boss client-visible.",
    }
)

local mobOptions = TargetService.GetMobOptions()

FarmCard:AddDropdown("Select Mob", mobOptions, false, function(selected)
    Config.SelectedMob = selected
    TweenController.Cancel()
end)

FarmCard:AddToggle("Auto Attack", true, function(value)
    Config.AutoAttack = value
end)

FarmCard:AddSlider("Attack / Second", 2, 20, Config.AttackRate, function(value)
    Config.AttackRate = value
end)

FarmCard:AddToggle("Auto Loot While Farming", true, function(value)
    Config.AutoLootAfterFarm = value
    Config.AutoPickup = value
end)

local WeaponCard = FarmAdvancedPage:CreateSection("Weapon / Hotbar")

local weaponOptions = HotbarService.GetOptions()

WeaponCard:AddDropdown("Select Weapon", weaponOptions, false, function(selected)
    Config.SelectedWeapon = selected
    Runtime.LastWeaponTitle = nil
end, {
    Title = "Select Weapon",
    Description = "Danh sách lấy trực tiếp từ custom Hotbar của game. Auto bỏ qua Key/Fragment/Rock/Pickaxe và ưu tiên skill combat.",
})

WeaponCard:AddButton("Refresh Weapon Detection", function()
    HotbarService.Refresh()
    notify("Detected Weapons", HotbarService.GetSnapshot(), 6)
end)

WeaponCard:AddToggle("Auto Use Selected Skill", false, function(value)
    Config.AutoSkill = value
end, {
    Title = "Auto Skill",
    Description = "Ngoài M1, định kỳ kích hoạt slot/hotbar đã chọn.",
})

WeaponCard:AddSlider("Skill Interval", 1, 8, Config.AutoSkillDelay, function(value)
    Config.AutoSkillDelay = value
end)

local BringCard = FarmAdvancedPage:CreateSection("Bring Mobs")

BringCard:AddToggle("Bring Mobs", false, function(value)
    Config.BringMobs = value
end, {
    Title = "Bring Mobs",
    Description = "Best-effort client stacking các mob phù hợp gần người chơi. Không ép network ownership hay gọi remote đoán.",
})

BringCard:AddSlider("Bring Radius", 20, 200, Config.BringRadius, function(value)
    Config.BringRadius = value
end)

BringCard:AddSlider("Mob Limit", 1, 20, Config.BringLimit, function(value)
    Config.BringLimit = value
end)

BringCard:AddSlider("Stack Distance", 2, 12, Config.BringDistance, function(value)
    Config.BringDistance = value
end)

BringCard:AddToggle("Allow Bring Boss", false, function(value)
    Config.BringBosses = value
end)

-- ============================================================
-- 💀 Combat
-- ============================================================

local CombatTab = Window:CreateTab("💀 Combat", false, false)
local CombatPage = CombatTab:CreatePage("Chiến Đấu")

local CombatCard = CombatPage:CreateSection("Combat Assist")

CombatCard:AddToggle("Auto Aim Target", true, function(value)
    Config.AutoAim = value
end)

CombatCard:AddToggle("Boss Priority", false, function(value)
    Config.AutoBoss = value

    if value and Config.AutoFarm then
        Config.FarmMode = "Boss"
    end
end)

CombatCard:AddSlider("Combat Distance", 3, 15, Config.CombatDistance, function(value)
    Config.CombatDistance = value
end)

CombatCard:AddSlider("Farm Height", 0, 14, Config.FarmHeight, function(value)
    Config.FarmHeight = value
end)

CombatCard:AddSlider("Farm Back", 0, 12, Config.FarmBack, function(value)
    Config.FarmBack = value
end)

local DefenseCard = CombatPage:CreateSection("Defense")

DefenseCard:AddToggle("Auto Block Low HP", false, function(value)
    Config.AutoBlock = value
    if not value then
        setBlock(false)
    end
end, {
    Title = "Auto Block",
    Description = "Game tutorial trong dump xác nhận block dùng phím F. Hub chỉ giữ F khi HP thấp và target đang gần.",
})

DefenseCard:AddSlider("Block Below HP %", 10, 80, Config.BlockHealthPercent, function(value)
    Config.BlockHealthPercent = value
end)

local CombatESPCard = CombatPage:CreateSection("Target Visual")

CombatESPCard:AddToggle("Current Target ESP", true, function(value)
    Config.QuestTargetESP = value
end)

CombatESPCard:AddToggle("Mob ESP", false, function(value)
    Config.MobESP = value
end)

CombatESPCard:AddToggle("Boss ESP", false, function(value)
    Config.BossESP = value
end)

-- ============================================================
-- 🏃 Movement
-- ============================================================

local MovementTab = Window:CreateTab("🏃 Movement", false, false)
local TweenPage = MovementTab:CreatePage("Tween")
local CharacterPage = MovementTab:CreatePage("Character")

local TweenCard = TweenPage:CreateSection("Tween Controller")

TweenCard:AddToggle("Tween Movement", true, function(value)
    Config.TweenEnabled = value

    if not value then
        TweenController.Cancel()
    end
end)

TweenCard:AddSlider("Tween Speed", 50, 450, Config.TweenSpeed, function(value)
    Config.TweenSpeed = value
end)

TweenCard:AddSlider("Arrival Distance", 3, 15, Config.ArrivalDistance, function(value)
    Config.ArrivalDistance = value
end)

TweenCard:AddToggle("Tween Noclip", true, function(value)
    Config.TweenNoclip = value
end)

TweenCard:AddButton("Stop Current Tween", TweenController.Cancel)

local CharacterCard = CharacterPage:CreateSection("Movement Overrides")

CharacterCard:AddToggle("WalkSpeed", false, function(value)
    Config.SpeedOverride = value
end)

CharacterCard:AddSlider("Walk Speed", 16, 120, Config.WalkSpeed, function(value)
    Config.WalkSpeed = value
end)

CharacterCard:AddToggle("Jump Override", false, function(value)
    Config.JumpOverride = value
end)

CharacterCard:AddSlider("Jump Power", 40, 150, Config.JumpPower, function(value)
    Config.JumpPower = value
end)

CharacterCard:AddToggle("Infinite Jump", false, function(value)
    Config.InfiniteJump = value
end)

CharacterCard:AddToggle("Noclip", false, function(value)
    Config.Noclip = value

    if not value and Runtime.CurrentTween == nil then
        restoreCollision()
    end
end)

-- ============================================================
-- 👤 Player
-- ============================================================

local PlayerTab = Window:CreateTab("👤 Player", false, false)
local LootPage = PlayerTab:CreatePage("Loot")
local LifePage = PlayerTab:CreatePage("Life Skills")

local LootCard = LootPage:CreateSection("Automatic Loot")

LootCard:AddToggle("Auto Pickup", false, function(value)
    Config.AutoPickup = value
end)

LootCard:AddToggle("Auto Chest", false, function(value)
    Config.AutoChest = value
end)

LootCard:AddToggle("Auto World Boss Chest", false, function(value)
    Config.AutoWorldBossChest = value
end, {
    Title = "World Boss Chest",
    Description = "Dump có WorldBossChestHandler và prompt World Boss Chest riêng.",
})

LootCard:AddToggle("Auto Fruit Chest", false, function(value)
    Config.AutoFruitChest = value
end)

LootCard:AddToggle("Auto Quest Items", false, function(value)
    Config.AutoQuestItems = value
end)

LootCard:AddToggle("Loot ESP", false, function(value)
    Config.LootESP = value
end)

local LifeCard = LifePage:CreateSection("Lifeskills")

LifeCard:AddToggle("Auto Mining", false, function(value)
    Config.AutoMining = value
end, {
    Title = "Auto Mining",
    Description = "Tự tìm Ore prompt và ưu tiên Rusty Pickaxe / hotbar pickaxe nếu có.",
})

LifeCard:AddToggle("Auto Farming", false, function(value)
    Config.AutoFarming = value
end)

LifeCard:AddToggle("Auto Fishing", false, function(value)
    Config.AutoFishing = value
    Runtime.LastFishingCast = 0
end, {
    Title = "Auto Fishing",
    Description = "Dùng PlayerGui.Fishing/Main/Move + Fish để tự điều khiển minigame khi UI đang active.",
})

LifeCard:AddButton("Tween Nearest Treasure DigSpot", function()
    LifeSkillService.TweenNearestDigSpot()
end, {
    Title = "Treasure Helper",
    Description = "Dump có TreasureMapLocations/DigSpots trên các island; nút này Tween tới DigSpot gần nhất.",
})

local PlayerUtilityCard = LifePage:CreateSection("Player Utility")

PlayerUtilityCard:AddToggle("Anti AFK", true, function(value)
    Config.AntiAFK = value
end)

-- ============================================================
-- 📜 Quest
-- ============================================================

local QuestTab = Window:CreateTab("📜 Quest", false, false)
local QuestPage = QuestTab:CreatePage("Nhiệm Vụ")

local QuestCard = QuestPage:CreateSection("Quest Automation")

QuestCard:AddToggle("Auto Quest", true, function(value)
    Config.AutoQuest = value
end, {
    Title = "Auto Quest",
    Description = "Đọc trực tiếp PlayerGui.Quests: QuestId, QuestName, Task progress và RecommendedQuest.",
})

QuestCard:AddToggle("Auto Accept Recommended", true, function(value)
    Config.AutoAcceptRecommended = value
end)

QuestCard:AddToggle("Auto Turn In", true, function(value)
    Config.AutoTurnIn = value
end)

QuestCard:AddToggle("Auto Dialogue", true, function(value)
    Config.AutoDialogue = value
end)

QuestCard:AddToggle("Auto Claim Reward", true, function(value)
    Config.AutoClaim = value
end)

local QuestStatusCard = QuestPage:CreateSection("Quest State")

QuestStatusCard:AddButton("Show Current Quest", function()
    notify(
        "Quest State",
        "Level: " .. PlayerState.GetLevel()
            .. "\n"
            .. currentQuestText()
            .. "\nRecommended: "
            .. tostring((QuestService.GetRecommended() or {}).Name or "None"),
        7
    )
end)

QuestStatusCard:AddButton("Tween To Current Quest Target", function()
    local quest, taskData = QuestService.GetNextTask()

    if not quest or not taskData then
        notify("Quest", "Không có task chưa hoàn thành.", 3)
        return
    end

    local target

    if taskData.Kind == "Defeat" then
        target = TargetService.Find(taskData.Target)
    elseif taskData.Kind == "Talk" or taskData.Kind == "Return" then
        target = QuestService.FindDialogueNPC(quest.Name, taskData.Target)
            or TargetService.Find(taskData.Target)
    else
        target = InteractionService.FindPromptByText(taskData.Target)
            or TargetService.Find(taskData.Target)
    end

    if target then
        Runtime.CurrentTarget = target
        Runtime.CurrentTargetReason = taskData.Text
        TweenController.MoveTo(target)
    else
        notify("Quest", "Chưa resolve được target: " .. taskData.Target, 3)
    end
end)

-- ============================================================
-- ⚙️ Settings
-- ============================================================

local SettingsTab = Window:CreateTab("⚙️ Settings", false, false)
local SettingsPage = SettingsTab:CreatePage("Cài Đặt")

local UISettingsCard = SettingsPage:CreateSection("Interface")

UISettingsCard:AddToggle("Glass UI", false, function(value)
    Window:SetTransparency(value and 0.18 or 0)
end)

local ConfigCard = SettingsPage:CreateSection("Config")
ConfigCard:AddConfigManager("son_hub_v3")

local RuntimeCard = SettingsPage:CreateSection("Runtime")

RuntimeCard:AddButton("Rebuild Game Index", function()
    task.spawn(function()
        notify("SON HUB", "Rebuilding Explorer cache...", 2)
        RuntimeIndex.Rebuild()
        HotbarService.Refresh()
        notify("SON HUB", "Runtime index rebuilt.", 2)
    end)
end)

RuntimeCard:AddButton("Unload SON HUB", function()
    if ENV.__SON_HUB_UNLOAD then
        ENV.__SON_HUB_UNLOAD()
    end
end)

-- ============================================================
-- ℹ️ Info
-- ============================================================

local InfoTab = Window:CreateTab("ℹ️ Info", false, false)
local InfoPage = InfoTab:CreatePage("Thông Tin")

local AboutCard = InfoPage:CreateSection("SON HUB")

AboutCard:AddCopyButton("Version", VERSION, {
    Title = "SON HUB",
    Description = "make by hongson • clean / no console spam",
})

AboutCard:AddCopyButton("Target PlaceId", tostring(EXPECTED_PLACE_ID))

AboutCard:AddButton("Show Detected Game Systems", function()
    notify("Detected Systems", detectedSystems(), 10)
end)

AboutCard:AddButton("Show Full Runtime Status", function()
    notify("SON HUB • Runtime", homeStatus(), 10)
end)

local SourceCard = InfoPage:CreateSection("Dump Basis")

SourceCard:AddButton("Snapshot Information", function()
    notify(
        "DexBridge Snapshot",
        "232,910 Instances\n27,826 UI objects\n31,197 script objects\n0 script source files\nMode: balanced",
        7
    )
end)

-- ============================================================
-- Cleanup
-- ============================================================

local function unload()
    if not Core.Running then
        return
    end

    Core.Running = false
    Config.AutoFarm = false
    Config.BringMobs = false

    setBlock(false)
    TweenController.Cancel()
    restoreCollision()

    for _, connection in ipairs(Core.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Core.Connections)

    for object in pairs(ESPService.Map) do
        ESPService.Clear(object)
    end

    for _, instance in ipairs(Core.Instances) do
        pcall(function()
            instance:Destroy()
        end)
    end

    table.clear(Core.Instances)
    ENV.__SON_HUB_UNLOAD = nil
end

ENV.__SON_HUB_UNLOAD = unload

-- ============================================================
-- Startup
-- ============================================================

task.defer(function()
    HotbarService.Refresh()

    local mismatch = game.PlaceId ~= EXPECTED_PLACE_ID
    local prefix = mismatch
        and ("Place mismatch: " .. tostring(game.PlaceId) .. "\n")
        or ""

    notify(
        "SON HUB Ready",
        prefix
            .. "Lv."
            .. PlayerState.GetLevel()
            .. " • "
            .. PlayerState.GetFruit()
            .. " • "
            .. currentQuestText(),
        6
    )
end)
