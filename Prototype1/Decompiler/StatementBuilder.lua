local StatementBuilder = {}

function StatementBuilder.Build(modules, proto, decoded, flow, quality, childNames)
    local expressionBuilder = modules.ExpressionBuilder
    local starts, elseAt, ends, skipped = {}, {}, {}, {}
    if quality ~= "Fast" then
        for _, region in ipairs(flow.Regions) do
            if not starts[region.StartPC] then
                starts[region.StartPC] = region
                ends[region.EndPC] = (ends[region.EndPC] or 0) + 1
                if region.ElsePC then elseAt[region.ElsePC] = true end
                if region.ClosingJumpPC then skipped[region.ClosingJumpPC] = true end
            end
        end
    end

    local output, indent, partial, unsupported = {}, 0, false, 0
    local function emit(line)
        output[#output + 1] = string.rep("\t", indent) .. line
    end

    if proto.MaxStackSize > 0 then
        local registers = {}
        for index = 0, proto.MaxStackSize - 1 do registers[#registers + 1] = expressionBuilder.Register(index) end
        emit("local " .. table.concat(registers, ", "))
        if proto.NumParams > 0 then
            local params, targets = {}, {}
            for index = 0, proto.NumParams - 1 do
                params[#params + 1] = "arg" .. index
                targets[#targets + 1] = expressionBuilder.Register(index)
            end
            emit(table.concat(targets, ", ") .. " = " .. table.concat(params, ", "))
        end
    end

    for _, instruction in ipairs(decoded.Instructions) do
        if elseAt[instruction.PC] then
            indent = math.max(0, indent - 1)
            emit("else")
            indent = indent + 1
        elseif ends[instruction.PC] then
            for _ = 1, ends[instruction.PC] do
                indent = math.max(0, indent - 1)
                emit("end")
            end
        end

        local region = starts[instruction.PC]
        if region then
            local condition = expressionBuilder.Condition(proto, instruction)
            emit((region.Kind == "While" and "while " or "if ") .. condition
                .. (region.Kind == "While" and " do" or " then"))
            indent = indent + 1
        elseif not skipped[instruction.PC] then
            local lines, wasPartial = expressionBuilder.Render(proto, instruction, childNames)
            for _, line in ipairs(lines) do emit(line) end
            if wasPartial then partial, unsupported = true, unsupported + 1 end
        end
    end

    while indent > 0 do
        indent = indent - 1
        emit("end")
        partial = true
    end
    return output, partial, unsupported
end

return StatementBuilder
