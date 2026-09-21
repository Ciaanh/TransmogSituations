local addonName, ns = ...

BetterSituationDB = BetterSituationDB or {}

local BetterSituation = {}
ns.BetterSituation = BetterSituation
BetterSituation.db = BetterSituationDB

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BetterSituation|r: " .. tostring(msg))
end

BetterSituation.Print = function(_, msg)
    Print(msg)
end

local function EnsureDefaults()
    if BetterSituationDB.debug == nil then
        BetterSituationDB.debug = false
    end

    BetterSituation.db = BetterSituationDB
end

local function HandleSlashCommand(input)
    local cmd = (input or ""):match("^%s*(%S*)")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        ns.Diagnostics:PrintEnvironmentSnapshot()
        return
    end

    if cmd == "list" then
        ns.Diagnostics:PrintCategoriesList()
        return
    end

    if cmd == "dump" then
        ns.Diagnostics:PrintRawDump()
        return
    end

    if cmd == "panel" then
        ns.StatusPanel:Toggle()
        return
    end

    if cmd == "eligible" then
        ns.Diagnostics:PrintEligible()
        return
    end

    if cmd == "verify" then
        ns.Diagnostics:PrintVerify()
        return
    end

    if cmd == "scan" then
        ns.OutfitCache:Scan()
        return
    end

    if cmd == "debug" then
        BetterSituationDB.debug = not BetterSituationDB.debug
        Print("Debug output " .. (BetterSituationDB.debug and "enabled" or "disabled"))
        return
    end

    if cmd == "help" then
        Print("Commands:")
        Print("  /bs          - Current value of every situation trigger")
        Print("  /bs panel    - Toggle the standalone panel")
        Print("  /bs eligible - Outfits matching the current situation")
        Print("  /bs verify   - Compare our prediction against the outfit Blizzard applied")
        Print("  /bs scan     - Record every outfit's situations (transmog window must be open)")
        Print("  /bs list     - Trigger options for the viewed outfit, with the live value marked")
        Print("  /bs dump     - Raw option IDs and player state, for diagnosing mismatches")
        Print("  /bs debug    - Toggle extra output")
        Print("  /bs help     - This message")
        return
    end

    Print("Unknown command. Use /bs help")
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
        ns.Triggers:Init(BetterSituation)
        ns.OutfitCache:Init(BetterSituation)
        ns.Eligibility:Init(BetterSituation)
        ns.Diagnostics:Init(BetterSituation)
        ns.StatusPanel:Init(BetterSituation)
        ns.SituationPanel:Init(BetterSituation)

        if BetterSituationDB.debug then
            Print(
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
