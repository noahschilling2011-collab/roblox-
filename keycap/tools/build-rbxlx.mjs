// Baut aus src/ eine fertig oeffnbare Roblox-Studio-Datei (KeycapRush.rbxlx),
// nach demselben Mapping wie default.project.json (Rojo):
//   src/shared  -> ReplicatedStorage.Shared
//   src/server  -> ServerScriptService.KeycapRush (Script mit Ordner "Services")
//   src/client  -> StarterPlayer.StarterPlayerScripts.KeycapRush (LocalScript)
// Ausfuehren:  node tools/build-rbxlx.mjs
import { readFileSync, readdirSync, statSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { pathToFileURL } from "url";

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

// Keine Drehung - alles in dieser Welt steht achsenparallel.
const IDENTITY_ROT = `<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>`;

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

// ---------------------------------------------------------------------
// Vorschau der Welt.
//
// Der Server baut Plots, Wege, Tore und Pads erst beim Start. Wer die Datei
// nur oeffnet, sah deshalb einen leeren Boden mit einem Spawn-Pad - das
// sieht aus, als waere nichts drin. Diese Vorschau backt dieselbe Geometrie
// fest in die Datei; init.server.luau loescht sie beim Start wieder, bevor
// der Server seine eigene baut.
//
// Die Positionen kommen aus src/shared/WorldLayout.luau, ausgefuehrt in
// einer echten Luau-VM. Nichts wird hier nachgerechnet - sonst laufen
// Vorschau und Spielwelt auseinander.
async function weltVorschau() {
  const luauPath = join(ROOT, "tests/node_modules/luau-web/src/index.js");
  if (!existsSync(luauPath)) {
    console.warn("! luau-web fehlt (cd tests && npm install) - Datei wird OHNE Weltvorschau gebaut.");
    return "";
  }
  const { LuauState } = await import(pathToFileURL(luauPath).href);

  function modul(relPath) {
    return readFileSync(join(ROOT, relPath), "utf8")
      .replace(/^--!strict\s*$/m, "")
      .replace(/^local (\w+) = require\(.+\)$/gm, 'local $1 = __deps["$1"]')
      .replace(/^export type/gm, "type");
  }

  const prelude = `
local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
local Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
local Enum = setmetatable({}, { __index = function(_, class)
	return setmetatable({}, { __index = function(_, item) return class .. "." .. item end })
end })
local __deps = {}
`;

  const module_list = [
    ["WorldConfig", "src/shared/Config/WorldConfig.luau"],
    ["EconomyConfig", "src/shared/Config/EconomyConfig.luau"],
    ["Theme", "src/shared/Theme.luau"],
    ["WorldLayout", "src/shared/WorldLayout.luau"],
  ];
  let body = prelude;
  for (const [name, relPath] of module_list) {
    body += `\n__deps["${name}"] = (function()\n${modul(relPath)}\nend)()\n`;
  }

  // Sammelt alle Parts als flache Liste "name|sx,sy,sz|px,py,pz|r,g,b|legende".
  const collect = `
local World = __deps["WorldConfig"]
local Economy = __deps["EconomyConfig"]
local Theme = __deps["Theme"]
local Layout = __deps["WorldLayout"]

local zeilen = {}
local function part(name, size, position, color, legende)
	table.insert(zeilen, ("%s|%g,%g,%g|%g,%g,%g|%d,%d,%d|%s"):format(
		name, size.X, size.Y, size.Z, position.X, position.Y, position.Z,
		color.r, color.g, color.b, legende or ""))
end

local promenade = Layout.promenade()
part("Promenade", promenade.size, promenade.position, Theme.WORLD.PATH)
local weg = Layout.path()
part("Path", weg.size, weg.position, Theme.WORLD.PATH)

for index = 1, World.PLOT_COUNT do
	local mitte = Layout.plotPosition(index)
	part("Plot" .. index, World.PLOT_SIZE, mitte, Theme.WORLD.PLATE)

	-- Chassis unter der Platte, gleiche Rechnung wie PlotService.buildWorld.
	part("Deck" .. index,
		Vector3.new(
			World.PLOT_SIZE.X + World.PLOT_DECK_OVERHANG * 2,
			World.PLOT_DECK_HEIGHT,
			World.PLOT_SIZE.Z + World.PLOT_DECK_OVERHANG * 2
		),
		Vector3.new(mitte.X, mitte.Y - World.PLOT_SIZE.Y / 2 - World.PLOT_DECK_HEIGHT / 2, mitte.Z),
		Theme.WORLD.CHASSIS)

	-- Schildtafel an der Vorderkante.
	local schild = Layout.signPosition(mitte)
	part("Sign" .. index, World.SIGN_BOARD_SIZE, schild, Theme.WORLD.PLATE)
end

-- Steckplatz-Mulden fehlen in der Vorschau mit Absicht: auf einem frischen
-- Server gehoert kein Plot jemandem, und ohne Besitzer sind sie ausgeblendet.
-- Sie erscheinen, sobald ein Spieler einen Plot bekommt.

-- Auf den NPC-Plots stehen von Anfang an Tasten. Sie zeigen in der Vorschau,
-- wie ein besetzter Plot aussieht; Spielerplots sind beim Oeffnen leer, weil
-- ohne Spieler auch keine Tasten existieren.
for slot = 1, World.NPC_PLOT_COUNT do
	local plotIndex = World.PLOT_COUNT - slot + 1
	local mitte = Layout.plotPosition(plotIndex)
	for keyIndex = 1, Economy.NPC_KEY_COUNT do
		local rarity = Economy.NPC_RARITIES[keyIndex] or "Common"
		-- Dieselbe Rechnung wie in PlotService.renderKeys: die Grundflaeche
		-- bleibt, die Taste waechst nach oben. Ohne das steht in der Vorschau
		-- eine andere Welt als im laufenden Spiel.
		local crown = Theme.KEY_CROWN[rarity] or 1
		local extra = World.KEY_SIZE.Y * (crown - 1)
		local basis = Layout.slotPosition(mitte, keyIndex)
		local koerperHoehe = World.KEY_SIZE.Y * crown
		local mitteY = basis.Y + extra / 2
		part("Key" .. keyIndex,
			Vector3.new(World.KEY_SIZE.X, koerperHoehe, World.KEY_SIZE.Z),
			Vector3.new(basis.X, mitteY, basis.Z),
			Theme.RARITY_COLORS[rarity])
		-- Deckplatte und Stem-Ring wie in PlotService.renderKeys, sonst
		-- zeigt die Vorschau Wuerfel und das Spiel Tastenkappen.
		part("KeyTop" .. keyIndex,
			Vector3.new(World.KEY_SIZE.X * World.KEY_TOP_INSET, World.KEY_TOP_HEIGHT, World.KEY_SIZE.Z * World.KEY_TOP_INSET),
			Vector3.new(basis.X, mitteY + koerperHoehe / 2 + World.KEY_TOP_HEIGHT / 2, basis.Z),
			Theme.RARITY_COLORS[rarity], World.KEY_LEGENDS[keyIndex] or "?")
		part("KeyStem" .. keyIndex,
			Vector3.new(World.KEY_SIZE.X * World.KEY_STEM_INSET, World.KEY_STEM_HEIGHT, World.KEY_SIZE.Z * World.KEY_STEM_INSET),
			Vector3.new(basis.X, mitteY - koerperHoehe / 2 + World.KEY_STEM_HEIGHT / 2, basis.Z),
			Theme.RARITY_EDGE[rarity])
	end
end

for index, position in World.STAGE_PAD_POSITIONS do
	part("CashOut" .. index, World.STAGE_PAD_SIZE, position, Theme.WORLD.SIGNAL)
	part("CashOutRing" .. index,
		Vector3.new(
			World.STAGE_PAD_SIZE.X + World.PAD_RING_OVERHANG * 2,
			World.PAD_RING_HEIGHT,
			World.STAGE_PAD_SIZE.Z + World.PAD_RING_OVERHANG * 2
		),
		Vector3.new(position.X, position.Y - World.STAGE_PAD_SIZE.Y / 2 - World.PAD_RING_HEIGHT / 2, position.Z),
		Theme.WORLD.SIGNAL_DIM)
end
for index, position in World.STAGE_GATE_POSITIONS do
	part("Gate" .. index, World.STAGE_GATE_SIZE, position, Theme.WORLD.SIGNAL_DIM)
end

return table.concat(zeilen, "\\n")
`;

  const state = await LuauState.createAsync();
  let rohdaten;
  try {
    rohdaten = await state.loadstring(body + collect, "weltvorschau", true)();
  } finally {
    state.destroy();
  }

  let xml = "";
  let anzahl = 0;
  for (const zeile of String(rohdaten).split("\n").filter(Boolean)) {
    const [name, size, position, color, legende] = zeile.split("|");
    const [sx, sy, sz] = size.split(",");
    const [px, py, pz] = position.split(",");
    const [r, g, b] = color.split(",").map(Number);
    // Color3uint8 ist alpha<<24 | r<<16 | g<<8 | b als vorzeichenlose Zahl.
    const packed = ((255 << 24) >>> 0) + (r << 16) + (g << 8) + b;
    // Material wird bewusst NICHT gesetzt: die Enum-Tokens sind hier nicht
    // nachschlagbar und ein falscher Wert koennte die Datei unbrauchbar
    // machen. Der Server setzt das Material beim Start ohnehin richtig.
    const kinder = legende
      ? `<Item class="SurfaceGui" referent="${nextReferent()}">
<Properties>
<string name="Name">Legend</string>
<token name="Face">1</token>
</Properties>
<Item class="TextLabel" referent="${nextReferent()}">
<Properties>
<string name="Name">Letter</string>
<string name="Text">${escapeXml(legende)}</string>
<bool name="TextScaled">true</bool>
<float name="BackgroundTransparency">1</float>
</Properties>
</Item>
</Item>
`
      : "";
    xml += `<Item class="Part" referent="${nextReferent()}">
<Properties>
<string name="Name">${escapeXml(name)}</string>
<bool name="Anchored">true</bool>
<Vector3 name="size"><X>${sx}</X><Y>${sy}</Y><Z>${sz}</Z></Vector3>
<CoordinateFrame name="CFrame"><X>${px}</X><Y>${py}</Y><Z>${pz}</Z>${IDENTITY_ROT}</CoordinateFrame>
<Color3uint8 name="Color3uint8">${packed}</Color3uint8>
</Properties>
${kinder}</Item>
`;
    anzahl += 1;
  }
  console.log(`Weltvorschau: ${anzahl} Parts gebacken`);
  return folderItem("WeltVorschau", xml);
}

const vorschauXml = await weltVorschau();
const sharedXml = folderItem("Shared", directoryChildren(join(ROOT, "src/shared")));
const serverXml = scriptItem("Script", "KeycapRush", join(ROOT, "src/server/init.server.luau"), directoryChildren(join(ROOT, "src/server")));
const clientXml = scriptItem("LocalScript", "KeycapRush", join(ROOT, "src/client/init.client.luau"), directoryChildren(join(ROOT, "src/client")));

// Spawn vor der Plotreihe, auf Hoehe der Promenade. Sobald ein Profil
// geladen ist, setzt PlotService den Spieler auf seinen eigenen Plot -
// dieser Punkt ist nur die Sekunde davor.
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
${spawnXml}${vorschauXml}</Item>
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
