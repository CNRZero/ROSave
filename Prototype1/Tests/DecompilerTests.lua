return function(harness)
    local modules = {
        BytecodeReader = require("../Decompiler/BytecodeReader"),
        InstructionDecoder = require("../Decompiler/InstructionDecoder"),
        ControlFlow = require("../Decompiler/ControlFlow"),
        ExpressionBuilder = require("../Decompiler/ExpressionBuilder"),
        StatementBuilder = require("../Decompiler/StatementBuilder"),
    }
    modules.Decompiler = require("../Decompiler/Decompiler")
    local fixture = require("./BytecodeFixture")

    harness.test("bytecode reader parses a standard v4 prototype", function()
        local parsed, readError = modules.BytecodeReader.Parse(fixture.PrintHello())
        harness.truthy(parsed, readError)
        harness.equal(parsed.Version, 4)
        harness.equal(#parsed.Prototypes, 1)
        harness.equal(#parsed.Prototypes[1].Words, 5)
    end)

    harness.test("instruction decoder accounts for AUX words", function()
        local parsed = assert(modules.BytecodeReader.Parse(fixture.PrintHello()))
        local decoded = assert(modules.InstructionDecoder.DecodeWords(parsed.Prototypes[1].Words))
        harness.equal(#decoded.Instructions, 4)
        harness.equal(decoded.Instructions[1].Op, "GETGLOBAL")
        harness.equal(decoded.Instructions[2].PC, 2)
    end)

    harness.test("decompiler produces deterministic Luau", function()
        local first = modules.Decompiler.Decompile(modules, fixture.PrintHello(), "Balanced")
        local second = modules.Decompiler.Decompile(modules, fixture.PrintHello(), "Balanced")
        harness.equal(first.Status, "success", first.Error)
        harness.equal(first.Source, second.Source)
        harness.contains(first.Source, "v0 = print")
        harness.contains(first.Source, 'v1 = "hello"')
        harness.contains(first.Source, "v0(v1)")
    end)

    harness.test("unknown bytecode versions fail explicitly", function()
        local result = modules.Decompiler.Decompile(modules, string.char(99), "Fast")
        harness.equal(result.Status, "failed")
        harness.contains(result.Error, "Unsupported Luau bytecode version")
    end)
end
