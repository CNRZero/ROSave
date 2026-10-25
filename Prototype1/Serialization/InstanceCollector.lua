local InstanceCollector = {}

local function safeFullName(instance)
    local ok, name = pcall(function() return instance:GetFullName() end)
    return ok and name or tostring(instance)
end

local function readAttributes(instance, logger)
    local ok, value = pcall(function() return instance:GetAttributes() end)
    if ok and type(value) == "table" then return value end
    logger:Warn("Could not read attributes.", safeFullName(instance))
    return {}
end

local function readTags(instance, logger)
    local ok, value = pcall(function() return instance:GetTags() end)
    if ok and type(value) == "table" then
        local copy = {}
        for _, tag in ipairs(value) do copy[#copy + 1] = tag end
        return copy
    end

    local okService, collectionService = pcall(function() return game:GetService("CollectionService") end)
    local okTags, tags = pcall(function() return collectionService:GetTags(instance) end)
    if okService and okTags and type(tags) == "table" then return tags end
    logger:Warn("Could not read CollectionService tags.", safeFullName(instance))
    return {}
end

function InstanceCollector.Collect(modules, scan, config, logger, progress)
    local project = {
        Roots = {}, Records = {}, InstanceToRecord = {}, SkippedByClass = {},
    }

    for index, root in ipairs(scan.Roots) do
        local record = {
            Id = "RBX_ROOT_" .. index,
            ClassName = root.ClassName,
            Name = root.Name,
            Properties = {
                { Name = "Name", Hint = "String", Value = root.Name },
                { Name = "Archivable", Hint = "Bool", Value = true },
            },
            Attributes = {}, Tags = {}, Children = {},
            IsPlayerGuiRoot = root.IsPlayerGui,
        }
        project.Roots[index] = record
        project.Records[#project.Records + 1] = record
    end

    progress:Begin(scan.SupportedInstances, "Collector")
    local nodeToRecord = {}
    for nodeIndex, node in ipairs(scan.Nodes) do
        if node.Supported then
            local instance = node.Instance
            local record = {
                Id = "RBX_" .. nodeIndex,
                ClassName = instance.ClassName,
                Name = instance.Name,
                Properties = modules.PropertyCatalog.ReadProperties(instance, logger),
                Attributes = readAttributes(instance, logger),
                Tags = readTags(instance, logger),
                Children = {},
                SourceInstance = instance,
            }

            if instance.ClassName == "LocalScript" or instance.ClassName == "ModuleScript" then
                record.Properties[#record.Properties + 1] = {
                    Name = "Source", Hint = "ProtectedString", Value = "-- Script recovery has not run.\n",
                }
            elseif instance.ClassName == "Terrain" then
                logger:Warn("Terrain metadata was saved, but voxel data is unsupported in Prototype 1.", safeFullName(instance))
            end

            nodeToRecord[nodeIndex] = record
            project.InstanceToRecord[instance] = record
            project.Records[#project.Records + 1] = record

            local parent = node.ParentOutput and nodeToRecord[node.ParentOutput] or project.Roots[node.RootIndex]
            if not parent then
                parent = project.Roots[node.RootIndex]
                logger:Warn("Recovered object had no output parent.", safeFullName(instance))
            end
            parent.Children[#parent.Children + 1] = record
            progress:Advance(1)
        else
            local className = node.Instance.ClassName
            project.SkippedByClass[className] = (project.SkippedByClass[className] or 0) + 1
        end
    end
    progress:Advance(0, true)

    for className, count in pairs(project.SkippedByClass) do
        logger:Warn(("Skipped %d unsupported %s instance(s); supported descendants were promoted."):format(count, className))
    end
    return project
end

return InstanceCollector
