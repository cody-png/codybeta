#===============================================================================
# KIF Settings – the descriptions shown at the bottom of the settings screen
# Keyed by the setting's registered name. A String is shown for every value;
# an Array has one line per value (same order as the choices). Settings not
# listed here keep the description they were registered with.
#===============================================================================
module KIF
  module SettingsScreen
    DESCRIPTIONS = {
      # Shinies
      "Wild Shiny Odds" =>
        "Chance for a wild Pokémon to be shiny, out of 65536. PIF's default is 16 (1 in 4096). Only Pokémon met after a change use the new odds.",
      "Shiny Gamble Odds" =>
        "Gamble Shininess (PC > Kuray Actions) makes a Pokémon shiny with a 1 in this number chance. 0 = it always works.",
      "Shiny Trainer Pokemon" => [
        "Opposing trainers' Pokémon can be shiny, at the Wild Odds.",
        "As Off, and each trainer's ace (strongest Pokémon) is always shiny.",
        "Every Pokémon of every opposing trainer is shiny.",
        "Trainers' Pokémon use the same shiny odds as your Wild Shiny Odds slider, as in PIF (no extra roll)."],
      "Shiny Colors" => [
        "KIF shinies only shift the hue. Fastest.",
        "KIF shinies shift the hue and swap colour channels.",
        "The widest range of KIF shiny colours, including inverted and darkened ones. Slowest."],
      "PIF's Improved Shinies" => [
        "Most shinies get PIF's palette with KIF colours on top; the rest get KIF colours only.",
        "Each shiny gets KIF colours, PIF's palette, or both.",
        "Only PIF's shiny palettes. KIF colours are off.",
        "Only KIF colours. PIF's shiny palettes are off."],
      "Shiny Fuse Dye" => [
        "A shiny fusion keeps the body's shiny colours (the head's when both are shiny).",
        "A shiny fusion takes the head's shiny colours whenever the head is shiny.",
        "Shiny colours are rolled again on every fusion and unfusion."],
      "Shiny Filter" => [
        "KIF shiny colours exactly as in KIF 0.20.7.",
        "Every KIF shiny is cleaned up to keep readable outlines and shading.",
        "Half of the KIF shinies are cleaned up, the other half keep their raw colours."],
      "Shiny Icons" => [
        "Party and PC icons use PIF's shiny icons.",
        "Party and PC icons also get the KIF shiny colours. Slower."],
      "Shiny Animation" => [
        "Shiny Pokémon sparkle when they enter a battle.",
        "No shiny sparkle in battles.",
        "Every Pokémon sparkles when it enters a battle, shiny or not."],
      "PokeRadar+" => [
        "The Poké Radar works as in PIF.",
        "Poké Radar chains show their count and never drop at random."],
      "Radar Chain Count" => [
        "PokeRadar+ doesn't show the chain count.",
        "PokeRadar+ shows the chain count and shiny chance when the grass shakes."],
      "Multi-Battle Radar" => [
        "Poké Radar battles are always 1v1, as in PIF.",
        "With Battle Format 2v2 or 3v3, every foe is the chained species. A battle adds 1 to the chain.",
        "With Battle Format 2v2 or 3v3, the other foes are normal encounters. A battle adds 1 to the chain."],
      "Shiny Cache" => [
        "KIF shiny sprites are worked out once and kept in the Cache folder.",
        "KIF shiny sprites are kept until the game closes.",
        "KIF shiny sprites are worked out every time they're shown. Slowest."],
      # Battles
      "Battle Format" => [
        "Battles are 1v1, unless the game makes it a double battle.",
        "Battles are 2v2 when both sides have enough Pokémon.",
        "Battles are 3v3 when both sides have enough Pokémon."],
      "Format Applies To" => [
        "Battle Format changes wild battles only.",
        "Battle Format changes trainer battles only.",
        "Battle Format changes wild and trainer battles."],
      "Auto-Battle" => [
        "You choose your own moves.",
        "The battle AI fights for you and battle text moves on by itself."],
      "Auto-Battle Shiny Stop" => [
        "Auto-Battle keeps going when a shiny wild Pokémon appears.",
        "Auto-Battle turns itself off when a shiny wild Pokémon appears."],
      "Auto-Battle Switching" => [
        "When a trainer sends in a new Pokémon, you're asked whether to switch.",
        "The battle AI decides whether to switch, and into whom, once it sees the new Pokémon.",
        "Your Pokémon stays in."],
      "Auto-Battle Level Up" => [
        "The stat window after a level up waits for you.",
        "The battle goes on after a level up."],
      "Auto-Battle New Moves" => [
        "You choose which move to forget, as usual.",
        "The battle AI keeps the four moves it rates best against the opposing team.",
        "New moves aren't learned while Auto-Battle is on."],
      "Auto-Battle Evolutions" => [
        "Evolutions after a battle wait for you, as usual.",
        "Evolutions after a battle play by themselves. B still stops one."],
      "Battle AI" => [
        "Opponents use PIF 6.8.2's own AI.",
        "Opponents use DemICE's AI, from the community hard-mode mods. It plays differently, not just harder."],
      "Damage Variance" => [
        "A move always does the same damage (no random roll).",
        "Damage varies between 85% and 100%, as in the official games."],
      "Modern Hail" => [
        "Hail as in PIF.",
        "In hail, Ice types take less damage from physical moves.",
        "Hail becomes Snow: no damage each turn, and Ice types take less damage from physical moves."],
      "Frostbite" => [
        "Freezing works as in PIF.",
        "Freezing becomes Frostbite: the Pokémon can still act, loses a little HP each turn and deals half special damage."],
      "Drowsy" => [
        "Sleep works as in PIF.",
        "Sleep becomes Drowsy: the Pokémon acts about half the time and deals half damage."],
      "Pre-Status" => [
        "Pokémon start battles with the status they already have.",
        "Kuray Actions (PC or party) > Start Battles makes a Pokémon start every battle burned or poisoned, if it can be."],
      "Bug Type Buffs" => [
        "Bug types as in PIF.",
        "Bug types resist Fairy, Psychic and Dark.",
        "Bug types resist Fairy, Psychic and Dark, and Bug moves are super effective on Fairy types."],
      "Ice Type Buffs" => [
        "Ice types as in PIF.",
        "Ice types resist Water and Flying."],
      "Gym Leader teams" => [
        "Gym Leaders bring their usual team.",
        "Gym Leaders bring one more Pokémon. On randomized saves, the Randomizer's Gyms page decides.",
        "Gym Leaders bring two more Pokémon. On randomized saves, the Randomizer's Gyms page decides.",
        "Gym Leaders bring six Pokémon. On randomized saves, the Randomizer's Gyms page decides."],
      "Your Pokémon in gyms" => [
        "Kanto Gym Leaders limit how many Pokémon you can use, as usual.",
        "You may use one more Pokémon against Kanto Gym Leaders.",
        "You may use two more Pokémon against Kanto Gym Leaders.",
        "You may use your whole party against Kanto Gym Leaders."],
      "Battle Info" => [
        "No battle info screen.",
        "In battle, INFO (or {ACTION}) shows stats, abilities, moves, the field and the speed order.",
        "Battle info opens with {ACTION} only; no INFO button on screen."],
      "Foe Info" => [
        "Battle Info lists a foe's abilities and moves from the start of the battle.",
        "Battle Info shows a foe's abilities and moves only once the battle has shown them."],
      "Move Effectiveness" => [
        "The Fight menu doesn't show how effective moves are.",
        "The Fight menu marks how effective each move is against the foe."],
      "Show Lv. in BSM" => [
        "Base Stats Mode hides levels in battle.",
        "Base Stats Mode shows levels in battle (the level doesn't change the stats there)."],
      "EBDX Battles" => [
        "Battles look like PIF's own.",
        "Battles use Elite Battle DX's look and animations."],
      "EBDX Camera Zoom" => [
        "The EBDX camera stays still during attacks.",
        "The EBDX camera zooms in on attacks."],
      "EBDX Stat Stage Icons" => [
        "No stat stage icons on the EBDX battle boxes.",
        "Raised and lowered stats show on the EBDX battle boxes."],
      "EBDX Own Trainer Animation" => [
        "Your trainer throws the ball at the start of an EBDX battle.",
        "Your Pokémon comes straight out."],
      # Pokémon
      "Level Cap" => [
        "No level cap from KIF.",
        "Level cap 10% above PIF's next-gym cap.",
        "Level cap at PIF's next-gym cap.",
        "Level cap 10% below PIF's next-gym cap."],
      "Cap Behavior" => [
        "EXP past the cap is saved and given back when the cap rises.",
        "No EXP past the cap.",
        "Each level past the cap becomes a Rare Candy."],
      "Trainer Exp. Boost" =>
        "Extra EXP from trainer battles, in %. 50 = PIF's normal bonus, 0 = same as wild battles, 100 = double.",
      "ExpAll Redistribution" =>
        "With Exp All, gives more of the shared EXP to your lower-level Pokémon. 0 = as in PIF, 10 = the most.",
      "No-EVs Mode" => [
        "EVs count, as usual.",
        "Stats are worked out as if every EV were 0. EVs are kept, so turning it off brings them back."],
      "Max IVs Mode" => [
        "IVs count, as usual.",
        "Stats are worked out as if every IV were 31. This applies to foes too."],
      "EVs Train Mode" => [
        "Defeated Pokémon give EVs, as usual.",
        "Defeated Pokémon give no EVs; only Power items give them."],
      "Critical Captures" => [
        "Only PIF's last-ball critical captures.",
        "Any ball can make a critical capture (an instant catch). More likely the more Pokémon you own."],
      "Rocket Mode" => [
        "You can't catch trainers' Pokémon.",
        "Rocket Balls can catch trainers' Pokémon.",
        "Any ball can catch trainers' Pokémon."],
      "Skip Caught Prompt" => [
        "With a full party, you're asked where a caught Pokémon goes.",
        "With a full party, a caught Pokémon always goes to the PC."],
      "Recover Consumables" => [
        "Items used up in battle (berries, gems...) are gone.",
        "Items your Pokémon used up in battle come back after the battle."],
      "Items to Bag" => [
        "Thief, Covet and Pickup only work for a Pokémon with no held item.",
        "If it holds an item, what it steals from wild Pokémon or finds with Pickup goes to the Bag."],
      "Fusion BaseStats" => [
        "Your fusions' base stats as in PIF.",
        "The sliders below set how much of each base stat comes from the head.",
        "The sliders below set how much of each base stat comes from the higher of the two."],
      "NPC Fusion BaseStats" => [
        "Other trainers' and wild fusions' base stats as in PIF.",
        "The sliders below set how much of each base stat comes from the head.",
        "The sliders below set how much of each base stat comes from the higher of the two."],
      "Self-Fusion Stat Boost" => [
        "A Pokémon fused with itself has normal stats.",
        "A Pokémon fused with itself gets a stat boost: bigger for weaker Pokémon."],
      "Dominant Fusion Types" => [
        "Fusion types as in PIF 6.",
        "Fusion types as before PIF 6 (dominant types)."],
      "Unfuse Traded" => [
        "Traded fusions can't be unfused.",
        "Traded fusions can be unfused."],
      "Legendary Breeding" => [
        "Legendary Pokémon can't breed.",
        "Legendary Pokémon (and fusions with one) can breed with any Pokémon."],
      "Head Legendary Breeding" => [
        "A fusion with a legendary head can't breed (PIF 6).",
        "A fusion with a legendary head breeds through its body (older PIF)."],
      "Event Moves" => [
        "The Egg Move Tutor teaches egg moves only.",
        "The Egg Move Tutor also teaches event moves."],
      "Egg Moves" => [
        "Change moves (party menu) offers known and level-up moves.",
        "Change moves (party menu) also offers egg moves."],
      "Enable EvoLock" => [
        "No evolution locks.",
        "Lock Evolution in PC > Kuray Actions: a locked Pokémon never evolves, like with an Everstone."],
      "K-Eggs Usage" => [
        "Using a K-Egg gives a Pokémon.",
        "Using a K-Egg gives an Egg that hatches into the Pokémon."],
      "K-Eggs Rarity" => [
        "Pokémon that are harder to catch come out of K-Eggs less often.",
        "Every Pokémon is as likely to come out of a K-Egg."],
      "K-Eggs Fusion Odds" =>
        "Chance, in %, that a K-Egg gives a fusion. Default 20.",
      "K-Eggs Fusion Pool" => [
        "In a K-Egg fusion, the other Pokémon can be anything.",
        "In a K-Egg fusion, the other Pokémon also comes from that egg's list."],
      "K-Eggs Rewards" =>
        "How many of each K-Egg you get when the Kuray Shop unlocks it. Default 3.",
      # Graphics
      "Battle Animations" => [
        "Moves play their animations in battle.",
        "Moves don't play animations in battle."],
      "Battle Type Icons" => [
        "No type icons in battle.",
        "The foe's types show next to its battle box."],
      "Type Display" => [
        "No KIF type icons in battle.",
        "KIF's type icons next to the foe's battle box (set by Lolpy1).",
        "TCG-style type icons next to the foe's battle box.",
        "Square type icons next to the foe's battle box (triple fusion types by Lolpy1).",
        "Type icons by FairyGodmother next to the foe's battle box.",
        "The foe's types as text next to its battle box."],
      "Swap BattleGUI" => [
        "PIF's battle boxes and bars.",
        "Mirasein's battle boxes and bars, version 1. No effect with EBDX Battles.",
        "Mirasein's battle boxes and bars, version 2. No effect with EBDX Battles."],
      "Fusion Screen" => [
        "The DNA Splicers show PIF's preview.",
        "The DNA Splicers show names, types, real stats, and let you preview evolved forms."],
      "Fusion Preview" => [
        "Fusions you haven't seen show as a silhouette.",
        "Fusions you haven't seen show their real sprite."],
      "Big Pokémon Icons" => [
        "Pokémon use their small icons.",
        "Party and other screens use the full battle sprite as the icon (PC boxes keep small icons).",
        "Every icon, PC boxes included, uses the full battle sprite."],
      "Summary IVs/EVs" => [
        "The Skills page shows stats only.",
        "The Skills page also shows IVs, EVs and base stats."],
      "Dark Mode" => [
        "Light Pokédex, Summary and PokéNav screens.",
        "Dark Pokédex, Summary and PokéNav screens, and dark battle menus (no effect with EBDX Battles)."],
      "Improved Pokedex" => [
        "Catching a fusion registers only the fusion.",
        "Catching, hatching or evolving a fusion also registers its head and body."],
      "Dex Evolutions" => [
        "Run on the Pokédex info page swaps the credits for the evolution lines.",
        "Run on the Pokédex info page shows an evolution chart in the entry box."],
      "Dex Sprite Select" => [
        "New species don't ask you to pick a sprite.",
        "Each new Pokémon or fusion asks you to pick its sprite."],
      "Game's Font" =>
        "The font for text in the game: PIF's, or the FireRed/LeafGreen, Diamond/Pearl or Red/Blue style.",
      "Speech Frame" =>
        "The frame drawn around text boxes.",
      # Self-Battle
      "Battle Size" => "How many Pokémon the opponent gets in a Self-Battle.",
      "Player Size" => "How many Pokémon you get in a Self-Battle (with Randomize Team or Team Select).",
      "Level" => "Level of every Pokémon in a Self-Battle. Default keeps their own levels.",
      "Team Select" => [
        "Self-Battles use your team as it is.",
        "You pick your team before a Self-Battle."],
      "Limitless Select" => [
        "Team Select picks as many Pokémon as Player Size.",
        "Team Select can pick any number, for 6v1 and the like."],
      "Randomize Team" => [
        "You use your own team in Self-Battles.",
        "Your team is drawn at random from the same Pokémon as the opponent's."],
      "Randomize Share" => [
        "You and the opponent never get the same Pokémon.",
        "You and the opponent can get the same Pokémon."],
      "Players Folder" => [
        "Your random team comes from the same place as the opponent's.",
        "Your random team comes from the Players folder in ExportedPokemons."],
      "Battle Loop" => [
        "A Self-Battle happens once.",
        "Self-Battles repeat. Hold B as a battle ends to stop."],
      "Stat Tracker" => [
        "No tracker during Auto-Battle loops.",
        "Shows wins, losses and other numbers during Auto-Battle Self-Battle loops."],
      "Import Level" => "Level given to imported Pokémon. Default keeps their own.",
      "Import De-Evolve" => [
        "Imported Pokémon stay as they are.",
        "Imported Pokémon go back to their first stage."],
      "Import as Egg" => [
        "Imported Pokémon stay as they are.",
        "Imported Pokémon arrive as Eggs."],
      "Import Without Deletion" => [
        "A Pokémon's file is renamed to .json.imported once it's imported (delete those yourself).",
        "A Pokémon's file stays in the folder after it's imported."],
      "Import Sprite on Import" => [
        "The Pokémon's .png sprite is imported with it.",
        "The .png sprite is used from the folder but not copied into the game.",
        "The .png sprite is ignored."],
      "Delete on Export" => [
        "Exported Pokémon stay in the game.",
        "Exported Pokémon are removed from the game."],
      "Export Sprite on Export" => [
        "The Pokémon's sprite is saved as a .png with it.",
        "No .png is saved.",
        "The .png is saved with shiny colours, but the exported Pokémon isn't shiny."],
      # Challenges
      "Metronome Madness" => [
        "Off.",
        "Every Pokémon can only use Metronome.",
        "Only your Pokémon can only use Metronome."],
      "Letdown" => "Chance that a Pokémon uses Splash instead of the move it picked.",
      "Letdown Player Only" => [
        "Letdown affects every Pokémon.",
        "Letdown only affects your Pokémon."],
      "Berserker" => [
        "Off.",
        "Opponents' stats rise by 1 every 3 turns.",
        "Opponents' stats rise by 1 every 2 turns.",
        "Opponents' stats rise by 1 every turn.",
        "Opponents' stats rise by 2 every turn."],
      # Game
      "Speed-up type" => [
        "Speed-up works while you hold the speed-up key.",
        "The speed-up key turns speed-up on and off."],
      "Speed-up Limit (Toggle)" =>
        "The highest speed in Toggle mode. PIF stops at 3x.",
      "Streamer's Dream" => [
        "Kuray Shop prices as usual.",
        "Rare Candies, Master Balls, Max Repels, stones and more are free in the Kuray Shop."],
      "Kuray QoL" => [
        "No PC or Heal in the pause menu.",
        "The pause menu gets PC and Heal Pokémon (not in some places, like the Elite Four)."],
      "Overworld Poison" => [
        "Poisoned Pokémon lose HP while walking, as in PIF.",
        "Poison Heal and Magic Guard don't lose HP to poison while walking.",
        "As On, and Poison Heal restores HP while walking."],
      "Tutor.net" => [
        "No Tutor.net.",
        "Tutor.net in the pause menu lists the TMs and tutors you've found, to teach any time."],
      "Autosave" => [
        "The game saves by itself when you heal at a Pokémon Center.",
        "No autosave."],
      "Quicksave" => [
        "{Y} does nothing on the map.",
        "Press {Y} on the map to open the save screen."],
      "Save Backups" => [
        "Every save you make keeps a backup forever; autosaves keep their newest 10.",
        "Only the newest backups are kept, as in PIF."],
      "Hatch to PC Prompt" => [
        "Hatched Pokémon stay in your party.",
        "After an egg hatches, you're asked whether to send the Pokémon to the PC."],
      "Kuray's Shenanigans" => [
        "Easter eggs are on (pizza Pokémon and more).",
        "No easter eggs."],
      # System
      "Frame rate" =>
        "Frames drawn per second (experimental). The game runs at PIF's pace; above 40 the overworld gets in-between frames.",
      "Sprite File Cache" => [
        "Sprite files are decoded once and kept (in memory and the Cache folder).",
        "Sprite files are decoded once each time the game runs.",
        "Sprite files are decoded every time they're shown. Slowest."],
      "Imported Archives" => [
        "A sprite pack .zip/.rar is deleted once its sprites are installed.",
        "A sprite pack .zip/.rar is moved to the Imported archives folder."],
      "Debug Exclusive" => [
        "Import and Export work without debug mode.",
        "Import and Export are only offered in debug mode."],
      "DEBUG" => [
        "Debug mode follows the game as usual.",
        "Debug mode is always on: debug menus and Debug entries show up."],
    }

    module_function

    # nil when the setting keeps its own description
    def description_for(opt)
      d = DESCRIPTIONS[opt.name.to_s.strip]
      return nil unless d
      if d.is_a?(Array)
        vals = (opt.respond_to?(:values) && opt.values.is_a?(Array)) ? opt.values : nil
        return nil unless vals && vals.length == d.length
        v = (opt.get rescue 0)
        return KIF::Keys.fill(_INTL(d[v.is_a?(Integer) ? v : 0] || d[0]))
      end
      return KIF::Keys.fill(_INTL(d))
    end
  end
end
