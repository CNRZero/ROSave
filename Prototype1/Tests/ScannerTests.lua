return function(harness)
    local scanner = require("../Core/Scanner")

    local function instance(className, name, children)
        local value = { ClassName = className, Name = name, Children = children or {} }
        function value:GetChildren() return self.Children end
        function value:IsA(query) return self.ClassName == query end
        function value:GetFullName() return self.Name end
        return value
    end

    harness.test("scanner counts hierarchy and scripts once", function()
        local localScript = instance("LocalScript", "Client")
        local folder = instance("Folder", "Systems", { localScript })
        local workspace = instance("Workspace", "Workspace", { folder })
        local environment = getfenv(scanner.Scan)
        local oldGame = environment.game
        environment.game = { GetService = function(_, name) if name == "Workspace" then return workspace end; error("missing") end }

        local config = {
            SaveWorkspace = true, SaveReplicatedStorage = false, SaveReplicatedFirst = false,
            SaveStarterGui = false, SavePlayerGui = false, SaveStarterPlayer = false,
            SaveLighting = false, SaveSoundService = false, DecompileScripts = true,
        }
        local catalog = { IsSupported = function(item) return item.ClassName == "Folder" or item.ClassName == "LocalScript" end }
        local logger = { Warn = function() end }
        local result = scanner.Scan({ PropertyCatalog = catalog }, config,
            { GetBytecode = function() return "abcd" end }, logger, {})

        environment.game = oldGame
        harness.equal(result.TotalInstances, 2)
        harness.equal(result.SupportedInstances, 2)
        harness.equal(result.LocalScripts, 1)
        harness.equal(result.BytecodeBytes, 4)
    end)
end
