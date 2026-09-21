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

    if cmd == "situations" then
        if C_TransmogOutfitInfo then
            local situationsData = C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions()
            if situationsData then
                for index, data in ipairs(situationsData) do
                    local situationData = {
                        triggerID = data.triggerID,
                        name = data.name,
                        description = data.description,
                        isRadioButton = data.isRadioButton,
                        groupData = data.groupData
                    }

                    print("Situation Data:", situationData.triggerID, situationData.name)
                end
            end

            local situationsEnabled = C_TransmogOutfitInfo.GetOutfitSituationsEnabled()
            if situationsEnabled then
                for triggerID, enabled in pairs(situationsEnabled) do
                    print("Situation Enabled:", triggerID, enabled)
                end
            end
        end
    end

    if cmd == "help" then
        Print("Commands:")
        Print("  /bs           - Display current environment trigger values")
        Print("  /bs list      - Display configured trigger options for viewed outfit")
        Print("  /bs help      - Show this help message")
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

        if ns.Diagnostics then
            ns.Diagnostics:Init(BetterSituation)
        end

        if ns.SituationPanel then
            ns.SituationPanel:Init(BetterSituation)
        end

        if BetterSituationDB.debug then
            Print("Loaded " .. addonName)
        end
    end
)
