local PropertyCatalog = {}

local SupportedClasses = {
    Folder = true, Model = true, WorldModel = true, Camera = true, Terrain = true,
    Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, MeshPart = true,
    UnionOperation = true, SpawnLocation = true, Seat = true, VehicleSeat = true,
    Attachment = true, Bone = true, SpecialMesh = true,
    Weld = true, WeldConstraint = true, Motor6D = true, ManualWeld = true,
    AlignPosition = true, AlignOrientation = true, AngularVelocity = true, LinearVelocity = true,
    VectorForce = true, Torque = true, RodConstraint = true, RopeConstraint = true,
    SpringConstraint = true, HingeConstraint = true, BallSocketConstraint = true,
    CylindricalConstraint = true, PrismaticConstraint = true, PlaneConstraint = true,
    NoCollisionConstraint = true,
    BoolValue = true, IntValue = true, NumberValue = true, StringValue = true,
    ObjectValue = true, Vector3Value = true, CFrameValue = true, Color3Value = true,
    BrickColorValue = true, RayValue = true,
    ScreenGui = true, BillboardGui = true, SurfaceGui = true, Frame = true,
    CanvasGroup = true, ScrollingFrame = true, TextLabel = true, TextButton = true,
    TextBox = true, ImageLabel = true, ImageButton = true, ViewportFrame = true,
    VideoFrame = true, GuiButton = true, UIListLayout = true, UIGridLayout = true,
    UITableLayout = true, UIPageLayout = true, UIPadding = true, UIScale = true,
    UIAspectRatioConstraint = true, UISizeConstraint = true, UITextSizeConstraint = true,
    UICorner = true, UIStroke = true, UIGradient = true, SelectionBox = true,
    Highlight = true, ProximityPrompt = true, ClickDetector = true,
    Sound = true, SoundGroup = true, EqualizerSoundEffect = true, ReverbSoundEffect = true,
    ChorusSoundEffect = true, CompressorSoundEffect = true, DistortionSoundEffect = true,
    EchoSoundEffect = true, FlangeSoundEffect = true, PitchShiftSoundEffect = true,
    Decal = true, Texture = true, ParticleEmitter = true, Beam = true, Trail = true,
    PointLight = true, SpotLight = true, SurfaceLight = true, Fire = true, Smoke = true,
    Sparkles = true, Sky = true, Atmosphere = true, BloomEffect = true,
    BlurEffect = true, ColorCorrectionEffect = true, DepthOfFieldEffect = true,
    SunRaysEffect = true,
    RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
    LocalScript = true, ModuleScript = true,
    Animation = true, Animator = true, Humanoid = true, AnimationController = true,
    StarterCharacterScripts = true, StarterPlayerScripts = true,
}

local Common = {
    { "Name", "String" },
    { "Archivable", "Bool" },
}

local CategoryProperties = {
    BasePart = {
        { "Anchored", "Bool" }, { "CanCollide", "Bool" }, { "CanQuery", "Bool" },
        { "CanTouch", "Bool" }, { "CastShadow", "Bool" }, { "CFrame", "CFrame" },
        { "Color", "Color3" }, { "CollisionGroup", "String" }, { "Massless", "Bool" },
        { "Material", "Token" }, { "Reflectance", "Float" }, { "RootPriority", "Int" },
        { "Size", "Vector3" }, { "Transparency", "Float" },
    },
    GuiObject = {
        { "Active", "Bool" }, { "AnchorPoint", "Vector2" }, { "AutomaticSize", "Token" },
        { "BackgroundColor3", "Color3" }, { "BackgroundTransparency", "Float" },
        { "BorderColor3", "Color3" }, { "BorderMode", "Token" }, { "BorderSizePixel", "Int" },
        { "ClipsDescendants", "Bool" }, { "LayoutOrder", "Int" }, { "Position", "UDim2" },
        { "Rotation", "Float" }, { "Selectable", "Bool" }, { "SelectionOrder", "Int" },
        { "Size", "UDim2" }, { "SizeConstraint", "Token" }, { "Visible", "Bool" },
        { "ZIndex", "Int" },
    },
    GuiBase2d = { { "AutoLocalize", "Bool" }, { "RootLocalizationTable", "Ref" } },
    LayerCollector = {
        { "Enabled", "Bool" }, { "ResetOnSpawn", "Bool" }, { "ZIndexBehavior", "Token" },
    },
    BaseScript = { { "Disabled", "Bool" } },
    Light = {
        { "Brightness", "Float" }, { "Color", "Color3" }, { "Enabled", "Bool" },
        { "Shadows", "Bool" },
    },
    Constraint = { { "Enabled", "Bool" }, { "Visible", "Bool" } },
}

