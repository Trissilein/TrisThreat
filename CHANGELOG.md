# TrisThreat

## 0.1.0

- First version: a threat capsule attached to the health bar of every enemy nameplate that fights you, with the threat value. The nameplate bar itself can be tinted by threat (Platynator and Blizzard nameplates).
- Continuous color grading from green (0 %) over yellow to red (100 %), mirrored for tanks, evaluated on a color curve so secret threat values work. Automatic role detection with a manual override; blue off-tank color when another tank or your pet holds the enemy. `/tt probe` reports whether the curve works on your client.
- Display modes in Blizzard's nameplate art: badge (like the level badge, left/right/top/bottom), segment in the health bar, strip above/below the bar, or a floating capsule (offsets up to 100 pixels, size). Optional make-room moves name, raid icon and crowd-control icons aside.
- Color combinations: number, background, nameplate bar.
- Settings window with a live copy of the Blizzard nameplate, value mode and filters; while it is open, your target gets a test element without combat.
- Titan Panel / LibDataBroker launcher, addon compartment entry and a minimap icon that can be hidden with a right-click.
- Retail and WoW Forever (beta) in one package.
