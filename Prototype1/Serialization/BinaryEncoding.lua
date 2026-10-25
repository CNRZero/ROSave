local BinaryEncoding = {}

local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function byte(value)
    return string.char(value % 256)
end


function BinaryEncoding.UInt32(value)
    value = math.floor(value)
    return byte(value)
        .. byte(math.floor(value / 256))
        .. byte(math.floor(value / 65536))
        .. byte(math.floor(value / 16777216))
end

function BinaryEncoding.Int32(value)
    if value < 0 then value = value + 4294967296 end
    return BinaryEncoding.UInt32(value)
end

local function packedNumber(value, size, writerName, packFormat)
    local bufferLibrary = rawget(_G, "buffer")
    if bufferLibrary and type(bufferLibrary.create) == "function" and type(bufferLibrary[writerName]) == "function" then
        local output = bufferLibrary.create(size)
        bufferLibrary[writerName](output, 0, value)
        return bufferLibrary.tostring(output)
    end
    if string.pack then return string.pack(packFormat, value) end
    return nil
end

function BinaryEncoding.Float32(value)
    return packedNumber(value, 4, "writef32", "<f")
end

function BinaryEncoding.Float64(value)
    return packedNumber(value, 8, "writef64", "<d")
end

function BinaryEncoding.Base64(data)
    local output = {}
    local index = 1
    while index <= #data do
        local a = string.byte(data, index) or 0
        local b = string.byte(data, index + 1) or 0
        local c = string.byte(data, index + 2) or 0
        local value = a * 65536 + b * 256 + c
        local i1 = math.floor(value / 262144) % 64
        local i2 = math.floor(value / 4096) % 64
        local i3 = math.floor(value / 64) % 64
        local i4 = value % 64
        output[#output + 1] = Alphabet:sub(i1 + 1, i1 + 1)
        output[#output + 1] = Alphabet:sub(i2 + 1, i2 + 1)
        output[#output + 1] = index + 1 <= #data and Alphabet:sub(i3 + 1, i3 + 1) or "="
        output[#output + 1] = index + 2 <= #data and Alphabet:sub(i4 + 1, i4 + 1) or "="
        index = index + 3
    end
    return table.concat(output)
end

function BinaryEncoding.Tags(tags)
    if not tags or #tags == 0 then return nil end
    table.sort(tags)
    return table.concat(tags, "\0")
end

local function vector2(value)
    local x = BinaryEncoding.Float32(value.X)
    local y = BinaryEncoding.Float32(value.Y)
    return x and y and (x .. y) or nil
end

local function vector3(value)
    local x = BinaryEncoding.Float32(value.X)
    local y = BinaryEncoding.Float32(value.Y)
    local z = BinaryEncoding.Float32(value.Z)
    return x and y and z and (x .. y .. z) or nil
end

local function encodeAttribute(value)
    local kind = typeof and typeof(value) or type(value)
    if kind == "string" then
        return 0x02, BinaryEncoding.UInt32(#value) .. value
    elseif kind == "boolean" then
        return 0x03, value and "\1" or "\0"
    elseif kind == "number" then
        return 0x06, BinaryEncoding.Float64(value)
    elseif kind == "UDim" then
        local scale = BinaryEncoding.Float32(value.Scale)
        return 0x09, scale and (scale .. BinaryEncoding.Int32(value.Offset)) or nil
    elseif kind == "UDim2" then
        local xs = BinaryEncoding.Float32(value.X.Scale)
        local ys = BinaryEncoding.Float32(value.Y.Scale)
        return 0x0A, xs and ys and (xs .. BinaryEncoding.Int32(value.X.Offset)
            .. ys .. BinaryEncoding.Int32(value.Y.Offset)) or nil
    elseif kind == "BrickColor" then
        return 0x0E, BinaryEncoding.UInt32(value.Number)
    elseif kind == "Color3" then
        local r, g, b = BinaryEncoding.Float32(value.R), BinaryEncoding.Float32(value.G), BinaryEncoding.Float32(value.B)
        return 0x0F, r and g and b and (r .. g .. b) or nil
    elseif kind == "Vector2" then
        return 0x10, vector2(value)
    elseif kind == "Vector3" then
        return 0x11, vector3(value)
    elseif kind == "CFrame" then
        local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
        local values = { x, y, z, r00, r10, r20, r01, r11, r21, r02, r12, r22 }
        local chunks = {}
        for index, component in ipairs(values) do
            local packed = BinaryEncoding.Float32(component)
            if not packed then return 0x14, nil end
            chunks[#chunks + 1] = packed
            if index == 3 then chunks[#chunks + 1] = "\0" end
        end
        return 0x14, table.concat(chunks)
    end
    return nil, nil
end

function BinaryEncoding.Attributes(attributes, logger, context)
    local names = {}
    for name in pairs(attributes or {}) do table.insert(names, name) end
    table.sort(names)

    local encoded = {}
    for _, name in ipairs(names) do
        local typeId, payload = encodeAttribute(attributes[name])
        if typeId and payload then
            encoded[#encoded + 1] = BinaryEncoding.UInt32(#name) .. name .. byte(typeId) .. payload
        elseif logger then
            local kind = typeof and typeof(attributes[name]) or type(attributes[name])
            logger:Warn("Unsupported attribute type " .. tostring(kind) .. " for " .. name, context)
        end
    end
    if #encoded == 0 then return nil end
    return BinaryEncoding.UInt32(#encoded) .. table.concat(encoded)
end

return BinaryEncoding
