# Kuray's Infinite Fusion – Feature Guide

KIF brings the features of Kuray's Infinite Fusion 0.20.7 to Pokémon Infinite Fusion 6.8.2. Almost everything is optional and lives in one place:

**Pause menu → Options → KIF Settings** (near the bottom of the list). Right below it, **Cody Settings** holds features added in KIF Beta that were never part of the original KIF (see "Cody Settings" further down).

KIF Settings opens six menus, listed below in the order you see them. Inside each menu:

- **GLOBAL** options are shared by every save file.
- **PER-SAVE FILE** options belong to the save you're playing. They only appear once a save is loaded; from the title screen's options you'll see "Load a save to edit" instead.

Defaults are shown in *(italics)*.

---

## Shinies

### Global

- **Shiny Animation** – On / Off / All *(On)*. Plays the sparkle when a shiny enters battle. All plays it for every Pokémon, shiny or not.
- **Shiny Icons** – Off / On *(Off)*. Gives party and PC icons the same KIF shiny colours as the battle sprite. Looks nicer but costs performance.
- **Shiny Cache** – Permanent / Per Session / Off *(Permanent)*. KIF shiny sprites are generated once and remembered. Per Session forgets them when you close the game; Off regenerates them every time (slowest).
- **Shiny Filter** – Off / Filtered / Hybrid *(Hybrid)*. KIF's colour shifts can wash out a sprite's outlines and shading. Filtered keeps every shiny readable, Off shows the raw KIF colours, and Hybrid filters half of all shinies and leaves the other half raw.

### Per-save

- **Shiny Colors** – Simple / Normal / Advanced *(Normal)*. How KIF shinies are coloured. Simple only shifts the hue (fastest). Normal also shifts colour channels. Advanced is the full system with the widest variety (slowest).
- **PIF's Improved Shinies** – Hybrid / Split / Vanilla / Off *(Hybrid)*. How KIF's shiny colours combine with PIF's own shiny palettes.
  - Hybrid: every shiny gets KIF colours, and most also get PIF's palette.
  - Split: some shinies get PIF colours, some KIF colours, some both.
  - Vanilla: PIF shinies only.
  - Off: KIF shinies only.
- **Shiny Fuse Dye** – Off / On / Random *(Off)*. On: fusing a shiny keeps its colours on the result, so you can "dye" a fusion. Random: the colours are re-rolled after every fusion or unfusion.
- **Shiny Gamble Odds** – slider, 0–1000 *(100)*. The odds for the PC's Shiny Gamble: 1 in this number. 0 means every gamble wins.
- **Wild Shiny Odds** – slider, 1–65536 *(16)*. Your shiny chance out of 65,536. 16 is the standard 1 in 4,096; raise it for more shinies. Use "Increment Slider by" (see the end of this guide) to move it faster.
- **Shiny Trainer Pokemon** – Off / Ace / All / Disabled *(Off)*.
  - Off: trainers' Pokémon have normal shiny odds.
  - Ace: every trainer's ace is shiny.
  - All: every trainer Pokémon is shiny.
  - Disabled: trainer Pokémon are never shiny.

---

## Battles & Pokemons

All options in this menu are per-save.

### Battle format and control

- **Battle Format** – 1v1 / 2v2 / 3v3 *(1v1)*. Turns battles into doubles or triples whenever the game allows it.
- **Format Applies To** – Wild / Trainers / Both *(Wild)*. Which battles Battle Format affects.
- **Auto-Battle** – Off / On *(Off)*. Trapstarr's Auto-Battler: an ally AI picks your moves for you.
- **Auto-Battle Shiny Stop** – Off / On *(Off)*. Turns Auto-Battle off as soon as a shiny wild Pokémon appears.
- **Damage Variance** – Off / On *(On)*. Off removes the random damage roll, so a move always does the same damage.
- **Battle AI** – PIF / DemICE *(DemICE)*. Which brain opponents use. DemICE's AI (from the community hard-mode mods) plays smarter and focuses on its best move. PIF is PIF 6.8.2's own AI.

### Battle mechanics (by Bluewuppo)

