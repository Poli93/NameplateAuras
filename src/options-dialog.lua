-- luacheck: no max line length
-- luacheck: globals LibStub SOUNDKIT GameTooltip PlaySound BackdropTemplateMixin UIDropDownMenu_SetWidth gmatch
-- luacheck: globals UIParent UIDropDownMenu_AddButton GameFontHighlightSmall StaticPopupDialogs StaticPopup_Show
-- luacheck: globals CreateFrame YES NO hooksecurefunc GameFontNormal InCombatLockdown format ceil wipe C_Timer GetSpellInfo
-- luacheck: globals PlaySoundFile

local addonName, addonTable = ...;
local VGUI = LibStub("LibRedDropdown-1.0");
local L = LibStub("AceLocale-3.0"):GetLocale("NameplateAuras");
local SML = LibStub("LibSharedMedia-3.0");
local LibSerialize = LibStub("LibSerialize");
local LibDeflate = LibStub("LibDeflate");
local MSQ = LibStub("Masque", true);

local 	_G, pairs, select, string_format, math_ceil, wipe, string_lower, table_insert, table_sort, CTimerAfter, GetSpellInfo =
		_G, pairs, select, format, ceil, wipe, string.lower, table.insert, table.sort, C_Timer.After, GetSpellInfo;

local AllSpellIDsAndIconsByName, GUIFrame = { };

-- // consts
local CONST_SPELL_MODE_DISABLED, CONST_SPELL_MODE_ALL, CONST_SPELL_MODE_MYAURAS, AURA_TYPE_BUFF, AURA_TYPE_DEBUFF, AURA_TYPE_ANY, AURA_SORT_MODE_NONE, AURA_SORT_MODE_EXPIRETIME, AURA_SORT_MODE_ICONSIZE;
local AURA_SORT_MODE_AURATYPE_EXPIRE, GLOW_TIME_INFINITE;
do
	CONST_SPELL_MODE_DISABLED, CONST_SPELL_MODE_ALL, CONST_SPELL_MODE_MYAURAS = addonTable.CONST_SPELL_MODE_DISABLED, addonTable.CONST_SPELL_MODE_ALL, addonTable.CONST_SPELL_MODE_MYAURAS;
	AURA_TYPE_BUFF, AURA_TYPE_DEBUFF, AURA_TYPE_ANY = addonTable.AURA_TYPE_BUFF, addonTable.AURA_TYPE_DEBUFF, addonTable.AURA_TYPE_ANY;
	AURA_SORT_MODE_NONE, AURA_SORT_MODE_EXPIRETIME, AURA_SORT_MODE_ICONSIZE, AURA_SORT_MODE_AURATYPE_EXPIRE =
		addonTable.AURA_SORT_MODE_NONE, addonTable.AURA_SORT_MODE_EXPIRETIME, addonTable.AURA_SORT_MODE_ICONSIZE, addonTable.AURA_SORT_MODE_AURATYPE_EXPIRE;
	GLOW_TIME_INFINITE = addonTable.GLOW_TIME_INFINITE; -- // 30 days
end

-- // utilities
local Print, msg, table_count, SpellTextureByID, SpellNameByID, CoroutineProcessor;
do
	Print, msg, table_count, SpellTextureByID, SpellNameByID, CoroutineProcessor =
		addonTable.Print, addonTable.msg, addonTable.table_count, addonTable.SpellTextureByID, addonTable.SpellNameByID, addonTable.CoroutineProcessor;
end

local CurrentIconGroup = 1;
local IconGroupsList;

function addonTable.OnSpellInfoCachesReady()

end

function addonTable.GuiOnProfileChanged()
	CurrentIconGroup = 1;
	addonTable.OnIconGroupChanged();
end

function addonTable.OnIconGroupChanged()
	if (GUIFrame ~= nil) then
		IconGroupsList.Reinitialize();
		local activeCategory = GUIFrame.ActiveCategory;
		for _, func in pairs(addonTable.GUIFrame.OnDBChangedHandlers) do
			func();
		end
		GUIFrame.CategoryButtons[activeCategory]:Click();
		UIDropDownMenu_SetText(IconGroupsList, addonTable.db.IconGroups[CurrentIconGroup].IconGroupName);
	end
	addonTable.RebuildAuraSortFunctions();
end

local function GetDefaultDBSpellEntry(enabledState, spellName, checkSpellID)
	return {
		["enabledState"] =				enabledState,
		["auraType"] =					AURA_TYPE_ANY,
		["iconSizeWidth"] =				addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth,
		["iconSizeHeight"] =			addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight,
		["spellName"] =					spellName,
		["checkSpellID"] =				checkSpellID,
		["showOnFriends"] =				true,
		["showOnEnemies"] =				true,
		["playerNpcMode"] =				addonTable.SHOW_ON_PLAYERS_AND_NPC,
		["showGlow"] =					nil,
		["glowType"] =					addonTable.GLOW_TYPE_AUTOUSE,
		["animationType"] =				addonTable.ICON_ANIMATION_TYPE_ALPHA,
		["animationTimer"] =			10,
		["animationDisplayMode"] =		addonTable.ICON_ANIMATION_DISPLAY_MODE_NONE,
		["customBorderColor"] = 		{ 1, 0.1, 0.1, 1 },
		["customBorderSize"] = 			addonTable.db.IconGroups[CurrentIconGroup].BorderThickness,
		["customBorderType"] = 			addonTable.BORDER_TYPE_DISABLED,
		["customBorderPath"] = 			"",
		["iconGroups"] =				{[1] = true},
	};
end

local function ShowGUICategory(index)
	for _, v in pairs(GUIFrame.Categories) do
		for _, l in pairs(v) do
			l:Hide();
		end
	end
	for _, v in pairs(GUIFrame.Categories[index]) do
		v:Show();
	end
end

local function OnGUICategoryClick(self)
	GUIFrame.CategoryButtons[GUIFrame.ActiveCategory].text:SetTextColor(1, 0.82, 0);
	GUIFrame.CategoryButtons[GUIFrame.ActiveCategory]:UnlockHighlight();
	GUIFrame.ActiveCategory = self.index;
	self.text:SetTextColor(1, 1, 1);
	self:LockHighlight();
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	ShowGUICategory(GUIFrame.ActiveCategory);
end

local function CreateGUICategory()
	local b = CreateFrame("Button", nil, GUIFrame.outline);
	b:SetWidth(GUIFrame.outline:GetWidth() - 8);
	b:SetHeight(18);
	b:SetScript("OnClick", OnGUICategoryClick);
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
	b:GetHighlightTexture():SetAlpha(0.7);
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	b.text:SetPoint("LEFT", 3, 0);
	GUIFrame.CategoryButtons[#GUIFrame.CategoryButtons + 1] = b;
	return b;
end

local function GUICategory_1(index)

	local checkBoxHideBlizzardFrames, checkBoxHidePlayerBlizzardFrame, checkBoxShowAurasOnPlayerNameplate,
		checkBoxShowAboveFriendlyUnits, checkBoxShowMyAuras, checkboxAuraTooltip, checkboxShowCooldownAnimation,
		checkboxShowOnlyOnTarget, checkboxShowAurasOnTargetEvenInDisabledAreas, zoneTypesArea, buttonInstances,
		buttonAlwaysShowMyAurasBlacklist, buttonAddAlwaysShowMyAurasBlacklist, editboxAddAlwaysShowMyAurasBlacklist,
		checkboxUseDefaultAuraTooltip, buttonNpcBlacklist, buttonNpcBlacklistAdd, editboxNpcBlacklistAdd,
		checkboxMasque;
	local dropdownAlwaysShowMyAurasBlacklist = VGUI.CreateDropdownMenu();
	local dropdownNpcBlacklist = VGUI.CreateDropdownMenu();

	-- checkBoxHideBlizzardFrames
	do
		checkBoxHideBlizzardFrames = VGUI.CreateCheckBox();
		checkBoxHideBlizzardFrames:SetText(L["options:general:hide-blizz-frames"]);
		checkBoxHideBlizzardFrames:SetOnClickHandler(function(this)
			addonTable.db.HideBlizzardFrames = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
			if (not addonTable.db.HideBlizzardFrames) then
				addonTable.PopupReloadUI();
			end
		end);
		checkBoxHideBlizzardFrames:SetChecked(addonTable.db.HideBlizzardFrames);
		checkBoxHideBlizzardFrames:SetParent(GUIFrame);
		checkBoxHideBlizzardFrames:SetPoint("TOPLEFT", GUIFrame, 160, -20);
		table_insert(GUIFrame.Categories[index], checkBoxHideBlizzardFrames);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			addonTable.UpdateAllNameplates(false);
			checkBoxHideBlizzardFrames:SetChecked(addonTable.db.HideBlizzardFrames);
		end);
	end

	-- checkBoxHidePlayerBlizzardFrame
	do
		checkBoxHidePlayerBlizzardFrame = VGUI.CreateCheckBox();
		checkBoxHidePlayerBlizzardFrame:SetText(L["options:general:hide-player-blizz-frame"]);
		checkBoxHidePlayerBlizzardFrame:SetOnClickHandler(function(this)
			addonTable.db.HidePlayerBlizzardFrame = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
			if (not addonTable.db.HidePlayerBlizzardFrame) then
				addonTable.PopupReloadUI();
			end
		end);
		checkBoxHidePlayerBlizzardFrame:SetChecked(addonTable.db.HidePlayerBlizzardFrame);
		checkBoxHidePlayerBlizzardFrame:SetParent(GUIFrame);
		checkBoxHidePlayerBlizzardFrame:SetPoint("TOPLEFT", checkBoxHideBlizzardFrames, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkBoxHidePlayerBlizzardFrame);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			addonTable.UpdateAllNameplates(false);
			checkBoxHidePlayerBlizzardFrame:SetChecked(addonTable.db.HidePlayerBlizzardFrame);
		end);
	end

	-- // checkBoxShowAurasOnPlayerNameplate
	do
		checkBoxShowAurasOnPlayerNameplate = VGUI.CreateCheckBox();
		checkBoxShowAurasOnPlayerNameplate:SetText(L["Display auras on player's nameplate"]);
		checkBoxShowAurasOnPlayerNameplate:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnPlayerNameplate = this:GetChecked();
		end);
		checkBoxShowAurasOnPlayerNameplate:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnPlayerNameplate);
		checkBoxShowAurasOnPlayerNameplate:SetParent(GUIFrame);
		checkBoxShowAurasOnPlayerNameplate:SetPoint("TOPLEFT", checkBoxHidePlayerBlizzardFrame, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkBoxShowAurasOnPlayerNameplate);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxShowAurasOnPlayerNameplate:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnPlayerNameplate); end);

	end

	-- // checkBoxShowAboveFriendlyUnits
	do
		checkBoxShowAboveFriendlyUnits = VGUI.CreateCheckBox();
		checkBoxShowAboveFriendlyUnits:SetText(L["Display auras on nameplates of friendly units"]);
		checkBoxShowAboveFriendlyUnits:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowAboveFriendlyUnits = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
		end);
		checkBoxShowAboveFriendlyUnits:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAboveFriendlyUnits);
		checkBoxShowAboveFriendlyUnits:SetParent(GUIFrame);
		checkBoxShowAboveFriendlyUnits:SetPoint("TOPLEFT", checkBoxShowAurasOnPlayerNameplate, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkBoxShowAboveFriendlyUnits);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxShowAboveFriendlyUnits:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAboveFriendlyUnits); end);

	end

	-- // checkBoxShowMyAuras
	do
		checkBoxShowMyAuras = VGUI.CreateCheckBox();
		checkBoxShowMyAuras:SetText(L["Always show auras cast by myself"]);
		checkBoxShowMyAuras:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAuras = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
		end);
		checkBoxShowMyAuras:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAuras);
		checkBoxShowMyAuras:SetParent(GUIFrame);
		checkBoxShowMyAuras:SetPoint("TOPLEFT", checkBoxShowAboveFriendlyUnits, "BOTTOMLEFT", 0, 0);
		VGUI.SetTooltip(checkBoxShowMyAuras, L["options:general:always-show-my-auras:tooltip"]);
		table_insert(GUIFrame.Categories[index], checkBoxShowMyAuras);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxShowMyAuras:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAuras); end);

	end

	-- // buttonAlwaysShowMyAurasBlacklist
	do
		buttonAlwaysShowMyAurasBlacklist = VGUI.CreateButton();
		buttonAlwaysShowMyAurasBlacklist:SetParent(GUIFrame);
		buttonAlwaysShowMyAurasBlacklist:SetText(L["options:general:always-show-my-auras-blacklist:button"]);
		VGUI.SetTooltip(buttonAlwaysShowMyAurasBlacklist, L["options:general:always-show-my-auras-blacklist:button:tooltip"]);
		buttonAlwaysShowMyAurasBlacklist:SetWidth(150);
		buttonAlwaysShowMyAurasBlacklist:SetHeight(20);
		buttonAlwaysShowMyAurasBlacklist:SetPoint("LEFT", checkBoxShowMyAuras.textFrame, "RIGHT", 5, 0);
		buttonAlwaysShowMyAurasBlacklist:SetScript("OnClick", function(button)
			if (dropdownAlwaysShowMyAurasBlacklist:IsShown()) then
				dropdownAlwaysShowMyAurasBlacklist:Hide();
			else
				local t = { };
				for spellName in pairs(addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAurasBlacklist) do
					table_insert(t, {
						text = spellName,
						icon = AllSpellIDsAndIconsByName[spellName] ~= nil and SpellTextureByID[next(AllSpellIDsAndIconsByName[spellName])] or 136243,
						onCloseButtonClick = function()
							addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAurasBlacklist[spellName] = nil;
							addonTable.UpdateAllNameplates(false);
							-- close and then open list again
							buttonAlwaysShowMyAurasBlacklist:Click(); buttonAlwaysShowMyAurasBlacklist:Click();
						end,
					});
				end
				table_sort(t, function(item1, item2) return item1.text < item2.text end);
				dropdownAlwaysShowMyAurasBlacklist:SetList(t);
				dropdownAlwaysShowMyAurasBlacklist:SetParent(button);
				dropdownAlwaysShowMyAurasBlacklist:Show();
				dropdownAlwaysShowMyAurasBlacklist.searchBox:SetFocus();
				dropdownAlwaysShowMyAurasBlacklist.searchBox:SetText("");
			end
		end);
		buttonAlwaysShowMyAurasBlacklist:SetScript("OnHide", function() dropdownAlwaysShowMyAurasBlacklist:Hide(); end);
		buttonAlwaysShowMyAurasBlacklist:Disable();
		hooksecurefunc(addonTable, "OnSpellInfoCachesReady", function() buttonAlwaysShowMyAurasBlacklist:Enable(); end);
		GUIFrame:HookScript("OnHide", function() buttonAlwaysShowMyAurasBlacklist:Disable(); end);
		table_insert(GUIFrame.Categories[index], buttonAlwaysShowMyAurasBlacklist);
	end

	-- buttonAddAlwaysShowMyAurasBlacklist
	do
		buttonAddAlwaysShowMyAurasBlacklist = VGUI.CreateButton();
		buttonAddAlwaysShowMyAurasBlacklist:SetParent(dropdownAlwaysShowMyAurasBlacklist);
		buttonAddAlwaysShowMyAurasBlacklist:SetText(L["Add spell"]);
		buttonAddAlwaysShowMyAurasBlacklist:SetWidth(dropdownAlwaysShowMyAurasBlacklist:GetWidth() / 3);
		buttonAddAlwaysShowMyAurasBlacklist:SetHeight(24);
		buttonAddAlwaysShowMyAurasBlacklist:SetPoint("TOPRIGHT", dropdownAlwaysShowMyAurasBlacklist, "BOTTOMRIGHT", 0, -8);
		buttonAddAlwaysShowMyAurasBlacklist:SetScript("OnClick", function()
			local text = editboxAddAlwaysShowMyAurasBlacklist:GetText();
			if (text ~= nil and text ~= "") then
				local spellExist = false;
				if (AllSpellIDsAndIconsByName[text]) then
					spellExist = true;
				else
					for _spellName in pairs(AllSpellIDsAndIconsByName) do
						if (string_lower(_spellName) == string_lower(text)) then
							text = _spellName;
							spellExist = true;
							break;
						end
					end
				end
				if (not spellExist) then
					msg(L["Spell seems to be nonexistent"]);
				else
					addonTable.db.IconGroups[CurrentIconGroup].AlwaysShowMyAurasBlacklist[text] = true;
					addonTable.UpdateAllNameplates(false);
					-- close and then open list again
					buttonAlwaysShowMyAurasBlacklist:Click(); buttonAlwaysShowMyAurasBlacklist:Click();
				end
			end
			editboxAddAlwaysShowMyAurasBlacklist:SetText("");
		end);
	end

	-- editboxAddAlwaysShowMyAurasBlacklist
	do
		editboxAddAlwaysShowMyAurasBlacklist = CreateFrame("EditBox", nil, dropdownAlwaysShowMyAurasBlacklist, "InputBoxTemplate");
		editboxAddAlwaysShowMyAurasBlacklist:SetAutoFocus(false);
		editboxAddAlwaysShowMyAurasBlacklist:SetFontObject(GameFontHighlightSmall);
		editboxAddAlwaysShowMyAurasBlacklist:SetHeight(20);
		editboxAddAlwaysShowMyAurasBlacklist:SetWidth(dropdownAlwaysShowMyAurasBlacklist:GetWidth() - buttonAddAlwaysShowMyAurasBlacklist:GetWidth() - 10);
		editboxAddAlwaysShowMyAurasBlacklist:SetPoint("BOTTOMRIGHT", buttonAddAlwaysShowMyAurasBlacklist, "BOTTOMLEFT", -5, 2);
		editboxAddAlwaysShowMyAurasBlacklist:SetJustifyH("LEFT");
		editboxAddAlwaysShowMyAurasBlacklist:EnableMouse(true);
		editboxAddAlwaysShowMyAurasBlacklist:SetScript("OnEscapePressed", function() editboxAddAlwaysShowMyAurasBlacklist:ClearFocus(); end);
		editboxAddAlwaysShowMyAurasBlacklist:SetScript("OnEnterPressed", function() buttonAddAlwaysShowMyAurasBlacklist:Click(); end);
		local text = editboxAddAlwaysShowMyAurasBlacklist:CreateFontString(nil, "ARTWORK", "GameFontDisableTiny");
		text:SetPoint("LEFT", 0, 0);
		text:SetText(L["options:spells:add-new-spell"]);
		editboxAddAlwaysShowMyAurasBlacklist:SetScript("OnEditFocusGained", function() text:Hide(); end);
		editboxAddAlwaysShowMyAurasBlacklist:SetScript("OnEditFocusLost", function() text:Show(); end);
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			if (editboxAddAlwaysShowMyAurasBlacklist:IsVisible() and editboxAddAlwaysShowMyAurasBlacklist:HasFocus() and link ~= nil) then
				local spellName = string.match(link, "%[\"?(.-)\"?%]");
				if (spellName ~= nil) then
					editboxAddAlwaysShowMyAurasBlacklist:SetText(spellName);
					editboxAddAlwaysShowMyAurasBlacklist:ClearFocus();
					return true;
				end
			end
		end);
	end

	-- dropdownAlwaysShowMyAurasBlacklist
	do
		dropdownAlwaysShowMyAurasBlacklist.Background = dropdownAlwaysShowMyAurasBlacklist:CreateTexture(nil, "BORDER");
		dropdownAlwaysShowMyAurasBlacklist.Background:SetPoint("TOPLEFT", dropdownAlwaysShowMyAurasBlacklist, "TOPLEFT", -2, 2);
		dropdownAlwaysShowMyAurasBlacklist.Background:SetPoint("BOTTOMRIGHT", buttonAddAlwaysShowMyAurasBlacklist, "BOTTOMRIGHT",  2, -2);
		dropdownAlwaysShowMyAurasBlacklist.Background:SetColorTexture(1, 0.3, 0.3, 1);
		dropdownAlwaysShowMyAurasBlacklist.Border = dropdownAlwaysShowMyAurasBlacklist:CreateTexture(nil, "BACKGROUND");
		dropdownAlwaysShowMyAurasBlacklist.Border:SetPoint("TOPLEFT", dropdownAlwaysShowMyAurasBlacklist, "TOPLEFT", -3, 3);
		dropdownAlwaysShowMyAurasBlacklist.Border:SetPoint("BOTTOMRIGHT", buttonAddAlwaysShowMyAurasBlacklist, "BOTTOMRIGHT",  3, -3);
		dropdownAlwaysShowMyAurasBlacklist.Border:SetColorTexture(0.1, 0.1, 0.1, 1);
		dropdownAlwaysShowMyAurasBlacklist:ClearAllPoints();
		dropdownAlwaysShowMyAurasBlacklist:SetPoint("TOPLEFT", buttonAlwaysShowMyAurasBlacklist, "TOPRIGHT", 5, 0);
	end

	-- // checkboxShowCooldownAnimation
	do
		checkboxShowCooldownAnimation = VGUI.CreateCheckBox();
		checkboxShowCooldownAnimation:SetText(L["options:general:show-cooldown-animation"]);
		checkboxShowCooldownAnimation:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownAnimation = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxShowCooldownAnimation:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownAnimation);
		checkboxShowCooldownAnimation:SetParent(GUIFrame);
		checkboxShowCooldownAnimation:SetPoint("TOPLEFT", checkBoxShowMyAuras, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkboxShowCooldownAnimation);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxShowCooldownAnimation:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownAnimation); end);
	end

	-- // checkboxShowOnlyOnTarget
	do
		checkboxShowOnlyOnTarget = VGUI.CreateCheckBox();
		checkboxShowOnlyOnTarget:SetText(L["options:general:show-on-target-only"]);
		checkboxShowOnlyOnTarget:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowOnlyOnTarget = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxShowOnlyOnTarget:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowOnlyOnTarget);
		checkboxShowOnlyOnTarget:SetParent(GUIFrame);
		checkboxShowOnlyOnTarget:SetPoint("TOPLEFT", checkboxShowCooldownAnimation, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkboxShowOnlyOnTarget);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxShowOnlyOnTarget:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowOnlyOnTarget); end);
	end

	-- // checkboxAuraTooltip
	do
		checkboxAuraTooltip = VGUI.CreateCheckBox();
		checkboxAuraTooltip:SetText(L["options:general:show-aura-tooltip"]);
		checkboxAuraTooltip:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowAuraTooltip = this:GetChecked();
			for _, icon in pairs(addonTable.AllAuraIconFrames) do
				addonTable.AllocateIcon_SetAuraTooltip(icon);
			end
			GameTooltip:Hide();
			if (addonTable.db.IconGroups[CurrentIconGroup].ShowAuraTooltip) then
				checkboxUseDefaultAuraTooltip:Show();
			else
				checkboxUseDefaultAuraTooltip:Hide();
			end
		end);
		checkboxAuraTooltip:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAuraTooltip);
		checkboxAuraTooltip:SetParent(GUIFrame);
		checkboxAuraTooltip:SetPoint("TOPLEFT", checkboxShowOnlyOnTarget, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkboxAuraTooltip);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxAuraTooltip:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAuraTooltip); end);

	end

	-- // checkboxUseDefaultAuraTooltip
	do
		checkboxUseDefaultAuraTooltip = VGUI.CreateCheckBox();
		checkboxUseDefaultAuraTooltip:SetText(L["options:general:use-default-tooltip"]);
		checkboxUseDefaultAuraTooltip:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].UseDefaultAuraTooltip = this:GetChecked();
			for _, icon in pairs(addonTable.AllAuraIconFrames) do
				addonTable.AllocateIcon_SetAuraTooltip(icon);
			end
			GameTooltip:Hide();
		end);
		checkboxUseDefaultAuraTooltip:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].UseDefaultAuraTooltip);
		checkboxUseDefaultAuraTooltip:SetParent(GUIFrame);
		checkboxUseDefaultAuraTooltip:SetPoint("TOPLEFT", checkboxAuraTooltip, "BOTTOMLEFT", 0, 0);
		checkboxUseDefaultAuraTooltip:HookScript("OnShow", function(self)
			if (not addonTable.db.IconGroups[CurrentIconGroup].ShowAuraTooltip) then
				self:Hide();
			end
		end);
		table_insert(GUIFrame.Categories[index], checkboxUseDefaultAuraTooltip);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxUseDefaultAuraTooltip:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].UseDefaultAuraTooltip); end);
		
	end

	-- // checkboxMasque
	do
		checkboxMasque = VGUI.CreateCheckBox();
		checkboxMasque:SetText(L["options:general:masque-experimental"]);
		checkboxMasque:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].MasqueEnabled = this:GetChecked();
			addonTable.PopupReloadUI();
		end);
		checkboxMasque:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].MasqueEnabled);
		checkboxMasque:SetParent(GUIFrame);
		checkboxMasque:SetPoint("TOPLEFT", checkboxUseDefaultAuraTooltip, "BOTTOMLEFT", 0, 0);
		checkboxMasque:HookScript("OnShow", function(self)
			if (not MSQ) then
				self:Hide();
			end
		end);
		table_insert(GUIFrame.Categories[index], checkboxMasque);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxMasque:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].MasqueEnabled); end);
		
	end

	-- // zoneTypesArea
	do

		zoneTypesArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		zoneTypesArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		zoneTypesArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		zoneTypesArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		zoneTypesArea:SetPoint("TOPLEFT", checkboxMasque, "BOTTOMLEFT", 0, -10);
		zoneTypesArea:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		zoneTypesArea:SetWidth(360);
		zoneTypesArea:SetHeight(90);
		table_insert(GUIFrame.Categories[index], zoneTypesArea);

	end

	-- // buttonInstances
	do
		local zoneTypes = {
			[addonTable.INSTANCE_TYPE_NONE] = 			L["instance-type:none"],
			[addonTable.INSTANCE_TYPE_UNKNOWN] = 		L["instance-type:unknown"],
			[addonTable.INSTANCE_TYPE_PVP] = 			L["instance-type:pvp"],
			[addonTable.INSTANCE_TYPE_PVP_BG_40PPL] = 	L["instance-type:pvp_bg_40ppl"],
			[addonTable.INSTANCE_TYPE_ARENA] = 			L["instance-type:arena"],
			[addonTable.INSTANCE_TYPE_PARTY] = 			L["instance-type:party"],
			[addonTable.INSTANCE_TYPE_RAID] = 			L["instance-type:raid"],
			[addonTable.INSTANCE_TYPE_SCENARIO] =		L["instance-type:scenario"],
		};
		local zoneIcons = {
			[addonTable.INSTANCE_TYPE_NONE] = 			SpellTextureByID[6711],
			[addonTable.INSTANCE_TYPE_UNKNOWN] = 		SpellTextureByID[175697],
			[addonTable.INSTANCE_TYPE_PVP] = 			SpellTextureByID[232352],
			[addonTable.INSTANCE_TYPE_PVP_BG_40PPL] = 	132485,
			[addonTable.INSTANCE_TYPE_ARENA] = 			SpellTextureByID[270697],
			[addonTable.INSTANCE_TYPE_PARTY] = 			SpellTextureByID[77629],
			[addonTable.INSTANCE_TYPE_RAID] = 			SpellTextureByID[3363],
			[addonTable.INSTANCE_TYPE_SCENARIO] =		SpellTextureByID[77628],
		};

		local dropdownInstances = VGUI.CreateDropdownMenu();
		dropdownInstances:SetHeight(230);
		buttonInstances = VGUI.CreateButton();
		buttonInstances:SetParent(zoneTypesArea);
		buttonInstances:SetText(L["options:general:instance-types"]);

		local function setEntries()
			local entries = { };
			for instanceType, instanceLocalizatedName in pairs(zoneTypes) do
				table_insert(entries, {
					["text"] = instanceLocalizatedName,
					["icon"] = zoneIcons[instanceType],
					["func"] = function(info)
						local btn = dropdownInstances:GetButtonByText(info.text);
						if (btn) then
							info.disabled = not info.disabled;
							btn:SetGray(info.disabled);
							addonTable.db.IconGroups[CurrentIconGroup].EnabledZoneTypes[info.instanceType] = not info.disabled;
						end
						addonTable.UpdateAllNameplates();
					end,
					["disabled"] = not addonTable.db.IconGroups[CurrentIconGroup].EnabledZoneTypes[instanceType],
					["dontCloseOnClick"] = true,
					["instanceType"] = instanceType,
				});
			end
			table_sort(entries, function(item1, item2) return item1.instanceType < item2.instanceType; end);
			return entries;
		end

		-- buttonInstances:SetWidth(350);
		buttonInstances:SetPoint("TOPLEFT", zoneTypesArea, "TOPLEFT", 10, -10);
		buttonInstances:SetPoint("TOPRIGHT", zoneTypesArea, "TOPRIGHT", -10, -10);
		buttonInstances:SetHeight(40);
		buttonInstances:SetScript("OnClick", function(self)
			if (dropdownInstances:IsVisible()) then
				dropdownInstances:Hide();
			else
				dropdownInstances:SetList(setEntries());
				dropdownInstances:SetParent(self);
				dropdownInstances:ClearAllPoints();
				dropdownInstances:SetPoint("TOP", self, "BOTTOM", 0, 0);
				dropdownInstances:Show();
			end
		end);
		buttonInstances:SetScript("OnHide", dropdownInstances.Hide);
		table_insert(GUIFrame.Categories[index], buttonInstances);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			dropdownInstances:SetList(setEntries());
			dropdownInstances:Hide();
		end);

	end

	-- // checkboxShowAurasOnTargetEvenInDisabledAreas
	do
		checkboxShowAurasOnTargetEvenInDisabledAreas = VGUI.CreateCheckBox();
		checkboxShowAurasOnTargetEvenInDisabledAreas:SetText(L["options:general:show-on-target-even-in-disabled-area-types"]);
		checkboxShowAurasOnTargetEvenInDisabledAreas:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnTargetEvenInDisabledAreas = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxShowAurasOnTargetEvenInDisabledAreas:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnTargetEvenInDisabledAreas);
		checkboxShowAurasOnTargetEvenInDisabledAreas:SetParent(zoneTypesArea);
		checkboxShowAurasOnTargetEvenInDisabledAreas:SetPoint("TOPLEFT", buttonInstances, "BOTTOMLEFT", 0, -10);
		table_insert(GUIFrame.Categories[index], checkboxShowAurasOnTargetEvenInDisabledAreas);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkboxShowAurasOnTargetEvenInDisabledAreas:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowAurasOnTargetEvenInDisabledAreas); end);
	end

	-- // buttonNpcBlacklist
	do
		buttonNpcBlacklist = VGUI.CreateButton();
		buttonNpcBlacklist:SetParent(GUIFrame);
		buttonNpcBlacklist:SetText(L["options:general:npc-blacklist"]);
		buttonNpcBlacklist:SetPoint("TOPLEFT", zoneTypesArea, "BOTTOMLEFT", 10, -10);
		buttonNpcBlacklist:SetPoint("TOPRIGHT", zoneTypesArea, "BOTTOMRIGHT", -10, -10);
		buttonNpcBlacklist:SetHeight(25);
		buttonNpcBlacklist:SetScript("OnClick", function(self)
			if (dropdownNpcBlacklist:IsShown()) then
				dropdownNpcBlacklist:Hide();
			else
				local t = { };
				for npcName in pairs(addonTable.db.IconGroups[CurrentIconGroup].NpcBlacklist) do
					table_insert(t, {
						text = npcName,
						onCloseButtonClick = function()
							addonTable.db.IconGroups[CurrentIconGroup].NpcBlacklist[npcName] = nil;
							addonTable.UpdateAllNameplates(false);
							-- close and then open list again
							buttonNpcBlacklist:Click(); 
							buttonNpcBlacklist:Click();
						end,
					});
				end
				table_sort(t, function(item1, item2) return item1.text < item2.text end);
				dropdownNpcBlacklist:SetList(t);
				dropdownNpcBlacklist:SetParent(self);
				dropdownNpcBlacklist:Show();
				dropdownNpcBlacklist.searchBox:SetFocus();
				dropdownNpcBlacklist.searchBox:SetText("");
			end
		end);
		buttonNpcBlacklist:SetScript("OnHide", function() dropdownNpcBlacklist:Hide() end);
		table_insert(GUIFrame.Categories[index], buttonNpcBlacklist);
	end

	-- buttonNpcBlacklistAdd
	do
		buttonNpcBlacklistAdd = VGUI.CreateButton();
		buttonNpcBlacklistAdd:SetParent(dropdownNpcBlacklist);
		buttonNpcBlacklistAdd:SetText(L["options:general:npc-blacklist-add-button"]);
		buttonNpcBlacklistAdd:SetWidth(dropdownNpcBlacklist:GetWidth() / 3);
		buttonNpcBlacklistAdd:SetHeight(24);
		buttonNpcBlacklistAdd:SetPoint("TOPRIGHT", dropdownNpcBlacklist, "BOTTOMRIGHT", 0, -8);
		buttonNpcBlacklistAdd:SetScript("OnClick", function()
			local text = editboxNpcBlacklistAdd:GetText();
			if (text ~= nil and text ~= "") then
				addonTable.db.IconGroups[CurrentIconGroup].NpcBlacklist[text] = true;
				addonTable.UpdateAllNameplates(false);
				buttonNpcBlacklist:Click();
				buttonNpcBlacklist:Click();
			end
			editboxNpcBlacklistAdd:SetText("");
		end);
	end

	-- editboxNpcBlacklistAdd
	do
		editboxNpcBlacklistAdd = CreateFrame("EditBox", nil, dropdownNpcBlacklist, "InputBoxTemplate");
		editboxNpcBlacklistAdd:SetAutoFocus(false);
		editboxNpcBlacklistAdd:SetFontObject(GameFontHighlightSmall);
		editboxNpcBlacklistAdd:SetHeight(20);
		editboxNpcBlacklistAdd:SetWidth(dropdownNpcBlacklist:GetWidth() - buttonNpcBlacklistAdd:GetWidth() - 10);
		editboxNpcBlacklistAdd:SetPoint("BOTTOMRIGHT", buttonNpcBlacklistAdd, "BOTTOMLEFT", -5, 2);
		editboxNpcBlacklistAdd:SetJustifyH("LEFT");
		editboxNpcBlacklistAdd:EnableMouse(true);
		editboxNpcBlacklistAdd:SetScript("OnEscapePressed", function() editboxNpcBlacklistAdd:ClearFocus() end);
		editboxNpcBlacklistAdd:SetScript("OnEnterPressed", function() buttonNpcBlacklistAdd:Click() end);
		local text = editboxNpcBlacklistAdd:CreateFontString(nil, "ARTWORK", "GameFontDisableTiny");
		text:SetPoint("LEFT", 0, 0);
		text:SetText(L["options:general:npc-blacklist-editbox-add"]);
		editboxNpcBlacklistAdd:SetScript("OnEditFocusGained", function() text:Hide() end);
		editboxNpcBlacklistAdd:SetScript("OnEditFocusLost", function() text:Show() end);
	end

	-- dropdownNpcBlacklist
	do
		dropdownNpcBlacklist.Background = dropdownNpcBlacklist:CreateTexture(nil, "BORDER");
		dropdownNpcBlacklist.Background:SetPoint("TOPLEFT", dropdownNpcBlacklist, "TOPLEFT", -2, 2);
		dropdownNpcBlacklist.Background:SetPoint("BOTTOMRIGHT", buttonNpcBlacklistAdd, "BOTTOMRIGHT",  2, -2);
		dropdownNpcBlacklist.Background:SetColorTexture(1, 0.3, 0.3, 1);
		dropdownNpcBlacklist.Border = dropdownNpcBlacklist:CreateTexture(nil, "BACKGROUND");
		dropdownNpcBlacklist.Border:SetPoint("TOPLEFT", dropdownNpcBlacklist, "TOPLEFT", -3, 3);
		dropdownNpcBlacklist.Border:SetPoint("BOTTOMRIGHT", buttonNpcBlacklistAdd, "BOTTOMRIGHT",  3, -3);
		dropdownNpcBlacklist.Border:SetColorTexture(0.1, 0.1, 0.1, 1);
		dropdownNpcBlacklist:ClearAllPoints();
		dropdownNpcBlacklist:SetPoint("TOPLEFT", buttonNpcBlacklist, "TOPRIGHT", 5, 0);
	end

