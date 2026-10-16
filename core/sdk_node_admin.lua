-- SDK node maintenance controls. Never bypass signed remote ACL.
local M={}
function M.install(app,options)
    options=options or {}
    local enabled=options.enabled==true
    for _,action in ipairs({"package_update","package_configure"}) do
        app:control("node_"..action,{
            label=action,remote=true,monitor=false,
            enabled=function()
                return enabled and type(options.actions)=="table"
                    and options.actions[action]==true
            end,
            run=function(args)
                if not enabled or type(options.actions)~="table"
                    or options.actions[action]~=true then
                    return false,"administration disabled"
                end
                if type(args)~="table" or type(args.package)~="string"
                    or #args.package<1 or #args.package>80
                    or not args.package:match("^[%w_.%-]+$") then
                    return false,"invalid package"
                end
                local packageName=args.package
                return app:deferAfterAck(function()
                    local ok,result=require("lib.admin_control").handle({
                        action=action,package=packageName})
                    if not ok then
                        app:log("error",action..": "..tostring(result))
                    end
                end)
            end
        })
    end
    app:control("node_reboot",{
        label="Reboot node",remote=true,monitor=false,
        enabled=function()
            return enabled and type(options.actions)=="table"
                and options.actions.reboot==true
        end,
        run=function(args)
            if not enabled or type(options.actions)~="table"
                or options.actions.reboot~=true then
                return false,"reboot disabled"
            end
            if type(args)~="table" or args.confirm~=true then
                return false,"explicit confirmation required"
            end
            return app:deferAfterAck(function() os.reboot() end)
        end
    })
end
return M
