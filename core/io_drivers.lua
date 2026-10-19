-- AttaCC I/O driver registry.
-- The native cc.redstone and cc.peripheral paths remain in io_registry for
-- backward compatibility; third-party adapters register here.
local M={}
local adapters={
    ["create.redstone_link"]="lib.io_driver_create_redstone_link",
}
local descriptions={
    {id="cc.redstone",label="CC / Redstone Relay (built-in)",builtIn=true},
    {id="cc.peripheral",label="Generic CC:Tweaked peripheral (built-in)",builtIn=true},
    {id="create.redstone_link",label="Create Redstone Link Bridge",peripheralType="redstone_link_bridge"},
}

function M.list()
    local result={}
    for _,definition in ipairs(descriptions) do
        result[#result+1]=definition
    end
    return result
end

function M.get(id)
    local module=adapters[id]
    if not module then return nil,"unknown I/O driver: "..tostring(id) end
    local ok,driver=pcall(require,module)
    if not ok then return nil,"cannot load driver "..id..": "..tostring(driver) end
    return driver
end

function M.candidates(id)
    local driver,err=M.get(id)
    if not driver then return nil,err end
    local names={}
    for _,name in ipairs(peripheral.getNames()) do
        if driver.matches(name) then names[#names+1]=name end
    end
    table.sort(names)
    return names
end

function M.resolve(binding,requirement)
    local driver,err=M.get(binding.driver)
    if not driver then return nil,err end
    local ok,reason=driver.validate(binding,requirement)
    if not ok then return nil,reason end
    return binding,nil,driver.describe(binding)
end

function M.read(binding)
    local driver,err=M.get(binding.driver)
    if not driver then return nil,err end
    return driver.read(binding)
end

function M.write(binding,value)
    local driver,err=M.get(binding.driver)
    if not driver then return false,err end
    return driver.write(binding,value)
end
return M
