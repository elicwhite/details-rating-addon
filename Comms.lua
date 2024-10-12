-- Copied and modified with much appreciation from
-- https://github.com/Tercioo/Open-Raid-Library/tree/main
-- The intent of this file is to test and validate the sending and
-- collection of player dungeon rating scores. 
-- Hopefully this code can be upstreamed back into LibOpenRaid

-- I originally considered trying to depend on this addon
-- and add comms channels to it, but I decided that I didn't
-- want to take a potential future message prefix which would
-- cause compatibility issues in the future.
-- Instead, duplicating this code lets me modify the addon chat channel
-- to avoid conflicts.

--[=[

Please refer to the docs.txt within this file folder for a guide on how to use this library.
If you get lost on implementing the lib, be free to contact Tercio on Details! discord: https://discord.gg/AGSzAZX or email to terciob@gmail.com
--PLAYER_AVG_ITEM_LEVEL_UPDATE
UnitID:
    UnitID use: "player", "target", "raid18", "party3", etc...
    If passing the unit name, use GetUnitName(unitId, true) or Ambiguate(playerName, 'none')

Code Rules:
    - When a function or variable name refers to 'Player', it indicates the local player.
    - When 'Unit' is use instead, it indicates any entity.
    - Internal callbacks are the internal communication of the library, e.g. when an event triggers it send to all modules that registered that event.
    - Public callbacks are callbacks registered by an external addon.

TODO:
    - add into gear info how many tier set parts the player has
    - raid lockouts normal-heroic-mythic

BUGS:
    - after a /reload, it is not starting new tickers for spells under cooldown

--]=]

---@alias castername string
---@alias castspellid string
---@alias schedulename string

LIB_OPEN_RAID_CAN_LOAD = false

local versionString, revision, launchDate, gameVersion = GetBuildInfo()

local isExpansion_Dragonflight = function()
	if (gameVersion >= 100000) then
		return true
	end
end

--don't load if it's not retail, emergencial patch due to classic and bcc stuff not transposed yet
if (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and not isExpansion_Dragonflight()) then
    return
end

local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0", true)

local major = "LibOpenRaid_Rating-1.0"

local CONST_LIB_VERSION = 143

if (LIB_OPEN_RAID_MAX_VERSION) then
    if (CONST_LIB_VERSION <= LIB_OPEN_RAID_MAX_VERSION) then
        return
    end
end

--declare the library within the LibStub
    local libStub = _G.LibStub
    local openRaidLib = libStub:NewLibrary(major, CONST_LIB_VERSION)

    if (not openRaidLib) then
        return
    end

    openRaidLib.__version = CONST_LIB_VERSION
    LIB_OPEN_RAID_CAN_LOAD = true
    LIB_OPEN_RAID_MAX_VERSION = CONST_LIB_VERSION

    --locals
    local unpack = table.unpack or _G.unpack

    openRaidLib.__errors = {} --/dump LibStub:GetLibrary("LibOpenRaid-1.0").__errors

