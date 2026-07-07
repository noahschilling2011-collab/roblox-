// Baut aus turmfall/src eine fertig öffnbare Roblox-Studio-Datei
// (Turmfall.rbxlx im Repo-Root), nach demselben Mapping wie
// default.project.json (Rojo):
//   src/shared -> ReplicatedStorage.Shared
//   src/server -> ServerScriptService.Server (Script mit Ordner "Services")
//   src/client -> StarterPlayer.StarterPlayerScripts.Client (LocalScript)
// Ausführen:  node turmfall/tools/build-rbxlx.mjs
import { readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { join } from "path";

const PROJECT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const REPO = new URL("../..", import.meta.url).pathname.replace(/\/$/, "");
const OUT = join(REPO, "Turmfall.rbxlx");

let referentCounter = 0;
function nextReferent() {
  referentCounter += 1;
  return `TF${referentCounter}`;
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

const sharedXml = folderItem("Shared", directoryChildren(join(PROJECT, "src/shared")));

const serverXml = scriptItem(
  "Script",
  "Server",
  join(PROJECT, "src/server/init.server.luau"),
  directoryChildren(join(PROJECT, "src/server"))
);

const clientXml = scriptItem(
  "LocalScript",
  "Client",
  join(PROJECT, "src/client/init.client.luau"),
  directoryChildren(join(PROJECT, "src/client"))
);

// Statischer Spawn auf Lobby-Höhe, bis der LobbyService die Lobby baut
// und den Spawn übernimmt (er verschiebt einen vorhandenen SpawnLocation).
const IDENTITY_ROT = `<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>`;
const spawnXml = `<Item class="SpawnLocation" referent="${nextReferent()}">
<Properties>
<string name="Name">LobbySpawn</string>
<bool name="Anchored">true</bool>
<Vector3 name="size"><X>10</X><Y>0.4</Y><Z>10</Z></Vector3>
<CoordinateFrame name="CFrame"><X>240</X><Y>21.4</Y><Z>20</Z>${IDENTITY_ROT}</CoordinateFrame>
<Color3uint8 name="Color3uint8">4282137674</Color3uint8>
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
