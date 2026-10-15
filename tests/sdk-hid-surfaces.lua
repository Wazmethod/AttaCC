-- Regression: CraftOS mouse and external monitor touch target separate UI.
local calls={}
local app={
    maintenanceTouch=function(_,_,x,y)
        calls[#calls+1]={"maintenance",x,y}
        return true
    end,
    touch=function(_,_,x,y)
        calls[#calls+1]={"monitor",x,y}
        return true
    end
}
local monitor={
    getSize=function(mode)
        assert(mode==0)
        return 20,10
    end
}
local oldPeripheral=peripheral
peripheral={wrap=function(name)
    assert(name=="monitor_0")
    return monitor
end}
local hid=dofile("core/sdk_hid.lua").new(app,{monitorName="monitor_0"})
hid:setRender({ok=true,backend="maintenance"},"maintenance")
hid:setRender({ok=true,backend="ccgraphics",width=200,height=100},"monitor")
assert(hid:handle("mouse_click",1,8,4))
assert(calls[1][1]=="maintenance" and calls[1][2]==8 and calls[1][3]==4)
assert(hid:handle("monitor_touch","monitor_0",10,5))
assert(calls[2][1]=="monitor")
assert(calls[2][2]>=90 and calls[2][2]<=100)
assert(calls[2][3]>=40 and calls[2][3]<=50)
assert(not hid:handle("monitor_touch","monitor_1",10,5))
peripheral=oldPeripheral
print("SDK HID surfaces: OK")
