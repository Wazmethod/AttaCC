local M={}
function M.setup(app)
    app:view("main",{label="SDK Example",layout="dashboard",
        data={"ticks"},controls={"reset"}})
end
return M