local ExactProperties = {
    Part = { { "Shape", "Token" } },
    MeshPart = {
        { "MeshId", "Content" }, { "TextureID", "Content" }, { "DoubleSided", "Bool" },
        { "RenderFidelity", "Token" }, { "CollisionFidelity", "Token" },
    },
    Model = { { "PrimaryPart", "Ref" }, { "WorldPivot", "CFrame" } },
    Camera = { { "CFrame", "CFrame" }, { "FieldOfView", "Float" }, { "CameraType", "Token" } },
    Attachment = {
        { "CFrame", "CFrame" }, { "Axis", "Vector3" }, { "SecondaryAxis", "Vector3" },
        { "Visible", "Bool" },
    },
    SpecialMesh = {
        { "MeshId", "Content" }, { "TextureId", "Content" }, { "MeshType", "Token" },
        { "Offset", "Vector3" }, { "Scale", "Vector3" }, { "VertexColor", "Vector3" },
    },
    WeldConstraint = { { "Part0", "Ref" }, { "Part1", "Ref" }, { "Enabled", "Bool" } },
    Weld = { { "Part0", "Ref" }, { "Part1", "Ref" }, { "C0", "CFrame" }, { "C1", "CFrame" }, { "Enabled", "Bool" } },
    Motor6D = { { "Part0", "Ref" }, { "Part1", "Ref" }, { "C0", "CFrame" }, { "C1", "CFrame" }, { "Enabled", "Bool" } },
    ScreenGui = { { "DisplayOrder", "Int" }, { "IgnoreGuiInset", "Bool" }, { "ScreenInsets", "Token" } },
    BillboardGui = {
        { "Adornee", "Ref" }, { "AlwaysOnTop", "Bool" }, { "Brightness", "Float" },
        { "LightInfluence", "Float" }, { "MaxDistance", "Float" }, { "Size", "UDim2" },
        { "StudsOffset", "Vector3" }, { "StudsOffsetWorldSpace", "Vector3" },
    },
    SurfaceGui = {
        { "Adornee", "Ref" }, { "AlwaysOnTop", "Bool" }, { "Brightness", "Float" },
        { "CanvasSize", "Vector2" }, { "Face", "Token" }, { "LightInfluence", "Float" },
        { "PixelsPerStud", "Float" }, { "SizingMode", "Token" },
    },
    ScrollingFrame = {
        { "AutomaticCanvasSize", "Token" }, { "CanvasPosition", "Vector2" },
        { "CanvasSize", "UDim2" }, { "ElasticBehavior", "Token" },
        { "HorizontalScrollBarInset", "Token" }, { "ScrollBarImageColor3", "Color3" },
        { "ScrollBarImageTransparency", "Float" }, { "ScrollBarThickness", "Int" },
        { "ScrollingDirection", "Token" }, { "ScrollingEnabled", "Bool" },
        { "VerticalScrollBarInset", "Token" }, { "VerticalScrollBarPosition", "Token" },
    },
    TextLabel = {
        { "Text", "String" }, { "TextColor3", "Color3" }, { "TextScaled", "Bool" },
        { "TextSize", "Float" }, { "TextStrokeColor3", "Color3" },
        { "TextStrokeTransparency", "Float" }, { "TextTransparency", "Float" },
        { "TextTruncate", "Token" }, { "TextWrapped", "Bool" },
        { "TextXAlignment", "Token" }, { "TextYAlignment", "Token" }, { "RichText", "Bool" },
    },
    TextButton = {
        { "Text", "String" }, { "TextColor3", "Color3" }, { "TextScaled", "Bool" },
        { "TextSize", "Float" }, { "TextStrokeColor3", "Color3" },
        { "TextStrokeTransparency", "Float" }, { "TextTransparency", "Float" },
        { "TextWrapped", "Bool" }, { "RichText", "Bool" }, { "AutoButtonColor", "Bool" },
    },
    TextBox = {
        { "Text", "String" }, { "TextColor3", "Color3" }, { "TextScaled", "Bool" },
        { "TextSize", "Float" }, { "TextTransparency", "Float" }, { "TextWrapped", "Bool" },
        { "ClearTextOnFocus", "Bool" }, { "MultiLine", "Bool" }, { "PlaceholderText", "String" },
        { "PlaceholderColor3", "Color3" }, { "RichText", "Bool" },
    },
    ImageLabel = {
        { "Image", "Content" }, { "ImageColor3", "Color3" }, { "ImageRectOffset", "Vector2" },
        { "ImageRectSize", "Vector2" }, { "ImageTransparency", "Float" }, { "ResampleMode", "Token" },
        { "ScaleType", "Token" }, { "SliceCenter", "Rect" }, { "SliceScale", "Float" },
        { "TileSize", "UDim2" },
    },
    ImageButton = {
        { "Image", "Content" }, { "ImageColor3", "Color3" }, { "ImageRectOffset", "Vector2" },
        { "ImageRectSize", "Vector2" }, { "ImageTransparency", "Float" },
        { "ScaleType", "Token" }, { "AutoButtonColor", "Bool" },
    },
    ViewportFrame = {
        { "Ambient", "Color3" }, { "CurrentCamera", "Ref" }, { "ImageColor3", "Color3" },
        { "ImageTransparency", "Float" }, { "LightColor", "Color3" }, { "LightDirection", "Vector3" },
    },
    Sound = {
        { "EmitterSize", "Float" }, { "IsSpatial", "Bool" }, { "Looped", "Bool" },
        { "MaxDistance", "Float" }, { "MinDistance", "Float" }, { "PlaybackRegion", "NumberRange" },
        { "PlaybackSpeed", "Float" }, { "RollOffMode", "Token" }, { "SoundGroup", "Ref" },
        { "SoundId", "Content" }, { "TimePosition", "Double" }, { "Volume", "Float" },
    },
    Decal = { { "Color3", "Color3" }, { "Face", "Token" }, { "Texture", "Content" }, { "Transparency", "Float" } },
    Texture = {
        { "Color3", "Color3" }, { "Face", "Token" }, { "OffsetStudsU", "Float" },
        { "OffsetStudsV", "Float" }, { "StudsPerTileU", "Float" }, { "StudsPerTileV", "Float" },
        { "Texture", "Content" }, { "Transparency", "Float" },
    },
    ParticleEmitter = {
        { "Acceleration", "Vector3" }, { "Brightness", "Float" }, { "Color", "ColorSequence" },
        { "Drag", "Float" }, { "EmissionDirection", "Token" }, { "Enabled", "Bool" },
        { "Lifetime", "NumberRange" }, { "LightEmission", "Float" }, { "LightInfluence", "Float" },
        { "LockedToPart", "Bool" }, { "Orientation", "Token" }, { "Rate", "Float" },
        { "RotSpeed", "NumberRange" }, { "Rotation", "NumberRange" }, { "Size", "NumberSequence" },
        { "Speed", "NumberRange" }, { "SpreadAngle", "Vector2" }, { "Texture", "Content" },
        { "TimeScale", "Float" }, { "Transparency", "NumberSequence" }, { "VelocityInheritance", "Float" },
        { "ZOffset", "Float" },
    },
    Beam = {
        { "Attachment0", "Ref" }, { "Attachment1", "Ref" }, { "Brightness", "Float" },
        { "Color", "ColorSequence" }, { "CurveSize0", "Float" }, { "CurveSize1", "Float" },
        { "Enabled", "Bool" }, { "FaceCamera", "Bool" }, { "LightEmission", "Float" },
        { "LightInfluence", "Float" }, { "Segments", "Int" }, { "Texture", "Content" },
        { "TextureLength", "Float" }, { "TextureMode", "Token" }, { "TextureSpeed", "Float" },
        { "Transparency", "NumberSequence" }, { "Width0", "Float" }, { "Width1", "Float" },
    },
    Trail = {
        { "Attachment0", "Ref" }, { "Attachment1", "Ref" }, { "Color", "ColorSequence" },
        { "Enabled", "Bool" }, { "FaceCamera", "Bool" }, { "Lifetime", "Float" },
        { "LightEmission", "Float" }, { "LightInfluence", "Float" }, { "MaxLength", "Float" },
        { "MinLength", "Float" }, { "Texture", "Content" }, { "TextureLength", "Float" },
        { "TextureMode", "Token" }, { "Transparency", "NumberSequence" },
        { "WidthScale", "NumberSequence" },
    },
    UICorner = { { "CornerRadius", "UDim" } },
    UIStroke = {
        { "ApplyStrokeMode", "Token" }, { "Color", "Color3" }, { "Enabled", "Bool" },
        { "LineJoinMode", "Token" }, { "Thickness", "Float" }, { "Transparency", "Float" },
    },
    UIGradient = { { "Color", "ColorSequence" }, { "Enabled", "Bool" }, { "Offset", "Vector2" }, { "Rotation", "Float" }, { "Transparency", "NumberSequence" } },
    UIPadding = { { "PaddingBottom", "UDim" }, { "PaddingLeft", "UDim" }, { "PaddingRight", "UDim" }, { "PaddingTop", "UDim" } },
    UIScale = { { "Scale", "Float" } },
    UIListLayout = { { "FillDirection", "Token" }, { "HorizontalAlignment", "Token" }, { "Padding", "UDim" }, { "SortOrder", "Token" }, { "VerticalAlignment", "Token" }, { "Wraps", "Bool" } },
    UIGridLayout = { { "CellPadding", "UDim2" }, { "CellSize", "UDim2" }, { "FillDirection", "Token" }, { "FillDirectionMaxCells", "Int" }, { "HorizontalAlignment", "Token" }, { "SortOrder", "Token" }, { "StartCorner", "Token" }, { "VerticalAlignment", "Token" } },
    LocalScript = { { "Enabled", "Bool" } },
    Animation = { { "AnimationId", "Content" } },
    Sky = { { "CelestialBodiesShown", "Bool" }, { "MoonAngularSize", "Float" }, { "MoonTextureId", "Content" }, { "SkyboxBk", "Content" }, { "SkyboxDn", "Content" }, { "SkyboxFt", "Content" }, { "SkyboxLf", "Content" }, { "SkyboxRt", "Content" }, { "SkyboxUp", "Content" }, { "StarCount", "Int" }, { "SunAngularSize", "Float" }, { "SunTextureId", "Content" } },
    Atmosphere = { { "Color", "Color3" }, { "Decay", "Color3" }, { "Density", "Float" }, { "Glare", "Float" }, { "Haze", "Float" }, { "Offset", "Float" } },
}

