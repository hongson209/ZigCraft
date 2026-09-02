--[[
    SON HUB v9 - Nexomia Safe
    Target PlaceId: 118635363908336
    UI: Fluent
    make by hongson

    Goals:
    - small/clean core
    - no WebSocket/getscriptclosure dependency
    - direct Fluent API
    - one owner for progression/movement
    - visible worker health instead of silent failures
    - no print/warn spam
]]

-- ============================================================
-- Bootstrap / executor compatibility
-- ============================================================

local VERSION = "9.0.0"
local TARGET_PLACE = 118635363908336
local FLUENT_URL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"

local ENV = _G
if type(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        ENV = env
    end
end

if type(ENV.__SON_HUB_UNLOAD) == "function" then
    pcall(ENV.__SON_HUB_UNLOAD)
end

local function envFunction(name)
    local value = rawget(ENV, name)
    if type(value) == "function" then
        return value
    end

    value = rawget(_G, name)
    if type(value) == "function" then
        return value
    end

    return nil
end

local requestFn =
    envFunction("request")
    or envFunction("http_request")
    or (type(rawget(ENV, "http")) == "table" and rawget(ENV, "http").request)
    or (
        type(rawget(ENV, "syn")) == "table"
        and type(rawget(ENV, "syn").request) == "function"
        and rawget(ENV, "syn").request
    )

local firePromptFn = envFunction("fireproximityprompt")
local fireSignalFn = envFunction("firesignal")
local clipboardFn = envFunction("setclipboard")

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local okVim, VirtualInputManager = pcall(function()
    return game:GetService("VirtualInputManager")
end)
if not okVim then
    VirtualInputManager = nil
end

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local function httpGet(url)
    local ok, body = pcall(function()
        if type(game.HttpGet) == "function" then
            return game:HttpGet(url)
        end
    end)

    if ok and type(body) == "string" and #body > 100 then
        return body
    end

    if type(requestFn) == "function" then
        local okRequest, response = pcall(requestFn, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "SON-HUB/Nexomia",
            },
        })

        if okRequest and type(response) == "table" then
            local responseBody = response.Body or response.body
            if type(responseBody) == "string" and #responseBody > 100 then
                return responseBody
            end
        end
    end

    return nil
end

local fluentSource = httpGet(FLUENT_URL)
if type(fluentSource) ~= "string" then
    error("SON HUB: cannot download Fluent (HttpGet/request unavailable)")
end

if type(loadstring) ~= "function" then
    error("SON HUB: executor does not expose loadstring")
end

local fluentChunk, fluentCompileError = loadstring(fluentSource)
if type(fluentChunk) ~= "function" then
    error("SON HUB: Fluent compile error: " .. tostring(fluentCompileError))
end

local okFluent, Fluent = pcall(fluentChunk)
if not okFluent or type(Fluent) ~= "table" then
    error("SON HUB: Fluent init error: " .. tostring(Fluent))
end

-- ============================================================
-- Runtime
-- ============================================================

local Config = {
    AutoProgress = false,
    AutoQuest = true,

    Weapon = "Auto",
    AutoAttack = true,
    AutoMastery = true,
    AttackRate = 8,

    BringMobs = true,
    BringRadius = 95,
    BringLimit = 8,
    BringDistance = 4,

    MobHitbox = true,
    HitboxSize = 8,

    FarmHeight = 20,
    PlatformSpeed = 160,
    ArrivalDistance = 7,

    AutoStats = false,
    StatsMode = "Auto Weapon",

    AutoPickup = false,
    AutoChest = false,
    AutoWorldBossChest = false,
    AutoFruitChest = false,

    AutoFishing = false,
    FishingSpot = nil,
    FishingTolerance = 12,
    FishingRequireBait = false,

    AutoMining = false,
    MiningMode = "Quest Required",
    SelectedOre = "Copper Ore",

    AutoBlock = false,
    BlockBelow = 35,
}

local Runtime = {
    Running = true,
    Connections = {},

    Prompts = setmetatable({}, {__mode = "k"}),
    Entities = setmetatable({}, {__mode = "k"}),
    Ores = setmetatable({}, {__mode = "k"}),

    DialogueQuestCache = setmetatable({}, {__mode = "k"}),

    CurrentTarget = nil,
    WantedMob = nil,
    FarmAnchor = nil,

    Platform = nil,
    PlatformWeld = nil,
    PlatformTween = nil,
    OldAutoRotate = nil,

    LastAttack = 0,
    LastBring = 0,
    LastHitbox = 0,
    LastStat = 0,

    FishingState = "IDLE",
    FishingCastAt = 0,
    FishingHold = false,
    FishingCalibrated = false,
    FishingHoldDirection = 1,
    FishingMoveCenter = nil,

    MiningTarget = nil,
    MiningState = "IDLE",
    MiningHold = false,

    State = "IDLE",
    Detail = "Ready",

    Workers = {
        Progress = 0,
        Fishing = 0,
        Mining = 0,
        Loot = 0,
        Stats = 0,
        Block = 0,
    },

    Errors = {},
    ErrorCount = {},
    LastNotifyError = {},
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Runtime.Connections, connection)
    return connection
end

local function setState(state, detail)
    Runtime.State = state
    Runtime.Detail = detail or ""
end

local function notify(title, content, duration)
    if not Fluent then
        return
    end

    pcall(function()
        Fluent:Notify({
            Title = tostring(title),
            Content = tostring(content or ""),
            Duration = duration or 4,
        })
    end)
end

local function tracebackMessage(err)
    local message = tostring(err)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, trace = pcall(debug.traceback, message, 2)
        if ok and type(trace) == "string" then
            return trace
        end
    end
    return message
end

local function safeWorker(name, callback)
    local ok, result = xpcall(callback, tracebackMessage)

    if ok then
        Runtime.Errors[name] = nil
        Runtime.ErrorCount[name] = 0
        return result
    end

    Runtime.Errors[name] = result
    Runtime.ErrorCount[name] = (Runtime.ErrorCount[name] or 0) + 1

    local now = os.clock()
    if now - (Runtime.LastNotifyError[name] or 0) > 8 then
        Runtime.LastNotifyError[name] = now
        notify(
            name .. " worker error",
            tostring(result):sub(1, 280),
            7
        )
    end

    return nil
end

-- ============================================================
-- Basic helpers
-- ============================================================

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
        local parent = object.Parent
        return parent and parent:IsA("BasePart") and parent or nil
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
    local root = rootPart()
    local target = objectRoot(object)

    if not root or not target then
        return math.huge
    end

    return (root.Position - target.Position).Magnitude
end

local function onScreen(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") or not guiObject.Visible then
        return false
    end

    local screen = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
    if screen and not screen.Enabled then
        return false
    end

    local pos = guiObject.AbsolutePosition
    local size = guiObject.AbsoluteSize
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

    return size.X > 1
        and size.Y > 1
        and pos.X + size.X > 0
        and pos.Y + size.Y > 0
        and pos.X < viewport.X
        and pos.Y < viewport.Y
end

local function mouseEvent(held, x, y)
    if not VirtualInputManager then
        return false
    end

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)

    x = x or viewport.X / 2
    y = y or viewport.Y / 2

    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, held, game, 0)
    end)
end

local function mouseClick(x, y)
    local ok = mouseEvent(true, x, y)
    task.wait(0.025)
    mouseEvent(false, x, y)
    return ok
end

local function keyEvent(key, held)
    if not VirtualInputManager or not key then
        return false
    end

    return pcall(function()
        VirtualInputManager:SendKeyEvent(held, key, false, game)
    end)
end

