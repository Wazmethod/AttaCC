-- Run on Master (ID 1) alongside the local Steam Plant app.
local WS_URL = "ws://YOUR_SERVER:8080/ws/machine"
local MACHINE_TOKEN = "change-me-machine-token"

local TELEMETRY, CONTROL, ACK, EVENTS = 4242, 4245, 4246, 4247
local modem = peripheral.find("modem", function(_,p) return p.isWireless and p.isWireless() end)
if not modem then error("Wireless modem introuvable") end
modem.open(TELEMETRY); modem.open(ACK); modem.open(EVENTS)

local function connect()
  while true do
    local ws,err=http.websocket(WS_URL,{Authorization="Bearer "..MACHINE_TOKEN})
    if ws then print("WebSocket connected"); return ws end
    print("WebSocket error: "..tostring(err)); sleep(3)
  end
end

local ws=connect()
local function send(obj)
  local raw=textutils.serializeJSON(obj)
  local ok=pcall(function() ws.send(raw) end)
  if not ok then pcall(function() ws.close() end); ws=connect(); ws.send(raw) end
end

local function websocketLoop()
  while true do
    local raw=ws.receive()
    if raw==nil then ws=connect()
    else
      local msg=textutils.unserializeJSON(raw)
      if type(msg)=="table" and msg.type=="command" then
        modem.transmit(CONTROL,CONTROL,{
          target="steam_plant",command=msg.command,rpm=msg.rpm,
          origin="web",id=msg.id,timestamp=os.epoch("utc")
        })
      end
    end
  end
end

local function modemLoop()
  while true do
    local _,_,channel,_,m=os.pullEvent("modem_message")
    if channel==TELEMETRY and type(m)=="table" and m.source=="steam_plant" then
      send({type="telemetry",data=m,timestamp=os.epoch("utc")})
    elseif channel==EVENTS and type(m)=="table" and m.type=="plant_event" then
      send({type="event",level=m.level,code=m.code,message=m.message,timestamp=m.timestamp or os.epoch("utc")})
    elseif channel==ACK and type(m)=="table" and m.type=="command_ack" and m.id and tostring(m.id):match("^web%-") then
      send({type="command_ack",id=m.id,command=m.command,ok=m.ok,error=m.error,timestamp=os.epoch("utc")})
    end
  end
end

parallel.waitForAny(websocketLoop,modemLoop)
