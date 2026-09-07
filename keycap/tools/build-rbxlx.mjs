// Baut aus src/ eine fertig oeffnbare Roblox-Studio-Datei (KeycapRush.rbxlx),
// nach demselben Mapping wie default.project.json (Rojo):
//   src/shared  -> ReplicatedStorage.Shared
//   src/server  -> ServerScriptService.KeycapRush (Script mit Ordner "Services")
//   src/client  -> StarterPlayer.StarterPlayerScripts.KeycapRush (LocalScript)
// Ausfuehren:  node tools/build-rbxlx.mjs
import { readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { join } from "path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const OUT = join(ROOT, "KeycapRush.rbxlx");

let referentCounter = 0;
function nextReferent() {
  referentCounter += 1;
  return `KC${referentCounter}`;
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

// Wandelt einen Quellordner rekursiv in Items um. init.*-Dateien werden
// uebersprungen - die sind das umgebende Script, nicht ein Kind davon.
function directoryChildren(dirPath) {
  let xml = "";
  for (const entry of readdirSync(dirPath).sort()) {
    const fullPath = join(dirPath, entry);
    if (statSync(fullPath).isDirectory()) {
      xml += folderItem(entry, directoryChildren(fullPath));
    } else if (entry.endsWith(".luau") && !entry.startsWith("init.")) {
      xml += scriptItem("ModuleScript", entry.replace(/\.luau$/, ""), fullPath);
    }
  }
  return xml;
}

const sharedXml = folderItem("Shared", directoryChildren(join(ROOT, "src/shared")));
const serverXml = scriptItem("Script", "KeycapRush", join(ROOT, "src/server/init.server.luau"), directoryChildren(join(ROOT, "src/server")));
const clientXml = scriptItem("LocalScript", "KeycapRush", join(ROOT, "src/client/init.client.luau"), directoryChildren(join(ROOT, "src/client")));

// Spawn vor der Plotreihe, auf Hoehe der Promenade. Sobald ein Profil
// geladen ist, setzt PlotService den Spieler auf seinen eigenen Plot -
// dieser Punkt ist nur die Sekunde davor.
const IDENTITY_ROT = `<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>`;
const spawnXml = `<Item class="SpawnLocation" referent="${nextReferent()}">
<Properties>
<string name="Name">Start</string>
<bool name="Anchored">true</bool>
<Vector3 name="size"><X>16</X><Y>1</Y><Z>16</Z></Vector3>
<CoordinateFrame name="CFrame"><X>0</X><Y>9.5</Y><Z>36</Z>${IDENTITY_ROT}</CoordinateFrame>
<Color3uint8 name="Color3uint8">4294962611</Color3uint8>
<token name="Material">1312</token>
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
