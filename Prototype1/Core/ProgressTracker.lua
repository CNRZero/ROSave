local ProgressTracker = {}
ProgressTracker.__index = ProgressTracker

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    if minutes > 0 then
        return ("%dm %02ds"):format(minutes, remainder)
    end
    return ("%ds"):format(remainder)
end

function ProgressTracker.new(config, clock, printer)
    return setmetatable({
        Enabled = config.ShowProgress,
        Clock = clock or os.clock,
        Printer = printer or print,
        Total = 0,
        Completed = 0,
        StartedAt = 0,
        LastPrintedAt = -math.huge,
        Label = "Items",
    }, ProgressTracker)
end

function ProgressTracker:Stage(index, name)
    self.Printer(("[%d/9] %s"):format(index, name))
end

function ProgressTracker:Begin(total, label)
    self.Total = total or 0
    self.Completed = 0
    self.StartedAt = self.Clock()
    self.LastPrintedAt = -math.huge
    self.Label = label or "Items"
end

function ProgressTracker:Advance(amount, force)
    self.Completed = math.min(self.Total, self.Completed + (amount or 1))
    if not self.Enabled then
        return
    end

    local now = self.Clock()
    if not force and self.Completed < self.Total and now - self.LastPrintedAt < 1 then
        return
    end
    self.LastPrintedAt = now

    local elapsed = math.max(now - self.StartedAt, 0.000001)
    local speed = self.Completed / elapsed
    local percent = self.Total > 0 and (self.Completed / self.Total * 100) or 100
    local eta = speed > 0 and ((self.Total - self.Completed) / speed) or 0
    self.Printer(("[%s]\n%d / %d\n\nProgress: %.1f%%\nSpeed: %.1f items/sec\nETA: ~%s remaining")
        :format(self.Label, self.Completed, self.Total, percent, speed, duration(eta)))
end

ProgressTracker.FormatDuration = duration

return ProgressTracker
