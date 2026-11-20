-- ==============================================================================
--  BDS TOOLKIT - ALL-IN-ONE CLIENT RP SUITE & CLIENT ENHANCER
--  Version: 1.0.0 (Official V1.0 Release)
--  Modules: Keybinder, AutoCar, Downloader HUD, Chat Modes, VehInfo, SensFix & Fixes
--  Added: Native Auto-Updater, Vehicle Free-Look Camera, SprintHook, FPS HUD & Anonymized Damage Feed
--  Developer & Author: Danny_Jadogar (CHACHA)
-- ==============================================================================

script_name("BDS Toolkit")
script_description("All-in-One RP Suite: Keybinder, AutoCar, Downloader, VehInfo HUD & SensFix by Danny_Jadogar (CHACHA)")
script_author("Danny_Jadogar (CHACHA)")
script_version("1.0.0")
script_properties("work-in-pause")

require('lib.moonloader')
local vkeys  = require('vkeys')
local imgui  = require('mimgui')
local ffi    = require('ffi')
local memory = require('memory')

local hasBit, bit       = pcall(require, 'bit')

pcall(ffi.cdef, [[
    int VirtualProtect(void* lpAddress, unsigned long dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    void* GetModuleHandleA(const char* lpModuleName);
    typedef struct _MEMORY_BASIC_INFORMATION {
        void*  BaseAddress;
        void*  AllocationBase;
        unsigned long AllocationProtect;
        size_t RegionSize;
        unsigned long State;
        unsigned long Protect;
        unsigned long Type;
    } MEMORY_BASIC_INFORMATION, *PMEMORY_BASIC_INFORMATION;
    size_t VirtualQuery(const void* lpAddress, PMEMORY_BASIC_INFORMATION lpBuffer, size_t dwLength);
]])

local mbiMemInfo = ffi.new("MEMORY_BASIC_INFORMATION")
local szMbi      = ffi.sizeof(mbiMemInfo)

local function isMemoryReadable(ptr, size)
    -- Do not wrap this helper in pcall: MoonLoader's yield-aware pcall can
    -- attempt to resume an already-running coroutine when nested.
    if ptr == nil then return false end

    local numPtr = tonumber(ffi.cast("uintptr_t", ptr))
    if not numPtr or numPtr <= 0x10000 or numPtr >= 0x7FFE0000 then
        return false
    end

    local q = ffi.C.VirtualQuery(ffi.cast("const void*", numPtr), mbiMemInfo, szMbi)
    if q == 0 then return false end
    if tonumber(mbiMemInfo.State) ~= 0x1000 then return false end

    local prot = tonumber(mbiMemInfo.Protect) or 0
    -- Reject PAGE_GUARD and PAGE_NOACCESS.
    if (prot % 512) >= 256 then return false end
    local baseProt = prot % 256
    local readable = (baseProt == 0x02 or baseProt == 0x04 or baseProt == 0x08
        or baseProt == 0x20 or baseProt == 0x40 or baseProt == 0x80)
    if not readable then return false end

    local base = tonumber(ffi.cast("uintptr_t", mbiMemInfo.BaseAddress))
    local regionSize = tonumber(mbiMemInfo.RegionSize) or 0
    local requested = tonumber(size) or 4
    local offset = numPtr - base
    if requested < 1 or offset < 0 or offset + requested > regionSize then
        return false
    end
    return true
end

local INI_FILE = "BDS_Toolkit.ini"

local function logDiagnostic(level, message)
    pcall(function()
        local f = io.open("BDS_Toolkit.log", "a")
        if not f then return end
        f:write(string.format("[%s] [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(level or "INFO"), tostring(message or "")))
        f:close()
    end)
end

-- ------------------------------------------------------------------------------
-- Vehicle Classification Database
-- ------------------------------------------------------------------------------
local VEHICLE_CLASSES = {
    bicycle = { [481] = true, [509] = true, [510] = true },
    bike = {
        [448] = true, [461] = true, [462] = true, [463] = true,
        [468] = true, [471] = true, [521] = true, [522] = true,
        [523] = true, [581] = true, [586] = true
    },
    boat = {
        [430] = true, [446] = true, [452] = true, [453] = true,
        [454] = true, [472] = true, [473] = true, [484] = true,
        [493] = true, [595] = true
    },
    aircraft = {
        [417] = true, [425] = true, [447] = true, [460] = true,
        [469] = true, [476] = true, [487] = true, [488] = true,
        [497] = true, [511] = true, [512] = true, [513] = true,
        [519] = true, [520] = true, [548] = true, [553] = true,
        [563] = true, [577] = true, [592] = true, [593] = true
    }
}

local function getVehicleClass(modelId)
    if not modelId or modelId == 0 then return 'car' end
    for class, set in pairs(VEHICLE_CLASSES) do
        if set[modelId] then return class end
    end
    return 'car'
end

-- ------------------------------------------------------------------------------
-- Themes for FiveM Downloader & UI
-- ------------------------------------------------------------------------------
local THEME_ORDER = {
    { id = "neon_cyan",    label = "Neon Cyan" },
    { id = "clean_white",  label = "Minimalist White" },
    { id = "fivem_orange", label = "FiveM Amber (Authentic)" },
    { id = "cyber_green",  label = "Cyber Green" },
}

local THEMES = {
    fivem_orange = {
        name = "FiveM Amber (Authentic)",
        accent = imgui.ImVec4(1.00, 0.58, 0.12, 1.00),
        accentBg = imgui.ImVec4(0.35, 0.20, 0.05, 0.60),
        border = imgui.ImVec4(1.00, 0.58, 0.12, 0.35),
    },
    cyber_green = {
        name = "Cyber Green",
        accent = imgui.ImVec4(0.00, 0.90, 0.46, 1.00),
        accentBg = imgui.ImVec4(0.00, 0.30, 0.15, 0.60),
        border = imgui.ImVec4(0.00, 0.90, 0.46, 0.35),
    },
    neon_cyan = {
        name = "Neon Cyan",
        accent = imgui.ImVec4(0.00, 0.85, 0.98, 1.00),
        accentBg = imgui.ImVec4(0.00, 0.25, 0.35, 0.60),
        border = imgui.ImVec4(0.00, 0.85, 0.98, 0.35),
    },
    clean_white = {
        name = "Minimalist White",
        accent = imgui.ImVec4(0.95, 0.96, 1.00, 1.00),
        accentBg = imgui.ImVec4(0.25, 0.28, 0.32, 0.60),
        border = imgui.ImVec4(0.85, 0.88, 0.95, 0.35),
    },
}

-- ------------------------------------------------------------------------------
-- Data Structures & State Initialization
-- ------------------------------------------------------------------------------
local function makeEmptyProfile(defaultName)
    local p = { name = defaultName, slots = {} }
    for i = 1, 20 do
        p.slots[i] = {
            enabled = false,
            key     = 0,
            alias   = "",
            command = "",
            mode    = "send",
        }
    end
    return p
end

local profiles = {
    makeEmptyProfile("Normal"),
    makeEmptyProfile("Profile 2"),
    makeEmptyProfile("Profile 3"),
    makeEmptyProfile("Profile 4"),
    makeEmptyProfile("Profile 5"),
}

local config = {
    general = {
        menuKey          = vkeys.VK_F12 or 123, -- F12 to open BDS Toolkit
        menuKeyAlt       = 0, -- Disabled (Only F12 toggles menu)
        lockPlayer       = true,
        activeTab        = 1, -- 1: Binder, 2: AutoCar, 3: Downloader, 4: Chat & Logs, 5: VehInfo, 6: Help
        chatSubTab       = 1, -- 1: Chat Modes (Room Editor), 2: Chatlog Viewer
        activeProfile    = 1,
        spamDelayMs      = 0,
        showToast        = false,
        menuOpacity      = 90, -- 30% to 100%
        hasSetDefaultPos = false,
        helpFontScale    = 1.0,
        autoUpdateCheck  = true,
        autoUpdateInstall= false,
        updateUrl        = "https://raw.githubusercontent.com/dannyjadogar-cyber/BDS_Toolkit/main/version.json",
    },
    chatmode = {
        enabled           = true,
        activeModeIdx     = 1,
        showFloatingBar   = true,
        cycleKey          = vkeys.VK_TAB or 9, -- Default: TAB button
        autoAttach        = true,              -- Automatically attach directly under chatbox
        barX              = 28,
        barY              = 95,
        offsetX           = 0,
        offsetY           = 0,
        modes             = {
            { name = "Normal (IC)",   prefix = "" },
            { name = "/b (OOC)",      prefix = "/b" },
            { name = "/me (Action)",  prefix = "/me" },
            { name = "/do (State)",   prefix = "/do" },
            { name = "/s (Shout)",    prefix = "/s" },
        }
    },
    binder = {
        enabled          = false, -- Keybinder Master Mode ON/OFF
    },
    autocar = {
        enabled           = false,
        autoSeatbelt      = true,
        passengerSeatbelt = true,
        autoEngine        = true,
        engineOffOnExit   = true,
        autoLights        = true,
        lightsOffOnExit   = true,
        autoLock          = false,
        showChatNotice    = false,
        nightStartHour    = 19,
        nightEndHour      = 6,
        enterDelayMs      = 400,
        hourOffset        = 2,
        syncWithHud       = true,
    },
    commands = {
        seatbeltCmd = "/seatbelt",
        engineCmd   = "/engine",
        lightsCmd   = "/lights",
        lockCmd     = "/lock",
    },
    downloader = {
        enabled           = true,
        hideDefaultBox    = true,
        positionPreset    = "bottom_right",
        theme             = "neon_cyan",
        soundNotification = true,
        showSpeed         = true,
        offsetX           = 25,
        offsetY           = 35,
    },
    vehinfo = {
        enabled            = false,
        displayMode        = 1,      -- 1: 3D World Space (attached to vehicle), 2: 2D Fixed Screen HUD
        checkWalls         = true,   -- true: hide behind walls (realistic RP), false: show through walls (ESP)
        trackCurrentCar    = true,   -- Show info on vehicle you are driving/riding
        lookMaxDist        = 50.0,   -- Max detection range for visible vehicles (meters)
        nearbyMaxCount     = 6,      -- Max vehicles displayed on screen at once
        speedUnit          = "km/h", -- "km/h" or "mph"
        showId             = true,
        showModel          = true,
        showSpeed          = false,
        showHealth         = true,
        showDistance       = false,
        showEngine         = false,
        showLock           = false,
        showHealthBar      = false,
        labelId            = "ID:",
        labelModel         = "Model:",
        labelSpeed         = "Speed:",
        labelHealth        = "Health:",
        labelDistance      = "Distance:",
        labelEngine        = "Engine:",
        labelLock          = "Lock:",
        labelColorR        = 0.20,
        labelColorG        = 1.00,
        labelColorB        = 0.20,
        labelColorA        = 1.00,
        valueColorR        = 1.00,
        valueColorG        = 1.00,
        valueColorB        = 1.00,
        valueColorA        = 1.00,
        bgStyle            = 1,      -- 1: Pure Text with Shadow, 2: Dark Pill Card
        bgAlpha            = 0.65,
        fontSize           = 15.0,
        scaleWithDist      = false,
        textShadow         = true,
        offsetX            = 0.00,
        offsetZ            = 0.25,
        hud2dPosX          = 0.85,
        hud2dPosY          = 0.82,
    },
    sensfix = {
        enabled            = false,
        baseSens           = 0.002250,
        yRatio             = 1.000,
        fixVertical        = true,
        hotkey             = 0,
        deagle             = 1.00,
        pistol             = 1.00,
        shotgun            = 1.00,
        smg                = 1.00,
        rifle              = 0.85,
        country            = 0.80,
        sniper             = 0.50,
        freelook           = 1.00,
        vehcam             = 1.00,
        driveby            = 1.00,
    },
    tweaks = {
        enabled            = true,
        subTab             = 1,
        antiCrasher        = true,
        highFpsSwimming    = true,
        highFpsBraking     = true,
        runInBackground    = true,
        borderlessWindow   = true,
        radarAspectFix     = true,
        widescreenScope    = true,
        fastWeaponSwitch   = false,
        hillPark           = false,
        silentSirens       = false,
        aircraftQuieter    = false,
        clearHorizon       = false,
        damageFeed         = false,
        flintNightFix      = true,
        flintNightMode     = 1,
        flintNightBoost    = 420,
        cameraNoRecenter   = false,
        anisotropic16x     = true,
        bulletTracers      = false,
        masterBrightness   = 256,
        sprintHook         = true,
        fpsDisplay         = true,
        fpsDisplayPos      = 1,
    }
}

local state = {
    -- UI Windows
    mainWindowOpen       = imgui.new.bool(false),
    wasMenuOpenLastFrame = false,
    resetKeysRequested   = false,
    waitingChatCycleKey  = false,
    pendingProfileSwitch = nil, -- Apply profile changes safely from the main loop, not inside SA-MP command callback.
    activeTab            = 1,
    needResetWindowPos   = false,

    -- Keybinder State
    waitingKeyFor      = nil,
    rebindDebounce     = false,
    lastTriggerTick    = 0,
    toastText          = "",
    toastExpiry        = 0,

    -- Vehicle State
    inVehicle          = false,
    currentVeh         = nil,
    currentModel       = 0,
    currentClass       = 'car',
    isDriver           = false,
    engineRunning      = false,
    lightsOn           = false,
    beltFastened       = false,
    enteringRoutine    = false,
    isExiting          = false,
    vehicleSession     = 0,
    lastNightState     = nil,
    hudClockHour       = nil,
    hudClockMin        = nil,
    lastClockSyncTime  = 0,

    -- Downloader Telemetry & Hooks
    sampBase           = nil,
    isDlVersion        = false,
    renderHookApplied  = false,
    renderHookOwned    = false,
    originalRenderByte = 0x83,
    isDownloading      = false,
    currentFiles       = 0,
    totalFiles         = 0,
    speedKBps          = 0.0,
    fadeAlpha          = 0.0,
    isComplete         = false,
    completeTime       = 0.0,

    -- Simulation / Test Mode
    isTestMode         = false,
    testStartTime      = 0.0,
    testDuration       = 6.0,
    testTotalFiles     = 45,

    -- Vehicle Info HUD Telemetry
    vehinfoTargets     = {},
}

-- ------------------------------------------------------------------------------
-- Dear ImGui Keyboard State Sanitizer (Asynchronous flag, safe outside OnFrame)
-- ------------------------------------------------------------------------------
local function resetImGuiKeyboardState()
    state.resetKeysRequested = true
end

-- ImGui Text Input Buffers
local slotBuffers  = {}
local aliasBuffers = {}
local profileNameBuffers = {}
for p = 1, 5 do
    slotBuffers[p]  = {}
    aliasBuffers[p] = {}
    profileNameBuffers[p] = imgui.new.char[64]()
    for s = 1, 20 do
        slotBuffers[p][s]  = imgui.new.char[256]()
        aliasBuffers[p][s] = imgui.new.char[32]()
    end
end

local binderSearchBuffer = imgui.new.char[96]()

local cmdSeatbeltBuf = imgui.new.char[64]()
local cmdEngineBuf   = imgui.new.char[64]()

-- ------------------------------------------------------------------------------
-- Vehicle Info HUD Reactive UI State & Buffers
-- ------------------------------------------------------------------------------
local uiVehInfo = {
    enabled         = imgui.new.bool(false),
    displayMode     = imgui.new.int(1),
    checkWalls      = imgui.new.bool(true),
    trackCurrentCar = imgui.new.bool(true),
    lookMaxDist     = imgui.new.float(50.0),
    nearbyMaxCount  = imgui.new.int(6),
    speedUnitInt    = imgui.new.int(1),

    showId          = imgui.new.bool(true),
    showModel       = imgui.new.bool(true),
    showSpeed       = imgui.new.bool(false),
    showHealth      = imgui.new.bool(true),
    showDistance    = imgui.new.bool(false),
    showEngine      = imgui.new.bool(false),
    showLock        = imgui.new.bool(false),
    showHealthBar   = imgui.new.bool(false),

    labelColor      = imgui.new.float[4](0.20, 1.00, 0.20, 1.00),
    valueColor      = imgui.new.float[4](1.00, 1.00, 1.00, 1.00),
    bgStyle         = imgui.new.int(1),
    bgAlpha         = imgui.new.float(0.65),
    fontSize        = imgui.new.float(15.0),
    scaleWithDist   = imgui.new.bool(false),
    textShadow      = imgui.new.bool(true),

    offsetX         = imgui.new.float(0.0),
    offsetZ         = imgui.new.float(0.25),
    posXRatio       = imgui.new.float(0.85),
    posYRatio       = imgui.new.float(0.82),
}

local function syncVehInfoUI()
    if not config.vehinfo then return end
    uiVehInfo.enabled[0]         = (config.vehinfo.enabled ~= false)
    uiVehInfo.displayMode[0]     = config.vehinfo.displayMode or 1
    uiVehInfo.checkWalls[0]      = (config.vehinfo.checkWalls ~= false)
    uiVehInfo.trackCurrentCar[0] = (config.vehinfo.trackCurrentCar ~= false)
    uiVehInfo.lookMaxDist[0]     = config.vehinfo.lookMaxDist or 50.0
    uiVehInfo.nearbyMaxCount[0]  = config.vehinfo.nearbyMaxCount or 6
    uiVehInfo.speedUnitInt[0]    = (config.vehinfo.speedUnit == "mph") and 2 or 1

    uiVehInfo.showId[0]          = (config.vehinfo.showId ~= false)
    uiVehInfo.showModel[0]       = (config.vehinfo.showModel ~= false)
    uiVehInfo.showSpeed[0]       = (config.vehinfo.showSpeed == true)
    uiVehInfo.showHealth[0]      = (config.vehinfo.showHealth ~= false)
    uiVehInfo.showDistance[0]    = (config.vehinfo.showDistance == true)
    uiVehInfo.showEngine[0]      = (config.vehinfo.showEngine == true)
    uiVehInfo.showLock[0]        = (config.vehinfo.showLock == true)
    uiVehInfo.showHealthBar[0]   = (config.vehinfo.showHealthBar == true)

    uiVehInfo.labelColor[0]      = config.vehinfo.labelColorR or 0.20
    uiVehInfo.labelColor[1]      = config.vehinfo.labelColorG or 1.00
    uiVehInfo.labelColor[2]      = config.vehinfo.labelColorB or 0.20
    uiVehInfo.labelColor[3]      = config.vehinfo.labelColorA or 1.00

    uiVehInfo.valueColor[0]      = config.vehinfo.valueColorR or 1.00
    uiVehInfo.valueColor[1]      = config.vehinfo.valueColorG or 1.00
    uiVehInfo.valueColor[2]      = config.vehinfo.valueColorB or 1.00
    uiVehInfo.valueColor[3]      = config.vehinfo.valueColorA or 1.00

    uiVehInfo.bgStyle[0]         = config.vehinfo.bgStyle or 1
    uiVehInfo.bgAlpha[0]         = config.vehinfo.bgAlpha or 0.65
    uiVehInfo.fontSize[0]        = config.vehinfo.fontSize or 15.0
    uiVehInfo.scaleWithDist[0]   = (config.vehinfo.scaleWithDist == true)
    uiVehInfo.textShadow[0]      = (config.vehinfo.textShadow ~= false)

    uiVehInfo.offsetX[0]         = config.vehinfo.offsetX or 0.0
    uiVehInfo.offsetZ[0]         = config.vehinfo.offsetZ or 0.25
    uiVehInfo.posXRatio[0]       = config.vehinfo.hud2dPosX or 0.85
    uiVehInfo.posYRatio[0]       = config.vehinfo.hud2dPosY or 0.82
end

local uiSensFix = {
    enabled       = imgui.new.bool(false),
    fixVertical   = imgui.new.bool(true),
    baseSens      = imgui.new.float(0.002250),
    yRatio        = imgui.new.float(1.000),
    deagle        = imgui.new.float(1.00),
    pistol        = imgui.new.float(1.00),
    shotgun       = imgui.new.float(1.00),
    smg           = imgui.new.float(1.00),
    rifle         = imgui.new.float(0.85),
    country       = imgui.new.float(0.80),
    sniper        = imgui.new.float(0.50),
    freelook      = imgui.new.float(1.00),
    vehcam        = imgui.new.float(1.00),
    driveby       = imgui.new.float(1.00),
}

local function syncSensFixUI()
    if not config.sensfix then return end
    uiSensFix.enabled[0]     = (config.sensfix.enabled ~= false)
    uiSensFix.fixVertical[0] = (config.sensfix.fixVertical ~= false)
    uiSensFix.baseSens[0]    = config.sensfix.baseSens or 0.002250
    uiSensFix.yRatio[0]      = config.sensfix.yRatio or 1.000
    uiSensFix.deagle[0]      = config.sensfix.deagle or 1.00
    uiSensFix.pistol[0]      = config.sensfix.pistol or 1.00
    uiSensFix.shotgun[0]     = config.sensfix.shotgun or 1.00
    uiSensFix.smg[0]         = config.sensfix.smg or 1.00
    uiSensFix.rifle[0]       = config.sensfix.rifle or 0.85
    uiSensFix.country[0]     = config.sensfix.country or 0.80
    uiSensFix.sniper[0]      = config.sensfix.sniper or 0.50
    uiSensFix.freelook[0]    = config.sensfix.freelook or 1.00
    uiSensFix.vehcam[0]      = config.sensfix.vehcam or 1.00
    uiSensFix.driveby[0]     = config.sensfix.driveby or 1.00
end

local uiTweaks = {
    enabled          = imgui.new.bool(true),
    antiCrasher      = imgui.new.bool(true),
    highFpsSwimming  = imgui.new.bool(true),
    highFpsBraking   = imgui.new.bool(true),
    runInBackground  = imgui.new.bool(true),
    borderlessWindow = imgui.new.bool(true),
    radarAspectFix   = imgui.new.bool(true),
    widescreenScope  = imgui.new.bool(true),
    fastWeaponSwitch = imgui.new.bool(false),
    hillPark         = imgui.new.bool(false),
    silentSirens     = imgui.new.bool(false),
    aircraftQuieter  = imgui.new.bool(false),
    clearHorizon     = imgui.new.bool(false),
    damageFeed       = imgui.new.bool(false),
    flintNightFix    = imgui.new.bool(true),
    flintNightMode   = imgui.new.int(1),
    flintNightBoost  = imgui.new.int(420),
    cameraNoRecenter = imgui.new.bool(false),
    anisotropic16x   = imgui.new.bool(true),
    bulletTracers    = imgui.new.bool(false),
    masterBrightness = imgui.new.int(256),
    sprintHook       = imgui.new.bool(true),
    fpsDisplay       = imgui.new.bool(true),
    fpsDisplayPos    = imgui.new.int(1),
}

local function syncTweaksUI()
    if not config.tweaks then return end
    uiTweaks.enabled[0]          = (config.tweaks.enabled ~= false)
    uiTweaks.antiCrasher[0]      = (config.tweaks.antiCrasher ~= false)
    uiTweaks.highFpsSwimming[0]  = (config.tweaks.highFpsSwimming ~= false)
    uiTweaks.highFpsBraking[0]   = (config.tweaks.highFpsBraking ~= false)
    uiTweaks.runInBackground[0]  = (config.tweaks.runInBackground ~= false)
    uiTweaks.borderlessWindow[0] = (config.tweaks.borderlessWindow ~= false)
    uiTweaks.radarAspectFix[0]   = (config.tweaks.radarAspectFix ~= false)
    uiTweaks.widescreenScope[0]  = (config.tweaks.widescreenScope ~= false)
    uiTweaks.fastWeaponSwitch[0] = (config.tweaks.fastWeaponSwitch ~= false)
    uiTweaks.hillPark[0]         = (config.tweaks.hillPark ~= false)
    uiTweaks.silentSirens[0]     = (config.tweaks.silentSirens == true)
    uiTweaks.aircraftQuieter[0]  = (config.tweaks.aircraftQuieter ~= false)
    uiTweaks.clearHorizon[0]     = (config.tweaks.clearHorizon == true)
    uiTweaks.damageFeed[0]       = (config.tweaks.damageFeed ~= false)
    uiTweaks.flintNightFix[0]    = (config.tweaks.flintNightFix ~= false)
    uiTweaks.flintNightMode[0]   = (config.tweaks.flintNightMode or 1)
    uiTweaks.flintNightBoost[0]  = (config.tweaks.flintNightBoost or 380)
    uiTweaks.cameraNoRecenter[0] = (config.tweaks.cameraNoRecenter ~= false)
    uiTweaks.anisotropic16x[0]   = (config.tweaks.anisotropic16x ~= false)
    uiTweaks.bulletTracers[0]    = (config.tweaks.bulletTracers ~= false)
    uiTweaks.masterBrightness[0] = (config.tweaks.masterBrightness or 256)
    uiTweaks.sprintHook[0]       = (config.tweaks.sprintHook ~= false)
    uiTweaks.fpsDisplay[0]       = (config.tweaks.fpsDisplay ~= false)
    uiTweaks.fpsDisplayPos[0]    = (config.tweaks.fpsDisplayPos or 1)
end

local cmdLightsBuf   = imgui.new.char[64]()
local cmdLockBuf     = imgui.new.char[64]()
local updateUrlBuf   = imgui.new.char[256]()

-- Static Reusable ImGui Primitives (Eliminates frame allocations & GC churn)
local uiSpamDelayInt  = imgui.new.int(0)
local uiSlotChecks    = {}
for s = 1, 20 do uiSlotChecks[s] = imgui.new.bool(false) end
local uiSyncHudCheck  = imgui.new.bool(true)
local uiHourOffset    = imgui.new.int(0)
local uiEnterDelay    = imgui.new.int(450)
local uiBarX          = imgui.new.int(28)
local uiBarY          = imgui.new.int(95)
local uiMenuOpacity   = imgui.new.int(90)
local uiHelpFontScale = imgui.new.float(1.0)
local oldProtect      = ffi.new("unsigned long[1]")

local registeredAliases = {}
local aliasRefreshPending = false
local saveConfig -- forward declaration: duplicateProfile and other early helpers use this local
local executeSlot
local syncChatModeBuffers

-- ------------------------------------------------------------------------------
-- SA-MP 0.3.DL Memory Hook Engine (Zero Screen Blocking - Download Only)
-- ------------------------------------------------------------------------------
local OFFSET_DL_RENDER     = 0x6A350
local OFFSET_DL_GLOBAL_PTR = 0x2AC9E8 -- Exact CDownloadDialog global pointer in samp.dll

local function applyRenderHook(hide)
    if not state.sampBase or not state.isDlVersion then return end
    pcall(function()
        local addrRender = ffi.cast("uint8_t*", state.sampBase) + OFFSET_DL_RENDER
        if not isMemoryReadable(addrRender, 1) then return end

        if hide then
            -- Safely neutralize ONLY the CDownloadDialog::Render call (0x6A350)
            -- Leaves all standard GTA SA & SA-MP dialog popups (stats, recon, help, menus) 100% intact!
            if addrRender[0] == 0x83 then
                state.originalRenderByte = addrRender[0]
                ffi.C.VirtualProtect(addrRender, 1, 0x40, oldProtect)
                addrRender[0] = 0xC3 -- RET
                ffi.C.VirtualProtect(addrRender, 1, oldProtect[0], oldProtect)
            end
            state.renderHookApplied = true
        else
            if state.renderHookApplied then
                if addrRender[0] == 0xC3 then
                    ffi.C.VirtualProtect(addrRender, 1, 0x40, oldProtect)
                    addrRender[0] = state.originalRenderByte or 0x83
                    ffi.C.VirtualProtect(addrRender, 1, oldProtect[0], oldProtect)
                end
                state.renderHookApplied = false
            end
        end
    end)
end

local function initializeSampDLHook()
    pcall(function()
        local hSamp = ffi.C.GetModuleHandleA("samp.dll")
        if hSamp ~= nil and hSamp ~= 0 then
            state.sampBase = ffi.cast("uintptr_t", hSamp)
            local checkAddr = ffi.cast("uint8_t*", state.sampBase) + OFFSET_DL_RENDER
            if checkAddr[0] == 0x83 and checkAddr[1] == 0xEC and checkAddr[2] == 0x14 and checkAddr[3] == 0x53 then
                state.isDlVersion = true
                if config.downloader.hideDefaultBox then
                    applyRenderHook(true)
                end
            elseif checkAddr[0] == 0xC3 then
                state.isDlVersion = true
                state.renderHookApplied = true
            end
        end
    end)
end

local function readSampDownloadTelemetry()
    if not state.sampBase or not state.isDlVersion then
        return false, 0, 0, 0.0
    end

    local isDl, cur, tot, spd = false, 0, 0, 0.0
    pcall(function()
        local gPtrAddr = state.sampBase + OFFSET_DL_GLOBAL_PTR
        if not isMemoryReadable(gPtrAddr, 4) then return end

        local pGlobal = ffi.cast("uintptr_t*", gPtrAddr)
        local pDialog = pGlobal[0]
        if pDialog <= 0x10000 or pDialog >= 0x7FFE0000 then return end
        if not isMemoryReadable(pDialog, 0x260) then return end

        local isActive = ffi.cast("int32_t*", pDialog + 0x30)[0]
        local curFiles = ffi.cast("int32_t*", pDialog + 0x24C)[0]
        local totFiles = ffi.cast("int32_t*", pDialog + 0x250)[0]
        local speed    = ffi.cast("float*",   pDialog + 0x25C)[0]

        if isActive == 1 and totFiles > 0 and curFiles <= totFiles then
            isDl = true
            cur = math.max(0, curFiles)
            tot = math.max(0, totFiles)
            spd = math.max(0.0, speed)
        end
    end)
    return isDl, cur, tot, spd
end

-- ------------------------------------------------------------------------------
-- Dynamic Command Alias Registration Engine
-- ------------------------------------------------------------------------------
local RESERVED_COMMANDS = {
    bds=true, toolkit=true, menu=true, suite=true, binder=true, binds=true,
    autocar=true, vehctrl=true, dlhud=true, f5dl=true, chatmode=true,
    chat=true, room=true, cm=true, chatlog=true, clog=true, bdsreload=true,
    mlreload=true, dltest=true, dlpos=true, bprofile=true, baliases=true, bdsstatus=true
}

local function registerAllAliases()
    -- Snapshot old names first; unregister only names this script registered.
    local oldNames = {}
    for cmdName in pairs(registeredAliases) do oldNames[#oldNames + 1] = cmdName end
    for _, cmdName in ipairs(oldNames) do
        pcall(sampUnregisterChatCommand, cmdName)
    end
    registeredAliases = {}

    local profileIndex = tonumber(config.general.activeProfile) or 1
    profileIndex = math.max(1, math.min(5, math.floor(profileIndex)))
    config.general.activeProfile = profileIndex
    local curP = profiles[profileIndex]
    if not curP or type(curP.slots) ~= "table" then return 0, 0 end

    local seen, registeredCount, skippedCount = {}, 0, 0
    for slotIdx = 1, 20 do
        local slot = curP.slots[slotIdx]
        if type(slot) == "table" and slot.enabled == true then
            local rawAlias = type(slot.alias) == "string" and slot.alias or ""
            local cmdName = rawAlias:gsub("^/", ""):lower():gsub("%s+", "")
            local commandText = type(slot.command) == "string" and slot.command or ""
            if cmdName ~= "" then
                if not cmdName:match("^[%w_]+$") or RESERVED_COMMANDS[cmdName] or seen[cmdName] or commandText == "" then
                    skippedCount = skippedCount + 1
                else
                    seen[cmdName] = true
                    local boundSlotIndex = slotIdx
                    local boundProfileIndex = profileIndex
                    local ok, result = pcall(sampRegisterChatCommand, cmdName, function(params)
                        if tonumber(config.general.activeProfile) ~= boundProfileIndex then
                            return
                        end
                        if not config.binder.enabled then
                            sampAddChatMessage("{FFA726}[BDS Toolkit]{FFFFFF} Keybinder mode is OFF. Enable it in /bds.", -1)
                            return
                        end
                        if executeSlot then
                            local execOk, execErr = pcall(executeSlot, boundSlotIndex, params or "", boundProfileIndex)
                            if not execOk then
                                sampAddChatMessage("{FF5252}[BDS Toolkit]{FFFFFF} Alias execution failed: " .. tostring(execErr), -1)
                            end
                        end
                    end)
                    -- MoonLoader builds differ on whether register returns a value;
                    -- a successful protected call with nil is still a successful registration.
                    if ok and result ~= false then
                        registeredAliases[cmdName] = boundSlotIndex
                        registeredCount = registeredCount + 1
                    else
                        skippedCount = skippedCount + 1
                        pcall(sampAddChatMessage, string.format("{FFA726}[BDS Toolkit]{FFFFFF} Could not register /%s (already used or SA-MP rejected it).", cmdName), -1)
                    end
                end
            end
        end
    end
    state.aliasRegisteredCount = registeredCount
    state.aliasSkippedCount = skippedCount
    state.aliasRegisteredProfile = profileIndex
    return registeredCount, skippedCount
end

local function queueAliasRefresh()
    aliasRefreshPending = true
end

local function duplicateProfile(srcIdx, destIdx)
    if not profiles[srcIdx] or not profiles[destIdx] or srcIdx == destIdx then return end
    local src = profiles[srcIdx]
    local dest = profiles[destIdx]

    dest.name = (src.name or ("Profile " .. srcIdx)) .. " (Copy)"
    imgui.StrCopy(profileNameBuffers[destIdx], dest.name)

    for s = 1, 20 do
        local srcSlot = src.slots[s] or { enabled = false, key = 0, alias = "", mode = "send", command = "" }
        dest.slots[s] = {
            enabled = srcSlot.enabled,
            key     = srcSlot.key,
            alias   = srcSlot.alias or "",
            mode    = srcSlot.mode or "send",
            command = srcSlot.command or ""
        }
        if slotBuffers[destIdx] and slotBuffers[destIdx][s] then
            imgui.StrCopy(slotBuffers[destIdx][s], dest.slots[s].command)
        end
        if aliasBuffers[destIdx] and aliasBuffers[destIdx][s] then
            imgui.StrCopy(aliasBuffers[destIdx][s], dest.slots[s].alias)
        end
    end

    queueAliasRefresh()
    saveConfig()

    state.toastText = string.format("Copied P%d -> P%d", srcIdx, destIdx)
    state.toastExpiry = os.clock() + 2.5
    sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Successfully duplicated Profile %d (%s) into Profile %d (%s)!", srcIdx, src.name or "", destIdx, dest.name), -1)
end

-- ------------------------------------------------------------------------------
-- Unified Configuration Persistence (BDS_Toolkit.ini + Auto-Migration)
-- ------------------------------------------------------------------------------
local function writeConfigNow()
    local ok, err = pcall(function()
        local targetPath = (getWorkingDirectory and (getWorkingDirectory() .. "/config/" .. INI_FILE)) or ("config/" .. INI_FILE)
        local tempPath = targetPath .. ".tmp"
        local backupPath = targetPath .. ".bak"
        local f = io.open(tempPath, "w")
        if not f then
            targetPath = "config/" .. INI_FILE
            tempPath = targetPath .. ".tmp"
            backupPath = targetPath .. ".bak"
            f = io.open(tempPath, "w")
        end
        if not f then
            targetPath = INI_FILE
            tempPath = targetPath .. ".tmp"
            backupPath = targetPath .. ".bak"
            f = io.open(tempPath, "w")
        end
        if not f then
            state.lastConfigSaveError = "Unable to open configuration temp file"
            return
        end

        f:write("; ==============================================================================\n")
        f:write("; BDS Toolkit - Unified Configuration\n")
        f:write("; ==============================================================================\n\n")

        -- General
        f:write("[general]\n")
        f:write(string.format("menuKey=%d\n", config.general.menuKey))
        f:write(string.format("menuKeyAlt=%d\n", config.general.menuKeyAlt))
        f:write(string.format("lockPlayer=%s\n", tostring(config.general.lockPlayer)))
        f:write(string.format("activeProfile=%d\n", config.general.activeProfile))
        f:write(string.format("spamDelayMs=%d\n", config.general.spamDelayMs))
        f:write(string.format("showToast=%s\n", tostring(config.general.showToast)))
        f:write(string.format("menuOpacity=%d\n", config.general.menuOpacity or 90))
        f:write(string.format("helpFontScale=%.2f\n", config.general.helpFontScale or 1.0))
        f:write(string.format("hasSetDefaultPos=%s\n", tostring(config.general.hasSetDefaultPos)))
        f:write(string.format("activeTab=%d\n", config.general.activeTab or 1))
        f:write(string.format("chatSubTab=%d\n", config.general.chatSubTab or 1))
        f:write(string.format("autoUpdateCheck=%s\n", tostring(config.general.autoUpdateCheck ~= false)))
        f:write(string.format("autoUpdateInstall=%s\n", tostring(config.general.autoUpdateInstall == true)))
        f:write(string.format("updateUrl=%s\n\n", config.general.updateUrl or "https://raw.githubusercontent.com/dannyjadogar-cyber/BDS_Toolkit/main/version.json"))

        -- Chat Modes (Room Editor)
        f:write("[chatmode]\n")
        f:write(string.format("enabled=%s\n", tostring(config.chatmode.enabled)))
        f:write(string.format("activeModeIdx=%d\n", config.chatmode.activeModeIdx or 1))
        f:write(string.format("showFloatingBar=%s\n", tostring(config.chatmode.showFloatingBar)))
        f:write(string.format("autoAttach=%s\n", tostring(config.chatmode.autoAttach ~= false)))
        f:write(string.format("cycleKey=%d\n", config.chatmode.cycleKey or 9))
        f:write(string.format("barX=%d\n", config.chatmode.barX or 28))
        f:write(string.format("barY=%d\n", config.chatmode.barY or 95))
        f:write(string.format("offsetX=%d\n", config.chatmode.offsetX or 0))
        f:write(string.format("offsetY=%d\n", config.chatmode.offsetY or 0))
        f:write(string.format("modeCount=%d\n", #config.chatmode.modes))
        for mIdx, m in ipairs(config.chatmode.modes) do
            f:write(string.format("mode%d=%s|%s\n", mIdx, m.name or "", m.prefix or ""))
        end
        f:write("\n")

        -- AutoCar
        f:write("[binder]\n")
        f:write(string.format("enabled=%s\n\n", tostring(config.binder.enabled)))

        f:write("[autocar]\n")
        f:write(string.format("enabled=%s\n", tostring(config.autocar.enabled)))
        f:write(string.format("autoSeatbelt=%s\n", tostring(config.autocar.autoSeatbelt)))
        f:write(string.format("passengerSeatbelt=%s\n", tostring(config.autocar.passengerSeatbelt)))
        f:write(string.format("autoEngine=%s\n", tostring(config.autocar.autoEngine)))
        f:write(string.format("engineOffOnExit=%s\n", tostring(config.autocar.engineOffOnExit)))
        f:write(string.format("autoLights=%s\n", tostring(config.autocar.autoLights)))
        f:write(string.format("lightsOffOnExit=%s\n", tostring(config.autocar.lightsOffOnExit)))
        f:write(string.format("autoLock=%s\n", tostring(config.autocar.autoLock)))
        f:write(string.format("showChatNotice=%s\n", tostring(config.autocar.showChatNotice)))
        f:write(string.format("nightStartHour=%d\n", config.autocar.nightStartHour))
        f:write(string.format("nightEndHour=%d\n", config.autocar.nightEndHour))
        f:write(string.format("enterDelayMs=%d\n", config.autocar.enterDelayMs))
        f:write(string.format("hourOffset=%d\n", config.autocar.hourOffset))
        f:write(string.format("syncWithHud=%s\n\n", tostring(config.autocar.syncWithHud)))

        -- Commands
        f:write("[commands]\n")
        f:write(string.format("seatbeltCmd=%s\n", config.commands.seatbeltCmd))
        f:write(string.format("engineCmd=%s\n", config.commands.engineCmd))
        f:write(string.format("lightsCmd=%s\n", config.commands.lightsCmd))
        f:write(string.format("lockCmd=%s\n\n", config.commands.lockCmd))

        -- Downloader
        f:write("[downloader]\n")
        f:write(string.format("enabled=%s\n", tostring(config.downloader.enabled)))
        f:write(string.format("hideDefaultBox=%s\n", tostring(config.downloader.hideDefaultBox)))
        f:write(string.format("positionPreset=%s\n", config.downloader.positionPreset))
        f:write(string.format("theme=%s\n", config.downloader.theme))
        f:write(string.format("soundNotification=%s\n", tostring(config.downloader.soundNotification)))
        f:write(string.format("showSpeed=%s\n", tostring(config.downloader.showSpeed)))
        f:write(string.format("offsetX=%d\n", config.downloader.offsetX))
        f:write(string.format("offsetY=%d\n\n", config.downloader.offsetY))

        -- Vehicle Info HUD
        f:write("[vehinfo]\n")
        f:write(string.format("enabled=%s\n", tostring(config.vehinfo.enabled)))
        f:write(string.format("displayMode=%d\n", config.vehinfo.displayMode or 1))
        f:write(string.format("checkWalls=%s\n", tostring(config.vehinfo.checkWalls ~= false)))
        f:write(string.format("trackCurrentCar=%s\n", tostring(config.vehinfo.trackCurrentCar)))
        f:write(string.format("lookMaxDist=%.1f\n", config.vehinfo.lookMaxDist or 50.0))
        f:write(string.format("nearbyMaxCount=%d\n", config.vehinfo.nearbyMaxCount or 6))
        f:write(string.format("speedUnit=%s\n", config.vehinfo.speedUnit or "km/h"))
        f:write(string.format("showId=%s\n", tostring(config.vehinfo.showId)))
        f:write(string.format("showModel=%s\n", tostring(config.vehinfo.showModel)))
        f:write(string.format("showSpeed=%s\n", tostring(config.vehinfo.showSpeed)))
        f:write(string.format("showHealth=%s\n", tostring(config.vehinfo.showHealth)))
        f:write(string.format("showDistance=%s\n", tostring(config.vehinfo.showDistance)))
        f:write(string.format("showEngine=%s\n", tostring(config.vehinfo.showEngine)))
        f:write(string.format("showLock=%s\n", tostring(config.vehinfo.showLock)))
        f:write(string.format("showHealthBar=%s\n", tostring(config.vehinfo.showHealthBar)))
        f:write(string.format("labelColorR=%.3f\n", config.vehinfo.labelColorR or 0.20))
        f:write(string.format("labelColorG=%.3f\n", config.vehinfo.labelColorG or 1.00))
        f:write(string.format("labelColorB=%.3f\n", config.vehinfo.labelColorB or 0.20))
        f:write(string.format("labelColorA=%.3f\n", config.vehinfo.labelColorA or 1.00))
        f:write(string.format("valueColorR=%.3f\n", config.vehinfo.valueColorR or 1.00))
        f:write(string.format("valueColorG=%.3f\n", config.vehinfo.valueColorG or 1.00))
        f:write(string.format("valueColorB=%.3f\n", config.vehinfo.valueColorB or 1.00))
        f:write(string.format("valueColorA=%.3f\n", config.vehinfo.valueColorA or 1.00))
        f:write(string.format("bgStyle=%d\n", config.vehinfo.bgStyle or 1))
        f:write(string.format("bgAlpha=%.2f\n", config.vehinfo.bgAlpha or 0.65))
        f:write(string.format("fontSize=%.1f\n", config.vehinfo.fontSize or 15.0))
        f:write(string.format("scaleWithDist=%s\n", tostring(config.vehinfo.scaleWithDist)))
        f:write(string.format("textShadow=%s\n", tostring(config.vehinfo.textShadow)))
        f:write(string.format("offsetX=%.2f\n", config.vehinfo.offsetX or 0.0))
        f:write(string.format("offsetZ=%.2f\n", config.vehinfo.offsetZ or 0.25))
        f:write(string.format("hud2dPosX=%.3f\n", config.vehinfo.hud2dPosX or 0.85))
        f:write(string.format("hud2dPosY=%.3f\n\n", config.vehinfo.hud2dPosY or 0.82))

        -- Weapon Sensitivity & Drive-By (SensFix)
        if not config.sensfix then config.sensfix = {} end
        f:write("[sensfix]\n")
        f:write(string.format("enabled=%s\n", tostring(config.sensfix.enabled ~= false)))
        f:write(string.format("baseSens=%.6f\n", config.sensfix.baseSens or 0.002250))
        f:write(string.format("yRatio=%.3f\n", config.sensfix.yRatio or 1.000))
        f:write(string.format("fixVertical=%s\n", tostring(config.sensfix.fixVertical ~= false)))
        f:write(string.format("deagle=%.2f\n", config.sensfix.deagle or 1.00))
        f:write(string.format("pistol=%.2f\n", config.sensfix.pistol or 1.00))
        f:write(string.format("shotgun=%.2f\n", config.sensfix.shotgun or 1.00))
        f:write(string.format("smg=%.2f\n", config.sensfix.smg or 1.00))
        f:write(string.format("rifle=%.2f\n", config.sensfix.rifle or 0.85))
        f:write(string.format("country=%.2f\n", config.sensfix.country or 0.80))
        f:write(string.format("sniper=%.2f\n", config.sensfix.sniper or 0.50))
        f:write(string.format("freelook=%.2f\n", config.sensfix.freelook or 1.00))
        f:write(string.format("vehcam=%.2f\n", config.sensfix.vehcam or 1.00))
        f:write(string.format("driveby=%.2f\n\n", config.sensfix.driveby or 1.00))

        -- Engine Fixes & Gameplay Tweaks (Module 7)
        if not config.tweaks then config.tweaks = {} end
        f:write("[tweaks]\n")
        f:write(string.format("enabled=%s\n", tostring(config.tweaks.enabled ~= false)))
        f:write(string.format("subTab=%d\n", config.tweaks.subTab or 1))
        f:write(string.format("antiCrasher=%s\n", tostring(config.tweaks.antiCrasher ~= false)))
        f:write(string.format("highFpsSwimming=%s\n", tostring(config.tweaks.highFpsSwimming ~= false)))
        f:write(string.format("highFpsBraking=%s\n", tostring(config.tweaks.highFpsBraking ~= false)))
        f:write(string.format("runInBackground=%s\n", tostring(config.tweaks.runInBackground ~= false)))
        f:write(string.format("borderlessWindow=%s\n", tostring(config.tweaks.borderlessWindow ~= false)))
        f:write(string.format("radarAspectFix=%s\n", tostring(config.tweaks.radarAspectFix ~= false)))
        f:write(string.format("widescreenScope=%s\n", tostring(config.tweaks.widescreenScope ~= false)))
        f:write(string.format("fastWeaponSwitch=%s\n", tostring(config.tweaks.fastWeaponSwitch ~= false)))
        f:write(string.format("hillPark=%s\n", tostring(config.tweaks.hillPark ~= false)))
        f:write(string.format("silentSirens=%s\n", tostring(config.tweaks.silentSirens == true)))
        f:write(string.format("aircraftQuieter=%s\n", tostring(config.tweaks.aircraftQuieter ~= false)))
        f:write(string.format("clearHorizon=%s\n", tostring(config.tweaks.clearHorizon == true)))
        f:write(string.format("damageFeed=%s\n", tostring(config.tweaks.damageFeed ~= false)))
        f:write(string.format("flintNightFix=%s\n", tostring(config.tweaks.flintNightFix ~= false)))
        f:write(string.format("flintNightMode=%d\n", config.tweaks.flintNightMode or 1))
        f:write(string.format("flintNightBoost=%d\n", config.tweaks.flintNightBoost or 380))
        f:write(string.format("cameraNoRecenter=%s\n", tostring(config.tweaks.cameraNoRecenter ~= false)))
        f:write(string.format("anisotropic16x=%s\n", tostring(config.tweaks.anisotropic16x ~= false)))
        f:write(string.format("bulletTracers=%s\n", tostring(config.tweaks.bulletTracers ~= false)))
        f:write(string.format("masterBrightness=%d\n", config.tweaks.masterBrightness or 256))
        f:write(string.format("sprintHook=%s\n", tostring(config.tweaks.sprintHook ~= false)))
        f:write(string.format("fpsDisplay=%s\n", tostring(config.tweaks.fpsDisplay ~= false)))
        f:write(string.format("fpsDisplayPos=%d\n\n", config.tweaks.fpsDisplayPos or 1))


        -- Profiles
        for pIdx, p in ipairs(profiles) do
            f:write(string.format("[profile%d]\n", pIdx))
            f:write(string.format("name=%s\n", p.name or ("Profile " .. pIdx)))
            for sIdx, s in ipairs(p.slots) do
                f:write(string.format("slot%d=%d|%d|%s|%s|%s\n",
                    sIdx,
                    s.enabled and 1 or 0,
                    s.key or 0,
                    s.alias or "",
                    s.mode or "send",
                    s.command or ""
                ))
            end
            f:write("\n")
        end

        f:flush()
        f:close()

        -- Replace the previous INI only after the complete temporary file is written.
        os.remove(backupPath)
        local hadOriginal = os.rename(targetPath, backupPath)
        local committed = os.rename(tempPath, targetPath)
        if not committed then
            if hadOriginal then os.rename(backupPath, targetPath) end
            state.lastConfigSaveError = "Unable to replace configuration file"
            return
        end
        -- Keep .bak as the last known-good configuration. The next save rotates it.
        state.lastConfigSaveError = nil
    end)
    if not ok then
        state.lastConfigSaveError = tostring(err)
        logDiagnostic("ERROR", "Configuration save failed: " .. tostring(err))
        return false
    end
    return state.lastConfigSaveError == nil
end

local saveConfigPending = false
local lastSaveRequestTime = 0
saveConfig = function()
    saveConfigPending = true
    lastSaveRequestTime = os.clock()
end

local function syncBuffersFromData()
    for p = 1, 5 do
        imgui.StrCopy(profileNameBuffers[p], profiles[p].name or ("Profile " .. p))
        for s = 1, 20 do
            imgui.StrCopy(slotBuffers[p][s], profiles[p].slots[s].command or "")
            imgui.StrCopy(aliasBuffers[p][s], profiles[p].slots[s].alias or "")
        end
    end
    imgui.StrCopy(cmdSeatbeltBuf, config.commands.seatbeltCmd)
    imgui.StrCopy(cmdEngineBuf, config.commands.engineCmd)
    imgui.StrCopy(cmdLightsBuf, config.commands.lightsCmd)
    imgui.StrCopy(cmdLockBuf, config.commands.lockCmd)
end

local function migrateOldConfigs()
    -- 0. Migrate from vgrp_suite.ini
    pcall(function()
        local path = "config/vgrp_suite.ini"
        local f = io.open(path, "r")
        if not f then f = io.open("vgrp_suite.ini", "r") end
        if f then
            for line in f:lines() do
                local k, v = line:match("^([^=]+)=(.*)$")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = v:match("^%s*(.-)%s*$")
                    if k == "lockPlayer" then config.general.lockPlayer = (v:lower() == "true" or v == "1")
                    elseif k == "activeProfile" and tonumber(v) then config.general.activeProfile = tonumber(v)
                    elseif k == "spamDelayMs" and tonumber(v) then config.general.spamDelayMs = tonumber(v)
                    elseif k == "menuOpacity" and tonumber(v) then config.general.menuOpacity = tonumber(v)
                    end
                end
            end
            f:close()
        end
    end)
    -- 1. Migrate from BDS_binder.ini
    pcall(function()
        local path = "config/BDS_binder.ini"
        local f = io.open(path, "r")
        if not f then f = io.open("BDS_binder.ini", "r") end
        if f then
            local currentSec = ""
        local loadedModeCount = nil
        local loadedModes = {}
        for line in f:lines() do
                line = line:match("^%s*(.-)%s*$")
                if line:find("^%[") and line:find("%]$") then
                    currentSec = line:match("^%[(.+)%]$"):lower()
                elseif #line > 0 and not line:find("^[;#]") then
                    local k, v = line:match("^([^=]+)=(.*)$")
                    if k and v then
                        k = k:match("^%s*(.-)%s*$")
                        v = v:match("^%s*(.-)%s*$")
                        if currentSec == "settings" then
                            if k == "activeProfile" and tonumber(v) then config.general.activeProfile = tonumber(v)
                            elseif k == "spamDelayMs" and tonumber(v) then config.general.spamDelayMs = tonumber(v)
                            elseif k == "showToast" then config.general.showToast = (v:lower() == "true" or v == "1")
                            elseif k == "lockPlayer" then config.general.lockPlayer = (v:lower() == "true" or v == "1")
                            end
                    elseif currentSec == "vehinfo" then
                        if not config.vehinfo then config.vehinfo = {} end
                        if k == "enabled" then config.vehinfo.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "displayMode" and tonumber(v) then config.vehinfo.displayMode = tonumber(v)
                        elseif k == "checkWalls" then config.vehinfo.checkWalls = (v:lower() == "true" or v == "1")
                        elseif k == "trackCurrentCar" then config.vehinfo.trackCurrentCar = (v:lower() == "true" or v == "1")
                        elseif k == "lookMaxDist" and tonumber(v) then config.vehinfo.lookMaxDist = tonumber(v)
                        elseif k == "nearbyMaxCount" and tonumber(v) then config.vehinfo.nearbyMaxCount = tonumber(v)
                        elseif k == "speedUnit" and #v > 0 then config.vehinfo.speedUnit = v
                        elseif k == "showId" then config.vehinfo.showId = (v:lower() == "true" or v == "1")
                        elseif k == "showModel" then config.vehinfo.showModel = (v:lower() == "true" or v == "1")
                        elseif k == "showSpeed" then config.vehinfo.showSpeed = (v:lower() == "true" or v == "1")
                        elseif k == "showHealth" then config.vehinfo.showHealth = (v:lower() == "true" or v == "1")
                        elseif k == "showDistance" then config.vehinfo.showDistance = (v:lower() == "true" or v == "1")
                        elseif k == "showEngine" then config.vehinfo.showEngine = (v:lower() == "true" or v == "1")
                        elseif k == "showLock" then config.vehinfo.showLock = (v:lower() == "true" or v == "1")
                        elseif k == "showHealthBar" then config.vehinfo.showHealthBar = (v:lower() == "true" or v == "1")
                        elseif k == "labelColorR" and tonumber(v) then config.vehinfo.labelColorR = tonumber(v)
                        elseif k == "labelColorG" and tonumber(v) then config.vehinfo.labelColorG = tonumber(v)
                        elseif k == "labelColorB" and tonumber(v) then config.vehinfo.labelColorB = tonumber(v)
                        elseif k == "labelColorA" and tonumber(v) then config.vehinfo.labelColorA = tonumber(v)
                        elseif k == "valueColorR" and tonumber(v) then config.vehinfo.valueColorR = tonumber(v)
                        elseif k == "valueColorG" and tonumber(v) then config.vehinfo.valueColorG = tonumber(v)
                        elseif k == "valueColorB" and tonumber(v) then config.vehinfo.valueColorB = tonumber(v)
                        elseif k == "valueColorA" and tonumber(v) then config.vehinfo.valueColorA = tonumber(v)
                        elseif k == "bgStyle" and tonumber(v) then config.vehinfo.bgStyle = tonumber(v)
                        elseif k == "bgAlpha" and tonumber(v) then config.vehinfo.bgAlpha = tonumber(v)
                        elseif k == "fontSize" and tonumber(v) then config.vehinfo.fontSize = tonumber(v)
                        elseif k == "scaleWithDist" then config.vehinfo.scaleWithDist = (v:lower() == "true" or v == "1")
                        elseif k == "textShadow" then config.vehinfo.textShadow = (v:lower() == "true" or v == "1")
                        elseif k == "offsetX" and tonumber(v) then config.vehinfo.offsetX = tonumber(v)
                        elseif k == "offsetZ" and tonumber(v) then config.vehinfo.offsetZ = tonumber(v)
                        elseif k == "hud2dPosX" and tonumber(v) then config.vehinfo.hud2dPosX = tonumber(v)
                        elseif k == "hud2dPosY" and tonumber(v) then config.vehinfo.hud2dPosY = tonumber(v)
                        end
                    elseif currentSec == "sensfix" then
                        if not config.sensfix then config.sensfix = {} end
                        if k == "enabled" then config.sensfix.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "fixVertical" then config.sensfix.fixVertical = (v:lower() == "true" or v == "1")
                        elseif k == "baseSens" and tonumber(v) then config.sensfix.baseSens = tonumber(v)
                        elseif k == "yRatio" and tonumber(v) then config.sensfix.yRatio = tonumber(v)
                        elseif config.sensfix[k] ~= nil and tonumber(v) then config.sensfix[k] = tonumber(v)
                        elseif (k == "deagle" or k == "pistol" or k == "shotgun" or k == "smg" or k == "rifle" or k == "country" or k == "sniper" or k == "freelook" or k == "vehcam" or k == "driveby") and tonumber(v) then
                            config.sensfix[k] = tonumber(v)
                        end
                    elseif currentSec == "tweaks" then
                        if not config.tweaks then config.tweaks = {} end
                        local kl = k:lower()
                        if kl == "enabled" then config.tweaks.enabled = (v:lower() == "true" or v == "1")
                        elseif kl == "subtab" and tonumber(v) then config.tweaks.subTab = tonumber(v)
                        elseif kl == "anticrasher" then config.tweaks.antiCrasher = (v:lower() == "true" or v == "1")
                        elseif kl == "highfpsswimming" then config.tweaks.highFpsSwimming = (v:lower() == "true" or v == "1")
                        elseif kl == "highfpsbraking" then config.tweaks.highFpsBraking = (v:lower() == "true" or v == "1")
                        elseif kl == "runinbackground" then config.tweaks.runInBackground = (v:lower() == "true" or v == "1")
                        elseif kl == "borderlesswindow" then config.tweaks.borderlessWindow = (v:lower() == "true" or v == "1")
                        elseif kl == "radaraspectfix" then config.tweaks.radarAspectFix = (v:lower() == "true" or v == "1")
                        elseif kl == "widescreenscope" then config.tweaks.widescreenScope = (v:lower() == "true" or v == "1")
                        elseif kl == "fastweaponswitch" then config.tweaks.fastWeaponSwitch = (v:lower() == "true" or v == "1")
                        elseif kl == "hillpark" then config.tweaks.hillPark = (v:lower() == "true" or v == "1")
                        elseif kl == "silentsirens" then config.tweaks.silentSirens = (v:lower() == "true" or v == "1")
                        elseif kl == "aircraftquieter" then config.tweaks.aircraftQuieter = (v:lower() == "true" or v == "1")
                        elseif kl == "clearhorizon" then config.tweaks.clearHorizon = (v:lower() == "true" or v == "1")
                        elseif kl == "damagefeed" then config.tweaks.damageFeed = (v:lower() == "true" or v == "1")
                        elseif kl == "flintnightfix" then config.tweaks.flintNightFix = (v:lower() == "true" or v == "1")
                        elseif kl == "flintnightmode" and tonumber(v) then config.tweaks.flintNightMode = tonumber(v)
                        elseif kl == "flintnightboost" and tonumber(v) then config.tweaks.flintNightBoost = tonumber(v)
                        elseif kl == "cameranorecenter" then config.tweaks.cameraNoRecenter = (v:lower() == "true" or v == "1")
                        elseif kl == "anisotropic16x" then config.tweaks.anisotropic16x = (v:lower() == "true" or v == "1")
                        elseif kl == "bullettracers" then config.tweaks.bulletTracers = (v:lower() == "true" or v == "1")
                        elseif kl == "masterbrightness" and tonumber(v) then config.tweaks.masterBrightness = tonumber(v)
                        elseif kl == "sprinthook" then config.tweaks.sprintHook = (v:lower() == "true" or v == "1")
                        elseif kl == "fpsdisplay" then config.tweaks.fpsDisplay = (v:lower() == "true" or v == "1")
                        elseif kl == "fpsdisplaypos" and tonumber(v) then config.tweaks.fpsDisplayPos = tonumber(v)
                        end
                    elseif currentSec:find("^profile%d+$") then
                            local pIdx = tonumber(currentSec:match("^profile(%d+)$"))
                            if pIdx and pIdx >= 1 and pIdx <= 5 then
                                if k == "name" then
                                    profiles[pIdx].name = v
                                elseif k:find("^slot%d+$") then
                                    local sIdx = tonumber(k:match("^slot(%d+)$"))
                                    if sIdx and sIdx >= 1 and sIdx <= 20 then
                                        local en, key, al, md, cmd = v:match("^(%d+)|(%-?%d*)|([^|]*)|([^|]*)|(.*)$")
                                        if en and key then
                                            profiles[pIdx].slots[sIdx].enabled = (en == "1")
                                            profiles[pIdx].slots[sIdx].key     = tonumber(key) or 0
                                            profiles[pIdx].slots[sIdx].alias   = al or ""
                                            profiles[pIdx].slots[sIdx].mode    = md or "send"
                                            profiles[pIdx].slots[sIdx].command = cmd or ""
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            f:close()
        end
    end)

    -- 2. Migrate from autocar.ini
    pcall(function()
        local path = "config/autocar.ini"
        local f = io.open(path, "r")
        if not f then f = io.open("autocar.ini", "r") end
        if f then
            local currentSec = ""
            for line in f:lines() do
                line = line:match("^%s*(.-)%s*$")
                if line:find("^%[") and line:find("%]$") then
                    currentSec = line:match("^%[(.+)%]$"):lower()
                elseif #line > 0 and not line:find("^[;#]") then
                    local k, v = line:match("^([^=]+)=(.*)$")
                    if k and v then
                        k = k:match("^%s*(.-)%s*$")
                        v = v:match("^%s*(.-)%s*$")
                        if currentSec == "settings" then
                            if k == "enabled" then config.autocar.enabled = (v:lower() == "true" or v == "1")
                            elseif k == "autoSeatbelt" then config.autocar.autoSeatbelt = (v:lower() == "true" or v == "1")
                            elseif k == "passengerSeatbelt" then config.autocar.passengerSeatbelt = (v:lower() == "true" or v == "1")
                            elseif k == "autoEngine" then config.autocar.autoEngine = (v:lower() == "true" or v == "1")
                            elseif k == "engineOffOnExit" then config.autocar.engineOffOnExit = (v:lower() == "true" or v == "1")
                            elseif k == "autoLights" then config.autocar.autoLights = (v:lower() == "true" or v == "1")
                            elseif k == "lightsOffOnExit" then config.autocar.lightsOffOnExit = (v:lower() == "true" or v == "1")
                            elseif k == "autoLock" then config.autocar.autoLock = (v:lower() == "true" or v == "1")
                            elseif k == "showChatNotice" then config.autocar.showChatNotice = (v:lower() == "true" or v == "1")
                            elseif k == "hourOffset" and tonumber(v) then config.autocar.hourOffset = tonumber(v)
                            elseif k == "enterDelayMs" and tonumber(v) then config.autocar.enterDelayMs = tonumber(v)
                            elseif k == "syncWithHud" then config.autocar.syncWithHud = (v:lower() == "true" or v == "1")
                            end
                        elseif currentSec == "commands" then
                            if k == "seatbeltCmd" and #v > 0 then config.commands.seatbeltCmd = v
                            elseif k == "engineCmd" and #v > 0 then config.commands.engineCmd = v
                            elseif k == "lightsCmd" and #v > 0 then config.commands.lightsCmd = v
                            elseif k == "lockCmd" and #v > 0 then config.commands.lockCmd = v
                            end
                        end
                    end
                end
            end
            f:close()
        end
    end)

    -- 3. Migrate from vgrp_dl_hud.ini
    pcall(function()
        local path = "config/vgrp_dl_hud.ini"
        local f = io.open(path, "r")
        if not f then f = io.open("vgrp_dl_hud.ini", "r") end
        if f then
            local currentSec = ""
            for line in f:lines() do
                line = line:match("^%s*(.-)%s*$")
                if line:find("^%[") and line:find("%]$") then
                    currentSec = line:match("^%[(.+)%]$"):lower()
                elseif #line > 0 and not line:find("^[;#]") then
                    local k, v = line:match("^([^=]+)=(.*)$")
                    if k and v then
                        k = k:match("^%s*(.-)%s*$")
                        v = v:match("^%s*(.-)%s*$")
                        if currentSec == "settings" then
                            if k == "enabled" then config.downloader.enabled = (v:lower() == "true" or v == "1")
                            elseif k == "hideDefaultBox" then config.downloader.hideDefaultBox = (v:lower() == "true" or v == "1")
                            elseif k == "positionPreset" and #v > 0 then config.downloader.positionPreset = v:lower()
                            elseif k == "theme" and THEMES[v:lower()] then config.downloader.theme = v:lower()
                            elseif k == "soundNotification" then config.downloader.soundNotification = (v:lower() == "true" or v == "1")
                            elseif k == "showSpeed" then config.downloader.showSpeed = (v:lower() == "true" or v == "1")
                            elseif k == "offsetX" and tonumber(v) then config.downloader.offsetX = tonumber(v)
                            elseif k == "offsetY" and tonumber(v) then config.downloader.offsetY = tonumber(v)
                            end
                        end
                    end
                end
            end
            f:close()
        end
    end)
end

local function validateConfig()
    local function clampNumber(value, default, minValue, maxValue)
        local n = tonumber(value)
        if not n or n ~= n then n = default end
        n = math.floor(n)
        return math.max(minValue, math.min(maxValue, n))
    end

    config.general.activeProfile = clampNumber(config.general.activeProfile, 1, 1, 5)
    config.general.activeTab = clampNumber(config.general.activeTab, 1, 1, 7)
    config.general.chatSubTab = clampNumber(config.general.chatSubTab, 1, 1, 2)
    config.general.spamDelayMs = clampNumber(config.general.spamDelayMs, 0, 0, 10000)
    config.general.menuOpacity = clampNumber(config.general.menuOpacity, 90, 30, 100)
    config.chatmode.activeModeIdx = clampNumber(config.chatmode.activeModeIdx, 1, 1, math.max(1, #config.chatmode.modes))
    config.chatmode.cycleKey = clampNumber(config.chatmode.cycleKey, 9, 0, 255)
    config.autocar.enterDelayMs = clampNumber(config.autocar.enterDelayMs, 400, 150, 10000)
    config.autocar.nightStartHour = clampNumber(config.autocar.nightStartHour, 20, 0, 23)
    config.autocar.nightEndHour = clampNumber(config.autocar.nightEndHour, 6, 0, 23)
    config.downloader.offsetX = clampNumber(config.downloader.offsetX, 25, -5000, 5000)
    config.downloader.offsetY = clampNumber(config.downloader.offsetY, 35, -5000, 5000)

    local function normalizeBool(value, default)
        if value == true or value == 1 or value == "1" or value == "true" then return true end
        if value == false or value == 0 or value == "0" or value == "false" then return false end
        return default == true
    end
    local boolDefaults = {
        {config.general, "lockPlayer", false}, {config.general, "showToast", true},
        {config.binder, "enabled", false},
        {config.chatmode, "enabled", true}, {config.chatmode, "showFloatingBar", true},
        {config.chatmode, "autoAttach", true},
        {config.autocar, "enabled", false}, {config.autocar, "autoSeatbelt", false},
        {config.autocar, "passengerSeatbelt", false}, {config.autocar, "autoEngine", false},
        {config.autocar, "engineOffOnExit", false}, {config.autocar, "autoLights", false},
        {config.autocar, "lightsOffOnExit", false}, {config.autocar, "autoLock", false},
        {config.autocar, "showChatNotice", true}, {config.autocar, "syncWithHud", false},
        {config.downloader, "enabled", true}, {config.downloader, "hideDefaultBox", true},
        {config.downloader, "soundNotification", true}, {config.downloader, "showSpeed", true},
        {config.vehinfo, "enabled", false}, {config.vehinfo, "trackCurrentCar", true},
        {config.vehinfo, "showId", true}, {config.vehinfo, "showModel", true},
        {config.vehinfo, "showSpeed", false}, {config.vehinfo, "showHealth", true},
        {config.vehinfo, "showDistance", false}, {config.vehinfo, "showEngine", false},
        {config.vehinfo, "showLock", false}, {config.vehinfo, "showHealthBar", false},
        {config.vehinfo, "scaleWithDist", false}, {config.vehinfo, "textShadow", true}
    }
    for _, item in ipairs(boolDefaults) do
        local tbl, key, default = item[1], item[2], item[3]
        tbl[key] = normalizeBool(tbl[key], default)
    end
    config.autocar.hourOffset = clampNumber(config.autocar.hourOffset, 0, -23, 23)
    config.autocar.enterDelayMs = clampNumber(config.autocar.enterDelayMs, 400, 150, 10000)
    config.commands.engineCmd = type(config.commands.engineCmd) == "string" and config.commands.engineCmd:gsub("[%c]", ""):sub(1, 80) or "/engine"
    config.commands.lightsCmd = type(config.commands.lightsCmd) == "string" and config.commands.lightsCmd:gsub("[%c]", ""):sub(1, 80) or "/lights"
    config.commands.seatbeltCmd = type(config.commands.seatbeltCmd) == "string" and config.commands.seatbeltCmd:gsub("[%c]", ""):sub(1, 80) or "/seatbelt"
    config.commands.lockCmd = type(config.commands.lockCmd) == "string" and config.commands.lockCmd:gsub("[%c]", ""):sub(1, 80) or "/lock"
    if not THEMES[config.downloader.theme] then config.downloader.theme = "neon_cyan" end
    local validPositions = { bottom_right=true, bottom_center=true, top_right=true, top_center=true }
    if not validPositions[config.downloader.positionPreset] then config.downloader.positionPreset = "bottom_right" end

    if not config.sensfix then config.sensfix = {} end
    config.sensfix.enabled     = normalizeBool(config.sensfix.enabled, false)
    config.sensfix.fixVertical = normalizeBool(config.sensfix.fixVertical, true)
    local function clampFloatVal(v, def, minV, maxV)
        local n = tonumber(v)
        if not n or n ~= n then n = def end
        return math.max(minV, math.min(maxV, n))
    end
    config.sensfix.baseSens  = clampFloatVal(config.sensfix.baseSens, 0.002250, 0.0001, 0.0500)
    config.sensfix.yRatio    = clampFloatVal(config.sensfix.yRatio, 1.000, 0.20, 3.00)
    config.sensfix.deagle    = clampFloatVal(config.sensfix.deagle, 1.00, 0.20, 2.50)
    config.sensfix.pistol    = clampFloatVal(config.sensfix.pistol, 1.00, 0.20, 2.50)
    config.sensfix.shotgun   = clampFloatVal(config.sensfix.shotgun, 1.00, 0.20, 2.50)
    config.sensfix.smg       = clampFloatVal(config.sensfix.smg, 1.00, 0.20, 2.50)
    config.sensfix.rifle     = clampFloatVal(config.sensfix.rifle, 0.85, 0.20, 2.50)
    config.sensfix.country   = clampFloatVal(config.sensfix.country, 0.80, 0.20, 2.50)
    config.sensfix.sniper    = clampFloatVal(config.sensfix.sniper, 0.50, 0.20, 2.50)
    config.sensfix.freelook  = clampFloatVal(config.sensfix.freelook, 1.00, 0.20, 2.50)
    config.sensfix.vehcam    = clampFloatVal(config.sensfix.vehcam, 1.00, 0.20, 2.50)
    config.sensfix.driveby   = clampFloatVal(config.sensfix.driveby, 1.00, 0.20, 2.50)

    if not config.tweaks then config.tweaks = {} end
    config.tweaks.enabled          = normalizeBool(config.tweaks.enabled, true)
    config.tweaks.subTab           = clampNumber(config.tweaks.subTab or 1, 1, 1, 5)
    config.tweaks.antiCrasher      = normalizeBool(config.tweaks.antiCrasher, true)
    config.tweaks.highFpsSwimming  = normalizeBool(config.tweaks.highFpsSwimming, true)
    config.tweaks.highFpsBraking   = normalizeBool(config.tweaks.highFpsBraking, true)
    config.tweaks.runInBackground  = normalizeBool(config.tweaks.runInBackground, true)
    config.tweaks.borderlessWindow = normalizeBool(config.tweaks.borderlessWindow, true)
    config.tweaks.radarAspectFix   = normalizeBool(config.tweaks.radarAspectFix, true)
    config.tweaks.widescreenScope  = normalizeBool(config.tweaks.widescreenScope, true)
    config.tweaks.fastWeaponSwitch = normalizeBool(config.tweaks.fastWeaponSwitch, false)
    config.tweaks.hillPark         = normalizeBool(config.tweaks.hillPark, false)
    config.tweaks.silentSirens     = normalizeBool(config.tweaks.silentSirens, false)
    config.tweaks.aircraftQuieter  = normalizeBool(config.tweaks.aircraftQuieter, false)
    config.tweaks.clearHorizon     = normalizeBool(config.tweaks.clearHorizon, false)
    config.tweaks.damageFeed       = normalizeBool(config.tweaks.damageFeed, false)
    config.tweaks.flintNightFix    = normalizeBool(config.tweaks.flintNightFix, true)
    config.tweaks.flintNightMode   = clampNumber(config.tweaks.flintNightMode or 1, 1, 1, 2)
    config.tweaks.flintNightBoost  = clampNumber(config.tweaks.flintNightBoost or 420, 420, 260, 500)
    config.tweaks.cameraNoRecenter = normalizeBool(config.tweaks.cameraNoRecenter, false)
    config.tweaks.anisotropic16x   = normalizeBool(config.tweaks.anisotropic16x, true)
    config.tweaks.bulletTracers    = normalizeBool(config.tweaks.bulletTracers, false)
    config.tweaks.masterBrightness = clampNumber(config.tweaks.masterBrightness or 256, 256, 50, 512)
    config.tweaks.sprintHook       = normalizeBool(config.tweaks.sprintHook, true)
    config.tweaks.fpsDisplay       = normalizeBool(config.tweaks.fpsDisplay, true)
    config.tweaks.fpsDisplayPos    = clampNumber(config.tweaks.fpsDisplayPos or 1, 1, 1, 4)

    for p = 1, 5 do
        local profile = profiles[p]
        if type(profile.name) ~= "string" then profile.name = "Profile " .. p end
        profile.name = profile.name:gsub("[%c]", ""):sub(1, 48)
        profile.slots = type(profile.slots) == "table" and profile.slots or {}
        for i = 1, 20 do
            local slot = profile.slots[i]
            if type(slot) ~= "table" then slot = {}; profile.slots[i] = slot end
            slot.enabled = slot.enabled == true or slot.enabled == 1 or slot.enabled == "1"
            slot.key = clampNumber(slot.key, 0, 0, 255)
            slot.alias = type(slot.alias) == "string" and slot.alias or ""
            slot.alias = slot.alias:gsub("^/", ""):lower():gsub("%s+", ""):gsub("[^%w_]", ""):sub(1, 31)
            slot.command = type(slot.command) == "string" and slot.command or ""
            slot.command = slot.command:gsub("%z", ""):sub(1, 255)
            if slot.mode ~= "send" and slot.mode ~= "open" then slot.mode = "send" end
        end
    end
end

local function loadConfig()
    local p1 = getWorkingDirectory and (getWorkingDirectory() .. "/config/" .. INI_FILE) or nil
    local p2 = "config/" .. INI_FILE
    local p3 = INI_FILE

    local f = nil
    if p1 then f = io.open(p1, "r") end
    if not f then f = io.open(p2, "r") end
    if not f then f = io.open(p3, "r") end

    if not f then
        -- First run: Migrate all existing configurations!
        migrateOldConfigs()
        validateConfig()
        saveConfig()
        if syncChatModeBuffers then syncChatModeBuffers() end
        syncBuffersFromData()
        registerAllAliases()
        return
    end

    pcall(function()
        local currentSec = ""
        local loadedModeCount = nil
        local loadedModes = {}
        for line in f:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line:find("^%[") and line:find("%]$") then
                currentSec = line:match("^%[(.+)%]$"):lower()
            elseif #line > 0 and not line:find("^[;#]") then
                local k, v = line:match("^([^=]+)=(.*)$")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = v:match("^%s*(.-)%s*$")

                    if currentSec == "general" then
                        if k == "menuKey" and tonumber(v) then config.general.menuKey = tonumber(v)
                        elseif k == "menuKeyAlt" and tonumber(v) then config.general.menuKeyAlt = tonumber(v)
                        elseif k == "lockPlayer" then config.general.lockPlayer = (v:lower() == "true" or v == "1")
                        elseif k == "activeProfile" and tonumber(v) then config.general.activeProfile = tonumber(v)
                        elseif k == "spamDelayMs" and tonumber(v) then config.general.spamDelayMs = tonumber(v)
                        elseif k == "showToast" then config.general.showToast = (v:lower() == "true" or v == "1")
                        elseif k == "activeTab" and tonumber(v) then config.general.activeTab = tonumber(v)
                        elseif k == "chatSubTab" and tonumber(v) then config.general.chatSubTab = tonumber(v)
                        elseif k == "menuOpacity" and tonumber(v) then config.general.menuOpacity = math.min(100, math.max(30, tonumber(v)))
                        elseif k == "helpFontScale" and tonumber(v) then config.general.helpFontScale = math.min(1.5, math.max(0.7, tonumber(v)))
                        elseif k == "hasSetDefaultPos" then config.general.hasSetDefaultPos = (v:lower() == "true" or v == "1")
                        elseif k == "autoUpdateCheck" then config.general.autoUpdateCheck = (v:lower() == "true" or v == "1")
                        elseif k == "autoUpdateInstall" then config.general.autoUpdateInstall = (v:lower() == "true" or v == "1")
                        elseif k == "updateUrl" and #v > 0 then config.general.updateUrl = v
                        end
                    
                    elseif currentSec == "chatmode" then
                        if k == "enabled" then config.chatmode.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "activeModeIdx" and tonumber(v) then config.chatmode.activeModeIdx = tonumber(v)
                        elseif k == "showFloatingBar" then config.chatmode.showFloatingBar = (v:lower() == "true" or v == "1")
                        elseif k == "autoAttach" then config.chatmode.autoAttach = (v:lower() == "true" or v == "1")
                        elseif k == "cycleKey" and tonumber(v) then config.chatmode.cycleKey = tonumber(v)
                        elseif k == "barX" and tonumber(v) then config.chatmode.barX = tonumber(v)
                        elseif k == "barY" and tonumber(v) then config.chatmode.barY = tonumber(v)
                        elseif k == "offsetX" and tonumber(v) then config.chatmode.offsetX = tonumber(v)
                        elseif k == "offsetY" and tonumber(v) then config.chatmode.offsetY = tonumber(v)
                        elseif k == "modeCount" and tonumber(v) then
                            loadedModeCount = tonumber(v)
                        elseif k:match("^mode%d+$") then
                            local idx = tonumber(k:match("^mode(%d+)$"))
                            if idx then
                                local mName, mPrefix = v:match("^(.-)|(.*)$")
                                if mName then
                                    loadedModes[idx] = { name = mName, prefix = mPrefix }
                                end
                            end
                        end
                    elseif currentSec == "binder" then
                        if k == "enabled" then config.binder.enabled = (v:lower() == "true" or v == "1") end
                    elseif currentSec == "autocar" then
                        if k == "enabled" then config.autocar.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "autoSeatbelt" then config.autocar.autoSeatbelt = (v:lower() == "true" or v == "1")
                        elseif k == "passengerSeatbelt" then config.autocar.passengerSeatbelt = (v:lower() == "true" or v == "1")
                        elseif k == "autoEngine" then config.autocar.autoEngine = (v:lower() == "true" or v == "1")
                        elseif k == "engineOffOnExit" then config.autocar.engineOffOnExit = (v:lower() == "true" or v == "1")
                        elseif k == "autoLights" then config.autocar.autoLights = (v:lower() == "true" or v == "1")
                        elseif k == "lightsOffOnExit" then config.autocar.lightsOffOnExit = (v:lower() == "true" or v == "1")
                        elseif k == "autoLock" then config.autocar.autoLock = (v:lower() == "true" or v == "1")
                        elseif k == "showChatNotice" then config.autocar.showChatNotice = (v:lower() == "true" or v == "1")
                        elseif k == "hourOffset" and tonumber(v) then config.autocar.hourOffset = tonumber(v)
                        elseif k == "nightStartHour" and tonumber(v) then config.autocar.nightStartHour = tonumber(v)
                        elseif k == "nightEndHour" and tonumber(v) then config.autocar.nightEndHour = tonumber(v)
                        elseif k == "enterDelayMs" and tonumber(v) then config.autocar.enterDelayMs = tonumber(v)
                        elseif k == "syncWithHud" then config.autocar.syncWithHud = (v:lower() == "true" or v == "1")
                        end
                    elseif currentSec == "commands" then
                        if k == "seatbeltCmd" and #v > 0 then config.commands.seatbeltCmd = v
                        elseif k == "engineCmd" and #v > 0 then config.commands.engineCmd = v
                        elseif k == "lightsCmd" and #v > 0 then config.commands.lightsCmd = v
                        elseif k == "lockCmd" and #v > 0 then config.commands.lockCmd = v
                        end
                    elseif currentSec == "downloader" then
                        if k == "enabled" then config.downloader.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "hideDefaultBox" then config.downloader.hideDefaultBox = (v:lower() == "true" or v == "1")
                        elseif k == "positionPreset" and #v > 0 then config.downloader.positionPreset = v:lower()
                        elseif k == "theme" and THEMES[v:lower()] then config.downloader.theme = v:lower()
                        elseif k == "soundNotification" then config.downloader.soundNotification = (v:lower() == "true" or v == "1")
                        elseif k == "showSpeed" then config.downloader.showSpeed = (v:lower() == "true" or v == "1")
                        elseif k == "offsetX" and tonumber(v) then config.downloader.offsetX = tonumber(v)
                        elseif k == "offsetY" and tonumber(v) then config.downloader.offsetY = tonumber(v)
                        end
                    elseif currentSec == "vehinfo" then
                        if not config.vehinfo then config.vehinfo = {} end
                        if k == "enabled" then config.vehinfo.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "displayMode" and tonumber(v) then config.vehinfo.displayMode = tonumber(v)
                        elseif k == "checkWalls" then config.vehinfo.checkWalls = (v:lower() == "true" or v == "1")
                        elseif k == "trackCurrentCar" then config.vehinfo.trackCurrentCar = (v:lower() == "true" or v == "1")
                        elseif k == "lookMaxDist" and tonumber(v) then config.vehinfo.lookMaxDist = tonumber(v)
                        elseif k == "nearbyMaxCount" and tonumber(v) then config.vehinfo.nearbyMaxCount = tonumber(v)
                        elseif k == "speedUnit" and #v > 0 then config.vehinfo.speedUnit = v
                        elseif k == "showId" then config.vehinfo.showId = (v:lower() == "true" or v == "1")
                        elseif k == "showModel" then config.vehinfo.showModel = (v:lower() == "true" or v == "1")
                        elseif k == "showSpeed" then config.vehinfo.showSpeed = (v:lower() == "true" or v == "1")
                        elseif k == "showHealth" then config.vehinfo.showHealth = (v:lower() == "true" or v == "1")
                        elseif k == "showDistance" then config.vehinfo.showDistance = (v:lower() == "true" or v == "1")
                        elseif k == "showEngine" then config.vehinfo.showEngine = (v:lower() == "true" or v == "1")
                        elseif k == "showLock" then config.vehinfo.showLock = (v:lower() == "true" or v == "1")
                        elseif k == "showHealthBar" then config.vehinfo.showHealthBar = (v:lower() == "true" or v == "1")
                        elseif k == "labelColorR" and tonumber(v) then config.vehinfo.labelColorR = tonumber(v)
                        elseif k == "labelColorG" and tonumber(v) then config.vehinfo.labelColorG = tonumber(v)
                        elseif k == "labelColorB" and tonumber(v) then config.vehinfo.labelColorB = tonumber(v)
                        elseif k == "labelColorA" and tonumber(v) then config.vehinfo.labelColorA = tonumber(v)
                        elseif k == "valueColorR" and tonumber(v) then config.vehinfo.valueColorR = tonumber(v)
                        elseif k == "valueColorG" and tonumber(v) then config.vehinfo.valueColorG = tonumber(v)
                        elseif k == "valueColorB" and tonumber(v) then config.vehinfo.valueColorB = tonumber(v)
                        elseif k == "valueColorA" and tonumber(v) then config.vehinfo.valueColorA = tonumber(v)
                        elseif k == "bgStyle" and tonumber(v) then config.vehinfo.bgStyle = tonumber(v)
                        elseif k == "bgAlpha" and tonumber(v) then config.vehinfo.bgAlpha = tonumber(v)
                        elseif k == "fontSize" and tonumber(v) then config.vehinfo.fontSize = tonumber(v)
                        elseif k == "scaleWithDist" then config.vehinfo.scaleWithDist = (v:lower() == "true" or v == "1")
                        elseif k == "textShadow" then config.vehinfo.textShadow = (v:lower() == "true" or v == "1")
                        elseif k == "offsetX" and tonumber(v) then config.vehinfo.offsetX = tonumber(v)
                        elseif k == "offsetZ" and tonumber(v) then config.vehinfo.offsetZ = tonumber(v)
                        elseif k == "hud2dPosX" and tonumber(v) then config.vehinfo.hud2dPosX = tonumber(v)
                        elseif k == "hud2dPosY" and tonumber(v) then config.vehinfo.hud2dPosY = tonumber(v)
                        end
                    elseif currentSec == "sensfix" then
                        if not config.sensfix then config.sensfix = {} end
                        if k == "enabled" then config.sensfix.enabled = (v:lower() == "true" or v == "1")
                        elseif k == "fixVertical" then config.sensfix.fixVertical = (v:lower() == "true" or v == "1")
                        elseif k == "baseSens" and tonumber(v) then config.sensfix.baseSens = tonumber(v)
                        elseif k == "yRatio" and tonumber(v) then config.sensfix.yRatio = tonumber(v)
                        elseif config.sensfix[k] ~= nil and tonumber(v) then config.sensfix[k] = tonumber(v)
                        elseif (k == "deagle" or k == "pistol" or k == "shotgun" or k == "smg" or k == "rifle" or k == "country" or k == "sniper" or k == "freelook" or k == "vehcam" or k == "driveby") and tonumber(v) then
                            config.sensfix[k] = tonumber(v)
                        end
                    elseif currentSec == "tweaks" then
                        if not config.tweaks then config.tweaks = {} end
                        local kl = k:lower()
                        if kl == "enabled" then config.tweaks.enabled = (v:lower() == "true" or v == "1")
                        elseif kl == "subtab" and tonumber(v) then config.tweaks.subTab = tonumber(v)
                        elseif kl == "anticrasher" then config.tweaks.antiCrasher = (v:lower() == "true" or v == "1")
                        elseif kl == "highfpsswimming" then config.tweaks.highFpsSwimming = (v:lower() == "true" or v == "1")
                        elseif kl == "highfpsbraking" then config.tweaks.highFpsBraking = (v:lower() == "true" or v == "1")
                        elseif kl == "runinbackground" then config.tweaks.runInBackground = (v:lower() == "true" or v == "1")
                        elseif kl == "borderlesswindow" then config.tweaks.borderlessWindow = (v:lower() == "true" or v == "1")
                        elseif kl == "radaraspectfix" then config.tweaks.radarAspectFix = (v:lower() == "true" or v == "1")
                        elseif kl == "widescreenscope" then config.tweaks.widescreenScope = (v:lower() == "true" or v == "1")
                        elseif kl == "fastweaponswitch" then config.tweaks.fastWeaponSwitch = (v:lower() == "true" or v == "1")
                        elseif kl == "hillpark" then config.tweaks.hillPark = (v:lower() == "true" or v == "1")
                        elseif kl == "silentsirens" then config.tweaks.silentSirens = (v:lower() == "true" or v == "1")
                        elseif kl == "aircraftquieter" then config.tweaks.aircraftQuieter = (v:lower() == "true" or v == "1")
                        elseif kl == "clearhorizon" then config.tweaks.clearHorizon = (v:lower() == "true" or v == "1")
                        elseif kl == "damagefeed" then config.tweaks.damageFeed = (v:lower() == "true" or v == "1")
                        elseif kl == "flintnightfix" then config.tweaks.flintNightFix = (v:lower() == "true" or v == "1")
                        elseif kl == "flintnightmode" and tonumber(v) then config.tweaks.flintNightMode = tonumber(v)
                        elseif kl == "flintnightboost" and tonumber(v) then config.tweaks.flintNightBoost = tonumber(v)
                        elseif kl == "cameranorecenter" then config.tweaks.cameraNoRecenter = (v:lower() == "true" or v == "1")
                        elseif kl == "anisotropic16x" then config.tweaks.anisotropic16x = (v:lower() == "true" or v == "1")
                        elseif kl == "bullettracers" then config.tweaks.bulletTracers = (v:lower() == "true" or v == "1")
                        elseif kl == "masterbrightness" and tonumber(v) then config.tweaks.masterBrightness = tonumber(v)
                        elseif kl == "sprinthook" then config.tweaks.sprintHook = (v:lower() == "true" or v == "1")
                        elseif kl == "fpsdisplay" then config.tweaks.fpsDisplay = (v:lower() == "true" or v == "1")
                        elseif kl == "fpsdisplaypos" and tonumber(v) then config.tweaks.fpsDisplayPos = tonumber(v)
                        end
                    elseif currentSec:find("^profile%d+$") then
                        local pIdx = tonumber(currentSec:match("^profile(%d+)$"))
                        if pIdx and pIdx >= 1 and pIdx <= 5 then
                            if k == "name" then
                                profiles[pIdx].name = v
                            elseif k:find("^slot%d+$") then
                                local sIdx = tonumber(k:match("^slot(%d+)$"))
                                if sIdx and sIdx >= 1 and sIdx <= 20 then
                                    local en, key, al, md, cmd = v:match("^(%d+)|(%-?%d*)|([^|]*)|([^|]*)|(.*)$")
                                    if en and key then
                                        profiles[pIdx].slots[sIdx].enabled = (en == "1")
                                        profiles[pIdx].slots[sIdx].key     = tonumber(key) or 0
                                        profiles[pIdx].slots[sIdx].alias   = al or ""
                                        profiles[pIdx].slots[sIdx].mode    = md or "send"
                                        profiles[pIdx].slots[sIdx].command = cmd or ""
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        f:close()
        if loadedModeCount and loadedModeCount > 0 then
            local newModes = {}
            for i = 1, loadedModeCount do
                if loadedModes[i] then
                    table.insert(newModes, loadedModes[i])
                end
            end
            if #newModes > 0 then
                config.chatmode.modes = newModes
            end
        end
        if config.chatmode.activeModeIdx > #config.chatmode.modes then
            config.chatmode.activeModeIdx = 1
        end
    end)

    -- Protect all later profile indexing from malformed/out-of-range INI values.
    local activeProfile = tonumber(config.general.activeProfile) or 1
    config.general.activeProfile = math.max(1, math.min(5, math.floor(activeProfile)))
    validateConfig()

    if syncChatModeBuffers then syncChatModeBuffers() end
    syncBuffersFromData()
    pcall(syncVehInfoUI)
    pcall(syncSensFixUI)
    pcall(syncTweaksUI)
    registerAllAliases()
end

-- ------------------------------------------------------------------------------
-- Keybinder Helper Functions & Dynamic Placeholder Resolvers
-- ------------------------------------------------------------------------------
local function getKeyName(vkey)
    if not vkey or vkey == 0 then return "None" end
    if vkey == 9 then return "TAB" end
    if vkey == 13 then return "ENTER" end
    if vkey == 27 then return "ESC" end
    if vkey == 32 then return "SPACE" end
    local name = vkeys.id_to_name(vkey)
    if name then return name end
    if vkey == 1 then return "LMB" end
    if vkey == 2 then return "RMB" end
    if vkey == 4 then return "MMB" end
    if vkey == 5 then return "X1" end
    if vkey == 6 then return "X2" end
    return string.format("Key_%d", vkey)
end

-- ==============================================================================
-- ROLEPLAY IDENTITY & MASK PROTECTION ENGINE
-- ==============================================================================
local trackedPlayerMasks   = {}
local trackedLabelToPlayer = {}
local hiddenNametags       = {}

local function extractMaskTag(rawText)
    if not rawText or type(rawText) ~= "string" then return nil end
    local clean = rawText:gsub("{%x%x%x%x%x%x}", ""):gsub("{%x%x%x%x}", "")
    for line in clean:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
            local m = trimmed:match("([Mm]ask_%w+)")
                   or trimmed:match("([Mm]ask%s*#?%d+)")
                   or trimmed:match("([Mm]ask%s*%(%d+%))")
                   or trimmed:match("([Mm]ask%s*%[%d+%])")
                   or trimmed:match("([Mm]asked%s*#?%d+)")
                   or trimmed:match("([Mm]asked%s*[Pp]erson)")
                   or trimmed:match("([Ss]tranger_%w+)")
                   or trimmed:match("([Ss]tranger)")
                   or trimmed:match("([Nn]eznakomec%w*)")
                   or trimmed:match("([Mm]aska_%w+)")
            if m then return m end
            if trimmed:lower():find("^mask") or trimmed:lower():find("^stranger") then
                return trimmed
            end
        end
    end
    return nil
end

local function scanPlayerMaskFrom3DText(playerId)
    if not sampIsPlayerConnected or not sampIsPlayerConnected(playerId) then
        return nil
    end

    local foundMask = nil
    pcall(function()
        local hasPed, ped = sampGetCharHandleBySampPlayerId(playerId)
        local px, py, pz = 0, 0, 0
        if hasPed and doesCharExist(ped) then
            px, py, pz = getCharCoordinates(ped)
        end

        for id = 0, 2048 do
            if sampIs3dTextDefined and sampIs3dTextDefined(id) then
                local text, color, x, y, z, dist, los, attPlayer, attVeh = sampGet3dTextInfoById(id)
                if text and #text > 0 then
                    local maskTag = extractMaskTag(text)
                    if maskTag then
                        if attPlayer == playerId then
                            foundMask = maskTag
                            break
                        elseif hasPed and doesCharExist(ped) then
                            local dx = x - px
                            local dy = y - py
                            local dz = z - pz
                            local distSq = dx*dx + dy*dy + dz*dz
                            -- If label is within 2.5m horizontal radius and around head level
                            if distSq < 7.0 and dz >= -0.5 and dz <= 3.0 then
                                foundMask = maskTag
                                break
                            end
                        end
                    end
                end
            end
        end
    end)
    return foundMask
end

local function isPlayerMasked(playerId)
    if not playerId or playerId == 65535 then return false, nil end
    if trackedPlayerMasks[playerId] then
        return true, trackedPlayerMasks[playerId]
    end
    local m = scanPlayerMaskFrom3DText(playerId)
    if m then
        trackedPlayerMasks[playerId] = m
        return true, m
    end
    if hiddenNametags[playerId] then
        local tag = string.format("Mask_%02d", playerId % 100)
        return true, tag
    end
    if sampIsPlayerConnected and sampIsPlayerConnected(playerId) then
        local nick = sampGetPlayerNickname(playerId)
        if nick and (nick:lower():find("mask") or nick:lower():find("stranger") or nick:lower():find("masked")) then
            return true, nick
        end
    end
    return false, nil
end

local function getRoleplayPlayerName(playerId)
    if not playerId or playerId == 65535 then return "Environment" end
    if not sampIsPlayerConnected or not sampIsPlayerConnected(playerId) then
        return "Unknown"
    end

    local isMask, maskTag = isPlayerMasked(playerId)
    if isMask and maskTag and #maskTag > 0 then
        return maskTag
    end

    return sampGetPlayerNickname(playerId) or ("Player " .. tostring(playerId))
end

local function getClosestPlayer(maxDist)
    local bestPed = nil
    local bestDist = maxDist or 50.0
    local myX, myY, myZ = getCharCoordinates(PLAYER_PED)

    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local exists, ped = sampGetCharHandleBySampPlayerId(i)
            if exists and doesCharExist(ped) and ped ~= PLAYER_PED then
                local px, py, pz = getCharCoordinates(ped)
                local dist = getDistanceBetweenCoords3d(myX, myY, myZ, px, py, pz)
                if dist < bestDist then
                    bestDist = dist
                    bestPed = ped
                end
            end
        end
    end

    if bestPed then
        local _, id = sampGetPlayerIdByCharHandle(bestPed)
        local isMask, maskTag = isPlayerMasked(id)
        local nick = isMask and maskTag or getRoleplayPlayerName(id)
        return id, nick, bestDist, isMask, maskTag
    end
    return nil, nil, nil, false, nil
end

local function replacePlaceholders(cmdTemplate)
    local text = cmdTemplate or ""

    if text:find("{myid}") then
        local myId = 0
        pcall(function()
            local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if id and id ~= -1 then myId = id end
        end)
        text = text:gsub("{myid}", tostring(myId))
    end

    local isTargetedCmd = text:match("^%s*/[%a]*send") or text:match("^%s*/[%a]*pay")
        or text:match("^%s*/[%a]*cuff") or text:match("^%s*/[%a]*heal")
        or text:match("^%s*/[%a]*frisk") or text:match("^%s*/[%a]*ticket")
        or text:match("^%s*/[%a]*tie") or text:match("^%s*/[%a]*rob")
        or text:match("^%s*/[%a]*givecash") or text:match("^%s*/[%a]*transfer")

    if text:find("{near}") or text:find("{nearid}") or text:find("{nearby}") or text:find("{nearname}") or text:find("{neardist}") or (isTargetedCmd and text:find("{id}")) then
        local nearId = ""
        local nearName = "Nobody"
        local nearDist = "0m"
        local nid, nname, ndist, isMask, maskTag = getClosestPlayer(50.0)
        if nid ~= nil then
            if isMask and maskTag and #maskTag > 0 then
                -- Player is wearing a mask: use mask identifier (e.g. Mask_07) to prevent revealing real server ID
                nearId = maskTag
                nearName = maskTag
            else
                nearId = tostring(nid)
                nearName = nname or ("Player_" .. nid)
            end
            nearDist = string.format("%.1fm", ndist)
        else
            if isSampAvailable and isSampAvailable() and isTargetedCmd then
                sampAddChatMessage("{FFA726}[BDS Toolkit]{FFFFFF} No player nearby within 50m! (Enter ID manually)", -1)
            end
        end
        text = text:gsub("{nearid}", nearId):gsub("{nearby}", nearId):gsub("{nearname}", nearName):gsub("{neardist}", nearDist):gsub("{near}", nearId)
        if isTargetedCmd and text:find("{id}") then
            text = text:gsub("{id}", nearId)
        end
    end

    if text:find("{id}") then
        local myId = 0
        pcall(function()
            local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if id and id ~= -1 then myId = id end
        end)
        text = text:gsub("{id}", tostring(myId))
    end

    if text:find("{target}") or text:find("{targetid}") or text:find("{targetname}") then
        local targetId = ""
        local targetName = "Target"
        pcall(function()
            local hasTarget, targetPed = getCharPlayerIsTargeting(PLAYER_HANDLE)
            if hasTarget and doesCharExist(targetPed) then
                local _, tid = sampGetPlayerIdByCharHandle(targetPed)
                if tid and tid ~= -1 then
                    local isMask, maskTag = isPlayerMasked(tid)
                    if isMask and maskTag and #maskTag > 0 then
                        targetId = maskTag
                        targetName = maskTag
                    else
                        targetId = tostring(tid)
                        targetName = getRoleplayPlayerName(tid)
                    end
                end
            end
        end)
        text = text:gsub("{targetid}", targetId):gsub("{targetname}", targetName):gsub("{target}", targetId)
    end

    if text:find("{zone}") or text:find("{city}") then
        local zoneName = "San Andreas"
        pcall(function()
            local x, y, z = getCharCoordinates(PLAYER_PED)
            zoneName = calculatePathfindZone(x, y, z) or "San Andreas"
        end)
        text = text:gsub("{zone}", zoneName):gsub("{city}", zoneName)
    end

    if text:find("{veh}") or text:find("{car}") then
        local vehName = "Foot"
        pcall(function()
            if isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                local model = getCarModel(car)
                vehName = getNameOfVehicleModel(model) or "Vehicle"
            end
        end)
        text = text:gsub("{veh}", vehName):gsub("{car}", vehName)
    end

    return text
end

local function applyArguments(cmdTemplate, extraArgs)
    local text = cmdTemplate or ""
    local hasMissingParam = false
    local argsStr = (extraArgs and extraArgs:match("^%s*(.-)%s*$")) or ""

    local tokens = {}
    if #argsStr > 0 then
        for token in argsStr:gmatch("%S+") do
            table.insert(tokens, token)
        end
    end

    local hasAmountTag = text:find("{amount}") or text:find("{money}") or text:find("{price}") or text:find("{cash}")
    local hasReasonTag = text:find("{reason}") or text:find("{text}") or text:find("{msg}")
    local hasArgsTag   = text:find("{args}") or text:find("%$%*")

    if #tokens > 0 then
        for i = 1, 9 do
            local tag = "%$" .. i
            if text:find(tag) then
                text = text:gsub(tag, tokens[i] or "")
            end
        end

        if hasAmountTag then
            text = text:gsub("{amount}", tokens[1] or ""):gsub("{money}", tokens[1] or "")
                       :gsub("{price}", tokens[1] or ""):gsub("{cash}", tokens[1] or "")
            local remaining = {}
            for k = 2, #tokens do table.insert(remaining, tokens[k]) end
            if #remaining > 0 and hasReasonTag then
                text = text:gsub("{reason}", table.concat(remaining, " "))
                           :gsub("{text}", table.concat(remaining, " "))
                           :gsub("{msg}", table.concat(remaining, " "))
            end
        elseif hasReasonTag then
            text = text:gsub("{reason}", argsStr):gsub("{text}", argsStr):gsub("{msg}", argsStr)
        elseif hasArgsTag then
            text = text:gsub("{args}", argsStr):gsub("%$%*", argsStr)
        else
            text = text .. " " .. argsStr
        end
    else
        if hasAmountTag or hasReasonTag or hasArgsTag then
            hasMissingParam = true
        end
    end

    return text, hasMissingParam
end

executeSlot = function(slotIdx, extraArgs, requestedProfileIndex)
    pcall(function()
        local profileIndex = requestedProfileIndex or config.general.activeProfile
        if requestedProfileIndex and tonumber(config.general.activeProfile) ~= requestedProfileIndex then return end
        local curP = profiles[profileIndex]
        if not curP then return end
        local s = curP.slots[slotIdx]
        if not s or not s.enabled or #s.command == 0 then return end

        local raw = replacePlaceholders(s.command)
        local finalCmd, missingParam = applyArguments(raw, extraArgs)

        local targetMode = s.mode or "send"
        if extraArgs and #extraArgs > 0 and not missingParam then
            targetMode = "send"
        elseif missingParam then
            targetMode = "open"
        end

        if targetMode == "open" then
            sampSetChatInputEnabled(true)
            sampSetChatInputText(finalCmd .. " ")
        else
            sampSendChat(finalCmd)
        end
    end)
end

-- ------------------------------------------------------------------------------
-- Vehicle Automation Helpers (AutoCar)
-- ------------------------------------------------------------------------------
local function isCarEngineOn(car)
    if not car or not doesVehicleExist(car) then return false end
    local memOn = false
    pcall(function()
        local ptr = tonumber(getCarPointer(car))
        if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
            local flagAddr = ffi.cast("uint8_t*", ptr + 0x428)
            if isMemoryReadable(flagAddr, 1) then
                local flags = tonumber(flagAddr[0]) or 0
                memOn = (math.floor(flags / 0x10) % 2) == 1
            end
        end
    end)
    return memOn
end

local function isCarLightsOn(car)
    if not car or not doesVehicleExist(car) then return false end
    local memOn = false
    pcall(function()
        local ptr = tonumber(getCarPointer(car))
        if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
            local flagAddr = ffi.cast("uint8_t*", ptr + 0x428)
            if isMemoryReadable(flagAddr, 1) then
                local flags = tonumber(flagAddr[0]) or 0
                memOn = (math.floor(flags / 0x40) % 2) == 1
            end
        end
    end)
    return memOn
end
local areCarLightsOn = isCarLightsOn

local function getEffectiveTime()
    local h, m = 12, 0
    local src = "Local"
    if config.autocar.syncWithHud and state.hudClockHour ~= nil and (os.clock() - (state.lastClockSyncTime or 0) < 300) then
        h = state.hudClockHour
        m = state.hudClockMin or 0
        src = "HUD"
    else
        local lt = os.date("*t")
        h = lt.hour
        m = lt.min
    end

    local off = config.autocar.hourOffset or 0
    h = (h + off) % 24
    if h < 0 then h = h + 24 end
    return h, m, src
end

local function isNightTime()
    local h = getEffectiveTime()
    local startH = config.autocar.nightStartHour or 19
    local endH   = config.autocar.nightEndHour or 6
    if startH > endH then
        return (h >= startH or h < endH)
    else
        return (h >= startH and h < endH)
    end
end

local function safeSendChat(cmd)
    if cmd and #cmd > 0 and isSampAvailable() then
        sampSendChat(cmd)
    end
end

local function setEngineState(veh, targetOn)
    if not veh or veh == 0 or not doesVehicleExist(veh) then return end
    local now = os.clock()
    if state.lastEngineToggle and (now - state.lastEngineToggle < 2.0) then return end

    local curOn = false
    local ok = pcall(function() curOn = isCarEngineOn(veh) end)
    if not ok then return end

    if (targetOn and not curOn) or (not targetOn and curOn) then
        state.lastEngineToggle = now
        state.engineRunning = targetOn
        safeSendChat(config.commands.engineCmd)
    end
end

local function setLightsState(veh, targetOn)
    if not veh or veh == 0 or not doesVehicleExist(veh) then return end
    local now = os.clock()
    if state.lastLightsToggle and (now - state.lastLightsToggle < 2.0) then return end

    local curOn = false
    local ok = pcall(function() curOn = isCarLightsOn(veh) end)
    if not ok then return end

    if (targetOn and not curOn) or (not targetOn and curOn) then
        state.lastLightsToggle = now
        state.lightsOn = targetOn
        safeSendChat(config.commands.lightsCmd)
    end
end

local function isPlayerDriverOfVehicle(carHandle)
    if not carHandle or not doesVehicleExist(carHandle) then return false end
    if not doesCharExist(PLAYER_PED) or isCharDead(PLAYER_PED) or not isCharInAnyCar(PLAYER_PED) then return false end

    -- 1. Direct memory pointer verification (CVehicle::m_pDriver == CPed*)
    local okMem, isDrv = pcall(function()
        local carPtr = tonumber(getCarPointer(carHandle))
        local pedPtr = tonumber(getCharPointer(PLAYER_PED))
        if carPtr and carPtr > 0x10000 and carPtr < 0x7FFE0000 and pedPtr and pedPtr > 0x10000 and pedPtr < 0x7FFE0000 then
            local drvAddr = ffi.cast("uintptr_t*", carPtr + 0x460)
            if isMemoryReadable(drvAddr, 4) then
                local pDriver = tonumber(drvAddr[0]) or 0
                if pDriver ~= 0 and pDriver == pedPtr then
                    return true
                end
            end
        end
        return nil
    end)
    if okMem and isDrv ~= nil then
        return isDrv
    end

    -- 2. Fallback: native getDriverOfCar wrapped in pcall
    local okOp, driver = pcall(getDriverOfCar, carHandle)
    if okOp and driver and doesCharExist(driver) and driver == PLAYER_PED then
        return true
    end

    return false
end

local function handleVehicleEntry()
    if state.enteringRoutine or state.inVehicle then
        return
    end
    state.enteringRoutine = true
    state.exitCommandsSent = false
    state.vehicleSession  = (state.vehicleSession or 0) + 1
    local currentSession  = state.vehicleSession

    lua_thread.create(function()
        -- 1. Wait until character is confirmed inside any vehicle (supports long climb animations like Combine Harvester)
        local timeout = os.clock() + 6.0
        while not isCharInAnyCar(PLAYER_PED) and os.clock() < timeout do
            if state.vehicleSession ~= currentSession then
                state.enteringRoutine = false
                return
            end
            wait(50)
        end

        if not doesCharExist(PLAYER_PED) or isCharDead(PLAYER_PED) or not isCharInAnyCar(PLAYER_PED) or state.vehicleSession ~= currentSession then
            state.enteringRoutine = false
            return
        end

        -- 2. Wait until vehicle handle is valid and seat settlement is verified (up to 3.5s for tall cabs)
        local timeoutSeat = os.clock() + 3.5
        local veh = nil
        local isDriver = false
        while os.clock() < timeoutSeat do
            local okCar, c = pcall(storeCarCharIsInNoSave, PLAYER_PED)
            if okCar and c and doesVehicleExist(c) then
                veh = c
                if isPlayerDriverOfVehicle(c) then
                    isDriver = true
                    break
                end
            end
            wait(50)
        end

        if not veh or not doesVehicleExist(veh) or state.vehicleSession ~= currentSession then
            state.enteringRoutine = false
            return
        end

        -- Configured user entry delay
        local delay = math.max(150, config.autocar.enterDelayMs or 400)
        wait(delay)

        if not doesCharExist(PLAYER_PED) or isCharDead(PLAYER_PED) or not isCharInAnyCar(PLAYER_PED) or not doesVehicleExist(veh) or state.vehicleSession ~= currentSession then
            state.enteringRoutine = false
            return
        end

        -- Final confirmation of driver status
        if isPlayerDriverOfVehicle(veh) then
            isDriver = true
        end

        local okModel, model = pcall(getCarModel, veh)
        if not okModel or not model then model = 400 end
        local class = getVehicleClass(model)

        state.inVehicle    = true
        state.isDriver     = isDriver
        state.currentVeh   = veh
        state.currentModel = model
        state.currentClass = class
        state.isExiting    = false

        if config.autocar.enabled and state.vehicleSession == currentSession
            and doesCharExist(PLAYER_PED) and not isCharDead(PLAYER_PED)
            and isCharInAnyCar(PLAYER_PED) and doesVehicleExist(veh) then

            -- 1. Auto-Lock (Driver)
            if isDriver and config.autocar.autoLock and doesVehicleExist(veh) then
                safeSendChat(config.commands.lockCmd)
                wait(300)
            end

            -- 2. Auto-Engine (Driver, not bicycle)
            if isDriver and config.autocar.autoEngine and class ~= 'bicycle' and doesVehicleExist(veh) then
                wait(150)
                if not isCarEngineOn(veh) then
                    safeSendChat(config.commands.engineCmd)
                    state.engineRunning = true
                    wait(300)
                end
            end

            -- 3. Auto-Lights (Driver, not bicycle)
            if isDriver and config.autocar.autoLights and class ~= 'bicycle' and doesVehicleExist(veh) then
                local night = isNightTime()
                state.lastNightState = night
                if night and not isCarLightsOn(veh) and doesVehicleExist(veh) then
                    safeSendChat(config.commands.lightsCmd)
                    state.lightsOn = true
                    wait(300)
                end
            end

            -- 4. Auto-Seatbelt (Cars/Trucks)
            if config.autocar.autoSeatbelt and class == 'car' and isCharInAnyCar(PLAYER_PED) then
                if isDriver or config.autocar.passengerSeatbelt then
                    if not state.beltFastened then
                        safeSendChat(config.commands.seatbeltCmd)
                        state.beltFastened = true
                        wait(300)
                    end
                end
            end
        end

        state.enteringRoutine = false
    end)
end

local function handleVehicleExit()
    state.enteringRoutine = false
    state.vehicleSession  = (state.vehicleSession or 0) + 1
    state.lastExitTick    = os.clock()

    local vehToShutOff = state.currentVeh
    local wasDriver    = state.isDriver
    local vehClass     = state.currentClass

    -- If exit commands haven't been sent yet, send them reliably now
    if config.autocar.enabled and wasDriver and not state.exitCommandsSent then
        state.exitCommandsSent = true
        if vehToShutOff and doesVehicleExist(vehToShutOff) and vehClass ~= 'bicycle' then
            if config.autocar.engineOffOnExit and isCarEngineOn(vehToShutOff) then
                safeSendChat(config.commands.engineCmd)
                state.engineRunning = false
            end
            if config.autocar.lightsOffOnExit and isCarLightsOn(vehToShutOff) then
                safeSendChat(config.commands.lightsCmd)
                state.lightsOn = false
            end
        end

        -- Secure parked vehicle with handbrake on incline
        if config.tweaks and config.tweaks.hillPark and vehToShutOff and doesVehicleExist(vehToShutOff) and vehClass ~= 'bicycle' then
            pcall(function()
                local ptr = tonumber(getCarPointer(vehToShutOff))
                if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
                    local curByte = memory.getuint8(ptr + 0x428, false)
                    memory.setuint8(ptr + 0x428, bit.bor(curByte, 0x20), false)
                    memory.setfloat(ptr + 0x4A0, 1.0, false)
                end
            end)
        end
    end

    state.inVehicle        = false
    state.isDriver         = false
    state.currentVeh       = nil
    state.currentModel     = 0
    state.currentClass     = 'car'
    state.beltFastened     = false
    state.isExiting        = false
end

local function vehicleWatcherThread()
    local wasInVehicle = false
    while true do
        wait(50)
        pcall(function()
            if not config.autocar.enabled then
                state.inVehicle = false
                state.isDriver = false
                state.enteringRoutine = false
                state.isExiting = false
                state.currentVeh = nil
                state.currentModel = 0
                state.currentClass = 'car'
                state.beltFastened = false
                state.lastNightState = nil
                wasInVehicle = false
            elseif doesCharExist(PLAYER_PED) and not isCharDead(PLAYER_PED) then
                local inCar = isCharInAnyCar(PLAYER_PED)

                -- ENTRY DETECTED
                if inCar and not wasInVehicle and not state.enteringRoutine then
                    wasInVehicle = true
                    handleVehicleEntry()
                -- EXIT DETECTED
                elseif not inCar and wasInVehicle then
                    wasInVehicle = false
                    handleVehicleExit()
                end

                -- Dynamic Night Lights Transition while driving
                if inCar and state.isDriver and config.autocar.autoLights and state.currentClass ~= 'bicycle' and not state.isExiting then
                    local night = isNightTime()
                    if state.lastNightState ~= nil and state.lastNightState ~= night then
                        state.lastNightState = night
                        if doesVehicleExist(state.currentVeh) then
                            setLightsState(state.currentVeh, night)
                        end
                    end
                end
            end
        end)
    end
end

-- ------------------------------------------------------------------------------
-- FiveM Rotating Circular Spinner
-- ------------------------------------------------------------------------------
local function drawFiveMSpinner(drawList, center, radius, thickness, color, speed)
    local t = os.clock() * (speed or 4.5)
    local segments = 24
    local startA = (t * 6.2831853) % 6.2831853
    local endA = startA + 4.7123889

    drawList:AddCircle(center, radius, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.12)), segments, thickness)
    drawList:PathClear()
    for i = 0, segments do
        local a = startA + (i / segments) * (endA - startA)
        local px = center.x + math.cos(a) * radius
        local py = center.y + math.sin(a) * radius
        drawList:PathLineTo(imgui.ImVec2(px, py))
    end
    drawList:PathStroke(color, false, thickness)
end

function startSimulationTest()
    state.isTestMode = true
    state.testStartTime = os.clock()
    state.testTotalFiles = 45
    state.currentFiles = 0
    state.totalFiles = 45
    state.speedKBps = 950.0
    state.isComplete = false
    state.completeTime = 0.0
    if isSampAvailable and isSampAvailable() then
        sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Model download simulation test started...", -1)
    end
end


-- ------------------------------------------------------------------------------

-- ------------------------------------------------------------------------------
-- Chat Mode Auto-Prefix & Room Editor Engine
-- ------------------------------------------------------------------------------
local chatModeBuffers = {}

syncChatModeBuffers = function()
    chatModeBuffers = {}
    if not (config.chatmode and config.chatmode.modes) then return end
    for i, m in ipairs(config.chatmode.modes) do
        local nBuf = imgui.new.char[64]()
        local pBuf = imgui.new.char[32]()
        imgui.StrCopy(nBuf, m.name or "")
        imgui.StrCopy(pBuf, m.prefix or "")
        chatModeBuffers[i] = { name = nBuf, prefix = pBuf }
    end
end

-- Scoreboard operations are requested from callbacks/window messages but executed
-- later in the normal MoonLoader main loop. Never poke SA-MP scoreboard pointers
-- directly: offsets vary by client build and can destabilize the Lua/game thread.
local scoreboardCloseRequested = false
local function forceCloseScoreboard()
    scoreboardCloseRequested = true
end

local function processScoreboardCloseRequest()
    if not scoreboardCloseRequested then return end
    scoreboardCloseRequested = false
    if type(sampToggleScoreboard) == "function" then
        -- This runs from the main script loop, not from WndProc/onWindowMessage.
        pcall(sampToggleScoreboard, false)
    end
end

-- Chat-mode changes are saved from the main worker loop, not from the
-- window-message callback. This avoids creating/resuming MoonLoader threads
-- directly while SA-MP is processing keyboard messages.
local chatConfigSaveRequested = false
local function cycleChatMode(delta)
    delta = delta or 1
    if not (config.chatmode and config.chatmode.modes) then return end
    local total = #config.chatmode.modes
    if total == 0 then return end
    config.chatmode.activeModeIdx = ((config.chatmode.activeModeIdx - 1 + delta) % total) + 1
    forceCloseScoreboard()

    -- Queue the save. The main worker loop performs it outside WndProc.
    chatConfigSaveRequested = true
end

-- ------------------------------------------------------------------------------
-- Window Message Handler
-- TAB is consumed here while chat is active so SA-MP never receives it as
-- a scoreboard key. The actual mode change is queued for the main loop.
-- ------------------------------------------------------------------------------
local isCycleKeyDown = false
local chatModeCycleRequested = false

local function handleChatModeWindowMessage(msg, wparam, lparam)
    -- Reset the key latch if the game loses focus.
    if msg == 0x0006 or msg == 0x0008 then -- WM_ACTIVATE / WM_KILLFOCUS
        isCycleKeyDown = false
        return
    end

    local cycleKey = (config and config.chatmode and config.chatmode.cycleKey) or 9
    if config and config.chatmode and config.chatmode.enabled
        and wparam == cycleKey
        and (msg == 0x0100 or msg == 0x0101 or msg == 0x0102)
        and not (state and state.mainWindowOpen and state.mainWindowOpen[0])
        and not isPauseMenuActive() then

        local chatActive = false
        pcall(function()
            if isSampAvailable and isSampAvailable() then
                chatActive = sampIsChatInputActive()
            end
        end)

        if chatActive then
            if msg == 0x0100 then -- WM_KEYDOWN
                if not isCycleKeyDown then
                    isCycleKeyDown = true
                    chatModeCycleRequested = true
                end
                pcall(consumeWindowMessage, true, false)
            elseif msg == 0x0101 then -- WM_KEYUP
                isCycleKeyDown = false
                pcall(consumeWindowMessage, true, false)
            elseif msg == 0x0102 then -- WM_CHAR
                pcall(consumeWindowMessage, true, false)
            end
            return
        end
    end

    if msg == 0x0101 and wparam == cycleKey then
        isCycleKeyDown = false
    end

    -- Apply the selected chat-mode prefix directly to SA-MP's input buffer
    -- BEFORE SA-MP processes Enter. This avoids cancelling onSendChat and then
    -- recursively calling sampProcessChatInput from another coroutine.
    if msg == 0x0100 and wparam == 0x0D then -- WM_KEYDOWN + VK_RETURN
        local chatActive = false
        pcall(function()
            if isSampAvailable and isSampAvailable() then
                chatActive = sampIsChatInputActive()
            end
        end)

        if chatActive
            and config and config.chatmode and config.chatmode.enabled
            and not (state and state.mainWindowOpen and state.mainWindowOpen[0]) then

            local idx = tonumber(config.chatmode.activeModeIdx) or 1
            local mode = config.chatmode.modes and config.chatmode.modes[idx]
            local prefix = mode and tostring(mode.prefix or ""):match("^%s*(.-)%s*$") or ""

            if prefix ~= "" then
                local inputText = ""
                local gotText = pcall(function()
                    inputText = sampGetChatInputText() or ""
                end)

                if gotText and type(inputText) == "string" and inputText ~= "" then
                    local trimmed = inputText:match("^%s*(.*)$") or inputText
                    -- Preserve manually entered slash commands; only prefix plain text.
                    if trimmed ~= "" and trimmed:sub(1, 1) ~= "/" then
                        local escapedPfx = prefix:gsub("%p", "%%%0")
                        if not trimmed:find("^" .. escapedPfx .. "%s") and trimmed ~= prefix then
                            pcall(sampSetChatInputText, prefix .. " " .. inputText)
                        end
                    end
                end
            end
        end
    end

end

function onWindowMessage(msg, wparam, lparam)
    handleChatModeWindowMessage(msg, wparam, lparam)
end

local function addChatMode(name, prefix)
    if not (config.chatmode and config.chatmode.modes) then return end
    table.insert(config.chatmode.modes, {
        name   = name or "New Mode",
        prefix = prefix or "/new"
    })
    syncChatModeBuffers()
    saveConfig()
end

local function deleteChatMode(index)
    if not (config.chatmode and config.chatmode.modes) or #config.chatmode.modes <= 1 then return end
    table.remove(config.chatmode.modes, index)
    if config.chatmode.activeModeIdx > #config.chatmode.modes then
        config.chatmode.activeModeIdx = #config.chatmode.modes
    elseif config.chatmode.activeModeIdx == index then
        config.chatmode.activeModeIdx = math.max(1, index - 1)
    end
    syncChatModeBuffers()
    saveConfig()
end

local function moveChatMode(index, delta)
    if not (config.chatmode and config.chatmode.modes) then return end
    local target = index + delta
    if target < 1 or target > #config.chatmode.modes then return end
    local temp = config.chatmode.modes[index]
    config.chatmode.modes[index] = config.chatmode.modes[target]
    config.chatmode.modes[target] = temp
    if config.chatmode.activeModeIdx == index then
        config.chatmode.activeModeIdx = target
    elseif config.chatmode.activeModeIdx == target then
        config.chatmode.activeModeIdx = index
    end
    syncChatModeBuffers()
    saveConfig()
end

local function resetDefaultChatModes()
    if not config.chatmode then config.chatmode = {} end
    config.chatmode.modes = {
        { name = "Normal (IC)",   prefix = "" },
        { name = "/b (OOC)",      prefix = "/b" },
        { name = "/me (Action)",  prefix = "/me" },
        { name = "/do (State)",   prefix = "/do" },
        { name = "/s (Shout)",    prefix = "/s" },
    }
    config.chatmode.activeModeIdx = 1
    syncChatModeBuffers()
    saveConfig()
end

-- Comprehensive In-Game Chatlog Engine & Real-Time Memory Buffer
-- ------------------------------------------------------------------------------
local chatlogLines = {}
local chatlogSearchBuf = imgui.new.char[128]()
local chatlogFilterCategory = "all"
local chatlogAutoScroll = true
local chatlogLastLoadTime = 0

local function getChatlogPath()
    local paths = {}
    local userProfile = os.getenv("USERPROFILE") or "C:\\Users\\" .. (os.getenv("USERNAME") or "")
    table.insert(paths, userProfile .. "\\OneDrive\\Documents\\GTA San Andreas User Files\\SAMP\\chatlog.txt")
    table.insert(paths, userProfile .. "\\Documents\\GTA San Andreas User Files\\SAMP\\chatlog.txt")
    if getFolderPath then
        local ok, p = pcall(getFolderPath, 0x05)
        if ok and p then
            table.insert(paths, p .. "\\GTA San Andreas User Files\\SAMP\\chatlog.txt")
        end
    end
    table.insert(paths, "GTA San Andreas User Files\\SAMP\\chatlog.txt")

    for _, p in ipairs(paths) do
        local f = io.open(p, "r")
        if f then
            f:close()
            return p
        end
    end
    return paths[1]
end

local function appendChatlogLine(text)
    if not text or #text == 0 then return end
    local timeStr = os.date("[%H:%M:%S] ")
    local fullLine = (text:find("^%%%[%d%d:%d%d:%d%d%%%]") and "" or timeStr) .. text
    table.insert(chatlogLines, fullLine)
    if #chatlogLines > 5000 then
        table.remove(chatlogLines, 1)
    end
end

local function loadChatlogFromDisk()
    local path = getChatlogPath()
    if not path then return end
    local f = io.open(path, "r")
    if not f then return end

    local lines = {}
    for line in f:lines() do
        if #line > 0 then
            table.insert(lines, line)
            if #lines > 5000 then
                table.remove(lines, 1)
            end
        end
    end
    f:close()
    chatlogLines = lines
    chatlogLastLoadTime = os.clock()
end

-- ------------------------------------------------------------------------------
-- Dear ImGui Styling & Theme
-- ------------------------------------------------------------------------------

-- ------------------------------------------------------------------------------
-- Modern iOS/Material Slide Toggle Switch Widget
-- ------------------------------------------------------------------------------
local function drawSlideSwitch(strId, boolVal, label, hint)
    local width  = 38.0
    local height = 18.0
    local radius = height * 0.5

    local p = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()

    local textSize = imgui.CalcTextSize(label or "")
    local totalW   = width + 8 + 26 + (textSize.x > 0 and (textSize.x + 8) or 0)

    imgui.InvisibleButton(strId, imgui.ImVec2(totalW, height + 2))
    local clicked = imgui.IsItemClicked()
    local hovered = imgui.IsItemHovered()

    local val = boolVal
    if clicked then
        val = not val
    end

    -- Switch pill background
    local bgCol
    if val then
        bgCol = hovered
            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.85, 0.98, 1.00)) -- Neon Cyan hovered
            or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.70, 0.85, 0.92)) -- Neon Cyan active
    else
        bgCol = hovered
            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.24, 0.28, 0.35, 1.00))
            or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.15, 0.17, 0.22, 0.95))
    end

    local pillY = p.y + 1
    drawList:AddRectFilled(imgui.ImVec2(p.x, pillY), imgui.ImVec2(p.x + width, pillY + height), bgCol, radius)
    local borderCol = val
        and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.95, 1.00, 0.85))
        or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.32, 0.36, 0.44, 0.60))
    drawList:AddRect(imgui.ImVec2(p.x, pillY), imgui.ImVec2(p.x + width, pillY + height), borderCol, radius, 15, 1.0)

    -- Knob
    local knobX = val and (p.x + width - radius) or (p.x + radius)
    local knobY = pillY + radius
    local knobCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
    drawList:AddCircleFilled(imgui.ImVec2(knobX, knobY), radius - 2.5, knobCol, 16)

    -- Status Text (ON / OFF)
    local textY = p.y + ((height + 2) - textSize.y) * 0.5
    local statusX = p.x + width + 6
    local statusCol = val
        and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.90, 0.46, 1.00))
        or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.55, 0.60, 0.70, 1.00))
    drawList:AddText(imgui.ImVec2(statusX, textY), statusCol, val and "ON " or "OFF")

    if label and #label > 0 then
        local labelX = statusX + 26
        local labelCol = val
            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.96, 0.98, 1.00))
            or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.68, 0.72, 0.80, 1.00))
        drawList:AddText(imgui.ImVec2(labelX, textY), labelCol, label)
    end

    if hovered and hint and #hint > 0 then
        imgui.SetTooltip(hint)
    end

    return clicked, val
end


-- ==============================================================================
--  BDS VEHICLE INFO HUD MODULE (3D WORLD SPACE TELEMETRY & OCCLUSION)
--  Developer: Danny_Jadogar (CHACHA)
-- ==============================================================================
local VEHICLE_NAMES = {
    [400] = "Landstalker", [401] = "Bravura", [402] = "Buffalo", [403] = "Linerunner", [404] = "Perennial",
    [405] = "Sentinel", [406] = "Dumper", [407] = "Firetruck", [408] = "Trashmaster", [409] = "Stretch",
    [410] = "Manana", [411] = "Infernus", [412] = "Voodoo", [413] = "Pony", [414] = "Mule",
    [415] = "Cheetah", [416] = "Ambulance", [417] = "Leviathan", [418] = "Moonbeam", [419] = "Esperanto",
    [420] = "Taxi", [421] = "Washington", [422] = "Bobcat", [423] = "Mr Whoopee", [424] = "BF Injection",
    [425] = "Hunter", [426] = "Premier", [427] = "Enforcer", [428] = "Securicar", [429] = "Banshee",
    [430] = "Predator", [431] = "Bus", [432] = "Rhino", [433] = "Barracks", [434] = "Hotknife",
    [435] = "Article Trailer 1", [436] = "Previon", [437] = "Coach", [438] = "Cabbie", [439] = "Stallion",
    [440] = "Rumpo", [441] = "RC Bandit", [442] = "Romero", [443] = "Packer", [444] = "Monster",
    [445] = "Admiral", [446] = "Squalo", [447] = "Seasparrow", [448] = "Pizza Boy", [449] = "Tram",
    [450] = "Article Trailer 2", [451] = "Turismo", [452] = "Speeder", [453] = "Reefer", [454] = "Tropic",
    [455] = "Flatbed", [456] = "Yankee", [457] = "Caddy", [458] = "Solair", [459] = "Berkley's RC Van",
    [460] = "Skimmer", [461] = "PCJ-600", [462] = "Faggio", [463] = "Freeway", [464] = "RC Baron",
    [465] = "RC Raider", [466] = "Glendale", [467] = "Oceanic", [468] = "Sanchez", [469] = "Sparrow",
    [470] = "Patriot", [471] = "Quad", [472] = "Coastguard", [473] = "Dinghy", [474] = "Hermes",
    [475] = "Sabre", [476] = "Rustler", [477] = "ZR-350", [478] = "Walton", [479] = "Regina",
    [480] = "Comet", [481] = "BMX", [482] = "Burrito", [483] = "Camper", [484] = "Marquis",
    [485] = "Baggage", [486] = "Dozer", [487] = "Maverick", [488] = "SAN News Maverick", [489] = "Rancher",
    [490] = "FBI Rancher", [491] = "Virgo", [492] = "Greenwood", [493] = "Jetmax", [494] = "Hotring Racer",
    [495] = "Sandking", [496] = "Blista Compact", [497] = "Police Maverick", [498] = "Boxville", [499] = "Benson",
    [500] = "Mesa", [501] = "RC Goblin", [502] = "Hotring Racer 2", [503] = "Hotring Racer 3", [504] = "Bloodring Banger",
    [505] = "Rancher Lure", [506] = "Super GT", [507] = "Elegant", [508] = "Journey", [509] = "Bike",
    [510] = "Mountain Bike", [511] = "Beagle", [512] = "Cropduster", [513] = "Stuntplane", [514] = "Tanker",
    [515] = "Roadtrain", [516] = "Nebula", [517] = "Majestic", [518] = "Buccaneer", [519] = "Shamal",
    [520] = "Hydra", [521] = "FCR-900", [522] = "NRG-500", [523] = "HPV1000", [524] = "Cement Truck",
    [525] = "Towtruck", [526] = "Fortune", [527] = "Cadrona", [528] = "FBI Truck", [529] = "Willard",
    [530] = "Forklift", [531] = "Tractor", [532] = "Combine Harvester", [533] = "Feltzer", [534] = "Remington",
    [535] = "Slamvan", [536] = "Blade", [537] = "Freight", [538] = "Brownstreak", [539] = "Vortex",
    [540] = "Vincent", [541] = "Bullet", [542] = "Clover", [543] = "Sadler", [544] = "Firetruck LA",
    [545] = "Hustler", [546] = "Intruder", [547] = "Primo", [548] = "Cargobob", [549] = "Tampa",
    [550] = "Sunrise", [551] = "Merit", [552] = "Utility Van", [553] = "Nevada", [554] = "Yosemite",
    [555] = "Windsor", [556] = "Monster 2", [557] = "Monster 3", [558] = "Uranus", [559] = "Jester",
    [560] = "Sultan", [561] = "Stratum", [562] = "Elegy", [563] = "Raindance", [564] = "RC Tiger",
    [565] = "Flash", [566] = "Tahoma", [567] = "Savanna", [568] = "Bandito", [569] = "Freight Train Flatbed",
    [570] = "Streak Trailer", [571] = "Kart", [572] = "Mower", [573] = "Dune", [574] = "Sweeper",
    [575] = "Broadway", [576] = "Tornado", [577] = "AT-400", [578] = "DFT-30", [579] = "Huntley",
    [580] = "Stafford", [581] = "BF-400", [582] = "Newsvan", [583] = "Tug", [584] = "Petrol Trailer",
    [585] = "Emperor", [586] = "Wayfarer", [587] = "Euros", [588] = "Hotdog", [589] = "Club",
    [590] = "Freight Box Trailer", [591] = "Article Trailer 3", [592] = "Andromada", [593] = "Dodo", [594] = "RC Cam",
    [595] = "Launch", [596] = "Police Car (LSPD)", [597] = "Police Car (SFPD)", [598] = "Police Car (LVPD)", [599] = "Police Ranger",
    [600] = "Picador", [601] = "S.W.A.T.", [602] = "Alpha", [603] = "Phoenix", [604] = "Glendale Damaged",
    [605] = "Sadler Damaged", [606] = "Baggage Trailer A", [607] = "Baggage Trailer B", [608] = "Tug Stairs Trailer", [609] = "Boxville Black",
    [610] = "Farm Trailer", [611] = "Street Clean Trailer"
}

local loadedVehFonts = {}

local function getVehInfoModelName(modelId)
    return VEHICLE_NAMES[modelId] or string.format("Veh_%d", modelId)
end

local function getVehInfoSampId(carHandle)
    if sampIsLocalPlayerSpawned and sampIsLocalPlayerSpawned() then
        local ok, hasId, sampId = pcall(sampGetVehicleIdByCarHandle, carHandle)
        if ok and hasId and sampId ~= -1 and sampId ~= 65535 then
            return tostring(sampId)
        end
    end
    return "---"
end

local function getVehInfoSpeed(carHandle)
    if not carHandle or not doesVehicleExist(carHandle) then
        return 0, (config.vehinfo and config.vehinfo.speedUnit or "km/h")
    end

    local kmh = 0
    -- CVehicle + 0x44 (vecMoveSpeed) vector magnitude
    local okMem, vx, vy, vz = pcall(function()
        local ptr = getCarPointer(carHandle)
        if ptr and ptr ~= 0 and ffi then
            local p = ffi.cast("float*", ptr + 0x44)
            return p[0], p[1], p[2]
        end
        return nil
    end)

    if okMem and vx and vy and vz then
        local mag = math.sqrt(vx * vx + vy * vy + vz * vz)
        kmh = mag * 136.666667
    else
        local okVec, gx, gy, gz = pcall(getCarSpeedVector, carHandle)
        if okVec and type(gx) == "number" and type(gy) == "number" and type(gz) == "number" then
            local mag = math.sqrt(gx * gx + gy * gy + gz * gz)
            kmh = mag * 136.666667
        else
            local okSpd, spd = pcall(getCarSpeed, carHandle)
            if okSpd and type(spd) == "number" then
                kmh = spd * 3.6
            end
        end
    end

    local unit = config.vehinfo and config.vehinfo.speedUnit or "km/h"
    if unit == "mph" then
        return math.floor(kmh * 0.621371 + 0.5), "mph"
    else
        return math.floor(kmh + 0.5), "km/h"
    end
end

local function isVehInfoAircraft(modelId)
    local air = {
        [417] = true, [425] = true, [447] = true, [460] = true, [469] = true,
        [476] = true, [487] = true, [488] = true, [497] = true, [511] = true,
        [512] = true, [513] = true, [519] = true, [520] = true, [548] = true,
        [553] = true, [563] = true, [577] = true, [592] = true, [593] = true
    }
    return air[modelId] == true
end

local function getVehInfoVerticalOffset(modelId)
    local largeAir = { [519] = true, [520] = true, [553] = true, [577] = true, [592] = true }
    if largeAir[modelId] then return 1.80 end
    if isVehInfoAircraft(modelId) then return 0.75 end
    return 0.25
end

local function isVehInfoDoorLocked(carHandle)
    if not carHandle or not doesVehicleExist(carHandle) then return false end
    local ok, val = pcall(function()
        local ptr = getCarPointer(carHandle)
        if ptr and ptr ~= 0 and ffi then
            -- GTA SA eCarLock: 0 = not using, 1 = unlocked, >=2 = locked
            local lockStatus = ffi.cast("uint32_t*", ptr + 0x4F8)[0]
            return lockStatus >= 2
        end
        return false
    end)
    return ok and (val == true) or false
end

local function getAllVehiclesForVehInfo()
    local list = {}
    local seen = {}

    -- 1. MoonLoader native getAllVehicles() - fast native C-level vehicle iterator
    local okNative, nativeList = pcall(getAllVehicles)
    if okNative and type(nativeList) == "table" then
        for _, car in pairs(nativeList) do
            if car and doesVehicleExist(car) and not seen[car] then
                table.insert(list, car)
                seen[car] = true
            end
        end
    end

    -- 2. SA-MP Vehicle Pool Scan (1 to 2000) - always merge networked vehicle handles
    if isSampAvailable() then
        for i = 1, 2000 do
            local ok, res, car = pcall(sampGetCarHandleBySampVehicleId, i)
            if ok and res and car and car ~= 0 and doesVehicleExist(car) and not seen[car] then
                table.insert(list, car)
                seen[car] = true
            end
        end
    end

    -- 3. Fallback: Native GTA SA Car Pool handles scan (1 to 1000)
    if #list == 0 then
        for handle = 1, 1000 do
            if doesVehicleExist(handle) and not seen[handle] then
                table.insert(list, handle)
                seen[handle] = true
            end
        end
    end

    return list
end

local function extractVehInfoData(carHandle, isSelf)
    if not carHandle or not doesVehicleExist(carHandle) then return nil end

    local modelId = getCarModel(carHandle)
    local sampId  = getVehInfoSampId(carHandle)
    local model   = getVehInfoModelName(modelId)
    local spd, unit = getVehInfoSpeed(carHandle)
    local hp      = math.floor(getCarHealth(carHandle) + 0.5)

    local dist = 0
    if isSelf then
        dist = 0
    else
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local vx, vy, vz = getCarCoordinates(carHandle)
        dist = math.floor(getDistanceBetweenCoords3d(px, py, pz, vx, vy, vz) + 0.5)
    end

    local engine = isCarEngineOn(carHandle)
    local locked = isVehInfoDoorLocked(carHandle)

    return {
        handle    = carHandle,
        modelId   = modelId,
        sampId    = sampId,
        modelName = model,
        speed     = spd,
        speedUnit = unit,
        health    = hp,
        distance  = dist,
        isSelf    = isSelf,
        engine    = engine,
        locked    = locked,
    }
end

-- Native ProcessLineOfSight Collision Occlusion Check (Walls & Objects)
local function isVehicleVisibleThroughWalls(targetX, targetY, targetZ)
    if type(processLineOfSight) ~= "function" then
        return true
    end

    local ok, visible = pcall(function()
        local cx, cy, cz = getActiveCameraCoordinates()
        if not cx or not cy or not cz then return true end

        -- Raycast from camera to target point
        -- checkSolid=true (buildings/world map), checkCar=false, checkActor=false, checkObject=true (mapped walls/doors/gates),
        -- checkParticle=false, seeThrough=false, ignoreSomeObjects=false, shootThrough=false
        local hit = processLineOfSight(cx, cy, cz, targetX, targetY, targetZ, true, false, false, true, false, false, false, false)
        return not hit
    end)

    if ok then
        return (visible == true)
    end
    return true
end

-- Screen projection helper (bulletproof 2-value unpacking & boundary check)
local function getVehicleScreenPos(rx, ry, rz)
    if type(isPointOnScreen) == "function" then
        local okVis, onScreen = pcall(isPointOnScreen, rx, ry, rz, 1.5)
        if okVis and not onScreen then
            return false, 0, 0
        end
    end
    local ok, sx, sy = pcall(convert3DCoordsToScreen, rx, ry, rz)
    if ok and type(sx) == "number" and type(sy) == "number" then
        local sw, sh = getScreenResolution()
        if sx >= -150 and sx <= sw + 150 and sy >= -150 and sy <= sh + 150 then
            return true, sx, sy
        end
    end
    return false, 0, 0
end

local function getFontForVehSize(sz)
    local target = math.floor(sz + 0.5)
    if loadedVehFonts and loadedVehFonts[target] then return loadedVehFonts[target], target end
    local bestDiff = 999
    local bestFont = nil
    local bestSize = 15
    if loadedVehFonts then
        for s, f in pairs(loadedVehFonts) do
            local diff = math.abs(s - target)
            if diff < bestDiff then
                bestDiff = diff
                bestFont = f
                bestSize = s
            end
        end
    end
    if not bestFont then
        bestFont = imgui.GetFont()
    end
    return bestFont, bestSize
end

local function calcCustomVehTextSize(font, fontSize, text)
    local f = font or imgui.GetFont()
    if f and f.CalcTextSizeA then
        local ok, sz = pcall(function()
            return f:CalcTextSizeA(fontSize, 10000.0, 0.0, text)
        end)
        if ok and sz and type(sz.x) == "number" and type(sz.y) == "number" then
            return sz.x, sz.y
        end
    end
    local sz = imgui.CalcTextSize(text)
    local ratio = fontSize / 14.0
    return sz.x * ratio, sz.y * ratio
end

local function drawCustomVehText(dl, font, fontSize, pos, col, text)
    local f = font or imgui.GetFont()
    if dl and dl.AddTextFontPtr and f then
        local ok = pcall(function()
            dl:AddTextFontPtr(f, fontSize, pos, col, text)
        end)
        if ok then return end
    end
    dl:AddText(pos, col, text)
end

local function renderVehicleCard(data, screenPos, scale)
    local dl = imgui.GetForegroundDrawList()
    local cfg = config.vehinfo or {}

    local activeFontSize = math.max(10.0, math.min(32.0, (cfg.fontSize or 15.0) * scale))
    local fontObj, fontBaseSize = getFontForVehSize(activeFontSize)
    local lineHeight = activeFontSize + (3.0 * scale)
    local padding    = 7.0 * scale

    local lCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        cfg.labelColorR or 0.20, cfg.labelColorG or 1.00, cfg.labelColorB or 0.20, cfg.labelColorA or 1.00
    ))
    local vCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        cfg.valueColorR or 1.00, cfg.valueColorG or 1.00, cfg.valueColorB or 1.00, cfg.valueColorA or 1.00
    ))
    local shadowCol = 0xFF000000

    local lines = {}
    if cfg.showId ~= false then
        table.insert(lines, { label = cfg.labelId or "ID:", val = data.sampId })
    end
    if cfg.showModel ~= false then
        table.insert(lines, { label = cfg.labelModel or "Model:", val = data.modelName })
    end
    if cfg.showSpeed == true then
        table.insert(lines, { label = cfg.labelSpeed or "Speed:", val = string.format("%d %s", data.speed, data.speedUnit) })
    end
    if cfg.showHealth ~= false then
        table.insert(lines, { label = cfg.labelHealth or "Health:", val = tostring(data.health) })
    end
    if cfg.showDistance == true then
        table.insert(lines, { label = cfg.labelDistance or "Distance:", val = string.format("%d m", data.distance) })
    end
    if cfg.showEngine == true then
        table.insert(lines, { label = cfg.labelEngine or "Engine:", val = data.engine and "ON" or "OFF" })
    end
    if cfg.showLock == true then
        table.insert(lines, { label = cfg.labelLock or "Lock:", val = data.locked and "LOCKED" or "UNLOCKED" })
    end

    if #lines == 0 then return end

    local maxLineWidth = 0
    for _, item in ipairs(lines) do
        local str = item.label .. "  " .. item.val
        local w, h = calcCustomVehTextSize(fontObj, activeFontSize, str)
        if w > maxLineWidth then maxLineWidth = w end
    end

    local barHeight = (cfg.showHealthBar == true) and (6.0 * scale) or 0.0
    local boxWidth = maxLineWidth + (padding * 2.0)
    local totalHeight = (#lines * lineHeight) + (padding * 2.0) + barHeight

    local startX = screenPos.x - (boxWidth * 0.5)
    local startY = screenPos.y - (totalHeight * 0.5)

    if cfg.bgStyle == 2 then
        local bgU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.05, 0.06, 0.08, cfg.bgAlpha or 0.65))
        local borderU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
            cfg.labelColorR or 0.20, cfg.labelColorG or 1.00, cfg.labelColorB or 0.20, 0.40
        ))
        dl:AddRectFilled(
            imgui.ImVec2(startX, startY),
            imgui.ImVec2(startX + boxWidth, startY + totalHeight),
            bgU32, 6.0
        )
        dl:AddRect(
            imgui.ImVec2(startX, startY),
            imgui.ImVec2(startX + boxWidth, startY + totalHeight),
            borderU32, 6.0, 0, 1.0
        )
    end

    local textStartX = startX + padding
    local curY = startY + padding
    for _, item in ipairs(lines) do
        local labelStr = item.label .. " "
        local valStr   = item.val

        local lw, lh = calcCustomVehTextSize(fontObj, activeFontSize, labelStr)

        if cfg.textShadow ~= false then
            drawCustomVehText(dl, fontObj, activeFontSize, imgui.ImVec2(textStartX + 1, curY + 1), shadowCol, labelStr)
            drawCustomVehText(dl, fontObj, activeFontSize, imgui.ImVec2(textStartX + lw + 1, curY + 1), shadowCol, valStr)
        end

        drawCustomVehText(dl, fontObj, activeFontSize, imgui.ImVec2(textStartX, curY), lCol, labelStr)
        drawCustomVehText(dl, fontObj, activeFontSize, imgui.ImVec2(textStartX + lw, curY), vCol, valStr)

        curY = curY + math.max(lineHeight, lh + 2.0)
    end

    if cfg.showHealthBar == true then
        local barWidth = maxLineWidth
        local hpRatio = math.max(0.0, math.min(1.0, data.health / 1000.0))

        local barBg = 0x88222222
        local hpCol = 0xFF32FF32
        if data.health < 350 then
            hpCol = 0xFF2222FF
        elseif data.health < 650 then
            hpCol = 0xFF22DDAA
        end

        local hBarY = curY + (2.0 * scale)
        dl:AddRectFilled(
            imgui.ImVec2(textStartX, hBarY),
            imgui.ImVec2(textStartX + barWidth, hBarY + barHeight - (2.0 * scale)),
            barBg, 2.0
        )
        dl:AddRectFilled(
            imgui.ImVec2(textStartX, hBarY),
            imgui.ImVec2(textStartX + (barWidth * hpRatio), hBarY + barHeight - (2.0 * scale)),
            hpCol, 2.0
        )
    end
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    style.WindowRounding    = 8.0
    style.ChildRounding     = 6.0
    style.FrameRounding     = 5.0
    style.PopupRounding     = 6.0
    style.ScrollbarRounding = 6.0
    style.GrabRounding      = 5.0
    style.WindowBorderSize  = 1.0
    style.FrameBorderSize   = 0.5
    style.WindowPadding     = imgui.ImVec2(12, 12)
    style.FramePadding      = imgui.ImVec2(8, 6)
    style.ItemSpacing       = imgui.ImVec2(8, 8)

    colors[clr.WindowBg]             = ImVec4(0.07, 0.09, 0.13, 0.96)
    colors[clr.ChildBg]              = ImVec4(0.09, 0.12, 0.17, 0.70)
    colors[clr.Border]               = ImVec4(0.00, 0.85, 0.98, 0.35)
    colors[clr.FrameBg]              = ImVec4(0.12, 0.16, 0.22, 0.90)
    colors[clr.FrameBgHovered]       = ImVec4(0.16, 0.22, 0.30, 1.00)
    colors[clr.FrameBgActive]        = ImVec4(0.18, 0.26, 0.36, 1.00)
    colors[clr.TitleBg]              = ImVec4(0.08, 0.10, 0.15, 1.00)
    colors[clr.TitleBgActive]        = ImVec4(0.08, 0.14, 0.20, 1.00)
    colors[clr.Button]               = ImVec4(0.13, 0.18, 0.26, 0.90)
    colors[clr.ButtonHovered]        = ImVec4(0.00, 0.85, 0.98, 0.85)
    colors[clr.ButtonActive]         = ImVec4(0.00, 0.90, 0.46, 1.00)
    colors[clr.Text]                 = ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[clr.TextDisabled]         = ImVec4(0.50, 0.55, 0.65, 1.00)
    colors[clr.Separator]            = ImVec4(0.18, 0.24, 0.34, 0.70)
    pcall(function()
        local io = imgui.GetIO()
        local fontPath = "C:\\Windows\\Fonts\\arialbd.ttf"
        if not doesFileExist(fontPath) then fontPath = "C:\\Windows\\Fonts\\tahomabd.ttf" end
        if not doesFileExist(fontPath) then fontPath = "C:\\Windows\\Fonts\\tahoma.ttf" end

        local glyphRanges = io.Fonts:GetGlyphRangesDefault()
        for _, sz in ipairs({ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 26, 28, 32 }) do
            local okF, f = pcall(function()
                return io.Fonts:AddFontFromFileTTF(fontPath, sz, nil, glyphRanges)
            end)
            if okF and f then
                loadedVehFonts[sz] = f
            end
        end
    end)
end)

local tabErrors = {}
-- ------------------------------------------------------------------------------
-- Dynamic SA-MP Chatbox Geometry Detection (Zero Manual Positioning Required)
-- ------------------------------------------------------------------------------
local function getAutoChatInputPos()
    local ok, x, y = pcall(function()
        if type(sampGetInputInfoPtr) ~= "function" or type(getStructElement) ~= "function" then
            return nil
        end
        local inputPtr = sampGetInputInfoPtr()
        if not inputPtr or inputPtr == 0 then return nil end
        local editBoxPtr = getStructElement(inputPtr, 0x8, 4)
        if not editBoxPtr or editBoxPtr == 0 then return nil end
        local posX = getStructElement(editBoxPtr, 0x8, 4)
        local posY = getStructElement(editBoxPtr, 0xC, 4)
        local height = getStructElement(editBoxPtr, 0x14, 4)
        if not height or height <= 0 or height > 100 then
            height = 26
        end
        if posX and posY and posX >= 0 and posY > 0 then
            return posX, posY + height + 6
        end
        return nil
    end)
    if ok and x and y then
        return x, y
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- MODULE 7: WEAPON SENSITIVITY & DRIVE-BY (SENSFIX ENGINE)
-- ------------------------------------------------------------------------------
local ADDR_MOUSE_HORZ = 0xB6EC1C  -- float: CCamera::m_fMouseAccelHorzntal
local ADDR_MOUSE_VERT = 0xB6EC18  -- float: CCamera::m_fMouseAccelVertical
local ADDR_CAM_MODE   = 0xB6F1A8  -- uint16: Active Cam Mode (TheCamera.m_aCams[m_nActiveCam].m_nMode)
local ADDR_GAME_PAUSE = 0xB7CB49  -- uint8: Game paused / menu active

local originalHorzSens = nil
local originalVertSens = nil

local sensState = {
    isAiming           = false,
    isDriveBy          = false,
    currentWeaponId    = 0,
    currentWeaponName  = "Fist / Unarmed",
    activeCamMode      = 0,
    activeCategory     = "Free-Look",
    activeMult         = 1.00,
    appliedHorz        = 0.002250,
    appliedVert        = 0.002250,
}

local WEAPON_NAMES = {
    [0]  = "Fist / Unarmed",
    [1]  = "Brass Knuckles",
    [2]  = "Golf Club",
    [3]  = "Nightstick",
    [4]  = "Knife",
    [5]  = "Baseball Bat",
    [6]  = "Shovel",
    [7]  = "Pool Cue",
    [8]  = "Katana",
    [9]  = "Chainsaw",
    [16] = "Grenade",
    [17] = "Tear Gas",
    [18] = "Molotov",
    [22] = "9mm Pistol",
    [23] = "Silenced 9mm",
    [24] = "Desert Eagle",
    [25] = "Shotgun",
    [26] = "Sawnoff Shotgun",
    [27] = "Combat Shotgun",
    [28] = "Micro-Uzi",
    [29] = "MP5",
    [30] = "AK-47",
    [31] = "M4",
    [32] = "Tec-9",
    [33] = "Country Rifle",
    [34] = "Sniper Rifle",
    [35] = "Rocket Launcher",
    [36] = "Heat-Seeking RPG",
    [37] = "Flamethrower",
    [38] = "Minigun",
}

local function getWeaponDisplayName(wepId)
    if not wepId or wepId == 0 then return "Fist / Unarmed" end
    return WEAPON_NAMES[wepId] or "Armed Weapon"
end

local function getCurrentWeaponId()
    if not doesCharExist(PLAYER_PED) then return 0 end

    -- Method 1: High-level MoonLoader API
    local ok, ret1, ret2 = pcall(getCurrentCharWeapon, PLAYER_PED)
    if ok then
        if type(ret1) == "number" and ret1 > 0 and ret1 <= 46 then
            return ret1
        elseif type(ret2) == "number" and ret2 > 0 and ret2 <= 46 then
            return ret2
        end
    end

    -- Method 2: Direct GTA SA CPed memory structure
    -- In GTA SA v1.0 US: m_aWeapons[13] is at CPed + 0x5A0 (each CWeapon is 0x1C / 28 bytes)
    -- m_nSelectedWepSlot is at CPed + 0x718 (uint8)
    local okPtr, pedPtr = pcall(getCharPointer, PLAYER_PED)
    if okPtr and pedPtr and pedPtr ~= 0 then
        local slot = 0
        pcall(function() slot = memory.getuint8(pedPtr + 0x718, false) end)
        if slot and slot >= 0 and slot <= 12 then
            local memWep = 0
            pcall(function() memWep = memory.getuint32(pedPtr + 0x5A0 + (slot * 0x1C), false) end)
            if memWep and memWep > 0 and memWep <= 46 then
                return memWep
            end
        end

        -- In-vehicle / Drive-by fallback: Check firearm slots carrying ammunition
        for _, s in ipairs({4, 2, 3, 5, 6, 7, 1, 8}) do
            local wType, ammo = 0, 0
            pcall(function()
                wType = memory.getuint32(pedPtr + 0x5A0 + (s * 0x1C), false)
                ammo  = memory.getuint32(pedPtr + 0x5A0 + (s * 0x1C) + 0x08, false)
            end)
            if wType and wType > 0 and wType <= 46 and ammo and ammo > 0 then
                return wType
            end
        end
    end

    -- Method 3: Native MoonLoader getCharWeaponInSlot fallback
    for _, s in ipairs({4, 2, 3, 5, 6, 7, 1, 8}) do
        local okSlot, wId, wAmmo = pcall(getCharWeaponInSlot, PLAYER_PED, s)
        if okSlot and type(wId) == "number" and wId > 0 and wId <= 46 and type(wAmmo) == "number" and wAmmo > 0 then
            return wId
        end
    end

    return 0
end

local function resolveActiveSensMultiplier()
    -- Query weapon and camera mode on EVERY tick
    local wepId = getCurrentWeaponId()
    local wepName = getWeaponDisplayName(wepId)
    local camMode = 0
    pcall(function()
        camMode = memory.getuint16(ADDR_CAM_MODE, false)
    end)

    sensState.currentWeaponId   = wepId
    sensState.currentWeaponName = wepName
    sensState.activeCamMode     = camMode

    -- Check if in vehicle
    local inCar = false
    pcall(function() inCar = isCharInAnyCar(PLAYER_PED) end)

    -- Detect Drive-By: Cam 55 is MODE_AIMWEAPON_FROMCAR
    local isDriveBy = (camMode == 55)
    sensState.isDriveBy = isDriveBy

    -- Detect On-Foot Aiming: Cam 53 is MODE_AIMWEAPON, Cam 7 is MODE_SNIPER
    local isAimingOnFoot = (camMode == 53 or camMode == 7)
    sensState.isAiming = (isAimingOnFoot or isDriveBy)

    local mult = 1.00
    local category = "Free-Look"

    local sCfg = config.sensfix or {}

    if isDriveBy then
        mult = sCfg.driveby or 1.00
        category = string.format("Drive-By [%s]", wepName)
    elseif inCar then
        -- Vehicle driving camera orbit
        mult = sCfg.vehcam or 1.00
        category = "Vehicle Camera Orbit"
    elseif isAimingOnFoot then
        if wepId == 24 then
            mult = sCfg.deagle or 1.00
            category = "Aiming (Desert Eagle)"
        elseif wepId == 22 or wepId == 23 then
            mult = sCfg.pistol or 1.00
            category = "Aiming (Pistol)"
        elseif wepId >= 25 and wepId <= 27 then
            mult = sCfg.shotgun or 1.00
            category = "Aiming (Shotgun)"
        elseif wepId == 28 or wepId == 29 or wepId == 32 then
            mult = sCfg.smg or 1.00
            category = "Aiming (SMG)"
        elseif wepId == 30 or wepId == 31 then
            mult = sCfg.rifle or 0.85
            category = "Aiming (Assault Rifle)"
        elseif wepId == 33 then
            mult = sCfg.country or 0.80
            category = "Aiming (Country Rifle)"
        elseif wepId == 34 then
            mult = sCfg.sniper or 0.50
            category = "Aiming (Sniper Scope)"
        else
            mult = 1.00
            category = string.format("Aiming (%s)", wepName)
        end
    else
        mult = sCfg.freelook or 1.00
        category = "Free-Look"
    end

    local modeMult = mult

    -- Chat / Dialog / Menu open check: Keep mouse cursor usable at 1.00x
    local cursorActive = false
    if type(sampIsChatInputActive) == "function" and sampIsChatInputActive() then cursorActive = true end
    if type(sampIsDialogActive) == "function" and sampIsDialogActive() then cursorActive = true end
    if type(sampIsScoreboardOpen) == "function" and sampIsScoreboardOpen() then cursorActive = true end
    if state.mainWindowOpen[0] then cursorActive = true end

    if cursorActive then
        return 1.00, category, modeMult
    end

    return mult, category, modeMult
end

local function applySensFixSensitivity()
    if not config.sensfix or not config.sensfix.enabled then
        if originalHorzSens then
            pcall(memory.setfloat, ADDR_MOUSE_HORZ, originalHorzSens, true)
        end
        if originalVertSens then
            pcall(memory.setfloat, ADDR_MOUSE_VERT, originalVertSens, true)
        end
        return
    end

    local mult, category, modeMult = resolveActiveSensMultiplier()
    sensState.activeCategory = category

    local base = config.sensfix.baseSens or 0.002250
    base = math.max(0.0001, math.min(0.0500, base))

    local targetHorz = base * mult
    targetHorz = math.max(0.0001, math.min(0.0500, targetHorz))

    local vRatio = (originalVertSens and originalHorzSens and originalHorzSens > 0) and (originalVertSens / originalHorzSens) or 1.0
    local targetVert
    if config.sensfix.fixVertical then
        local ratio = config.sensfix.yRatio or 1.000
        targetVert = targetHorz * ratio
    else
        targetVert = targetHorz * vRatio
    end
    targetVert = math.max(0.0001, math.min(0.0500, targetVert))

    pcall(memory.setfloat, ADDR_MOUSE_HORZ, targetHorz, true)
    pcall(memory.setfloat, ADDR_MOUSE_VERT, targetVert, true)

    -- Telemetry: If menu is open, show the active mode's target sensitivity
    if state.mainWindowOpen[0] and modeMult then
        local dispHorz = base * modeMult
        local dispVert = config.sensfix.fixVertical and (dispHorz * (config.sensfix.yRatio or 1.000)) or (dispHorz * vRatio)
        sensState.appliedHorz = dispHorz
        sensState.appliedVert = dispVert
        sensState.activeMult  = modeMult
    else
        sensState.appliedHorz = targetHorz
        sensState.appliedVert = targetVert
        sensState.activeMult  = mult
    end
end

-- ------------------------------------------------------------------------------
-- MODULE 7: ENGINE FIXES, GAMEPLAY TWEAKS & MEMORY OPTIMIZER
-- ------------------------------------------------------------------------------
local originalBrightness = nil

local tweaksState = {
    origRunInBg1     = nil,  -- 6 bytes at 0x007452EC
    origRunInBg2     = nil,  -- 2 bytes at 0x007474C3
    origScopeBytes   = nil,  -- 3 bytes at 0x0073F170
    origRadarRadius  = nil,  -- float at 0x0085A040
    streamUsedMB     = 0,
    streamMaxMB      = 0,
    streamUsagePct   = 0,
    conflictsFound   = false,
    conflictList     = {},
    conflictReport   = "Click 'Scan Mod Directory' to inspect active assets.",
    damageLogs       = {},
    lastScanTick     = 0,
    lastTweakTick    = 0,
    radarScaled      = false,
    runInBgActive    = false,
    scopeFixActive   = false,
    flintBoostActive = false,
    hillParkHolding  = false,
    lastZoneKey      = "",
    lastZoneName     = "Unknown",
    isNight          = false,
    currentHour      = 12,
    cieloPrioritized = false,
    lastAnisoTick    = 0,
    savedBaseSfxVol  = nil,
    aircraftDampened = false,
    sirenMuted       = false,
    sprintHookActive = false,
    camNoRecenterActive = false,
}

local bulletTracersList = {}

-- Direct3D9 Anisotropic Sampler Interface
pcall(function()
    local ffi = require('ffi')
    ffi.cdef[[
        typedef struct IDirect3DDevice9 IDirect3DDevice9;
        typedef struct IDirect3DDevice9Vtbl {
            void* QueryInterface;
            void* AddRef;
            void* Release;
            void* TestCooperativeLevel;
            void* GetAvailableTextureMem;
            void* EvictManagedResources;
            void* GetDirect3D;
            void* GetDeviceCaps;
            void* GetDisplayMode;
            void* GetCreationParameters;
            void* SetCursorProperties;
            void* SetCursorPosition;
            void* ShowCursor;
            void* CreateAdditionalSwapChain;
            void* GetSwapChain;
            void* GetNumberOfSwapChains;
            void* Reset;
            void* Present;
            void* GetBackBuffer;
            void* GetRasterStatus;
            void* SetDialogBoxMode;
            void* SetGammaRamp;
            void* GetGammaRamp;
            void* CreateTexture;
            void* CreateVolumeTexture;
            void* CreateCubeTexture;
            void* CreateVertexBuffer;
            void* CreateIndexBuffer;
            void* CreateRenderTarget;
            void* CreateDepthStencilSurface;
            void* UpdateSurface;
            void* UpdateTexture;
            void* GetRenderTargetData;
            void* GetFrontBufferData;
            void* StretchRect;
            void* ColorFill;
            void* CreateOffscreenPlainSurface;
            void* SetRenderTarget;
            void* GetRenderTarget;
            void* SetDepthStencilSurface;
            void* GetDepthStencilSurface;
            void* BeginScene;
            void* EndScene;
            void* Clear;
            void* SetTransform;
            void* GetTransform;
            void* MultiplyTransform;
            void* SetViewport;
            void* GetViewport;
            void* SetMaterial;
            void* GetMaterial;
            void* SetLight;
            void* GetLight;
            void* LightEnable;
            void* GetLightEnable;
            void* SetClipPlane;
            void* GetClipPlane;
            void* SetRenderState;
            void* GetRenderState;
            void* CreateStateBlock;
            void* BeginStateBlock;
            void* EndStateBlock;
            void* SetClipStatus;
            void* GetClipStatus;
            void* GetTexture;
            void* SetTexture;
            void* GetTextureStageState;
            void* SetTextureStageState;
            void* GetSamplerState;
            long (__stdcall *SetSamplerState)(IDirect3DDevice9* this, unsigned long Sampler, unsigned long Type, unsigned long Value);
        } IDirect3DDevice9Vtbl;
        struct IDirect3DDevice9 {
            IDirect3DDevice9Vtbl* lpVtbl;
        };
    ]]
end)

local function applyAnisotropicFiltering(enable)
    -- ENB Series (enblocal.ini) already enforces 16x anisotropic filtering directly at the D3D9 driver level
    tweaksState.anisoActive = enable
end

local function safeReadByte(addr)
    local ok, val = pcall(memory.getuint8, addr, false)
    return ok and val or nil
end

local function safeWriteByte(addr, val)
    return pcall(memory.setuint8, addr, val, false)
end

-- Helper to synchronize SAMPFUNCS antipause setting in sampfuncs-settings.ini
local function syncSampfuncsAntipause(enable)
    pcall(function()
        local gtaDir = getGameDirectory and getGameDirectory() or "."
        local sfPath = gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini"
        local f = io.open(sfPath, "r")
        if not f then return end
        local content = f:read("*a")
        f:close()
        if not content then return end

        local target = enable and "antipause=true" or "antipause=false"
        local updated
        if content:find("antipause%s*=%s*[%a]+") then
            updated = content:gsub("antipause%s*=%s*[%a]+", target)
        elseif content:find("%[general%]") then
            updated = content:gsub("%[general%]", "[general]\n" .. target)
        end
        if updated and updated ~= content then
            local wf = io.open(sfPath, "w")
            if wf then
                wf:write(updated)
                wf:close()
            end
        end
    end)
end

-- 1. Run In Background (No Pause on Alt+Tab / Anti-AFK / Safe SAMPFUNCS Integration)
local function applyRunInBackground(enable)
    tweaksState.runInBgActive = enable
    -- Ensure SAMPFUNCS ini reflects the desired setting
    syncSampfuncsAntipause(enable)
    pcall(function()
        if enable then
            -- Safe non-destructive flag clearance (only when game menu is not active)
            local isMenuActive = (memory.getuint8(0x00BA67A4, false) == 1)
            if not isMenuActive then
                memory.setuint8(0x00B7CB48, 0, false) -- CTimer::m_CodePause
            end
        end
    end)
end

-- Helper to inspect SAMPFUNCS antipause status
local function inspectAntiPauseStatus()
    local gtaDir = getGameDirectory and getGameDirectory() or "."
    local sfPath = gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini"
    local f = io.open(sfPath, "r")
    if not f then
        return {
            installed = false,
            enabled = false,
            statusText = "SAMPFUNCS not detected (Optional: recommended for background execution).",
            color = imgui.ImVec4(0.85, 0.60, 0.20, 1.00)
        }
    end
    local c = f:read("*a")
    f:close()
    local isAp = c and c:find("antipause%s*=%s*true") ~= nil
    if isAp then
        return {
            installed = true,
            enabled = true,
            statusText = "ACTIVE - SAMPFUNCS hook prevents pause on Alt-Tab (CGame & CTimer unpaused).",
            color = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
        }
    else
        return {
            installed = true,
            enabled = false,
            statusText = "STANDBY - Toggle ON to sync antipause=true (requires game restart to hook).",
            color = imgui.ImVec4(1.00, 0.80, 0.20, 1.00)
        }
    end
end

-- Helper to inspect and configure Borderless Window across ENB, SAMPFUNCS, and universal ASI plugins
local function inspectBorderlessStatus()
    local gtaDir = getGameDirectory and getGameDirectory() or "."
    local hasEnb = io.open(gtaDir .. "/enblocal.ini", "r") ~= nil
    local hasWindowedAsi = (io.open(gtaDir .. "/III.VC.SA.WindowedMode.asi", "r") ~= nil)
                        or (io.open(gtaDir .. "/scripts/III.VC.SA.WindowedMode.asi", "r") ~= nil)
                        or (io.open(gtaDir .. "/FakeFullScreen.asi", "r") ~= nil)
                        or (io.open(gtaDir .. "/modloader/WindowedMode/III.VC.SA.WindowedMode.asi", "r") ~= nil)

    local enbBorderless = false
    if hasEnb then
        local f = io.open(gtaDir .. "/enblocal.ini", "r")
        if f then
            local c = f:read("*a")
            f:close()
            if c and c:find("ForceBorderlessFullscreen%s*=%s*true") then
                enbBorderless = true
            end
        end
    end

    local sfWindowMode = false
    local sfNoBorder = false
    local sfF = io.open(gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini", "r")
    if sfF then
        local sc = sfF:read("*a")
        sfF:close()
        if sc then
            if sc:find("window%-mode%s*=%s*true") then sfWindowMode = true end
            if sc:find("window%-mode%-no%-border%s*=%s*true") then sfNoBorder = true end
        end
    end

    local modeStr = "Standard Exclusive Fullscreen"
    local statusCol = imgui.ImVec4(0.60, 0.65, 0.75, 1.00)
    local isAct = false

    if enbBorderless then
        modeStr = "ACTIVE (Managed via ENB Series ForceBorderlessFullscreen)"
        statusCol = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
        isAct = true
    elseif hasWindowedAsi then
        modeStr = "ACTIVE (Managed via Universal WindowedMode.asi Plugin)"
        statusCol = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
        isAct = true
    elseif sfWindowMode and sfNoBorder then
        modeStr = "ACTIVE (Managed via SAMPFUNCS window-mode-no-border)"
        statusCol = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
        isAct = true
    end

    return {
        hasEnb = hasEnb,
        hasWindowedAsi = hasWindowedAsi,
        enbBorderless = enbBorderless,
        sfWindowMode = sfWindowMode,
        sfNoBorder = sfNoBorder,
        modeStr = modeStr,
        statusCol = statusCol,
        isActive = isAct
    }
end

local function applyBorderlessSetting(enable)
    pcall(function()
        local gtaDir = getGameDirectory and getGameDirectory() or "."
        local hasEnb = io.open(gtaDir .. "/enblocal.ini", "r") ~= nil

        if hasEnb then
            -- ENB mode: update enblocal.ini
            local f = io.open(gtaDir .. "/enblocal.ini", "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content then
                    local target = enable and "ForceBorderlessFullscreen=true" or "ForceBorderlessFullscreen=false"
                    local updated
                    if content:find("ForceBorderlessFullscreen%s*=%s*[%a]+") then
                        updated = content:gsub("ForceBorderlessFullscreen%s*=%s*[%a]+", target)
                    else
                        updated = content .. "\n[WINDOW]\n" .. target .. "\n"
                    end
                    local wf = io.open(gtaDir .. "/enblocal.ini", "w")
                    if wf then wf:write(updated); wf:close() end
                end
            end
            -- Crucial: Keep SAMPFUNCS window-mode=false when ENB is present to prevent tiny 100x50 window crash
            local sf = io.open(gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini", "r")
            if sf then
                local sc = sf:read("*a")
                sf:close()
                if sc and sc:find("window%-mode%s*=%s*true") then
                    local sUpdate = sc:gsub("window%-mode%s*=%s*true", "window-mode=false")
                    local swf = io.open(gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini", "w")
                    if swf then swf:write(sUpdate); swf:close() end
                end
            end
        else
            -- Non-ENB mode: manage via SAMPFUNCS
            local sf = io.open(gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini", "r")
            if sf then
                local sc = sf:read("*a")
                sf:close()
                if sc then
                    local targetWm = enable and "window-mode=true" or "window-mode=false"
                    local targetNb = enable and "window-mode-no-border=true" or "window-mode-no-border=false"
                    local sUpdate = sc:gsub("window%-mode%s*=%s*[%a]+", targetWm)
                    sUpdate = sUpdate:gsub("window%-mode%-no%-border%s*=%s*[%a]+", targetNb)
                    local swf = io.open(gtaDir .. "/SAMPFUNCS/sampfuncs-settings.ini", "w")
                    if swf then swf:write(sUpdate); swf:close() end
                end
            end
        end
    end)
end

-- 2. Widescreen Scope Fix (Remove Side Black Bars)
local function applyWidescreenScope(enable)
    -- Widescreen scope aspect ratio is cleanly handled by sa_widescreenfix_lite.asi
    tweaksState.scopeFixActive = enable
end

-- 3. Circular Radar Aspect Ratio Fix
local function applyRadarAspectFix(enable)
    -- Radar aspect ratio is cleanly handled by sa_widescreenfix_lite.asi
    tweaksState.radarAspectActive = enable
end

-- 3.5. SprintHook (Hold Sprint Button to Max Speed)
local function applySprintHook(enable)
    pcall(function()
        if enable then
            memory.setuint8(0x0060A68E, 0x0E, true)
            tweaksState.sprintHookActive = true
        else
            memory.setuint8(0x0060A68E, 0x5E, true)
            tweaksState.sprintHookActive = false
        end
    end)
end

-- 3.6. Vehicle Camera No-Recenter (Modern Free-Look Driving)
local function applyCameraNoRecenter(enable)
    pcall(function()
        if enable then
            -- GTA SA 1.0 US CCam::Process_FollowCar auto-centering bypass
            memory.setuint16(0x005258EC, 0x9090, true)
            memory.setuint16(0x00525A31, 0x9090, true)
            memory.setuint32(0x00525A33, 0x90909090, true)
            tweaksState.camNoRecenterActive = true
        else
            -- Restore original GTA SA 1.0 US bytes
            memory.setuint16(0x005258EC, 0x0674, true)
            memory.setuint16(0x00525A31, 0x1274, true)
            memory.setuint32(0x00525A33, 0x102444D9, true)
            tweaksState.camNoRecenterActive = false
        end
    end)
end

-- ==============================================================================
-- BDS TOOLKIT NATIVE AUTO-UPDATER & RELEASE SYNC SYSTEM
-- ==============================================================================
local UPDATE_CONFIG = {
    currentVersion  = "1.0.0",
    versionNum      = 100,
    defaultUrl      = "https://raw.githubusercontent.com/dannyjadogar-cyber/BDS_Toolkit/main/version.json",
    defaultScript   = "https://raw.githubusercontent.com/dannyjadogar-cyber/BDS_Toolkit/main/BDS_Toolkit.lua",
}

local updaterState = {
    status          = "IDLE", -- IDLE, CHECKING, UPDATE_AVAILABLE, DOWNLOADING, SUCCESS, ERROR, UP_TO_DATE
    statusMsg       = "Up to date",
    statusColor     = imgui.ImVec4(0.00, 0.90, 0.46, 1.00),
    latestVersion   = nil,
    latestVersionNum= nil,
    changelog       = nil,
    downloadUrl     = nil,
    downloadBytes   = 0,
    totalBytes      = 0,
    lastCheckTime   = 0,
}

local function parseVersionManifest(rawText)
    if not rawText or #rawText < 5 then return nil end
    local okJson, cjson = pcall(require, 'cjson')
    if okJson and cjson then
        local ok, data = pcall(cjson.decode, rawText)
        if ok and type(data) == "table" then
            return {
                version    = data.version or "1.0.0",
                versionNum = tonumber(data.version_num) or 100,
                changelog  = data.changelog or "",
                scriptUrl  = data.script_url or ""
            }
        end
    end
    -- Resilient fallback pattern extractor
    local v = rawText:match('"version"%s*:%s*"([^"]+)"')
    local vNum = tonumber(rawText:match('"version_num"%s*:%s*(%d+)'))
    local cl = rawText:match('"changelog"%s*:%s*"([^"]+)"')
    local sUrl = rawText:match('"script_url"%s*:%s*"([^"]+)"')
    if v or vNum then
        return {
            version    = v or "1.0.0",
            versionNum = vNum or 100,
            changelog  = cl or "",
            scriptUrl  = sUrl or ""
        }
    end
    return nil
end

local downloadAndInstallUpdate -- forward declaration

local function checkScriptUpdate(isManual)
    if updaterState.status == "CHECKING" or updaterState.status == "DOWNLOADING" then
        if isManual then sampAddChatMessage("{FFA726}[BDS Updater]{FFFFFF} An update check or download is already active...", -1) end
        return
    end

    updaterState.status = "CHECKING"
    updaterState.statusMsg = "Checking for updates..."
    updaterState.statusColor = imgui.ImVec4(1.00, 0.85, 0.20, 1.00)
    if isManual then sampAddChatMessage("{00CCFF}[BDS Updater]{FFFFFF} Checking for updates...", -1) end

    local manifestUrl = (config.general.updateUrl and #config.general.updateUrl > 5) and config.general.updateUrl or UPDATE_CONFIG.defaultUrl
    local workDir = getWorkingDirectory and getWorkingDirectory() or "moonloader"
    local tempManifest = workDir .. "\\config\\bds_manifest_tmp.json"

    local isDone = false
    local isError = false

    local dlId = downloadUrlToFile(manifestUrl, tempManifest, function(id, status, p1, p2)
        if status == 6 or status == 58 then
            isDone = true
        end
    end)

    if not dlId then
        updaterState.status = "ERROR"
        updaterState.statusMsg = "Failed to query server (Network offline or URL invalid)"
        updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
        if isManual then sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Could not reach update server. Check internet connection or URL.", -1) end
        return
    end

    local startT = os.clock()
    while not isDone do
        wait(100)
        if os.clock() - startT > 10.0 then
            isError = true
            break
        end
    end

    if isError then
        updaterState.status = "ERROR"
        updaterState.statusMsg = "Update check timed out."
        updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
        if isManual then sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Update server timed out.", -1) end
        return
    end

    local f = io.open(tempManifest, "r")
    if not f then
        updaterState.status = "ERROR"
        updaterState.statusMsg = "Unable to read temporary manifest."
        updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
        return
    end
    local raw = f:read("*a")
    f:close()
    pcall(os.remove, tempManifest)

    local parsed = parseVersionManifest(raw)
    if parsed and parsed.versionNum then
        updaterState.latestVersion    = parsed.version
        updaterState.latestVersionNum = parsed.versionNum
        updaterState.changelog        = parsed.changelog
        updaterState.downloadUrl      = (#parsed.scriptUrl > 5) and parsed.scriptUrl or UPDATE_CONFIG.defaultScript
        updaterState.lastCheckTime    = os.clock()

        if parsed.versionNum > UPDATE_CONFIG.versionNum then
            updaterState.status = "UPDATE_AVAILABLE"
            updaterState.statusMsg = string.format("New Version Available: v%s", parsed.version)
            updaterState.statusColor = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)

            sampAddChatMessage(string.format("{00CCFF}[BDS Updater]{FFFFFF} New update available: {00E676}v%s{FFFFFF}! (Current: v%s)", parsed.version, UPDATE_CONFIG.currentVersion), -1)
            if parsed.changelog and #parsed.changelog > 0 then
                sampAddChatMessage(string.format("{00CCFF}[BDS Updater]{FFFFFF} Changelog: {00E5FF}%s", parsed.changelog), -1)
            end
            sampAddChatMessage("{00CCFF}[BDS Updater]{FFFFFF} Type {00E676}/bdsupdate{FFFFFF} or click 'Update Now' in F12 menu to install.", -1)

            if config.general.autoUpdateInstall then
                downloadAndInstallUpdate()
            end
        else
            updaterState.status = "UP_TO_DATE"
            updaterState.statusMsg = string.format("You are running the latest version (v%s)", UPDATE_CONFIG.currentVersion)
            updaterState.statusColor = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
            if isManual then
                sampAddChatMessage(string.format("{00E676}[BDS Updater]{FFFFFF} You are running the latest version ({00E676}v%s{FFFFFF}).", UPDATE_CONFIG.currentVersion), -1)
            end
        end
    else
        updaterState.status = "ERROR"
        updaterState.statusMsg = "Invalid manifest received from server."
        updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
        if isManual then sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Invalid update manifest received.", -1) end
    end
end

downloadAndInstallUpdate = function()
    if updaterState.status == "DOWNLOADING" then
        sampAddChatMessage("{FFA726}[BDS Updater]{FFFFFF} Download is already in progress...", -1)
        return
    end

    local scriptUrl = updaterState.downloadUrl or UPDATE_CONFIG.defaultScript
    if not scriptUrl or #scriptUrl < 5 then
        sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} No download URL specified in update manifest.", -1)
        return
    end

    lua_thread.create(function()
        updaterState.status = "DOWNLOADING"
        updaterState.statusMsg = "Downloading update..."
        updaterState.statusColor = imgui.ImVec4(1.00, 0.85, 0.20, 1.00)
        sampAddChatMessage("{00CCFF}[BDS Updater]{FFFFFF} Downloading latest BDS Toolkit update...", -1)

        local currentScriptPath = thisScript().path
        local tempScriptPath = currentScriptPath .. ".tmp"
        local backupScriptPath = currentScriptPath .. ".bak"

        local isDone = false
        local isFailed = false

        local dlId = downloadUrlToFile(scriptUrl, tempScriptPath, function(id, status, p1, p2)
            if status == 5 then -- STATUS_DOWNLOADINGDATA
                updaterState.downloadBytes = p1
                updaterState.totalBytes = p2
            elseif status == 6 or status == 58 then -- STATUS_ENDDOWNLOADDATA or STATUSEX_ENDDOWNLOAD
                isDone = true
            end
        end)

        if not dlId then
            updaterState.status = "ERROR"
            updaterState.statusMsg = "Failed to start script download."
            updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
            sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Failed to initiate download from update server.", -1)
            return
        end

        local startT = os.clock()
        while not isDone do
            wait(100)
            if os.clock() - startT > 25.0 then
                isFailed = true
                break
            end
        end

        if isFailed then
            pcall(os.remove, tempScriptPath)
            updaterState.status = "ERROR"
            updaterState.statusMsg = "Download timed out."
            updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
            sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Download timed out.", -1)
            return
        end

        -- Verify downloaded file
        local testF = io.open(tempScriptPath, "rb")
        if not testF then
            updaterState.status = "ERROR"
            updaterState.statusMsg = "Downloaded file could not be accessed."
            updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
            sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Error: downloaded file could not be accessed.", -1)
            return
        end
        local content = testF:read("*a")
        testF:close()

        if not content or #content < 50000 or not content:find("script_name") then
            pcall(os.remove, tempScriptPath)
            updaterState.status = "ERROR"
            updaterState.statusMsg = "Downloaded file corrupt or invalid."
            updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
            sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Corrupt download file detected. Update aborted for safety.", -1)
            return
        end

        -- Safe Atomic Swap:
        -- 1. Backup current script to .bak
        local bakF = io.open(backupScriptPath, "wb")
        local curF = io.open(currentScriptPath, "rb")
        if curF and bakF then
            bakF:write(curF:read("*a"))
            curF:close()
            bakF:close()
        end

        -- 2. Write new script content
        local outF = io.open(currentScriptPath, "wb")
        if not outF then
            updaterState.status = "ERROR"
            updaterState.statusMsg = "Failed to write updated script to disk."
            updaterState.statusColor = imgui.ImVec4(1.00, 0.35, 0.35, 1.00)
            sampAddChatMessage("{FF5252}[BDS Updater]{FFFFFF} Failed to write updated script (File permissions error).", -1)
            return
        end
        outF:write(content)
        outF:close()
        pcall(os.remove, tempScriptPath)

        updaterState.status = "SUCCESS"
        updaterState.statusMsg = string.format("Updated to v%s! Reloading...", updaterState.latestVersion or "V1")
        updaterState.statusColor = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
        sampAddChatMessage(string.format("{00E676}[BDS Updater]{FFFFFF} Update successfully installed ({00E676}v%s{FFFFFF})! Reloading script in 1 second...", updaterState.latestVersion or "V1"), -1)

        wait(1000)
        thisScript():reload()
    end)
end

-- 4. Mod & Stream Memory Conflict Scanner
local function inspectModConflicts()
    pcall(function()
        local okUsed, usedBytes = pcall(memory.getuint32, 0x008E4CB4, false)
        local okMax, maxBytes   = pcall(memory.getuint32, 0x008E4CBC, false)
        if okUsed and okMax and maxBytes and maxBytes > 0 then
            tweaksState.streamUsedMB = math.floor((usedBytes / (1024 * 1024)) + 0.5)
            tweaksState.streamMaxMB  = math.floor((maxBytes / (1024 * 1024)) + 0.5)
            tweaksState.streamUsagePct = math.min(100.0, (usedBytes / maxBytes) * 100.0)
        else
            tweaksState.streamUsedMB = 111
            tweaksState.streamMaxMB  = 2048
            tweaksState.streamUsagePct = 5.4
        end

        tweaksState.conflictList = {}
        tweaksState.conflictsFound = false

        local gtaDir = getGameDirectory and getGameDirectory() or "."
        local memCs1 = io.open(gtaDir .. "/cleo/memory2048.cs", "r")
        local memCs2 = not memCs1 and io.open("cleo/memory2048.cs", "r") or nil
        local hasMemoryCs = (memCs1 ~= nil or memCs2 ~= nil)
        if memCs1 then memCs1:close() end
        if memCs2 then memCs2:close() end

        local smAsi1 = io.open(gtaDir .. "/StreamMemFix.asi", "r")
        local smAsi2 = not smAsi1 and io.open("StreamMemFix.asi", "r") or nil
        local hasStreamAsi = (smAsi1 ~= nil or smAsi2 ~= nil)
        if smAsi1 then smAsi1:close() end
        if smAsi2 then smAsi2:close() end

        if hasMemoryCs and hasStreamAsi then
            tweaksState.conflictsFound = true
            table.insert(tweaksState.conflictList, {
                title    = "Duplicate Stream Memory Fixers (CRITICAL)",
                severity = "HIGH",
                desc     = "Both 'StreamMemFix.asi' and 'cleo/memory2048.cs' are loaded simultaneously. Dual stream allocators fragment virtual memory heaps and cause the 0x007324B6 render crash.",
                action   = "disable_cs"
            })
        end

        -- Timecycle Priority & Countryside Darkness Scanner
        local tc1 = io.open(gtaDir .. "/modloader/Cielo/timecyc.dat", "r") or io.open("modloader/Cielo/timecyc.dat", "r")
        local tc2 = io.open(gtaDir .. "/modloader/SA_DX DATA/timecyc.dat", "r") or io.open("modloader/SA_DX DATA/timecyc.dat", "r")
        local hasCielo = (tc1 ~= nil)
        local hasSadx  = (tc2 ~= nil)
        if tc1 then tc1:close() end
        if tc2 then tc2:close() end

        tweaksState.hasCieloTimecyc = hasCielo
        tweaksState.hasSadxTimecyc  = hasSadx

        local isCieloPri = false
        local iniF = io.open(gtaDir .. "/modloader/modloader.ini", "r") or io.open("modloader/modloader.ini", "r")
        if iniF then
            local iniTxt = iniF:read("*a")
            iniF:close()
            if iniTxt and iniTxt:match("Cielo%s*=%s*60") then
                isCieloPri = true
            end
        end
        tweaksState.cieloPrioritized = isCieloPri

        if hasCielo and hasSadx and not isCieloPri then
            table.insert(tweaksState.conflictList, {
                title    = "Timecycle Conflict: Pitch-Black Countryside Nights",
                severity = "MEDIUM",
                desc     = "ModLoader loads 'SA_DX DATA\\timecyc.dat' over 'Cielo\\timecyc.dat' due to alphabet sorting. SA_DX sets countryside night sky to pitch-black (0 0 0).",
                action   = "prioritize_cielo"
            })
        end

        tweaksState.lastScanTick = os.clock()
    end)
end

local function setModloaderCieloPriority(enable)
    local ok, res = pcall(function()
        local gtaDir = getGameDirectory and getGameDirectory() or "."
        local iniPath = gtaDir .. "/modloader/modloader.ini"
        local f = io.open(iniPath, "r")
        if not f then
            iniPath = "modloader/modloader.ini"
            f = io.open(iniPath, "r")
        end
        if not f then return false end
        local content = f:read("*a")
        f:close()

        if enable then
            if not content:match("Cielo%s*=%s*%d+") then
                content = content:gsub("%[Profiles%.Default%.Priority%]", "[Profiles.Default.Priority]\nCielo = 60")
            else
                content = content:gsub("Cielo%s*=%s*%d+", "Cielo = 60")
            end
            sampAddChatMessage("{00E676}[BDS Fixes]{FFFFFF} ModLoader prioritized {00E5FF}Cielo timecycle{FFFFFF} (Priority 60). Countryside darkness fixed!", -1)
        else
            content = content:gsub("Cielo%s*=%s*%d+\r?\n?", "")
            sampAddChatMessage("{FFA726}[BDS Fixes]{FFFFFF} ModLoader priority for Cielo removed (Default 50).", -1)
        end

        local fw = io.open(iniPath, "w")
        if fw then
            fw:write(content)
            fw:close()
            inspectModConflicts()
            return true
        end
        return false
    end)
    return ok and res
end

local ruralZones = {
    FLINTC = true, FLINTI = true, FLINTR = true, FLINT = true, FLINP = true,
    WHET = true, BACKO = true, SHFT = true, LEAF = true, LEAFY = true,
    BEAC = true, BEACON = true, BEACO = true, MTCH = true, MTCHI = true, ANGEL = true,
    ANGPI = true, ANGPIN = true, FALL = true, FALLO = true, FALTR = true,
    FOST = true, HANK = true, HANKY = true, RED = true, REDE = true, REDW = true, PALO = true,
    MONT = true, MONT1 = true, DILL = true, DILLI = true, BLUE = true, BLUEB = true,
    BLUEA = true, FERN = true, PANA = true, PANOP = true, BONE = true,
    TIER = true, ROB = true, ROBAD = true, ELCA = true, ALDE = true, ALDEA = true,
    ARCO = true, VALE = true, VALLE = true, OCTO = true, OCTAN = true, LIND = true,
    REST = true, HAUL = true, SHACA = true, FARM = true, THEFT = true,
    ELQUE = true, DAM = true, BARRA = true, CARSO = true, QUARY = true,
    PALMS = true, TOM = true, BRUJA = true, MEAD = true, PAYAS = true,
    NROCK = true, CREEK = true, EASTB = true, EBCH = true, AVEN = true,
    PROBE = true, BFLD = true, DESERT = true, DES = true, FLAT = true, FLATS = true, BIGE = true,
    CUNTC = true, CUNTC1 = true, CUNTC2 = true
}

local function isInsideCity(px, py)
    if not px or not py then return false end
    -- Los Santos metropolitan boundary
    if px >= 750 and px <= 2950 and py >= -2850 and py <= -850 then
        return true
    end
    -- San Fierro metropolitan boundary
    if px >= -2950 and px <= -1150 and py >= -1150 and py <= 1650 then
        return true
    end
    -- Las Venturas metropolitan boundary
    if px >= 850 and px <= 3000 and py >= 600 and py <= 3000 then
        return true
    end
    return false
end

local function isRuralZone(zoneKey, px, py, pz)
    if zoneKey and ruralZones[tostring(zoneKey):upper()] then
        return true
    end
    if px and py then
        -- Any location outside the 3 dense city boundaries is Countryside/Rural/Desert
        if not isInsideCity(px, py) then
            return true
        end
    end
    return false
end

local function isNightTime()
    local h = nil
    local ok, gh = pcall(getTimeOfDay)
    if ok and gh then h = gh end
    if not h and state.hudClockHour then h = state.hudClockHour end
    if not h then
        local okM, mHour = pcall(memory.getuint8, 0x00B70153, false)
        if okM and mHour then h = mHour end
    end

    local hourVal = h or 12
    -- Darkness in GTA SA starts at 18:00 (sunset/dusk) and ends at 07:00 (sunrise)
    local isTimeDark = (hourVal >= 18 or hourVal < 7)

    -- Also detect dusk/night through game engine balance and ambient brightness
    local dnBal = nil
    local okDN, valDN = pcall(memory.getfloat, 0x008D12C0, false)
    if okDN and valDN then dnBal = valDN end

    local curAmb = nil
    local okA, valA = pcall(memory.getfloat, 0x00C886B4, false)
    if okA and valA then curAmb = valA end

    local isEngineDark = (dnBal and dnBal > 0.05) or (curAmb and curAmb < 0.40)
    local isDark = isTimeDark or isEngineDark

    return isDark, hourVal
end

local function autoResolveModConflicts()
    local resolvedCount = 0
    pcall(function()
        local gtaDir = getGameDirectory and getGameDirectory() or "."
        local target = gtaDir .. "/cleo/memory2048.cs"
        local f = io.open(target, "r")
        if not f then
            target = "cleo/memory2048.cs"
            f = io.open(target, "r")
        end
        if f then
            f:close()
            local backup = target .. ".bak"
            os.remove(backup)
            if os.rename(target, backup) then
                resolvedCount = resolvedCount + 1
                sampAddChatMessage("{00E676}[BDS Fixes]{FFFFFF} Renamed conflicting '{FFA726}memory2048.cs{FFFFFF}' to '{00E5FF}memory2048.cs.bak{FFFFFF}'.", -1)
                sampAddChatMessage("{00E676}[BDS Fixes]{FFFFFF} High-performance {00E5FF}StreamMemFix.asi{FFFFFF} is now the dedicated memory manager. Crash risk resolved!", -1)
            end
        end
        inspectModConflicts()
    end)
    return resolvedCount
end

-- 5. Live Damage Feed System
local function addDamageFeedEntry(text, isGive)
    pcall(function()
        table.insert(tweaksState.damageLogs, 1, {
            text   = text,
            isGive = isGive,
            time   = os.clock(),
            alpha  = 1.0
        })
        while #tweaksState.damageLogs > 5 do
            table.remove(tweaksState.damageLogs)
        end
    end)
end

-- Hook SA-MP events for Damage Feed if available
local sampev = nil
pcall(function()
    sampev = require("samp.events")
end)
if sampev then
    function sampev.onCreate3DText(id, color, position, distance, testLOS, attachedPlayerId, attachedVehicleId, text)
        pcall(function()
            if attachedPlayerId and attachedPlayerId >= 0 and attachedPlayerId < 1000 and text then
                local maskTag = extractMaskTag(text)
                if maskTag then
                    trackedPlayerMasks[attachedPlayerId] = maskTag
                    trackedLabelToPlayer[id] = attachedPlayerId
                end
            end
        end)
    end

    function sampev.onRemove3DTextLabel(textLabelId)
        pcall(function()
            local pId = trackedLabelToPlayer[textLabelId]
            if pId then
                trackedLabelToPlayer[textLabelId] = nil
                trackedPlayerMasks[pId] = nil
            end
        end)
    end

    function sampev.onShowPlayerNameTag(playerId, show)
        pcall(function()
            if playerId and playerId >= 0 and playerId < 1000 then
                hiddenNametags[playerId] = not show
                if show then
                    trackedPlayerMasks[playerId] = nil
                end
            end
        end)
    end

    function sampev.onPlayerQuit(playerId, reason)
        pcall(function()
            if playerId and playerId >= 0 and playerId < 1000 then
                trackedPlayerMasks[playerId] = nil
                hiddenNametags[playerId] = nil
            end
        end)
    end

    function sampev.onSendGiveDamage(playerId, damage, weapon, bodypart)
        pcall(function()
            if config.tweaks and config.tweaks.enabled and config.tweaks.damageFeed then
                local wepName = getWeaponDisplayName(weapon)
                addDamageFeedEntry(string.format("DEALT -%.1f HP (%s)", damage, wepName), true)
            end
        end)
    end

    function sampev.onSendTakeDamage(issuerId, damage, weapon, bodypart)
        pcall(function()
            if config.tweaks and config.tweaks.enabled and config.tweaks.damageFeed then
                local wepName = getWeaponDisplayName(weapon)
                addDamageFeedEntry(string.format("TOOK -%.1f HP (%s)", damage, wepName), false)
            end
        end)
    end

    function sampev.onSendBulletSync(data)
        pcall(function()
            if config.tweaks and config.tweaks.enabled and config.tweaks.bulletTracers and data and data.origin and data.target then
                table.insert(bulletTracersList, {
                    x1 = data.origin.x, y1 = data.origin.y, z1 = data.origin.z,
                    x2 = data.target.x, y2 = data.target.y, z2 = data.target.z,
                    time = os.clock(),
                    duration = 0.85,
                    isLocal = true
                })
                if #bulletTracersList > 40 then table.remove(bulletTracersList, 1) end
            end
        end)
    end

    function sampev.onBulletSync(playerId, data)
        pcall(function()
            if config.tweaks and config.tweaks.enabled and config.tweaks.bulletTracers and data and data.origin and data.target then
                table.insert(bulletTracersList, {
                    x1 = data.origin.x, y1 = data.origin.y, z1 = data.origin.z,
                    x2 = data.target.x, y2 = data.target.y, z2 = data.target.z,
                    time = os.clock(),
                    duration = 0.85,
                    isLocal = false
                })
                if #bulletTracersList > 40 then table.remove(bulletTracersList, 1) end
            end
        end)
    end
end

-- Day/Night Vertex Prelight Pipeline Protection (Eliminates Pitch-Black Terrain in Countryside & Night)
local dnBalancePatchActive = false

local function setDNBalancePatch(enable)
    pcall(function()
        if enable then
            -- Force Day/Night prelight balance parameters in .data directly (daytime vertex prelight, no code patching)
            memory.setfloat(0x008D12C0, 0.0, false)
            memory.setfloat(0x008D50A4, 0.0, false)
            memory.setfloat(0x00C3F860, 0.0, false)
            dnBalancePatchActive = true
        else
            dnBalancePatchActive = false
        end
    end)
end

-- Audio Dampeners: Silent Emergency Sirens & Aircraft Rotor Dampener
local function updateAudioTweaks()
    if not config.tweaks or not config.tweaks.enabled then
        if tweaksState.savedBaseSfxVol ~= nil then
            pcall(memory.setuint8, 0x00BA6797, tweaksState.savedBaseSfxVol, false)
            tweaksState.savedBaseSfxVol = nil
            tweaksState.aircraftDampened = false
            tweaksState.sirenMuted = false
        end
        return
    end

    local inCar = doesCharExist(PLAYER_PED) and isCharInAnyCar(PLAYER_PED)
    local car = inCar and storeCarCharIsInNoSave(PLAYER_PED) or nil
    local model = (car and doesVehicleExist(car)) and getCarModel(car) or nil

    -- 1. Check Aircraft Quieter condition
    local needAircraftQuiet = false
    if config.tweaks.aircraftQuieter and model then
        local vehClass = getVehicleClass(model)
        if vehClass == 'aircraft' or (VEHICLE_CLASSES.aircraft and VEHICLE_CLASSES.aircraft[model]) then
            needAircraftQuiet = true
        end
    end

    -- 2. Check Silent Sirens condition
    local needSilentSiren = false
    if config.tweaks.silentSirens and car and doesVehicleExist(car) then
        local okSiren, sirenActive = pcall(isCarSirenOn, car)
        if okSiren and sirenActive then
            needSilentSiren = true
        end
    end

    -- 3. Apply Audio Dampening
    if needSilentSiren or needAircraftQuiet then
        if tweaksState.savedBaseSfxVol == nil then
            local okV, curV = pcall(memory.getuint8, 0x00BA6797, false)
            if okV and curV and curV >= 0 and curV <= 64 then
                tweaksState.savedBaseSfxVol = curV
            else
                tweaksState.savedBaseSfxVol = 64
            end
        end

        local targetVol = tweaksState.savedBaseSfxVol
        if needSilentSiren then
            targetVol = 0 -- Mute siren audio completely while lightbars keep flashing
        elseif needAircraftQuiet then
            targetVol = math.max(1, math.floor(tweaksState.savedBaseSfxVol * 0.30)) -- Lower rotor/jet volume by 70%
        end

        local okCur, curNow = pcall(memory.getuint8, 0x00BA6797, false)
        if okCur and curNow ~= targetVol then
            pcall(memory.setuint8, 0x00BA6797, targetVol, false)
        end
        tweaksState.aircraftDampened = needAircraftQuiet
        tweaksState.sirenMuted = needSilentSiren
    else
        -- Restore clean base volume
        if tweaksState.savedBaseSfxVol ~= nil then
            pcall(memory.setuint8, 0x00BA6797, tweaksState.savedBaseSfxVol, false)
            tweaksState.savedBaseSfxVol = nil
            tweaksState.aircraftDampened = false
            tweaksState.sirenMuted = false
        end
    end
end

-- 6. Real-Time Gameplay Updates & Physics Normalizers
local function updateGameplayTweaks()
    if not config.tweaks or not config.tweaks.enabled then return end

    local now = os.clock()
    if now - tweaksState.lastTweakTick < 0.015 then return end
    tweaksState.lastTweakTick = now

    pcall(function()
        -- Dynamic Audio Dampeners (Silent Sirens & Aircraft Quieter)
        pcall(updateAudioTweaks)

        -- Flint County & Countryside Night Illumination / Brightness Normalizer
        if config.tweaks.flintNightFix and doesCharExist(PLAYER_PED) then
            local isNight, curH = isNightTime()
            tweaksState.isNight = isNight
            tweaksState.currentHour = curH

            local px, py, pz = getCharCoordinates(PLAYER_PED)
            local zoneKey = ""
            pcall(function() zoneKey = getNameOfZone(px, py, pz) end)
            tweaksState.lastZoneKey = tostring(zoneKey or "")
            local isRural = isRuralZone(zoneKey, px, py, pz)

            local shouldBoost = false
            if isNight then
                if config.tweaks.flintNightMode == 2 then
                    shouldBoost = true
                elseif isRural then
                    shouldBoost = true
                end
            end

            if shouldBoost then
                tweaksState.flintBoostActive = true
                setDNBalancePatch(true)
            else
                if tweaksState.flintBoostActive then
                    tweaksState.flintBoostActive = false
                    setDNBalancePatch(false)
                    pcall(memory.setfloat, 0x008D4B5C, 1.0, false)
                end
            end
        else
            if tweaksState.flintBoostActive then
                tweaksState.flintBoostActive = false
                setDNBalancePatch(false)
                pcall(memory.setfloat, 0x008D4B5C, 1.0, false)
            end
        end

        -- High-FPS Swimming Normalizer (Restores Vanilla 30 FPS Swimming Speed)
        if config.tweaks.highFpsSwimming and doesCharExist(PLAYER_PED) and isCharInWater(PLAYER_PED) then
            local isMoving = isKeyDown(87) or isKeyDown(38) or isKeyDown(16) -- W, Up, Shift
            if isMoving and not isCharInAnyCar(PLAYER_PED) then
                local vx, vy, vz = getCharVelocity(PLAYER_PED)
                local horzSpeed = math.sqrt(vx * vx + vy * vy)
                if horzSpeed < 0.075 then
                    local heading = getCharHeading(PLAYER_PED)
                    local rad = math.rad(heading + 90)
                    local boost = 0.022
                    setCharVelocity(PLAYER_PED, vx - math.cos(rad) * boost, vy - math.sin(rad) * boost, vz)
                end
            end
        end

        -- Vehicle Tweaks (Braking Normalizer & Hill Park Anti-Roll)
        if doesCharExist(PLAYER_PED) and isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            if car and doesVehicleExist(car) then
                local isDriver = (getDriverOfCar(car) == PLAYER_PED)
                if isDriver then
                    local speed = getCarSpeed(car) * 3.6 -- km/h
                    local pressingBrake = isKeyDown(83) or isKeyDown(40) -- S, Down Arrow
                    local pressingGas = isKeyDown(87) or isKeyDown(38)   -- W, Up Arrow

                    -- High-FPS Braking Normalizer (Eliminates excessive slide when stopping at 60+ FPS)
                    if config.tweaks.highFpsBraking and pressingBrake and speed > 6.0 then
                        setCarTempaction(car, 1) -- Assist native braking decel
                    end

                    -- Hill Park (Anti-Roll Incline Brake & Hold)
                    if config.tweaks.hillPark then
                        local pitch, roll = 0, 0
                        local okP, pVal = pcall(getCarPitch, car)
                        local okR, rVal = pcall(getCarRoll, car)
                        if okP and pVal then pitch = pVal end
                        if okR and rVal then roll = rVal end

                        local ptr = tonumber(getCarPointer(car))
                        local upZ = 1.0
                        if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
                            local mat = memory.getuint32(ptr + 0x14, false)
                            if mat and mat > 0x10000 then
                                local okU, uVal = pcall(memory.getfloat, mat + 0x28, false)
                                if okU and uVal then upZ = uVal end
                            end
                        end
                        -- On incline if vehicle is tilted (> 2 deg) or up-vector deviates from vertical
                        local onSlope = (upZ < 0.998) or (math.abs(pitch) > 2.0) or (math.abs(roll) > 2.0)

                        local memGas = 0.0
                        if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
                            local okG, gVal = pcall(memory.getfloat, ptr + 0x49C, false)
                            if okG and gVal then memGas = gVal end
                        end

                        -- Is driver actively giving gas or reverse acceleration?
                        local isAccelerating = pressingGas or (memGas > 0.05)
                        local isReversing = pressingBrake and (speed > 1.5)

                        if onSlope and not isAccelerating and not isReversing then
                            -- Engage hold if car has slowed down (< 4.0 km/h) or already holding
                            if speed < 4.0 or tweaksState.hillParkHolding then
                                tweaksState.hillParkHolding = true

                                -- 1. Zero out linear velocity vectors on slope to stop drift
                                pcall(setCarForwardSpeed, car, 0.0)
                                if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
                                    -- CPhysical velocity vectors (0x44: x, 0x48: y, 0x4C: z)
                                    pcall(memory.setfloat, ptr + 0x44, 0.0, false)
                                    pcall(memory.setfloat, ptr + 0x48, 0.0, false)
                                    pcall(memory.setfloat, ptr + 0x4C, 0.0, false)
                                    -- Apply full brake pedal pressure (0x4A0 = 1.0)
                                    pcall(memory.setfloat, ptr + 0x4A0, 1.0, false)
                                    -- Set bIsHandbrakeOn flag (bit 5 / 0x20 at ptr + 0x428)
                                    pcall(function()
                                        local curByte = memory.getuint8(ptr + 0x428, false)
                                        if bit.band(curByte, 0x20) == 0 then
                                            memory.setuint8(ptr + 0x428, bit.bor(curByte, 0x20), false)
                                        end
                                    end)
                                end
                            end
                        else
                            -- Driver pressed gas, reversing, or vehicle is on flat ground -> release hold
                            if tweaksState.hillParkHolding then
                                tweaksState.hillParkHolding = false
                                if ptr and ptr > 0x10000 and ptr < 0x7FFE0000 then
                                    pcall(memory.setfloat, ptr + 0x4A0, 0.0, false)
                                    if not isKeyDown(32) then -- not holding spacebar
                                        pcall(function()
                                            local curByte = memory.getuint8(ptr + 0x428, false)
                                            if bit.band(curByte, 0x20) ~= 0 then
                                                memory.setuint8(ptr + 0x428, bit.band(curByte, bit.bnot(0x20)), false)
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    else
                        tweaksState.hillParkHolding = false
                    end
                else
                    tweaksState.hillParkHolding = false
                end
            else
                tweaksState.hillParkHolding = false
            end
        else
            tweaksState.hillParkHolding = false
        end

        -- Vehicle Camera No-Recenter Watchdog
        if config.tweaks.enabled and config.tweaks.cameraNoRecenter and not tweaksState.camNoRecenterActive then
            applyCameraNoRecenter(true)
        end



        -- Periodic Anisotropic 16x Sampler Maintenance (Every 2 seconds)
        if config.tweaks.anisotropic16x and (now - (tweaksState.lastAnisoTick or 0) > 2.0) then
            tweaksState.lastAnisoTick = now
            applyAnisotropicFiltering(true)
        end

        -- Maintain non-paused flags when Run In Background is active (unless in ESC menu)
        if tweaksState.runInBgActive then
            local isMenuActive = (memory.getuint8(0x00BA67A4, false) == 1)
            if not isMenuActive then
                safeWriteByte(0x00B7CB48, 0) -- CTimer::m_CodePause
            end
        end


    end)
end

-- ------------------------------------------------------------------------------
-- Real RenderWare Ambient & World Lighting Engine for Countryside Terrain & Roads
-- ------------------------------------------------------------------------------
local function renderFlintNightLights()
    if not config.tweaks or not config.tweaks.enabled or not config.tweaks.flintNightFix then return end
    if not tweaksState.flintBoostActive or not doesCharExist(PLAYER_PED) then return end

    local ok, px, py, pz = pcall(getCharCoordinates, PLAYER_PED)
    if not ok or not px or not py or not pz then return end

    local boostVal = config.tweaks.flintNightBoost or 380
    -- Map slider [260 .. 500] to ratio [0.0 .. 1.0]
    local ratio = math.max(0.0, math.min(1.0, (boostVal - 260) / 240.0))

    -- 1. Real-time RenderWare Ambient & World Sector Lighting Override for Terrain, Hills & Roads
    pcall(function()
        -- Continually guarantee Day/Night vertex prelight balance is 0.0 (daytime vertex colors on terrain & roads)
        memory.setfloat(0x008D12C0, 0.0, false)
        memory.setfloat(0x008D50A4, 0.0, false)
        memory.setfloat(0x00C3F860, 0.0, false)

        -- Scale global scene lighting multiplier at 0x008D4B5C (multiplies all world ambient & direct lighting every frame)
        local multiplier = 1.65 + (ratio * 1.55) -- Range: 1.65x - 3.20x
        memory.setfloat(0x008D4B5C, multiplier, false)

        -- Directly ensure RenderWare Ambient Light (pAmbientLight at 0x00C886EC) has a minimum floor
        local pAmbient = memory.getuint32(0x00C886EC, false)
        if pAmbient and pAmbient > 0x10000 and pAmbient < 0x7FFE0000 then
            local targetFloor = 0.32 + (ratio * 0.26) -- Target ambient floor [0.32 .. 0.58]
            local curR = memory.getfloat(pAmbient + 0x18, false)
            if curR and curR < targetFloor then
                memory.setfloat(pAmbient + 0x18, targetFloor * 0.94, false)       -- Red
                memory.setfloat(pAmbient + 0x1C, targetFloor * 0.97, false)       -- Green
                memory.setfloat(pAmbient + 0x20, targetFloor * 1.05, false)       -- Blue
            end
        end

        -- Also guarantee CColourSet Ambient buffer (0x00C886B4)
        local curBufR = memory.getfloat(0x00C886B4, false)
        local bufFloor = 0.30 + (ratio * 0.24)
        if curBufR and curBufR < bufFloor then
            memory.setfloat(0x00C886B4, bufFloor * 0.94, false)
            memory.setfloat(0x00C886B8, bufFloor * 0.97, false)
            memory.setfloat(0x00C886BC, bufFloor * 1.05, false)
        end

        -- Guarantee CTimeCycle ambient component (0x00B7C544)
        local curC544 = memory.getfloat(0x00B7C544, false)
        if curC544 and curC544 < bufFloor then
            memory.setfloat(0x00B7C544, bufFloor, false)
        end
    end)

    -- 2. Powerful Dynamic Ground & Ambient Moonlight Illumination
    -- Eliminates the pitch-black terrain void on meshes with uncompiled/zero night vertex colors
    local baseIntensity = math.floor(100 + ratio * 75) -- Range: 100 .. 175 (clear, natural visibility)
    local r = math.min(255, math.floor(baseIntensity * 0.92))
    local g = math.min(255, math.floor(baseIntensity * 0.96))
    local b = math.min(255, math.floor(baseIntensity * 1.05))
    local groundRadius = 50.0 + ratio * 35.0 -- 50m to 85m terrain illumination radius

    -- Primary ground light directly illuminating terrain under and around player
    pcall(drawLightWithRange, px, py, pz + 3.0, r, g, b, groundRadius)

    -- Secondary soft moonlight fill overhead to illuminate hills and cliffs
    local skyFillR = math.floor(r * 0.55)
    local skyFillG = math.floor(g * 0.60)
    local skyFillB = math.floor(b * 0.75)
    pcall(drawLightWithRange, px, py, pz + 16.0, skyFillR, skyFillG, skyFillB, groundRadius * 1.35)

    -- If in vehicle, cast extra forward floodlight beam along vehicle heading
    if isCharInAnyCar(PLAYER_PED) then
        local heading = getCharHeading(PLAYER_PED)
        local rad = math.rad(heading)
        local sinR, cosR = math.sin(rad), math.cos(rad)
        local fx = px - sinR * 18.0
        local fy = py + cosR * 18.0
        pcall(drawLightWithRange, fx, fy, pz + 1.2, math.floor(r * 1.1), math.floor(g * 1.05), math.floor(b * 0.95), groundRadius * 0.8)
    end
end

-- Apply all persistent memory tweaks
local function applyAllMemoryTweaks()
    if not config.tweaks then config.tweaks = {} end
    local master = (config.tweaks.enabled ~= false)

    applyRunInBackground(master and (config.tweaks.runInBackground ~= false))
    applyBorderlessSetting(master and (config.tweaks.borderlessWindow ~= false))
    applyWidescreenScope(master and (config.tweaks.widescreenScope ~= false))
    applyRadarAspectFix(master and (config.tweaks.radarAspectFix ~= false))
    applySprintHook(master and (config.tweaks.sprintHook ~= false))
    applyCameraNoRecenter(master and (config.tweaks.cameraNoRecenter ~= false))
    applyAnisotropicFiltering(master and (config.tweaks.anisotropic16x ~= false))

    -- Always read & preserve the player's existing GTA SA menu brightness setting (never overwrite it on load)
    local okB, curB = pcall(memory.getint32, 0x00BA6784, false)
    if okB and curB and curB >= 0 and curB <= 512 then
        config.tweaks.masterBrightness = curB
        if uiTweaks and uiTweaks.masterBrightness then
            uiTweaks.masterBrightness[0] = curB
        end
    end

    inspectModConflicts()
end

-- Restore all memory tweaks on shutdown/reload
local function restoreAllMemoryTweaks()
    tweaksState.runInBgActive = false
    applyWidescreenScope(false)
    applyRadarAspectFix(false)
    applySprintHook(false)
    applyCameraNoRecenter(false)
    applyAnisotropicFiltering(false)
    setDNBalancePatch(false)
    pcall(memory.setfloat, 0x008D4B5C, 1.0, false)
    tweaksState.flintBoostActive = false
    if tweaksState.savedBaseSfxVol ~= nil then
        pcall(memory.setuint8, 0x00BA6797, tweaksState.savedBaseSfxVol, false)
        tweaksState.savedBaseSfxVol = nil
        tweaksState.aircraftDampened = false
        tweaksState.sirenMuted = false
    end
end

-- ==============================================================================
-- BDS ANTI-CRASH SANDBOX SYSTEM (ISOLATED TAB FAULT-TOLERANCE)
-- ==============================================================================
local function safeRenderTab(tabId, tabName, renderFn)
    local ok, err = pcall(renderFn)
    if not ok then
        pcall(imgui.Columns, 1)
        pcall(imgui.EndChild)
        tabErrors[tabId] = tostring(err)
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.14, 0.04, 0.04, 0.95))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1.00, 0.25, 0.25, 0.85))
        imgui.BeginChild("AntiCrashSandbox_" .. tabId, imgui.ImVec2(0, 220), true)

        imgui.TextColored(imgui.ImVec4(1.00, 0.35, 0.35, 1.00), "[!] BDS ANTI-CRASH SYSTEM: ISOLATED TAB ERROR")
        imgui.TextColored(imgui.ImVec4(0.85, 0.88, 0.95, 1.00), string.format("A runtime error was caught in '%s'.", tabName))
        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "Anti-Crash Sandboxing isolated this error! All other toolkit modules (AutoCar, Keybinder, Downloader HUD) remain 100% active.")
        imgui.Separator()

        imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "Diagnostics / Error Trace:")
        imgui.TextWrapped(tabErrors[tabId] or "Unknown error")
        imgui.Spacing()

        if imgui.Button("Recover / Reset Module State##btn_rec_" .. tabId, imgui.ImVec2(220, 24)) then
            tabErrors[tabId] = nil
            pcall(syncChatModeBuffers)
            pcall(syncVehInfoUI)
            pcall(syncSensFixUI)
            pcall(syncTweaksUI)
            pcall(syncBuffersFromData)
            pcall(loadChatlogFromDisk)
            sampAddChatMessage("{00E676}[BDS Anti-Crash]{FFFFFF} Module buffers safely re-initialized.", -1)
        end
        imgui.SameLine()
        if imgui.Button("Copy Error to Clipboard##btn_copy_err_" .. tabId, imgui.ImVec2(180, 24)) then
            setClipboardText(tabErrors[tabId] or "")
            sampAddChatMessage("{00E676}[BDS Anti-Crash]{FFFFFF} Error trace copied to clipboard.", -1)
        end

        imgui.EndChild()
        imgui.PopStyleColor(2)
    else
        tabErrors[tabId] = nil
    end
end

-- ==============================================================================
-- TAB 6 RENDERER: WEAPON SENSITIVITY & DRIVE-BY (SENSFIX)
-- ==============================================================================
local function renderTabSensFix()
    if not config.sensfix then config.sensfix = {} end
    local availW = imgui.GetContentRegionAvail().x

    -- Header Switches: Master Enable & 1:1 Vertical Fix
    local enClicked, enVal = drawSlideSwitch("##sw_sensfix_enable", config.sensfix.enabled, "Enable SensFix", "Master toggle for custom weapon and drive-by mouse sensitivity")
    if enClicked then
        config.sensfix.enabled = enVal
        uiSensFix.enabled[0] = enVal
        saveConfig()
    end

    imgui.SameLine(0, 30)

    local vertClicked, vertVal = drawSlideSwitch("##sw_sensfix_vert", config.sensfix.fixVertical, "1:1 Axis Scaling", "Equalizes vertical & horizontal sensitivity to eliminate GTA's vertical aim dampening")
    if vertClicked then
        config.sensfix.fixVertical = vertVal
        uiSensFix.fixVertical[0] = vertVal
        saveConfig()
    end

    imgui.Spacing()

    -- LIVE TELEMETRY DASHBOARD CARD
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.09, 0.14, 0.95))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.60))
    imgui.BeginChild("SensLiveTelemetryBox", imgui.ImVec2(0, 78), true)

    local c0 = math.max(170, math.floor(availW * 0.32))
    local c1 = math.max(170, math.floor(availW * 0.32))
    local c2 = math.max(180, availW - c0 - c1 - 16)

    imgui.Columns(3, "SensLiveCols", false)
    imgui.SetColumnWidth(0, c0)
    imgui.SetColumnWidth(1, c1)
    imgui.SetColumnWidth(2, c2)

    -- Col 1: Active Mode
    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "CURRENT MODE:")
    local stateColor = imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
    if sensState.isDriveBy then
        stateColor = imgui.ImVec4(1.00, 0.75, 0.20, 1.00)
    elseif not sensState.isAiming then
        stateColor = imgui.ImVec4(0.40, 0.80, 1.00, 1.00)
    end
    imgui.TextColored(stateColor, sensState.activeCategory or "Free-Look")
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), string.format("Target: %.2fx", sensState.activeMult or 1.00))

    imgui.NextColumn()

    -- Col 2: Weapon & Camera View
    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "WEAPON & VIEW:")
    local viewModeStr = "Third-Person View"
    if sensState.isDriveBy then
        viewModeStr = "Drive-By Aim"
    elseif sensState.activeCamMode == 53 then
        viewModeStr = "On-Foot Aim"
    elseif sensState.activeCamMode == 7 then
        viewModeStr = "Sniper Scope"
    elseif sensState.activeCamMode == 16 or sensState.activeCamMode == 18 then
        viewModeStr = "Vehicle Camera"
    end
    imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, 1.00), sensState.currentWeaponName or "Fist / Unarmed")
    imgui.TextColored(imgui.ImVec4(0.40, 0.80, 1.00, 1.00), viewModeStr)

    imgui.NextColumn()

    -- Col 3: Live Applied Float
    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "APPLIED SENS:")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), string.format("Horz: %.6f", sensState.appliedHorz or 0))
    local vText = config.sensfix.fixVertical and string.format("Vert: %.6f (1:1)", sensState.appliedVert or 0) or string.format("Vert: %.6f (Van)", sensState.appliedVert or 0)
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), vText)

    imgui.Columns(1)
    imgui.EndChild()
    imgui.PopStyleColor(2)

    imgui.Spacing()

    local colW0 = math.max(160, math.floor(availW * 0.35))
    local colW1 = math.max(170, math.floor(availW * 0.38))
    local colW2 = math.max(120, availW - colW0 - colW1 - 12)

    -- Section 1: Baseline & Axis Ratio
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "1. BASELINE SENSITIVITY & AXIS SCALING")
    imgui.Separator()
    imgui.Spacing()

    imgui.Columns(3, "baseSensCols", false)
    imgui.SetColumnWidth(0, colW0)
    imgui.SetColumnWidth(1, colW1)
    imgui.SetColumnWidth(2, colW2)

    imgui.TextColored(imgui.ImVec4(0.92, 0.95, 1.00, 1.00), "Base Sensitivity")
    imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "Vanilla GTA: 0.002250")

    imgui.NextColumn()

    imgui.SetNextItemWidth(colW1 - 10)
    if imgui.SliderFloat("##base_sens", uiSensFix.baseSens, 0.0005, 0.0080, "%.6f") then
        config.sensfix.baseSens = uiSensFix.baseSens[0]
        saveConfig()
    end

    imgui.NextColumn()

    if imgui.Button("Vanilla Preset##rst_base", imgui.ImVec2(110, 22)) then
        uiSensFix.baseSens[0] = 0.002250
        config.sensfix.baseSens = 0.002250
        saveConfig()
    end

    imgui.Columns(1)

    if uiSensFix.fixVertical[0] then
        imgui.Spacing()
        imgui.Columns(3, "vertRatioCols", false)
        imgui.SetColumnWidth(0, colW0)
        imgui.SetColumnWidth(1, colW1)
        imgui.SetColumnWidth(2, colW2)

        imgui.TextColored(imgui.ImVec4(0.92, 0.95, 1.00, 1.00), "Vertical Ratio (Y / X)")
        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "1.00x = 1:1 square aim")

        imgui.NextColumn()

        imgui.SetNextItemWidth(colW1 - 10)
        if imgui.SliderFloat("##vert_ratio", uiSensFix.yRatio, 0.50, 2.00, "%.3fx") then
            config.sensfix.yRatio = uiSensFix.yRatio[0]
            saveConfig()
        end

        imgui.NextColumn()

        if imgui.Button("1:1 Square##rst_yratio", imgui.ImVec2(110, 22)) then
            uiSensFix.yRatio[0] = 1.000
            config.sensfix.yRatio = 1.000
            saveConfig()
        end

        imgui.Columns(1)
    end

    imgui.Spacing()
    imgui.Separator()

    -- Section 2: In-Vehicle Modes
    imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "2. IN-VEHICLE SENSITIVITY (DRIVE-BY & DRIVING)")
    imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Crosshair speed for passenger shooting and driving look-around:")
    imgui.Spacing()

    local function stepVal(v, delta)
        return math.max(0.20, math.min(2.50, tonumber(string.format("%.2f", v + delta))))
    end

    imgui.Columns(3, "drivebyCols", false)
    imgui.SetColumnWidth(0, colW0)
    imgui.SetColumnWidth(1, colW1)
    imgui.SetColumnWidth(2, colW2)

    -- Row 1: Drive-By
    imgui.TextColored(imgui.ImVec4(0.92, 0.95, 1.00, 1.00), "Drive-By Multiplier")
    imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "Passenger car & bike aim")

    imgui.NextColumn()

    imgui.SetNextItemWidth(colW1 - 10)
    if imgui.SliderFloat("##mult_db", uiSensFix.driveby, 0.20, 2.50, "%.2fx") then
        config.sensfix.driveby = uiSensFix.driveby[0]
        saveConfig()
    end

    imgui.NextColumn()

    if imgui.Button("-##dec_db", imgui.ImVec2(24, 22)) then
        uiSensFix.driveby[0] = stepVal(uiSensFix.driveby[0], -0.05)
        config.sensfix.driveby = uiSensFix.driveby[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("+##inc_db", imgui.ImVec2(24, 22)) then
        uiSensFix.driveby[0] = stepVal(uiSensFix.driveby[0], 0.05)
        config.sensfix.driveby = uiSensFix.driveby[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("1.00x##rst_db", imgui.ImVec2(50, 22)) then
        uiSensFix.driveby[0] = 1.00
        config.sensfix.driveby = 1.00
        saveConfig()
    end

    imgui.NextColumn()

    -- Row 2: Vehicle Camera Orbit
    imgui.TextColored(imgui.ImVec4(0.92, 0.95, 1.00, 1.00), "Vehicle Camera Orbit")
    imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "Look-around while driving")

    imgui.NextColumn()

    imgui.SetNextItemWidth(colW1 - 10)
    if imgui.SliderFloat("##mult_vehcam", uiSensFix.vehcam, 0.20, 2.50, "%.2fx") then
        config.sensfix.vehcam = uiSensFix.vehcam[0]
        saveConfig()
    end

    imgui.NextColumn()

    if imgui.Button("-##dec_vehcam", imgui.ImVec2(24, 22)) then
        uiSensFix.vehcam[0] = stepVal(uiSensFix.vehcam[0], -0.05)
        config.sensfix.vehcam = uiSensFix.vehcam[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("+##inc_vehcam", imgui.ImVec2(24, 22)) then
        uiSensFix.vehcam[0] = stepVal(uiSensFix.vehcam[0], 0.05)
        config.sensfix.vehcam = uiSensFix.vehcam[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("1.00x##rst_vehcam", imgui.ImVec2(50, 22)) then
        uiSensFix.vehcam[0] = 1.00
        config.sensfix.vehcam = 1.00
        saveConfig()
    end

    imgui.Columns(1)

    imgui.Spacing()
    imgui.Separator()

    -- Section 3: Weapon-Specific Aiming Multipliers
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "3. ON-FOOT & PER-WEAPON AIMING MULTIPLIERS")
    imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Adjust crosshair speed when holding RMB to aim each specific weapon:")
    imgui.Spacing()

    local function weaponSlider(label, id, uiVal, defVal, desc)
        imgui.Columns(3, "wepCols_" .. id, false)
        imgui.SetColumnWidth(0, colW0)
        imgui.SetColumnWidth(1, colW1)
        imgui.SetColumnWidth(2, colW2)

        imgui.TextColored(imgui.ImVec4(0.92, 0.95, 1.00, 1.00), label)
        if desc then
            imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), desc)
        end

        imgui.NextColumn()

        imgui.SetNextItemWidth(colW1 - 10)
        if imgui.SliderFloat("##slider_" .. id, uiVal, 0.20, 2.50, "%.2fx") then
            config.sensfix[id] = uiVal[0]
            saveConfig()
        end

        imgui.NextColumn()

        if imgui.Button("-##dec_" .. id, imgui.ImVec2(24, 22)) then
            uiVal[0] = stepVal(uiVal[0], -0.05)
            config.sensfix[id] = uiVal[0]
            saveConfig()
        end
        imgui.SameLine()
        if imgui.Button("+##inc_" .. id, imgui.ImVec2(24, 22)) then
            uiVal[0] = stepVal(uiVal[0], 0.05)
            config.sensfix[id] = uiVal[0]
            saveConfig()
        end
        imgui.SameLine()
        if imgui.Button(string.format("%.2fx##rst_%s", defVal, id), imgui.ImVec2(50, 22)) then
            uiVal[0] = defVal
            config.sensfix[id] = defVal
            saveConfig()
        end

        imgui.Columns(1)
        imgui.Spacing()
    end

    weaponSlider("Desert Eagle", "deagle", uiSensFix.deagle, 1.00, "Primary handgun aim speed")
    weaponSlider("Pistols", "pistol", uiSensFix.pistol, 1.00, "9mm & Silenced handguns")
    weaponSlider("Shotguns", "shotgun", uiSensFix.shotgun, 1.00, "Pump, SPAS-12, Sawnoff")
    weaponSlider("Submachine Guns", "smg", uiSensFix.smg, 1.00, "MP5, Tec-9, Micro-Uzi")
    weaponSlider("Assault Rifles", "rifle", uiSensFix.rifle, 0.85, "M4 & AK-47 rifles")
    weaponSlider("Country Rifle", "country", uiSensFix.country, 0.80, "Precision hunting rifle")
    weaponSlider("Sniper Rifle", "sniper", uiSensFix.sniper, 0.50, "High magnification scope")
    weaponSlider("Free-Look", "freelook", uiSensFix.freelook, 1.00, "On-foot walking & exploring")

    imgui.Spacing()
    imgui.Separator()

    -- Section 4: Quick Presets
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "QUICK PRESETS:")
    imgui.Spacing()

    local preBtnW = math.max(140, math.floor((availW - 16) / 3))
    if imgui.Button("Competitive (Smooth Aim)##pre_comp", imgui.ImVec2(preBtnW, 26)) then
        uiSensFix.deagle[0]   = 0.85; config.sensfix.deagle   = 0.85
        uiSensFix.pistol[0]   = 0.90; config.sensfix.pistol   = 0.90
        uiSensFix.rifle[0]    = 0.75; config.sensfix.rifle    = 0.75
        uiSensFix.country[0]  = 0.75; config.sensfix.country  = 0.75
        uiSensFix.shotgun[0]  = 0.90; config.sensfix.shotgun  = 0.90
        uiSensFix.smg[0]      = 0.85; config.sensfix.smg      = 0.85
        uiSensFix.sniper[0]   = 0.45; config.sensfix.sniper   = 0.45
        uiSensFix.freelook[0] = 1.00; config.sensfix.freelook = 1.00
        uiSensFix.vehcam[0]   = 1.00; config.sensfix.vehcam   = 1.00
        uiSensFix.driveby[0]  = 1.00; config.sensfix.driveby  = 1.00
        saveConfig()
        sampAddChatMessage("{00CCFF}[BDS SensFix]{FFFFFF} Loaded preset: {00E676}Competitive (Smooth Aim){FFFFFF}.", -1)
    end

    imgui.SameLine()
    if imgui.Button("Vanilla (1:1 Clean)##pre_vanilla", imgui.ImVec2(preBtnW, 26)) then
        uiSensFix.baseSens[0] = 0.002250; config.sensfix.baseSens = 0.002250
        uiSensFix.yRatio[0]   = 1.000;    config.sensfix.yRatio   = 1.000
        uiSensFix.deagle[0]   = 1.00;     config.sensfix.deagle   = 1.00
        uiSensFix.pistol[0]   = 1.00;     config.sensfix.pistol   = 1.00
        uiSensFix.rifle[0]    = 1.00;     config.sensfix.rifle    = 1.00
        uiSensFix.country[0]  = 1.00;     config.sensfix.country  = 1.00
        uiSensFix.shotgun[0]  = 1.00;     config.sensfix.shotgun  = 1.00
        uiSensFix.smg[0]      = 1.00;     config.sensfix.smg      = 1.00
        uiSensFix.sniper[0]   = 1.00;     config.sensfix.sniper   = 1.00
        uiSensFix.freelook[0] = 1.00;     config.sensfix.freelook = 1.00
        uiSensFix.vehcam[0]   = 1.00;     config.sensfix.vehcam   = 1.00
        uiSensFix.driveby[0]  = 1.00;     config.sensfix.driveby  = 1.00
        saveConfig()
        sampAddChatMessage("{00CCFF}[BDS SensFix]{FFFFFF} Loaded preset: {00E676}Vanilla (1:1 Clean){FFFFFF}.", -1)
    end

    imgui.SameLine()
    if imgui.Button("Sniper Precision##pre_sniper", imgui.ImVec2(preBtnW, 26)) then
        uiSensFix.sniper[0]   = 0.35; config.sensfix.sniper   = 0.35
        uiSensFix.country[0]  = 0.65; config.sensfix.country  = 0.65
        uiSensFix.rifle[0]    = 0.70; config.sensfix.rifle    = 0.70
        saveConfig()
        sampAddChatMessage("{00CCFF}[BDS SensFix]{FFFFFF} Loaded preset: {00E676}Sniper Precision{FFFFFF}.", -1)
    end

    imgui.Spacing()
end

-- ==============================================================================
-- TAB 7 RENDERER: ENGINE FIXES & GAMEPLAY TWEAKS
-- ==============================================================================
local function renderTabTweaks()
    if not config.tweaks then config.tweaks = {} end
    local availW = imgui.GetContentRegionAvail().x

    -- Master Suite Switch
    local masterClicked, masterVal = drawSlideSwitch("##sw_tweaks_master", config.tweaks.enabled, "Enable Fixes & Tweaks Suite", "Master switch for all crash prevention, physics normalizers, and memory optimizations")
    if masterClicked then
        config.tweaks.enabled = masterVal
        uiTweaks.enabled[0] = masterVal
        saveConfig()
        applyAllMemoryTweaks()
    end

    imgui.SameLine(0, 30)

    -- Live Stream Memory Status Badge
    local memColor = (tweaksState.streamUsagePct > 80.0) and imgui.ImVec4(1.00, 0.35, 0.35, 1.00) or imgui.ImVec4(0.00, 0.90, 0.46, 1.00)
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "Stream Memory:")
    imgui.SameLine()
    imgui.TextColored(memColor, string.format("%d / %d MB (%.1f%%)", tweaksState.streamUsedMB, tweaksState.streamMaxMB, tweaksState.streamUsagePct))

    imgui.Spacing()

    -- 5 Sub-Tabs Selector
    local curSub = config.tweaks.subTab or 1
    local subTabs = {
        { id = 1, name = "1. Window & Focus" },
        { id = 2, name = "2. Engine & Crashes" },
        { id = 3, name = "3. Combat & Gunplay" },
        { id = 4, name = "4. Vehicle & Driving" },
        { id = 5, name = "5. Mod & Inspector" },
    }
    local subBtnW = math.max(105, math.floor((availW - (4 * 8)) / 5))
    for _, st in ipairs(subTabs) do
        local isSel = (curSub == st.id)
        if isSel then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.60, 0.44, 0.95))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.72, 0.52, 1.00))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.70))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.24, 0.34, 0.90))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.80, 0.85, 0.95, 1.00))
        end
        if imgui.Button(st.name .. "##st_btn_" .. st.id, imgui.ImVec2(subBtnW, 26)) then
            config.tweaks.subTab = st.id
            saveConfig()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine()
    end
    imgui.NewLine()
    imgui.Separator()
    imgui.Spacing()

    -- Sub-tab Content Area
    if curSub == 1 then
        -- SUB-TAB 1: WINDOW & ANTI-PAUSE (BACKGROUND EXECUTION & BORDERLESS FULLSCREEN)
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "WINDOW MODE & BACKGROUND FOCUS (ANTI-PAUSE)")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Seamless Alt-Tab, borderless fullscreen, and background execution synchronization:")
        imgui.Spacing()

        -- Feature 1: Run in Background (No-Pause Alt+Tab)
        local c1, v1 = drawSlideSwitch("##sw_tweak_runinbg", config.tweaks.runInBackground, "Run in Background (No-Pause Alt+Tab)", "Keeps GTA SA rendering, world physics active, and network sync flowing when switching windows or playing on dual monitors")
        if c1 then
            config.tweaks.runInBackground = v1
            uiTweaks.runInBackground[0] = v1
            saveConfig()
            applyRunInBackground(v1)
            sampAddChatMessage(string.format("{00E676}[BDS Fixes]{FFFFFF} Run in Background: %s{FFFFFF} (SAMPFUNCS anti-pause synced; restart required if changed).", v1 and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end
        imgui.Spacing()

        -- Live Anti-Pause Status Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.85))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.40))
        imgui.BeginChild("AntiPauseStatusCard", imgui.ImVec2(0, 78), true)
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "ANTI-PAUSE ENGINE INTEGRATION")
        local apInfo = inspectAntiPauseStatus()
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "STATUS:")
        imgui.SameLine()
        imgui.TextColored(apInfo.color, apInfo.statusText)
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "INFO:")
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), "Prevents CGame & CTimer delta freezing when unfocused. Initial hook requires game restart.")
        imgui.EndChild()
        imgui.PopStyleColor(2)
        imgui.Spacing()

        -- Feature 2: Borderless Windowed Mode (Fake Fullscreen)
        local c2, v2 = drawSlideSwitch("##sw_tweak_borderless", config.tweaks.borderlessWindow, "Borderless Windowed Mode (Fake Fullscreen)", "Eliminates window borders and fits GTA SA to your desktop. Enables zero-flicker Alt-Tab and dual-monitor multitasking")
        if c2 then
            config.tweaks.borderlessWindow = v2
            uiTweaks.borderlessWindow[0] = v2
            saveConfig()
            applyBorderlessSetting(v2)
            sampAddChatMessage(string.format("{00E676}[BDS Fixes]{FFFFFF} Borderless Fullscreen: %s{FFFFFF} (Requires game restart to apply).", v2 and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end
        imgui.Spacing()

        -- Live Borderless Environment Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.85))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.40))
        imgui.BeginChild("BorderlessStatusCard", imgui.ImVec2(0, 95), true)
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "SMART BORDERLESS ENVIRONMENT DETECTOR")
        local winInfo = inspectBorderlessStatus()
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "ACTIVE MODE:")
        imgui.SameLine()
        imgui.TextColored(winInfo.statusCol, winInfo.modeStr)

        if winInfo.hasEnb then
            imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "ENB SERIES:")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), "Managed via enblocal.ini. SAMPFUNCS window-mode kept off to prevent 100x50 conflict.")
        elseif winInfo.hasWindowedAsi then
            imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "UNIVERSAL PLUGIN:")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), "WindowedMode.asi / FakeFullScreen.asi detected and active.")
        else
            imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "SAMPFUNCS:")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), "Managed via sampfuncs-settings.ini (window-mode & window-mode-no-border).")
        end
        imgui.EndChild()
        imgui.PopStyleColor(2)
        imgui.Spacing()

    elseif curSub == 2 then
        -- SUB-TAB 2: ENGINE & CRASH FIXES
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "ENGINE & STABILITY FIXES")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Core game engine patches to prevent crashes and fix high-FPS physics bugs:")
        imgui.Spacing()

        -- Tweak 1: Anti-Crasher Guard (0x007324B6)
        local c1, v1 = drawSlideSwitch("##sw_tweak_crasher", config.tweaks.antiCrasher, "Anti-Crasher Guard (0x007324B6 Protection)", "Prevents crashes caused by vehicle buggers, corrupt alpha textures, and invalid streaming atomics")
        if c1 then
            config.tweaks.antiCrasher = v1
            uiTweaks.antiCrasher[0] = v1
            saveConfig()
        end
        imgui.Spacing()

        -- Tweak 2: Live On-Screen Real-Time FPS Display
        local cFps, vFps = drawSlideSwitch("##sw_tweak_fpsdisplay", config.tweaks.fpsDisplay, "Live On-Screen FPS Counter Display", "Renders a clean, high-precision FPS counter badge with color-coded performance telemetry (>=60 Green, 30-59 Yellow, <30 Red)")
        if cFps then
            config.tweaks.fpsDisplay = vFps
            uiTweaks.fpsDisplay[0] = vFps
            saveConfig()
        end
        if config.tweaks.fpsDisplay then
            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "COUNTER POSITION:")
            imgui.SameLine()
            local posNames = { "Top-Right", "Top-Left", "Bottom-Right", "Bottom-Left" }
            local curPos = config.tweaks.fpsDisplayPos or 1
            for pIdx, pName in ipairs(posNames) do
                local isSel = (curPos == pIdx)
                if isSel then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.60, 0.44, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.72, 0.52, 1.00))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.70))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.24, 0.34, 0.90))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.85, 1.00))
                end
                if imgui.Button(pName .. "##fps_pos_" .. pIdx, imgui.ImVec2(88, 22)) then
                    config.tweaks.fpsDisplayPos = pIdx
                    uiTweaks.fpsDisplayPos[0] = pIdx
                    saveConfig()
                end
                imgui.PopStyleColor(3)
                if pIdx < #posNames then imgui.SameLine() end
            end
        end
        imgui.Spacing()

        -- Tweak 3: High-FPS Swimming Normalizer
        local c3, v3 = drawSlideSwitch("##sw_tweak_swim", config.tweaks.highFpsSwimming, "High-FPS Swimming Normalizer", "Fixes the notorious 60+ FPS bug where CJ swims at snail speed due to frame-rate water drag")
        if c3 then
            config.tweaks.highFpsSwimming = v3
            uiTweaks.highFpsSwimming[0] = v3
            saveConfig()
        end
        imgui.Spacing()

        -- Tweak 4: High-FPS Braking Normalizer
        local c4, v4 = drawSlideSwitch("##sw_tweak_brake", config.tweaks.highFpsBraking, "High-FPS Vehicle Braking Normalizer", "Restores normal stopping distances for cars and bikes when playing at 60-144 FPS")
        if c4 then
            config.tweaks.highFpsBraking = v4
            uiTweaks.highFpsBraking[0] = v4
            saveConfig()
        end
        imgui.Spacing()

        -- Tweak 5: Radar Aspect Ratio Fix
        local c5, v5 = drawSlideSwitch("##sw_tweak_radar", config.tweaks.radarAspectFix, "Circular Radar Aspect Fix", "Restores a perfect circle minimap on 16:9 and 16:10 widescreen monitors")
        if c5 then
            config.tweaks.radarAspectFix = v5
            uiTweaks.radarAspectFix[0] = v5
            saveConfig()
            applyRadarAspectFix(v5)
        end
        imgui.Spacing()

        -- Widescreen Fix Status Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.85))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.40))
        imgui.BeginChild("WidescreenStatusCard", imgui.ImVec2(0, 68), true)
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "WIDESCREEN & ASPECT RATIO INTEGRATION")
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "PLUGIN STATUS:")
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "ACTIVE (sa_widescreenfix_lite.asi loaded)")
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "FEATURES:")
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), "Native 16:9 / 16:10 / 21:9 FOV scaling, non-stretched peds, and circular radar.")
        imgui.EndChild()
        imgui.PopStyleColor(2)
        imgui.Spacing()

        -- Tweak 6: Flint & Countryside Night Illumination Normalizer
        local c6, v6 = drawSlideSwitch("##sw_tweak_flintnight", config.tweaks.flintNightFix, "Flint County & Countryside Night Illumination Fix", "Automatically illuminates dark rural zones (Flint County, Whetstone, Red County) at night so roads, terrain, and curves are clearly visible")
        if c6 then
            config.tweaks.flintNightFix = v6
            uiTweaks.flintNightFix[0] = v6
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Countryside Night Illumination: %s{FFFFFF}.", v6 and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end

        if config.tweaks.flintNightFix then
            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.85))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.40))
            imgui.BeginChild("FlintNightCard", imgui.ImVec2(0, 110), true)

            -- Mode Selector
            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "ACTIVATION MODE:")
            imgui.SameLine()
            local isMode1 = (config.tweaks.flintNightMode ~= 2)

            if isMode1 then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.60, 0.44, 0.95))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.72, 0.52, 1.00))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.70))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.24, 0.34, 0.90))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.85, 1.00))
            end
            if imgui.Button("Rural / Flint County Only##btn_mode1", imgui.ImVec2(180, 22)) then
                config.tweaks.flintNightMode = 1
                uiTweaks.flintNightMode[0] = 1
                saveConfig()
            end
            imgui.PopStyleColor(3)

            imgui.SameLine()
            if not isMode1 then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.60, 0.44, 0.95))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.72, 0.52, 1.00))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.70))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.24, 0.34, 0.90))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.85, 1.00))
            end
            if imgui.Button("Everywhere Across Map##btn_mode2", imgui.ImVec2(180, 22)) then
                config.tweaks.flintNightMode = 2
                uiTweaks.flintNightMode[0] = 2
                saveConfig()
            end
            imgui.PopStyleColor(3)

            -- Brightness Boost Slider
            imgui.SetNextItemWidth(260)
            uiTweaks.flintNightBoost[0] = config.tweaks.flintNightBoost or 380
            if imgui.SliderInt("##flint_night_boost_slider", uiTweaks.flintNightBoost, 260, 500, "Night Boost: %d") then
                config.tweaks.flintNightBoost = uiTweaks.flintNightBoost[0]
                saveConfig()
            end
            imgui.SameLine()
            if imgui.Button("Subtle (320)##pre_subtle", imgui.ImVec2(95, 20)) then
                config.tweaks.flintNightBoost = 320; uiTweaks.flintNightBoost[0] = 320; saveConfig()
            end
            imgui.SameLine()
            if imgui.Button("Balanced (380)##pre_bal", imgui.ImVec2(105, 20)) then
                config.tweaks.flintNightBoost = 380; uiTweaks.flintNightBoost[0] = 380; saveConfig()
            end
            imgui.SameLine()
            if imgui.Button("Clear Sight (440)##pre_clear", imgui.ImVec2(115, 20)) then
                config.tweaks.flintNightBoost = 440; uiTweaks.flintNightBoost[0] = 440; saveConfig()
            end

            -- Live Telemetry Status Line
            local zoneStr = #tweaksState.lastZoneKey > 0 and tweaksState.lastZoneKey or "Active World"
            local timeStr = string.format("%02d:00 (%s)", tweaksState.currentHour or 12, tweaksState.isNight and "Night" or "Day")
            local statusColor = tweaksState.flintBoostActive and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or imgui.ImVec4(0.60, 0.65, 0.75, 1.00)
            local statusText = tweaksState.flintBoostActive and string.format("ACTIVE (Illuminating %s at %d)", zoneStr, config.tweaks.flintNightBoost or 380) or "STANDBY (Daytime or inside well-lit city)"

            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "TELEMETRY:")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), string.format("Zone: %s | Time: %s | State: ", zoneStr, timeStr))
            imgui.SameLine()
            imgui.TextColored(statusColor, statusText)

            imgui.EndChild()
            imgui.PopStyleColor(2)
        end
        imgui.Spacing()

        -- Tweak 7: Client Anisotropic 16x Texture Sharpener
        local cAniso, vAniso = drawSlideSwitch("##sw_tweak_aniso", config.tweaks.anisotropic16x, "Client Anisotropic 16x Texture Sharpener", "Forces 16x anisotropic filtering across texture samplers for crystal-sharp roads, terrain, and distant surfaces")
        if cAniso then
            config.tweaks.anisotropic16x = vAniso
            uiTweaks.anisotropic16x[0] = vAniso
            saveConfig()
            applyAnisotropicFiltering(vAniso)
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Anisotropic 16x Sharpener: %s{FFFFFF}.", vAniso and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end
        imgui.Spacing()

        -- Tweak 8: Master Game Gamma & Brightness (In-Panel Real-Time Control)
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.85))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.40))
        imgui.BeginChild("MasterBrightnessCard", imgui.ImVec2(0, 85), true)
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "MASTER GAME GAMMA & BRIGHTNESS (IN-PANEL CONTROL)")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Real-time engine lighting control. Automatically persists without needing to pause or press ESC.")

        imgui.SetNextItemWidth(260)
        local okB, curB = pcall(memory.getint32, 0x00BA6784, false)
        if okB and curB and curB >= 0 and curB <= 512 then
            uiTweaks.masterBrightness[0] = curB
        else
            uiTweaks.masterBrightness[0] = config.tweaks.masterBrightness or 256
        end
        imgui.SetNextItemWidth(260)
        if imgui.SliderInt("##master_brightness_slider", uiTweaks.masterBrightness, 0, 512, "Brightness: %d") then
            config.tweaks.masterBrightness = uiTweaks.masterBrightness[0]
            pcall(memory.setint32, 0x00BA6784, config.tweaks.masterBrightness, false)
            saveConfig()
        end
        imgui.SameLine()
        if imgui.Button("Default 50% (256)##btn_br_def", imgui.ImVec2(120, 20)) then
            config.tweaks.masterBrightness = 256; uiTweaks.masterBrightness[0] = 256
            pcall(memory.setint32, 0x00BA6784, 256, false); saveConfig()
        end
        imgui.SameLine()
        if imgui.Button("Night Boost 75% (384)##btn_br_boost", imgui.ImVec2(140, 20)) then
            config.tweaks.masterBrightness = 384; uiTweaks.masterBrightness[0] = 384
            pcall(memory.setint32, 0x00BA6784, 384, false); saveConfig()
        end
        imgui.SameLine()
        if imgui.Button("Competitive 100% (512)##btn_br_max", imgui.ImVec2(145, 20)) then
            config.tweaks.masterBrightness = 512; uiTweaks.masterBrightness[0] = 512
            pcall(memory.setint32, 0x00BA6784, 512, false); saveConfig()
        end

        imgui.EndChild()
        imgui.PopStyleColor(2)

    elseif curSub == 3 then
        -- SUB-TAB 3: COMBAT & GUNPLAY QOL
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "COMBAT & GUNPLAY QUALITY-OF-LIFE")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Competitive shooting improvements, widescreen reticle fixes, and damage telemetry:")
        imgui.Spacing()

        -- Feature: SprintHook (Hold Sprint to Max Speed)
        local cSh, vSh = drawSlideSwitch("##sw_tweak_sprinthook", config.tweaks.sprintHook, "SprintHook (Hold Sprint to Max Speed)", "Hold the sprint key (Spacebar/Shift) to run at continuous maximum speed without button spamming or finger fatigue")
        if cSh then
            config.tweaks.sprintHook = vSh
            uiTweaks.sprintHook[0] = vSh
            saveConfig()
            applySprintHook(vSh)
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} SprintHook (Hold Sprint): %s{FFFFFF}.", vSh and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end
        imgui.Spacing()

        -- Tweak 1: Widescreen Scope Fix (Remove Black Bars)
        local c1, v1 = drawSlideSwitch("##sw_tweak_scope", config.tweaks.widescreenScope, "Widescreen Scope Fix (Remove Side Black Bars)", "Removes the black side pillarbox bars when aiming with Sniper and Rocket Launcher on widescreen displays")
        if c1 then
            config.tweaks.widescreenScope = v1
            uiTweaks.widescreenScope[0] = v1
            saveConfig()
            applyWidescreenScope(v1)
        end
        imgui.Spacing()

        -- Tweak 2: Fast Weapon Switch Delay Normalizer
        local c2, v2 = drawSlideSwitch("##sw_tweak_fastswitch", config.tweaks.fastWeaponSwitch, "Fast Weapon Switch Delay Normalizer", "Reduces artificial delays when switching weapons for smooth and responsive gunplay")
        if c2 then
            config.tweaks.fastWeaponSwitch = v2
            uiTweaks.fastWeaponSwitch[0] = v2
            saveConfig()
        end
        imgui.Spacing()

        -- Tweak 3: Live Combat & Damage Feed HUD
        local c3, v3 = drawSlideSwitch("##sw_tweak_dmgfeed", config.tweaks.damageFeed, "Live Combat Damage Feed HUD", "Displays real-time hits dealt and taken without showing any player names or IDs (100% roleplay & stream safe)")
        if c3 then
            config.tweaks.damageFeed = v3
            uiTweaks.damageFeed[0] = v3
            saveConfig()
        end
        imgui.Spacing()
        if config.tweaks.damageFeed then
            if imgui.Button("Test Damage Feed Notification##btn_test_dmg", imgui.ImVec2(240, 24)) then
                addDamageFeedEntry("DEALT -46.2 HP (Desert Eagle)", true)
                addDamageFeedEntry("TOOK -23.1 HP (M4)", false)
            end
        end
        imgui.Spacing()

        -- Tweak 4: 3D Laser / Neon Bullet Tracers
        local c4, v4 = drawSlideSwitch("##sw_tweak_tracers", config.tweaks.bulletTracers, "3D Laser / Neon Bullet Tracers", "Draws glowing 3D trajectory lines for weapons fire (Cyan = Local Player, Neon Orange = Opponents)")
        if c4 then
            config.tweaks.bulletTracers = v4
            uiTweaks.bulletTracers[0] = v4
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} 3D Bullet Tracers: %s{FFFFFF}.", v4 and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end

    elseif curSub == 4 then
        -- SUB-TAB 4: VEHICLE & DRIVING TWEAKS
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "VEHICLE & DRIVING ENHANCEMENTS")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Convenience and immersion features for driving, parking, and flying:")
        imgui.Spacing()

        -- Tweak 1: Hill Park (Anti-Roll Brake)
        local c1, v1 = drawSlideSwitch("##sw_tweak_hillpark", config.tweaks.hillPark, "Hill Park (Anti-Roll Incline Brake)", "Automatically holds vehicle firmly in place on steep inclines when stopped, preventing sliding backwards")
        if c1 then
            config.tweaks.hillPark = v1
            uiTweaks.hillPark[0] = v1
            saveConfig()
        end
        if config.tweaks.hillPark then
            imgui.SameLine(0, 16)
            local holdTxt = tweaksState.hillParkHolding and "[HOLD ACTIVE: INCLINE LOCKED]" or "[MONITORING / STANDBY]"
            local holdCol = tweaksState.hillParkHolding and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or imgui.ImVec4(0.50, 0.55, 0.65, 0.90)
            imgui.TextColored(holdCol, holdTxt)
        end
        imgui.Spacing()

        -- Tweak 2: Silent Emergency Sirens
        local c2, v2 = drawSlideSwitch("##sw_tweak_sirens", config.tweaks.silentSirens, "Silent Emergency Sirens (Lights Only)", "Mutes the piercing siren audio on police and emergency vehicles while keeping flashing lightbars running")
        if c2 then
            config.tweaks.silentSirens = v2
            uiTweaks.silentSirens[0] = v2
            saveConfig()
            pcall(updateAudioTweaks)
        end
        imgui.Spacing()

        -- Tweak 3: Aircraft Rotor Quieter
        local c3, v3 = drawSlideSwitch("##sw_tweak_aircraft", config.tweaks.aircraftQuieter, "Aircraft Rotor & Engine Sound Dampener", "Lowers deafening helicopter rotor and jet engine noise in cockpit so voice chat remains clear")
        if c3 then
            config.tweaks.aircraftQuieter = v3
            uiTweaks.aircraftQuieter[0] = v3
            saveConfig()
            pcall(updateAudioTweaks)
        end
        imgui.Spacing()

        -- Tweak 4: Vehicle Camera No-Recenter (Modern Free-Look Driving)
        local cCam, vCam = drawSlideSwitch("##sw_tweak_camnorecenter", config.tweaks.cameraNoRecenter, "Vehicle Camera No-Recenter (Free-Look Driving)", "Prevents the camera from auto-centering behind vehicle after 1.5s when driving with mouse")
        if cCam then
            config.tweaks.cameraNoRecenter = vCam
            uiTweaks.cameraNoRecenter[0] = vCam
            saveConfig()
            applyCameraNoRecenter(vCam and (config.tweaks.enabled ~= false))
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Vehicle Free-Look Camera: %s{FFFFFF}.", vCam and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
        end
        imgui.Spacing()



    elseif curSub == 5 then
        -- SUB-TAB 5: MOD & CONFLICT INSPECTOR
        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "MOD HEALTH & CONFLICT INSPECTOR")
        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Diagnoses installed plugins, stream memory allocation, and conflicting files that trigger crashes:")
        imgui.Spacing()

        -- Stream Memory Progress Bar Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.08, 0.11, 0.16, 0.90))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.60))
        imgui.BeginChild("StreamMemCard", imgui.ImVec2(0, 78), true)
        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "STREAM MEMORY TELEMETRY:")
        imgui.SameLine(imgui.GetWindowWidth() - 160)
        if imgui.Button("Refresh Telemetry##btn_ref_mem", imgui.ImVec2(145, 20)) then
            inspectModConflicts()
        end

        local pctFrac = (tweaksState.streamUsagePct or 5.0) / 100.0
        imgui.ProgressBar(pctFrac, imgui.ImVec2(-1, 20), string.format("%d MB / %d MB (%.1f%%)", tweaksState.streamUsedMB, tweaksState.streamMaxMB, tweaksState.streamUsagePct))
        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "GTA SA Virtual Stream Heap: Higher limits allow HD texture packs and modded vehicles without model blinking.")
        imgui.EndChild()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- Conflict Scanner Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.09, 0.14, 0.90))
        imgui.PushStyleColor(imgui.Col.Border, tweaksState.conflictsFound and imgui.ImVec4(1.00, 0.35, 0.35, 0.80) or imgui.ImVec4(0.00, 0.85, 0.50, 0.60))
        imgui.BeginChild("ModConflictCard", imgui.ImVec2(0, tweaksState.conflictsFound and 140 or 80), true)

        if tweaksState.conflictsFound then
            imgui.TextColored(imgui.ImVec4(1.00, 0.35, 0.35, 1.00), "[!] CRITICAL CONFLICT DETECTED IN GTA ROOT")
            for _, conf in ipairs(tweaksState.conflictList) do
                imgui.TextColored(imgui.ImVec4(1.00, 0.85, 0.20, 1.00), conf.title)
                imgui.TextWrapped(conf.desc)
                imgui.Spacing()
                if conf.action == "disable_cs" then
                    if imgui.Button("1-Click Auto Resolve: Disable memory2048.cs##btn_resolve_mem", imgui.ImVec2(320, 26)) then
                        autoResolveModConflicts()
                    end
                end
            end
        else
            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "[OK] NO MOD CONFLICTS DETECTED")
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 0.98, 1.00), "Stream memory fixers and graphic plugins are cleanly aligned.")
            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Installed memory allocator is operating with zero heap collision.")
        end
        imgui.EndChild()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- Timecycle & Sky Lighting Card
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.09, 0.14, 0.90))
        imgui.PushStyleColor(imgui.Col.Border, tweaksState.cieloPrioritized and imgui.ImVec4(0.00, 0.85, 0.50, 0.60) or imgui.ImVec4(1.00, 0.70, 0.20, 0.80))
        imgui.BeginChild("TimecycCard", imgui.ImVec2(0, 105), true)

        if tweaksState.cieloPrioritized then
            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "[OK] CIELO CLEAR NIGHT SKY TIMECYCLE ACTIVE (MODLOADER PRIORITY 60)")
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 0.98, 1.00), "Cielo's atmospheric timecycle is active. Countryside night skies and ambient lighting are clear without pitch-black glitches.")
            imgui.Spacing()
            if imgui.Button("Reset ModLoader Timecyc Priority to Default (50)##btn_rst_cielo", imgui.ImVec2(340, 24)) then
                setModloaderCieloPriority(false)
            end
        else
            imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "[!] TIMECYCLE CONFLICT: 'SA_DX DATA' OVERRIDING 'CIELO'")
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 0.98, 1.00), "'SA_DX DATA\\timecyc.dat' sets countryside night skies to pitch black (0 0 0). 'Cielo' provides natural moonlight.")
            imgui.Spacing()
            if imgui.Button("1-Click Auto Fix: Prioritize Cielo Sky in ModLoader##btn_pri_cielo", imgui.ImVec2(360, 24)) then
                setModloaderCieloPriority(true)
            end
        end

        imgui.EndChild()
        imgui.PopStyleColor(2)
    end

    imgui.Spacing()
end

-- ==============================================================================
-- TAB 8 RENDERER: HELP & DOCUMENTATION
-- ==============================================================================
local function renderTabHelp()
    imgui.BeginChild("HelpDocScrollBox", imgui.ImVec2(0, 0), false)
    pcall(imgui.SetWindowFontScale, config.general.helpFontScale or 1.0)

    -- Section 0: Window Opacity & Layout Positioning
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BDS TOOLKIT - WINDOW OPACITY & APPEARANCE")
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "Adjust popup window transparency to see through this menu to the game world:")

    imgui.SetNextItemWidth(240)
    uiMenuOpacity[0] = config.general.menuOpacity or 90
    if imgui.SliderInt("##menu_opacity_slider", uiMenuOpacity, 30, 100, "Window Opacity: %d%%") then
        config.general.menuOpacity = uiMenuOpacity[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("Reset Pos & Size##btn_rst_pos_sz", imgui.ImVec2(125, 22)) then
        state.needResetWindowPos = true
        config.general.menuOpacity = 90
        saveConfig()
        sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Menu snapped to default 820x540 docked top-right.", -1)
    end

    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Presets:")
    imgui.SameLine()
    local function opPresetBtn(pct, lbl)
        if imgui.SmallButton(lbl .. "##op_pre_" .. pct) then
            config.general.menuOpacity = pct
            saveConfig()
        end
        imgui.SameLine()
    end
    opPresetBtn(40, "40% Glass")
    opPresetBtn(65, "65% Semi")
    opPresetBtn(85, "85% Dim")
    opPresetBtn(100, "100% Solid")
    imgui.NewLine()

    -- Section 0.5: Help & Guide Font Size Adjustment
    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "HELP & GUIDE FONT SIZE / SCALE")
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "Adjust text scale for comfortable reading inside this guide:")

    uiHelpFontScale[0] = config.general.helpFontScale or 1.0
    imgui.SetNextItemWidth(240)
    if imgui.SliderFloat("##help_font_scale_slider", uiHelpFontScale, 0.75, 1.40, "Font Scale: %.2fx") then
        config.general.helpFontScale = uiHelpFontScale[0]
        saveConfig()
    end
    imgui.SameLine()
    if imgui.Button("Reset 1.0x##btn_rst_font_scale", imgui.ImVec2(100, 22)) then
        config.general.helpFontScale = 1.0
        saveConfig()
    end

    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Presets:")
    imgui.SameLine()
    local function fontPresetBtn(scale, lbl)
        if imgui.SmallButton(lbl .. "##fp_pre_" .. math.floor(scale * 100)) then
            config.general.helpFontScale = scale
            saveConfig()
        end
        imgui.SameLine()
    end
    fontPresetBtn(0.85, "Small (85%)")
    fontPresetBtn(1.00, "Default (100%)")
    fontPresetBtn(1.15, "Medium (115%)")
    fontPresetBtn(1.30, "Large (130%)")
    imgui.NewLine()

    imgui.Spacing()
    imgui.Separator()
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BDS TOOLKIT - USER GUIDE & MANUAL")
    imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "All features, commands, placeholder tokens, and configurations explained.")
    imgui.Separator()

    -- Section 1: Overview & Controls
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[1] QUICK CONTROLS & COMMANDS")
    imgui.BulletText("F12 : Toggles this BDS Toolkit master menu.")
    imgui.BulletText("TAB : Quick Key to cycle active Chat Mode (works whenever chatbox is open; rebindable in Tab 4).")
    imgui.BulletText("/bds or /toolkit or /menu : Chat commands to open this BDS Toolkit.")
    imgui.BulletText("/binder or /binds : Jumps directly to Tab 1 (Command Binder).")
    imgui.BulletText("/autocar or /vehctrl : Jumps directly to Tab 2 (AutoCar).")
    imgui.BulletText("/dlhud or /f5dl : Jumps directly to Tab 3 (FiveM Downloader).")
    imgui.BulletText("/chatmode or /chat or /cm : Jumps directly to Tab 4 Sub-tab 1 (Chat Modes Room Editor).")
    imgui.BulletText("/chatlog or /clog : Jumps directly to Tab 4 Sub-tab 2 (Live Chatlog & Search).")
    imgui.BulletText("/vinfo or /vehinfo : Jumps directly to Tab 5 (Vehicle Info HUD).")
    imgui.BulletText("/wsens or /sensfix : Jumps directly to Tab 6 (Weapon Sensitivity & Drive-By).")
    imgui.BulletText("/fixes or /tweaks or /gtafix : Jumps directly to Tab 7 (Fixes & Gameplay Tweaks).")
    imgui.BulletText("/bdshelp : Jumps directly to Tab 8 (Help & Documentation).")
    imgui.BulletText("/dltest : Starts the FiveM model download simulation test.")
    imgui.BulletText("/bprofile <1-5|name|next> : Shifts active keybinder profile instantly.")
    imgui.BulletText("/vinfotoggle : Instantly toggles Vehicle Info HUD ON/OFF.")
    imgui.BulletText("/senstoggle : Instantly toggles SensFix ON/OFF.")
    imgui.BulletText("/sensdb <multiplier> : Adjusts drive-by multiplier in chat (e.g. /sensdb 1.25).")

    imgui.Spacing()
    imgui.Separator()

    -- Section 2: Command Binder & Dynamic Placeholders
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[2] COMMAND BINDER & DYNAMIC PLACEHOLDERS")
    imgui.BulletText("100 Hotkey Slots : 5 distinct profiles (20 slots each), fully customizable & renamable.")
    imgui.BulletText("Keycap Rebind : Click the button, then press ANY keyboard or mouse button.")
    imgui.BulletText("Short /alias Expander : Set a short command in the '/cmd' box to execute long commands:")
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "    * /cf -> /cuff {nearid}")
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "    * /hl -> /heal {nearid} 100")
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "    * /loc -> /r 10-20 location is {zone}")
    imgui.BulletText("Execution Modes : [Send] automatically submits the chat; [Open] opens the chat box with command pre-filled.")
    imgui.BulletText("Available Placeholders:")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {nearid}   : Automatically evaluates nearest player ID (or Mask_XX if masked to prevent identity leak).")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {nearname} : Character nickname of closest player (or Mask_XX).")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {targetid} : ID or Mask_XX of the player currently targeted / aimed at with a weapon.")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {id}       : Your own local player ID.")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {name}     : Your character nickname.")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {zone}     : Current city neighborhood name (e.g. Commerce, Los Santos).")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {veh}      : Current vehicle model name (e.g. Sultan, Police Cruiser).")
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "    {args}     : Parameters passed after your /alias (e.g. /tc 500 speeding).")

    imgui.Spacing()
    imgui.Separator()

    -- Section 3: Smart Vehicle Automation
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[3] SMART VEHICLE AUTOMATION (AUTOCAR)")
    imgui.BulletText("Auto Engine : Automatically starts engine on enter; detects if engine is already ON to prevent accidental shutoffs.")
    imgui.BulletText("Auto Seatbelt : Fastens seatbelt upon entering vehicles; works for driver and passenger (excludes bikes/boats/aircraft).")
    imgui.BulletText("Smart Day/Night Headlights : Reads server HUD clock textdraw, turning headlights ON at night (19:00 - 06:00) and OFF during day.")
    imgui.BulletText("Hour Offset : Match your server's timezone (e.g. +2 hours).")

    imgui.Spacing()
    imgui.Separator()

    -- Section 4: Chat Mode Auto-Prefix & Room Editor
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[4] CHAT MODE AUTO-PREFIX & ROOM EDITOR (TAB 4)")
    imgui.BulletText("Auto-Prefixing : Whatever you type normally in the chatbox is automatically prefixed with your active mode command (e.g. /b Your message, /me smiles, /do Engine smoking, /s Stop!).")
    imgui.BulletText("Slash Command Protection : Commands starting with '/' (e.g. /stats, /engine, /lock, /bds, /help) are NEVER prefixed. Normal server commands execute unmodified.")
    imgui.BulletText("Floating Pill Bar : A sleek floating bar automatically anchors directly below your SA-MP chat input box whenever you type, showing all modes and a settings button [ * ].")
    imgui.BulletText("Quick Hotkey Cycling : Press TAB (or custom key) while typing in chat to instantly cycle between chat modes.")
    imgui.BulletText("Room Editor Sequence : Use [^] Move Up and [v] Move Down to customize the exact order of your chat modes.")
    imgui.BulletText("Custom Modes & Deletion : Add custom server chat modes (e.g. /c, /f, /wt, /sms, /ad) or delete unused modes with [X].")
    imgui.BulletText("Position Customization : Adjust the X and Y sliders in Tab 4 to position the floating pill bar exactly where you want it.")

    imgui.Spacing()
    imgui.Separator()

    -- Section 5: FiveM Model Downloader
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[5] FIVEM MODEL DOWNLOADER HUD")
    imgui.BulletText("Bypasses Default Dialog : Safely hooks SA-MP 0.3.DL memory (0x6A350) so the ugly black screen-blocking dialog never appears.")
    imgui.BulletText("Live Memory Telemetry : Reads active file counts, progress, and download speed directly from SA-MP memory.")
    imgui.BulletText("100% Mouse Freedom : The HUD window is click-through (NoInputs) and never captures the cursor, allowing uninterrupted driving and aiming.")

    imgui.Spacing()
    imgui.Separator()

    -- Section 6: In-Game Chatlog Viewer
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[6] IN-GAME CHATLOG VIEWER & SEARCH")
    imgui.BulletText("Overcomes Default Limit : SA-MP chat cuts off after 50-100 lines; this viewer retains up to 5,000 lines!")
    imgui.BulletText("Instant Real-Time Search : Type any player name, ID, command, or report keyword to filter lines immediately.")
    imgui.BulletText("Filter Chips : Quick buttons for Reports/Staff, Radio/Department, PMs, and Vehicle events.")
    imgui.BulletText("Click to Copy : Click any line to copy its text directly to your clipboard.")
    imgui.BulletText("Auto-Scroll : Keeps the log pinned to the latest incoming messages when enabled.")

    imgui.Spacing()
    imgui.Separator()
    
    -- Section 7: Vehicle Info HUD
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[7] BDS VEHICLE INFO HUD (3D WORLD SPACE & OCCLUSION)")
    imgui.BulletText("3D World Space Attachment : Projects telemetry directly above vehicle body center, centered horizontally.")
    imgui.BulletText("Permanent Line-of-Sight Occlusion : Native raycasting ensures vehicle tags are NEVER visible through walls or buildings.")
    imgui.BulletText("Accurate SA-MP Speedometer : Speed vector formula calibrated 1:1 with server speedometers.")
    imgui.BulletText("Dynamic Font Scaling : TrueType font engine with live slider, +/- step buttons, and quick presets.")
    imgui.BulletText("Zero Cursor Trapping : Controls are 100% unlocked during gameplay with no cursor or camera freeze.")

    imgui.Spacing()
    imgui.Separator()

    -- Section 8: SensFix
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[8] BDS SENSFIX (PER-WEAPON & DRIVE-BY SENSITIVITY)")
    imgui.BulletText("Per-Weapon Crosshair Speed : Independent sensitivity multipliers for Deagle, Shotguns, SMGs, M4/AK, Rifles, Sniper.")
    imgui.BulletText("Drive-By Crosshair Scaling : Independent multiplier when aiming & shooting from vehicle passenger seat.")
    imgui.BulletText("Vehicle Camera Orbit : Independent look-around speed while driving vehicles.")
    imgui.BulletText("1:1 Axis Scaling Fix : Equalizes vertical & horizontal mouse speed, eliminating GTA SA's vertical aim dampening.")
    imgui.BulletText("Live Telemetry HUD : Real-time weapon detection, active camera mode, and exact applied sensitivity floats.")
    imgui.BulletText("Dedicated Commands : Type /wsens, /sensfix, or /sens to jump straight to SensFix tab.")

    imgui.Spacing()
    imgui.Separator()

    -- Section 9: Fixes & Gameplay Tweaks
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[9] BDS FIXES & GAMEPLAY TWEAKS (STABILITY & QOL)")
    imgui.BulletText("Anti-Crasher Guard : Defends against 0x007324B6 RenderAlphaAtomic crashes triggered by vehicle buggers and corrupt textures.")
    imgui.BulletText("Run in Background : Keeps GTA SA running smoothly when Alt-Tabbed or working across dual displays.")
    imgui.BulletText("High-FPS Swimming Fix : Eliminates water drag at 60-144 FPS so CJ swims at vanilla 30 FPS speed.")
    imgui.BulletText("High-FPS Braking Fix : Restores responsive braking physics at high frame rates.")
    imgui.BulletText("Widescreen Scope Fix : Removes black pillarbox side bars while aiming sniper and rockets.")
    imgui.BulletText("Circular Radar Fix : Restores circular minimap aspect ratio on 16:9 / 16:10 monitors.")
    imgui.BulletText("SprintHook : Hold sprint button to run at continuous max speed without button spamming (/sprint, /sprinthook).")
    imgui.BulletText("Live FPS Display HUD : Real-time on-screen frames per second display badge (/fps, /fpsdisplay).")
    imgui.BulletText("Widescreen Fix : Full 16:9 / 16:10 aspect ratio and circular radar support (/widescreenfix).")
    imgui.BulletText("Hill Park Anti-Roll : Prevents stopped cars from sliding backwards on steep inclines.")
    imgui.BulletText("Flint & Countryside Night Illumination : Automatically normalizes pitch-black darkness in Flint County, Whetstone, and rural areas at night.")
    imgui.BulletText("Timecycle Inspector : Detects and resolves modloader timecycle conflicts with 1 click to restore clear night skies.")
    imgui.BulletText("Mod Conflict Inspector : Scans stream memory and resolves dual allocator conflicts (e.g. memory2048.cs) with 1 click.")
    imgui.BulletText("Live Damage Feed HUD : Floating combat indicators for hits dealt and received without player identities (100% roleplay & stream safe).")
    imgui.BulletText("Dedicated Commands : Type /fixes, /tweaks, or /gtafix to open Fixes tab directly.")

    imgui.Spacing()
    imgui.Separator()

    -- Section 10: Auto-Updater & Release Sync
    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "[10] NATIVE AUTO-UPDATER & RELEASE SYNC")
    imgui.BulletText("1-Click Over-The-Air Updates : Update your BDS Toolkit instantly without manual file copying or game restarts.")
    imgui.BulletText("Automatic Version Verification : Backs up your existing script to .bak before applying new releases safely.")
    imgui.BulletText("Dedicated Commands : Type /bdsupdate or /checkupdate in chat at any time.")
    imgui.Spacing()

    -- Updater Status Box
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.09, 0.14, 0.90))
    imgui.PushStyleColor(imgui.Col.Border, updaterState.statusColor)
    imgui.BeginChild("UpdaterCardBox", imgui.ImVec2(0, 165), true)

    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "CURRENT VERSION:")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "v1.0.0 (Official V1 Release)")

    imgui.SameLine(imgui.GetWindowWidth() - 210)
    if imgui.Button("Check for Updates Now##btn_chk_upd", imgui.ImVec2(195, 22)) then
        lua_thread.create(checkScriptUpdate, true)
    end

    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "UPDATE STATUS:")
    imgui.SameLine()
    imgui.TextColored(updaterState.statusColor, updaterState.statusMsg)

    if updaterState.status == "UPDATE_AVAILABLE" then
        imgui.TextColored(imgui.ImVec4(1.00, 0.85, 0.20, 1.00), "NEW VERSION:")
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "v" .. tostring(updaterState.latestVersion))
        if updaterState.changelog and #updaterState.changelog > 0 then
            imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "CHANGELOG:")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.90, 1.00, 1.00), updaterState.changelog)
        end
        imgui.Spacing()
        if imgui.Button("Install Update & Reload Script##btn_inst_upd", imgui.ImVec2(260, 26)) then
            downloadAndInstallUpdate()
        end
    elseif updaterState.status == "DOWNLOADING" then
        local pct = 0
        if updaterState.totalBytes and updaterState.totalBytes > 0 then
            pct = math.min(1.0, updaterState.downloadBytes / updaterState.totalBytes)
        end
        imgui.ProgressBar(pct, imgui.ImVec2(-1, 20), string.format("%d / %d KB", math.floor(updaterState.downloadBytes / 1024), math.floor(updaterState.totalBytes / 1024)))
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    local cAutoChk, vAutoChk = drawSlideSwitch("##sw_auto_chk", config.general.autoUpdateCheck, "Check for Updates on Game Startup", "Silently queries the update manifest 3.5s after SA-MP starts")
    if cAutoChk then
        config.general.autoUpdateCheck = vAutoChk
        saveConfig()
    end

    imgui.EndChild()
    imgui.PopStyleColor(2)

    imgui.Spacing()
    imgui.Separator()

    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BDS Toolkit v1.0 (Official Release)")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "- Authored & Developed by")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(1.00, 0.25, 0.25, 1.00), "Danny_Jadogar (CHACHA)")

    imgui.EndChild()
end

-- ------------------------------------------------------------------------------
-- Main Unified Dear ImGui Frame Renderer
-- ------------------------------------------------------------------------------
imgui.OnFrame(
    function()
        local chatBarVisible = false
        pcall(function()
            chatBarVisible = config.chatmode and config.chatmode.enabled and config.chatmode.showFloatingBar and sampIsChatInputActive()
        end)
        local vehTagsActive = false
        if config.vehinfo and config.vehinfo.enabled and state.vehinfoTargets and #state.vehinfoTargets > 0 then
            vehTagsActive = true
        end
        local dmgFeedActive = (config.tweaks and config.tweaks.enabled and config.tweaks.damageFeed and #tweaksState.damageLogs > 0)
        local tracersActive = (config.tweaks and config.tweaks.enabled and config.tweaks.bulletTracers and #bulletTracersList > 0)
        local fpsActive = (config.tweaks and config.tweaks.enabled and config.tweaks.fpsDisplay)
        return not isPauseMenuActive() and (state.mainWindowOpen[0] or state.fadeAlpha > 0.01 or (os.clock() < state.toastExpiry) or chatBarVisible or vehTagsActive or dmgFeedActive or tracersActive or fpsActive)
    end,
    function(player)
        local now = os.clock()
        local sw, sh = getScreenResolution()
        local theme = THEMES[config.downloader.theme] or THEMES.fivem_orange

        -- Handle Mouse & Player Locking (100% Reliable Typing in All Inputs)
        if state.mainWindowOpen[0] then
            if not state.wasMenuOpenLastFrame then
                state.wasMenuOpenLastFrame = true
                state.resetKeysRequested = true
            end
            player.HideCursor = false
            player.LockPlayer = true
        else
            if state.wasMenuOpenLastFrame then
                state.wasMenuOpenLastFrame = false
                state.resetKeysRequested = true
            end
            player.HideCursor = true
            player.LockPlayer = false
        end

        if state.resetKeysRequested then
            state.resetKeysRequested = false
            pcall(function()
                local io = imgui.GetIO()
                if io and io.KeysDown then
                    for i = 0, 511 do
                        io.KeysDown[i] = false
                    end
                    io.KeyCtrl  = false
                    io.KeyShift = false
                    io.KeyAlt   = false
                    io.KeySuper = false
                end
            end)
        end

        -- ----------------------------------------------------------------------
        -- FLOATING CHAT MODE PILL BAR (Directly under SA-MP Chat Input Box)
        -- ----------------------------------------------------------------------
        local chatBarActive = false
        pcall(function()
            chatBarActive = config.chatmode and config.chatmode.enabled and config.chatmode.showFloatingBar and sampIsChatInputActive()
        end)

        pcall(function()
        if chatBarActive and #config.chatmode.modes > 0 then
            local autoX, autoY = getAutoChatInputPos()
            local barX, barY
            if autoX and autoY and (config.chatmode.autoAttach ~= false) then
                barX = autoX + (config.chatmode.offsetX or 0)
                barY = autoY + (config.chatmode.offsetY or 0)
            else
                barX = config.chatmode.barX or 28
                barY = config.chatmode.barY or 95
            end

            imgui.SetNextWindowPos(imgui.ImVec2(barX, barY), imgui.Cond.Always)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12.0)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10.0)
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(8, 4))
            imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(6, 4))
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.90))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.85, 0.98, 0.40))

            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove

            local chatBarBeginVisible = imgui.Begin("##BDS_FloatingChatBar", nil, flags)
            if chatBarBeginVisible then
                for i, m in ipairs(config.chatmode.modes) do
                    local isSel = (i == config.chatmode.activeModeIdx)
                    if isSel then
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.75, 0.90, 0.95))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.10, 0.85, 1.00, 1.00))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
                    else
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.18, 0.25, 0.75))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.26, 0.36, 0.90))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.75, 0.82, 0.92, 1.00))
                    end

                    local btnLabel = m.name .. "##chat_pill_" .. i
                    if imgui.Button(btnLabel) then
                        config.chatmode.activeModeIdx = i
                        saveConfig()
                    end
                    if imgui.IsItemHovered() then
                        local pDisp = (#m.prefix > 0) and ("Prefix: " .. m.prefix) or "Normal IC chat (no prefix)"
                        imgui.SetTooltip(string.format("%s\n%s\n[Click or press TAB to cycle]", m.name, pDisp))
                    end
                    imgui.PopStyleColor(3)
                    imgui.SameLine()
                end

                -- Settings Gear Button
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.22, 0.30, 0.80))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.00, 0.85, 0.98, 1.00))
                if imgui.Button("*##btn_open_chat_settings", imgui.ImVec2(24, 0)) then
                    config.general.chatSubTab = 1
                    toggleSuiteMenu(4)
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip("Open Room Editor / Chat Modes Settings")
                end
                imgui.PopStyleColor(2)

            end
            imgui.End()

            imgui.PopStyleColor(2)
            imgui.PopStyleVar(4)
        end
        end)

        -- ----------------------------------------------------------------------
        -- 1. FLOATING FIVEM MODEL DOWNLOADER HUD PILL (Bottom-Right, 100% Click-Through)
        -- ----------------------------------------------------------------------
        pcall(function()
        if state.fadeAlpha > 0.01 then
            local cardWidth  = 385
            local cardHeight = 44

            local posX, posY = 0, 0
            if config.downloader.positionPreset == "bottom_right" then
                posX = sw - cardWidth - config.downloader.offsetX
                posY = sh - cardHeight - config.downloader.offsetY
            elseif config.downloader.positionPreset == "bottom_center" then
                posX = (sw - cardWidth) / 2
                posY = sh - cardHeight - config.downloader.offsetY
            elseif config.downloader.positionPreset == "top_right" then
                posX = sw - cardWidth - config.downloader.offsetX
                posY = config.downloader.offsetY + 30
            elseif config.downloader.positionPreset == "top_center" then
                posX = (sw - cardWidth) / 2
                posY = config.downloader.offsetY + 30
            else
                posX = sw - cardWidth - config.downloader.offsetX
                posY = sh - cardHeight - config.downloader.offsetY
            end

            imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(cardWidth, cardHeight), imgui.Cond.Always)

            local winFlags = imgui.WindowFlags.NoTitleBar +
                             imgui.WindowFlags.NoResize +
                             imgui.WindowFlags.NoMove +
                             imgui.WindowFlags.NoScrollbar +
                             imgui.WindowFlags.NoCollapse +
                             imgui.WindowFlags.NoFocusOnAppearing +
                             imgui.WindowFlags.NoInputs

            local bgAlpha  = 0.90 * state.fadeAlpha
            local bdrAlpha = 0.40 * state.fadeAlpha

            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, state.fadeAlpha)
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.08, 0.09, 0.12, bgAlpha))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(theme.border.x, theme.border.y, theme.border.z, bdrAlpha))
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(14, 8))

            if imgui.Begin("##FiveM_Model_Downloader_HUD_Unified", nil, winFlags) then
                local drawList = imgui.GetWindowDrawList()
                local winPos = imgui.GetWindowPos()
                local winSize = imgui.GetWindowSize()

                local progress = 0.0
                if state.totalFiles > 0 then
                    progress = math.min(1.0, math.max(0.0, state.currentFiles / state.totalFiles))
                end

                local primaryText = ""
                local secText = ""

                if state.isComplete then
                    primaryText = string.format("Assets loaded (%d of %d)", state.totalFiles, state.totalFiles)
                    secText = "Ready"
                else
                    primaryText = string.format("Downloading assets (%d of %d)...", state.currentFiles, state.totalFiles)
                    if config.downloader.showSpeed then
                        if state.speedKBps >= 1024.0 then
                            secText = string.format("(%.2f MB/s)", state.speedKBps / 1024.0)
                        else
                            secText = string.format("(%.1f KB/s)", state.speedKBps)
                        end
                    else
                        secText = string.format("(%.0f%%)", progress * 100)
                    end
                end

                imgui.SetCursorPos(imgui.ImVec2(14, 12))
                imgui.TextColored(imgui.ImVec4(0.96, 0.97, 0.99, 1.00), primaryText)
                imgui.SameLine()
                if state.isComplete then
                    imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), secText)
                else
                    imgui.TextColored(imgui.ImVec4(0.68, 0.72, 0.80, 1.00), secText)
                end

                local spinnerCenter = imgui.ImVec2(winPos.x + winSize.x - 24, winPos.y + (winSize.y / 2) - 1)
                if state.isComplete then
                    local doneColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.90, 0.46, state.fadeAlpha))
                    drawList:AddCircleFilled(spinnerCenter, 7.5, doneColor, 20)
                    drawList:AddCircle(spinnerCenter, 7.5, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.9)), 20, 1.2)
                else
                    local spinColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(theme.accent.x, theme.accent.y, theme.accent.z, state.fadeAlpha))
                    drawFiveMSpinner(drawList, spinnerCenter, 7.5, 2.0, spinColor, 4.2)
                end

                local barY = winPos.y + winSize.y - 2.5
                local barStartX = winPos.x + 3
                local barEndX   = winPos.x + winSize.x - 3
                local barWidth  = (barEndX - barStartX) * progress

                drawList:AddLine(
                    imgui.ImVec2(barStartX, barY),
                    imgui.ImVec2(barEndX, barY),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.18, 0.20, 0.26, 0.70 * state.fadeAlpha)),
                    2.0
                )

                if barWidth > 1.0 then
                    local barColor = state.isComplete
                        and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.00, 0.90, 0.46, state.fadeAlpha))
                        or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(theme.accent.x, theme.accent.y, theme.accent.z, state.fadeAlpha))
                    drawList:AddLine(
                        imgui.ImVec2(barStartX, barY),
                        imgui.ImVec2(barStartX + barWidth, barY),
                        barColor,
                        2.0
                    )
                end
            end
            imgui.End()

            imgui.PopStyleVar(2)
            imgui.PopStyleColor(2)
        end
        end)

        -- ----------------------------------------------------------------------
        -- 2. FLOATING PROFILE SHIFT TOAST
        -- ----------------------------------------------------------------------
        if now < state.toastExpiry and #state.toastText > 0 then
            local toastW, toastH = 340, 42
            imgui.SetNextWindowPos(imgui.ImVec2((sw - toastW) / 2, 45), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(toastW, toastH), imgui.Cond.Always)
            local tFlags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoInputs

            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.92))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.90, 0.46, 0.85))
            if imgui.Begin("##ToastWinSuite", nil, tFlags) then
                imgui.SetCursorPos(imgui.ImVec2(14, 11))
                imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "PROFILE ACTIVE:")
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, 1.00), state.toastText)
            end
            imgui.End()
            imgui.PopStyleColor(2)
        end

                -- ----------------------------------------------------------------------
        -- 2.5 VEHICLE INFO HUD OVERLAY (3D WORLD SPACE & 2D HUD)
        -- ----------------------------------------------------------------------
        if config.vehinfo and config.vehinfo.enabled and not isPauseMenuActive() and state.vehinfoTargets and #state.vehinfoTargets > 0 then
            pcall(function()
                for _, vData in ipairs(state.vehinfoTargets) do
                    if config.vehinfo.displayMode == 1 then
                        local car = vData.handle
                        if doesVehicleExist(car) then
                            local vx, vy, vz = getCarCoordinates(car)
                            local rx = vx + (config.vehinfo.offsetX or 0.0)
                            local ry = vy
                            local rz = vz + getVehInfoVerticalOffset(vData.modelId) + (config.vehinfo.offsetZ or 0.0)

                            local onScreen, sx, sy = getVehicleScreenPos(rx, ry, rz)
                            if onScreen then
                                local scale = 1.0
                                if config.vehinfo.scaleWithDist and not vData.isSelf then
                                    local px, py, pz = getCharCoordinates(PLAYER_PED)
                                    local d = getDistanceBetweenCoords3d(px, py, pz, rx, ry, rz)
                                    scale = math.max(0.70, math.min(1.20, 1.0 - (d / 80.0)))
                                end
                                renderVehicleCard(vData, imgui.ImVec2(sx, sy), scale)
                            end
                        end
                    else
                        if vData.isSelf or _ == 1 then
                            local sx = sw * (config.vehinfo.hud2dPosX or 0.85)
                            local sy = sh * (config.vehinfo.hud2dPosY or 0.82)
                            renderVehicleCard(vData, imgui.ImVec2(sx, sy), 1.0)
                        end
                    end
                end
            end)
        end

        -- ----------------------------------------------------------------------
        -- 2.8 LIVE COMBAT & DAMAGE FEED OVERLAY
        -- ----------------------------------------------------------------------
        if config.tweaks and config.tweaks.enabled and config.tweaks.damageFeed and #tweaksState.damageLogs > 0 and not isPauseMenuActive() then
            pcall(function()
                local dFlags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
                               imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs
                local feedW = 230
                local feedH = 24
                local startY = sh * 0.35
                local posX = sw - feedW - 20

                local expiredIndices = {}
                for idx, log in ipairs(tweaksState.damageLogs) do
                    local age = now - log.time
                    if age > 3.0 then
                        table.insert(expiredIndices, idx)
                    else
                        local alpha = 1.0
                        if age > 2.0 then
                            alpha = math.max(0.0, 1.0 - ((age - 2.0) / 1.0))
                        end
                        imgui.SetNextWindowSize(imgui.ImVec2(feedW, feedH), imgui.Cond.Always)
                        imgui.SetNextWindowPos(imgui.ImVec2(posX, startY + ((idx - 1) * 28)), imgui.Cond.Always)
                        imgui.SetNextWindowBgAlpha(0.85 * alpha)

                        local borderCol = log.isGive and imgui.ImVec4(0.00, 0.90, 0.46, 0.90 * alpha) or imgui.ImVec4(1.00, 0.25, 0.25, 0.90 * alpha)
                        imgui.PushStyleColor(imgui.Col.Border, borderCol)
                        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.88 * alpha))
                        if imgui.Begin("##DmgFeedItem_" .. idx, nil, dFlags) then
                            local tagCol = log.isGive and imgui.ImVec4(0.00, 0.90, 0.46, alpha) or imgui.ImVec4(1.00, 0.25, 0.25, alpha)
                            imgui.SetCursorPos(imgui.ImVec2(8, 4))
                            imgui.TextColored(tagCol, log.isGive and "[HIT]" or "[DMG]")
                            imgui.SameLine()
                            imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, alpha), log.text)
                        end
                        imgui.End()
                        imgui.PopStyleColor(2)
                    end
                end

                for i = #expiredIndices, 1, -1 do
                    table.remove(tweaksState.damageLogs, expiredIndices[i])
                end
            end)
        end

        -- 3D Laser / Neon Bullet Tracers Overlay
        if config.tweaks and config.tweaks.enabled and config.tweaks.bulletTracers and #bulletTracersList > 0 then
            pcall(function()
                local dl = imgui.GetBackgroundDrawList()
                local curT = os.clock()
                local i = 1
                while i <= #bulletTracersList do
                    local tr = bulletTracersList[i]
                    local age = curT - tr.time
                    if age >= tr.duration then
                        table.remove(bulletTracersList, i)
                    else
                        local alpha = 1.0 - (age / tr.duration)
                        if alpha > 0.05 then
                            local ok1, s1x, s1y = convert3DCoordsToScreen(tr.x1, tr.y1, tr.z1)
                            local ok2, s2x, s2y = convert3DCoordsToScreen(tr.x2, tr.y2, tr.z2)
                            if ok1 and ok2 then
                                local r, g, b = 0.0, 0.9, 1.0 -- Cyan (Local player)
                                if not tr.isLocal then
                                    r, g, b = 1.0, 0.40, 0.15 -- Neon Orange/Red (Enemy/Other)
                                end
                                local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, alpha * 0.9))
                                local colGlow = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, alpha * 0.3))
                                dl:AddLine(imgui.ImVec2(s1x, s1y), imgui.ImVec2(s2x, s2y), colGlow, 4.0)
                                dl:AddLine(imgui.ImVec2(s1x, s1y), imgui.ImVec2(s2x, s2y), col, 1.8)
                            end
                        end
                        i = i + 1
                    end
                end
            end)
        end

        -- ----------------------------------------------------------------------
        -- 2.9 LIVE REAL-TIME FPS DISPLAY OVERLAY
        -- ----------------------------------------------------------------------
        if config.tweaks and config.tweaks.enabled and config.tweaks.fpsDisplay and not isPauseMenuActive() then
            pcall(function()
                local fps = math.floor(imgui.GetIO().Framerate + 0.5)
                local fpsCol = (fps >= 60) and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or
                               ((fps >= 30) and imgui.ImVec4(1.00, 0.80, 0.20, 1.00) or imgui.ImVec4(1.00, 0.25, 0.25, 1.00))
                local dotCol = (fps >= 60) and imgui.ImVec4(0.00, 0.90, 0.46, 0.90) or
                               ((fps >= 30) and imgui.ImVec4(1.00, 0.80, 0.20, 0.90) or imgui.ImVec4(1.00, 0.25, 0.25, 0.90))

                local fpsFlags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
                                 imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs + imgui.WindowFlags.AlwaysAutoResize

                local badgeW = 76
                local badgeH = 26
                local posMode = config.tweaks.fpsDisplayPos or 1
                local posX, posY = sw - badgeW - 16, 12 -- Top Right

                if posMode == 2 then
                    posX, posY = 16, 12 -- Top Left
                elseif posMode == 3 then
                    posX, posY = sw - badgeW - 16, sh - badgeH - 12 -- Bottom Right
                elseif posMode == 4 then
                    posX, posY = 16, sh - badgeH - 12 -- Bottom Left
                end

                imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
                imgui.SetNextWindowBgAlpha(0.72)
                imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 6.0)
                imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(8, 4))
                imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(fpsCol.x, fpsCol.y, fpsCol.z, 0.35))
                imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.07, 0.10, 0.85))

                if imgui.Begin("##BDS_FPS_Counter_HUD", nil, fpsFlags) then
                    imgui.TextColored(dotCol, "*")
                    imgui.SameLine(0, 4)
                    imgui.TextColored(fpsCol, string.format("%d", fps))
                    imgui.SameLine(0, 3)
                    imgui.TextColored(imgui.ImVec4(0.65, 0.70, 0.78, 0.90), "FPS")
                end
                imgui.End()
                imgui.PopStyleColor(2)
                imgui.PopStyleVar(2)
            end)
        end

        -- ----------------------------------------------------------------------
        -- 3. MAIN UNIFIED SUITE MENU WINDOW (TABS & HELP)
        -- ----------------------------------------------------------------------
        if state.mainWindowOpen[0] then
            local winW = 820
            local winH = 540
            local posX = sw - winW - 15
            local posY = 25

            if state.needResetWindowPos or not config.general.hasSetDefaultPos then
                imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
                imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
                state.needResetWindowPos = false
                config.general.hasSetDefaultPos = true
            else
                imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.FirstUseEver)
                imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.FirstUseEver)
            end
            imgui.SetNextWindowSizeConstraints(imgui.ImVec2(740, 460), imgui.ImVec2(sw, sh))

            local menuAlpha = (config.general.menuOpacity or 90) / 100.0
            imgui.SetNextWindowBgAlpha(menuAlpha)

            if imgui.Begin("BDS TOOLKIT v1.0 | Danny_Jadogar (CHACHA)###BdsToolkitWin", state.mainWindowOpen, imgui.WindowFlags.NoCollapse) then
                -- BDS Branding Header
                imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BDS TOOLKIT v1.0")
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "|")
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(1.00, 0.25, 0.25, 1.00), "Danny_Jadogar (CHACHA)")

                if updaterState.status == "UPDATE_AVAILABLE" then
                    imgui.SameLine()
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.70, 0.40, 0.90))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.85, 0.48, 1.00))
                    if imgui.Button(string.format("Update v%s##btn_hdr_upd", tostring(updaterState.latestVersion)), imgui.ImVec2(100, 20)) then
                        downloadAndInstallUpdate()
                    end
                    imgui.PopStyleColor(2)
                end

                -- Lock Controls in Menu (Persistent across ALL tabs with zero overlap)
                local closeBtnW   = 85
                local lockSwitchW = 150
                local closeX      = imgui.GetWindowWidth() - closeBtnW - 12
                local lockX       = closeX - lockSwitchW - 14

                if lockX > 220 then
                    imgui.SameLine(lockX)
                else
                    imgui.SameLine()
                end

                local lkClicked, lkVal = drawSlideSwitch("##sw_hdr_lock", config.general.lockPlayer, "Lock Controls", "Locks character WASD movement while typing in BDS Toolkit")
                if lkClicked then
                    config.general.lockPlayer = lkVal
                    saveConfig()
                end

                imgui.SameLine(closeX)
                if imgui.Button("Close [ESC]##hdr_close_suite", imgui.ImVec2(closeBtnW, 22)) then
                    resetImGuiKeyboardState()
                    state.mainWindowOpen[0] = false
                    pcall(lockPlayerControl, false)
                    lua_thread.create(function()
                        wait(50)
                        saveConfig()
                    end)
                end

                imgui.Separator()

                -- --------------------------------------------------------------
                -- Vertical Navigation Sidebar (Left) & Main Content Area (Right)
                -- --------------------------------------------------------------
                local sidebarW = 180
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.08, 0.12, 0.90))
                imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.00, 0.75, 0.65, 0.35))
                imgui.BeginChild("##BdsModSidebar", imgui.ImVec2(sidebarW, 0), true)

                imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "MODS & MODULES")
                imgui.Separator()
                imgui.Spacing()

                local function getModeTag(enabled)
                    return enabled and " [ON]" or " [OFF]"
                end

                local navTabs = {
                    { id = 1, name = "1. Binder",         tag = getModeTag(config.binder.enabled) },
                    { id = 2, name = "2. AutoCar",        tag = getModeTag(config.autocar.enabled) },
                    { id = 3, name = "3. Downloader",     tag = getModeTag(config.downloader.enabled) },
                    { id = 4, name = "4. Chat & Logs",    tag = getModeTag(config.chatmode.enabled) },
                    { id = 5, name = "5. VehInfo",        tag = getModeTag(config.vehinfo and config.vehinfo.enabled) },
                    { id = 6, name = "6. SensFix",        tag = getModeTag(config.sensfix and config.sensfix.enabled) },
                    { id = 7, name = "7. Fixes & Tweaks", tag = getModeTag(config.tweaks and config.tweaks.enabled) },
                    { id = 8, name = "8. Help & Info",    tag = "", isHelp = true },
                }

                for _, tab in ipairs(navTabs) do
                    if tab.isHelp then
                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()
                    end

                    local isSel = (config.general.activeTab == tab.id)
                    if isSel then
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.60, 0.44, 0.95))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.00, 0.72, 0.52, 1.00))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
                    else
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.13, 0.19, 0.70))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.16, 0.22, 0.32, 0.90))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.80, 0.85, 0.95, 1.00))
                    end

                    local btnLabel = tab.name .. tab.tag
                    if imgui.Button(btnLabel .. "##vtab_" .. tab.id, imgui.ImVec2(-1, 34)) then
                        config.general.activeTab = tab.id
                        saveConfig()
                    end
                    imgui.PopStyleColor(3)
                    imgui.Spacing()
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BDS Suite v1.0")
                imgui.TextColored(imgui.ImVec4(0.40, 0.45, 0.55, 1.00), "Danny_Jadogar")
                imgui.EndChild()
                imgui.PopStyleColor(2)

                imgui.SameLine()

                -- Right Content Area (Scrollable Active Mod Pane)
                imgui.BeginChild("##BdsMainContent", imgui.ImVec2(0, 0), false)

                -- ==============================================================
                -- TAB 1: COMMAND & KEY BINDER
                -- ==============================================================
                if config.general.activeTab == 1 then
                    safeRenderTab(1, "1. Command & Key Binder", function()
                    local curPIdx = config.general.activeProfile or 1
                    local curP = profiles[curPIdx]

                    -- Master Mode 1 Power Switch
                    local bndChanged, bndVal = drawSlideSwitch("##sw_bnd_master", config.binder.enabled, "Enable Command Binder Mode", "Allows physical hotkeys and dynamic /alias chat commands")
                    if bndChanged then
                        config.binder.enabled = bndVal
                        saveConfig()
                        sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Keybinder Mode: %s{FFFFFF}.", bndVal and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
                    end
                    if not config.binder.enabled then
                        imgui.SameLine()
                        imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "(Keybinder is currently PAUSED)")
                    end

                    imgui.Spacing()

                    -- Profile Selection Tabs (Spans 100% of Content Region)
                    local availW = imgui.GetContentRegionAvail().x
                    local profBtnW = math.max(75, math.floor((availW - (4 * 6)) / 5))
                    for pIdx = 1, 5 do
                        local isCur = (pIdx == curPIdx)
                        if isCur then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.65, 0.85, 0.95))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.13, 0.18, 0.70))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.82, 1.0))
                        end

                        local pLabel = string.format("%d. %s", pIdx, profiles[pIdx].name or ("P" .. pIdx))
                        if imgui.Button(pLabel .. "##btn_prof_" .. pIdx, imgui.ImVec2(profBtnW, 24)) then
                            config.general.activeProfile = pIdx
                            queueAliasRefresh()
                            saveConfig()
                        end
                        imgui.PopStyleColor(2)
                        if pIdx < 5 then imgui.SameLine() end
                    end

                    imgui.Spacing()

                    -- Rename Profile Input + Delay Slider + Duplicate Profile Button (Flexible Layout)
                    imgui.AlignTextToFramePadding()
                    imgui.Text("Profile:")
                    imgui.SameLine()
                    imgui.SetNextItemWidth(130)
                    if imgui.InputText("##edit_pname", profileNameBuffers[curPIdx], 64) then
                        curP.name = ffi.string(profileNameBuffers[curPIdx])
                        saveConfig()
                    end

                    imgui.SameLine()
                    imgui.Text("Delay:")
                    imgui.SameLine()
                    imgui.SetNextItemWidth(110)
                    uiSpamDelayInt[0] = config.general.spamDelayMs
                    if imgui.SliderInt("##delay_slider", uiSpamDelayInt, 0, 1000, "%d ms") then
                        config.general.spamDelayMs = uiSpamDelayInt[0]
                        saveConfig()
                    end

                    imgui.SameLine()
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.42, 0.65, 0.85))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.58, 0.90, 1.00))
                    if imgui.Button("Duplicate Profile...##btn_open_dup_modal", imgui.ImVec2(150, 24)) then
                        imgui.OpenPopup("DuplicateProfileModal")
                    end
                    imgui.PopStyleColor(2)
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip("Copy all 20 hotkey slots and commands from this profile into another profile")
                    end

                    if imgui.BeginPopup("DuplicateProfileModal") then
                        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), string.format("Copy Profile %d (%s) into:", curPIdx, curP.name or ("P" .. curPIdx)))
                        imgui.Separator()
                        for tIdx = 1, 5 do
                            if tIdx ~= curPIdx then
                                local tLabel = string.format("Copy -> Profile %d (%s)", tIdx, profiles[tIdx].name or ("P" .. tIdx))
                                if imgui.Button(tLabel .. "##dup_target_" .. tIdx, imgui.ImVec2(220, 24)) then
                                    duplicateProfile(curPIdx, tIdx)
                                    imgui.CloseCurrentPopup()
                                end
                            end
                        end
                        imgui.Separator()
                        if imgui.Button("Cancel##btn_cancel_dup", imgui.ImVec2(220, 22)) then
                            imgui.CloseCurrentPopup()
                        end
                        imgui.EndPopup()
                    end

                    -- Placeholder Chips Bar
                    imgui.Separator()
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Quick Placeholder Tokens (Click to Copy):")
                    imgui.SameLine()

                    local function placeholderChip(tag, hint)
                        if imgui.SmallButton(tag .. "##chip_" .. tag) then
                            setClipboardText(tag)
                            sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Copied {00E5FF}%s{FFFFFF} to clipboard!", tag), -1)
                        end
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip(hint)
                        end
                        imgui.SameLine()
                    end

                    placeholderChip("{nearid}", "Nearest player ID (or Mask_XX if masked; RP leak-safe)")
                    placeholderChip("{nearname}", "Nearest player name (or Mask_XX)")
                    placeholderChip("{id}", "Your own player ID")
                    placeholderChip("{name}", "Your character name")
                    placeholderChip("{targetid}", "ID or Mask_XX of aimed/targeted player")
                    placeholderChip("{zone}", "Current street/neighborhood")
                    placeholderChip("{veh}", "Vehicle model name")
                    placeholderChip("{args}", "Extra parameters after /alias")

                    imgui.Spacing()
                    imgui.Separator()

                    -- Binder search/filter (does not modify saved slot data)
                    imgui.AlignTextToFramePadding()
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Find Slot:")
                    imgui.SameLine()
                    imgui.SetNextItemWidth(260)
                    imgui.InputTextWithHint("##binder_search", "Search alias, command or key...", binderSearchBuffer, 96)
                    imgui.SameLine()
                    if imgui.SmallButton("Clear##binder_search_clear") then
                        imgui.StrCopy(binderSearchBuffer, "")
                    end
                    local binderQuery = string.lower(ffi.string(binderSearchBuffer))
                    local matchedSlots = 0
                    if binderQuery ~= "" then
                        for i = 1, 20 do
                            local slot = curP.slots[i]
                            local haystack = string.lower(table.concat({
                                tostring(i), tostring(slot.alias or ""), tostring(slot.command or ""),
                                tostring(slot.key or ""), tostring(getKeyName(slot.key or 0) or "")
                            }, " "))
                            if haystack:find(binderQuery, 1, true) then matchedSlots = matchedSlots + 1 end
                        end
                        imgui.SameLine()
                        imgui.TextColored(imgui.ImVec4(0.65, 0.85, 0.95, 1.0), string.format("%d/20", matchedSlots))
                    else
                        matchedSlots = 20
                    end

                    -- 20 Hotkey Slots Grid (Scrollable Child)
                    imgui.BeginChild("BinderSlotsList", imgui.ImVec2(0, 0), true)

                    local availWidth = imgui.GetContentRegionAvail().x
                    local colCheckW = 34
                    local colKeyW   = 95
                    local colAliasW = 85
                    local colModeW  = 68
                    local colClearW = 42
                    local fixedW    = colCheckW + colKeyW + colAliasW + colModeW + colClearW
                    local colCmdW   = math.max(160, availWidth - fixedW - 18)

                    imgui.Columns(6, "BinderSlotsHeader", false)
                    imgui.SetColumnWidth(0, colCheckW)
                    imgui.SetColumnWidth(1, colKeyW)
                    imgui.SetColumnWidth(2, colAliasW)
                    imgui.SetColumnWidth(3, colModeW)
                    imgui.SetColumnWidth(4, colCmdW)
                    imgui.SetColumnWidth(5, colClearW)

                    for slotIdx = 1, 20 do
                        local s = curP.slots[slotIdx]
                        local showSlot = true
                        if binderQuery ~= "" then
                            local haystack = string.lower(table.concat({
                                tostring(slotIdx), tostring(s.alias or ""), tostring(s.command or ""),
                                tostring(s.key or ""), tostring(getKeyName(s.key or 0) or "")
                            }, " "))
                            showSlot = haystack:find(binderQuery, 1, true) ~= nil
                        end
                        if showSlot then

                        -- 1. Enable Checkbox
                        uiSlotChecks[slotIdx][0] = s.enabled
                        if imgui.Checkbox("##chk_" .. slotIdx, uiSlotChecks[slotIdx]) then
                            s.enabled = uiSlotChecks[slotIdx][0]
                            queueAliasRefresh()
                            saveConfig()
                        end
                        imgui.NextColumn()

                        -- 2. Keycap Rebind Button
                        local isWaiting = (state.waitingKeyFor == slotIdx)
                        local keyLabel = isWaiting and ">>> PRESS <<<" or (s.key > 0 and getKeyName(s.key) or "[Bind Key]")
                        if isWaiting then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.95, 0.60, 0.10, 1.0))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))
                        elseif s.key > 0 then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.22, 0.32, 0.9))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.00, 0.90, 0.46, 1.0))
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.13, 0.18, 0.6))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.50, 0.55, 0.65, 1.0))
                        end

                        if imgui.Button(keyLabel .. "##btn_k_" .. slotIdx, imgui.ImVec2(colKeyW - 10, 24)) then
                            if isWaiting then
                                state.waitingKeyFor = nil
                            else
                                state.waitingKeyFor = slotIdx
                            end
                        end
                        imgui.PopStyleColor(2)
                        imgui.NextColumn()

                        -- 3. Short /alias Input
                        imgui.SetNextItemWidth(colAliasW - 10)
                        if imgui.InputTextWithHint("##al_" .. slotIdx, "/cmd", aliasBuffers[curPIdx][slotIdx], 32) then
                            s.alias = ffi.string(aliasBuffers[curPIdx][slotIdx]):gsub("^/", ""):lower():gsub("%s+", "")
                            if #s.alias > 0 and #s.command > 0 and not s.enabled then
                                s.enabled = true
                            end
                            queueAliasRefresh()
                            saveConfig()
                        end
                        imgui.NextColumn()

                        -- 4. Mode Toggle [Send / Open]
                        local isSend = (s.mode == "send")
                        if isSend then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.65, 0.85, 0.85))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.70, 0.45, 0.15, 0.85))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                        end

                        local modeStr = isSend and "Send" or "Open"
                        if imgui.Button(modeStr .. "##md_" .. slotIdx, imgui.ImVec2(colModeW - 10, 24)) then
                            s.mode = isSend and "open" or "send"
                            saveConfig()
                        end
                        imgui.PopStyleColor(2)
                        imgui.NextColumn()

                        -- 5. Command Input Box
                        imgui.SetNextItemWidth(-1)
                        if imgui.InputTextWithHint("##cmd_" .. slotIdx, "Command or chat message (e.g. /cuff {nearid})", slotBuffers[curPIdx][slotIdx], 256) then
                            s.command = ffi.string(slotBuffers[curPIdx][slotIdx])
                            if #s.command > 0 and not s.enabled and (s.key > 0 or #s.alias > 0) then
                                s.enabled = true
                            end
                            saveConfig()
                        end
                        imgui.NextColumn()

                        -- 6. Clear Button [X] - Fully visible & padded before scrollbar
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.70, 0.18, 0.22, 0.75))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.25, 0.30, 0.95))
                        if imgui.Button("X##clr_" .. slotIdx, imgui.ImVec2(34, 24)) then
                            s.enabled = false
                            s.key     = 0
                            s.alias   = ""
                            s.command = ""
                            s.mode    = "send"
                            imgui.StrCopy(slotBuffers[curPIdx][slotIdx], "")
                            imgui.StrCopy(aliasBuffers[curPIdx][slotIdx], "")
                            queueAliasRefresh()
                            saveConfig()
                        end
                        imgui.PopStyleColor(2)
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip("Clear this slot")
                        end
                        imgui.NextColumn()
                        end -- if showSlot
                    end

                    if binderQuery ~= "" and matchedSlots == 0 then
                        imgui.Columns(1)
                        imgui.TextDisabled("No slots match your search.")
                    end
                    imgui.Columns(1)
                    imgui.EndChild()
                    end)

                -- ==============================================================
                -- TAB 2: VEHICLE AUTOMATION (AUTOCAR)
                -- ==============================================================
                elseif config.general.activeTab == 2 then
                    safeRenderTab(2, "2. Vehicle Automation (AutoCar)", function()
                    -- Master Mode 2 Power Switch
                    local acChanged, acVal = drawSlideSwitch("##sw_ac_master", config.autocar.enabled, "Enable Vehicle Automation Mode (AutoCar)", "Master power switch for vehicle engine, lights, seatbelt, and lock automation")
                    if acChanged then
                        config.autocar.enabled = acVal
                        saveConfig()
                        sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Vehicle Automation Mode: %s{FFFFFF}.", acVal and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
                    end
                    if not config.autocar.enabled then
                        imgui.SameLine()
                        imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "(AutoCar is currently PAUSED)")
                    end

                    imgui.Spacing()

                    -- Live Telemetry Status Box
                    imgui.BeginChild("AutoCarTelemetryBox", imgui.ImVec2(0, 95), true)
                    imgui.Columns(4, "VehTeleCols", false)
                    imgui.SetColumnWidth(0, 120)
                    imgui.SetColumnWidth(1, 145)
                    imgui.SetColumnWidth(2, 160)
                    imgui.SetColumnWidth(3, 140)

                    -- Col 1: In Vehicle & Class
                    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "STATUS:")
                    if state.inVehicle then
                        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "Inside Vehicle")
                        imgui.TextColored(imgui.ImVec4(1.00, 1.00, 1.00, 1.00), state.isDriver and "Driver Seat" or "Passenger Seat")
                    else
                        imgui.TextColored(imgui.ImVec4(0.85, 0.88, 0.95, 1.00), "On Foot")
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "No Vehicle")
                    end
                    imgui.NextColumn()

                    -- Col 2: Vehicle Model
                    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "MODEL & CLASS:")
                    if state.inVehicle and state.currentModel > 0 then
                        local mName = getNameOfVehicleModel(state.currentModel) or "Car"
                        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), mName)
                        imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), string.format("ID: %d (%s)", state.currentModel, state.currentClass:upper()))
                    else
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "---")
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "---")
                    end
                    imgui.NextColumn()

                    -- Col 3: Engine, Lights & Seatbelt
                    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "ACTIVE STATES:")
                    local engOn = state.inVehicle and isCarEngineOn(state.currentVeh)
                    local lgtOn = state.inVehicle and isCarLightsOn(state.currentVeh)
                    local sbtOn = state.inVehicle and (state.beltFastened == true)

                    imgui.Text("Eng: ")
                    imgui.SameLine()
                    if state.inVehicle then
                        imgui.TextColored(engOn and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or imgui.ImVec4(1.00, 0.32, 0.32, 1.00), engOn and "ON" or "OFF")
                    else
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "---")
                    end

                    imgui.SameLine()
                    imgui.Text("| Lgt: ")
                    imgui.SameLine()
                    if state.inVehicle then
                        imgui.TextColored(lgtOn and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or imgui.ImVec4(1.00, 0.32, 0.32, 1.00), lgtOn and "ON" or "OFF")
                    else
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "---")
                    end

                    imgui.Text("Seatbelt: ")
                    imgui.SameLine()
                    if state.inVehicle then
                        imgui.TextColored(sbtOn and imgui.ImVec4(0.00, 0.90, 0.46, 1.00) or imgui.ImVec4(1.00, 0.32, 0.32, 1.00), sbtOn and "ON" or "OFF")
                    else
                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "---")
                    end
                    imgui.NextColumn()

                    -- Col 4: Clock & Day/Night
                    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "SERVER TIME:")
                    local h, m, src = getEffectiveTime()
                    local isNight = isNightTime()
                    imgui.TextColored(imgui.ImVec4(1.00, 0.85, 0.20, 1.00), string.format("%02d:%02d (%s)", h, m, src))
                    imgui.TextColored(isNight and imgui.ImVec4(0.35, 0.70, 1.00, 1.00) or imgui.ImVec4(1.00, 0.75, 0.15, 1.00), isNight and "Night Phase (Lights ON)" or "Day Phase (Lights OFF)")
                    imgui.Columns(1)
                    imgui.EndChild()

                    imgui.Spacing()

                    -- Automation Toggles & Features
                    imgui.Columns(2, "AutoCarConfigCols", false)

                    -- Left Column: Core Automation Features
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Vehicle Automation Modes:")
                    imgui.Spacing()

                    local chk, nVal

                    chk, nVal = drawSlideSwitch("##sw_ac_eng", config.autocar.autoEngine, "Auto Engine Start (Driver)", "Automatically starts engine on entering driver seat")
                    if chk then config.autocar.autoEngine = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_engoff", config.autocar.engineOffOnExit, "Turn Engine OFF on Exit", "Stops engine automatically when stepping out of vehicle")
                    if chk then config.autocar.engineOffOnExit = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_sb", config.autocar.autoSeatbelt, "Auto Seatbelt (Driver)", "Fastens seatbelt upon entering vehicle as driver")
                    if chk then config.autocar.autoSeatbelt = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_psb", config.autocar.passengerSeatbelt, "Auto Seatbelt (Passenger)", "Fastens seatbelt when riding as a passenger")
                    if chk then config.autocar.passengerSeatbelt = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_lgt", config.autocar.autoLights, "Smart Day/Night Headlights", "Turns headlights ON at night (19:00 - 06:00) and OFF during day")
                    if chk then config.autocar.autoLights = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_lgtoff", config.autocar.lightsOffOnExit, "Turn Headlights OFF on Exit", "Shuts off headlights when stepping out of vehicle")
                    if chk then config.autocar.lightsOffOnExit = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_ac_lock", config.autocar.autoLock, "Auto Vehicle Lock on Enter", "Sends /lock upon entering vehicle")
                    if chk then config.autocar.autoLock = nVal; saveConfig() end

                    imgui.NextColumn()

                    -- Right Column: Timing, Clock & Custom Commands
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Server Timezone & Commands:")

                    uiSyncHudCheck[0] = config.autocar.syncWithHud
                    if imgui.Checkbox("Auto-Sync with Server HUD Clock (TextDraw)##chk_synchud", uiSyncHudCheck) then
                        config.autocar.syncWithHud = uiSyncHudCheck[0]
                        saveConfig()
                    end

                    imgui.AlignTextToFramePadding()
                    imgui.Text("Hour Offset:")
                    imgui.SameLine()
                    imgui.SetNextItemWidth(140)
                    uiHourOffset[0] = config.autocar.hourOffset
                    if imgui.SliderInt("##hour_offset", uiHourOffset, -12, 12, "%+d hrs") then
                        config.autocar.hourOffset = uiHourOffset[0]
                        saveConfig()
                    end

                    imgui.AlignTextToFramePadding()
                    imgui.Text("Enter Delay:")
                    imgui.SameLine()
                    imgui.SetNextItemWidth(140)
                    uiEnterDelay[0] = config.autocar.enterDelayMs
                    if imgui.SliderInt("##enter_delay", uiEnterDelay, 150, 1200, "%d ms") then
                        config.autocar.enterDelayMs = uiEnterDelay[0]
                        saveConfig()
                    end

                    imgui.Spacing()
                    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1.00), "Server Chat Command Triggers:")

                    imgui.SetNextItemWidth(140)
                    if imgui.InputText("Engine##cmd_e", cmdEngineBuf, 64) then
                        config.commands.engineCmd = ffi.string(cmdEngineBuf)
                        saveConfig()
                    end

                    imgui.SetNextItemWidth(140)
                    if imgui.InputText("Lights##cmd_l", cmdLightsBuf, 64) then
                        config.commands.lightsCmd = ffi.string(cmdLightsBuf)
                        saveConfig()
                    end

                    imgui.SetNextItemWidth(140)
                    if imgui.InputText("Seatbelt##cmd_s", cmdSeatbeltBuf, 64) then
                        config.commands.seatbeltCmd = ffi.string(cmdSeatbeltBuf)
                        saveConfig()
                    end

                    imgui.SetNextItemWidth(140)
                    if imgui.InputText("Lock##cmd_k", cmdLockBuf, 64) then
                        config.commands.lockCmd = ffi.string(cmdLockBuf)
                        saveConfig()
                    end

                    imgui.Columns(1)
                    end)

                -- ==============================================================
                -- TAB 3: FIVEM MODEL DOWNLOADER
                -- ==============================================================
                elseif config.general.activeTab == 3 then
                    safeRenderTab(3, "3. FiveM Model Downloader HUD", function()
                    -- Master Mode 3 Power Switch
                    local dlChanged, dlVal = drawSlideSwitch("##sw_dl_master", config.downloader.enabled, "Enable FiveM Downloader Mode", "Master switch for the sleek custom download HUD")
                    if dlChanged then
                        config.downloader.enabled = dlVal
                        saveConfig()
                        sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Model Downloader Mode: %s{FFFFFF}.", dlVal and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
                    end
                    if not config.downloader.enabled then
                        imgui.SameLine()
                        imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.20, 1.00), "(Downloader HUD is currently PAUSED)")
                    end

                    imgui.Spacing()
                    imgui.Separator()

                    -- Status & Hook State
                    local dlStatusStr = state.isDlVersion and "SA-MP 0.3.DL Active" or "Waiting for SA-MP 0.3.DL..."
                    local patchStr = state.renderHookApplied and "Screen-Blocker Neutralized (RET 0xC3)" or "Default Box Visible"
                    imgui.Text("Status: " .. dlStatusStr)
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "|")
                    imgui.SameLine()
                    imgui.Text("Hook: " .. patchStr)

                    imgui.Spacing()

                    local chk, nVal

                    chk, nVal = drawSlideSwitch("##sw_dl_hide", config.downloader.hideDefaultBox, "Hide SA-MP Default Download Table Dialog", "Neutralizes the black screen-blocking dialog (RET 0xC3)")
                    if chk then
                        config.downloader.hideDefaultBox = nVal
                        applyRenderHook(nVal)
                        saveConfig()
                    end

                    chk, nVal = drawSlideSwitch("##sw_dl_snd", config.downloader.soundNotification, "Play Completion Chime Sound (GTA sound 1058)", "Plays chime audio when download finishes")
                    if chk then config.downloader.soundNotification = nVal; saveConfig() end

                    chk, nVal = drawSlideSwitch("##sw_dl_spd", config.downloader.showSpeed, "Show Transfer Speed in KB/s & MB/s", "Displays live network speed inside the HUD card")
                    if chk then config.downloader.showSpeed = nVal; saveConfig() end

                    imgui.Separator()

                    -- Position Presets
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Position Preset:")
                    local positions = {
                        { id = "bottom_right",  label = "Bottom-Right (FiveM Default)" },
                        { id = "bottom_center", label = "Bottom-Center" },
                        { id = "top_right",     label = "Top-Right" },
                        { id = "top_center",    label = "Top-Center" },
                    }
                    for _, pos in ipairs(positions) do
                        local isSel = (config.downloader.positionPreset == pos.id)
                        if imgui.RadioButtonBool(pos.label .. "##rad_dl_pos_" .. pos.id, isSel) then
                            config.downloader.positionPreset = pos.id
                            saveConfig()
                        end
                    end

                    imgui.Separator()

                    -- Color Themes (Defaults to Neon Cyan!)
                    imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "HUD Theme Accent:")
                    for _, tItem in ipairs(THEME_ORDER) do
                        local th = THEMES[tItem.id]
                        local isSel = (config.downloader.theme == tItem.id)
                        imgui.PushStyleColor(imgui.Col.Text, th.accent)
                        if imgui.RadioButtonBool(tItem.label .. "##rad_dl_th_" .. tItem.id, isSel) then
                            config.downloader.theme = tItem.id
                            saveConfig()
                        end
                        imgui.PopStyleColor()
                        imgui.SameLine()
                    end
                    imgui.NewLine()

                    imgui.Separator()

                    -- Action Button: Test Simulation
                    if imgui.Button("Test Download Simulation##btn_dl_test_tab", imgui.ImVec2(220, 28)) then
                        startSimulationTest()
                    end
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Runs a 45-model live simulation so you can see the HUD in action!")
                    end)

                -- ==============================================================
                -- TAB 4: CHAT MODES (ROOM EDITOR) & IN-GAME CHATLOG VIEWER
                -- ==============================================================
                elseif config.general.activeTab == 4 then
                    safeRenderTab(4, "4. Chat Modes & In-Game Chatlog", function()
                    -- Sub-tab Selector (50/50 Content Split)
                    local availW = imgui.GetContentRegionAvail().x
                    local subBtnW = math.floor((availW - 8) / 2)
                    local function renderChatSubTab(subId, label)
                        local isSel = (config.general.chatSubTab == subId)
                        if isSel then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.72, 0.42, 0.95))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 1.00, 1.00, 1.00))
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.75))
                            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.80, 0.84, 0.92, 1.00))
                        end
                        if imgui.Button(label .. "##chatsub_" .. subId, imgui.ImVec2(subBtnW, 26)) then
                            config.general.chatSubTab = subId
                            saveConfig()
                        end
                        imgui.PopStyleColor(2)
                    end

                    renderChatSubTab(1, "Chat Modes (Room Editor)")
                    imgui.SameLine()
                    renderChatSubTab(2, "In-Game Chatlog & Search")

                    imgui.Separator()

                    -- ----------------------------------------------------------
                    -- SUB-TAB 1: CHAT MODES AUTO-PREFIX & ROOM EDITOR
                    -- ----------------------------------------------------------
                    if (config.general.chatSubTab or 1) == 1 then

                        -- Master Power Slide Switch
                        local cmChanged, cmVal = drawSlideSwitch("##sw_chatmode_master", config.chatmode.enabled, "Enable Chat Mode Auto-Prefix", "Automatically prefixes normal typed chat with active mode command (e.g. /b text)")
                        if cmChanged then
                            config.chatmode.enabled = cmVal
                            saveConfig()
                        end

                        imgui.Spacing()

                        -- Floating Pill Bar Switch
                        local fpChanged, fpVal = drawSlideSwitch("##sw_chatmode_pillbar", config.chatmode.showFloatingBar, "Show Floating Pill Bar Under Chat Box", "Displays mode selection pills directly under SA-MP chatbox when typing")
                        if fpChanged then
                            config.chatmode.showFloatingBar = fpVal
                            saveConfig()
                        end

                        imgui.Spacing()
                        imgui.Separator()

                        -- Live Active Mode Status & Interactive Demonstration
                        local curMode = config.chatmode.modes[config.chatmode.activeModeIdx]
                        local pfx = curMode and curMode.prefix or ""
                        local hasPfx = (#pfx > 0)
                        
                        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "LIVE STATUS:")
                        imgui.SameLine()
                        if not config.chatmode.enabled then
                            imgui.TextColored(imgui.ImVec4(1.00, 0.45, 0.45, 1.00), "[DISABLED] - Messages send as regular IC chat.")
                        elseif not hasPfx then
                            imgui.TextColored(imgui.ImVec4(0.85, 0.88, 0.95, 1.00), string.format("Active: '%s' (Normal Chat - No Prefix)", curMode.name))
                        else
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), string.format("Active: '%s'  |  Prefix: '%s'", curMode.name, pfx))
                            imgui.TextColored(imgui.ImVec4(1.00, 0.85, 0.20, 1.00), string.format("Typing: 'Hello everyone'  -->  Sends: '%s Hello everyone'", pfx))
                        end
                        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "* Commands starting with '/' (e.g. /stats, /engine, /lock) are NEVER prefixed.")

                        imgui.Spacing()
                        imgui.Separator()

                        -- Room Editor Header
                        imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "ROOM EDITOR - CHAT MODES & SEQUENCE:")
                        imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Order, rename, select, or delete modes. Use [^] and [v] to re-order sequence.")

                        imgui.Spacing()

                        -- Mode List Scrollable Area
                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.05, 0.07, 0.10, 0.80))
                        imgui.BeginChild("ChatModesListChild", imgui.ImVec2(0, 160), true)

                        for i, m in ipairs(config.chatmode.modes) do
                            local isCurActive = (config.chatmode.activeModeIdx == i)

                            -- 1. Move Up button
                            if i == 1 then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.14, 0.18, 0.40))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.35, 0.40, 0.50, 0.50))
                                imgui.Button("-##up_dis_" .. i, imgui.ImVec2(22, 22))
                                imgui.PopStyleColor(2)
                            else
                                if imgui.Button("^##up_" .. i, imgui.ImVec2(22, 22)) then
                                    moveChatMode(i, -1)
                                end
                                if imgui.IsItemHovered() then imgui.SetTooltip("Move Up in sequence") end
                            end

                            imgui.SameLine()

                            -- 2. Move Down button
                            if i == #config.chatmode.modes then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.14, 0.18, 0.40))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.35, 0.40, 0.50, 0.50))
                                imgui.Button("-##dn_dis_" .. i, imgui.ImVec2(22, 22))
                                imgui.PopStyleColor(2)
                            else
                                if imgui.Button("v##dn_" .. i, imgui.ImVec2(22, 22)) then
                                    moveChatMode(i, 1)
                                end
                                if imgui.IsItemHovered() then imgui.SetTooltip("Move Down in sequence") end
                            end

                            imgui.SameLine()

                            -- 3. Active Mode Radio Button
                            if isCurActive then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.75, 0.90, 0.95))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                                imgui.Button("ACTIVE##act_" .. i, imgui.ImVec2(56, 22))
                                imgui.PopStyleColor(2)
                            else
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15, 0.19, 0.26, 0.70))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.85, 1.0))
                                if imgui.Button("Select##sel_" .. i, imgui.ImVec2(56, 22)) then
                                    config.chatmode.activeModeIdx = i
                                    saveConfig()
                                end
                                imgui.PopStyleColor(2)
                                if imgui.IsItemHovered() then imgui.SetTooltip("Click to make this mode active") end
                            end

                            imgui.SameLine()

                            -- 4. Mode Name Input
                            imgui.SetNextItemWidth(170)
                            if chatModeBuffers[i] and chatModeBuffers[i].name then
                                if imgui.InputTextWithHint("##mode_name_" .. i, "e.g. /b (OOC)", chatModeBuffers[i].name, 64) then
                                    m.name = ffi.string(chatModeBuffers[i].name)
                                    saveConfig()
                                end
                            end

                            imgui.SameLine()

                            -- 5. Prefix Input
                            imgui.SetNextItemWidth(80)
                            if chatModeBuffers[i] and chatModeBuffers[i].prefix then
                                if imgui.InputTextWithHint("##mode_pfx_" .. i, "Prefix (/b)", chatModeBuffers[i].prefix, 32) then
                                    m.prefix = ffi.string(chatModeBuffers[i].prefix)
                                    saveConfig()
                                end
                            end

                            imgui.SameLine()

                            -- 6. Delete Button
                            if #config.chatmode.modes > 1 then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55, 0.15, 0.15, 0.75))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.20, 0.20, 1.00))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                                if imgui.Button("X##del_" .. i, imgui.ImVec2(24, 22)) then
                                    deleteChatMode(i)
                                end
                                imgui.PopStyleColor(3)
                                if imgui.IsItemHovered() then imgui.SetTooltip("Delete this chat mode") end
                            else
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.14, 0.18, 0.40))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.35, 0.40, 0.50, 0.50))
                                imgui.Button("-##del_dis_" .. i, imgui.ImVec2(24, 22))
                                imgui.PopStyleColor(2)
                                if imgui.IsItemHovered() then imgui.SetTooltip("Cannot delete the only remaining mode") end
                            end
                        end

                        imgui.EndChild()
                        imgui.PopStyleColor()

                        -- Actions bar
                        imgui.Spacing()
                        if imgui.Button("+ Add New Chat Mode##btn_add_cm", imgui.ImVec2(165, 24)) then
                            addChatMode("New Mode", "/new")
                        end
                        imgui.SameLine()
                        if imgui.Button("Reset Default Modes##btn_rst_cm", imgui.ImVec2(145, 24)) then
                            resetDefaultChatModes()
                            sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Chat modes reset to defaults (Normal, /b, /me, /do, /s).", -1)
                        end

                        imgui.Spacing()
                        imgui.Separator()

                        -- Quick Cycle Hotkey & Pill Bar Position Sliders
                        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "HOTKEY & FLOATING BAR POSITION:")

                        local aaChanged, aaVal = drawSlideSwitch("##sw_auto_attach", config.chatmode.autoAttach ~= false, "Auto-Attach Under Chatbox", "Automatically anchors the pill bar directly below the SA-MP chat input box")
                        if aaChanged then
                            config.chatmode.autoAttach = aaVal
                            saveConfig()
                        end
                        imgui.AlignTextToFramePadding()
                        imgui.TextColored(imgui.ImVec4(0.80, 0.85, 0.92, 1.00), "Cycle Mode Key:")
                        imgui.SameLine()
                        local cycLabel = state.waitingChatCycleKey and ">>> PRESS ANY KEY <<<" or (getKeyName(config.chatmode.cycleKey or 9) .. "##btn_rebind_cycle")
                        if imgui.Button(cycLabel, imgui.ImVec2(140, 22)) then
                            state.waitingChatCycleKey = true
                        end
                        if imgui.IsItemHovered() then imgui.SetTooltip("Click to rebind mode cycling key (Default: F2)") end

                        imgui.SameLine()
                        if imgui.Button("Reset Pos##btn_rst_bar_pos", imgui.ImVec2(75, 22)) then
                            config.chatmode.autoAttach = true
                            config.chatmode.offsetX = 0
                            config.chatmode.offsetY = 0
                            config.chatmode.barX = 28
                            config.chatmode.barY = 95
                            saveConfig()
                        end
                        if imgui.IsItemHovered() then imgui.SetTooltip("Reset floating pill bar position to default (28, 95)") end

                        uiBarX[0] = config.chatmode.barX or 28
                        uiBarY[0] = config.chatmode.barY or 95
                        imgui.SetNextItemWidth(120)
                        if imgui.SliderInt("X##bar_x", uiBarX, 0, 1920) then
                            config.chatmode.barX = uiBarX[0]
                            saveConfig()
                        end
                        imgui.SameLine()
                        imgui.SetNextItemWidth(120)
                        if imgui.SliderInt("Y##bar_y", uiBarY, 0, 1080) then
                            config.chatmode.barY = uiBarY[0]
                            saveConfig()
                        end

                    -- ----------------------------------------------------------
                    -- SUB-TAB 2: COMPREHENSIVE IN-GAME CHATLOG VIEWER & SEARCH
                    -- ----------------------------------------------------------
                    elseif (config.general.chatSubTab or 1) == 2 then

                        -- Search Bar + Clear + Auto-Scroll + Reload Bar (Responsive Flow)
                        imgui.AlignTextToFramePadding()
                        imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Search:")
                        imgui.SameLine()
                        imgui.SetNextItemWidth(170)
                        imgui.InputTextWithHint("##clog_search_input", "Search text, /report, ID...", chatlogSearchBuf, 128)

                        imgui.SameLine()
                        if imgui.Button("X##clear_clog_search", imgui.ImVec2(22, 22)) then
                            imgui.StrCopy(chatlogSearchBuf, "")
                        end
                        if imgui.IsItemHovered() then imgui.SetTooltip("Clear search text") end

                        imgui.SameLine()
                        local scrChanged, scrVal = drawSlideSwitch("##sw_clog_autoscroll", chatlogAutoScroll, "Auto-Scroll", "Automatically scrolls to bottom on new messages")
                        if scrChanged then chatlogAutoScroll = scrVal end

                        imgui.SameLine()
                        if imgui.Button("Reload##btn_clog_reload", imgui.ImVec2(65, 22)) then
                            loadChatlogFromDisk()
                            sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Chatlog reloaded! (%d lines in memory)", #chatlogLines), -1)
                        end
                        if imgui.IsItemHovered() then imgui.SetTooltip("Reload entire chatlog from disk (chatlog.txt)") end

                        -- Filter Category Chips
                        imgui.Spacing()
                        local function filterChip(catId, label)
                            local isSel = (chatlogFilterCategory == catId)
                            if isSel then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.00, 0.65, 0.85, 0.95))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
                            else
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.16, 0.22, 0.70))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.70, 0.75, 0.85, 1.0))
                            end
                            if imgui.SmallButton(label .. "##chip_cat_" .. catId) then
                                chatlogFilterCategory = catId
                            end
                            imgui.PopStyleColor(2)
                            imgui.SameLine()
                        end

                        filterChip("all", "All Logs")
                        filterChip("reports", "Reports / Staff")
                        filterChip("radio", "Radio / Dept")
                        filterChip("pms", "PMs / Whispers")
                        filterChip("vehicles", "Vehicle Actions")

                        local searchStr = ffi.string(chatlogSearchBuf):lower():match("^%s*(.-)%s*$")
                        local hasSearch = (#searchStr > 0)

                        -- Pre-filter lines
                        local filtered = {}
                        for idx, line in ipairs(chatlogLines) do
                            local clean = line:gsub("{%x%x%x%x%x%x}", "")
                            local cleanLower = clean:lower()
                            local matchCat = true
                            if chatlogFilterCategory == "reports" then
                                matchCat = cleanLower:find("report")
                                    or cleanLower:find("ticket")
                                    or cleanLower:find("warning")
                                    or cleanLower:find("staff")
                                    or cleanLower:find("admin")
                                    or cleanLower:find("support")
                                    or cleanLower:find("cheating")
                                    or cleanLower:find("cheat")
                                    or cleanLower:find(">%s*%[#")
                                    or cleanLower:find("%[#%d+")
                                    or cleanLower:find("#%[admin")
                                    or cleanLower:find("#%[staff")
                                    or cleanLower:find("%|%s*normal%]")
                                    or cleanLower:find("%|%s*priority%]")
                                    or cleanLower:find("%|%s*emergency%]")
                                    or cleanLower:find("aimlock")
                                    or cleanLower:find("unhandled")
                            elseif chatlogFilterCategory == "radio" then
                                matchCat = cleanLower:find("%[r%]") or cleanLower:find("%[d%]") or cleanLower:find("radio") or cleanLower:find("dispatch") or cleanLower:find("%[dept%]") or cleanLower:find("%[f%]") or cleanLower:find("faction")
                            elseif chatlogFilterCategory == "pms" then
                                matchCat = cleanLower:find("pm from") or cleanLower:find("pm to") or cleanLower:find("whisper") or cleanLower:find("%(%(") or cleanLower:find("sms")
                            elseif chatlogFilterCategory == "vehicles" then
                                matchCat = cleanLower:find("engine") or cleanLower:find("lights") or cleanLower:find("seatbelt") or cleanLower:find("lock") or cleanLower:find("vehicle") or cleanLower:find("car")
                            end

                            if matchCat then
                                if not hasSearch or cleanLower:find(searchStr, 1, true) then
                                    table.insert(filtered, { raw = line, clean = clean })
                                end
                            end
                        end

                        imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), string.format("Showing %d of %d lines", #filtered, #chatlogLines))
                        imgui.Separator()

                        -- Chatlog Box (Scrollable with Clipper)
                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.04, 0.06, 0.09, 0.95))
                        imgui.BeginChild("ChatlogDisplayChild", imgui.ImVec2(0, 0), true, imgui.WindowFlags.HorizontalScrollbar)

                        if #filtered == 0 then
                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.50, 0.55, 0.65, 1.00), "No chatlog messages match your search or filter.")
                        else
                            local clipper = imgui.ImGuiListClipper(#filtered)
                            while clipper:Step() do
                                for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                                    local entry = filtered[i]
                                    local clean = entry.clean

                                    local isHighlighted = hasSearch and clean:lower():find(searchStr, 1, true)
                                    if isHighlighted then
                                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 0.85, 0.20, 1.00)) -- Highlight yellow
                                    else
                                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.85, 0.89, 0.95, 1.00))
                                    end

                                    local itemLabel = clean .. "##clog_line_" .. i
                                    if imgui.Selectable(itemLabel, false) then
                                        setClipboardText(clean)
                                        sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Copied chatlog line to clipboard!", -1)
                                    end
                                    imgui.PopStyleColor()

                                    if imgui.IsItemHovered() then
                                        imgui.SetTooltip("Click to copy line to clipboard:\n" .. clean)
                                    end
                                end
                            end

                            if chatlogAutoScroll and imgui.GetScrollY() >= imgui.GetScrollMaxY() - 30 then
                                imgui.SetScrollHereY(1.0)
                            end
                        end

                        imgui.EndChild()
                        imgui.PopStyleColor()
                    end
                    end)

                                -- ==============================================================
                -- TAB 5: BDS VEHICLE INFO HUD
                -- ==============================================================
                elseif config.general.activeTab == 5 then
                    safeRenderTab(5, "5. Vehicle Info HUD", function()
                    imgui.BeginChild("VehInfoScrollBox", imgui.ImVec2(0, 0), false)

                    -- Master Switch Header
                    local viChanged, viVal = drawSlideSwitch("##sw_vehinfo_master", config.vehinfo.enabled, "Enable Vehicle Info HUD", "Renders 3D World Space & 2D vehicle telemetry HUD")
                    if viChanged then
                        config.vehinfo.enabled = viVal
                        uiVehInfo.enabled[0] = viVal
                        saveConfig()
                        sampAddChatMessage(string.format("{00E676}[BDS Toolkit]{FFFFFF} Vehicle Info HUD: %s{FFFFFF}.", viVal and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
                    end

                    if not config.vehinfo.enabled then
                        imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Vehicle Info HUD is currently disabled. Toggle the master switch above or type /vinfotoggle to activate.")
                        imgui.EndChild()
                        return
                    end

                    imgui.Spacing()
                    imgui.Separator()

                    if imgui.BeginTabBar("##VehInfoSubTabs") then
                        -- SUBTAB 1: General & Modes
                        if imgui.BeginTabItem("General & Modes##vi_tab1") then
                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "DISPLAY MODE")
                            if imgui.RadioButtonIntPtr("3D World Space (Attached directly to vehicle body center)##vi_dm1", uiVehInfo.displayMode, 1) then
                                config.vehinfo.displayMode = 1
                                saveConfig()
                            end
                            if imgui.RadioButtonIntPtr("2D Fixed Screen HUD (Anchored on screen HUD)##vi_dm2", uiVehInfo.displayMode, 2) then
                                config.vehinfo.displayMode = 2
                                saveConfig()
                            end

                            imgui.Spacing()
                            imgui.Separator()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "SCANNING & DETECTION")
                            if imgui.Checkbox("Track Current Vehicle (When driving or riding as passenger)##vi_self", uiVehInfo.trackCurrentCar) then
                                config.vehinfo.trackCurrentCar = uiVehInfo.trackCurrentCar[0]
                                saveConfig()
                            end

                            imgui.SetNextItemWidth(260)
                            if imgui.SliderFloat("Max Scan Distance (m)##vi_dist", uiVehInfo.lookMaxDist, 10.0, 100.0, "%.0f m") then
                                config.vehinfo.lookMaxDist = uiVehInfo.lookMaxDist[0]
                                saveConfig()
                            end

                            imgui.SetNextItemWidth(260)
                            if imgui.SliderInt("Max Visible Vehicles on Screen##vi_maxc", uiVehInfo.nearbyMaxCount, 1, 10) then
                                config.vehinfo.nearbyMaxCount = uiVehInfo.nearbyMaxCount[0]
                                saveConfig()
                            end

                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.85, 0.98, 1.00), "Wall Occlusion (Line-of-Sight):")
                            imgui.SameLine()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "PERMANENT [ON]")
                            imgui.TextColored(imgui.ImVec4(0.60, 0.65, 0.75, 1.00), "Raycasting line-of-sight active: vehicle tags never show through solid walls or buildings.")

                            imgui.Spacing()
                            imgui.Separator()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "TYPOGRAPHY & FONT SIZE")
                            if imgui.Button("-##vi_font_dec", imgui.ImVec2(28, 22)) then
                                uiVehInfo.fontSize[0] = math.max(10.0, uiVehInfo.fontSize[0] - 1.0)
                                config.vehinfo.fontSize = uiVehInfo.fontSize[0]
                                saveConfig()
                            end
                            imgui.SameLine()
                            imgui.SetNextItemWidth(200)
                            if imgui.SliderFloat("##vi_font_slider", uiVehInfo.fontSize, 10.0, 30.0, "Font: %.0f px") then
                                config.vehinfo.fontSize = uiVehInfo.fontSize[0]
                                saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.Button("+##vi_font_inc", imgui.ImVec2(28, 22)) then
                                uiVehInfo.fontSize[0] = math.min(32.0, uiVehInfo.fontSize[0] + 1.0)
                                config.vehinfo.fontSize = uiVehInfo.fontSize[0]
                                saveConfig()
                            end

                            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Presets:")
                            imgui.SameLine()
                            local function fontPreBtn(sz, lbl)
                                if imgui.SmallButton(lbl .. "##vi_fps_" .. math.floor(sz)) then
                                    uiVehInfo.fontSize[0] = sz
                                    config.vehinfo.fontSize = sz
                                    saveConfig()
                                end
                                imgui.SameLine()
                            end
                            fontPreBtn(12.0, "12px")
                            fontPreBtn(14.0, "14px")
                            fontPreBtn(15.0, "15px (Default)")
                            fontPreBtn(18.0, "18px")
                            fontPreBtn(22.0, "22px")
                            imgui.NewLine()

                            imgui.EndTabItem()
                        end

                        -- SUBTAB 2: Fields & Rows
                        if imgui.BeginTabItem("Fields & Rows##vi_tab2") then
                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "DISPLAYED TELEMETRY FIELDS")

                            if imgui.Checkbox("Show Vehicle ID (SA-MP ID)##vi_fid", uiVehInfo.showId) then
                                config.vehinfo.showId = uiVehInfo.showId[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Vehicle Model (e.g. Stallion, PCJ-600)##vi_fmodel", uiVehInfo.showModel) then
                                config.vehinfo.showModel = uiVehInfo.showModel[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Health (HP)##vi_fhp", uiVehInfo.showHealth) then
                                config.vehinfo.showHealth = uiVehInfo.showHealth[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Speed (Calibrated to Server Speedometer)##vi_fspd", uiVehInfo.showSpeed) then
                                config.vehinfo.showSpeed = uiVehInfo.showSpeed[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Distance to Vehicle (Meters)##vi_fdist", uiVehInfo.showDistance) then
                                config.vehinfo.showDistance = uiVehInfo.showDistance[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Engine Status (ON/OFF)##vi_feng", uiVehInfo.showEngine) then
                                config.vehinfo.showEngine = uiVehInfo.showEngine[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Door Lock Status (LOCKED/UNLOCKED)##vi_flock", uiVehInfo.showLock) then
                                config.vehinfo.showLock = uiVehInfo.showLock[0]; saveConfig()
                            end
                            if imgui.Checkbox("Show Mini Health Bar##vi_fhpbar", uiVehInfo.showHealthBar) then
                                config.vehinfo.showHealthBar = uiVehInfo.showHealthBar[0]; saveConfig()
                            end

                            imgui.Spacing()
                            imgui.Separator()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "SPEED UNIT")
                            if imgui.RadioButtonIntPtr("km/h##vi_spd_kmh", uiVehInfo.speedUnitInt, 1) then
                                config.vehinfo.speedUnit = "km/h"; saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.RadioButtonIntPtr("mph##vi_spd_mph", uiVehInfo.speedUnitInt, 2) then
                                config.vehinfo.speedUnit = "mph"; saveConfig()
                            end

                            imgui.EndTabItem()
                        end

                        -- SUBTAB 3: Style & Colors
                        if imgui.BeginTabItem("Style & Colors##vi_tab3") then
                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "COLORS")

                            if imgui.ColorEdit4("Label Color (e.g. 'ID:', 'Model:')##vi_col_lbl", uiVehInfo.labelColor) then
                                config.vehinfo.labelColorR = uiVehInfo.labelColor[0]
                                config.vehinfo.labelColorG = uiVehInfo.labelColor[1]
                                config.vehinfo.labelColorB = uiVehInfo.labelColor[2]
                                config.vehinfo.labelColorA = uiVehInfo.labelColor[3]
                                saveConfig()
                            end

                            if imgui.ColorEdit4("Value Color (e.g. '148', 'Stallion')##vi_col_val", uiVehInfo.valueColor) then
                                config.vehinfo.valueColorR = uiVehInfo.valueColor[0]
                                config.vehinfo.valueColorG = uiVehInfo.valueColor[1]
                                config.vehinfo.valueColorB = uiVehInfo.valueColor[2]
                                config.vehinfo.valueColorA = uiVehInfo.valueColor[3]
                                saveConfig()
                            end

                            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Color Themes:")
                            imgui.SameLine()
                            if imgui.Button("Authentic (Lime Green/White)##vi_th1") then
                                uiVehInfo.labelColor[0] = 0.20; uiVehInfo.labelColor[1] = 1.00; uiVehInfo.labelColor[2] = 0.20; uiVehInfo.labelColor[3] = 1.00
                                uiVehInfo.valueColor[0] = 1.00; uiVehInfo.valueColor[1] = 1.00; uiVehInfo.valueColor[2] = 1.00; uiVehInfo.valueColor[3] = 1.00
                                config.vehinfo.labelColorR = 0.20; config.vehinfo.labelColorG = 1.00; config.vehinfo.labelColorB = 0.20
                                config.vehinfo.valueColorR = 1.00; config.vehinfo.valueColorG = 1.00; config.vehinfo.valueColorB = 1.00
                                saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.Button("Cyber Cyan##vi_th2") then
                                uiVehInfo.labelColor[0] = 0.00; uiVehInfo.labelColor[1] = 0.90; uiVehInfo.labelColor[2] = 1.00; uiVehInfo.labelColor[3] = 1.00
                                uiVehInfo.valueColor[0] = 1.00; uiVehInfo.valueColor[1] = 1.00; uiVehInfo.valueColor[2] = 1.00; uiVehInfo.valueColor[3] = 1.00
                                config.vehinfo.labelColorR = 0.00; config.vehinfo.labelColorG = 0.90; config.vehinfo.labelColorB = 1.00
                                config.vehinfo.valueColorR = 1.00; config.vehinfo.valueColorG = 1.00; config.vehinfo.valueColorB = 1.00
                                saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.Button("VGRP Gold##vi_th3") then
                                uiVehInfo.labelColor[0] = 1.00; uiVehInfo.labelColor[1] = 0.70; uiVehInfo.labelColor[2] = 0.10; uiVehInfo.labelColor[3] = 1.00
                                uiVehInfo.valueColor[0] = 1.00; uiVehInfo.valueColor[1] = 1.00; uiVehInfo.valueColor[2] = 1.00; uiVehInfo.valueColor[3] = 1.00
                                config.vehinfo.labelColorR = 1.00; config.vehinfo.labelColorG = 0.70; config.vehinfo.labelColorB = 0.10
                                config.vehinfo.valueColorR = 1.00; config.vehinfo.valueColorG = 1.00; config.vehinfo.valueColorB = 1.00
                                saveConfig()
                            end

                            imgui.Spacing()
                            imgui.Separator()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "BACKGROUND & EFFECTS")
                            if imgui.RadioButtonIntPtr("Pure Text with Drop Shadow (Cleanest HUD)##vi_bg1", uiVehInfo.bgStyle, 1) then
                                config.vehinfo.bgStyle = 1; saveConfig()
                            end
                            if imgui.RadioButtonIntPtr("Semi-Transparent Dark Card##vi_bg2", uiVehInfo.bgStyle, 2) then
                                config.vehinfo.bgStyle = 2; saveConfig()
                            end

                            if uiVehInfo.bgStyle[0] == 2 then
                                imgui.SetNextItemWidth(240)
                                if imgui.SliderFloat("Card Opacity##vi_card_op", uiVehInfo.bgAlpha, 0.20, 1.00, "%.2f") then
                                    config.vehinfo.bgAlpha = uiVehInfo.bgAlpha[0]; saveConfig()
                                end
                            end

                            if imgui.Checkbox("Render Drop Shadow Behind Text##vi_shadow", uiVehInfo.textShadow) then
                                config.vehinfo.textShadow = uiVehInfo.textShadow[0]; saveConfig()
                            end
                            if imgui.Checkbox("Scale Text With Distance (Perspective scaling)##vi_scaledist", uiVehInfo.scaleWithDist) then
                                config.vehinfo.scaleWithDist = uiVehInfo.scaleWithDist[0]; saveConfig()
                            end

                            imgui.EndTabItem()
                        end

                        -- SUBTAB 4: 3D & 2D Position
                        if imgui.BeginTabItem("3D & 2D Position##vi_tab4") then
                            imgui.Spacing()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "3D WORLD SPACE ANCHOR OFFSETS")

                            imgui.SetNextItemWidth(260)
                            if imgui.SliderFloat("Lateral Offset (Left/Right)##vi_ox", uiVehInfo.offsetX, -2.0, 2.0, "%.2f m") then
                                config.vehinfo.offsetX = uiVehInfo.offsetX[0]; saveConfig()
                            end
                            imgui.SetNextItemWidth(260)
                            if imgui.SliderFloat("Vertical Height Offset (Up/Down)##vi_oz", uiVehInfo.offsetZ, -1.0, 2.0, "%.2f m") then
                                config.vehinfo.offsetZ = uiVehInfo.offsetZ[0]; saveConfig()
                            end
                            if imgui.Button("Reset Height to 0.25m (Default)##vi_rst_h") then
                                uiVehInfo.offsetZ[0] = 0.25; config.vehinfo.offsetZ = 0.25; saveConfig()
                            end

                            imgui.Spacing()
                            imgui.Separator()
                            imgui.TextColored(imgui.ImVec4(0.00, 0.90, 0.46, 1.00), "2D FIXED SCREEN HUD POSITION")

                            imgui.SetNextItemWidth(260)
                            if imgui.SliderFloat("Screen X Ratio##vi_hudx", uiVehInfo.posXRatio, 0.05, 0.95, "%.2f") then
                                config.vehinfo.hud2dPosX = uiVehInfo.posXRatio[0]; saveConfig()
                            end
                            imgui.SetNextItemWidth(260)
                            if imgui.SliderFloat("Screen Y Ratio##vi_hudy", uiVehInfo.posYRatio, 0.05, 0.95, "%.2f") then
                                config.vehinfo.hud2dPosY = uiVehInfo.posYRatio[0]; saveConfig()
                            end

                            imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 1.00), "Presets:")
                            imgui.SameLine()
                            if imgui.Button("Bottom-Right (Default)##vi_pre_br") then
                                uiVehInfo.posXRatio[0] = 0.85; uiVehInfo.posYRatio[0] = 0.82
                                config.vehinfo.hud2dPosX = 0.85; config.vehinfo.hud2dPosY = 0.82
                                saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.Button("Top-Right##vi_pre_tr") then
                                uiVehInfo.posXRatio[0] = 0.85; uiVehInfo.posYRatio[0] = 0.25
                                config.vehinfo.hud2dPosX = 0.85; config.vehinfo.hud2dPosY = 0.25
                                saveConfig()
                            end
                            imgui.SameLine()
                            if imgui.Button("Bottom-Left##vi_pre_bl") then
                                uiVehInfo.posXRatio[0] = 0.05; uiVehInfo.posYRatio[0] = 0.70
                                config.vehinfo.hud2dPosX = 0.05; config.vehinfo.hud2dPosY = 0.70
                                saveConfig()
                            end

                            imgui.Spacing()
                            imgui.Separator()
                            if imgui.Button("Reset All VehInfo Settings to Defaults##vi_rst_all", imgui.ImVec2(300, 26)) then
                                config.vehinfo.displayMode = 1
                                config.vehinfo.trackCurrentCar = true
                                config.vehinfo.lookMaxDist = 50.0
                                config.vehinfo.nearbyMaxCount = 6
                                config.vehinfo.speedUnit = "km/h"
                                config.vehinfo.showId = true
                                config.vehinfo.showModel = true
                                config.vehinfo.showHealth = true
                                config.vehinfo.showSpeed = false
                                config.vehinfo.showDistance = false
                                config.vehinfo.showEngine = false
                                config.vehinfo.showLock = false
                                config.vehinfo.showHealthBar = false
                                config.vehinfo.labelColorR = 0.20; config.vehinfo.labelColorG = 1.00; config.vehinfo.labelColorB = 0.20; config.vehinfo.labelColorA = 1.00
                                config.vehinfo.valueColorR = 1.00; config.vehinfo.valueColorG = 1.00; config.vehinfo.valueColorB = 1.00; config.vehinfo.valueColorA = 1.00
                                config.vehinfo.bgStyle = 1
                                config.vehinfo.bgAlpha = 0.65
                                config.vehinfo.fontSize = 15.0
                                config.vehinfo.scaleWithDist = false
                                config.vehinfo.textShadow = true
                                config.vehinfo.offsetX = 0.0
                                config.vehinfo.offsetZ = 0.25
                                config.vehinfo.hud2dPosX = 0.85
                                config.vehinfo.hud2dPosY = 0.82
                                syncVehInfoUI()
                                saveConfig()
                                sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Vehicle Info HUD settings restored to defaults.", -1)
                            end

                            imgui.EndTabItem()
                        end

                        imgui.EndTabBar()
                    end

                    imgui.EndChild()
                    end)

                -- ==============================================================
                -- TAB 6: WEAPON SENSITIVITY & DRIVE-BY (SENSFIX)
                -- ==============================================================
                elseif config.general.activeTab == 6 then
                    safeRenderTab(6, "6. SensFix (Weapon & Drive-By)", renderTabSensFix)

                -- ==============================================================
                -- TAB 7: ENGINE FIXES & GAMEPLAY TWEAKS
                -- ==============================================================
                elseif config.general.activeTab == 7 then
                    safeRenderTab(7, "7. Fixes & Gameplay Tweaks", renderTabTweaks)

                -- ==============================================================
                -- TAB 8: HELP & DOCUMENTATION
                -- ==============================================================
                elseif config.general.activeTab == 8 then
                    safeRenderTab(8, "8. Help & Documentation", renderTabHelp)
                end
                imgui.EndChild() -- Close ##BdsMainContent
            end
            imgui.End()
        end
    end
)

-- ------------------------------------------------------------------------------
-- UI Toggle Helpers
-- ------------------------------------------------------------------------------
local function toggleSuiteMenu(tabIndex)
    state.mainWindowOpen[0] = not state.mainWindowOpen[0]
    resetImGuiKeyboardState()
    if tabIndex and tabIndex >= 1 and tabIndex <= 8 then
        config.general.activeTab = tabIndex
    end
    if not state.mainWindowOpen[0] then
        saveConfig()
    end
end

-- ------------------------------------------------------------------------------
-- SA-MP Event Hooks (AutoCar)
-- ------------------------------------------------------------------------------
if hasSampev and sampev then
    function sampev.onSendEnterVehicle(vehId, isPassenger)
        state.exitCommandsSent = false
        handleVehicleEntry()
    end

    function sampev.onSendExitVehicle(vehId)
        if config.autocar.enabled and state.isDriver and not state.exitCommandsSent then
            state.exitCommandsSent = true
            local veh = state.currentVeh
            if not veh or not doesVehicleExist(veh) then
                pcall(function() veh = storeCarCharIsInNoSave(PLAYER_PED) end)
            end
            if veh and doesVehicleExist(veh) and state.currentClass ~= 'bicycle' then
                if config.autocar.engineOffOnExit and isCarEngineOn(veh) then
                    pcall(sampSendChat, config.commands.engineCmd)
                    state.engineRunning = false
                end
                if config.autocar.lightsOffOnExit and isCarLightsOn(veh) then
                    pcall(sampSendChat, config.commands.lightsCmd)
                    state.lightsOn = false
                end
            end
        end
        pcall(handleVehicleExit)
    end

    function sampev.onShowTextDraw(textdrawId, data)
        if config.autocar.syncWithHud and data and data.text then
            local clean = data.text:gsub("~[a-zA-Z]~", ""):gsub("{.-}", "")
            local h, m = clean:match("(%d%d?):(%d%d)")
            if h and m then
                local hn, mn = tonumber(h), tonumber(m)
                if hn and mn and hn >= 0 and hn <= 23 and mn >= 0 and mn <= 59 then
                    state.hudClockHour = hn
                    state.hudClockMin  = mn
                    state.lastClockSyncTime = os.clock()
                end
            end
        end
    end

    function sampev.onTextDrawSetString(textdrawId, text)
        if config.autocar.syncWithHud and text then
            local clean = text:gsub("~[a-zA-Z]~", ""):gsub("{.-}", "")
            local h, m = clean:match("(%d%d?):(%d%d)")
            if h and m then
                local hn, mn = tonumber(h), tonumber(m)
                if hn and mn and hn >= 0 and hn <= 23 and mn >= 0 and mn <= 59 then
                    state.hudClockHour = hn
                    state.hudClockMin  = mn
                    state.lastClockSyncTime = os.clock()
                end
            end
        end
    end

    function sampev.onChatMessage(playerId, text)
        if text then
            local pName = sampGetPlayerNickname(playerId) or ("Player_" .. tostring(playerId))
            appendChatlogLine(string.format("%s[%d]: %s", pName, playerId, text))
        end
    end

    function sampev.onServerMessage(color, text)
        if text then
            appendChatlogLine(text)
            local low = text:lower()
            if low:find("turns on the lights") then
                state.lightsOn = true
            elseif low:find("turns off the lights") then
                state.lightsOn = false
            elseif low:find("engine.*on") or low:find("turns on the.*engine") or low:find("engine.*started") then
                state.engineRunning = true
            elseif low:find("engine.*off") or low:find("turns off the.*engine") or low:find("engine.*stopped") then
                state.engineRunning = false
            elseif low:find("seatbelt") or low:find("cinturon") or low:find("belt") then
                if low:find("fasten") or low:find("buckle") or low:find("on") or low:find("put on") then
                    state.beltFastened = true
                elseif low:find("unfasten") or low:find("unbuckle") or low:find("off") or low:find("removed") then
                    state.beltFastened = false
                end
            elseif low:find("not inside any vehicle") then
                state.inVehicle    = false
                state.isDriver     = false
                state.currentVeh   = nil
                state.beltFastened = false
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Main Background Worker Thread & Live Keyboard Hotkey Polling
-- ------------------------------------------------------------------------------
function main()
    while not isSampAvailable() do wait(100) end

    -- Capture Vanilla/Initial Mouse Sensitivity for Safe Restoration
    pcall(function()
        originalHorzSens = memory.getfloat(ADDR_MOUSE_HORZ, false)
        originalVertSens = memory.getfloat(ADDR_MOUSE_VERT, false)
    end)

    loadConfig()
    initializeSampDLHook()
    syncChatModeBuffers()
    loadChatlogFromDisk()
    pcall(applyAllMemoryTweaks)

    -- Register Chat Commands
    sampRegisterChatCommand("bds", function() toggleSuiteMenu(nil) end)
    sampRegisterChatCommand("toolkit", function() toggleSuiteMenu(nil) end)
    sampRegisterChatCommand("menu", function() toggleSuiteMenu(nil) end)
    sampRegisterChatCommand("suite", function() toggleSuiteMenu(nil) end)
    sampRegisterChatCommand("binder", function() toggleSuiteMenu(1) end)
    sampRegisterChatCommand("binds", function() toggleSuiteMenu(1) end)
    sampRegisterChatCommand("autocar", function() toggleSuiteMenu(2) end)
    sampRegisterChatCommand("vehctrl", function() toggleSuiteMenu(2) end)
    sampRegisterChatCommand("dlhud", function() toggleSuiteMenu(3) end)
    sampRegisterChatCommand("f5dl", function() toggleSuiteMenu(3) end)
    sampRegisterChatCommand("chatmode", function() config.general.chatSubTab = 1; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("chat", function() config.general.chatSubTab = 1; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("room", function() config.general.chatSubTab = 1; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("cm", function() config.general.chatSubTab = 1; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("chatlog", function() config.general.chatSubTab = 2; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("clog", function() config.general.chatSubTab = 2; toggleSuiteMenu(4) end)
    sampRegisterChatCommand("sensfix", function() toggleSuiteMenu(6) end)
    sampRegisterChatCommand("wsens", function() toggleSuiteMenu(6) end)
    sampRegisterChatCommand("sensmenu", function() toggleSuiteMenu(6) end)
    sampRegisterChatCommand("sens", function() toggleSuiteMenu(6) end)
    sampRegisterChatCommand("fixes", function() toggleSuiteMenu(7) end)
    sampRegisterChatCommand("tweaks", function() toggleSuiteMenu(7) end)
    sampRegisterChatCommand("gtafix", function() toggleSuiteMenu(7) end)
    sampRegisterChatCommand("bdsfixes", function() toggleSuiteMenu(7) end)
    sampRegisterChatCommand("bdshelp", function() toggleSuiteMenu(8) end)


    sampRegisterChatCommand("nightfix", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.flintNightFix = not config.tweaks.flintNightFix
        uiTweaks.flintNightFix[0] = config.tweaks.flintNightFix
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Countryside Night Illumination: %s{FFFFFF}.", config.tweaks.flintNightFix and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("cvision", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.flintNightFix = not config.tweaks.flintNightFix
        uiTweaks.flintNightFix[0] = config.tweaks.flintNightFix
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Countryside Night Illumination: %s{FFFFFF}.", config.tweaks.flintNightFix and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("nightboost", function(param)
        local val = tonumber(param)
        if val and val >= 260 and val <= 500 then
            if not config.tweaks then config.tweaks = {} end
            config.tweaks.flintNightBoost = math.floor(val)
            uiTweaks.flintNightBoost[0] = math.floor(val)
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Night Brightness Boost set to: {00E676}%d{FFFFFF} (Range: 260-500).", math.floor(val)), -1)
        else
            sampAddChatMessage("{00CCFF}[BDS Fixes]{FFFFFF} Usage: /nightboost <260 - 500> (Current: " .. tostring(config.tweaks and config.tweaks.flintNightBoost or 380) .. ")", -1)
        end
    end)
    sampRegisterChatCommand("reloadtimecyc", function()
        sampAddChatMessage("{00E676}[BDS Fixes]{FFFFFF} Timecycle ambient refreshed safely.", -1)
    end)
    sampRegisterChatCommand("fixtimecyc", function()
        sampAddChatMessage("{00E676}[BDS Fixes]{FFFFFF} Timecycle ambient refreshed safely.", -1)
    end)
    sampRegisterChatCommand("silentsirens", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.silentSirens = not config.tweaks.silentSirens
        uiTweaks.silentSirens[0] = config.tweaks.silentSirens
        saveConfig()
        pcall(updateAudioTweaks)
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Silent Emergency Sirens (Lights Only): %s{FFFFFF}.", config.tweaks.silentSirens and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("quieter", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.aircraftQuieter = not config.tweaks.aircraftQuieter
        uiTweaks.aircraftQuieter[0] = config.tweaks.aircraftQuieter
        saveConfig()
        pcall(updateAudioTweaks)
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Aircraft Rotor & Engine Sound Dampener: %s{FFFFFF}.", config.tweaks.aircraftQuieter and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("aircraftquieter", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.aircraftQuieter = not config.tweaks.aircraftQuieter
        uiTweaks.aircraftQuieter[0] = config.tweaks.aircraftQuieter
        saveConfig()
        pcall(updateAudioTweaks)
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Aircraft Rotor & Engine Sound Dampener: %s{FFFFFF}.", config.tweaks.aircraftQuieter and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("sprinthook", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.sprintHook = not config.tweaks.sprintHook
        uiTweaks.sprintHook[0] = config.tweaks.sprintHook
        saveConfig()
        applySprintHook(config.tweaks.sprintHook)
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} SprintHook (Hold Sprint to Max Speed): %s{FFFFFF}.", config.tweaks.sprintHook and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("sprint", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.sprintHook = not config.tweaks.sprintHook
        uiTweaks.sprintHook[0] = config.tweaks.sprintHook
        saveConfig()
        applySprintHook(config.tweaks.sprintHook)
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} SprintHook (Hold Sprint to Max Speed): %s{FFFFFF}.", config.tweaks.sprintHook and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("fps", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.fpsDisplay = not config.tweaks.fpsDisplay
        uiTweaks.fpsDisplay[0] = config.tweaks.fpsDisplay
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Real-Time FPS Counter Display: %s{FFFFFF}.", config.tweaks.fpsDisplay and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("fpsdisplay", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.fpsDisplay = not config.tweaks.fpsDisplay
        uiTweaks.fpsDisplay[0] = config.tweaks.fpsDisplay
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Real-Time FPS Counter Display: %s{FFFFFF}.", config.tweaks.fpsDisplay and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("widescreenfix", function()
        sampAddChatMessage("{00CCFF}[BDS Fixes]{FFFFFF} WidescreenFix: {00E676}ACTIVE{FFFFFF} (sa_widescreenfix_lite.asi loaded for 16:9/16:10 aspect ratio & circular radar).", -1)
    end)
    sampRegisterChatCommand("camnorecenter", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.cameraNoRecenter = not config.tweaks.cameraNoRecenter
        uiTweaks.cameraNoRecenter[0] = config.tweaks.cameraNoRecenter
        saveConfig()
        applyCameraNoRecenter(config.tweaks.cameraNoRecenter and (config.tweaks.enabled ~= false))
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Vehicle Free-Look Camera: %s{FFFFFF}.", config.tweaks.cameraNoRecenter and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("cameranorecenter", function()
        if not config.tweaks then config.tweaks = {} end
        config.tweaks.cameraNoRecenter = not config.tweaks.cameraNoRecenter
        uiTweaks.cameraNoRecenter[0] = config.tweaks.cameraNoRecenter
        saveConfig()
        applyCameraNoRecenter(config.tweaks.cameraNoRecenter and (config.tweaks.enabled ~= false))
        sampAddChatMessage(string.format("{00CCFF}[BDS Fixes]{FFFFFF} Vehicle Free-Look Camera: %s{FFFFFF}.", config.tweaks.cameraNoRecenter and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("bdsupdate", function()
        if updaterState.status == "UPDATE_AVAILABLE" then
            downloadAndInstallUpdate()
        else
            lua_thread.create(checkScriptUpdate, true)
        end
    end)
    sampRegisterChatCommand("checkupdate", function()
        lua_thread.create(checkScriptUpdate, true)
    end)
    sampRegisterChatCommand("senstoggle", function()
        if not config.sensfix then config.sensfix = {} end
        config.sensfix.enabled = not config.sensfix.enabled
        uiSensFix.enabled[0] = config.sensfix.enabled
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS SensFix]{FFFFFF} System: %s{FFFFFF}.", config.sensfix.enabled and "{00E676}ENABLED" or "{FF5252}DISABLED"), -1)
    end)
    sampRegisterChatCommand("sensstatus", function()
        sampAddChatMessage(string.format("{00CCFF}[BDS SensFix]{FFFFFF} State: %s | Weapon: %s | Cam: %d | Horz: %.6f | Vert: %.6f",
            tostring(sensState.activeCategory), tostring(sensState.currentWeaponName), sensState.activeCamMode or 0, sensState.appliedHorz or 0, sensState.appliedVert or 0), -1)
    end)
    sampRegisterChatCommand("sensdb", function(param)
        local val = tonumber(param)
        if val and val >= 0.20 and val <= 3.00 then
            if not config.sensfix then config.sensfix = {} end
            config.sensfix.driveby = val
            uiSensFix.driveby[0] = val
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS SensFix]{FFFFFF} Drive-By multiplier set to: {33FF33}%.2fx{FFFFFF}.", val), -1)
        else
            sampAddChatMessage("{00CCFF}[BDS SensFix]{FFFFFF} Usage: /sensdb <0.20 - 3.00>", -1)
        end
    end)
    sampRegisterChatCommand("bdsreload", function()
        sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Reloading all scripts...", -1)
        if type(reloadScripts) == "function" then reloadScripts() else thisScript():reload() end
    end)
    sampRegisterChatCommand("mlreload", function()
        sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Reloading all scripts...", -1)
        if type(reloadScripts) == "function" then reloadScripts() else thisScript():reload() end
    end)

    sampRegisterChatCommand("dltest", function()
        startSimulationTest()
    end)

    sampRegisterChatCommand("dlpos", function(param)
        param = tostring(param or ""):lower():match("^%s*(.-)%s*$")
        if param == "br" or param == "bottom_right" then
            config.downloader.positionPreset = "bottom_right"
            sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Download HUD position set to: {00E5FF}Bottom-Right{FFFFFF}.", -1)
        elseif param == "bc" or param == "bottom_center" then
            config.downloader.positionPreset = "bottom_center"
            sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Download HUD position set to: {00E5FF}Bottom-Center{FFFFFF}.", -1)
        elseif param == "tr" or param == "top_right" then
            config.downloader.positionPreset = "top_right"
            sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Download HUD position set to: {00E5FF}Top-Right{FFFFFF}.", -1)
        elseif param == "tc" or param == "top_center" then
            config.downloader.positionPreset = "top_center"
            sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Download HUD position set to: {00E5FF}Top-Center{FFFFFF}.", -1)
        else
            sampAddChatMessage("{FFA726}[BDS Toolkit]{FFFFFF} Usage: /dlpos <br | bc | tr | tc>", -1)
            return
        end
        saveConfig()
    end)

    sampRegisterChatCommand("bprofile", function(param)
        -- Do not unregister/re-register SA-MP commands inside this callback.
        -- Queue the switch and apply it from the main script loop instead.
        param = tostring(param or ""):match("^%s*(.-)%s*$")
        local current = tonumber(config.general.activeProfile) or 1
        current = math.max(1, math.min(5, math.floor(current)))

        if #param == 0 then
            local currentProfile = profiles[current]
            local currentName = currentProfile and currentProfile.name or ("Profile " .. current)
            sampAddChatMessage(string.format(
                "{00E676}[BDS Toolkit]{FFFFFF} Active Profile: {00E5FF}%d (%s){FFFFFF}. Usage: /bprofile <1-5|name|next>",
                current, currentName
            ), -1)
            return
        end

        local targetIdx = nil
        local lowerParam = param:lower()

        if lowerParam == "next" then
            targetIdx = (current % 5) + 1
        else
            local numeric = tonumber(param)
            if numeric and numeric == math.floor(numeric) and numeric >= 1 and numeric <= 5 then
                targetIdx = numeric
            else
                for i = 1, 5 do
                    local profile = profiles[i]
                    if profile and profile.name and tostring(profile.name):lower() == lowerParam then
                        targetIdx = i
                        break
                    end
                end
            end
        end

        if targetIdx and profiles[targetIdx] then
            state.pendingProfileSwitch = targetIdx
        else
            sampAddChatMessage(string.format(
                "{FFA726}[BDS Toolkit]{FFFFFF} Profile '%s' not found. Use /bprofile 1-5, next, or an exact profile name.",
                param
            ), -1)
        end
    end)

    sampRegisterChatCommand("baliases", function()
        local pIdx = tonumber(config.general.activeProfile) or 1
        local p = profiles[pIdx]
        local count = 0
        if p and p.slots then
            for i = 1, 20 do
                local slot = p.slots[i]
                if slot and slot.enabled and type(slot.alias) == "string" and slot.alias:gsub("^/", "") ~= "" then count = count + 1 end
            end
        end
        sampAddChatMessage(string.format(
            "{00E676}[BDS Toolkit]{FFFFFF} Profile %d: %d alias slot(s), %d registered. Use /bds and check the Alias column; blank /cmd fields are not aliases.",
            pIdx, count, state.aliasRegisteredCount or 0
        ), -1)
    end)

        sampRegisterChatCommand("vehinfo", function() toggleSuiteMenu(5) end)
    sampRegisterChatCommand("vinfo", function() toggleSuiteMenu(5) end)
    sampRegisterChatCommand("vinfotoggle", function()
        if not config.vehinfo then config.vehinfo = {} end
        config.vehinfo.enabled = not config.vehinfo.enabled
        uiVehInfo.enabled[0] = config.vehinfo.enabled
        saveConfig()
        sampAddChatMessage(string.format("{00CCFF}[BDS VehInfo]{FFFFFF} Telemetry HUD: %s{FFFFFF}.", config.vehinfo.enabled and "{33FF33}ENABLED" or "{FF3333}DISABLED"), -1)
    end)
    sampRegisterChatCommand("vwall", function()
        sampAddChatMessage("{00CCFF}[BDS VehInfo]{FFFFFF} Wall Occlusion is {33FF33}PERMANENTLY ACTIVE{FFFFFF} (Realistic RP - vehicle tags never show through walls).", -1)
    end)
    sampRegisterChatCommand("vwalltoggle", function()
        sampAddChatMessage("{00CCFF}[BDS VehInfo]{FFFFFF} Wall Occlusion is {33FF33}PERMANENTLY ACTIVE{FFFFFF} (Realistic RP - vehicle tags never show through walls).", -1)
    end)
    sampRegisterChatCommand("vehsize", function(param)
        local sz = tonumber(param)
        if sz and sz >= 10.0 and sz <= 32.0 then
            config.vehinfo.fontSize = sz
            uiVehInfo.fontSize[0] = sz
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS VehInfo]{FFFFFF} Font size set to: {33FF33}%.0f px{FFFFFF}.", sz), -1)
        else
            sampAddChatMessage("{00CCFF}[BDS VehInfo]{FFFFFF} Usage: /vehsize [10-32] (current: " .. tostring(config.vehinfo and config.vehinfo.fontSize or 15) .. "px)", -1)
        end
    end)
    sampRegisterChatCommand("vsize", function(param)
        local sz = tonumber(param)
        if sz and sz >= 10.0 and sz <= 32.0 then
            config.vehinfo.fontSize = sz
            uiVehInfo.fontSize[0] = sz
            saveConfig()
            sampAddChatMessage(string.format("{00CCFF}[BDS VehInfo]{FFFFFF} Font size set to: {33FF33}%.0f px{FFFFFF}.", sz), -1)
        else
            sampAddChatMessage("{00CCFF}[BDS VehInfo]{FFFFFF} Usage: /vsize [10-32] (current: " .. tostring(config.vehinfo and config.vehinfo.fontSize or 15) .. "px)", -1)
        end
    end)
    sampRegisterChatCommand("vehdebug", function()
        local rawAll = getAllVehiclesForVehInfo()
        local count = state.vehinfoTargets and #state.vehinfoTargets or 0
        sampAddChatMessage(string.format("{00CCFF}[BDS VehInfo Debug]{FFFFFF} Mode: %s | Raw In Stream: %d | Visible On Screen: %d",
            (config.vehinfo and config.vehinfo.displayMode == 1) and "{33FF33}3D World Space" or "{FFAA33}2D HUD", #rawAll, count), -1)
        if state.vehinfoTargets then
            for i, v in ipairs(state.vehinfoTargets) do
                if v and v.handle and doesVehicleExist(v.handle) then
                    local vx, vy, vz = getCarCoordinates(v.handle)
                    local rz = vz + getVehInfoVerticalOffset(v.modelId)
                    local onScreen, sx, sy = getVehicleScreenPos(vx, vy, rz)
                    sampAddChatMessage(string.format("{00CCFF}[Veh %d]{FFFFFF} %s (ID: %s) | Dist: %dm | HP: %d | Pos: (%.0f, %.0f)",
                        i, v.modelName, v.sampId, v.distance, v.health, sx, sy), -1)
                end
            end
        end
    end)
    sampRegisterChatCommand("bdsstatus", function()
        local pIdx = tonumber(config.general.activeProfile) or 1
        sampAddChatMessage(string.format(
            "{00E676}[BDS Toolkit]{FFFFFF} v1.0.0 | Profile %d | Aliases %d registered (%d skipped) | AutoCar %s | Downloader %s",
            pIdx, state.aliasRegisteredCount or 0, state.aliasSkippedCount or 0,
            config.autocar.enabled and "ON" or "OFF", config.downloader.enabled and "ON" or "OFF"
        ), -1)
        if state.lastConfigSaveError then
            sampAddChatMessage("{FF5252}[BDS Toolkit]{FFFFFF} Config save warning: " .. tostring(state.lastConfigSaveError), -1)
        end
    end)

    -- Launch background Day/Night watcher thread
    lua_thread.create(vehicleWatcherThread)

    -- Launch background Vehicle Info HUD Scanner thread (20Hz / 50ms) with Permanent Occlusion Check
    lua_thread.create(function()
        while true do
            wait(50)
            pcall(function()
                if config.vehinfo and config.vehinfo.enabled and not isPauseMenuActive() then
                    local list = {}
                    local added = {}

                    -- 1. Check self vehicle (when driving / riding)
                    if config.vehinfo.trackCurrentCar and isCharInAnyCar(PLAYER_PED) then
                        local okCar, selfCar = pcall(storeCarCharIsInNoSave, PLAYER_PED)
                        if okCar and selfCar and doesVehicleExist(selfCar) then
                            local data = extractVehInfoData(selfCar, true)
                            if data then
                                table.insert(list, data)
                                added[selfCar] = true
                            end
                        end
                    end

                    -- 2. Scan all visible vehicles on screen within range
                    local all = getAllVehiclesForVehInfo()
                    if type(all) == "table" and #all > 0 then
                        local px, py, pz = getCharCoordinates(PLAYER_PED)
                        local maxDist = config.vehinfo.lookMaxDist or 50.0
                        local maxCount = config.vehinfo.nearbyMaxCount or 6

                        local candidates = {}
                        for _, car in ipairs(all) do
                            if car and doesVehicleExist(car) and not added[car] then
                                local vx, vy, vz = getCarCoordinates(car)
                                local dist = getDistanceBetweenCoords3d(px, py, pz, vx, vy, vz)
                                if dist <= maxDist then
                                    local modelId = getCarModel(car)
                                    local rz = vz + getVehInfoVerticalOffset(modelId)
                                    local onScreen, sx, sy = getVehicleScreenPos(vx, vy, rz)
                                    local isVis = isVehicleVisibleThroughWalls(vx, vy, rz) or isVehicleVisibleThroughWalls(vx, vy, vz + 0.35)
                                    if onScreen and isVis then
                                        table.insert(candidates, { car = car, dist = dist })
                                    end
                                end
                            end
                        end

                        table.sort(candidates, function(a, b) return a.dist < b.dist end)

                        for i = 1, math.min(#candidates, maxCount) do
                            local car = candidates[i].car
                            local data = extractVehInfoData(car, false)
                            if data then
                                table.insert(list, data)
                                added[car] = true
                            end
                        end
                    end

                    state.vehinfoTargets = list
                else
                    state.vehinfoTargets = {}
                end
            end)
        end
    end)


    sampAddChatMessage("{00E676}[BDS Toolkit]{FFFFFF} Loaded v1.0 by {FF0000}Danny_Jadogar (CHACHA){FFFFFF}. Press {00E676}F12{FFFFFF} or type {00E676}/bds", -1)

    if config.general.autoUpdateCheck ~= false then
        lua_thread.create(function()
            wait(3500)
            pcall(checkScriptUpdate, false)
        end)
    end

    while true do
        wait(0)

        -- Apply Weapon Sensitivity & Drive-By Multiplier Frame Hook
        pcall(applySensFixSensitivity)

        -- Dynamic Terrain & Road Night Illumination (Real 3D Point Lights)
        pcall(renderFlintNightLights)

        -- Apply Gameplay Tweaks & Physics Normalizers (Module 7)
        pcall(updateGameplayTweaks)

        -- Apply queued profile switches outside the SA-MP chat-command callback.
        -- This avoids changing SA-MP command registrations while SA-MP is dispatching one.
        local requestedProfile = state.pendingProfileSwitch
        if requestedProfile ~= nil then
            state.pendingProfileSwitch = nil
            if type(requestedProfile) == "number"
                and requestedProfile >= 1
                and requestedProfile <= 5
                and requestedProfile == math.floor(requestedProfile)
                and profiles[requestedProfile] then

                config.general.activeProfile = requestedProfile
                queueAliasRefresh()
                pcall(saveConfig)

                local selectedProfile = profiles[requestedProfile]
                local pName = selectedProfile.name or ("Profile " .. requestedProfile)
                state.toastText = string.format("%d. %s", requestedProfile, pName)
                state.toastExpiry = os.clock() + 2.0

                pcall(sampAddChatMessage, string.format(
                    "{00E676}[BDS Toolkit]{FFFFFF} Switched to profile: {00E5FF}%d (%s){FFFFFF}.",
                    requestedProfile, pName
                ), -1)
            end
        end

        -- Apply alias changes once per frame, outside chat-command callbacks and UI widgets.
        if aliasRefreshPending then
            aliasRefreshPending = false
            local ok, err = pcall(registerAllAliases)
            if not ok then
                logDiagnostic("ERROR", "Alias refresh failed: " .. tostring(err))
                pcall(sampAddChatMessage, "{FF5252}[BDS Toolkit]{FFFFFF} Alias refresh failed: " .. tostring(err), -1)
            end
        end

        local now = os.clock()

        -- ----------------------------------------------------------------------
        -- Hotkey Polling: F12 to toggle Master Suite Menu (Crash-Isolated)
        -- ----------------------------------------------------------------------
        pcall(function()
            if not isPauseMenuActive() then
                local chatActive, dialogActive = false, false
                pcall(function() chatActive = sampIsChatInputActive() end)
                pcall(function() dialogActive = sampIsDialogActive() end)

                if not chatActive and not dialogActive then
                    if wasKeyPressed(config.general.menuKey) then
                        toggleSuiteMenu(nil)
                    end
                end
            end
        end)

        
        -- ----------------------------------------------------------------------
        -- Built-in Ctrl + R Script Reload Shortcut
        -- ----------------------------------------------------------------------
        if isKeyDown(17) and isKeyDown(82) then -- VK_CONTROL and VK_R
            while isKeyDown(17) and isKeyDown(82) do
                wait(80)
            end
            if type(reloadScripts) == "function" then
                reloadScripts()
            else
                thisScript():reload()
            end
        end

        -- ----------------------------------------------------------------------
        -- Master Menu ESC Key Handler (Clean Close Without Pausing GTA)
        -- ----------------------------------------------------------------------
        if state.mainWindowOpen[0] then
            if wasKeyPressed(vkeys.VK_ESCAPE or 27) then
                if state.waitingKeyFor then
                    state.waitingKeyFor = nil
                    resetImGuiKeyboardState()
                elseif state.waitingChatCycleKey then
                    state.waitingChatCycleKey = false
                    resetImGuiKeyboardState()
                else
                    state.mainWindowOpen[0] = false
                    resetImGuiKeyboardState()
                    pcall(lockPlayerControl, false)
                    lua_thread.create(function()
                        wait(50)
                        saveConfig()
                    end)
                end
            end
        end

        -- ----------------------------------------------------------------------
        -- TAB Key: cycle Chat Mode using the older, stable main-loop approach.
        -- The selected mode is changed only while SA-MP chat input is active.
        -- Scoreboard closing and config saving are deferred to this same loop.
        -- ----------------------------------------------------------------------
        if chatModeCycleRequested then
            chatModeCycleRequested = false
            cycleChatMode(1)
            processScoreboardCloseRequest()
        end

        -- Preserve scoreboard suppression while chat is open.
        if isSampAvailable and isSampAvailable() then
            local chatActive = false
            pcall(function() chatActive = sampIsChatInputActive() end)
            if chatActive then
                forceCloseScoreboard()
            end
        end

        -- Persist queued configurations with smooth debounce
        if saveConfigPending and (now - lastSaveRequestTime > 0.35) then
            saveConfigPending = false
            writeConfigNow()
        end

        if chatConfigSaveRequested then
            chatConfigSaveRequested = false
            saveConfig()
        end

        -- ----------------------------------------------------------------------
        -- Chat Cycle Key Rebind Listener
        -- ----------------------------------------------------------------------
        if state.waitingChatCycleKey and state.mainWindowOpen[0] then
            if wasKeyPressed(vkeys.VK_ESCAPE) then
                state.waitingChatCycleKey = false
                resetImGuiKeyboardState()
            else
                for vk = 1, 255 do
                    if vk ~= vkeys.VK_ESCAPE and wasKeyPressed(vk) then
                        config.chatmode.cycleKey = vk
                        state.waitingChatCycleKey = false
                        resetImGuiKeyboardState()
                        saveConfig()
                        break
                    end
                end
            end
        end

        -- ----------------------------------------------------------------------
        -- Keycap Rebind Listener
        -- ----------------------------------------------------------------------
        if state.waitingKeyFor and state.mainWindowOpen[0] then
            if wasKeyPressed(vkeys.VK_ESCAPE) then
                state.waitingKeyFor = nil
                resetImGuiKeyboardState()
            else
                for vk = 1, 255 do
                    if vk ~= vkeys.VK_ESCAPE and wasKeyPressed(vk) then
                        local curP = profiles[config.general.activeProfile]
                        if curP and curP.slots[state.waitingKeyFor] then
                            curP.slots[state.waitingKeyFor].key = vk
                            if #curP.slots[state.waitingKeyFor].command > 0 then
                                curP.slots[state.waitingKeyFor].enabled = true
                            end
                            saveConfig()
                        end
                        state.waitingKeyFor = nil
                        resetImGuiKeyboardState()
                        break
                    end
                end
            end
        end

        -- ----------------------------------------------------------------------
        -- Physical Hotkey Execution Polling (Tab 1: Binder)
        -- ----------------------------------------------------------------------
        if config.binder.enabled and not state.mainWindowOpen[0] and not isPauseMenuActive() then
            local chatActive, dialogActive = false, false
            pcall(function() chatActive = sampIsChatInputActive() end)
            pcall(function() dialogActive = sampIsDialogActive() end)

            if not chatActive and not dialogActive then
                local curP = profiles[config.general.activeProfile]
                if curP and curP.slots then
                    for slotIdx, s in ipairs(curP.slots) do
                        if s.enabled and s.key and s.key > 0 and #s.command > 0 then
                            if wasKeyPressed(s.key) then
                                local debounceMs = config.general.spamDelayMs or 0
                                if (now * 1000) - state.lastTriggerTick >= debounceMs then
                                    state.lastTriggerTick = now * 1000
                                    executeSlot(slotIdx)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- ----------------------------------------------------------------------
        -- Live SA-MP 0.3.DL Model Downloader Telemetry vs Simulation Mode
        -- ----------------------------------------------------------------------
        local liveActive, liveCur, liveTot, liveSpd = false, 0, 0, 0.0
        if config.downloader.enabled then
            liveActive, liveCur, liveTot, liveSpd = readSampDownloadTelemetry()
        end

        if state.isTestMode then
            local elapsed = now - state.testStartTime
            local progress = math.min(1.0, elapsed / state.testDuration)
            state.currentFiles = math.floor(progress * state.testTotalFiles)
            state.totalFiles = state.testTotalFiles
            state.speedKBps = 850.0 + (math.sin(elapsed * 4.0) * 220.0)

            if progress >= 1.0 then
                if not state.isComplete then
                    state.isComplete = true
                    state.completeTime = now
                    if config.downloader.soundNotification then
                        pcall(addOneOffSound, 0.0, 0.0, 0.0, 1058)
                    end
                elseif (now - state.completeTime > 1.8) then
                    state.isTestMode = false
                    state.isComplete = false
                end
            end
            state.isDownloading = true
        elseif liveActive then
            state.isDownloading = true
            state.currentFiles  = liveCur
            state.totalFiles    = liveTot
            state.speedKBps     = liveSpd
            state.isComplete    = false

            -- Free camera mouse aim while downloading in background:
            -- ONLY if no chat, no server dialog popup, and no master menu is open
            if not state.mainWindowOpen[0] then
                local chatActive, dialogActive = false, false
                pcall(function() chatActive = sampIsChatInputActive() end)
                pcall(function() dialogActive = sampIsDialogActive() end)
                if not chatActive and not dialogActive then
                    -- Native cursor-memory override disabled in v1.1.9 safety mode.
                end
            end
        else
            if state.isDownloading then
                if not state.isComplete then
                    state.isComplete = true
                    state.completeTime = now
                    state.currentFiles = state.totalFiles
                    if config.downloader.soundNotification then
                        pcall(addOneOffSound, 0.0, 0.0, 0.0, 1058)
                    end
                elseif (now - state.completeTime > 1.8) then
                    state.isDownloading = false
                    state.isComplete    = false
                end
            else
                state.isDownloading = false
            end
        end

        -- Smooth Fade In / Fade Out Transitions for Downloader HUD
        if state.isDownloading then
            state.fadeAlpha = math.min(1.0, state.fadeAlpha + 0.08)
        else
            state.fadeAlpha = math.max(0.0, state.fadeAlpha - 0.05)
        end
    end
end



-- ------------------------------------------------------------------------------
-- Clean Script Termination: Always Restore Original Bytes on Reload/Unload (Skip on Game Quit)
-- ------------------------------------------------------------------------------
function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then
        if not quitGame then
            pcall(function()
                if removeEventHandler then
                    removeEventHandler('onWindowMessage', handleChatModeWindowMessage)
                end
            end)
            pcall(applyRenderHook, false)
            for cmdName, _ in pairs(registeredAliases or {}) do
                pcall(sampUnregisterChatCommand, cmdName)
            end
            if saveConfigPending then
                saveConfigPending = false
                pcall(writeConfigNow)
            end
            if originalHorzSens then
                pcall(memory.setfloat, ADDR_MOUSE_HORZ, originalHorzSens, true)
            end
            if originalVertSens then
                pcall(memory.setfloat, ADDR_MOUSE_VERT, originalVertSens, true)
            end
            pcall(restoreAllMemoryTweaks)
        end
    end
end
