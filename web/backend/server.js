import express from "express";
import { WebSocketServer, WebSocket } from "ws";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { unzipSync } from "fflate";
import luaparse from "luaparse";
import multer from "multer";
import { execFileSync } from "node:child_process";

const PORT = Number(process.env.PORT || 8080);
const MACHINE_TOKEN = process.env.MACHINE_TOKEN || "change-me-machine-token";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "change-me-admin-token";
const HISTORY_LIMIT = Number(process.env.HISTORY_LIMIT || 1000);
const EVENTS_FILE = "/data/events.jsonl";
const PUBLIC_DIR = process.env.PUBLIC_DIR || "/app/public";
const NODE_STALE_MS = Number(process.env.NODE_STALE_MS || 10000);
const TELEMETRY_STALE_MS = Number(process.env.TELEMETRY_STALE_MS || 10000);

fs.mkdirSync("/data", { recursive: true });

const app = express();
app.use(express.json({ limit: "256kb" }));
app.use(express.static(PUBLIC_DIR));

// Local AttaCC package repository. Read-only over HTTP: no GitHub credentials
// are sent to CC clients, and only the mounted repository tree is exposed.
const REPOSITORY_DIR = path.resolve(process.env.ATTACC_REPOSITORY_DIR || "/repo");
const REPOSITORY_PUBLIC_URL = process.env.ATTACC_REPOSITORY_PUBLIC_URL || "";
function safeRepositoryFile(input) {
  if (typeof input !== "string" || !input || input.includes("\\0")) return null;
  const relative = input.replace(/^\/+/, "");
  if (relative.split("/").some(part => part === ".." || part === "." || part === "")) return null;
  const root = fs.existsSync(path.join("/data/managed-repository","packages/manifest.lua")) ? "/data/managed-repository" : REPOSITORY_DIR;
  const full = path.resolve(root, relative);
  return full.startsWith(root + path.sep) ? full : null;
}
app.get("/api/repository/status", (_req, res) => {
  const manifest = safeRepositoryFile("packages/manifest.lua");
  res.json({
    enabled: fs.existsSync(manifest),
    mode: "filesystem",
    publicUrl: repoSettings().publicUrl,
    manifestReady: fs.existsSync(manifest),
    managed: fs.existsSync("/data/managed-repository/packages/manifest.lua"),
  });
});
app.get("/repo/install.lua", (req,res) => {
  const source = safeRepositoryFile("install.lua");
  if (!source || !fs.existsSync(source)) return res.sendStatus(404);
  const configured = typeof repoSettings === "function" ? repoSettings().publicUrl : "";
  const origin = req.get("host") ? (req.protocol + "://" + req.get("host")) : "";
  const base = (configured || origin + "/repo").replace(/\/+$/,"");
  const sourceText = fs.readFileSync(source,"utf8");
  if (!sourceText.includes("local SOURCE = configuredSource()")) return res.status(503).send("Installer source injection unsupported");
  const updated = sourceText.replace("local SOURCE = configuredSource()", "local SOURCE = configuredSource() or " + JSON.stringify(base));
  res.setHeader("Cache-Control","no-store");
  res.type("text/plain").send(updated);
});
app.get(/^\/repo\/(.+)$/, (req, res) => {
  const candidate = safeRepositoryFile(req.params[0]);
  if (!candidate) return res.sendStatus(400);
  fs.stat(candidate, (err, stat) => {
    if (err || !stat.isFile()) return res.sendStatus(404);
    res.setHeader("Cache-Control", "public, max-age=30");
    const root = fs.existsSync(path.join("/data/managed-repository","packages/manifest.lua")) ? "/data/managed-repository" : REPOSITORY_DIR;
    if (!fs.realpathSync(candidate).startsWith(fs.realpathSync(root) + path.sep)) return res.sendStatus(403);
    res.type("text/plain").sendFile(candidate);
  });
});

const server = http.createServer(app);
const machineWss = new WebSocketServer({ noServer: true });
const browserWss = new WebSocketServer({ noServer: true });

const machines = new Set();
let events = [];
const nodes = new Map();
const telemetry = new Map();
const telemetryHistory = new Map();
const browsers = new Set();
const GRAPH_HISTORY_LIMIT = Number(process.env.GRAPH_HISTORY_LIMIT || 180);

if (fs.existsSync(EVENTS_FILE)) {
  events = fs.readFileSync(EVENTS_FILE, "utf8")
    .split("\n")
    .filter(Boolean)
    .slice(-HISTORY_LIMIT)
    .map(line => {
      try { return JSON.parse(line); } catch { return null; }
    })
    .filter(Boolean)
    .reverse();
}

function machineUp() {
  return [...machines].some(ws => ws.readyState === WebSocket.OPEN);
}

function bridgeCount() {
  return [...machines].filter(ws => ws.readyState === WebSocket.OPEN).length;
}

function sendToNetwork(network, payload) {
  const raw = JSON.stringify(payload);
  const open = [...machines].filter(ws => ws.readyState === WebSocket.OPEN);
  const targeted = open.filter(ws => ws.networks instanceof Set && ws.networks.has(network));
  const targets = targeted.length ? targeted : open;

  for (const ws of targets) ws.send(raw);
  return targets.length;
}

function nodeKey(network, key) {
  return `${network || "default"}::${key}`;
}

function telemetryKey(network, machineKey, module) {
  return `${network || "default"}::${machineKey || "unknown"}::${module || "unknown"}`;
}

function activeNodes() {
  const now = Date.now();
  return [...nodes.values()]
    .map(node => ({
      ...node,
      online: now - node.lastSeen < NODE_STALE_MS,
      ageMs: now - node.lastSeen,
    }))
    .sort((a, b) =>
      String(a.network).localeCompare(String(b.network))
      || String(a.label || a.key).localeCompare(String(b.label || b.key))
    );
}

function activeTelemetry() {
  const now = Date.now();
  return [...telemetry.entries()]
    .map(([key, item]) => ({
      ...item,
      history: telemetryHistory.get(key) || {},
      fresh: now - item.lastSeen < TELEMETRY_STALE_MS,
      ageMs: now - item.lastSeen,
    }))
    .sort((a, b) =>
      String(a.network).localeCompare(String(b.network))
      || String(a.machine).localeCompare(String(b.machine))
      || String(a.module).localeCompare(String(b.module))
    );
}

