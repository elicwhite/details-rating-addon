local addonName = ... ---@type string @The name of the addon.
local ns = select(2, ...) ---@class ns @The addon namespace.

--do not load if this is a classic version of the game
if (DetailsFramework.IsTBCWow() or DetailsFramework.IsWotLKWow() or DetailsFramework.IsClassicWow() or DetailsFramework.IsCataWow()) then
	return
end

---@type detailsframework
local detailsFramework = DetailsFramework

SLASH_MYTHIC1 = "/mythic"
SLASH_MYTCHI2 = "/rg"

function SlashCmdList.MYTHIC(msg, editbox)
	if rating_cache == nil then
		rating_cache = {}
	end


	local DUNGEONS = ns.dungeons

	table.sort(DUNGEONS, function(d1, d2) return d1.shortName < d2.shortName end)

	-- for i=1,GetNumPartyMembers() do 
    --     local roleName = "party"..i
	-- 	print(GetUnitName(roleName))
    -- end

	---@module 'Comms'
	local openRaidLibRating = LibStub:GetLibrary("LibOpenRaid_Rating-1.0", true)
	local openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0", true)

	if (openRaidLib and openRaidLibRating) then
		if (not DetailsRatingInfoFrame) then
			
			local CONST_WINDOW_WIDTH = 512
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
					if (event == "GROUP_ROSTER_UPDATE") then
						self:RefreshRatingData()
					end
				end
			end)

			local statusBar = detailsFramework:CreateStatusBar(f)
			statusBar.text = statusBar:CreateFontString(nil, "overlay", "GameFontNormal")
			statusBar.text:SetPoint("left", statusBar, "left", 5, 0)
			statusBar.text:SetText("By Withertea | From Details! Group Rating")
			detailsFramework:SetFontSize(statusBar.text, 12)
			detailsFramework:SetFontColor(statusBar.text, "gray")

			local requestFromPartyButton = detailsFramework:CreateButton(f, function()
				if (IsInGroup()) then
					f:RegisterEvent("GROUP_ROSTER_UPDATE")

					C_Timer.NewTicker(1, function()
						f:RefreshRatingData()
					end, 30)

					C_Timer.After(30, function()
						f:UnregisterEvent("GROUP_ROSTER_UPDATE")
					end)

					openRaidLibRating.RequestRatingDataFromParty()
				end
			end, 100, 22, "Request from Party")
			requestFromPartyButton:SetPoint("bottomleft", statusBar, "topleft", 2, 2)
			requestFromPartyButton:SetTemplate(detailsFramework:GetTemplate("button", "OPTIONS_BUTTON_TEMPLATE"))
			requestFromPartyButton:SetIcon("UI-RefreshButton", 20, 20, "overlay", {0, 1, 0, 1}, "lawngreen")
			requestFromPartyButton:SetFrameLevel(f:GetFrameLevel()+5)
			f.RequestFromPartyButton = requestFromPartyButton

			--header

			local headerTable = {}
			table.insert(headerTable, {
				text = "", -- Player Name
				width = 80,
				canSort = true,
				dataType = "string",
				order = "DESC",
				offset = 0
			})

			table.insert(headerTable, {
				text = "", -- Current rating
				width = 40,        
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
					offset = 0,
					-- align = "left"
				})
			end

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
				f.RefreshRatingData()
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

						local unitName, classID, currentSeasonScore, runs, inMyParty, isOnline = unpack(unitTable)

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

						-- local dungeon = DUNGEONS[i]
						-- if (dungeon) then
						-- 	line.shortNameText.text = dungeon.shortName
						-- else 
						-- 	line.shortNameText.text = ""
						-- end

						--remove the realm name from the player name (if any)
						local unitNameNoRealm = detailsFramework:RemoveRealmName(unitName)
						line.playerNameText.text = unitNameNoRealm
						detailsFramework:TruncateText(line.playerNameText, 80)

						line.currentSeasonScoreText.text = currentSeasonScore

						for i = 1, #DUNGEONS do
							local dungeon = DUNGEONS[i]
							line.dungeonRatingTexts[i].text = runs[dungeon.keystone_instance].bestRunLevel or ""
						end

						-- line.keystoneLevelText.text = level
						-- line.dungeonNameText.text = mapName
						-- detailsFramework:TruncateText(line.dungeonNameText, 240)
						-- line.classicDungeonNameText.text = "" --mapNameChallenge
						-- detailsFramework:TruncateText(line.classicDungeonNameText, 120)
						line.inMyParty = inMyParty > 0
						-- line.inMyGuild = isGuildMember

						-- if (rioProfile) then
						-- 	local score = rioProfile.currentScore or 0
						-- 	local previousScore = rioProfile.previousScore or 0
						-- 	if (previousScore > score) then
						-- 		score = previousScore
						-- 		line.ratingText.text = rating .. " (" .. score .. ")"
						-- 	else
						-- 		line.ratingText.text = rating
						-- 	end
						-- else
						-- 	line.ratingText.text = rating
						-- end

						if (line.inMyParty) then
							line:SetBackdropColor(unpack(backdrop_color_inparty))
						-- elseif (isGuildMember) then
						-- 	line:SetBackdropColor(unpack(backdrop_color_inguild))
						else
							line:SetBackdropColor(unpack(backdrop_color))
						end

						local _, className = GetClassInfo(classID)
						
						line.playerNameText.textcolor = className
						if (isOnline) then
							-- line.shortNameText.textcolor = "white"
							line.currentSeasonScoreText.textcolor = {RaiderIO.GetScoreColor(currentSeasonScore)}
							
							-- line.keystoneLevelText.textcolor = "white"
							-- line.dungeonNameText.textcolor = "white"
							-- line.classicDungeonNameText.textcolor = "white"
							-- line.ratingText.textcolor = "white"
						else
							line.currentSeasonScoreText.textcolor = "gray"

							for i = 1, #DUNGEONS do
								line.dungeonRatingTexts[i].textcolor = "gray"
							end

						-- 	line.shortNameText.textcolor = "gray"
						-- 	line.playerNameText.textcolor = "gray"
						-- 	line.keystoneLevelText.textcolor = "gray"
						-- 	line.dungeonNameText.textcolor = "gray"
						-- 	line.classicDungeonNameText.textcolor = "gray"
						-- 	line.ratingText.textcolor = "gray"
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
				-- elseif (self.inMyGuild) then
				-- 	self:SetBackdropColor(unpack(backdrop_color_on_enter_inguild))
				else
					self:SetBackdropColor(unpack(backdrop_color_on_enter))
				end
			end
			local lineOnLeave = function(self)
				if (self.inMyParty) then
					self:SetBackdropColor(unpack(backdrop_color_inparty))
				-- elseif (self.inMyGuild) then
				-- 	self:SetBackdropColor(unpack(backdrop_color_inguild))
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

				-- dungeon shortName
				-- local shortNameText = detailsFramework:CreateLabel(line, "")


				local dungeonTexts = {}
				for i = 1, #DUNGEONS do
					local dungeonText = detailsFramework:CreateLabel(line, "")

					table.insert(dungeonTexts, dungeonText)
				end

				line.dungeonRatingTexts = dungeonTexts


				--player name
				local playerNameText = detailsFramework:CreateLabel(line, "")

				-- player rating
				local currentSeasonScoreText = detailsFramework:CreateLabel(line, "")

				-- --keystone level
				-- local keystoneLevelText = detailsFramework:CreateLabel(line, "")

				-- --dungeon name
				-- local dungeonNameText = detailsFramework:CreateLabel(line, "")

				-- --classic dungeon name
				-- local classicDungeonNameText = detailsFramework:CreateLabel(line, "")

				-- --player rating
				-- local ratingText = detailsFramework:CreateLabel(line, "")

				-- line.shortNameText = shortNameText
				line.playerNameText = playerNameText
				line.currentSeasonScoreText = currentSeasonScoreText
				-- line.keystoneLevelText = keystoneLevelText
				-- line.dungeonNameText = dungeonNameText
				-- line.classicDungeonNameText = classicDungeonNameText
				-- line.ratingText = ratingText
				
				line:AddFrameToHeaderAlignment(playerNameText)
				line:AddFrameToHeaderAlignment(currentSeasonScoreText)

				for i = 1, #DUNGEONS do
					local dungeonText = dungeonTexts[i]
					line:AddFrameToHeaderAlignment(dungeonText)
				end


				-- line:AddFrameToHeaderAlignment(shortNameText)
				-- line:AddFrameToHeaderAlignment(keystoneLevelText)
				-- line:AddFrameToHeaderAlignment(dungeonNameText)
				-- --line:AddFrameToHeaderAlignment(classicDungeonNameText)
				-- line:AddFrameToHeaderAlignment(ratingText)

				line:AlignWithHeader(f.Header, "left")
				return line
			end

			--create lines
			for i = 1, CONST_SCROLL_LINE_AMOUNT do
				scrollFrame:CreateLine(createLineForScroll)
			end

			local GetOnlineBNetFriends = function()
				local onlineFriendCharacters = {}

				local numBNetTotal = BNGetNumFriends()

				--- I should perhaps include C_FriendList friends too
				for i = 1, numBNetTotal do
					local friendInfo = C_BattleNet.GetFriendAccountInfo(i)
			
					-- Check if the friend is online
					if friendInfo and friendInfo.gameAccountInfo.isOnline then
						local characterName = friendInfo.gameAccountInfo.characterName
						local clientProgram = friendInfo.gameAccountInfo.clientProgram
			
						if characterName ~= nil and clientProgram == "WoW" then
							onlineFriendCharacters[characterName] = true
						end
					end
				end

				return onlineFriendCharacters;
			end
			
			function f.RefreshRatingData()
				local newData = {}

				local onlineFriends = GetOnlineBNetFriends()

				---@as table<string, ratinginfo>
				local ratingData = openRaidLibRating.GetAllRatingInfo()


				if (ratingData) then
					local unitsAdded = {}
					local isOnline = true

					for unitName, ratingInfo in pairs(ratingData) do
						local isInMyParty = UnitInParty(unitName) and (string.byte(unitName, 1) + string.byte(unitName, 2)) or 0

						if (ratingInfo.currentSeasonScore > 0) then
							local ratingTable = {
								unitName,
								ratingInfo.classID,
								ratingInfo.currentSeasonScore,
								ratingInfo.runs,
								isInMyParty,
								isOnline, --is false when the unit is from the cache
							}

							newData[#newData+1] = ratingTable
							unitsAdded[unitName] = true

							--is this unitName listed as a player in the player's guild?
							if (onlineFriends[unitName]) then
								--store the player information into a cache
								ratingTable.date = time()
								rating_cache[unitName] = ratingTable
							end
						end
					end

					local cutoffDate = time() - (86400 * 7) --7 days
					for unitName, ratingTable in pairs(rating_cache) do
						--this unit in the cache isn't shown?
						if (not unitsAdded[unitName] and ratingTable.date > cutoffDate) then
							if (ratingTable[3] > 0) then --if they have rating this season
								ratingTable[5] = false --isOnline
								
								newData[#newData+1] = ratingTable
								unitsAdded[unitName] = true
							end
						end
					end
				end

				scrollFrame:SetData(newData)
				scrollFrame:Refresh()
			end

			function f.OnRatingUpdate(unitId, keystoneInfo, allRatingsInfo)
				if (f:IsShown()) then
					f.RefreshRatingData()
				end
			end

			f:SetScript("OnHide", function()
				openRaidLib.UnregisterCallback(DetailsRatingInfoFrame, "RatingUpdate", "OnRatingUpdate")
			end)

			f:SetScript("OnUpdate", function(self, deltaTime)
				if (not self.lastUpdate) then
					self.lastUpdate = 0
				end

				self.lastUpdate = self.lastUpdate + deltaTime
				if (self.lastUpdate > 1) then
					self.lastUpdate = 0
					self.RefreshRatingData()
				end
			end)

			-- function f.RefreshData()
			-- 	local newData = {}
			-- 	newData.offlineGuildPlayers = {}
			-- 	local keystoneData = openRaidLib.GetAllKeystonesInfo()
			-- 	openRaidLibRating.WipeRatingData()
			-- 	local ratingData = openRaidLibRating.GetAllRatingInfo()
				

			-- 	-- DevTools_Dump(ratingData)

			-- 	--[=[
			-- 		["Exudragão"] =  {
			-- 			["mapID"] = 2526,
			-- 			["challengeMapID"] = 402,
			-- 			["mythicPlusMapID"] = 0,
			-- 			["rating"] = 215,
			-- 			["classID"] = 13,
			-- 			["level"] = 6,
			-- 		},
			-- 	--]=]

			-- 	local guildUsers = {}
			-- 	local totalMembers, onlineMembers, onlineAndMobileMembers = GetNumGuildMembers()

			-- 	--[=[
			-- 	local unitsInMyGroup = {
			-- 		[Details:GetFullName("player")] = true,
			-- 	}
			-- 	for i = 1, GetNumGroupMembers() do
			-- 		local unitName = Details:GetFullName("party" .. i)
			-- 		unitsInMyGroup[unitName] = true
			-- 	end
			-- 	--]=]

			-- 	--create a string to use into the gsub call when removing the realm name from the player name, by default all player names returned from GetGuildRosterInfo() has PlayerName-RealmName format
			-- 	local realmNameGsub = "%-.*"
			-- 	local guildName = GetGuildInfo("player")

			-- 	if (guildName) then
			-- 		for i = 1, totalMembers do
			-- 			local fullName, rank, rankIndex, level, class, zone, note, officernote, online, isAway, classFileName, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
			-- 			if (fullName) then
			-- 				fullName = fullName:gsub(realmNameGsub, "")
			-- 				if (online) then
			-- 					guildUsers[fullName] = true
			-- 				end
			-- 			else
			-- 				break
			-- 			end
			-- 		end
			-- 	end

			-- 	if (keystoneData) then
			-- 		local unitsAdded = {}
			-- 		local isOnline = true

			-- 		for unitName, keystoneInfo in pairs(keystoneData) do
			-- 			local classId = keystoneInfo.classID
			-- 			local _, class = GetClassInfo(classId)

			-- 			local mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.mythicPlusMapID)
			-- 			if (not mapName) then
			-- 				mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.challengeMapID)
			-- 			end
			-- 			if (not mapName and keystoneInfo.mapID) then
			-- 				mapName = C_ChallengeMode.GetMapUIInfo(keystoneInfo.mapID)
			-- 			end

			-- 			mapName = mapName or "map name not found"

			-- 			--local mapInfoChallenge = C_Map.GetMapInfo(keystoneInfo.challengeMapID)
			-- 			--local mapNameChallenge = mapInfoChallenge and mapInfoChallenge.name or ""

			-- 			local isInMyParty = UnitInParty(unitName) and (string.byte(unitName, 1) + string.byte(unitName, 2)) or 0
			-- 			local isGuildMember = guildName and guildUsers[unitName] and true

			-- 			if (keystoneInfo.level > 0 or keystoneInfo.rating > 0) then
			-- 				local keystoneTable = {
			-- 					unitName,
			-- 					keystoneInfo.level,
			-- 					keystoneInfo.mapID,
			-- 					keystoneInfo.challengeMapID,
			-- 					keystoneInfo.classID,
			-- 					keystoneInfo.rating,
			-- 					keystoneInfo.mythicPlusMapID,

			-- 					mapName, --10
			-- 					isInMyParty,
			-- 					isOnline, --is false when the unit is from the cache
			-- 					isGuildMember, --is a guild member
			-- 					--mapNameChallenge,
			-- 				}

			-- 				newData[#newData+1] = keystoneTable --this is the table added into the keystone cache
			-- 				unitsAdded[unitName] = true

			-- 				--is this unitName listed as a player in the player's guild?
			-- 				if (isGuildMember) then
			-- 					--store the player information into a cache
			-- 					keystoneTable.guild_name = guildName
			-- 					keystoneTable.date = time()
			-- 					Details.rating_cache[unitName] = keystoneTable
			-- 				end
			-- 			end
			-- 		end

			-- 		local cutoffDate = time() - (86400 * 7) --7 days
			-- 		for unitName, keystoneTable in pairs(Details.rating_cache) do
			-- 			--this unit in the cache isn't shown?
			-- 			if (not unitsAdded[unitName] and keystoneTable.guild_name == guildName and keystoneTable.date > cutoffDate) then
			-- 				if (keystoneTable[2] > 0 or keystoneTable[6] > 0) then
			-- 					keystoneTable[9] = UnitInParty(unitName) and (string.byte(unitName, 1) + string.byte(unitName, 2)) or 0 --isInMyParty
			-- 					keystoneTable[10] = false --isOnline
			-- 					newData[#newData+1] = keystoneTable
			-- 					unitsAdded[unitName] = true
			-- 				end
			-- 			end
			-- 		end
			-- 	end

			-- 	--get which column is currently selected and the sort order
			-- 	local columnIndex, order = f.Header:GetSelectedColumn()
			-- 	local sortByIndex = 2

			-- 	--sort by player class
			-- 	if (columnIndex == 1) then
			-- 		sortByIndex = 5

			-- 	--sort by player name
			-- 	elseif (columnIndex == 2) then
			-- 		sortByIndex = 1

			-- 	--sort by keystone level
			-- 	elseif (columnIndex == 3) then
			-- 		sortByIndex = 2

			-- 	--sort by dungeon name
			-- 	elseif (columnIndex == 4) then
			-- 		sortByIndex = 3

			-- 	--sort by classic dungeon name
			-- 	--elseif (columnIndex == 5) then
			-- 	--	sortByIndex = 4

			-- 	--sort by mythic+ ranting
			-- 	elseif (columnIndex == 5) then
			-- 		sortByIndex = 6
			-- 	end

			-- 	if (order == "DESC") then
			-- 		table.sort(newData, function(t1, t2) return t1[sortByIndex] > t2[sortByIndex] end)
			-- 	else
			-- 		table.sort(newData, function(t1, t2) return t1[sortByIndex] < t2[sortByIndex] end)
			-- 	end

			-- 	--remove offline guild players from the list
			-- 	for i = #newData, 1, -1 do
			-- 		local keystoneTable = newData[i]
			-- 		if (not keystoneTable[10]) then
			-- 			tremove(newData, i)
			-- 			newData.offlineGuildPlayers[#newData.offlineGuildPlayers+1] = keystoneTable
			-- 		end
			-- 	end

			-- 	newData.offlineGuildPlayers = detailsFramework.table.reverse(newData.offlineGuildPlayers)

			-- 	--put players in the group at the top of the list
			-- 	if (IsInGroup() and not IsInRaid()) then
			-- 		local playersInTheParty = {}
			-- 		for i = #newData, 1, -1 do
			-- 			local keystoneTable = newData[i]
			-- 			if (keystoneTable[9] > 0) then
			-- 				playersInTheParty[#playersInTheParty+1] = keystoneTable
			-- 				tremove(newData, i)
			-- 			end
			-- 		end

			-- 		if (#playersInTheParty > 0) then
			-- 			table.sort(playersInTheParty, function(t1, t2) return t1[9] > t2[9] end)
			-- 			for i = 1, #playersInTheParty do
			-- 				local keystoneTable = playersInTheParty[i]
			-- 				table.insert(newData, 1, keystoneTable)
			-- 			end
			-- 		end
			-- 	end

			-- 	--reinsert offline guild players into the data
			-- 	local offlinePlayers = newData.offlineGuildPlayers
			-- 	for i = 1, #offlinePlayers do
			-- 		local keystoneTable = offlinePlayers[i]
			-- 		newData[#newData+1] = keystoneTable
			-- 	end

			-- 	scrollFrame:SetData(newData)
			-- 	scrollFrame:Refresh()
			-- end

			-- function f.OnKeystoneUpdate(unitId, keystoneInfo, allKeystonesInfo)
			-- 	if (f:IsShown()) then
			-- 		f.RefreshData()
			-- 	end
			-- end

			-- f:SetScript("OnHide", function()
			-- 	openRaidLib.UnregisterCallback(DetailsRatingInfoFrame, "KeystoneUpdate", "OnKeystoneUpdate")
			-- end)

			-- f:SetScript("OnUpdate", function(self, deltaTime)
			-- 	if (not self.lastUpdate) then
			-- 		self.lastUpdate = 0
			-- 	end

			-- 	self.lastUpdate = self.lastUpdate + deltaTime
			-- 	if (self.lastUpdate > 1) then
			-- 		self.lastUpdate = 0
			-- 		self.RefreshData()
			-- 	end
			-- end)
			end

			--show the frame
			DetailsRatingInfoFrame:Show()

			openRaidLibRating.RegisterCallback(DetailsRatingInfoFrame, "RatingUpdate", "OnRatingUpdate")

			--openRaidLib.WipeKeystoneData()

			if (IsInRaid()) then
				openRaidLibRating.RequestRatingDataFromRaid()
			elseif (IsInGroup()) then
				openRaidLibRating.RequestRatingDataFromParty()
			end

			DetailsRatingInfoFrame.RefreshRatingData()
		end
end



-- /run DevTools_Dump(C_FriendList.GetFriendInfo("Cellwynn"))
-- /run DevTools_Dump(C_FriendList.GetFriendInfoByIndex(1))

-- /run DevTools_Dump(C_FriendList.GetFriendInfoByIndex(1))

-- /run DevTools_Dump(FRIENDS_LIST_MANAGER:FindDataByDisplayName("Cellwynn"))

-- /run print(C_FriendList.GetNumFriends())

-- C_BattleNet.GetGameAccountInfoByID
-- /run DevTools_Dump(BNGetFriendInfo(1))

-- /run DevTools_Dump(C_BattleNet.GetFriendAccountInfo(1))