import {useState} from "react";

export function RepositoryTree({files=[],filter="",active="",onOpen}) {
  const [closed,setClosed]=useState({});
  const root={children:new Map()};
  for(const filename of files.filter(f=>f.toLowerCase().includes(filter.toLowerCase()))) {
    let current=root;
    const parts=filename.split("/");
    parts.forEach((part,index)=>{
      if(!current.children.has(part))current.children.set(part,{
        name:part,path:parts.slice(0,index+1).join("/"),
        dir:index<parts.length-1,children:new Map()
      });
      current=current.children.get(part);
    });
  }
  const render=(parent,depth=0)=>[...parent.children.values()]
    .sort((a,b)=>Number(b.dir)-Number(a.dir)||a.name.localeCompare(b.name))
    .map(node=><div key={node.path}>
      <button className={"repo-tree-node"+(active===node.path?" selected":"")}
        style={{paddingLeft:8+depth*15}} onClick={()=>node.dir?
          setClosed(v=>({...v,[node.path]:!v[node.path]})):onOpen(node.path)}>
        <span className="repo-tree-glyph">{node.dir?(closed[node.path]?"▸":"▾"):"·"}</span>
        <span>{node.name}</span>
      </button>
      {node.dir&&!closed[node.path]&&render(node,depth+1)}
    </div>);
  return <div className="repo-tree-scroll" role="tree">{render(root)}</div>;
}

export function RepositoryCatalog({items=[],onRefresh,onUpdate,onDelete}) {
  const [kind,setKind]=useState("all");
  const [search,setSearch]=useState("");
  const filtered=items.filter(p=>(kind==="all"||p.kind===kind)
    && (p.name+" "+p.description).toLowerCase().includes(search.toLowerCase()));
  return <section className="repo-catalogue">
    <div className="repo-catalog-controls">
      <input aria-label="Search packages" placeholder="Search apps, modules, presets..."
        value={search} onChange={e=>setSearch(e.target.value)}/>
      <select aria-label="Package kind" value={kind} onChange={e=>setKind(e.target.value)}>
        <option value="all">All packages</option><option value="app">Applications</option>
        <option value="module">Modules</option><option value="preset">Presets</option>
      </select>
      <button onClick={onRefresh}>Refresh</button>
    </div>
    <div className="repo-catalog-grid">{filtered.map(pkg=>
      <article className="mc-panel repo-catalog-card" key={pkg.name}>
        <div className="repo-catalog-top"><span className="repo-catalog-icon">{pkg.kind==="app"?"▣":pkg.kind==="module"?"⬡":"◈"}</span>
          <span className="repo-app-kind">{pkg.kind}</span></div>
        <h3>{pkg.name}</h3><p>{pkg.description||"No description provided"}</p>
        <div className="repo-catalog-count">{(pkg.files||[]).length} files · {(pkg.depends||[]).length} dependencies</div>
        {pkg.custom&&<div className="repo-actions">
          <button onClick={()=>onUpdate?.(pkg)}>Update</button>
          <button className="repo-danger" onClick={()=>onDelete?.(pkg)}>Delete</button>
        </div>}
        {(pkg.depends||[]).length>0&&<details><summary>Dependencies</summary>
          <div>{pkg.depends.join(", ")}</div></details>}
        {(pkg.files||[]).length>0&&<details><summary>Installed files</summary>
          {(pkg.files||[]).map((f,i)=><div key={i}><code>{f.src} → {f.dest}</code></div>)}</details>}
      </article>)}</div>
    {!filtered.length&&<p className="repo-empty">No packages match the filter.</p>}
  </section>;
}