- **Modern Hail** – Off / Hail / Snow *(Off)*. Hail: Ice types get a defence boost during hail. Snow: hail becomes Gen 9 Snow.
- **Frostbite** – Off / On *(Off)*. Replaces Freeze with Gen 9-style Frostbite: the Pokémon can still act, but takes damage each turn.
- **Drowsy** – Off / On *(Off)*. Replaces Sleep with Drowsy: the Pokémon isn't fully disabled.
- **Bug Type Buffs** – Off / Defensive / + Offensive *(Off)*. Defensive: Bug resists Fairy, Psychic and Dark. + Offensive: also makes Fairy weak to Bug moves.
- **Ice Type Buffs** – Off / On *(Off)*. Ice resists Water and Flying.
- **Show Lv. in BSM** – Off / On *(Off)*. In PIF's Base Stats Mode, still shows Pokémon levels in battle. The level doesn't reflect their stats there.

### Levels and experience

- **Level Cap** – Off / Easy / Normal / Hard *(Off)*. A forced level cap that follows your badges, from generous (Easy) to strict (Hard).
- **Cap Behavior** – Smart / Lock / RC *(Smart)*. What happens at the cap.
  - Smart: experience is banked and given back when the cap rises.
  - Lock: no experience past the cap.
  - RC: you get Rare Candies instead.
- **ExpAll Redistribution** – slider, 0–10 *(0)*. While Exp All is active, moves 10% per step of its experience toward your lower-level Pokémon.
- **No-EVs Mode** – Off / On *(Off)*. Pokémon have no EVs at all.
- **Max IVs Mode** – Off / On *(Off)*. Every Pokémon has perfect IVs.
- **EVs Train Mode** – Off / On *(Off)*. Defeated Pokémon give no EVs. Only Power items give EVs, so you can train exactly what you want.
- **Trainer Exp. Boost** – slider, 0–1000% *(+50%)*. Extra experience from trainer battles.

### Catching

- **Rocket Mode** – Off / On / All Balls *(Off)*. Lets Rocket Balls (sold in the Kuray Shop) steal trainers' Pokémon. All Balls lets any ball do it.
- **Recover Consumables** – Off / On *(Off)*. Berries, gems and other items your Pokémon use up in battle come back afterwards.
- **Skip Caught Prompt** – Off / On *(Off)*. With a full party, a caught Pokémon goes straight to the PC with no question asked.
- **Critical Captures** – Off / On *(On)*. Critical captures can happen with any ball, and get more likely the more Pokémon you own. Off keeps only PIF's own last-ball critical capture.

### Fusion

- **Self-Fusion Stat Boost** – Off / On *(Off)*. A Pokémon fused with itself gets a stat boost scaled to its base stat total.
- **Fusion BaseStats** – Off / Head / Better *(Off)*. Choose how your fusions' base stats are made. The six sliders under it set, per stat, what percentage comes from the head (Head) or from whichever parent has the higher stat (Better).
- **NPC Fusion BaseStats** – Off / Head / Better *(Off)*. The same, for other trainers' and wild fusions. Has its own six sliders.
- **Dominant Fusion Types** – Off / On *(Off)*. Brings back the pre-v6 fusion typing, where dominant types such as Steel or Water take priority.
- **Head Legendary Breeding** – Off / On *(Off)*. Fusions with a legendary head can breed again, as in older PIF versions.

### K-Eggs

K-Eggs are sold in the Kuray Shop (see "Others → Kuray QoL").

- **K-Eggs Fusion Pool** – Off / On *(Off)*. When an egg rolls a fusion, the second Pokémon comes from the same egg's pool. Off makes it random.
- **K-Eggs Rarity** – On / Off *(On)*. On: rarer Pokémon (lower catch rate) come out less often. Off: every Pokémon in the pool has equal odds.
- **K-Eggs Fusion Odds** – slider, 0–100% *(20%)*. The chance that a K-Egg gives a fusion.
- **K-Eggs Usage** – Pokemon / Egg *(Pokemon)*. Using a K-Egg gives a level 1 Pokémon, or an Egg that hatches into it.
- **K-Eggs Rewards** – slider, 0–10 *(3)*. How many of each new K-Egg tier you get for free when it unlocks.