--default values
    openRaidLib.inGroup = false
    openRaidLib.UnitIDCache = {}

    openRaidLib.Util = openRaidLib.Util or {}

    local CONST_CVAR_TEMPCACHE = "LibOpenRaidTempCache_Rating"
    local CONST_CVAR_TEMPCACHE_DEBUG = "LibOpenRaidTempCache_RatingDebug"

    --delay to request all data from other players
    local CONST_REQUEST_ALL_DATA_COOLDOWN = 30
    --delay to send all data to other players
    local CONST_SEND_ALL_DATA_COOLDOWN = 30

    --show failures (when the function return an error) results to chat
    local CONST_DIAGNOSTIC_ERRORS = false
    --show the data to be sent and data received from comm
    local CONST_DIAGNOSTIC_COMM = true
    --show data received from other players
    local CONST_DIAGNOSTIC_COMM_RECEIVED = false

    local CONST_COMM_PREFIX = "LRSR"
    local CONST_COMM_PREFIX_LOGGED = "LRSR_LOGGED"

    local CONST_COMM_KEYSTONE_DATA_PREFIX = "K"
    local CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX = "J"
    
    local CONST_COMM_RATING_DATA_PREFIX = "R"
    local CONST_COMM_RATING_DATAREQUEST_PREFIX = "Q" 
    
    local CONST_COMM_SENDTO_PARTY = "0x1"
    local CONST_COMM_SENDTO_RAID = "0x2"
    local CONST_COMM_SENDTO_GUILD = "0x4"

    local CONST_ONE_SECOND = 1.0
    local CONST_TWO_SECONDS = 2.0
    local CONST_THREE_SECONDS = 3.0

    local CONST_SPECIALIZATION_VERSION_CLASSIC = 0
    local CONST_SPECIALIZATION_VERSION_MODERN = 1

    local CONST_COOLDOWN_CHECK_INTERVAL = CONST_THREE_SECONDS
    local CONST_COOLDOWN_TIMELEFT_HAS_CHANGED = CONST_THREE_SECONDS

    local CONST_COOLDOWN_INDEX_TIMELEFT = 1
    local CONST_COOLDOWN_INDEX_CHARGES = 2
    local CONST_COOLDOWN_INDEX_TIMEOFFSET = 3
    local CONST_COOLDOWN_INDEX_DURATION = 4
    local CONST_COOLDOWN_INDEX_UPDATETIME = 5
    local CONST_COOLDOWN_INDEX_AURA_DURATION = 6

    local CONST_COOLDOWN_INFO_SIZE = 6

    local CONST_USE_DEFAULT_SCHEDULE_TIME = true

    -- Real throttle is 10 messages per 1 second, but we want to be safe due to fact we dont know when it actually resets
    local CONST_COMM_BURST_BUFFER_COUNT = 9

    local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
    local GetContainerItemID = GetContainerItemID or C_Container.GetContainerItemID
    local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink

    --from vanilla to cataclysm, the specID did not existed, hence its considered version 0
    --for mists of pandaria and beyond it's version 1
    local getSpecializationVersion = function()
        if (gameVersion >= 50000) then
            return CONST_SPECIALIZATION_VERSION_MODERN
        else
            return CONST_SPECIALIZATION_VERSION_CLASSIC
        end
    end

    function openRaidLib.ShowDiagnosticErrors(value)
        CONST_DIAGNOSTIC_ERRORS = value
    end

    --make the 'pri-nt' word be only used once, this makes easier to find lost debug pri-nts in the code
    local sendChatMessage = function(...)
        print(...)
    end

    openRaidLib.DiagnosticError = function(msg, ...)
        if (CONST_DIAGNOSTIC_ERRORS) then
            sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
        end
    end

    local diagnosticFilter = nil
    local diagnosticComm = function(msg, ...)
        if (CONST_DIAGNOSTIC_COMM) then
            if (diagnosticFilter) then
                local lowerMessage = msg:lower()
                if (lowerMessage:find(diagnosticFilter)) then
                    sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
                    --dumpt(msg)
                end
            else
                sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
            end
        end
    end

    local diagnosticCommReceivedFilter = false
    openRaidLib.diagnosticCommReceived = function(msg, ...)
        if (diagnosticCommReceivedFilter) then
            local lowerMessage = msg:lower()
            if (lowerMessage:find(diagnosticCommReceivedFilter)) then
                sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
            end
        else
            sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
        end
    end


    openRaidLib.DeprecatedMessage = function(msg)
        sendChatMessage("|cFFFF9922OpenRaidLib|r:", "|cFFFF5555" .. msg .. "|r")
    end

    local isTimewalkWoW = function()
        local _, _, _, buildInfo = GetBuildInfo()
        if (buildInfo < 40000) then
            return true
        end
    end

    local checkClientVersion = function(...)
        for i = 1, select("#", ...) do
            local clientVersion = select(i, ...)

            if (clientVersion == "retail" and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or isExpansion_Dragonflight())) then --retail
                return true

            elseif (clientVersion == "classic_era" and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then --classic era (vanila)
                return true

            elseif (clientVersion == "bcc" and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC) then --the burning crusade classic
                return true
            end
        end
    end

--------------------------------------------------------------------------------------------------------------------------------
--~internal cache
--use a console variable to create a flash cache to keep data while the game reload
--this is not a long term database as saved variables are and it get clean up often

C_CVar.RegisterCVar(CONST_CVAR_TEMPCACHE)
C_CVar.RegisterCVar(CONST_CVAR_TEMPCACHE_DEBUG)

--internal namespace
local tempCache = {
    debugString = "",
}

tempCache.copyCache = function(t1, t2)
    for key, value in pairs(t2) do
        if (type(value) == "table") then
            t1[key] = t1[key] or {}
            tempCache.copyCache(t1[key], t2[key])
        else
            t1[key] = value
        end
    end
    return t1
end

--use debug cvar to find issues that occurred during the logoff process
function openRaidLib.PrintTempCacheDebug()
    local debugMessage = C_CVar.GetCVar(CONST_CVAR_TEMPCACHE_DEBUG)
    sendChatMessage("|cFFFF9922OpenRaidLib|r Temp CVar Result:\n", debugMessage)
end

function tempCache.SaveDebugText()
    C_CVar.SetCVar(CONST_CVAR_TEMPCACHE_DEBUG, "0")
    --C_CVar.SetCVar(CONST_CVAR_TEMPCACHE_DEBUG, tempCache.debugString)
end

function tempCache.AddDebugText(text)
    tempCache.debugString = tempCache.debugString .. date("%H:%M:%S") .. "| " .. text .. "\n"
end

function tempCache.SaveCacheOnCVar(data)
    C_CVar.SetCVar(CONST_CVAR_TEMPCACHE, "0")
    --C_CVar.SetCVar(CONST_CVAR_TEMPCACHE, data)
    tempCache.AddDebugText("CVars Saved on saveCahceOnCVar(), Size: " .. #data)
end

function tempCache.RestoreData()
    local data = C_CVar.GetCVar(CONST_CVAR_TEMPCACHE)
    if (data and type(data) == "string" and string.len(data) > 2) then
        local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0", true)
        if (LibAceSerializer) then
            local okay, cacheInfo = LibAceSerializer:Deserialize(data)
            if (okay) then
                local age = cacheInfo.createdAt
                --if the data is older than 5 minutes, much has been changed from the group and the data is out dated
                if (age + (60 * 5) < time()) then
                    return
                end

                local unitsInfo = cacheInfo.unitsInfo
                local cooldownsInfo = cacheInfo.cooldownsInfo
                local gearInfo = cacheInfo.gearInfo

                local okayUnitsInfo, unitsInfo = LibAceSerializer:Deserialize(unitsInfo)
                local okayCooldownsInfo, cooldownsInfo = LibAceSerializer:Deserialize(cooldownsInfo)
                local okayGearInfo, gearInfo = LibAceSerializer:Deserialize(gearInfo)

                if (okayUnitsInfo and unitsInfo) then
                    openRaidLib.UnitInfoManager.UnitData = tempCache.copyCache(openRaidLib.UnitInfoManager.UnitData, unitsInfo)
                else
                    tempCache.AddDebugText("invalid UnitInfo")
                end

                if (okayCooldownsInfo and cooldownsInfo) then
                    openRaidLib.CooldownManager.UnitData = tempCache.copyCache(openRaidLib.CooldownManager.UnitData, cooldownsInfo)
                else
                    tempCache.AddDebugText("invalid CooldownsInfo")
                end

                if (okayGearInfo and gearInfo) then
                    openRaidLib.GearManager.UnitData = tempCache.copyCache(openRaidLib.GearManager.UnitData, gearInfo)
                else
                    tempCache.AddDebugText("invalid GearInfo")
                end
            else
                tempCache.AddDebugText("Deserialization not okay, reason: " .. cacheInfo)
            end
        else
            tempCache.AddDebugText("LibAceSerializer not found")
        end
    else
        if (not data) then
            tempCache.AddDebugText("invalid temporary cache: getCVar returned nil")
        elseif (type(data) ~= "string") then
            tempCache.AddDebugText("invalid temporary cache: getCVar did not returned a string")
        elseif (string.len(data) < 2) then
            tempCache.AddDebugText("invalid temporary cache: data length lower than 2 bytes (first login?)")
        else
            tempCache.AddDebugText("invalid temporary cache: no reason found")
        end
    end
end

function tempCache.SaveData()
    tempCache.AddDebugText("SaveData() called.")

    local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0", true)
    if (LibAceSerializer) then
        local allUnitsInfo = openRaidLib.UnitInfoManager.UnitData
        local allUnitsCooldowns = openRaidLib.CooldownManager.UnitData
        local allPlayersGear = openRaidLib.GearManager.UnitData

        local cacheInfo = {
            createdAt = time(),
        }

        local unitsInfoSerialized = LibAceSerializer:Serialize(allUnitsInfo)
        local unitsCooldownsSerialized = LibAceSerializer:Serialize(allUnitsCooldowns)
        local playersGearSerialized = LibAceSerializer:Serialize(allPlayersGear)

        if (unitsInfoSerialized) then
            cacheInfo.unitsInfo = unitsInfoSerialized
            tempCache.AddDebugText("SaveData() units info serialized okay.")
        else
            tempCache.AddDebugText("SaveData() units info serialized failed.")
        end

        if (unitsCooldownsSerialized) then
            cacheInfo.cooldownsInfo = unitsCooldownsSerialized
            tempCache.AddDebugText("SaveData() cooldowns info serialized okay.")
        else
            tempCache.AddDebugText("SaveData() cooldowns info serialized failed.")
        end

        if (playersGearSerialized) then
            cacheInfo.gearInfo = playersGearSerialized
            tempCache.AddDebugText("SaveData() gear info serialized okay.")
        else
            tempCache.AddDebugText("SaveData() gear info serialized failed.")
        end

        local cacheInfoSerialized = LibAceSerializer:Serialize(cacheInfo)
        tempCache.SaveCacheOnCVar(cacheInfoSerialized)
    else
        tempCache.AddDebugText("SaveData() AceSerializer not found.")
    end

    tempCache.SaveDebugText()
end


--------------------------------------------------------------------------------------------------------------------------------
--~comms
    openRaidLib.commHandler = {}
    function openRaidLib.commHandler.OnReceiveComm(self, event, prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
        --check if the data belong to us
        if (prefix == CONST_COMM_PREFIX) then
            sender = Ambiguate(sender, "none")

            --don't receive comms from the player it self
            local playerName = UnitName("player")
            if (playerName == sender) then
                return
            end

            local commId = 0

            --verify if this is a safe comm
            local data = ""
            local bIsSafe = event == "CHAT_MSG_ADDON_LOGGED"
            if (bIsSafe) then
                data = text:gsub("%%", "\n")
                --replace the the first ";" found in the data string with a ",", only the first occurence
                data = data:gsub(";", ",", 1)
                --get the commId
                commId = data:match("#([^#]+)$")
                --remove the commId from the data
                data = data:gsub("#([^#]+)$", "")
                --add the commId to the end of the data after a comma
                data = data .. "," .. commId
            else
                data = text
                local LibDeflate = LibStub:GetLibrary("LibDeflate")
                local dataCompressed = LibDeflate:DecodeForWoWAddonChannel(data)
                data = LibDeflate:DecompressDeflate(dataCompressed)
            end

            --some users are reporting errors where 'data is nil'. Making some sanitization
            if (not data) then
                openRaidLib.DiagnosticError("Invalid data from player:", sender, "data:", text)
                return
            elseif (type(data) ~= "string") then
                openRaidLib.DiagnosticError("Invalid data from player:", sender, "data:", text, "data type is:", type(data))
                return
            end

            --get the first byte of the data, it indicates what type of data was transmited
            local dataTypePrefix = data:match("^.")
            if (not dataTypePrefix) then
                openRaidLib.DiagnosticError("Invalid dataTypePrefix from player:", sender, "data:", data, "dataTypePrefix:", dataTypePrefix)
                return
            elseif (openRaidLib.commPrefixDeprecated[dataTypePrefix]) then
                openRaidLib.DiagnosticError("Invalid dataTypePrefix from player:", sender, "data:", data, "dataTypePrefix:", dataTypePrefix)
                return
            end

            --if this is isn't a keystone data comm, check if the lib can receive comms
            if (dataTypePrefix ~= CONST_COMM_KEYSTONE_DATA_PREFIX and dataTypePrefix ~= CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX) then
                if (not openRaidLib.IsCommAllowed()) then
                    openRaidLib.DiagnosticError("comm not allowed.")
                    return
                end
            end

            --if this is isn't a rating data comm, check if the lib can receive comms
            if (dataTypePrefix ~= CONST_COMM_RATING_DATA_PREFIX and dataTypePrefix ~= CONST_COMM_RATING_DATAREQUEST_PREFIX) then
                if (not openRaidLib.IsCommAllowed()) then
                    openRaidLib.DiagnosticError("comm not allowed.")
                    return
                end
            end

            if (CONST_DIAGNOSTIC_COMM_RECEIVED) then
                openRaidLib.diagnosticCommReceived(data)
            end

            --get the table with functions regitered for this type of data
            local callbackTable = openRaidLib.commHandler.commCallback[dataTypePrefix]
            if (not callbackTable) then
                openRaidLib.DiagnosticError("Not callbackTable for dataTypePrefix:", dataTypePrefix, "from player:", sender, "data:", data)
                return
            end

            --convert to table
            local dataAsTable = {strsplit(",", data)}

            --remove the first index (prefix)
            tremove(dataAsTable, 1)

            --trigger callbacks
            for i = 1, #callbackTable do
                callbackTable[i](dataAsTable, sender)
            end
        end
    end

    C_ChatInfo.RegisterAddonMessagePrefix(CONST_COMM_PREFIX)
    openRaidLib.commHandler.eventFrame = CreateFrame("frame")
    openRaidLib.commHandler.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    openRaidLib.commHandler.eventFrame:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
    openRaidLib.commHandler.eventFrame:SetScript("OnEvent", openRaidLib.commHandler.OnReceiveComm)

    openRaidLib.commHandler.commCallback = {
                                            --when transmiting
        [CONST_COMM_KEYSTONE_DATA_PREFIX] = {}, --received keystone data
        [CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX] = {}, --received a request to send keystone data
        [CONST_COMM_RATING_DATA_PREFIX] = {}, --received rating data
        [CONST_COMM_RATING_DATAREQUEST_PREFIX] = {}, --received a request to send rating data
    }

    function openRaidLib.commHandler.RegisterComm(prefix, func)
        --the table for the prefix need to be declared at the 'openRaidLib.commHandler.commCallback' table
        tinsert(openRaidLib.commHandler.commCallback[prefix], func)
    end

    local charactesrPerMessage = 251
    local receivingMsgInParts = {}

    local debugCommReception = CreateFrame("frame")
    debugCommReception:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
    debugCommReception:SetScript("OnEvent", function(self, event, prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
        if (prefix == CONST_COMM_PREFIX_LOGGED) then
            local chunkNumber, totalChunks, data = text:match("^%$(%d+)%$(%d+)(.*)")
            local onlyData = text:match("^(.*)")

            if (not chunkNumber and not totalChunks and onlyData) then
                openRaidLib.commHandler.OnReceiveComm(self, "CHAT_MSG_ADDON_LOGGED", CONST_COMM_PREFIX, onlyData, channel, sender, target, zoneChannelID, localID, name, instanceID)

            elseif (chunkNumber and totalChunks and data) then
                chunkNumber = tonumber(chunkNumber)
                totalChunks = tonumber(totalChunks)

                if (chunkNumber and totalChunks) then
                    if (chunkNumber <= totalChunks and chunkNumber >= 1) then
                        if (not receivingMsgInParts[sender]) then
                            local parts = {}
                            for i = 1, totalChunks do
                                parts[i] = false
                            end
                            receivingMsgInParts[sender] = {
                                totalChunks = totalChunks,
                                chunks = parts
                            }
                        end

                        receivingMsgInParts[sender].chunks[chunkNumber] = data

                        --verify if all parts were received
                        local allPartsReceived = true
                        for i = 1, totalChunks do
                            if (not receivingMsgInParts[sender].chunks[i]) then
                                allPartsReceived = false
                                break
                            end
                        end

                        if (allPartsReceived) then
                            local fullData = ""
                            --sew the parts together
                            for i = 1, totalChunks do
                                fullData = fullData .. receivingMsgInParts[sender].chunks[i]
                            end

                            receivingMsgInParts[sender] = nil
                            openRaidLib.commHandler.OnReceiveComm(self, "CHAT_MSG_ADDON_LOGGED", CONST_COMM_PREFIX, fullData, channel, sender, target, zoneChannelID, localID, name, instanceID)
                        end
                    end
                end
            else
                openRaidLib.DiagnosticError("Logged comm in parts missing information, sender:", sender, "chunkNumber:", chunkNumber, "totalChunks:", totalChunks, "data:", type(data))
            end
        end
    end)

    --@flags
    --0x1: to party
    --0x2: to raid
    --0x4: to guild
    local sendData = function(dataEncoded, channel, bIsSafe, plainText)
        local aceComm = LibStub:GetLibrary("AceComm-3.0", true)
        if (aceComm) then
            if (bIsSafe) then
                plainText = plainText:gsub("\n", "%%")
                plainText = plainText:gsub(",", ";")

                local commId = tostring(GetServerTime() + GetTime())
                plainText = plainText .. "#" .. commId

                if (plainText:len() > 255) then
                    local totalMessages = math.ceil(plainText:len() / charactesrPerMessage)
                    for i = 1, totalMessages do
                        local chunk = plainText:sub((i - 1) * charactesrPerMessage + 1, i * charactesrPerMessage)
                        local chunkNumberAndTotalChuncks = "$" .. i .. "$" .. totalMessages
                        local chunkMessage = chunkNumberAndTotalChuncks .. chunk
                        ChatThrottleLib:SendAddonMessageLogged("NORMAL", CONST_COMM_PREFIX_LOGGED, chunkMessage, channel)
                    end
                else
                    ChatThrottleLib:SendAddonMessageLogged("NORMAL", CONST_COMM_PREFIX_LOGGED, plainText, channel)
                end
            else
                aceComm:SendCommMessage(CONST_COMM_PREFIX, dataEncoded, channel, nil, "ALERT")
            end
        else
            C_ChatInfo.SendAddonMessage(CONST_COMM_PREFIX, dataEncoded, channel)
        end
    end

	if (C_ChatInfo) then
		C_ChatInfo.RegisterAddonMessagePrefix(CONST_COMM_PREFIX_LOGGED)
	else
		RegisterAddonMessagePrefix(CONST_COMM_PREFIX_LOGGED)
	end

    ---@class commdata : table
    ---@field data string
    ---@field channel string
    ---@field bIsSafe boolean
    ---@field plainText string

    ---@type {}[]
    local commScheduler = {};

    local commBurstBufferCount = CONST_COMM_BURST_BUFFER_COUNT;
    local commServerTimeLastThrottleUpdate = GetServerTime();

    do
        --if there's an old version that already registered the comm ticker, cancel it
        if (LIB_OPEN_RAID_COMM_SCHEDULER) then
            LIB_OPEN_RAID_COMM_SCHEDULER:Cancel();
        end

        local newTickerHandle = C_Timer.NewTicker(0.05, function()
            local serverTime = GetServerTime();

            -- Replenish the counter if last server time is not the same as the last throttle update
            -- Clamp it to CONST_COMM_BURST_BUFFER_COUNT
            commBurstBufferCount = math.min((serverTime ~= commServerTimeLastThrottleUpdate) and commBurstBufferCount + 1 or commBurstBufferCount, CONST_COMM_BURST_BUFFER_COUNT);
            commServerTimeLastThrottleUpdate = serverTime;

            -- while (anything in queue) and (throttle allows it)
            while(#commScheduler > 0 and commBurstBufferCount > 0) do
                -- FIFO queue
                ---@type commdata
                local commData = table.remove(commScheduler, 1);
                sendData(commData.data, commData.channel, commData.bIsSafe, commData.plainText);
                commBurstBufferCount = commBurstBufferCount - 1;
            end
        end);

        LIB_OPEN_RAID_COMM_SCHEDULER = newTickerHandle
    end

    function openRaidLib.commHandler.SendCommData(data, flags, bIsSafe)
        local LibDeflate = LibStub:GetLibrary("LibDeflate")
        local dataCompressed = LibDeflate:CompressDeflate(data, {level = 9})
        local dataEncoded = LibDeflate:EncodeForWoWAddonChannel(dataCompressed)

        if (flags) then
            if (bit.band(flags, CONST_COMM_SENDTO_PARTY)) then --send to party
                if (IsInGroup() and not IsInRaid()) then
                    ---@type commdata
                    local commData = {data = dataEncoded, channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY", bIsSafe = bIsSafe, plainText = data}
                    table.insert(commScheduler, commData)
                end
            end

            if (bit.band(flags, CONST_COMM_SENDTO_RAID)) then --send to raid
                if (IsInRaid()) then
                    local commData = {data = dataEncoded, channel = IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "RAID", bIsSafe = bIsSafe, plainText = data}
                    table.insert(commScheduler, commData)
                end
            end

            if (bit.band(flags, CONST_COMM_SENDTO_GUILD)) then --send to guild
                if (IsInGuild()) then
                    --Guild has no 10 msg restriction so send it directly
                    sendData(dataEncoded, "GUILD");
                end
            end
        else
            if (IsInGroup() and not IsInRaid()) then --in party only
                local commData = {data = dataEncoded, channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY", bIsSafe = bIsSafe, plainText = data}
                table.insert(commScheduler, commData)

            elseif (IsInRaid()) then
                local commData = {data = dataEncoded, channel = IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "RAID", bIsSafe = bIsSafe, plainText = data}
                table.insert(commScheduler, commData)
            end
        end
	end

--------------------------------------------------------------------------------------------------------------------------------
--~schedule ~timers
    ---@type table<schedulename, number>
    local defaultScheduleCooldownTimeByScheduleName = {
        ["sendFullData_Schedule"] = 25,
        ["sendAllPlayerCooldowns_Schedule"] = 23,
        ["sendDurability_Schedule"] = 10,
        ["sendAllGearInfo_Schedule"] = 20,
        ["petStatus_Schedule"] = 8,
        ["updatePlayerData_Schedule"] = 22,
        --["sendKeystoneInfoToParty_Schedule"] = 2,
        --["sendKeystoneInfoToGuild_Schedule"] = 2,
    }

    openRaidLib.Schedules = {
        registeredUniqueTimers = {}
    }

    local timersCanRunWithoutGroup = {
        ["mainControl"] = {
            ["updatePlayerData_Schedule"] = true
        }
    }

    --run a scheduled function with its payload
    local triggerScheduledTick = function(tickerObject)
        local payload = tickerObject.payload
        local callback = tickerObject.callback
        local bCanRunWithoutGroup = tickerObject.bCanRunWithoutGroup

        if (tickerObject.isUnique) then
            local namespace = tickerObject.namespace
            local scheduleName = tickerObject.scheduleName
            openRaidLib.Schedules.CancelUniqueTimer(namespace, scheduleName)
        end

        --check if the player is still in group
        if (not openRaidLib.IsInGroup()) then
            if (not bCanRunWithoutGroup) then
                return
            end
        end

        local result, errortext = xpcall(callback, geterrorhandler(), unpack(payload))
        --if (not result) then
        --    sendChatMessage("openRaidLib: error on scheduler:", tickerObject.scheduleName, tickerObject.stack)
        --end

        return result
    end

    --create a new schedule
    function openRaidLib.Schedules.NewTimer(time, callback, bCanRunWithoutGroup, ...)
        local payload = {...}
        local newTimer = C_Timer.NewTimer(time, triggerScheduledTick)
        newTimer.bCanRunWithoutGroup = bCanRunWithoutGroup
        newTimer.payload = payload
        newTimer.callback = callback
        --newTimer.stack = debugstack()
        return newTimer
    end

    --create an unique schedule
    --if a schedule already exists, cancels it and make a new ~unique
    function openRaidLib.Schedules.NewUniqueTimer(time, callback, namespace, scheduleName, ...)
        --the the schedule uses a default time, get it from the table, if the timer already exists, quit
        if (time == CONST_USE_DEFAULT_SCHEDULE_TIME) then
            if (openRaidLib.Schedules.IsUniqueTimerOnCooldown(namespace, scheduleName)) then
                return
            end
            time = defaultScheduleCooldownTimeByScheduleName[scheduleName] or time
        else
            openRaidLib.Schedules.CancelUniqueTimer(namespace, scheduleName)
        end

        local bCanRunWithoutGroup = timersCanRunWithoutGroup[namespace] and timersCanRunWithoutGroup[namespace][scheduleName]

        local newTimer = openRaidLib.Schedules.NewTimer(time, callback, bCanRunWithoutGroup, ...)
        newTimer.namespace = namespace
        newTimer.scheduleName = scheduleName
        --newTimer.stack = debugstack()
        newTimer.isUnique = true

        local registeredUniqueTimers = openRaidLib.Schedules.registeredUniqueTimers
        registeredUniqueTimers[namespace] = registeredUniqueTimers[namespace] or {}
        registeredUniqueTimers[namespace][scheduleName] = newTimer
    end

    --does timer by schedule name exists?
    function openRaidLib.Schedules.IsUniqueTimerOnCooldown(namespace, scheduleName)
        local registeredUniqueTimers = openRaidLib.Schedules.registeredUniqueTimers
        local currentSchedule = registeredUniqueTimers[namespace] and registeredUniqueTimers[namespace][scheduleName]

        if (currentSchedule) then
            return true
        end
        return false
    end

    --cancel an unique schedule
    function openRaidLib.Schedules.CancelUniqueTimer(namespace, scheduleName)
        local registeredUniqueTimers = openRaidLib.Schedules.registeredUniqueTimers
        local currentSchedule = registeredUniqueTimers[namespace] and registeredUniqueTimers[namespace][scheduleName]

        if (currentSchedule) then
            if (not currentSchedule:IsCancelled()) then
                currentSchedule:Cancel()
            end
            registeredUniqueTimers[namespace][scheduleName] = nil
        end
    end

    --cancel all unique timers
    function openRaidLib.Schedules.CancelAllUniqueTimers()
        local registeredUniqueTimers = openRaidLib.Schedules.registeredUniqueTimers
        for namespace, schedulesTable in pairs(registeredUniqueTimers) do
            for scheduleName, timerObject in pairs(schedulesTable) do
                if (timerObject and not timerObject:IsCancelled()) then
                    timerObject:Cancel()
                end
            end
        end
        table.wipe(registeredUniqueTimers)
    end


--------------------------------------------------------------------------------------------------------------------------------
--~public ~callbacks
--these are the events where other addons can register and receive calls
    local allPublicCallbacks = {
        "KeystoneUpdate",
        "KeystoneWipe",
        "RatingUpdate",
        "RatingWipe"
    }

    --save build the table to avoid lose registered events on older versions
    openRaidLib.publicCallback = openRaidLib.publicCallback or {}
    openRaidLib.publicCallback.events = openRaidLib.publicCallback.events or {}
    for _, callbackName in ipairs(allPublicCallbacks) do
        openRaidLib.publicCallback.events[callbackName] = openRaidLib.publicCallback.events[callbackName] or {}
    end

    local checkRegisterDataIntegrity = function(addonObject, event, callbackMemberName)
        --check of integrity
        if (type(addonObject) == "string") then
            addonObject = _G[addonObject]
        end

        if (type(addonObject) ~= "table") then
            return 1
        end

        if (not openRaidLib.publicCallback.events[event]) then
            return 2

        elseif (not addonObject[callbackMemberName]) then
            return 3
        end

        return true
    end

    --call the registered function within the addon namespace
    --payload is sent together within the call
    function openRaidLib.publicCallback.TriggerCallback(event, ...)
        local eventCallbacks = openRaidLib.publicCallback.events[event]

        for i = 1, #eventCallbacks do
            local thisCallback = eventCallbacks[i] --got a case where this was nil, which is kinda impossible? | event: CooldownUpdate
            local addonObject = thisCallback[1] --670: attempt to index local 'thisCallback' (a nil value)
            local functionName = thisCallback[2]

            --[=[
                eventCallbacks = {
                    1 = {}
                }

                (for index) = 2
                (for limit) = 2
                (for step) = 1
                i = 2

                thisCallback = nil
            --]=]

            --get the function from within the addon object
            local functionToCallback = addonObject[functionName]

            if (functionToCallback) then
                --if this isn't a function, xpcall trigger an error
                local okay, errorMessage = xpcall(functionToCallback, geterrorhandler(), ...)
                if (not okay) then
                    sendChatMessage("error on callback for event:", event)
                end
            else
                --the registered function wasn't found
            end
        end
    end

    function openRaidLib.RegisterCallback(addonObject, event, callbackMemberName)
        --check of integrity
        local passIntegrityTest = checkRegisterDataIntegrity(addonObject, event, callbackMemberName)
        if (passIntegrityTest and type(passIntegrityTest) ~= "boolean") then
            return passIntegrityTest
        end

        --register
        tinsert(openRaidLib.publicCallback.events[event], {addonObject, callbackMemberName})
        return true
    end

    function openRaidLib.UnregisterCallback(addonObject, event, callbackMemberName)
        --check of integrity
        local passIntegrityTest = checkRegisterDataIntegrity(addonObject, event, callbackMemberName)
        if (passIntegrityTest and type(passIntegrityTest) ~= "boolean") then
            return passIntegrityTest
        end

        for i = 1, #openRaidLib.publicCallback.events[event] do
            local registeredCallback = openRaidLib.publicCallback.events[event][i]
            if (registeredCallback[1] == addonObject and registeredCallback[2] == callbackMemberName) then
                tremove(openRaidLib.publicCallback.events[event], i)
                break
            end
        end
    end


--------------------------------------------------------------------------------------------------------------------------------
--~internal ~callbacks
--internally, each module can register events through the internal callback to be notified when something happens in the game

    openRaidLib.internalCallback = {}
    openRaidLib.internalCallback.events = {
        ["onEnterGroup"] = {},
        ["onLeaveGroup"] = {},
        ["onEnterWorld"] = {},
        ["mythicDungeonEnd"] = {},
    }

    openRaidLib.internalCallback.RegisterCallback = function(event, func)
        tinsert(openRaidLib.internalCallback.events[event], func)
    end

    openRaidLib.internalCallback.UnRegisterCallback = function(event, func)
        local eventCallbacks = openRaidLib.internalCallback.events[event]
        for i = 1, #eventCallbacks do
            if (eventCallbacks[i] == func) then
                tremove(eventCallbacks, i)
                break
            end
        end
    end

    function openRaidLib.internalCallback.TriggerEvent(event, ...)
        local eventCallbacks = openRaidLib.internalCallback.events[event]
        for i = 1, #eventCallbacks do
            local functionToCallback = eventCallbacks[i]
            functionToCallback(event, ...)
        end
    end

    --create the frame for receiving game events
    local eventFrame = _G.OpenRaidLibFrame
    if (not eventFrame) then
        eventFrame = CreateFrame("frame", "OpenRaidLibFrame", UIParent)
    end

    local eventFunctions = {
        --check if the player joined a group
        ["GROUP_ROSTER_UPDATE"] = function()
            local bEventTriggered = false
            if (openRaidLib.IsInGroup()) then
                if (not openRaidLib.inGroup) then
                    openRaidLib.inGroup = true
                    openRaidLib.internalCallback.TriggerEvent("onEnterGroup")
                    bEventTriggered = true
                end
            else
                if (openRaidLib.inGroup) then
                    openRaidLib.inGroup = false
                    openRaidLib.internalCallback.TriggerEvent("onLeaveGroup")
                    bEventTriggered = true
                end
            end
        end,

        ["PLAYER_ENTERING_WORLD"] = function(...)
            --has the selected character just loaded?
            if (not openRaidLib.bHasEnteredWorld) then
                --register events
                openRaidLib.OnEnterWorldRegisterEvents()


                if (IsInGroup()) then
                    -- Request all rating info
                end

                openRaidLib.bHasEnteredWorld = true
            end

            openRaidLib.internalCallback.TriggerEvent("onEnterWorld")
        end,

        --SPELLS_CHANGED

        ["CHALLENGE_MODE_COMPLETED"] = function()
            openRaidLib.internalCallback.TriggerEvent("mythicDungeonEnd")
        end,

        ["PLAYER_LOGOUT"] = function()
            tempCache.SaveData()
        end,
    }
    openRaidLib.eventFunctions = eventFunctions

    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        local eventCallbackFunc = eventFunctions[event]
        eventCallbackFunc(...)
    end)

    --run when PLAYER_ENTERING_WORLD triggers, this avoid any attempt of getting information without the game has completed the load process
    function openRaidLib.OnEnterWorldRegisterEvents()
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")

        if (checkClientVersion("retail")) then
            eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        end
    end


--------------------------------------------------------------------------------------------------------------------------------
--~main ~control

--------------------------------------------------------------------------------------------------------------------------------
--~rating

--- unitName with server
--- classID
--- rating
--- table<dungeonId, rating>

    ---@class MythicPlusRatingMapSummary	
    ---@field mapScore number	
    ---@field bestRunLevel number	
    ---@field bestRunDurationMS number
    ---@field finishedSuccess boolean	

    ---@class ratinginfo
    ---@field classID number
    ---@field currentSeasonScore number
    ---structure:
    ---[challengeModeID] = MythicPlusRatingMapSummary
    ---@field runs table<number, MythicPlusRatingMapSummary>

    --manager constructor
    openRaidLib.RatingInfoManager = {
        --structure:
        --[playerName] = ratinginfo
        ---@type table<string, ratinginfo>
        RatingData = {},
    }

    --API calls
        --return a table containing all information of units
        --format: [playerName-realm] = {information}
        function openRaidLib.GetAllRatingInfo()
            return openRaidLib.RatingInfoManager.GetAllRatingInfo()
        end

        --return a table containing information of a single unit
        function openRaidLib.GetRatingInfo(unitId)
            local unitName = GetUnitName(unitId, true) or unitId
            return openRaidLib.RatingInfoManager.GetRatingInfo(unitName)
        end

        function openRaidLib.RequestRatingDataFromGuild()
            if (IsInGuild()) then
                local dataToSend = "" .. CONST_COMM_RATING_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x4)
                diagnosticComm("RequestRatingDataFromGuild| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.RequestRatingDataFromParty()
            if (IsInGroup() and not IsInRaid()) then
                local dataToSend = "" .. CONST_COMM_RATING_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x1)
                diagnosticComm("RequestRatingDataFromParty| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.RequestRatingDataFromRaid()
            if (IsInRaid()) then
                local dataToSend = "" .. CONST_COMM_RATING_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x2)
                diagnosticComm("RequestRatingDataFromRaid| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.WipeRatingData()
            wipe(openRaidLib.RatingInfoManager.RatingData)
            --trigger public callback
            openRaidLib.publicCallback.TriggerCallback("RatingWipe", openRaidLib.RatingInfoManager.RatingData)

            --rating are only available on retail
            if (not checkClientVersion("retail")) then
                return
            end

            --generate rating info for the player
            local unitName = UnitName("player")
            local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(unitName, true)
            openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)

            openRaidLib.publicCallback.TriggerCallback("RatingUpdate", unitName, ratingInfo, openRaidLib.RatingInfoManager.RatingData)
            return true
        end

    --privite stuff, these function can still be called, but not advised
        ---@type ratinginfo
        local ratingTablePrototype = {
            classID = 0,
            currentSeasonScore = 0,
            runs = {}
        }

    function openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)
        --- I really just want this whole thing
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")

        ratingInfo.currentSeasonScore = summary.currentSeasonScore

        for _, runInfo in ipairs(summary.runs) do
            ratingInfo.runs[runInfo.challengeModeID] = {
                mapScore = runInfo.mapScore,
                bestRunLevel = runInfo.bestRunLevel,
                bestRunDurationMS = runInfo.bestRunDurationMS,
                finishedSuccess = runInfo.finishedSuccess
            }
        end
        
        local _, _, playerClassID = UnitClass("player")
        ratingInfo.classID = playerClassID
    end

    function openRaidLib.RatingInfoManager.GetAllRatingInfo()
        return openRaidLib.RatingInfoManager.RatingData
    end

    --get the rating info table or create a new one if 'createNew' is true
    function openRaidLib.RatingInfoManager.GetRatingInfo(unitName, createNew)
        local ratingInfo = openRaidLib.RatingInfoManager.RatingData[unitName]
        if (not ratingInfo and createNew) then
            ratingInfo = {}
            openRaidLib.TCopy(ratingInfo, ratingTablePrototype)
            openRaidLib.RatingInfoManager.RatingData[unitName] = ratingInfo
        end
        return ratingInfo
    end

    local getRatingInfoToComm = function()
        local playerName = UnitName("player")
        local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(playerName, true)
        openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)
    
        local dataToSend = "" .. CONST_COMM_RATING_DATA_PREFIX .. ","

        dataToSend = dataToSend .. ratingInfo.classID .. ","
        dataToSend = dataToSend .. ratingInfo.currentSeasonScore .. ","
        dataToSend = dataToSend .. openRaidLib.PackTable(ratingInfo.runs)
        
        -- local dataToSend = CONST_COMM_RATING_DATA_PREFIX .. "," .. serialized
        -- local dataToSend = CONST_COMM_RATING_DATA_PREFIX .. "," .. ratingInfo.classID .. "," .. openRaidLib.PackTableAndSubTables(ratingInfo.summary)
        return dataToSend
    end

    function openRaidLib.RatingInfoManager.SendPlayerRatingInfoToParty()
        local dataToSend = getRatingInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_PARTY)
        diagnosticComm("SendPlayerRatingInfoToParty| " .. dataToSend) --debug
    end

    function openRaidLib.RatingInfoManager.SendPlayerRatingInfoToGuild()
        local dataToSend = getRatingInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_GUILD)
        diagnosticComm("SendPlayerRatingInfoToGuild| " .. dataToSend) --debug
    end

    --when a request data is received, only send the data to party and guild
    --sending stuff to raid need to be called my the application with 'openRaidLib.RequestRatingDataFromRaid()'
    function openRaidLib.RatingInfoManager.OnReceiveRequestData()
        if (not checkClientVersion("retail")) then
            return
        end

        --update the information about the key stone the player has
        local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(UnitName("player"), true)
        openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)

        local _, instanceType = GetInstanceInfo()
        if (instanceType == "party") then
            openRaidLib.Schedules.NewUniqueTimer(math.random(1), openRaidLib.RatingInfoManager.SendPlayerRatingInfoToParty, "RatingInfoManager", "sendRatingInfoToParty_Schedule")

        elseif (instanceType == "raid" or instanceType == "pvp") then
            openRaidLib.Schedules.NewUniqueTimer(math.random(0, 30) + math.random(1), openRaidLib.RatingInfoManager.SendPlayerRatingInfoToParty, "RatingInfoManager", "sendRatingInfoToParty_Schedule")

        else
            openRaidLib.Schedules.NewUniqueTimer(math.random(4), openRaidLib.RatingInfoManager.SendPlayerRatingInfoToParty, "RatingInfoManager", "sendRatingInfoToParty_Schedule")
        end

        if (IsInGuild()) then
            openRaidLib.Schedules.NewUniqueTimer(math.random(0, 6) + math.random(), openRaidLib.RatingInfoManager.SendPlayerRatingInfoToGuild, "RatingInfoManager", "sendRatingInfoToGuild_Schedule")
        end
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_RATING_DATAREQUEST_PREFIX, openRaidLib.RatingInfoManager.OnReceiveRequestData)

    function openRaidLib.RatingInfoManager.OnReceiveRatingData(data, unitName)
        if (not checkClientVersion("retail")) then
            return
        end

        -- DevTools_Dump(deserialized)
        -- print("deserialized")

        local classID = tonumber(data[1])
        local currentSeasonScore = toNumber(data[2])
        local numberOfRuns = toNumber(data[3]);

        -- unpack the table as a pairs table
        local unpackedTable = openRaidLib.UnpackTable(data, 3, true, true, numberOfRuns)

        local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(unitName, true)
        ratingInfo.classID = classID
        ratingInfo.currentSeasonScore = currentSeasonScore

        for dungeonId, info in pairs(unpackedTable) do
            ratingInfo.runs[dungeonId] = info
        end

        --trigger public callback
        openRaidLib.publicCallback.TriggerCallback("RatingUpdate", unitName, ratingInfo, openRaidLib.RatingInfoManager.RatingData)
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_RATING_DATA_PREFIX, openRaidLib.RatingInfoManager.OnReceiveRatingData)

    --on entering a group, send rating information for the party
    function openRaidLib.RatingInfoManager.OnPlayerEnterGroup()
        --rating is only available on retail
        if (not checkClientVersion("retail")) then
            return
        end

        if (IsInGroup() and not IsInRaid()) then
            --update the information about the rating the player has
            local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(UnitName("player"), true)
            openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)

            --send to the group what rating the player has
            openRaidLib.Schedules.NewUniqueTimer(1 + math.random(0, 2) + math.random(), openRaidLib.RatingInfoManager.SendPlayerRatingInfoToParty, "RatingInfoManager", "sendRatingInfoToParty_Schedule")
        end
    end

    local ratingManagerOnPlayerEnterWorld = function()
        --hack: trigger a received data request to send data to party and guild when logging in
        openRaidLib.RatingInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(unitName, true)
        openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)

        openRaidLib.publicCallback.TriggerCallback("RatingUpdate", unitName, ratingInfo, openRaidLib.RatingInfoManager.RatingData)
    end

    function openRaidLib.RatingInfoManager.OnPlayerEnterWorld()
        --rating is only available on retail
        if (not checkClientVersion("retail")) then
            return
        end

        C_Timer.After(2, ratingManagerOnPlayerEnterWorld)
    end

    function openRaidLib.RatingInfoManager.OnMythicDungeonFinished()
        --rating is only available on retail
        if (not checkClientVersion("retail")) then
            return
        end
        --hack: on received data send data to party and guild
        openRaidLib.RatingInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local ratingInfo = openRaidLib.RatingInfoManager.GetRatingInfo(unitName, true)
        openRaidLib.RatingInfoManager.UpdatePlayerRatingInfo(ratingInfo)

        openRaidLib.publicCallback.TriggerCallback("RatingUpdate", unitName, ratingInfo, openRaidLib.RatingInfoManager.RatingData)
    end

    openRaidLib.internalCallback.RegisterCallback("onEnterWorld", openRaidLib.RatingInfoManager.OnPlayerEnterWorld)
    openRaidLib.internalCallback.RegisterCallback("onEnterGroup", openRaidLib.RatingInfoManager.OnPlayerEnterGroup)
    openRaidLib.internalCallback.RegisterCallback("mythicDungeonEnd", openRaidLib.RatingInfoManager.OnMythicDungeonFinished)


