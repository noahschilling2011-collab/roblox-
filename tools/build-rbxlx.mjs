// Baut aus src/ eine fertig öffnbare Roblox-Studio-Datei (PlanetForge.rbxlx),
// nach demselben Mapping wie default.project.json (Rojo):
//   src/shared  -> ReplicatedStorage.Shared
//   src/server  -> ServerScriptService.Server (Script mit Ordner "Services")
//   src/client  -> StarterPlayer.StarterPlayerScripts.Client (LocalScript)
// Ausführen:  node tools/build-rbxlx.mjs
import { readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { join } from "path";

const REPO = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const OUT = join(REPO, "PlanetForge.rbxlx");

let referentCounter = 0;
function nextReferent() {
  referentCounter += 1;
  return `PF${referentCounter}`;
}

function escapeXml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function scriptItem(className, name, sourcePath, children = "") {
  const source = readFileSync(sourcePath, "utf8");
  return `<Item class="${className}" referent="${nextReferent()}">
<Properties>
<string name="Name">${escapeXml(name)}</string>
<ProtectedString name="Source">${escapeXml(source)}</ProtectedString>
</Properties>
${children}</Item>
`;
}

function folderItem(name, children) {
  return `<Item class="Folder" referent="${nextReferent()}">
<Properties>
<string name="Name">${escapeXml(name)}</string>
</Properties>
${children}</Item>
`;
}

// Wandelt einen Quellordner rekursiv in Items um (ohne init.*-Dateien,
// die behandelt der Aufrufer als umgebendes Script).
function directoryChildren(dirPath) {
  let xml = "";
  const entries = readdirSync(dirPath).sort();
  for (const entry of entries) {
    const fullPath = join(dirPath, entry);
    if (statSync(fullPath).isDirectory()) {
      xml += folderItem(entry, directoryChildren(fullPath));
    } else if (entry.endsWith(".luau") && !entry.startsWith("init.")) {
      const name = entry.replace(/\.luau$/, "");
      xml += scriptItem("ModuleScript", name, fullPath);
    }
  }
  return xml;
}

const sharedXml = folderItem("Shared", directoryChildren(join(REPO, "src/shared")));

const serverXml = scriptItem(
  "Script",
  "Server",
  join(REPO, "src/server/init.server.luau"),
  directoryChildren(join(REPO, "src/server"))
);

const clientXml = scriptItem(
  "LocalScript",
  "Client",
  join(REPO, "src/client/init.client.luau"),
  directoryChildren(join(REPO, "src/client"))
);

// Spawn-Plattform, damit neue Charaktere festen Boden haben, bis der
// PlanetService sie auf ihren Planeten teleportiert.
const spawnXml = `<Item class="SpawnLocation" referent="${nextReferent()}">
<Properties>
<string name="Name">SpawnLocation</string>
<bool name="Anchored">true</bool>
<Vector3 name="size"><X>24</X><Y>1</Y><Z>24</Z></Vector3>
</Properties>
</Item>
`;

const place = `<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
<Item class="Workspace" referent="${nextReferent()}">
<Properties>
<string name="Name">Workspace</string>
</Properties>
${spawnXml}</Item>
<Item class="ReplicatedStorage" referent="${nextReferent()}">
<Properties>
<string name="Name">ReplicatedStorage</string>
</Properties>
${sharedXml}</Item>
<Item class="ServerScriptService" referent="${nextReferent()}">
<Properties>
<string name="Name">ServerScriptService</string>
</Properties>
${serverXml}</Item>
<Item class="Lighting" referent="${nextReferent()}">
<Properties>
<string name="Name">Lighting</string>
<token name="Technology">4</token>
</Properties>
</Item>
<Item class="StarterPlayer" referent="${nextReferent()}">
<Properties>
<string name="Name">StarterPlayer</string>
</Properties>
<Item class="StarterPlayerScripts" referent="${nextReferent()}">
<Properties>
<string name="Name">StarterPlayerScripts</string>
</Properties>
${clientXml}</Item>
</Item>
</roblox>
`;

writeFileSync(OUT, place);
console.log(`Geschrieben: ${OUT} (${Math.round(place.length / 1024)} KB, ${referentCounter} Instanzen)`);
