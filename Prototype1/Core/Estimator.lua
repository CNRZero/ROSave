local Estimator = {}

local QualityMultiplier = {
    Fast = 0.70,
    Balanced = 1.00,
    Best = 1.65,
}

local function humanRange(low, high, formatDuration)
    return ("Approximately %s-%s"):format(formatDuration(low), formatDuration(high))
end

function Estimator.Estimate(scan, config, formatDuration)
    local instanceCost = scan.SupportedInstances * 0.00045
    local scriptCost = #scan.Scripts * 0.008
    local bytecodeCost = scan.BytecodeBytes / 180000
    local guiCost = scan.PlayerGuiObjects * 0.00015
    local seconds = (instanceCost + scriptCost + bytecodeCost + guiCost + 0.25)
        * QualityMultiplier[config.Quality]

    local low = math.max(1, seconds * 0.70)
    local high = math.max(low + 1, seconds * 1.60)
    local estimate = {
        LowSeconds = low,
        HighSeconds = high,
        WorkUnits = scan.SupportedInstances + #scan.Scripts * 8 + math.ceil(scan.BytecodeBytes / 1024),
    }

    if config.ShowEstimate then
        print("[Estimate]\n" .. humanRange(low, high, formatDuration))
    end
    return estimate
end

return Estimator