function networkSummary(nodeList, telemetryList) {
  const byNetwork = new Map();

  function ensure(network, label) {
    const key = network || "default";
    if (!byNetwork.has(key)) {
      byNetwork.set(key, {
        key,
        label: label || key,
        machines: 0,
        onlineMachines: 0,
        modules: 0,
        freshModules: 0,
        conflicts: 0,
        roles: {},
        tags: {},
      });
    }
    const item = byNetwork.get(key);
    if (label && (!item.label || item.label === key)) item.label = label;
    return item;
  }

  for (const node of nodeList) {
    const n = ensure(node.network, node.networkLabel);
    n.machines += 1;
    if (node.online) n.onlineMachines += 1;
    if (node.conflict) n.conflicts += 1;
    const preset = node.preset || node.role || "unknown";
    n.roles[preset] = (n.roles[preset] || 0) + 1;
    for (const tag of node.tags || []) n.tags[tag] = (n.tags[tag] || 0) + 1;
  }

  for (const item of telemetryList) {
    const n = ensure(item.network);
    n.modules += 1;
    if (item.fresh) n.freshModules += 1;
  }
  return [...byNetwork.values()].sort((a, b) => String(a.key).localeCompare(String(b.key)));
}

function snapshot() {
  const nodeList = activeNodes();
  const telemetryList = activeTelemetry();
  const networks = networkSummary(nodeList, telemetryList);

  return {
    type: "snapshot",
    bridgeConnected: machineUp(),
    bridgeCount: bridgeCount(),
    generatedAt: Date.now(),
    stats: {
      bridges: bridgeCount(),
      networks: networks.length,
      machines: nodeList.length,
      onlineMachines: nodeList.filter(n => n.online).length,
      modules: telemetryList.length,
      freshModules: telemetryList.filter(t => t.fresh).length,
      conflicts: nodeList.filter(n => n.conflict).length,
      events: events.length,
    },
    networks,
    nodes: nodeList,
    telemetry: telemetryList,
    events: events.slice(0, 200),
  };
}

function broadcast(payload = snapshot()) {
  const raw = JSON.stringify(payload);
  for (const ws of browsers) {
    if (ws.readyState === WebSocket.OPEN) ws.send(raw);
  }
}

function addEvent(event) {
  const network = event.network || "default";
  const machine = event.machine || null;
  const node = machine
    ? activeNodes().find(item => item.network === network && item.key === machine)
    : null;
  const normalized = {
    timestamp: event.timestamp || Date.now(),
    level: event.level || "info",
    code: event.code || "EVENT",
    message: event.message || "",
    network,
    module: event.module || null,
    machine,
    hostname: event.hostname || node?.hostname || node?.label || machine,
  };

  events.unshift(normalized);
  events = events.slice(0, HISTORY_LIMIT);
  fs.appendFile(EVENTS_FILE, JSON.stringify(normalized) + "\n", () => {});
  broadcast();
}

