local component = require("component")
local tape = component.tape_drive
local path = ...

assert(tape, "No tape drive found")
assert(tape.isReady(), "No tape inserted in tape drive")
assert(path, "Usage: lua loadtape.lua file.dfpwm")

tape.stop()
tape.seek(-tape.getSize()) -- rewind

local f = assert(io.open(path, "rb"))

local function writeChunk(chunk)
  -- some versions accept a raw string
  local ok = pcall(tape.write, chunk)
  if ok then return end
  -- fallback: byte array
  local t = {}
  for i = 1, #chunk do t[i] = chunk:byte(i) end
  tape.write(t)
end

local written = 0
while true do
  local chunk = f:read(8192)
  if not chunk then break end
  writeChunk(chunk)
  written = written + #chunk
end

f:close()
tape.seek(-tape.getSize())
print("Wrote " .. written .. " bytes to tape.")
