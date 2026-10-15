local attacc=require("lib.attacc")
local app=attacc.app("example",{title="AttaCC SDK Example"})
app:requirements()
app:require("core.runtime")
require("logic").setup(app)
require("views").setup(app)
return app