end

local function GUICategory_Fonts(index)
	local dropdownMenuFont = VGUI.CreateDropdownMenu();
	local textAnchors = { "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "TOP", "CENTER", "BOTTOM", "TOPLEFT", "LEFT", "BOTTOMLEFT" };
	local textAnchorsLocalization = {
		[textAnchors[1]] = L["anchor-point:topright"],
		[textAnchors[2]] = L["anchor-point:right"],
		[textAnchors[3]] = L["anchor-point:bottomright"],
		[textAnchors[4]] = L["anchor-point:top"],
		[textAnchors[5]] = L["anchor-point:center"],
		[textAnchors[6]] = L["anchor-point:bottom"],
		[textAnchors[7]] = L["anchor-point:topleft"],
		[textAnchors[8]] = L["anchor-point:left"],
		[textAnchors[9]] = L["anchor-point:bottomleft"]
	};
	local sliderTimerFontScale, sliderTimerFontSize, timerTextColorArea, tenthsOfSecondsArea, checkboxShowCooldownText, auraTextArea, buttonFont, checkBoxUseRelativeFontSize, sliderTimerTextXOffset;
	local dropdownTimerTextAnchor, checkBoxUseRelativeTextColor, colorPickerTimerTextZeroPercent, colorPickerTimerTextFiveSeconds, colorPickerTimerTextMinute, colorPickerTimerTextHundredPercent;
	local colorPickerTimerTextMore;

	-- // checkboxShowCooldownText
	do
		checkboxShowCooldownText = VGUI.CreateCheckBox();
		checkboxShowCooldownText:SetText(L["options:general:show-cooldown-text"]);
		checkboxShowCooldownText:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownText = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
			if (addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownText) then
				auraTextArea:Show();
			else
				auraTextArea:Hide();
			end
		end);
		checkboxShowCooldownText:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownText);
		checkboxShowCooldownText:SetParent(GUIFrame);
		checkboxShowCooldownText:SetPoint("TOPLEFT", GUIFrame, "TOPLEFT", 160, -20);
		table_insert(GUIFrame.Categories[index], checkboxShowCooldownText);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkboxShowCooldownText:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownText);
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxShowCooldownText:SetScript("OnShow", function()
			if (addonTable.db.IconGroups[CurrentIconGroup].ShowCooldownText) then
				auraTextArea:Show();
			else
				auraTextArea:Hide();
			end
		end);
		checkboxShowCooldownText:SetScript("OnHide", function()
			auraTextArea:Hide();
		end);
	end

	-- // auraTextArea;
	do
		auraTextArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		auraTextArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		auraTextArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		auraTextArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		auraTextArea:SetPoint("TOPLEFT", checkboxShowCooldownText, "BOTTOMLEFT", 0, 0);
		auraTextArea:SetPoint("BOTTOMRIGHT", GUIFrame.ControlsFrame, "BOTTOMRIGHT", 0, 0);
		auraTextArea:Hide();
	end

	-- // dropdownFont
	do
		local fonts = { };
		buttonFont = VGUI.CreateButton();
		buttonFont:SetParent(auraTextArea);
		buttonFont:SetText(L["Font"] .. ": " .. addonTable.db.IconGroups[CurrentIconGroup].Font);

		for _, font in next, SML:List("font") do
			table_insert(fonts, {
				["text"] = font,
				["icon"] = [[Interface\AddOns\NameplateAuras\media\font.tga]],
				["func"] = function(info)
					buttonFont.Text:SetText(L["Font"] .. ": " .. info.text);
					addonTable.db.IconGroups[CurrentIconGroup].Font = info.text;
					addonTable.UpdateAllNameplates(true);
				end,
				["font"] = SML:Fetch("font", font),
			});
		end
		table_sort(fonts, function(item1, item2) return item1.text < item2.text; end);

		buttonFont:SetHeight(24);
		buttonFont:SetPoint("TOPLEFT", auraTextArea, "TOPLEFT", 10, -10);
		buttonFont:SetPoint("TOPRIGHT", auraTextArea, "TOPRIGHT", -10, -10);
		buttonFont:SetScript("OnClick", function(self)
			if (dropdownMenuFont:IsVisible()) then
				dropdownMenuFont:Hide();
			else
				dropdownMenuFont:SetList(fonts);
				dropdownMenuFont:SetParent(self);
				dropdownMenuFont:ClearAllPoints();
				dropdownMenuFont:SetPoint("TOP", self, "BOTTOM", 0, 0);
				dropdownMenuFont:Show();
			end
		end);
	end

	-- // checkBoxUseRelativeFontSize
	do

		checkBoxUseRelativeFontSize = VGUI.CreateCheckBox();
		checkBoxUseRelativeFontSize:SetText(L["options:timer-text:scale-font-size"]);
		checkBoxUseRelativeFontSize:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeScale = this:GetChecked();
			if (addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeScale) then
				sliderTimerFontScale:Show();
				sliderTimerFontSize:Hide();
			else
				sliderTimerFontScale:Hide();
				sliderTimerFontSize:Show();
			end
		end);
		checkBoxUseRelativeFontSize:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeScale);
		checkBoxUseRelativeFontSize:SetParent(auraTextArea);
		checkBoxUseRelativeFontSize:SetPoint("TOPLEFT", buttonFont, "BOTTOMLEFT", 0, -10);
		table_insert(GUIFrame.Categories[index], checkBoxUseRelativeFontSize);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxUseRelativeFontSize:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeScale);
		end);
		checkBoxUseRelativeFontSize:SetScript("OnShow", function()
			if (addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeScale) then
				sliderTimerFontScale:Show();
				sliderTimerFontSize:Hide();
			else
				sliderTimerFontScale:Hide();
				sliderTimerFontSize:Show();
			end
		end);
		checkBoxUseRelativeFontSize:SetScript("OnHide", function()
			sliderTimerFontScale:Hide();
			sliderTimerFontSize:Hide();
		end);

	end

	-- // sliderTimerFontScale
	do
		local minValue, maxValue = 0.3, 3;
		sliderTimerFontScale = VGUI.CreateSlider();
		sliderTimerFontScale:SetParent(auraTextArea);
		sliderTimerFontScale:SetWidth(170);
		sliderTimerFontScale:SetPoint("TOPLEFT", checkBoxUseRelativeFontSize, "BOTTOMLEFT", 0, -10);
		sliderTimerFontScale.label:SetText(L["Font scale"]);
		sliderTimerFontScale.slider:SetValueStep(0.1);
		sliderTimerFontScale.slider:SetMinMaxValues(minValue, maxValue);
		sliderTimerFontScale.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].FontScale);
		sliderTimerFontScale.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.1f", value));
			sliderTimerFontScale.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].FontScale = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderTimerFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].FontScale));
		sliderTimerFontScale.editbox:SetScript("OnEnterPressed", function()
			if (sliderTimerFontScale.editbox:GetText() ~= "") then
				local v = tonumber(sliderTimerFontScale.editbox:GetText());
				if (v == nil) then
					sliderTimerFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].FontScale));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderTimerFontScale.slider:SetValue(v);
				end
				sliderTimerFontScale.editbox:ClearFocus();
			end
		end);
		sliderTimerFontScale.lowtext:SetText(tostring(minValue));
		sliderTimerFontScale.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderTimerFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].FontScale));
			sliderTimerFontScale.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].FontScale);
		end);
	end

	-- // sliderTimerTextXOffset
	do
		local minValue, maxValue = -100, 100;
		sliderTimerTextXOffset = VGUI.CreateSlider();
		sliderTimerTextXOffset:SetParent(auraTextArea);
		sliderTimerTextXOffset:SetWidth(170);
		sliderTimerTextXOffset:SetPoint("LEFT", sliderTimerFontScale, "RIGHT", 0, 0);
		sliderTimerTextXOffset.label:SetText(L["X offset"]);
		sliderTimerTextXOffset.slider:SetValueStep(1);
		sliderTimerTextXOffset.slider:SetMinMaxValues(minValue, maxValue);
		sliderTimerTextXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset);
		sliderTimerTextXOffset.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderTimerTextXOffset.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderTimerTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset));
		sliderTimerTextXOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderTimerTextXOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderTimerTextXOffset.editbox:GetText());
				if (v == nil) then
					sliderTimerTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderTimerTextXOffset.slider:SetValue(v);
				end
				sliderTimerTextXOffset.editbox:ClearFocus();
			end
		end);
		sliderTimerTextXOffset.lowtext:SetText(tostring(minValue));
		sliderTimerTextXOffset.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderTimerTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset));
			sliderTimerTextXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextXOffset);
		end);
		sliderTimerTextXOffset:Show();
	end

	-- // sliderTimerTextYOffset
	do
		local minValue, maxValue = -100, 100;
		local sliderTimerTextYOffset = VGUI.CreateSlider();
		sliderTimerTextYOffset:SetParent(auraTextArea);
		sliderTimerTextYOffset:SetWidth(170);
		sliderTimerTextYOffset:SetPoint("LEFT", sliderTimerTextXOffset, "RIGHT", 0, 0);
		sliderTimerTextYOffset.label:SetText(L["Y offset"]);
		sliderTimerTextYOffset.slider:SetValueStep(1);
		sliderTimerTextYOffset.slider:SetMinMaxValues(minValue, maxValue);
		sliderTimerTextYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset);
		sliderTimerTextYOffset.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderTimerTextYOffset.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderTimerTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset));
		sliderTimerTextYOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderTimerTextYOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderTimerTextYOffset.editbox:GetText());
				if (v == nil) then
					sliderTimerTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderTimerTextYOffset.slider:SetValue(v);
				end
				sliderTimerTextYOffset.editbox:ClearFocus();
			end
		end);
		sliderTimerTextYOffset.lowtext:SetText(tostring(minValue));
		sliderTimerTextYOffset.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderTimerTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset));
			sliderTimerTextYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextYOffset);
		end);
		sliderTimerTextYOffset:Show();
	end

	-- // sliderTimerFontSize
	do
		local minValue, maxValue = 6, 96;
		sliderTimerFontSize = VGUI.CreateSlider();
		sliderTimerFontSize:SetParent(auraTextArea);
		sliderTimerFontSize:SetWidth(170);
		sliderTimerFontSize:SetPoint("TOPLEFT", checkBoxUseRelativeFontSize, "BOTTOMLEFT", 0, -10);
		sliderTimerFontSize.label:SetText(L["Font size"]);
		sliderTimerFontSize.slider:SetValueStep(1);
		sliderTimerFontSize.slider:SetMinMaxValues(minValue, maxValue);
		sliderTimerFontSize.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize);
		sliderTimerFontSize.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderTimerFontSize.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderTimerFontSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize));
		sliderTimerFontSize.editbox:SetScript("OnEnterPressed", function()
			if (sliderTimerFontSize.editbox:GetText() ~= "") then
				local v = tonumber(sliderTimerFontSize.editbox:GetText());
				if (v == nil) then
					sliderTimerFontSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderTimerFontSize.slider:SetValue(v);
				end
				sliderTimerFontSize.editbox:ClearFocus();
			end
		end);
		sliderTimerFontSize.lowtext:SetText(tostring(minValue));
		sliderTimerFontSize.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderTimerFontSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize));
			sliderTimerFontSize.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].TimerTextSize);
		end);
	end

	-- // dropdownTimerTextAnchor
	do
		dropdownTimerTextAnchor = CreateFrame("Frame", "NAuras.GUI.Fonts.DropdownTimerTextAnchor", auraTextArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownTimerTextAnchor, 210);
		dropdownTimerTextAnchor:SetPoint("TOPLEFT", sliderTimerFontScale, "BOTTOMLEFT", 0, 20);
		local info = {};
		dropdownTimerTextAnchor.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(textAnchors) do
				info.text = textAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchor = self.value;
					_G[dropdownTimerTextAnchor:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = anchorPoint == addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchor;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownTimerTextAnchor:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchor]);
		dropdownTimerTextAnchor.text = dropdownTimerTextAnchor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownTimerTextAnchor.text:SetPoint("LEFT", 20, 20);
		dropdownTimerTextAnchor.text:SetText(L["Anchor point"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownTimerTextAnchor:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchor]);
		end);
	end

	-- // dropdownTimerTextAnchorIcon
	do
		local dropdownTimerTextAnchorIcon = CreateFrame("Frame", "NAuras.GUI.Fonts.DropdownTimerTextAnchorIcon", auraTextArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownTimerTextAnchorIcon, 210);
		dropdownTimerTextAnchorIcon:SetPoint("LEFT", dropdownTimerTextAnchor, "RIGHT", 0, 0);
		local info = {};
		dropdownTimerTextAnchorIcon.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(textAnchors) do
				info.text = textAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchorIcon = self.value;
					_G[dropdownTimerTextAnchorIcon:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = anchorPoint == addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchorIcon;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownTimerTextAnchorIcon:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchorIcon]);
		dropdownTimerTextAnchorIcon.text = dropdownTimerTextAnchorIcon:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownTimerTextAnchorIcon.text:SetPoint("LEFT", 20, 20);
		dropdownTimerTextAnchorIcon.text:SetText(L["Anchor to icon"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownTimerTextAnchorIcon:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].TimerTextAnchorIcon]);
		end);
	end

	-- // timerTextColorArea
	do
		timerTextColorArea = CreateFrame("Frame", nil, auraTextArea, BackdropTemplateMixin and "BackdropTemplate");
		timerTextColorArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		timerTextColorArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		timerTextColorArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		timerTextColorArea:SetPoint("TOP", auraTextArea, "TOP", 0, -200);
		timerTextColorArea:SetWidth(400);
		timerTextColorArea:SetHeight(95);
	end

	-- // timerTextColorInfo
	do

		local timerTextColorInfo = timerTextColorArea:CreateFontString(nil, "OVERLAY", "GameFontNormal");
		timerTextColorInfo:SetText(L["options:timer-text:text-color-note"]);
		timerTextColorInfo:SetPoint("TOP", 0, -10);

	end

	-- // colorPickerTimerTextFiveSeconds
	do
		colorPickerTimerTextFiveSeconds = VGUI.CreateColorPicker();
		colorPickerTimerTextFiveSeconds:SetParent(timerTextColorArea);
		colorPickerTimerTextFiveSeconds:SetPoint("TOPLEFT", 10, -40);
		colorPickerTimerTextFiveSeconds:SetText(L["< 5sec"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].TimerTextSoonToExpireColor;
		colorPickerTimerTextFiveSeconds:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerTimerTextFiveSeconds.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextSoonToExpireColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		colorPickerTimerTextFiveSeconds:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].TimerTextSoonToExpireColor;
			colorPickerTimerTextFiveSeconds:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // colorPickerTimerTextZeroPercent
	do
		colorPickerTimerTextZeroPercent = VGUI.CreateColorPicker();
		colorPickerTimerTextZeroPercent:SetParent(timerTextColorArea);
		colorPickerTimerTextZeroPercent:SetPoint("TOPLEFT", 10, -40);
		colorPickerTimerTextZeroPercent:SetText("0%");
		local t = addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorZeroPercent;
		colorPickerTimerTextZeroPercent:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerTimerTextZeroPercent.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorZeroPercent = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		colorPickerTimerTextZeroPercent:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorZeroPercent;
			colorPickerTimerTextZeroPercent:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // colorPickerTimerTextMinute
	do
		colorPickerTimerTextMinute = VGUI.CreateColorPicker();
		colorPickerTimerTextMinute:SetParent(timerTextColorArea);
		colorPickerTimerTextMinute:SetPoint("TOPLEFT", 135, -40);
		colorPickerTimerTextMinute:SetText(L["< 1min"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].TimerTextUnderMinuteColor;
		colorPickerTimerTextMinute:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerTimerTextMinute.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextUnderMinuteColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		colorPickerTimerTextMinute:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].TimerTextUnderMinuteColor;
			colorPickerTimerTextMinute:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // colorPickerTimerTextHundredPercent
	do
		colorPickerTimerTextHundredPercent = VGUI.CreateColorPicker();
		colorPickerTimerTextHundredPercent:SetParent(timerTextColorArea);
		colorPickerTimerTextHundredPercent:SetPoint("TOPLEFT", 135, -40);
		colorPickerTimerTextHundredPercent:SetText("100%");
		local t = addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorHundredPercent;
		colorPickerTimerTextHundredPercent:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerTimerTextHundredPercent.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorHundredPercent = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		colorPickerTimerTextHundredPercent:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].TimerTextColorHundredPercent;
			colorPickerTimerTextHundredPercent:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // colorPickerTimerTextMore
	do
		colorPickerTimerTextMore = VGUI.CreateColorPicker();
		colorPickerTimerTextMore:SetParent(timerTextColorArea);
		colorPickerTimerTextMore:SetPoint("TOPLEFT", 260, -40);
		colorPickerTimerTextMore:SetText(L["> 1min"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].TimerTextLongerColor;
		colorPickerTimerTextMore:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerTimerTextMore.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextLongerColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		colorPickerTimerTextMore:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].TimerTextLongerColor;
			colorPickerTimerTextMore:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // checkBoxUseRelativeTextColor
	do

		local function OnPropertyChanged()
			if (addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeColor) then
				colorPickerTimerTextFiveSeconds:Hide();
				colorPickerTimerTextMinute:Hide();
				colorPickerTimerTextMore:Hide();
				colorPickerTimerTextZeroPercent:Show();
				colorPickerTimerTextHundredPercent:Show();
			else
				colorPickerTimerTextFiveSeconds:Show();
				colorPickerTimerTextMinute:Show();
				colorPickerTimerTextMore:Show();
				colorPickerTimerTextZeroPercent:Hide();
				colorPickerTimerTextHundredPercent:Hide();
			end
		end

		checkBoxUseRelativeTextColor = VGUI.CreateCheckBox();
		checkBoxUseRelativeTextColor:SetText(L["options:timer-text:relative-color"]);
		VGUI.SetTooltip(checkBoxUseRelativeTextColor, L["options:timer-text:relative-color:tooltip"]);
		checkBoxUseRelativeTextColor:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeColor = this:GetChecked();
			OnPropertyChanged();
		end);
		checkBoxUseRelativeTextColor:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeColor);
		checkBoxUseRelativeTextColor:SetParent(timerTextColorArea);
		checkBoxUseRelativeTextColor:SetPoint("TOPLEFT", 10, -65);
		table_insert(GUIFrame.Categories[index], checkBoxUseRelativeTextColor);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxUseRelativeTextColor:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].TimerTextUseRelativeColor);
		end);
		checkBoxUseRelativeTextColor:HookScript("OnShow", function()
			OnPropertyChanged();
		end);

	end

	-- // tenthsOfSecondsArea
	do
		tenthsOfSecondsArea = CreateFrame("Frame", nil, auraTextArea, BackdropTemplateMixin and "BackdropTemplate");
		tenthsOfSecondsArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		tenthsOfSecondsArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		tenthsOfSecondsArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		tenthsOfSecondsArea:SetPoint("TOP", timerTextColorArea, "BOTTOM", 0, -10);
		tenthsOfSecondsArea:SetWidth(360);
		tenthsOfSecondsArea:SetHeight(71);
	end

	-- // sliderDisplayTenthsOfSeconds
	do
		local minValue, maxValue = 0, 10;
		local sliderDisplayTenthsOfSeconds = VGUI.CreateSlider();
		sliderDisplayTenthsOfSeconds:SetParent(tenthsOfSecondsArea);
		sliderDisplayTenthsOfSeconds:SetWidth(340);
		sliderDisplayTenthsOfSeconds:SetPoint("TOPLEFT", 10, -10);
		sliderDisplayTenthsOfSeconds.label:SetText(L["options:timer-text:min-duration-to-display-tenths-of-seconds"]);
		sliderDisplayTenthsOfSeconds.slider:SetValueStep(0.1);
		sliderDisplayTenthsOfSeconds.slider:SetMinMaxValues(minValue, maxValue);
		sliderDisplayTenthsOfSeconds.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds);
		sliderDisplayTenthsOfSeconds.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.1f", value));
			sliderDisplayTenthsOfSeconds.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds = actualValue;
		end);
		sliderDisplayTenthsOfSeconds.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds));
		sliderDisplayTenthsOfSeconds.editbox:SetScript("OnEnterPressed", function(self)
			if (self:GetText() ~= "") then
				local v = tonumber(self:GetText());
				if (v == nil) then
					self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderDisplayTenthsOfSeconds.slider:SetValue(v);
				end
				self:ClearFocus();
			else
				self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds));
				msg(L["Value must be a number"]);
			end
		end);
		sliderDisplayTenthsOfSeconds.lowtext:SetText(tostring(minValue));
		sliderDisplayTenthsOfSeconds.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderDisplayTenthsOfSeconds.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds));
			sliderDisplayTenthsOfSeconds.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].MinTimeToShowTenthsOfSeconds);
		end);
		sliderDisplayTenthsOfSeconds:Show();
	end

