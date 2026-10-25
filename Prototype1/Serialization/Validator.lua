local Validator = {}

function Validator.ValidateXml(xml, expectedItems)
    local errors = {}
    if type(xml) ~= "string" or #xml == 0 then return false, { "Output is empty." } end
    if not xml:find("<roblox", 1, true) or not xml:find("</roblox>", 1, true) then
        errors[#errors + 1] = "Missing RBXLX root element."
    end

    local itemCount, seen = 0, {}
    for referent in xml:gmatch('<Item class="[^"]+" referent="([^"]+)">') do
        itemCount = itemCount + 1
        if seen[referent] then errors[#errors + 1] = "Duplicate referent: " .. referent end
        seen[referent] = true
    end
    if itemCount ~= expectedItems then
        errors[#errors + 1] = ("Expected %d Item nodes, found %d."):format(expectedItems, itemCount)
    end
    local opens = select(2, xml:gsub("<Item ", ""))
    local closes = select(2, xml:gsub("</Item>", ""))
    if opens ~= closes then
        errors[#errors + 1] = ("Unbalanced Item elements (%d open, %d close)."):format(opens, closes)
    end
    return #errors == 0, errors
end

function Validator.ValidateSources(project, runtime)
    local errors = {}
    if type(runtime.Compile) ~= "function" then return true, errors end
    for _, record in ipairs(project.Records) do
        if record.ClassName == "LocalScript" or record.ClassName == "ModuleScript" then
            for _, property in ipairs(record.Properties) do
                if property.Name == "Source" then
                    local chunk, compileError = runtime.Compile(property.Value, "@Recovered/" .. record.Name)
                    if not chunk then errors[#errors + 1] = record.Name .. ": " .. tostring(compileError) end
                end
            end
        end
    end
    return #errors == 0, errors
end

return Validator
