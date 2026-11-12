# TrisThreat

## 0.1.0

- First version: a threat element attached to the health bar of every enemy nameplate that fights you, with the threat value. The nameplate bar itself can be tinted by threat (Platynator and Blizzard nameplates).
- Pulsing red aggro warning glow (tank loses the enemy, anybody else pulls it).
- Continuous color grading from green (0 %) over yellow to red (100 %), for tanks driven by the lead over the next player (the strip is full and green with a big lead and shrinks and reddens as it melts), evaluated on a color curve so secret threat values work. Automatic role detection with a manual override; blue off-tank color when another tank or your pet holds the enemy. `/tt probe` reports whether the curve works on your client.
- Blizzard's nameplate art: a badge (like the level badge, left/right/top/bottom of the bar, or dragged anywhere, with a size setting), a segment in the bar's left or right end, or a strip above/below the bar. No mode switch: drag the element in the settings preview; dots mark the spots that snap it to a badge position or turn it into the strip. Optional make-room moves name, raid icon and crowd-control icons aside.
- Color combinations: number, background, nameplate bar.
- Settings window with a live copy of the Blizzard nameplate and filters; while it is open, your target gets a test element without combat.
- Titan Panel / LibDataBroker display showing the current mode (Tank, DPS or Healer mode; * = set by hand), addon compartment entry and a minimap icon that can be hidden with a right-click.
- WoW Forever (beta) only; there is no Retail build.
