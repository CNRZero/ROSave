local InstructionDecoder = {}

-- Numeric order is the ABI order from upstream Luau Bytecode.h.
-- Slots 60 and 62 were reclaimed from instructions removed by bytecode v3.
local OpcodeNames = {
    [0] = "NOP",
    "BREAK",
    "LOADNIL",
    "LOADB",
    "LOADN",
    "LOADK",
    "MOVE",
    "GETGLOBAL",
    "SETGLOBAL",
    "GETUPVAL",
    "SETUPVAL",
    "CLOSEUPVALS",
    "GETIMPORT",
    "GETTABLE",
    "SETTABLE",
    "GETTABLEKS",
    "SETTABLEKS",
    "GETTABLEN",
    "SETTABLEN",
    "NEWCLOSURE",
    "NAMECALL",
    "CALL",
    "RETURN",
    "JUMP",
    "JUMPBACK",
    "JUMPIF",
    "JUMPIFNOT",
    "JUMPIFEQ",
    "JUMPIFLE",
    "JUMPIFLT",
    "JUMPIFNOTEQ",
    "JUMPIFNOTLE",
    "JUMPIFNOTLT",
    "ADD",
    "SUB",
    "MUL",
    "DIV",
    "MOD",
    "POW",
    "ADDK",
    "SUBK",
    "MULK",
    "DIVK",
    "MODK",
    "POWK",
    "AND",
    "OR",
    "ANDK",
    "ORK",
    "CONCAT",
    "NOT",
    "MINUS",
    "LENGTH",
    "NEWTABLE",
    "DUPTABLE",
    "SETLIST",
    "FORNPREP",
    "FORNLOOP",
    "FORGLOOP",
    "FORGPREP_INEXT",
    "FASTCALL3",
    "FORGPREP_NEXT",
    "NATIVECALL",
    "GETVARARGS",
    "DUPCLOSURE",
    "PREPVARARGS",
    "LOADKX",
    "JUMPX",
    "FASTCALL",
    "COVERAGE",
    "CAPTURE",
    "SUBRK",
    "DIVRK",
    "FASTCALL1",
    "FASTCALL2",
    "FASTCALL2K",
    "FORGPREP",
    "JUMPXEQKNIL",
    "JUMPXEQKB",
    "JUMPXEQKN",
    "JUMPXEQKS",
    "IDIV",
    "IDIVK",
    "GETUDATAKS",
    "SETUDATAKS",
    "NAMECALLUDATA",
    "NEWCLASSMEMBER",
    "CALLFB",
    "CMPPROTO",
    "FASTPCALL",
}

local MinimumVersion = {
    FASTCALL3 = 6,
    SUBRK = 5,
    DIVRK = 5,
    FORGPREP = 3,
    JUMPXEQKNIL = 3,
    JUMPXEQKB = 3,
    JUMPXEQKN = 3,
    JUMPXEQKS = 3,
    IDIV = 4,
    IDIVK = 4,
    GETUDATAKS = 9,
    SETUDATAKS = 9,
    NAMECALLUDATA = 9,
    NEWCLASSMEMBER = 10,
    CALLFB = 11,
    CMPPROTO = 11,
    FASTPCALL = 14,
}

local HasAux = {
    GETGLOBAL = true,
    SETGLOBAL = true,
    GETIMPORT = true,
    GETTABLEKS = true,
    SETTABLEKS = true,
    NAMECALL = true,
    JUMPIFEQ = true,
    JUMPIFLE = true,
    JUMPIFLT = true,
    JUMPIFNOTEQ = true,
    JUMPIFNOTLE = true,
    JUMPIFNOTLT = true,
    NEWTABLE = true,
    SETLIST = true,
    FORGLOOP = true,
    LOADKX = true,
    FASTCALL2 = true,
    FASTCALL2K = true,
    FASTCALL3 = true,
    JUMPXEQKNIL = true,
    JUMPXEQKB = true,
    JUMPXEQKN = true,
    JUMPXEQKS = true,
    GETUDATAKS = true,
    SETUDATAKS = true,
    NAMECALLUDATA = true,
    NEWCLASSMEMBER = true,
    CALLFB = true,
    CMPPROTO = true,
}

local JumpD = {
    JUMP = true,
    JUMPBACK = true,
    JUMPIF = true,
    JUMPIFNOT = true,
    JUMPIFEQ = true,
    JUMPIFLE = true,
    JUMPIFLT = true,
    JUMPIFNOTEQ = true,
    JUMPIFNOTLE = true,
    JUMPIFNOTLT = true,
    FORNPREP = true,
    FORNLOOP = true,
    FORGPREP = true,
    FORGLOOP = true,
    FORGPREP_INEXT = true,
    FORGPREP_NEXT = true,
    JUMPXEQKNIL = true,
    JUMPXEQKB = true,
    JUMPXEQKN = true,
    JUMPXEQKS = true,
    CMPPROTO = true,
}

