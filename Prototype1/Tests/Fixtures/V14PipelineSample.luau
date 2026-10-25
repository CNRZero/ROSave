local function makeCounter(start)
    local value = start

    return function(limit)
        while value < limit do
            if value % 2 == 0 then
                value += 1
            else
                value += 2
            end
        end

        return value
    end
end

local counter = makeCounter(0)
local ok, result = pcall(counter, 8)

return ok and result or -1