local function pressKey(key, duration)
    keyEvent(key, true)
    task.wait(duration or 0.035)
    keyEvent(key, false)
end

local function clickGui(button)
    if not button or not button:IsA("GuiButton") or not onScreen(button) then
        return false
    end

    if type(fireSignalFn) == "function" then
        local ok = pcall(fireSignalFn, button.Activated)
        if ok then
            return true
        end
    end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize
    return mouseClick(pos.X + size.X / 2, pos.Y + size.Y / 2)
end

-- ============================================================
-- Runtime index
-- ============================================================

local function entitiesFolder()
    return Workspace:FindFirstChild("Entities")
end

local function dialogueRoot()
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    return important and important:FindFirstChild("DialogueNPCs")
end

local function registerInstance(instance)
    if instance:IsA("ProximityPrompt") then
        Runtime.Prompts[instance] = true
        return
    end

    if instance:IsA("Model") then
        local entities = entitiesFolder()

        if entities and instance.Parent == entities then
            Runtime.Entities[instance] = true
        end

        if instance:GetAttribute("ObjectType") == "Ore"
            or instance:GetAttribute("Ore") ~= nil then
            Runtime.Ores[instance] = true
        end
    end
end

local function unregisterInstance(instance)
    Runtime.Prompts[instance] = nil
    Runtime.Entities[instance] = nil
    Runtime.Ores[instance] = nil
    Runtime.DialogueQuestCache[instance] = nil
end

task.spawn(function()
    local descendants = Workspace:GetDescendants()
    for index, instance in ipairs(descendants) do
        registerInstance(instance)

        if index % 6000 == 0 then
            task.wait()
        end
    end
end)

connect(Workspace.DescendantAdded, registerInstance)
connect(Workspace.DescendantRemoving, unregisterInstance)

-- ============================================================
-- Player / hotbar
-- ============================================================

local function playerLevel()
    return tonumber(LocalPlayer:GetAttribute("Level")) or 0
end

local function playerReady()
    local loaded = LocalPlayer:GetAttribute("Loaded")
    local playerLoaded = LocalPlayer:GetAttribute("PlayerLoaded")

    return rootPart() ~= nil
        and humanoid() ~= nil
        and loaded ~= false
        and playerLoaded ~= false
end

local SLOT_KEYS = {
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
    "rod",
    "map",
    "pouch",
    "shovel",
    "food",
}

local function hotbar()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local backpack = gui and gui:FindFirstChild("Backpack")

    if not backpack then
        return nil
    end

    return backpack:FindFirstChild("Hotbar", true)
end

local function hotbarSlots()
    local bar = hotbar()
    local result = {}

    if not bar then
        return result
    end

    for _, slot in ipairs(bar:GetChildren()) do
        local key = SLOT_KEYS[slot.Name]
        local toolFrame = slot:FindFirstChild("ToolFrame")
        local title = toolFrame and toolFrame:FindFirstChild("Title", true)

        if key and title and title:IsA("TextLabel") then
            local name = normalize(title.Text)

            if name ~= "" then
                table.insert(result, {
                    Slot = slot.Name,
                    Key = key,
                    Name = name,
                    Frame = toolFrame,
                })
            end
        end
    end

    table.sort(result, function(a, b)
        local av = tonumber(a.Slot) or 10
        local bv = tonumber(b.Slot) or 10
        return av < bv
    end)

    return result
end

