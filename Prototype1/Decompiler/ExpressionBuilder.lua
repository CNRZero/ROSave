local ExpressionBuilder = {}

local function register(index)
    return "v" .. tostring(index)
end

local function identifier(value)
    return type(value) == "string" and value:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function quote(value)
    return string.format("%q", tostring(value))
end

local function constant(proto, index)
    local item = proto.Constants[index + 1]
    if not item then return "nil --[[ invalid constant " .. index .. " ]]", true end
    if item.Type == "Nil" then return "nil", false end
    if item.Type == "Boolean" or item.Type == "Number" then
        return tostring(item.Value), false
    end
    if item.Type == "Integer" then
        return item.Literal or tostring(item.Value), item.SourceExact == false
    end
    if item.Type == "String" then return quote(item.Value), false end
    if item.Type == "Vector" or item.Type == "VectorDouble" then
        return ("Vector3.new(%s, %s, %s)"):format(item.Value[1], item.Value[2], item.Value[3]), item.Value[4] ~= 0
    end
    if item.Type == "Table" then return "{}", true end
    if item.Type == "Closure" then return "function() end", true end
    if item.Type == "ClassShape" then return "{} --[[ class-shape constant ]]", true end
    return "nil --[[ " .. item.Type .. " constant ]]", true
end

local function constantString(proto, index)
    local item = proto.Constants[index + 1]
    return item and item.Type == "String" and item.Value or nil
end

local function importExpression(proto, constantIndex)
    local item = proto.Constants[constantIndex + 1]
    if not item or item.Type ~= "Import" then return "nil --[[ invalid import ]]", true end
    local packed = item.Value
    local count = math.floor(packed / 1073741824)
    local ids = {
        math.floor(packed / 1048576) % 1024,
        math.floor(packed / 1024) % 1024,
        packed % 1024,
    }
    local expression
    for index = 1, count do
        local name = constantString(proto, ids[index])
        if not name then return "nil --[[ invalid import path ]]", true end
        if not expression then
            expression = identifier(name) and name or ("_G[%s]"):format(quote(name))
        else
            expression = identifier(name) and (expression .. "." .. name) or (expression .. "[" .. quote(name) .. "]")
        end
    end
    return expression or "nil", expression == nil
end

local function property(base, name)
    if identifier(name) then return base .. "." .. name end
    return base .. "[" .. quote(name) .. "]"
end

local BinaryOperators = {
    ADD = "+", SUB = "-", MUL = "*", DIV = "/", MOD = "%", POW = "^", IDIV = "//",
    AND = "and", OR = "or",
}

local ConstantOperators = {
    ADDK = "+", SUBK = "-", MULK = "*", DIVK = "/", MODK = "%", POWK = "^",
    ANDK = "and", ORK = "or", IDIVK = "//",
}

function ExpressionBuilder.Condition(proto, instruction)
    local a = register(instruction.A)
    if instruction.Op == "JUMPIFNOT" then return a, false end
    if instruction.Op == "JUMPIF" then return "not " .. a, false end

    local b = register((instruction.Aux or 0) % 256)
    local operators = {
        JUMPIFEQ = "~=", JUMPIFNOTEQ = "==", JUMPIFLE = ">", JUMPIFNOTLE = "<=",
        JUMPIFLT = ">=", JUMPIFNOTLT = "<",
    }
    if operators[instruction.Op] then
        return a .. " " .. operators[instruction.Op] .. " " .. b, false
    end

    if instruction.Op == "JUMPXEQKNIL" or instruction.Op == "JUMPXEQKB"
        or instruction.Op == "JUMPXEQKN" or instruction.Op == "JUMPXEQKS" then
        local value, isPartial
        if instruction.Op == "JUMPXEQKNIL" then
            value, isPartial = "nil", false
        elseif instruction.Op == "JUMPXEQKB" then
            value, isPartial = tostring((instruction.AuxConstant or 0) % 2 ~= 0), false
        else
            value, isPartial = constant(proto, instruction.AuxConstant or 0)
        end
        local operator = instruction.AuxNot and "==" or "~="
        return a .. " " .. operator .. " " .. value, isPartial
    end

    if instruction.Op == "CMPPROTO" then
        return ("true --[[ %s matches proto id %s ]]"):format(a, tostring(instruction.ProtoId)), true
    end
    return "true --[[ unsupported branch condition " .. instruction.Op .. " ]]", true
end

