# TrisThreat

## Unreleased

- Removed the red aggro-warning glow. The safe-target indicator recommends one attackable enemy with a confirmed threat lead, prioritizes the selected tank's target, and supports automatic or per-group tank selection.
- Added safe-glow color selection and fades between recommendations. The glow is a feathered ring with rounded corners outside the health-bar rectangle, so current HP remains visible.
- Safe-glow rework: round radial corners, one soft profile per Feather step, and a gutter around each texture tile so mipmaps cannot bleed dark spots. The glow wraps bar and strip; the strip number gets a shadow for contrast.
- Safe glow is stricter: an enemy glows only while the tank (or pet) holding it leads clearly, is targeting exactly that enemy, and your own threat on it is low (under 60 % of the holder's where the game exposes it). Each tank's target can glow, so two tanks give two glows. Unreadable threat counts as not safe.
- Safe glow now lights only the top edge of the nameplate bar and radiates upward (straight edge plus rounded end caps); the sides and bottom no longer glow.
- Safe glow settings: new Width (widen or narrow both ends) and Position (lift or sink) sliders. Removed the Feather slider and the Test button (toggling the option or moving a slider already shows the glow).
- Snap spots in the settings preview: strip at top and bottom center, badge above the top-left or top-right corner (new), plus the badge beside the bar and the segment ends. The "badge below" spot is gone; a stored badge-below setting still works.
- Added separate Solo and Group visibility controls. The health-bar color option applies to the filled portion only.

## 0.1.0

- First version: a threat element attached to the health bar of every enemy nameplate that fights you, with the threat value. The nameplate bar itself can be tinted by threat (Platynator and Blizzard nameplates).
- Pulsing red aggro warning glow (tank loses the enemy, anybody else pulls it).
- Glows section in the settings: Aggro warning glow (red) and Safe target glow (green) are soft pill-shaped pulsing glows around the health bar (and the strip) with sliders for reach, strength and feather; each with a checkbox and a Test button (preview, plus your real target plate). Safe target glow: a green pulsing halo on the enemy that is safest to attack (a group tank or your pet holds it and you are not on its threat list; if the tank targets one of them, only that one). For damage dealers and healers, can be switched off. `/tt probe` also reports whether a tank's target is readable.
- Continuous color grading from green (0 %) over yellow to red (100 %), for tanks driven by the lead over the next player (the strip is full and green with a big lead and shrinks and reddens as it melts), evaluated on a color curve so secret threat values work. Automatic role detection with a manual override; blue off-tank color when another tank or your pet holds the enemy. `/tt probe` reports whether the curve works on your client.
- Blizzard's nameplate art: a badge (like the level badge, left/right/top/bottom of the bar, or dragged anywhere, with a size setting), a segment in the bar's left or right end, or a strip above/below the bar. No mode switch: drag the element in the settings preview; dots mark the spots that snap it to a badge position or turn it into the strip. Optional make-room moves name, raid icon and crowd-control icons aside.
- Color combinations: number, background, nameplate bar.
- Settings window with a live copy of the Blizzard nameplate and filters; while it is open, your target gets a test element without combat.
- Titan Panel / LibDataBroker display showing the current mode (Tank, DPS or Healer mode; * = set by hand), addon compartment entry and a minimap icon that can be hidden with a right-click.
- WoW Forever (beta) only; there is no Retail build.
