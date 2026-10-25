local BytecodeReader = {}
BytecodeReader.__index = BytecodeReader

local MIN_VERSION = 3
local MAX_VERSION = 14
local MAX_COLLECTION_COUNT = 1000000
local UINT32_BASE = 4294967296
local MAX_SAFE_HIGH = 2097152

local ConstantType = {
    Nil = 0,
    Boolean = 1,
    Number = 2,
    String = 3,
    Import = 4,
    Table = 5,
    Closure = 6,
    Vector = 7,
    TableWithConstants = 8,
    Integer = 9,
    ClassShape = 10,
    VectorDouble = 11,
}

local ConstantMinimumVersion = {
    [ConstantType.Vector] = 5,
    [ConstantType.TableWithConstants] = 7,
    [ConstantType.Integer] = 8,
    [ConstantType.ClassShape] = 10,
    [ConstantType.VectorDouble] = 13,
}

function BytecodeReader.new(data)
    assert(type(data) == "string", "Bytecode must be a string")
    return setmetatable({ Data = data, Position = 1 }, BytecodeReader)
end

function BytecodeReader:Remaining()
    return #self.Data - self.Position + 1
end

function BytecodeReader:_need(count)
    if count < 0 or self.Position + count - 1 > #self.Data then
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
    return value >= 2147483648 and value - UINT32_BASE or value
end

function BytecodeReader:VarUInt()
    local value, multiplier = 0, 1
    for index = 1, 5 do
        local current = self:Byte()
        local payload = current % 128
        if index == 5 and payload > 15 then
            error("Variable-length integer exceeds 32 bits.", 0)
        end
        value = value + payload * multiplier
        if current < 128 then return value end
        multiplier = multiplier * 128
    end
    error("Malformed variable-length integer.", 0)
end

function BytecodeReader:VarUInt64()
    local low, high, shift = 0, 0, 0
    for index = 1, 10 do
        local current = self:Byte()
        local payload = current % 128
        if index == 10 and payload > 1 then
            error("Variable-length integer exceeds 64 bits.", 0)
        end

        if shift < 32 then
            local lowBits = math.min(7, 32 - shift)
            local lowMask = 2 ^ lowBits
            low = low + (payload % lowMask) * (2 ^ shift)
            if lowBits < 7 then
                high = high + math.floor(payload / lowMask)
            end
        else
            high = high + payload * (2 ^ (shift - 32))
        end

        if current < 128 then
            return { Low = low, High = high }
        end
        shift = shift + 7
    end
    error("Malformed variable-length integer.", 0)
end