local FastCall = {
    FASTCALL = true,
    FASTCALL1 = true,
    FASTCALL2 = true,
    FASTCALL2K = true,
    FASTCALL3 = true,
    FASTPCALL = true,
}

local function signed(value, threshold, modulus)
    return value >= threshold and value - modulus or value
end

local function validateTarget(instruction, byPC, wordCount)
    if not instruction.Target then return nil end
    if instruction.Target < 0 or instruction.Target > wordCount then
        return ("%s at pc %d jumps outside the instruction stream to pc %d.")
            :format(instruction.Op, instruction.PC, instruction.Target)
    end
    if instruction.Target ~= wordCount and not byPC[instruction.Target] then
        return ("%s at pc %d jumps into an AUX word at pc %d.")
            :format(instruction.Op, instruction.PC, instruction.Target)
    end
    return nil
end

function InstructionDecoder.DecodeWords(words, version)
    version = version or 14
    if type(version) ~= "number" or version < 3 or version > 14 then
        return nil, "Instruction decoding requires bytecode version 3 through 14."
    end

    local instructions, byPC = {}, {}
    local index = 1
    while index <= #words do
        local word = words[index]
        if type(word) ~= "number" then
            return nil, ("Instruction word %d is not numeric."):format(index - 1)
        end

        local opcode = word % 256
        local name = OpcodeNames[opcode]
        if not name then
            return nil, ("Unknown opcode %d at word %d; its length cannot be decoded safely."):format(opcode, index - 1)
        end

        local minimumVersion = MinimumVersion[name]
        if minimumVersion and version < minimumVersion then
            return nil, ("%s at word %d requires bytecode version %d.")
                :format(name, index - 1, minimumVersion)
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
            if index == #words then
                return nil, ("Missing AUX word after %s at pc %d."):format(name, instruction.PC)
            end
            instruction.Aux = words[index + 1]
            if type(instruction.Aux) ~= "number" then
                return nil, ("AUX word after %s at pc %d is not numeric."):format(name, instruction.PC)
            end
        end

        if JumpD[name] then
            instruction.Target = instruction.PC + instruction.D + 1
            instruction.TargetKind = "jump"
        elseif name == "JUMPX" then
            instruction.Target = instruction.PC + instruction.E + 1
            instruction.TargetKind = "jump"
        elseif FastCall[name] then
            instruction.CallPC = instruction.PC + instruction.C + 1
            instruction.Target = instruction.PC + instruction.C + 2
            instruction.TargetKind = "fastcall-skip"
        elseif name == "LOADB" and instruction.C ~= 0 then
            instruction.Target = instruction.PC + instruction.C + 1
            instruction.TargetKind = "skip"
        end

        if name == "GETUDATAKS" or name == "SETUDATAKS" or name == "NAMECALLUDATA" then
            instruction.AuxConstant = instruction.Aux % 65536
            instruction.AuxSlot = math.floor(instruction.Aux / 65536)
        elseif name == "CALLFB" then
            instruction.FeedbackSlot = instruction.Aux
        elseif name == "CMPPROTO" then
            instruction.ProtoId = instruction.Aux
        elseif name == "JUMPXEQKNIL" or name == "JUMPXEQKB"
            or name == "JUMPXEQKN" or name == "JUMPXEQKS" then
            instruction.AuxNot = math.floor(instruction.Aux / 2147483648) % 2 == 1
            instruction.AuxConstant = instruction.Aux % 16777216
        end

        instructions[#instructions + 1] = instruction
        byPC[instruction.PC] = instruction
        index = index + instruction.Length
    end

    for _, instruction in ipairs(instructions) do
        local targetError = validateTarget(instruction, byPC, #words)
        if targetError then return nil, targetError end

        if instruction.CallPC then
            local call = byPC[instruction.CallPC]
            if not call or (call.Op ~= "CALL" and call.Op ~= "CALLFB") then
                return nil, ("%s at pc %d does not point to a following CALL.")
                    :format(instruction.Op, instruction.PC)
            end
            if instruction.Op == "FASTPCALL" and call.Op ~= "CALL" then
                return nil, ("FASTPCALL at pc %d must point to CALL, not %s.")
                    :format(instruction.PC, call.Op)
            end
        end
    end

    return {
        Instructions = instructions,
        ByPC = byPC,
        WordCount = #words,
        Version = version,
    }
end

InstructionDecoder.OpcodeNames = OpcodeNames
InstructionDecoder.MinimumVersion = MinimumVersion
InstructionDecoder.HasAux = HasAux

return InstructionDecoder