--!strict
-- Onboarding-Schritte. Reihenfolge = Spielreihenfolge.
--
-- Ziel: ein neuer Spieler versteht in unter einer Minute, was zu tun ist.
-- Jeder Schritt erklaert GENAU EINE Sache und wird durch eine Handlung
-- abgeschlossen, nicht durch Wegklicken - sonst lernt niemand etwas.
--
-- `event` = was den Schritt abschliesst. "vorrat" ist der Sonderfall: er
-- wird nicht gemeldet, sondern vom Server gegen die Speed-Kurve geprueft.

local TutorialConfig = {
	STEPS = {
		{
			id = "sammeln",
			event = "vorrat",
			requiresVorratForStage = 1, -- genug fuer das erste Tor
			text = "Deine Tasten sammeln von selbst. Je mehr Vorrat, desto schneller laeufst du.",
		},
		{
			id = "auszahlen",
			event = "cashout",
			text = "Du bist schnell genug! Lauf zum goldenen Pad und halte die Taste zum Auszahlen.",
		},
		{
			id = "kaufen",
			event = "buy",
			text = "Wins gibt es im Laden. Kauf dir eine zweite Taste - mehr Tasten, mehr Vorrat.",
		},
		{
			id = "klauen",
			event = "steal",
			text = "Am Ende der Reihe stehen fremde Plots. Halt dort die Klau-Taste und nimm dir eine.",
		},
	},

	DONE_TEXT = "Fertig! Jetzt du: sammeln, auszahlen, aufruesten - und aufpassen, wer bei dir klaut.",
	-- Belohnung fuers Durchspielen: reicht fuer ein paar Common-Tasten,
	-- macht aber niemanden reich.
	REWARD_WINS = 50,
}

return TutorialConfig
