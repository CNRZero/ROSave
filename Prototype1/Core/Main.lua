local Main = {}

local function setSource(record, source)
    for _, property in ipairs(record.Properties) do
        if property.Name == "Source" then
            property.Value = source
            return
        end
    end
    record.Properties[#record.Properties + 1] = { Name = "Source", Hint = "ProtectedString", Value = source }
end

local function scriptName(instance)
    local ok, value = pcall(function() return instance:GetFullName() end)
    return ok and value or tostring(instance)
end

local function formatReport(version, scan, stats, playerGuiSaved, elapsed, output, warnings)
    return table.concat({
        "SAVE COMPLETE", "", "Prototype:", version, "",
        "Instances discovered:", tostring(scan.TotalInstances), "",
        "Instances saved:", tostring(scan.SupportedInstances), "",
        "Scripts discovered:", tostring(#scan.Scripts), "",
        "Scripts successfully decompiled:", tostring(stats.Success), "",
        "Scripts partially recovered:", tostring(stats.Partial), "",
        "Scripts failed:", tostring(stats.Failed), "",
        "PlayerGui objects saved:", tostring(playerGuiSaved), "",
        "Elapsed time:", elapsed, "", "Output:", output, "", "Warnings:", tostring(warnings),
    }, "\n")
end

function Main.Run(modules, config, runtime, prototypeVersion)
    local startedAt = (runtime.Clock or os.clock)()
    local logger = modules.Logger.new(print)
    local progress = modules.ProgressTracker.new(config, runtime.Clock, print)

    if type(runtime.WriteFile) ~= "function" then
        error("Output unavailable: supply ROSaveRuntime.WriteFile(path, contents) before starting.", 0)
    end

    progress:Stage(2, "Scanning...")
    local scan = modules.Scanner.Scan(modules, config, runtime, logger, progress)
    modules.Estimator.Estimate(scan, config, modules.ProgressTracker.FormatDuration)

    progress:Stage(3, "Collecting instances...")
    local project = modules.InstanceCollector.Collect(modules, scan, config, logger, progress)

    progress:Stage(4, "Saving hierarchy...")
    logger:Info(("Prepared %d supported instance records across %d roots.")
        :format(scan.SupportedInstances, #project.Roots))

    progress:Stage(5, "Saving PlayerGui...")
    local playerGuiSaved = modules.PlayerGuiCollector.Summarize(project, scan, logger)

    progress:Stage(6, "Decompiling scripts...")
    local stats = { Success = 0, Partial = 0, Failed = 0 }
    progress:Begin(#scan.Scripts, "Decompiler")
    if config.DecompileScripts and type(runtime.GetBytecode) ~= "function" then
        logger:Warn("Script decompilation is enabled, but ROSaveRuntime.GetBytecode(script) is unavailable.")
    end

    for _, nodeIndex in ipairs(scan.Scripts) do
        local node = scan.Nodes[nodeIndex]
        local instance = node.Instance
        local record = project.InstanceToRecord[instance]
        local bytes = scan.BytecodeCache[instance]

        local result
        if not config.DecompileScripts then
            result = { Status = "partial", Source = "-- Decompilation was disabled in Prototype 1 configuration.\n" }
        elseif type(bytes) ~= "string" then
            result = { Status = "failed", Source = "-- Bytecode was unavailable in this authorized runtime.\n",
                Error = "Runtime bytecode provider returned no data." }
        else
            local ok, value = pcall(modules.Decompiler.Decompile, modules, bytes, config.Quality)
            result = ok and value or { Status = "failed", Source = "-- Decompiler failure: " .. tostring(value) .. "\n", Error = value }
        end

        if result.Status == "failed" and not config.ContinueOnError then
            error("Script decompilation stopped: " .. tostring(result.Error), 0)
        end

        if result.Status == "success" then
            stats.Success = stats.Success + 1
        elseif result.Status == "partial" then
            stats.Partial = stats.Partial + 1
            logger:Warn("Script was partially recovered.", scriptName(instance))
        else
            stats.Failed = stats.Failed + 1
            logger:Warn("Script could not be decompiled: " .. tostring(result.Error), scriptName(instance))
        end
        if record then setSource(record, result.Source) end
        progress:Advance(1)
    end
    progress:Advance(0, true)

    progress:Stage(7, "Writing output...")
    local xml = modules.Serializer.Serialize(modules, project, logger, prototypeVersion)
    local outputPath, writeError = modules.FileWriter.Write(runtime, config, xml)
    if not outputPath then error("Failed to write RBXLX output: " .. tostring(writeError), 0) end

    progress:Stage(8, "Validating...")
    local xmlValid, xmlErrors = modules.Validator.ValidateXml(xml, #project.Records)
    local sourcesValid, sourceErrors = modules.Validator.ValidateSources(project, runtime)
    for _, validationError in ipairs(xmlErrors) do logger:Warn("RBXLX validation: " .. validationError) end
    for _, validationError in ipairs(sourceErrors) do logger:Warn("Luau validation: " .. validationError) end
    if not xmlValid then error("The written RBXLX failed structural validation. Review warnings before using it.", 0) end
    if not sourcesValid then logger:Warn("Some reconstructed sources did not compile; output remains available for inspection.") end

    progress:Stage(9, "Complete")
    local elapsed = (runtime.Clock or os.clock)() - startedAt
    print(formatReport(prototypeVersion, scan, stats, playerGuiSaved,
        modules.ProgressTracker.FormatDuration(elapsed), outputPath, logger.WarningCount))

    return {
        Output = outputPath, Scan = scan, Stats = stats, Warnings = logger.WarningCount,
        XmlValid = xmlValid, SourcesValid = sourcesValid,
    }
end

return Main
