local BytecodeReader = {}
BytecodeReader.__index = BytecodeReader

local ConstantType = {
    Nil = 0, Boolean = 1, Number = 2, String = 3, Import = 4,
    Table = 5, Closure = 6, Vector = 7, TableWithConstants = 8, Integer = 9,
}

function BytecodeReader.new(data)
    assert(type(data) == "string", "Bytecode must be a string")
    return setmetatable({ Data = data, Position = 1 }, BytecodeReader)
end

function BytecodeReader:_need(count)
    if self.Position + count - 1 > #self.Data then
        error(("Unexpected end of bytecode at offset %d (needed %d byte(s))."):format(self.Position - 1, count), 0)
    end
end

function BytecodeReader:Byte()
    self:_need(1)
    local value = string.byte(self.Data, self.Position)
    self.Position = self.Position + 1
    return value
end

function BytecodeReader:Bytes(count)
    self:_need(count)
    local value = self.Data:sub(self.Position, self.Position + count - 1)
    self.Position = self.Position + count
    return value
end

function BytecodeReader:UInt32()
    local a, b, c, d = string.byte(self:Bytes(4), 1, 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

function BytecodeReader:Int32()
    local value = self:UInt32()
    return value >= 2147483648 and value - 4294967296 or value
end

function BytecodeReader:VarUInt()
    local value, multiplier = 0, 1
    for _ = 1, 10 do
        local current = self:Byte()
        value = value + (current % 128) * multiplier
        if current < 128 then return value end
        multiplier = multiplier * 128
    end
    error("Malformed variable-length integer.", 0)
end

local function unpackNumber(bytes, readerName, format)
    local bufferLibrary = rawget(_G, "buffer")
    if bufferLibrary and type(bufferLibrary.fromstring) == "function" then
        local object = bufferLibrary.fromstring(bytes)
        return bufferLibrary[readerName](object, 0)
    end
    if string.unpack then
        return string.unpack(format, bytes)
    end
    error("This runtime cannot decode floating-point bytecode constants.", 0)
end

function BytecodeReader:Float32()
    return unpackNumber(self:Bytes(4), "readf32", "<f")
end

function BytecodeReader:Float64()
    return unpackNumber(self:Bytes(8), "readf64", "<d")
end

local function stringAt(strings, reference)
    if reference == 0 then return nil end
    if not strings[reference] then error("Invalid string table reference " .. reference, 0) end
    return strings[reference]
end

local function readConstant(reader, strings, version)
    local kind = reader:Byte()
    if kind == ConstantType.Nil then
        return { Type = "Nil", Value = nil }
    elseif kind == ConstantType.Boolean then
        return { Type = "Boolean", Value = reader:Byte() ~= 0 }
    elseif kind == ConstantType.Number then
        return { Type = "Number", Value = reader:Float64() }
    elseif kind == ConstantType.String then
        return { Type = "String", Value = stringAt(strings, reader:VarUInt()) }
    elseif kind == ConstantType.Import then
        return { Type = "Import", Value = reader:UInt32() }
    elseif kind == ConstantType.Table or kind == ConstantType.TableWithConstants then
        if kind == ConstantType.TableWithConstants and version < 7 then
            error("Table-with-constants appeared before bytecode version 7.", 0)
        end
        local keys, values = {}, {}
        local count = reader:VarUInt()
        for index = 1, count do
            keys[index] = reader:VarUInt()
            if kind == ConstantType.TableWithConstants then values[index] = reader:Int32() end
        end
        return { Type = "Table", Keys = keys, Values = values }
    elseif kind == ConstantType.Closure then
        return { Type = "Closure", Value = reader:VarUInt() }
    elseif kind == ConstantType.Vector then
        return { Type = "Vector", Value = { reader:Float32(), reader:Float32(), reader:Float32(), reader:Float32() } }
    elseif kind == ConstantType.Integer and version >= 8 then
        local negative = reader:Byte() ~= 0
        local magnitude = reader:VarUInt()
        return { Type = "Integer", Value = negative and -magnitude or magnitude }
    end
    error("Unsupported constant type " .. kind, 0)
end

local function parsePrototype(reader, strings, version)
    local proto = {
        MaxStackSize = reader:Byte(),
        NumParams = reader:Byte(),
        NumUpvalues = reader:Byte(),
        IsVararg = reader:Byte() ~= 0,
        Flags = 0,
    }

    if version >= 4 then
        proto.Flags = reader:Byte()
        proto.TypeInfo = reader:Bytes(reader:VarUInt())
    end

    local codeCount = reader:VarUInt()
    proto.Words = {}
    for index = 1, codeCount do proto.Words[index] = reader:UInt32() end

    local constantCount = reader:VarUInt()
    proto.Constants = {}
    for index = 1, constantCount do proto.Constants[index] = readConstant(reader, strings, version) end

    local childCount = reader:VarUInt()
    proto.Protos = {}
    for index = 1, childCount do proto.Protos[index] = reader:VarUInt() end

    proto.LineDefined = reader:VarUInt()
    proto.DebugName = stringAt(strings, reader:VarUInt())

    proto.Lines = {}
    if reader:Byte() ~= 0 then
        local gapLog2 = reader:Byte()
        local relative = {}
        local last = 0
        for index = 1, codeCount do
            last = (last + reader:Byte()) % 256
            relative[index] = last
        end
        local intervalCount = math.floor((codeCount - 1) / (2 ^ gapLog2)) + 1
        local baselines, line = {}, 0
        for index = 1, intervalCount do
            line = line + reader:Int32()
            baselines[index] = line
        end
        for index = 1, codeCount do
            local baseline = baselines[math.floor((index - 1) / (2 ^ gapLog2)) + 1]
            proto.Lines[index] = baseline + relative[index]
        end
    end

    proto.Locals, proto.UpvalueNames = {}, {}
    if reader:Byte() ~= 0 then
        local localCount = reader:VarUInt()
        for index = 1, localCount do
            proto.Locals[index] = {
                Name = stringAt(strings, reader:VarUInt()),
                StartPC = reader:VarUInt(),
                EndPC = reader:VarUInt(),
                Register = reader:Byte(),
            }
        end
        local upvalueCount = reader:VarUInt()
        for index = 1, upvalueCount do
            proto.UpvalueNames[index] = stringAt(strings, reader:VarUInt())
        end
    end
    return proto
end

function BytecodeReader.Parse(data)
    local ok, result = pcall(function()
        local reader = BytecodeReader.new(data)
        local version = reader:Byte()
        if version == 0 then
            error("Compiler error blob: " .. reader:Bytes(#data - 1), 0)
        end
        if version < 3 or version > 8 then
            error(("Unsupported Luau bytecode version %d; Prototype 1 supports standard versions 3-8."):format(version), 0)
        end

        local typesVersion = version >= 4 and reader:Byte() or 0
        local strings = {}
        local stringCount = reader:VarUInt()
        for index = 1, stringCount do strings[index] = reader:Bytes(reader:VarUInt()) end

        local userdataTypes = {}
        if typesVersion == 3 then
            while true do
                local typeIndex = reader:Byte()
                if typeIndex == 0 then break end
                userdataTypes[typeIndex] = stringAt(strings, reader:VarUInt())
            end
        end

        local prototypes = {}
        local prototypeCount = reader:VarUInt()
        for index = 1, prototypeCount do prototypes[index] = parsePrototype(reader, strings, version) end
        local mainIndex = reader:VarUInt() + 1
        if not prototypes[mainIndex] then error("Main prototype index is out of range.", 0) end

        return {
            Version = version, TypesVersion = typesVersion, Strings = strings,
            UserdataTypes = userdataTypes, Prototypes = prototypes, MainIndex = mainIndex,
            BytesConsumed = reader.Position - 1, ByteLength = #data,
        }
    end)

    if ok then return result end
    return nil, tostring(result)
end

return BytecodeReader
