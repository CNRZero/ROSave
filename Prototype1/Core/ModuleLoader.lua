local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

ModuleLoader.Manifest = {
    "Core/Config.lua",
    "Core/Logger.lua",
    "Core/ProgressTracker.lua",
    "Serialization/BinaryEncoding.lua",
    "Serialization/PropertyCatalog.lua",
    "Decompiler/BytecodeReader.lua",
    "Decompiler/InstructionDecoder.lua",
    "Decompiler/ControlFlow.lua",
    "Decompiler/ExpressionBuilder.lua",
    "Decompiler/StatementBuilder.lua",
    "Decompiler/Decompiler.lua",
    "Core/Scanner.lua",
    "Core/Estimator.lua",
    "Serialization/InstanceCollector.lua",
    "Serialization/PlayerGuiCollector.lua",
    "Serialization/Serializer.lua",
    "Serialization/FileWriter.lua",
    "Serialization/Validator.lua",
    "Core/Main.lua",
}

local function moduleName(path)
    return path:match("([^/]+)%.lua$")
end

function ModuleLoader.new(repository, runtime, sourceMode)
    assert(type(repository) == "table" and type(repository.BaseURL) == "string", "Repository.BaseURL is required")
    assert(type(runtime) == "table" and type(runtime.Compile) == "function", "Runtime.Compile is required")
    return setmetatable({
        Repository = repository, Runtime = runtime, SourceMode = sourceMode or "GitHub",
        SourceCache = {}, ModuleCache = {},
    }, ModuleLoader)
end

function ModuleLoader:_read(path)
    if self.SourceCache[path] then return self.SourceCache[path] end
    local reader, location
    if self.SourceMode == "Local" then
        reader, location = self.Runtime.LoadLocalModule, path
        if type(reader) ~= "function" then
            return nil, "Local mode requires ROSaveRuntime.LoadLocalModule(path)."
        end
    elseif self.SourceMode == "GitHub" then
        reader, location = self.Runtime.HttpGet, self.Repository.BaseURL .. path
        if type(reader) ~= "function" then
            return nil, "GitHub mode requires ROSaveRuntime.HttpGet(url)."
        end
    else
        return nil, "Unknown module source: " .. tostring(self.SourceMode)
    end

    local ok, source = pcall(reader, location)
    if not ok then return nil, source end
    if type(source) ~= "string" or #source == 0 then return nil, "Module source was empty or not text." end
    self.SourceCache[path] = source
    return source
end

function ModuleLoader:Load(path)
    if self.ModuleCache[path] then return self.ModuleCache[path] end
    local source, readError = self:_read(path)
    if not source then return nil, readError end

    local chunk, compileError = self.Runtime.Compile(source, "@" .. path)
    if not chunk then return nil, "Compilation failed: " .. tostring(compileError) end
    local ok, value = pcall(chunk)
    if not ok then return nil, "Initialization failed: " .. tostring(value) end
    if type(value) ~= "table" then return nil, "Module must return a table." end

    self.ModuleCache[path] = value
    return value
end

function ModuleLoader:LoadAll(manifest)
    local registry = {}
    for _, path in ipairs(manifest) do
        local value, loadError = self:Load(path)
        if not value then return nil, { Path = path, Reason = loadError } end
        local name = moduleName(path)
        if not name or registry[name] then
            return nil, { Path = path, Reason = "Duplicate or invalid module name." }
        end
        registry[name] = value
    end
    return registry
end

return ModuleLoader