end

local function GUICategory_AuraStackFont(index)
	local dropdownMenuFont = VGUI.CreateDropdownMenu();
	local textAnchors = { "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "TOP", "CENTER", "BOTTOM", "TOPLEFT", "LEFT", "BOTTOMLEFT" };
	local textAnchorsLocalization = {
		[textAnchors[1]] = L["anchor-point:topright"],
		[textAnchors[2]] = L["anchor-point:right"],
		[textAnchors[3]] = L["anchor-point:bottomright"],
		[textAnchors[4]] = L["anchor-point:top"],
		[textAnchors[5]] = L["anchor-point:center"],
		[textAnchors[6]] = L["anchor-point:bottom"],
		[textAnchors[7]] = L["anchor-point:topleft"],
		[textAnchors[8]] = L["anchor-point:left"],
		[textAnchors[9]] = L["anchor-point:bottomleft"]
	};
	local checkboxShowStacks, auraTextArea, sliderStacksFontScale, buttonFont, sliderStacksTextXOffset, dropdownStacksAnchor;

	-- // checkboxShowStacks
	do
		checkboxShowStacks = VGUI.CreateCheckBox();
		checkboxShowStacks:SetText(L["options:general:show-stacks"]);
		checkboxShowStacks:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowStacks = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
			if (addonTable.db.IconGroups[CurrentIconGroup].ShowStacks) then
				auraTextArea:Show();
			else
				auraTextArea:Hide();
			end
		end);
		checkboxShowStacks:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowStacks);
		checkboxShowStacks:SetParent(GUIFrame);
		checkboxShowStacks:SetPoint("TOPLEFT", GUIFrame, "TOPLEFT", 160, -20);
		table_insert(GUIFrame.Categories[index], checkboxShowStacks);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkboxShowStacks:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowStacks);
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxShowStacks:SetScript("OnShow", function()
			if (addonTable.db.IconGroups[CurrentIconGroup].ShowStacks) then
				auraTextArea:Show();
			else
				auraTextArea:Hide();
			end
		end);
		checkboxShowStacks:SetScript("OnHide", function()
			auraTextArea:Hide();
		end);
	end

	-- // auraTextArea;
	do
		auraTextArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		auraTextArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		auraTextArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		auraTextArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		auraTextArea:SetPoint("TOPLEFT", checkboxShowStacks, "BOTTOMLEFT", 0, 0);
		auraTextArea:SetPoint("BOTTOMRIGHT", GUIFrame.ControlsFrame, "BOTTOMRIGHT", 0, 0);
		auraTextArea:Hide();
	end

	-- // dropdownStacksFont, buttonFont
	do
		local fonts = { };
		buttonFont = VGUI.CreateButton();
		buttonFont:SetParent(auraTextArea);
		buttonFont:SetText(L["Font"] .. ": " .. addonTable.db.IconGroups[CurrentIconGroup].StacksFont);

		for _, font in next, SML:List("font") do
			table_insert(fonts, {
				["text"] = font,
				["icon"] = [[Interface\AddOns\NameplateAuras\media\font.tga]],
				["func"] = function(info)
					buttonFont.Text:SetText(L["Font"] .. ": " .. info.text);
					addonTable.db.IconGroups[CurrentIconGroup].StacksFont = info.text;
					addonTable.UpdateAllNameplates(true);
				end,
				["font"] = SML:Fetch("font", font),
			});
		end
		table_sort(fonts, function(item1, item2) return item1.text < item2.text; end);

		buttonFont:SetWidth(170);
		buttonFont:SetHeight(24);
		buttonFont:SetPoint("TOPLEFT", auraTextArea, "TOPLEFT", 10, -10);
		buttonFont:SetPoint("TOPRIGHT", auraTextArea, "TOPRIGHT", -10, -10);
		buttonFont:SetScript("OnClick", function(self)
			if (dropdownMenuFont:IsVisible()) then
				dropdownMenuFont:Hide();
			else
				dropdownMenuFont:SetList(fonts);
				dropdownMenuFont:SetParent(self);
				dropdownMenuFont:ClearAllPoints();
				dropdownMenuFont:SetPoint("TOP", self, "BOTTOM", 0, 0);
				dropdownMenuFont:Show();
			end
		end);
		buttonFont:Show();
	end

	-- // sliderStacksFontScale
	do
		local minValue, maxValue = 0.3, 3;
		sliderStacksFontScale = VGUI.CreateSlider();
		sliderStacksFontScale:SetParent(auraTextArea);
		sliderStacksFontScale:SetWidth(170);
		sliderStacksFontScale:SetPoint("TOPLEFT", buttonFont, "BOTTOMLEFT", 0, -20);
		sliderStacksFontScale.label:SetText(L["Font scale"]);
		sliderStacksFontScale.slider:SetValueStep(0.1);
		sliderStacksFontScale.slider:SetMinMaxValues(minValue, maxValue);
		sliderStacksFontScale.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale);
		sliderStacksFontScale.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.1f", value));
			sliderStacksFontScale.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderStacksFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale));
		sliderStacksFontScale.editbox:SetScript("OnEnterPressed", function()
			if (sliderStacksFontScale.editbox:GetText() ~= "") then
				local v = tonumber(sliderStacksFontScale.editbox:GetText());
				if (v == nil) then
					sliderStacksFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderStacksFontScale.slider:SetValue(v);
				end
				sliderStacksFontScale.editbox:ClearFocus();
			end
		end);
		sliderStacksFontScale.lowtext:SetText(tostring(minValue));
		sliderStacksFontScale.hightext:SetText(tostring(maxValue));
		sliderStacksFontScale:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderStacksFontScale.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale));
			sliderStacksFontScale.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksFontScale);
		end);

	end

	-- // sliderStacksTextXOffset
	do

		local minValue, maxValue = -100, 100;
		sliderStacksTextXOffset = VGUI.CreateSlider();
		sliderStacksTextXOffset:SetParent(auraTextArea);
		sliderStacksTextXOffset:SetWidth(170);
		sliderStacksTextXOffset:SetPoint("LEFT", sliderStacksFontScale, "RIGHT", 0, 0);
		sliderStacksTextXOffset.label:SetText(L["X offset"]);
		sliderStacksTextXOffset.slider:SetValueStep(1);
		sliderStacksTextXOffset.slider:SetMinMaxValues(minValue, maxValue);
		sliderStacksTextXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset);
		sliderStacksTextXOffset.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderStacksTextXOffset.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderStacksTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset));
		sliderStacksTextXOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderStacksTextXOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderStacksTextXOffset.editbox:GetText());
				if (v == nil) then
					sliderStacksTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderStacksTextXOffset.slider:SetValue(v);
				end
				sliderStacksTextXOffset.editbox:ClearFocus();
			end
		end);
		sliderStacksTextXOffset.lowtext:SetText(tostring(minValue));
		sliderStacksTextXOffset.hightext:SetText(tostring(maxValue));
		sliderStacksTextXOffset:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderStacksTextXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset));
			sliderStacksTextXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksTextXOffset);
		end);

	end

	-- // sliderStacksTextYOffset
	do

		local minValue, maxValue = -100, 100;
		local sliderStacksTextYOffset = VGUI.CreateSlider();
		sliderStacksTextYOffset:SetParent(auraTextArea);
		sliderStacksTextYOffset:SetWidth(165);
		sliderStacksTextYOffset:SetPoint("LEFT", sliderStacksTextXOffset, "RIGHT", 0, 0);
		sliderStacksTextYOffset.label:SetText(L["Y offset"]);
		sliderStacksTextYOffset.slider:SetValueStep(1);
		sliderStacksTextYOffset.slider:SetMinMaxValues(minValue, maxValue);
		sliderStacksTextYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset);
		sliderStacksTextYOffset.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderStacksTextYOffset.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderStacksTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset));
		sliderStacksTextYOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderStacksTextYOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderStacksTextYOffset.editbox:GetText());
				if (v == nil) then
					sliderStacksTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderStacksTextYOffset.slider:SetValue(v);
				end
				sliderStacksTextYOffset.editbox:ClearFocus();
			end
		end);
		sliderStacksTextYOffset.lowtext:SetText(tostring(minValue));
		sliderStacksTextYOffset.hightext:SetText(tostring(maxValue));
		sliderStacksTextYOffset:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderStacksTextYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset));
			sliderStacksTextYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].StacksTextYOffset);
		end);

	end

	-- // dropdownStacksAnchor
	do
		dropdownStacksAnchor = CreateFrame("Frame", "NAuras.GUI.Fonts.DropdownStacksAnchor", auraTextArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownStacksAnchor, 210);
		dropdownStacksAnchor:SetPoint("TOPLEFT", sliderStacksFontScale, "BOTTOMLEFT", 0, 20);
		local info = {};
		dropdownStacksAnchor.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(textAnchors) do
				info.text = textAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchor = self.value;
					_G[dropdownStacksAnchor:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = anchorPoint == addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchor;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownStacksAnchor:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchor]);
		dropdownStacksAnchor.text = dropdownStacksAnchor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownStacksAnchor.text:SetPoint("LEFT", 20, 20);
		dropdownStacksAnchor.text:SetText(L["Anchor point"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownStacksAnchor:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchor]);
		end);
	end

	-- // dropdownStacksAnchorIcon
	do

		local dropdownStacksAnchorIcon = CreateFrame("Frame", "NAuras.GUI.Fonts.DropdownStacksAnchorIcon", auraTextArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownStacksAnchorIcon, 210);
		dropdownStacksAnchorIcon:SetPoint("LEFT", dropdownStacksAnchor, "RIGHT", 0, 0);
		local info = {};
		dropdownStacksAnchorIcon.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(textAnchors) do
				info.text = textAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchorIcon = self.value;
					_G[dropdownStacksAnchorIcon:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = anchorPoint == addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchorIcon;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownStacksAnchorIcon:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchorIcon]);
		dropdownStacksAnchorIcon.text = dropdownStacksAnchorIcon:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownStacksAnchorIcon.text:SetPoint("LEFT", 20, 20);
		dropdownStacksAnchorIcon.text:SetText(L["Anchor to icon"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownStacksAnchorIcon:GetName() .. "Text"]:SetText(textAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].StacksTextAnchorIcon]);
		end);

	end

	-- // colorPickerStacksTextColor
	do
		local colorPickerStacksTextColor = VGUI.CreateColorPicker();
		colorPickerStacksTextColor:SetParent(auraTextArea);
		colorPickerStacksTextColor:SetPoint("TOPLEFT", dropdownStacksAnchor, "BOTTOMLEFT", 20, -20);
		colorPickerStacksTextColor:SetText(L["Text color"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].StacksTextColor;
		colorPickerStacksTextColor:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerStacksTextColor.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].StacksTextColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].StacksTextColor;
			colorPickerStacksTextColor:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
		colorPickerStacksTextColor:Show();
	end

end

local function GUICategory_Borders(index)

	local debuffArea, dropdownBorderType, editBoxBorderFilePath, sliderBorderThickness;
	local SetControls;

	-- // dropdownBorderType
	do
		local borderTypes = {
			[addonTable.BORDER_TYPE_BUILTIN] = L["options:borders:BORDER_TYPE_BUILTIN"],
			[addonTable.BORDER_TYPE_CUSTOM] = L["options:borders:BORDER_TYPE_CUSTOM"],
		};
		dropdownBorderType = CreateFrame("Frame", "NAuras.GUI.Border.dropdownBorderType", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownBorderType, 150);
		dropdownBorderType:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -20);
		local info = {};
		dropdownBorderType.initialize = function()
			wipe(info);
			for borderType, borderTypeL in pairs(borderTypes) do
				info.text = borderTypeL;
				info.value = borderType;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].BorderType = self.value;
					_G[dropdownBorderType:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
					SetControls();
				end
				info.checked = borderType == addonTable.db.IconGroups[CurrentIconGroup].BorderType;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownBorderType:GetName() .. "Text"]:SetText(borderTypes[addonTable.db.IconGroups[CurrentIconGroup].BorderType]);
		dropdownBorderType.text = dropdownBorderType:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownBorderType.text:SetPoint("LEFT", 20, 20);
		dropdownBorderType.text:SetText(L["options:borders:border-type"]);

		function SetControls()
			if (addonTable.db.IconGroups[CurrentIconGroup].BorderType == addonTable.BORDER_TYPE_BUILTIN) then
				editBoxBorderFilePath:Hide();
				sliderBorderThickness:Show();
			elseif (addonTable.db.IconGroups[CurrentIconGroup].BorderType == addonTable.BORDER_TYPE_CUSTOM) then
				editBoxBorderFilePath:Show();
				sliderBorderThickness:Hide();
			end
		end

		table_insert(GUIFrame.Categories[index], dropdownBorderType);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownBorderType:GetName() .. "Text"]:SetText(borderTypes[addonTable.db.IconGroups[CurrentIconGroup].BorderType]);
			addonTable.UpdateAllNameplates(true);
			SetControls();
		end);
	end

	-- // editBoxBorderFilePath
	do
		editBoxBorderFilePath = CreateFrame("EditBox", nil, dropdownBorderType, "InputBoxTemplate");
		editBoxBorderFilePath:SetAutoFocus(false);
		editBoxBorderFilePath:SetFontObject(GameFontHighlightSmall);
		editBoxBorderFilePath:SetPoint("LEFT", dropdownBorderType, "RIGHT", 0, 0);
		editBoxBorderFilePath:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		editBoxBorderFilePath:SetHeight(20);
		editBoxBorderFilePath:SetJustifyH("LEFT");
		editBoxBorderFilePath:EnableMouse(true);
		editBoxBorderFilePath:SetScript("OnEscapePressed", function() editBoxBorderFilePath:ClearFocus(); end);
		editBoxBorderFilePath:SetScript("OnEnterPressed", function() editBoxBorderFilePath:ClearFocus(); end);
		editBoxBorderFilePath:SetScript("OnTextChanged", function(self)
			local inputText = self:GetText();
			addonTable.db.IconGroups[CurrentIconGroup].BorderFilePath = inputText;
			addonTable.UpdateAllNameplates(true);
		end);
		local text = editBoxBorderFilePath:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		text:SetPoint("LEFT", 0, 15);
		text:SetText(L["options:borders:border-file-path"]);
		editBoxBorderFilePath:SetText(addonTable.db.IconGroups[CurrentIconGroup].BorderFilePath or "");
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			editBoxBorderFilePath:SetText(addonTable.db.IconGroups[CurrentIconGroup].BorderFilePath or "");
		end);
	end

	-- // sliderBorderThickness
	do

		local minValue, maxValue = 1, 5;
		sliderBorderThickness = VGUI.CreateSlider();
		sliderBorderThickness:SetParent(dropdownBorderType);
		sliderBorderThickness:SetWidth(325);
		sliderBorderThickness:SetPoint("LEFT", dropdownBorderType, "RIGHT", 0, -25);
		sliderBorderThickness:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		sliderBorderThickness.label:SetText(L["Border thickness"]);
		sliderBorderThickness.slider:SetValueStep(1);
		sliderBorderThickness.slider:SetMinMaxValues(minValue, maxValue);
		sliderBorderThickness.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].BorderThickness);
		sliderBorderThickness.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.0f", value));
			sliderBorderThickness.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].BorderThickness = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderBorderThickness.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].BorderThickness));
		sliderBorderThickness.editbox:SetScript("OnEnterPressed", function()
			if (sliderBorderThickness.editbox:GetText() ~= "") then
				local v = tonumber(sliderBorderThickness.editbox:GetText());
				if (v == nil) then
					sliderBorderThickness.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].BorderThickness));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderBorderThickness.slider:SetValue(v);
				end
				sliderBorderThickness.editbox:ClearFocus();
			end
		end);
		sliderBorderThickness.lowtext:SetText(tostring(minValue));
		sliderBorderThickness.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderBorderThickness.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].BorderThickness));
			sliderBorderThickness.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].BorderThickness);
			addonTable.UpdateAllNameplates(true);
		end);

	end

	-- // debuffArea
	do

		debuffArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		debuffArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		debuffArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		debuffArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		debuffArea:SetPoint("TOPLEFT", dropdownBorderType, "BOTTOMLEFT", 0, -10);
		debuffArea:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		debuffArea:SetHeight(110);
		table_insert(GUIFrame.Categories[index], debuffArea);

	end

	-- // checkBoxDebuffBorder
	do

		local checkBoxDebuffBorder = VGUI.CreateCheckBox();
		checkBoxDebuffBorder:SetText(L["Show border around debuff icons"]);
		checkBoxDebuffBorder:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowDebuffBorders = this:GetChecked();
			addonTable.UpdateAllNameplates();
		end);
		checkBoxDebuffBorder:SetParent(debuffArea);
		checkBoxDebuffBorder:SetPoint("TOPLEFT", 15, -15);
		checkBoxDebuffBorder:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowDebuffBorders);
		table_insert(GUIFrame.Categories[index], checkBoxDebuffBorder);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxDebuffBorder:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowDebuffBorders);
		end);

	end

	-- // colorPickerDebuffMagic
	do
		local colorPickerDebuffMagic = VGUI.CreateColorPicker();
		colorPickerDebuffMagic:SetParent(debuffArea);
		colorPickerDebuffMagic:SetPoint("TOPLEFT", 15, -45);
		colorPickerDebuffMagic:SetText(L["Magic"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersMagicColor;
		colorPickerDebuffMagic:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerDebuffMagic.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersMagicColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], colorPickerDebuffMagic);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersMagicColor;
			colorPickerDebuffMagic:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // colorPickerDebuffCurse
	do

		local colorPickerDebuffCurse = VGUI.CreateColorPicker();
		colorPickerDebuffCurse:SetParent(debuffArea);
		colorPickerDebuffCurse:SetPoint("TOPLEFT", 135, -45);
		colorPickerDebuffCurse:SetText(L["Curse"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersCurseColor;
		colorPickerDebuffCurse:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerDebuffCurse.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersCurseColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], colorPickerDebuffCurse);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersCurseColor;
			colorPickerDebuffCurse:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);

	end

	-- // colorPickerDebuffDisease
	do

		local colorPickerDebuffDisease = VGUI.CreateColorPicker();
		colorPickerDebuffDisease:SetParent(debuffArea);
		colorPickerDebuffDisease:SetPoint("TOPLEFT", 255, -45);
		colorPickerDebuffDisease:SetText(L["Disease"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersDiseaseColor;
		colorPickerDebuffDisease:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerDebuffDisease.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersDiseaseColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], colorPickerDebuffDisease);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersDiseaseColor;
			colorPickerDebuffDisease:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);

	end

	-- // colorPickerDebuffPoison
	do

		local colorPickerDebuffPoison = VGUI.CreateColorPicker();
		colorPickerDebuffPoison:SetParent(debuffArea);
		colorPickerDebuffPoison:SetPoint("TOPLEFT", 375, -45);
		colorPickerDebuffPoison:SetText(L["Poison"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersPoisonColor;
		colorPickerDebuffPoison:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerDebuffPoison.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersPoisonColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], colorPickerDebuffPoison);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersPoisonColor;
			colorPickerDebuffPoison:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);

	end

	-- // colorPickerDebuffOther
	do
		local colorPickerDebuffOther = VGUI.CreateColorPicker();
		colorPickerDebuffOther:SetParent(debuffArea);
		colorPickerDebuffOther:SetPoint("TOPLEFT", 15, -70);
		colorPickerDebuffOther:SetText(L["Other"]);
		local t = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersOtherColor;
		colorPickerDebuffOther:SetColor(t[1], t[2], t[3], t[4]);
		colorPickerDebuffOther.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersOtherColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], colorPickerDebuffOther);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].DebuffBordersOtherColor;
			colorPickerDebuffOther:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);
	end

	-- // checkBoxBuffBorder
	do

		local checkBoxBuffBorder = VGUI.CreateCheckBoxWithColorPicker();
		checkBoxBuffBorder:SetText(L["Show border around buff icons"]);
		checkBoxBuffBorder:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].ShowBuffBorders = this:GetChecked();
			addonTable.UpdateAllNameplates();
		end);
		checkBoxBuffBorder:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowBuffBorders);
		checkBoxBuffBorder:SetParent(GUIFrame);
		checkBoxBuffBorder:SetPoint("TOPLEFT", debuffArea, "BOTTOMLEFT", 0, -10);
		local t = addonTable.db.IconGroups[CurrentIconGroup].BuffBordersColor;
		checkBoxBuffBorder.ColorButton:SetColor(t[1], t[2], t[3], t[4]);
		checkBoxBuffBorder.ColorButton.func = function(_, r, g, b, a)
			addonTable.db.IconGroups[CurrentIconGroup].BuffBordersColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(GUIFrame.Categories[index], checkBoxBuffBorder);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxBuffBorder:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].ShowBuffBorders);
			local t1 = addonTable.db.IconGroups[CurrentIconGroup].BuffBordersColor;
			checkBoxBuffBorder.ColorButton:SetColor(t1[1], t1[2], t1[3], t1[4]);
		end);

	end

	SetControls();
end

