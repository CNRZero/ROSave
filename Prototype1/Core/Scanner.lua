local Scanner = {}

local RootSettings = {
    { Setting = "SaveWorkspace", Service = "Workspace", OutputName = "Workspace" },
    { Setting = "SaveReplicatedStorage", Service = "ReplicatedStorage", OutputName = "ReplicatedStorage" },
    { Setting = "SaveReplicatedFirst", Service = "ReplicatedFirst", OutputName = "ReplicatedFirst" },
    { Setting = "SaveStarterGui", Service = "StarterGui", OutputName = "StarterGui" },
    { Setting = "SaveStarterPlayer", Service = "StarterPlayer", OutputName = "StarterPlayer" },
    { Setting = "SaveLighting", Service = "Lighting", OutputName = "Lighting" },
    { Setting = "SaveSoundService", Service = "SoundService", OutputName = "SoundService" },
}

local function getChildren(instance)
    local ok, children = pcall(function() return instance:GetChildren() end)
    return ok and children or nil
end

local function getService(name)
    local ok, service = pcall(function() return game:GetService(name) end)
    return ok and service or nil
end

local function addRoot(roots, instance, name, className, isPlayerGui)
    if instance then
        table.insert(roots, {
            Instance = instance,
            Name = name,
            ClassName = className,
            IsPlayerGui = isPlayerGui == true,
        })
    end
end

function Scanner.Scan(modules, config, runtime, logger, progress)
    local catalog = modules.PropertyCatalog
    local roots = {}
    for _, definition in ipairs(RootSettings) do
        if config[definition.Setting] then
            local service = getService(definition.Service)
            if service then
                addRoot(roots, service, definition.OutputName, definition.Service, false)
            else
                logger:Warn("Service is unavailable and will be skipped.", definition.Service)
            end
        end
    end

    if config.SavePlayerGui then
        local players = getService("Players")
        local player = players and players.LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            addRoot(roots, playerGui, "RecoveredPlayerGui", "Folder", true)
        else
            logger:Warn("SavePlayerGui is enabled, but LocalPlayer.PlayerGui is unavailable.")
        end
    end

    local result = {
        Roots = roots,
        Nodes = {},
        Scripts = {},
        BytecodeCache = {},
        TotalInstances = 0,
        SupportedInstances = 0,
        LocalScripts = 0,
        ModuleScripts = 0,
        BytecodeBytes = 0,
        PlayerGuiObjects = 0,
        SerializationWork = 0,
    }

    for rootIndex, root in ipairs(roots) do
        local initial = getChildren(root.Instance)
        if not initial then
            logger:Warn("Could not enumerate root.", root.Name)
        else
            local queue = {}
            for _, child in ipairs(initial) do
                table.insert(queue, { Instance = child, ParentOutput = nil })
            end

            local cursor = 1
            while cursor <= #queue do
                local item = queue[cursor]
                cursor = cursor + 1
                local instance = item.Instance
                local supported = catalog.IsSupported(instance)
                local node = {
                    Instance = instance,
                    RootIndex = rootIndex,
                    ParentOutput = item.ParentOutput,
                    Supported = supported,
                }
                table.insert(result.Nodes, node)
                local nodeIndex = #result.Nodes

                result.TotalInstances = result.TotalInstances + 1
                if root.IsPlayerGui then
                    result.PlayerGuiObjects = result.PlayerGuiObjects + 1
                end
                if supported then
                    result.SupportedInstances = result.SupportedInstances + 1
                    result.SerializationWork = result.SerializationWork + 1
                end

                if instance.ClassName == "LocalScript" or instance.ClassName == "ModuleScript" then
                    if instance.ClassName == "LocalScript" then
                        result.LocalScripts = result.LocalScripts + 1
                    else
                        result.ModuleScripts = result.ModuleScripts + 1
                    end
                    table.insert(result.Scripts, nodeIndex)

                    if config.DecompileScripts and type(runtime.GetBytecode) == "function" then
                        local okBytes, bytes = pcall(runtime.GetBytecode, instance)
                        if okBytes and type(bytes) == "string" then
                            result.BytecodeCache[instance] = bytes
                            result.BytecodeBytes = result.BytecodeBytes + #bytes
                        else
                            result.BytecodeCache[instance] = false
                        end
                    end
                end

                local children = getChildren(instance)
                if not children then
                    logger:Warn("Could not enumerate children.", instance:GetFullName())
                else
                    local nextParent = supported and nodeIndex or item.ParentOutput
                    for _, child in ipairs(children) do
                        table.insert(queue, { Instance = child, ParentOutput = nextParent })
                    end
                end
            end
        end
    end

    print(("[Scan] %s instances detected\n[Supported] %s instances\n[Scripts] %s scripts detected\n[PlayerGui] %s objects detected")
        :format(result.TotalInstances, result.SupportedInstances, #result.Scripts, result.PlayerGuiObjects))

    return result
end

return Scanner
