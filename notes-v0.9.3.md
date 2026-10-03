**New: Records screen** (main menu > Records). Panel Attack only keeps a few records, and most aren't visible anywhere in the game, so this port adds a screen for them:

- **Endless and Time Attack:** best score, last score, best chain and games played for every setting: Classic (Easy, Normal, Hard, EX) and Modern (levels 1–11). Panel Attack itself only saves Classic-style scores; Modern ones are saved from this version on. Classic records you set before updating are included.
- **Vs CPU:** best total time for each difficulty, how many times you've cleared it and continues used. Pick a difficulty to see the stage times of your best run next to your best time on each stage. Vs CPU times weren't saved before, so they start with your next clear.
- **Vs Yourself:** best and last garbage lines sent per level (Panel Attack's own records).
- **Lifetime:** biggest chain and combo, panels cleared, garbage sent, and how many chains and combos of each size you've made, from the stats Panel Attack already keeps (Options > General > Enable analytics).

Switch modes with L/R or left/right. The new records are saved in `data/miyoo_records.json`; Panel Attack's own save files are only read.

This screen is added by the port and isn't part of Panel Attack. Please report problems [here](https://github.com/snyderman3000/panelattack-miyoo/issues), not to the Panel Attack team.
