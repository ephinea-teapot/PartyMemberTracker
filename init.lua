local core_mainmenu = require("core_mainmenu")
local lib_helpers = require("solylib.helpers")
local lib_characters = require("solylib.characters")
local lib_menu = require("solylib.menu")

local origPackagePath = package.path
package.path = './addons/Dropbox Tracker/lua-xtype/src/?.lua;' .. package.path
package.path = './addons/Dropbox Tracker/MGL/src/?.lua;' .. package.path
local xtype = require("xtype")
local mgl = require("MGL")
package.path = origPackagePath

local enableAddon = true

local windowParams = { "NoTitleBar", "NoResize", "NoMove", "NoInputs", "NoSavedSettings", "AlwaysAutoResize" }


local playerSelfAddr       = nil
local playerSelfCoords     = nil
local playerSelfDirs       = nil
local playerSelfNormDir    = nil
local pCoord               = nil
local cameraCoords         = nil
local cameraDirs           = nil
local cameraNormDirVec2    = nil
local cameraNormDirVec3    = nil
local item_graph_data      = {}
local toolLookupTable      = {}
local invToolLookupTable   = {}
local musicDiskLookupTable = {}
local resolutionWidth      = {}
local resolutionHeight     = {}
local trackerBox           = {}
local screenFov            = nil
local aspectRatio          = nil
local eyeWorld             = nil
local eyeDir               = nil
local determinantScr       = nil
local cameraZoom           = nil
local lastCameraZoom       = nil
local trackerWindowLookup  = {}

local _CameraPosX          = 0x00A48780
local _CameraPosY          = 0x00A48784
local _CameraPosZ          = 0x00A48788
local _CameraDirX          = 0x00A4878C
local _CameraDirY          = 0x00A48790
local _CameraDirZ          = 0x00A48794
local _CameraZoomLevel     = 0x009ACEDC

local options              = {}

local function GetPlayerCoordinates(player)
    local x = 0
    local y = 0
    local z = 0
    if player ~= 0 then
        x = pso.read_f32(player + 0x38)
        y = pso.read_f32(player + 0x3C)
        z = pso.read_f32(player + 0x40)
    end

    return
    {
        x = x,
        y = y,
        z = z,
    }
end

local function GetPlayerDirection(player)
    local x = 0
    local z = 0
    if player ~= 0 then
        x = pso.read_f32(player + 0x410)
        z = pso.read_f32(player + 0x418)
    end

    return
    {
        x = x,
        z = z,
    }
end

local function getCameraZoom()
    return pso.read_u32(_CameraZoomLevel)
end
local function getCameraCoordinates()
    return
    {
        x = pso.read_f32(_CameraPosX),
        y = pso.read_f32(_CameraPosY),
        z = pso.read_f32(_CameraPosZ),
    }
end
local function getCameraDirection()
    return
    {
        x = pso.read_f32(_CameraDirX), -- -1 to 1 in x direction (west to east)
        y = pso.read_f32(_CameraDirY), -- pitch
        z = pso.read_f32(_CameraDirZ), -- -1 to 1 in z direction (north to south)
    }
end

local function clampVal(clamp, min, max)
    return clamp < min and min or clamp > max and max or clamp
end

local function Norm(Val, Min, Max)
    return (Val - Min) / (Max - Min)
end
local function Lerp(Norm, Min, Max)
    return (Max - Min) * Norm + Min
end

local function shiftHexColor(color)
    return
    {
        bit.band(bit.rshift(color, 24), 0xFF),
        bit.band(bit.rshift(color, 16), 0xFF),
        bit.band(bit.rshift(color, 8), 0xFF),
        bit.band(color, 0xFF)
    }
end

