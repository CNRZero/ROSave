local Config = {}

local Defaults = {
    SaveWorkspace = true,
    SaveReplicatedStorage = true,
    SaveReplicatedFirst = true,
    SaveStarterGui = true,
    SavePlayerGui = true,
    SaveStarterPlayer = true,
    SaveLighting = true,
    SaveSoundService = true,
    DecompileScripts = true,
    Quality = "Balanced",
    ShowEstimate = true,
    ShowProgress = true,
    ContinueOnError = true,
    OutputName = "RecoveredPlace",
    ModuleSource = "GitHub",
}

local BooleanKeys = {
    "SaveWorkspace", "SaveReplicatedStorage", "SaveReplicatedFirst", "SaveStarterGui",
    "SavePlayerGui", "SaveStarterPlayer", "SaveLighting", "SaveSoundService",
    "DecompileScripts", "ShowEstimate", "ShowProgress", "ContinueOnError",
}

local function copy(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

function Config.Build(overrides)
    local result = copy(Defaults)
    for key, value in pairs(overrides or {}) do
        if result[key] == nil then
            error("Unknown configuration key: " .. tostring(key), 2)
        end
        result[key] = value
    end

    for _, key in ipairs(BooleanKeys) do
        assert(type(result[key]) == "boolean", key .. " must be a boolean")
    end

    assert(result.Quality == "Fast" or result.Quality == "Balanced" or result.Quality == "Best",
        "Quality must be Fast, Balanced, or Best")
    assert(result.ModuleSource == "GitHub" or result.ModuleSource == "Local",
        "ModuleSource must be GitHub or Local")
    assert(type(result.OutputName) == "string" and result.OutputName:match("^[%w_%-]+$"),
        "OutputName may contain only letters, digits, underscore, and hyphen")

    return result
end

return Config
