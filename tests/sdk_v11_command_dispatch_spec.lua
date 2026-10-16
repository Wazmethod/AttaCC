-- SDK command dispatch smoke test: no peripherals and no live machine.
package.path="./core/?.lua;"..package.path
local oldEpoch=os.epoch
os.epoch=function() return 100000 end
textutils={serializeJSON=function(x)
  if type(x)=="boolean" then return tostring(x) end
  if type(x)=="number" then return tostring(x) end
  if type(x)=="string" then return string.format("%q",x) end
  error("unsupported test JSON")
end}
local cmds=require("sdk_commands")
local count=0
local app={id="test_app",controls={demo={remote=true}}}
function app:invoke(id,args)
  assert(id=="demo" and args.confirm==true)
  count=count+1
  return true,true
end
local dispatcher=cmds.new(app,{machine="generator",network="plant",
  authorize=function(msg) return msg.origin=="master" end,
  signAck=function() return "test-hmac" end})
local function request(id)
  return {type="attacc.sdk.command.v1",id=id,app="test_app",control="demo",
    origin="master",target="generator",network="plant",timestamp=100000,
    args={confirm=true}}
end
local first=dispatcher:handle(request("r1"))
assert(first and first.ok and first.auth.signature=="test-hmac")
assert(count==1)
local duplicate=dispatcher:handle(request("r1"))
assert(duplicate and duplicate.ok and count==1,"duplicate executed control")
local unauthorized=request("r2");unauthorized.origin="stranger"
local denied=dispatcher:handle(unauthorized)
assert(denied and denied.ok==false and count==1)
local wrongTarget=request("r3");wrongTarget.target="other"
assert(dispatcher:handle(wrongTarget).ok==false and count==1)
local wrongNetwork=request("r4");wrongNetwork.network="other"
assert(dispatcher:handle(wrongNetwork).ok==false and count==1)
local stale=request("r5");stale.timestamp=1
assert(dispatcher:handle(stale).ok==false and count==1)
local unsigned=cmds.new(app,{machine="generator",network="plant",
  authorize=function() return true end})
assert(unsigned:handle(request("r6"))==nil,"unsigned ACK permitted")
assert(count==1,"unsigned ACK path executed a command")
os.epoch=oldEpoch
print("SDK command dispatch smoke checks passed")
