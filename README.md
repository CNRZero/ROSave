# ROSave Prototype 1

ROSave is a small, modular Luau proof of concept for recovering client-visible content from Roblox places you own or are explicitly authorized to test. It scans the selected replicated roots once, preserves supported hierarchy and runtime `PlayerGui`, reconstructs supported standard Luau bytecode, and writes an XML place (`.rbxlx`) with a final report.

Prototype version: `0.1.0`

## Important runtime boundary

Stock Roblox client scripts cannot read another script's protected `Source`, cannot obtain its bytecode, cannot write arbitrary local files, and normally cannot compile downloaded source. Those capabilities must be supplied by the authorized test environment through `_G.ROSaveRuntime`. ROSave does not bypass those boundaries and never scans `ServerScriptService`, `ServerStorage`, or other server-only containers.

The required adapters are:

```lua
_G.ROSaveRuntime = {
    HttpGet = function(url) -- return source text end,
    Compile = function(source, chunkName) -- return function or nil, error end,
    WriteFile = function(path, contents) -- write the RBXLX end,
    GetBytecode = function(localOrModuleScript) -- return a standard Luau bytecode string end,
}
```

The bootstrap has conservative fallbacks for `game:HttpGet`, `loadstring`, `writefile`, and `getscriptbytecode` when an authorized environment exposes them as globals. Missing essential loading or output capabilities produce explicit errors. Missing bytecode access does not destroy the hierarchy save; affected scripts are reported as failed.

## Setup and use

1. Put `Prototype1/` in a GitHub repository.
2. Change the single `Repository.BaseURL` in [`Bootstrap.lua`](./Prototype1/Bootstrap.lua) from `OWNER/REPOSITORY` to that repository.
3. Edit `UserConfig` in the bootstrap if the defaults need changing.
4. Define the authorized runtime adapters, then run the small bootstrap in the test environment.
5. Open the generated `RecoveredPlace.rbxlx` in Studio and review warnings plus recovered scripts before running them.

Configuration defaults live in [`Config.lua`](./Prototype1/Core/Config.lua). The loader downloads each listed module once per run and cancels startup if any module is missing, fails compilation, or returns an invalid value.

Local development mode is also wired in. Set `ModuleSource = "Local"` and provide `ROSaveRuntime.LoadLocalModule(relativePath)`; no project module needs to change.

## Implemented scope

- Configured scans of Workspace, ReplicatedStorage, ReplicatedFirst, StarterGui, StarterPlayer, Lighting, SoundService, and current `LocalPlayer.PlayerGui`.
- A property catalog for common parts, models, values, GUI, effects, sounds, constraints, remotes, bindables, LocalScripts, and ModuleScripts.
- Native RBXLX hierarchy, references, XML-safe source, tags, and common attribute types.
- Pre-scan counts, byte-size-aware estimate, nine stages, measured throughput, live ETA, warnings, and final totals.
- Standard open-source Luau bytecode versions 3 through 8, including constants, instructions/AUX words, basic blocks, simple `if`/`else` and `while` regions, expressions, calls, and deterministic variable names.
- `Fast`, `Balanced`, and `Best` modes. Fast skips structural control-flow regions; Balanced and Best enable them. Best currently favors validation rather than speculative naming.
- Object- and script-level continuation when `ContinueOnError` is enabled; loader and invalid-output failures remain fatal.

## Explicit Prototype 1 limitations

- Roblox may use a bytecode encoding or version different from the standard open-source versions supported here. Such input is rejected with its version/error; it is not guessed or fabricated.
- Complex generic/numeric loops, multireturn flows, captures, some table templates, and newer opcodes can be emitted as valid partial recovery with comments. Original local names are not invented.
- The property catalog is intentionally finite. Unsupported instances are reported by class, while supported descendants are promoted to the nearest preserved ancestor.
- Terrain instance metadata is retained, but voxel terrain data is explicitly unsupported in this prototype.
- Common scalar, vector, color, dimension, BrickColor, and CFrame attributes are encoded. Other attribute variants are warned and omitted.
- RBXLX structural validation and reconstructed-source compilation are performed when a compiler is available, but the prototype does not automate a Studio import round trip.

These limits are why each script is counted as successful, partial, or failed rather than being presented as perfect original source.

## Tests

With the open-source Luau CLI available, run from the repository root:

```text
luau Prototype1/Tests/TestRunner.lua
```

The suite covers a real serialized v4 bytecode fixture, AUX-aware instruction decoding, deterministic decompilation, unsupported-version handling, Base64/RBXLX serialization, validation, and single-pass scanning.

[`TestPlaceBuilder.lua`](./Prototype1/Tests/Fixtures/TestPlaceBuilder.lua) builds a controlled Studio fixture with nested models, attributes, tags, scripts, closures, branches, loops, tables, a large script, runtime-created `PlayerGui`, a large GUI hierarchy, and an unsupported container whose supported child must survive. Run it only in a blank place you control.

## Design references

The bytecode reader follows the open-source [Luau bytecode definitions](https://github.com/luau-lang/luau/blob/master/Common/include/Luau/Bytecode.h). The writer follows the community-documented [Roblox XML format](https://github.com/RobloxAPI/spec/blob/master/formats/rbxlx.md) and [attribute/tag binary formats](https://github.com/rojo-rbx/rbx-dom/blob/master/docs/binary-strings.md). Roblox documents that script `Source` is protected outside authorized Studio capabilities in the [Script API reference](https://create.roblox.com/docs/reference/engine/classes/Script).
