local addonName, ns = ...

-- SavedVariables are loaded after this file runs and before ADDON_LOADED, so the table assigned
-- here is only a placeholder; the bootstrap below re-reads the global.
BetterSituationDB = BetterSituationDB or {}

local BetterSituation = {}
ns.BetterSituation = BetterSituation
BetterSituation.db = BetterSituationDB

-- The addon's only way to write to chat.
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BetterSituation|r: " .. tostring(msg))
end

local function EnsureDefaults()
    if BetterSituationDB.debug == nil then
        BetterSituationDB.debug = false
    end

    BetterSituation.db = BetterSituationDB
end

-- One table drives both the dispatch and /bs help, so the two cannot drift apart.
local COMMANDS
COMMANDS = {
    { "", "Current value of every situation trigger", function() ns.Diagnostics:PrintEnvironmentSnapshot() end },
    { "panel", "Toggle the standalone panel", function() ns.StatusPanel:Toggle() end },
    { "eligible", "Outfits matching the current situation", function() ns.Diagnostics:PrintEligible() end },
    { "verify", "Check the outfit Blizzard applied is one of the eligible ones", function() ns.Diagnostics:PrintVerify() end },
    { "scan", "Record every outfit's situations (transmog window must be open)", function() ns.OutfitCache:Scan() end },
    { "list", "Trigger options for the viewed outfit, with the live value marked", function() ns.Diagnostics:PrintCategoriesList() end },
    { "dump", "Raw option IDs and player state, for diagnosing mismatches", function() ns.Diagnostics:PrintRawDump() end },
    {
        "debug",
        "Toggle extra output",
        function()
            BetterSituationDB.debug = not BetterSituationDB.debug
            ns.Print("Debug output " .. (BetterSituationDB.debug and "enabled" or "disabled"))
        end
    },
    {
        "help",
        "This message",
        function()
            ns.Print("Commands:")
            for _, command in ipairs(COMMANDS) do
                ns.Print(string.format("  /bs %-9s - %s", command[1], command[2]))
            end
        end
    }
}

local function HandleSlashCommand(input)
    local cmd = ((input or ""):match("^%s*(%S*)") or ""):lower()

    for _, command in ipairs(COMMANDS) do
        if command[1] == cmd then
            command[3]()
            return
        end
    end

    ns.Print("Unknown command. Use /bs help")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript(
    "OnEvent",
    function(_, event, loadedAddon)
        if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
            return
        end

        EnsureDefaults()

        SLASH_BETTERSITUATION1 = "/bs"
        SLASH_BETTERSITUATION2 = "/bettersituation"
        SlashCmdList.BETTERSITUATION = HandleSlashCommand

        -- Capabilities first: every other module asks it what this client supports.
        ns.Capabilities:Init()
        ns.Triggers:Init()
        ns.OutfitCache:Init()
        ns.StatusPanel:Init()
        ns.SituationPanel:Init()

        if BetterSituationDB.debug then
            ns.Print(
                string.format(
                    "Loaded %s (situations=%s, weather=%s)",
                    addonName,
                    tostring(ns.Capabilities.hasSituations),
                    tostring(ns.Capabilities.hasWeather)
                )
            )
        end
    end
)
