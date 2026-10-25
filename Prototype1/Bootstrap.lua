-- Roblox Recovery Prototype 0.1.0
-- Run only in a place you own or have explicit permission to test.

local PrototypeVersion = "0.2.0"

local Repository = {
    Branch = "main",
    BaseURL = "https://raw.githubusercontent.com/CNRZero/ROSave/main/Prototype1/",
}

local UserConfig = {
    -- Change Prototype 1 settings here. See Core/Config.lua for defaults.
    ModuleSource = "GitHub",
}

print(("Roblox Recovery Prototype\nVersion %s\n\n[1/9] Loading modules..."):format(PrototypeVersion))

local runtime = rawget(_G, "ROSaveRuntime") or {}

-- Some authorized runtimes inject capabilities into the script environment
-- without mirroring them into _G. Resolve those direct globals first, while
-- retaining _G compatibility for environments that use a shared table.
runtime.Compile = runtime.Compile or loadstring or rawget(_G, "loadstring")
runtime.WriteFile = runtime.WriteFile or writefile or rawget(_G, "writefile")
runtime.GetBytecode = runtime.GetBytecode or getscriptbytecode or rawget(_G, "getscriptbytecode")
runtime.Clock = runtime.Clock or os.clock

if not runtime.HttpGet then
    runtime.HttpGet = function(url)
        return game:HttpGet(url)
    end
end

local function startupError(path, reason)
    error(("\n[Loader Error]\n\nFailed to load:\n%s\n\nReason:\n%s\n\nPrototype startup cancelled.")
        :format(path, tostring(reason)), 0)
end

if type(runtime.Compile) ~= "function" then
    startupError("Core/ModuleLoader.lua", "No Luau source compiler is available. Supply ROSaveRuntime.Compile.")
end

local loaderPath = "Core/ModuleLoader.lua"
local okFetch, loaderSource = pcall(runtime.HttpGet, Repository.BaseURL .. loaderPath)
if not okFetch or type(loaderSource) ~= "string" then
    startupError(loaderPath, okFetch and "HTTP response was not source text." or loaderSource)
end

local loaderChunk, compileError = runtime.Compile(loaderSource, "@" .. loaderPath)
if not loaderChunk then
    startupError(loaderPath, compileError)
end

local okLoader, ModuleLoader = pcall(loaderChunk)
if not okLoader or type(ModuleLoader) ~= "table" then
    startupError(loaderPath, okLoader and "Module did not return a table." or ModuleLoader)
end

local loader = ModuleLoader.new(Repository, runtime, UserConfig.ModuleSource)
local modules, loadError = loader:LoadAll(ModuleLoader.Manifest)
if not modules then
    startupError(loadError.Path or "unknown module", loadError.Reason or "Unknown loader failure.")
end

local config = modules.Config.Build(UserConfig)
local okRun, runError = xpcall(function()
    modules.Main.Run(modules, config, runtime, PrototypeVersion)
end, function(message)
    return debug and debug.traceback and debug.traceback(tostring(message), 2) or tostring(message)
end)

if not okRun then
    error("[Prototype Error]\n" .. tostring(runError), 0)
end
