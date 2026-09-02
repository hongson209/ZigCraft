--[[
    SON HUB v6
    Target snapshot: PlaceId 118635363908336
    UI: ZyronX UI Library
    make by hongson

    Architecture
      Core / RuntimeIndex
      PlayerState / QuestService / QuestCatalogService
      HotbarService / TargetService
      PlatformTransport
      BringService / HitboxService / CombatService / MasteryService
      StatsService
      InteractionService
      FishingService / MiningQTEService / LifeSkillService
      ProgressionController
      ESPService / UI

    Principles
      - One progression owner controls movement/combat.
      - Auto Farm uses a local moving platform instead of tweening HRP directly.
      - Hitbox applies only to combat mobs, never players/dialogue NPCs.
      - Bring only matching farm/quest mobs.
      - No console logging spam.
      - No guessed RemoteEvent/RemoteFunction contracts.
      - Expensive scans are cached or run only when their feature is active.
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local EXPECTED_PLACE_ID = 118635363908336
local VERSION = "6.1.0"

local SON_ICON_URL = "https://cdn.discordapp.com/attachments/1522131539696160882/1544607843666231326/ChatGPT_Image_Jun_14_2026_10_34_47_PM.png?ex=6a991fa7&is=6a97ce27&hm=486693cbb9841a7bdd2743b8af49abd2238e80fc00ac3bd8e55c73857ef9fff6"
local FALLBACK_ICON = "rbxassetid://82367817676382"

-- Forward declarations for clean dependency order.
local QuestService
local QuestCatalogService
local HotbarService
local TargetService
local InteractionService
local PlatformTransport
local BringService
local HitboxService
local CombatService
local MasteryService
local StatsService
local FishingService
local MiningQTEService
local LifeSkillService
local ProgressionController
local ESPService

-- ============================================================
-- Core state
-- ============================================================

local Core = {
    Running = true,
    Connections = {},
    Instances = {},
    CollisionBackup = setmetatable({}, {__mode = "k"}),
}

local Config = {
    -- Full progression
    AutoProgress = false,
    AutoQuest = true,
    AutoAcceptRecommended = true,
    AutoTurnIn = true,
    AutoDialogue = true,
    AutoClaim = true,

    -- Farm
    FarmMode = "Smart Quest",
    SelectedMob = "Nearest Hostile",
    AutoAttack = true,
    AttackRate = 8,

    -- Moving platform
    PlatformTransport = true,
    PlatformSpeed = 185,
    PlatformSize = 8,
    PlatformTransparency = 0.82,
    PlatformFarmHeight = 12,
    PlatformNpcHeight = 3.5,
    PlatformBackDistance = 4,
    PlatformArrivalDistance = 5,
    PlatformRetargetDistance = 10,
    PlatformNoclip = true,

    -- Bring + hitbox
    BringMobs = true,
    BringRadius = 110,
    BringLimit = 10,
    MobBelowFeet = 7,
    BringSpread = 1.4,
    BringBosses = false,

    MobHitbox = true,
    HitboxSize = 10,
    HitboxTransparency = 0.62,
    HitboxBosses = false,

    -- Weapon / mastery
    SelectedWeapon = "Auto",
    AutoMastery = false,
    MasteryMode = "Combat Skills",
    MasteryInterval = 0.45,
    MasteryReadyOnly = true,

    -- Combat
    AutoAim = true,
    AutoBlock = false,
    BlockHealthPercent = 40,

    -- Stats
    AutoStats = false,
    StatBuild = "Auto Weapon",
    StatSpendInterval = 0.25,

    -- Collection / lifeskills
    AutoPickup = false,
    AutoChest = false,
    AutoWorldBossChest = false,
    AutoFruitChest = false,
    AutoQuestItems = false,

    AutoMining = false,
    AutoMiningQTE = true,
    MiningMode = "Quest Required",
    SelectedOre = "Copper Ore",
    MiningCriticalTolerance = 0.035,
    MiningHoldTimeout = 5.0,
    MiningRetryDelay = 0.55,
    MiningAutoAim = true,

    AutoFarming = false,

    AutoFishing = false,
    FishingSpotMode = "Saved Position",
    FishingAutoReturn = true,
    FishingRequireBait = false,
    FishingBiteTimeout = 40,
    FishingCooldown = 2.0,
    FishingReelTolerance = 14,
    FishingAutoCalibrate = true,
    FishingHoldMovesRight = true,
    FishingAutoShake = true,
    FishingAutoSpamClick = true,
    FishingAutoTimedRelease = true,
    FishingReleaseThreshold = 0.92,

    -- Movement / player
    SpeedOverride = false,
    WalkSpeed = 24,
    JumpOverride = false,
    JumpPower = 55,
    InfiniteJump = false,
    Noclip = false,
    AntiAFK = true,

    -- ESP
    CurrentTargetESP = true,
    MobESP = false,
    BossESP = false,
    LootESP = false,
    ESPDistance = 1200,
    TargetColor = Color3.fromRGB(95, 200, 255),
    MobColor = Color3.fromRGB(255, 205, 80),
    BossColor = Color3.fromRGB(255, 75, 95),
    LootColor = Color3.fromRGB(115, 255, 145),
}

local Runtime = {
    Prompts = setmetatable({}, {__mode = "k"}),
    Entities = setmetatable({}, {__mode = "k"}),
    DialogueNPCs = setmetatable({}, {__mode = "k"}),
    DialogueQuestNames = setmetatable({}, {__mode = "k"}),
    Ores = setmetatable({}, {__mode = "k"}),

    IndexReady = false,

    ProgressState = "IDLE",
    ProgressDetail = "Waiting",
    ProgressQuestKey = nil,
    CurrentTarget = nil,
    CurrentWantedMob = nil,
    FarmAnchorCFrame = nil,

    LastInteraction = 0,
    LastQuestChange = 0,
    LastAttack = 0,
    LastBring = 0,
    LastHitbox = 0,
    LastMastery = 0,
    LastStatsSpend = 0,

    TransportPart = nil,
    TransportTween = nil,
    TransportWeld = nil,
    TransportGoal = nil,
    TransportMoving = false,

    ExpandedHitboxes = setmetatable({}, {__mode = "k"}),

    FishingState = "IDLE",
    FishingStateSince = 0,
    FishingSpotCFrame = nil,
    FishingReason = "Disabled",
    FishingHadReel = false,
    FishingMouseHeld = false,
    FishingKeyHeld = nil,
    FishingLastCast = 0,
    FishingRodCache = nil,
    FishingRodCacheAt = 0,
    FishingBaitCache = nil,
    FishingBaitCacheAt = 0,
    FishingLastShakeClick = 0,
    FishingLastShakePosition = nil,
    FishingLastSpamClick = 0,
    FishingTimedReleaseDone = false,
    FishingReelCalibrated = false,
    FishingHoldDirection = 1,
    FishingLastMoveCenter = nil,
    FishingLastMoveVelocity = 0,

    MiningLastQTE = 0,
    MiningState = "IDLE",
    MiningStateSince = 0,
    MiningTarget = nil,
    MiningMouseHeld = false,
    MiningLastAttempt = 0,
    MiningReleaseDone = false,
    ProgressLifeSkill = nil,

    ClaimButtons = setmetatable({}, {__mode = "k"}),

    MasteryCursor = 0,

    BlockHeld = false,

    QuestCatalog = {},
    QuestCatalogByName = {},
    QuestToNPCs = {},

    LastLevel = nil,
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
    local target = objectRoot(object)

    if not ownRoot or not target then
        return math.huge
    end

    return (ownRoot.Position - target.Position).Magnitude
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

local function isScriptTemplateDescendant(object)
    local current = object and object.Parent
    while current and current ~= game do
        if current:IsA("LocalScript")
            or current:IsA("ModuleScript")
            or current:IsA("Script") then
            return true
        end
        current = current.Parent
    end

    return false
end

local function isOnScreen(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") or not isGuiVisible(guiObject) then
        return false
    end

    local pos = guiObject.AbsolutePosition
    local size = guiObject.AbsoluteSize
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

    return size.X > 0
        and size.Y > 0
        and pos.X + size.X >= 0
        and pos.Y + size.Y >= 0
        and pos.X <= viewport.X
        and pos.Y <= viewport.Y
end

local function textOf(object)
    if not object then
        return ""
    end

    if object:IsA("TextLabel")
        or object:IsA("TextButton")
        or object:IsA("TextBox") then
        return normalize(object.Text)
    end

    local label = object:FindFirstChildWhichIsA("TextLabel", true)
    return label and normalize(label.Text) or ""
end

local function pressKey(key, holdTime)
    if not key or key == Enum.KeyCode.Unknown then
        return false
    end

    holdTime = holdTime or 0.035

    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(holdTime)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

local function mouseClickAt(x, y)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.025)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

local function mouseClickCenter()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    return mouseClickAt(viewport.X / 2, viewport.Y / 2)
end

local function mouseButtonAt(x, y, held)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, held, game, 0)
    end)
end

local function screenPointOf(object)
    local camera = Workspace.CurrentCamera
    local part = objectRoot(object)
    if not camera or not part then
        return nil
    end

    local point, visible = camera:WorldToViewportPoint(part.Position)
    if not visible or point.Z <= 0 then
        return nil
    end

    return Vector2.new(point.X, point.Y)
end

local function clickButton(button, allowHiddenSignal)
    if not button or not button:IsA("GuiButton") then
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

    if allowHiddenSignal ~= true and not isGuiVisible(button) then
        return false
    end

    if not isOnScreen(button) then
        return false
    end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize
    return mouseClickAt(pos.X + size.X / 2, pos.Y + size.Y / 2)
end

-- ============================================================
-- Runtime index
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

    if instance:GetAttribute("ObjectType") == "Ore"
        or instance:GetAttribute("Ore") ~= nil then
        Runtime.Ores[instance] = true
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
    Runtime.Ores[instance] = nil
end

function RuntimeIndex.Rebuild()
    Runtime.IndexReady = false

    table.clear(Runtime.Prompts)
    table.clear(Runtime.Entities)
    table.clear(Runtime.DialogueNPCs)
    table.clear(Runtime.DialogueQuestNames)
    table.clear(Runtime.Ores)

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
-- Player state
-- ============================================================

local PlayerState = {}

function PlayerState.GetLevel()
    local direct = tonumber(LocalPlayer:GetAttribute("Level"))
    if direct then
        return direct
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local value = leaderstats and (
        leaderstats:FindFirstChild("Level")
        or leaderstats:FindFirstChild("Lvl")
    )

    if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
        return tonumber(value.Value) or 0
    end

    return 0
end

function PlayerState.GetWorld()
    return tostring(
        LocalPlayer:GetAttribute("WorldType")
        or Workspace:GetAttribute("WorldType")
        or "Unknown"
    )
end

function PlayerState.GetFruit()
    return tostring(LocalPlayer:GetAttribute("Fruit") or "None")
end

function PlayerState.GetFruitLevel()
    return tonumber(LocalPlayer:GetAttribute("FruitLevel")) or 0
end

function PlayerState.GetEntity()
    local entities = entitiesFolder()
    return entities and entities:FindFirstChild(LocalPlayer.Name)
end

function PlayerState.GetWeaponTypes()
    local entity = PlayerState.GetEntity()
    if not entity then
        return {}
    end

    local result = {}
    for index = 1, 3 do
        local value = entity:GetAttribute("WeaponType" .. index)
        if value and tostring(value) ~= "" then
            table.insert(result, tostring(value))
        end
    end

    return result
end

function PlayerState.GetHealthPercent()
    local hum = humanoid()
    if not hum or hum.MaxHealth <= 0 then
        return 100
    end

    return math.clamp((hum.Health / hum.MaxHealth) * 100, 0, 100)
end

function PlayerState.GetLeaderValue(name)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local value = leaderstats and leaderstats:FindFirstChild(name)
    return value and value.Value or nil
end

function PlayerState.IsReady()
    local loaded = LocalPlayer:GetAttribute("Loaded")
    local playerLoaded = LocalPlayer:GetAttribute("PlayerLoaded")

    if loaded == nil and playerLoaded == nil then
        return humanoid() ~= nil and rootPart() ~= nil
    end

    return loaded ~= false
        and playerLoaded ~= false
        and humanoid() ~= nil
        and rootPart() ~= nil
end

-- ============================================================
-- Quest service
-- ============================================================

QuestService = {}

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
    local localScript = quest and quest:FindFirstChild("QuestLocal")
    return localScript and localScript:FindFirstChild("Storage")
end

local function taskIsComplete(frame, rawText)
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

local function parseQuestTask(raw)
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
        {"Use", "^Use%s+(.+)$"},
        {"Equip", "^Equip%s+(.+)$"},
        {"Craft", "^Craft%s+(.+)$"},
        {"Fish", "^Catch%s+(.+)$"},
        {"Fish", "^Fish%s+(.+)$"},
        {"Mine", "^Mine%s+(.+)$"},
        {"Farm", "^Harvest%s+(.+)$"},
        {"Farm", "^Grow%s+(.+)$"},
        {"Cook", "^Cook%s+(.+)$"},
        {"Upgrade", "^Upgrade%s+(.+)$"},
        {"Learn", "^Learn%s+(.+)$"},
    }

    for _, pattern in ipairs(patterns) do
        local target = clean:match(pattern[2])
        if target then
            return pattern[1], normalize(target)
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
                local questName = child:GetAttribute("QuestName")
                local nameLabel = child:FindFirstChild("QuestName", true)

                byId[questId] = {
                    Id = questId,
                    Name = normalize(
                        questName
                        or (nameLabel and textOf(nameLabel))
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
                local raw = info and tostring(info.Text) or ""
                local kind, target = parseQuestTask(raw)

                table.insert(quest.Tasks, {
                    Frame = child,
                    Text = normalize(raw),
                    RawText = raw,
                    Kind = kind,
                    Target = target,
                    Complete = taskIsComplete(child, raw),
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

function QuestService.StateKey()
    local completed = QuestService.GetCompletedQuest()
    if completed then
        return "complete|" .. tostring(completed.Id) .. "|" .. completed.Name
    end

    local quest, taskData = QuestService.GetNextTask()
    if quest and taskData then
        return "task|" .. tostring(quest.Id) .. "|" .. quest.Name .. "|" .. taskData.Text
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "recommended|" .. tostring(recommended.Id) .. "|" .. recommended.Name
    end

    return "idle"
end

-- ============================================================
-- Quest catalog + quest NPC mapping
-- ============================================================

QuestCatalogService = {}

local function questModulesRoot()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local questInfo = modules and modules:FindFirstChild("QuestInfo")
    return questInfo and questInfo:FindFirstChild("Quests")
end

local function relativePath(root, object)
    local names = {}
    local current = object

    while current and current ~= root do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end

    return table.concat(names, "/")
end

local function findDialogueNpcRoot(descendant)
    local root = dialogueRoot()
    if not root then
        return nil
    end

    local current = descendant
    while current and current.Parent do
        if current:IsA("Model")
            and current.Parent.Parent == root then
            return current
        end

        current = current.Parent
    end

    return descendant:FindFirstAncestorWhichIsA("Model")
end

function QuestCatalogService.Build()
    table.clear(Runtime.QuestCatalog)
    table.clear(Runtime.QuestCatalogByName)
    table.clear(Runtime.QuestToNPCs)

    local questsRoot = questModulesRoot()
    if questsRoot then
        for _, object in ipairs(questsRoot:GetDescendants()) do
            if object:IsA("ModuleScript") then
                local entry = {
                    Name = object.Name,
                    Path = relativePath(questsRoot, object),
                    Module = object,
                }

                table.insert(Runtime.QuestCatalog, entry)

                local key = lower(object.Name)
                Runtime.QuestCatalogByName[key] = Runtime.QuestCatalogByName[key] or {}
                table.insert(Runtime.QuestCatalogByName[key], entry)
            end
        end

        table.sort(Runtime.QuestCatalog, function(a, b)
            return lower(a.Path) < lower(b.Path)
        end)
    end

    local root = dialogueRoot()
    if root then
        for _, object in ipairs(root:GetDescendants()) do
            local questName

            if object:IsA("StringValue")
                and object.Name == "QuestName"
                and object.Value ~= "" then
                questName = object.Value
            end

            local questNode = object:GetAttribute("QuestNode")
            if type(questNode) == "string" and questNode ~= "" then
                questName = questName or questNode
            end

            if object:IsA("TextLabel") and object.Name == "QuestLabel" then
                local text = normalize(object.Text)
                if text ~= "" then
                    questName = questName or text
                end
            end

            if questName then
                local npc = findDialogueNpcRoot(object)

                if npc then
                    local key = lower(questName)
                    Runtime.QuestToNPCs[key] = Runtime.QuestToNPCs[key] or {}

                    local exists = false
                    for _, current in ipairs(Runtime.QuestToNPCs[key]) do
                        if current == npc then
                            exists = true
                            break
                        end
                    end

                    if not exists then
                        table.insert(Runtime.QuestToNPCs[key], npc)
                    end
                end
            end
        end
    end
end

function QuestCatalogService.GetNames()
    local names = {}

    for _, entry in ipairs(Runtime.QuestCatalog) do
        table.insert(names, entry.Path)
    end

    if #names == 0 then
        table.insert(names, "Quest catalog unavailable")
    end

    return names
end

function QuestCatalogService.FindQuestGiver(questName, preferredNpc)
    if preferredNpc and preferredNpc ~= "" and TargetService then
        local entity = TargetService.Find(preferredNpc)
        if entity then
            return entity
        end
    end

    local list = Runtime.QuestToNPCs[lower(questName)] or {}
    local ownRoot = rootPart()
    local best
    local bestDistance

    for _, npc in ipairs(list) do
        if npc and npc.Parent then
            local part = objectRoot(npc)
            if part then
                local distance = ownRoot and (ownRoot.Position - part.Position).Magnitude or 0
                if not bestDistance or distance < bestDistance then
                    best = npc
                    bestDistance = distance
                end
            end
        end
    end

    if best then
        return best
    end

    -- Partial quest-name fallback.
    local wanted = lower(questName)
    for questKey, npcs in pairs(Runtime.QuestToNPCs) do
        if questKey:find(wanted, 1, true)
            or wanted:find(questKey, 1, true) then

            for _, npc in ipairs(npcs) do
                if npc and npc.Parent then
                    return npc
                end
            end
        end
    end

    return nil
end

QuestCatalogService.Build()

-- ============================================================
-- Hotbar service
-- ============================================================

HotbarService = {
    Slots = {},
    TitleToSlot = {},
    Hotbar = nil,
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

local UTILITY_WORDS = {
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
    "seed",
    "ore",
}

local COMBAT_WORDS = {
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
    "sulong",
    "bomb",
    "flame",
    "dark",
}

local function findHotbar()
    if HotbarService.Hotbar and HotbarService.Hotbar.Parent then
        return HotbarService.Hotbar
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local backpack = playerGui and playerGui:FindFirstChild("Backpack")
    if not backpack then
        return nil
    end

    for _, object in ipairs(backpack:GetDescendants()) do
        if object.Name == "Hotbar" and object:IsA("GuiObject") then
            HotbarService.Hotbar = object
            return object
        end
    end

    return nil
end

local function isUtilityTitle(title)
    local value = lower(title)

    for _, word in ipairs(UTILITY_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    return false
end

function HotbarService.Refresh()
    table.clear(HotbarService.Slots)
    table.clear(HotbarService.TitleToSlot)

    local hotbar = findHotbar()
    if not hotbar then
        return
    end

    for _, slot in ipairs(hotbar:GetChildren()) do
        local key = KEY_BY_SLOT[slot.Name]

        if key then
            local toolFrame = slot:FindFirstChild("ToolFrame")
            local title = toolFrame and toolFrame:FindFirstChild("Title", true)

            if title and title:IsA("TextLabel") then
                local name = normalize(title.Text)

                if name ~= "" then
                    local data = {
                        Slot = slot.Name,
                        Key = key,
                        Title = name,
                        Frame = slot,
                        ToolFrame = toolFrame,
                        Cooldown = toolFrame and toolFrame:FindFirstChild("Cooldown", true),
                        EXP = toolFrame and toolFrame:FindFirstChild("EXP", true),
                        Upgradable = toolFrame and toolFrame:FindFirstChild("Upgradable", true),
                    }

                    HotbarService.Slots[slot.Name] = data
                    HotbarService.TitleToSlot[name] = data
                end
            end
        end
    end
end

function HotbarService.IsCombat(data)
    if not data or isUtilityTitle(data.Title) then
        return false
    end

    local value = lower(data.Title)

    for _, word in ipairs(COMBAT_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    -- Unknown non-utility hotbar slots can still be skills.
    return true
end

function HotbarService.IsReady(data)
    if not data then
        return false
    end

    local cooldown = data.Cooldown
    if cooldown and cooldown:IsA("GuiObject") then
        return cooldown.Visible == false
    end

    return true
end

function HotbarService.Press(data)
    return data and pressKey(data.Key, 0.03) or false
end

function HotbarService.AutoCombatSlot()
    local best
    local bestScore = -math.huge

    for _, data in pairs(HotbarService.Slots) do
        if HotbarService.IsCombat(data) then
            local score = 10
            local value = lower(data.Title)

            for index, word in ipairs(COMBAT_WORDS) do
                if value:find(word, 1, true) then
                    score += 100 - index
                    break
                end
            end

            local slotNumber = tonumber(data.Slot)
            if slotNumber then
                score -= slotNumber * 0.01
            end

            if score > bestScore then
                best = data
                bestScore = score
            end
        end
    end

    return best
end

function HotbarService.ResolveConfigured()
    HotbarService.Refresh()

    if Config.SelectedWeapon == "Auto" then
        return HotbarService.AutoCombatSlot()
    end

    return HotbarService.TitleToSlot[Config.SelectedWeapon]
end

function HotbarService.GetWeaponOptions()
    HotbarService.Refresh()

    local result = {"Auto"}
    local rows = {}

    for _, data in pairs(HotbarService.Slots) do
        if HotbarService.IsCombat(data) then
            table.insert(rows, data)
        end
    end

    table.sort(rows, function(a, b)
        return (tonumber(a.Slot) or 99) < (tonumber(b.Slot) or 99)
    end)

    for _, data in ipairs(rows) do
        table.insert(result, data.Title)
    end

    return result
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
-- Target service
-- ============================================================

TargetService = {}

local function isPlayerEntity(model)
    return model and (
        model:GetAttribute("PlayerCharacter") == true
        or Players:FindFirstChild(model.Name) ~= nil
    )
end

function TargetService.IsAliveNPC(model)
    if not model
        or not model.Parent
        or not model:IsA("Model")
        or isPlayerEntity(model) then
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

    local value = lower(
        model.Name
        .. " "
        .. tostring(model:GetAttribute("NPCType") or "")
        .. " "
        .. tostring(model:GetAttribute("NPCName") or "")
    )

    return value:find("boss", 1, true) ~= nil
end

function TargetService.IsDialogueNPC(model)
    if not model then
        return false
    end

    local interaction = lower(model:GetAttribute("Interaction") or "")
    local npcType = lower(model:GetAttribute("NPCType") or "")

    if interaction:find("dialogue", 1, true) then
        return true
    end

    if npcType == "civilian" and model:GetAttribute("Combat") ~= true then
        return true
    end

    local root = dialogueRoot()
    return root and model:IsDescendantOf(root) or false
end

function TargetService.IsHostile(model)
    if not TargetService.IsAliveNPC(model)
        or TargetService.IsDialogueNPC(model) then
        return false
    end

    if TargetService.IsBoss(model) then
        return true
    end

    if model:GetAttribute("Combat") == true
        or model:GetAttribute("NPCCombat") == true then
        return true
    end

    local party = lower(
        model:GetAttribute("Party")
        or model:GetAttribute("DefaultParty")
        or ""
    )

    return party:find("enemy", 1, true) ~= nil
        or party:find("corrupt", 1, true) ~= nil
        or party:find("hostile", 1, true) ~= nil
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

function TargetService.IsFarmMob(model, wanted)
    if not TargetService.IsAliveNPC(model)
        or TargetService.IsDialogueNPC(model) then
        return false
    end

    if wanted == "Boss Only" then
        return TargetService.IsBoss(model)
    elseif wanted == "Nearest Hostile" then
        return TargetService.IsHostile(model)
    elseif wanted == "Any Hostile" then
        return TargetService.IsHostile(model)
    elseif wanted and wanted ~= "" then
        if not npcMatches(model, wanted) then
            return false
        end

        -- Exact quest-name target can be accepted even if party metadata is incomplete,
        -- but never a dialogue-only NPC.
        return TargetService.IsHostile(model)
            or model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    return false
end

function TargetService.Find(wanted)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted) then

            local distance = distanceTo(model)
            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

function TargetService.FindNamedNPC(name)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model and model.Parent and npcMatches(model, name) then
            local distance = distanceTo(model)
            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

function TargetService.GetMobOptions()
    local set = {
        ["Nearest Hostile"] = true,
        ["Boss Only"] = true,
    }

    local folder = entitiesFolder()
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model")
                and not isPlayerEntity(model)
                and not TargetService.IsDialogueNPC(model) then

                local name = tostring(
                    model:GetAttribute("NPCType")
                    or model:GetAttribute("NPCName")
                    or stripRuntimeSuffix(model.Name)
                )

                if name ~= "" then
                    set[name] = true
                end
            end
        end
    end

    local result = {}
    for name in pairs(set) do
        table.insert(result, name)
    end

    table.sort(result)
    return result
end

-- ============================================================
-- Platform transport
-- ============================================================

PlatformTransport = {}

local PLATFORM_NAME = "SON_TransportPlatform"

local function transportPlatformCFrameForRoot(rootGoal)
    return rootGoal * CFrame.new(0, -3.25, 0)
end

function PlatformTransport.Ensure()
    local part = Runtime.TransportPart

    if part and part.Parent then
        part.Size = Vector3.new(Config.PlatformSize, 1, Config.PlatformSize)
        part.Transparency = Config.PlatformTransparency
        return part
    end

    local root = rootPart()
    if not root then
        return nil
    end

    part = Instance.new("Part")
    part.Name = PLATFORM_NAME
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Size = Vector3.new(Config.PlatformSize, 1, Config.PlatformSize)
    part.Transparency = Config.PlatformTransparency
    part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)
    part.Parent = Workspace

    Runtime.TransportPart = part
    track(part)

    return part
end

function PlatformTransport.DestroyWeld()
    if Runtime.TransportWeld then
        pcall(function()
            Runtime.TransportWeld:Destroy()
        end)
    end

    Runtime.TransportWeld = nil
end

function PlatformTransport.Cancel(keepPlatform)
    if Runtime.TransportTween then
        pcall(function()
            Runtime.TransportTween:Cancel()
        end)
    end

    Runtime.TransportTween = nil
    Runtime.TransportGoal = nil
    Runtime.TransportMoving = false

    PlatformTransport.DestroyWeld()

    if keepPlatform == false and Runtime.TransportPart then
        pcall(function()
            Runtime.TransportPart:Destroy()
        end)
        Runtime.TransportPart = nil
    end
end

function PlatformTransport.MoveToRootCFrame(rootGoal)
    local root = rootPart()
    local part = PlatformTransport.Ensure()

    if not root or not part or not rootGoal then
        return false, "missing"
    end

    local distance = (root.Position - rootGoal.Position).Magnitude

    if distance <= Config.PlatformArrivalDistance then
        PlatformTransport.Cancel(true)

        pcall(function()
            part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)
        end)

        return true, "arrived"
    end

    if not Config.PlatformTransport then
        return false, "disabled"
    end

    local platformGoal = transportPlatformCFrameForRoot(rootGoal)

    if Runtime.TransportTween and Runtime.TransportGoal then
        local moved = (
            Runtime.TransportGoal.Position
            - platformGoal.Position
        ).Magnitude

        if moved < Config.PlatformRetargetDistance then
            return false, "moving"
        end
    end

    PlatformTransport.Cancel(true)

    -- Re-seat the platform directly under the player before attaching.
    part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)
    part.Size = Vector3.new(Config.PlatformSize, 1, Config.PlatformSize)
    part.Transparency = Config.PlatformTransparency

    local weld = Instance.new("WeldConstraint")
    weld.Name = "SON_TransportWeld"
    weld.Part0 = part
    weld.Part1 = root
    weld.Parent = part
    Runtime.TransportWeld = weld

    local duration = math.clamp(
        distance / math.max(40, Config.PlatformSpeed),
        0.12,
        12
    )

    local tween = TweenService:Create(
        part,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out
        ),
        {CFrame = platformGoal}
    )

    Runtime.TransportTween = tween
    Runtime.TransportGoal = platformGoal
    Runtime.TransportMoving = true

    tween.Completed:Connect(function()
        if Runtime.TransportTween == tween then
            Runtime.TransportTween = nil
            Runtime.TransportGoal = nil
            Runtime.TransportMoving = false

            PlatformTransport.DestroyWeld()

            local currentRoot = rootPart()
            if currentRoot then
                pcall(function()
                    currentRoot.AssemblyLinearVelocity = Vector3.zero
                    currentRoot.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end)

    tween:Play()
    return false, "started"
end

function PlatformTransport.MoveAbove(object)
    local target = objectRoot(object)
    if not target then
        return false, "missing target"
    end

    local position = target.Position + Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )

    local goal = CFrame.lookAt(
        position,
        Vector3.new(target.Position.X, position.Y, target.Position.Z)
    )

    return PlatformTransport.MoveToRootCFrame(goal)
end

function PlatformTransport.MoveNear(object)
    local target = objectRoot(object)
    if not target then
        return false, "missing target"
    end

    local position = (
        target.CFrame
        * CFrame.new(
            0,
            Config.PlatformNpcHeight,
            Config.PlatformBackDistance
        )
    ).Position

    local goal = CFrame.lookAt(position, target.Position)
    return PlatformTransport.MoveToRootCFrame(goal)
end

function PlatformTransport.SetFarmAnchorFrom(object)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    local position = target.Position + Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )

    Runtime.FarmAnchorCFrame = CFrame.lookAt(
        position,
        Vector3.new(target.Position.X, position.Y, target.Position.Z)
    )

    return Runtime.FarmAnchorCFrame
end

function PlatformTransport.MoveToFarmAnchor()
    if not Runtime.FarmAnchorCFrame then
        return false, "no anchor"
    end

    return PlatformTransport.MoveToRootCFrame(Runtime.FarmAnchorCFrame)
end

-- ============================================================
-- Bring / hitbox
-- ============================================================

BringService = {}

function BringService.Step(wanted)
    if not Config.BringMobs then
        return
    end

    local now = os.clock()
    if now - Runtime.LastBring < 0.28 then
        return
    end
    Runtime.LastBring = now

    local root = rootPart()
    if not root then
        return
    end

    local count = 0

    for model in pairs(Runtime.Entities) do
        if count >= Config.BringLimit then
            break
        end

        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted)
            and (Config.BringBosses or not TargetService.IsBoss(model)) then

            local part = model:FindFirstChild("HumanoidRootPart")
                or objectRoot(model)

            if part
                and not part.Anchored
                and (part.Position - root.Position).Magnitude <= Config.BringRadius then

                count += 1

                local column = ((count - 1) % 3) - 1
                local row = math.floor((count - 1) / 3)

                local destination = root.CFrame * CFrame.new(
                    column * Config.BringSpread,
                    -Config.MobBelowFeet,
                    row * Config.BringSpread
                )

                pcall(function()
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                    part.CFrame = destination
                end)
            end
        end
    end