local function GUICategory_4(index)
	local controls = { };
	local selectedSpell = 0;
	local dropdownMenuSpells = VGUI.CreateDropdownMenu();
	local spellArea, editboxAddSpell, buttonAddSpell, sliderSpellIconSizeWidth, dropdownSpellShowType, editboxSpellID, buttonDeleteSpell, checkboxShowOnFriends, checkboxAnimationRelative,
		checkboxShowOnEnemies, selectSpell, checkboxPvPMode, checkboxEnabled, checkboxGlow, areaGlow, sliderGlowThreshold, areaIconSize, areaAuraType, areaIDs, checkboxGlowRelative,
		dropdownGlowType, areaAnimation, checkboxAnimation, dropdownAnimationType, sliderAnimationThreshold, sliderSpellIconSizeHeight;
	local areaCustomBorder, checkboxCustomBorder, textboxCustomBorderPath, sliderCustomBorderSize, colorPickerCustomBorderColor, buttonExportSpell, areaTooltip;
	local areaIconGroups, dropdownIconGroups;

	local AuraTypesLocalization = {
		[AURA_TYPE_BUFF] =		L["Buff"],
		[AURA_TYPE_DEBUFF] =	L["Debuff"],
		[AURA_TYPE_ANY] =		L["Any"],
	};

	local glowTypes = {
		[addonTable.GLOW_TYPE_ACTIONBUTTON] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON"],
		[addonTable.GLOW_TYPE_AUTOUSE] = L["options:glow-type:GLOW_TYPE_AUTOUSE"],
		[addonTable.GLOW_TYPE_PIXEL] = L["options:glow-type:GLOW_TYPE_PIXEL"],
		[addonTable.GLOW_TYPE_ACTIONBUTTON_DIM] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON_DIM"],
	};

	local animationTypes = {
		[addonTable.ICON_ANIMATION_TYPE_ALPHA] = L["options:animation-type:ICON_ANIMATION_TYPE_ALPHA"],
	};

	local function GetButtonNameForSpell(spellInfo)
		local text = spellInfo.spellName;
		if (spellInfo.checkSpellID ~= nil and table_count(spellInfo.checkSpellID) > 0) then
			local t = { };
			for spellID in pairs(spellInfo.checkSpellID) do
				table_insert(t, spellID);
			end
			text = text .. " (" .. table.concat(t, ",") .. ")";
		end
		return text;
	end

	local function GetIDAndTextureForSpell(spellInfo)
		local spellID, textureID;
		if (spellInfo.checkSpellID ~= nil and table_count(spellInfo.checkSpellID) > 0) then
			spellID = next(spellInfo.checkSpellID);
			textureID = SpellTextureByID[spellID];
		else
			spellID = next(AllSpellIDsAndIconsByName[spellInfo.spellName]);
			if (spellID ~= nil) then
				textureID = SpellTextureByID[spellID];
			else
				textureID = 136243;
			end
		end
		return spellID, textureID;
	end

	function addonTable.GetCurrentlyEditingSpell()
		if (spellArea:IsVisible()) then
			if (selectedSpell ~= nil and selectedSpell > 0) then
				local spellID;
				local spell = addonTable.db.CustomSpells2[selectedSpell];
				if (spell.checkSpellID ~= nil and #spell.checkSpellID > 0) then
					spellID = next(spell.checkSpellID);
				else
					spellID = next(AllSpellIDsAndIconsByName[spell.spellName]);
				end
				return spell, spellID;
			else
				return nil;
			end
		else
			return nil;
		end
	end

	-- // batch actions
	do
		local buttonWidth = 250;
		local buttonHeight = 18;

		local frame = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		frame:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 3, right = 3, top = 3, bottom = 3 }
		});
		frame:SetBackdropColor(0.25, 0.24, 0.32, 1);
		frame:SetBackdropBorderColor(0.1,0.1,0.1,1);
		frame:SetWidth(buttonWidth+20);
		frame:SetHeight(10+18+5+18+5+18+10);
		frame:Hide();

		-- // batchActionsButton
		local batchActionsButton = VGUI.CreateButton();
		batchActionsButton:SetParent(dropdownMenuSpells);
		batchActionsButton:SetPoint("TOPLEFT", dropdownMenuSpells, "BOTTOMLEFT", 0, -10);
		batchActionsButton:SetPoint("TOPRIGHT", dropdownMenuSpells, "BOTTOMRIGHT", 0, -10);
		batchActionsButton:SetHeight(18);
		batchActionsButton:SetText(L["options:spells:batch-actions"]);
		batchActionsButton:SetScript("OnClick", function(self)
			frame:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 10, 0);
			frame:SetShown(not frame:IsVisible());
		end);
		batchActionsButton:SetScript("OnHide", function(self)
			frame:Hide();
		end);

		-- // enableAllSpellsButton
		local enableAllSpellsButton = VGUI.CreateButton();
		enableAllSpellsButton.clickedOnce = false;
		enableAllSpellsButton:SetParent(frame);
		enableAllSpellsButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10);
		enableAllSpellsButton:SetHeight(buttonHeight);
		enableAllSpellsButton:SetWidth(buttonWidth);
		enableAllSpellsButton:SetText(L["options:spells:enable-all-spells"]);
		enableAllSpellsButton:SetScript("OnClick", function(self)
			if (self.clickedOnce) then
				for spellIndex in pairs(addonTable.db.CustomSpells2) do
					addonTable.db.CustomSpells2[spellIndex].enabledState = CONST_SPELL_MODE_ALL;
				end
				addonTable.UpdateAllNameplates(false);
				selectSpell:Click();
				self.clickedOnce = false;
				self:SetText(L["options:spells:enable-all-spells"]);
			else
				self.clickedOnce = true;
				self:SetText(L["options:spells:please-push-once-more"]);
				CTimerAfter(3, function()
					self.clickedOnce = false;
					self:SetText(L["options:spells:enable-all-spells"]);
				end);
			end
		end);
		enableAllSpellsButton:SetScript("OnHide", function(self)
			self.clickedOnce = false;
			self:SetText(L["options:spells:enable-all-spells"]);
		end);

		-- // disableAllSpellsButton
		local disableAllSpellsButton = VGUI.CreateButton();
		disableAllSpellsButton.clickedOnce = false;
		disableAllSpellsButton:SetParent(frame);
		disableAllSpellsButton:SetPoint("TOPLEFT", enableAllSpellsButton, "BOTTOMLEFT", 0, -5);
		disableAllSpellsButton:SetPoint("TOPRIGHT", enableAllSpellsButton, "BOTTOMRIGHT", 0, -5);
		disableAllSpellsButton:SetHeight(buttonHeight);
		disableAllSpellsButton:SetText(L["options:spells:disable-all-spells"]);
		disableAllSpellsButton:SetScript("OnClick", function(self)
			if (self.clickedOnce) then
				for spellIndex in pairs(addonTable.db.CustomSpells2) do
					addonTable.db.CustomSpells2[spellIndex].enabledState = CONST_SPELL_MODE_DISABLED;
				end
				addonTable.UpdateAllNameplates(false);
				selectSpell:Click();
				self.clickedOnce = false;
				self:SetText(L["options:spells:disable-all-spells"]);
			else
				self.clickedOnce = true;
				self:SetText(L["options:spells:please-push-once-more"]);
				CTimerAfter(3, function()
					self.clickedOnce = false;
					self:SetText(L["options:spells:disable-all-spells"]);
				end);
			end
		end);
		disableAllSpellsButton:SetScript("OnHide", function(self)
			self.clickedOnce = false;
			self:SetText(L["options:spells:disable-all-spells"]);
		end);

		-- // setAllSpellsToMine
		local setAllSpellsToMine = VGUI.CreateButton();
		setAllSpellsToMine.clickedOnce = false;
		setAllSpellsToMine:SetParent(frame);
		setAllSpellsToMine:SetPoint("TOPLEFT", disableAllSpellsButton, "BOTTOMLEFT", 0, -5);
		setAllSpellsToMine:SetPoint("TOPRIGHT", disableAllSpellsButton, "BOTTOMRIGHT", 0, -5);
		setAllSpellsToMine:SetHeight(buttonHeight);
		setAllSpellsToMine:SetText(L["options:spells:set-all-spells-to-my-auras-only"]);
		setAllSpellsToMine:SetScript("OnClick", function(self)
			if (self.clickedOnce) then
				for spellIndex in pairs(addonTable.db.CustomSpells2) do
					addonTable.db.CustomSpells2[spellIndex].enabledState = CONST_SPELL_MODE_MYAURAS;
	end
				addonTable.UpdateAllNameplates(false);
				selectSpell:Click();
				self.clickedOnce = false;
				self:SetText(L["options:spells:set-all-spells-to-my-auras-only"]);
			else
				self.clickedOnce = true;
				self:SetText(L["options:spells:please-push-once-more"]);
				CTimerAfter(3, function()
					self.clickedOnce = false;
					self:SetText(L["options:spells:set-all-spells-to-my-auras-only"]);
				end);
			end
		end);
		setAllSpellsToMine:SetScript("OnHide", function(self)
			self.clickedOnce = false;
			self:SetText(L["options:spells:set-all-spells-to-my-auras-only"]);
		end);
	end

	-- // delete all spells button
	do

		local function DeleteAllSpellsFromDB()
			if (not StaticPopupDialogs["NAURAS_MSG_DELETE_ALL_SPELLS"]) then
				StaticPopupDialogs["NAURAS_MSG_DELETE_ALL_SPELLS"] = {
					text = L["Do you really want to delete ALL spells?"],
					button1 = YES,
					button2 = NO,
					OnAccept = function()
						wipe(addonTable.db.CustomSpells2);
						addonTable.RebuildSpellCache();
						selectSpell:Click();
						addonTable.UpdateAllNameplates(true);
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				};
			end
			StaticPopup_Show("NAURAS_MSG_DELETE_ALL_SPELLS");
		end

		local deleteAllSpellsButton = VGUI.CreateButton();
		deleteAllSpellsButton.clickedOnce = false;
		deleteAllSpellsButton:SetParent(dropdownMenuSpells);
		deleteAllSpellsButton:SetPoint("TOPLEFT", dropdownMenuSpells, "BOTTOMLEFT", 0, -29);
		deleteAllSpellsButton:SetPoint("TOPRIGHT", dropdownMenuSpells, "BOTTOMRIGHT", 0, -29);
		deleteAllSpellsButton:SetHeight(18);
		deleteAllSpellsButton:SetText(L["Delete all spells"]);
		deleteAllSpellsButton:SetScript("OnClick", function(self)
			if (self.clickedOnce) then
				DeleteAllSpellsFromDB();
				self.clickedOnce = false;
				self:SetText(L["Delete all spells"]);
			else
				self.clickedOnce = true;
				self:SetText(L["options:spells:please-push-once-more"]);
				CTimerAfter(3, function()
					self.clickedOnce = false;
					self:SetText(L["Delete all spells"]);
				end);
			end
		end);
		deleteAllSpellsButton:SetScript("OnHide", function(self)
			self.clickedOnce = false;
			self:SetText(L["Delete all spells"]);
		end);

	end

	-- // spellArea
	do

		spellArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		spellArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		spellArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		spellArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		spellArea:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -70);
		spellArea:SetPoint("BOTTOMRIGHT", GUIFrame.ControlsFrame, "BOTTOMRIGHT", -10, 0);

		spellArea.scrollArea = CreateFrame("ScrollFrame", nil, spellArea, "UIPanelScrollFrameTemplate");
		spellArea.scrollArea:SetPoint("TOPLEFT", spellArea, "TOPLEFT", 0, -3);
		spellArea.scrollArea:SetPoint("BOTTOMRIGHT", spellArea, "BOTTOMRIGHT", -8, 3);
		spellArea.scrollArea:Show();

		spellArea.controlsFrame = CreateFrame("Frame", nil, spellArea.scrollArea);
		spellArea.scrollArea:SetScrollChild(spellArea.controlsFrame);
		spellArea.controlsFrame:SetWidth(360);
		spellArea.controlsFrame:SetHeight(spellArea:GetHeight() + 170);

		spellArea.scrollBG = CreateFrame("Frame", nil, spellArea, BackdropTemplateMixin and "BackdropTemplate")
		spellArea.scrollBG:SetBackdrop({
			bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
			edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 16,
			insets = { left = 4, right = 3, top = 4, bottom = 3 }
		});
		spellArea.scrollBG:SetBackdropColor(0, 0, 0)
		spellArea.scrollBG:SetBackdropBorderColor(0.4, 0.4, 0.4)
		spellArea.scrollBG:SetWidth(20);
		spellArea.scrollBG:SetHeight(spellArea.scrollArea:GetHeight());
		spellArea.scrollBG:SetPoint("TOPRIGHT", spellArea.scrollArea, "TOPRIGHT", 23, 0)


		table_insert(controls, spellArea);

	end

	-- // editboxAddSpell, buttonAddSpell
	do

		editboxAddSpell = CreateFrame("EditBox", nil, GUIFrame, "InputBoxTemplate");
		editboxAddSpell:SetAutoFocus(false);
		editboxAddSpell:SetFontObject(GameFontHighlightSmall);
		editboxAddSpell:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, 10, -10);
		editboxAddSpell:SetHeight(20);
		editboxAddSpell:SetWidth(340);
		editboxAddSpell:SetJustifyH("LEFT");
		editboxAddSpell:EnableMouse(true);
		editboxAddSpell:SetScript("OnEscapePressed", function() editboxAddSpell:ClearFocus(); end);
		editboxAddSpell:SetScript("OnEnterPressed", function() buttonAddSpell:Click(); end);
		local editboxText = editboxAddSpell:CreateFontString(nil, "ARTWORK", "GameFontDisable");
		editboxText:SetPoint("LEFT", 0, 0);
		editboxText:SetText(L["options:spells:add-new-spell"]);
		editboxAddSpell:SetScript("OnEditFocusGained", function() editboxText:Hide(); end);
		editboxAddSpell:SetScript("OnEditFocusLost", function() 
			local text = editboxAddSpell:GetText();
			if (text == nil or text == "") then
				editboxText:Show();
			end
		end);
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			if (editboxAddSpell:IsVisible() and editboxAddSpell:HasFocus() and link ~= nil) then
				local spellName = string.match(link, "%[\"?(.-)\"?%]");
				if (spellName ~= nil) then
					editboxAddSpell:SetText(spellName);
					editboxAddSpell:ClearFocus();
					return true;
				end
			end
		end);
		table_insert(GUIFrame.Categories[index], editboxAddSpell);

		buttonAddSpell = VGUI.CreateButton();
		buttonAddSpell:SetParent(GUIFrame);
		buttonAddSpell:SetText(L["options:spells:add-import-new-spell"]);
		buttonAddSpell:SetHeight(20);
		buttonAddSpell:SetPoint("LEFT", editboxAddSpell, "RIGHT", 10, 0);
		buttonAddSpell:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		buttonAddSpell:SetScript("OnClick", function()
			local text = editboxAddSpell:GetText();
			local customSpellID = nil;
			if (tonumber(text) ~= nil) then
				customSpellID = tonumber(text);
				text = SpellNameByID[tonumber(text)] or "";
			end
			-- if user entered name of spell
			if (customSpellID == nil) then
				if (AllSpellIDsAndIconsByName[text] == nil) then
					for _spellName in pairs(AllSpellIDsAndIconsByName) do
						if (string_lower(_spellName) == string_lower(text)) then
							text = _spellName;
						end
					end
				end
			end
			if (text ~= nil and AllSpellIDsAndIconsByName[text] ~= nil) then
				local spellName = text;
				local newSpellInfo = GetDefaultDBSpellEntry(CONST_SPELL_MODE_ALL, spellName, (customSpellID ~= nil) and { [customSpellID] = true } or nil);
				table_insert(addonTable.db.CustomSpells2, newSpellInfo);
				addonTable.RebuildSpellCache();
				selectSpell:Click();
				local btn = dropdownMenuSpells:GetButtonByText(GetButtonNameForSpell(newSpellInfo));
				if (btn ~= nil) then btn:Click(); end
				addonTable.UpdateAllNameplates(false);
				editboxAddSpell:SetText("");
				editboxAddSpell:ClearFocus();
			else
				-- import string?
				local decoded = LibDeflate:DecodeForPrint(editboxAddSpell:GetText());
				if (decoded == nil) then
					msg(L["Spell seems to be nonexistent"]);
					return;
				end

				local decompressed = LibDeflate:DecompressDeflate(decoded);
				if (decompressed == nil) then
					msg(L["Spell seems to be nonexistent"]);
					return;
				end

				local success, deserialized = LibSerialize:Deserialize(decompressed);
				if (not success) then
					msg(L["Spell seems to be nonexistent"]);
					return;
				end

				table_insert(addonTable.db.CustomSpells2, deserialized);
				addonTable.RebuildSpellCache();
				selectSpell:Click();
				local btn = dropdownMenuSpells:GetButtonByText(GetButtonNameForSpell(deserialized));
				if (btn ~= nil) then btn:Click(); end
				addonTable.UpdateAllNameplates(false);
				editboxAddSpell:SetText("");
				editboxAddSpell:ClearFocus();
			end
		end);
		buttonAddSpell:Disable();
		hooksecurefunc(addonTable, "OnSpellInfoCachesReady", function() buttonAddSpell:Enable(); end);
		GUIFrame:HookScript("OnHide", function() buttonAddSpell:Disable(); end);
		table_insert(GUIFrame.Categories[index], buttonAddSpell);

	end

	-- // selectSpell
	do

		local function OnSpellSelected(buttonInfo)
			local spellInfo = buttonInfo.info;
			for _, control in pairs(controls) do
				control:Show();
			end
			selectedSpell = buttonInfo.indexInDB;
			selectSpell.Text:SetText(buttonInfo.text);
			selectSpell:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT");
				GameTooltip:SetSpellByID(GetIDAndTextureForSpell(spellInfo));
				GameTooltip:Show();
			end);
			selectSpell:SetScript("OnLeave", function() GameTooltip:Hide(); end);
			selectSpell.icon:SetTexture(select(2, GetIDAndTextureForSpell(spellInfo)));
			selectSpell.icon:Show();
			sliderSpellIconSizeWidth.slider:SetValue(spellInfo.iconSizeWidth);
			sliderSpellIconSizeWidth.editbox:SetText(tostring(spellInfo.iconSizeWidth));
			sliderSpellIconSizeHeight.slider:SetValue(spellInfo.iconSizeHeight);
			sliderSpellIconSizeHeight.editbox:SetText(tostring(spellInfo.iconSizeHeight));
			_G[dropdownSpellShowType:GetName().."Text"]:SetText(AuraTypesLocalization[spellInfo.auraType]);
			if (spellInfo.checkSpellID) then
				local t = { };
				for key in pairs(spellInfo.checkSpellID) do
					table_insert(t, key);
				end
				editboxSpellID:SetText(table.concat(t, ","));
			else
				editboxSpellID:SetText("");
			end
			checkboxShowOnFriends:SetChecked(spellInfo.showOnFriends);
			checkboxShowOnEnemies:SetChecked(spellInfo.showOnEnemies);
			if (spellInfo.enabledState == CONST_SPELL_MODE_DISABLED) then
				checkboxEnabled:SetTriState(0);
			elseif (spellInfo.enabledState == CONST_SPELL_MODE_ALL) then
				checkboxEnabled:SetTriState(2);
			else
				checkboxEnabled:SetTriState(1);
			end
			if (spellInfo.playerNpcMode == addonTable.SHOW_ON_PLAYERS_AND_NPC) then
				checkboxPvPMode:SetTriState(0);
			elseif (spellInfo.playerNpcMode == addonTable.SHOW_ON_PLAYERS) then
				checkboxPvPMode:SetTriState(1);
			else
				checkboxPvPMode:SetTriState(2);
			end
			if (spellInfo.showGlow == nil) then
				checkboxGlow:SetTriState(0);
				sliderGlowThreshold:Hide();
				checkboxGlowRelative:Hide();
				dropdownGlowType:Hide();
				areaGlow:SetHeight(40);
			elseif (spellInfo.showGlow == GLOW_TIME_INFINITE) then
				checkboxGlow:SetTriState(2);
				sliderGlowThreshold:Hide();
				checkboxGlowRelative:Hide();
				areaGlow:SetHeight(80);
			else
				checkboxGlow:SetTriState(1);
				sliderGlowThreshold.slider:SetValue(spellInfo.showGlow);
				checkboxGlowRelative:SetChecked(spellInfo.useRelativeGlowTimer);
				areaGlow:SetHeight(80);
			end
			_G[dropdownGlowType:GetName().."Text"]:SetText(glowTypes[spellInfo.glowType]);
			if (spellInfo.animationDisplayMode == addonTable.ICON_ANIMATION_DISPLAY_MODE_NONE) then
				checkboxAnimation:SetTriState(0);
				sliderAnimationThreshold:Hide();
				checkboxAnimationRelative:Hide();
				dropdownAnimationType:Hide();
				areaAnimation:SetHeight(40);
			elseif (spellInfo.animationDisplayMode == addonTable.ICON_ANIMATION_DISPLAY_MODE_ALWAYS) then
				checkboxAnimation:SetTriState(2);
				sliderAnimationThreshold:Hide();
				checkboxAnimationRelative:Hide();
				areaAnimation:SetHeight(80);
			elseif (spellInfo.animationDisplayMode == addonTable.ICON_ANIMATION_DISPLAY_MODE_THRESHOLD) then
				checkboxAnimation:SetTriState(1);
				sliderAnimationThreshold.slider:SetValue(spellInfo.animationTimer);
				checkboxAnimationRelative:SetChecked(spellInfo.useRelativeAnimationTimer);
				areaAnimation:SetHeight(80);
			end
			if (spellInfo.customBorderType == nil or spellInfo.customBorderType == addonTable.BORDER_TYPE_DISABLED) then
				checkboxCustomBorder:SetTriState(0);
				textboxCustomBorderPath:Hide();
				sliderCustomBorderSize:Hide();
				colorPickerCustomBorderColor:Hide();
				areaCustomBorder:SetHeight(40);
			elseif (spellInfo.customBorderType == addonTable.BORDER_TYPE_BUILTIN) then
				checkboxCustomBorder:SetTriState(1);
				textboxCustomBorderPath:Hide();
				sliderCustomBorderSize:Show();
				sliderCustomBorderSize.slider:SetValue(addonTable.db.CustomSpells2[selectedSpell].customBorderSize);
				colorPickerCustomBorderColor:Show();
				local color = addonTable.db.CustomSpells2[selectedSpell].customBorderColor or {1,0,0,1};
				colorPickerCustomBorderColor:SetColor(color[1], color[2], color[3], color[4]);
				areaCustomBorder:SetHeight(80);
			elseif (spellInfo.customBorderType == addonTable.BORDER_TYPE_CUSTOM) then
				checkboxCustomBorder:SetTriState(2);
				textboxCustomBorderPath:Show();
				textboxCustomBorderPath:SetText(addonTable.db.CustomSpells2[selectedSpell].customBorderPath or "");
				sliderCustomBorderSize:Hide();
				colorPickerCustomBorderColor:Show();
				local color = addonTable.db.CustomSpells2[selectedSpell].customBorderColor or {1,0,0,1};
				colorPickerCustomBorderColor:SetColor(color[1], color[2], color[3], color[4]);
				areaCustomBorder:SetHeight(80);
			end
			_G[dropdownAnimationType:GetName().."Text"]:SetText(animationTypes[spellInfo.animationType]);
		end

		local function HideGameTooltip()
			GameTooltip:Hide();
		end

		local function ResetSelectSpell()
			for _, control in pairs(controls) do
				control:Hide();
			end
			selectSpell.Text:SetText(L["Click to select spell"]);
			selectSpell:SetScript("OnEnter", nil);
			selectSpell:SetScript("OnLeave", nil);
			selectSpell.icon:Hide();
		end

		dropdownMenuSpells:SetCustomSearchHandler(function(_text)
			local list = dropdownMenuSpells:GetList();
			local t = {};

			local igPattern = "^group:(%d+)$";
			local igMatchRaw = string.match(_text, igPattern);
			if (igMatchRaw ~= nil) then
				local igMatch = tonumber(igMatchRaw);
				for _, value in pairs(list) do
					if (value.info.iconGroups ~= nil and value.info.iconGroups[igMatch] == true) then
						table_insert(t, value);
					end
				end
			else
				for _, value in pairs(list) do
					if (string.find(value.text:lower(), _text:lower())) then
						table_insert(t, value);
					end
				end
			end
			return t;
		end);
		dropdownMenuSpells:SetSearchBoxHint("You can use filters:\n\ngroup:{group index} -- ex: `group:1`");

		selectSpell = VGUI.CreateButton();
		selectSpell:SetParent(GUIFrame);
		selectSpell:SetText(L["Click to select spell"]);
		selectSpell:SetWidth(285);
		selectSpell:SetHeight(24);
		selectSpell.icon = selectSpell:CreateTexture(nil, "OVERLAY");
		selectSpell.icon:SetPoint("RIGHT", selectSpell.Text, "LEFT", -3, 0);
		selectSpell.icon:SetWidth(20);
		selectSpell.icon:SetHeight(20);
		selectSpell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
		selectSpell.icon:Hide();
		selectSpell:SetPoint("BOTTOMLEFT", spellArea, "TOPLEFT", 15, 5);
		selectSpell:SetPoint("BOTTOMRIGHT", spellArea, "TOPRIGHT", -15, 5);
		selectSpell:SetScript("OnClick", function(button)
			local t = { };
			for spellIndex, spellInfo in pairs(addonTable.db.CustomSpells2) do
				table_insert(t, {
					icon = select(2, GetIDAndTextureForSpell(spellInfo)),
					text = GetButtonNameForSpell(spellInfo),
					info = spellInfo,
					indexInDB = spellIndex,
					onEnter = function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
						GameTooltip:SetSpellByID(GetIDAndTextureForSpell(spellInfo));
						local allSpellIDs = AllSpellIDsAndIconsByName[spellInfo.spellName];
						if (allSpellIDs ~= nil and table_count(allSpellIDs) > 0) then
							local descText = "\n" .. L["options:spells:appropriate-spell-ids"];
							for id, icon in pairs(allSpellIDs) do
								descText = string_format("%s\n|T%d:0|t: %d", descText, icon, id);
							end
							GameTooltip:AddLine(descText);
						end
						GameTooltip:Show();
					end,
					onLeave = HideGameTooltip,
					func = OnSpellSelected,
					checkBoxEnabled = true,
					checkBoxState = spellInfo.enabledState ~= CONST_SPELL_MODE_DISABLED,
					onCheckBoxClick = function(checkbox)
						if (checkbox:GetChecked()) then
							spellInfo.enabledState = CONST_SPELL_MODE_ALL;
						else
							spellInfo.enabledState = CONST_SPELL_MODE_DISABLED;
						end
						addonTable.UpdateAllNameplates(false);
					end,
					onCloseButtonClick = function(buttonInfo) OnSpellSelected(buttonInfo); buttonDeleteSpell:Click(); selectSpell:Click(); end,
				});
			end
			table_sort(t, function(item1, item2) return item1.text < item2.text end);
			dropdownMenuSpells:SetList(t);
			dropdownMenuSpells:SetWidth(400);
			dropdownMenuSpells:SetParent(button);
			dropdownMenuSpells:ClearAllPoints();
			dropdownMenuSpells:SetPoint("TOP", button, "BOTTOM", 0, 0);
			dropdownMenuSpells:Show();
			dropdownMenuSpells.searchBox:SetFocus();
			dropdownMenuSpells.searchBox:SetText("");
			ResetSelectSpell();
			HideGameTooltip();
		end);
		selectSpell:SetScript("OnHide", function()
			ResetSelectSpell();
			dropdownMenuSpells:Hide();
		end);
		selectSpell:Disable();
		hooksecurefunc(addonTable, "OnSpellInfoCachesReady", function() selectSpell:Enable(); end);
		GUIFrame:HookScript("OnHide", function() selectSpell:Disable(); end);
		table_insert(GUIFrame.Categories[index], selectSpell);

	end

	-- // checkboxEnabled
	do
		checkboxEnabled = VGUI.CreateCheckBoxTristate();
		checkboxEnabled:SetTextEntries({
			addonTable.ColorizeText(L["Disabled"], 1, 1, 1),
			addonTable.ColorizeText(L["options:auras:enabled-state-mineonly"], 0, 1, 1),
			addonTable.ColorizeText(L["options:auras:enabled-state-all"], 0, 1, 0),
		});
		checkboxEnabled:SetOnClickHandler(function(self)
			if (self:GetTriState() == 0) then
				addonTable.db.CustomSpells2[selectedSpell].enabledState = CONST_SPELL_MODE_DISABLED;
			elseif (self:GetTriState() == 1) then
				addonTable.db.CustomSpells2[selectedSpell].enabledState = CONST_SPELL_MODE_MYAURAS;
			else
				addonTable.db.CustomSpells2[selectedSpell].enabledState = CONST_SPELL_MODE_ALL;
			end
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxEnabled:SetParent(spellArea.controlsFrame);
		checkboxEnabled:SetPoint("TOPLEFT", 15, -15);
		VGUI.SetTooltip(checkboxEnabled, format(L["options:auras:enabled-state:tooltip"],
			addonTable.ColorizeText(L["Disabled"], 1, 1, 1),
			addonTable.ColorizeText(L["options:auras:enabled-state-mineonly"], 0, 1, 1),
			addonTable.ColorizeText(L["options:auras:enabled-state-all"], 0, 1, 0)), "LEFT");
		table_insert(controls, checkboxEnabled);

	end

	-- // checkboxShowOnFriends
	do
		checkboxShowOnFriends = VGUI.CreateCheckBox();
		checkboxShowOnFriends:SetText(L["Show this aura on nameplates of allies"]);
		checkboxShowOnFriends:SetOnClickHandler(function(this)
			addonTable.db.CustomSpells2[selectedSpell].showOnFriends = this:GetChecked();
			if (this:GetChecked() and not addonTable.db.IconGroups[CurrentIconGroup].ShowAboveFriendlyUnits) then
				msg(L["options:spells:show-on-friends:warning0"]);
			end
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxShowOnFriends:SetParent(spellArea.controlsFrame);
		checkboxShowOnFriends:SetPoint("TOPLEFT", 15, -35);
		table_insert(controls, checkboxShowOnFriends);
	end

	-- // checkboxShowOnEnemies
	do
		checkboxShowOnEnemies = VGUI.CreateCheckBox();
		checkboxShowOnEnemies:SetText(L["Show this aura on nameplates of enemies"]);
		checkboxShowOnEnemies:SetOnClickHandler(function(this)
			addonTable.db.CustomSpells2[selectedSpell].showOnEnemies = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxShowOnEnemies:SetParent(spellArea.controlsFrame);
		checkboxShowOnEnemies:SetPoint("TOPLEFT", 15, -55);
		table_insert(controls, checkboxShowOnEnemies);
	end

	-- // checkboxPvPMode
	do
		checkboxPvPMode = VGUI.CreateCheckBoxTristate();
		checkboxPvPMode:SetTextEntries({
			L["options:auras:show-on-npcs-and-players"],
			addonTable.ColorizeText(L["options:auras:show-on-players"], 1, 0, 0),
			addonTable.ColorizeText(L["options:auras:show-on-npcs"], 0, 1, 0),
		});
		checkboxPvPMode:SetOnClickHandler(function(self)
			if (self:GetTriState() == 0) then
				addonTable.db.CustomSpells2[selectedSpell].playerNpcMode = addonTable.SHOW_ON_PLAYERS_AND_NPC;
			elseif (self:GetTriState() == 1) then
				addonTable.db.CustomSpells2[selectedSpell].playerNpcMode = addonTable.SHOW_ON_PLAYERS;
			else
				addonTable.db.CustomSpells2[selectedSpell].playerNpcMode = addonTable.SHOW_ON_NPC;
			end
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxPvPMode:SetParent(spellArea.controlsFrame);
		checkboxPvPMode:SetPoint("TOPLEFT", 15, -75);
		table_insert(controls, checkboxPvPMode);

	end

	-- // areaGlow
	do

		areaGlow = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaGlow:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaGlow:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaGlow:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaGlow:SetPoint("TOPLEFT", spellArea.controlsFrame, "TOPLEFT", 10, -95);
		areaGlow:SetWidth(500);
		areaGlow:SetHeight(80);
		table_insert(controls, areaGlow);

	end

	-- // checkboxGlow
	do
		checkboxGlow = VGUI.CreateCheckBoxTristate();
		checkboxGlow:SetTextEntries({
			addonTable.ColorizeText(L["options:spells:icon-glow"], 1, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-glow-threshold"], 0, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-glow-always"], 0, 1, 0),
		});
		checkboxGlow:SetOnClickHandler(function(self)
			if (self:GetTriState() == 0) then
				addonTable.db.CustomSpells2[selectedSpell].showGlow = nil; -- // making addonTable.db smaller
				sliderGlowThreshold:Hide();
				checkboxGlowRelative:Hide();
				dropdownGlowType:Hide();
				areaGlow:SetHeight(40);
			elseif (self:GetTriState() == 1) then
				addonTable.db.CustomSpells2[selectedSpell].showGlow = 5;
				sliderGlowThreshold:Show();
				checkboxGlowRelative:Show();
				dropdownGlowType:Show();
				sliderGlowThreshold.slider:SetValue(5);
				areaGlow:SetHeight(80);
			else
				addonTable.db.CustomSpells2[selectedSpell].showGlow = GLOW_TIME_INFINITE;
				sliderGlowThreshold:Hide();
				checkboxGlowRelative:Hide();
				dropdownGlowType:Show();
				areaGlow:SetHeight(80);
			end
			addonTable.UpdateAllNameplates(false);
		end);
		checkboxGlow:SetParent(areaGlow);
		checkboxGlow:SetPoint("TOPLEFT", 10, -10);
		table_insert(controls, checkboxGlow);
	end

	-- // dropdownGlowType
	do
		dropdownGlowType = CreateFrame("Frame", "NAurasGUI.Spell.dropdownGlowType", areaGlow, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownGlowType, 145);
		dropdownGlowType:SetPoint("TOPLEFT", areaGlow, "TOPLEFT", -5, -40);
		local info = {};
		dropdownGlowType.initialize = function()
			wipe(info);
			for glowType, glowTypeLocalized in pairs(glowTypes) do
				info.text = glowTypeLocalized;
				info.value = glowType;
				info.func = function(self)
					addonTable.db.CustomSpells2[selectedSpell].glowType = self.value;
					_G[dropdownGlowType:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = glowType == addonTable.db.CustomSpells2[selectedSpell].glowType;
				UIDropDownMenu_AddButton(info);
			end
		end
		dropdownGlowType.text = dropdownGlowType:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownGlowType.text:SetPoint("LEFT", 20, 20);
		dropdownGlowType.text:SetText(L["options:glow-type"]);
		table_insert(controls, dropdownGlowType);

	end

	-- // sliderGlowThreshold
	do

		local minV, maxV = 1, 100;
		sliderGlowThreshold = VGUI.CreateSlider();
		sliderGlowThreshold:SetParent(areaGlow);
		sliderGlowThreshold:SetWidth(140);
		sliderGlowThreshold.label:ClearAllPoints();
		sliderGlowThreshold.label:SetPoint("CENTER", sliderGlowThreshold, "CENTER", 0, 15);
		sliderGlowThreshold.label:SetText();
		sliderGlowThreshold:ClearAllPoints();
		sliderGlowThreshold:SetPoint("LEFT", dropdownGlowType, "RIGHT", 0, 10);
		sliderGlowThreshold.slider:ClearAllPoints();
		sliderGlowThreshold.slider:SetPoint("LEFT", 3, 0)
		sliderGlowThreshold.slider:SetPoint("RIGHT", -3, 0)
		sliderGlowThreshold.slider:SetValueStep(1);
		sliderGlowThreshold.slider:SetMinMaxValues(minV, maxV);
		sliderGlowThreshold.slider:SetScript("OnValueChanged", function(_, value)
			sliderGlowThreshold.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.CustomSpells2[selectedSpell].showGlow = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderGlowThreshold.editbox:SetScript("OnEnterPressed", function()
			if (sliderGlowThreshold.editbox:GetText() ~= "") then
				local v = tonumber(sliderGlowThreshold.editbox:GetText());
				if (v == nil) then
					sliderGlowThreshold.editbox:SetText(tostring(addonTable.db.CustomSpells2[selectedSpell].showGlow));
					Print(L["Value must be a number"]);
				else
					if (v > maxV) then
						v = maxV;
					end
					if (v < minV) then
						v = minV;
					end
					sliderGlowThreshold.slider:SetValue(v);
				end
				sliderGlowThreshold.editbox:ClearFocus();
			end
		end);
		sliderGlowThreshold.lowtext:SetText(tostring(minV));
		sliderGlowThreshold.hightext:SetText(tostring(maxV));
		table_insert(controls, sliderGlowThreshold);

	end

	-- // checkboxGlowRelative
	do
		checkboxGlowRelative = VGUI.CreateCheckBox();
		checkboxGlowRelative:SetText(L["options:spells:glow-relative"]);
		checkboxGlowRelative:SetOnClickHandler(function(this)
			addonTable.db.CustomSpells2[selectedSpell].useRelativeGlowTimer = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
		end);
		VGUI.SetTooltip(checkboxGlowRelative, L["options:spells:glow-relative:tooltip"]);
		checkboxGlowRelative:SetParent(areaGlow);
		checkboxGlowRelative:SetPoint("LEFT", sliderGlowThreshold, "RIGHT", 10, 0);
		table_insert(controls, checkboxGlowRelative);
	end

	-- // areaAnimation
	do
		areaAnimation = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaAnimation:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaAnimation:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaAnimation:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaAnimation:SetPoint("TOPLEFT", areaGlow, "BOTTOMLEFT", 0, 0);
		areaAnimation:SetPoint("TOPRIGHT", areaGlow, "BOTTOMRIGHT", 0, 0);
		areaAnimation:SetHeight(80);
		table_insert(controls, areaAnimation);
	end

	-- // checkboxAnimation
	do
		checkboxAnimation = VGUI.CreateCheckBoxTristate();
		checkboxAnimation:SetTextEntries({
			addonTable.ColorizeText(L["options:spells:icon-animation"], 1, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-animation-threshold"], 0, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-animation-always"], 0, 1, 0),
		});
		checkboxAnimation:SetOnClickHandler(function(self)
			if (self:GetTriState() == 0) then
				addonTable.db.CustomSpells2[selectedSpell].animationDisplayMode = addonTable.ICON_ANIMATION_DISPLAY_MODE_NONE;
				sliderAnimationThreshold:Hide();
				checkboxAnimationRelative:Hide();
				dropdownAnimationType:Hide();
				areaAnimation:SetHeight(40);
			elseif (self:GetTriState() == 1) then
				addonTable.db.CustomSpells2[selectedSpell].animationDisplayMode = addonTable.ICON_ANIMATION_DISPLAY_MODE_THRESHOLD;
				sliderAnimationThreshold:Show();
				checkboxAnimationRelative:Show();
				dropdownAnimationType:Show();
				sliderAnimationThreshold.slider:SetValue(5);
				areaAnimation:SetHeight(80);
			else
				addonTable.db.CustomSpells2[selectedSpell].animationDisplayMode = addonTable.ICON_ANIMATION_DISPLAY_MODE_ALWAYS;
				sliderAnimationThreshold:Hide();
				checkboxAnimationRelative:Hide();
				dropdownAnimationType:Show();
				areaAnimation:SetHeight(80);
			end
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxAnimation:SetParent(areaAnimation);
		checkboxAnimation:SetPoint("TOPLEFT", 10, -10);
		table_insert(controls, checkboxAnimation);
	end

	-- // dropdownAnimationType
	do
		dropdownAnimationType = CreateFrame("Frame", "NAurasGUI.Spell.dropdownAnimationType", areaAnimation, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownAnimationType, 145);
		dropdownAnimationType:SetPoint("TOPLEFT", areaAnimation, "TOPLEFT", -5, -40);
		local info = {};
		dropdownAnimationType.initialize = function()
			wipe(info);
			for animationType, animationTypeLocalized in pairs(animationTypes) do
				info.text = animationTypeLocalized;
				info.value = animationType;
				info.func = function(self)
					addonTable.db.CustomSpells2[selectedSpell].animationType = self.value;
					_G[dropdownAnimationType:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = animationType == addonTable.db.CustomSpells2[selectedSpell].animationType;
				UIDropDownMenu_AddButton(info);
			end
		end
		dropdownAnimationType.text = dropdownAnimationType:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownAnimationType.text:SetPoint("LEFT", 20, 20);
		dropdownAnimationType.text:SetText(L["options:spells:animation-type"]);
		table_insert(controls, dropdownAnimationType);

	end

	-- // sliderAnimationThreshold
	do

		local minV, maxV = 1, 100;
		sliderAnimationThreshold = VGUI.CreateSlider();
		sliderAnimationThreshold:SetParent(areaAnimation);
		sliderAnimationThreshold:SetWidth(140);
		sliderAnimationThreshold.label:ClearAllPoints();
		sliderAnimationThreshold.label:SetPoint("CENTER", sliderAnimationThreshold, "CENTER", 0, 15);
		sliderAnimationThreshold.label:SetText();
		sliderAnimationThreshold:ClearAllPoints();
		sliderAnimationThreshold:SetPoint("LEFT", dropdownAnimationType, "RIGHT", 0, 10);
		sliderAnimationThreshold.slider:ClearAllPoints();
		sliderAnimationThreshold.slider:SetPoint("LEFT", 3, 0)
		sliderAnimationThreshold.slider:SetPoint("RIGHT", -3, 0)
		sliderAnimationThreshold.slider:SetValueStep(1);
		sliderAnimationThreshold.slider:SetMinMaxValues(minV, maxV);
		sliderAnimationThreshold.slider:SetScript("OnValueChanged", function(_, value)
			sliderAnimationThreshold.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.CustomSpells2[selectedSpell].animationTimer = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderAnimationThreshold.editbox:SetScript("OnEnterPressed", function()
			if (sliderAnimationThreshold.editbox:GetText() ~= "") then
				local v = tonumber(sliderAnimationThreshold.editbox:GetText());
				if (v == nil) then
					sliderAnimationThreshold.editbox:SetText(tostring(addonTable.db.CustomSpells2[selectedSpell].animationTimer));
					Print(L["Value must be a number"]);
				else
					if (v > maxV) then
						v = maxV;
					end
					if (v < minV) then
						v = minV;
					end
					sliderAnimationThreshold.slider:SetValue(v);
				end
				sliderAnimationThreshold.editbox:ClearFocus();
			end
		end);
		sliderAnimationThreshold.lowtext:SetText(tostring(minV));
		sliderAnimationThreshold.hightext:SetText(tostring(maxV));
		table_insert(controls, sliderAnimationThreshold);

	end

	-- // checkboxAnimationRelative
	do
		checkboxAnimationRelative = VGUI.CreateCheckBox();
		checkboxAnimationRelative:SetText(L["options:spells:glow-relative"]);
		checkboxAnimationRelative:SetOnClickHandler(function(this)
			addonTable.db.CustomSpells2[selectedSpell].useRelativeAnimationTimer = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
		end);
		VGUI.SetTooltip(checkboxAnimationRelative, L["options:spells:animation-relative:tooltip"]);
		checkboxAnimationRelative:SetParent(areaAnimation);
		checkboxAnimationRelative:SetPoint("LEFT", sliderAnimationThreshold, "RIGHT", 10, 0);
		table_insert(controls, checkboxAnimationRelative);
	end

	-- areaCustomBorder
	do
		areaCustomBorder = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaCustomBorder:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaCustomBorder:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaCustomBorder:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaCustomBorder:SetPoint("TOPLEFT", areaAnimation, "BOTTOMLEFT", 0, 0);
		areaCustomBorder:SetPoint("TOPRIGHT", areaAnimation, "BOTTOMRIGHT", 0, 0);
		areaCustomBorder:SetHeight(80);
		table_insert(controls, areaCustomBorder);
	end

	-- // checkboxCustomBorder
	do
		checkboxCustomBorder = VGUI.CreateCheckBoxTristate();
		checkboxCustomBorder:SetTextEntries({
			addonTable.ColorizeText(L["options:spells:icon-border:disabled"], 1, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-border:builtin"], 0, 1, 1),
			addonTable.ColorizeText(L["options:spells:icon-border:custom"], 0, 1, 0),
		});
		checkboxCustomBorder:SetOnClickHandler(function(self)
			local color = addonTable.db.CustomSpells2[selectedSpell].customBorderColor or {1,0,0,1};
			if (self:GetTriState() == 0) then
				addonTable.db.CustomSpells2[selectedSpell].customBorderType = addonTable.BORDER_TYPE_DISABLED;
				textboxCustomBorderPath:Hide();
				sliderCustomBorderSize:Hide();
				colorPickerCustomBorderColor:Hide();
				areaCustomBorder:SetHeight(40);
			elseif (self:GetTriState() == 1) then
				addonTable.db.CustomSpells2[selectedSpell].customBorderType = addonTable.BORDER_TYPE_BUILTIN;
				textboxCustomBorderPath:Hide();
				sliderCustomBorderSize:Show();
				sliderCustomBorderSize.slider:SetValue(addonTable.db.CustomSpells2[selectedSpell].customBorderSize or 1);
				colorPickerCustomBorderColor:Show();
				colorPickerCustomBorderColor:SetColor(color[1], color[2], color[3], color[4]);
				areaCustomBorder:SetHeight(80);
			else
				addonTable.db.CustomSpells2[selectedSpell].customBorderType = addonTable.BORDER_TYPE_CUSTOM;
				textboxCustomBorderPath:Show();
				textboxCustomBorderPath:SetText(addonTable.db.CustomSpells2[selectedSpell].customBorderPath or "");
				sliderCustomBorderSize:Hide();
				colorPickerCustomBorderColor:Show();
				colorPickerCustomBorderColor:SetColor(color[1], color[2], color[3], color[4]);
				areaCustomBorder:SetHeight(80);
			end
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxCustomBorder:SetParent(areaCustomBorder);
		checkboxCustomBorder:SetPoint("TOPLEFT", 10, -10);
		table_insert(controls, checkboxCustomBorder);
	end

	-- // colorPickerCustomBorderColor
	do
		colorPickerCustomBorderColor = VGUI.CreateColorPicker();
		colorPickerCustomBorderColor:SetParent(areaCustomBorder);
		colorPickerCustomBorderColor:SetPoint("TOPLEFT", 15, -45);
		colorPickerCustomBorderColor:SetText();
		colorPickerCustomBorderColor.func = function(_, r, g, b, a)
			addonTable.db.CustomSpells2[selectedSpell].customBorderColor = {r, g, b, a};
			addonTable.UpdateAllNameplates(true);
		end
		table_insert(controls, colorPickerCustomBorderColor);
	end

	-- // sliderCustomBorderSize
	do

		local minV, maxV = 1, 5;
		sliderCustomBorderSize = VGUI.CreateSlider();
		sliderCustomBorderSize:SetParent(areaCustomBorder);
		sliderCustomBorderSize:SetWidth(140);
		sliderCustomBorderSize.label:ClearAllPoints();
		sliderCustomBorderSize.label:SetPoint("CENTER", sliderCustomBorderSize, "CENTER", 0, 15);
		sliderCustomBorderSize.label:SetText();
		sliderCustomBorderSize:ClearAllPoints();
		sliderCustomBorderSize:SetPoint("LEFT", colorPickerCustomBorderColor, "RIGHT", 10, 10);
		sliderCustomBorderSize.slider:ClearAllPoints();
		sliderCustomBorderSize.slider:SetPoint("LEFT", 3, 0)
		sliderCustomBorderSize.slider:SetPoint("RIGHT", -3, 0)
		sliderCustomBorderSize.slider:SetValueStep(1);
		sliderCustomBorderSize.slider:SetMinMaxValues(minV, maxV);
		sliderCustomBorderSize.slider:SetScript("OnValueChanged", function(_, value)
			sliderCustomBorderSize.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.CustomSpells2[selectedSpell].customBorderSize = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderCustomBorderSize.editbox:SetScript("OnEnterPressed", function()
			if (sliderCustomBorderSize.editbox:GetText() ~= "") then
				local v = tonumber(sliderCustomBorderSize.editbox:GetText());
				if (v == nil) then
					sliderCustomBorderSize.editbox:SetText(tostring(addonTable.db.CustomSpells2[selectedSpell].customBorderSize));
					Print(L["Value must be a number"]);
				else
					if (v > maxV) then
						v = maxV;
					end
					if (v < minV) then
						v = minV;
					end
					sliderCustomBorderSize.slider:SetValue(v);
				end
				sliderCustomBorderSize.editbox:ClearFocus();
			end
		end);
		sliderCustomBorderSize.lowtext:SetText(tostring(minV));
		sliderCustomBorderSize.hightext:SetText(tostring(maxV));
		table_insert(controls, sliderCustomBorderSize);

	end

	-- // textboxCustomBorderPath
	do
		textboxCustomBorderPath = CreateFrame("EditBox", nil, areaCustomBorder, "InputBoxTemplate");
		textboxCustomBorderPath:SetAutoFocus(false);
		textboxCustomBorderPath:SetFontObject(GameFontHighlightSmall);
		textboxCustomBorderPath:SetPoint("LEFT", colorPickerCustomBorderColor, "RIGHT", 10, 0);
		textboxCustomBorderPath:SetPoint("RIGHT", areaCustomBorder, "RIGHT", -10, 0);
		textboxCustomBorderPath:SetHeight(20);
		textboxCustomBorderPath:SetJustifyH("LEFT");
		textboxCustomBorderPath:EnableMouse(true);
		textboxCustomBorderPath:SetScript("OnEscapePressed", function() textboxCustomBorderPath:ClearFocus(); end);
		textboxCustomBorderPath:SetScript("OnEnterPressed", function() textboxCustomBorderPath:ClearFocus(); end);
		textboxCustomBorderPath:SetScript("OnTextChanged", function(self)
			local inputText = self:GetText();
			addonTable.db.CustomSpells2[selectedSpell].customBorderPath = inputText;
			addonTable.UpdateAllNameplates(true);
		end);
		local text = textboxCustomBorderPath:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		text:SetPoint("LEFT", 0, 15);
		text:SetText(L["options:borders:border-file-path"]);
		table_insert(controls, textboxCustomBorderPath);
	end

	-- // areaAuraType
	do

		areaAuraType = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaAuraType:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaAuraType:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaAuraType:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaAuraType:SetPoint("TOPLEFT", areaCustomBorder, "BOTTOMLEFT", 0, 0);
		areaAuraType:SetWidth(167);
		areaAuraType:SetHeight(70);
		table_insert(controls, areaAuraType);

	end

	-- // dropdownSpellShowType
	do

		dropdownSpellShowType = CreateFrame("Frame", "NAuras.GUI.Cat4.DropdownSpellShowType", areaAuraType, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownSpellShowType, 130);

		dropdownSpellShowType.text = dropdownSpellShowType:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		dropdownSpellShowType.text:SetPoint("CENTER", areaAuraType, "CENTER", 0, 15);
		dropdownSpellShowType.text:SetText(L["Aura type"]);
		dropdownSpellShowType:SetPoint("CENTER", 0, -11);
		local info = {};
		dropdownSpellShowType.initialize = function()
			wipe(info);
			for _, auraType in pairs({ AURA_TYPE_BUFF, AURA_TYPE_DEBUFF, AURA_TYPE_ANY }) do
				info.text = AuraTypesLocalization[auraType];
				info.value = auraType;
				info.func = function(self)
					addonTable.db.CustomSpells2[selectedSpell].auraType = self.value;
					_G[dropdownSpellShowType:GetName().."Text"]:SetText(self:GetText());
				end
				info.checked = (info.value == addonTable.db.CustomSpells2[selectedSpell].auraType);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownSpellShowType:GetName().."Text"]:SetText("");
		table_insert(controls, dropdownSpellShowType);

	end

	-- // areaIconSize
	do

		areaIconSize = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaIconSize:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaIconSize:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaIconSize:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaIconSize:SetPoint("TOPLEFT", areaAuraType, "TOPRIGHT", 0, 0);
		areaIconSize:SetWidth(333);
		areaIconSize:SetHeight(70);
		table_insert(controls, areaIconSize);

	end

	-- // sliderSpellIconSizeWidth
	do

		sliderSpellIconSizeWidth = VGUI.CreateSlider();
		sliderSpellIconSizeWidth:SetParent(areaIconSize);
		sliderSpellIconSizeWidth:SetWidth(160);
		sliderSpellIconSizeWidth:SetPoint("TOPLEFT", 18, -23);
		sliderSpellIconSizeWidth.label:ClearAllPoints();
		sliderSpellIconSizeWidth.label:SetPoint("CENTER", sliderSpellIconSizeWidth, "CENTER", 0, 15);
		sliderSpellIconSizeWidth.label:SetText(L["options:spells:icon-width"]);
		sliderSpellIconSizeWidth:ClearAllPoints();
		sliderSpellIconSizeWidth:SetPoint("LEFT", areaIconSize, "LEFT", 5, 0);
		sliderSpellIconSizeWidth.slider:ClearAllPoints();
		sliderSpellIconSizeWidth.slider:SetPoint("LEFT", 3, 0)
		sliderSpellIconSizeWidth.slider:SetPoint("RIGHT", -3, 0)
		sliderSpellIconSizeWidth.slider:SetValueStep(1);
		sliderSpellIconSizeWidth.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderSpellIconSizeWidth.slider:SetScript("OnValueChanged", function(_, value)
			sliderSpellIconSizeWidth.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.CustomSpells2[selectedSpell].iconSizeWidth = math_ceil(value);
			addonTable.UpdateAllNameplates(true);
		end);
		sliderSpellIconSizeWidth.editbox:SetScript("OnEnterPressed", function()
			if (sliderSpellIconSizeWidth.editbox:GetText() ~= "") then
				local v = tonumber(sliderSpellIconSizeWidth.editbox:GetText());
				if (v == nil) then
					sliderSpellIconSizeWidth.editbox:SetText(tostring(addonTable.db.CustomSpells2[selectedSpell].iconSizeWidth));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderSpellIconSizeWidth.slider:SetValue(v);
				end
				sliderSpellIconSizeWidth.editbox:ClearFocus();
			end
		end);
		sliderSpellIconSizeWidth.lowtext:SetText("1");
		sliderSpellIconSizeWidth.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		table_insert(controls, sliderSpellIconSizeWidth);

	end

	-- // sliderSpellIconSizeHeight
	do

		sliderSpellIconSizeHeight = VGUI.CreateSlider();
		sliderSpellIconSizeHeight:SetParent(areaIconSize);
		sliderSpellIconSizeHeight:SetWidth(160);
		sliderSpellIconSizeHeight:SetPoint("TOPLEFT", 18, -23);
		sliderSpellIconSizeHeight.label:ClearAllPoints();
		sliderSpellIconSizeHeight.label:SetPoint("CENTER", sliderSpellIconSizeHeight, "CENTER", 0, 15);
		sliderSpellIconSizeHeight.label:SetText(L["options:spells:icon-height"]);
		sliderSpellIconSizeHeight:ClearAllPoints();
		sliderSpellIconSizeHeight:SetPoint("LEFT", sliderSpellIconSizeWidth, "RIGHT", 0, 0);
		sliderSpellIconSizeHeight.slider:ClearAllPoints();
		sliderSpellIconSizeHeight.slider:SetPoint("LEFT", 3, 0)
		sliderSpellIconSizeHeight.slider:SetPoint("RIGHT", -3, 0)
		sliderSpellIconSizeHeight.slider:SetValueStep(1);
		sliderSpellIconSizeHeight.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderSpellIconSizeHeight.slider:SetScript("OnValueChanged", function(_, value)
			sliderSpellIconSizeHeight.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.CustomSpells2[selectedSpell].iconSizeHeight = math_ceil(value);
			addonTable.UpdateAllNameplates(true);
		end);
		sliderSpellIconSizeHeight.editbox:SetScript("OnEnterPressed", function()
			if (sliderSpellIconSizeHeight.editbox:GetText() ~= "") then
				local v = tonumber(sliderSpellIconSizeHeight.editbox:GetText());
				if (v == nil) then
					sliderSpellIconSizeHeight.editbox:SetText(tostring(addonTable.db.CustomSpells2[selectedSpell].iconSizeHeight));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderSpellIconSizeHeight.slider:SetValue(v);
				end
				sliderSpellIconSizeHeight.editbox:ClearFocus();
			end
		end);
		sliderSpellIconSizeHeight.lowtext:SetText("1");
		sliderSpellIconSizeHeight.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		table_insert(controls, sliderSpellIconSizeHeight);

	end

	-- // areaIDs
	do

		areaIDs = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaIDs:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaIDs:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaIDs:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaIDs:SetPoint("TOPLEFT", areaAuraType, "BOTTOMLEFT", 0, 0);
		areaIDs:SetWidth(500);
		areaIDs:SetHeight(40);
		table_insert(controls, areaIDs);

	end

	-- // editboxSpellID
	do

		local function StringToTableKeys(str)
			local t = { };
			for key in gmatch(str, "%w+") do
				local nmbr = tonumber(key);
				if (nmbr ~= nil) then
					t[nmbr] = true;
				end
			end
			return t;
		end

		editboxSpellID = CreateFrame("EditBox", nil, areaIDs, BackdropTemplateMixin and "BackdropTemplate");
		editboxSpellID:SetAutoFocus(false);
		editboxSpellID:SetFontObject(GameFontHighlightSmall);
		editboxSpellID.text = editboxSpellID:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		editboxSpellID.text:SetPoint("TOPLEFT", areaIDs, "TOPLEFT", 10, -10);
		editboxSpellID.text:SetText(L["Check spell ID"]);
		editboxSpellID:SetPoint("LEFT", editboxSpellID.text, "RIGHT", 5, 0);
		editboxSpellID:SetPoint("RIGHT", areaIDs, "RIGHT", -15, 0);
		editboxSpellID:SetHeight(20);
		editboxSpellID:SetJustifyH("LEFT");
		editboxSpellID:EnableMouse(true);
		editboxSpellID:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
			tile = true, edgeSize = 1, tileSize = 5,
		});
		editboxSpellID:SetBackdropColor(0, 0, 0, 0.5);
		editboxSpellID:SetBackdropBorderColor(0.3, 0.3, 0.30, 0.80);
		editboxSpellID:SetScript("OnEscapePressed", function() editboxSpellID:ClearFocus(); end);
		editboxSpellID:SetScript("OnEnterPressed", function(self)
			local text = self:GetText();
			local t = StringToTableKeys(text);
			addonTable.db.CustomSpells2[selectedSpell].checkSpellID = (table_count(t) > 0) and t or nil;
			addonTable.UpdateAllNameplates(true);
			if (table_count(t) == 0) then
				self:SetText("");
			end
			self:ClearFocus();
		end);
		table_insert(controls, editboxSpellID);

	end

	-- // areaTooltip
	do

		areaTooltip = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaTooltip:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaTooltip:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaTooltip:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaTooltip:SetPoint("TOPLEFT", areaIDs, "BOTTOMLEFT", 0, 0);
		areaTooltip:SetWidth(500);
		areaTooltip:SetHeight(40);
		table_insert(controls, areaTooltip);

	end

	-- // areaIconGroups
	do

		areaIconGroups = CreateFrame("Frame", nil, spellArea.controlsFrame, BackdropTemplateMixin and "BackdropTemplate");
		areaIconGroups:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		areaIconGroups:SetBackdropColor(0.1, 0.1, 0.2, 1);
		areaIconGroups:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		areaIconGroups:SetPoint("TOPLEFT", areaTooltip, "BOTTOMLEFT", 0, 0);
		areaIconGroups:SetWidth(500);
		areaIconGroups:SetHeight(40);
		table_insert(controls, areaIconGroups);

	end

	-- // dropdownIconGroups
	do

		local function initialize(_self, _level, _menuList)
			local info = UIDropDownMenu_CreateInfo();
			for index, igData in pairs(addonTable.db.IconGroups) do
				info.text = igData.IconGroupName;
				info.value = index;
				info.checked = function() 
					if (selectedSpell ~= nil and selectedSpell ~= 0) then
						return addonTable.db.CustomSpells2[selectedSpell].iconGroups[index];
					else
						return false;
					end
				end;
				info.func = function()
					addonTable.db.CustomSpells2[selectedSpell].iconGroups[index] = not addonTable.db.CustomSpells2[selectedSpell].iconGroups[index];
					addonTable.UpdateAllNameplates(true);
				end;
				UIDropDownMenu_AddButton(info);
			end
		end

		addonTable.GuiSpellsDropdownIconGroups = "NAuras.GUIFrame.Spells.DropdownIconGroups";
		dropdownIconGroups = CreateFrame("Frame", addonTable.GuiSpellsDropdownIconGroups, areaIconGroups, "UIDropDownMenuTemplate");
		dropdownIconGroups:SetPoint("LEFT", areaIconGroups, "LEFT", -3, -2);
		dropdownIconGroups.Reinitialize = function()
			UIDropDownMenu_Initialize(dropdownIconGroups, initialize);
		end

		UIDropDownMenu_Initialize(dropdownIconGroups, initialize);
		UIDropDownMenu_SetWidth(dropdownIconGroups, 130);
		UIDropDownMenu_SetText(dropdownIconGroups, "Icon Groups");

		areaIconGroups:SetWidth(dropdownIconGroups:GetWidth());

	end

	-- // buttonDeleteSpell
	do

		buttonDeleteSpell = VGUI.CreateButton();
		buttonDeleteSpell:SetParent(spellArea.controlsFrame);
		buttonDeleteSpell:SetText(L["Delete spell"]);
		--buttonDeleteSpell:SetWidth(90);
		buttonDeleteSpell:SetHeight(20);
		buttonDeleteSpell:SetPoint("TOPLEFT", areaIconGroups, "BOTTOMLEFT", 10, -10);
		buttonDeleteSpell:SetPoint("RIGHT", spellArea.scrollArea, "RIGHT", -10, 0);
		buttonDeleteSpell:SetScript("OnClick", function()
			addonTable.db.CustomSpells2[selectedSpell] = nil;
			addonTable.RebuildSpellCache();
			addonTable.UpdateAllNameplates(false);
			selectSpell.Text:SetText(L["Click to select spell"]);
			selectSpell.icon:SetTexture(nil);
			for _, control in pairs(controls) do
				control:Hide();
			end
		end);
		table_insert(controls, buttonDeleteSpell);

	end

	-- // buttonExportSpell
	do
		local luaEditor = VGUI.CreateLuaEditor();

		buttonExportSpell = VGUI.CreateButton();
		buttonExportSpell:SetParent(spellArea.controlsFrame);
		buttonExportSpell:SetText(L["options:spells:export-spell"]);
		--buttonExportSpell:SetWidth(90);
		buttonExportSpell:SetHeight(20);
		buttonExportSpell:SetPoint("TOPLEFT", buttonDeleteSpell, "BOTTOMLEFT", 0, -10);
		buttonExportSpell:SetPoint("TOPRIGHT", buttonDeleteSpell, "BOTTOMRIGHT", 0, -10);
		buttonExportSpell:SetScript("OnClick", function()
			local data = addonTable.db.CustomSpells2[selectedSpell];
			local serialized = LibSerialize:Serialize(data);
			local compressed = LibDeflate:CompressDeflate(serialized);
			local encoded = LibDeflate:EncodeForPrint(compressed);

			luaEditor:SetHeaderText("Export aura");
			luaEditor:SetText(encoded);
			luaEditor:SetAcceptButton(false, nil);
			luaEditor:Show();
		end);
		table_insert(controls, buttonExportSpell);

	end

end

local function GUICategory_Interrupts(index)

	local interruptOptionsArea, checkBoxInterrupts, checkBoxUseSharedIconTexture, checkBoxEnableOnlyInPvPMode, sizeArea, sliderInterruptIconSizeWidth, sliderInterruptIconSizeHeight;

	-- // checkBoxInterrupts
	do

		checkBoxInterrupts = VGUI.CreateCheckBox();
		checkBoxInterrupts:SetText(L["options:interrupts:enable-interrupts"]);
		checkBoxInterrupts:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].InterruptsEnabled = this:GetChecked();
			if (addonTable.db.IconGroups[CurrentIconGroup].InterruptsEnabled) then
				interruptOptionsArea:Show();
			else
				interruptOptionsArea:Hide();
			end
		end);
		checkBoxInterrupts:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsEnabled);
		checkBoxInterrupts:SetParent(GUIFrame);
		checkBoxInterrupts:SetPoint("TOPLEFT", 160, -20);
		checkBoxInterrupts:HookScript("OnShow", function() if (addonTable.db.IconGroups[CurrentIconGroup].InterruptsEnabled) then interruptOptionsArea:Show(); end end);
		checkBoxInterrupts:HookScript("OnHide", function() interruptOptionsArea:Hide(); end);
		table_insert(GUIFrame.Categories[index], checkBoxInterrupts);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxInterrupts:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsEnabled);
		end);

	end

	-- // interruptOptionsArea
	do

		interruptOptionsArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		interruptOptionsArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		interruptOptionsArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		interruptOptionsArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		interruptOptionsArea:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -30);
		interruptOptionsArea:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -5, 0);
		interruptOptionsArea:SetHeight(200);
		interruptOptionsArea:Hide();

	end

	-- // checkBoxUseSharedIconTexture
	do
		checkBoxUseSharedIconTexture = VGUI.CreateCheckBox();
		checkBoxUseSharedIconTexture:SetText(L["options:interrupts:use-shared-icon-texture"]);
		checkBoxUseSharedIconTexture:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].InterruptsUseSharedIconTexture = this:GetChecked();
			for spellID in pairs(addonTable.Interrupts) do
				SpellTextureByID[spellID] = addonTable.db.IconGroups[CurrentIconGroup].InterruptsUseSharedIconTexture and "Interface\\AddOns\\NameplateAuras\\media\\warrior_disruptingshout.tga" or SpellTextureByID[spellID]; -- // icon of Interrupting Shout
			end
			addonTable.UpdateAllNameplates(true);
		end);
		checkBoxUseSharedIconTexture:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsUseSharedIconTexture);
		checkBoxUseSharedIconTexture:SetParent(interruptOptionsArea);
		checkBoxUseSharedIconTexture:SetPoint("TOPLEFT", 20, -10);
		checkBoxUseSharedIconTexture:Show();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxUseSharedIconTexture:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsUseSharedIconTexture);
		end);

	end

	-- // checkBoxEnableOnlyInPvPMode
	do
		checkBoxEnableOnlyInPvPMode = VGUI.CreateCheckBox();
		checkBoxEnableOnlyInPvPMode:Show();
		checkBoxEnableOnlyInPvPMode:SetText(L["options:interrupts:enable-only-during-pvp-battles"]);
		checkBoxEnableOnlyInPvPMode:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].InterruptsShowOnlyOnPlayers = this:GetChecked();
			addonTable.UpdateAllNameplates(false);
		end);
		checkBoxEnableOnlyInPvPMode:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsShowOnlyOnPlayers);
		checkBoxEnableOnlyInPvPMode:SetParent(interruptOptionsArea);
		checkBoxEnableOnlyInPvPMode:SetPoint("TOPLEFT", checkBoxUseSharedIconTexture, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxEnableOnlyInPvPMode:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].InterruptsShowOnlyOnPlayers);
		end);
	end

	-- // sizeArea
	do

		sizeArea = CreateFrame("Frame", nil, interruptOptionsArea, BackdropTemplateMixin and "BackdropTemplate");
		sizeArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		sizeArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		sizeArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		sizeArea:SetPoint("TOPLEFT", checkBoxEnableOnlyInPvPMode, "BOTTOMLEFT", 0, -10);
		sizeArea:SetPoint("RIGHT", interruptOptionsArea, "RIGHT", -10, 0);
		sizeArea:SetHeight(80);

	end

	-- // sliderInterruptIconSizeWidth
	do

		sliderInterruptIconSizeWidth = VGUI.CreateSlider();
		sliderInterruptIconSizeWidth:Show();
		sliderInterruptIconSizeWidth:SetParent(sizeArea);
		sliderInterruptIconSizeWidth:SetWidth((sizeArea:GetWidth() - 20 - 10)/2);
		sliderInterruptIconSizeWidth:ClearAllPoints();
		sliderInterruptIconSizeWidth:SetPoint("LEFT", sizeArea, "LEFT", 10, 0);
		sliderInterruptIconSizeWidth.label:ClearAllPoints();
		sliderInterruptIconSizeWidth.label:SetPoint("CENTER", sliderInterruptIconSizeWidth, "CENTER", 0, 15);
		sliderInterruptIconSizeWidth.label:SetText(L["options:spells:icon-width"]);
		sliderInterruptIconSizeWidth.slider:ClearAllPoints();
		sliderInterruptIconSizeWidth.slider:SetPoint("LEFT", 3, 0)
		sliderInterruptIconSizeWidth.slider:SetPoint("RIGHT", -3, 0)
		sliderInterruptIconSizeWidth.slider:SetValueStep(1);
		sliderInterruptIconSizeWidth.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderInterruptIconSizeWidth.slider:SetScript("OnValueChanged", function(_, value)
			sliderInterruptIconSizeWidth.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderInterruptIconSizeWidth.editbox:SetScript("OnEnterPressed", function()
			if (sliderInterruptIconSizeWidth.editbox:GetText() ~= "") then
				local v = tonumber(sliderInterruptIconSizeWidth.editbox:GetText());
				if (v == nil) then
					sliderInterruptIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderInterruptIconSizeWidth.slider:SetValue(v);
				end
				sliderInterruptIconSizeWidth.editbox:ClearFocus();
			end
		end);
		sliderInterruptIconSizeWidth.lowtext:SetText("1");
		sliderInterruptIconSizeWidth.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		sliderInterruptIconSizeWidth.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth);
		sliderInterruptIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderInterruptIconSizeWidth.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth);
			sliderInterruptIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeWidth));
		end);

	end

	-- // sliderInterruptIconSizeHeight
	do

		sliderInterruptIconSizeHeight = VGUI.CreateSlider();
		sliderInterruptIconSizeHeight:Show();
		sliderInterruptIconSizeHeight:SetParent(sizeArea);
		sliderInterruptIconSizeHeight:SetWidth((sizeArea:GetWidth() - 20 - 10)/2);
		sliderInterruptIconSizeHeight:ClearAllPoints();
		sliderInterruptIconSizeHeight:SetPoint("LEFT", sliderInterruptIconSizeWidth, "RIGHT", 10, 0);
		sliderInterruptIconSizeHeight.label:ClearAllPoints();
		sliderInterruptIconSizeHeight.label:SetPoint("CENTER", sliderInterruptIconSizeHeight, "CENTER", 0, 15);
		sliderInterruptIconSizeHeight.label:SetText(L["options:spells:icon-height"]);
		sliderInterruptIconSizeHeight.slider:ClearAllPoints();
		sliderInterruptIconSizeHeight.slider:SetPoint("LEFT", 3, 0)
		sliderInterruptIconSizeHeight.slider:SetPoint("RIGHT", -3, 0)
		sliderInterruptIconSizeHeight.slider:SetValueStep(1);
		sliderInterruptIconSizeHeight.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderInterruptIconSizeHeight.slider:SetScript("OnValueChanged", function(_, value)
			sliderInterruptIconSizeHeight.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderInterruptIconSizeHeight.editbox:SetScript("OnEnterPressed", function()
			if (sliderInterruptIconSizeHeight.editbox:GetText() ~= "") then
				local v = tonumber(sliderInterruptIconSizeHeight.editbox:GetText());
				if (v == nil) then
					sliderInterruptIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderInterruptIconSizeHeight.slider:SetValue(v);
				end
				sliderInterruptIconSizeHeight.editbox:ClearFocus();
			end
		end);
		sliderInterruptIconSizeHeight.lowtext:SetText("1");
		sliderInterruptIconSizeHeight.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		sliderInterruptIconSizeHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight);
		sliderInterruptIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderInterruptIconSizeHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight);
			sliderInterruptIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].InterruptsIconSizeHeight));
		end);

	end

	-- // dropdownGlowType
	do
		local glowTypes = {
			[addonTable.GLOW_TYPE_NONE] = L["options:glow-type:GLOW_TYPE_NONE"],
			[addonTable.GLOW_TYPE_ACTIONBUTTON] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON"],
			[addonTable.GLOW_TYPE_AUTOUSE] = L["options:glow-type:GLOW_TYPE_AUTOUSE"],
			[addonTable.GLOW_TYPE_PIXEL] = L["options:glow-type:GLOW_TYPE_PIXEL"],
			[addonTable.GLOW_TYPE_ACTIONBUTTON_DIM] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON_DIM"],
		};

		local dropdownGlowType = CreateFrame("Frame", "NAurasGUI.Interrupts.dropdownGlowType", interruptOptionsArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownGlowType, 150);
		dropdownGlowType:SetPoint("TOPLEFT", sizeArea, "BOTTOMLEFT", -10, -20);
		local info = {};
		dropdownGlowType.initialize = function()
			wipe(info);
			for glowType, glowTypeLocalized in pairs(glowTypes) do
				info.text = glowTypeLocalized;
				info.value = glowType;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].InterruptsGlowType = self.value;
					_G[dropdownGlowType:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = glowType == addonTable.db.IconGroups[CurrentIconGroup].InterruptsGlowType;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownGlowType:GetName() .. "Text"]:SetText(glowTypes[addonTable.db.IconGroups[CurrentIconGroup].InterruptsGlowType]);
		dropdownGlowType.text = dropdownGlowType:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownGlowType.text:SetPoint("LEFT", 20, 20);
		dropdownGlowType.text:SetText(L["options:glow-type"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownGlowType:GetName() .. "Text"]:SetText(glowTypes[addonTable.db.IconGroups[CurrentIconGroup].InterruptsGlowType]); end);
	end

