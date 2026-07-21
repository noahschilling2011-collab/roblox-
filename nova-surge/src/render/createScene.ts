import * as THREE from "three";
import { ARENAS, DEBUG_ARENA, type ArenaDef } from "../config/arena";
import { FEEL } from "../config/tuning";

export interface SceneSetup {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  /** Zeigt die gewählte Arena (Meshes, Fog, Himmel); alle anderen versteckt. */
  showArena(def: ArenaDef): void;
}

// Alle Arenen werden EINMAL beim Boot gebaut und per Sichtbarkeit
// umgeschaltet — kein Aufbau/Abbau zur Laufzeit, keine Leaks.

export function createScene(aspect: number): SceneSetup {
  const scene = new THREE.Scene();

  const hemi = new THREE.HemisphereLight(0xe8f4ff, 0x4d5560, 1.0);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff2dc, 1.5);
  sun.position.set(35, 60, 25);
  scene.add(sun);

  const camera = new THREE.PerspectiveCamera(FEEL.baseFov, aspect, 0.05, 300);
  camera.position.set(0, 1.7, 12);

  const groups = new Map<string, THREE.Group>();
  // Debug-Arena wird mitgebaut (winzig), ist aber nur via ?debug=1 wählbar
  for (const def of [...ARENAS, DEBUG_ARENA]) {
    const g = buildArenaGroup(def);
    g.visible = false;
    scene.add(g);
    groups.set(def.id, g);
  }

  const fog = new THREE.Fog(0xffffff, 50, 150);
  scene.fog = fog;

  function showArena(def: ArenaDef): void {
    for (const [id, g] of groups) g.visible = id === def.id;
    scene.background = new THREE.Color(def.palette.sky);
    fog.color.setHex(def.palette.sky);
    fog.near = def.palette.fogNear;
    fog.far = def.palette.fogFar;
  }

  showArena(ARENAS[0]!);
  return { scene, camera, showArena };
}

const unitBox = new THREE.BoxGeometry(1, 1, 1);

function buildArenaGroup(def: ArenaDef): THREE.Group {
  const group = new THREE.Group();
  const p = def.palette;

  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(def.size + 40, def.size + 40),
    new THREE.MeshLambertMaterial({ color: p.floor })
  );
  floor.rotation.x = -Math.PI / 2;
  group.add(floor);

  if (def.showGrid !== false) {
    const grid = new THREE.GridHelper(def.size, def.size / 4, p.grid1, p.grid2);
    grid.position.y = 0.02;
    group.add(grid);
  }

  const materials = {
    wall: new THREE.MeshLambertMaterial({ color: p.wall }),
    tall: new THREE.MeshLambertMaterial({ color: p.tall }),
    low: new THREE.MeshLambertMaterial({ color: p.low }),
  };
  const trimMaterial = new THREE.MeshLambertMaterial({ color: p.accent });
  const gateMaterial = new THREE.MeshLambertMaterial({
    color: p.accent,
    emissive: p.accent,
    emissiveIntensity: 0.35,
  });

  def.boxes.forEach((b) => {
    const base = b.y ?? 0;
    const mesh = new THREE.Mesh(unitBox, materials[b.kind]);
    mesh.scale.set(b.sx, b.h, b.sz);
    mesh.position.set(b.x, base + b.h / 2, b.z);
    group.add(mesh);
    // Akzentkante oben auf Deckungen — nur für kompakte Boden-Deckungen.
    // Dünne Wände/Geländer und Etagen-Elemente (y > 0) bekommen KEINE Kante
    // (Draw-Call-Budget: Innenräume bestehen aus vielen schlanken Wänden).
    if ((b.kind === "tall" || b.kind === "low") && Math.min(b.sx, b.sz) >= 0.6 && base === 0) {
      const trim = new THREE.Mesh(unitBox, trimMaterial);
      trim.scale.set(b.sx + 0.06, 0.09, b.sz + 0.06);
      trim.position.set(b.x, base + b.h + 0.045, b.z);
      group.add(trim);
    }
  });

  // Treppen: EINE gekippte Rampen-Box pro Treppe (statt ~12 Stufen-Meshes —
  // Draw-Call-Budget). Die KOLLISION bleibt der Stufen-Generator; die Rampe
  // liegt optisch bündig auf den Stufen-Oberkanten.
  for (const s of def.stairs ?? []) {
    const asc = s.from[2] <= s.to[2];
    const [fx, fz, fy] = asc ? s.from : s.to;
    const [tx, tz, ty] = asc ? s.to : s.from;
    const rise = ty - fy;
    const alongX = Math.abs(tx - fx) >= Math.abs(tz - fz);
    const run = alongX ? tx - fx : tz - fz;
    const length = Math.hypot(rise, run);
    const ramp = new THREE.Mesh(unitBox, materials.low);
    if (alongX) {
      ramp.scale.set(length, 0.35, s.width);
      ramp.rotation.z = Math.atan2(rise, run);
    } else {
      ramp.scale.set(s.width, 0.35, length);
      ramp.rotation.x = -Math.atan2(rise, run);
    }
    ramp.position.set((fx + tx) / 2, (fy + ty) / 2 + 0.05, (fz + tz) / 2);
    group.add(ramp);
  }

  // Deko-Props (keine Kollision): Neonschilder, Deck, Pflanzen, ...
  if (def.props) {
    for (const pr of def.props) {
      const mesh = new THREE.Mesh(
        unitBox,
        new THREE.MeshLambertMaterial(
          pr.glow ? { color: pr.color, emissive: pr.color, emissiveIntensity: 0.7 } : { color: pr.color }
        )
      );
      mesh.scale.set(pr.sx, pr.sy, pr.sz);
      mesh.position.set(pr.x, pr.y, pr.z);
      group.add(mesh);
    }
  }

  // Spawn-Markierung: Tor-Rahmen an Wandmitten, sonst flaches Leucht-Pad
  // (z. B. Yacht: Spawns liegen im Deck-Inneren — Pad statt Rahmen).
  for (const sp of def.enemySpawns) {
    const spawnY = sp.y ?? 0;
    const nearPerimeter = spawnY === 0 && Math.max(Math.abs(sp.x), Math.abs(sp.z)) > def.size / 2 - 4;
    const gate = new THREE.Mesh(unitBox, gateMaterial);
    if (nearPerimeter) {
      const onXWall = Math.abs(sp.x) > Math.abs(sp.z);
      gate.scale.set(onXWall ? 0.4 : 6, 3.4, onXWall ? 6 : 0.4);
      gate.position.set(sp.x * 1.06, 1.7, sp.z * 1.06);
    } else {
      // Erhöhte Spawns (Etagen/Decks) bekommen ein flaches Leucht-Pad
      gate.scale.set(2.4, 0.06, 2.4);
      gate.position.set(sp.x, spawnY + 0.05, sp.z);
    }
    group.add(gate);
  }

  return group;
}
