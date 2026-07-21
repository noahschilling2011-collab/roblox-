// Waypoint-Navigation (Multi-Level Phase 2): Der Graph wird beim Arena-Wechsel
// aus den Kollisions-Boxen generiert (Raster-Sampling + Treppen-Links +
// einseitige Drop-Kanten), A* läuft allokationsfrei auf vorab angelegten
// Arrays. Gegner nutzen Pfade NUR, wenn der Spieler auf einer anderen Ebene
// steht — auf flachen Maps kostet das System praktisch nichts.

import { NAV } from "../config/nav";
import type { ArenaDef } from "../config/arena";
import type { CollisionWorld } from "./collision";
import type { Aabb } from "./math";

export interface NavGraph {
  nodeCount: number;
  nodeX: Float32Array;
  nodeY: Float32Array;
  nodeZ: Float32Array;
  /** CSR-Adjazenz: Kanten von Knoten n = edgeTarget[edgeStart[n] .. edgeStart[n+1]). */
  edgeStart: Int32Array;
  edgeTarget: Int32Array;
  edgeCost: Float32Array;
  walkEdges: number;
  dropEdges: number;
  stairLinks: number;
}

/** Steht ein Körper (Radius/Höhe aus NAV) frei an dieser Fußposition? */
function hasClearance(x: number, y: number, z: number, solids: readonly Aabb[]): boolean {
  const r = NAV.clearanceRadius;
  const y0 = y + 0.05; // minimal über der Standfläche (die eigene Stufe zählt nicht)
  const y1 = y + NAV.clearanceHeight;
  for (let i = 0; i < solids.length; i++) {
    const b = solids[i]!;
    if (x + r <= b.minX || x - r >= b.maxX) continue;
    if (z + r <= b.minZ || z - r >= b.maxZ) continue;
    if (y1 > b.minY && y0 < b.maxY) return false;
  }
  return true;
}