end

local function GUICategory_Additions(index)
	local area2, checkBoxDRPvP;

	-- area2
	do
		area2 = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		area2:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		area2:SetBackdropColor(0.1, 0.1, 0.2, 1);
		area2:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		area2:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, 0);
		area2:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -10, 0);
		area2:SetHeight(85);
		table_insert(GUIFrame.Categories[index], area2);
	end

	-- textDR
	do
		local textDR = area2:CreateFontString(nil, "OVERLAY", "GameFontNormal");
		textDR:SetPoint("TOPLEFT", area2, "TOPLEFT", 20, -15);
		textDR:SetText(L["options:apps:dr"]);
	end

	-- // checkBoxDRPvP
	do
		checkBoxDRPvP = VGUI.CreateCheckBox();
		checkBoxDRPvP:SetText(L["options:apps:dr:pvp"]);
		checkBoxDRPvP:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvP = this:GetChecked();
			if (not addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvP) then
				addonTable.UpdateAllNameplates(true);
			end
		end);
		checkBoxDRPvP:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvP);
		checkBoxDRPvP:SetParent(area2);
		checkBoxDRPvP:SetPoint("LEFT", area2, "LEFT", 20, -5);
		table_insert(GUIFrame.Categories[index], checkBoxDRPvP);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxDRPvP:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvP);
		end);
	end

	-- // checkBoxDRPvE
	do
		local checkBoxDRPvE = VGUI.CreateCheckBox();
		checkBoxDRPvE:SetText(L["options:apps:dr:pve"]);
		checkBoxDRPvE:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvE = this:GetChecked();
			if (not addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvE) then
				addonTable.UpdateAllNameplates(true);
			end
		end);
		checkBoxDRPvE:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvE);
		checkBoxDRPvE:SetParent(area2);
		checkBoxDRPvE:SetPoint("TOPLEFT", checkBoxDRPvP, "BOTTOMLEFT", 0, 0);
		table_insert(GUIFrame.Categories[index], checkBoxDRPvE);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxDRPvE:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DRPvE);
		end);
	end

