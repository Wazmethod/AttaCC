import express from "express";
import { WebSocketServer } from "ws";
import fs from "node:fs";
import path from "node:path";
import http from "node:http";

const PORT = Number(process.env.PORT || 8080);
const MACHINE_TOKEN = process.env.MACHINE_TOKEN || "change-me-machine-token";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "change-me-admin-token";
const HISTORY_LIMIT = Number(process.env.HISTORY_LIMIT || 500);
const EVENTS_FILE = "/data/events.jsonl";

fs.mkdirSync("/data", {recursive:true});

const app = express();
app.use(express.json({limit:"256kb"}));
app.use(express.static("public"));
const server = http.createServer(app);
const wss = new WebSocketServer({noServer:true});

let machine = null;
let latest = null;
let latestAt = 0;
let events = [];

if (fs.existsSync(EVENTS_FILE)) {
  events = fs.readFileSync(EVENTS_FILE,"utf8").split("\n").filter(Boolean)
    .slice(-HISTORY_LIMIT).map(x=>{try{return JSON.parse(x)}catch{return null}})
    .filter(Boolean).reverse();
}

function addEvent(e) {
  events.unshift(e);
  events = events.slice(0,HISTORY_LIMIT);
  fs.appendFile(EVENTS_FILE, JSON.stringify(e)+"\n", ()=>{});
}
function bearer(req) {
  const h=req.headers.authorization||"";
  return h.startsWith("Bearer ")?h.slice(7):"";
}
function requireAdmin(req,res,next) {
  if ((bearer(req)||req.headers["x-admin-token"]) !== ADMIN_TOKEN)
    return res.status(401).json({error:"unauthorized"});
  next();
}
function machineUp() {
  return machine && machine.readyState === machine.OPEN;
}

app.get("/api/health", (_req,res)=>res.json({ok:true,machineConnected:!!machineUp(),latestAgeMs:latestAt?Date.now()-latestAt:null}));
app.get("/api/status", (_req,res)=>res.json({machineConnected:!!machineUp(),latestAt,latestAgeMs:latestAt?Date.now()-latestAt:null,data:latest}));
app.get("/api/events", (_req,res)=>res.json(events.slice(0,100)));

app.post("/api/command", requireAdmin, (req,res)=>{
  if (!machineUp()) return res.status(503).json({error:"machine_offline"});
  const {command,rpm}=req.body||{};
  if (!command) return res.status(400).json({error:"invalid_command"});
  const id=`web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  machine.send(JSON.stringify({type:"command",id,command,rpm,timestamp:Date.now()}));
  addEvent({timestamp:Date.now(),level:"info",code:"WEB_COMMAND",message:`Web command: ${command}${rpm?` ${rpm} RPM`:""}`});
  res.json({ok:true,id});
});

server.on("upgrade",(req,socket,head)=>{
  const u=new URL(req.url,`http://${req.headers.host}`);
  if (u.pathname!=="/ws/machine") return socket.destroy();
  const token=bearer(req)||u.searchParams.get("token");
  if (token!==MACHINE_TOKEN) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    return socket.destroy();
  }
  wss.handleUpgrade(req,socket,head,ws=>wss.emit("connection",ws,req));
});

wss.on("connection", ws=>{
  if (machine && machine!==ws) try{machine.close(4000,"replaced")}catch{}
  machine=ws;
  addEvent({timestamp:Date.now(),level:"success",code:"MACHINE_CONNECTED",message:"CC:Tweaked Master connected"});

  ws.on("message", buf=>{
    let m; try{m=JSON.parse(buf.toString())}catch{return}
    if (m.type==="telemetry") { latest=m.data; latestAt=Date.now(); }
    else if (m.type==="event") addEvent({timestamp:m.timestamp||Date.now(),level:m.level||"info",code:m.code||"CC_EVENT",message:m.message||"CC event"});
    else if (m.type==="command_ack") addEvent({timestamp:Date.now(),level:m.ok?"success":"critical",code:m.ok?"COMMAND_ACK":"COMMAND_ERROR",message:m.ok?`Command acknowledged: ${m.command}`:`Command failed: ${m.command} - ${m.error||"unknown"}`});
  });

  ws.on("close",()=>{
    if(machine===ws) machine=null;
    addEvent({timestamp:Date.now(),level:"warning",code:"MACHINE_DISCONNECTED",message:"CC:Tweaked Master disconnected"});
  });
});

server.listen(PORT,"0.0.0.0",()=>console.log(`Steam Plant POC listening on :${PORT}`));
