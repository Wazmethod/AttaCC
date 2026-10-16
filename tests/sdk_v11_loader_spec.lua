-- App loader must share SDK lib modules, while app-local modules remain private.
package.path="./core/?.lua;"..package.path
local path="apps/example/main.lua"
local seen={}
local originalFs,originalLoadfile,originalRequire=fs,loadfile,require
fs={
 combine=function(a,b) return a.."/"..b end,
 exists=function(p) return p==path end,
 isDir=function() return false end,
}
local appSdk={marker="shared-sdk"}
local shared={marker="shared-services"}
package.loaded["lib.attacc"]=appSdk
package.loaded["lib.sdk_services"]=shared
loadfile=function(filename,mode,env)
    assert(filename==path)
    return function()
        seen.sdk=env.require("lib.attacc")
        seen.services=env.require("lib.sdk_services")
        return seen
    end
end
local loader=require("app_loader")
local result,err=loader.load("example")
assert(result,err)
assert(result.sdk==appSdk)
assert(result.services==shared)
fs,loadfile=originalFs,originalLoadfile
print("SDK shared module loader checks passed")
