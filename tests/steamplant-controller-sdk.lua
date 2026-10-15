-- Contract test: SteamPlant native controller with simulated SDK app and IO.
local config=dofile("apps/steamplant/config.lua")
local persistent={}
local function walk(path)
    local node=config
    for key in path:gmatch("[^%.]+") do
        if type(node)~="table" then return nil end
        node=node[key]
    end
    return node
end
local app={}
function app:config(path,fallback)
    local value=walk(path)
    return value==nil and fallback or value
end
function app:state(key,value)
    if value~=nil then persistent[key]=value;return true end
    return persistent[key]
end
local values={main=true,alternator=true,gen=false,motorRPM=0}
local writes={}
local io={}
function io.restoreOutputs() return true,nil,"config" end
function io.getOutputState() return values end
function io.setMain(value) values.main=value;writes[#writes+1]="main";return true end
function io.setAlternator(value) values.alternator=value;writes[#writes+1]="alternator";return true end
function io.setGen(value) values.gen=value;writes[#writes+1]="gen";return true end
function io.mainEngaged() return values.main end
function io.alternatorEngaged() return values.alternator end
function io.genEngaged() return values.gen end
function io.setMotorSpeed(value)
    if type(value)~="number" or value~=value or value==math.huge then
        return false,"invalid RPM"
    end
    values.motorRPM=value
    return true
end
function io.stopMotor() values.motorRPM=0;return true end
function io.getSpeed() return 0 end
function io.call(role,method,default) return default end
local controller=dofile("apps/steamplant/controller.lua").setup(app,io)
assert(controller.getState()=="BOOT")
assert(controller.prepareBootOutputs())
assert(controller.initialize({rpm=0,capacity=0})=="OFFLINE")
assert(controller.executeCommand("arm"))
assert(controller.isArmed()==true)
assert(persistent.controller and persistent.controller.armed==true)
assert(controller.executeCommand("disarm"))
assert(controller.isArmed()==false)
assert(controller.executeCommand("all_cut"))
assert(values.main==false and values.gen==false and values.alternator==false)
assert(values.motorRPM==0)
local ok,reason=controller.executeCommand("motor_speed",{rpm=math.huge})
assert(ok==false and type(reason)=="string")
local bad,why=controller.executeCommand("unknown_command")
assert(bad==false and type(why)=="string")
print("SteamPlant native controller contract: OK")
