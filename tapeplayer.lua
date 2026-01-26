local component=require("component")
local event=require("event")
local term=require("term")
local computer=require("computer")

local tape=component.tape_drive or component.tape
assert(tape,"No tape_drive")
assert(tape.isReady and tape.isReady(),"No tape inserted")
assert(tape.getSize,"Tape API missing getSize()")

-- args
local speed,vol=1.0,1.0
local inf=false
local loops=1
local ui=0.20

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function usage()
  term.clear()
  term.setCursor(1,1)
  term.write("Usage: lua tapeplayer.lua [--loop|--loops N] [--speed X] [--volume X] [--ui SEC]\n")
  term.write("Keys: q stop | space pause | +/= faster | - slower\n")
  os.exit(2)
end

local args={...}
local i=1
while i<=#args do
  local a=tostring(args[i])
  if a=="--help" or a=="-h" then usage()
  elseif a=="--loop" then inf=true
  elseif a=="--loops" then local n=tonumber(args[i+1]); if not n or n<1 then usage() end; loops=math.floor(n); i=i+1
  elseif a=="--speed" then local x=tonumber(args[i+1]); if not x then usage() end; speed=clamp(x,0.25,2.0); i=i+1
  elseif a=="--volume" then local x=tonumber(args[i+1]); if not x then usage() end; vol=clamp(x,0,1); i=i+1
  elseif a=="--ui" then local x=tonumber(args[i+1]); if not x then usage() end; ui=clamp(x,0.05,1.0); i=i+1
  else usage() end
  i=i+1
end

local total=tape.getSize()
assert(total>0,"Tape size 0?")

local function rewind()
  tape.stop()
  tape.seek(-tape.getSize())
end

local paused=false
local done=0

-- timekeeping for estimated progress (no getPosition() needed)
local start=0
local pausedAt=0
local pausedAcc=0
local function clockStart() start=computer.uptime(); pausedAt=0; pausedAcc=0 end
local function elapsed()
  local now=computer.uptime()
  if paused and pausedAt>0 then return pausedAt-start-pausedAcc end
  return now-start-pausedAcc
end

local function setSpeed(s) speed=clamp(s,0.25,2.0); if tape.setSpeed then tape.setSpeed(speed) end end
local function setVol(v)   vol=clamp(v,0,1);     if tape.setVolume then tape.setVolume(vol) end end

local function togglePause()
  paused=not paused
  if paused then
    pausedAt=computer.uptime()
    tape.stop()
  else
    pausedAcc=pausedAcc+(computer.uptime()-pausedAt)
    pausedAt=0
    tape.play()
  end
end

-- terminal width (avoid wrapping: always write <= w-1 chars)
local function termWidth()
  if term.getViewport then
    local a,b,c,d = term.getViewport()
    if a and b and c and d then
      -- either (x,y,w,h) or (x1,y1,x2,y2) depending on OC/OpenOS build
      if a==1 and b==1 then return c end
      if c>=a then return (c-a+1) end
    end
  end
  if component.isAvailable("gpu") then
    local w = select(1, component.gpu.getResolution())
    if w and w>0 then return w end
  end
  return 80
end

local function mkbar(p, w)
  p=clamp(p,0,1)
  local f=math.floor(p*w+0.5)
  return string.rep("=",f)..string.rep(".",w-f)
end

-- DFPWM stream estimate: ~4096 bytes/sec at speed 1.0
local BPS=4096

local function drawStatus(extra)
  local w=termWidth()
  local maxLen = math.max(20, w-1) -- never write full width, prevents wrap
  local secs=math.max(0, elapsed())
  local estBytes=secs*BPS*speed
  local p=clamp(estBytes/total,0,1)
  local pct=math.floor(p*100+0.5)

  local loopTxt = inf and (tostring(done).."/∞") or (tostring(done).."/"..tostring(loops))
  local tail = string.format(" %3d%% sp%.2f v%.2f L%s%s", pct, speed, vol, loopTxt, extra and (" "..extra) or "")

  local barW = 28
  local line = "["..mkbar(p, barW).."]"..tail
  if #line > maxLen then line = line:sub(1, maxLen) end
  -- pad to erase leftovers from previous frame, but still <= maxLen
  if #line < maxLen then line = line .. string.rep(" ", maxLen-#line) end

  term.setCursor(1,2)
  term.write(line)
end

local function main()
  term.clear()
  term.setCursor(1,1)
  term.write("Keys: q stop | space pause | +/= faster | - slower\n")
  -- line 2 is reserved for progress

  setVol(vol); setSpeed(speed)
  rewind(); clockStart(); tape.play()

  local last=0
  while true do
    local now=computer.uptime()
    if now-last>=ui then
      drawStatus(paused and "(paused)" or nil)
      last=now
    end

    if tape.isEnd and tape.isEnd() then
      done=done+1
      if inf or done<loops then
        rewind(); clockStart()
        if not paused then tape.play() end
      else
        break
      end
    end

    local _,_,ch=event.pull(0.10,"key_down")
    if ch then
      if ch==113 or ch==81 then break -- q/Q
      elseif ch==32 then togglePause()
      elseif ch==43 or ch==61 then setSpeed(speed+0.05) -- + or =
      elseif ch==45 then setSpeed(speed-0.05) -- -
      end
    end
  end

  tape.stop()
  drawStatus("done")
  term.setCursor(1,3)
  term.write("Stopped.\n")
end

local ok,err=pcall(main)
if not ok then pcall(function() tape.stop() end)
  term.setCursor(1,4)
  term.write("ERROR: "..tostring(err).."\n")
end
