-- Movement Recorder by stacky and contributors

local VERSION = "v1.2"
local printPrefix = "[Movement Recorder] "
print(printPrefix .. VERSION)

-- Optimization

-- locals are faster than globals
-- https://lua-users.org/wiki/OptimisingUsingLocalVariables
local math_fmod = math.fmod
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_abs = math.abs

local bit_band = bit.band
local bit_bnot = bit.bnot

-- Variables

local currentMap = engine.GetMapName()

local recordingsFolder = "movement recordings"
local fileExt = ".mr.dat" -- i've tried removing ".dat" but file.Enumerate won't pick it up
local fileExtEscaped = string.gsub(fileExt, "%.", "%%.")

local recordingsPaths = {}
local loadedRecordings = { {} }
local loadedRecordingsNames = { "local" }
local visibleRecordings = {}

local isRecording = false

local isPlayback = false
local playbackTicks = nil
local playbackIterator = nil
local playbackEndIndex = nil

local originAtStart = false
local viewanglesAtStart = false

local lastWeaponType = 0
local lastWeaponID = 0
local taserWeaponID = 31

local recordToDelete = nil
local recordSaveName = nil
local recordSaveOverwriteIndex = nil
local dialogOpen = false

local fontStart = draw.CreateFont("Tahoma", 12, 800)
local fontIndicator = draw.CreateFont("Tahoma", 24, 800)

local cl_forwardspeed = tonumber(client.GetConVar("cl_forwardspeed"))
local cl_sidespeed = tonumber(client.GetConVar("cl_sidespeed"))
-- local cl_upspeed = tonumber(client.GetConVar("cl_upspeed"))

local IN_BULLRUSH = bit.lshift(1, 22)

local disableSettingsPrev = {}

local disableSettingsKV = {
	"misc.strafe.enable", false, 
	"misc.fakelag.enable", false,
	"misc.duckjump", false,
	"rbot.antiaim.base", "-170.0 \"Backward\"",
	"rbot.antiaim.left", "160.0 \"Backward\"",
	"rbot.antiaim.right", "-160.0 \"Backward\"",
	"rbot.accuracy.movement.quickstop", false,
	"lbot.antiaim.type", "Off",
	"lbot.movement.quickstop", false,
}

local CONTENTS_SOLID 	= 0x1 -- an eye is never valid in a solid
local CONTENTS_OPAQUE	= 0x80 -- things that cannot be seen through (may be non-solid though)
local CONTENTS_IGNORE_NODRAW_OPAQUE = 0x2000 -- ignore CONTENTS_OPAQUE on surfaces that have SURF_NODRAW
local CONTENTS_MOVEABLE	= 0x4000 -- hits entities which are MOVETYPE_PUSH (doors, plats, etc.)

local MASK_OPAQUE = bit.bor(CONTENTS_SOLID, CONTENTS_MOVEABLE, CONTENTS_OPAQUE) -- everything that blocks lighting
local MASK_VISIBLE = bit.bor(MASK_OPAQUE, CONTENTS_IGNORE_NODRAW_OPAQUE) -- everything that blocks line of sight for players

local recordTickViewanglesIndex = 1
local recordTickMovesIndex = recordTickViewanglesIndex + 3
local recordTickButtonsIndex = recordTickMovesIndex + 3
local recordTickOriginIndex = recordTickButtonsIndex + 1
local recordTickElementCount = recordTickOriginIndex + 3

local function SerializeRecording(tbl)
	local result = "{\n"
	for i = 1, #tbl do
		result = result .. "{\n"
		for j = 1, recordTickElementCount do
			if tbl[i][j] ~= nil then
				local indexValue = string.format("%s[%d]=%.3f,\n", result, j, tbl[i][j])
				-- remove trailing zeroes
				result = string.gsub(indexValue, "%.0+,", ",")
			end
		end
		result = result .. "},"
	end
	result = result .. "\n}"
	return result
end

-- Tab

local refMenu = gui.Reference("Menu")
local refMisc = gui.Reference("MISC")
local TAB = gui.Tab(refMisc, "movrec", "Movement Recorder")

