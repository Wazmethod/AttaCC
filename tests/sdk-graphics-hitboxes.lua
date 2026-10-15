-- Hardware-free regression: CC:Graphics hitboxes are pixel rectangles.
local fakeRequire=function(name)
    if name=="lib.display_sdk" then return {hit=function()
        error("text hit tester must not handle CC:Graphics")
    end} end
    if name=="lib.display_graphics" then return {} end
    error("unexpected dependency: "..tostring(name))
end
local env=setmetatable({require=fakeRequire},{__index=_G})
local renderer=assert(loadfile("modules/display_sdk_graphics.lua","t",env))()
local result={ok=true,backend="ccgraphics",hitboxes={
    {id="show_overview",x1=10,y1=30,x2=80,y2=48},
    {id="show_status",x1=90,y1=30,x2=160,y2=48},
}}
assert(renderer.hit(result,25,40)=="show_overview")
assert(renderer.hit(result,110,40)=="show_status")
assert(renderer.hit(result,25,29)==nil)
assert(renderer.hit(result,170,40)==nil)
print("SDK graphics rectangle hit testing: OK")