local function computePixelCoordinates(pWorld, eyeWorld, eyeDir, determinant)
    local pRaster = mgl.vec2(0)
    local vis = -1

    local vDir = pWorld - eyeWorld
    vDir = mgl.normalize(vDir)
    local fdp = mgl.dot(eyeDir, vDir)

    --fdp must be nonzero ( in other words, vDir must not be perpendicular to angCamRot:Forward() )
    --or we will get a divide by zero error when calculating vProj below.
    if fdp == 0 then
        return pRaster, -1
    end

    --Using linear projection, project this vector onto the plane of the slice
    local ddfp     = determinant / fdp
    local vProj    = mgl.vec3(ddfp, ddfp, ddfp) * vDir
    --get the up component from the forward vector assuming world yaxis (vertical axis 0,+1,0) is up
    --https://stackoverflow.com/questions/1171849/finding-quaternion-representing-the-rotation-from-one-vector-to-another/1171995#1171995
    local eyeRight = mgl.cross(eyeDir, mgl.vec3(0, 1, 0))
    local eyeLeft  = mgl.cross(eyeRight, eyeDir)

    if fdp > 0.0000001 then
        vis = 1
    end
    pRaster.x = mgl.dot(eyeRight, vProj) --0.5 * iScreenW + mgl.dot(eyeRight,vProj)
    pRaster.y = -mgl.dot(eyeLeft, vProj) --0.5 * iScreenH - mgl.dot(eyeLeft,vProj)

    return pRaster, vis
end

local function calcScreenResolutions(trkIdx, forced)
    if forced or not resolutionWidth.val or not resolutionHeight.val then
        if options.customScreenResEnabled then
            resolutionWidth.val  = options.customScreenResX
            resolutionHeight.val = options.customScreenResY
        else
            resolutionWidth.val  = lib_helpers.GetResolutionWidth()
            resolutionHeight.val = lib_helpers.GetResolutionHeight()
        end
        aspectRatio                   = resolutionWidth.val / resolutionHeight.val
        resolutionWidth.half          = resolutionWidth.val * 0.5
        resolutionHeight.half         = resolutionHeight.val * 0.5
        resolutionWidth.clampRescale  = resolutionWidth.val * 1
        resolutionHeight.clampRescale = resolutionHeight.val * 1

        -- trackerBox.sizeX                 = options[trkIdx].boxSizeX
        -- trackerBox.sizeHalfX             = options[trkIdx].boxSizeX * 0.5
        -- trackerBox.sizeY                 = options[trkIdx].boxSizeY
        -- trackerBox.sizeHalfY             = options[trkIdx].boxSizeY * 0.5
        -- trackerBox.offsetX               = options[trkIdx].boxOffsetX
        -- trackerBox.offsetY               = options[trkIdx].boxOffsetY

        -- resolutionWidth.clampBoxLowest   = -resolutionWidth.half  + trackerBox.sizeHalfX
        -- resolutionWidth.clampBoxHighest  =  resolutionWidth.half  - trackerBox.sizeHalfX
        -- resolutionHeight.clampBoxLowest  = -resolutionHeight.half + trackerBox.sizeHalfY + 2
        -- resolutionHeight.clampBoxHighest =  resolutionHeight.half - trackerBox.sizeHalfY - 2
    end
end

local function calcScreenFoV(trkIdx, forced)
    if not aspectRatio or not cameraZoom or not resolutionHeight.val then
        cameraZoom = getCameraZoom()
        calcScreenResolutions(trkIdx, forced)
    end

    if forced or cameraZoom ~= lastCameraZoom or cameraZoom == nil then
        if options.customFoVEnabled then
            if cameraZoom == 0 then
                screenFov = math.rad(options.customFoV0)
            elseif cameraZoom == 1 then
                screenFov = math.rad(options.customFoV1)
            elseif cameraZoom == 2 then
                screenFov = math.rad(options.customFoV2)
            elseif cameraZoom == 3 then
                screenFov = math.rad(options.customFoV3)
            elseif cameraZoom == 4 then
                screenFov = math.rad(options.customFoV4)
            else
                screenFov = 69 -- a good guess
            end
        else
            screenFov = math.rad(
                math.deg(
                    2 * math.atan(0.56470588 * aspectRatio) -- 0.56470588 is 768/1360
                ) - (cameraZoom - 1) * 0.600 -
                clampVal(cameraZoom, 0, 1) *
                0.300 -- the constant here should work for most to all aspect ratios between 1.25 to 1.77, gud enuff.
            )
        end
        determinantScr = aspectRatio * 3 * resolutionHeight.val / (6 * math.tan(0.5 * screenFov))
        lastCameraZoom = CameraZoom
    end
