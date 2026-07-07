--!strict
-- QuestConfig: die Session-Aufträge von Turmfall (pur, testbar).
--
-- Drei klare Ziele pro Session mit Trümmer-Belohnung - kurzfristige Ziele
-- neben dem Runden-Loop sind ein Standard-Muster der Roblox-Topspiele.
-- Getrackt wird alles serverseitig (QuestService); die IDs entsprechen
-- den Zähler-Hooks: "platzieren", "katastrophe", "gold".

export type QuestDef = {
	id: string,
	text: string,
	target: number,
	rewardDebris: number,
}

local QuestConfig = {}

QuestConfig.Quests = {
	{ id = "platzieren", text = "🧱 Platziere 15 Teile", target = 15, rewardDebris = 75 },
	{ id = "katastrophe", text = "🌪️ Erlebe 1 Katastrophe", target = 1, rewardDebris = 50 },
	{ id = "gold", text = "✨ Baue 2 goldene Teile", target = 2, rewardDebris = 100 },
} :: { QuestDef }

return QuestConfig
