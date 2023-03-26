-- Movement Recorder v1.2.1 by stacky and contributors

local printPrefix = "[Movement Recorder] "

-- GUI stuff

local refMenu = gui.Reference("Menu")
local refMisc = gui.Reference("Misc")
local settingTab = gui.Tab(refMisc, "movrec", "Movement Recorder")

local settingSettingsGroup = gui.Groupbox(settingTab, "Settings", 16, 16, 296, 0)
local settingEnable = gui.Checkbox(settingSettingsGroup, "settings.enable", "Enable", true)
local settingDrawIndicator = gui.Checkbox(settingSettingsGroup, "settings.drawindicator", "Draw Playback Indicator", true)
local settingColorIndicator = gui.ColorPicker(settingDrawIndicator, "color.indicator", "", 255, 255, 255, 255)
local settingColorArrowVisible = gui.ColorPicker(settingSettingsGroup, "color.arrow.visible", "Arrow Visible", 92, 92, 92, 192)
local settingColorArrowOccluded = gui.ColorPicker(settingSettingsGroup, "color.arrow.occluded", "Arrow Occluded", 92, 92, 92, 92)
local settingColorTextVisible = gui.ColorPicker(settingSettingsGroup, "color.text.visible", "Text Visible", 255, 255, 255, 255)
local settingColorTextOccluded = gui.ColorPicker(settingSettingsGroup, "color.text.occluded", "Text Occluded", 255, 255, 255, 64)
local settingArrowStyle = gui.Combobox(settingSettingsGroup, "settings.arrowstyle", "Arrow Style", "Outlined", "Filled")
settingArrowStyle:SetValue(1)
local settingFilter = gui.Multibox(settingSettingsGroup, "Filter")
local settingVisCheck = gui.Checkbox(settingFilter, "settings.filter.vischeck", "Visible", true)
local settingDistCheck = gui.Checkbox(settingFilter, "settings.filter.distcheck", "Nearby", true)

local settingLoadedGroup = gui.Groupbox(settingTab, "Loaded Recordings", 16, 400, 296, 0)
local settingLoaded = gui.Listbox(settingLoadedGroup, "recordings.loaded", 300)

local Delete = nil -- forward declaration
local settingDelete = gui.Button(settingLoadedGroup, "Delete", function()
	Delete()
end)
settingDelete:SetWidth(264)
settingDelete:SetHeight(28)

local Reload = nil -- forward declaration
local settingReload = gui.Button(settingLoadedGroup, "Reload", function()
	Reload()
end)
settingReload:SetWidth(264)
settingReload:SetHeight(28)

local settingRecordGroup = gui.Groupbox(settingTab, "Record", 328, 16, 296, 0)
local settingRecordKey = gui.Keybox(settingRecordGroup, "record.key", "Record Key", 0)
local settingRecordName = gui.Editbox(settingRecordGroup, "record.name", "Name")

local Save = nil -- forward declaration
local settingSave = gui.Button(settingRecordGroup, "Save", function()
	Save()
end)
settingSave:SetWidth(264)
settingSave:SetHeight(28)

local settingPlaybackGroup = gui.Groupbox(settingTab, "Playback", 328, 236, 296, 0)
local settingPlaybackKey = gui.Keybox(settingPlaybackGroup, "playback.key", "Playback Key", 0)
local settingAimSpeed = gui.Slider(settingPlaybackGroup, "playback.aimspeed", "Aim Speed", 2, 1, 10, 0.5)
local settingMaxDist = gui.Slider(settingPlaybackGroup, "playback.maxdist", "Max Distance", 300, 100, 500, 10)

local settingPlaybackSettingsGroup = gui.Multibox(settingPlaybackGroup, "Playback Settings")
local settingSwitchKnife = gui.Checkbox(settingPlaybackSettingsGroup, "playback.settings.switchknife", "Switch To Knife", true)
local settingSwitchBack = gui.Checkbox(settingPlaybackSettingsGroup, "playback.settings.switchback", "Switch Back", false)
local settingPSilent = gui.Checkbox(settingPlaybackSettingsGroup, "playback.settings.psilent", "Perfect Silent Angles", false)
local settingYawOnly = gui.Checkbox(settingPlaybackSettingsGroup, "playback.settings.yawonly", "Yaw Only", false)

