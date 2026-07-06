--!strict
-- ReceiptLogic: pure Idempotenz-Logik für Kauf-Belege (testbar).
--
-- Roblox ruft ProcessReceipt so lange erneut auf, bis PurchaseGranted
-- zurückkommt - auch nach Abstürzen oder Server-Wechseln. Wird derselbe
-- Beleg dann zweimal gutgeschrieben, ist das der häufigste Anfängerfehler
-- in der Roblox-Monetarisierung. Darum führt jedes Profil ein Log der
-- verarbeiteten Receipt-IDs (persistiert im DataStore): Ein bekannter
-- Beleg wird NUR bestätigt, nie erneut gutgeschrieben.

local ReceiptLogic = {}

-- So viele Belege merken wir uns pro Profil (mehr braucht kein Mensch;
-- verhindert unbegrenztes Profil-Wachstum).
ReceiptLogic.LOG_LIMIT = 50

-- Wurde dieser Beleg bereits verarbeitet?
function ReceiptLogic.alreadyProcessed(receiptIds: { string }, receiptId: string): boolean
	return table.find(receiptIds, receiptId) ~= nil
end

-- Merkt sich einen verarbeiteten Beleg (älteste fliegen raus).
-- Verändert die Liste in place, damit sie direkt im Profil liegt.
function ReceiptLogic.remember(receiptIds: { string }, receiptId: string)
	if ReceiptLogic.alreadyProcessed(receiptIds, receiptId) then
		return
	end
	table.insert(receiptIds, receiptId)
	while #receiptIds > ReceiptLogic.LOG_LIMIT do
		table.remove(receiptIds, 1)
	end
end

return ReceiptLogic