function bearer(req) {
  const header = req.headers.authorization || "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

function requireAdmin(req, res, next) {
  if ((bearer(req) || req.headers["x-admin-token"]) !== ADMIN_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
}


const repoSettingsFile = "/data/repository-settings.json";
const managedRepo = "/data/managed-repository";
function repoSettings() {
  try { return JSON.parse(fs.readFileSync(repoSettingsFile, "utf8")); }
  catch { return { remote: "https://github.com/Wazmethod/steamplant-cc.git", ref: "dev", publicUrl: REPOSITORY_PUBLIC_URL }; }
}
let repoOperation = false;

function editableRepoPath(relative) {
  if (typeof relative !== "string" || !relative || relative.length > 220 ||
      relative.startsWith("/") || relative.includes("\\") ||
      relative.split("/").some(segment=>!segment || segment==="." || segment===".." || segment.startsWith("."))) return null;
  if (!/^(?:packages|apps|modules|core|docs)\/|^(?:install|pkgctl|version)\.(?:lua|json)$/.test(relative)) return null;
  const full=path.resolve(managedRepo,relative);
  if (!full.startsWith(managedRepo+path.sep)) return null;
  let cursor=path.dirname(full);
  while(cursor.startsWith(managedRepo+path.sep)) {
    if (fs.existsSync(cursor) && fs.lstatSync(cursor).isSymbolicLink()) return null;
    cursor=path.dirname(cursor);
  }
  if(fs.existsSync(full) && fs.lstatSync(full).isSymbolicLink()) return null;
  return full;
}
function initManagedRepo() {
  if (fs.existsSync(path.join(managedRepo,"packages/manifest.lua"))) return;
  if (!fs.existsSync(path.join(REPOSITORY_DIR,"packages/manifest.lua")))
    throw Error("No seed repository mounted: configure ATTACC_REPOSITORY_PATH");
  fs.mkdirSync(managedRepo,{recursive:true});
  fs.cpSync(REPOSITORY_DIR,managedRepo,{
    recursive:true,filter:src=>!path.relative(REPOSITORY_DIR,src).split(path.sep).some(s=>s===".git" || s==="node_modules" || s===".env" || s==="data")
  });
}
function listEditableFiles(root,relative="",out=[]) {
  if(out.length>=2500) return out;
  const dir=path.join(root,relative);
  if (!fs.existsSync(dir)) return out;
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
    if (entry.name.startsWith(".") || entry.name==="node_modules" || entry.name==="data") continue;
    const item=path.posix.join(relative,entry.name);
    if(entry.isDirectory()) listEditableFiles(root,item,out);
    else if(entry.isFile() && editableRepoPath(item)) out.push(item);
  }
  return out;
}


// Atomically register a complete project, not a collection of half-installed files.
// Lua grammar validation checks syntax, not the presence of CraftOS peripherals or runtime APIs.
const packageUpload=multer({storage:multer.memoryStorage(),limits:{fileSize:10*1024*1024,files:1,fields:2}});
function validateLua(src,label) {
  try {luaparse.parse(src,{luaVersion:"5.2"});}
  catch(e){throw Error(label+": Lua syntax: "+e.message);}
}
function packageDefinition(spec,mappings) {
  const q=s=>JSON.stringify(s);
  const dep=spec.depends.map(q).join(", ");
  const entries=mappings.map(m=>"{ src = "+q(m.src)+", dest = "+q(m.dest)+" }").join(", ");
  return '        ["'+spec.name+'"] = {\n'
    +'            kind = '+q(spec.kind)+',\n'
    +'            description = '+q(spec.description)+',\n'
    +'            version = '+q(spec.version||"1.0.0")+',\n'
    +'            depends = { '+dep+' },\n'
    +'            files = { '+entries+' },\n'
    +'        },\n';
}
function validatePackageSpec(spec,imports,root) {
  if(!spec || !["app","module"].includes(spec.kind) ||
    typeof spec.name!=="string" || !new RegExp("^"+spec.kind+"\\.[a-z][a-z0-9-]{1,48}$").test(spec.name) ||
    typeof spec.description!=="string" || spec.description.length>200 ||
    (spec.version!==undefined && (typeof spec.version!=="string" || !/^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?$/.test(spec.version))) ||
    !Array.isArray(spec.depends) || spec.depends.length>20 ||
    spec.depends.some(d=>typeof d!=="string" || !/^[a-z][\w.-]{1,70}$/.test(d)) ||
    !Array.isArray(spec.files) || spec.files.length===0 || spec.files.length>250)
    throw Error("Invalid package name, kind, dependencies or mappings");
  const sourceSet=new Set(imports.map(i=>i.relative));
  const destSet=new Set();
  for(const mapping of spec.files) {
    if(!sourceSet.has(mapping.src) || typeof mapping.dest!=="string" ||
      !/^[\w./-]{1,150}$/.test(mapping.dest) || mapping.dest.split("/").some(s=>!s||s===".."||s===".") ||
      destSet.has(mapping.dest))throw Error("Invalid or repeated source/destination mapping");
    destSet.add(mapping.dest);
  }
}
const multipartPackage=packageUpload.single("archive");
app.post("/api/repository/import-package",requireAdmin,(req,res)=>{
  multipartPackage(req,res,async err=>{
    if(err)return res.status(400).json({error:err.message});
    if(repoOperation)return res.status(409).json({error:"repository busy"});
    repoOperation=true;
    let staged;
    try{
      if(!req.file?.buffer)throw Error("ZIP archive required");
      const spec=JSON.parse(req.body.spec||"null");
      const root=req.body.root;
      if(typeof root!=="string" || !/^(apps|modules)\/[a-zA-Z0-9_/-]+$/.test(root) ||
        root.split("/").some(s=>!s||s===".."||s==="."))throw Error("Invalid target directory");
      // The front-end limits ZIP size, but parsing and expansion must also be constrained.
      let advertisedBytes=0, advertisedFiles=0;
      const archive=unzipSync(new Uint8Array(req.file.buffer),{filter:info=>{
        if(info.name.endsWith("/"))return false;
        advertisedFiles++;
        advertisedBytes+=info.originalSize;
        if(advertisedFiles>120 || advertisedBytes>16*1024*1024)
          throw Error("ZIP uncompressed size or file count exceeds the limit");
        return true;
      }});
      const imported=[];
      let total=0;
      for(const [name,bytes] of Object.entries(archive)) {
        if(name.endsWith("/"))continue;
        total+=bytes.length;
        if(total>16*1024*1024 || imported.length>=120)throw Error("ZIP expanded size or file count exceeded");
        if(name.startsWith("/") || name.includes("\\") ||
          name.split("/").some(s=>!s||s==="."||s===".."||s.startsWith(".")))
          throw Error("Unsafe ZIP filename: "+name);
        const relative=path.posix.join(root,name);
        if(!editableRepoPath(relative))throw Error("File path rejected: "+relative);
        if(!/\.(lua|json|md|txt)$/.test(name))throw Error("Unsupported package file: "+name);
        if(name.endsWith(".lua"))validateLua(Buffer.from(bytes).toString("utf8"),name);
        imported.push({relative,bytes});
      }
      if(!imported.length)throw Error("Empty ZIP");
      validatePackageSpec(spec,imported,root);
      initManagedRepo();
      const previousManifest=fs.readFileSync(path.join(managedRepo,"packages/manifest.lua"),"utf8");
      const previous=parseManifestCatalogue(previousManifest);
      const customFile="/data/repository-custom-packages.json";
      const custom=customPackageNames();
      const updating=req.body.mode==="update";
      const oldPackage=previous.packages[spec.name];
      if(updating && (!oldPackage || !custom.includes(spec.name)))
        throw Error("Only custom packages can be updated");
      if(!updating && oldPackage)throw Error("Package already registered");
      validateRepositoryManifest(previousManifest,managedRepo);
      for(const dep of spec.depends)if(!previous.packages[dep])throw Error("Unknown dependency: "+dep);
      let manifest;
      if(updating){
        // Remove the exact previously generated package block, then insert its replacement.
        const oldStart=previousManifest.indexOf('        ["'+spec.name+'"] = {');
        if(oldStart<0)throw Error("Custom package definition not found");
        const next=previousManifest.indexOf('\n        },',oldStart);
        if(next<0)throw Error("Custom package definition is not in supported format");
        manifest=previousManifest.slice(0,oldStart)+previousManifest.slice(next+12);
      }else manifest=previousManifest;
      manifest=manifest.replace("    packages = {","    packages = {\n"+packageDefinition(spec,spec.files));
      if(manifest===previousManifest && !updating)throw Error("Manifest insertion failed");
      const importedPaths=new Set(imported.map(x=>x.relative));
      validateRepositoryManifest(manifest,managedRepo,importedPaths);
      for(const item of imported){
        if(fs.existsSync(path.join(managedRepo,item.relative)) &&
            (!updating || !(oldPackage.files||[]).some(x=>x.src===item.relative)))
          throw Error("File already exists: "+item.relative);
      }
      staged=fs.mkdtempSync("/data/repo-package-stage-");
      fs.cpSync(managedRepo,staged,{recursive:true});
      for(const item of imported){
        const output=path.join(staged,item.relative);
        fs.mkdirSync(path.dirname(output),{recursive:true});
        fs.writeFileSync(output,item.bytes);
      }
      if(updating)for(const oldFile of oldPackage.files||[]){
        if(!importedPaths.has(oldFile.src) &&
          !Object.entries(previous.packages).some(([name,p])=>name!==spec.name&&(p.files||[]).some(x=>x.src===oldFile.src)))
          fs.rmSync(path.join(staged,oldFile.src),{force:true});
      }
      fs.writeFileSync(path.join(staged,"packages/manifest.lua"),manifest);
      validateRepositoryManifest(manifest,staged);
      const prior="/data/repository-previous",old="/data/repo-package-old";
      if(fs.existsSync(old))throw Error("Interrupted previous import; manual inspection required");
      fs.renameSync(managedRepo,old);
      try{fs.renameSync(staged,managedRepo);staged=null;}
      catch(e){fs.renameSync(old,managedRepo);throw e;}
      fs.rmSync(prior,{recursive:true,force:true});
      fs.renameSync(old,prior);
      if(!custom.includes(spec.name)){custom.push(spec.name);fs.writeFileSync(customFile,JSON.stringify(custom));}
      return res.json({ok:true,package:spec.name,mode:updating?"updated":"created",count:imported.length});
    }catch(e){return res.status(400).json({error:String(e.message||e)});}
    finally{if(staged)fs.rmSync(staged,{recursive:true,force:true});repoOperation=false;}
  });
});


function parseManifestCatalogue(source) {
  const ast=luaparse.parse(source,{luaVersion:"5.2"});
  const toValue=node=>{
    if(!node)return null;
    if(node.type==="StringLiteral")return node.value===null||node.value===undefined?JSON.parse(node.raw):node.value;
    if(node.type==="NumericLiteral"||node.type==="BooleanLiteral")return node.value;
    if(node.type==="NilLiteral")return null;
    if(node.type!=="TableConstructorExpression")throw Error("non-literal manifest value");
    const fields=node.fields||[];
    const result={};const array=[];let object=false;
    for(const field of fields) {
      if(field.type==="TableValue")array.push(toValue(field.value));
      else if(field.type==="TableKeyString"){object=true;result[field.key.name]=toValue(field.value);}
      else if(field.type==="TableKey"){object=true;result[String(toValue(field.key))]=toValue(field.value);}
      else throw Error("unsupported manifest table member");
    }
    return object?result:array;
  };
  const statement=ast.body.find(s=>s.type==="ReturnStatement");
  if(!statement?.arguments?.[0])throw Error("manifest must return a table");
  const manifest=toValue(statement.arguments[0]);
  if(!manifest||!manifest.packages||typeof manifest.packages!=="object")throw Error("invalid manifest packages");
  return manifest;
}
function customPackageNames() {
  const file="/data/repository-custom-packages.json";
  const registered=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,"utf8")):[];
  const names=new Set(Array.isArray(registered)?registered:[]);
  // Recognize packages imported before the custom-package registry was introduced.
  const baseline=path.join(REPOSITORY_DIR,"packages/manifest.lua");
  const active=path.join(managedRepo,"packages/manifest.lua");
  if(fs.existsSync(baseline) && fs.existsSync(active)) {
    const standard=parseManifestCatalogue(fs.readFileSync(baseline,"utf8")).packages;
    const current=parseManifestCatalogue(fs.readFileSync(active,"utf8")).packages;
    for(const name of Object.keys(current)) if(!standard[name])names.add(name);
  }
  return [...names];
}
function validateRepositoryManifest(text,root,extraFiles=new Set()) {
  const manifest=parseManifestCatalogue(text);
  const errors=[];
  for(const [name,def] of Object.entries(manifest.packages)){
    if(!def||!["app","module","preset","core","runtime"].includes(def.kind))errors.push(name+": invalid kind");
    for(const dep of def?.depends||[])if(!manifest.packages[dep])errors.push(name+": missing dependency "+dep);
    for(const mapping of def?.files||[]){
      if(typeof mapping.src!=="string"||typeof mapping.dest!=="string"||
        !editableRepoPath(mapping.src)||(!fs.existsSync(path.join(root,mapping.src))&&!extraFiles.has(mapping.src)))
        errors.push(name+": missing or unsafe source "+String(mapping.src));
    }
  }
  if(errors.length)throw Error(errors.slice(0,12).join("; "));
  return manifest;
}
app.delete("/api/repository/package-custom",requireAdmin,(req,res)=>{
  if(repoOperation)return res.status(409).json({error:"repository busy"});
  const name=req.body?.name;
  const customFile="/data/repository-custom-packages.json";
  const custom=fs.existsSync(customFile)?JSON.parse(fs.readFileSync(customFile,"utf8")):[];
  if(typeof name!=="string"||!custom.includes(name))
    return res.status(403).json({error:"Only Web-created custom packages can be removed"});
  repoOperation=true;
  let stage;
  try{
    const original=fs.readFileSync(path.join(managedRepo,"packages/manifest.lua"),"utf8");
    const parsed=validateRepositoryManifest(original,managedRepo);
    const pkg=parsed.packages[name];
    if(!pkg)throw Error("package not found");
    for(const [other,def] of Object.entries(parsed.packages))
      if(other!==name && (def.depends||[]).includes(name))throw Error("Package is required by "+other);
    const start=original.indexOf('        ["'+name+'"] = {');
    const stop=original.indexOf('\n        },',start);
    if(start<0||stop<0)throw Error("Cannot identify generated package definition");
    const updated=original.slice(0,start)+original.slice(stop+12);
    stage=fs.mkdtempSync("/data/repo-delete-stage-");
    fs.cpSync(managedRepo,stage,{recursive:true});
    for(const mapping of pkg.files||[]) {
      if(!Object.entries(parsed.packages).some(([other,def])=>other!==name&&(def.files||[]).some(f=>f.src===mapping.src)))
        fs.rmSync(path.join(stage,mapping.src),{force:true});
    }
    fs.writeFileSync(path.join(stage,"packages/manifest.lua"),updated);
    validateRepositoryManifest(updated,stage);
    const prev="/data/repository-previous",old="/data/repo-package-old";
    if(fs.existsSync(old))throw Error("Unfinished previous change detected");
    fs.renameSync(managedRepo,old);
    try{fs.renameSync(stage,managedRepo);stage=null;}catch(e){fs.renameSync(old,managedRepo);throw e;}
    fs.rmSync(prev,{recursive:true,force:true});
    fs.renameSync(old,prev);
    fs.writeFileSync(customFile,JSON.stringify(custom.filter(x=>x!==name)));
    res.json({ok:true,removed:name});
  }catch(e){res.status(400).json({error:String(e.message||e)});}
  finally{if(stage)fs.rmSync(stage,{recursive:true,force:true});repoOperation=false;}
});
app.get("/api/repository/catalog",(_req,res)=>{
  try{
    const file=safeRepositoryFile("packages/manifest.lua");
    if(!file||!fs.existsSync(file))return res.status(503).json({error:"repository not initialized"});
    const manifest=parseManifestCatalogue(fs.readFileSync(file,"utf8"));
    const custom=customPackageNames();
    res.json({version:manifest.version,packages:Object.entries(manifest.packages).map(([name,p])=>({
      name,kind:p.kind,description:p.description||"",version:p.version||manifest.version,depends:p.depends||[],files:p.files||[],custom:custom.includes(name)
    })).sort((a,b)=>a.name.localeCompare(b.name))});
  }catch(e){res.status(422).json({error:String(e.message)});}
});