-- if we draw dialog in the center of the screen it just gets covered by the menu
local dialog = gui.Window("movrec.dialog", GetScriptName(), 16, 50, 304, 150)
dialog:SetActive(false)

local dialogText = gui.Text(dialog, "")

local dialogYesFn = nil
local dialogYes = gui.Button(dialog, "YES", function()
	dialogYesFn()
	dialog:SetActive(false)
end)
dialogYes:SetHeight(28)
dialogYes:SetPosY(78)

local dialogNoFn = nil
local dialogNo = gui.Button(dialog, "NO", function()
	dialogNoFn()
	dialog:SetActive(false)
end)
dialogNo:SetHeight(28)
dialogNo:SetPosX(160)
dialogNo:SetPosY(78)

local function Dialog(text, fnYes, fnNo)
	local screenW, screenH = draw.GetScreenSize()
	dialog:SetPosX((screenW - 304) * 0.5)
	dialog:SetPosY(50)

	dialogText:SetText(text)
	dialogYesFn = fnYes
	dialogNoFn = fnNo

	dialog:SetActive(true)
end

-- end of GUI stuff

local recordTickViewanglesIndex = 1
local recordTickMovesIndex = recordTickViewanglesIndex + 3
local recordTickButtonsIndex = recordTickMovesIndex + 3
local recordTickOriginIndex = recordTickButtonsIndex + 1
local recordTickElementCount = recordTickOriginIndex + 3

-- recordings management stuff

local recordingsPaths = {}
local loadedRecordings = { {} }
local loadedRecordingsNames = { "local" }
local recordingsVisibility = {}

local lastVisCheckTime = -1.0

local fileExt = ".mr.dat" -- i've tried removing ".dat" but file.Enumerate won't pick it up
local fileExtEscaped = string.gsub(fileExt, "%.", "%%.")

local currentMap = engine.GetMapName()