export function buildNavGraph(arena: ArenaDef, world: CollisionWorld): NavGraph {
  const solids = world.solids;
  const half = arena.size / 2 - 0.8; // Innenkante der Außenwände
  const n = Math.max(2, Math.floor((half * 2) / NAV.cellSize));
  const cell = (half * 2) / n;

  const xs: number[] = [];
  const ys: number[] = [];
  const zs: number[] = [];
  // Knoten pro Rasterzelle (nur während des Baus; Laufzeit nutzt flache Arrays)
  const cellNodes: number[][][] = [];
  const candidates: number[] = [];

  for (let i = 0; i < n; i++) {
    cellNodes.push([]);
    for (let j = 0; j < n; j++) {
      const x = -half + cell * (i + 0.5);
      const z = -half + cell * (j + 0.5);
      // Außerhalb der begehbaren Klammer (z. B. Wasser um die Yacht):
      // keine Knoten — spart Speicher und nearestNode-Scans
      if (Math.abs(x) > world.halfX - 0.4 || Math.abs(z) > world.halfZ - 0.4) {
        cellNodes[i]!.push([]);
        continue;
      }
      // Kandidaten-Höhen: Boden + jede Box-Oberkante unter dem Punkt
      candidates.length = 0;
      candidates.push(0);
      for (const b of solids) {
        if (x <= b.minX || x >= b.maxX || z <= b.minZ || z >= b.maxZ) continue;
        if (b.maxY > 0 && b.maxY <= NAV.maxNodeY) candidates.push(b.maxY);
      }
      candidates.sort((a, b) => a - b);
      const nodesHere: number[] = [];
      let lastY = -99;
      for (const y of candidates) {
        if (y - lastY < 0.2) continue; // fast identische Ebenen zusammenfassen
        if (!hasClearance(x, y, z, solids)) continue;
        nodesHere.push(xs.length);
        xs.push(x);
        ys.push(y);
        zs.push(z);
        lastY = y;
      }
      cellNodes[i]!.push(nodesHere);
    }
  }

  // Kantenlisten (Bauzeit-Allokation okay)
  const adj: number[][] = xs.map(() => []);
  const cost: number[][] = xs.map(() => []);
  let walkEdges = 0;
  let dropEdges = 0;

  const addEdge = (a: number, b: number, c: number): void => {
    adj[a]!.push(b);
    cost[a]!.push(c);
  };
  /** Mittelpunkt-Check: verhindert Kanten durch dünne Wände/Geländer. */
  const midClear = (a: number, b: number): boolean =>
    hasClearance((xs[a]! + xs[b]!) / 2, Math.max(ys[a]!, ys[b]!), (zs[a]! + zs[b]!) / 2, solids);

  const dirs = [
    [1, 0],
    [0, 1],
    [1, 1],
    [1, -1],
  ] as const;
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      for (const [di, dj] of dirs) {
        const i2 = i + di;
        const j2 = j + dj;
        if (i2 < 0 || i2 >= n || j2 < 0 || j2 >= n) continue;
        const diagonal = di !== 0 && dj !== 0;
        for (const a of cellNodes[i]![j]!) {
          for (const b of cellNodes[i2]![j2]!) {
            const dy = ys[b]! - ys[a]!;
            const dist = Math.hypot(xs[b]! - xs[a]!, zs[b]! - zs[a]!);
            if (Math.abs(dy) <= NAV.stepTolerance) {
              // Ecken-Schneiden verhindern: Diagonale nur, wenn beide
              // Orthogonal-Zellen ebenfalls einen Knoten dieser Ebene haben
              if (diagonal && !(hasLevelNode(cellNodes[i2]![j]!, ys, ys[a]!) && hasLevelNode(cellNodes[i]![j2]!, ys, ys[a]!)))
                continue;
              if (!midClear(a, b)) continue;
              addEdge(a, b, dist);
              addEdge(b, a, dist);
              walkEdges++;
            } else if (!diagonal && Math.abs(dy) <= NAV.dropMax) {
              // Drop-Kante: nur von oben nach unten, einseitig. Der FALL-
              // KORRIDOR muss frei sein — sonst entstehen Kanten "durch den
              // Etagen-Boden" (Knoten auf dem Slab -> Knoten darunter), die
              // A* wählt und an denen Gegner ewig stehen bleiben.
              const from = dy < 0 ? a : b;
              const to = dy < 0 ? b : a;
              const midX = (xs[from]! + xs[to]!) / 2;
              const midZ = (zs[from]! + zs[to]!) / 2;
              if (!hasClearance(midX, ys[from]!, midZ, solids)) continue;
              // Prüfpunkt bei 75% der Strecke: klar HINTER der Absprungkante
              // (der Mittelpunkt läge bei kleinen Podesten noch über der
              // Kante und würde echte Drops fälschlich verwerfen)
              const px = xs[from]! + (xs[to]! - xs[from]!) * 0.75;
              const pz = zs[from]! + (zs[to]! - zs[from]!) * 0.75;
              if (!dropCorridorClear(px, pz, ys[to]!, ys[from]!, solids)) continue;
              if (!dropCorridorClear(xs[to]!, zs[to]!, ys[to]!, ys[from]!, solids)) continue;
              addEdge(from, to, dist + NAV.dropCost);
              dropEdges++;
            }
          }
        }
      }
    }
  }

  // Treppen: EIGENE Nav-Knoten entlang der Treppen-Mittellinie (authored-
  // walkable — die Grid-Clearance würde auf Stufen fehlschlagen, weil die
  // Nachbarstufen in den Prüfradius ragen). Die Knoten werden verkettet, an
  // beiden Enden mit dem nächsten Grid-Knoten verbunden UND mit nahen
  // Grid-Knoten gleicher Ebene verlinkt (das Grid erzeugt an Treppenrändern
  // vereinzelt Knoten — ohne Querverbindung schickt A* Gegner von dort per
  // Drop-Kante von der Treppe runter und außen herum: Endlos-Schleife).
  let stairLinks = 0;
  const gridCount = xs.length; // End-Anschlüsse nur an Grid-Knoten
  for (const s of arena.stairs ?? []) {
    const asc = s.from[2] <= s.to[2];
    const [fx, fz, fy] = asc ? s.from : s.to;
    const [tx, tz, ty] = asc ? s.to : s.from;
    const alongX = Math.abs(tx - fx) >= Math.abs(tz - fz);
    const dirX = alongX ? Math.sign(tx - fx) : 0;
    const dirZ = alongX ? 0 : Math.sign(tz - fz);
    const len = Math.hypot(tx - fx, tz - fz, ty - fy);
    const samples = Math.max(1, Math.ceil(len / 1.2));
    let prev = -1;
    for (let i = 0; i <= samples; i++) {
      const t = i / samples;
      const node = xs.length;
      xs.push(fx + (tx - fx) * t);
      ys.push(fy + (ty - fy) * t);
      zs.push(fz + (tz - fz) * t);
      adj.push([]);
      cost.push([]);
      if (prev >= 0) {
        const c = Math.hypot(xs[node]! - xs[prev]!, ys[node]! - ys[prev]!, zs[node]! - zs[prev]!);
        addEdge(prev, node, c);
        addEdge(node, prev, c);
        stairLinks++;
      }
      for (let gIdx = 0; gIdx < gridCount; gIdx++) {
        const dXZ = Math.hypot(xs[gIdx]! - xs[node]!, zs[gIdx]! - zs[node]!);
        if (dXZ > 2.0 || Math.abs(ys[gIdx]! - ys[node]!) > 0.6) continue;
        const c = Math.hypot(dXZ, ys[gIdx]! - ys[node]!);
        addEdge(gIdx, node, c);
        addEdge(node, gIdx, c);
      }
      prev = node;
    }
    // End-Anschlüsse: kurz VOR dem unteren bzw. HINTER dem oberen Ende
    const firstStairNode = xs.length - samples - 1;
    const bottomGrid = nearestGrid(xs, ys, zs, gridCount, fx - dirX * 1.2, fy, fz - dirZ * 1.2);
    const topGrid = nearestGrid(xs, ys, zs, gridCount, tx + dirX * 1.2, ty, tz + dirZ * 1.2);
    if (bottomGrid >= 0) {
      const c = Math.hypot(
        xs[bottomGrid]! - xs[firstStairNode]!,
        ys[bottomGrid]! - ys[firstStairNode]!,
        zs[bottomGrid]! - zs[firstStairNode]!
      );
      addEdge(bottomGrid, firstStairNode, c);
      addEdge(firstStairNode, bottomGrid, c);
      stairLinks++;
    }
    if (topGrid >= 0) {
      const c = Math.hypot(xs[topGrid]! - xs[prev]!, ys[topGrid]! - ys[prev]!, zs[topGrid]! - zs[prev]!);
      addEdge(topGrid, prev, c);
      addEdge(prev, topGrid, c);
      stairLinks++;
    }
  }

  // CSR-Form für die Laufzeit
  const nodeCount = xs.length;
  const edgeStart = new Int32Array(nodeCount + 1);
  let total = 0;
  for (let i = 0; i < nodeCount; i++) {
    edgeStart[i] = total;
    total += adj[i]!.length;
  }
  edgeStart[nodeCount] = total;
  const edgeTarget = new Int32Array(total);
  const edgeCost = new Float32Array(total);
  let k = 0;
  for (let i = 0; i < nodeCount; i++) {
    for (let e = 0; e < adj[i]!.length; e++) {
      edgeTarget[k] = adj[i]![e]!;
      edgeCost[k] = cost[i]![e]!;
      k++;
    }
  }

  return {
    nodeCount,
    nodeX: Float32Array.from(xs),
    nodeY: Float32Array.from(ys),
    nodeZ: Float32Array.from(zs),
    edgeStart,
    edgeTarget,
    edgeCost,
    walkEdges,
    dropEdges,
    stairLinks,
  };
}