const zipUpload = express.raw({type:"application/zip",limit:"12mb"});
app.post("/api/repository/import-zip",requireAdmin,zipUpload,(req,res)=>{
  if(repoOperation) return res.status(409).json({error:"repository operation in progress"});
  if(!Buffer.isBuffer(req.body) || req.body.length<4) return res.status(400).json({error:"ZIP file required"});
  const root=req.query.root || "";
  if(typeof root!=="string" || (root!=="" && (!/^(apps|modules|core|packages)\/[a-zA-Z0-9/_-]+$/.test(root) || root.includes(".."))))
    return res.status(400).json({error:"invalid destination folder"});
  repoOperation=true;
  let stage=null;
  try {
    initManagedRepo();
    // fflate rejects malformed ZIPs. Limit both compressed and extracted sizes.
    const archive=unzipSync(new Uint8Array(req.body));
    const entries=Object.entries(archive).filter(([name])=>!name.endsWith("/"));
    if(entries.length===0 || entries.length>250) throw Error("ZIP must contain 1-250 files");
    let size=0;
    const targets=[];
    for(const [name,bytes] of entries) {
      size+=bytes.length;
      if(size>24*1024*1024) throw Error("ZIP expanded size exceeds 24 MB");
      if (name.startsWith("/") || name.includes("\\") || name.split("/").some(segment=>segment===".." || segment==="." || segment.startsWith(".")))
        throw Error("unsafe ZIP path: "+name);
      const relative=path.posix.join(root,name);
      const target=editableRepoPath(relative);
      if(!target || /(^|\/)__MACOSX\//.test(name) || name.includes("\\"))
        throw Error("unsafe path: "+name);
      if(fs.existsSync(target)) throw Error("file already exists: "+relative);
      targets.push({relative,target,bytes});
    }
    stage=fs.mkdtempSync(path.join("/data","attacc-zip-"));
    for(const item of targets) {
      const dest=path.join(stage,item.relative);
      fs.mkdirSync(path.dirname(dest),{recursive:true});
      fs.writeFileSync(dest,item.bytes,{flag:"wx"});
    }
    // Prevalidate all paths; existing files are never overwritten.
    for(const item of targets) {
      fs.mkdirSync(path.dirname(item.target),{recursive:true});
      fs.renameSync(path.join(stage,item.relative),item.target);
    }
    res.json({ok:true,files:targets.map(t=>t.relative),count:targets.length});
  }catch(e){
    res.status(400).json({error:String(e.message||e)});
  }finally{
    if(stage) fs.rmSync(stage,{recursive:true,force:true});
    repoOperation=false;
  }
});
// A custom preset describes which installed program to boot; its files come from dependencies.
app.post("/api/repository/preset",requireAdmin,(req,res)=>{
  if(repoOperation)return res.status(409).json({error:"repository busy"});
  const {name,description,version,depends,program}=req.body||{};
  if(typeof name!=="string" || !/^preset\.[a-z][a-z0-9-]{1,48}$/.test(name) ||
     typeof description!=="string" || description.length>200 ||
     typeof version!=="string" || !/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(version) ||
     !Array.isArray(depends) || !depends.length || depends.length>20 ||
     depends.some(x=>typeof x!=="string"||!/^[a-z][\w.-]{1,70}$/.test(x)) ||
     typeof program!=="string" || !/^[\w./-]+\.lua$/.test(program) ||
     program.startsWith("/") || program.split("/").some(x=>x===".."||x==="."||!x))
    return res.status(400).json({error:"invalid custom preset definition"});
  repoOperation=true;
  try {
    initManagedRepo();
    const file=path.join(managedRepo,"packages/manifest.lua");
    const original=fs.readFileSync(file,"utf8");
    const manifest=validateRepositoryManifest(original,managedRepo);
    if(manifest.packages[name])throw Error("preset name already exists");
    const available=new Set(),visited=new Set();
    const scan=dep=>{
      if(visited.has(dep))return;
      visited.add(dep);
      const pkg=manifest.packages[dep];
      if(!pkg)throw Error("Unknown dependency: "+dep);
      for(const mapping of pkg.files||[])available.add(mapping.dest);
      for(const nested of pkg.depends||[])scan(nested);
    };
    depends.forEach(scan);
    if(!available.has(program))throw Error("Boot program must be installed by a dependency: "+program);
    const definition='        ["'+name+'"] = {\n'
       +'            kind = "preset",\n'
       +'            version = '+JSON.stringify(version)+',\n'
       +'            description = '+JSON.stringify(description)+',\n'
       +'            program = '+JSON.stringify(program)+',\n'
       +'            depends = { '+depends.map(JSON.stringify).join(", ")+' },\n'
       +'            files = {},\n'
       +'        },\n';
    const updated=original.replace("    packages = {","    packages = {\n"+definition);
    validateRepositoryManifest(updated,managedRepo);
    fs.writeFileSync(file+".new",updated);
    fs.renameSync(file+".new",file);
    const customFile="/data/repository-custom-packages.json";
    const custom=customPackageNames();
    custom.push(name);
    fs.writeFileSync(customFile,JSON.stringify([...new Set(custom)]));
    res.json({ok:true,name,program});
  }catch(e){res.status(400).json({error:String(e.message||e)});}
  finally{repoOperation=false;}
});
app.post("/api/repository/package",requireAdmin,(req,res)=>{
  if(repoOperation) return res.status(409).json({error:"repository operation in progress"});
  const {name,kind,description,depends,files} = req.body||{};
  if(typeof name!=="string" || !/^(?:app|module|preset)\.[a-z][a-z0-9-]{1,48}$/.test(name)
    || !["app","module","preset"].includes(kind) || !name.startsWith(kind+".")
    || typeof description!=="string" || description.length>200
    || !Array.isArray(depends) || depends.length>20 || depends.some(d=>typeof d!=="string" || !/^[a-z][\w.-]{1,70}$/.test(d))
    || (kind!=="preset" && (!Array.isArray(files) || !files.length || files.length>100
      || files.some(f=>!f || !editableRepoPath(f.src) || typeof f.dest!=="string"
        || !/^[\w./-]{1,150}$/.test(f.dest) || f.dest.includes("..")
        || !fs.existsSync(editableRepoPath(f.src))))))
    return res.status(400).json({error:"invalid package definition"});
  try{
    initManagedRepo();
    const manifest=path.join(managedRepo,"packages/manifest.lua");
    let body=fs.readFileSync(manifest,"utf8");
    if(body.includes('["'+name+'"]'))return res.status(409).json({error:"package already exists"});
    if(!body.includes("    packages = {"))throw Error("manifest packages section unavailable");
    const luaString=s=>JSON.stringify(s);
    const deps=depends.map(luaString).join(", ");
    const fileDefinitions=kind==="preset"?"{}":"{ "+files.map(f=>"{ src = "+luaString(f.src)+", dest = "+luaString(f.dest)+" }").join(", ")+" }";
    const definition='        ["'+name+'"] = {\n'
      +'            kind = '+luaString(kind)+',\n'
      +'            description = '+luaString(description)+',\n'
      +'            depends = { '+deps+' },\n'
      +'            files = '+fileDefinitions+',\n'
      +'        },\n';
    body=body.replace("    packages = {","    packages = {\n"+definition);
    fs.writeFileSync(manifest+".new",body);
    fs.renameSync(manifest+".new",manifest);
    return res.json({ok:true,name,fileCount:files?.length||0});
  }catch(e){return res.status(500).json({error:String(e.message)});}
});
app.post("/api/repository/initialize",requireAdmin,(_req,res)=>{
  try {initManagedRepo();res.json({ok:true});}
  catch(e){res.status(500).json({error:String(e.message)});}
});
app.get("/api/repository/files",requireAdmin,(_req,res)=>{
  res.json({files:listEditableFiles(fs.existsSync(managedRepo)?managedRepo:REPOSITORY_DIR)});
});
app.get("/api/repository/file",requireAdmin,(req,res)=>{
  const filename=editableRepoPath(req.query.path);
  if (!filename) return res.status(400).json({error:"invalid path"});
  const current=fs.existsSync(managedRepo)?filename:path.join(REPOSITORY_DIR,req.query.path);
  if (!fs.existsSync(current) || !fs.statSync(current).isFile()) return res.sendStatus(404);
  res.json({path:req.query.path,content:fs.readFileSync(current,"utf8")});
});
app.put("/api/repository/file",requireAdmin,(req,res)=>{
  if(repoOperation) return res.status(409).json({error:"repository operation in progress"});
  const filename=editableRepoPath(req.body?.path);
  const content=req.body?.content;
  if(!filename || typeof content!=="string" || Buffer.byteLength(content)>200000)
    return res.status(400).json({error:"invalid file or content (200KB maximum)"});
  try {
    initManagedRepo();
    fs.mkdirSync(path.dirname(filename),{recursive:true});
    const tmp=filename+".upload-tmp";
    fs.writeFileSync(tmp,content,{flag:"w",mode:0o600});
    fs.renameSync(tmp,filename);
    res.json({ok:true,path:req.body.path});
  } catch(e){res.status(500).json({error:String(e.message)});}
});
app.delete("/api/repository/file",requireAdmin,(req,res)=>{
  if(repoOperation) return res.status(409).json({error:"repository operation in progress"});
  const filename=editableRepoPath(req.body?.path);
  if(!filename || !fs.existsSync(filename)) return res.status(404).json({error:"file not found"});
  if(["install.lua","pkgctl.lua","packages/manifest.lua"].includes(req.body.path))
    return res.status(400).json({error:"required repository file"});
  fs.unlinkSync(filename);res.json({ok:true});
});

app.get("/api/repository/settings", requireAdmin, (_req,res) => {
  res.json({ ...repoSettings(), busy: repoOperation, managed: fs.existsSync(path.join(managedRepo,"packages/manifest.lua")) });
});
app.put("/api/repository/settings", requireAdmin, (req,res) => {
  const {remote,ref,publicUrl} = req.body || {};
  if (typeof remote !== "string" || !/^https:\/\/[^\s]+\.git$/.test(remote)
    || typeof ref !== "string" || !/^[\w./-]{1,100}$/.test(ref) || ref.includes("..")
    || typeof publicUrl !== "string"
    || (publicUrl !== "" && !/^https?:\/\/[^\s]+\/repo\/?$/.test(publicUrl))) {
    return res.status(400).json({error:"invalid settings"});
  }
  const data = {remote,ref,publicUrl:publicUrl.replace(/\/$/,"")};
  fs.writeFileSync(repoSettingsFile + ".tmp",JSON.stringify(data,null,2));
  fs.renameSync(repoSettingsFile + ".tmp",repoSettingsFile);
  res.json(data);
});
app.post("/api/repository/sync", requireAdmin, (_req,res) => {
  if (repoOperation) return res.status(409).json({error:"operation in progress"});
  repoOperation = true;
  const {remote,ref} = repoSettings();
  const staging = "/data/repository-stage";
  try {
    fs.rmSync(staging,{force:true,recursive:true});
    execFileSync("git",["clone","--depth","1","--branch",ref,"--",remote,staging],{
      timeout:120000,stdio:"pipe",env:{...process.env,GIT_TERMINAL_PROMPT:"0"}
    });
    for (const p of ["install.lua","pkgctl.lua","packages/manifest.lua"])
      if (!fs.existsSync(path.join(staging,p))) throw new Error("missing "+p);
    const manifestText = fs.readFileSync(path.join(staging,"packages/manifest.lua"),"utf8");
    const sourceFiles = [...manifestText.matchAll(/\bsrc\s*=\s*"([^"]+)"/g)].map(m=>m[1]);
    if (!sourceFiles.length) throw new Error("manifest contains no package files");
    for (const source of sourceFiles) {
      if (source.startsWith("/") || source.split("/").includes("..") ||
          !fs.existsSync(path.join(staging,source)))
        throw new Error("missing or unsafe package file: "+source);
    }
    const previous = "/data/repository-previous";
    fs.rmSync(previous,{recursive:true,force:true});
    if (fs.existsSync(managedRepo)) fs.renameSync(managedRepo,previous);
    fs.renameSync(staging,managedRepo);
    res.json({ok:true,ref,revision:execFileSync("git",["-C",managedRepo,"rev-parse","HEAD"],{encoding:"utf8"}).trim()});
  } catch(e) {
    if (!fs.existsSync(managedRepo) && fs.existsSync("/data/repository-previous"))
      fs.renameSync("/data/repository-previous",managedRepo);
    res.status(500).json({error:String(e.message)});
  } finally { fs.rmSync(staging,{recursive:true,force:true}); repoOperation=false; }
});
app.post("/api/repository/rollback", requireAdmin, (_req,res) => {
  if (repoOperation) return res.status(409).json({error:"operation in progress"});
  const prev="/data/repository-previous",tmp="/data/repository-swap";
  if (!fs.existsSync(prev)) return res.status(404).json({error:"no previous revision"});
  fs.rmSync(tmp,{recursive:true,force:true});
  if (fs.existsSync(managedRepo)) fs.renameSync(managedRepo,tmp);
  fs.renameSync(prev,managedRepo);
  if (fs.existsSync(tmp)) fs.renameSync(tmp,prev);
  res.json({ok:true});
});

app.get("/api/health", (_req, res) => {
  const s = snapshot();
  res.json({
    ok: true,
    bridgeConnected: s.bridgeConnected,
    bridgeCount: s.bridgeCount,
    stats: s.stats,
  });
});

app.get("/api/status", (_req, res) => res.json(snapshot()));
app.get("/api/networks", (_req, res) => res.json(snapshot().networks));

app.get("/api/events", (req, res) => {
  const limit = Math.max(1, Math.min(500, Number(req.query.limit || 100)));
  const filtered = events.filter(event =>
    (!req.query.network || event.network === req.query.network)
    && (!req.query.module || event.module === req.query.module)
    && (!req.query.machine || event.machine === req.query.machine)
    && (!req.query.level || event.level === req.query.level)
  );
  res.json(filtered.slice(0, limit));
});

app.post("/api/nodes/reboot", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });

  const targets = Array.isArray(req.body?.targets)
    ? [...new Set(req.body.targets.filter(v => typeof v === "string" && v.length > 0))]
    : [];
  const network = typeof req.body?.network === "string" && req.body.network
    ? req.body.network
    : null;

  if (targets.length === 0) return res.status(400).json({ error: "no_targets" });

  const knownNodes = activeNodes().filter(n => !network || n.network === network);
  const known = new Set(knownNodes.map(n => n.key));
  const unknown = targets.filter(key => !known.has(key));
  if (unknown.length > 0) {
    return res.status(400).json({ error: "unknown_targets", targets: unknown });
  }

  const targetNetworks = [...new Set(
    knownNodes.filter(n => targets.includes(n.key)).map(n => n.network)
  )];

  if (targetNetworks.length !== 1) {
    return res.status(400).json({ error: "targets_cross_networks", networks: targetNetworks });
  }

  const targetNetwork = targetNetworks[0];
  const id = `web-reboot-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  const sent = sendToNetwork(targetNetwork, {
    type: "node_reboot",
    id,
    network: targetNetwork,
    targets,
    global: true,
    timestamp: Date.now(),
  });

  if (!sent) return res.status(503).json({ error: "bridge_offline" });

  addEvent({
    timestamp: Date.now(),
    network: targetNetwork,
    level: "warning",
    code: "NODE_REBOOT_REQUEST",
    message: `Web requested reboot: ${targets.join(", ")}`,
  });

  res.json({ ok: true, id, network: targetNetwork, targets });
});

function sendModuleCommand({ network, module, command, args = {}, targetMachine = null }) {
  const id = `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  const sent = sendToNetwork(network || "default", {
    type: "command",
    id,
    network: network || "default",
    module,
    command,
    args,
    targetMachine,
    timestamp: Date.now(),
  });

  if (!sent) return null;

  addEvent({
    timestamp: Date.now(),
    network: network || "default",
    module,
    machine: targetMachine,
    level: "info",
    code: "MODULE_COMMAND",
    message: `${module} // ${command}${targetMachine ? ` -> ${targetMachine}` : ""}`,
  });

  return id;
}