local function EnumerateCallback(path)
	if string.find(path, fileExt .. "$") ~= nil then
		recordingsPaths[#recordingsPaths + 1] = path
	end
end

local function RefreshSaved()
	recordingsPaths = {}
	file.Enumerate(EnumerateCallback)
end

RefreshSaved()

local function LoadMapRecords()
	loadedRecordings = { {} }
	loadedRecordingsNames = { "local" }

	if currentMap == nil or currentMap == "" then
		return
	end

	for i = 1, #recordingsPaths do
		local recordingPath = recordingsPaths[i]
		local filenameNoExt = string.match(recordingPath, "/([^/]+)" .. fileExtEscaped .. "$")
		if filenameNoExt ~= nil and
			string.find(recordingPath, "/" .. currentMap .. "/", 1, true) ~= nil then

			local reader = file.Open(recordingPath, "r")
			local tbl = load("return " .. reader:Read(), nil, "t", {})()
			reader:Close()

			loadedRecordings[#loadedRecordings + 1] = tbl
			loadedRecordingsNames[#loadedRecordingsNames + 1] = filenameNoExt
		end
	end

	settingLoaded:SetOptions(unpack(loadedRecordingsNames, 2))
end

LoadMapRecords()

-- get recordings root folder name, which contains our map subfolders
local function GetRecordingsFolder()
	-- checl if we have found at least 1 recording
	if 0 < #recordingsPaths then
		-- check if loaded path has a subfolder
		local firstFolder = string.match(recordingsPaths[1], "^([^/]+)/.+/")
		if firstFolder ~= nil then
			-- assume it to be a root folder
			return firstFolder
		end
	end
	-- default recordings root folder name
	return "movement recordings"
end

local recordingsFolder = GetRecordingsFolder()

Reload = function()
	RefreshSaved()
	LoadMapRecords()
end

local saveName = nil
local saveOverwriteIndex = nil

local function SerializeRecording(recording)
	local result = "{\n"
	for i = 1, #recording do
		result = result .. "{\n"
		for j = 1, recordTickElementCount do
			if recording[i][j] ~= nil then
				local indexValue = string.format("%s[%d]=%.3f,\n", result, j, recording[i][j])
				-- remove trailing zeroes
				result = string.gsub(indexValue, "%.0+,", ",")
			end
		end
		result = result .. "},"
	end
	result = result .. "\n}"
	return result
end

local function SaveRecording()
	if saveName == nil then
		return
	end

	local path = recordingsFolder .. "/" .. currentMap .. "/" .. saveName .. fileExt

	local writer = file.Open(path, "w")
	writer:Write(SerializeRecording(loadedRecordings[1]))
	writer:Close()

	if saveOverwriteIndex ~= nil then
		loadedRecordings[saveOverwriteIndex] = loadedRecordings[1]
	else
		recordingsPaths[#recordingsPaths + 1] = path

		loadedRecordings[#loadedRecordings + 1] = loadedRecordings[1]

		loadedRecordingsNames[#loadedRecordingsNames + 1] = saveName
		settingLoaded:SetOptions(unpack(loadedRecordingsNames, 2))
	end

	loadedRecordings[1] = {}

	saveName = nil
	saveOverwriteIndex = nil
end

local function CancelSaving()
	saveName = nil
	saveOverwriteIndex = nil
end

Save = function()
	if #loadedRecordings[1] == 0 then
		print(printPrefix .. "Nothing to save")
		return
	end

	local name = settingRecordName:GetValue()
	if name == nil or name == "" then
		print(printPrefix .. "Invalid record name")
		return
	end

	if currentMap == nil or currentMap == "" then
		print(printPrefix .. "Invalid map name")
		return
	end

	-- remove bad characters from name
	saveName = string.gsub(name, "[%p%c.]", "")

	local fileExists = false

	for i = 2, #loadedRecordingsNames do
		if loadedRecordingsNames[i] == saveName then
			fileExists = true
			saveOverwriteIndex = i
			break
		end
	end

	if fileExists then
		Dialog("File named \"" .. saveName .. "\" already exists.\nAre you sure you want to overwrite it?",
			SaveRecording, CancelSaving)
	else
		SaveRecording()
	end
end

local deleteIndex = nil

local function DeleteRecording()
	if deleteIndex == nil then
		return
	end

	for i = 1, #recordingsPaths do
		local recordingPath = recordingsPaths[i]
		local recordingName = loadedRecordingsNames[deleteIndex]
		if string.find(recordingPath, "/" .. currentMap .. "/", 1, true) ~= nil and
			string.find(recordingPath, "/" .. recordingName .. fileExtEscaped .. "$") ~= nil then
			file.Delete(recordingPath)
			table.remove(recordingsPaths, i)
			break
		end
	end

	table.remove(loadedRecordings, deleteIndex)

	table.remove(loadedRecordingsNames, deleteIndex)
	settingLoaded:SetOptions(unpack(loadedRecordingsNames, 2))

	deleteIndex = nil
end

local function CancelDeletion()
	deleteIndex = nil
end

Delete = function()
	deleteIndex = settingLoaded:GetValue() + 2 -- +1 because local recording is at index 1

	Dialog("Are you sure you want to delete the recording?", DeleteRecording, CancelDeletion)
end

-- end of recordings management stuff

-- optimization stuff

-- locals are faster than globals
-- https://lua-users.org/wiki/OptimisingUsingLocalVariables
local math_fmod = math.fmod
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_abs = math.abs

local bit_band = bit.band
local bit_bnot = bit.bnot

-- end of optimization stuff

-- ffi stuff

ffi.cdef[[
	typedef int				HMODULE;
	typedef const char*		LPCSTR;
	typedef int (__stdcall* FARPROC)();

	HMODULE GetModuleHandleA(LPCSTR lpModuleName);
	FARPROC GetProcAddress(HMODULE hModule, LPCSTR lpProcName);

	typedef bool (__thiscall* ReturnBoolNoArgsFn)(void*);

	typedef void* (* CreateInterfaceFn)(const char* pName, int* pReturnCode);
]]

local function GetInterface(mod, interface)
    return ffi.cast("CreateInterfaceFn", ffi.C.GetProcAddress(ffi.C.GetModuleHandleA(mod), "CreateInterface"))(interface, nil)
end

local function GetVF(ppVT, type, index)
	return ffi.cast(type, ffi.cast("void***", ppVT)[0][index])
end

local EngineClient = GetInterface("engine.dll", "VEngineClient014")
local EngineClient__Con_IsVisible = GetVF(EngineClient, "ReturnBoolNoArgsFn", 11)

local function IsTyping()
	local cl_mouseenable = tonumber(client.GetConVar("cl_mouseenable"))
	return (cl_mouseenable == 0 or EngineClient__Con_IsVisible(EngineClient))
end

-- end of ffi stuff

local isRecording = false

local isPlayback = false
local playbackTicks = nil
local playbackIterator = nil
local playbackEndIndex = nil

local switchedFromWeaponID = 0
local originAtStart = false
local viewanglesAtStart = false

local fontStart = draw.CreateFont("Tahoma", 12, 800)
local fontIndicator = draw.CreateFont("Tahoma", 22, 800)

local cl_forwardspeed = tonumber(client.GetConVar("cl_forwardspeed"))
local cl_sidespeed = tonumber(client.GetConVar("cl_sidespeed"))
-- local cl_upspeed = tonumber(client.GetConVar("cl_upspeed"))

local IN_BULLRUSH = bit.lshift(1, 22)

local disableSettingsPrev = {}

local disableSettingsKV = {
	"misc.strafe.enable",				false,
	"misc.fakelag.enable",				false,
	"misc.duckjump",					false,
	"rbot.antiaim.base",				"-180.0 Backward",
	"rbot.antiaim.left", 				"90.0 Backward",
	"rbot.antiaim.right", 				"-90.0 Backward",
	"rbot.accuracy.movement.quickstop",	false,
	"lbot.antiaim.type",				"Off",
	"lbot.movement.quickstop", 			false,
}

local CONTENTS_SOLID = 0x1 -- an eye is never valid in a solid
local CONTENTS_OPAQUE = 0x80 -- things that cannot be seen through (may be non-solid though)
local CONTENTS_IGNORE_NODRAW_OPAQUE = 0x2000 -- ignore CONTENTS_OPAQUE on surfaces that have SURF_NODRAW
local CONTENTS_MOVEABLE = 0x4000 -- hits entities which are MOVETYPE_PUSH (doors, plats, etc.)

local MASK_OPAQUE = bit.bor(CONTENTS_SOLID, CONTENTS_MOVEABLE, CONTENTS_OPAQUE) -- everything that blocks lighting
local MASK_VISIBLE = bit.bor(MASK_OPAQUE, CONTENTS_IGNORE_NODRAW_OPAQUE) -- everything that blocks line of sight for players

local function clamp(val, min, max)
	if val > max then
		return max
	elseif val < min then
		return min
	else
		return val
	end
end

local function Vector2DRotate(point, degrees)
	local radians = math_rad(degrees)

	local c = math_cos(radians)
	local s = math_sin(radians)

	local out_x = point[1] * c - point[2] * s
	local out_y = point[1] * s + point[2] * c
	return out_x, out_y
end

local function AnglesNormalize(v)
	if v[1] > 89 then
		v[1] = 89
	elseif v[1] < -89 then
		v[1] = -89
	end

	if v[2] ~= v[2] or 1.e+5 < v[2] or v[2] < -1.e+5 then
		v[2] = 0
	else
		v[2] = vector.AngleNormalize(v[2])
	end

	v[3] = 0
	return v[1], v[2], v[3]
end

-- ensure that 0 <= angle <= 360
local function AngleNormalizePositive(angle)
	angle = math_fmod(angle, 360)

	if angle < 0 then
		angle = angle + 360
	end

	return angle
end

local function CorrectMovement(cmd, newYaw)
	local viewangles = engine.GetViewAngles()
	local delta = AngleNormalizePositive(viewangles["yaw"] - newYaw)

	local prevForward = cmd:GetForwardMove()
	local prevSide = cmd:GetSideMove()

	local forwardmove = math_cos(math_rad(delta)) * prevForward + math_cos(math_rad(delta + 90)) * prevSide
	local sidemove = math_sin(math_rad(delta)) * prevForward + math_sin(math_rad(delta + 90)) * prevSide

	cmd:SetForwardMove(clamp(forwardmove, -cl_forwardspeed, cl_forwardspeed))
	cmd:SetSideMove(clamp(sidemove, -cl_sidespeed, cl_sidespeed))
end

local function GetRecordTickViewangles(tick)
	return tick[recordTickViewanglesIndex],
		tick[recordTickViewanglesIndex + 1],
		0 -- tick[recordTickViewanglesIndex + 2] -- roll
end

local function GetRecordTickMoves(tick)
	return tick[recordTickMovesIndex],
		tick[recordTickMovesIndex + 1],
		0 -- tick[recordTickMovesIndex + 2] -- upmove
end

local function GetRecordTickButtons(tick)
	return tick[recordTickButtonsIndex]
end

local function GetRecordTickOrigin(tick)
	return tick[recordTickOriginIndex],
		tick[recordTickOriginIndex + 1],
		tick[recordTickOriginIndex + 2]
end

local function SetRecordTickOrigin(tick, vecOrigin)
	tick[recordTickOriginIndex] = vecOrigin["x"]
	tick[recordTickOriginIndex + 1] = vecOrigin["y"]
	tick[recordTickOriginIndex + 2] = vecOrigin["z"]
end

local function FindClosestRecording(localOrigin)
	local minDistance = settingMaxDist:GetValue()
	local closest = nil

	for i = 1, #loadedRecordings do
		local record = loadedRecordings[i]
		if record ~= nil and #record ~= 0 then
			local recordOrigin = { GetRecordTickOrigin(record[1]) }
			local dist = vector.Distance(
				{ localOrigin["x"], localOrigin["y"], localOrigin["z"] },
				recordOrigin
			)
			if dist < minDistance and math_abs(localOrigin["z"] - recordOrigin[3]) < 25 then
				minDistance = dist
				closest = record
			end
		end
	end

	return closest
end

local function CheckRecordingsVisibility(localOrigin, eyePos)
	recordingsVisibility = {}
	for i = 1, #loadedRecordings do
		local record = loadedRecordings[i]
		if record ~= nil and #record ~= 0 then
			local recordStart = Vector3(GetRecordTickOrigin(record[1]))

			if settingDistCheck:GetValue() then
				local dist = vector.Distance(localOrigin, recordStart)
				if dist >= settingMaxDist:GetValue() then
					goto continue
				end
			end

			local fract = engine.TraceLine(eyePos, recordStart, MASK_VISIBLE).fraction
			recordingsVisibility[i] = (fract == 1)
		end
		::continue::
	end
end

local function IsIdleRecordTick(tick)
	local tickMoves = { GetRecordTickMoves(tick) }
	local tickButtons = GetRecordTickButtons(tick)

	return (tickMoves[1] == 0 and
		tickMoves[2] == 0 and
		-- tickMoves[3] == 0 and -- upmove
		bit_band(tickButtons, bit_bnot(IN_BULLRUSH)) == 0)
end

local function FindNonIdleIndex(ticks, backwards)
	if ticks == nil then
		return nil
	end

	local from, to, step
	if backwards then
		from = #ticks
		to = 1
		step = -1
	else
		from = 1
		to = #ticks
		step = 1
	end

	for i = from, to, step do
		if not IsIdleRecordTick(ticks[i]) then
			return i
		end
	end

	return nil
end

-- disable settings that might interfere with our movement
local function DisableInterferingSettings()
	for i = 1, #disableSettingsKV, 2 do
		local key = disableSettingsKV[i]
		local value = disableSettingsKV[i + 1]
		disableSettingsPrev[i] = gui.GetValue(key)
		gui.SetValue(key, value)
	end
end

local function RestoreInterferingSettings()
	for i = 1, #disableSettingsKV, 2 do
		gui.SetValue(disableSettingsKV[i], disableSettingsPrev[i])
	end
end

local function DrawIndicator()
	local text = ""

	if isRecording then
		text = "RECORDING"
	elseif isPlayback then
		if not originAtStart then
			text = "GOING TO START POSITION"
		elseif not viewanglesAtStart then
			text = "SETTING START ANGLE"
		else
			text = "PLAYBACK"
		end
	end

	draw.Color(settingColorIndicator:GetValue())
	draw.SetFont(fontIndicator)

	local screenW, screenH = draw.GetScreenSize()
	local textW, textH = draw.GetTextSize(text)
	local x = ((screenW - textW) * 0.5)

	draw.TextShadow(x, 100, text)
end

local function DrawStart(localOrigin, ticks, name, arrowColor, textColor)
	local startOrigin = { GetRecordTickOrigin(ticks[1]) }

	local dist = vector.Distance(
		{ localOrigin["x"], localOrigin["y"], localOrigin["z"] },
		startOrigin
	)

	local startAlpha = arrowColor[4]
	local textAlpha = textColor[4]

	if settingDistCheck:GetValue() then
		if dist >= settingMaxDist:GetValue() then
			return
		end

		local alphaStep = 50
		local alphaDistOpaque = settingMaxDist:GetValue() - alphaStep
		local alphaDistDiff = dist - alphaDistOpaque

		if 0 < alphaDistDiff then
			startAlpha = arrowColor[4] - alphaDistDiff * (arrowColor[4] / alphaStep)
			textAlpha = textColor[4] - alphaDistDiff * (textColor[4] / alphaStep)
		end
	end

	if startAlpha < 1 and textAlpha < 1 then
		return
	end

	local screenStart = { client.WorldToScreen(Vector3(startOrigin[1], startOrigin[2], startOrigin[3])) }
	if screenStart[1] == nil then
		return
	end

	-- don't draw triangles if they are too far
	if dist < 800 then
		local endOrigin = { GetRecordTickOrigin(ticks[#ticks]) }
		local originDelta = { vector.Subtract(endOrigin, startOrigin) }

		originDelta[3] = 0

		local deltaDir = { vector.Normalize(originDelta) }
		local multipliedDeltaDir = { vector.Multiply(deltaDir, 20) }

		local croppedEnd = { vector.Add(startOrigin, multipliedDeltaDir) }
		local screenEnd = { client.WorldToScreen(Vector3(croppedEnd[1], croppedEnd[2], croppedEnd[3])) }

		local rotationLeft = { Vector2DRotate({deltaDir[1] * 15, deltaDir[2] * 15}, 135) }
		local left = { vector.Add(startOrigin, { rotationLeft[1], rotationLeft[2], 0}) }
		local screenLeft = { client.WorldToScreen(Vector3(left[1], left[2], left[3])) }

		local rotationRight = { Vector2DRotate({deltaDir[1] * 15, deltaDir[2] * 15}, -135) }
		local right = { vector.Add(startOrigin, { rotationRight[1], rotationRight[2], 0}) }
		local screenRight = { client.WorldToScreen(Vector3(right[1], right[2], right[3])) }

		if screenEnd[1] ~= nil and screenLeft[1] ~= nil and screenRight[1] ~= nil then
			draw.Color(arrowColor[1], arrowColor[2], arrowColor[3], startAlpha)
			if settingArrowStyle:GetValue() == 1 then
				draw.Triangle(screenEnd[1], screenEnd[2], screenLeft[1], screenLeft[2], screenRight[1], screenRight[2])
			else
				draw.Line(screenEnd[1], screenEnd[2], screenLeft[1], screenLeft[2])
				draw.Line(screenEnd[1], screenEnd[2], screenRight[1], screenRight[2])
				draw.Line(screenLeft[1], screenLeft[2], screenRight[1], screenRight[2])
			end
		end
	end

	draw.Color(textColor[1], textColor[2], textColor[3], textAlpha)
	draw.SetFont(fontStart)
	local textW, textH = draw.GetTextSize(name)
	draw.TextShadow(screenStart[1] - (textW * 0.5), screenStart[2] - textH, name)
end

local function StartRecording(localPlayer)
	local vecVelocity = localPlayer:GetPropVector("localdata", "m_vecVelocity[0]")
	-- 1.1 because our velocity is bigger than 1 when using micromoving desync
	if 1.1 < vecVelocity:Length() then
		return
	end

	loadedRecordings[1] = {}

	DisableInterferingSettings()

	isRecording = true
end

local function StopRecording(localPlayer)
	local localRecording = loadedRecordings[1]
	local lastNonIdle = FindNonIdleIndex(localRecording, true)
	if lastNonIdle ~= nil then
		-- remove idle ticks at the end
		for i = lastNonIdle + 1, #localRecording do
			table.remove(loadedRecordings[1]) -- remove last element
		end

		-- add origin at the end
		local lastRecordTick = loadedRecordings[1][#localRecording]
		SetRecordTickOrigin(lastRecordTick, localPlayer:GetAbsOrigin())
	else
		loadedRecordings[1] = {}
	end

	RestoreInterferingSettings()

	isRecording = false
end

local function StartPlayback(localPlayer)
	playbackTicks = FindClosestRecording(localPlayer:GetAbsOrigin())
	playbackIterator = FindNonIdleIndex(playbackTicks, false)
	playbackEndIndex = FindNonIdleIndex(playbackTicks, true)

	if playbackTicks ~= nil and playbackIterator ~= nil and playbackEndIndex ~= nil then
		if settingSwitchKnife:GetValue() then
			switchedFromWeaponID = localPlayer:GetWeaponID()
			client.Command("use weapon_knife; use weapon_fists", true)
		end

		originAtStart = false
		viewanglesAtStart = settingPSilent:GetValue()

		DisableInterferingSettings()

		isPlayback = true
	end
end

local function StopPlayback(localPlayer)
	if settingSwitchBack:GetValue() then
		local weaponID = localPlayer:GetWeaponID()
		-- don't switch back if we didn't switch
		if weaponID ~= switchedFromWeaponID then
			client.Command("lastinv", true)
		end
	end

	RestoreInterferingSettings()

	isPlayback = false
end

client.AllowListener("game_newmap")

callbacks.Register("FireGameEvent", function(event)
	local eventName = event:GetName()

	if eventName == "game_newmap" then
		local newMap = event:GetString("mapname")
		if currentMap ~= newMap then
			currentMap = newMap
			lastVisCheckTime = -1.0
			LoadMapRecords()
		end
	end
end)

callbacks.Register("Draw", function()
	if refMenu:IsActive() then
		settingSwitchBack:SetDisabled(not settingSwitchKnife:GetValue())
	end

	if not settingEnable:GetValue() then
		return
	end

	local localPlayer = entities.GetLocalPlayer()
	if not localPlayer or not localPlayer:IsAlive() then
		-- don't save recording if we died
		if isRecording or isPlayback then
			loadedRecordings[1] = {}
			RestoreInterferingSettings()
			isRecording = false
			isPlayback = false
		end
		return
	end

	local recordKey = settingRecordKey:GetValue()
	if recordKey ~= 0 then
		if not isPlayback and input.IsButtonPressed(recordKey) and not IsTyping() then
			if not isRecording then
				StartRecording(localPlayer)
			else
				StopRecording(localPlayer)
			end
		end
	end

	local playbackKey = settingPlaybackKey:GetValue()
	if playbackKey ~= 0 then
		if not isRecording and input.IsButtonPressed(playbackKey) and not IsTyping() then
			if not isPlayback then
				StartPlayback(localPlayer)
			else
				StopPlayback(localPlayer)
			end
		end
	end

	if settingDrawIndicator:GetValue() then
		DrawIndicator()
	end

	if not isRecording then
		for i = 1, #loadedRecordings do
			local record = loadedRecordings[i]
			if record ~= nil and #record ~= 0 then
				if recordingsVisibility[i] then
					DrawStart(localPlayer:GetAbsOrigin(), record, loadedRecordingsNames[i], { settingColorArrowVisible:GetValue() }, { settingColorTextVisible:GetValue() })
				elseif not settingVisCheck:GetValue() then
					DrawStart(localPlayer:GetAbsOrigin(), record, loadedRecordingsNames[i], { settingColorArrowOccluded:GetValue() }, { settingColorTextOccluded:GetValue() })
				end
			end
		end
	end
end)

local function RecordTick(localPlayer, cmd)
	local viewangles = engine.GetViewAngles()

	local tick = {
		viewangles["pitch"],
		viewangles["yaw"],
		nil, -- was viewangles["roll"] before -- roll is only used when getting headshotted without helmet, plus we don't CorrectMovement for roll, plus we are clamping this to 0
		cmd:GetForwardMove(),
		cmd:GetSideMove(),
		nil, -- was cmd:GetUpMove() before -- upmove is only used when nocliping, and in water
		cmd:GetButtons(),
		-- origin goes here
	}

	-- ignore idle ticks at the start
	local localRecording = loadedRecordings[1]
	local start = (#localRecording == 0)
	if not start or not IsIdleRecordTick(tick) then
		-- add origin at the start
		if start then
			SetRecordTickOrigin(tick, localPlayer:GetAbsOrigin())
		end

		loadedRecordings[1][#localRecording + 1] = tick
	end
end

local function GoToStart(localPlayer, cmd)
	local localOrigin = localPlayer:GetAbsOrigin()
	local startOrigin = { GetRecordTickOrigin(playbackTicks[1]) }

	local deltaXY = { vector.Subtract(
		{ startOrigin[1], startOrigin[2], 0 },
		{ localOrigin["x"], localOrigin["y"], 0 }
	) }

	local distXY = vector.Length(deltaXY)

	-- some jumps are precise
	if 0.33 < distXY then
		cmd:SetForwardMove(clamp(distXY * 7.5, -cl_forwardspeed, cl_forwardspeed))
		cmd:SetSideMove(0)

		local angles = { vector.Angles(deltaXY) }
		CorrectMovement(cmd, angles[2])
	else
		local vecVelocity = localPlayer:GetPropVector("localdata", "m_vecVelocity[0]")
		if 1 > vecVelocity:Length() then
			originAtStart = true
		end
	end
end

local function SetStartAngles()
	local localViewangles = engine.GetViewAngles()
	local startAngles = { GetRecordTickViewangles(playbackTicks[playbackIterator])} -- first non idle angles

	local delta = { vector.Subtract(
		startAngles,
		{ localViewangles["x"], localViewangles["y"], localViewangles["z"] }
	) }

	if settingYawOnly:GetValue() then
		delta[1] = 0
	end

	local clampedDelta = { AnglesNormalize(delta) }

	local deltaLen = vector.Length(clampedDelta)

	if deltaLen < settingAimSpeed:GetValue() then
		viewanglesAtStart = true
		return
	end

	local normalizedDelta = { vector.Normalize(clampedDelta) }
	local multipliedDelta = { vector.Multiply(normalizedDelta, settingAimSpeed:GetValue()) }

	local newAngles = { vector.Add(
		{ localViewangles["x"], localViewangles["y"], localViewangles["z"] },
		multipliedDelta
	) }

	engine.SetViewAngles(EulerAngles(AnglesNormalize(newAngles)))
end

local function PlaybackTick(tick, cmd)
	local tickViewangles = { GetRecordTickViewangles(tick) }
	local tickMoves = { GetRecordTickMoves(tick) }
	local tickButtons = GetRecordTickButtons(tick)

	local pitch = (settingYawOnly:GetValue() and engine.GetViewAngles()["pitch"] or tickViewangles[1])

	local newAngles = EulerAngles(AnglesNormalize({
		pitch,
		tickViewangles[2],
		tickViewangles[3]
	}))

	if settingPSilent:GetValue() then
		if math_fmod(cmd.tick_count, 2) == 0 then
			cmd:SetViewAngles(newAngles)
			cmd:SetSendPacket(false)
		end
	else
		engine.SetViewAngles(newAngles)
	end

	cmd:SetForwardMove(clamp(tickMoves[1], -cl_forwardspeed, cl_forwardspeed))
	cmd:SetSideMove(clamp(tickMoves[2], -cl_sidespeed, cl_sidespeed))
	-- cmd:SetUpMove(clamp(tickMoves[3], -cl_upspeed, cl_upspeed))

	cmd:SetButtons(tickButtons)

	if settingPSilent:GetValue() then
		CorrectMovement(cmd, newAngles["yaw"])
	end

	playbackIterator = playbackIterator + 1
end

callbacks.Register("CreateMove", function(cmd)
	if not settingEnable:GetValue() then
		return
	end

	local localPlayer = entities.GetLocalPlayer()
	if not localPlayer then
		return
	end

	if not isRecording then
		local localOrigin = localPlayer:GetAbsOrigin()

		local eyePos = Vector3(localOrigin["x"], localOrigin["y"], localOrigin["z"]) -- copy
		eyePos["z"] = eyePos["z"] + localPlayer:GetPropFloat("localdata", "m_vecViewOffset[2]")

		local curTime = globals.CurTime()
		
		if (lastVisCheckTime + 0.1) < curTime then
			lastVisCheckTime = curTime
			CheckRecordingsVisibility(localOrigin, eyePos)
		end
	end

	if isRecording then
		RecordTick(localPlayer, cmd)

	elseif isPlayback then
		if not originAtStart then
			GoToStart(localPlayer, cmd)

		elseif not viewanglesAtStart then
			SetStartAngles()

		elseif playbackIterator <= playbackEndIndex then
			PlaybackTick(playbackTicks[playbackIterator], cmd)

		else
			StopPlayback(localPlayer)
		end
	end
end)