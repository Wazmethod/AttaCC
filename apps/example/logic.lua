local M={}
function M.setup(app)
    app:data("ticks",{label="Runtime ticks",unit="ticks",value=0})
    app:control("reset",{label="Reset counter",run=function()
        app:set("ticks",0)
        return true
    end})
    app:on("example.increment",function()
        local count=0
        for _,item in ipairs(app:values()) do
            if item.id=="ticks" then count=item.value or 0 end
        end
        app:set("ticks",count+1)
    end)
end
return M
