-- Offline-compatible unit assertions for pure SHA-256 and SDK request signatures.
-- Designed for running under a mocked CraftOS host; do NOT trigger actuators.
local sha = require("lib.sha256")
assert(sha.digest("") ==
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
assert(sha.digest("abc") ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
local auth=require("lib.sdk_auth")
local key=string.rep("test-key-",5)
local request={
    type="attacc.sdk.command.v1",app="steamplant",control="motor_stop",
    origin="master",target="cc:generator",network="infra-main",
    id="test-request-123",timestamp=1000,args={}
}
local signature,err=auth.sign(request,key)
assert(signature,err)
request.auth={version=1,signature=signature}
local policy={peers={master={enabled=true,key=key,controls={motor_stop=true}}}}
assert(auth.authorize(request,policy))
request.control="procedure"
assert(not auth.authorize(request,policy))
request.control="motor_stop"
request.args.rpm=999
assert(not auth.authorize(request,policy))
print("SDK crypto vectors and tamper rejection: OK")
