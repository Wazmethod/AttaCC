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
                return require("lib.admin_control").handle({
                    action=action,package=args.package})
            end
        })
    end
end
return M