--------------------------------------------------------------------------------------------------------------------------------
--~keystones

    ---@class keystoneinfo
    ---@field level number
    ---@field mapID number
    ---@field challengeMapID number
    ---@field classID number
    ---@field rating number
    ---@field mythicPlusMapID number

    --manager constructor
    openRaidLib.KeystoneInfoManager = {
        --structure:
        --[playerName] = keystoneinfo
        ---@type table<string, keystoneinfo>
        KeystoneData = {},
    }

    --search the player backpack to find a mythic keystone
    --with the keystone object, it'll attempt to get the mythicPlusMapID to be used with C_ChallengeMode.GetMapUIInfo(mythicPlusMapID)
    --ATM we are obligated to do this due to C_MythicPlus.GetOwnedKeystoneMapID() return the same mapID for the two Tazavesh dungeons
    local getMythicPlusMapID = function()
        for backpackId = 0, 4 do
            for slotId = 1, GetContainerNumSlots(backpackId) do
                local itemId = GetContainerItemID(backpackId, slotId)
                if (itemId == LIB_OPEN_RAID_MYTHICKEYSTONE_ITEMID) then
                    local itemLink = GetContainerItemLink(backpackId, slotId)
                    local destroyedItemLink = itemLink:gsub("|", "")
                    local color, itemID, mythicPlusMapID = strsplit(":", destroyedItemLink)
                    return tonumber(mythicPlusMapID)
                end
            end
        end
    end

    local checkForKeystoneChange = function()
        --clear the timer reference
        openRaidLib.KeystoneInfoManager.KeystoneChangedTimer = nil

        --check if the player has a keystone in the backpack by quering the keystone level
        local level = C_MythicPlus.GetOwnedKeystoneLevel()
        if (not level) then
            return
        end
        local mapID = C_MythicPlus.GetOwnedKeystoneMapID()

        --get the current player keystone info and then compare with the keystone info from the bag, if there is differences update the player keystone info
        local unitName = UnitName("player")
        ---@type keystoneinfo
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)

        if (keystoneInfo.level ~= level or keystoneInfo.mapID ~= mapID) then
            openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)
            --hack: trigger a received data request to send data to party and guild when logging in
            openRaidLib.KeystoneInfoManager.OnReceiveRequestData()
        end
    end

    local bagUpdateEventFrame = _G["OpenRaidBagUpdateFrame"] or CreateFrame("frame", "OpenRaidBagUpdateFrame")
    bagUpdateEventFrame:RegisterEvent("BAG_UPDATE")
    bagUpdateEventFrame:RegisterEvent("ITEM_CHANGED")
    bagUpdateEventFrame:SetScript("OnEvent", function(bagUpdateEventFrame, event, ...)
        if (openRaidLib.KeystoneInfoManager.KeystoneChangedTimer) then
            return
        else
            openRaidLib.KeystoneInfoManager.KeystoneChangedTimer = C_Timer.NewTimer(2, checkForKeystoneChange)
        end
    end)

    --public callback does not check if the keystone has changed from the previous callback

    --API calls
        --return a table containing all information of units
        --format: [playerName-realm] = {information}
        function openRaidLib.GetAllKeystonesInfo()
            return openRaidLib.KeystoneInfoManager.GetAllKeystonesInfo()
        end

        --return a table containing information of a single unit
        function openRaidLib.GetKeystoneInfo(unitId)
            local unitName = GetUnitName(unitId, true) or unitId
            return openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName)
        end

        function openRaidLib.RequestKeystoneDataFromGuild()
            if (IsInGuild()) then
                local dataToSend = "" .. CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x4)
                diagnosticComm("RequestKeystoneDataFromGuild| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.RequestKeystoneDataFromParty()
            if (IsInGroup() and not IsInRaid()) then
                local dataToSend = "" .. CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x1)
                diagnosticComm("RequestKeystoneDataFromParty| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.RequestKeystoneDataFromRaid()
            if (IsInRaid()) then
                local dataToSend = "" .. CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX
                openRaidLib.commHandler.SendCommData(dataToSend, 0x2)
                diagnosticComm("RequestKeystoneDataFromRaid| " .. dataToSend) --debug
                return true
            else
                return false
            end
        end

        function openRaidLib.WipeKeystoneData()
            wipe(openRaidLib.KeystoneInfoManager.KeystoneData)
            --trigger public callback
            openRaidLib.publicCallback.TriggerCallback("KeystoneWipe", openRaidLib.KeystoneInfoManager.KeystoneData)

            --keystones are only available on retail
            if (not checkClientVersion("retail")) then
                return
            end

            --generate keystone info for the player
            local unitName = UnitName("player")
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
            openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

            openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
            return true
        end

    --privite stuff, these function can still be called, but not advised

        ---@type keystoneinfo
        local keystoneTablePrototype = {
            level = 0,
            mapID = 0,
            challengeMapID = 0,
            classID = 0,
            rating = 0,
            mythicPlusMapID = 0,
        }

    function openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)
        keystoneInfo.level = C_MythicPlus.GetOwnedKeystoneLevel() or 0
        keystoneInfo.mapID = C_MythicPlus.GetOwnedKeystoneMapID() or 0 --returning nil?
        keystoneInfo.mythicPlusMapID = getMythicPlusMapID() or 0
        keystoneInfo.challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0

        local _, _, playerClassID = UnitClass("player")
        keystoneInfo.classID = playerClassID

        local ratingSummary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        keystoneInfo.rating = ratingSummary and ratingSummary.currentSeasonScore or 0
    end

    function openRaidLib.KeystoneInfoManager.GetAllKeystonesInfo()
        return openRaidLib.KeystoneInfoManager.KeystoneData
    end

    --get the keystone info table or create a new one if 'createNew' is true
    function openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, createNew)
        local keystoneInfo = openRaidLib.KeystoneInfoManager.KeystoneData[unitName]
        if (not keystoneInfo and createNew) then
            keystoneInfo = {}
            openRaidLib.TCopy(keystoneInfo, keystoneTablePrototype)
            openRaidLib.KeystoneInfoManager.KeystoneData[unitName] = keystoneInfo
        end
        return keystoneInfo
    end

    local getKeystoneInfoToComm = function()
        local playerName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(playerName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        local dataToSend = CONST_COMM_KEYSTONE_DATA_PREFIX .. "," .. keystoneInfo.level .. "," .. keystoneInfo.mapID .. "," .. keystoneInfo.challengeMapID .. "," .. keystoneInfo.classID .. "," .. keystoneInfo.rating .. "," .. keystoneInfo.mythicPlusMapID
        return dataToSend
    end

    function openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty()
        local dataToSend = getKeystoneInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_PARTY)
        diagnosticComm("SendPlayerKeystoneInfoToParty| " .. dataToSend) --debug
    end

    function openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToGuild()
        local dataToSend = getKeystoneInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_GUILD)
        diagnosticComm("SendPlayerKeystoneInfoToGuild| " .. dataToSend) --debug
    end

    --when a request data is received, only send the data to party and guild
    --sending stuff to raid need to be called my the application with 'openRaidLib.RequestKeystoneDataFromRaid()'
    function openRaidLib.KeystoneInfoManager.OnReceiveRequestData()
        if (not checkClientVersion("retail")) then
            return
        end

        --update the information about the key stone the player has
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(UnitName("player"), true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        local _, instanceType = GetInstanceInfo()
        if (instanceType == "party") then
            openRaidLib.Schedules.NewUniqueTimer(math.random(1), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")

        elseif (instanceType == "raid" or instanceType == "pvp") then
            openRaidLib.Schedules.NewUniqueTimer(math.random(0, 30) + math.random(1), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")

        else
            openRaidLib.Schedules.NewUniqueTimer(math.random(4), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")
        end

        if (IsInGuild()) then
            openRaidLib.Schedules.NewUniqueTimer(math.random(0, 6) + math.random(), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToGuild, "KeystoneInfoManager", "sendKeystoneInfoToGuild_Schedule")
        end
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX, openRaidLib.KeystoneInfoManager.OnReceiveRequestData)

    function openRaidLib.KeystoneInfoManager.OnReceiveKeystoneData(data, unitName)
        if (not checkClientVersion("retail")) then
            return
        end

        local level = tonumber(data[1])
        local mapID = tonumber(data[2])
        local challengeMapID = tonumber(data[3])
        local classID = tonumber(data[4])
        local rating = tonumber(data[5])
        local mythicPlusMapID = tonumber(data[6])

        if (level and mapID and challengeMapID and classID and rating and mythicPlusMapID) then
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
            keystoneInfo.level = level
            keystoneInfo.mapID = mapID
            keystoneInfo.mythicPlusMapID = mythicPlusMapID
            keystoneInfo.challengeMapID = challengeMapID
            keystoneInfo.classID = classID
            keystoneInfo.rating = rating

            --trigger public callback
            openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
        end
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_KEYSTONE_DATA_PREFIX, openRaidLib.KeystoneInfoManager.OnReceiveKeystoneData)

    --on entering a group, send keystone information for the party
    function openRaidLib.KeystoneInfoManager.OnPlayerEnterGroup()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end

        if (IsInGroup() and not IsInRaid()) then
            --update the information about the key stone the player has
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(UnitName("player"), true)
            openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

            --send to the group which keystone the player has
            openRaidLib.Schedules.NewUniqueTimer(1 + math.random(0, 2) + math.random(), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")
        end
    end

    local keystoneManagerOnPlayerEnterWorld = function()
        --hack: trigger a received data request to send data to party and guild when logging in
        openRaidLib.KeystoneInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
    end

    function openRaidLib.KeystoneInfoManager.OnPlayerEnterWorld()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end

        --attempt to load keystone item link as reports indicate it can be nil
        getMythicPlusMapID()

        C_Timer.After(2, keystoneManagerOnPlayerEnterWorld)
    end

    function openRaidLib.KeystoneInfoManager.OnMythicDungeonFinished()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end
        --hack: on received data send data to party and guild
        openRaidLib.KeystoneInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
    end

    openRaidLib.internalCallback.RegisterCallback("onEnterWorld", openRaidLib.KeystoneInfoManager.OnPlayerEnterWorld)
    openRaidLib.internalCallback.RegisterCallback("onEnterGroup", openRaidLib.KeystoneInfoManager.OnPlayerEnterGroup)
    openRaidLib.internalCallback.RegisterCallback("mythicDungeonEnd", openRaidLib.KeystoneInfoManager.OnMythicDungeonFinished)

--------------------------------------------------------------------------------------------------------------------------------
--data

tempCache.RestoreData()


--------------------------------------------------------------------------------------------------------------------------------functions

-- These are taken from https://github.com/Tercioo/Open-Raid-Library/blob/main/Functions.lua
-- and unchanged. Should make upstreaming easy


--simple non recursive table copy
function openRaidLib.TCopy(tableToReceive, tableToCopy)
    if (not tableToCopy) then
        print(debugstack())
    end
    for key, value in pairs(tableToCopy) do
        tableToReceive[key] = value
    end
end

function openRaidLib.IsCommAllowed()
    return IsInGroup() or IsInRaid()
end

--returns if the player is in group
function openRaidLib.IsInGroup()
    local inParty = IsInGroup()
    local inRaid = IsInRaid()
    return inParty or inRaid
end

--transform a table index into a string dividing values with a comma
--@table: an indexed table with unknown size
function openRaidLib.PackTable(table)
    local tableSize = #table
    local newString = "" .. tableSize .. ","
    for i = 1, tableSize do
        newString = newString .. table[i] .. ","
    end

    newString = newString:gsub(",$", "")
    return newString
end

function openRaidLib.PackTableAndSubTables(table)
    local totalSize = 0
    local subTablesAmount = #table
    for i = 1, subTablesAmount do
        totalSize = totalSize + #table[i]
    end

    local newString = "" .. totalSize .. ","

    for i = 1, subTablesAmount do
        local subTable = table[i]
        for subIndex = 1, #subTable do
            newString = newString .. subTable[subIndex] .. ","
        end
    end

    newString = newString:gsub(",$", "")
    return newString
end

--transform a string table into a regular table
--@table: a table with unknown values
--@index: where in the table is the information we want
--@isPair: if true treat the table as pairs(), ipairs() otherwise
--@valueAsTable: return {value1, value2, value3}
--@amountOfValues: for the parameter above
function openRaidLib.UnpackTable(table, index, isPair, valueIsTable, amountOfValues)
    local result = {}
    local reservedIndexes = table[index]
    if (not reservedIndexes) then
        return result
    end
    local indexStart = index+1
    local indexEnd = reservedIndexes+index

    if (isPair) then
        amountOfValues = amountOfValues or 2
        for i = indexStart, indexEnd, amountOfValues do
            if (valueIsTable) then
                local key = tonumber(table[i])
                local values = selectIndexes(table, i+1, max(amountOfValues-2, 1), true)
                result[key] = values
            else
                local key = tonumber(table[i])
                local value = tonumber(table[i+1])
                result[key] = value
            end
        end
    else
        if (valueIsTable) then
            for i = indexStart, indexEnd, amountOfValues do
                local values = selectIndexes(table, i, amountOfValues - 1)
                tinsert(result, values)
            end
        else
            for i = indexStart, indexEnd do
                local value = tonumber(table[i])
                result[#result+1] = value
            end
        end
    end

    return result
end