local function isUtilityTitle(name)
    local value = lower(name)

    for _, word in ipairs(UTILITY_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    return false
end

local function weaponOptions()
    local result = {"Auto"}

    for _, data in ipairs(hotbarSlots()) do
        if not isUtilityTitle(data.Name) then
            table.insert(result, data.Name)
        end
    end

    return result
end

local function selectedWeaponSlot()
    local slots = hotbarSlots()

    if Config.Weapon ~= "Auto" then
        for _, data in ipairs(slots) do
            if data.Name == Config.Weapon then
                return data
            end
        end
    end

    local priorities = {
        "slash",
        "sword",
        "punch",
        "cannon",
        "gunshot",
        "gun",
        "claw",
        "kick",
    }

    local best
    local bestScore = -math.huge

    for _, data in ipairs(slots) do
        if not isUtilityTitle(data.Name) then
            local value = lower(data.Name)
            local score = 10

            for i, word in ipairs(priorities) do
                if value:find(word, 1, true) then
                    score = 100 - i
                    break
                end
            end

            if score > bestScore then
                bestScore = score
                best = data
            end
        end
    end

    return best
end

local function pickaxeSlot()
    for _, data in ipairs(hotbarSlots()) do
        if lower(data.Name):find("pickaxe", 1, true) then
            return data
        end
    end
    return nil
end

local function rodSlot()
    for _, data in ipairs(hotbarSlots()) do
        if lower(data.Name):find("rod", 1, true) then
            return data
        end
    end
    return nil
end

-- ============================================================
-- Quest
-- ============================================================

local function questScrolling()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local quests = gui and gui:FindFirstChild("Quests")
    local quest = quests and quests:FindFirstChild("Quest")

    return quest and quest:FindFirstChild("ScrollingFrame")
end

local function questStorage()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local quests = gui and gui:FindFirstChild("Quests")
    local quest = quests and quests:FindFirstChild("Quest")
    local localScript = quest and quest:FindFirstChild("QuestLocal")

    return localScript and localScript:FindFirstChild("Storage")
end

local function taskInfoText(frame)
    local info = frame:FindFirstChild("Info1", true)
    if info and (info:IsA("TextLabel") or info:IsA("TextButton")) then
        return tostring(info.Text)
    end
    return ""
end

local function taskDone(frame, rawText)
    if rawText:find("<s>", 1, true) then
        return true
    end

    local checkbox = frame:FindFirstChild("Checkbox")
    if checkbox and checkbox:IsA("GuiObject") and checkbox.Visible then
        return true
    end

    local current, required = rawText:match("%((%d+)%s*/%s*(%d+)%)")
    return current ~= nil
        and required ~= nil
        and tonumber(current) >= tonumber(required)
end

local function parseTask(rawText)
    local clean = normalize(rawText)
    clean = clean:gsub("%s*%(%d+%s*/%s*%d+%)%.?$", "")
    clean = normalize(clean)

    local patterns = {
        {"Defeat", "^Defeat%s+(.+)$"},
        {"Defeat", "^Kill%s+(.+)$"},
        {"Talk", "^Talk%s+[Tt]o%s+(.+)$"},
        {"Talk", "^Speak%s+[Tt]o%s+(.+)$"},
        {"Collect", "^Collect%s+(.+)$"},
        {"Collect", "^Gather%s+(.+)$"},
        {"Mine", "^Mine%s+(.+)$"},
        {"Fish", "^Catch%s+(.+)$"},
        {"Fish", "^Fish%s+(.+)$"},
        {"Return", "^Return%s+[Tt]o%s+(.+)$"},
        {"Find", "^Find%s+(.+)$"},
    }

    for _, data in ipairs(patterns) do
        local target = clean:match(data[2])
        if target then
            return data[1], normalize(target)
        end
    end

    return "Unknown", clean
end

local function activeQuest()
    local scrolling = questScrolling()
    if not scrolling then
        return nil, nil
    end

    local titles = {}

    for _, child in ipairs(scrolling:GetChildren()) do
        if child.Name == "QuestTitle" then
            local id = child:GetAttribute("QuestId")
            if id ~= nil then
                titles[id] = tostring(
                    child:GetAttribute("QuestName")
                    or normalize(taskInfoText(child))
                )
            end
        end
    end

    local firstComplete

    for id, name in pairs(titles) do
        local tasks = {}
        local allDone = true

        for _, child in ipairs(scrolling:GetChildren()) do
            if child.Name == "Task" and child:GetAttribute("QuestId") == id then
                local raw = taskInfoText(child)
                local done = taskDone(child, raw)
                local kind, target = parseTask(raw)

                table.insert(tasks, {
                    Frame = child,
                    Text = normalize(raw),
                    Done = done,
                    Kind = kind,
                    Target = target,
                    Order = child.LayoutOrder,
                })

                if not done then
                    allDone = false
                end
            end
        end

        table.sort(tasks, function(a, b)
            return a.Order < b.Order
        end)

        if allDone and #tasks > 0 then
            firstComplete = {
                Id = id,
                Name = name,
                Tasks = tasks,
                Complete = true,
            }
        else
            for _, taskData in ipairs(tasks) do
                if not taskData.Done then
                    return {
                        Id = id,
                        Name = name,
                        Tasks = tasks,
                        Complete = false,
                    }, taskData
                end
            end
        end
    end

    return firstComplete, nil
end

local function recommendedQuest()
    local storage = questStorage()
    local object = storage and storage:FindFirstChild("RecommendedQuest")
    if not object then
        return nil
    end

    local info = object:FindFirstChild("Info1", true)
    local text = info and normalize(info.Text) or ""
    local name = text:match("[Rr]ecommended:%s*(.+)$")

    if not name or name == "" then
        return nil
    end

    return {
        Id = object:GetAttribute("QuestId"),
        Name = normalize(name),
    }
end

-- ============================================================
-- Target / dialogue resolution
-- ============================================================

local function isPlayerEntity(model)
    return model:GetAttribute("PlayerCharacter") == true
        or Players:FindFirstChild(model.Name) ~= nil
end

local function aliveMob(model)
    if not model or not model.Parent or not model:IsA("Model") or isPlayerEntity(model) then
        return false
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then
        return false
    end

    return objectRoot(model) ~= nil
end

local function mobMatches(model, wanted)
    if not aliveMob(model) then
        return false
    end

    wanted = lower(wanted)
    if wanted == "" then
        return false
    end

    local values = {
        model.Name,
        model:GetAttribute("NPCName"),
        model:GetAttribute("NPCType"),
        model:GetAttribute("OriginalName"),
    }

    for _, value in ipairs(values) do
        if value then
            local candidate = lower(value)
            if candidate == wanted
                or candidate:find(wanted, 1, true)
                or wanted:find(candidate, 1, true) then
                return true
            end
        end
    end

    return false
end

local function nearestMob(wanted)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if mobMatches(model, wanted) then
            local distance = distanceTo(model)
            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

local function dialogueQuestNames(model)
    local cached = Runtime.DialogueQuestCache[model]
    if cached then
        return cached
    end

    local names = {}

    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("StringValue")
            and object.Name == "QuestName"
            and object.Value ~= "" then
            names[normalize(object.Value)] = true
        end

        local node = object:GetAttribute("QuestNode")
        if type(node) == "string" and node ~= "" then
            names[normalize(node)] = true
        end

        if object:IsA("TextLabel") and object.Name == "QuestLabel" then
            local value = normalize(object.Text)
            if value ~= "" then
                names[value] = true
            end
        end
    end

    Runtime.DialogueQuestCache[model] = names
    return names
end

local function findDialogueNpc(questName, preferredName)
    local root = dialogueRoot()
    if not root then
        return nil
    end

    local wantedQuest = lower(questName)
    local wantedNpc = lower(preferredName)

    local best
    local bestScore = -math.huge

    for _, object in ipairs(root:GetDescendants()) do
        if object:IsA("Model") then
            local score = 0
            local nameBlob = lower(
                object.Name
                .. " "
                .. tostring(object:GetAttribute("NPCName") or "")
                .. " "
                .. tostring(object:GetAttribute("NPCType") or "")
            )

            if wantedNpc ~= "" and nameBlob:find(wantedNpc, 1, true) then
                score = score + 100
            end

            if wantedQuest ~= "" then
                for name in pairs(dialogueQuestNames(object)) do
                    if lower(name) == wantedQuest then
                        score = score + 90
                    end
                end
            end

            if score > 0 then
                score = score - math.min(distanceTo(object), 5000) * 0.002
                if score > bestScore then
                    best = object
                    bestScore = score
                end
            end
        end
    end

    return best
end

local function promptNear(object, dialogueOnly)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local value = lower(prompt.Name)
            local allowed = not dialogueOnly or value:find("dialogue", 1, true)

            if allowed then
                local part = objectRoot(prompt)
                if part then
                    local distance = (part.Position - target.Position).Magnitude
                    if distance <= 30 and (not bestDistance or distance < bestDistance) then
                        best = prompt
                        bestDistance = distance
                    end
                end
            end
        end
    end

    return best
end

local function firePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    if type(firePromptFn) == "function" then
        local ok = pcall(
            firePromptFn,
            prompt,
            math.max(0, tonumber(prompt.HoldDuration) or 0)
        )
        if ok then
            return true
        end
    end

    local key = prompt.KeyboardKeyCode
    if key and key ~= Enum.KeyCode.Unknown then
        pressKey(key, math.max(0.06, prompt.HoldDuration + 0.04))
        return true
    end

    return false
end

local DIALOGUE_WORDS = {
    "accept",
    "quest",
    "continue",
    "yes",
    "next",
    "complete",
    "finish",
    "training",
    "help",
}

local function dialogueButton()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local dialogue = gui and gui:FindFirstChild("DialogueUI")
    if not dialogue then
        return nil
    end

    local best
    local bestScore = -1

    for _, object in ipairs(dialogue:GetDescendants()) do
        if object:IsA("GuiButton") and onScreen(object) then
            local blob = lower(object.Name)

            for _, descendant in ipairs(object:GetDescendants()) do
                if descendant:IsA("TextLabel") then
                    blob = blob .. " " .. lower(descendant.Text)
                end
            end

            local score = 1
            for i, word in ipairs(DIALOGUE_WORDS) do
                if blob:find(word, 1, true) then
                    score = score + (50 - i)
                end
            end

            if score > bestScore then
                best = object
                bestScore = score
            end
        end
    end

    return best
end

-- ============================================================
-- Moving platform
-- ============================================================

local function destroyWeld()
    if Runtime.PlatformWeld then
        pcall(function()
            Runtime.PlatformWeld:Destroy()
        end)
        Runtime.PlatformWeld = nil
    end
end

local function platformPart()
    if Runtime.Platform and Runtime.Platform.Parent then
        return Runtime.Platform
    end

    local part = Instance.new("Part")
    part.Name = "SON_Platform"
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = false
    part.CanQuery = false
    part.Transparency = 0.45
    part.Size = Vector3.new(8, 1, 8)
    part.Material = Enum.Material.SmoothPlastic
    part.Parent = Workspace

    Runtime.Platform = part
    return part
end

local function cancelPlatform(remove)
    if Runtime.PlatformTween then
        pcall(function()
            Runtime.PlatformTween:Cancel()
        end)
        Runtime.PlatformTween = nil
    end

    destroyWeld()

    local hum = humanoid()
    if hum and Runtime.OldAutoRotate ~= nil then
        hum.AutoRotate = Runtime.OldAutoRotate
        Runtime.OldAutoRotate = nil
    end

    if remove and Runtime.Platform then
        pcall(function()
            Runtime.Platform:Destroy()
        end)
        Runtime.Platform = nil
    end
end

local function movePlatformTo(object, height, back)
    local root = rootPart()
    local target = objectRoot(object)

    if not root or not target then
        return false
    end

    height = height or 3
    back = back or 0

    local goalPosition = (
        target.CFrame
        * CFrame.new(0, height - 3, back)
    ).Position

    local playerGoal = CFrame.lookAt(
        goalPosition,
        target.Position
    )

    local platformGoal = playerGoal * CFrame.new(0, -3.4, 0)
    local distance = (root.Position - goalPosition).Magnitude

    if distance <= Config.ArrivalDistance then
        return true
    end

    local platform = platformPart()

    if not Runtime.PlatformWeld then
        platform.CFrame = root.CFrame * CFrame.new(0, -3.4, 0)

        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        local hum = humanoid()
        if hum and Runtime.OldAutoRotate == nil then
            Runtime.OldAutoRotate = hum.AutoRotate
            hum.AutoRotate = false
        end

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = platform
        weld.Part1 = root
        weld.Parent = platform
        Runtime.PlatformWeld = weld
    end

    if Runtime.PlatformTween then
        return false
    end

    local duration = math.clamp(
        distance / math.max(50, Config.PlatformSpeed),
        0.12,
        10
    )

    local tween = TweenService:Create(
        platform,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        {CFrame = platformGoal}
    )

    Runtime.PlatformTween = tween

    tween.Completed:Connect(function()
        if Runtime.PlatformTween == tween then
            Runtime.PlatformTween = nil
            destroyWeld()

            local hum = humanoid()
            if hum and Runtime.OldAutoRotate ~= nil then
                hum.AutoRotate = Runtime.OldAutoRotate
                Runtime.OldAutoRotate = nil
            end
        end
    end)

    tween:Play()
    return false
end

-- ============================================================
-- Farm / bring / hitbox / attack
-- ============================================================

local HitboxBackup = setmetatable({}, {__mode = "k"})

local function restoreHitboxes()
    for model, data in pairs(HitboxBackup) do
        local part = data.Part
        if part and part.Parent then
            pcall(function()
                part.Size = data.Size
                part.Transparency = data.Transparency
                part.CanCollide = data.CanCollide
            end)
        end
        HitboxBackup[model] = nil
    end
end

local function applyHitbox(wanted)
    if not Config.MobHitbox then
        restoreHitboxes()
        return
    end

    local keep = {}

    for model in pairs(Runtime.Entities) do
        if mobMatches(model, wanted) then
            keep[model] = true

            local part = objectRoot(model)
            if part then
                if not HitboxBackup[model] then
                    HitboxBackup[model] = {
                        Part = part,
                        Size = part.Size,
                        Transparency = part.Transparency,
                        CanCollide = part.CanCollide,
                    }
                end

                pcall(function()
                    part.Size = Vector3.new(
                        Config.HitboxSize,
                        Config.HitboxSize,
                        Config.HitboxSize
                    )
                    part.Transparency = 0.55
                    part.CanCollide = false
                end)
            end
        end
    end

    for model in pairs(HitboxBackup) do
        if not keep[model] then
            local data = HitboxBackup[model]
            if data.Part and data.Part.Parent then
                pcall(function()
                    data.Part.Size = data.Size
                    data.Part.Transparency = data.Transparency
                    data.Part.CanCollide = data.CanCollide
                end)
            end
            HitboxBackup[model] = nil
        end
    end
end

local function bringMobs(wanted)
    if not Config.BringMobs or not Runtime.FarmAnchor then
        return
    end

    if os.clock() - Runtime.LastBring < 0.3 then
        return
    end
    Runtime.LastBring = os.clock()

    local count = 0

    for model in pairs(Runtime.Entities) do
        if count >= Config.BringLimit then
            break
        end

        if mobMatches(model, wanted) then
            local part = objectRoot(model)

            if part
                and not part.Anchored
                and (part.Position - Runtime.FarmAnchor.Position).Magnitude <= Config.BringRadius then

                count = count + 1

                local column = (count - 1) % 3
                local row = math.floor((count - 1) / 3)

                local offset = CFrame.new(
                    (column - 1) * 1.5,
                    -Config.FarmHeight + 3,
                    -Config.BringDistance - row * 1.5
                )

                pcall(function()
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                    part.CFrame = Runtime.FarmAnchor * offset
                end)
            end
        end
    end
end

local function equipWeapon()
    local slot = selectedWeaponSlot()
    if slot then
        pressKey(slot.Key)
    end
    return slot
end

local function attack()
    if not Config.AutoAttack then
        return
    end

    local delay = 1 / math.max(1, Config.AttackRate)
    if os.clock() - Runtime.LastAttack < delay then
        return
    end

    Runtime.LastAttack = os.clock()
    equipWeapon()
    mouseClick()

    if Config.AutoMastery then
        for _, data in ipairs(hotbarSlots()) do
            if not isUtilityTitle(data.Name) then
                local cooldown = data.Frame and data.Frame:FindFirstChild("Cooldown", true)
                local ready = not cooldown
                    or not cooldown:IsA("GuiObject")
                    or not cooldown.Visible

                if ready then
                    pressKey(data.Key)
                    break
                end
            end
        end
    end
end

local function farmMob(wanted)
    local target = Runtime.CurrentTarget

    if not target
        or not target.Parent
        or not mobMatches(target, wanted) then
        target = nearestMob(wanted)
        Runtime.CurrentTarget = target
    end

    if not target then
        setState("SEARCHING MOB", wanted)
        return
    end

    local targetRoot = objectRoot(target)
    if not targetRoot then
        return
    end

    if not Runtime.FarmAnchor then
        Runtime.FarmAnchor = targetRoot.CFrame * CFrame.new(0, Config.FarmHeight, 0)
    end

    local root = rootPart()
    if not root then
        return
    end

    if (root.Position - Runtime.FarmAnchor.Position).Magnitude > Config.ArrivalDistance then
        movePlatformTo(target, Config.FarmHeight, 0)
        setState("MOVING TO FARM", wanted)
        return
    end

    cancelPlatform(false)

    bringMobs(wanted)

    if os.clock() - Runtime.LastHitbox > 0.4 then
        Runtime.LastHitbox = os.clock()
        applyHitbox(wanted)
    end

    attack()
    setState("FARMING", wanted)
end

local function clearFarm()
    Runtime.CurrentTarget = nil
    Runtime.WantedMob = nil
    Runtime.FarmAnchor = nil
    restoreHitboxes()
end

-- ============================================================
-- Quest interaction / progression
-- ============================================================

local function interactNpc(questName, npcName, stateName)
    clearFarm()

    local npc = findDialogueNpc(questName, npcName)
    if not npc then
        setState("SEARCHING NPC", npcName ~= "" and npcName or questName)
        return false
    end

    if distanceTo(npc) > 10 then
        movePlatformTo(npc, 3.5, 3)
        setState("MOVING TO NPC", npc.Name)
        return false
    end

    cancelPlatform(false)

    local prompt = promptNear(npc, true)
    if prompt then
        firePrompt(prompt)
        task.wait(0.12)
    end

    local button = dialogueButton()
    if button then
        clickGui(button)
    end

    setState(stateName, questName)
    return true
end

local function promptByText(target)
    local wanted = lower(target)
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local model = prompt:FindFirstAncestorWhichIsA("Model")
            local blob = lower(
                prompt.Name
                .. " "
                .. tostring(prompt.ActionText or "")
                .. " "
                .. tostring(prompt.ObjectText or "")
                .. " "
                .. tostring(model and model.Name or "")
            )

            if blob:find(wanted, 1, true) then
                local distance = distanceTo(prompt)
                if not bestDistance or distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

local function collectTarget(target)
    clearFarm()

    local prompt = promptByText(target)
    if not prompt then
        setState("SEARCHING ITEM", target)
        return
    end

    if distanceTo(prompt) > Config.ArrivalDistance then
        movePlatformTo(prompt, 3, 2)
        setState("MOVING TO ITEM", target)
        return
    end

    cancelPlatform(false)
    firePrompt(prompt)
    setState("COLLECTING", target)
end

local function progressionStep()
    Runtime.Workers.Progress = Runtime.Workers.Progress + 1

    if not Config.AutoProgress then
        clearFarm()
        cancelPlatform(false)
        setState("IDLE", "Auto Progress off")
        return
    end

    if not playerReady() then
        setState("WAIT PLAYER", "Character/data not ready")
        return
    end

    local quest, taskData = activeQuest()

    if quest and quest.Complete then
        interactNpc(quest.Name, "", "TURN IN")
        return
    end

    if quest and taskData then
        if taskData.Kind == "Defeat" then
            Runtime.WantedMob = taskData.Target
            farmMob(taskData.Target)
            return
        elseif taskData.Kind == "Talk"
            or taskData.Kind == "Return" then
            interactNpc(
                quest.Name,
                taskData.Target,
                "QUEST DIALOGUE"
            )
            return
        elseif taskData.Kind == "Collect"
            or taskData.Kind == "Find" then
            collectTarget(taskData.Target)
            return
        elseif taskData.Kind == "Mine" then
            clearFarm()
            Runtime.MiningState = "QUEST"
            Config.AutoMining = true
            setState("QUEST MINING", taskData.Target)
            return
        elseif taskData.Kind == "Fish" then
            clearFarm()
            setState("QUEST FISHING", taskData.Target)
            return
        end

        setState("UNSUPPORTED TASK", taskData.Text)
        return
    end

    local recommended = recommendedQuest()

    if Config.AutoQuest and recommended then
        interactNpc(recommended.Name, "", "ACCEPT QUEST")
        return
    end

    setState(
        "WAIT QUEST",
        "Lv." .. tostring(playerLevel()) .. " / no active recommendation"
    )
end

-- ============================================================
-- Auto stats
-- ============================================================

local function statPointCount()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local menu = gui and gui:FindFirstChild("Menu")
    local text = menu and menu:FindFirstChild("StatpointText", true)

    if text and text:IsA("TextLabel") then
        return tonumber(text.Text:match("(%d+)")) or 0
    end

    return 0
end

local function preferredStat()
    if Config.StatsMode ~= "Auto Weapon" then
        return Config.StatsMode
    end

    local slot = selectedWeaponSlot()
    local name = lower(slot and slot.Name or "")

    if name:find("gun", 1, true)
        or name:find("cannon", 1, true)
        or name:find("shot", 1, true) then
        return "Precision"
    end

    return "Strength"
end

local function spendStat()
    Runtime.Workers.Stats = Runtime.Workers.Stats + 1

    if not Config.AutoStats or os.clock() - Runtime.LastStat < 0.25 then
        return
    end

    if statPointCount() <= 0 then
        return
    end

    Runtime.LastStat = os.clock()

    local wanted = preferredStat()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local menu = gui and gui:FindFirstChild("Menu")
    local radar = menu and menu:FindFirstChild("Radar", true)
    local stat = radar and radar:FindFirstChild(wanted, true)

    if not stat then
        return
    end

    local button = stat:IsA("GuiButton")
        and stat
        or stat:FindFirstChildWhichIsA("GuiButton", true)

    if button then
        clickGui(button)
    end
end

-- ============================================================
-- Loot prompts
-- ============================================================

local function promptKind(prompt)
    local name = lower(prompt.Name)

    if name:find("world boss chest", 1, true) then
        return "WorldBossChest"
    elseif name:find("fruit chest", 1, true) then
        return "FruitChest"
    elseif name:find("chest", 1, true) then
        return "Chest"
    elseif name == "pickup"
        or name == "money bag"
        or name == "grab" then
        return "Pickup"
    end

    return nil
end

local function lootEnabled(kind)
    return kind == "Pickup" and Config.AutoPickup
        or kind == "Chest" and Config.AutoChest
        or kind == "WorldBossChest" and Config.AutoWorldBossChest
        or kind == "FruitChest" and Config.AutoFruitChest
end

local function lootStep()
    Runtime.Workers.Loot = Runtime.Workers.Loot + 1

    if Config.AutoProgress and Runtime.State:find("MOVING", 1, true) then
        return
    end

    local best
    local bestDistance = 15

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local kind = promptKind(prompt)

            if kind and lootEnabled(kind) then
                local distance = distanceTo(prompt)
                if distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    if best then
        firePrompt(best)
    end
end

-- ============================================================
-- Fishing
-- ============================================================

local function fishingGui()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return gui and gui:FindFirstChild("Fishing")
end

local function qteRoot()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local qte = gui and gui:FindFirstChild("QuickTimeEvents")
    local client = qte and qte:FindFirstChild("QTEClient")

    return client and client:FindFirstChild("Events")
end

local function setFishingHold(value)
    if Runtime.FishingHold == value then
        return
    end

    Runtime.FishingHold = value
    mouseEvent(value)
end

local function findVisibleTextButton(text)
    local root = qteRoot()
    if not root then
        return nil
    end

    local wanted = lower(text)

    for _, object in ipairs(root:GetDescendants()) do
        if object:IsA("GuiButton") and onScreen(object) then
            local blob = lower(object.Name)

            for _, child in ipairs(object:GetDescendants()) do
                if child:IsA("TextLabel") then
                    blob = blob .. " " .. lower(child.Text)
                end
            end

            if blob:find(wanted, 1, true) then
                return object
            end
        end
    end

    return nil
end

local function reelActive()
    local gui = fishingGui()
    if not gui then
        return false, nil
    end

    local main = gui:FindFirstChild("Main")
    return main ~= nil and main.Visible, main
end

local function fishingStep()
    Runtime.Workers.Fishing = Runtime.Workers.Fishing + 1

    if not Config.AutoFishing then
        setFishingHold(false)
        Runtime.FishingState = "IDLE"
        return 0.7
    end

    if Config.AutoProgress and Runtime.State:find("FARMING", 1, true) then
        return 0.5
    end

    local root = rootPart()
    if not root then
        return 0.7
    end

    if not Config.FishingSpot then
        Runtime.FishingState = "MISSING SPOT"
        return 0.7
    end

    if (root.Position - Config.FishingSpot.Position).Magnitude > Config.ArrivalDistance then
        local fake = Instance.new("Part")
        fake.Anchored = true
        fake.Transparency = 1
        fake.CanCollide = false
        fake.CFrame = Config.FishingSpot
        fake.Parent = Workspace

        movePlatformTo(fake, 3, 0)
        fake:Destroy()

        Runtime.FishingState = "MOVE TO SPOT"
        return 0.25
    end

    local shake = findVisibleTextButton("shake")
    if shake then
        clickGui(shake)
        Runtime.FishingState = "SHAKE"
        return 0.05
    end

    local clickButton = findVisibleTextButton("click")
    if clickButton then
        clickGui(clickButton)
        Runtime.FishingState = "CLICK QTE"
        return 0.05
    end

    local active, main = reelActive()
    if active and main then
        local move = main:FindFirstChild("Move")
        local fish = main:FindFirstChild("Fish")

        if move and fish
            and move:IsA("GuiObject")
            and fish:IsA("GuiObject") then

            local moveCenter =
                move.AbsolutePosition.X
                + move.AbsoluteSize.X / 2

            local fishCenter =
                fish.AbsolutePosition.X
                + fish.AbsoluteSize.X / 2

            if not Runtime.FishingCalibrated then
                local before = moveCenter
                setFishingHold(true)
                task.wait(0.07)

                local after =
                    move.AbsolutePosition.X
                    + move.AbsoluteSize.X / 2

                if math.abs(after - before) > 0.5 then
                    Runtime.FishingHoldDirection =
                        after > before and 1 or -1
                end

                Runtime.FishingCalibrated = true
                setFishingHold(false)
                return 0.04
            end

            local wantedDirection =
                fishCenter > moveCenter and 1 or -1

            local inside =
                fish.AbsolutePosition.X
                    >= move.AbsolutePosition.X + Config.FishingTolerance
                and fish.AbsolutePosition.X + fish.AbsoluteSize.X
                    <= move.AbsolutePosition.X + move.AbsoluteSize.X
                        - Config.FishingTolerance

            if inside then
                wantedDirection =
                    fishCenter > moveCenter and 1 or -1
            end

            setFishingHold(
                wantedDirection == Runtime.FishingHoldDirection
            )

            Runtime.FishingState = "REEL"
            return 0.035
        end
    end

    setFishingHold(false)

    local rod = rodSlot()
    if not rod then
        Runtime.FishingState = "MISSING ROD"
        return 0.8
    end

    if os.clock() - Runtime.FishingCastAt > 3 then
        pressKey(rod.Key)
        task.wait(0.08)
        mouseClick()

        Runtime.FishingCastAt = os.clock()
        Runtime.FishingCalibrated = false
        Runtime.FishingState = "CAST"
    else
        Runtime.FishingState = "WAIT BITE"
    end

    return 0.25
end

-- ============================================================
-- Mining
-- ============================================================

local ORE_NAMES = {
    "Copper Ore",
    "Iron Ore",
    "Silver Ore",
    "Gold Ore",
    "Diamond Ore",
}

local function oreName(model)
    return tostring(
        model:GetAttribute("Ore")
        or model:GetAttribute("Name")
        or model.Name
    )
end

local function oreAvailable(model)
    return model
        and model.Parent
        and objectRoot(model) ~= nil
        and model:GetAttribute("Mined") ~= true
        and (
            model:GetAttribute("ObjectType") == "Ore"
            or model:GetAttribute("Ore") ~= nil
        )
end

local function wantedOre()
    if Config.MiningMode == "Selected Ore" then
        return Config.SelectedOre
    end

    if Config.MiningMode == "Quest Required" then
        local _, taskData = activeQuest()
        if taskData and taskData.Kind == "Mine" then
            local value = lower(taskData.Target)

            for _, name in ipairs(ORE_NAMES) do
                if lower(name):find(value, 1, true)
                    or value:find(lower(name), 1, true) then
                    return name
                end
            end
        end

        return Config.SelectedOre
    end

    return nil
end

local function findOre()
    local wanted = wantedOre()
    local best
    local bestDistance
    local bestDrop = -math.huge

    for model in pairs(Runtime.Ores) do
        if oreAvailable(model) then
            local name = oreName(model)
            local accepted =
                Config.MiningMode == "Any Available"
                or Config.MiningMode == "Highest Drop"
                or wanted == nil
                or lower(name) == lower(wanted)

            if accepted then
                local distance = distanceTo(model)
                local drop = tonumber(model:GetAttribute("DropAmount")) or 0

                if Config.MiningMode == "Highest Drop" then
                    if drop > bestDrop
                        or (
                            drop == bestDrop
                            and (
                                not bestDistance
                                or distance < bestDistance
                            )
                        ) then
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

local function miningQte()
    local root = qteRoot()
    if not root then
        return nil
    end

    for _, object in ipairs(root:GetDescendants()) do
        if object.Name == "Critical Zone" and object:IsA("GuiObject") then
            local frame = object.Parent
            local amount = frame and frame:FindFirstChild("Amount")

            if amount and amount:IsA("GuiObject") and onScreen(amount) then
                return object, amount
            end
        end
    end

    return nil
end

local function miningMouse(value)
    if Runtime.MiningHold == value then
        return
    end

    Runtime.MiningHold = value
    mouseEvent(value)
end

local function miningStep()
    Runtime.Workers.Mining = Runtime.Workers.Mining + 1

    if not Config.AutoMining then
        miningMouse(false)
        Runtime.MiningState = "IDLE"
        Runtime.MiningTarget = nil
        return 0.7
    end

    local ore = Runtime.MiningTarget

    if not oreAvailable(ore) then
        ore = findOre()
        Runtime.MiningTarget = ore
    end

    if not ore then
        miningMouse(false)
        Runtime.MiningState = "NO ORE"
        return 0.7
    end

    if distanceTo(ore) > 8 then
        miningMouse(false)
        movePlatformTo(ore, 3.5, 4)
        Runtime.MiningState = "MOVE"
        return 0.2
    end

    cancelPlatform(false)

    local pickaxe = pickaxeSlot()
    if not pickaxe then
        miningMouse(false)
        Runtime.MiningState = "MISSING PICKAXE"
        return 0.7
    end

    pressKey(pickaxe.Key)

    local critical, amount = miningQte()
    if critical and amount then
        local amountTop = 1 - math.clamp(amount.Size.Y.Scale, 0, 1)
        local targetTop = critical.Position.Y.Scale
        local targetBottom = targetTop + critical.Size.Y.Scale

        if amountTop >= targetTop - 0.025
            and amountTop <= targetBottom + 0.025 then
            miningMouse(false)
            Runtime.MiningState = "RELEASE"
        else
            miningMouse(true)
            Runtime.MiningState = "CHARGE"
        end

        return 0.035
    end

    miningMouse(true)
    Runtime.MiningState = "HOLD"
    return 0.06
end

-- ============================================================
-- Block
-- ============================================================

local blockHeld = false

local function blockStep()
    Runtime.Workers.Block = Runtime.Workers.Block + 1

    local hum = humanoid()
    local shouldHold = false

    if Config.AutoBlock and hum and hum.MaxHealth > 0 then
        local percent = hum.Health / hum.MaxHealth * 100
        shouldHold =
            percent <= Config.BlockBelow
            and Runtime.CurrentTarget ~= nil
            and distanceTo(Runtime.CurrentTarget) < 22
    end

    if shouldHold ~= blockHeld then
        blockHeld = shouldHold
        keyEvent(Enum.KeyCode.F, blockHeld)
    end
end

-- ============================================================
-- Self test
-- ============================================================

local function selfTest()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")

    local checks = {
        {"Fluent", Fluent ~= nil},
        {"loadstring", type(loadstring) == "function"},
        {"HTTP", type(game.HttpGet) == "function" or type(requestFn) == "function"},
        {"VirtualInputManager", VirtualInputManager ~= nil},
        {"fireproximityprompt/fallback", firePromptFn ~= nil or VirtualInputManager ~= nil},
        {"PlayerGui", gui ~= nil},
        {"Quest UI", questScrolling() ~= nil},
        {"Workspace.Entities", entitiesFolder() ~= nil},
        {"DialogueNPCs", dialogueRoot() ~= nil},
        {"Hotbar", hotbar() ~= nil},
    }

    local rows = {}

    for _, check in ipairs(checks) do
        table.insert(
            rows,
            (check[2] and "[OK] " or "[--] ") .. check[1]
        )
    end

    return table.concat(rows, "\n")
end

local function workerHealth()
    local rows = {
        "State: " .. tostring(Runtime.State),
        "Detail: " .. tostring(Runtime.Detail),
        "",
        "Progress ticks: " .. Runtime.Workers.Progress,
        "Fishing ticks: " .. Runtime.Workers.Fishing,
        "Mining ticks: " .. Runtime.Workers.Mining,
        "Loot ticks: " .. Runtime.Workers.Loot,
        "Stats ticks: " .. Runtime.Workers.Stats,
        "Block ticks: " .. Runtime.Workers.Block,
    }

    local hasError = false

    for name, err in pairs(Runtime.Errors) do
        if err then
            hasError = true
            table.insert(rows, "")
            table.insert(
                rows,
                "ERROR " .. name .. ": " .. tostring(err):sub(1, 180)
            )
        end
    end

    if not hasError then
        table.insert(rows, "")
        table.insert(rows, "No worker errors recorded.")
    end

    return table.concat(rows, "\n")
end

-- ============================================================
-- Schedulers
-- ============================================================

task.spawn(function()
    while Runtime.Running do
        safeWorker("Progress", progressionStep)
        task.wait(Config.AutoProgress and 0.12 or 0.65)
    end
end)

task.spawn(function()
    while Runtime.Running do
        local delay = safeWorker("Fishing", fishingStep)
        task.wait(tonumber(delay) or 0.6)
    end
end)

task.spawn(function()
    while Runtime.Running do
        local delay = safeWorker("Mining", miningStep)
        task.wait(tonumber(delay) or 0.6)
    end
end)

task.spawn(function()
    while Runtime.Running do
        safeWorker("Loot", lootStep)
        task.wait(
            (
                Config.AutoPickup
                or Config.AutoChest
                or Config.AutoWorldBossChest
                or Config.AutoFruitChest
            )
            and 0.35
            or 1
        )
    end
end)

task.spawn(function()
    while Runtime.Running do
        safeWorker("Stats", spendStat)
        task.wait(Config.AutoStats and 0.25 or 1)
    end
end)

task.spawn(function()
    while Runtime.Running do
        safeWorker("Block", blockStep)
        task.wait(Config.AutoBlock and 0.12 or 0.8)
    end
end)

-- ============================================================
-- Fluent UI
-- ============================================================

local Window = Fluent:CreateWindow({
    Title = "SON HUB " .. VERSION,
    SubTitle = "Nexomia Safe | make by hongson",
    TabWidth = 155,
    Size = UDim2.fromOffset(690, 500),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Home = Window:AddTab({Title = "Trang Chu", Icon = "home"}),
    Farm = Window:AddTab({Title = "Farm", Icon = "target"}),
    Combat = Window:AddTab({Title = "Combat", Icon = "shield"}),
    Movement = Window:AddTab({Title = "Movement", Icon = "move"}),
    Player = Window:AddTab({Title = "Player", Icon = "user"}),
    Quest = Window:AddTab({Title = "Quest", Icon = "scroll"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"}),
    Info = Window:AddTab({Title = "Info", Icon = "info"}),
}

local HomeMain = Tabs.Home:AddSection("Main Automation")

local AutoProgressToggle = HomeMain:AddToggle("AutoProgress", {
    Title = "AUTO FARM / PROGRESS",
    Description = "Quest -> platform -> correct mobs -> bring -> mob hitbox -> attack -> turn-in.",
    Default = false,
})

AutoProgressToggle:OnChanged(function()
    Config.AutoProgress = AutoProgressToggle.Value

    if not Config.AutoProgress then
        clearFarm()
        cancelPlatform(false)
    end
end)

HomeMain:AddButton({
    Title = "Run Self Test",
    Description = "Checks the exact client structures needed by SON HUB.",
    Callback = function()
        notify("SON HUB Self Test", selfTest(), 10)
    end,
})

HomeMain:AddButton({
    Title = "Worker Health",
    Description = "Shows tick counters and the last caught worker error.",
    Callback = function()
        notify("Worker Health", workerHealth(), 12)
    end,
})

local FarmMain = Tabs.Farm:AddSection("Auto Farm")

local weaponValues = weaponOptions()

local WeaponDropdown = FarmMain:AddDropdown("Weapon", {
    Title = "Weapon",
    Values = weaponValues,
    Multi = false,
    Default = 1,
})

WeaponDropdown:OnChanged(function(value)
    Config.Weapon = value
end)

local AttackToggle = FarmMain:AddToggle("AutoAttack", {
    Title = "Auto Attack",
    Default = true,
})
AttackToggle:OnChanged(function()
    Config.AutoAttack = AttackToggle.Value
end)

local MasteryToggle = FarmMain:AddToggle("AutoMastery", {
    Title = "Auto Mastery Skills",
    Description = "Uses ready combat hotbar slots while farming.",
    Default = true,
})
MasteryToggle:OnChanged(function()
    Config.AutoMastery = MasteryToggle.Value
end)

FarmMain:AddSlider("AttackRate", {
    Title = "Attacks / Second",
    Default = Config.AttackRate,
    Min = 2,
    Max = 15,
    Rounding = 0,
    Callback = function(value)
        Config.AttackRate = value
    end,
})

local FarmStack = Tabs.Farm:AddSection("Bring + Mob Hitbox")

local BringToggle = FarmStack:AddToggle("BringMobs", {
    Title = "Bring Quest Mobs",
    Description = "Only matching non-player mobs are moved under the farm platform.",
    Default = true,
})
BringToggle:OnChanged(function()
    Config.BringMobs = BringToggle.Value
end)

FarmStack:AddSlider("BringRadius", {
    Title = "Bring Radius",
    Default = Config.BringRadius,
    Min = 25,
    Max = 180,
    Rounding = 0,
    Callback = function(value)
        Config.BringRadius = value
    end,
})

local HitboxToggle = FarmStack:AddToggle("MobHitbox", {
    Title = "Mob-only Hitbox",
    Description = "Never applies to players/dialogue NPCs.",
    Default = true,
})
HitboxToggle:OnChanged(function()
    Config.MobHitbox = HitboxToggle.Value
    if not Config.MobHitbox then
        restoreHitboxes()
    end
end)

FarmStack:AddSlider("HitboxSize", {
    Title = "Hitbox Size",
    Default = Config.HitboxSize,
    Min = 4,
    Max = 14,
    Rounding = 0,
    Callback = function(value)
        Config.HitboxSize = value
    end,
})

local CombatMain = Tabs.Combat:AddSection("Combat")

local BlockToggle = CombatMain:AddToggle("AutoBlock", {
    Title = "Auto Block (F)",
    Default = false,
})
BlockToggle:OnChanged(function()
    Config.AutoBlock = BlockToggle.Value
end)

CombatMain:AddSlider("BlockBelow", {
    Title = "Block Below HP %",
    Default = Config.BlockBelow,
    Min = 10,
    Max = 70,
    Rounding = 0,
    Callback = function(value)
        Config.BlockBelow = value
    end,
})

local MoveMain = Tabs.Movement:AddSection("Moving Platform")

MoveMain:AddSlider("PlatformSpeed", {
    Title = "Platform Speed",
    Default = Config.PlatformSpeed,
    Min = 60,
    Max = 350,
    Rounding = 0,
    Callback = function(value)
        Config.PlatformSpeed = value
    end,
})

MoveMain:AddSlider("FarmHeight", {
    Title = "Farm Height",
    Description = "Player stands above the quest mobs; mobs are brought below.",
    Default = Config.FarmHeight,
    Min = 10,
    Max = 35,
    Rounding = 0,
    Callback = function(value)
        Config.FarmHeight = value
        Runtime.FarmAnchor = nil
    end,
})

MoveMain:AddButton({
    Title = "Stop Platform",
    Callback = function()
        cancelPlatform(false)
    end,
})

local PlayerStats = Tabs.Player:AddSection("Auto Stats")

local StatsToggle = PlayerStats:AddToggle("AutoStats", {
    Title = "Auto Stats",
    Default = false,
})
StatsToggle:OnChanged(function()
    Config.AutoStats = StatsToggle.Value
end)

local StatsDropdown = PlayerStats:AddDropdown("StatsMode", {
    Title = "Stats Priority",
    Values = {
        "Auto Weapon",
        "Strength",
        "Precision",
        "Health",
        "Energy",
        "Agility",
        "Willpower",
    },
    Multi = false,
    Default = 1,
})
StatsDropdown:OnChanged(function(value)
    Config.StatsMode = value
end)

local PlayerLoot = Tabs.Player:AddSection("Loot")

local function bindToggle(id, title, default, callback)
    local option = PlayerLoot:AddToggle(id, {
        Title = title,
        Default = default,
    })
    option:OnChanged(function()
        callback(option.Value)
    end)
end

bindToggle("AutoPickup", "Auto Pickup", false, function(value)
    Config.AutoPickup = value
end)

bindToggle("AutoChest", "Auto Chest", false, function(value)
    Config.AutoChest = value
end)

bindToggle("AutoWorldBossChest", "Auto World Boss Chest", false, function(value)
    Config.AutoWorldBossChest = value
end)

bindToggle("AutoFruitChest", "Auto Fruit Chest", false, function(value)
    Config.AutoFruitChest = value
end)

local FishingSection = Tabs.Player:AddSection("Fishing")

local FishingToggle = FishingSection:AddToggle("AutoFishing", {
    Title = "Auto Fishing",
    Description = "Save a location where manual fishing works before enabling.",
    Default = false,
})
FishingToggle:OnChanged(function()
    Config.AutoFishing = FishingToggle.Value
end)

FishingSection:AddButton({
    Title = "Save Current Fishing Spot",
    Callback = function()
        local root = rootPart()
        if root then
            Config.FishingSpot = root.CFrame
            notify("Fishing", "Current fishing position saved.", 3)
        end
    end,
})

FishingSection:AddButton({
    Title = "Fishing State",
    Callback = function()
        notify(
            "Fishing",
            "State: " .. Runtime.FishingState
                .. "\nRod: "
                .. tostring(rodSlot() and rodSlot().Name or "None")
                .. "\nSpot: "
                .. tostring(Config.FishingSpot ~= nil),
            7
        )
    end,
})

local MiningSection = Tabs.Player:AddSection("Mining")

local MiningToggle = MiningSection:AddToggle("AutoMining", {
    Title = "Auto Mining",
    Description = "Selects actual Ore models; no Ore ProximityPrompt assumption.",
    Default = false,
})
MiningToggle:OnChanged(function()
    Config.AutoMining = MiningToggle.Value
end)

local MiningModeDropdown = MiningSection:AddDropdown("MiningMode", {
    Title = "Mining Mode",
    Values = {
        "Quest Required",
        "Selected Ore",
        "Any Available",
        "Highest Drop",
    },
    Multi = false,
    Default = 1,
})
MiningModeDropdown:OnChanged(function(value)
    Config.MiningMode = value
    Runtime.MiningTarget = nil
end)

local OreDropdown = MiningSection:AddDropdown("Ore", {
    Title = "Select Ore",
    Values = ORE_NAMES,
    Multi = false,
    Default = 1,
})
OreDropdown:OnChanged(function(value)
    Config.SelectedOre = value
    Runtime.MiningTarget = nil
end)

MiningSection:AddButton({
    Title = "Mining State",
    Callback = function()
        notify(
            "Mining",
            "State: " .. Runtime.MiningState
                .. "\nWanted: " .. tostring(wantedOre() or "Any")
                .. "\nTarget: "
                .. tostring(
                    Runtime.MiningTarget
                    and oreName(Runtime.MiningTarget)
                    or "None"
                ),
            7
        )
    end,
})

local QuestMain = Tabs.Quest:AddSection("Quest")

local AutoQuestToggle = QuestMain:AddToggle("AutoQuest", {
    Title = "Auto Accept / Turn-in",
    Default = true,
})
AutoQuestToggle:OnChanged(function()
    Config.AutoQuest = AutoQuestToggle.Value
end)

QuestMain:AddButton({
    Title = "Current Quest State",
    Callback = function()
        local quest, taskData = activeQuest()
        local recommended = recommendedQuest()

        notify(
            "Quest",
            table.concat({
                "Level: " .. playerLevel(),
                "Quest: " .. tostring(quest and quest.Name or "None"),
                "Task: " .. tostring(taskData and taskData.Text or "None"),
                "Recommended: "
                    .. tostring(recommended and recommended.Name or "None"),
                "Worker: " .. Runtime.State,
                "Detail: " .. Runtime.Detail,
            }, "\n"),
            10
        )
    end,
})

local SettingsCompat = Tabs.Settings:AddSection("Nexomia Compatibility")

SettingsCompat:AddButton({
    Title = "Executor Capabilities",
    Callback = function()
        notify(
            "Capabilities",
            table.concat({
                "loadstring: " .. tostring(type(loadstring) == "function"),
                "HttpGet/request: "
                    .. tostring(
                        type(game.HttpGet) == "function"
                        or type(requestFn) == "function"
                    ),
                "VirtualInputManager: "
                    .. tostring(VirtualInputManager ~= nil),
                "fireproximityprompt: "
                    .. tostring(type(firePromptFn) == "function"),
                "firesignal: "
                    .. tostring(type(fireSignalFn) == "function"),
                "setclipboard: "
                    .. tostring(type(clipboardFn) == "function"),
                "WebSocket: not used",
                "getscriptclosure: not used",
            }, "\n"),
            10
        )
    end,
})

SettingsCompat:AddButton({
    Title = "Worker Health / Last Error",
    Callback = function()
        notify("Worker Health", workerHealth(), 12)
    end,
})

local InfoMain = Tabs.Info:AddSection("SON HUB")

InfoMain:AddParagraph({
    Title = "Version",
    Content = VERSION .. " | make by hongson",
})

InfoMain:AddParagraph({
    Title = "Compatibility",
    Content =
        "No WebSocket. No getscriptclosure. No SaveManager filesystem. "
        .. "Fluent loads using HttpGet with request fallback.",
})

InfoMain:AddButton({
    Title = "Copy Version",
    Callback = function()
        if type(clipboardFn) == "function" then
            pcall(clipboardFn, "SON HUB " .. VERSION)
            notify("Copied", "SON HUB " .. VERSION, 2)
        end
    end,
})

Window:SelectTab(1)

task.defer(function()
    notify(
        "SON HUB Ready",
        "Lv." .. tostring(playerLevel())
            .. " | "
            .. (game.PlaceId == TARGET_PLACE and "target game" or "place mismatch")
            .. "\nRun Self Test before enabling automation.",
        6
    )
end)

-- ============================================================
-- Cleanup
-- ============================================================

local function unload()
    if not Runtime.Running then
        return
    end

    Runtime.Running = false
    Config.AutoProgress = false
    Config.AutoFishing = false
    Config.AutoMining = false

    setFishingHold(false)
    miningMouse(false)

    if blockHeld then
        blockHeld = false
        keyEvent(Enum.KeyCode.F, false)
    end

    clearFarm()
    cancelPlatform(true)

    for _, connection in ipairs(Runtime.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Runtime.Connections)

    pcall(function()
        Fluent:Destroy()
    end)

    ENV.__SON_HUB_UNLOAD = nil
end

ENV.__SON_HUB_UNLOAD = unload
