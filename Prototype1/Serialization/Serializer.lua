local Serializer = {}

local function escape(value)
    local encoded = tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&apos;")
    return encoded
end

local function cdata(value)
    return "<![CDATA[" .. tostring(value):gsub("]]>", "]]]]><![CDATA[>") .. "]]>"
end

local function finite(value)
    if value ~= value then return 0 end
    if value == math.huge then return 3.402823466e38 end
    if value == -math.huge then return -3.402823466e38 end
    return value
end

local function number(value) return string.format("%.17g", finite(value)) end

local function enumValue(value)
    local ok, numeric = pcall(function() return value.Value end)
    return ok and numeric or tonumber(value) or 0
end

local function vector2(name, value)
    return ("<Vector2 name=\"%s\"><X>%s</X><Y>%s</Y></Vector2>")
        :format(escape(name), number(value.X), number(value.Y))
end

local function vector3(name, value)
    return ("<Vector3 name=\"%s\"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>")
        :format(escape(name), number(value.X), number(value.Y), number(value.Z))
end

local function color3(name, value)
    return ("<Color3 name=\"%s\"><R>%s</R><G>%s</G><B>%s</B></Color3>")
        :format(escape(name), number(value.R), number(value.G), number(value.B))
end

local function cframe(name, value)
    local v = { value:GetComponents() }
    return ("<CoordinateFrame name=\"%s\"><X>%s</X><Y>%s</Y><Z>%s</Z>"
        .. "<R00>%s</R00><R01>%s</R01><R02>%s</R02><R10>%s</R10><R11>%s</R11>"
        .. "<R12>%s</R12><R20>%s</R20><R21>%s</R21><R22>%s</R22></CoordinateFrame>")
        :format(escape(name), number(v[1]), number(v[2]), number(v[3]), number(v[4]),
            number(v[5]), number(v[6]), number(v[7]), number(v[8]), number(v[9]),
            number(v[10]), number(v[11]), number(v[12]))
end

local function sequence(value, color)
    local output = {}
    for _, keypoint in ipairs(value.Keypoints) do
        if color then
            output[#output + 1] = table.concat({ number(keypoint.Time), number(keypoint.Value.R),
                number(keypoint.Value.G), number(keypoint.Value.B), "0" }, " ")
        else
            output[#output + 1] = table.concat({ number(keypoint.Time), number(keypoint.Value),
                number(keypoint.Envelope) }, " ")
        end
    end
    return table.concat(output, " ")
end


local function propertyXml(property, referents)
    local name = escape(property.Name)
    local hint, value = property.Hint, property.Value
    if hint == "String" then
        return ("<string name=\"%s\">%s</string>"):format(name, escape(value))
    elseif hint == "Content" then
        return ("<Content name=\"%s\"><url>%s</url></Content>"):format(name, escape(value))
    elseif hint == "ProtectedString" then
        return ("<ProtectedString name=\"%s\">%s</ProtectedString>"):format(name, cdata(value))
    elseif hint == "Bool" then
        return ("<bool name=\"%s\">%s</bool>"):format(name, value and "true" or "false")
    elseif hint == "Int" then
        return ("<int name=\"%s\">%d</int>"):format(name, value)
    elseif hint == "Float" then
        return ("<float name=\"%s\">%s</float>"):format(name, number(value))
    elseif hint == "Double" then
        return ("<double name=\"%s\">%s</double>"):format(name, number(value))
    elseif hint == "Token" then
        return ("<token name=\"%s\">%d</token>"):format(name, enumValue(value))
    elseif hint == "Vector2" then return vector2(property.Name, value)
    elseif hint == "Vector3" then return vector3(property.Name, value)
    elseif hint == "Color3" then return color3(property.Name, value)
    elseif hint == "CFrame" then return cframe(property.Name, value)
    elseif hint == "UDim" then
        return ("<UDim name=\"%s\"><S>%s</S><O>%d</O></UDim>")
            :format(name, number(value.Scale), value.Offset)
    elseif hint == "UDim2" then
        return ("<UDim2 name=\"%s\"><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>")
            :format(name, number(value.X.Scale), value.X.Offset, number(value.Y.Scale), value.Y.Offset)
    elseif hint == "Rect" then
        return ("<Rect2D name=\"%s\"><min><X>%s</X><Y>%s</Y></min><max><X>%s</X><Y>%s</Y></max></Rect2D>")
            :format(name, number(value.Min.X), number(value.Min.Y), number(value.Max.X), number(value.Max.Y))
    elseif hint == "NumberRange" then
        return ("<NumberRange name=\"%s\">%s %s</NumberRange>"):format(name, number(value.Min), number(value.Max))
    elseif hint == "NumberSequence" then
        return ("<NumberSequence name=\"%s\">%s</NumberSequence>"):format(name, sequence(value, false))
    elseif hint == "ColorSequence" then
        return ("<ColorSequence name=\"%s\">%s</ColorSequence>"):format(name, sequence(value, true))
    elseif hint == "BrickColor" then
        return ("<int name=\"%s\">%d</int>"):format(name, value.Number)
    elseif hint == "Ref" then
        return ("<Ref name=\"%s\">%s</Ref>"):format(name, referents[value] or "null")
    end
    return nil
end

function Serializer.Serialize(modules, project, logger, prototypeVersion)
    local encoding, referents = modules.BinaryEncoding, {}
    for _, record in ipairs(project.Records) do
        if record.SourceInstance then referents[record.SourceInstance] = record.Id end
    end

    local itemXml
    itemXml = function(record, depth)
        local indent = string.rep("\t", depth)
        local lines = { indent .. ("<Item class=\"%s\" referent=\"%s\">"):format(escape(record.ClassName), escape(record.Id)) }
        lines[#lines + 1] = indent .. "\t<Properties>"
        for _, property in ipairs(record.Properties) do
            local ok, xml = pcall(propertyXml, property, referents)
            if ok and xml then
                lines[#lines + 1] = indent .. "\t\t" .. xml
            else
                logger:Warn("Failed to serialize property " .. property.Name,
                    record.Name .. (ok and " (unsupported value)" or (": " .. tostring(xml))))
            end
        end

        local attributeBlob = encoding.Attributes(record.Attributes, logger, record.Name)
        if attributeBlob then
            lines[#lines + 1] = indent .. "\t\t<BinaryString name=\"AttributesSerialize\">"
                .. encoding.Base64(attributeBlob) .. "</BinaryString>"
        end
        local tagBlob = encoding.Tags(record.Tags)
        if tagBlob then
            lines[#lines + 1] = indent .. "\t\t<BinaryString name=\"Tags\">"
                .. encoding.Base64(tagBlob) .. "</BinaryString>"
        end
        lines[#lines + 1] = indent .. "\t</Properties>"
        for _, child in ipairs(record.Children) do lines[#lines + 1] = itemXml(child, depth + 1) end
        lines[#lines + 1] = indent .. "</Item>"
        return table.concat(lines, "\n")
    end

    local output = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        ("\t<Meta name=\"ROSavePrototypeVersion\">%s</Meta>"):format(escape(prototypeVersion)),
        "\t<External>null</External>", "\t<External>nil</External>",
    }
    for _, root in ipairs(project.Roots) do output[#output + 1] = itemXml(root, 1) end
    output[#output + 1] = "</roblox>"
    return table.concat(output, "\n")
end

return Serializer