function sendNodeAdmin({ network, target, request }) {
  const id = `web-admin-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const sent = sendToNetwork(network, {
    type: "node_admin",
    id,
    network,
    targets: [target],
    request,
    global: true,
    timestamp: Date.now(),
  });
  return sent ? id : null;
}

app.post("/api/nodes/update", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });
  const { network, target, package: packageName } = req.body || {};
  if (![network, target].every(v => typeof v === "string" && v)) {
    return res.status(400).json({ error: "invalid_request" });
  }

  const id = sendNodeAdmin({
    network,
    target,
    request: { action: "package_update", package: typeof packageName === "string" ? packageName : null },
  });
  if (!id) return res.status(503).json({ error: "bridge_offline" });

  addEvent({
    timestamp: Date.now(), network, machine: target, level: "warning",
    code: "PACKAGE_UPDATE", message: packageName ? `Update requested: ${packageName}` : "Full package update requested",
  });
  res.json({ ok: true, id });
});

app.post("/api/nodes/package-configure", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });
  const { network, target, package: packageName } = req.body || {};
  if (![network, target, packageName].every(v => typeof v === "string" && v)) {
    return res.status(400).json({ error: "invalid_request" });
  }

  const id = sendNodeAdmin({
    network,
    target,
    request: { action: "package_configure", package: packageName },
  });
  if (!id) return res.status(503).json({ error: "bridge_offline" });
  res.json({ ok: true, id });
});

app.post("/api/module/command", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });

  const { network, module, command, args, targetMachine } = req.body || {};
  if (typeof network !== "string" || network.length === 0) {
    return res.status(400).json({ error: "invalid_network" });
  }
  if (typeof module !== "string" || module.length === 0) {
    return res.status(400).json({ error: "invalid_module" });
  }
  if (typeof command !== "string" || command.length === 0) {
    return res.status(400).json({ error: "invalid_command" });
  }
  if (args != null && (typeof args !== "object" || Array.isArray(args))) {
    return res.status(400).json({ error: "invalid_args" });
  }

  const id = sendModuleCommand({
    network,
    module,
    command,
    args: args || {},
    targetMachine: typeof targetMachine === "string" && targetMachine ? targetMachine : null,
  });

  if (!id) return res.status(503).json({ error: "bridge_offline" });
  res.json({ ok: true, id });
});

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === "/ws/machine") {
    const token = bearer(req) || url.searchParams.get("token");
    if (token !== MACHINE_TOKEN) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }

    machineWss.handleUpgrade(req, socket, head, ws => {
      machineWss.emit("connection", ws, req);
    });
    return;
  }

  if (url.pathname === "/ws/browser") {
    browserWss.handleUpgrade(req, socket, head, ws => {
      browserWss.emit("connection", ws, req);
    });
    return;
  }

  socket.destroy();
});

function appendTelemetryHistory(key, data) {
  const graphs = Array.isArray(data?.ui?.graphs) ? data.ui.graphs : [];
  if (!graphs.length) return;

  const history = telemetryHistory.get(key) || {};
  const ts = Number(data.timestamp || Date.now());

  for (const graph of graphs) {
    const id = String(graph?.id || graph?.label || "value");
    const value = Number(graph?.value);
    if (!Number.isFinite(value)) continue;

    const bucket = Array.isArray(history[id]) ? history[id] : [];
    const last = bucket[bucket.length - 1];
    if (!last || last.timestamp !== ts) {
      bucket.push({
        timestamp: ts,
        value,
        label: graph.label || id,
        unit: graph.unit || "",
      });
      while (bucket.length > GRAPH_HISTORY_LIMIT) bucket.shift();
    }
    history[id] = bucket;
  }

  telemetryHistory.set(key, history);
}

machineWss.on("connection", ws => {
  ws.networks = new Set();
  machines.add(ws);
  addEvent({
    timestamp: Date.now(),
    network: "infra",
    level: "success",
    code: "BRIDGE_CONNECTED",
    message: `CC:Tweaked Web bridge connected (bridges: ${bridgeCount()})`,
  });

  ws.on("message", buf => {
    let msg;
    try { msg = JSON.parse(buf.toString()); } catch { return; }

    if (msg.type === "telemetry" && msg.data) {
      const data = msg.data;
      const network = msg.network || data.network || "default";
      ws.networks.add(network);
      const machineKey = msg.machine || data.machine || "unknown";
      const module = msg.module || data.module || "unknown";

      const tKey = telemetryKey(network, machineKey, module);
      for (const [existingKey, existing] of telemetry.entries()) {
        if (existingKey !== tKey && existing.machine === machineKey && existing.module === module) {
          telemetry.delete(existingKey);
          telemetryHistory.delete(existingKey);
        }
      }
      telemetry.set(tKey, {
        network,
        machine: machineKey,
        module,
        data,
        lastSeen: Date.now(),
      });
      appendTelemetryHistory(tKey, data);
      broadcast();
      return;
    }

    if (msg.type === "event") {
      if (msg.network) ws.networks.add(msg.network);
      addEvent(msg);
      return;
    }

    if (msg.type === "node_status" && msg.key) {
      const now = Date.now();
      const network = msg.network || "default";
      ws.networks.add(network);
      const key = nodeKey(network, msg.key);
      const previous = nodes.get(key);
      const physicalIdentity = msg.physicalIdentity || `cc:${msg.computerId}`;
      const duplicate = previous
        && previous.physicalIdentity
        && previous.physicalIdentity !== physicalIdentity
        && now - previous.lastSeen < NODE_STALE_MS;

      for (const [existingKey, existing] of nodes.entries()) {
        if (existingKey !== key
            && existing.physicalIdentity
            && existing.physicalIdentity === physicalIdentity) {
          nodes.delete(existingKey);
        }
      }

      nodes.set(key, {
        key: msg.key,
        role: msg.role || "unknown",
        preset: msg.preset || msg.role || "unknown",
        computerId: msg.computerId,
        physicalIdentity,
        hostname: msg.hostname || msg.name || msg.key,
        name: msg.name || msg.hostname || msg.key,
        label: msg.label || msg.hostname || msg.key,
        network,
        networkLabel: msg.networkLabel || network,
        runtime: msg.runtime && typeof msg.runtime === "object" ? msg.runtime : {},
        system: msg.system && typeof msg.system === "object" ? msg.system : null,
        apps: Array.isArray(msg.apps) ? msg.apps : [],
        modules: Array.isArray(msg.modules) ? msg.modules : [],
        capabilities: Array.isArray(msg.capabilities) ? msg.capabilities : [],
        tags: Array.isArray(msg.tags) ? msg.tags : [],
        conflict: duplicate,
        conflictPhysicalIdentity: duplicate ? previous.physicalIdentity : null,
        lastSeen: now,
      });
      broadcast();
      return;
    }

    if (msg.type === "node_admin_ack") {
      const key = nodeKey(msg.network || "default", msg.key);
      const node = nodes.get(key);
      if (node && msg.system && typeof msg.system === "object") {
        node.system = msg.system;
        node.lastSeen = Date.now();
        nodes.set(key, node);
      }

      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        machine: msg.key || null,
        level: msg.ok === false ? "critical" : "success",
        code: msg.ok === false ? "ADMIN_ACTION_FAILED" : "ADMIN_ACTION_ACK",
        message: msg.ok === false
          ? `Admin action failed: ${msg.error || "unknown error"}`
          : "Admin action accepted",
      });
      broadcast();
      return;
    }

    if (msg.type === "node_reboot_ack") {
      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        machine: msg.key || null,
        level: msg.ok === false ? "critical" : "success",
        code: "NODE_REBOOT_ACK",
        message: `Reboot acknowledged by ${msg.key || "unknown node"}`,
      });
      return;
    }

    if (msg.type === "command_ack" || msg.type === "module_ack") {
      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        module: msg.module || null,
        machine: msg.machine || null,
        level: msg.ok ? "success" : "critical",
        code: msg.ok ? "COMMAND_ACK" : "COMMAND_ERROR",
        message: msg.ok
          ? `Command acknowledged: ${msg.command}`
          : `Command failed: ${msg.command} - ${msg.error || "unknown error"}`,
      });
    }
  });

  ws.on("close", () => {
    machines.delete(ws);
    addEvent({
      timestamp: Date.now(),
      network: "infra",
      level: "warning",
      code: "BRIDGE_DISCONNECTED",
      message: `CC:Tweaked Web bridge disconnected (bridges: ${bridgeCount()})`,
    });
  });
});

browserWss.on("connection", ws => {
  browsers.add(ws);
  ws.send(JSON.stringify(snapshot()));
  ws.on("close", () => browsers.delete(ws));
});

app.get("*splat", (_req, res) => {
  res.sendFile("index.html", { root: PUBLIC_DIR });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`AttaCC dashboard listening on :${PORT}`);
});
