local Fixture = {}

local function byte(value)
    return string.char(value % 256)
end

local function u32(value)
    if value < 0 then value = value + 4294967296 end
    return byte(value)
        .. byte(math.floor(value / 256))
        .. byte(math.floor(value / 65536))
        .. byte(math.floor(value / 16777216))
end

local function varuint(value)
    local output = {}
    repeat
        local current = value % 128
        value = math.floor(value / 128)
        output[#output + 1] = byte(current + (value > 0 and 128 or 0))
    until value == 0
    return table.concat(output)
end

local function abc(op, a, b, c)
    return op + a * 256 + b * 65536 + c * 16777216
end

local function ad(op, a, d)
    if d < 0 then d = d + 65536 end
    return op + a * 256 + d * 65536
end

local function floatBytes(value, double)
    local size = double and 8 or 4
    local object = buffer.create(size)
    if double then buffer.writef64(object, 0, value) else buffer.writef32(object, 0, value) end
    return buffer.tostring(object)
end

local function encodeConstant(spec)
    local kind = spec.Type
    if kind == "Nil" then
        return byte(0)
    elseif kind == "Boolean" then
        return byte(1) .. byte(spec.Value and 1 or 0)
    elseif kind == "Number" then
        return byte(2) .. floatBytes(spec.Value, true)
    elseif kind == "String" then
        return byte(3) .. varuint(spec.StringReference)
    elseif kind == "Import" then
        return byte(4) .. u32(spec.Value)
    elseif kind == "Table" then
        local chunks = { byte(5), varuint(#spec.Keys) }
        for _, key in ipairs(spec.Keys) do chunks[#chunks + 1] = varuint(key) end
        return table.concat(chunks)
    elseif kind == "Closure" then
        return byte(6) .. varuint(spec.Prototype)
    elseif kind == "Vector" then
        return byte(7)
            .. floatBytes(spec.Value[1], false) .. floatBytes(spec.Value[2], false)
            .. floatBytes(spec.Value[3], false) .. floatBytes(spec.Value[4] or 0, false)
    elseif kind == "TableWithConstants" then
        local chunks = { byte(8), varuint(#spec.Keys) }
        for index, key in ipairs(spec.Keys) do
            chunks[#chunks + 1] = varuint(key)
            chunks[#chunks + 1] = u32(spec.Values[index])
        end
        return table.concat(chunks)
    elseif kind == "Integer" then
        return byte(9) .. byte(spec.Value < 0 and 1 or 0) .. varuint(math.abs(spec.Value))
    elseif kind == "ClassShape" then
        local chunks = {
            byte(10),
            varuint(spec.ClassName),
            byte(spec.PrivateProperties or 0),
            byte(spec.PrivateMethods or 0),
            varuint(spec.PropertyCount),
            varuint(spec.MethodCount),
        }
        for _, index in ipairs(spec.PropertyNames or {}) do chunks[#chunks + 1] = varuint(index) end
        for _, index in ipairs(spec.MethodNames or {}) do chunks[#chunks + 1] = varuint(index) end
        return table.concat(chunks)
    elseif kind == "VectorDouble" then
        return byte(11)
            .. floatBytes(spec.Value[1], true) .. floatBytes(spec.Value[2], true)
            .. floatBytes(spec.Value[3], true) .. floatBytes(spec.Value[4] or 0, true)
    end
    error("Unknown fixture constant " .. tostring(kind), 0)
end

local function protoBody(version, spec)
    local chunks = {
        byte(spec.MaxStackSize or 1),
        byte(spec.NumParams or 0),
        byte(spec.NumUpvalues or 0),
        byte(spec.IsVararg and 1 or 0),
    }

    local flags = spec.Flags or 0
    if version >= 4 then
        chunks[#chunks + 1] = byte(flags)
        chunks[#chunks + 1] = varuint(#(spec.TypeInfo or ""))
        chunks[#chunks + 1] = spec.TypeInfo or ""
    end

    local words = spec.Words or { abc(22, 0, 1, 0) }
    chunks[#chunks + 1] = varuint(#words)
    for _, word in ipairs(words) do chunks[#chunks + 1] = u32(word) end

    local constants = spec.Constants or {}
    chunks[#chunks + 1] = varuint(#constants)
    for _, constant in ipairs(constants) do chunks[#chunks + 1] = encodeConstant(constant) end

    local children = spec.Children or {}
    chunks[#chunks + 1] = varuint(#children)
    for _, child in ipairs(children) do chunks[#chunks + 1] = varuint(child) end

    chunks[#chunks + 1] = varuint(spec.LineDefined or 0)
    chunks[#chunks + 1] = varuint(spec.DebugName or 0)
    chunks[#chunks + 1] = byte(0) -- no line info
    chunks[#chunks + 1] = byte(0) -- no local/upvalue debug names

    if version >= 11 then
        local feedback = spec.Feedback or {}
        chunks[#chunks + 1] = varuint(#feedback)
        for _, slot in ipairs(feedback) do
            chunks[#chunks + 1] = byte(slot.Kind)
            chunks[#chunks + 1] = varuint(slot.Value)
        end
    end

    if version >= 12 and math.floor(flags / 8) % 2 == 1 then
        chunks[#chunks + 1] = varuint(spec.Cost or 0)
    end

    chunks[#chunks + 1] = spec.Extension or ""
    return table.concat(chunks)
end

local function serialize(version, spec)
    spec = spec or {}
    local typesVersion = spec.TypesVersion or (version == 4 and 2 or 3)
    local chunks = { byte(version) }
    if version >= 4 then chunks[#chunks + 1] = byte(typesVersion) end

    local strings = spec.Strings or {}
    chunks[#chunks + 1] = varuint(#strings)
    for _, value in ipairs(strings) do
        chunks[#chunks + 1] = varuint(#value)
        chunks[#chunks + 1] = value
    end

    if version >= 4 and typesVersion == 3 then
        for _, mapping in ipairs(spec.UserdataTypes or {}) do
            chunks[#chunks + 1] = byte(mapping.Index)
            chunks[#chunks + 1] = varuint(mapping.StringReference)
        end
        chunks[#chunks + 1] = byte(0)
    end

    local prototypes = spec.Prototypes or { {} }
    chunks[#chunks + 1] = varuint(#prototypes)
    for _, prototype in ipairs(prototypes) do
        local body = protoBody(version, prototype)
        if version >= 12 then chunks[#chunks + 1] = varuint(#body) end
        chunks[#chunks + 1] = body
    end
    chunks[#chunks + 1] = varuint(spec.MainIndex or 0)
    return table.concat(chunks)
end

local function decodeBase64(value)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for index = 1, #alphabet do lookup[alphabet:sub(index, index)] = index - 1 end

    local output, accumulator, bits = {}, 0, 0
    for index = 1, string.len(value) do
        local character = value:sub(index, index)
        if character ~= "=" then
            accumulator = accumulator * 64 + lookup[character]
            bits = bits + 6
            while bits >= 8 do
                bits = bits - 8
                local divisor = 2 ^ bits
                output[#output + 1] = byte(math.floor(accumulator / divisor) % 256)
                accumulator = accumulator % divisor
            end
        end
    end
    return table.concat(output)
end

function Fixture.Minimal(version)
    return serialize(version)
end

function Fixture.UserdataV9()
    return serialize(9, {
        Strings = { "field" },
        Prototypes = {{
            MaxStackSize = 2,
            Words = { abc(83, 0, 1, 0), 7 * 65536, abc(22, 0, 1, 0) },
            Constants = {{ Type = "String", StringReference = 1 }},
        }},
    })
end

function Fixture.ClassShapeV10()
    return serialize(10, {
        Strings = { "Class", "field", "method" },
        Prototypes = {{
            MaxStackSize = 2,
            Words = { abc(86, 0, 0, 1), 2, abc(22, 0, 1, 0) },
            Constants = {
                { Type = "String", StringReference = 1 },
                { Type = "String", StringReference = 2 },
                { Type = "String", StringReference = 3 },
                {
                    Type = "ClassShape", ClassName = 0,
                    PropertyCount = 1, MethodCount = 1,
                    PropertyNames = { 1 }, MethodNames = { 2 },
                },
            },
        }},
    })
end

function Fixture.FeedbackV11()
    return serialize(11, {
        Strings = { "print" },
        Prototypes = {{
            MaxStackSize = 1,
            Words = {
                abc(7, 0, 0, 0), 0,
                abc(87, 0, 1, 1), 0,
                ad(88, 0, 1), 42,
                abc(22, 0, 1, 0),
            },
            Constants = {{ Type = "String", StringReference = 1 }},
            Feedback = {{ Kind = 0, Value = 2 }},
        }},
    })
end

function Fixture.SizedV12(extension)
    return serialize(12, {
        Prototypes = {{ Flags = 8, Cost = 321, Extension = extension or "" }},
    })
end

function Fixture.VectorDoubleV13()
    return serialize(13, {
        Prototypes = {{
            Words = { ad(5, 0, 0), abc(22, 0, 2, 0) },
            Constants = {{ Type = "VectorDouble", Value = { 1.5, -2.25, 3.125, 0 } }},
        }},
    })
end

function Fixture.PipelineV14()
    return serialize(14, {
        Strings = { "pcall", "child" },
        Prototypes = {
            {
                MaxStackSize = 1,
                NumUpvalues = 1,
                DebugName = 2,
                Words = { abc(9, 0, 0, 0), abc(22, 0, 2, 0) },
            },
            {
                MaxStackSize = 3,
                Flags = 8,
                Cost = 123,
                Words = {
                    ad(4, 2, 7),
                    ad(19, 1, 0),
                    abc(70, 0, 2, 0),
                    abc(89, 0, 1, 2),
                    abc(7, 0, 0, 0), 0,
                    abc(21, 0, 2, 2),
                    abc(22, 0, 2, 0),
                },
                Constants = {{ Type = "String", StringReference = 1 }},
                Children = { 0 },
                Feedback = {{ Kind = 0, Value = 6 }},
            },
        },
        MainIndex = 1,
    })
end

function Fixture.ControlFlowV14()
    return serialize(14, {
        Prototypes = {{
            MaxStackSize = 3,
            Words = {
                abc(3, 0, 1, 0),
                ad(26, 0, 2),
                ad(4, 1, 1),
                ad(23, 0, 1),
                ad(4, 1, 2),
                ad(4, 2, 0),
                ad(26, 0, 2),
                ad(4, 2, 1),
                ad(24, 0, -3),
                abc(22, 1, 2, 0),
            },
        }},
    })
end

function Fixture.LoopsV14()
    return serialize(14, {
        Prototypes = {{
            MaxStackSize = 4,
            Words = {
                ad(4, 0, 3), ad(4, 1, 1), ad(4, 2, 0),
                ad(56, 0, 1), ad(57, 0, -2),
                abc(22, 0, 1, 0),
            },
        }},
    })
end

function Fixture.UnknownOpcodeV14()
    return serialize(14, { Prototypes = {{ Words = { 250 } }} })
end

function Fixture.MalformedV14()
    local value = Fixture.PipelineV14()
    return value:sub(1, #value - 2)
end

-- Produced by the official Luau 0.744 compiler with
-- --binary --fflags=LuauCompileFastpcall=true from V14PipelineSample.luau.
local OfficialV14Base64 = "DgMCC21ha2VDb3VudGVyBXBjYWxsAAODAQMBAQAAABEJAQAAIAENAAAAAAAJAgAAKwECAE8BBQABAACACQEAACcBAQIKAQAAFwADAAkBAAAnAQEACgEAABgA8f8JAQAAFgECAAMCAAAAAAAAAEACAAAAAAAAAAACAAAAAAAA8D8ABAABGAAAAAEAAAABAAAAAgAA/AgABQAAAAAALgMBAAAIAAUGAQAAEwIAAEYBAQALAQAAFgICAAABAAEBARgAAgAAAAIAAAAAAApuBQAAAQoAEEEAAABAAAAABgEAAAQCAAAVAQICBgMBAAQECABZAAICDAICAAAAEEAVAgMDGgICAAYEAwAZBAEABAT//xYEAgADBgEDAgQAABBAAQEBAAEYAAAQAAABAAAAAAACAAAAAAEAAAAAABYC"

function Fixture.OfficialV14()
    return decodeBase64(OfficialV14Base64)
end

Fixture.Serialize = serialize
Fixture.ABC = abc
Fixture.AD = ad

return Fixture