function hasLevelNode(nodes: readonly number[], ys: readonly number[], y: number): boolean {
  for (const idx of nodes) if (Math.abs(ys[idx]! - y) <= NAV.stepTolerance) return true;
  return false;
}

/** Nächster GRID-Knoten (Treppen-Knoten ausgenommen) im Suchradius. */
function nearestGrid(
  xs: number[],
  ys: number[],
  zs: number[],
  gridCount: number,
  x: number,
  y: number,
  z: number
): number {
  let best = -1;
  let bestScore = 2.5 + 2; // Suchradius: max ~2,5 m horizontal
  for (let i = 0; i < gridCount; i++) {
    const score = Math.hypot(xs[i]! - x, zs[i]! - z) + Math.abs(ys[i]! - y) * 2;
    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}

/** Ist die vertikale Fallstrecke (yLow..yHigh) an dieser XZ-Position frei? */
function dropCorridorClear(x: number, z: number, yLow: number, yHigh: number, solids: readonly Aabb[]): boolean {
  const r = 0.4;
  for (let i = 0; i < solids.length; i++) {
    const b = solids[i]!;
    if (x + r <= b.minX || x - r >= b.maxX) continue;
    if (z + r <= b.minZ || z - r >= b.maxZ) continue;
    if (b.maxY > yLow + 0.1 && b.minY < yHigh - 0.1) return false;
  }
  return true;
}

/** A* auf dem Graphen — alle Arbeits-Arrays vorab angelegt, Stempel statt
 *  Löschen (kein GC-Druck im Gameplay-Loop). */
class Pathfinder {
  private readonly g: NavGraph;
  private readonly gScore: Float32Array;
  private readonly fScore: Float32Array;
  private readonly parent: Int32Array;
  private readonly stampArr: Int32Array;
  private readonly closed: Int32Array;
  private readonly heap: Int32Array;
  private readonly chain: Int32Array;
  private heapSize = 0;
  private stamp = 0;

  constructor(g: NavGraph) {
    this.g = g;
    const nc = Math.max(1, g.nodeCount);
    this.gScore = new Float32Array(nc);
    this.fScore = new Float32Array(nc);
    this.parent = new Int32Array(nc);
    this.stampArr = new Int32Array(nc);
    this.closed = new Int32Array(nc);
    this.heap = new Int32Array(nc * 4);
    this.chain = new Int32Array(nc);
  }

  private h(a: number, goal: number): number {
    const g = this.g;
    return (
      Math.hypot(g.nodeX[goal]! - g.nodeX[a]!, g.nodeZ[goal]! - g.nodeZ[a]!) + Math.abs(g.nodeY[goal]! - g.nodeY[a]!)
    );
  }

  private push(node: number): void {
    const heap = this.heap;
    if (this.heapSize >= heap.length) return; // Überlauf-Schutz (A* bleibt korrekt genug)
    const f = this.fScore;
    let i = this.heapSize++;
    heap[i] = node;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (f[heap[p]!]! <= f[heap[i]!]!) break;
      const t = heap[p]!;
      heap[p] = heap[i]!;
      heap[i] = t;
      i = p;
    }
  }

  private pop(): number {
    const heap = this.heap;
    const f = this.fScore;
    const top = heap[0]!;
    const last = heap[--this.heapSize]!;
    heap[0] = last;
    let i = 0;
    for (;;) {
      const l = i * 2 + 1;
      const r = l + 1;
      let smallest = i;
      if (l < this.heapSize && f[heap[l]!]! < f[heap[smallest]!]!) smallest = l;
      if (r < this.heapSize && f[heap[r]!]! < f[heap[smallest]!]!) smallest = r;
      if (smallest === i) break;
      const t = heap[smallest]!;
      heap[smallest] = heap[i]!;
      heap[i] = t;
      i = smallest;
    }
    return top;
  }

  /** Schreibt den Pfad (vorwärts, ab Startknoten) nach `out`, liefert die
   *  Länge. Findet A* das Ziel nicht, wird der Pfad zum erreichbaren Knoten
   *  mit der geringsten Restdistanz geliefert (nie "gar nichts"). */
  find(from: number, to: number, out: Int32Array): number {
    const g = this.g;
    if (g.nodeCount === 0 || from < 0 || to < 0) return 0;
    if (from === to) {
      out[0] = to;
      return 1;
    }
    const stamp = ++this.stamp;
    this.heapSize = 0;
    this.gScore[from] = 0;
    this.fScore[from] = this.h(from, to);
    this.parent[from] = -1;
    this.stampArr[from] = stamp;
    this.push(from);
    let bestNode = from;
    let bestH = this.h(from, to);
    let expanded = 0;

    while (this.heapSize > 0 && expanded < NAV.maxExpand) {
      const cur = this.pop();
      if (this.closed[cur] === stamp) continue;
      this.closed[cur] = stamp;
      expanded++;
      if (cur === to) {
        bestNode = to;
        break;
      }
      const hCur = this.h(cur, to);
      if (hCur < bestH) {
        bestH = hCur;
        bestNode = cur;
      }
      const end = g.edgeStart[cur + 1]!;
      for (let e = g.edgeStart[cur]!; e < end; e++) {
        const nb = g.edgeTarget[e]!;
        if (this.closed[nb] === stamp) continue;
        const tentative = this.gScore[cur]! + g.edgeCost[e]!;
        if (this.stampArr[nb] !== stamp || tentative < this.gScore[nb]!) {
          this.stampArr[nb] = stamp;
          this.gScore[nb] = tentative;
          this.fScore[nb] = tentative + this.h(nb, to);
          this.parent[nb] = cur;
          this.push(nb);
        }
      }
    }

    // Kette rückwärts einsammeln, dann vorwärts (ab Start) ausgeben
    let len = 0;
    let cur = bestNode;
    while (cur >= 0 && len < this.chain.length) {
      this.chain[len++] = cur;
      cur = this.parent[cur]!;
    }
    const outLen = Math.min(len, out.length);
    for (let i = 0; i < outLen; i++) out[i] = this.chain[len - 1 - i]!;
    return outLen;
  }
}

