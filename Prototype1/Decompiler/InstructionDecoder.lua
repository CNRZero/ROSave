local InstructionDecoder = {}

local OpcodeNames = {
    [0] = "NOP", "BREAK", "LOADNIL", "LOADB", "LOADN", "LOADK", "MOVE",
    "GETGLOBAL", "SETGLOBAL", "GETUPVAL", "SETUPVAL", "CLOSEUPVALS", "GETIMPORT",
    "GETTABLE", "SETTABLE", "GETTABLEKS", "SETTABLEKS", "GETTABLEN", "SETTABLEN",
    "NEWCLOSURE", "NAMECALL", "CALL", "RETURN", "JUMP", "JUMPBACK", "JUMPIF",
    "JUMPIFNOT", "JUMPIFEQ", "JUMPIFLE", "JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE",
    "JUMPIFNOTLT", "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "ADDK", "SUBK",
    "MULK", "DIVK", "MODK", "POWK", "AND", "OR", "ANDK", "ORK", "CONCAT",
    "NOT", "MINUS", "LENGTH", "NEWTABLE", "DUPTABLE", "SETLIST", "FORNPREP",
    "FORNLOOP", "FORGLOOP", "FORGPREP_INEXT", "DEP_FORGLOOP_INEXT", "FORGPREP_NEXT",
    "DEP_FORGLOOP_NEXT", "GETVARARGS", "DUPCLOSURE", "PREPVARARGS", "LOADKX",
    "JUMPX", "FASTCALL", "COVERAGE", "CAPTURE", "SUBRK", "DIVRK", "FASTCALL1",
    "FASTCALL2", "FASTCALL2K", "FORGPREP", "JUMPXEQKNIL", "JUMPXEQKB",
    "JUMPXEQKN", "JUMPXEQKS", "IDIV", "IDIVK", "FASTCALL3",
}

local HasAux = {
    GETGLOBAL = true, SETGLOBAL = true, GETIMPORT = true, GETTABLEKS = true,
    SETTABLEKS = true, NAMECALL = true, JUMPIFEQ = true, JUMPIFLE = true,
    JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
    NEWTABLE = true, SETLIST = true, FORGLOOP = true, LOADKX = true,
    FASTCALL2 = true, FASTCALL2K = true, FASTCALL3 = true, JUMPXEQKNIL = true,
    JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
}

local JumpD = {
    JUMP = true, JUMPBACK = true, JUMPIF = true, JUMPIFNOT = true,
    JUMPIFEQ = true, JUMPIFLE = true, JUMPIFLT = true, JUMPIFNOTEQ = true,
    JUMPIFNOTLE = true, JUMPIFNOTLT = true, FORNPREP = true, FORNLOOP = true,
    FORGPREP = true, FORGLOOP = true, FORGPREP_INEXT = true, FORGPREP_NEXT = true,
    JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
}

local function signed(value, threshold, modulus)
    return value >= threshold and value - modulus or value
end

function InstructionDecoder.DecodeWords(words)
    local instructions, byPC = {}, {}
    local index = 1
    while index <= #words do
        local word = words[index]
        local opcode = word % 256
        local name = OpcodeNames[opcode]
        if not name then
            return nil, ("Unknown opcode %d at word %d."):format(opcode, index - 1)
        end

        local instruction = {
            PC = index - 1,
            Opcode = opcode,
            Op = name,
            A = math.floor(word / 256) % 256,
            B = math.floor(word / 65536) % 256,
            C = math.floor(word / 16777216) % 256,
            D = signed(math.floor(word / 65536) % 65536, 32768, 65536),
            E = signed(math.floor(word / 256) % 16777216, 8388608, 16777216),
            Word = word,
            Length = HasAux[name] and 2 or 1,
        }
        if instruction.Length == 2 then
            if index == #words then return nil, "Missing AUX word after " .. name end
            instruction.Aux = words[index + 1]
        end
        if JumpD[name] then
            instruction.Target = instruction.PC + instruction.D + 1
        elseif name == "JUMPX" then
            instruction.Target = instruction.PC + instruction.E + 1
        elseif name == "LOADB" and instruction.C ~= 0 then
            instruction.Target = instruction.PC + instruction.C + 1
        end

        instructions[#instructions + 1] = instruction
        byPC[instruction.PC] = instruction
        index = index + instruction.Length
    end
    return { Instructions = instructions, ByPC = byPC }
end

InstructionDecoder.OpcodeNames = OpcodeNames
InstructionDecoder.HasAux = HasAux

return InstructionDecoder