local SETTINGS_GBOX = gui.Groupbox(TAB, "Settings", 16, 16, 296, 0)
local RECORD_GBOX = gui.Groupbox(TAB, "Record", 328, 16, 296, 0)
local PLAYBACK_GBOX = gui.Groupbox(TAB, "Playback", 328, 236, 296, 0)

-- Dialog

-- if we draw this in the center it just gets covered by the main menu
local DIALOG = gui.Window("movrec.dialog", GetScriptName(), 16, 50, 304, 150)
DIALOG:SetActive(false)

local DIALOG_TEXT = gui.Text(DIALOG, "")

local DIALOG_FN_YES = nil

local DIALOG_YES = gui.Button(DIALOG, "YES", function()
	DIALOG_FN_YES()
	dialogOpen = false
end)
DIALOG_YES:SetHeight(28)
DIALOG_YES:SetPosY(78)

local DIALOG_FN_NO = nil

local DIALOG_NO = gui.Button(DIALOG, "NO", function()
	DIALOG_FN_NO()
	dialogOpen = false
end)
DIALOG_NO:SetHeight(28)
DIALOG_NO:SetPosX(160)
DIALOG_NO:SetPosY(78)

local function Dialog(text, fnYes, fnNo)
	local screenW, screenH = draw.GetScreenSize()
	DIALOG:SetPosX((screenW - 304) * 0.5)
	DIALOG:SetPosY(50)

	DIALOG_TEXT:SetText(text)
	DIALOG_FN_YES = fnYes
	DIALOG_FN_NO = fnNo
	dialogOpen = true
end

-- Settings

local SETTINGS_ENABLE = gui.Checkbox(SETTINGS_GBOX, "settings.enable", "Enable", false)
local SETTINGS_INDICATOR = gui.Checkbox(SETTINGS_GBOX, "settings.drawindicator", "Draw Indicator", true)
local SETTINGS_DRAWSTART = gui.Checkbox(SETTINGS_GBOX, "settings.drawstart", "Draw Start", true)
local SETTINGS_STARTCOLOR =
	gui.ColorPicker(SETTINGS_DRAWSTART, "settings.startcolor", "", 92, 92, 92, 192)
local SETTINGS_DRAWSTARTSTYLE = gui.Combobox(SETTINGS_GBOX, "settings.drawstartstyle", "Start Style", "Outlined", "Filled")
SETTINGS_DRAWSTARTSTYLE:SetValue(1)

local SETTINGS_DRAWFILTER = gui.Multibox(SETTINGS_GBOX, "Start Filter")
local SETTINGS_DRAWFILTER_VISCHECK =
	gui.Checkbox(SETTINGS_DRAWFILTER, "settings.drawstartfilter.vischeck", "Visible", true)
local SETTINGS_DRAWFILTER_DISTCHECK =
	gui.Checkbox(SETTINGS_DRAWFILTER, "settings.drawstartfilter.distcheck", "Nearby", true)

-- Loaded Recordings

local RECORDINGS_GBOX = gui.Groupbox(TAB, "Loaded Recordings", 16, 300, 296, 0)

local RECORDINGS_LOADED = gui.Listbox(RECORDINGS_GBOX, "recordings.loaded", 300)
RECORDINGS_LOADED:SetWidth(264)

-- Record

local RECORD_KEY = gui.Keybox(RECORD_GBOX, "record.key", "Record Key", 0)

local RECORDINGS_NAME = gui.Editbox(RECORD_GBOX, "recordings.name", "Name")

