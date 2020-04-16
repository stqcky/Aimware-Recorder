-- Movement Recorder by stacky

local VERSION = "v1.1"
print("Movement Recorder " .. VERSION .. " loaded.")

function pickle(t)
    return Pickle:clone():pickle_(t)
  end
  
  Pickle = {
    clone = function (t) local nt={}; for i, v in pairs(t) do nt[i]=v end return nt end 
  }
  
  function Pickle:pickle_(root)
    if type(root) ~= "table" then 
      error("can only pickle tables, not ".. type(root).."s")
    end
    self._tableToRef = {}
    self._refToTable = {}
    local savecount = 0
    self:ref_(root)
    local s = ""
  
    while table.getn(self._refToTable) > savecount do
      savecount = savecount + 1
      local t = self._refToTable[savecount]
      s = s.."{\n"
      for i, v in pairs(t) do
          s = string.format("%s[%s]=%s,\n", s, self:value_(i), self:value_(v))
      end
      s = s.."},\n"
    end
  
    return string.format("{%s}", s)
  end
  
  function Pickle:value_(v)
    local vtype = type(v)
    if     vtype == "string" then return string.format("%q", v)
    elseif vtype == "number" then return v
    elseif vtype == "boolean" then return tostring(v)
    elseif vtype == "table" then return "{"..self:ref_(v).."}"
    else --error("pickle a "..type(v).." is not supported")
    end  
  end
  
  function Pickle:ref_(t)
    local ref = self._tableToRef[t]
    if not ref then 
      if t == self then error("can't pickle the pickle class") end
      table.insert(self._refToTable, t)
      ref = table.getn(self._refToTable)
      self._tableToRef[t] = ref
    end
    return ref
  end
  
  function unpickle(s)
    if type(s) ~= "string" then
      error("can't unpickle a "..type(s)..", only strings")
    end
    local gentables = loadstring("return "..s)
    local tables = gentables()
    
    for tnum = 1, table.getn(tables) do
      local t = tables[tnum]
      local tcopy = {}; for i, v in pairs(t) do tcopy[i] = v end
      for i, v in pairs(tcopy) do
        local ni, nv
        if type(i) == "table" then ni = tables[i[1]] else ni = i end
        if type(v) == "table" then nv = tables[v[1]] else nv = v end
        t[i] = nil
        t[ni] = nv
      end
    end
    return tables[1]
  end

