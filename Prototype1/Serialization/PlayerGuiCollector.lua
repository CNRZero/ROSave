local PlayerGuiCollector = {}

function PlayerGuiCollector.Summarize(project, scan, logger)
    if scan.PlayerGuiObjects == 0 then return 0 end

    for _, root in ipairs(project.Roots) do
        if root.IsPlayerGuiRoot then
            root.Attributes.ROSaveRuntimeSnapshot = true
            root.Attributes.ROSaveSource = "LocalPlayer.PlayerGui"
            return scan.PlayerGuiObjects
        end
    end

    logger:Warn("PlayerGui objects were scanned but no RecoveredPlayerGui root was created.")
    return 0
end

return PlayerGuiCollector
