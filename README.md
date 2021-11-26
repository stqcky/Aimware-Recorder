# Aimware Lua Movement Recorder

Demo: https://www.youtube.com/watch?v=cX_7ekpMTSg

### How to port old recording to v1.2 format:
1. Rename a file to have an extension ".mr.dat"
2. Replace "\[\d+\]=\{\d+\},\r?\n" regex with ""
3. Replace "\{\r?\n\}," regex with ""