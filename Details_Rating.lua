local addonName = ... ---@type string @The name of the addon.
local ns = select(2, ...) ---@class ns @The addon namespace.

--do not load if this is a classic version of the game
if (DetailsFramework.IsTBCWow() or DetailsFramework.IsWotLKWow() or DetailsFramework.IsClassicWow() or DetailsFramework.IsCataWow()) then
	return
end

local detailsFramework = DetailsFramework

SLASH_MYTHIC1 = "/mythic"
SLASH_MYTCHI2 = "/m"

function SlashCmdList.MYTHIC(msg, editbox)
	local DUNGEONS = ns.dungeons

	for i = 1, #DUNGEONS do
        local dungeon = DUNGEONS[i] ---@type Dungeon
		print(dungeon.shortName);
    end

	-- for i=1,GetNumPartyMembers() do 
    --     local roleName = "party"..i
	-- 	print(GetUnitName(roleName))
    -- end

	local openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0", true)
	if (openRaidLib) then
		if (not DetailsRatingInfoFrame) then
			---@type detailsframework
			local detailsFramework = detailsFramework

			local CONST_WINDOW_WIDTH = 614
			local CONST_WINDOW_HEIGHT = 300
			local CONST_SCROLL_LINE_HEIGHT = 20
			local CONST_SCROLL_LINE_AMOUNT = 30

			local backdrop_color = {.2, .2, .2, 0.2}
			local backdrop_color_on_enter = {.8, .8, .8, 0.4}

			local backdrop_color_inparty = {.5, .5, .8, 0.2}
			local backdrop_color_on_enter_inparty = {.5, .5, 1, 0.4}

			local backdrop_color_inguild = {.5, .8, .5, 0.2}
			local backdrop_color_on_enter_inguild = {.5, 1, .5, 0.4}

			local f = detailsFramework:CreateSimplePanel(UIParent, CONST_WINDOW_WIDTH, CONST_WINDOW_HEIGHT, "Mythic Levels (/mythic)", "DetailsRatingInfoFrame")
			f:SetPoint("center", UIParent, "center", 0, 0)

			f:SetScript("OnMouseDown", nil) --disable framework native moving scripts
			f:SetScript("OnMouseUp", nil) --disable framework native moving scripts

			local LibWindow = LibStub("LibWindow-1.1")
			LibWindow.RegisterConfig(f, Details.keystone_frame.position)
			LibWindow.MakeDraggable(f)
			LibWindow.RestorePosition(f)

			f:SetScript("OnEvent", function(self, event, ...)
				if (f:IsShown()) then
					if (event == "GUILD_ROSTER_UPDATE") then
						self:RefreshData()
					end
				end
			end)

			local statusBar = detailsFramework:CreateStatusBar(f)
			statusBar.text = statusBar:CreateFontString(nil, "overlay", "GameFontNormal")
			statusBar.text:SetPoint("left", statusBar, "left", 5, 0)
			statusBar.text:SetText("By Terciob | From Details! Damage Meter")
			detailsFramework:SetFontSize(statusBar.text, 12)
			detailsFramework:SetFontColor(statusBar.text, "gray")

			-- local requestFromGuildButton = detailsFramework:CreateButton(f, function()
			-- 	local guildName = GetGuildInfo("player")
			-- 	if (guildName) then
			-- 		f:RegisterEvent("GUILD_ROSTER_UPDATE")

			-- 		C_Timer.NewTicker(1, function()
			-- 			f:RefreshData()
			-- 		end, 30)

			-- 		C_Timer.After(30, function()
			-- 			f:UnregisterEvent("GUILD_ROSTER_UPDATE")
			-- 		end)
			-- 		C_GuildInfo.GuildRoster()

			-- 		openRaidLib.RequestKeystoneDataFromGuild()
			-- 	end
			-- end, 100, 22, "Request from Guild")
			-- requestFromGuildButton:SetPoint("bottomleft", statusBar, "topleft", 2, 2)
			-- requestFromGuildButton:SetTemplate(detailsFramework:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE"))
			-- requestFromGuildButton:SetIcon("UI-RefreshButton", 20, 20, "overlay", {0, 1, 0, 1}, "lawngreen")
			-- requestFromGuildButton:SetFrameLevel(f:GetFrameLevel()+5)
			-- f.RequestFromGuildButton = requestFromGuildButton

			--header``

			local headerTable = {}
			table.insert(headerTable, {
				text = "", -- Player Name
				width = 140,        
				canSort = true,
				dataType = "string",
				order = "DESC",
				offset = 0
			})

			for i = 1, #DUNGEONS do
				local dungeon = DUNGEONS[i] ---@type Dungeon
				table.insert(headerTable, {
					text = dungeon.shortName,
					width = 40,        -- Adjust width as needed
					canSort = true,
					dataType = "string", -- Assuming shortName is a string, adjust if necessary
					order = "DESC",
					offset = 0
				})
			end

			-- local headerTable = {
			-- 	{text = "", width = 140, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Class", width = 40, canSort = true, dataType = "number", order = "DESC", offset = 0},
			-- 	{text = "Player Name", width = 140, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Level", width = 60, canSort = true, dataType = "number", order = "DESC", offset = 0, selected = true},
			-- 	{text = "Dungeon", width = 240, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	--{text = "Classic Dungeon", width = 120, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Mythic+ Rating", width = 100, canSort = true, dataType = "number", order = "DESC", offset = 0},
			-- }

			-- local headerTable = {
			-- 	{text = "ShortName", width = 40, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Class", width = 40, canSort = true, dataType = "number", order = "DESC", offset = 0},
			-- 	{text = "Player Name", width = 140, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Level", width = 60, canSort = true, dataType = "number", order = "DESC", offset = 0, selected = true},
			-- 	{text = "Dungeon", width = 240, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	--{text = "Classic Dungeon", width = 120, canSort = true, dataType = "string", order = "DESC", offset = 0},
			-- 	{text = "Mythic+ Rating", width = 100, canSort = true, dataType = "number", order = "DESC", offset = 0},
			-- }

			local headerOnClickCallback = function(headerFrame, columnHeader)
				f.RefreshData()
			end

			local headerOptions = {
				padding = 1,
				header_backdrop_color = {.3, .3, .3, .8},
				header_backdrop_color_selected = {.5, .5, .5, 0.8},
				use_line_separators = true,
				line_separator_color = {.1, .1, .1, .5},
				line_separator_width = 1,
				line_separator_height = CONST_WINDOW_HEIGHT-30,
				line_separator_gap_align = true,
				header_click_callback = headerOnClickCallback,
			}

			f.Header = detailsFramework:CreateHeader(f, headerTable, headerOptions, "DetailsRatingInfoFrameHeader")
			f.Header:SetPoint("topleft", f, "topleft", 3, -25)

			--scroll
			local refreshScrollLines = function(self, data, offset, totalLines)
				local RaiderIO = _G.RaiderIO
				local faction = UnitFactionGroup("player") --this can get problems with 9.2.5 cross faction raiding

				for i = 1, totalLines do
					local index = i + offset
					local unitTable = data[index]

					if (unitTable) then
						local line = self:GetLine(i)

						local unitName, level, mapID, challengeMapID, classID, rating, mythicPlusMapID, classIconTexture, iconTexCoords, mapName, inMyParty, isOnline, isGuildMember = unpack(unitTable)

						if (mapName == "") then
							mapName = "user need update details!"
						end

						local rioProfile
						if (RaiderIO) then
							local playerName, playerRealm = unitName:match("(.+)%-(.+)")
							if (playerName and playerRealm) then
								rioProfile = RaiderIO.GetProfile(playerName, playerRealm, faction == "Horde" and 2 or 1)
								if (rioProfile) then
									rioProfile = rioProfile.mythicKeystoneProfile
								end
							else
								rioProfile = RaiderIO.GetProfile(unitName, GetRealmName(), faction == "Horde" and 2 or 1)
								if (rioProfile) then
									rioProfile = rioProfile.mythicKeystoneProfile
								end
							end
						end

						line.icon:SetTexture(classIconTexture)
						local L, R, T, B = unpack(iconTexCoords)
						line.icon:SetTexCoord(L+0.02, R-0.02, T+0.02, B-0.02)

						--remove the realm name from the player name (if any)
						local unitNameNoRealm = detailsFramework:RemoveRealmName(unitName)
						line.playerNameText.text = unitNameNoRealm
						line.keystoneLevelText.text = level
						line.dungeonNameText.text = mapName
						detailsFramework:TruncateText(line.dungeonNameText, 240)
						line.classicDungeonNameText.text = "" --mapNameChallenge
						detailsFramework:TruncateText(line.classicDungeonNameText, 120)
						line.inMyParty = inMyParty > 0
						line.inMyGuild = isGuildMember

						if (rioProfile) then
							local score = rioProfile.currentScore or 0
							local previousScore = rioProfile.previousScore or 0
							if (previousScore > score) then
								score = previousScore
								line.ratingText.text = rating .. " (" .. score .. ")"
							else
								line.ratingText.text = rating
							end
						else
							line.ratingText.text = rating
						end

						if (line.inMyParty) then
							line:SetBackdropColor(unpack(backdrop_color_inparty))
						elseif (isGuildMember) then
							line:SetBackdropColor(unpack(backdrop_color_inguild))
						else
							line:SetBackdropColor(unpack(backdrop_color))
						end

						if (isOnline) then
							line.playerNameText.textcolor = "white"
							line.keystoneLevelText.textcolor = "white"
							line.dungeonNameText.textcolor = "white"
							line.classicDungeonNameText.textcolor = "white"
							line.ratingText.textcolor = "white"
							line.icon:SetAlpha(1)
						else
							line.playerNameText.textcolor = "gray"
							line.keystoneLevelText.textcolor = "gray"
							line.dungeonNameText.textcolor = "gray"
							line.classicDungeonNameText.textcolor = "gray"
							line.ratingText.textcolor = "gray"
							line.icon:SetAlpha(.6)
						end
					end
				end
			end

			local scrollFrame = detailsFramework:CreateScrollBox(f, "$parentScroll", refreshScrollLines, {}, CONST_WINDOW_WIDTH-10, CONST_WINDOW_HEIGHT-90, CONST_SCROLL_LINE_AMOUNT, CONST_SCROLL_LINE_HEIGHT)
			detailsFramework:ReskinSlider(scrollFrame)
			scrollFrame:SetPoint("topleft", f.Header, "bottomleft", -1, -1)
			scrollFrame:SetPoint("topright", f.Header, "bottomright", 0, -1)

			local lineOnEnter = function(self)
				if (self.inMyParty) then
					self:SetBackdropColor(unpack(backdrop_color_on_enter_inparty))
				elseif (self.inMyGuild) then
					self:SetBackdropColor(unpack(backdrop_color_on_enter_inguild))
				else
					self:SetBackdropColor(unpack(backdrop_color_on_enter))
				end
			end
			local lineOnLeave = function(self)
				if (self.inMyParty) then
					self:SetBackdropColor(unpack(backdrop_color_inparty))
				elseif (self.inMyGuild) then
					self:SetBackdropColor(unpack(backdrop_color_inguild))
				else
					self:SetBackdropColor(unpack(backdrop_color))
				end
			end

			local createLineForScroll = function(self, index)
				local line = CreateFrame("frame", "$parentLine" .. index, self, "BackdropTemplate")
				line:SetPoint("topleft", self, "topleft", 1, -((index-1) * (CONST_SCROLL_LINE_HEIGHT + 1)) - 1)
				line:SetSize(scrollFrame:GetWidth() - 2, CONST_SCROLL_LINE_HEIGHT)

				line:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true})
				line:SetBackdropColor(unpack(backdrop_color))

				detailsFramework:Mixin(line, detailsFramework.HeaderFunctions)

				line:SetScript("OnEnter", lineOnEnter)
				line:SetScript("OnLeave", lineOnLeave)

				--class icon
				local icon = line:CreateTexture("$parentClassIcon", "overlay")
				icon:SetSize(CONST_SCROLL_LINE_HEIGHT - 2, CONST_SCROLL_LINE_HEIGHT - 2)

				--player name
				local playerNameText = detailsFramework:CreateLabel(line, "")

				--keystone level
				local keystoneLevelText = detailsFramework:CreateLabel(line, "")

				--dungeon name
				local dungeonNameText = detailsFramework:CreateLabel(line, "")

				--classic dungeon name
				local classicDungeonNameText = detailsFramework:CreateLabel(line, "")

				--player rating
				local ratingText = detailsFramework:CreateLabel(line, "")

				line.icon = icon
				line.playerNameText = playerNameText
				line.keystoneLevelText = keystoneLevelText
				line.dungeonNameText = dungeonNameText
				line.classicDungeonNameText = classicDungeonNameText
				line.ratingText = ratingText

				line:AddFrameToHeaderAlignment(playerNameText)
				line:AddFrameToHeaderAlignment(keystoneLevelText)
				line:AddFrameToHeaderAlignment(dungeonNameText)
				line:AddFrameToHeaderAlignment(ratingText)
				line:AddFrameToHeaderAlignment(ratingText)
				line:AddFrameToHeaderAlignment(ratingText)
				line:AddFrameToHeaderAlignment(ratingText)
				line:AddFrameToHeaderAlignment(ratingText)
				line:AddFrameToHeaderAlignment(ratingText)

				line:AlignWithHeader(f.Header, "left")
				return line
			end

			--create lines
			for i = 1, CONST_SCROLL_LINE_AMOUNT do
				scrollFrame:CreateLine(createLineForScroll)
			end

			function f.RefreshData()
				local newData = {}
				newData.offlineGuildPlayers = {}
				local keystoneData = openRaidLib.GetAllKeystonesInfo()

				--[=[
					["Exudragão"] =  {
						["mapID"] = 2526,
						["challengeMapID"] = 402,
						["mythicPlusMapID"] = 0,
						["rating"] = 215,
						["classID"] = 13,
						["level"] = 6,
					},
				--]=]

				local guildUsers = {}
				local totalMembers, onlineMembers, onlineAndMobileMembers = GetNumGuildMembers()

				--[=[
				local unitsInMyGroup = {
					[Details:GetFullName("player")] = true,
				}
				for i = 1, GetNumGroupMembers() do
					local unitName = Details:GetFullName("party" .. i)
					unitsInMyGroup[unitName] = true
				end
				--]=]

				--create a string to use into the gsub call when removing the realm name from the player name, by default all player names returned from GetGuildRosterInfo() has PlayerName-RealmName format
				local realmNameGsub = "%-.*"
				local guildName = GetGuildInfo("player")

				if (guildName) then
					for i = 1, totalMembers do
						local fullName, rank, rankIndex, level, class, zone, note, officernote, online, isAway, classFileName, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
						if (fullName) then
							fullName = fullName:gsub(realmNameGsub, "")
							if (online) then
								guildUsers[fullName] = true
							end
						else
							break
						end
					end
				end

				if (keystoneData) then
					local unitsAdded = {}
					local isOnline = true

					for unitName, keystoneInfo in pairs(keystoneData) do
						local classId = keystoneInfo.classID
						local classIcon = [[Interface\GLUES\CHARACTERCREATE\UI-CharacterCreate-Classes]]
						local coords = CLASS_ICON_TCOORDS
						local _, class = GetClassInfo(classId)

						local mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.mythicPlusMapID)
						if (not mapName) then
							mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.challengeMapID)
						end
						if (not mapName and keystoneInfo.mapID) then
							mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.mapID)
						end

						mapName = mapName or "map name not found"

						--local mapInfoChallenge = C_Map.GetMapInfo(keystoneInfo.challengeMapID)
						--local mapNameChallenge = mapInfoChallenge and mapInfoChallenge.name or ""

						local isInMyParty = UnitInParty(unitName) and (string.byte(unitName, 1) + string.byte(unitName, 2)) or 0
						local isGuildMember = guildName and guildUsers[unitName] and true

						if (keystoneInfo.level > 0 or keystoneInfo.rating > 0) then
							local keystoneTable = {
								unitName,
								keystoneInfo.level,
								keystoneInfo.mapID,
								keystoneInfo.challengeMapID,
								keystoneInfo.classID,
								keystoneInfo.rating,
								keystoneInfo.mythicPlusMapID,
								classIcon,
								coords[class],
								mapName, --10
								isInMyParty,
								isOnline, --is false when the unit is from the cache
								isGuildMember, --is a guild member
								--mapNameChallenge,
							}

							newData[#newData+1] = keystoneTable --this is the table added into the keystone cache
							unitsAdded[unitName] = true

							--is this unitName listed as a player in the player's guild?
							if (isGuildMember) then
								--store the player information into a cache
								keystoneTable.guild_name = guildName
								keystoneTable.date = time()
								Details.keystone_cache[unitName] = keystoneTable
							end
						end
					end

					local cutoffDate = time() - (86400 * 7) --7 days
					for unitName, keystoneTable in pairs(Details.keystone_cache) do
						--this unit in the cache isn't shown?
						if (not unitsAdded[unitName] and keystoneTable.guild_name == guildName and keystoneTable.date > cutoffDate) then
							if (keystoneTable[2] > 0 or keystoneTable[6] > 0) then
								keystoneTable[11] = UnitInParty(unitName) and (string.byte(unitName, 1) + string.byte(unitName, 2)) or 0 --isInMyParty
								keystoneTable[12] = false --isOnline
								newData[#newData+1] = keystoneTable
								unitsAdded[unitName] = true
							end
						end
					end
				end

				--get which column is currently selected and the sort order
				local columnIndex, order = f.Header:GetSelectedColumn()
				local sortByIndex = 2

				--sort by player class
				if (columnIndex == 1) then
					sortByIndex = 5

				--sort by player name
				elseif (columnIndex == 2) then
					sortByIndex = 1

				--sort by keystone level
				elseif (columnIndex == 3) then
					sortByIndex = 2

				--sort by dungeon name
				elseif (columnIndex == 4) then
					sortByIndex = 3

				--sort by classic dungeon name
				--elseif (columnIndex == 5) then
				--	sortByIndex = 4

				--sort by mythic+ ranting
				elseif (columnIndex == 5) then
					sortByIndex = 6
				end

				if (order == "DESC") then
					table.sort(newData, function(t1, t2) return t1[sortByIndex] > t2[sortByIndex] end)
				else
					table.sort(newData, function(t1, t2) return t1[sortByIndex] < t2[sortByIndex] end)
				end

				--remove offline guild players from the list
				for i = #newData, 1, -1 do
					local keystoneTable = newData[i]
					if (not keystoneTable[12]) then
						tremove(newData, i)
						newData.offlineGuildPlayers[#newData.offlineGuildPlayers+1] = keystoneTable
					end
				end

				newData.offlineGuildPlayers = detailsFramework.table.reverse(newData.offlineGuildPlayers)

				--put players in the group at the top of the list
				if (IsInGroup() and not IsInRaid()) then
					local playersInTheParty = {}
					for i = #newData, 1, -1 do
						local keystoneTable = newData[i]
						if (keystoneTable[11] > 0) then
							playersInTheParty[#playersInTheParty+1] = keystoneTable
							tremove(newData, i)
						end
					end

					if (#playersInTheParty > 0) then
						table.sort(playersInTheParty, function(t1, t2) return t1[11] > t2[11] end)
						for i = 1, #playersInTheParty do
							local keystoneTable = playersInTheParty[i]
							table.insert(newData, 1, keystoneTable)
						end
					end
				end

				--reinsert offline guild players into the data
				local offlinePlayers = newData.offlineGuildPlayers
				for i = 1, #offlinePlayers do
					local keystoneTable = offlinePlayers[i]
					newData[#newData+1] = keystoneTable
				end

				scrollFrame:SetData(newData)
				scrollFrame:Refresh()
			end

			function f.OnKeystoneUpdate(unitId, keystoneInfo, allKeystonesInfo)
				if (f:IsShown()) then
					f.RefreshData()
				end
			end

			f:SetScript("OnHide", function()
				openRaidLib.UnregisterCallback(DetailsRatingInfoFrame, "KeystoneUpdate", "OnKeystoneUpdate")
			end)

			f:SetScript("OnUpdate", function(self, deltaTime)
				if (not self.lastUpdate) then
					self.lastUpdate = 0
				end

				self.lastUpdate = self.lastUpdate + deltaTime
				if (self.lastUpdate > 1) then
					self.lastUpdate = 0
					self.RefreshData()
				end
			end)
			end

			--show the frame
			DetailsRatingInfoFrame:Show()

			openRaidLib.RegisterCallback(DetailsRatingInfoFrame, "KeystoneUpdate", "OnKeystoneUpdate")

			local guildName = GetGuildInfo("player")
			if (guildName) then
				--call an update on the guild roster
				if (C_GuildInfo and C_GuildInfo.GuildRoster) then
					C_GuildInfo.GuildRoster()
				end
				DetailsRatingInfoFrame.RequestFromGuildButton:Enable()
			else
				DetailsRatingInfoFrame.RequestFromGuildButton:Disable()
			end

			--openRaidLib.WipeKeystoneData()

			if (IsInRaid()) then
				openRaidLib.RequestKeystoneDataFromRaid()
			elseif (IsInGroup()) then
				openRaidLib.RequestKeystoneDataFromParty()
			end

			DetailsRatingInfoFrame.RefreshData()
		end
end