end

local function getMyAddress()
    local _PlayerArray = 0x00A94254
    local _PlayerIndex = 0x00A9C4F4
    local playerIndex = pso.read_u32(_PlayerIndex)
    local playerAddr = pso.read_u32(_PlayerArray + 4 * playerIndex)
    return playerAddr
end

local function shouldBeDisplay()
    if lib_menu.IsSymbolChatOpen() then
        return false
    end
    if lib_menu.IsMenuOpen() then
        return false
    end
    if lib_menu.IsMenuUnavailable() then
        return false
    end
    return true
end

local function getColor(i)
    if i == 1 then
        return 1.0, 0.0, 0.0
    end

    if i == 2 then
        return 0.0, 1.0, 0.0
    end

    if i == 3 then
        return 1.0, 1.0, 0.0
    end

    if i == 4 then
        return 0.0, 0.0, 1.0
    end

    return 1.0, 1.0, 1.0
end

local _PlayerArray = 0x00A94254
local _PlayerCount = 0x00AAE168
local _PlayerMyIndex = 0x00A9C4F4
local _Location = 0x00AAFC9C

local function _getPlayerAddress()
    local playerIndex = pso.read_u32(_PlayerMyIndex)
    return pso.read_u32(_PlayerArray + 4 * playerIndex)
end

local function isSessionActive()

    local playerCount = pso.read_u32(_PlayerCount)
    local playerAddress = _getPlayerAddress()
    local location = pso.read_u32(_Location + 0x04)

    -- Location of 0xF indicates
    -- the player is in the lobby
    return
        location ~= 0xF and
        playerCount ~= 0 and
        playerAddress ~= 0
end

local function present()
    if enableAddon == false then
        return
    end

    if shouldBeDisplay() ~= true then
        return
    end

    if isSessionActive() ~= true then
        return
    end

    local cameraCoords = getCameraCoordinates()
    local cameraDirs   = getCameraDirection()
    local eyeWorld     = mgl.vec3(cameraCoords.x, cameraCoords.y, cameraCoords.z)
    local eyeDir       = mgl.vec3(cameraDirs.x, cameraDirs.y, cameraDirs.z)

    calcScreenFoV(nil)

    local myFloor = lib_characters.GetCurrentFloorSelf()

    local playerList = lib_characters.GetPlayerList()
    for i = 1, #playerList do
        local index = playerList[i].index
        local address = playerList[i].address

        if address ~= getMyAddress() and myFloor == lib_characters.GetPlayerFloor(address) then
            local name = lib_characters.GetPlayerName(address)

            local X = pso.read_f32(address + 0x38) -- left/right
            local Y = pso.read_f32(address + 0x3C) -- up/down
            local Z = pso.read_f32(address + 0x40) -- out/in

            local pRaster, visible = computePixelCoordinates(mgl.vec3(X, Y, Z), eyeWorld, eyeDir, determinantScr)
            if (visible > 0) then
                local ps = lib_helpers.GetPosBySizeAndAnchor(pRaster.x, pRaster.y, 100, 100, 5)
                imgui.SetNextWindowPos(ps[1], ps[2], "Always")
                imgui.SetNextWindowSize(100, 40, "AlwaysAutoResize")
                imgui.Begin("PTMemberTracker - Hud" .. i, nil, windowParams)
                local r, g, b = getColor(index)
                imgui.TextColored(r, g, b, 1.0, name)
                imgui.End()
            end
        end
    end
end

local function init()
    local function mainMenuButtonHandler()
        if enableAddon == false then
        end
        enableAddon = not enableAddon
    end

    core_mainmenu.add_button("Party Member Tracker", mainMenuButtonHandler)

    return
    {
        name = "Party Member Tracker",
        version = "0.0.1",
        author = "teapot",
        description =
        "This is an add-on that displays the player's name in the position of the character of the party member.",
        present = present,
        -- key_pressed = key_pressed,
    }
end

return
{
    __addon =
    {
        init = init
    }
}