end

HitboxService = {}

function HitboxService.Restore(model)
    local data = Runtime.ExpandedHitboxes[model]
    if not data then
        return
    end

    local part = data.Part
    if part and part.Parent then
        pcall(function()
            part.Size = data.Size
            part.Transparency = data.Transparency
            part.CanCollide = data.CanCollide
            part.Massless = data.Massless
        end)
    end

    Runtime.ExpandedHitboxes[model] = nil
end

function HitboxService.Clear()
    for model in pairs(Runtime.ExpandedHitboxes) do
        HitboxService.Restore(model)
    end
end

function HitboxService.Apply(model, wanted)
    -- Strict mob-only condition.
    if not Config.MobHitbox
        or not TargetService.IsFarmMob(model, wanted)
        or (TargetService.IsBoss(model) and not Config.HitboxBosses) then

        HitboxService.Restore(model)
        return
    end

    local part = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")

    if not part then
        return
    end

    if not Runtime.ExpandedHitboxes[model] then
        Runtime.ExpandedHitboxes[model] = {
            Part = part,
            Size = part.Size,
            Transparency = part.Transparency,
            CanCollide = part.CanCollide,
            Massless = part.Massless,
        }
    end

    pcall(function()
        part.Size = Vector3.new(
            Config.HitboxSize,
            Config.HitboxSize,
            Config.HitboxSize
        )
        part.Transparency = Config.HitboxTransparency
        part.CanCollide = false
        part.Massless = true
    end)
