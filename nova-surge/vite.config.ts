import { defineConfig } from "vite";

export default defineConfig({
  // Relative Pfade, damit der Build als reines Static-Bundle überall läuft
  // (CrazyGames lädt das Spiel aus einem Unterpfad).
  base: "./",
  build: {
    target: "es2022",
    sourcemap: false,
    // Ein Bundle ist für ein Spiel dieser Größe gewollt (kein Code-Splitting);
    // die Standard-Warnung ab 500 kB wäre nur Rauschen. Budget-Grenze: 20 MB Gesamtgröße.
    chunkSizeWarningLimit: 900,
  },
});
