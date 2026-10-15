-- Unit-level contract for SDK-only application discovery.
local snap=require("lib.sdk_snapshot")
local desc={
    schema="attacc.sdk.app.v1",id="example",title="Generic example",
    data={{id="pressure",label="Pressure",value=42,unit="bar"}},
    graphs={{id="pressure",label="Pressure",unit="bar",
        samples={{timestamp=1,value=41},{timestamp=2,value=42}}}},
    controls={{id="open",label="Open",remote=true,enabled=true},
        {id="local",label="Local only",remote=false,enabled=true}},
    hardware={private={peripheral="not-on-wire"}},
}
local wire,err=snap.frame(desc,"cc:test","default",1234)
assert(wire,err)
assert(wire.descriptor.hardware==nil)
assert(#wire.descriptor.graphs[1].samples==1)
assert(wire.descriptor.graphs[1].samples[1].value==42)
local compat,problem=snap.compat(wire)
assert(compat,problem)
assert(compat.ui.app.id=="example")
assert(compat.ui.metrics[1].value==42)
assert(compat.ui.graphs[1].value==42)
assert(#compat.ui.controls==1)
assert(compat.ui.controls[1].command=="open")
assert(snap.compat({type="wrong"})==nil)
print("SDK snapshot wire-to-UI compatibility: OK")
