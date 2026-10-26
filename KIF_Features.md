# Kuray Infinite Fusion - Feature Guide

KIF brings the features of Kuray's Infinite Fusion 0.20.7 to Pokémon Infinite Fusion 6.8.2. Everything is optional and lives in **Pause menu > Options** (also on the load screen): one screen, which also holds PIF's own options (volume, text speed, screen size, difficulty, speed-up, sprites, challenge rules), with sections on the left (Shinies, Battles, Pokémon, Graphics, Self-Battle, Challenges, Game, System, **Modules**, **Mods**, **Presets**) and that section's settings on the right, under headings. Up/Down picks, Right opens a section, Left/Right changes a setting (its choices show as a bar), Esc goes back. An orange dot marks a setting you changed; **Z** sets it back to its default (the bottom bar shows the default and whether the setting is per save or for all saves). **D** (or Q) opens the search bar (the screen shows whichever key you've bound): type, and the list shows the matching settings of every section as you type (every word has to be in the name or the description); Enter goes to the results, Esc closes the bar. The box at the bottom explains the selected setting (a long text moves up by itself). Sub-settings, such as the Base Stats sliders, only show while their setting is on. A section whose settings all belong to modules that are Off is greyed out and skipped; each module in **Modules** says which sections hold its settings. Buttons other mods add to Options are listed under **Mods**.

### Modules

Every feature belongs to a module. Each module can be:

- **Off** *(default for every module)* - the game plays like PIF: the module's features, settings, pause menu and PC entries are gone.
- **On** - the features work and their settings are listed in the Options sections.
- **Hidden** - the features work, but their settings aren't listed (for a tidier menu once you've set things up).

| Module | What's in it (sections below) |
|---|---|
| Auto Battle | Auto-Battle and its options, Self-Battle from the PC |
| Shinies | Shinies: custom colours, odds, gamble, selling, Poké Radar chains |
| Graphical Changes | EBDX battles, battle box extras, Move Effectiveness, big icons, game font, dark mode, living title screen |
| Information | Fusion preview and fusion screen, the improved Pokédex (evolutions, sprites), IVs and EVs in the summary, Battle Info |
| Battles & Challenges | Battle format, damage variance, Battle AI, Challenges, battle mechanics, level caps, EXP/EV/IV modes, Rocket mode, catching extras, Gym Leader teams, trainers keeping their rolled teams |
| Randomizer | The randomizer (incl. Entrances) and gym leader teams. Off plays a randomized save without the randomizer until it's turned back on |
| Pokémon & Fusion | Fusion rules and base stats, breeding, evolution lock, item effects, gender, move learning, Tutor.net, type overrides |
| Kuray Shop | The Kuray Shop in the pause menu, Streamer's Dream |
| K-Eggs | K-Eggs (sold in the Kuray Shop) |
| PC & Saves | PC extras (Kuray Actions), quicksave, save backups, eggs hatching into the PC |
| Import & Export | Exporting Pokémon to files and importing them back |
| Quality of Life | Pause menu extras, quick field moves, speed-up, intro skip, title screen links, Wonder Trade names, shenanigans |
| Mod Settings | The **Mods** section of Options: every installed mod with On/Off, and its settings |

Things a module changes while the game starts (some data tables) stay in place until the next start. Pokémon & Fusion's base stat rules apply the next time a Pokémon's stats are worked out (level up, evolving...).

Settings of always-available features (frame rate, updates, caches) are in the **System** section, with **Increment Slider by** and **DEBUG**. Switch modules in the **Modules** section.

The first time the game starts, it asks **How do you want to play?** - **Classic KIF** (every module On), **PIF only** (every module Off, plays like Pokémon Infinite Fusion) or **Let me choose** (opens Modules). Classic KIF leaves the features KIF 0.20.7 never had (EBDX battles, Move Effectiveness, Fusion Screen, Battle Info) Off; turn them on in KIF Settings. You can change everything later in Options > Modules.

Players who were already playing KIF before Modules existed get every module turned On once, so nothing they had set up stops working.

