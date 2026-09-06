--!strict
-- Aufbau der Karte. Alles wird zur Laufzeit aus Parts gebaut, damit die
-- Place-Datei leer bleiben kann. Keine Magic Numbers in den Services.

local WorldConfig = {
	-- Plots: eine Reihe nebeneinander, je Spieler einer.
	PLOT_COUNT = 12, -- Obergrenze fuer die Servergroesse
	PLOT_SIZE = Vector3.new(48, 2, 48),
	PLOT_SPACING = 64, -- Mittenabstand zweier Plots
	PLOT_ORIGIN = Vector3.new(0, 8, 0), -- Mitte des ersten Plots

	-- Steckplaetze auf dem Plot: Raster, auf dem die Tasten stehen.
	SLOT_COLUMNS = 5,
	SLOT_SPACING = 9,
	KEY_SIZE = Vector3.new(6, 3, 6),

	-- "Zuhause": Radius um die Plotmitte, in dem der Besitzer als anwesend
	-- gilt (verdoppelt die Klau-Dauer).
	PRESENCE_RADIUS = 34,

	-- Parcours: drei Stages, jede weiter weg. Die Cash-Out-Pads stehen am
	-- Ende der jeweiligen Stage.
	STAGE_PAD_POSITIONS = {
		Vector3.new(0, 8, -140),
		Vector3.new(0, 8, -300),
		Vector3.new(0, 8, -520),
	},
	STAGE_PAD_SIZE = Vector3.new(24, 2, 24),

	-- Speed-Tore: wer langsamer ist, kommt nicht durch.
	STAGE_GATE_POSITIONS = {
		Vector3.new(0, 12, -60),
		Vector3.new(0, 12, -210),
		Vector3.new(0, 12, -400),
	},
	STAGE_GATE_SIZE = Vector3.new(40, 12, 2),

	-- Laufweg zwischen Plotreihe und Stage 1.
	PATH_WIDTH = 40,

	-- Wie oft der Server den Zustand an die Clients schickt.
	STATE_PUSH_INTERVAL = 0.5,

	-- NPC-Plots [ENTSCHEIDUNG]
	-- Die Bewertung: "Der Loop braucht Mitspieler und du hast keine."
	-- Auf einem leeren Server waere KEYCAP RUSH ein Farm-Spiel. NPC-Plots
	-- sind immer da und immer beklaubar - sie fuellen die Luecke, ohne den
	-- Wettbewerb zwischen echten Spielern zu ersetzen.
	NPC_PLOT_COUNT = 3, -- belegen die letzten Plots der Reihe
	NPC_NAMES = { "Alte Tastatur", "Fundbuero", "Schrottplatz" },

	-- Part-Budget: obere Schranke fuer alles, was der Server baut.
	-- Auf dem Handy ist die Zahl gleichzeitig sichtbarer ProximityPrompts
	-- oft das engere Limit als die reine Part-Zahl. UNGEPRUEFT - nicht gemessen.
	PART_BUDGET = 3000,
}

return WorldConfig
