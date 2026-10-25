local ControlFlow = {}

local Conditional = {
    JUMPIF = true, JUMPIFNOT = true, JUMPIFEQ = true, JUMPIFLE = true,
    JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
    JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
}

local function predecessor(instructions, pc)
    local previous
    for _, instruction in ipairs(instructions) do
        if instruction.PC >= pc then break end
        previous = instruction
    end
    return previous
end

function ControlFlow.Analyze(decoded)
    local instructions = decoded.Instructions
    local blocks = { { StartPC = 0, Instructions = {} } }
    local boundaries = { [0] = true }

    for _, instruction in ipairs(instructions) do
        if instruction.Target then boundaries[instruction.Target] = true end
        if Conditional[instruction.Op] then boundaries[instruction.PC + instruction.Length] = true end
    end

    blocks = {}
    local current
    for _, instruction in ipairs(instructions) do
        if boundaries[instruction.PC] or not current then
            current = { StartPC = instruction.PC, Instructions = {}, Successors = {} }
            blocks[#blocks + 1] = current
        end
        current.Instructions[#current.Instructions + 1] = instruction
    end

    local blockByPC = {}
    for _, block in ipairs(blocks) do blockByPC[block.StartPC] = block end
    for blockIndex, block in ipairs(blocks) do
        local last = block.Instructions[#block.Instructions]
        if last.Target and blockByPC[last.Target] then block.Successors[#block.Successors + 1] = last.Target end
        if Conditional[last.Op] and blocks[blockIndex + 1] then
            block.Successors[#block.Successors + 1] = blocks[blockIndex + 1].StartPC
        elseif not (last.Op == "RETURN" or last.Op == "JUMP" or last.Op == "JUMPBACK" or last.Op == "JUMPX")
            and blocks[blockIndex + 1] then
            block.Successors[#block.Successors + 1] = blocks[blockIndex + 1].StartPC
        end
    end

    local regions = {}
    for _, instruction in ipairs(instructions) do
        if Conditional[instruction.Op] and instruction.Target and instruction.Target > instruction.PC then
            local beforeTarget = predecessor(instructions, instruction.Target)
            if beforeTarget and beforeTarget.Op == "JUMPBACK" and beforeTarget.Target <= instruction.PC then
                regions[#regions + 1] = {
                    Kind = "While", StartPC = instruction.PC, EndPC = instruction.Target,
                    ClosingJumpPC = beforeTarget.PC,
                }
            elseif beforeTarget and beforeTarget.Op == "JUMP" and beforeTarget.Target > instruction.Target then
                regions[#regions + 1] = {
                    Kind = "IfElse", StartPC = instruction.PC, ElsePC = instruction.Target,
                    EndPC = beforeTarget.Target, ClosingJumpPC = beforeTarget.PC,
                }
            else
                regions[#regions + 1] = {
                    Kind = "If", StartPC = instruction.PC, EndPC = instruction.Target,
                }
            end
        end
    end

    return { Blocks = blocks, BlockByPC = blockByPC, Regions = regions }
end

ControlFlow.Conditional = Conditional

return ControlFlow
