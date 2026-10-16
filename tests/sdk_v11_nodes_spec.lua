package.path="./core/?.lua;"..package.path
local nodes=require("sdk_nodes").new({network="plant"},{staleMs=12000})
local frame={type="attacc.sdk.node.v1",key="node-a",network="plant",
    computerId=4,hostname="Alpha"}
local ok=nodes:accept(frame,"node-a")
assert(ok==true)
assert(nodes:get("node-a").hostname=="Alpha")
local spoofed={type=frame.type,key="node-b",network="plant",
    computerId=4,hostname="Spoof"}
ok=nodes:accept(spoofed,"node-a")
assert(ok==false)
assert(nodes:get("node-b")==nil)
local conflicting={type=frame.type,key="node-a",network="plant",
    computerId=5,hostname="Conflicting"}
ok=nodes:accept(conflicting,"node-a")
assert(ok==false)
assert(nodes:get("node-a").conflict==true)
print("SDK authenticated node discovery tests passed")
