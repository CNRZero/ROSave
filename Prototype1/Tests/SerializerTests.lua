return function(harness)
    local modules = { BinaryEncoding = require("../Serialization/BinaryEncoding") }
    local serializer = require("../Serialization/Serializer")
    local validator = require("../Serialization/Validator")
    local logger = { Warn = function() end }

    harness.test("base64 encoder matches RFC 4648 examples", function()
        harness.equal(modules.BinaryEncoding.Base64("Man"), "TWFu")
        harness.equal(modules.BinaryEncoding.Base64("Ma"), "TWE=")
        harness.equal(modules.BinaryEncoding.Base64("M"), "TQ==")
    end)

    harness.test("serializer escapes XML and splits CDATA terminators", function()
        local rootRecord = {
            Id = "RBX_ROOT_1", ClassName = "Folder", Name = "A&B",
            Properties = {
                { Name = "Name", Hint = "String", Value = "A&B" },
                { Name = "Source", Hint = "ProtectedString", Value = "return \"x]]>y\"" },
            },
            Attributes = { Enabled = true, Owner = "test" }, Tags = { "One", "Two" }, Children = {},
        }
        local project = { Roots = { rootRecord }, Records = { rootRecord } }
        local xml = serializer.Serialize(modules, project, logger, "0.1.0")
        harness.contains(xml, "A&amp;B")
        harness.contains(xml, "]]]]><![CDATA[>")
        harness.contains(xml, "AttributesSerialize")
        local valid, errors = validator.ValidateXml(xml, 1)
        harness.truthy(valid, table.concat(errors, "; "))
    end)
end
