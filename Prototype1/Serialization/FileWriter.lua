local FileWriter = {}

function FileWriter.Write(runtime, config, contents)
    if type(runtime.WriteFile) ~= "function" then
        return nil, "No file writer is available. Supply ROSaveRuntime.WriteFile(path, contents)."
    end
    local path = config.OutputName .. ".rbxlx"
    local ok, result = pcall(runtime.WriteFile, path, contents)
    if not ok then return nil, tostring(result) end
    return path
end

return FileWriter