### Other

- **Unfuse Traded** – Off / On *(Off)*. Allows unfusing Pokémon you got through trades.
- **Event Moves** – Off / On *(Off)*. The Egg Move Tutor (and the party's "Change moves") also offers event-exclusive moves.
- **Improved Pokedex** – Off / On *(Off)*. Catching or evolving a fusion also registers its head and body Pokémon in the Pokédex.

---

## Graphics

### Global

- **Type Display** – Off / Ico / TCG / Sqr / FGM / Txt *(Off)*. Shows each Pokémon's in-battle types on its HP box.
  - Ico: icons by Lolpy1.
  - TCG: trading-card style.
  - Sqr: square icons (Triple Fusion by Lolpy1).
  - FGM: icons by FairyGodmother.
  - Txt: plain text.
- **Swap BattleGUI** – Off / Type 1 / Type 2 *(Off)*. Alternative HP/Exp bar designs by Mirasein.
- **Fusion Preview** – Off / On *(Off)*. When fusing, shows the real sprite of fusions you haven't seen yet instead of a silhouette, with shiny colours if the result will be shiny.
- **Big Pokémon Icons** – Off / Limited / All *(Off)*. Icons use a small version of the Pokémon's battle sprite.
  - Limited: party, summary and other screens.
  - All: also the PC boxes.
  - The party screen adjusts its layout for them: the level sits by the HP, and status badges (PSN, FNT…) sit on the sprite.
- **Game's Font** – Default / FR/LG / D/P / R/B *(Default)*. Changes the game's font.

### Per-save

- **Dark Mode** – Off / On *(Off)*. Dark Pokédex, Summary and PokéNav screens, plus dark battle menus.

---

## Self-Battle & Import

All options in this menu are per-save. They control the PC's **Battle** and **Import/Export** features (see "Elsewhere in the game" at the end).

### Import & Export

- **Import Level** – Default / 1 / 5 / 50 / 100 *(Default)*. Sets the level of imported Pokémon, or keeps their original level.
- **Import De-Evolve** – Off / On *(Off)*. Imported Pokémon become their baby form.
- **Import as Egg** – Off / On *(Off)*. Imported Pokémon arrive as Eggs.
- **Import Without Deletion** – Off / On *(Off)*. Keeps the file in the import folder after importing, so it can be imported again.
- **Delete on Export** – Off / On *(Off)*. Removes the Pokémon from your game when you export it.
- **Export Sprite on Export** – On / Off / Shiny *(On)*.
  - On: saves the Pokémon's picture (.png) next to its file.
  - Off: saves the file only.
  - Shiny: saves a shiny-coloured picture, but exports the Pokémon itself as non-shiny.
- **Import Sprite on Import** – On / Read-Only / Off *(On)*.
  - On: uses the picture that comes with an imported Pokémon.
  - Read-Only: reads the picture without copying it.
  - Off: ignores it.

### Self-Battle

- **Battle Size** – 1–6 *(6)*. How many Pokémon the opponent gets in a Self-Battle.
- **Player Size** – 1–6 *(6)*. How many Pokémon you get when your team is randomized.
- **Level** – Default / 1 / 5 / 10 / 50 / 70 / 100 *(Default)*. Sets every Pokémon in a Self-Battle to this level.
- **Randomize Team** – Off / On *(Off)*. Your team is also drawn at random from the chosen pool.
- **Randomize Share** – Off / On *(On)*. You and the opponent may draw the same Pokémon.
- **Players Folder** – Off / On *(Off)*. Your random team comes from a separate exported-Pokémon folder.
- **Team Select** – Off / On *(On)*. Lets you pick your team before the battle.
- **Limitless Select** – Off / On *(On)*. Lets you pick any number of Pokémon (6 vs 1 and so on).
- **Battle Loop** – Off / On *(Off)*. Box Self-Battles repeat with new random teams. Hold B as a battle ends to stop.
- **Stat Tracker** – Off / On *(Off)*. Shows a win/loss counter while Auto-Battle and Battle Loop are both on.

Self-Battles use copies: nothing gains Exp, no money changes hands, and your team is restored and healed afterwards.

---

## Challenges

All options in this menu are per-save.

- **Metronome Madness** – Off / Normal / Hard *(Off)*. Normal: every Pokémon can only use Metronome. Hard: only yours.
- **Letdown** – Off / 1% / 5% / 10% / 25% / 50% *(Off)*. The chance that a Pokémon uses Splash instead of its chosen move.
- **Letdown Player Only** – Off / On *(Off)*. Letdown only affects your Pokémon.
- **Berserker** – Off / Easy / Normal / Hard / Chaos *(Off)*. Opponents' stats keep rising during battle.
  - Easy: +1 every 3 turns.
  - Normal: +1 every 2 turns.
  - Hard: +1 every turn.
  - Chaos: +2 every turn, and maxed out after 3 turns.

---

## Others

### Global

- **Save Backups** – Infinite / PIF *(Infinite)*. Infinite: every save makes a backup and none are ever deleted. PIF: only the newest ones are kept. The Save menu also gains:
  - **Name the next backup:** gives that backup a label in the load-backup list.
  - **Open the save folder.**
- **Debug Exclusive** – Off / On *(Off)*. On: Import/Export and other tools need Debug mode.
- **Dex Evolutions** – Credits Box / Entry Box *(Credits Box)*. On the Pokédex info page, the Run button shows the Pokémon's evolutions (levels, items, conditions). Credits Box swaps the sprite-credits box for evolution lines; Entry Box shows an evolution chart in the entry box.
- **Dex Sprite Select** – Off / On *(On)*. Each newly registered Pokémon or fusion asks which sprite to use.
- **Summary IVs/EVs** – Off / On *(On)*. The Summary's Skills page shows IVs, EVs and base stats next to each stat.
- **Speed-up Limit (Toggle)** – slider, 1–10 *(3)*. The top speed when speed-up is in Toggle mode. PIF stops at 3x.
- **Quicksave with S** – Off / On *(On)*. Press S on the map to save instantly.

### Per-save

- **Overworld Poison** – Off / On / On+Healing *(Off)*. On: Pokémon whose ability protects them from poison don't take poison damage while walking. On+Healing: abilities like Poison Heal restore HP instead.
- **Streamer's Dream** – Off / On *(Off)*. Makes several items free in the Kuray Shop, and makes Buy Box and the Shiny Gamble free:
  - Rare Candy, Master Ball, Max Repel, Rage Candy Bar.
  - Transgender and Mist Stones, Devolution Spray.
  - Every K-Egg.
- **PokeRadar+** – Off / On *(Off)*. Poké Radar chains never break at random.
- **Radar Chain Count** – Off / On *(On)*. With PokeRadar+, shows your chain count when the grass shakes.
- **Enable EvoLock** – Off / On *(Off)*. Lets you lock a Pokémon's evolution from the PC ("Kuray Actions → Lock Evolution"). A locked Pokémon won't evolve by any means until you unlock it. A padlock shows on its party panel and Summary.
- **Tutor.net** – Off / On *(On)*. Adds "Tutor.net" to the pause menu (by DemICE): every TM you own and every move tutor you've used, in one list. TMs are free to use. A tutor's move costs once, then stays unlocked forever.
- **Kuray QoL** – Off / On *(On)*. Adds three entries to the pause menu (they can't be used in the Elite Four, Mt. Silver and a few story areas):
  - **PC:** open the PC anywhere.
  - **Heal Pokémon.**
  - **Kuray Shop:** TMs, PP and Power items, Rare Candy, Master Ball, the Transgender and Mist Stones, Devolution Spray, Rocket Balls, K-Eggs and more.
- **Hatch to PC Prompt** – Off / On *(On)*. When an Egg hatches, asks whether to send the baby to the PC.
- **Kuray's Shenanigans** – On / Off *(On)*. Easter eggs around the secret "pizza" gender (a 1 in 256 roll). A pizza Pokémon shows a pizza icon in battle, its Attract works on anyone, and the Transgender Stone can make or remove pizza.

---

## Bottom of KIF Settings

- **Increment Slider by** – 1 / 10 / 100 / 1000 / 10000 *(1)*. How far big sliders (like Wild Shiny Odds) move per press.
- **DEBUG** – Off / On *(Off)*. Turns on PIF's debug mode, with the Debug menu and debug options in the PC and party.

---

## Cody Settings

**Pause menu → Options → Cody Settings** – new features made for KIF Beta, kept apart from KIF's own settings. Same layout as KIF Settings, split into categories.

### Battles

- **Move Effectiveness** – Off / On *(On, all saves)*. The Fight menu shows how well each damaging move works against the foe: a green ▲ (super effective), orange ▼ (resisted) or grey ✕ (no effect) on each move button, and "Super eff." / "Resisted" / "No effect" under the PP of the highlighted move. With several foes, the info box lists each one with its multiplier (e.g. "Gyarados x4", "Onix x0") and names too long for the box scroll like a car radio display. The button marker shows the best result. Uses the battle's real type rules (including KIF's type buffs). Abilities stay hidden until the battle reveals them: once a foe's Levitate, Flash Fire, Volt Absorb, Water Absorb, Wonder Guard (and similar) has popped up, its immunity shows as "No effect" for the rest of that battle (not against Mold Breaker). Air Balloon and Magnet Rise also show Ground moves as "No effect".
- **Gym Leader teams** – Normal / +1 / +2 / Full *(Normal, per save)*. Gym Leaders bring extra Pokémon to every battle with them (gym, rematch or story battle). The extras have the gym's type (randomized gym types count), are fusions about as often as the rest of the team, are about as strong as the team, are evolved as far as their level allows and join at the team's average level. Never legendaries, repeats or banned Pokémon, and the same every time for a save. On randomized saves with random trainers, the Randomizer's *Leader team size* decides instead.
- **Your Pokémon in gyms** – Normal / +1 / +2 / Full *(Normal, per save)*. Raises how many Pokémon you may pick before a Kanto Gym Leader battle (Full = your whole party). The picker still shows.

### Breeding & Fusion

- **Legendary Breeding** – Off / On *(Off, per save)*. Legendary Pokémon (and fusions with a legendary head or body) can breed with any Pokémon that can breed – no egg group or gender needed. The Egg is one of four results, 25% each: either parent, or either fusion of the two (Mewtwo + Vulpix → Mewtwo, Vulpix, Mewpix or Vultwo). With Ditto, the Egg is the other parent. Baby Pokémon still can't breed.

### Randomizer

Only on saves started as randomized saves: **Cody Settings → Randomizer**. The same screen also replaces PIF's randomizer menu when you make a randomized save, and the Update Man's *Advanced options → Randomizer options → Randomizer settings* opens it too.

- **Seed** – an 8-character code (like `K7Q2-9XMA`). The same seed with the same settings gives the same randomized game (on the same KIF Beta version and sprite pack). New random seed, type one in, or copy it.
- **Presets & sharing** – *Copy settings code* puts the seed and every setting on your clipboard as one line (paste it into Discord); *Paste settings code* loads someone else's. *Save as preset* / *Load preset* use files in the `Randomizer/Presets` folder (saving over an existing name asks first; presets from earlier KIF Beta versions still load).
- **Spoiler log** – Off / On *(On)*. Writes `Randomizer Log - <seed>.txt` in the `Randomizer/Logs` folder every time something is shuffled: every Pokémon swap, route, trainer team, gym type, item and TM. *View spoiler log* shows it in-game (asks first; each part is built when opened); Up/Down scroll, Left/Right turn a page, Z jumps to a dex number or text.
- **Pokémon** – each part has its own switch:
  - *Wild encounters*: Off / Swap (each species becomes one other species everywhere) / Route (every route rolls its own) / Dynamic (every encounter rolls its own Pokémon on the spot, within the Strength range) / Dynamic Route (like Route, but a route rolls new Pokémon every time you enter it; the roll stays while you're on that map, saving and loading included, and follows the seed).
  - *PokéRadar*: the radar's route list matches what really appears (PIF used the Swap table even when wild Pokémon weren't swapped); radar-only rares are randomized too (Swap: what it became; Route: one per route; Dynamic Route: one per visit; Dynamic: any). Oak's aide on Route 24 finishes her field research in Dynamic (nothing repeats) and in Dynamic Route (once the visit is catalogued), with the quest points and reward.
  - *Starters* (Off / 1st stage / Any), *Static encounters*, *Gift Pokémon*.
  - *Trades*: Off / Swap (what the Pokémon became; fusion trades too) / Random (each trade rolls its own within the Strength range). The spoiler log lists every trade.
  - *NPC requests*: Original / Swapped *(default)* / Any. When a trade or quest asks for a specific Pokémon: Swapped = what it became (Swap mode; other modes accept any Pokémon), Any = any Pokémon. The NPC's lines name the new Pokémon; with Any they add "(Any Pokémon will do.)". PokéRadar rares are always asked for as what they became.
  - *Strength range* 0–999 (how close in base stat total a replacement must be; 999 = anything), *Legendaries*, *Custom sprites only*, *Fuse everything*.
- **Trainers**
  - **Trainers** – Off / Random / Follow wild. Follow wild gives trainers the wild swap table (a trainer's Pidgey becomes whatever wild Pidgey became).
  - **Strength range**, **Custom sprites only** – as in PIF.
  - **Class themes** – Off / On *(On)*. Every Pokémon of a themed class has its type: Bug Catchers use Bug types, Swimmers Water types, Hikers Rock/Ground, and so on; *Class theme list* shows every class. Follows randomized types. Gym leaders use the Gyms page.
  - **Shuffle themes** – Off / On. Each class gets a random type instead (the same for the same seed); Type Experts keep theirs.
  - **Extra class themes** – Off / On *(On)*. Also themes the less obvious classes: Scientists, Bikers, Burglars, Jugglers, Robots, Roughnecks, Cue Balls, Aroma Ladies, Painters and Tubers.
  - **Rival keeps his team** – Off / On. Each Pokémon line in the rival's team gets one replacement line for every battle, at the same stage.
  - **Team size** – Same / +1 / +2 / Full. Extra Pokémon join at the team's average level. Not Gym Leaders (see Gyms).
  - **Fuse everything** – Off / On. Every trainer Pokémon is a fusion.
  - **Unfused Pokémon** – Normal / 25% / 50% / 75% / All. How many trainer Pokémon are plain, unfused Pokémon (Normal = the game's own odds, nearly all fusions). Fuse everything wins if both are on.
- **Gyms** – PIF's options (custom sprites only, gym types, rerandomize each battle), plus **Leader team size** – Same / +1 / +2 / Full: Gym Leaders bring extra Pokémon in every battle with them.
- **Items**
  - **Item mode** – Mapped / Dynamic. Mapped: each item always becomes the same other item. Dynamic: every item ball, gift and shop rolls its own item; the same spot always gives the same item for the same seed. TMs follow the mode too.
  - **Found items**, **Found TMs**, **Given items**, **Given TMs**, **Shop items** – each only changes its own part.
  - **Trainer held items** – Off / Random / Fixed. Random gives a new item every battle; Fixed gives each trainer's Pokémon the same item every time.
  - **Keep categories** – Off / On. Balls stay balls, medicine stays medicine, berries, held items, evolution items, gems, mail, battle items and TMs stay in their group.
  - **Keep shop basics** – Off / On *(On)*. Poké Balls and Splicers stay buyable.
  - **Banned items** – never a random result. Starts with the items that have no use in PIF (shards, apricorns, contest scarves, mail, flavour-only berries, ...).
- **Pokémon data** – changes the Pokémon themselves (fusions are built from their two parts, so they follow):
  - *Types*: Same / Random (each evolution family gets new types) / Dual (everyone gets two types); *Original type*: Allowed / Never.
  - *Moves follow type*: moves of the old type become moves of the new type at the same level with similar power (other moves stay). *TMs follow type* does the same for TM and tutor compatibility.
  - *Abilities*: Same / Random / Flavour (abilities themed on the Pokémon's types) / Bound (only abilities Pokémon of its types have in the base game). *No self-harm* never gives Truant, Slow Start, Defeatist, Klutz, Stall, or weather that hurts the Pokémon's own type.
  - *Base stats*: Same / Shuffle (same numbers, new order) / Total (random spread, same total) / Chaos (every stat 1–255). *Chaos safety*: Off / Total (evolving never lowers the total) / Each stat (evolving never lowers any stat).
- **Evolutions** – Same / Random: a Pokémon that evolves turns into a higher stage or a Pokémon that doesn't evolve, at the same level or with the same item. *Type-themed*: the evolution shares a type.
- **Exclusions** – lists of Pokémon, moves and abilities the randomizer never picks (A: ban/unban, L/R: page, Z: clear all). Bans only affect what the randomizer picks; parts that aren't randomized keep their normal Pokémon.
- **Randomize now** – applies the settings mid-game (asks first; your party and boxes stay).
- **Settings wait for Randomize now** – changing a setting on a randomized save doesn't change your game until you randomize. Changed settings are marked `*`, and the Randomize now button shows how many. Leaving the screen with changes asks: *Randomize now*, *Keep for later* (they stay marked next time, the game keeps the old ones), or *Undo changes*. The new-game setup works as before. (The Spoiler log switch is the one setting that applies at once.)

### Interface

- **Fusion Screen** – Off / On *(On, all saves)*. The DNA Splicers' preview shows, for both fusion orders, the fusion's name, types and the stats it will really have once fused (its fused level, the body's EVs and nature, the averaged IVs – or the higher ones with Super Splicers – and every setting that changes stats or types, such as No-EVs / Max IVs modes, custom fusion base stats, the self-fusion boost and Dominant Fusion Types). The higher stat of each left/right pair is green; the bars and "Base total" show the base stats. Press **A** on a fusion for **Change Body / Change Head / Confirm**. Change Body or Change Head lists that part's current form and every later evolution (branches included), tagged Stage 1, Stage 2 or Final; the preview follows the cursor, and the other side mirrors the change so both orders stay comparable. Confirm always fuses the Pokémon you have now (it reads "Fuse <name>" while you're previewing an evolution).

---

## Elsewhere in the game

These features have no option of their own.

- **PC → a Pokémon → Kuray Actions** (also in the party menu):
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
- **K-Eggs** (Kuray Shop): Random, Sparkling (40x shiny odds), one per type, Fusion, Base (never a fusion), Legendary, Hoenn (Pokémon new to PIF 6.8.2), and tier eggs.
  - Every egg gives 10x your Wild Shiny Odds.
  - The tier eggs are Starter, 1–8 Badges and Elite 4, each with a base-stat range for that point in the game.
  - New tiers unlock as you earn badges and beat the Elite Four. You're told the next time you open the Kuray Shop.
- **DemICE's Endgame Challenge:** after the Elite Four, talk to Dem in the League lobby to turn on the challenge.
  - The Elite Four, Blue, the Fighting Arena leaders, Gold and Cynthia use level 100 fusion teams scaled to your strongest Pokémon.
  - Challenge rules: singles only, no items in trainer battles, Set style, and foes have doubled PP.
  - Beating Blue earns emblems; the Silver Emblem opens the Mt. Silver vortex to Cynthia.
- **Mystery Gift:** KIF's gift "Fire Misbok!" appears in "Search for public gifts". It's a shiny Ghost/Fire Misdreavus/Arbok fusion: it shows that a Pokémon's types aren't always locked to its species.
- **Speed keys:** with speed-up in Toggle mode, L goes to the next speed and R goes back to 1x.
- **Skip the intro:** put an empty file named `NoIntro.krs` in your save folder to go straight to the load screen.
- **Load screen:** links to the KIF Discord and documentation.
- **Mods folder:** any `.rb` file in the `Mods` folder next to Game.exe loads when the game starts. A broken mod is skipped instead of crashing the game.
- **Crash log:** if the game crashes, the full error is saved to `KIF_errorlog.txt` next to Game.exe, ready to share.
- **Old KIF saves** load directly. Their settings, Pokémon and items carry over.
