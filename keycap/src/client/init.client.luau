--!strict
-- Startet die Controller. Der Client zeigt nur an und schickt Absichten.

local Controllers = script:WaitForChild("Controllers")

local HudController = require(Controllers.HudController)
local ShopController = require(Controllers.ShopController)

HudController.start()
ShopController.start()

print("[KEYCAP] Client bereit.")