end

function HitboxService.Step(wanted)
    local now = os.clock()
    if now - Runtime.LastHitbox < 0.35 then
        return
    end
    Runtime.LastHitbox = now

    local keep = {}

    if Config.MobHitbox then
        for model in pairs(Runtime.Entities) do
            if model
                and model.Parent
                and TargetService.IsFarmMob(model, wanted) then

                keep[model] = true
                HitboxService.Apply(model, wanted)
            end
        end
    end

    for model in pairs(Runtime.ExpandedHitboxes) do
        if not keep[model] then
            HitboxService.Restore(model)
        end
    end
end

-- ============================================================
-- Small GUI caches
-- ============================================================

local function cacheClaimButton(object)
    if object
        and object:IsA("GuiButton")
        and lower(object.Name .. " " .. textOf(object)):find("claim", 1, true) then
        Runtime.ClaimButtons[object] = true
    end
end

local function initGuiCaches()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    local descendants = playerGui:GetDescendants()

    for index, object in ipairs(descendants) do
        cacheClaimButton(object)

        if index % 4000 == 0 then
            task.wait()
        end
    end

    connect(playerGui.DescendantAdded, cacheClaimButton)
    connect(playerGui.DescendantRemoving, function(object)
        Runtime.ClaimButtons[object] = nil
    end)
end

task.spawn(initGuiCaches)

-- ============================================================
-- Interaction service
-- ============================================================

InteractionService = {}

local firePromptFn = type(fireproximityprompt) == "function"
    and fireproximityprompt
    or nil

local function promptKind(prompt)
    local name = lower(prompt.Name)
    local path = lower(prompt:GetFullName())

    if name:find("fruit chest", 1, true) then
        return "FruitChest"
    elseif name:find("world boss chest", 1, true) then
        return "WorldBossChest"
    elseif name:find("chest", 1, true) then
        return "Chest"
    elseif name:find("dialogue", 1, true) then
        return "Dialogue"
    elseif name:find("ore", 1, true)
        or path:find(".ores.", 1, true) then
        return "Ore"
    elseif path:find(".crops.", 1, true)
        or path:find(".farmgear.", 1, true)
        or path:find(".pests.", 1, true) then
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
    end

    return "Other"
end

function InteractionService.FirePrompt(prompt)
    if not prompt
        or not prompt.Parent
        or not prompt:IsA("ProximityPrompt")
        or not prompt.Enabled then
        return false
    end

    if firePromptFn then
        local ok = pcall(function()
            firePromptFn(prompt, math.max(0, prompt.HoldDuration or 0))
        end)

        if ok then
            return true
        end
    end

    return pressKey(
        prompt.KeyboardKeyCode,
        math.max(0.06, (prompt.HoldDuration or 0) + 0.03)
    )
end

function InteractionService.FindPromptNear(object, desiredKind)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local part = objectRoot(prompt)

            if part then
                local distance = (part.Position - target.Position).Magnitude
                local correctKind = not desiredKind
                    or promptKind(prompt) == desiredKind

                if correctKind
                    and distance <= 35
                    and (not bestDistance or distance < bestDistance) then

                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

function InteractionService.FindPromptByText(text, allowedKinds)
    local wanted = lower(text)
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local kind = promptKind(prompt)
            local kindAllowed = not allowedKinds or allowedKinds[kind]

            if kindAllowed then
                local model = prompt:FindFirstAncestorWhichIsA("Model")

                local blob = lower(table.concat({
                    prompt.Name,
                    tostring(prompt.ActionText or ""),
                    tostring(prompt.ObjectText or ""),
                    model and model.Name or "",
                }, " "))

                if blob:find(wanted, 1, true) then
                    local distance = distanceTo(prompt)

                    if not bestDistance or distance < bestDistance then
                        best = prompt
                        bestDistance = distance
                    end
                end
            end
        end
    end

    return best
end

local function dialogueUI()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("DialogueUI")
end

local function dialogueIsOpen()
    local ui = dialogueUI()
    return ui and (not ui:IsA("ScreenGui") or ui.Enabled)
end

local function scoreDialogueButton(button, questName)
    if not button
        or not button:IsA("ImageButton")
        or isScriptTemplateDescendant(button)
        or not isOnScreen(button) then
        return nil
    end

    local wanted = lower(questName)
    local parent = button.Parent
    local text = parent and textOf(parent) or ""
    local blob = lower((parent and parent.Name or "") .. " " .. text)

    local score = 1

    if wanted ~= "" and blob:find(wanted, 1, true) then
        score += 120
    end

    local questGlow = parent and parent:FindFirstChild("Quest Glow", true)
    if questGlow and questGlow:IsA("GuiObject") and questGlow.Visible then
        score += 90
    end

    for _, word in ipairs({
        "quest",
        "help",
        "training",
        "accept",
        "continue",
        "yes",
        "finish",
        "complete",
    }) do
        if blob:find(word, 1, true) then
            score += 20
        end
    end

    return score
end

function InteractionService.ProcessDialogue(questName)
    if not Config.AutoDialogue or not dialogueIsOpen() then
        return false
    end

    local ui = dialogueUI()
    local best
    local bestScore = -math.huge

    for _, object in ipairs(ui:GetDescendants()) do
        if object:IsA("ImageButton") then
            local score = scoreDialogueButton(object, questName or "")

            if score and score > bestScore then
                best = object
                bestScore = score
            end
        end
    end

    if best then
        return clickButton(best, false)
    end

    -- Fallback for games that temporarily reuse/reparent the NodeFrame template.
    for _, object in ipairs(ui:GetDescendants()) do
        if object:IsA("ImageButton") and isOnScreen(object) then
            local parent = object.Parent
            local blob = lower(
                (parent and parent.Name or "")
                .. " "
                .. (parent and textOf(parent) or "")
            )

            if blob:find("quest", 1, true)
                or blob:find("accept", 1, true)
                or (
                    questName
                    and questName ~= ""
                    and blob:find(lower(questName), 1, true)
                ) then
                return clickButton(object, false)
            end
        end
    end

    return false
end

function InteractionService.ProcessClaimButtons()
    if not Config.AutoClaim then
        return
    end

    for object in pairs(Runtime.ClaimButtons) do
        if object and object.Parent then
            if isGuiVisible(object) then
                clickButton(object, false)
                return
            end
        else
            Runtime.ClaimButtons[object] = nil
        end
    end
end

function InteractionService.InteractWithQuestNPC(object, questName)
    if not object then
        return false
    end

    if dialogueIsOpen() then
        return InteractionService.ProcessDialogue(questName)
    end

    if os.clock() - Runtime.LastInteraction < 0.75 then
        return false
    end

    Runtime.LastInteraction = os.clock()

    local prompt = object:IsA("ProximityPrompt")
        and object
        or InteractionService.FindPromptNear(object, "Dialogue")

    if prompt then
        InteractionService.FirePrompt(prompt)
        return true
    end

    return false
end

-- ============================================================
-- Mastery / combat
-- ============================================================

MasteryService = {}

local function currentFruitSkillNames()
    local result = {}
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local skillInfo = modules and modules:FindFirstChild("SkillInformation")
    local skills = skillInfo and skillInfo:FindFirstChild("Skills")
    local fruits = skills and skills:FindFirstChild("Fruits")
    local fruit = fruits and fruits:FindFirstChild(PlayerState.GetFruit())

    if fruit then
        for _, object in ipairs(fruit:GetDescendants()) do
            if object:IsA("ModuleScript") then
                result[lower(object.Name)] = true
            end
        end
    end

    return result
end

function MasteryService.GetCandidates()
    HotbarService.Refresh()

    local candidates = {}
    local fruitSkills = Config.MasteryMode == "Current Fruit"
        and currentFruitSkillNames()
        or nil

    for _, data in pairs(HotbarService.Slots) do
        local accepted = false

        if Config.MasteryMode == "Selected Skill" then
            accepted = Config.SelectedWeapon ~= "Auto"
                and data.Title == Config.SelectedWeapon
        elseif Config.MasteryMode == "Current Fruit" then
            local title = lower(data.Title)

            if fruitSkills then
                for skillName in pairs(fruitSkills) do
                    if title == skillName
                        or title:find(skillName, 1, true)
                        or skillName:find(title, 1, true) then
                        accepted = true
                        break
                    end
                end
            end
        else
            accepted = HotbarService.IsCombat(data)
        end

        if accepted
            and (not Config.MasteryReadyOnly or HotbarService.IsReady(data)) then
            table.insert(candidates, data)
        end
    end

    table.sort(candidates, function(a, b)
        return (tonumber(a.Slot) or 99) < (tonumber(b.Slot) or 99)
    end)

    return candidates
end

