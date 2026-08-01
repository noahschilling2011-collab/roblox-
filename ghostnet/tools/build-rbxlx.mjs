// Baut aus ghostnet/src eine fertig oeffnbare Roblox-Studio-Datei
// (ghostnet/GhostNet.rbxlx), nach demselben Mapping wie default.project.json:
//   src/shared  -> ReplicatedStorage.Shared
//   src/server  -> ServerScriptService  (GhostNetServer + Systems + World)
//   src/client  -> StarterPlayer.StarterPlayerScripts (Ordner UI)
// Ausfuehren:  node ghostnet/tools/build-rbxlx.mjs
import { readFileSync, readdirSync, statSync, writeFileSync } from "fs";
import { join } from "path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const OUT = join(ROOT, "GhostNet.rbxlx");

let referentCounter = 0;
function nextReferent() {
  referentCounter += 1;
  return `GN${referentCounter}`;
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

// Die Dateiendung bestimmt den Script-Typ - genau wie bei Rojo:
//   Name.server.luau = Script  ·  Name.client.luau = LocalScript
//   Name.luau        = ModuleScript
function classFor(entry) {
  if (entry.endsWith(".server.luau")) return ["Script", entry.slice(0, -12)];
  if (entry.endsWith(".client.luau")) return ["LocalScript", entry.slice(0, -12)];
  return ["ModuleScript", entry.slice(0, -5)];
}

function directoryChildren(dirPath) {
  let xml = "";
  for (const entry of readdirSync(dirPath).sort()) {
    const fullPath = join(dirPath, entry);
    if (statSync(fullPath).isDirectory()) {
      xml += folderItem(entry, directoryChildren(fullPath));
    } else if (entry.endsWith(".luau")) {
      const [className, name] = classFor(entry);
      xml += scriptItem(className, name, fullPath);
    }
  }
  return xml;
}

const sharedXml = folderItem("Shared", directoryChildren(join(ROOT, "src/shared")));
const serverXml = directoryChildren(join(ROOT, "src/server"));
const clientXml = directoryChildren(join(ROOT, "src/client"));

// Baseplate und Spawn: die Testziele und den Hehler baut TestTargets beim
// Serverstart selbst, hier steht nur der Boden, auf dem sie stehen.
const IDENTITY_ROT = `<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>`;

const worldXml = `<Item class="Part" referent="${nextReferent()}">
<Properties>
<string name="Name">Baseplate</string>
<bool name="Anchored">true</bool>
<bool name="CanCollide">true</bool>
<CoordinateFrame name="CFrame"><X>0</X><Y>-8</Y><Z>0</Z>${IDENTITY_ROT}</CoordinateFrame>
<Vector3 name="size"><X>512</X><Y>16</Y><Z>512</Z></Vector3>
<!-- RGB(118,120,116): heller Untergrund. Ein fast schwarzer Boden unter
     einer hellen Stadt sieht aus wie ein Loch. -->
<Color3uint8 name="Color3uint8">4285954164</Color3uint8>
<token name="TopSurface">0</token>
<token name="BottomSurface">0</token>
</Properties>
</Item>
<Item class="SpawnLocation" referent="${nextReferent()}">
<Properties>
<string name="Name">SpawnLocation</string>
<bool name="Anchored">true</bool>
<bool name="CanCollide">true</bool>
<CoordinateFrame name="CFrame"><X>0</X><Y>0.5</Y><Z>10</Z>${IDENTITY_ROT}</CoordinateFrame>
<Vector3 name="size"><X>16</X><Y>1</Y><Z>16</Z></Vector3>
<Color3uint8 name="Color3uint8">4278213225</Color3uint8>
<token name="TopSurface">0</token>
<token name="BottomSurface">0</token>
</Properties>
</Item>
`;

// Heller Tag ueber Vantorra. Diese Werte sind nur der ZUSTAND BEIM OEFFNEN
// der Datei - sobald der Server laeuft, setzt TimeService sie aus
// Config.World neu. Sie stehen hier trotzdem passend, damit die Place-Datei
// in Studio nicht erst dunkel aufgeht und dann umspringt.
const lightingXml = `<Item class="Lighting" referent="${nextReferent()}">
<Properties>
<string name="Name">Lighting</string>
<token name="Technology">4</token>
<string name="TimeOfDay">13:30:00</string>
<float name="GeographicLatitude">12</float>
<bool name="GlobalShadows">true</bool>
<float name="Brightness">3</float>
<float name="EnvironmentDiffuseScale">1</float>
<float name="EnvironmentSpecularScale">1</float>
<float name="ShadowSoftness">0.2</float>
<Color3 name="Ambient"><R>0.541</R><G>0.557</G><B>0.588</B></Color3>
<Color3 name="OutdoorAmbient"><R>0.659</R><G>0.682</G><B>0.722</B></Color3>
<Color3 name="FogColor"><R>0.78</R><G>0.83</G><B>0.89</B></Color3>
<float name="FogEnd">2200</float>
</Properties>
<Item class="Atmosphere" referent="${nextReferent()}">
<Properties>
<string name="Name">Atmosphere</string>
<float name="Density">0.12</float>
<float name="Haze">0.6</float>
<float name="Glare">0.05</float>
<Color3 name="Color"><R>0.831</R><G>0.863</G><B>0.91</B></Color3>
<Color3 name="Decay"><R>0.588</R><G>0.659</G><B>0.745</B></Color3>
</Properties>
</Item>
<Item class="BloomEffect" referent="${nextReferent()}">
<Properties>
<string name="Name">Bloom</string>
<bool name="Enabled">true</bool>
<float name="Intensity">0.25</float>
<float name="Size">24</float>
<float name="Threshold">0.95</float>
</Properties>
</Item>
<Item class="ColorCorrectionEffect" referent="${nextReferent()}">
<Properties>
<string name="Name">ColorCorrection</string>
<bool name="Enabled">true</bool>
<float name="Brightness">0</float>
<float name="Contrast">0.08</float>
<float name="Saturation">0.05</float>
<Color3 name="TintColor"><R>1</R><G>0.988</G><B>0.957</B></Color3>
</Properties>
</Item>
</Item>
`;

const place = `<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
<Item class="Workspace" referent="${nextReferent()}">
<Properties>
<string name="Name">Workspace</string>
<float name="Gravity">196.2</float>
<bool name="StreamingEnabled">true</bool>
<int name="StreamingMinRadius">128</int>
<int name="StreamingTargetRadius">512</int>
</Properties>
${worldXml}</Item>
${lightingXml}<Item class="ReplicatedStorage" referent="${nextReferent()}">
<Properties>
<string name="Name">ReplicatedStorage</string>
</Properties>
${sharedXml}</Item>
<Item class="ServerScriptService" referent="${nextReferent()}">
<Properties>
<string name="Name">ServerScriptService</string>
</Properties>
${serverXml}</Item>
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
