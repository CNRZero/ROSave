local Fixture = {}

local function byte(value) return string.char(value % 256) end

local function u32(value)
    return byte(value) .. byte(math.floor(value / 256)) .. byte(math.floor(value / 65536))
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

function Fixture.PrintHello()
    local chunks = {
        byte(4), byte(2), -- bytecode and type-info versions
        varuint(2), varuint(5), "print", varuint(5), "hello",
        varuint(1), -- prototype count
        byte(2), byte(0), byte(0), byte(0), -- stack, params, upvalues, vararg
        byte(0), varuint(0), -- flags and type info
        varuint(5),
        u32(abc(7, 0, 0, 0)), u32(0), -- GETGLOBAL v0, constant 0
        u32(ad(5, 1, 1)), -- LOADK v1, constant 1
        u32(abc(21, 0, 2, 1)), -- CALL v0(v1), no results
        u32(abc(22, 0, 1, 0)), -- RETURN
        varuint(2), byte(3), varuint(1), byte(3), varuint(2),
        varuint(0), -- children
        varuint(0), varuint(0), -- line defined, debug name
        byte(0), byte(0), -- no line/debug info
        varuint(0), -- main prototype index
    }
    return table.concat(chunks)
end

return Fixture