function MasteryService.Step()
    if not Config.AutoMastery then
        return false
    end

    local now = os.clock()
    if now - Runtime.LastMastery < Config.MasteryInterval then
        return false
    end

    local candidates = MasteryService.GetCandidates()
    if #candidates == 0 then
        return false
    end

    Runtime.LastMastery = now
    Runtime.MasteryCursor = (Runtime.MasteryCursor % #candidates) + 1

    return HotbarService.Press(candidates[Runtime.MasteryCursor])
end

function MasteryService.GetSnapshot()
    local candidates = MasteryService.GetCandidates()
    local rows = {}

    for _, data in ipairs(candidates) do
        local ready = HotbarService.IsReady(data) and "Ready" or "Cooldown"
        local exp = data.EXP
        local expText = ""

        if exp and exp:IsA("GuiObject") then
            local bar = exp:FindFirstChild("Bar", true)
            if bar and bar:IsA("GuiObject") then
                expText = string.format(
                    " • EXP %.0f%%",
                    math.clamp(bar.Size.X.Scale * 100, 0, 100)
                )
            end
        end

        table.insert(
            rows,
            data.Slot .. ": " .. data.Title .. " [" .. ready .. "]" .. expText
        )
    end

    return #rows > 0 and table.concat(rows, "\n") or "No mastery candidates"
end

CombatService = {}

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

    local root = rootPart()
    local target = objectRoot(model)

    if root and target then
        local position = root.Position

        pcall(function()
            root.CFrame = CFrame.lookAt(
                position,
                Vector3.new(
                    target.Position.X,
                    position.Y,
                    target.Position.Z
                )
            )
        end)
    end
end

function CombatService.AttackStep()
    if not Config.AutoAttack then
        return
    end

    MasteryService.Step()

    local now = os.clock()
    local minimumDelay = 1 / math.max(1, Config.AttackRate)

    if now - Runtime.LastAttack >= minimumDelay then
        Runtime.LastAttack = now
        mouseClickCenter()
    end
end

function CombatService.BlockStep()
    if not Config.AutoBlock then
        setBlock(false)
        return
    end

    local target = Runtime.CurrentTarget
    local shouldBlock = target
        and target.Parent
        and distanceTo(target) <= 25
        and PlayerState.GetHealthPercent() <= Config.BlockHealthPercent

    setBlock(shouldBlock == true)
end

-- ============================================================
-- Stats service
-- ============================================================

StatsService = {}

local STAT_NAMES = {
    "Health",
    "Strength",
    "Energy",
    "Willpower",
    "Agility",
    "Precision",
}

local STAT_WEIGHTS = {
    ["Balanced"] = {
        Health = 1,
        Strength = 1,
        Energy = 1,
        Willpower = 1,
        Agility = 1,
        Precision = 1,
    },
    ["Strength"] = {
        Health = 1.4,
        Strength = 4.5,
        Energy = 1.3,
        Willpower = 1.0,
        Agility = 1.0,
        Precision = 0.1,
    },
    ["Precision"] = {
        Health = 1.4,
        Strength = 0.1,
        Energy = 1.3,
        Willpower = 1.0,
        Agility = 1.0,
        Precision = 4.5,
    },
    ["Tank"] = {
        Health = 5.0,
        Strength = 0.8,
        Energy = 1.3,
        Willpower = 2.3,
        Agility = 0.8,
        Precision = 0.8,
    },
    ["Mobility"] = {
        Health = 1.4,
        Strength = 1.0,
        Energy = 2.0,
        Willpower = 1.0,
        Agility = 4.0,
        Precision = 1.0,
    },
    ["Haki"] = {
        Health = 1.5,
        Strength = 1.0,
        Energy = 1.4,
        Willpower = 4.5,
        Agility = 1.0,
        Precision = 1.0,
    },
}

local function radarFrame()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local menu = playerGui and playerGui:FindFirstChild("Menu")
    local container = menu and menu:FindFirstChild("ContainerFrame")
    local right = container and container:FindFirstChild("Right")
    return right and right:FindFirstChild("Radar")
end

function StatsService.GetStatPoints()
    local radar = radarFrame()
    local statpoint = radar and radar:FindFirstChild("StatpointText")
    local label = statpoint and statpoint:FindFirstChild("StatpointText")

    if label and label:IsA("TextLabel") then
        return tonumber(label.Text:match("(%d+)")) or 0
    end

    return 0
end

function StatsService.GetValues()
    local radar = radarFrame()
    local statsFolder = radar and radar:FindFirstChild("Stats")
    local values = {}

    for _, name in ipairs(STAT_NAMES) do
        local value = statsFolder and statsFolder:FindFirstChild(name)

        if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
            values[name] = tonumber(value.Value) or 0
        else
            local label = radar
                and radar:FindFirstChild(name)
                and radar[name]:FindFirstChild("Number")

            values[name] = label
                and tonumber((label.Text or ""):match("(%d+)"))
                or 0
        end
    end

    return values
end

local function autoWeaponBuild()
    local selected = HotbarService.ResolveConfigured()

    local blob = lower(
        Config.SelectedWeapon
        .. " "
        .. tostring(selected and selected.Title or "")
        .. " "
        .. table.concat(PlayerState.GetWeaponTypes(), " ")
        .. " "
        .. PlayerState.GetFruit()
    )

    if blob:find("gun", 1, true)
        or blob:find("cannon", 1, true)
        or blob:find("precision", 1, true)
        or blob:find("rifle", 1, true)
        or blob:find("shot", 1, true) then
        return "Precision"
    end

    return "Strength"
end

function StatsService.GetBuild()
    if Config.StatBuild == "Auto Weapon" then
        return autoWeaponBuild()
    end

    return Config.StatBuild
end

function StatsService.ChooseStat()
    local build = StatsService.GetBuild()
    local weights = STAT_WEIGHTS[build] or STAT_WEIGHTS.Balanced
    local values = StatsService.GetValues()

    local totalWeight = 0
    local totalValue = 0

    for _, name in ipairs(STAT_NAMES) do
        totalWeight += weights[name] or 0
        totalValue += values[name] or 0
    end

    local best
    local bestDeficit = -math.huge

    for _, name in ipairs(STAT_NAMES) do
        local weight = weights[name] or 0
        local target = totalWeight > 0
            and ((totalValue + 1) * weight / totalWeight)
            or 0

        local deficit = target - (values[name] or 0)

        if deficit > bestDeficit then
            best = name
            bestDeficit = deficit
        end
    end

    return best
end

function StatsService.SpendOne()
    if not Config.AutoStats then
        return false
    end

    local now = os.clock()
    if now - Runtime.LastStatsSpend < Config.StatSpendInterval then
        return false
    end

    if StatsService.GetStatPoints() <= 0 then
        return false
    end

    local stat = StatsService.ChooseStat()
    local radar = radarFrame()
    local frame = radar and radar:FindFirstChild(stat or "")
    local button = frame and frame:FindFirstChild("ImageButton")

    if not button or not button:IsA("ImageButton") then
        return false
    end

    Runtime.LastStatsSpend = now
    return clickButton(button, true)
end

function StatsService.GetSnapshot()
    local values = StatsService.GetValues()
    local rows = {
        "Points: " .. StatsService.GetStatPoints(),
        "Build: " .. StatsService.GetBuild(),
    }

    for _, name in ipairs(STAT_NAMES) do
        table.insert(rows, name .. ": " .. tostring(values[name] or 0))
    end

    return table.concat(rows, "\n")
end

-- ============================================================
-- Fishing service + QTE
-- ============================================================

FishingService = {}

local ROD_NAMES = {
    "Wooden Rod",
    "Carbon Rod",
    "Fiberglass Rod",
    "Silverline Rod",
    "Deep-Sea Rod",
    "Terry's Trusted Rod",
    "Celestial Rod",
}

local function fishInventory()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("FishInventory")
end

local function fishingGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Fishing")
end

local function qteScreen()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("QuickTimeEvents")
end

local function setFishingState(state, reason)
    if Runtime.FishingState ~= state then
        Runtime.FishingState = state
        Runtime.FishingStateSince = os.clock()
    end

    Runtime.FishingReason = reason or Runtime.FishingReason
end

local function setFishingMouseHeld(held)
    if Runtime.FishingMouseHeld == held then
        return
    end

    Runtime.FishingMouseHeld = held

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)

    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(
            viewport.X / 2,
            viewport.Y / 2,
            0,
            held,
            game,
            0
        )
    end)
end

local function releaseFishingKey()
    if not Runtime.FishingKeyHeld then
        return
    end

    local key = Runtime.FishingKeyHeld
    Runtime.FishingKeyHeld = nil

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

local function holdFishingKey(key)
    if Runtime.FishingKeyHeld == key then
        return
    end

    releaseFishingKey()
    Runtime.FishingKeyHeld = key

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
    end)
end

local function findHotbarRod()
    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        local value = lower(data.Title)

        if value:find("rod", 1, true) then
            return {
                Name = data.Title,
                Source = "Hotbar",
                Hotbar = data,
            }
        end
    end

    return nil
end

local function findInventoryRod()
    local inventory = fishInventory()
    local root = inventory
        and inventory:FindFirstChild("Inventory")
        and inventory.Inventory:FindFirstChild("Inventory")

    local rodFrame = root and root:FindFirstChild("RodFrame")
    local inner = rodFrame and rodFrame:FindFirstChild("Frame")
    local itemName = inner and inner:FindFirstChild("ItemName")
    local equip = inner and inner:FindFirstChild("Equip")

    if itemName and itemName:IsA("TextLabel") then
        local name = normalize(itemName.Text):gsub("^%[", ""):gsub("%]$", "")

        return {
            Name = name,
            Source = "FishInventory",
            EquipButton = equip,
        }
    end

    return nil
end

function FishingService.FindRod()
    local now = os.clock()

    if Runtime.FishingRodCache
        and now - Runtime.FishingRodCacheAt < 1.0 then
        return Runtime.FishingRodCache
    end

    Runtime.FishingRodCacheAt = now
    Runtime.FishingRodCache = findHotbarRod() or findInventoryRod()
    return Runtime.FishingRodCache
end

function FishingService.GetBait()
    local now = os.clock()

    if Runtime.FishingBaitCache
        and now - Runtime.FishingBaitCacheAt < 1.5 then
        return Runtime.FishingBaitCache
    end

    Runtime.FishingBaitCacheAt = now

    local inventory = fishInventory()
    local root = inventory
        and inventory:FindFirstChild("Inventory")
        and inventory.Inventory:FindFirstChild("Inventory")

    local baitFrame = root and root:FindFirstChild("BaitFrame")
    local inner = baitFrame and baitFrame:FindFirstChild("Frame")
    local itemName = inner and inner:FindFirstChild("ItemName")
    local amount = inner and inner:FindFirstChild("Amount")

    if itemName and itemName:IsA("TextLabel") then
        local count = amount
            and amount:IsA("TextLabel")
            and tonumber((amount.Text or ""):match("(%d+)"))
            or 0

        Runtime.FishingBaitCache = {
            Name = normalize(itemName.Text):gsub("^%[", ""):gsub("%]$", ""),
            Amount = count or 0,
        }

        return Runtime.FishingBaitCache
    end

    Runtime.FishingBaitCache = nil
    return nil
end

local function largestAnchorTownWater()
    local islands = Workspace:FindFirstChild("Islands")
    local anchor = islands and islands:FindFirstChild("Anchor Town")
    if not anchor then
        return nil
    end

    local best
    local bestArea = 0

    for _, object in ipairs(anchor:GetDescendants()) do
        if object:IsA("BasePart") and object.Name == "Water" then
            local area = object.Size.X * object.Size.Z
            if area > bestArea then
                best = object
                bestArea = area
            end
        end
    end

    return best
end

local function shorePosition(water)
    local root = rootPart()
    if not water or not root then
        return nil
    end

    local localPos = water.CFrame:PointToObjectSpace(root.Position)
    local halfX = water.Size.X / 2
    local halfZ = water.Size.Z / 2
    local margin = 7

    local edges = {
        {math.abs(localPos.X + halfX), "left"},
        {math.abs(halfX - localPos.X), "right"},
        {math.abs(localPos.Z + halfZ), "back"},
        {math.abs(halfZ - localPos.Z), "front"},
    }

    table.sort(edges, function(a, b)
        return a[1] < b[1]
    end)

    local x = math.clamp(localPos.X, -halfX, halfX)
    local z = math.clamp(localPos.Z, -halfZ, halfZ)

    if edges[1][2] == "left" then
        x = -halfX - margin
    elseif edges[1][2] == "right" then
        x = halfX + margin
    elseif edges[1][2] == "back" then
        z = -halfZ - margin
    else
        z = halfZ + margin
    end

    local world = water.CFrame:PointToWorldSpace(Vector3.new(
        x,
        water.Size.Y / 2 + 3,
        z
    ))

    return CFrame.lookAt(world, water.Position)
end

function FishingService.ResolveSpot()
    if Config.FishingSpotMode == "Saved Position" then
        return Runtime.FishingSpotCFrame,
            Runtime.FishingSpotCFrame and "Saved position" or "No saved spot"
    elseif Config.FishingSpotMode == "Current Position" then
        local root = rootPart()
        return root and root.CFrame or nil,
            root and "Current position" or "Character unavailable"
    elseif Config.FishingSpotMode == "Anchor Town Pond" then
        local water = largestAnchorTownWater()
        return water and shorePosition(water) or nil,
            water and "Detected Anchor Town water edge" or "Anchor Town water not found"
    end

    return nil, "Unknown spot mode"
end

local function fishingReelActive()
    local gui = fishingGui()
    local main = gui and gui:FindFirstChild("Main")

    return gui
        and (not gui:IsA("ScreenGui") or gui.Enabled)
        and main
        and main.Visible,
        main
end

local function qteButtonByText(text)
    local screen = qteScreen()
    if not screen or not screen.Enabled then
        return nil
    end

    local wanted = lower(text)

    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("ImageButton")
            and not isScriptTemplateDescendant(object)
            and isOnScreen(object) then

            local label = object:FindFirstChildWhichIsA("TextLabel", true)
            if label and lower(label.Text) == wanted then
                return object
            end
        end
    end

    -- Some QTE implementations may reuse the template in place.
    -- In the inactive dump, those template buttons sit at Y=-58;
    -- only accept a template if it has moved into the viewport.
    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("ImageButton") and isOnScreen(object) then
            local label = object:FindFirstChildWhichIsA("TextLabel", true)
            if label and lower(label.Text) == wanted then
                return object
            end
        end
    end

    return nil
