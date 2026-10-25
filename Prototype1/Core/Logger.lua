local Logger = {}
Logger.__index = Logger

function Logger.new(printer)
    return setmetatable({
        Entries = {},
        WarningCount = 0,
        ErrorCount = 0,
        Printer = printer or print,
    }, Logger)
end

function Logger:_write(level, message, context)
    local entry = {
        Level = level,
        Message = tostring(message),
        Context = context,
    }
    table.insert(self.Entries, entry)

    if level == "Warning" then
        self.WarningCount = self.WarningCount + 1
    elseif level == "Error" then
        self.ErrorCount = self.ErrorCount + 1
    end

    local suffix = context and ("\nContext: " .. tostring(context)) or ""
    self.Printer(("[%s]\n%s%s"):format(level, entry.Message, suffix))
end

function Logger:Info(message, context)
    self:_write("Info", message, context)
end

function Logger:Warn(message, context)
    self:_write("Warning", message, context)
end

function Logger:Error(message, context)
    self:_write("Error", message, context)
end

function Logger:Try(label, continueOnError, callback)
    local ok, a, b, c = pcall(callback)
    if ok then
        return true, a, b, c
    end

    self:Warn(label .. " failed: " .. tostring(a))
    if not continueOnError then
        error(a, 0)
    end
    return false, a
end

return Logger
