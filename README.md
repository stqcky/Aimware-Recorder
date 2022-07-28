# Aimware Lua Movement Recorder

Demo: https://www.youtube.com/watch?v=cX_7ekpMTSg

### How to convert old recording to v1.2 format:
1. Load the "1.1to1.2" lua
2. Select the recording and press convert button in an opened window
3. Place the converted recording in *aw folder*/movement recordings/*mapname*

OR

1. Rename a file to have an extension ".mr.dat"
2. Replace "\[\d+\]=\{\d+\},\r?\n" regex with ""
3. Replace "\{\r?\n\}," regex with ""