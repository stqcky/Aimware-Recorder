-- Movement Recorder by stacky

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

local minMov = nil
local visibleMoves = nil

local lastWeapon = 0
local lastWeaponID = 0

local FONT = draw.CreateFont("Verdana", 30, 2000)

-- Some functions

local function fetchRecordings(filename)
    if string.match(filename, ".dat") then
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

    if math.floor((entities.GetLocalPlayer():GetPropInt("m_fFlags") % 4) / 2) == 1 then
        origin.z = origin.z + 46
    else
        origin.z = origin.z + 64 
    end

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

-- Main Menu

local WINDOW = gui.Window( "movrec", "Movement Recorder", 100, 100, 430, 360 ) 

local RECORDINGS_GBOX = gui.Groupbox( WINDOW, "Manage Recordings", 10, 10, 410, 0 )
RECORDINGS_GBOX:SetInvisible(true)

local SETTINGS_GBOX = gui.Groupbox( WINDOW, "Settings", 10, 10, 200, 0 )
local RECORD_GBOX = gui.Groupbox( WINDOW, "Record", 220, 10, 200, 0 )
local PLAYBACK_GBOX = gui.Groupbox( WINDOW, "Playback", 220, 158, 200, 0 )

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
end)


-- Main Menu Record
local RECORD_KEY = gui.Keybox( RECORD_GBOX, "record.key", "Record Key", 0 )

-- Main Menu Playback
local PLAYBACK_KEY = gui.Keybox( PLAYBACK_GBOX, "playback.key", "Playback Key", 0 )
local PLAYBACK_SETTINGS = gui.Multibox( PLAYBACK_GBOX, "Playback Settings" )
local PLAYBACK_SETTINGS_SWITCHKNIFE = gui.Checkbox( PLAYBACK_SETTINGS, "playback.settings.switchknife", "Switch to Knife", false )
local PLAYBACK_SETTINGS_SWITCHBACK = gui.Checkbox( PLAYBACK_SETTINGS, "playback.settings.switchback", "Switch Back", false )

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
            print("%" .. chars[i])
            fileName = string.gsub(fileName, chars[i], "")
        end
        print(fileName)

        writer = file.Open( fileName, "w")
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

local RECORDINGS_DELETE = gui.Button( RECORDINGS_GBOX, "Delete", function()
    local name = savedRecordings[RECORDINGS_SAVED:GetValue() + 1]
    file.Delete(name)
    refreshSaved()
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
    WINDOW:SetHeight(360)
end )
RECORDINGS_GOBACK:SetPosX(230)
RECORDINGS_GOBACK:SetPosY(340)

local function moveToStart(destination, cmd)
    deg2rad = (math.pi / 180)
    local deltaView, f1, f2
    viewangle_x = cmd:GetViewAngles()["pitch"]
    viewangle_y = cmd:GetViewAngles()["yaw"]
    viewangle_z = cmd:GetViewAngles()["roll"]
    fOldForward = cmd:GetForwardMove()
    fOldSidemove = cmd:GetSideMove()

    if (destination < 0) then f1 = 360 + destination else f1 = destination end
    if (viewangle_y < 0) then f2 = 360 + viewangle_y else f2 = viewangle_y end
    if (f2 < f1) then deltaView = math.abs(f2 - f1) else deltaView = 360 - math.abs(f1 - f2) end

    deltaView = 360 - deltaView

    cmd:SetForwardMove( math.cos( (deg2rad*deltaView) ) * fOldForward + math.cos( (deg2rad*(deltaView + 90)) ) * fOldSidemove )
    cmd:SetSideMove( math.sin( (deg2rad*deltaView) ) * fOldForward + math.sin( (deg2rad*(deltaView + 90)) ) * fOldSidemove )
end

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
                minMov = findClosest()
                playback = not playback
            end
        end

        if SETTINGS_INDICATORS:GetValue() then
            if recording then
                drawIndicator("-- RECORDING --")
            elseif playback then 
                if atStart then
                    drawIndicator("-- PLAYBACK --")
                else
                    drawIndicator("-- GOING TO START POSITION --")
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
                        drawStart(loadedMovements[k][1][8], loadedMovements[k][1][9], loadedMovements[k][1][10], k:gsub("%.dat", ""))
                    end
                end
            else
                if visibleMoves ~= nil then
                    for k, v in pairs(visibleMoves) do
                        drawStart(v[1][8], v[1][9], v[1][10], k:gsub("%.dat", ""))
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
            tickMoves = {}

            viewAnglesPitch = engine.GetViewAngles()["pitch"]
            viewAnglesYaw = engine.GetViewAngles()["yaw"]
            viewAnglesRoll = engine.GetViewAngles()["roll"]

            forwardMove = cmd:GetForwardMove()
            sideMove = cmd:GetSideMove()
            upMove = cmd:GetUpMove()

            buttons = cmd:GetButtons()

            positionx = entities.GetLocalPlayer():GetAbsOrigin()["x"]
            positiony = entities.GetLocalPlayer():GetAbsOrigin()["y"]
            positionz = entities.GetLocalPlayer():GetAbsOrigin()["z"]
            
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
                absorigin = entities.GetLocalPlayer():GetAbsOrigin()
                dist = vector.Distance( {minMov[1][8], minMov[1][9], minMov[1][10]}, {absorigin["x"], absorigin["y"], absorigin["z"]} )
                if lastDistance ~= dist or dist > 1 then
                    cmd:SetForwardMove(dist * SETTINGS_SPEED:GetValue())
                    cmd:SetSideMove(0)

                    _1, _2, _3 = vector.Subtract( {minMov[1][8], minMov[1][9], minMov[1][10]}, {absorigin["x"], absorigin["y"], absorigin["z"]} )  
                    vectorangles1, vectorangles2, vectorangles3 = vector.Angles({_1, _2, _3})
                    moveToStart(vectorangles2, cmd)
                    lastDistance = dist
                else
                    atStart = true
                end
                return
            end

            if playbackIterator <= table.getn(minMov) then
                tickMove = minMov[playbackIterator]

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