/** Laufzeit-Fassade für die Sim: Budget pro Tick, Statistiken fürs F3-Overlay. */
export class NavSystem {
  readonly graph: NavGraph;
  private readonly finder: Pathfinder;
  private budgetLeft = 0;
  private repathAccum = 0;
  private repathWindow = 0;
  /** Repaths der letzten vollen Sekunde (F3). */
  repathsPerSecond = 0;
  /** Gegner, die diesen Tick einem Pfad folgen (F3, von EnemyManager gesetzt). */
  activeFollowers = 0;

  constructor(arena: ArenaDef, world: CollisionWorld) {
    this.graph = buildNavGraph(arena, world);
    this.finder = new Pathfinder(this.graph);
  }

  /** Einmal pro Sim-Tick aufrufen: Budget zurücksetzen, Statistik rollen. */
  beginTick(dt: number): void {
    this.budgetLeft = NAV.repathBudget;
    this.activeFollowers = 0;
    this.repathWindow += dt;
    if (this.repathWindow >= 1) {
      this.repathsPerSecond = this.repathAccum;
      this.repathAccum = 0;
      this.repathWindow = 0;
    }
  }

  nearestNode(x: number, y: number, z: number): number {
    const g = this.graph;
    let best = -1;
    let bestScore = Infinity;
    for (let i = 0; i < g.nodeCount; i++) {
      const score = Math.hypot(g.nodeX[i]! - x, g.nodeZ[i]! - z) + Math.abs(g.nodeY[i]! - y) * 2;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /** Pfad berechnen, wenn das Tick-Budget es erlaubt. true = Pfad erneuert. */
  tryRepath(fromX: number, fromY: number, fromZ: number, toX: number, toY: number, toZ: number, out: Int32Array): number {
    if (this.budgetLeft <= 0) return -1;
    this.budgetLeft--;
    this.repathAccum++;
    const from = this.nearestNode(fromX, fromY, fromZ);
    const to = this.nearestNode(toX, toY, toZ);
    return this.finder.find(from, to, out);
  }

  debugLine(): string {
    const g = this.graph;
    return `nav       ${g.nodeCount} nodes · ${g.walkEdges}w/${g.dropEdges}d/${g.stairLinks}s · ${this.activeFollowers} paths · ${this.repathsPerSecond} rp/s`;
  }
}