end

local function GUICategory_SizeAndPosition(index)
	local dropdownFrameAnchorToNameplate;
	local frameAnchors = { "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "TOP", "CENTER", "BOTTOM", "TOPLEFT", "LEFT", "BOTTOMLEFT" };
	local frameAnchorsLocalization = {
		[frameAnchors[1]] = L["anchor-point:topright"],
		[frameAnchors[2]] = L["anchor-point:right"],
		[frameAnchors[3]] = L["anchor-point:bottomright"],
		[frameAnchors[4]] = L["anchor-point:top"],
		[frameAnchors[5]] = L["anchor-point:center"],
		[frameAnchors[6]] = L["anchor-point:bottom"],
		[frameAnchors[7]] = L["anchor-point:topleft"],
		[frameAnchors[8]] = L["anchor-point:left"],
		[frameAnchors[9]] = L["anchor-point:bottomleft"]
	};

	-- // sliderIconSize
	do

		local sliderIconSize = VGUI.CreateSlider();
		sliderIconSize:SetParent(GUIFrame);
		sliderIconSize:SetWidth(170);
		sliderIconSize:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 5, -13);
		sliderIconSize.label:SetText(L["options:size-and-position:icon-width"]);
		sliderIconSize.slider:SetValueStep(1);
		sliderIconSize.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderIconSize.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth);
		sliderIconSize.slider:SetScript("OnValueChanged", function(_, value)
			local valueNum = math_ceil(value);
			sliderIconSize.editbox:SetText(tostring(valueNum));
			for _, spellInfo in pairs(addonTable.db.CustomSpells2) do
				if (spellInfo.iconSizeWidth == addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth) then
					spellInfo.iconSizeWidth = valueNum;
				end
			end
			addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth = valueNum;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth));
		sliderIconSize.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconSize.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconSize.editbox:GetText());
				if (v == nil) then
					sliderIconSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth));
					msg(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderIconSize.slider:SetValue(v);
				end
				sliderIconSize.editbox:ClearFocus();
			end
		end);
		sliderIconSize.lowtext:SetText("1");
		sliderIconSize.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		table_insert(GUIFrame.Categories[index], sliderIconSize);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconSize.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth);
			sliderIconSize.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeWidth));
		end);

	end

	-- // sliderIconHeight
	do
		local sliderIconHeight = VGUI.CreateSlider();
		sliderIconHeight:SetParent(GUIFrame);
		sliderIconHeight:SetWidth(170);
		sliderIconHeight:SetPoint("TOP", GUIFrame.ControlsFrame, "TOP", 0, -13);
		sliderIconHeight.label:SetText(L["options:size-and-position:icon-height"]);
		sliderIconHeight.slider:SetValueStep(1);
		sliderIconHeight.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderIconHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight);
		sliderIconHeight.slider:SetScript("OnValueChanged", function(_, value)
			local valueNum = math_ceil(value);
			sliderIconHeight.editbox:SetText(tostring(valueNum));
			for _, spellInfo in pairs(addonTable.db.CustomSpells2) do
				if (spellInfo.iconSizeHeight == addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight) then
					spellInfo.iconSizeHeight = valueNum;
				end
			end
			addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight = valueNum;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight));
		sliderIconHeight.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconHeight.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconHeight.editbox:GetText());
				if (v == nil) then
					sliderIconHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight));
					msg(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderIconHeight.slider:SetValue(v);
				end
				sliderIconHeight.editbox:ClearFocus();
			end
		end);
		sliderIconHeight.lowtext:SetText("1");
		sliderIconHeight.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		table_insert(GUIFrame.Categories[index], sliderIconHeight);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight);
			sliderIconHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DefaultIconSizeHeight));
		end);
	end

	-- // sliderIconSpacing
	do
		local minValue, maxValue = 0, 50;
		local sliderIconSpacing = VGUI.CreateSlider();
		sliderIconSpacing:SetParent(GUIFrame);
		sliderIconSpacing:SetWidth(170);
		sliderIconSpacing:SetPoint("TOPRIGHT", GUIFrame.ControlsFrame, "TOPRIGHT", -5, -13);
		sliderIconSpacing.label:SetText(L["Space between icons"]);
		sliderIconSpacing.slider:SetValueStep(1);
		sliderIconSpacing.slider:SetMinMaxValues(minValue, maxValue);
		sliderIconSpacing.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconSpacing);
		sliderIconSpacing.slider:SetScript("OnValueChanged", function(_, value)
			sliderIconSpacing.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].IconSpacing = math_ceil(value);
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconSpacing.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconSpacing));
		sliderIconSpacing.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconSpacing.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconSpacing.editbox:GetText());
				if (v == nil) then
					sliderIconSpacing.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconSpacing));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderIconSpacing.slider:SetValue(v);
				end
				sliderIconSpacing.editbox:ClearFocus();
			end
		end);
		sliderIconSpacing.lowtext:SetText(tostring(minValue));
		sliderIconSpacing.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.Categories[index], sliderIconSpacing);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconSpacing.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconSpacing);
			sliderIconSpacing.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconSpacing));
		end);
	end

	-- // sliderIconXOffset
	do

		local sliderIconXOffset = VGUI.CreateSlider();
		sliderIconXOffset:SetParent(GUIFrame);
		sliderIconXOffset:SetWidth(170);
		sliderIconXOffset:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 5, -73);
		sliderIconXOffset.label:SetText(L["Icon X-coord offset"]);
		sliderIconXOffset.slider:SetValueStep(1);
		sliderIconXOffset.slider:SetMinMaxValues(-200, 200);
		sliderIconXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconXOffset);
		sliderIconXOffset.slider:SetScript("OnValueChanged", function(_, value)
			sliderIconXOffset.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].IconXOffset = math_ceil(value);
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconXOffset));
		sliderIconXOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconXOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconXOffset.editbox:GetText());
				if (v == nil) then
					sliderIconXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconXOffset));
					Print(L["Value must be a number"]);
				else
					if (v > 200) then
						v = 200;
					end
					if (v < -200) then
						v = -200;
					end
					sliderIconXOffset.slider:SetValue(v);
				end
				sliderIconXOffset.editbox:ClearFocus();
			end
		end);
		sliderIconXOffset.lowtext:SetText("-200");
		sliderIconXOffset.hightext:SetText("200");
		table_insert(GUIFrame.Categories[index], sliderIconXOffset);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconXOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconXOffset);
			sliderIconXOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconXOffset));
		end);

	end

	-- // sliderIconYOffset
	do

		local sliderIconYOffset = VGUI.CreateSlider();
		sliderIconYOffset:SetParent(GUIFrame);
		sliderIconYOffset:SetWidth(170);
		sliderIconYOffset:SetPoint("TOP", GUIFrame.ControlsFrame, "TOP", 0, -73);
		sliderIconYOffset.label:SetText(L["Icon Y-coord offset"]);
		sliderIconYOffset.slider:SetValueStep(1);
		sliderIconYOffset.slider:SetMinMaxValues(-200, 200);
		sliderIconYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconYOffset);
		sliderIconYOffset.slider:SetScript("OnValueChanged", function(_, value)
			sliderIconYOffset.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].IconYOffset = math_ceil(value);
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconYOffset));
		sliderIconYOffset.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconYOffset.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconYOffset.editbox:GetText());
				if (v == nil) then
					sliderIconYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconYOffset));
					Print(L["Value must be a number"]);
				else
					if (v > 200) then
						v = 200;
					end
					if (v < -200) then
						v = -200;
					end
					sliderIconYOffset.slider:SetValue(v);
				end
				sliderIconYOffset.editbox:ClearFocus();
			end
		end);
		sliderIconYOffset.lowtext:SetText("-200");
		sliderIconYOffset.hightext:SetText("200");
		table_insert(GUIFrame.Categories[index], sliderIconYOffset);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconYOffset.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconYOffset);
			sliderIconYOffset.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconYOffset));
		end);

	end

	-- // sliderIconZoom
	do
		local minV, maxV = 0, 0.3;
		local sliderIconZoom = VGUI.CreateSlider();
		sliderIconZoom:SetParent(GUIFrame);
		sliderIconZoom:SetWidth(170);
		sliderIconZoom:SetPoint("TOPRIGHT", GUIFrame.ControlsFrame, "TOPRIGHT", -5, -73);
		sliderIconZoom.label:SetText(L["options:size-and-position:icon-zoom"]);
		sliderIconZoom.slider:SetValueStep(0.01);
		sliderIconZoom.slider:SetMinMaxValues(minV, maxV);
		sliderIconZoom.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconZoom);
		sliderIconZoom.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.2f", value));
			sliderIconZoom.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].IconZoom = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderIconZoom.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconZoom));
		sliderIconZoom.editbox:SetScript("OnEnterPressed", function()
			if (sliderIconZoom.editbox:GetText() ~= "") then
				local v = tonumber(sliderIconZoom.editbox:GetText());
				if (v == nil) then
					sliderIconZoom.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconZoom));
					Print(L["Value must be a number"]);
				else
					if (v > maxV) then
						v = maxV;
					end
					if (v < minV) then
						v = minV;
					end
					sliderIconZoom.slider:SetValue(v);
				end
				sliderIconZoom.editbox:ClearFocus();
			end
		end);
		sliderIconZoom.lowtext:SetText(tostring(minV));
		sliderIconZoom.hightext:SetText(tostring(maxV));
		table_insert(GUIFrame.Categories[index], sliderIconZoom);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderIconZoom.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconZoom);
			sliderIconZoom.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconZoom));
		end);
	end

	-- // checkboxKeepAspectRatio
	do
		local checkboxKeepAspectRatio = VGUI.CreateCheckBox();
		checkboxKeepAspectRatio:SetText(L["options:size-and-position:keep-aspect-ratio"]);
		VGUI.SetTooltip(checkboxKeepAspectRatio, L["options:size-and-position:keep-aspect-ratio:tooltip"]);
		checkboxKeepAspectRatio:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].KeepAspectRatio = this:GetChecked();
			addonTable.UpdateAllNameplates();
		end);
		checkboxKeepAspectRatio:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].KeepAspectRatio);
		checkboxKeepAspectRatio:SetParent(GUIFrame);
		checkboxKeepAspectRatio:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -120);
		table_insert(GUIFrame.Categories[index], checkboxKeepAspectRatio);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkboxKeepAspectRatio:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].KeepAspectRatio);
		end);
	end

	-- // dropdownFrameAnchorToNameplate
	do
		dropdownFrameAnchorToNameplate = CreateFrame("Frame", "NAuras.GUI.SizeAndPosition.dropdownFrameAnchorToNameplate", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownFrameAnchorToNameplate, 220);
		dropdownFrameAnchorToNameplate:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -160);
		local info = {};
		dropdownFrameAnchorToNameplate.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(frameAnchors) do
				info.text = frameAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].FrameAnchorToNameplate = self.value;
					_G[dropdownFrameAnchorToNameplate:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = anchorPoint == addonTable.db.IconGroups[CurrentIconGroup].FrameAnchorToNameplate;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownFrameAnchorToNameplate:GetName() .. "Text"]:SetText(frameAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].FrameAnchorToNameplate]);
		dropdownFrameAnchorToNameplate.text = dropdownFrameAnchorToNameplate:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownFrameAnchorToNameplate.text:SetPoint("LEFT", 20, 20);
		dropdownFrameAnchorToNameplate.text:SetText(L["options:size-and-position:anchor-point-to-nameplate"]);
		table_insert(GUIFrame.Categories[index], dropdownFrameAnchorToNameplate);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownFrameAnchorToNameplate:GetName() .. "Text"]:SetText(frameAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].FrameAnchorToNameplate]);
		end);
	end

	-- // dropdownFrameAnchor
	do
		local dropdownFrameAnchor = CreateFrame("Frame", "NAuras.GUI.Cat1.DropdownFrameAnchor", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownFrameAnchor, 220);
		dropdownFrameAnchor:SetPoint("TOPRIGHT", GUIFrame.ControlsFrame, "TOPRIGHT", 0, -160);
		local info = {};
		dropdownFrameAnchor.initialize = function()
			wipe(info);
			for _, anchorPoint in pairs(frameAnchors) do
				info.text = frameAnchorsLocalization[anchorPoint];
				info.value = anchorPoint;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].FrameAnchor = self.value;
					_G[dropdownFrameAnchor:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].FrameAnchor == anchorPoint);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownFrameAnchor:GetName().."Text"]:SetText(frameAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].FrameAnchor]);
		dropdownFrameAnchor.text = dropdownFrameAnchor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownFrameAnchor.text:SetPoint("LEFT", 20, 20);
		dropdownFrameAnchor.text:SetText(L["options:size-and-position:anchor-point-of-frame"]);
		VGUI.SetTooltip(dropdownFrameAnchor, L["options:size-and-position:anchor-point-of-frame:tooltip"]);
		table_insert(GUIFrame.Categories[index], dropdownFrameAnchor);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownFrameAnchor:GetName().."Text"]:SetText(frameAnchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].FrameAnchor]);
		end);

	end

	-- // dropdownIconAnchor
	do
		local anchors = { addonTable.ICON_ALIGN_BOTTOM_LEFT, addonTable.ICON_ALIGN_TOP_RIGHT, addonTable.ICON_ALIGN_CENTER }; -- // if you change this, don't forget to change 'symmetricAnchors'
		local anchorsLocalization = {
			[anchors[1]] = L["options:size-and-position:icon-align:bottom-left"],
			[anchors[2]] = L["options:size-and-position:icon-align:top-right"],
			[anchors[3]] = L["options:size-and-position:icon-align:center"] };
		local dropdownIconAnchor = CreateFrame("Frame", "NAuras.GUI.Cat1.DropdownIconAnchor", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownIconAnchor, 220);
		dropdownIconAnchor:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -200);
		local info = {};
		dropdownIconAnchor.initialize = function()
			wipe(info);
			for _, anchor in pairs(anchors) do
				info.text = anchorsLocalization[anchor];
				info.value = anchor;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].IconAnchor = self.value;
					_G[dropdownIconAnchor:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].IconAnchor == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownIconAnchor:GetName().."Text"]:SetText(anchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].IconAnchor]);
		dropdownIconAnchor.text = dropdownIconAnchor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownIconAnchor.text:SetPoint("LEFT", 20, 20);
		dropdownIconAnchor.text:SetText(L["options:size-and-position:icon-align"]);
		table_insert(GUIFrame.Categories[index], dropdownIconAnchor);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownIconAnchor:GetName().."Text"]:SetText(anchorsLocalization[addonTable.db.IconGroups[CurrentIconGroup].IconAnchor]); end);
	end

	-- // dropdownIconGrowDirection
	do
		local growDirections = { addonTable.ICON_GROW_DIRECTION_RIGHT, addonTable.ICON_GROW_DIRECTION_LEFT,
			addonTable.ICON_GROW_DIRECTION_UP, addonTable.ICON_GROW_DIRECTION_DOWN };
		local growDirectionsL = {
			[growDirections[1]] = L["icon-grow-direction:right"],
			[growDirections[2]] = L["icon-grow-direction:left"],
			[growDirections[3]] = L["icon-grow-direction:up"],
			[growDirections[4]] = L["icon-grow-direction:down"],
		};
		local dropdownIconGrowDirection = CreateFrame("Frame", "NAuras.GUI.SizeAndPosition.DropdownIconGrowDirection", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownIconGrowDirection, 220);
		dropdownIconGrowDirection:SetPoint("TOPRIGHT", GUIFrame.ControlsFrame, "TOPRIGHT", 0, -200);
		local info = {};
		dropdownIconGrowDirection.initialize = function()
			wipe(info);
			for _, direction in pairs(growDirections) do
				info.text = growDirectionsL[direction];
				info.value = direction;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].IconGrowDirection = self.value;
					_G[dropdownIconGrowDirection:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].IconGrowDirection == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownIconGrowDirection:GetName().."Text"]:SetText(growDirectionsL[addonTable.db.IconGroups[CurrentIconGroup].IconGrowDirection]);
		dropdownIconGrowDirection.text = dropdownIconGrowDirection:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownIconGrowDirection.text:SetPoint("LEFT", 20, 20);
		dropdownIconGrowDirection.text:SetText(L["options:general:icon-grow-direction"]);
		table.insert(GUIFrame.Categories[index], dropdownIconGrowDirection);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownIconGrowDirection:GetName().."Text"]:SetText(growDirectionsL[addonTable.db.IconGroups[CurrentIconGroup].IconGrowDirection]);
		end);
	end

	local dropdownTargetStrata, dropdownNonTargetStrata;
	local frameStratas = {
		"BACKGROUND",
		"LOW",
		"MEDIUM",
		"HIGH",
		"DIALOG",
		"FULLSCREEN",
		"FULLSCREEN_DIALOG",
		"TOOLTIP",
	};

	-- // dropdownTargetStrata
	do
		dropdownTargetStrata = CreateFrame("Frame", "NAuras.GUI.SizeAndPosition.dropdownTargetStrata", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownTargetStrata, 220);
		dropdownTargetStrata:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -240);
		local info = {};
		dropdownTargetStrata.initialize = function()
			wipe(info);
			for _, strata in pairs(frameStratas) do
				info.text = strata;
				info.value = strata;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].TargetStrata = self.value;
					_G[dropdownTargetStrata:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].TargetStrata == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownTargetStrata:GetName().."Text"]:SetText(addonTable.db.IconGroups[CurrentIconGroup].TargetStrata);
		dropdownTargetStrata.text = dropdownTargetStrata:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownTargetStrata.text:SetPoint("LEFT", 20, 20);
		dropdownTargetStrata.text:SetText(L["options:size-and-position:target-strata"]);
		table.insert(GUIFrame.Categories[index], dropdownTargetStrata);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownTargetStrata:GetName().."Text"]:SetText(addonTable.db.IconGroups[CurrentIconGroup].TargetStrata); end);
	end

	-- // dropdownNonTargetStrata
	do
		dropdownNonTargetStrata = CreateFrame("Frame", "NAuras.GUI.SizeAndPosition.dropdownNonTargetStrata", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownNonTargetStrata, 220);
		dropdownNonTargetStrata:SetPoint("TOPRIGHT", GUIFrame.ControlsFrame, "TOPRIGHT", 0, -240);
		local info = {};
		dropdownNonTargetStrata.initialize = function()
			wipe(info);
			for _, strata in pairs(frameStratas) do
				info.text = strata;
				info.value = strata;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].NonTargetStrata = self.value;
					_G[dropdownNonTargetStrata:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].NonTargetStrata == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownNonTargetStrata:GetName().."Text"]:SetText(addonTable.db.IconGroups[CurrentIconGroup].NonTargetStrata);
		dropdownNonTargetStrata.text = dropdownNonTargetStrata:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownNonTargetStrata.text:SetPoint("LEFT", 20, 20);
		dropdownNonTargetStrata.text:SetText(L["options:size-and-position:non-target-strata"]);
		table.insert(GUIFrame.Categories[index], dropdownNonTargetStrata);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownNonTargetStrata:GetName().."Text"]:SetText(addonTable.db.IconGroups[CurrentIconGroup].NonTargetStrata); end);
	end

	local dropdownSortMode, buttonCustomSortFunction;
	do
		local SortModesLocalization = {
			[AURA_SORT_MODE_NONE] =					L["icon-sort-mode:none"],
			[AURA_SORT_MODE_EXPIRETIME] =			L["icon-sort-mode:by-expire-time"],
			[AURA_SORT_MODE_ICONSIZE] =				L["icon-sort-mode:by-icon-size"],
			[AURA_SORT_MODE_AURATYPE_EXPIRE] =		L["icon-sort-mode:by-aura-type+by-expire-time"],
			[addonTable.AURA_SORT_MODE_CUSTOM] =	L["icon-sort-mode:custom"],
		};

		local function UpdateButton()
			if (addonTable.db.IconGroups[CurrentIconGroup].SortMode == addonTable.AURA_SORT_MODE_CUSTOM) then
				buttonCustomSortFunction:Show();
			else
				buttonCustomSortFunction:Hide();
			end
		end

		dropdownSortMode = CreateFrame("Frame", "NAuras.GUI.Cat1.DropdownSortMode", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownSortMode, 300);
		dropdownSortMode:SetPoint("TOP", GUIFrame.ControlsFrame, "TOP", 0, -290);
		local info = {};
		dropdownSortMode.initialize = function()
			wipe(info);
			for sortMode, sortModeL in pairs(SortModesLocalization) do
				info.text = sortModeL;
				info.value = sortMode;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].SortMode = self.value;
					_G[dropdownSortMode:GetName().."Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
					UpdateButton();
				end
				info.checked = (addonTable.db.IconGroups[CurrentIconGroup].SortMode == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownSortMode:GetName().."Text"]:SetText(SortModesLocalization[addonTable.db.IconGroups[CurrentIconGroup].SortMode]);
		dropdownSortMode.text = dropdownSortMode:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		dropdownSortMode.text:SetPoint("LEFT", 20, 20);
		dropdownSortMode.text:SetText(L["Sort mode:"]);
		table_insert(GUIFrame.Categories[index], dropdownSortMode);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownSortMode:GetName().."Text"]:SetText(SortModesLocalization[addonTable.db.IconGroups[CurrentIconGroup].SortMode]); end);

		local LuaEditor = VGUI.CreateLuaEditor();
		LuaEditor:SetOnAcceptHandler(function(self)
			addonTable.db.IconGroups[CurrentIconGroup].CustomSortMethod = self:GetText();
			addonTable.RebuildAuraSortFunctions();
			addonTable.UpdateAllNameplates(true);
		end);
		LuaEditor:SetOnTextChangedHandler(function(self)
			local script = self:GetText();
			script = "return " .. script;
			local func, errorMsg = loadstring(script);
			if (func ~= nil) then
				self:SetStatusText("");
			else
				self:SetStatusText(errorMsg);
			end
		end);

		local LuaEditorTooltip = VGUI.CreateTooltip();
		LuaEditorTooltip:SetParent(LuaEditor);
		LuaEditorTooltip:SetPoint("TOPLEFT", LuaEditor, "BOTTOMLEFT", 0, 0);
		LuaEditorTooltip:SetPoint("TOPRIGHT", LuaEditor, "BOTTOMRIGHT", 0, 0);
		LuaEditorTooltip:GetTextObject():SetFontObject(GameFontNormal);
		LuaEditorTooltip:GetTextObject():SetJustifyH("LEFT");
		LuaEditorTooltip:SetText(L["options:size-and-position:custom-sorting:tooltip"]);
		LuaEditor:SetInfoButton(true, function()
			if (LuaEditorTooltip:IsShown()) then
				LuaEditorTooltip:Hide();
			else
				LuaEditorTooltip:Show();
			end
		end);

		buttonCustomSortFunction = VGUI.CreateButton();
		buttonCustomSortFunction:SetParent(dropdownSortMode);
		buttonCustomSortFunction:SetText("Lua -->>");
		buttonCustomSortFunction:SetWidth(60);
		buttonCustomSortFunction:SetHeight(22);
		buttonCustomSortFunction:SetPoint("LEFT", dropdownSortMode, "RIGHT", 0, 3);
		buttonCustomSortFunction:SetScript("OnClick", function()
			LuaEditor:SetText(addonTable.db.IconGroups[CurrentIconGroup].CustomSortMethod);
			LuaEditor:Show();
		end);
		UpdateButton();
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			UpdateButton();
		end);

	end

	local scaleArea, sliderScaleTarget;

	-- // scaleArea
	do

		scaleArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		scaleArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		scaleArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		scaleArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		scaleArea:SetPoint("TOP", dropdownSortMode, "BOTTOM", 0, 0);
		scaleArea:SetWidth(360);
		scaleArea:SetHeight(70);
		table_insert(GUIFrame.Categories[index], scaleArea);

	end

	-- // sliderScaleTarget
	do

		local minValue, maxValue, step = 0.1, 10, 0.1;
		sliderScaleTarget = VGUI.CreateSlider();
		sliderScaleTarget:SetParent(scaleArea);
		sliderScaleTarget:SetWidth(scaleArea:GetWidth() - 20);
		sliderScaleTarget:SetPoint("TOPLEFT", 10, -20);
		sliderScaleTarget.label:SetText(L["options:size-and-position:scale-target"]);
		sliderScaleTarget.slider:SetValueStep(step);
		sliderScaleTarget.slider:SetMinMaxValues(minValue, maxValue);
		sliderScaleTarget.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget);
		sliderScaleTarget.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.1f", value));
			sliderScaleTarget.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderScaleTarget.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget));
		sliderScaleTarget.editbox:SetScript("OnEnterPressed", function(self)
			if (self:GetText() ~= "") then
				local v = tonumber(self:GetText());
				if (v == nil) then
					self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderScaleTarget.slider:SetValue(v);
				end
				self:ClearFocus();
			else
				self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget));
				msg(L["Value must be a number"]);
			end
		end);
		sliderScaleTarget.lowtext:SetText(tostring(minValue));
		sliderScaleTarget.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderScaleTarget.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget));
			sliderScaleTarget.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconScaleTarget);
		end);
		sliderScaleTarget:Show();

	end