end

local function findEnabledBillboard(name)
    local screen = qteScreen()
    if not screen then
        return nil
    end

    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("BillboardGui")
            and object.Name == name
            and object.Enabled then
            return object
        end
    end

    return nil
end

function FishingService.HandleShake()
    if not Config.FishingAutoShake then
        return false
    end

    local button = qteButtonByText("SHAKE")
    if not button then
        return false
    end

    local now = os.clock()
    local position = button.AbsolutePosition

    local moved = not Runtime.FishingLastShakePosition
        or (Runtime.FishingLastShakePosition - position).Magnitude > 3

    if moved or now - Runtime.FishingLastShakeClick >= 0.12 then
        Runtime.FishingLastShakePosition = position
        Runtime.FishingLastShakeClick = now
        clickButton(button, false)
    end

    setFishingState("SHAKE", "Clicking SHAKE QTE")
    return true
end

function FishingService.HandleSpamClick()
    if not Config.FishingAutoSpamClick then
        return false
    end

    local button = qteButtonByText("CLICK")
    if not button then
        return false
    end

    local now = os.clock()
    if now - Runtime.FishingLastSpamClick >= 0.065 then
        Runtime.FishingLastSpamClick = now
        clickButton(button, false)
    end

    setFishingState("SPAM_CLICK", "Handling CLICK QTE")
    return true
end

function FishingService.HandleTimedRelease()
    if not Config.FishingAutoTimedRelease then
        Runtime.FishingTimedReleaseDone = false
        setFishingMouseHeld(false)
        return false
    end

    local bar = findEnabledBillboard("Fishing Bar")
    if not bar then
        Runtime.FishingTimedReleaseDone = false
        setFishingMouseHeld(false)
        return false
    end

    local frame = bar:FindFirstChild("Frame")
    local amount = frame and frame:FindFirstChild("Amount")

    if not amount or not amount:IsA("GuiObject") then
        return false
    end

    if Runtime.FishingTimedReleaseDone then
        setFishingMouseHeld(false)
        setFishingState("TIMED_RELEASE", "Release completed")
        return true
    end

    local fill = math.clamp(amount.Size.Y.Scale, 0, 1)

    if fill < Config.FishingReleaseThreshold then
        setFishingMouseHeld(true)
        setFishingState(
            "TIMED_RELEASE",
            string.format("Holding %.0f%%", fill * 100)
        )
    else
        setFishingMouseHeld(false)
        Runtime.FishingTimedReleaseDone = true
        setFishingState(
            "TIMED_RELEASE",
            string.format("Released %.0f%%", fill * 100)
        )
    end

    return true
end

function FishingService.HandleReel()
    local active, main = fishingReelActive()
    if not active or not main then
        releaseFishingKey()
        setFishingMouseHeld(false)
        Runtime.FishingReelCalibrated = false
        Runtime.FishingLastMoveCenter = nil
        return false
    end

    local move = main:FindFirstChild("Move")
    local fish = main:FindFirstChild("Fish")

    if not move or not fish
        or not move:IsA("GuiObject")
        or not fish:IsA("GuiObject") then
        return false
    end

    -- Confirmed from the dump:
    -- Move = the wide controllable catcher bar.
    -- Fish = the smaller target block that must stay inside Move.
    local moveLeft = move.AbsolutePosition.X
    local moveRight = moveLeft + move.AbsoluteSize.X
    local moveCenter = moveLeft + move.AbsoluteSize.X / 2

    local fishLeft = fish.AbsolutePosition.X
    local fishRight = fishLeft + fish.AbsoluteSize.X
    local fishCenter = fishLeft + fish.AbsoluteSize.X / 2

    local previousCenter = Runtime.FishingLastMoveCenter
    if previousCenter then
        Runtime.FishingLastMoveVelocity = moveCenter - previousCenter
    end
    Runtime.FishingLastMoveCenter = moveCenter

    -- Optional one-time calibration. We briefly hold and observe whether Move
    -- travels right or left. This avoids hard-coding the input direction.
    if Config.FishingAutoCalibrate and not Runtime.FishingReelCalibrated then
        local before = moveCenter
        setFishingMouseHeld(true)
        task.wait(0.075)

        local after = move.AbsolutePosition.X + move.AbsoluteSize.X / 2
        local delta = after - before

        if math.abs(delta) >= 0.5 then
            Runtime.FishingHoldDirection = delta > 0 and 1 or -1
        else
            Runtime.FishingHoldDirection = Config.FishingHoldMovesRight and 1 or -1
        end

        Runtime.FishingReelCalibrated = true
        Runtime.FishingLastMoveCenter = after
        setFishingMouseHeld(false)
        return true
    end

    local tolerance = Config.FishingReelTolerance
    local innerLeft = moveLeft + tolerance
    local innerRight = moveRight - tolerance

    -- Target control direction:
    -- +1 = Move should travel right, -1 = Move should travel left.
    local wantedDirection = 0

    if fishRight > innerRight then
        wantedDirection = 1
    elseif fishLeft < innerLeft then
        wantedDirection = -1
    else
        -- Fish is already contained. Counter the current bar velocity so it
        -- does not drift out of the target while we wait for the next frame.
        local velocity = Runtime.FishingLastMoveVelocity or 0
        if velocity > 0.6 and fishCenter <= moveCenter + tolerance then
            wantedDirection = -1
        elseif velocity < -0.6 and fishCenter >= moveCenter - tolerance then
            wantedDirection = 1
        else
            wantedDirection = fishCenter > moveCenter and 1 or -1
        end
    end

    local holdDirection = Runtime.FishingHoldDirection or 1
    local shouldHold = wantedDirection == holdDirection
    setFishingMouseHeld(shouldHold)
    releaseFishingKey()

    Runtime.FishingHadReel = true
    setFishingState(
        "REEL",
        string.format(
            "Keeping Fish inside Move | error %.1f | %s",
            fishCenter - moveCenter,
            shouldHold and "HOLD" or "RELEASE"
        )
    )

    return true
end

function FishingService.EquipRod(rod)
    if not rod then
        return false
    end

    if rod.Source == "Hotbar" then
        return HotbarService.Press(rod.Hotbar)
    end

    if rod.EquipButton and rod.EquipButton:IsA("GuiButton") then
        local ok = clickButton(rod.EquipButton, true)

        if ok then
            Runtime.FishingRodCache = nil
            Runtime.FishingRodCacheAt = 0
        end

        return ok
    end

    return false
end

function FishingService.GetConditions()
    local rod = FishingService.FindRod()
    local bait = FishingService.GetBait()
    local spot, spotReason = FishingService.ResolveSpot()

    return {
        Enabled = Config.AutoFishing,
        PlayerReady = PlayerState.IsReady(),
        ProgressionFree = not Config.AutoProgress
            or Runtime.ProgressLifeSkill == "Fishing",
        Rod = rod and rod.Name or "None",
        RodSource = rod and rod.Source or "None",
        Bait = bait and bait.Name or "None",
        BaitAmount = bait and bait.Amount or 0,
        BaitRequired = Config.FishingRequireBait,
        SpotFound = spot ~= nil,
        Spot = spotReason,
        State = Runtime.FishingState,
        Reason = Runtime.FishingReason,
        CanStart =
            Config.AutoFishing
            and PlayerState.IsReady()
            and (
                not Config.AutoProgress
                or Runtime.ProgressLifeSkill == "Fishing"
            )
            and rod ~= nil
            and spot ~= nil
            and (
                not Config.FishingRequireBait
                or (bait and bait.Amount > 0)
            ),
    }
end

function FishingService.Reset(reason)
    releaseFishingKey()
    setFishingMouseHeld(false)
    Runtime.FishingHadReel = false
    Runtime.FishingTimedReleaseDone = false
    Runtime.FishingLastShakePosition = nil
    setFishingState("CHECK", reason or "reset")
end

function FishingService.Step()
    local progressionFishing = Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Fishing"

    if not Config.AutoFishing and not progressionFishing then
        FishingService.Reset("Auto Fishing disabled")
        setFishingState("IDLE", "Auto Fishing disabled")
        return 0.8
    end

    if Config.AutoProgress
        and Runtime.ProgressLifeSkill ~= "Fishing" then
        FishingService.Reset("Auto Progress owns movement")
        return 0.6
    end

    if not PlayerState.IsReady() then
        FishingService.Reset("Player not ready")
        return 0.8
    end

    -- QTE priority comes before inventory/hotbar checks so a 30-60 Hz QTE
    -- never performs expensive hotbar/inventory discovery every frame.
    if FishingService.HandleShake() then
        return 0.045
    end

    if FishingService.HandleSpamClick() then
        return 0.055
    end

    if FishingService.HandleTimedRelease() then
        return 0.035
    end

    if FishingService.HandleReel() then
        return 0.035
    end

    releaseFishingKey()
    setFishingMouseHeld(false)

    local rod = FishingService.FindRod()
    if not rod then
        FishingService.Reset("No fishing rod detected")
        setFishingState("MISSING_ROD", "No rod in Hotbar/FishInventory")
        return 1.0
    end

    local bait = FishingService.GetBait()
    if Config.FishingRequireBait
        and (not bait or bait.Amount <= 0) then

        FishingService.Reset("Required bait missing")
        setFishingState("MISSING_BAIT", "Bait required but unavailable")
        return 1.0
    end

    local spot, spotReason = FishingService.ResolveSpot()
    if not spot then
        FishingService.Reset(spotReason)
        setFishingState("MISSING_SPOT", spotReason)
        return 1.0
    end

    if Runtime.FishingHadReel then
        Runtime.FishingHadReel = false
        Runtime.FishingLastCast = os.clock()
        setFishingState("COOLDOWN", "Reel ended")
    end

    if Runtime.FishingState == "COOLDOWN" then
        if os.clock() - Runtime.FishingStateSince < Config.FishingCooldown then
            return 0.25
        end

        setFishingState("CHECK", "Cooldown complete")
    end

    local root = rootPart()
    local distance = root and (root.Position - spot.Position).Magnitude or math.huge

    if distance > Config.PlatformArrivalDistance then
        if not Config.FishingAutoReturn then
            setFishingState("WAIT_SPOT", "Move to fishing spot manually")
            return 0.8
        end

        setFishingState("MOVE_TO_SPOT", spotReason)
        PlatformTransport.MoveToRootCFrame(spot)
        return 0.20
    end

    PlatformTransport.Cancel(true)

    if Runtime.FishingState == "WAIT_QTE" then
        if os.clock() - Runtime.FishingStateSince >= Config.FishingBiteTimeout then
            Runtime.FishingLastCast = os.clock()
            setFishingState("COOLDOWN", "No bite/QTE; retrying")
        end

        return 0.25
    end

    if os.clock() - Runtime.FishingLastCast < Config.FishingCooldown then
        return 0.25
    end

    FishingService.EquipRod(rod)
    task.wait(0.08)
    mouseClickCenter()

    Runtime.FishingLastCast = os.clock()
    setFishingState("WAIT_QTE", "Cast once; waiting for SHAKE/QTE")

    return 0.20
end

-- ============================================================
-- Mining service
-- Real ore models + verified hold/release QTE
-- ============================================================

MiningQTEService = {}

local ORE_CATALOG = {
    "Copper Ore",
    "Iron Ore",
    "Silver Ore",
    "Gold Ore",
    "Diamond Ore",
}

local function setMiningState(state, reason)
    if Runtime.MiningState ~= state then
        Runtime.MiningState = state
        Runtime.MiningStateSince = os.clock()
    end
    Runtime.ProgressDetail = reason or Runtime.ProgressDetail
end

local function miningMouse(held, ore)
    if Runtime.MiningMouseHeld == held then
        return
    end

    Runtime.MiningMouseHeld = held

    local point = ore and screenPointOf(ore)
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = point and point.X or viewport.X / 2
    local y = point and point.Y or viewport.Y / 2

    mouseButtonAt(x, y, held)
end

local function oreName(model)
    if not model then
        return nil
    end

    return tostring(
        model:GetAttribute("Ore")
        or model:GetAttribute("Name")
        or model.Name
    )
end

local function oreIsAvailable(model)
    if not model or not model.Parent or not model:IsA("Model") then
        return false
    end

    if model:GetAttribute("ObjectType") ~= "Ore"
        and model:GetAttribute("Ore") == nil then
        return false
    end

    return model:GetAttribute("Mined") ~= true
        and objectRoot(model) ~= nil
end

local function questRequiredOre()
    local _, taskData = QuestService.GetNextTask()
    if not taskData or taskData.Kind ~= "Mine" then
        return nil
    end

    local target = normalize(taskData.Target)
    if target == "" then
        return nil
    end

    for _, name in ipairs(ORE_CATALOG) do
        local a = lower(name)
        local b = lower(target)
        if a == b or a:find(b, 1, true) or b:find(a, 1, true) then
            return name
        end
    end

    return target
end

function MiningQTEService.GetWantedOre()
    if Config.MiningMode == "Quest Required" then
        return questRequiredOre() or Config.SelectedOre
    elseif Config.MiningMode == "Selected Ore" then
        return Config.SelectedOre
    end

    return nil
end

function MiningQTEService.GetOreOptions()
    local set = {}
    for _, name in ipairs(ORE_CATALOG) do
        set[name] = true
    end

    for model in pairs(Runtime.Ores) do
        if oreIsAvailable(model) then
            set[oreName(model)] = true
        end
    end

    local result = {}
    for name in pairs(set) do
        table.insert(result, name)
    end
    table.sort(result)
    return result
end

function MiningQTEService.FindOre()
    local wanted = MiningQTEService.GetWantedOre()
    local best
    local bestDistance
    local bestDrop = -math.huge

    for model in pairs(Runtime.Ores) do
        if oreIsAvailable(model) then
            local name = oreName(model)
            local accepted = Config.MiningMode == "Any Available"
                or wanted == nil
                or lower(name) == lower(wanted)

            if accepted then
                local distance = distanceTo(model)
                local drop = tonumber(model:GetAttribute("DropAmount")) or 0

                if Config.MiningMode == "Highest Drop" then
                    if drop > bestDrop or (drop == bestDrop and (not bestDistance or distance < bestDistance)) then
                        best = model
                        bestDrop = drop
                        bestDistance = distance
                    end
                elseif not bestDistance or distance < bestDistance then
                    best = model
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