local function uint64ToDecimal(value)
    local high, low = value.High, value.Low
    if high == 0 and low == 0 then return "0" end

    local digits = {}
    while high ~= 0 or low ~= 0 do
        local nextHigh = math.floor(high / 10)
        local carried = (high - nextHigh * 10) * UINT32_BASE + low
        local nextLow = math.floor(carried / 10)
        digits[#digits + 1] = tostring(carried - nextLow * 10)
        high, low = nextHigh, nextLow
    end

    local output = {}
    for index = #digits, 1, -1 do output[#output + 1] = digits[index] end
    return table.concat(output)
end

local function uint64ToSafeNumber(value)
    if value.High < MAX_SAFE_HIGH then
        return value.High * UINT32_BASE + value.Low
    elseif value.High == MAX_SAFE_HIGH and value.Low == 0 then
        return 9007199254740992
    end
    return nil
end

local function hasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

local function unpackNumber(bytes, readerName, format)
    local bufferLibrary = buffer or rawget(_G, "buffer")
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

local function checkCount(reader, count, label, minimumBytes)
    if count > MAX_COLLECTION_COUNT then
        error(("%s count %d exceeds the safety limit."):format(label, count), 0)
    end
    if minimumBytes and count * minimumBytes > reader:Remaining() then
        error(("%s count %d exceeds the remaining bytecode."):format(label, count), 0)
    end
end

local function stringAt(strings, reference)
    if reference == 0 then return nil end
    if not strings[reference] then error("Invalid string table reference " .. reference, 0) end
    return strings[reference]
end

local function readClassShape(reader)
    local shape = {
        ClassName = reader:VarUInt(),
        PrivateInstanceProperties = reader:Byte(),
        PrivateStaticMethods = reader:Byte(),
        PropertyCount = reader:VarUInt(),
        MethodCount = reader:VarUInt(),
        PropertyNames = {},
        MethodNames = {},
    }

    if shape.PrivateInstanceProperties > shape.PropertyCount then
        error("Class-shape private property count exceeds total properties.", 0)
    end
    if shape.PrivateStaticMethods > shape.MethodCount then
        error("Class-shape private method count exceeds total methods.", 0)
    end

    local publicProperties = shape.PropertyCount - shape.PrivateInstanceProperties
    local publicMethods = shape.MethodCount - shape.PrivateStaticMethods
    checkCount(reader, publicProperties + publicMethods, "Class-shape member", 1)

    for index = 1, publicProperties do shape.PropertyNames[index] = reader:VarUInt() end
    for index = 1, publicMethods do shape.MethodNames[index] = reader:VarUInt() end
    return shape
end

local function readInteger(reader)
    local negativeByte = reader:Byte()
    if negativeByte > 1 then error("Integer constant has an invalid sign byte.", 0) end

    local magnitude = reader:VarUInt64()
    if negativeByte == 0 then
        if magnitude.High >= 2147483648 then
            error("Positive integer constant exceeds int64 range.", 0)
        end
    elseif magnitude.High > 2147483648 or (magnitude.High == 2147483648 and magnitude.Low > 0) then
        error("Negative integer constant exceeds int64 range.", 0)
    end

    local decimal = uint64ToDecimal(magnitude)
    local numberValue = uint64ToSafeNumber(magnitude)
    return {
        Type = "Integer",
        Negative = negativeByte == 1,
        Magnitude = decimal,
        Literal = (negativeByte == 1 and "-" or "") .. decimal,
        Value = numberValue and (negativeByte == 1 and -numberValue or numberValue) or nil,
        SourceExact = numberValue ~= nil,
    }
end

local function readConstant(reader, strings, version)
    local kind = reader:Byte()
    local minimumVersion = ConstantMinimumVersion[kind]
    if minimumVersion and version < minimumVersion then
        error(("Constant type %d requires bytecode version %d."):format(kind, minimumVersion), 0)
    end

    if kind == ConstantType.Nil then
        return { Type = "Nil", Value = nil }
    elseif kind == ConstantType.Boolean then
        local value = reader:Byte()
        if value > 1 then error("Boolean constant has an invalid value.", 0) end
        return { Type = "Boolean", Value = value ~= 0 }
    elseif kind == ConstantType.Number then
        return { Type = "Number", Value = reader:Float64() }
    elseif kind == ConstantType.String then
        return { Type = "String", Value = stringAt(strings, reader:VarUInt()) }
    elseif kind == ConstantType.Import then
        return { Type = "Import", Value = reader:UInt32() }
    elseif kind == ConstantType.Table or kind == ConstantType.TableWithConstants then
        local keys, values = {}, {}
        local count = reader:VarUInt()
        checkCount(reader, count, "Table constant key", kind == ConstantType.TableWithConstants and 5 or 1)
        for index = 1, count do
            keys[index] = reader:VarUInt()
            if kind == ConstantType.TableWithConstants then values[index] = reader:Int32() end
        end
        return {
            Type = "Table",
            Keys = keys,
            Values = values,
            HasConstants = kind == ConstantType.TableWithConstants,
        }
    elseif kind == ConstantType.Closure then
        return { Type = "Closure", Value = reader:VarUInt() }
    elseif kind == ConstantType.Vector then
        return {
            Type = "Vector",
            Precision = "float",
            Value = { reader:Float32(), reader:Float32(), reader:Float32(), reader:Float32() },
        }
    elseif kind == ConstantType.Integer then
        return readInteger(reader)
    elseif kind == ConstantType.ClassShape then
        return { Type = "ClassShape", Value = readClassShape(reader) }
    elseif kind == ConstantType.VectorDouble then
        return {
            Type = "VectorDouble",
            Precision = "double",
            Value = { reader:Float64(), reader:Float64(), reader:Float64(), reader:Float64() },
        }
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

    if proto.NumParams > proto.MaxStackSize then
        error("Prototype parameter count exceeds its stack size.", 0)
    end

    if version >= 4 then
        proto.Flags = reader:Byte()
        local typeSize = reader:VarUInt()
        proto.TypeInfo = reader:Bytes(typeSize)
    else
        proto.TypeInfo = ""
    end

    local codeCount = reader:VarUInt()
    checkCount(reader, codeCount, "Instruction word", 4)
    proto.Words = {}
    for index = 1, codeCount do proto.Words[index] = reader:UInt32() end

    local constantCount = reader:VarUInt()
    checkCount(reader, constantCount, "Constant", 1)
    proto.Constants = {}
    for index = 1, constantCount do
        proto.Constants[index] = readConstant(reader, strings, version)
    end

    local childCount = reader:VarUInt()
    checkCount(reader, childCount, "Child prototype", 1)
    proto.Protos = {}
    for index = 1, childCount do proto.Protos[index] = reader:VarUInt() end

    proto.LineDefined = reader:VarUInt()
    proto.DebugName = stringAt(strings, reader:VarUInt())

    proto.Lines = {}
    local hasLines = reader:Byte()
    if hasLines > 1 then error("Prototype line-info marker is invalid.", 0) end
    if hasLines ~= 0 then
        local gapLog2 = reader:Byte()
        if gapLog2 > 31 then error("Prototype line-info gap is invalid.", 0) end

        local relative = {}
        local last = 0
        for index = 1, codeCount do
            last = (last + reader:Byte()) % 256
            relative[index] = last
        end

        local span = 2 ^ gapLog2
        local intervalCount = codeCount == 0 and 0 or math.floor((codeCount - 1) / span) + 1
        checkCount(reader, intervalCount, "Line-info interval", 4)
        local baselines, line = {}, 0
        for index = 1, intervalCount do
            line = line + reader:Int32()
            baselines[index] = line
        end
        for index = 1, codeCount do
            local baseline = baselines[math.floor((index - 1) / span) + 1]
            proto.Lines[index] = baseline + relative[index]
        end
    end

    proto.Locals, proto.UpvalueNames = {}, {}
    local hasDebug = reader:Byte()
    if hasDebug > 1 then error("Prototype debug-info marker is invalid.", 0) end
    if hasDebug ~= 0 then
        local localCount = reader:VarUInt()
        checkCount(reader, localCount, "Debug local", 4)
        for index = 1, localCount do
            local localInfo = {
                Name = stringAt(strings, reader:VarUInt()),
                StartPC = reader:VarUInt(),
                EndPC = reader:VarUInt(),
                Register = reader:Byte(),
            }
            if localInfo.StartPC > localInfo.EndPC or localInfo.EndPC > codeCount then
                error("Debug local has an invalid PC range.", 0)
            end
            if localInfo.Register >= proto.MaxStackSize and proto.MaxStackSize > 0 then
                error("Debug local register is outside the prototype stack.", 0)
            end
            proto.Locals[index] = localInfo
        end

        local upvalueCount = reader:VarUInt()
        if upvalueCount ~= proto.NumUpvalues then
            error("Debug upvalue count does not match the prototype header.", 0)
        end
        checkCount(reader, upvalueCount, "Debug upvalue", 1)
        for index = 1, upvalueCount do
            proto.UpvalueNames[index] = stringAt(strings, reader:VarUInt())
        end
    end

    proto.FeedbackSlots = {}
    if version >= 11 then
        local feedbackCount = reader:VarUInt()
        checkCount(reader, feedbackCount, "Feedback slot", 2)
        for index = 1, feedbackCount do
            local kind = reader:Byte()
            if kind ~= 0 and kind ~= 1 then
                error("Unknown feedback slot type " .. kind, 0)
            end
            proto.FeedbackSlots[index] = {
                Type = kind == 0 and "CallTarget" or "Construct",
                Value = reader:VarUInt(),
            }
        end
    end

    if version >= 12 and hasFlag(proto.Flags, 8) then
        local cost = reader:VarUInt64()
        proto.Cost = uint64ToSafeNumber(cost)
        proto.CostLiteral = uint64ToDecimal(cost)
    end

    return proto
end

local function validateConstantReferences(proto, prototypes)
    for _, constant in ipairs(proto.Constants) do
        if constant.Type == "Table" then
            for index, key in ipairs(constant.Keys) do
                if not proto.Constants[key + 1] then
                    error("Table constant has an invalid key constant index " .. key, 0)
                end
                local value = constant.Values[index]
                if constant.HasConstants and value >= 0 and not proto.Constants[value + 1] then
                    error("Table constant has an invalid value constant index " .. value, 0)
                end
            end
        elseif constant.Type == "Closure" then
            if not prototypes[constant.Value + 1] then
                error("Closure constant has an invalid prototype index " .. constant.Value, 0)
            end
        elseif constant.Type == "ClassShape" then
            local shape = constant.Value
            local function requireString(index)
                local item = proto.Constants[index + 1]
                if not item or item.Type ~= "String" then
                    error("Class-shape member references a non-string constant " .. index, 0)
                end
            end
            requireString(shape.ClassName)
            for _, index in ipairs(shape.PropertyNames) do requireString(index) end
            for _, index in ipairs(shape.MethodNames) do requireString(index) end
        end
    end

    for _, child in ipairs(proto.Protos) do
        if not prototypes[child + 1] then
            error("Prototype has an invalid child index " .. child, 0)
        end
    end
end

function BytecodeReader.Parse(data)
    local ok, result = pcall(function()
        local reader = BytecodeReader.new(data)
        local version = reader:Byte()
        if version == 0 then
            error("Compiler error blob: " .. reader:Bytes(#data - 1), 0)
        end
        if version < MIN_VERSION or version > MAX_VERSION then
            error(("Unsupported Luau bytecode version %d; Prototype 1 supports standard versions %d-%d.")
                :format(version, MIN_VERSION, MAX_VERSION), 0)
        end

        local typesVersion = version >= 4 and reader:Byte() or 0
        if version >= 4 then
            if typesVersion < 1 or typesVersion > 3 then
                error(("Unsupported Luau type-info version %d."):format(typesVersion), 0)
            end
            if version == 4 and typesVersion == 3 then
                error("Luau type-info version 3 requires bytecode version 5 or newer.", 0)
            end
        end

        local stringCount = reader:VarUInt()
        checkCount(reader, stringCount, "String", 1)
        local strings = {}
        for index = 1, stringCount do
            local length = reader:VarUInt()
            strings[index] = reader:Bytes(length)
        end

        local userdataTypes = {}
        if typesVersion == 3 then
            while true do
                local typeIndex = reader:Byte()
                if typeIndex == 0 then break end
                if typeIndex > 32 then error("Userdata type index exceeds the supported mapping range.", 0) end
                if userdataTypes[typeIndex] then error("Duplicate userdata type index " .. typeIndex, 0) end
                userdataTypes[typeIndex] = stringAt(strings, reader:VarUInt())
            end
        end

        local prototypeCount = reader:VarUInt()
        checkCount(reader, prototypeCount, "Prototype", version >= 12 and 2 or 1)
        if prototypeCount == 0 then error("Bytecode contains no prototypes.", 0) end

        local prototypes = {}
        local hasUnknownProtoData = false
        for index = 1, prototypeCount do
            local declaredSize
            if version >= 12 then
                declaredSize = reader:VarUInt()
                if declaredSize > reader:Remaining() then
                    error(("Prototype %d size exceeds the remaining bytecode."):format(index - 1), 0)
                end
            end

            local protoStart = reader.Position
            local proto = parsePrototype(reader, strings, version)
            if declaredSize then
                local consumed = reader.Position - protoStart
                if consumed > declaredSize then
                    error(("Prototype %d exceeded its declared byte size."):format(index - 1), 0)
                end
                proto.SerializedSize = declaredSize
                proto.KnownSerializedSize = consumed
                if consumed < declaredSize then
                    proto.UnknownSerializedData = reader:Bytes(declaredSize - consumed)
                    hasUnknownProtoData = true
                end
            end
            prototypes[index] = proto
        end

        for _, proto in ipairs(prototypes) do
            validateConstantReferences(proto, prototypes)
        end

        local mainIndex = reader:VarUInt() + 1
        if not prototypes[mainIndex] then error("Main prototype index is out of range.", 0) end
        if reader:Remaining() ~= 0 then
            error(("Trailing bytecode data remains at offset %d."):format(reader.Position - 1), 0)
        end

        return {
            Version = version,
            TypesVersion = typesVersion,
            Strings = strings,
            UserdataTypes = userdataTypes,
            Prototypes = prototypes,
            MainIndex = mainIndex,
            HasUnknownProtoData = hasUnknownProtoData,
            BytesConsumed = reader.Position - 1,
            ByteLength = #data,
        }
    end)

    if ok then return result end
    return nil, tostring(result)
end

BytecodeReader.MinimumVersion = MIN_VERSION
BytecodeReader.MaximumVersion = MAX_VERSION
BytecodeReader.ConstantType = ConstantType

return BytecodeReader