local ValueClasses = {
    BoolValue = true, IntValue = true, NumberValue = true, StringValue = true,
    ObjectValue = true, Vector3Value = true, CFrameValue = true, Color3Value = true,
    BrickColorValue = true,
}

local function safeIsA(instance, className)
    local ok, result = pcall(function()
        return instance:IsA(className)
    end)
    return ok and result
end

local function inferHint(value)
    local kind = typeof and typeof(value) or type(value)
    local hints = {
        string = "String", boolean = "Bool", number = "Double", Instance = "Ref",
        Vector2 = "Vector2", Vector3 = "Vector3", Color3 = "Color3", CFrame = "CFrame",
        UDim = "UDim", UDim2 = "UDim2", Rect = "Rect", BrickColor = "BrickColor",
        NumberRange = "NumberRange", NumberSequence = "NumberSequence", ColorSequence = "ColorSequence",
        EnumItem = "Token",
    }
    return hints[kind]
end

function PropertyCatalog.IsSupported(instance)
    local className = instance.ClassName
    return SupportedClasses[className] == true
        or safeIsA(instance, "BasePart")
        or safeIsA(instance, "GuiObject")
        or safeIsA(instance, "Constraint")
        or safeIsA(instance, "Light")
end

function PropertyCatalog.ReadProperties(instance, logger)
    local definitions = {}
    local seen = {}
    local function append(list)
        for _, definition in ipairs(list or {}) do
            if not seen[definition[1]] then
                seen[definition[1]] = true
                table.insert(definitions, definition)
            end
        end
    end

    append(Common)
    for category, list in pairs(CategoryProperties) do
        if safeIsA(instance, category) then
            append(list)
        end
    end
    append(ExactProperties[instance.ClassName])

    if ValueClasses[instance.ClassName] then
        local ok, value = pcall(function() return instance.Value end)
        if ok then
            local hint = inferHint(value)
            if hint then
                table.insert(definitions, { "Value", hint })
            end
        end
    end

    local properties = {}
    for _, definition in ipairs(definitions) do
        local ok, value = pcall(function()
            return instance[definition[1]]
        end)
        if ok then
            table.insert(properties, { Name = definition[1], Hint = definition[2], Value = value })
        elseif logger then
            logger:Warn("Failed to read property " .. definition[1], instance:GetFullName())
        end
    end
    return properties
end

return PropertyCatalog
