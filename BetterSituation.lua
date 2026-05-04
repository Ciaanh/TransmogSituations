local addonName, ns = ...

BetterSituationDB = BetterSituationDB or {}
BetterSituationCharDB = BetterSituationCharDB or {}

local BetterSituation = {}
ns.BetterSituation = BetterSituation

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BetterSituation|r: " .. tostring(msg))
end

local function HandleSlashCommand(input)
    local cmd = (input or ""):lower():match("^%s*(.-)%s*$")

    if cmd == "" or cmd == "help" then
        Print("Commands: /bs, /bettersituation, /bs help")
        Print("Bootstrap build active. Diagnostics modules will be added next.")
        return
    end

    if cmd == "version" then
        Print("Version 0.1.0")
        return
    end

    Print("Unknown command. Use /bs help")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
        return
    end

    SLASH_BETTERSITUATION1 = "/bs"
    SLASH_BETTERSITUATION2 = "/bettersituation"
    SlashCmdList.BETTERSITUATION = HandleSlashCommand

    if BetterSituationDB.debug then
        Print("Loaded " .. addonName)
    end
end)
