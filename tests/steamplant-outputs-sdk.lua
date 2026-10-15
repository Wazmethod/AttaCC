-- Hardware-free API contract for native SteamPlant outputs.
local writes,calls={},{}
local app={}
local stored={}
function app:state(key,value)
    if value~=nil then stored[key]=value;return true end
    return stored[key]
end
function app:output(role)
    assert(role=="main_clutch" or role=="alternator_clutch" or role=="gen_clutch")
    return {set=function(_,value) writes[role]=value;return true end}
end
function app:read(role) return writes[role] end
function app:call(role,method,...)
    calls[#calls+1]={role,method,...}
    if role=="speedometer" then return 128 end
    return nil
end
function app:config(key,default) return default end
function app:hardwareStatus() return {},true end
local outputs=dofile("apps/steamplant/outputs_sdk.lua").setup(app)
assert(outputs.setMain(true))
assert(outputs.mainEngaged()==true)
assert(outputs.setAlternator(false))
assert(outputs.alternatorEngaged()==false)
assert(outputs.setGen(true))
assert(outputs.genEngaged()==true)
assert(outputs.setMotorSpeed(64))
assert(calls[#calls][1]=="motor" and calls[#calls][2]=="setSpeed" and calls[#calls][3]==64)
assert(outputs.stopMotor())
assert(calls[#calls][2]=="stop")
assert(outputs.getSpeed()==128)
assert(outputs.getOutputState().motorRPM==0)
local ok,err=outputs.setMotorSpeed(0/0)
assert(ok==false and type(err)=="string")
print("SteamPlant native outputs contract: OK")
