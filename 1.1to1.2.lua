local GUI = {}
local RecordingConverter = {
    FileList = {}
}

GUI.Window        = gui.Window("convert", "Convert Movement Recordings", 300, 300, 314, 455)
GUI.Groupbox      = gui.Groupbox(GUI.Window, "Converter", 7, 7, 300, 0)
GUI.FileList      = gui.Listbox(GUI.Groupbox, "filelist", 300, "Nothing found")
gui.RefreshButton = gui.Button(GUI.Groupbox, "Refresh", function() RecordingConverter:UpdateFileList() end)
GUI.ConvertButton = gui.Button(GUI.Groupbox, "Convert", function() RecordingConverter:Convert() end); GUI.ConvertButton:SetPosX(140); GUI.ConvertButton:SetPosY(316)

function RecordingConverter:UpdateFileList()
    self.FileList = {}

    file.Enumerate(function(filename)
        if string.find(filename, ".dat") and not string.find(filename, ".mr.dat") and string.sub(file.Read(filename), 1, 2) == "{{" then
            self.FileList[#self.FileList + 1] = filename
        end
    end)

    GUI.FileList:SetOptions(unpack(self.FileList))
end

function RecordingConverter:GetSelectedFileName()
    return self.FileList[GUI.FileList:GetValue() + 1]
end

function RecordingConverter:Convert()
    local filename = self:GetSelectedFileName()
    local data = file.Read(filename)

    data = string.gsub(data, "%[%d+%]={%d+},\r?\n", "")
    data = string.gsub(data, "{\r?\n},", "")

    file.Delete(filename)
    file.Write(string.sub(filename, 1, -5) .. ".mr.dat", data)

    self:UpdateFileList()
end

local function main()
    RecordingConverter:UpdateFileList()
end

main()