The box at the bottom says whether a setting is for **all saves** (shared by every save file) or **this save** (belongs to the save you're playing). Per-save settings only appear once a save is loaded, so the title screen's Options shows fewer.

The sections below list every setting by its original KIF menu; the table above says which module each belongs to.

Defaults are shown in *(italics)*.

---

## Shinies

### Global

- **Shiny Animation** - On / Off / All *(On)*. Plays the sparkle when a shiny enters battle. All plays it for every Pokémon, shiny or not.
- **Shiny Icons** - Off / On *(Off)*. Gives party and PC icons the same KIF shiny colours as the battle sprite. Looks nicer but costs performance.
- **Shiny Cache** - Permanent / Per Session / Off *(Permanent)*. KIF shiny sprites are generated once and remembered. Per Session forgets them when you close the game; Off regenerates them every time (slowest).
- **Shiny Filter** - Off / Filtered / Hybrid *(Hybrid)*. KIF's colour shifts can wash out a sprite's outlines and shading. Filtered keeps every shiny readable, Off shows the raw KIF colours, and Hybrid filters half of all shinies and leaves the other half raw.

### Per-save

- **Shiny Colors** - Simple / Normal / Advanced *(Normal)*. How KIF shinies are coloured. Simple only shifts the hue (fastest). Normal also shifts colour channels. Advanced is the full system with the widest variety (slowest).
- **PIF's Improved Shinies** - Hybrid / Split / Vanilla / Off *(Hybrid)*. How KIF's shiny colours combine with PIF's own shiny palettes.
  - Hybrid: every shiny gets KIF colours, and most also get PIF's palette.
  - Split: some shinies get PIF colours, some KIF colours, some both.
  - Vanilla: PIF shinies only.
  - Off: KIF shinies only.
- **Shiny Fuse Dye** - Off / On / Random *(Off)*. On: fusing a shiny keeps its colours on the result, so you can "dye" a fusion. Random: the colours are re-rolled after every fusion or unfusion.
- **Shiny Gamble Odds** - slider, 0-1000 *(100)*. The odds for the PC's Shiny Gamble: 1 in this number. 0 means every gamble wins.
- **Wild Shiny Odds** - slider, 1-65536 *(16)*. Your shiny chance out of 65,536. 16 is the standard 1 in 4,096; raise it for more shinies. Use "Increment Slider by" (see the end of this guide) to move it faster.
- **Shiny Trainer Pokemon** - Off / Ace / All / Normal *(Off)*.
  - Off: trainers' Pokémon have normal shiny odds.
  - Ace: every trainer's ace is shiny.
  - All: every trainer Pokémon is shiny.
  - Normal: trainer Pokémon use the same shiny odds as your Wild Shiny Odds slider. (This used to be called Disabled.)

---

## Battles & Pokemons

All options in this menu are per-save.

### Battle format and control

- **Battle Format** - 1v1 / 2v2 / 3v3 *(1v1)*. Turns battles into doubles or triples whenever the game allows it.
- **Format Applies To** - Wild / Trainers / Both *(Wild)*. Which battles Battle Format affects.
- **Auto-Battle** - Off / On *(Off)*. The Auto-Battler: an ally AI picks your moves and replacements for you. Your Pokémon still count as yours the rest of the time (badge boosts, Pickup, Pay Day).
- **Auto-Battle Shiny Stop** - Off / On *(Off)*. Turns Auto-Battle off as soon as a shiny wild Pokémon appears.
- **Auto-Battle Switching** - Ask / AI decides / Stay in *(AI decides)*. When a trainer is about to send in a Pokémon: with AI decides, the battle AI (PIF's or DemICE's, whichever is set) looks at the new Pokémon and decides whether yours switches out, and into whom.
- **Auto-Battle Level Up** - Show stats / Continue *(Continue)*. Whether the level-up stat windows wait for you.
- **Auto-Battle New Moves** - Ask / AI picks / Skip *(AI picks)*. When a Pokémon with four moves wants a new one: the battle AI keeps the four it rates best against the opposing team (the new move may not make the cut), or new moves are skipped. Picks are noted in KIF_log.txt with verbose logging.
- **Auto-Battle Evolutions** - Watch / Automatic *(Automatic)*. Evolutions right after a battle play by themselves (B still stops one); a move the new form wants follows Auto-Battle New Moves.
- **Damage Variance** - Off / On *(On)*. Off removes the random damage roll, so a move always does the same damage.
- **Battle AI** - PIF / DemICE *(DemICE)*. Which brain opponents use. DemICE's AI (from the community hard-mode mods) plays smarter and focuses on its best move. PIF is PIF 6.8.2's own AI.
  Both AIs know the Frostbite and Drowsy options (a frostbitten or drowsy Pokémon is not treated as frozen or asleep), and use Mean Look, Block or Spider Web when trapping pays off: with Perish Song, on a foe that loses HP every turn (Toxic, Leech Seed, Curse, Nightmare), or on a foe that can barely hurt them.

### Battle mechanics (by Bluewuppo)

- **Modern Hail** - Off / Hail / Snow *(Off)*. Hail: Ice types get a defence boost during hail. Snow: hail becomes Gen 9 Snow.
- **Frostbite** - Off / On *(Off)*. Replaces Freeze with Gen 9-style Frostbite: the Pokémon can still act, but takes damage each turn.
- **Drowsy** - Off / On *(Off)*. Replaces Sleep with Drowsy: the Pokémon isn't fully disabled.
- **Bug Type Buffs** - Off / Defensive / + Offensive *(Off)*. Defensive: Bug resists Fairy, Psychic and Dark. + Offensive: also makes Fairy weak to Bug moves.
- **Ice Type Buffs** - Off / On *(Off)*. Ice resists Water and Flying.
- **Show Lv. in BSM** - Off / On *(Off)*. In PIF's Base Stats Mode, still shows Pokémon levels in battle. The level doesn't reflect their stats there.

### Levels and experience

- **Level Cap** - Off / Easy / Normal / Hard *(Off)*. A forced level cap that follows your badges, from generous (Easy) to strict (Hard).
- **Cap Behavior** - Smart / Lock / RC *(Smart)*. What happens at the cap.
  - Smart: experience is banked and given back when the cap rises.
  - Lock: no experience past the cap.
  - RC: you get Rare Candies instead (sent to your PC when the Bag is full).
- **ExpAll Redistribution** - slider, 0-10 *(0)*. While Exp All is active, moves 10% per step of its experience toward your lower-level Pokémon.
- **No-EVs Mode** - Off / On *(Off)*. Pokémon have no EVs at all.
- **Max IVs Mode** - Off / On *(Off)*. Every Pokémon has perfect IVs.
- **EVs Train Mode** - Off / On *(Off)*. Defeated Pokémon give no EVs. Only Power items give EVs, so you can train exactly what you want.
- **EV Allocation** - Off / On *(Off)*. EVs won in battle don't go on stats by themselves: they wait on the Pokémon as EV points, and you spend them on the Summary's Skills page. Press USE there, Up/Down picks a stat, Left/Right takes or gives 4 EVs, ACTION puts every EV back into points (free to redo), USE when done. The usual limits stay (252 in one stat, 510 in all). Vitamins and feathers still raise their stat directly. Points left over after turning it Off can still be spent.
- **Trainer Exp. Boost** - slider, 0-1000% *(+50%)*. Extra experience from trainer battles.

### Catching

- **Rocket Mode** - Off / On / All Balls *(Off)*. Lets Rocket Balls (sold in the Kuray Shop) steal trainers' Pokémon. All Balls lets any ball do it. Stolen Pokémon follow the Level Cap like your own (one stolen above it is held at the cap; its extra Exp is saved for later).
- **Recover Consumables** - Off / On *(Off)*. Berries, gems and other items your Pokémon use up in battle come back afterwards.
- **Skip Caught Prompt** - Off / On *(Off)*. With a full party, a caught Pokémon goes straight to the PC with no question asked.
- **Critical Captures** - Off / On *(On)*. Critical captures can happen with any ball, and get more likely the more Pokémon you own. Off keeps only PIF's own last-ball critical capture.

### Fusion

- **Self-Fusion Stat Boost** - Off / On *(Off)*. A Pokémon fused with itself gets a stat boost scaled to its base stat total.
- **Fusion BaseStats** - Off / Head / Better *(Off)*. Choose how your fusions' base stats are made. The six sliders under it set, per stat, what percentage comes from the head (Head) or from whichever parent has the higher stat (Better).
- **NPC Fusion BaseStats** - Off / Head / Better *(Off)*. The same, for other trainers' and wild fusions. Has its own six sliders.
- **Dominant Fusion Types** - Off / On *(Off)*. Brings back the pre-v6 fusion typing, where dominant types such as Steel or Water take priority. With randomized types it uses the types a species has in your game (a Bulbasaur randomized to Ice makes Ice fusions).
- **Head Legendary Breeding** - Off / On *(Off)*. Fusions with a legendary head can breed again, as in older PIF versions.

### K-Eggs

K-Eggs are sold in the Kuray Shop (see "Others > Kuray QoL").

- **K-Eggs Fusion Pool** - Off / On *(Off)*. When an egg rolls a fusion, the second Pokémon comes from the same egg's pool. Off makes it random.
- **K-Eggs Rarity** - On / Off *(On)*. On: rarer Pokémon (lower catch rate) come out less often. Off: every Pokémon in the pool has equal odds.
- **K-Eggs Fusion Odds** - slider, 0-100% *(20%)*. The chance that a K-Egg gives a fusion.
- **K-Eggs Usage** - Pokemon / Egg *(Pokemon)*. Using a K-Egg gives a level 1 Pokémon, or an Egg that hatches into it.
- **K-Eggs Rewards** - slider, 0-10 *(3)*. How many of each new K-Egg tier you get for free when it unlocks.

### Other

- **Unfuse Traded** - Off / On *(Off)*. Allows unfusing Pokémon you got through trades.
- **Event Moves** - Off / On *(Off)*. The Egg Move Tutor (and the party's "Change moves") also offers event-exclusive moves.
- **Egg Moves** - Off / On *(Off)*. The party's "Change moves" also offers the Pokémon's egg moves (the Egg Move Tutor always does).
- **Improved Pokedex** - Off / On *(Off)*. Catching or evolving a fusion also registers its head and body Pokémon in the Pokédex.

---

## Graphics

### Global

- **Type Display** - Off / Ico / TCG / Sqr / FGM / Txt *(Off)*. Shows each Pokémon's in-battle types on its HP box.
  - Ico: icons by Lolpy1.
  - TCG: trading-card style.
  - Sqr: square icons (Triple Fusion by Lolpy1).
  - FGM: icons by FairyGodmother.
  - Txt: plain text.
- **Swap BattleGUI** - Off / Type 1 / Type 2 *(Off)*. Alternative HP/Exp bar designs by Mirasein.
- **EBDX Battles** - Off / On *(Off)*. Elite Battle DX battle visuals (Luka S.J.; the version from KIF Multiplayer by Aleks): animated backdrops, camera, move animations and its own battle boxes and menus. Also **EBDX Camera Zoom**, **EBDX Stat Stage Icons** and **EBDX Own Trainer Animation**. Type Display works on EBDX's boxes too. Turning the Graphical Changes module Off gives PIF's normal battles.
- **Fusion Preview** - Off / On *(Off)*. When fusing, shows the real sprite of fusions you haven't seen yet instead of a silhouette, with shiny colours if the result will be shiny.
- **Big Pokémon Icons** - Off / Limited / All *(Off)*. Icons use a small version of the Pokémon's battle sprite.
  - Limited: party, summary and other screens.
  - All: also the PC boxes.
  - The party screen adjusts its layout for them: the level sits by the HP, and status badges (PSN, FNT...) sit on the sprite.
- **Game's Font** - Default / FR/LG / D/P / R/B *(Default)*. Changes the game's font.

### Per-save

- **Dark Mode** - Off / On *(Off)*. Dark Pokédex, Summary and PokéNav screens, plus dark battle menus.

---

## Self-Battle & Import

All options in this menu are per-save. They control the PC's **Battle** and **Import/Export** features (see "Elsewhere in the game" at the end).

### Import & Export

- **Import Level** - Default / 1 / 5 / 50 / 100 *(Default)*. Sets the level of imported Pokémon, or keeps their original level.
- **Import De-Evolve** - Off / On *(Off)*. Imported Pokémon become their baby form.
- **Import as Egg** - Off / On *(Off)*. Imported Pokémon arrive as Eggs.
- **Import Without Deletion** - Off / On *(Off)*. Keeps the file in the import folder after importing, so it can be imported again. Off: the file is renamed to `.json.imported` (nothing is deleted; remove those yourself).
- **Delete on Export** - Off / On *(Off)*. Removes the Pokémon from your game when you export it.
- **Export Sprite on Export** - On / Off / Shiny *(On)*.
  - On: saves the Pokémon's picture (.png) next to its file.
  - Off: saves the file only.
  - Shiny: saves a shiny-coloured picture, but exports the Pokémon itself as non-shiny.
- **Import Sprite on Import** - On / Read-Only / Off *(On)*.
  - On: uses the picture that comes with an imported Pokémon.
  - Read-Only: reads the picture without copying it.
  - Off: ignores it.

### Self-Battle

- **Battle Size** - 1-6 *(6)*. How many Pokémon the opponent gets in a Self-Battle.
- **Player Size** - 1-6 *(6)*. How many Pokémon you get when your team is randomized.
- **Level** - Default / 1 / 5 / 10 / 50 / 70 / 100 *(Default)*. Sets every Pokémon in a Self-Battle to this level.
- **Randomize Team** - Off / On *(Off)*. Your team is also drawn at random from the chosen pool.
- **Randomize Share** - Off / On *(On)*. You and the opponent may draw the same Pokémon.
- **Players Folder** - Off / On *(Off)*. Your random team comes from a separate exported-Pokémon folder.
- **Team Select** - Off / On *(On)*. Lets you pick your team before the battle.
- **Limitless Select** - Off / On *(On)*. Lets you pick any number of Pokémon (6 vs 1 and so on).
- **Battle Loop** - Off / On *(Off)*. Box Self-Battles repeat with new random teams. Hold B as a battle ends to stop.
- **Stat Tracker** - Off / On *(Off)*. Shows a win/loss counter while Auto-Battle and Battle Loop are both on.

Self-Battles use copies: nothing gains Exp, no money changes hands, and your team is restored and healed afterwards.

---

## Challenges

All options in this menu are per-save.

- **Metronome Madness** - Off / Normal / Hard *(Off)*. Normal: every Pokémon can only use Metronome. Hard: only yours.
- **Letdown** - Off / 1% / 5% / 10% / 25% / 50% *(Off)*. The chance that a Pokémon uses Splash instead of its chosen move.
- **Letdown Player Only** - Off / On *(Off)*. Letdown only affects your Pokémon.
- **Berserker** - Off / Easy / Normal / Hard / Chaos *(Off)*. Opponents' stats keep rising during battle.
  - Easy: +1 every 3 turns.
  - Normal: +1 every 2 turns.
  - Hard: +1 every turn.
  - Chaos: +2 every turn, and maxed out after 3 turns.
- **Nuzlocke** - Off / On *(Off)*. Only the first wild Pokémon you meet in each place can be caught; a place is a map without its floors, so all of Mt. Moon is one place. A Pokémon that faints is dead: it can't be healed or revived, fused or unfused, and a fusion that faints takes both halves with it. Poké Balls are refused when the Pokémon can't be caught.
  - **Fainted Pokémon** - Graveyard / Released / Stay *(Graveyard)*. After the battle a dead Pokémon goes to the Graveyard box, is released, or stays where it is, fainted for good.
  - **Nuzlocke whiteout** - Keep playing / Lock save / Blackout *(Keep playing)*. When the whole party is dead: the run is over and Nuzlocke turns Off; the run is over and the save is locked for good (the load screen marks it "Nuzlocke over" with a grave, and choosing it only offers View Graveyard); or you black out as usual and a Pokémon from the PC joins you.
  - **Dupes clause** - Off / On *(On)*. A Pokémon whose evolution line you already have (both halves, for a fusion) doesn't use up the place.
  - **Shiny clause** - Off / On *(On)*. A shiny can always be caught and doesn't use up the place.
  - **Gift Pokémon** - Free / Counts *(Free)*. Free: gifts, eggs and trades never use up a place. Counts: a gift, egg or trade uses up the place you got it in, if you haven't had that place's encounter yet (you still get the Pokémon). Your starter never uses up a place.
  - **Kuray Shop** - Counts / Free *(Counts)*. The Kuray Shop's Pokémon (K-Eggs) never use up a place. Counts: you can buy one K-Egg on this run; after that the shop refuses another before taking any money (other items still sell). Free: no limit.
  - **Safari Zone** - Per area / Whole zone *(Per area)*. In the Safari Zone, meeting a Pokémon or failing to catch it doesn't use up the place; only a catch does. Per area: one catch in each Safari Zone area. Whole zone: one catch in the whole Safari Zone. After that, Safari Balls are refused (Bait, Rock and Run still work). The Dupes and Shiny clauses apply as usual.
  - **Pinkan Island** is left as in PIF: no Nuzlocke rule applies there. Catch as many as you like, gifts are free, a Pokémon that faints there isn't dead, and whiting out takes you back to the start of the island as usual. The Pokémon that go to your PC at the end of the quest (and Diancie) are ordinary Pokémon of your run: they don't use up a place and aren't dead.
  - **Nuzlocke Graveyard** - a box of the Pokémon that died on this run. It's on the pause menu (grave icon) while Nuzlocke is On with Fainted Pokémon: Graveyard, and on the PC once one has died. You can look at each one's Summary and where it died, but nothing in it can be moved, withdrawn, fused or released, and it is never one of your PC boxes.

---

## Others

### Global

- **Save Backups** - Infinite / Newest 10 / Off *(Newest 10)*. Always works, even with the PC & Saves module Off. Infinite: every save you make keeps a backup that is never deleted; saves the game makes by itself (autosaves, Transfer Box, PC, Battle Frontier) keep only their newest 10 (they were filling gigabytes on long games). Newest 10: only the newest 10 of each save file are kept (backups you named are never removed). Off: no new backups (named backups still work; old ones are kept). The Save menu also gains:
  - **Name the next backup:** gives that backup a label in the load-backup list.
  - **Open the save folder.**
- **Compressed save backups** - new backups are stored compressed, about a tenth of a save's size; "Load an older backup" reads them like before. **Compress old backups** (in the Save menu) shrinks the backups made before this; each one is checked before its old copy is replaced, and any it can't check is left as it was.
- **Debug Exclusive** - Off / On *(Off)*. On: Import/Export and other tools need Debug mode.
- **Dex Evolutions** - Credits Box / Entry Box *(Credits Box)*. On the Pokédex info page, the Run button shows the Pokémon's evolutions (levels, items, conditions). Credits Box swaps the sprite-credits box for evolution lines; Entry Box shows an evolution chart in the entry box.
- **Dex Sprite Select** - Off / On *(On)*. Each newly registered Pokémon or fusion asks which sprite to use.
- **Summary IVs/EVs** - Off / On *(On)*. The Summary's Skills page shows IVs, EVs and base stats next to each stat.
- **Speed-up Limit (Toggle)** - slider, 1-10 *(3)*. The top speed when speed-up is in Toggle mode. PIF stops at 3x.
- **Quicksave** - Off / On *(On)*. Press S (or the key you set for it in the controls) on the map to save instantly.

### Per-save

- **Overworld Poison** - Off / On / On+Healing *(Off)*. On: Pokémon whose ability protects them from poison don't take poison damage while walking. On+Healing: abilities like Poison Heal restore HP instead.
- **Streamer's Dream** - Off / On *(Off)*. Makes several items free in the Kuray Shop, and makes Buy Box and the Shiny Gamble free:
  - Rare Candy, Master Ball, Max Repel, Rage Candy Bar.
  - Transgender and Mist Stones, Devolution Spray.
  - Every K-Egg.
- **PokeRadar+** - Off / On *(Off)*. Poké Radar chains never break at random.
- **Radar Chain Count** - Off / On *(On)*. With PokeRadar+, shows your chain count and the current shiny chance when the grass shakes.
- **Endless chains** *(always, with the Shinies module)*. PIF stops counting a Poké Radar chain at 40 and its shiny odds stop improving at 20. KIF keeps counting with no cap, and past 20 the shiny grass keeps getting likelier per patch of shaking grass: chain 20: 1 in 200 (PIF's best), 40: 1 in 112, 60: 1 in 63, 80: 1 in 36, **100: 1 in 20**, 150: 1 in 14, **200: 1 in 10**, 300: 1 in 5, and from 474 on every patch is shiny. How easily a chain breaks stays as in PIF. A message announces chains of 20, 40, 60, 80, 100, 150 and 200 with the shiny chance, and every change of the chance is written to `Logs/KIF_log.txt` with verbose logging.
- **Multi-Battle Radar** - Off / Same Species / Mixed *(Off, per save)*. PIF makes every Poké Radar grass battle 1v1. With this on and Battle Format 2v2 / 3v3 for wild battles, the radar Pokémon brings company. **Same Species:** the others are the chained species too. **Mixed:** the others are normal Pokémon from the area. Either way a won battle adds 1 to the chain, however many foes it had. Shininess is rolled for each Pokémon on its own: the shiny patch only decides the radar Pokémon, which can be in any spot; every other one rolls with the chain's chance, as if it had its own shaking patch.
- **Enable EvoLock** - Off / On *(Off)*. Lets you lock a Pokémon's evolution from the PC ("Kuray Actions > Lock Evolution"). A locked Pokémon won't evolve by any means until you unlock it. A padlock shows on its party panel and Summary.
- **Tutor.net** - Off / On *(On)*. Adds "Tutor.net" to the pause menu (by DemICE): every TM you own and every move tutor you've used, in one list. TMs are free to use. A tutor's move costs once, then stays unlocked forever.
- **Kuray QoL** - Off / On *(On)*. Adds three entries to the pause menu (they can't be used in the Elite Four, Mt. Silver and a few story areas):
  - **PC:** open the PC anywhere.
  - **Heal Pokémon.**
  - **Kuray Shop:** TMs, PP and Power items, Rare Candy, Master Ball, the Transgender and Mist Stones, Devolution Spray, Rocket Balls, K-Eggs and more.
- **Hatch to PC Prompt** - Off / On *(On)*. When an Egg hatches, asks whether to send the baby to the PC.
- **Kuray's Shenanigans** - On / Off *(On)*. Easter eggs around the secret "pizza" gender (a 1 in 256 roll). A pizza Pokémon shows a pizza icon in battle, its Attract works on anyone, and the Transgender Stone can make or remove pizza.

---

## Presets and System

- **Settings Presets** - 12 named slots. *Save* puts this save file's per-save settings (every module) into a slot, *Load* puts a slot's settings into the save you're playing, *Rename* names it. Set up a run once, then load it on every new game. Global settings are shared by all saves already; Randomizer settings have their own presets. Needs a loaded save.
- **Increment Slider by** - 1 / 10 / 100 / 1000 / 10000 *(1)*. How far big sliders (like Wild Shiny Odds) move per press.
- **DEBUG** - Off / On *(Off)*. Turns on PIF's debug mode, with the Debug menu and debug options in the PC and party.

---

## Cody's additions

New features made for KIF 1.0 that were never part of the original KIF. They sit in the same modules as KIF's features (switched in Options > Modules; their settings are in the Options sections).

### Battles

- **Move Effectiveness** - Off / On *(On, all saves)*. The Fight menu shows how well each damaging move works against the foe: a green ▲ (super effective), orange ▼ (resisted) or grey ✕ (no effect) on each move button, and "Super eff." / "Resisted" / "No effect" under the PP of the highlighted move. With several foes, the info box lists each one with its multiplier (e.g. "Gyarados x4", "Onix x0") and names too long for the box scroll like a car radio display. The button marker shows the best result. Uses the battle's real type rules (including KIF's type buffs). Abilities stay hidden until the battle reveals them: once a foe's Levitate, Flash Fire, Volt Absorb, Water Absorb, Wonder Guard (and similar) has popped up, its immunity shows as "No effect" for the rest of that battle (not against Mold Breaker). Air Balloon and Magnet Rise also show Ground moves as "No effect".
- **Gym Leader teams** - Normal / +1 / +2 / Full *(Normal, per save)*. Gym Leaders bring extra Pokémon to every battle with them (gym, rematch or story battle). The extras have the gym's type (in Remix and Expert, the type the leader's own team uses most; randomized gym types count), are fusions about as often as the rest of the team, are about as strong as the team, are evolved as far as their level allows and join at the team's average level. Never legendaries, repeats or banned Pokémon, and the same every time for a save. On randomized saves with random trainers, the Randomizer's *Leader team size* decides instead (the leaders' lines follow it even with Battles & Challenges Off).
- **Trainers keep their teams** *(always, Battles module)*. A trainer's Pokémon are rolled on the first fight (which ability a fusion gets, shininess) and kept for every rematch, so a Ralts fusion with Synchronize still has it later. Each trainer's rolls are saved with the save file.
- **Your Pokémon in gyms** - Normal / +1 / +2 / Full *(Normal, per save)*. Raises how many Pokémon you may pick before a Kanto Gym Leader battle (Full = your whole party). The picker still shows.
- With either setting on, the Kanto Gym Leaders say the real numbers ("I will be using three Pokémon, and you may use two."). At six they say "my full team" / "your whole team" instead of a number.

### Breeding & Fusion

- **Legendary Breeding** - Off / On *(Off, per save)*. Legendary Pokémon (and fusions with a legendary head or body) can breed with any Pokémon that can breed - no egg group or gender needed. The Egg is one of four results, 25% each: either parent, or either fusion of the two (Mewtwo + Vulpix > Mewtwo, Vulpix, Mewpix or Vultwo). With Ditto, the Egg is the other parent. Baby Pokémon still can't breed.

### Randomizer

Only on saves started as randomized saves: **Options > Game > Randomizer** (Randomizer module On). The same screen also replaces PIF's randomizer menu when you make a randomized save, and the Update Man's *Advanced options > Randomizer options* opens it too. In Oak's Lab, *Re-randomize Pokémon?* opens it as well, so you can pick a new seed before choosing your starter (the same seed always gives the same starters).

- **Seed** - an 8-character code (like `K7Q2-9XMA`). The same seed with the same settings gives the same randomized game (on the same KIF version and sprite pack). New random seed, type one in, or copy it.
- **Presets & sharing** - *Copy settings code* puts the seed and every setting on your clipboard as one line (paste it into Discord); *Paste settings code* loads someone else's. *Built-in presets* are ready-made settings to start from: First Randomizer, Gym Challenge, Item Hunt, Fusion Frenzy, Dungeon Crawl and Total Chaos (each says what it does before loading; every setting it doesn't name goes back to its default, and your seed is kept). *Save as preset* / *Load preset* use your own files in the `Randomizer/Presets` folder (saving over an existing name asks first; presets from earlier versions still load).
- **Spoiler log** - Off / On *(On)*. Writes `Randomizer Log - <seed>.txt` in the `Randomizer/Logs` folder every time something is shuffled: every Pokémon swap, route, trainer team, gym type, item and TM. *View spoiler log* shows it in-game (asks first; each part is built when opened); Up/Down scroll, Left/Right turn a page, Z jumps to a dex number or text.
- **Pokémon** - each part has its own switch:
  - *Wild encounters*: Off / Swap (each species becomes one other species everywhere) / Route (every route rolls its own) / Dynamic (every encounter rolls its own Pokémon on the spot, within the Strength range) / Dynamic Route (like Route, but a route rolls new Pokémon every time you enter it; the roll stays while you're on that map, saving and loading included, and follows the seed).
  - *PokéRadar*: the radar's route list matches what really appears (PIF used the Swap table even when wild Pokémon weren't swapped); radar-only rares are randomized too (Swap: what it became; Route: one per route; Dynamic Route: one per visit; Dynamic: any). Oak's aide on Route 24 finishes her field research in Dynamic (nothing repeats) and in Dynamic Route (once the visit is catalogued), with the quest points and reward.
  - *Starters* (Off / 1st stage / Any), *Static encounters*, *Gift Pokémon*.
  - *Trades*: Off / Swap (what the Pokémon became; fusion trades too) / Random (each trade rolls its own within the Strength range). The spoiler log lists every trade.
  - *NPC requests*: Original / Swapped *(default)* / Any. When a trade or quest asks for a specific Pokémon: Swapped = what it became (Swap mode; other modes accept any Pokémon), Any = any Pokémon. The NPC's lines name the new Pokémon; with Any they add "(Any Pokémon will do.)". PokéRadar rares are always asked for as what they became.
  - *Strength range* 0-999 (how close in base stat total a replacement must be; 999 = anything), *Legendaries*, *Custom sprites only*, *Fuse everything*.
- **Trainers**
  - **Trainers** - Off / Random / Follow wild. Follow wild gives trainers the wild swap table (a trainer's Pidgey becomes whatever wild Pidgey became).
  - **Strength range**, **Custom sprites only** - as in PIF.
  - **Class themes** - Off / On *(On)*. Every Pokémon of a themed class has its type: Bug Catchers use Bug types, Swimmers Water types, Hikers Rock/Ground, and so on; *Class theme list* shows every class. Follows randomized types. Gym leaders use the Gyms page.
  - **Shuffle themes** - Off / On. Each class gets a random type instead (the same for the same seed); Type Experts keep theirs.
  - **Extra class themes** - Off / On *(On)*. Also themes the less obvious classes: Scientists, Bikers, Burglars, Jugglers, Robots, Roughnecks, Cue Balls, Aroma Ladies, Painters and Tubers.
  - **Rival keeps his team** - Off / On. Each Pokémon line in the rival's team gets one replacement line for every battle, at the same stage.
  - **Team size** - Same / +1 / +2 / Full. Extra Pokémon join at the team's average level. Not Gym Leaders (see Gyms).
  - **Fuse everything** - Off / On. Every trainer Pokémon is a fusion.
  - **Unfused Pokémon** - Normal / 25% / 50% / 75% / All. How many trainer Pokémon are plain, unfused Pokémon (Normal = the game's own odds, nearly all fusions). Fuse everything wins if both are on.
- **Gyms** - PIF's options (custom sprites only, gym types, rerandomize each battle), plus **Leader team size** - Same / +1 / +2 / Full: Gym Leaders bring extra Pokémon in every battle with them.
- **Items**
  - **Item mode** - Mapped / Dynamic. Mapped: each item always becomes the same other item. Dynamic: every item ball, gift and shop rolls its own item; the same spot always gives the same item for the same seed. TMs follow the mode too.
  - **Found items**, **Found TMs**, **Given items**, **Given TMs**, **Shop items** - each only changes its own part.
  - **Trainer held items** - Off / Random / Fixed. Random gives a new item every battle; Fixed gives each trainer's Pokémon the same item every time.
  - **Keep categories** - Off / On. Balls stay balls, medicine stays medicine, berries, held items, evolution items, gems, mail, battle items and TMs stay in their group.
  - **Keep shop basics** - Off / On *(On)*. Poké Balls and Splicers stay buyable.
  - **Banned items** - never a random result. Starts with the items that have no use in PIF (shards, apricorns, contest scarves, mail, flavour-only berries, ...).
- **Pokémon data** - changes the Pokémon themselves (fusions are built from their two parts, so they follow):
  - *Types*: Same / Random (each evolution family gets new types) / Dual (everyone gets two types); *Original type*: Allowed / Never.
  - *Moves follow type*: moves of the old type become moves of the new type at the same level with similar power (other moves stay). *TMs follow type* does the same for TM and tutor compatibility.
  - *Abilities*: Same / Random / Flavour (abilities themed on the Pokémon's types) / Bound (only abilities Pokémon of its types have in the base game). *No self-harm* never gives Truant, Slow Start, Defeatist, Klutz, Stall, or weather that hurts the Pokémon's own type.
  - *Base stats*: Same / Shuffle (same numbers, new order) / Total (random spread, same total) / Chaos (every stat 1-255). *Chaos safety*: Off / Total (evolving never lowers the total) / Each stat (evolving never lowers any stat).
- **Evolutions** - Same / Random: a Pokémon that evolves turns into a higher stage or a Pokémon that doesn't evolve, at the same level or with the same item. *Type-themed*: the evolution shares a type.
- **Exclusions** - lists of Pokémon, moves and abilities the randomizer never picks (A: ban/unban, L/R: page, Z: clear all). Bans only affect what the randomizer picks; parts that aren't randomized keep their normal Pokémon.
- **Entrances** *(beta)* - the doors of Kanto lead somewhere else. Every door between an outdoor map and the place behind it (gyms, Centers, marts, houses, caves, towers, gates, tunnels, the Mansion, the League building, Victory Road) can be shuffled; the game only keeps layouts it has checked can be finished: from Pallet Town, with the badges, HMs, key items and story events each reachable place gives, the Hall of Fame is reachable. Pallet Town's doors, the S.S. Anne, the Safari Zone areas, elevators, stairs inside buildings and cutscene teleports stay as they are.
  - **Entrances** - Off / Simple / Full. Simple keeps the two ends of a gate or two-sided cave on the same gate or cave; Full shuffles every door on its own.
  - **Which doors** - Dungeons (caves, towers, forests, gates, tunnels) / Buildings (Centers, gyms, marts, houses) / Everything / Custom.
  - **Door kinds** - opens a page with one On/Off per kind of door: Pokémon Centers, Gyms, Marts and shops, Houses, Other buildings (hotels, museums, labs, harbors...), Gates, Caves and dungeons. Opening it sets Which doors to Custom, which shuffles only the kinds that are On.
  - **And Johto?** - Off / On. On: Johto's doors (103: Goldenrod, Ecruteak, Violet, Azalea, Blackthorn, the Ruins of Alph, the route gates...) join the shuffle, mixed with Kanto's - a Kanto door can lead into Johto and back. Layouts stay checked the same way. Johto doors behind story events the logic can't see yet (Olivine, Route 38-39) stay as they are.
  - **And Sevii?** - Off / On. On: the Sevii Islands' doors (33: the Pokémon Centers, harbours, houses, Ember Spa, the Battle Tower and Factory, Ruby Chamber, the Old Shipwreck, Berry Forest, the Rocket Warehouse...) join the shuffle too, mixed with Kanto's (and Johto's when that's on). Layouts stay checked the same way: the Seagallop Pass, Surf, Dive, Brine Road's currents and the Old Shipwreck's Wailmer Pail jump are all taken into account.
  - **Coupled** - Off / On *(On)*. On: going back the way you came returns you to where you were. Off: the way back may lead somewhere else again.
  - **Door hints** - Off / On. The first time you use a shuffled door, a line names the door you came out of and the place it belongs to (after that it's in the Entrance log).
  - **Door signs** - Off / Corner / Above door. Facing a shuffled door you've already used shows where it leads ("To: Cerulean Gym"), in the top-left corner or just above the door. It goes away when you turn or move.
  - **Start** - Pallet / Random town / Random map. Oak's parcel errand is skipped: once you have your starter, the next door you take hands you the Pokédex and five Poké Balls (as Oak would) and leads into a random Pokémon Center (in a town, or anywhere in Kanto), which becomes home. The layout is made at that moment and checked from there. New games only.
  - **Level scaling** - Off / Trainers / Trainers + wild. Trainers are as strong as the ones you would normally meet at that point of the game: the game measures how far into the reachable world each map sits (in vanilla and in your layout) and scales every trainer on it along the vanilla level curve - a gym you reach first has low levels, an Elite Four reached early is weaker (moves learnt by level follow, hand-picked movesets stay). Near your start nothing outlevels a fresh starter: on the places you can reach with nothing, no Pokémon is above level 6 at the start and one door out, plus 2 for every door after that; trainers one door out are also never above your strongest Pokémon. Progress is measured from where your journey started (Pallet Town or the random start Center). *Trainers + wild* scales wild Pokémon the same way: grass, water, fishing and overworld legendaries.
  - **Return to Pokémon Center** - in the pause menu while Entrances are shuffled: a free trip back to the last Pokémon Center you used (asks first; not offered inside that Center, in the League, the Safari Zone or the Bug-Catching Contest). Shuffled doors can drop you somewhere the normal game never would - below a one-way ledge, in a gym puzzle before you have Strength - so a bad spot is never the end of a run. If that Center is itself a dead end for now (a shuffle can put one in a pocket you can't leave yet), it says so and takes you home instead - Pallet Town, or a random start's first Center - which is always a way on. Each use is noted in `KIF_entrance_returns.txt` in the save folder (where you were, your last doors) so such spots can be found and fixed.
  - **Entrance log** - the Town Map with a line for every shuffled door you have used: from the door's own town or route to where the place behind it really belongs (purple = caves, gates and towers, yellow = buildings). Newest first: Up/Down walk the doors one by one (the map follows, the door's name and where it led are shown below), A opens the same list as text, Left/Right look at the door's end, then where it led, then the whole line; B goes back. The top shows how many you've found and how many are left. With Entrances on, the Town Map opens the Entrance log (once you've used a door), and the Fly / Teleport map shows the same lines - the ones at the town under the cursor light up red; flying works as usual. The spoiler log's *Entrances* part lists the whole layout by sphere: sphere 0 is what you can reach with nothing, sphere 1 needs a badge or key item found in sphere 0, and so on.
  - A new game shuffles when the intro ends; on a randomized save it happens at Randomize now. Same seed and settings = same layout: Randomize now keeps your doors (and what you've found) unless the seed or a door setting changed. Every layout reaches everything the normal game reaches, and both ends of every shuffled door. In *Simple*, a gate's or cave's doors always move together.
  - **Randomize now mid-run** is checked from where you stand with what your save really has: the new doors must be beatable and reach everything from there. Everything you can walk to right away is capped at your strongest Pokémon's level (+2 per door further), and trainers one door away are never above your strongest Pokémon. If no layout works from your spot, your doors stay as they are and the game says so; turning Entrances Off is refused where the normal doors couldn't finish from there. If no finishable layout is found (rare), doors stay normal and the game says so. The insides of dungeons and Fly spots are later batches.
- **Archipelago** *(beta)* - play KIF in an Archipelago multiworld. Kanto's item balls, gifts and the 8 gym badges are checks (trainers too, with Trainersanity), and the goal is the Hall of Fame. Put `kif.apworld` in Archipelago's `custom_worlds` folder, connect with the **KIF Client** (it asks once for the KIF game folder), then open the pause menu in a save and choose **Archipelago** to link it (the entry shows once the client has connected). Other saves play as normal. Items you receive arrive on the map when nothing else is going on; checks found while the client is closed are sent when it connects. A linked save uses the slot's randomizer settings, seed and difficulty; Entrances are off and found items aren't randomized, because Archipelago places them. yaml options: League badges (0-8), shuffled badges, Trainersanity (0 to every Kanto trainer), field moves without badges, Exp modifier, minimum or guaranteed catch, starting money, a free Fly town, DeathLink, game difficulty, and KIF's randomizer settings. **Dexsanity** (yaml `dexsanity`): registering a Pokémon as caught in the Pokédex sends a check (100 random species by default, up to all you can get before the Hall of Fame; catching, hatching, evolving, trades and gifts all count, and a fusion counts for both of its Pokémon), plus a check every 10 Pokémon registered. It needs the normal wild Pokémon: linking is refused while wild Pokémon are randomized, or when the save plays Classic and the game was made for Remix (or the other way round). Pokémon the save already has are sent when you link.
- **Pinkan Island** is left as in PIF: its wild Pokémon, bosses, gift Pokémon, trainers, items (HMs and Pinkan Berries included) and levels are never randomized, whatever the settings, so the Team Rocket / police quest can always be finished. Archipelago never makes anything there a check.
- **Randomize now** - applies the settings mid-game (asks first; your party and boxes stay).
- **Settings wait for Randomize now** - changing a setting on a randomized save doesn't change your game until you randomize. Changed settings are marked `*`, and the Randomize now button shows how many. Leaving the screen with changes asks: *Randomize now*, *Keep for later* (they stay marked next time, the game keeps the old ones), or *Undo changes*. The new-game setup works as before. (The Spoiler log switch is the one setting that applies at once.)

### Interface
- **Frame rate** - 40 / 60 / 80 / 100 / 120 / Match monitor *(40, global, experimental)*. The game still runs at PIF's 40 steps a second, so all timing (walking, events, battles, menus, key repeat, play time) is exactly as in PIF. Above 40, extra frames are drawn in between, showing the overworld part of the way from one step to the next (camera, characters, shadows, weather), so walking and scrolling are smoother. Battles and menus look the same as at 40. Match monitor uses the screen's refresh rate (up to 120, the engine's limit). If the computer can't keep up, the rate steps down by itself and tries again later.
- **Skip intro** - Off / On *(On, global)*. On: the game starts at the title screen without the opening movie (Gengar and Nidorino). The title screen and its music stay.
- **Title screen** - Living / Simple / Classic *(Living; Simple on phones; global)*. Living: Pokémon wander through a slowly scrolling world (a grassy field, a beach, a forest) behind the title menu: Play (the save selection, unchanged), Options, Mods, Links, Quit. Diglett dig, birds fly over, and now and then two Pokémon meet and fuse: a flash, then one walks on in the other's colour, with the fusion's battle sprite above it when that sprite is on your computer. Simple: one still picture behind the same menu. Classic: PIF's own title screen. Part of Graphical Changes: with that module Off, the title is PIF's.
- **Mouse** - Off / On *(Off, global; not on phones)*. Options > System > Controls. In menus, pointing at an entry selects it, left click confirms, right click goes back, and the wheel scrolls. A left click also moves a message on. This works in choice boxes, Yes/No, the pause menu, the Bag, the party, the Summary page tabs, PC boxes, the battle menus, the load screen, the title menu, Options and EV allocation (click the left half of a stat for -, the right half for +). On the map, left click a tile and you walk there, going round walls, people and water (and over ledges only downward), and taking stairs and bridges the way you would with the keys. Click a person or object and you walk up to it and talk to it (next to water or a tree, a click on it Surfs or Cuts, like pressing the confirm key). Hold the button to keep walking toward the pointer. Any key or a new click stops the walk. Nothing happens while an event or message is running. The pointer hides after a few seconds without moving. Off while the Mouse UI mod is installed and on, and with Classic KIF.
- **Click to move** - Off / On *(On, global; shown while Mouse is On)*. Options > System > Controls. Off: clicking the map does nothing, and the mouse works in menus only.
- **Touch controls** - Off / On *(Off, global; phones only)*. Options > System > Controls. Taps work like Mouse clicks: tap an entry to choose it, tap the map to walk there, tap a person to walk up and talk. JoiPlay's on-screen buttons keep working alongside. **Tap to move** - Off / On *(On; shown while Touch controls is On)*: Off keeps taps in menus only.
- **Animated sprites** *(always on)*. A sprite drawn as an animation strip (its frames side by side) moves in battle, at 10 frames a second (the first 48 frames). Everywhere else it shows its first frame instead of the whole strip. Shinies coloured by PIF's Improved Shinies palettes always show their first frame.
- **Soft reset (F12)** *(always on)*. Starts the game again as if you closed and reopened it. Unsaved progress is lost, as with any soft reset.
- **Map load cache** *(always on)*. Walking back and forth between connected maps no longer reloads the next map's tileset each time it comes into view (PIF did, ~60 ms each time, a visible hitch). The last few tilesets and animated tiles no longer on screen are kept.

- **Fusion Screen** - Off / On *(On, all saves)*. The DNA Splicers' preview shows, for both fusion orders, the fusion's name, types and the stats it will really have once fused (its fused level, the body's EVs and nature, the averaged IVs - or the higher ones with Super Splicers - and every setting that changes stats or types, such as No-EVs / Max IVs modes, custom fusion base stats, the self-fusion boost and Dominant Fusion Types). The higher stat of each left/right pair is green when the two base stats differ (with equal base stats the numbers only differ by the body's nature and EVs, which you pick after fusing); the bars and "Base total" show the base stats. Press **A** on a fusion for **Change Body / Change Head / Confirm**. Change Body or Change Head lists that part's current form and every later evolution (branches included), tagged Stage 1, Stage 2 or Final; the preview follows the cursor, and the other side mirrors the change so both orders stay comparable. Confirm always fuses the Pokémon you have now (it reads "Fuse <name>" while you're previewing an evolution). With Fusion Preview Off, a fusion you haven't seen is a silhouette: green when it has a custom sprite (from the sprite sheets or a sprite you imported), grey when it's an autogen.
- **Battle Info** - Off / On / No button *(On, global; always available, in no module)*. While choosing Fight / Bag / Pokémon / Run, choose **INFO** (a small tab above the left end of the command box; a 5th button with EBDX) or press **Z / Shift**. The top row lists every Pokémon on the field, then **Field**, **Speed** and **Log** (Left / Right). Each Pokémon has three pages (Up / Down): **Stats** (stat changes with their multiplier and your Pokémon's resulting stats, current types, HP and status, ability, held item, effects with turns left such as Taunt, Encore, Leech Seed, Substitute or the Perish count), **Abilities** (its ability and any extra abilities a mod gives it, such as KIF: Elite Redux's innates, each with a description; *Worked this battle* marks one that has triggered) and **Moves** (type, category, power, accuracy and PP; for a foe's moves, how often it has used them). On **Abilities** and **Moves**, press Use (C / Enter) to put a cursor on the list, Up / Down to choose, and Use again to read the full description (for a move also its type, category, power, accuracy and PP); Up / Down scrolls a long one, Back closes it. A row shown as ??? can't be opened. **Field** shows weather, terrain, Trick Room and the other rooms, Gravity, screens, Tailwind and hazards on each side, Future Sight and Wish; **Speed** lists who moves first this turn (Trick Room, Tailwind, paralysis and items counted), with each Pokémon's Speed this turn, foes' included; **Log** lists every message and ability pop-up of the battle so far by turn, newest at the bottom (Up / Down scrolls back), with a green dot for lines about your Pokémon and a red one for lines about the foe's, so pop-ups that went by too fast can be read. A foe's held item shows as ??? until the battle reveals it. Works in PIF's battle screen and with EBDX. *No button* hides the INFO tab/button and keeps only Z / Shift.
- **Foe Info** - All / As seen *(All, global)*. **All**: Battle Info lists a foe's abilities (a mod's too, such as KIF: Elite Redux's innates) and all its moves from the start of the battle, as in Elite Redux. **As seen**: they show as ??? until the battle shows them (an ability's pop-up or a message naming it, a move once it is used).

## System (Cody)

- **Sprite import** - an `Import Sprites` folder next to InfiniteFusion.exe. Drop sprites in any shape - loose .png files, a sprite pack folder, folders inside folders, a .zip (or .rar / .7z) - and the next start-up *moves* every sprite to where the game reads it (base sprites, fusions into `indexed/<head>/`, triple fusions, sprite sheets). A progress screen shows while this runs. An archive is deleted once its sprites are in (Options > System > Imported Archives: Keep moves it to an `Imported archives` folder instead), and what else it held (icons, outfits, credits) is not kept. Sprites you already have are dropped quietly; ones that differ are held and you're asked once: "Keep the ones I have" or "Use the new ones". A pack's egg sprites are older than the game's, so those are dropped without asking (eggs the game doesn't have are still installed). PIF's own "Sprites to import" folder works the same way. Single sprite files are now read *before* sprite sheets (PIF 6.8.2 only read base sprites from downloaded sheets and remembered a fusion's first pick), so old KIF-style packs work again.
- **Sprite File Cache** (Options > System) - Permanent / Per Session / Off *(Permanent)*. A sprite that comes from a single sprite file is decoded once and remembered, like the Shiny Cache: Permanent also keeps a small copy of the decoded pixels in `Cache/KIFSprites`, so even the first look at a Pokémon in a new session is instant; Per Session forgets at close; Off decodes the file every time it is shown (some files take 40 ms and more, which showed as a short pause when the PC cursor or the party reached those Pokémon).
- **Updates** (Options > System) - Stable / Beta / Off *(the channel of the version you installed)*. At start-up KIF checks for a newer version and asks: **Update now / What's new / Later / Skip this version**. Update now downloads only the files that changed (not the whole game), with a progress bar (B cancels; what was downloaded is kept for next time). The game then closes, a small "KIF update" window moves the new files in, and the game starts again and says it was updated. On a phone (JoiPlay, Kirin) the game moves the new files in itself and then asks you to close the game and open it again; if it was closed while moving them in, the next start finishes the update. Saves, Mods, Logs, Import Sprites and sprite packs you installed are never touched. Old sound files that a shipped file of the same name in another format replaced (e.g. a .wav beside the new .ogg, left by installing over an older version) are removed once per version. **Check for Updates** looks any time. Beta gets new versions before Stable does. If the game folder can't be written to (e.g. Program Files), it tells you where to download the new version instead.
- **No start-up announcement** - PIF's load-screen message ("Pokémon Infinite Fusion 2 is now available!...", sent by PIF's server) and its "Version X is now available, use the installer" prompt are not shown; KIF's own updater tells you about KIF's versions instead.
- **KIF_log.txt** - one short log per session in the save folder (the last one becomes `KIF_log_previous.txt` at start, so a crash's log is kept). Versions and folders, what the game has to show sprites with (sprite files, sheets, Download data), sprites that came out as "?", everything KIF reports (Entrances, sprite import, failures), crashes with the last maps visited. It also notes the engine, screen and controller, mod versions, each save loaded (map, play time, Randomizer code, settings changed from default) and saved, how long the start-up downloads took, and the battle at a crash. Repeats are counted instead of written, 200 KB at most; "Session ended" means the game closed normally. Send it with a bug report.
  - **Verbose logging** (for testing): put an empty file named `verbose.txt` in the `Logs` folder (or start in debug mode). The log then also notes every map change, start-up timings, Auto-Battle choices, Poké Radar chances and mod details, up to 2 MB. Delete the file to go back to the short log.
- **Phones (JoiPlay)** - when the game folder can be written, updates work as on a computer (see **Updates**). When it is read-only:
  - KIF never downloads or installs an update there. At start-up (when Updates isn't Off) and from Check for Updates it says "KIF x.y.z is out", offers What's new, and copies the link to the release page (https://github.com/cody-png/codybeta/releases/latest). At start-up it says this once per new version. Install the full new version to update.
  - Mods aren't installed or updated from the catalog on a phone. The game lists the new versions (once per new version at start-up) and you replace the mod's folder by hand.
  - What KIF writes into the game folder on a computer goes to the save folder instead: the shiny and sprite caches (`Cache/`), the Randomizer's `Logs` and `Presets`, and update downloads. Logs already did this.
  - Put sprites to import in `Import Sprites` inside the save folder, and mods in `Mods` inside the save folder (KIF makes both folders). Mods in the game's own `Mods` folder still load. Only single sprite files can be imported this way (base sprites and fusions); sprite sheets, triple fusions and eggs need a writable game folder.
  - Frame rate offers 40 and 60 only. Key hints name the gamepad buttons (A, B, C, X, Y, Z, L, R). A change of speed, Auto-Battler or Loop Self-Battle shows for two seconds at the top of the screen, since there's no window title.
- **Save folder** - KIF keeps its saves in `%APPDATA%\KIF` (`KIF Savefiles` shortcut), apart from old KIF's `%APPDATA%\kurayinfinitefusion` (`Old Savefile location` shortcut). On the very first launch, if the old folder has saves and the new one has none, the game offers once to copy them over (copied, so old KIF keeps its own; save backups stay in the old folder).

---

## Elsewhere in the game

These features have no option of their own.

- **PC > a Pokémon > Kuray Actions** (also in the party menu):
  - Export, Export All Pokémon.
  - Lock / Unlock Evolution.
  - **Shiny Gamble:** P1000 for a chance to turn the Pokémon shiny. Gambling an existing shiny re-rolls its colours.
  - **Sell Shininess:** +P1000; the Pokémon becomes normal again.
- **PC box menu** (select the box name):
  - Lock Sorting / Lock Exporting.
  - **Buy Box.**
  - **Sort / Sort (all Boxes):** 26 criteria, normal or reverse order.
  - 160 extra wallpapers.
  - **Battle:** a Self-Battle against random teams from the box, the whole PC or an exported-Pokémon folder.
  - Export this Box, Export All, Import, Import Randomly.
- **Multi-select in the PC:** Battle Selected, Export, Release.
- **Import / Export:** Pokémon are saved as files in the **ExportedPokemons** folder next to the game, so you can share them. Exports from old KIF, including the KIF Pokémon Bank, can be imported.
- **Items:**
  - **Transgender Stone:** choose a Pokémon's gender.
  - **Mist Stone:** evolves into the evolution you choose, including the head or body of a fusion.
  - **Devolution Spray:** devolves a Pokémon, choosing head or body for a fusion.
  - **Rocket Balls.**
  - **Perfect Ball:** always maxes two different IVs.
- **K-Eggs** (Kuray Shop): Random, Sparkling (40x shiny odds), one per type, Fusion, Base (never a fusion), Legendary, and tier eggs.
  - Every egg gives 10x your Wild Shiny Odds.
  - The tier eggs are Starter, 1-8 Badges and Elite 4, each with a base-stat range for that point in the game.
  - New tiers unlock as you earn badges and beat the Elite Four. You're told the next time you open the Kuray Shop.
- **DemICE's Endgame Challenge:** after the Elite Four, talk to Dem in the League lobby to turn on the challenge.
  - The Elite Four, Blue, the Fighting Arena leaders, Gold and Cynthia use level 100 fusion teams scaled to your strongest Pokémon.
  - Challenge rules: singles only, no items in trainer battles, Set style, and foes have doubled PP.
  - Beating Blue earns emblems; the Silver Emblem opens the Mt. Silver vortex to Cynthia.
- **Mystery Gift:** KIF's gift "Fire Misbok!" appears in "Search for public gifts". It's a shiny Ghost/Fire Misdreavus/Arbok fusion: it shows that a Pokémon's types aren't always locked to its species.
- **Speed keys:** with speed-up in Toggle mode, L goes to the next speed and R goes back to 1x.
- **Skip the intro:** put an empty file named `NoIntro.krs` in your save folder to go straight to the load screen.
- **Load screen:** links to the KIF Discord and documentation.
- **Mods folder:** the `Mods` folder next to InfiniteFusion.exe takes a mod as a `.rb` file, a folder (its `.rb` files load in name order, or in the order its `mod.json` lists; mods it depends on load first) or a `.zip` (unpacked into a folder of the same name the next time the game starts; the zip is moved to `Mods/Imported`). Folders with a `mod.json` are left to Mod Manager when it's installed. A folder with only pictures and sounds (`Graphics/`, `Audio/`) is a mod too. A mod's pictures and sounds stay in its own folder and the game uses them from there (a mod that loads later wins when two have the same file), so deleting a mod's folder removes it completely. The **Mods** section of Options starts with a row that switches between five lists (Left / Right):
  - **Installed** - every mod with **On / Off** (applies at the next start, shown as *ON/OFF NEXT START*; Mod Manager's mods use Mod Manager's own switch), a settings page for each mod that added settings, and *Settings by category*. A broken mod is skipped instead of crashing the game and shows *ERROR*. **USE** on a mod > **Uninstall** removes it (asks first); its settings are set aside, outside your save, and come back if you install it again.
  - **Browse** - the mod catalogs (KIF-Mods is the one Mod Manager 2.0 lists). Enter installs a mod, and any mods it needs (it asks first and shows the download size), into `Mods/<mod>`. It starts working the next time the game starts.
  - **Modpacks** - sets of mods the catalogs offer. Enter installs the ones you don't have (and updates any older than the pack wants).
  - **Share Code** - *Copy my share code* copies a code (KIF-...) for the mods you have On; *Use a share code* installs the mods from a code someone copied for you (or type it in). Codes from Mod Manager 2.0 work too.
  - **Updates** - installed catalog mods with a newer version; **Update all** updates them in one go. Only changed files are downloaded, and a mod's own settings are kept. At start-up, right after KIF's own update check, KIF asks "Updates for N mods. Open Mods > Updates?" (not when Updates is Off or there's no internet).
  - **Publish a mod** (PC only) - for modders: pick a folder in `Mods` (or `ModDev` next to the game), fill in name, version (*Raise version* for an update), author, description and tags (saved to its mod.json), and the community catalog's own checks run in game; nothing is sent until they pass. Then `Tools/publish_mod` opens in its own window and sends it with the GitHub CLI under your own GitHub account (straight in for catalog contributors' own mods, otherwise as a pull request that is reviewed). KIF never sees or keeps your GitHub sign-in.
  With Mod Manager 2.0 installed, Browse, Modpacks, Share Code and Updates are left to its own browser.
- **Mods that change KIF:** a mod can replace one KIF feature with its own version, or set some settings and modules while it's On. Those rows show LOCKED ("Set by <mod>"). Switch the mod Off and your own settings are back.
- **Mods that can't start:** a mod made for another KIF version, or one that doesn't work with a mod you have On, isn't loaded. Options > Mods shows it as BLOCKED with the reason. Browse warns before installing one (WON'T START / CLASH).
- **More mod catalogs:** Browse lists KIF-Mods, KIF Mods (cody-png) (KIF's own mods) and Discord Mods (mods shared on Discord), and can list other modders' catalogs too. A mod can bring its own, or add `owner/repo` lines to `KIF_mods_catalogs.txt` next to the game.
- **Misty:** losing to her no longer keeps her gym music playing in the Pokémon Center.
- **Comatose** works for every Pokémon that has it (random abilities, mods), not only Komala (PIF checked for Komala).
- **Celadon Dept. Store:** the X-item clerk sells X Sp. Def (PIF listed a placeholder "Thing" for P50 there by mistake).
- **Trade bubbles:** every NPC who offers a trade shows the trade bubble above their head until the trade is done (PIF only showed it for some of them).
- **Faster PC boxes:** a fusion's icon is made much faster the first time it's shown, and switching boxes no longer draws the new box's icons twice, so flipping between full boxes doesn't stutter. Shiny fusion icons show the shiny colours on the right half in both the party and the PC.
- **Crash log:** if the game crashes, the full error is saved to `KIF_errorlog.txt` in the `Logs` folder next to InfiniteFusion.exe, ready to share. Every other KIF log (session log, frame log, Entrances returns) is in that folder too.
- **Old KIF saves** load directly. Their settings, Pokémon and items carry over.
- **Items from a removed mod:** when a save holds items from a mod that is Off or uninstalled (in the Bag, the PC or held by Pokémon), they are put aside when the save loads instead of showing as UNKNOWN. Turn the mod back on and they return to your Bag.