end

local function GUICategory_Alpha(index)
	local alphaArea, sliderAlpha, sliderAlphaTarget, checkboxUseTargetAlphaIfNotTargetSelected;

	-- // alphaArea
	do

		alphaArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		alphaArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		alphaArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		alphaArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		alphaArea:SetPoint("TOPLEFT", 150, -12);
		alphaArea:SetPoint("TOPRIGHT", -12, -12);
		alphaArea:SetHeight(170);
		table_insert(GUIFrame.Categories[index], alphaArea);

	end

	-- // sliderAlpha
	do

		local minValue, maxValue, step = 0, 1, 0.01;
		sliderAlpha = VGUI.CreateSlider();
		sliderAlpha:SetParent(alphaArea);
		sliderAlpha:SetWidth(alphaArea:GetWidth() - 20);
		sliderAlpha:SetPoint("TOPLEFT", 10, -20);
		sliderAlpha.label:SetText(L["options:alpha:alpha"]);
		sliderAlpha.slider:SetValueStep(step);
		sliderAlpha.slider:SetMinMaxValues(minValue, maxValue);
		sliderAlpha.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha);
		sliderAlpha.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.2f", value));
			sliderAlpha.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].IconAlpha = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderAlpha.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha));
		sliderAlpha.editbox:SetScript("OnEnterPressed", function(self)
			if (self:GetText() ~= "") then
				local v = tonumber(self:GetText());
				if (v == nil) then
					self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderAlpha.slider:SetValue(v);
				end
				self:ClearFocus();
			else
				self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha));
				msg(L["Value must be a number"]);
			end
		end);
		sliderAlpha.lowtext:SetText(tostring(minValue));
		sliderAlpha.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderAlpha.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha));
			sliderAlpha.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconAlpha);
		end);
		sliderAlpha:Show();

	end

	-- // sliderAlphaTarget
	do

		local minValue, maxValue, step = 0, 1, 0.01;
		sliderAlphaTarget = VGUI.CreateSlider();
		sliderAlphaTarget:SetParent(alphaArea);
		sliderAlphaTarget:SetWidth(alphaArea:GetWidth() - 20);
		sliderAlphaTarget:SetPoint("TOPLEFT", 10, -85);
		sliderAlphaTarget.label:SetText(L["options:alpha:alpha-target"]);
		sliderAlphaTarget.slider:SetValueStep(step);
		sliderAlphaTarget.slider:SetMinMaxValues(minValue, maxValue);
		sliderAlphaTarget.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget);
		sliderAlphaTarget.slider:SetScript("OnValueChanged", function(_, value)
			local actualValue = tonumber(string_format("%.2f", value));
			sliderAlphaTarget.editbox:SetText(tostring(actualValue));
			addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget = actualValue;
			addonTable.UpdateAllNameplates(true);
		end);
		sliderAlphaTarget.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget));
		sliderAlphaTarget.editbox:SetScript("OnEnterPressed", function(self)
			if (self:GetText() ~= "") then
				local v = tonumber(self:GetText());
				if (v == nil) then
					self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget));
					msg(L["Value must be a number"]);
				else
					if (v > maxValue) then
						v = maxValue;
					end
					if (v < minValue) then
						v = minValue;
					end
					sliderAlphaTarget.slider:SetValue(v);
				end
				self:ClearFocus();
			else
				self:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget));
				msg(L["Value must be a number"]);
			end
		end);
		sliderAlphaTarget.lowtext:SetText(tostring(minValue));
		sliderAlphaTarget.hightext:SetText(tostring(maxValue));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderAlphaTarget.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget));
			sliderAlphaTarget.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].IconAlphaTarget);
		end);
		sliderAlphaTarget:Show();

	end

	-- // checkboxUseTargetAlphaIfNotTargetSelected
	do
		checkboxUseTargetAlphaIfNotTargetSelected = VGUI.CreateCheckBox();
		checkboxUseTargetAlphaIfNotTargetSelected:SetText(L["options:alpha:use-target-alpha-if-not-target-selected"]);
		checkboxUseTargetAlphaIfNotTargetSelected:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].UseTargetAlphaIfNotTargetSelected = this:GetChecked();
			addonTable.UpdateAllNameplates(true);
		end);
		checkboxUseTargetAlphaIfNotTargetSelected:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].UseTargetAlphaIfNotTargetSelected);
		checkboxUseTargetAlphaIfNotTargetSelected:SetParent(alphaArea);
		checkboxUseTargetAlphaIfNotTargetSelected:SetPoint("TOPLEFT", alphaArea, "TOPLEFT", 10, -140);
		table_insert(GUIFrame.Categories[index], checkboxUseTargetAlphaIfNotTargetSelected);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkboxUseTargetAlphaIfNotTargetSelected:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].UseTargetAlphaIfNotTargetSelected);
		end);
	end

end

local function GUICategory_Dispel(index)
	local checkBoxDispellableSpells, dispellableSpellsBlacklist, addButton, editboxAddSpell, dropdownGlowType, controlArea, sizeArea, sliderDispelIconSizeHeight, sliderDispelIconSizeWidth;
	local dispellableSpellsBlacklistMenu = VGUI.CreateDropdownMenu();

	-- // checkBoxDispellableSpells
	do

		checkBoxDispellableSpells = VGUI.CreateCheckBox();
		checkBoxDispellableSpells:SetText(L["options:apps:dispellable-spells"]);
		checkBoxDispellableSpells:SetOnClickHandler(function(this)
			addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells = this:GetChecked();
			if (not addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells) then
				addonTable.UpdateAllNameplates(true);
				controlArea:Hide();
			else
				controlArea:Show();
			end
		end);
		checkBoxDispellableSpells:HookScript("OnShow", function() if (addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells) then controlArea:Show(); end end);
		checkBoxDispellableSpells:HookScript("OnHide", function() controlArea:Hide(); end);
		checkBoxDispellableSpells:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells);
		checkBoxDispellableSpells:SetParent(GUIFrame);
		checkBoxDispellableSpells:SetPoint("TOPLEFT", 160, -20);
		VGUI.SetTooltip(checkBoxDispellableSpells, L["options:apps:dispellable-spells:tooltip"]);
		table_insert(GUIFrame.Categories[index], checkBoxDispellableSpells);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			checkBoxDispellableSpells:SetChecked(addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells);
		end);

	end

	-- controlArea
	do
		controlArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		controlArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		controlArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		controlArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		controlArea:SetPoint("TOPLEFT", GUIFrame.ControlsFrame, "TOPLEFT", 0, -30);
		controlArea:SetPoint("RIGHT", GUIFrame.ControlsFrame, "RIGHT", -5, 0);
		controlArea:SetHeight(160);
		controlArea:Hide();
	end

	-- // sizeArea
	do

		sizeArea = CreateFrame("Frame", nil, controlArea, BackdropTemplateMixin and "BackdropTemplate");
		sizeArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		sizeArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		sizeArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		sizeArea:SetPoint("TOPLEFT", controlArea, "TOPLEFT", 10, -10);
		sizeArea:SetPoint("RIGHT", controlArea, "RIGHT", -10, 0);
		sizeArea:SetHeight(80);

	end

	-- // sliderDispelIconSizeWidth
	do

		sliderDispelIconSizeWidth = VGUI.CreateSlider();
		sliderDispelIconSizeWidth:Show();
		sliderDispelIconSizeWidth:SetParent(sizeArea);
		sliderDispelIconSizeWidth:SetWidth((sizeArea:GetWidth() - 20 - 10)/2);
		sliderDispelIconSizeWidth:ClearAllPoints();
		sliderDispelIconSizeWidth:SetPoint("LEFT", sizeArea, "LEFT", 10, 0);
		sliderDispelIconSizeWidth.label:ClearAllPoints();
		sliderDispelIconSizeWidth.label:SetPoint("CENTER", sliderDispelIconSizeWidth, "CENTER", 0, 15);
		sliderDispelIconSizeWidth.label:SetText(L["options:spells:icon-width"]);
		sliderDispelIconSizeWidth.slider:ClearAllPoints();
		sliderDispelIconSizeWidth.slider:SetPoint("LEFT", 3, 0)
		sliderDispelIconSizeWidth.slider:SetPoint("RIGHT", -3, 0)
		sliderDispelIconSizeWidth.slider:SetValueStep(1);
		sliderDispelIconSizeWidth.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderDispelIconSizeWidth.slider:SetScript("OnValueChanged", function(_, value)
			sliderDispelIconSizeWidth.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderDispelIconSizeWidth.editbox:SetScript("OnEnterPressed", function()
			if (sliderDispelIconSizeWidth.editbox:GetText() ~= "") then
				local v = tonumber(sliderDispelIconSizeWidth.editbox:GetText());
				if (v == nil) then
					sliderDispelIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderDispelIconSizeWidth.slider:SetValue(v);
				end
				sliderDispelIconSizeWidth.editbox:ClearFocus();
			end
		end);
		sliderDispelIconSizeWidth.lowtext:SetText("1");
		sliderDispelIconSizeWidth.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		sliderDispelIconSizeWidth.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth);
		sliderDispelIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderDispelIconSizeWidth.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth);
			sliderDispelIconSizeWidth.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeWidth));
		end);

	end

	-- // sliderDispelIconSizeHeight
	do

		sliderDispelIconSizeHeight = VGUI.CreateSlider();
		sliderDispelIconSizeHeight:Show();
		sliderDispelIconSizeHeight:SetParent(sizeArea);
		sliderDispelIconSizeHeight:SetWidth((sizeArea:GetWidth() - 20 - 10)/2);
		sliderDispelIconSizeHeight:ClearAllPoints();
		sliderDispelIconSizeHeight:SetPoint("LEFT", sliderDispelIconSizeWidth, "RIGHT", 10, 0);
		sliderDispelIconSizeHeight.label:ClearAllPoints();
		sliderDispelIconSizeHeight.label:SetPoint("CENTER", sliderDispelIconSizeHeight, "CENTER", 0, 15);
		sliderDispelIconSizeHeight.label:SetText(L["options:spells:icon-height"]);
		sliderDispelIconSizeHeight.slider:ClearAllPoints();
		sliderDispelIconSizeHeight.slider:SetPoint("LEFT", 3, 0)
		sliderDispelIconSizeHeight.slider:SetPoint("RIGHT", -3, 0)
		sliderDispelIconSizeHeight.slider:SetValueStep(1);
		sliderDispelIconSizeHeight.slider:SetMinMaxValues(1, addonTable.MAX_AURA_ICON_SIZE);
		sliderDispelIconSizeHeight.slider:SetScript("OnValueChanged", function(_, value)
			sliderDispelIconSizeHeight.editbox:SetText(tostring(math_ceil(value)));
			addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight = math_ceil(value);
			addonTable.UpdateAllNameplates(false);
		end);
		sliderDispelIconSizeHeight.editbox:SetScript("OnEnterPressed", function()
			if (sliderDispelIconSizeHeight.editbox:GetText() ~= "") then
				local v = tonumber(sliderDispelIconSizeHeight.editbox:GetText());
				if (v == nil) then
					sliderDispelIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight));
					Print(L["Value must be a number"]);
				else
					if (v > addonTable.MAX_AURA_ICON_SIZE) then
						v = addonTable.MAX_AURA_ICON_SIZE;
					end
					if (v < 1) then
						v = 1;
					end
					sliderDispelIconSizeHeight.slider:SetValue(v);
				end
				sliderDispelIconSizeHeight.editbox:ClearFocus();
			end
		end);
		sliderDispelIconSizeHeight.lowtext:SetText("1");
		sliderDispelIconSizeHeight.hightext:SetText(tostring(addonTable.MAX_AURA_ICON_SIZE));
		sliderDispelIconSizeHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight);
		sliderDispelIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight));
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			sliderDispelIconSizeHeight.slider:SetValue(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight);
			sliderDispelIconSizeHeight.editbox:SetText(tostring(addonTable.db.IconGroups[CurrentIconGroup].DispelIconSizeHeight));
		end);

	end

	-- // dropdownGlowType
	do
		local glowTypes = {
			[addonTable.GLOW_TYPE_NONE] = L["options:glow-type:GLOW_TYPE_NONE"],
			[addonTable.GLOW_TYPE_ACTIONBUTTON] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON"],
			[addonTable.GLOW_TYPE_AUTOUSE] = L["options:glow-type:GLOW_TYPE_AUTOUSE"],
			[addonTable.GLOW_TYPE_PIXEL] = L["options:glow-type:GLOW_TYPE_PIXEL"],
			[addonTable.GLOW_TYPE_ACTIONBUTTON_DIM] = L["options:glow-type:GLOW_TYPE_ACTIONBUTTON_DIM"],
		};

		dropdownGlowType = CreateFrame("Frame", "NAurasGUI.Dispel.dropdownGlowType", controlArea, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownGlowType, 170);
		dropdownGlowType:SetPoint("TOPLEFT", sizeArea, "BOTTOMLEFT", -10, -20);
		local info = {};
		dropdownGlowType.initialize = function()
			wipe(info);
			for glowType, glowTypeLocalized in pairs(glowTypes) do
				info.text = glowTypeLocalized;
				info.value = glowType;
				info.func = function(self)
					addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_GlowType = self.value;
					_G[dropdownGlowType:GetName() .. "Text"]:SetText(self:GetText());
					addonTable.UpdateAllNameplates(true);
				end
				info.checked = glowType == addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_GlowType;
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownGlowType:GetName() .. "Text"]:SetText(glowTypes[addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_GlowType]);
		dropdownGlowType.text = dropdownGlowType:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownGlowType.text:SetPoint("LEFT", 20, 20);
		dropdownGlowType.text:SetText(L["options:glow-type"]);
		table_insert(GUIFrame.OnDBChangedHandlers, function()
			_G[dropdownGlowType:GetName() .. "Text"]:SetText(glowTypes[addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_GlowType]);
		end);

	end

	-- // dispellableSpellsBlacklist
	do
		dispellableSpellsBlacklist = VGUI.CreateButton();
		dispellableSpellsBlacklist:SetParent(controlArea);
		dispellableSpellsBlacklist:SetText(L["options:apps:dispellable-spells:black-list-button"]);
		dispellableSpellsBlacklist:SetWidth(controlArea:GetWidth());
		dispellableSpellsBlacklist:SetHeight(24);
		dispellableSpellsBlacklist:SetPoint("TOP", controlArea, "BOTTOM", 0, -10);
		dispellableSpellsBlacklist:SetScript("OnClick", function(button)
			if (dispellableSpellsBlacklistMenu:IsShown()) then
				dispellableSpellsBlacklistMenu:Hide();
			else
				local t = { };
				for spellName in pairs(addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_Blacklist) do
					table_insert(t, {
						text = spellName,
						icon = AllSpellIDsAndIconsByName[spellName] ~= nil and SpellTextureByID[next(AllSpellIDsAndIconsByName[spellName])] or 136243,
						onCloseButtonClick = function()
							addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_Blacklist[spellName] = nil;
							-- close and then open list again
							dispellableSpellsBlacklist:Click(); dispellableSpellsBlacklist:Click();
						end,
					});
				end
				table_sort(t, function(item1, item2) return item1.text < item2.text end);
				dispellableSpellsBlacklistMenu:SetList(t);
				dispellableSpellsBlacklistMenu:SetParent(button);
				dispellableSpellsBlacklistMenu:Show();
				dispellableSpellsBlacklistMenu.searchBox:SetFocus();
				dispellableSpellsBlacklistMenu.searchBox:SetText("");
			end
		end);
		dispellableSpellsBlacklist:SetScript("OnHide", function() dispellableSpellsBlacklistMenu:Hide(); end);
		dispellableSpellsBlacklist:Disable();
		hooksecurefunc(addonTable, "OnSpellInfoCachesReady", function() dispellableSpellsBlacklist:Enable(); end);
		GUIFrame:HookScript("OnHide", function() dispellableSpellsBlacklist:Disable(); end);
	end

	-- addButton
	do
		addButton = VGUI.CreateButton();
		addButton:SetParent(dispellableSpellsBlacklistMenu);
		addButton:SetText(L["Add spell"]);
		addButton:SetWidth(dispellableSpellsBlacklistMenu:GetWidth() / 3);
		addButton:SetHeight(24);
		addButton:SetPoint("TOPRIGHT", dispellableSpellsBlacklistMenu, "BOTTOMRIGHT", 0, -8);
		addButton:SetScript("OnClick", function()
			local text = editboxAddSpell:GetText();
			if (text ~= nil and text ~= "") then
				local spellExist = false;
				if (AllSpellIDsAndIconsByName[text]) then
					spellExist = true;
				else
					for _spellName in pairs(AllSpellIDsAndIconsByName) do
						if (string_lower(_spellName) == string_lower(text)) then
							text = _spellName;
							spellExist = true;
							break;
						end
					end
				end
				if (not spellExist) then
					msg(L["Spell seems to be nonexistent"]);
				else
					addonTable.db.IconGroups[CurrentIconGroup].Additions_DispellableSpells_Blacklist[text] = true;
					addonTable.UpdateAllNameplates(false);
					-- close and then open list again
					dispellableSpellsBlacklist:Click(); dispellableSpellsBlacklist:Click();
				end
			end
			editboxAddSpell:SetText("");
		end);
	end

	-- editboxAddSpell
	do
		editboxAddSpell = CreateFrame("EditBox", nil, dispellableSpellsBlacklistMenu, "InputBoxTemplate");
		editboxAddSpell:SetAutoFocus(false);
		editboxAddSpell:SetFontObject(GameFontHighlightSmall);
		editboxAddSpell:SetHeight(20);
		editboxAddSpell:SetWidth(dispellableSpellsBlacklistMenu:GetWidth() - addButton:GetWidth() - 10);
		editboxAddSpell:SetPoint("BOTTOMRIGHT", addButton, "BOTTOMLEFT", -5, 2);
		editboxAddSpell:SetJustifyH("LEFT");
		editboxAddSpell:EnableMouse(true);
		editboxAddSpell:SetScript("OnEscapePressed", function() editboxAddSpell:ClearFocus(); end);
		editboxAddSpell:SetScript("OnEnterPressed", function() addButton:Click(); end);
		local text = editboxAddSpell:CreateFontString(nil, "ARTWORK", "GameFontDisableTiny");
		text:SetPoint("LEFT", 0, 0);
		text:SetText(L["options:spells:add-new-spell"]);
		editboxAddSpell:SetScript("OnEditFocusGained", function() text:Hide(); end);
		editboxAddSpell:SetScript("OnEditFocusLost", function() text:Show(); end);
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			if (editboxAddSpell:IsVisible() and editboxAddSpell:HasFocus() and link ~= nil) then
				local spellName = string.match(link, "%[\"?(.-)\"?%]");
				if (spellName ~= nil) then
					editboxAddSpell:SetText(spellName);
					editboxAddSpell:ClearFocus();
					return true;
				end
			end
		end);
	end

	-- dispellableSpellsBlacklistMenu
	do
		dispellableSpellsBlacklistMenu.Background = dispellableSpellsBlacklistMenu:CreateTexture(nil, "BORDER");
		dispellableSpellsBlacklistMenu.Background:SetPoint("TOPLEFT", dispellableSpellsBlacklistMenu, "TOPLEFT", -2, 2);
		dispellableSpellsBlacklistMenu.Background:SetPoint("BOTTOMRIGHT", addButton, "BOTTOMRIGHT",  2, -2);
		dispellableSpellsBlacklistMenu.Background:SetColorTexture(1, 0.3, 0.3, 1);
		dispellableSpellsBlacklistMenu.Border = dispellableSpellsBlacklistMenu:CreateTexture(nil, "BACKGROUND");
		dispellableSpellsBlacklistMenu.Border:SetPoint("TOPLEFT", dispellableSpellsBlacklistMenu, "TOPLEFT", -3, 3);
		dispellableSpellsBlacklistMenu.Border:SetPoint("BOTTOMRIGHT", addButton, "BOTTOMRIGHT",  3, -3);
		dispellableSpellsBlacklistMenu.Border:SetColorTexture(0.1, 0.1, 0.1, 1);
		dispellableSpellsBlacklistMenu:ClearAllPoints();
		dispellableSpellsBlacklistMenu:SetPoint("TOPLEFT", dispellableSpellsBlacklist, "TOPRIGHT", 5, 0);
	end

