local Decompiler = {}

local function indentLines(lines, depth)
    local prefix = string.rep("\t", depth)
    local output = {}
    for _, line in ipairs(lines) do output[#output + 1] = prefix .. line end
    return output
end

function Decompiler.Decompile(modules, bytecode, quality)
    local parsed, parseError = modules.BytecodeReader.Parse(bytecode)
    if not parsed then
        return { Status = "failed", Error = parseError, Source = "-- Bytecode parse failed: " .. tostring(parseError) .. "\n" }
    end

    local decoded = {}
    for index, proto in ipairs(parsed.Prototypes) do
        local value, decodeError = modules.InstructionDecoder.DecodeWords(proto.Words)
        if not value then
            return { Status = "failed", Error = decodeError, Source = "-- Instruction decode failed: " .. tostring(decodeError) .. "\n" }
        end
        decoded[index] = value
    end

    local childNames = {}
    for index = 1, #parsed.Prototypes do childNames[index] = "function_" .. index end

    local source = {
        "-- Recovered by ROSave Prototype 0.1.0",
        "-- Deterministic reconstruction; review partial-recovery comments before use.",
    }
    local partial, unsupported = false, 0

    if #parsed.Prototypes > 1 then
        local declarations = {}
        for index = 1, #parsed.Prototypes do
            if index ~= parsed.MainIndex then declarations[#declarations + 1] = childNames[index] end
        end
        if #declarations > 0 then source[#source + 1] = "local " .. table.concat(declarations, ", ") end
    end

    for index, proto in ipairs(parsed.Prototypes) do
        if index ~= parsed.MainIndex then
            local flow = modules.ControlFlow.Analyze(decoded[index])
            local body, wasPartial, count = modules.StatementBuilder.Build(modules, proto, decoded[index], flow, quality, childNames)
            partial = partial or wasPartial
            unsupported = unsupported + count

            local args = {}
            for param = 0, proto.NumParams - 1 do args[#args + 1] = "arg" .. param end
            if proto.IsVararg then args[#args + 1] = "..." end
            source[#source + 1] = ("%s = function(%s)"):format(childNames[index], table.concat(args, ", "))
            local nested = indentLines(body, 1)
            for _, line in ipairs(nested) do source[#source + 1] = line end
            source[#source + 1] = "end"
        end
    end

    local main = parsed.Prototypes[parsed.MainIndex]
    local mainFlow = modules.ControlFlow.Analyze(decoded[parsed.MainIndex])
    local mainBody, mainPartial, mainUnsupported = modules.StatementBuilder.Build(
        modules, main, decoded[parsed.MainIndex], mainFlow, quality, childNames)
    partial = partial or mainPartial
    unsupported = unsupported + mainUnsupported
    for _, line in ipairs(mainBody) do source[#source + 1] = line end

    return {
        Status = partial and "partial" or "success",
        Source = table.concat(source, "\n") .. "\n",
        BytecodeVersion = parsed.Version,
        PrototypeCount = #parsed.Prototypes,
        UnsupportedInstructions = unsupported,
    }
end

return Decompiler