local function SaveRecording()
	if recordSaveName == nil then
		return
	end

	local path = recordingsFolder .. "/" .. currentMap .. "/" .. recordSaveName .. fileExt

	local writer = file.Open(path, "w")
	writer:Write(SerializeRecording(loadedRecordings[1]))
	writer:Close()
	
	if recordSaveOverwriteIndex ~= nil then
		loadedRecordings[recordSaveOverwriteIndex] = loadedRecordings[1]
	else
		recordingsPaths[#recordingsPaths + 1] = path
		
		loadedRecordings[#loadedRecordings + 1] = loadedRecordings[1]

		loadedRecordingsNames[#loadedRecordingsNames + 1] = recordSaveName
		RECORDINGS_LOADED:SetOptions(unpack(loadedRecordingsNames, 2))
	end
	
	loadedRecordings[1] = {}
	
	recordSaveName = nil
	recordSaveOverwriteIndex = nil
end

local function CancelSaving()
	recordSaveName = nil
	recordSaveOverwriteIndex = nil
end

local RECORDINGS_SAVE = gui.Button(RECORD_GBOX, "Save", function()
	if #loadedRecordings[1] == 0 then
		print(printPrefix .. "Nothing to save")
		return
	end

	local name = RECORDINGS_NAME:GetValue()
	if name == nil or name == "" then
		print(printPrefix .. "Invalid record name")
		return
	end
	
	if currentMap == nil or currentMap == "" then
		print(printPrefix .. "Invalid map name")
		return
	end
	
	-- remove bad characters from name
	recordSaveName = string.gsub(name, "[%p%c.]", "")
	
	local fileExists = false
	
	for i = 2, #loadedRecordingsNames do
		if loadedRecordingsNames[i] == recordSaveName then
			fileExists = true
			recordSaveOverwriteIndex = i
			break
		end
	end
	
	if fileExists then
		Dialog("File named \"" .. recordSaveName .. "\" already exists.\nAre you sure you want to overwrite it?",
			SaveRecording, CancelSaving)
	else
		SaveRecording()
	end
end)
RECORDINGS_SAVE:SetWidth(264)
RECORDINGS_SAVE:SetHeight(28)

-- Playback

local PLAYBACK_KEY = gui.Keybox(PLAYBACK_GBOX, "playback.key", "Playback Key", 0)

local PLAYBACK_SETTINGS = gui.Multibox(PLAYBACK_GBOX, "Playback Settings")
local PLAYBACK_SETTINGS_SWITCHKNIFE =
	gui.Checkbox(PLAYBACK_SETTINGS, "playback.settings.switchknife", "Switch to Knife", true)
local PLAYBACK_SETTINGS_SWITCHBACK =
	gui.Checkbox(PLAYBACK_SETTINGS, "playback.settings.switchback", "Switch Back", false)
local PLAYBACK_SETTINGS_PSILENT =
	gui.Checkbox(PLAYBACK_SETTINGS, "playback.settings.psilent", "Perfect Silent Angles", false)
local PLAYBACK_SETTINGS_YAWONLY =
	gui.Checkbox(PLAYBACK_SETTINGS, "playback.settings.yawonly", "Yaw Only", false)

local PLAYBACK_AIMSPEED = gui.Slider(PLAYBACK_GBOX, "playback.aimspeed", "Aim Speed", 3, 1, 10)
local PLAYBACK_MAXDIST = gui.Slider(PLAYBACK_GBOX, "playback.maxdist", "Max Distance", 250, 100, 500, 10)

local function DeleteRecording()
	if recordToDelete == nil then
		return
	end

	for i = 1, #recordingsPaths do
		local recordingPath = recordingsPaths[i]
		local recordingName = loadedRecordingsNames[recordToDelete]
		if string.find(recordingPath, "/" .. currentMap .. "/", 1, true) ~= nil and
			string.find(recordingPath, "/" .. recordingName .. fileExtEscaped .. "$") ~= nil then
			file.Delete(recordingPath)
			table.remove(recordingsPaths, i)
			break
		end
	end
	
	table.remove(loadedRecordings, recordToDelete)
	
	table.remove(loadedRecordingsNames, recordToDelete)
	RECORDINGS_LOADED:SetOptions(unpack(loadedRecordingsNames, 2))
	
	recordToDelete = nil
end

local function CancelDeletion()
	recordToDelete = nil
end

local RECORDINGS_DELETE = gui.Button(RECORDINGS_GBOX, "Delete", function()
	recordToDelete = RECORDINGS_LOADED:GetValue() + 2
	
	Dialog("Are you sure you want to delete the recording?", DeleteRecording, CancelDeletion)
end)
RECORDINGS_DELETE:SetWidth(264)
RECORDINGS_DELETE:SetHeight(28)

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

-- set main folder name, which contains all our recordings
local function SetRecordingsFolder()
	if #recordingsPaths ~= 0 then
		-- check if we have more than a subfolder
		local firstFolder = string.match(recordingsPaths[1], "^([^/]+)/.+/")

		if firstFolder ~= nil then
			recordingsFolder = firstFolder
		end
	end
end

SetRecordingsFolder()

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
	
	RECORDINGS_LOADED:SetOptions(unpack(loadedRecordingsNames, 2))
end

LoadMapRecords()

client.AllowListener("server_spawn")

callbacks.Register("FireGameEvent", function(event)
	if event:GetName() == "server_spawn" then
		local newMap = event:GetString("mapname")
		if currentMap ~= newMap then
			currentMap = newMap
			LoadMapRecords()
		end
	end
end)

local RECORDINGS_RELOAD = gui.Button(RECORDINGS_GBOX, "Reload", function()
	RefreshSaved()
	LoadMapRecords()
end)
RECORDINGS_RELOAD:SetWidth(264)
RECORDINGS_RELOAD:SetHeight(28)

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
	local minDistance = PLAYBACK_MAXDIST:GetValue()
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

local function FindVisibleRecordings(localOrigin, eyePos)
	local visible = {}

	for i = 1, #loadedRecordings do
		local record = loadedRecordings[i]
		if record ~= nil and #record ~= 0 then
			local recordStart = Vector3(GetRecordTickOrigin(record[1]))
			
			if SETTINGS_DRAWFILTER_DISTCHECK:GetValue() then
				local dist = vector.Distance(localOrigin, recordStart)
				if dist >= PLAYBACK_MAXDIST:GetValue() then
					goto continue
				end
			end
			
			local fract = engine.TraceLine(eyePos, recordStart, MASK_VISIBLE).fraction
			if fract == 1 then
				visible[#visible + 1] = i
			end
		end
		::continue::
	end

	return visible
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
	
	draw.Color(255, 255, 255, 255)
	draw.SetFont(fontIndicator)
	
	local screenW, screenH = draw.GetScreenSize()
	local textW, textH = draw.GetTextSize(text)
	local x = ((screenW - textW) * 0.5)
	
	draw.TextShadow(x, 100, text)
end

local function DrawStart(localOrigin, ticks, name)
	local startOrigin = { GetRecordTickOrigin(ticks[1]) }
	
	local dist = vector.Distance(
		{ localOrigin["x"], localOrigin["y"], localOrigin["z"] },
		startOrigin
	)

	local startColor = { SETTINGS_STARTCOLOR:GetValue() }
	local alpha = startColor[4]

	if SETTINGS_DRAWFILTER_DISTCHECK:GetValue() then
		if dist >= PLAYBACK_MAXDIST:GetValue() then
			return
		end
		
		local alphaStep = 50
		local alphaDistOpaque = PLAYBACK_MAXDIST:GetValue() - alphaStep
		local alphaDistDiff = dist - alphaDistOpaque
		
		if 0 < alphaDistDiff then
			alpha = startColor[4] - alphaDistDiff * (startColor[4] / alphaStep)
		end
	end
	
	if alpha < 1 then
		return
	end

	local screenStart = { client.WorldToScreen(Vector3(startOrigin[1], startOrigin[2], startOrigin[3])) }
	if screenStart[1] == nil then
		return
	end
	
	-- don't draw triangles we can't see
	if dist < 1000 then
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
			draw.Color(startColor[1], startColor[2], startColor[3], alpha)
			if SETTINGS_DRAWSTARTSTYLE:GetValue() == 1 then
				draw.Triangle(screenEnd[1], screenEnd[2], screenLeft[1], screenLeft[2], screenRight[1], screenRight[2])
			else
				draw.Line(screenEnd[1], screenEnd[2], screenLeft[1], screenLeft[2])
				draw.Line(screenEnd[1], screenEnd[2], screenRight[1], screenRight[2])
				draw.Line(screenLeft[1], screenLeft[2], screenRight[1], screenRight[2])
			end
		end
	end
	
	draw.Color(255, 255, 255, alpha)
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
		lastWeaponType = localPlayer:GetWeaponType()
		lastWeaponID = localPlayer:GetWeaponID()

		if PLAYBACK_SETTINGS_SWITCHKNIFE:GetValue() and
			(lastWeaponType ~= 0 or lastWeaponID == taserWeaponID) then
			client.Command("slot3", true)
		end
		
		originAtStart = false
		viewanglesAtStart = PLAYBACK_SETTINGS_PSILENT:GetValue()
		
		DisableInterferingSettings()
		
		isPlayback = true
	end
end

local function StopPlayback()
	if PLAYBACK_SETTINGS_SWITCHBACK:GetValue() then
		if lastWeaponType == 1 then
			client.Command("slot2", true)
		elseif lastWeaponType >= 2 and lastWeaponType <= 6 then
			client.Command("slot1", true)
		elseif lastWeaponType == 0 or lastWeaponID == taserWeaponID then
			client.Command("slot3", true)
		elseif lastWeaponType == 9 then
			client.Command("slot4", true)
		elseif lastWeaponType == 7 then
			client.Command("slot5", true)
		end
	end

	RestoreInterferingSettings()
	
	isPlayback = false
end

callbacks.Register("Draw", function()
	DIALOG:SetActive(dialogOpen and refMenu:IsActive())

	if not SETTINGS_ENABLE:GetValue() then
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
	
	local recordKey = RECORD_KEY:GetValue()
	if recordKey ~= 0 then
		if not isPlayback and input.IsButtonPressed(recordKey) then
			if not isRecording then
				StartRecording(localPlayer)
			else
				StopRecording(localPlayer)
			end
		end
	end
	
	local playbackKey = PLAYBACK_KEY:GetValue()
	if playbackKey ~= 0 then
		if not isRecording and input.IsButtonPressed(playbackKey) then
			if not isPlayback then
				StartPlayback(localPlayer)
			else
				StopPlayback()
			end
		end
	end

	if SETTINGS_INDICATOR:GetValue() then
		DrawIndicator()
	end

	if not isRecording and SETTINGS_DRAWSTART:GetValue() then
		if SETTINGS_DRAWFILTER_VISCHECK:GetValue() then
			for i = 1, #visibleRecordings do
				local index = visibleRecordings[i]
				local record = loadedRecordings[index]
				if record ~= nil and #record ~= 0 then
					DrawStart(localPlayer:GetAbsOrigin(), record, loadedRecordingsNames[index])
				end
			end
		else
			for i = 1, #loadedRecordings do
				local record = loadedRecordings[i]
				if record ~= nil and #record ~= 0 then
					DrawStart(localPlayer:GetAbsOrigin(), record, loadedRecordingsNames[i])
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
	
	if PLAYBACK_SETTINGS_YAWONLY:GetValue() then
		delta[1] = 0
	end
	
	local clampedDelta = { AnglesNormalize(delta) }
	
	local deltaLen = vector.Length(clampedDelta)
		
	if deltaLen < PLAYBACK_AIMSPEED:GetValue() then
		viewanglesAtStart = true
		return
	end
	
	local normalizedDelta = { vector.Normalize(clampedDelta) }
	local multipliedDelta = { vector.Multiply(normalizedDelta, PLAYBACK_AIMSPEED:GetValue()) }
		
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

	local pitch = (PLAYBACK_SETTINGS_YAWONLY:GetValue() and engine.GetViewAngles()["pitch"] or tickViewangles[1])

	local newAngles = EulerAngles(AnglesNormalize({
		pitch,
		tickViewangles[2],
		tickViewangles[3]
	}))
	
	if PLAYBACK_SETTINGS_PSILENT:GetValue() then
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

	if PLAYBACK_SETTINGS_PSILENT:GetValue() then
		CorrectMovement(cmd, newAngles["yaw"])
	end

	playbackIterator = playbackIterator + 1
end

callbacks.Register("CreateMove", function(cmd)
	if not SETTINGS_ENABLE:GetValue() then
		return
	end

	local localPlayer = entities.GetLocalPlayer()
	if not localPlayer then
		return
	end
	
	if not isRecording and SETTINGS_DRAWFILTER_VISCHECK:GetValue() then	
		local localOrigin = localPlayer:GetAbsOrigin()
		
		local eyePos = Vector3(localOrigin["x"], localOrigin["y"], localOrigin["z"]) -- copy
		eyePos["z"] = eyePos["z"] + localPlayer:GetPropFloat("localdata", "m_vecViewOffset[2]")

		visibleRecordings = FindVisibleRecordings(localOrigin, eyePos)
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
			StopPlayback()
		end
	end
end)