local function findPickaxe()
    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        if lower(data.Title):find("pickaxe", 1, true) then
            return data
        end
    end

    return nil
end

local function findMiningQTE()
    local screen = qteScreen()
    if not screen then
        return nil
    end

    -- The real Mining QTE in the dump is:
    -- Events/Mining/Mining/Frame/{Critical Zone, Amount}
    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("BillboardGui")
            and object.Name == "Mining"
            and object.Enabled
            and object.Parent
            and object.Parent.Name == "Mining" then

            local frame = object:FindFirstChild("Frame")
            local critical = frame and frame:FindFirstChild("Critical Zone")
            local amount = frame and frame:FindFirstChild("Amount")

            if critical and amount
                and critical:IsA("GuiObject")
                and amount:IsA("GuiObject") then
                return object, frame, critical, amount
            end
        end
    end

    return nil
end

local function miningAmountTop(amount)
    -- Amount is anchored at Y=1 and grows upward.
    return 1 - math.clamp(amount.Size.Y.Scale, 0, 1)
end

local function miningCriticalBand(critical)
    local top = critical.Position.Y.Scale
    local bottom = top + critical.Size.Y.Scale
    return math.min(top, bottom), math.max(top, bottom)
end

function MiningQTEService.HandleQTE(ore)
    if not Config.AutoMiningQTE then
        return false
    end

    local _, _, critical, amount = findMiningQTE()
    if not critical or not amount then
        return false
    end

    local amountTop = miningAmountTop(amount)
    local criticalTop, criticalBottom = miningCriticalBand(critical)
    local tolerance = Config.MiningCriticalTolerance

    -- Game tutorial confirms: hold mouse to charge; release at the target/top.
    -- We use the actual green Critical Zone instead of a guessed fixed %.
    local inside = amountTop >= (criticalTop - tolerance)
        and amountTop <= (criticalBottom + tolerance)

    if inside and not Runtime.MiningReleaseDone then
        miningMouse(false, ore)
        Runtime.MiningReleaseDone = true
        Runtime.MiningLastQTE = os.clock()
        setMiningState("RELEASE", string.format("Released on %s critical zone", oreName(ore)))
    elseif not Runtime.MiningReleaseDone then
        miningMouse(true, ore)
        setMiningState("CHARGE", string.format("Charging %s", oreName(ore)))
    end

    return true
end

function MiningQTEService.Reset(reason)
    miningMouse(false, Runtime.MiningTarget)
    Runtime.MiningTarget = nil
    Runtime.MiningReleaseDone = false
    setMiningState("CHECK", reason or "reset")
end

function MiningQTEService.Step()
    local progressionMining = Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Mining"

    if not Config.AutoMining and not progressionMining then
        MiningQTEService.Reset("Auto Mining disabled")
        return 0.8
    end

    if Config.AutoProgress and Runtime.ProgressLifeSkill ~= "Mining" then
        MiningQTEService.Reset("Progression owns another task")
        return 0.8
    end

    if not PlayerState.IsReady() then
        MiningQTEService.Reset("Player not ready")
        return 0.8
    end

    local ore = Runtime.MiningTarget
    if not oreIsAvailable(ore) then
        ore = MiningQTEService.FindOre()
        Runtime.MiningTarget = ore
        Runtime.MiningReleaseDone = false
    end

    if not ore then
        miningMouse(false)
        setMiningState("WAIT_ORE", "No matching ore spawned")
        return 0.8
    end

    local wanted = oreName(ore)
    local distance = distanceTo(ore)

    if distance > Config.PlatformArrivalDistance then
        miningMouse(false, ore)
        setMiningState("MOVE", "Moving to " .. wanted)
        PlatformTransport.MoveNear(ore)
        return 0.18
    end

    PlatformTransport.Cancel(true)

    local pickaxe = findPickaxe()
    if not pickaxe then
        miningMouse(false, ore)
        setMiningState("MISSING_PICKAXE", "No pickaxe in hotbar")
        return 0.8
    end

    HotbarService.Press(pickaxe)

    if Config.MiningAutoAim then
        local ownRoot = rootPart()
        local targetPart = objectRoot(ore)
        if ownRoot and targetPart then
            pcall(function()
                ownRoot.CFrame = CFrame.lookAt(
                    ownRoot.Position,
                    Vector3.new(targetPart.Position.X, ownRoot.Position.Y, targetPart.Position.Z)
                )
            end)
        end
    end

    if MiningQTEService.HandleQTE(ore) then
        if Runtime.MiningReleaseDone then
            -- Wait for the game to consume the release and either reset the bar
            -- or mark the ore Mined before another swing.
            if os.clock() - Runtime.MiningLastQTE >= Config.MiningRetryDelay then
                Runtime.MiningReleaseDone = false
                Runtime.MiningLastAttempt = os.clock()
            end
        end
        return 0.035
    end

    -- No QTE yet: start/continue one mining swing by holding M1 on the ore.
    local elapsed = os.clock() - Runtime.MiningStateSince
    if Runtime.MiningState ~= "HOLD" then
        setMiningState("HOLD", "Holding M1 on " .. wanted)
        Runtime.MiningStateSince = os.clock()
        miningMouse(true, ore)
    elseif elapsed >= Config.MiningHoldTimeout then
        miningMouse(false, ore)
        Runtime.MiningLastAttempt = os.clock()
        setMiningState("RETRY", "Mining QTE timeout")
        return Config.MiningRetryDelay
    end

    return 0.05
end

-- ============================================================
-- Lifeskill / collection
-- ============================================================

LifeSkillService = {}

local function promptFeatureEnabled(kind)
    return kind == "Pickup" and Config.AutoPickup
        or kind == "Chest" and Config.AutoChest
        or kind == "WorldBossChest" and Config.AutoWorldBossChest
        or kind == "FruitChest" and Config.AutoFruitChest
        or kind == "QuestItem" and Config.AutoQuestItems
        or kind == "Farm" and (
            Config.AutoFarming
            or Runtime.ProgressLifeSkill == "Farming"
        )
end

function LifeSkillService.FindNearestEnabledPrompt()
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local kind = promptKind(prompt)

            if promptFeatureEnabled(kind) then
                local distance = distanceTo(prompt)

                if not bestDistance or distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best, bestDistance
end

function LifeSkillService.StepPrompts()
    if Config.AutoProgress then
        -- While full progression is active, only collect nearby loot.
        local prompt, distance = LifeSkillService.FindNearestEnabledPrompt()

        if prompt and distance <= 12 then
            InteractionService.FirePrompt(prompt)
        end

        return
    end

    local prompt = LifeSkillService.FindNearestEnabledPrompt()
    if not prompt then
        return
    end

    local kind = promptKind(prompt)


    if distanceTo(prompt) > Config.PlatformArrivalDistance then
        PlatformTransport.MoveNear(prompt)
    else
        PlatformTransport.Cancel(true)
        InteractionService.FirePrompt(prompt)
    end
end

-- ============================================================
-- Progression controller
-- ============================================================

ProgressionController = {}

local function setProgressState(state, detail)
    Runtime.ProgressState = state
    Runtime.ProgressDetail = detail or ""
end

local function clearFarmState()
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil
    Runtime.FarmAnchorCFrame = nil

    HitboxService.Clear()
end

local function handleQuestNpc(questName, preferredNpc, stateName)
    local npc = QuestCatalogService.FindQuestGiver(questName, preferredNpc)

    if not npc and preferredNpc then
        npc = TargetService.FindNamedNPC(preferredNpc)
    end

    if not npc then
        setProgressState("SEARCH_NPC", questName .. " / " .. tostring(preferredNpc or ""))
        return
    end

    Runtime.CurrentTarget = npc
    Runtime.CurrentWantedMob = nil
    HitboxService.Clear()

    local arrived = distanceTo(npc) <= math.max(
        Config.PlatformArrivalDistance + 2,
        9
    )

    if not arrived then
        setProgressState("MOVE_NPC", questName)
        PlatformTransport.MoveNear(npc)
        return
    end

    PlatformTransport.Cancel(true)
    setProgressState(stateName, questName)

    InteractionService.InteractWithQuestNPC(npc, questName)
end

local function handleDefeatTask(quest, taskData)
    local wanted = taskData.Target
    local current = Runtime.CurrentTarget

    if not current
        or not current.Parent
        or not TargetService.IsFarmMob(current, wanted) then

        current = TargetService.Find(wanted)
        Runtime.CurrentTarget = current
        Runtime.FarmAnchorCFrame = nil
    end

    Runtime.CurrentWantedMob = wanted

    if not current then
        setProgressState("SEARCH_MOBS", wanted)
        return
    end

    if not Runtime.FarmAnchorCFrame then
        PlatformTransport.SetFarmAnchorFrom(current)
    end

    local root = rootPart()
    local anchor = Runtime.FarmAnchorCFrame
    local atAnchor = root
        and anchor
        and (root.Position - anchor.Position).Magnitude
            <= Config.PlatformArrivalDistance

    if not atAnchor then
        setProgressState("MOVE_ABOVE_MOBS", wanted)
        PlatformTransport.MoveToFarmAnchor()
        return
    end

    PlatformTransport.Cancel(true)

    setProgressState("FARM_QUEST_MOBS", wanted)

    BringService.Step(wanted)
    HitboxService.Step(wanted)

    -- Keep a current target for aim/ESP, but farm is centered below the player.
    if not Runtime.CurrentTarget
        or not Runtime.CurrentTarget.Parent
        or not TargetService.IsFarmMob(Runtime.CurrentTarget, wanted) then
        Runtime.CurrentTarget = TargetService.Find(wanted)
    end

    if Runtime.CurrentTarget then
        CombatService.AimAt(Runtime.CurrentTarget)
    end

    CombatService.AttackStep()
end

local function handleCollectTask(quest, taskData)
    clearFarmState()

    local allowed = {
        Pickup = true,
        QuestItem = true,
        Chest = true,
        FruitChest = true,
        Other = true,
    }

    local prompt = InteractionService.FindPromptByText(
        taskData.Target,
        allowed
    )

    if not prompt then
        setProgressState("SEARCH_OBJECT", taskData.Target)
        return
    end

    Runtime.CurrentTarget = prompt

    if distanceTo(prompt) > Config.PlatformArrivalDistance + 2 then
        setProgressState("MOVE_OBJECT", taskData.Target)
        PlatformTransport.MoveNear(prompt)
        return
    end

    PlatformTransport.Cancel(true)
    setProgressState("INTERACT_OBJECT", taskData.Target)
    InteractionService.FirePrompt(prompt)
end

function ProgressionController.Step()
    if not Config.AutoProgress then
        Runtime.ProgressLifeSkill = nil
        setProgressState("IDLE", "Auto Progress disabled")
        clearFarmState()
        return
    end

    Runtime.ProgressLifeSkill = nil

    if not PlayerState.IsReady() then
        setProgressState("WAIT_PLAYER", "Player data/character not ready")
        return
    end

    if Config.FarmMode == "Selected Mob" then
        local pseudoQuest = {Name = "Selected Mob"}
        local pseudoTask = {
            Kind = "Defeat",
            Target = Config.SelectedMob,
            Text = "Farm " .. Config.SelectedMob,
        }

        handleDefeatTask(pseudoQuest, pseudoTask)
        return
    end

    if not Config.AutoQuest then
        setProgressState("WAIT_QUEST", "Auto Quest disabled")
        clearFarmState()
        return
    end

    local stateKey = QuestService.StateKey()
    if stateKey ~= Runtime.ProgressQuestKey then
        Runtime.ProgressQuestKey = stateKey
        Runtime.LastQuestChange = os.clock()

        PlatformTransport.Cancel(true)
        Runtime.FarmAnchorCFrame = nil
        HitboxService.Clear()
    end

    local completed = QuestService.GetCompletedQuest()

    if completed and Config.AutoTurnIn then
        clearFarmState()
        handleQuestNpc(completed.Name, nil, "TURN_IN")
        return
    end

    local quest, taskData = QuestService.GetNextTask()

    if quest and taskData then
        if taskData.Kind == "Defeat" then
            handleDefeatTask(quest, taskData)
        elseif taskData.Kind == "Talk"
            or taskData.Kind == "Return"
            or taskData.Kind == "Deliver" then

            clearFarmState()
            handleQuestNpc(
                quest.Name,
                taskData.Target,
                "QUEST_DIALOGUE"
            )
        elseif taskData.Kind == "Collect"
            or taskData.Kind == "Find" then

            handleCollectTask(quest, taskData)
        elseif taskData.Kind == "Fish" then
            clearFarmState()
            Runtime.ProgressLifeSkill = "Fishing"
            setProgressState(
                "QUEST_FISHING",
                taskData.Text
            )
        elseif taskData.Kind == "Mine" then
            clearFarmState()
            Runtime.ProgressLifeSkill = "Mining"
            setProgressState(
                "QUEST_MINING",
                taskData.Text
            )
        elseif taskData.Kind == "Farm" then
            clearFarmState()
            Runtime.ProgressLifeSkill = "Farming"
            setProgressState(
                "QUEST_FARMING",
                taskData.Text
            )
        elseif taskData.Kind == "Craft"
            or taskData.Kind == "Cook"
            or taskData.Kind == "Upgrade"
            or taskData.Kind == "Learn" then

            clearFarmState()
            setProgressState(
                "QUEST_MANUAL_ACTION",
                taskData.Text
            )
        else
            -- Generic resolver: try object prompt first, then named NPC.
            local prompt = InteractionService.FindPromptByText(taskData.Target)

            if prompt then
                handleCollectTask(quest, taskData)
            else
                clearFarmState()
                handleQuestNpc(
                    quest.Name,
                    taskData.Target,
                    "QUEST_GENERIC"
                )
            end
        end

        return
    end

    local recommended = QuestService.GetRecommended()

    if recommended and Config.AutoAcceptRecommended then
        clearFarmState()
        handleQuestNpc(
            recommended.Name,
            nil,
            "ACCEPT_RECOMMENDED"
        )
        return
    end

    clearFarmState()
    PlatformTransport.Cancel(true)
    setProgressState(
        "IDLE",
        "No active/recommended quest at Lv." .. PlayerState.GetLevel()
    )