end

local function GUICategory_IconGroups(_index)
	local description, controlArea, editboxAddIconGroup, dropdownIconGroups, btnRemoveIconGroup;

	local function OnIconGroupsChanged()
		addonTable.OnIconGroupChanged();
		dropdownIconGroups.Reinitialize();
		UIDropDownMenu_SetText(dropdownIconGroups, "");
		if (#addonTable.db.IconGroups <= 1) then
			btnRemoveIconGroup:Disable();
		else
			btnRemoveIconGroup:Enable();
		end
	end

	-- description
	do
		description = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		description:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		description:SetBackdropColor(0.1, 0.1, 0.2, 1);
		description:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		description:SetPoint("TOPLEFT", 150, -12);
		description:SetPoint("TOPRIGHT", -12, -12);
		description:SetHeight(160);
		description:Show();

		local text = description:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		text:SetJustifyH("CENTER");
		text:SetPoint("TOPLEFT", description, "TOPLEFT", 10, -10);
		text:SetPoint("TOPRIGHT", description, "TOPRIGHT", -10, -10);
		text:SetText(L["options:icon-groups:description"]);

		table_insert(GUIFrame.Categories[_index], description);
	end

	-- controlArea
	do
		controlArea = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
		controlArea:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		controlArea:SetBackdropColor(0.1, 0.1, 0.2, 1);
		controlArea:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		controlArea:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10);
		controlArea:SetPoint("TOPRIGHT", description, "BOTTOMRIGHT", 0, -10);
		controlArea:SetHeight(160);
		controlArea:Show();
		table_insert(GUIFrame.Categories[_index], controlArea);
	end

	-- // editboxAddIconGroup
	do
		
		local overlayText;

		editboxAddIconGroup = CreateFrame("EditBox", nil, controlArea, BackdropTemplateMixin and "BackdropTemplate");
		editboxAddIconGroup:SetAutoFocus(false);
		editboxAddIconGroup:SetFontObject(GameFontHighlightSmall);
		editboxAddIconGroup:SetPoint("TOPLEFT", controlArea, "TOPLEFT", 10, -10);
		editboxAddIconGroup:SetPoint("TOPRIGHT", controlArea, "TOPRIGHT", -10, -10);
		editboxAddIconGroup:SetHeight(20);
		editboxAddIconGroup:SetJustifyH("LEFT");
		editboxAddIconGroup:EnableMouse(true);
		editboxAddIconGroup:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
			tile = true, edgeSize = 1, tileSize = 5,
		});
		editboxAddIconGroup:SetBackdropColor(0, 0, 0, 0.5);
		editboxAddIconGroup:SetBackdropBorderColor(0.3, 0.3, 0.30, 0.80);
		editboxAddIconGroup:SetScript("OnEscapePressed", function() editboxAddIconGroup:ClearFocus(); end);
		editboxAddIconGroup:SetScript("OnEnterPressed", function(self)
			local text = self:GetText();
			if (text ~= nil and text ~= "") then
				local newIg = addonTable.deepcopy(addonTable.db.IconGroups[CurrentIconGroup]);
				newIg.IconGroupName = text;
				table.insert(addonTable.db.IconGroups, newIg);
				CurrentIconGroup = #addonTable.db.IconGroups;
				OnIconGroupsChanged();
				self:SetText("");
			end
			self:ClearFocus();
			overlayText:Show();
		end);

		overlayText = editboxAddIconGroup:CreateFontString(nil, "ARTWORK", "GameFontDisable");
		overlayText:SetPoint("LEFT", 5, 0);
		overlayText:SetText(L["options:icon-groups:editbox-add-text"]);
		editboxAddIconGroup:SetScript("OnEditFocusGained", function() overlayText:Hide(); end);
		editboxAddIconGroup:SetScript("OnEditFocusLost", function()
			local text = editboxAddIconGroup:GetText();
			if (text == nil or text == "") then
				overlayText:Show();
			end
		end);

	end

	-- // dropdownIconGroups
	do

		local function initialize(_self, _level, _menuList)
			local info = UIDropDownMenu_CreateInfo();
			for index, igData in pairs(addonTable.db.IconGroups) do
				info.text = igData.IconGroupName;
				info.value = index;
				info.checked = false;
				info.func = function(_self)
					--UIDropDownMenu_SetText(dropdownIconGroups, addonTable.db.IconGroups[_self.value].IconGroupName);
					UIDropDownMenu_SetSelectedValue(dropdownIconGroups, _self.value);
				end
				UIDropDownMenu_AddButton(info);
			end
		end

		dropdownIconGroups = CreateFrame("Frame", "NAuras.GUIFrame.IconGroups.DropdownIconGroups", controlArea, "UIDropDownMenuTemplate");
		dropdownIconGroups:SetPoint("TOPLEFT", controlArea, "TOPLEFT", -5, -70);
		dropdownIconGroups.Reinitialize = function()
			UIDropDownMenu_Initialize(dropdownIconGroups, initialize);
		end

		UIDropDownMenu_Initialize(dropdownIconGroups, initialize);
		UIDropDownMenu_SetWidth(dropdownIconGroups, 130);
		UIDropDownMenu_SetText(dropdownIconGroups, "");

		dropdownIconGroups.text = dropdownIconGroups:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		dropdownIconGroups.text:SetPoint("BOTTOMLEFT", dropdownIconGroups, "TOPLEFT", 20, 0);
		dropdownIconGroups.text:SetText(L["options:icon-groups:dropdown-list"]);

	end

	-- btnRemoveIconGroup
	do
		btnRemoveIconGroup = VGUI.CreateButton();
		btnRemoveIconGroup:SetParent(controlArea);
		btnRemoveIconGroup:SetText(L["options:icon-groups:remove"]);
		btnRemoveIconGroup:SetWidth(75);
		btnRemoveIconGroup:SetHeight(24);
		btnRemoveIconGroup:SetPoint("LEFT", dropdownIconGroups, "RIGHT", 0, 2);
		btnRemoveIconGroup:SetScript("OnClick", function()
			local igIndex = UIDropDownMenu_GetSelectedValue(dropdownIconGroups);
			if (igIndex == nil or #addonTable.db.IconGroups < igIndex) then
				return;
			end
			if (CurrentIconGroup >= igIndex) then
				CurrentIconGroup = 1;
			end
			addonTable.array_delete_and_shift(addonTable.db.IconGroups, igIndex);
			
			for _index, spellData in pairs(addonTable.db.CustomSpells2) do
				addonTable.array_delete_and_shift(spellData.iconGroups, igIndex);
			end
			_G[addonTable.GuiSpellsDropdownIconGroups].Reinitialize();

			OnIconGroupsChanged();
		end);

		if (#addonTable.db.IconGroups <= 1) then
			btnRemoveIconGroup:Disable();
		else
			btnRemoveIconGroup:Enable();
		end
	end

end

local function DeleteUnexistantSpells()
    local db = addonTable.db;
	for index, spellInfo in pairs(db.CustomSpells2) do
		if (AllSpellIDsAndIconsByName[spellInfo.spellName] == nil) then
			addonTable.Print(("Spell with name '%s' is not found (deleted from game?)"):format(spellInfo.spellName));
			db.CustomSpells2[index] = nil;
			addonTable.RebuildSpellCache();
		end
	end
end

local function InitializeGUI_CreateSpellInfoCaches()
	GUIFrame:HookScript("OnShow", function()
		local scanAllSpells = coroutine.create(function()
			local misses = 0;
			local id = 0;
			while (misses < 400) do
				id = id + 1;
				local name, _, icon = GetSpellInfo(id);
				if (icon == 136243) then -- 136243 is the a gear icon
					misses = 0;
				elseif (name and name ~= "") then
					misses = 0;
					if (AllSpellIDsAndIconsByName[name] == nil) then AllSpellIDsAndIconsByName[name] = { }; end
					AllSpellIDsAndIconsByName[name][id] = icon;
				else
					misses = misses + 1;
				end
				coroutine.yield();
			end
			DeleteUnexistantSpells();
			addonTable.OnSpellInfoCachesReady();
		end);
		CoroutineProcessor:Queue("scanAllSpells", scanAllSpells);
	end);
	GUIFrame:HookScript("OnHide", function()
		CoroutineProcessor:DeleteFromQueue("scanAllSpells");
		wipe(AllSpellIDsAndIconsByName);
	end);
end

local function InitializeGUI()
	GUIFrame = CreateFrame("Frame", "NAuras.GUIFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate");
	GUIFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
	GUIFrame:SetScript("OnEvent", function(self, event)
		if (event == "PLAYER_REGEN_DISABLED") then
			if (self:IsVisible()) then
				self:Hide();
				self:RegisterEvent("PLAYER_REGEN_ENABLED");
			end
		elseif (event == "PLAYER_REGEN_ENABLED") then
			self:UnregisterEvent("PLAYER_REGEN_ENABLED");
			self:Show();
		end
	end);
	GUIFrame:SetHeight(445);
	GUIFrame:SetWidth(530*1.3+20);
	GUIFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80);
	GUIFrame:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = 1,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	});
	GUIFrame:SetBackdropColor(0.25, 0.24, 0.32, 1);
	GUIFrame:SetBackdropBorderColor(0.1,0.1,0.1,1);
	GUIFrame:EnableMouse(1);
	GUIFrame:SetMovable(1);
	GUIFrame:SetFrameStrata("DIALOG");
	GUIFrame:SetToplevel(1);
	GUIFrame:SetClampedToScreen(1);
	GUIFrame:SetScript("OnMouseDown", function() GUIFrame:StartMoving(); end);
	GUIFrame:SetScript("OnMouseUp", function() GUIFrame:StopMovingOrSizing(); end);
	GUIFrame:Hide();

	GUIFrame.CategoryButtons = {};
	GUIFrame.ActiveCategory = 1;

	local header = GUIFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	header:SetFont(GameFontNormal:GetFont(), 22, "THICKOUTLINE");
	header:SetPoint("BOTTOM", GUIFrame, "TOP", 0, 0);
	header:SetJustifyH("CENTER");
	header:SetText("NameplateAuras");

	GUIFrame.outline = CreateFrame("Frame", nil, GUIFrame, BackdropTemplateMixin and "BackdropTemplate");
	GUIFrame.outline:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = 1,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	});
	GUIFrame.outline:SetBackdropColor(0.1, 0.1, 0.2, 1);
	GUIFrame.outline:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
	GUIFrame.outline:SetPoint("TOPLEFT", 12, -12);
	GUIFrame.outline:SetPoint("BOTTOMLEFT", 12, 12);
	GUIFrame.outline:SetWidth(130);

	GUIFrame.ControlsFrame = CreateFrame("Frame", nil, GUIFrame);
	GUIFrame.ControlsFrame:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 12, 0);
	GUIFrame.ControlsFrame:SetPoint("BOTTOMRIGHT", GUIFrame, "BOTTOMRIGHT", -12, 12);
	GUIFrame.ControlsFrame:Hide();

	local closeButton = VGUI.CreateButton();
	closeButton:SetParent(GUIFrame);
	closeButton:SetText("Close");
	closeButton:SetWidth(60);
	closeButton:SetHeight(20);
	closeButton:SetPoint("BOTTOMRIGHT", GUIFrame, "TOPRIGHT", -4, 0);
	closeButton:SetScript("OnClick", function() GUIFrame:Hide(); end);

	GUIFrame.Categories = {};
	GUIFrame.OnDBChangedHandlers = {};
	table_insert(GUIFrame.OnDBChangedHandlers, function() OnGUICategoryClick(GUIFrame.CategoryButtons[1]); end);

	local categories = { L["General"], L["options:category:size-and-position"], L["options:category:alpha"], L["Timer text"], L["Stack text"],
		L["Icon borders"], L["Spells"], L["options:category:interrupts"], L["options:category:dispel"], L["options:category:apps"], L["options:category:icon-groups"] };
	for index, value in pairs(categories) do
		local b = CreateGUICategory();
		b.index = index;
		b.text:SetText(value);
		if (index == 1) then
			b:LockHighlight();
			b.text:SetTextColor(1, 1, 1);
			b:SetPoint("TOPLEFT", GUIFrame.outline, "TOPLEFT", 5, -6);
		elseif (value == L["options:category:icon-groups"]) then
			b:SetPoint("TOPLEFT",GUIFrame.outline,"TOPLEFT", 5, -18 * (index - 1) - 46);
		elseif (index >= #categories - 4) then
			b:SetPoint("TOPLEFT",GUIFrame.outline,"TOPLEFT", 5, -18 * (index - 1) - 26);
		else
			b:SetPoint("TOPLEFT",GUIFrame.outline,"TOPLEFT", 5, -18 * (index - 1) - 6);
		end

		GUIFrame.Categories[index] = {};

		if (value == L["General"]) then
			GUICategory_1(index);
		elseif (value == L["Timer text"]) then
			GUICategory_Fonts(index);
		elseif (value == L["Stack text"]) then
			GUICategory_AuraStackFont(index);
		elseif (value == L["Icon borders"]) then
			GUICategory_Borders(index);
		elseif (value == L["Spells"]) then
			GUICategory_4(index);
		elseif (value == L["options:category:interrupts"]) then
			GUICategory_Interrupts(index);
		elseif (value == L["options:category:apps"]) then
			GUICategory_Additions(index);
		elseif (value == L["options:category:size-and-position"]) then
			GUICategory_SizeAndPosition(index);
		elseif (value == L["options:category:dispel"]) then
			GUICategory_Dispel(index);
		elseif (value == L["options:category:alpha"]) then
			GUICategory_Alpha(index);
		elseif (value == L["options:category:icon-groups"]) then
			GUICategory_IconGroups(index);
		end
	end

	local buttonTestMode;
	do
		buttonTestMode = VGUI.CreateButton();
		buttonTestMode:SetParent(GUIFrame.outline);
		buttonTestMode:SetText(L["options:general:test-mode"]);
		buttonTestMode:SetPoint("BOTTOMLEFT", GUIFrame.outline, "BOTTOMLEFT", 4, 4);
		buttonTestMode:SetPoint("BOTTOMRIGHT", GUIFrame.outline, "BOTTOMRIGHT", -4, 4);
		buttonTestMode:SetHeight(30);
		buttonTestMode:SetScript("OnClick", addonTable.SwitchTestMode);
	end

	local profilesButton;
	do
		profilesButton = VGUI.CreateButton();
		profilesButton:SetParent(GUIFrame.outline);
		profilesButton:SetText(L["Profiles"]);
		profilesButton:SetHeight(30);
		profilesButton:SetPoint("BOTTOMLEFT", buttonTestMode, "TOPLEFT", 0, 10);
		profilesButton:SetPoint("BOTTOMRIGHT", buttonTestMode, "TOPRIGHT", 0, 10);
		profilesButton:SetScript("OnClick", function()
			LibStub("AceConfigDialog-3.0"):Open("NameplateAuras.profiles");
			GUIFrame:Hide();
		end);
	end

	local profileImportExportWindow = VGUI.CreateLuaEditor();
	local profileImportButton;
	do
		profileImportButton = VGUI.CreateButton();
		profileImportButton:SetParent(GUIFrame.outline);
		profileImportButton:SetText(L["options:general:import-profile"]);
		profileImportButton:SetHeight(20);
		profileImportButton:SetPoint("BOTTOMLEFT", profilesButton, "TOPLEFT", 0, 0);
		profileImportButton:SetPoint("BOTTOMRIGHT", profilesButton, "TOPRIGHT", 0, 0);
		profileImportButton:SetScript("OnClick", function()
			profileImportExportWindow:Hide();
			profileImportExportWindow:SetHeaderText("Import profile");
			profileImportExportWindow:SetText("");
			profileImportExportWindow:SetAcceptButton(true, function(self)
				local decoded = LibDeflate:DecodeForPrint(self:GetText());
				if (decoded == nil) then
					msg(L["Import data decoding error"]);
				end

				local decompressed = LibDeflate:DecompressDeflate(decoded);
				if (decompressed == nil) then
					msg(L["Import data decompressing error"]);
				end

				local success, deserialized = LibSerialize:Deserialize(decompressed);
				if (not success) then
					msg(L["Import data deserialization error"]);
				end

				for key, value in pairs(deserialized) do
					addonTable.db[key] = value;
				end
				for key, value in pairs(addonTable.db) do
					if (deserialized[key] == nil) then
						addonTable.db[key] = nil;
					end
				end

				addonTable.ReloadDB();
				addonTable.RebuildSpellCache();
				addonTable.OnIconGroupChanged();
			end);
			profileImportExportWindow:Show();
		end);
	end

	local profileExportButton;
	do
		profileExportButton = VGUI.CreateButton();
		profileExportButton:SetParent(GUIFrame.outline);
		profileExportButton:SetText(L["options:general:export-profile"]);
		profileExportButton:SetHeight(20);
		profileExportButton:SetPoint("BOTTOMLEFT", profileImportButton, "TOPLEFT", 0, 0);
		profileExportButton:SetPoint("BOTTOMRIGHT", profileImportButton, "TOPRIGHT", 0, 0);
		profileExportButton:SetScript("OnClick", function()
			local data = addonTable.db;
			local serialized = LibSerialize:Serialize(data);
			local compressed = LibDeflate:CompressDeflate(serialized);
			local encoded = LibDeflate:EncodeForPrint(compressed);

			profileImportExportWindow:Hide();
			profileImportExportWindow:SetHeaderText("Export profile");
			profileImportExportWindow:SetText(encoded);
			profileImportExportWindow:SetAcceptButton(false, nil);
			profileImportExportWindow:Show();
		end);
	end

	-- IconGroupsList
	do
		local function initialize(_self, _level, _menuList)
			local info = UIDropDownMenu_CreateInfo();
			for index, igData in pairs(addonTable.db.IconGroups) do
				info.text = igData.IconGroupName;
				info.value = index;
				info.func = function(_self)
					CurrentIconGroup = _self.value;
					addonTable.OnIconGroupChanged();
				end
				info.checked = function(_self)
					return CurrentIconGroup == _self.value;
				end
				UIDropDownMenu_AddButton(info);
			end
		end

		IconGroupsList = CreateFrame("Frame", "NAuras.GUIFrame.IconGroupsList", GUIFrame, "UIDropDownMenuTemplate");
		IconGroupsList:SetPoint("BOTTOMLEFT", GUIFrame, "TOPLEFT", -13, -5);
		IconGroupsList.Reinitialize = function()
			UIDropDownMenu_Initialize(IconGroupsList, initialize);
		end

		IconGroupsList.text = IconGroupsList:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		IconGroupsList.text:SetPoint("BOTTOMLEFT", IconGroupsList, "TOPLEFT", 20, 0);
		IconGroupsList.text:SetText(L["options:general:current-icon-group"]);

		UIDropDownMenu_Initialize(IconGroupsList, initialize);
		UIDropDownMenu_SetWidth(IconGroupsList, 130);
		UIDropDownMenu_SetText(IconGroupsList, addonTable.db.IconGroups[CurrentIconGroup].IconGroupName);
	end

	InitializeGUI_CreateSpellInfoCaches();
	addonTable.GUIFrame = GUIFrame;
end

function addonTable.ShowGUI()
	if (not InCombatLockdown()) then
		if (not GUIFrame) then
			InitializeGUI();
		end
		GUIFrame:Show();
		OnGUICategoryClick(GUIFrame.CategoryButtons[1]);
	else
		Print(L["Options are not available in combat!"]);
	end
end

local LDB = LibStub("LibDataBroker-1.1");
if (LDB ~= nil) then
	local plugin = LDB:NewDataObject(addonName,
		{
			type = "data source",
			text = "",
			icon = [[Interface\AddOns\NameplateAuras\media\broker_logo.tga]],
			tocname = addonName,
		}
	);
	plugin.OnClick = function(_, button)
		if (button == "LeftButton") then
			if (GUIFrame ~= nil and GUIFrame:IsShown()) then
				GUIFrame:Hide();
			else
				addonTable.ShowGUI();
			end
		elseif (button == "RightButton") then
			addonTable.SwitchTestMode();
		end
	end
	plugin.OnTooltipShow = function(tooltip)
		tooltip:AddLine(addonName);
		tooltip:AddLine(" ");
		tooltip:AddLine("|cffeda55fLeftClick:|r open options window");
		tooltip:AddLine("|cffeda55fRightClick:|r switch test mode");
	end
end