function ExpressionBuilder.Render(proto, instruction, childNames)
    local op, a, b, c = instruction.Op, instruction.A, instruction.B, instruction.C
    local lines, partial = {}, false
    local function emit(line) lines[#lines + 1] = line end

    if op == "NOP" or op == "BREAK" or op == "PREPVARARGS" or op == "COVERAGE" then
        return lines, false
    elseif op == "LOADNIL" then emit(register(a) .. " = nil")
    elseif op == "LOADB" then emit(register(a) .. " = " .. tostring(b ~= 0))
    elseif op == "LOADN" then emit(register(a) .. " = " .. tostring(instruction.D))
    elseif op == "LOADK" or op == "LOADKX" then
        local value, isPartial = constant(proto, op == "LOADK" and instruction.D or instruction.Aux)
        emit(register(a) .. " = " .. value); partial = isPartial
    elseif op == "MOVE" then emit(register(a) .. " = " .. register(b))
    elseif op == "GETGLOBAL" then
        local name = constantString(proto, instruction.Aux)
        if name then emit(register(a) .. " = " .. (identifier(name) and name or ("_G[%s]"):format(quote(name))))
        else emit(register(a) .. " = nil --[[ invalid global ]]" ); partial = true end
    elseif op == "SETGLOBAL" then
        local name = constantString(proto, instruction.Aux)
        if name then emit((identifier(name) and name or ("_G[%s]"):format(quote(name))) .. " = " .. register(a))
        else emit("--[[ invalid SETGLOBAL ]]" ); partial = true end
    elseif op == "GETUPVAL" then emit(register(a) .. " = upvalue_" .. tostring(b + 1))
    elseif op == "SETUPVAL" then emit("upvalue_" .. tostring(b + 1) .. " = " .. register(a))
    elseif op == "CLOSEUPVALS" or op == "CAPTURE" then
        return lines, false
    elseif op == "GETIMPORT" then
        local value, isPartial = importExpression(proto, instruction.D)
        emit(register(a) .. " = " .. value); partial = isPartial
    elseif op == "GETTABLE" then emit(register(a) .. " = " .. register(b) .. "[" .. register(c) .. "]")
    elseif op == "SETTABLE" then emit(register(b) .. "[" .. register(c) .. "] = " .. register(a))
    elseif op == "GETTABLEKS" or op == "NAMECALL" then
        local name = constantString(proto, instruction.Aux)
        if name then
            emit(register(a) .. " = " .. property(register(b), name))
            if op == "NAMECALL" or op == "NAMECALLUDATA" then emit(register(a + 1) .. " = " .. register(b)) end
        else emit(register(a) .. " = nil --[[ invalid property ]]" ); partial = true end
    elseif op == "SETTABLEKS" then
        local name = constantString(proto, instruction.Aux)
        if name then emit(property(register(b), name) .. " = " .. register(a))
        else emit("--[[ invalid SETTABLEKS ]]" ); partial = true end
    elseif op == "GETTABLEN" then emit(register(a) .. " = " .. register(b) .. "[" .. tostring(c + 1) .. "]")
    elseif op == "SETTABLEN" then emit(register(b) .. "[" .. tostring(c + 1) .. "] = " .. register(a))
    elseif op == "NEWCLOSURE" then
        local globalIndex = proto.Protos[instruction.D + 1]
        local name = globalIndex and childNames[globalIndex + 1]
        emit(register(a) .. " = " .. (name or "function() end --[[ missing child prototype ]]") )
        partial = not name
    elseif op == "DUPCLOSURE" then
        local item = proto.Constants[instruction.D + 1]
        local name = item and item.Type == "Closure" and childNames[item.Value + 1]
        emit(register(a) .. " = " .. (name or "function() end --[[ missing closure prototype ]]") )
        partial = not name
    elseif op == "CALL" or op == "CALLFB" then
        local args = {}
        if b == 0 then partial = true else
            for index = 1, b - 1 do args[#args + 1] = register(a + index) end
        end
        local call = register(a) .. "(" .. table.concat(args, ", ") .. ")"
        if c == 1 then emit(call)
        elseif c == 0 then emit(register(a) .. " = " .. call .. " --[[ multret truncated ]]"); partial = true
        else
            local results = {}
            for index = 0, c - 2 do results[#results + 1] = register(a + index) end
            emit(table.concat(results, ", ") .. " = " .. call)
        end
    elseif op == "RETURN" then
        local values = {}
        if b == 0 then
            emit("return " .. register(a) .. " --[[ multret ]]" ); partial = true
        else
            for index = 0, b - 2 do values[#values + 1] = register(a + index) end
            emit(#values > 0 and ("return " .. table.concat(values, ", ")) or "return")
        end
    elseif BinaryOperators[op] then
        emit(register(a) .. " = " .. register(b) .. " " .. BinaryOperators[op] .. " " .. register(c))
    elseif ConstantOperators[op] then
        local value, isPartial = constant(proto, c)
        emit(register(a) .. " = " .. register(b) .. " " .. ConstantOperators[op] .. " " .. value)
        partial = isPartial
    elseif op == "SUBRK" or op == "DIVRK" then
        local value, isPartial = constant(proto, b)
        emit(register(a) .. " = " .. value .. (op == "SUBRK" and " - " or " / ") .. register(c))
        partial = isPartial
    elseif op == "CONCAT" then
        local values = {}
        for index = b, c do values[#values + 1] = register(index) end
        emit(register(a) .. " = " .. table.concat(values, " .. "))
    elseif op == "NOT" then emit(register(a) .. " = not " .. register(b))
    elseif op == "MINUS" then emit(register(a) .. " = -" .. register(b))
    elseif op == "LENGTH" then emit(register(a) .. " = #" .. register(b))
    elseif op == "NEWTABLE" or op == "DUPTABLE" then emit(register(a) .. " = {}")
    elseif op == "SETLIST" then
        local count = c == 0 and 1 or c - 1
        for index = 1, count do emit(register(a) .. "[" .. tostring((instruction.Aux or 1) + index - 1) .. "] = " .. register(b + index - 1)) end
        if c == 0 then partial = true end
    elseif op == "GETVARARGS" then
        emit(register(a) .. " = select(1, ...)")
        if b ~= 2 then partial = true end
    elseif op == "NEWCLASSMEMBER" then
        emit("--[[ unsupported class member definition ]]")
        partial = true
    elseif op:match("^FASTCALL") or op == "FASTPCALL" then
        emit("--[[ " .. op .. " optimization; following CALL retained ]]" )
    elseif op == "JUMP" or op == "JUMPBACK" or op == "JUMPX" or op == "CMPPROTO" or op:match("^FOR") or op:match("^JUMP") then
        emit(("--[[ %s to bytecode pc %s ]] "):format(tostring(op), tostring(instruction.Target)))
        partial = true
    else
        emit("--[[ unsupported opcode " .. op .. " ]]" ); partial = true
    end
    return lines, partial
end

ExpressionBuilder.Register = register

return ExpressionBuilder