function split(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do table.insert(t, str) end
    return t
end


 -- Variables
local loadedMovements = {}
local localMovements = nil

local savedRecordings = {}
local loadedRecordings = {}

local recording = false

local playback = false
local playbackIterator = 1

local lastDistance = 0
local atStart = false

local snapAngle = nil
local snapped = false

local minMov = nil
local visibleMoves = nil

local lastWeapon = 0
local lastWeaponID = 0

local fileToDelete = nil
local deleteDialogOpen = false

local moved = true
local lastDistanceMoved = 0

local FONT = draw.CreateFont("Verdana", 30, 2000)

-- Some functions

local function fetchRecordings(filename)
    if string.match(filename, "%.dat") then
        table.insert(savedRecordings, filename)
    end
end

local function findClosest()
    local origin = entities.GetLocalPlayer():GetAbsOrigin()
    local minDistance = math.huge
    local minMovement = nil

    for k, v in pairs(loadedMovements) do
        local curDistance = vector.Distance( {origin["x"], origin["y"], origin["z"]}, {v[1][8], v[1][9], v[1][10]} )
        if curDistance < minDistance then
            minDistance = curDistance
            minMovement = v
        end
    end

    if localMovements ~= nil then
        local curDistance = vector.Distance( {origin["x"], origin["y"], origin["z"]}, {localMovements[1][8], localMovements[1][9], localMovements[1][10]} )
        if curDistance < minDistance then
            minDistance = curDistance
            minMovement = localMovements
        end
    end

    return minMovement
end

local function findVisible()
    local origin = entities.GetLocalPlayer():GetAbsOrigin()
    local visMoves = {}

    origin.z = origin.z + entities.GetLocalPlayer():GetPropVector("localdata", "m_vecViewOffset[0]").z

    for k, v in pairs(loadedMovements) do
        local fract = engine.TraceLine( origin, Vector3( v[1][8], v[1][9], v[1][10] ), 0x1 ).fraction
        if fract == 1 then
            visMoves[k] = v
        end
    end

    if localMovements ~= nil then
        local fract = engine.TraceLine( origin, Vector3( localMovements[1][8], localMovements[1][9], localMovements[1][10] ), 0x1 ).fraction
        if fract == 1 then
            visMoves["Local"] = localMovements
        end
    end

    return visMoves
end

local function moveToStart(destination, cmd)
    local deg2rad = (math.pi / 180)
    local deltaView, f1, f2
    local viewangle_x = cmd:GetViewAngles()["pitch"]
    local viewangle_y = cmd:GetViewAngles()["yaw"]
    local viewangle_z = cmd:GetViewAngles()["roll"]
    local fOldForward = cmd:GetForwardMove()
    local fOldSidemove = cmd:GetSideMove()

    if (destination < 0) then f1 = 360 + destination else f1 = destination end
    if (viewangle_y < 0) then f2 = 360 + viewangle_y else f2 = viewangle_y end
    if (f2 < f1) then deltaView = math.abs(f2 - f1) else deltaView = 360 - math.abs(f1 - f2) end

    deltaView = 360 - deltaView

    cmd:SetForwardMove( math.cos( (deg2rad*deltaView) ) * fOldForward + math.cos( (deg2rad*(deltaView + 90)) ) * fOldSidemove )
    cmd:SetSideMove( math.sin( (deg2rad*deltaView) ) * fOldForward + math.sin( (deg2rad*(deltaView + 90)) ) * fOldSidemove )
end

-- Main Menu

local WINDOW = gui.Window( "movrec", "Movement Recorder", 100, 100, 430, 365 ) 

local RECORDINGS_GBOX = gui.Groupbox( WINDOW, "Manage Recordings", 10, 10, 410, 0 )
RECORDINGS_GBOX:SetInvisible(true)

local SETTINGS_GBOX = gui.Groupbox( WINDOW, "Settings", 10, 10, 200, 0 )
local RECORD_GBOX = gui.Groupbox( WINDOW, "Record", 220, 10, 200, 0 )
local PLAYBACK_GBOX = gui.Groupbox( WINDOW, "Playback", 220, 120, 200, 0 )

-- Main Menu Settings
local SETTINGS_INDICATORS = gui.Checkbox( SETTINGS_GBOX, "settings.indicators", "Indicators", false )
local SETTINGS_INDICATORCOLOR = gui.ColorPicker( SETTINGS_INDICATORS, "settings.indicatorcolor", "name", 255, 0, 0, 255 )
local SETTINGS_SPEED = gui.Slider( SETTINGS_GBOX, "settings.speed", "Start Pos Speed", 2, 1, 100 )
local SETTINGS_DRAWPATH = gui.Checkbox( SETTINGS_GBOX, "settings.drawpath", "Draw Path", false )
local SETTINGS_PATHCOLOR = gui.ColorPicker( SETTINGS_DRAWPATH, "settings.pathcolor", "", 255, 0, 0, 255 )
local SETTINGS_DRAWSTART = gui.Checkbox( SETTINGS_GBOX, "settings.drawstart", "Draw Start", false )
local SETTINGS_STARTCOLOR = gui.ColorPicker( SETTINGS_DRAWSTART, "settings.startcolor", "Start Pos Color", 255, 0, 0, 255 )
local SETTINGS_DRAWSELECTION = gui.Combobox( SETTINGS_GBOX, "settings.drawselection", "Draw Selection", "All", "Visible" )
local SETTINGS_RECORDINGSMENU = gui.Button( SETTINGS_GBOX, "Manage Recordings", function()
    SETTINGS_GBOX:SetInvisible(true)
    RECORD_GBOX:SetInvisible(true)
    PLAYBACK_GBOX:SetInvisible(true)
    RECORDINGS_GBOX:SetInvisible(false)
    WINDOW:SetHeight(485)
    WINDOW:SetWidth(430)
end)

-- Main Menu Record
local RECORD_KEY = gui.Keybox( RECORD_GBOX, "record.key", "Record Key", 0 )

-- Main Menu Playback
local PLAYBACK_KEY = gui.Keybox( PLAYBACK_GBOX, "playback.key", "Playback Key", 0 )
local PLAYBACK_SETTINGS = gui.Multibox( PLAYBACK_GBOX, "Playback Settings" )
local PLAYBACK_SETTINGS_SWITCHKNIFE = gui.Checkbox( PLAYBACK_SETTINGS, "playback.settings.switchknife", "Switch to Knife", false )
local PLAYBACK_SETTINGS_SWITCHBACK = gui.Checkbox( PLAYBACK_SETTINGS, "playback.settings.switchback", "Switch Back", false )
local PLAYBACK_SNAPSMOOTH = gui.Slider( PLAYBACK_GBOX, "playback.snapsmooth", "Snap Smooth", 1, 0, 10, 0.5 )

-- Manage Recordings
gui.Text(RECORDINGS_GBOX, "Saved Recordings")
local RECORDINGS_SAVED = gui.Listbox(RECORDINGS_GBOX, "saved", 150, "not loaded")
RECORDINGS_SAVED:SetWidth(200)

gui.Text(RECORDINGS_GBOX, "Loaded Recordings")
local RECORDINGS_LOADED = gui.Listbox(RECORDINGS_GBOX, "loaded", 150, "")
RECORDINGS_LOADED:SetWidth(200)

local RECORDINGS_NAME = gui.Editbox( RECORDINGS_GBOX, "name", "Name" )
RECORDINGS_NAME:SetPosX(230)
RECORDINGS_NAME:SetPosY(0)
RECORDINGS_NAME:SetWidth(130)

local RECORDINGS_CREATE = gui.Button( RECORDINGS_GBOX, "Create", function()
    if RECORDINGS_NAME:GetValue() ~= "" then
        local chars = {"\\", "/", ":", "*", "?", "<", ">", "|"}
        local fileName = RECORDINGS_NAME:GetValue() .. ".dat"

        for i = 1, #chars do
            fileName = string.gsub(fileName, chars[i], "")
        end

        local writer = file.Open( fileName, "w")
        writer:Write(pickle(localMovements))
        writer:Close()
    end
end )
RECORDINGS_CREATE:SetPosX(230)
RECORDINGS_CREATE:SetPosY(50)

local function loadRecording()
    local name = savedRecordings[RECORDINGS_SAVED:GetValue() + 1]
    if loadedMovements[name] == nil then
        local reader = file.Open( name, "r")
        local file = unpickle(reader:Read())
        reader:Close()
        loadedMovements[name] = file

        table.insert(loadedRecordings, name)
        RECORDINGS_LOADED:SetOptions(unpack(loadedRecordings))
    end
end

local RECORDINGS_LOAD = gui.Button( RECORDINGS_GBOX, "Load", loadRecording)
RECORDINGS_LOAD:SetPosX(230)
RECORDINGS_LOAD:SetPosY(110)

local function unloadRecording()
    local name = loadedRecordings[RECORDINGS_LOADED:GetValue() + 1]
    table.remove(loadedRecordings, RECORDINGS_LOADED:GetValue() + 1)
    RECORDINGS_LOADED:SetOptions(unpack(loadedRecordings))
    loadedMovements[name] = nil
end

local RECORDINGS_UNLOAD = gui.Button( RECORDINGS_GBOX, "Unload", unloadRecording)
RECORDINGS_UNLOAD:SetPosX(230)
RECORDINGS_UNLOAD:SetPosY(150)

local function refreshSaved()
    savedRecordings = {}
    file.Enumerate(fetchRecordings)
    RECORDINGS_SAVED:SetOptions(unpack(savedRecordings))
end

-- Delete Dialog

local deleteWINDOW = gui.Window( "movrec.dialog", "Delete Recording", 10, 10, 300, 120 )
deleteWINDOW:SetActive(false)
local deleteTEXT = gui.Text( deleteWINDOW, "Are you sure you want to delete the recording?" )
local deleteYES = gui.Button( deleteWINDOW, "YES", function()
    file.Delete(fileToDelete)
    refreshSaved()
    deleteDialogOpen = false
end )
local deleteNO = gui.Button( deleteWINDOW, "NO", function()
    deleteDialogOpen = false
end )
deleteNO:SetPosX(160)
deleteNO:SetPosY(45)

local RECORDINGS_DELETE = gui.Button( RECORDINGS_GBOX, "Delete", function()
    local screenW, screenH = draw.GetScreenSize()
    deleteWINDOW:SetPosX(screenW / 2)
    deleteWINDOW:SetPosY(screenH / 2)
    deleteDialogOpen = true
    fileToDelete = savedRecordings[RECORDINGS_SAVED:GetValue() + 1]
end )
RECORDINGS_DELETE:SetPosX(230)
RECORDINGS_DELETE:SetPosY(225)

local RECORDINGS_REFRESH = gui.Button( RECORDINGS_GBOX, "Refresh List", refreshSaved)
RECORDINGS_REFRESH:SetPosX(230)
RECORDINGS_REFRESH:SetPosY(300)

refreshSaved()

local RECORDINGS_GOBACK = gui.Button( RECORDINGS_GBOX, "Go Back", function()
    SETTINGS_GBOX:SetInvisible(false)
    RECORD_GBOX:SetInvisible(false)
    PLAYBACK_GBOX:SetInvisible(false)
    RECORDINGS_GBOX:SetInvisible(true)
    WINDOW:SetHeight(365)
    WINDOW:SetWidth(430)
end )
RECORDINGS_GOBACK:SetPosX(230)
RECORDINGS_GOBACK:SetPosY(340)

local function drawPath(moves)
    draw.Color(SETTINGS_PATHCOLOR:GetValue())
    lastPosX, lastPosY = client.WorldToScreen( Vector3( moves[1][8], moves[1][9], moves[1][10] ) )
    for i = 2, #moves do
        curPosX, curPosY = client.WorldToScreen( Vector3( moves[i][8], moves[i][9], moves[i][10] ) )
        if lastPosX ~= nil and curPosX ~= nil then
            draw.Line( lastPosX, lastPosY, curPosX, curPosY )
        end
        
        lastPosX = curPosX
        lastPosY = curPosY
    end
end

local function drawIndicator(indicator)
    draw.Color(SETTINGS_INDICATORCOLOR:GetValue())
    draw.SetFont(FONT)
    screenW, screenH = draw.GetScreenSize()
    textW, textH = draw.GetTextSize( indicator )
    x = (screenW / 2) - (textW / 2)
    draw.TextShadow( x, 100, indicator )
end

local function drawStart(x, y, z, name)
    draw.Color( SETTINGS_STARTCOLOR:GetValue() )
    
    x1, y1 = client.WorldToScreen( Vector3(x - 10, y + 10, z) )
    x2, y2 = client.WorldToScreen( Vector3(x + 10, y + 10, z) )
    x3, y3 = client.WorldToScreen( Vector3(x + 10, y - 10, z) )
    x4, y4 = client.WorldToScreen( Vector3(x - 10, y - 10, z) )

    if x1 ~= nil and x2 ~= nil and x3 ~= nil and x4 ~=  nil then
        draw.Line( x1, y1, x2, y2 )
        draw.Line( x2, y2, x3, y3 )
        draw.Line( x3, y3, x4, y4 )
        draw.Line( x4, y4, x1, y1 )
    end

    draw.SetFont(FONT)
    textW, textH = draw.GetTextSize( name )
    sX, sY = client.WorldToScreen( Vector3(x, y, z + 20 ) )
    if sX ~= nil then
        draw.TextShadow( sX - (textW / 2), sY - (textH / 2), name )
    end
end

callbacks.Register( "Draw", function()
    WINDOW:SetActive(gui.Reference("Menu"):IsActive())
    if not gui.Reference("Menu"):IsActive() then
        deleteWINDOW:SetActive(false)
    else
        deleteWINDOW:SetActive(deleteDialogOpen)
    end

    if entities.GetLocalPlayer() then
        if RECORD_KEY:GetValue() ~= 0 then
            if input.IsButtonPressed( RECORD_KEY:GetValue() ) and not playback then
                if not recording then
                    velocity = math.sqrt(entities.GetLocalPlayer():GetPropFloat( "localdata", "m_vecVelocity[0]" )^2 + entities.GetLocalPlayer():GetPropFloat( "localdata", "m_vecVelocity[1]" )^2)
                    if velocity == 0 then
                        localMovements = {}
                        recording = not recording
                    end
                else
                    recording = not recording
                end
            end
        end

        if PLAYBACK_KEY:GetValue() ~= 0 then
            if input.IsButtonPressed( PLAYBACK_KEY:GetValue() ) and not recording then
                lastWeapon = entities.GetLocalPlayer():GetWeaponType()
                lastWeaponID = entities.GetLocalPlayer():GetWeaponID() -- taser = 31

                if PLAYBACK_SETTINGS_SWITCHKNIFE:GetValue() then
                    if lastWeapon ~= 0 or lastWeaponID == 31 then
                        client.Command( "slot3", true )
                    end
                end
                
                playbackIterator = 1
                lastDistance = 0
                atStart = false
                snapped = false
                minMov = findClosest()
                snapAngle = EulerAngles(minMov[1][1], minMov[1][2], minMov[1][3])
                playback = not playback
            end
        end

        if SETTINGS_INDICATORS:GetValue() then
            if recording then
                drawIndicator("-- RECORDING --")
            elseif playback then 
                if not atStart then
                    drawIndicator("-- GOING TO START POSITION --")
                elseif not snapped then
                    drawIndicator("-- SNAPPING TO START ANGLE --")
                else
                    drawIndicator("-- PLAYBACK --")
                end
            end
        end

        if SETTINGS_DRAWSTART:GetValue() then
            if SETTINGS_DRAWSELECTION:GetValue() == 0 then
                if localMovements ~= nil then
                    drawStart(localMovements[1][8], localMovements[1][9], localMovements[1][10], "Local")
                end

                for k, v in pairs(loadedMovements) do
                    if v ~= nil then
                        local name = split(k, "/")
                        drawStart(loadedMovements[k][1][8], loadedMovements[k][1][9], loadedMovements[k][1][10], name[#name]:gsub("%.dat", ""))
                    end
                end
            else
                if visibleMoves ~= nil then
                    for k, v in pairs(visibleMoves) do
                        local name = split(k, "/")
                        drawStart(v[1][8], v[1][9], v[1][10], name[#name]:gsub("%.dat", ""))
                    end
                end
            end
        end

        if SETTINGS_DRAWPATH:GetValue() then
            if SETTINGS_DRAWSELECTION:GetValue() == 0 then
                if localMovements ~= nil then
                    drawPath(localMovements)
                end

                for k, v in pairs(loadedMovements) do
                    if v ~= nil then
                        drawPath(loadedMovements[k])
                    end
                end
            else
                for k, v in pairs(visibleMoves) do
                    drawPath(v)
                end
            end
        end
    end
end )

callbacks.Register( "CreateMove", function(cmd)
    if entities.GetLocalPlayer() then
        if SETTINGS_DRAWSELECTION:GetValue() == 1 then
            visibleMoves = findVisible()
        end

        if recording then
            local tickMoves = {}

            local viewAnglesPitch = engine.GetViewAngles()["pitch"]
            local viewAnglesYaw = engine.GetViewAngles()["yaw"]
            local viewAnglesRoll = engine.GetViewAngles()["roll"]

            local forwardMove = cmd:GetForwardMove()
            local sideMove = cmd:GetSideMove()
            local upMove = cmd:GetUpMove()

            local buttons = cmd:GetButtons()

            local positionx = entities.GetLocalPlayer():GetAbsOrigin()["x"]
            local positiony = entities.GetLocalPlayer():GetAbsOrigin()["y"]
            local positionz = entities.GetLocalPlayer():GetAbsOrigin()["z"]
            
            table.insert(tickMoves, viewAnglesPitch)
            table.insert(tickMoves, viewAnglesYaw)
            table.insert(tickMoves, viewAnglesRoll)

            table.insert(tickMoves, forwardMove)
            table.insert(tickMoves, sideMove)
            table.insert(tickMoves, upMove)

            table.insert(tickMoves, buttons)

            table.insert(tickMoves, positionx)
            table.insert(tickMoves, positiony)
            table.insert(tickMoves, positionz)

            table.insert(localMovements, tickMoves)
        end

        if playback then

            if not atStart then
                local absorigin = entities.GetLocalPlayer():GetAbsOrigin()
                local dist = vector.Distance( {minMov[1][8], minMov[1][9], minMov[1][10]}, {absorigin["x"], absorigin["y"], absorigin["z"]} )
                if lastDistance ~= dist or dist > 1 then
                    cmd:SetForwardMove(dist * SETTINGS_SPEED:GetValue())
                    cmd:SetSideMove(0)

                    local _1, _2, _3 = vector.Subtract( {minMov[1][8], minMov[1][9], minMov[1][10]}, {absorigin["x"], absorigin["y"], absorigin["z"]} )  
                    local vectorangles1, vectorangles2, vectorangles3 = vector.Angles({_1, _2, _3})
                    moveToStart(vectorangles2, cmd)
                    lastDistance = dist

                    return
                else
                    atStart = true
                end
            end

            if not snapped and PLAYBACK_SNAPSMOOTH:GetValue() ~= 0 then
                local angle = engine.GetViewAngles() - snapAngle

                if angle["yaw"] > 300 then angle["yaw"] = (360 - angle["yaw"]) * -1
                elseif angle["yaw"] < -300 then angle["yaw"] = (-360 - angle["yaw"]) * -1 end
                local smooth = PLAYBACK_SNAPSMOOTH:GetValue() * 5
            
                if angle["pitch"] < 5 and angle["yaw"] < 5 then smooth = smooth / 1.25 end
            
                local smoothedAngle = angle / smooth
                smoothedAngle["roll"] = 0
                engine.SetViewAngles(engine.GetViewAngles() - smoothedAngle) 

                if angle["pitch"] < 0.05 and angle["yaw"] < 0.05 then snapped = true else return end
            end

            if playbackIterator <= table.getn(minMov) then
                local tickMove = minMov[playbackIterator]

                engine.SetViewAngles( EulerAngles(tickMove[1], tickMove[2], tickMove[3]) )
                --cmd:SetViewAngles(EulerAngles(tickMove[1], tickMove[2], tickMove[3]))
                --cmd.viewangles = EulerAngles(tickMove[1], tickMove[2], tickMove[3])
                cmd:SetForwardMove(tickMove[4])
                cmd:SetSideMove(tickMove[5])
                cmd:SetUpMove(tickMove[6])
                cmd:SetButtons(tickMove[7])

                playbackIterator = playbackIterator + 1
            else
                playback = false
                if PLAYBACK_SETTINGS_SWITCHBACK:GetValue() then
                    if lastWeapon == 1 then
                        client.Command( "slot2", true )
                    elseif lastWeapon == 2 or lastWeapon == 3 or lastWeapon == 4 or lastWeapon == 5 or lastWeapon == 6 then
                        client.Command( "slot1", true )
                    elseif lastWeapon == 0 or lastWeaponID == 31 then
                        client.Command( "slot3", true )
                    elseif lastWeapon == 9 then
                        client.Command( "slot4", true )
                    elseif lastWeapon == 7 then
                        client.Command( "slot5", true )
                    end
                end
            end
        end
    end
end )