end

-- ============================================================
-- Character modifiers
-- ============================================================

local function restoreCollision()
    for part, value in pairs(Core.CollisionBackup) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = value
            end)
        end
    end

    table.clear(Core.CollisionBackup)
end

local function updateCharacter()
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
        or (
            Config.PlatformNoclip
            and Runtime.TransportMoving
        )

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
        updateCharacter()
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
-- ESP
-- ============================================================

ESPService = {
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
    if not object
        or not object.Parent
        or distanceTo(object) > Config.ESPDistance then

        ESPService.Clear(object)
        return
    end

    local adornee

    if object:IsA("Model") or object:IsA("BasePart") then
        adornee = object
    else
        adornee = object:FindFirstAncestorWhichIsA("Model")
            or objectRoot(object)
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
end

function ESPService.Step()
    local active = {}

    if Config.CurrentTargetESP and Runtime.CurrentTarget then
        active[Runtime.CurrentTarget] = true
        ESPService.Set(Runtime.CurrentTarget, Config.TargetColor)
    end

    if Config.MobESP or Config.BossESP then
        for model in pairs(Runtime.Entities) do
            if TargetService.IsAliveNPC(model)
                and not TargetService.IsDialogueNPC(model) then

                if Config.BossESP and TargetService.IsBoss(model) then
                    active[model] = true
                    ESPService.Set(model, Config.BossColor)
                elseif Config.MobESP and TargetService.IsHostile(model) then
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
-- Schedulers
-- ============================================================

task.spawn(function()
    while Core.Running do
        local delay = MiningQTEService.Step()
        task.wait(tonumber(delay) or 0.5)
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.AutoClaim then
            InteractionService.ProcessClaimButtons()
        end

        task.wait(Config.AutoClaim and 0.8 or 1.5)
    end
end)

task.spawn(function()
    while Core.Running do
        local active =
            Config.CurrentTargetESP
            or Config.MobESP
            or Config.BossESP
            or Config.LootESP

        if active then
            ESPService.Step()
        end

        task.wait(active and 0.85 or 1.8)
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

task.spawn(function()
    while Core.Running do
        local level = PlayerState.GetLevel()

        if Runtime.LastLevel == nil then
            Runtime.LastLevel = level
        elseif Runtime.LastLevel ~= level then
            local previous = Runtime.LastLevel
            Runtime.LastLevel = level

            notify(
                "Level Up",
                string.format(
                    "Lv.%d → Lv.%d • progression refreshed",
                    previous,
                    level
                ),
                4
            )

            Runtime.FarmAnchorCFrame = nil
            PlatformTransport.Cancel(true)
        end

        task.wait(0.5)
    end
end)

-- ============================================================
-- UI helpers
-- ============================================================

local function currentQuestSummary()
    local completed = QuestService.GetCompletedQuest()
    if completed then
        return completed.Name .. " → ready to turn in"
    end

    local quest, taskData = QuestService.GetNextTask()
    if quest and taskData then
        return quest.Name .. " → " .. taskData.Text
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "Recommended → " .. recommended.Name
    end

    return "None"
end

local function runtimeStatus()
    return table.concat({
        "SON HUB v" .. VERSION,
        "Level: " .. tostring(PlayerState.GetLevel()),
        "World: " .. PlayerState.GetWorld(),
        "Fruit: " .. PlayerState.GetFruit()
            .. " (Lv." .. PlayerState.GetFruitLevel() .. ")",
        "Bounty: " .. tostring(PlayerState.GetLeaderValue("Bounty") or 0),
        "Faction: " .. tostring(PlayerState.GetLeaderValue("Faction") or "None"),
        "Crew: " .. tostring(PlayerState.GetLeaderValue("Crew") or "None"),
        "Quest: " .. currentQuestSummary(),
        "Progress: " .. Runtime.ProgressState
            .. " • " .. Runtime.ProgressDetail,
        "Hotbar: " .. HotbarService.GetSnapshot(),
        "Quest catalog: " .. tostring(#Runtime.QuestCatalog),
    }, "\n")
end

local function detectedSystems()
    return table.concat({
        "151 Quest modules + live RecommendedQuest",
        "DialogueNPC QuestName / QuestNode mapping",
        "Entities / Combat / BossCombat",
        "Moving Platform transport",
        "Quest-only Bring + mob-only Hitbox",
        "Custom 0-9 Hotbar + Cooldown/EXP",
        "Auto Stats via Radar stat buttons",
        "Skill EXP / Mastery candidate cycling",
        "Fishing: SHAKE / CLICK / Timed Release / Reel",
        "Mining Critical Zone QTE",
        "Fishing / Mining / Farming",
        "Fruit / FruitLevel",
        "Bounty / Faction / Crew",
        "Pickup / Chest / Fruit Chest / World Boss Chest",
        "Treasure / DigSpots",
        "Logbook Claim",
        "Block = F",
    }, "\n")
end

-- ============================================================
-- UI
-- ============================================================

local Window = Library:CreateWindow({
    Title = "SON HUB",
    Subtitle = "Quest Platform Farm • make by hongson",
    SubtitleColor = Color3.fromRGB(100, 190, 255),
    Logo = SON_ICON_URL,
    LogoSize = 32,
    SphereText = false,
    SphereWords = "SON",
    SphereImage = SON_ICON_URL,
    SphereIconSize = 38,
})

-- ---------------- Home ----------------

local HomeTab = Window:CreateTab("⌂ Trang Chủ", true, false)
local HomePage = HomeTab:CreatePage("Dashboard")

local StatusCard = HomePage:CreateSection("Live Status")

StatusCard:AddButton("Show Runtime Status", function()
    notify("SON HUB", runtimeStatus(), 10)
end)

StatusCard:AddButton("Refresh Index / Quest Map", function()
    task.spawn(function()
        RuntimeIndex.Rebuild()
        QuestCatalogService.Build()
        HotbarService.Refresh()
        notify(
            "SON HUB",
            "Index rebuilt • "
                .. tostring(#Runtime.QuestCatalog)
                .. " quests",
            4
        )
    end)
end)

local QuickCard = HomePage:CreateSection("One Toggle")

QuickCard:AddToggle("Full Auto Progress", false, function(value)
    Config.AutoProgress = value

    if value then
        Config.FarmMode = "Smart Quest"
        Config.AutoQuest = true
        Config.BringMobs = true
        Config.MobHitbox = true
        Config.AutoAttack = true
        Config.AutoClaim = true

        notify(
            "Full Auto",
            "Quest → Platform → Bring → Hitbox → Kill → Turn-in",
            4
        )
    else
        PlatformTransport.Cancel(false)
        HitboxService.Clear()
        Runtime.FarmAnchorCFrame = nil
        Runtime.CurrentTarget = nil
    end
end, {
    Title = "Full Auto Progress",
    Description = "Tự nhận quest, lên platform trên khu mob, bring đúng mob task xuống dưới chân, hitbox mob, đánh đến khi task hoàn thành rồi turn-in.",
})

QuickCard:AddToggle("Auto Stats", false, function(value)
    Config.AutoStats = value
end)

QuickCard:AddToggle("Auto Mastery", false, function(value)
    Config.AutoMastery = value
end)

QuickCard:AddToggle("Full Auto Everything", false, function(value)
    Config.AutoProgress = value
    Config.AutoStats = value
    Config.AutoMastery = value
    Config.AutoQuest = true
    Config.BringMobs = true
    Config.MobHitbox = true
    Config.AutoAttack = true
    Config.AutoClaim = true

    if not value then
        PlatformTransport.Cancel(false)
        HitboxService.Clear()
    end
end, {
    Title = "Progress + Stats + Mastery",
    Description = "Bật chung Auto Progress, Auto Stats và Auto Mastery. Stat Build/Mastery Mode vẫn theo cấu hình bạn chọn.",
})

-- ---------------- Farm ----------------

local FarmTab = Window:CreateTab("⚔ Farm", false, false)
local FarmPage = FarmTab:CreatePage("Quest Farm")
local BringPage = FarmTab:CreatePage("Bring / Hitbox")
local MasteryPage = FarmTab:CreatePage("Mastery")

local FarmCard = FarmPage:CreateSection("Progression")

FarmCard:AddToggle("Auto Progress", false, function(value)
    Config.AutoProgress = value

    if not value then
        PlatformTransport.Cancel(false)
        HitboxService.Clear()
    end
end)

FarmCard:AddDropdown(
    "Farm Mode",
    {"Smart Quest", "Selected Mob"},
    false,
    function(value)
        Config.FarmMode = value
        Runtime.FarmAnchorCFrame = nil
    end
)

local mobOptions = TargetService.GetMobOptions()

FarmCard:AddDropdown("Selected Mob", mobOptions, false, function(value)
    Config.SelectedMob = value
    Runtime.FarmAnchorCFrame = nil
end)

FarmCard:AddToggle("Auto Attack", true, function(value)
    Config.AutoAttack = value
end)

FarmCard:AddSlider("Attack / Second", 2, 20, Config.AttackRate, function(value)
    Config.AttackRate = value
end)

local PlatformCard = FarmPage:CreateSection("Moving Platform")

PlatformCard:AddToggle("Platform Transport", true, function(value)
    Config.PlatformTransport = value

    if not value then
        PlatformTransport.Cancel(false)
    end
end, {
    Title = "Platform Movement",
    Description = "Tạo một platform local dưới chân, weld người chơi vào platform trong lúc platform Tween, đến nơi thì tháo weld và để platform đứng yên.",
})

PlatformCard:AddSlider("Platform Speed", 60, 450, Config.PlatformSpeed, function(value)
    Config.PlatformSpeed = value
end)

PlatformCard:AddSlider("Farm Height", 6, 24, Config.PlatformFarmHeight, function(value)
    Config.PlatformFarmHeight = value
    Runtime.FarmAnchorCFrame = nil
end)

PlatformCard:AddSlider("Platform Size", 5, 14, Config.PlatformSize, function(value)
    Config.PlatformSize = value
end)

PlatformCard:AddSlider(
    "Platform Transparency x10",
    0,
    10,
    math.floor(Config.PlatformTransparency * 10),
    function(value)
        Config.PlatformTransparency = value / 10
    end
)

PlatformCard:AddButton("Destroy Platform", function()
    PlatformTransport.Cancel(false)
end)

local BringCard = BringPage:CreateSection("Quest Mob Bring")

BringCard:AddToggle("Bring Matching Mobs", true, function(value)
    Config.BringMobs = value
end)

BringCard:AddSlider("Bring Radius", 25, 220, Config.BringRadius, function(value)
    Config.BringRadius = value
end)

BringCard:AddSlider("Bring Limit", 1, 20, Config.BringLimit, function(value)
    Config.BringLimit = value
end)

BringCard:AddSlider("Below Feet", 4, 14, Config.MobBelowFeet, function(value)
    Config.MobBelowFeet = value
end)

BringCard:AddToggle("Bring Bosses", false, function(value)
    Config.BringBosses = value
end)

local HitboxCard = BringPage:CreateSection("Mob Hitbox Only")

HitboxCard:AddToggle("Mob Hitbox", true, function(value)
    Config.MobHitbox = value

    if not value then
        HitboxService.Clear()
    end
end, {
    Title = "Mob-only Hitbox",
    Description = "Chỉ áp dụng lên alive combat mob phù hợp target. Player, civilian và dialogue NPC bị loại.",
})

HitboxCard:AddSlider("Hitbox Size", 4, 18, Config.HitboxSize, function(value)
    Config.HitboxSize = value
end)

HitboxCard:AddSlider(
    "Hitbox Transparency x10",
    0,
    10,
    math.floor(Config.HitboxTransparency * 10),
    function(value)
        Config.HitboxTransparency = value / 10
    end
)

HitboxCard:AddToggle("Hitbox Bosses", false, function(value)
    Config.HitboxBosses = value
end)

local WeaponCard = MasteryPage:CreateSection("Weapon / Skill")

local weaponOptions = HotbarService.GetWeaponOptions()

WeaponCard:AddDropdown("Selected Weapon", weaponOptions, false, function(value)
    Config.SelectedWeapon = value
end)

WeaponCard:AddButton("Show Hotbar", function()
    notify("Hotbar", HotbarService.GetSnapshot(), 8)
end)

local MasteryCard = MasteryPage:CreateSection("Auto Mastery")

MasteryCard:AddToggle("Auto Farm Mastery", false, function(value)
    Config.AutoMastery = value
end, {
    Title = "Auto Mastery",
    Description = "Trong lúc farm, tự cycle các skill hotbar đang ready để kiếm Skill EXP thay vì chỉ spam một slot.",
})

MasteryCard:AddDropdown(
    "Mastery Mode",
    {"Combat Skills", "Current Fruit", "Selected Skill"},
    false,
    function(value)
        Config.MasteryMode = value
        Runtime.MasteryCursor = 0
    end
)

MasteryCard:AddSlider(
    "Mastery Interval x100",
    15,
    150,
    math.floor(Config.MasteryInterval * 100),
    function(value)
        Config.MasteryInterval = value / 100
    end
)

MasteryCard:AddToggle("Ready Skills Only", true, function(value)
    Config.MasteryReadyOnly = value
end)

MasteryCard:AddButton("Show Mastery Candidates", function()
    notify("Mastery", MasteryService.GetSnapshot(), 10)
end)

-- ---------------- Combat ----------------

local CombatTab = Window:CreateTab("☠ Combat", false, false)
local CombatPage = CombatTab:CreatePage("Chiến Đấu")

local CombatCard = CombatPage:CreateSection("Combat")

CombatCard:AddToggle("Auto Aim", true, function(value)
    Config.AutoAim = value
end)

CombatCard:AddToggle("Auto Block Low HP", false, function(value)
    Config.AutoBlock = value

    if not value then
        setBlock(false)
    end
end)

CombatCard:AddSlider(
    "Block Below HP %",
    10,
    80,
    Config.BlockHealthPercent,
    function(value)
        Config.BlockHealthPercent = value
    end
)

local CombatESPCard = CombatPage:CreateSection("ESP")

CombatESPCard:AddToggle("Current Target ESP", true, function(value)
    Config.CurrentTargetESP = value
end)

CombatESPCard:AddToggle("Mob ESP", false, function(value)
    Config.MobESP = value
end)

CombatESPCard:AddToggle("Boss ESP", false, function(value)
    Config.BossESP = value
end)

-- ---------------- Movement ----------------

local MovementTab = Window:CreateTab("➤ Movement", false, false)
local TransportPage = MovementTab:CreatePage("Platform")
local CharacterPage = MovementTab:CreatePage("Character")

local TransportCard = TransportPage:CreateSection("Transport Status")

TransportCard:AddButton("Re-seat Platform Under Feet", function()
    PlatformTransport.Cancel(false)
    PlatformTransport.Ensure()
end)

TransportCard:AddToggle("Movement Noclip", true, function(value)
    Config.PlatformNoclip = value
end)

TransportCard:AddSlider(
    "Arrival Distance",
    2,
    12,
    Config.PlatformArrivalDistance,
    function(value)
        Config.PlatformArrivalDistance = value
    end
)

local CharacterCard = CharacterPage:CreateSection("Character")

CharacterCard:AddToggle("WalkSpeed Override", false, function(value)
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

    if not value and not Runtime.TransportMoving then
        restoreCollision()
    end
end)

-- ---------------- Player ----------------

local PlayerTab = Window:CreateTab("☺ Player", false, false)
local StatsPage = PlayerTab:CreatePage("Stats")
local LootPage = PlayerTab:CreatePage("Loot")
local LifePage = PlayerTab:CreatePage("Life Skills")

local StatsCard = StatsPage:CreateSection("Auto Stats")

StatsCard:AddToggle("Auto Stats", false, function(value)
    Config.AutoStats = value
end)

StatsCard:AddDropdown(
    "Stat Build",
    {
        "Auto Weapon",
        "Balanced",
        "Strength",
        "Precision",
        "Tank",
        "Mobility",
        "Haki",
    },
    false,
    function(value)
        Config.StatBuild = value
    end
)

StatsCard:AddButton("Show Stats", function()
    notify("Stats", StatsService.GetSnapshot(), 9)
end)

local LootCard = LootPage:CreateSection("Loot")

LootCard:AddToggle("Auto Pickup", false, function(value)
    Config.AutoPickup = value
end)

LootCard:AddToggle("Auto Chest", false, function(value)
    Config.AutoChest = value
end)

LootCard:AddToggle("Auto World Boss Chest", false, function(value)
    Config.AutoWorldBossChest = value
end)

LootCard:AddToggle("Auto Fruit Chest", false, function(value)
    Config.AutoFruitChest = value
end)

LootCard:AddToggle("Auto Quest Items", false, function(value)
    Config.AutoQuestItems = value
end)

LootCard:AddToggle("Loot ESP", false, function(value)
    Config.LootESP = value
end)

local FishingCard = LifePage:CreateSection("Fishing")

FishingCard:AddToggle("Auto Fishing", false, function(value)
    Config.AutoFishing = value
    FishingService.Reset(value and "Enabled" or "Disabled")
end)

FishingCard:AddDropdown(
    "Fishing Spot",
    {"Saved Position", "Anchor Town Pond", "Current Position"},
    false,
    function(value)
        Config.FishingSpotMode = value
        FishingService.Reset("Spot changed")
    end
)

FishingCard:AddButton("Save Current Fishing Spot", function()
    local root = rootPart()

    if root then
        Runtime.FishingSpotCFrame = root.CFrame
        Config.FishingSpotMode = "Saved Position"
        FishingService.Reset("Saved current spot")
        notify("Fishing", "Current fishing spot saved.", 3)
    end
end)

FishingCard:AddToggle("Auto Return To Spot", true, function(value)
    Config.FishingAutoReturn = value
end)

FishingCard:AddToggle("Require Bait", false, function(value)
    Config.FishingRequireBait = value
end)

FishingCard:AddToggle("Auto SHAKE", true, function(value)
    Config.FishingAutoShake = value
end)

FishingCard:AddToggle("Auto CLICK Spam", true, function(value)
    Config.FishingAutoSpamClick = value
end)

FishingCard:AddToggle("Auto Timed Release", true, function(value)
    Config.FishingAutoTimedRelease = value
end)

FishingCard:AddSlider(
    "Release Threshold %",
    70,
    99,
    math.floor(Config.FishingReleaseThreshold * 100),
    function(value)
        Config.FishingReleaseThreshold = value / 100
    end
)

FishingCard:AddSlider(
    "Reel Tolerance",
    5,
    40,
    Config.FishingReelTolerance,
    function(value)
        Config.FishingReelTolerance = value
    end
)

FishingCard:AddToggle("Auto Calibrate Reel Direction", true, function(value)
    Config.FishingAutoCalibrate = value
    Runtime.FishingReelCalibrated = false
end, {
    Title = "Hold / Release Reel Calibration",
    Description = "Move là thanh lớn, Fish là cục mục tiêu. Hub tự thử HOLD ngắn để biết HOLD đẩy thanh sang trái hay phải rồi giữ Fish nằm trong Move.",
})

FishingCard:AddButton("Check Fishing Conditions", function()
    local c = FishingService.GetConditions()

    notify(
        "Fishing Conditions",
        table.concat({
            "State: " .. tostring(c.State),
            "Can Start: " .. tostring(c.CanStart),
            "Rod: " .. tostring(c.Rod)
                .. " [" .. tostring(c.RodSource) .. "]",
            "Bait: " .. tostring(c.Bait)
                .. " x" .. tostring(c.BaitAmount),
            "Bait Required: " .. tostring(c.BaitRequired),
            "Spot: " .. tostring(c.Spot),
            "Reason: " .. tostring(c.Reason),
        }, "\n"),
        10
    )
end)

local MiningCard = LifePage:CreateSection("Mining / Farming")

MiningCard:AddToggle("Auto Mining", false, function(value)
    Config.AutoMining = value
    MiningQTEService.Reset(value and "Enabled" or "Disabled")
end, {
    Title = "Auto Mining",
    Description = "Chọn đúng Ore model theo attribute Ore/Name, đi tới khoáng sản, equip pickaxe, HOLD chuột và RELEASE trong Critical Zone.",
})

MiningCard:AddDropdown(
    "Mining Mode",
    {"Quest Required", "Selected Ore", "Any Available", "Highest Drop"},
    false,
    function(value)
        Config.MiningMode = value
        MiningQTEService.Reset("Mining mode changed")
    end
)

MiningCard:AddDropdown(
    "Select Ore",
    {"Copper Ore", "Iron Ore", "Silver Ore", "Gold Ore", "Diamond Ore"},
    false,
    function(value)
        Config.SelectedOre = value
        MiningQTEService.Reset("Ore selection changed")
    end,
    {
        Title = "Ore Type",
        Description = "Game dump xác nhận Copper/Iron/Silver/Gold/Diamond Ore. Snapshot hiện có Copper + Iron đang spawn.",
    }
)

MiningCard:AddToggle("Auto Mining QTE", true, function(value)
    Config.AutoMiningQTE = value
end)

MiningCard:AddButton("Show Mining State", function()
    local target = Runtime.MiningTarget
    notify(
        "Mining",
        table.concat({
            "State: " .. tostring(Runtime.MiningState),
            "Mode: " .. tostring(Config.MiningMode),
            "Wanted: " .. tostring(MiningQTEService.GetWantedOre() or "Any"),
            "Target: " .. tostring(target and oreName(target) or "None"),
            "DropAmount: " .. tostring(target and target:GetAttribute("DropAmount") or "-"),
            "Mined: " .. tostring(target and target:GetAttribute("Mined") or "-"),
        }, "\n"),
        8
    )
end)

MiningCard:AddToggle("Auto Farming", false, function(value)
    Config.AutoFarming = value
end)

local UtilityCard = LifePage:CreateSection("Utility")

UtilityCard:AddToggle("Anti AFK", true, function(value)
    Config.AntiAFK = value
end)

-- ---------------- Quest ----------------

local QuestTab = Window:CreateTab("✦ Quest", false, false)
local CurrentQuestPage = QuestTab:CreatePage("Current")
local CatalogPage = QuestTab:CreatePage("Catalog")

local QuestCard = CurrentQuestPage:CreateSection("Automation")

QuestCard:AddToggle("Auto Quest", true, function(value)
    Config.AutoQuest = value
end)

QuestCard:AddToggle("Auto Accept Recommended", true, function(value)
    Config.AutoAcceptRecommended = value
end)

QuestCard:AddToggle("Auto Turn In", true, function(value)
    Config.AutoTurnIn = value
end)

QuestCard:AddToggle("Auto Dialogue", true, function(value)
    Config.AutoDialogue = value
end)

QuestCard:AddToggle("Auto Claim", true, function(value)
    Config.AutoClaim = value
end)

local QuestStatusCard = CurrentQuestPage:CreateSection("State")

QuestStatusCard:AddButton("Show Current Quest", function()
    notify(
        "Quest",
        "Lv." .. tostring(PlayerState.GetLevel())
            .. "\n"
            .. currentQuestSummary()
            .. "\nWorker: "
            .. Runtime.ProgressState
            .. " • "
            .. Runtime.ProgressDetail,
        10
    )
end)

QuestStatusCard:AddButton("Rebuild Quest NPC Map", function()
    QuestCatalogService.Build()

    notify(
        "Quest Map",
        tostring(#Runtime.QuestCatalog)
            .. " quest modules indexed.",
        4
    )
end)

if #Runtime.QuestCatalog == 0 then
    QuestCatalogService.Build()
end

local questCatalogOptions = QuestCatalogService.GetNames()
local selectedQuestPath = questCatalogOptions[1]

local CatalogCard = CatalogPage:CreateSection("All Game Quests")

CatalogCard:AddDropdown(
    "Quest Catalog",
    questCatalogOptions,
    false,
    function(value)
        selectedQuestPath = value
    end
)

CatalogCard:AddButton("Find Quest Giver", function()
    local questName = tostring(selectedQuestPath):match("([^/]+)$")
        or tostring(selectedQuestPath)

    local npc = QuestCatalogService.FindQuestGiver(questName)

    if npc then
        Runtime.CurrentTarget = npc
        PlatformTransport.MoveNear(npc)
        notify("Quest Giver", questName .. " → " .. npc.Name, 5)
    else
        notify("Quest Giver", "No mapped NPC for " .. questName, 4)
    end
end)

CatalogCard:AddCopyButton(
    "Quest Count",
    tostring(#Runtime.QuestCatalog),
    {
        Title = "Quest Catalog",
        Description = "Quest modules discovered from ReplicatedStorage.Modules.QuestInfo.Quests.",
    }
)

-- ---------------- Settings ----------------

local SettingsTab = Window:CreateTab("✧ Settings", false, false)
local SettingsPage = SettingsTab:CreatePage("Cài Đặt")

local InterfaceCard = SettingsPage:CreateSection("Interface")

InterfaceCard:AddToggle("Glass UI", false, function(value)
    Window:SetTransparency(value and 0.18 or 0)
end)

local ConfigCard = SettingsPage:CreateSection("Config")
ConfigCard:AddConfigManager("son_hub_v6")

local RuntimeCard = SettingsPage:CreateSection("Runtime")

RuntimeCard:AddButton("Reset Automation State", function()
    PlatformTransport.Cancel(false)
    HitboxService.Clear()

    Runtime.ProgressQuestKey = nil
    Runtime.FarmAnchorCFrame = nil
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil

    FishingService.Reset("Manual reset")
    MiningQTEService.Reset("Manual reset")

    notify("SON HUB", "Automation state reset.", 3)
end)

RuntimeCard:AddButton("Unload SON HUB", function()
    if ENV.__SON_HUB_UNLOAD then
        ENV.__SON_HUB_UNLOAD()
    end
end)

-- ---------------- Info ----------------

local InfoTab = Window:CreateTab("❖ Info", false, false)
local InfoPage = InfoTab:CreatePage("Thông Tin")

local AboutCard = InfoPage:CreateSection("SON HUB")

AboutCard:AddCopyButton("Version", VERSION)
AboutCard:AddCopyButton("Target PlaceId", tostring(EXPECTED_PLACE_ID))
AboutCard:AddCopyButton("Icon URL", SON_ICON_URL)

AboutCard:AddButton("Show Detected Systems", function()
    notify("Detected Systems", detectedSystems(), 12)
end)

AboutCard:AddButton("Show Full Runtime", function()
    notify("SON HUB", runtimeStatus(), 12)
end)

local LimitCard = InfoPage:CreateSection("Snapshot Limits")

LimitCard:AddButton("Source Availability", function()
    notify(
        "DexBridge Snapshot",
        "232,910 Instances\n27,826 UI objects\n31,197 script objects\n0 script source files\n\nQuest/UI/object logic is mapped from client-visible structures; hidden remote contracts are not guessed.",
        10
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
    Config.AutoProgress = false
    Config.AutoFishing = false
    Config.AutoStats = false

    setBlock(false)
    releaseFishingKey()
    setFishingMouseHeld(false)

    PlatformTransport.Cancel(false)
    HitboxService.Clear()
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
            if instance and instance.Parent then
                instance:Destroy()
            end
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
    QuestCatalogService.Build()

    local mismatch = game.PlaceId ~= EXPECTED_PLACE_ID
    local prefix = mismatch
        and ("Place mismatch: " .. tostring(game.PlaceId) .. "\n")
        or ""

    notify(
        "SON HUB v6 Ready",
        prefix
            .. "Lv."
            .. tostring(PlayerState.GetLevel())
            .. " • "
            .. PlayerState.GetFruit()
            .. " • "
            .. tostring(#Runtime.QuestCatalog)
            .. " quests indexed",
        6
    )
end)
