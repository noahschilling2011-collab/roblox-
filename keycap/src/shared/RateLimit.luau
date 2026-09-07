--!strict
-- Rate-Limit pro Spieler und Kanal. Jede Remote am Server-Eingang benutzt
-- das - sonst kann ein Client den Server mit Anfragen fluten.

local RateLimit = {}

local buckets: { [string]: { tokens: number, last: number } } = {}

-- true = erlaubt. `perSecond` ist zugleich die Eimergroesse, ein Spieler
-- kann also kurz bursten und muss dann warten.
function RateLimit.allow(userId: number, channel: string, perSecond: number): boolean
	local id = userId .. "|" .. channel
	local now = os.clock()
	local bucket = buckets[id]
	if not bucket then
		buckets[id] = { tokens = perSecond - 1, last = now }
		return true
	end
	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.last) * perSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimit.forget(userId: number)
	for id in buckets do
		if id:sub(1, #tostring(userId) + 1) == userId .. "|" then
			buckets[id] = nil
		end
	end
end

return RateLimit
