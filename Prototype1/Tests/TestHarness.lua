local Harness = { Passed = 0, Failed = 0 }

function Harness.equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. (" (expected %s, got %s)"):format(tostring(expected), tostring(actual)), 2)
    end
end

function Harness.truthy(value, message)
    if not value then error(message or "expected a truthy value", 2) end
end

function Harness.contains(value, fragment, message)
    if not tostring(value):find(fragment, 1, true) then
        error((message or "missing fragment") .. ": " .. tostring(fragment), 2)
    end
end

function Harness.test(name, callback)
    local ok, message = pcall(callback)
    if ok then
        Harness.Passed = Harness.Passed + 1
        print("[PASS] " .. name)
    else
        Harness.Failed = Harness.Failed + 1
        print("[FAIL] " .. name .. "\n" .. tostring(message))
    end
end

function Harness.finish()
    print(("\n%d passed, %d failed"):format(Harness.Passed, Harness.Failed))
    if Harness.Failed > 0 then error("Test suite failed.", 0) end
end

return Harness
