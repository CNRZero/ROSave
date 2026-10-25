-- Run this module only in a blank test place that you control.
local TestPlaceBuilder = {}

local function make(className, name, parent)
    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

local function setSource(scriptObject, source)
    local ok, message = pcall(function() scriptObject.Source = source end)
    if not ok then
        warn("Studio denied Source assignment for " .. scriptObject:GetFullName() .. ": " .. tostring(message))
    end
end

function TestPlaceBuilder.Build()
    local old = workspace:FindFirstChild("ROSavePrototypeFixture")
    if old then old:Destroy() end

    local root = make("Folder", "ROSavePrototypeFixture", workspace)
    root:SetAttribute("FixtureVersion", "0.1.0")
    root:AddTag("RecoveryFixture")

    local outer = make("Model", "NestedModels", root)
    local inner = make("Model", "Inner", outer)
    local part = make("Part", "TaggedPart", inner)
    part.Anchored = true
    part.Color = Color3.fromRGB(30, 160, 255)
    part.Size = Vector3.new(4, 2, 6)
    part:SetAttribute("HitPoints", 125)
    part:SetAttribute("SpawnOffset", Vector3.new(1, 2, 3))
    part:AddTag("Interactable")

    local attachment = make("Attachment", "BeamOrigin", part)
    local particles = make("ParticleEmitter", "Particles", attachment)
    particles.Rate = 12
    particles.Lifetime = NumberRange.new(0.5, 1.5)

    local values = make("Folder", "Values", root)
    local count = make("IntValue", "Count", values)
    count.Value = 42
    local title = make("StringValue", "Title", values)
    title.Value = "Fixture <&> value"

    local localScript = make("LocalScript", "ControlFlowExamples", root)
    setSource(localScript, [[
local function closure(seed)
    return function(value)
        return seed + value
    end
end

local addTen = closure(10)
local tableModule = require(script.Parent.TableAndRequireExamples)
print(tableModule:greet("fixture").message)
for index = 1, 5 do
    if index % 2 == 0 then
        print("even", addTen(index))
    elseif index == 3 then
        print("three")
    else
        print("odd", index)
    end
end
]])

    local moduleScript = make("ModuleScript", "TableAndRequireExamples", root)
    setSource(moduleScript, [[
local Module = {}
function Module:greet(name)
    return { message = "hello " .. name, nested = { ok = true } }
end
return Module
]])

    local largeScript = make("ModuleScript", "LargeScript", root)
    local source = { "local Module = {}" }
    for index = 1, 250 do
        source[#source + 1] = ("function Module.f%d(value) return value + %d end"):format(index, index)
    end
    source[#source + 1] = "return Module"
    setSource(largeScript, table.concat(source, "\n"))

    local unsupported = make("Configuration", "DeliberatelyUnsupportedContainer", root)
    make("Folder", "SupportedChildMustSurvive", unsupported)

    local players = game:GetService("Players")
    local playerGui = players.LocalPlayer and players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local previous = playerGui:FindFirstChild("ROSaveRuntimeGui")
        if previous then previous:Destroy() end
        local screenGui = make("ScreenGui", "ROSaveRuntimeGui", playerGui)
        local scrolling = make("ScrollingFrame", "LargeHierarchy", screenGui)
        scrolling.Size = UDim2.fromScale(0.5, 0.5)
        make("UIListLayout", "Layout", scrolling)
        for index = 1, 150 do
            local label = make("TextLabel", "Row" .. index, scrolling)
            label.Size = UDim2.new(1, 0, 0, 24)
            label.Text = "Runtime row " .. index
        end
        screenGui:SetAttribute("CreatedAtRuntime", true)
    else
        warn("PlayerGui fixture was skipped because no LocalPlayer is present.")
    end

    return root
end

return TestPlaceBuilder
