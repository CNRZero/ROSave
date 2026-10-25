--!nolint DeprecatedApi
return function(harness)
    local modules = {
        BytecodeReader = require("../Decompiler/BytecodeReader"),
        InstructionDecoder = require("../Decompiler/InstructionDecoder"),
        ControlFlow = require("../Decompiler/ControlFlow"),
        ExpressionBuilder = require("../Decompiler/ExpressionBuilder"),
        StatementBuilder = require("../Decompiler/StatementBuilder"),
    }
    modules.Decompiler = require("../Decompiler/Decompiler")

    local fixture = require("./ModernBytecodeFixture")

    local function decodeMain(bytecode)
        local parsed = assert(modules.BytecodeReader.Parse(bytecode))
        local proto = parsed.Prototypes[parsed.MainIndex]
        return parsed, assert(modules.InstructionDecoder.DecodeWords(proto.Words, parsed.Version))
    end

    local function findInstruction(decoded, name)
        for _, instruction in ipairs(decoded.Instructions) do
            if instruction.Op == name then return instruction end
        end
        return nil
    end

    local function validateSource(source)
        local chunk, compileError = getfenv(0).loadstring(source, "@RecoveredV14")
        harness.truthy(chunk, compileError)
    end

    harness.test("bytecode reader accepts every standard version from 3 through 14", function()
        for version = 3, 14 do
            local parsed, readError = modules.BytecodeReader.Parse(fixture.Minimal(version))
            harness.truthy(parsed, ("v%d: %s"):format(version, tostring(readError)))
            harness.equal(parsed.Version, version)
            harness.equal(parsed.BytesConsumed, parsed.ByteLength)
        end
    end)

    harness.test("v9 userdata field opcodes decode their split AUX data", function()
        local parsed, decoded = decodeMain(fixture.UserdataV9())
        harness.equal(parsed.Version, 9)
        local instruction = decoded.Instructions[1]
        harness.equal(instruction.Op, "GETUDATAKS")
        harness.equal(instruction.Length, 2)
        harness.equal(instruction.AuxConstant, 0)
        harness.equal(instruction.AuxSlot, 7)
    end)

    harness.test("v10 class-shape constants and NEWCLASSMEMBER are parsed", function()
        local parsed, decoded = decodeMain(fixture.ClassShapeV10())
        local shape = parsed.Prototypes[1].Constants[4]
        harness.equal(shape.Type, "ClassShape")
        harness.equal(shape.Value.PropertyCount, 1)
        harness.equal(shape.Value.MethodNames[1], 2)
        harness.equal(decoded.Instructions[1].Op, "NEWCLASSMEMBER")

        local result = modules.Decompiler.Decompile(modules, fixture.ClassShapeV10(), "Balanced")
        harness.equal(result.Status, "partial")
        harness.contains(result.Source, "unsupported class member definition")
        validateSource(result.Source)
    end)

    harness.test("v11 feedback vectors, CALLFB, and CMPPROTO retain alignment", function()
        local parsed, decoded = decodeMain(fixture.FeedbackV11())
        local proto = parsed.Prototypes[1]
        harness.equal(#proto.FeedbackSlots, 1)
        harness.equal(proto.FeedbackSlots[1].Type, "CallTarget")
        harness.equal(proto.FeedbackSlots[1].Value, 2)
        harness.equal(findInstruction(decoded, "CALLFB").FeedbackSlot, 0)
        harness.equal(findInstruction(decoded, "CMPPROTO").ProtoId, 42)
    end)

    harness.test("v12 sized prototypes parse cost and preserve extensions", function()
        local parsed = assert(modules.BytecodeReader.Parse(fixture.SizedV12()))
        harness.equal(parsed.Prototypes[1].Cost, 321)
        harness.equal(parsed.Prototypes[1].SerializedSize, parsed.Prototypes[1].KnownSerializedSize)

        local extended = assert(modules.BytecodeReader.Parse(fixture.SizedV12("\1\2")))
        harness.truthy(extended.HasUnknownProtoData)
        harness.equal(#extended.Prototypes[1].UnknownSerializedData, 2)
        local result = modules.Decompiler.Decompile(modules, fixture.SizedV12("\1\2"), "Balanced")
        harness.equal(result.Status, "partial")
        validateSource(result.Source)
    end)

    harness.test("v13 double-precision vector constants retain their values", function()
        local parsed = assert(modules.BytecodeReader.Parse(fixture.VectorDoubleV13()))
        local constant = parsed.Prototypes[1].Constants[1]
        harness.equal(constant.Type, "VectorDouble")
        harness.equal(constant.Value[1], 1.5)
        harness.equal(constant.Value[2], -2.25)
        harness.equal(constant.Value[3], 3.125)
    end)

    harness.test("v14 FASTPCALL uses the official opcode and has no AUX word", function()
        local parsed, decoded = decodeMain(fixture.PipelineV14())
        harness.equal(parsed.Version, 14)
        harness.equal(#parsed.Prototypes, 2)
        local fastpcall = findInstruction(decoded, "FASTPCALL")
        harness.truthy(fastpcall)
        harness.equal(fastpcall.Opcode, 89)
        harness.equal(fastpcall.Length, 1)
        harness.equal(fastpcall.CallPC, 6)
        harness.equal(fastpcall.Target, 7)
    end)

    harness.test("FASTCALL3 uses its reclaimed official opcode slot from v6 onward", function()
        local words = {
            fixture.ABC(60, 1, 2, 1),
            3 + 4 * 256,
            fixture.ABC(21, 0, 1, 1),
            fixture.ABC(22, 0, 1, 0),
        }
        local decoded, decodeError = modules.InstructionDecoder.DecodeWords(words, 14)
        harness.truthy(decoded, decodeError)
        harness.equal(decoded.Instructions[1].Op, "FASTCALL3")
        harness.equal(decoded.Instructions[1].Length, 2)

        local oldDecoded, oldError = modules.InstructionDecoder.DecodeWords(words, 5)
        harness.equal(oldDecoded, nil)
        harness.contains(oldError, "requires bytecode version 6")
    end)

    harness.test("v14 closures, captures, calls, and upvalues complete the source pipeline", function()
        local result = modules.Decompiler.Decompile(modules, fixture.PipelineV14(), "Balanced")
        local repeated = modules.Decompiler.Decompile(modules, fixture.PipelineV14(), "Balanced")
        harness.equal(result.Status, "success", result.Error)
        harness.equal(result.Source, repeated.Source)
        harness.contains(result.Source, "function_1 = function")
        harness.contains(result.Source, "upvalue_1")
        harness.contains(result.Source, "FASTPCALL optimization")
        harness.contains(result.Source, "v0(v1)")
        validateSource(result.Source)
    end)

    harness.test("v14 branches and while loops generate valid Luau", function()
        local result = modules.Decompiler.Decompile(modules, fixture.ControlFlowV14(), "Balanced")
        harness.equal(result.Status, "success", result.Error)
        harness.contains(result.Source, "if v0 then")
        harness.contains(result.Source, "while v0 do")
        validateSource(result.Source)
    end)

    harness.test("v14 numeric loop boundaries remain parseable as partial output", function()
        local _parsed, decoded = decodeMain(fixture.LoopsV14())
        harness.equal(findInstruction(decoded, "FORNPREP").Target, 5)
        harness.equal(findInstruction(decoded, "FORNLOOP").Target, 3)

        local result = modules.Decompiler.Decompile(modules, fixture.LoopsV14(), "Balanced")
        harness.equal(result.Status, "partial")
        harness.contains(result.Source, "FORNPREP")
        validateSource(result.Source)
    end)

    harness.test("official compiler v14 sample parses and validates end to end", function()
        local bytecode = fixture.OfficialV14()
        local parsed, readError = modules.BytecodeReader.Parse(bytecode)
        harness.truthy(parsed, readError)
        harness.equal(parsed.Version, 14)
        harness.equal(parsed.ByteLength, 315)

        local sawFastPcall = false
        for _, proto in ipairs(parsed.Prototypes) do
            local decoded, decodeError = modules.InstructionDecoder.DecodeWords(proto.Words, parsed.Version)
            harness.truthy(decoded, decodeError)
            sawFastPcall = sawFastPcall or findInstruction(decoded, "FASTPCALL") ~= nil
        end
        harness.truthy(sawFastPcall, "official v14 fixture did not contain FASTPCALL")

        local result = modules.Decompiler.Decompile(modules, bytecode, "Balanced")
        harness.truthy(result.Status == "success" or result.Status == "partial", result.Error)
        validateSource(result.Source)
    end)

    harness.test("version-gated opcodes and malformed bytecode are rejected safely", function()
        local v14 = fixture.PipelineV14()
        local v13WithFastPcall = string.char(13) .. v14:sub(2)
        local result = modules.Decompiler.Decompile(modules, v13WithFastPcall, "Fast")
        harness.equal(result.Status, "failed")
        harness.contains(result.Error, "FASTPCALL")

        local malformed, malformedError = modules.BytecodeReader.Parse(fixture.MalformedV14())
        harness.equal(malformed, nil)
        harness.truthy(malformedError)

        local unknown = modules.Decompiler.Decompile(modules, fixture.UnknownOpcodeV14(), "Fast")
        harness.equal(unknown.Status, "failed")
        harness.contains(unknown.Error, "length cannot be decoded safely")

        local decoded, auxError = modules.InstructionDecoder.DecodeWords({ 83 }, 14)
        harness.equal(decoded, nil)
        harness.contains(auxError, "Missing AUX")
    end)
end
