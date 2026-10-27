#===============================================================================
# KIF Settings (new screen, 2026-10-16) – where every setting goes
# Sections in the sidebar, headings inside them, and the shorter names a row
# gets under its heading.
# PIF's own options (System & Audio, Gameplay, Visuals & Content, Challenge
# Options) are placed here too: the screen replaces Options entirely.
# A setting not listed here still shows: it lands under "Other" in Game, so
# a new feature's setting is never lost.
#===============================================================================
module KIF
  module SettingsScreen
    # [id, label, colour, [[heading, [setting names as registered]], ...]]
    SECTIONS = [
      [:shinies, "Shinies", [220, 180, 60], [
        ["Odds", ["Wild Shiny Odds", "Shiny Gamble Odds", "Shiny Trainer Pokemon"]],
        ["Look", ["Shiny Colors", "PIF's Improved Shinies", "Shiny Fuse Dye", "Shiny Filter",
                  "Shiny Icons", "Shiny Animation"]],
        ["Poké Radar", ["PokeRadar+", "Radar Chain Count", "Multi-Battle Radar"]],
        ["Speed", ["Shiny Cache"]]]],
      [:battles, "Battles", [210, 80, 80], [
        ["Format", ["Battle Format", "Format Applies To", "Battle Style"]],
        ["Auto-Battle", ["Auto-Battle", "Auto-Battle Shiny Stop", "Auto-Battle Switching",
                         "Auto-Battle Level Up", "Auto-Battle New Moves", "Auto-Battle Evolutions"]],
        ["Mechanics", ["Battle AI", "Damage Variance", "Modern Hail", "Frostbite", "Drowsy",
                       "Pre-Status", "Bug Type Buffs", "Ice Type Buffs"]],
        ["Gyms", ["Gym Leader teams", "Your Pokémon in gyms"]],
        ["Screens", ["Battle Info", "Foe Info", "Move Effectiveness", "Show Lv. in BSM"]],
        ["EBDX", ["EBDX Battles", "EBDX Camera Zoom", "EBDX Stat Stage Icons", "EBDX Own Trainer Animation"]]]],
      [:pokemon, "Pokémon", [90, 170, 100], [
        ["Levels and EXP", ["Level Cap", "Cap Behavior", "Trainer Exp. Boost", "ExpAll Redistribution"]],
        ["EVs and IVs", ["No-EVs Mode", "Max IVs Mode", "EVs Train Mode", "EV Allocation"]],
        ["Catching", ["Prompt Nicknames", "Critical Captures", "Rocket Mode", "Skip Caught Prompt",
                      "Recover Consumables", "Items to Bag"]],
        ["Fusion", ["Fusion BaseStats", "NPC Fusion BaseStats", "Self-Fusion Stat Boost",
                    "Dominant Fusion Types", "Unfuse Traded"]],
        ["Breeding and moves", ["Legendary Breeding", "Head Legendary Breeding", "Event Moves",
                                "Egg Moves", "Enable EvoLock"]],
        ["K-Eggs", ["K-Eggs Usage", "K-Eggs Rarity", "K-Eggs Fusion Odds", "K-Eggs Fusion Pool",
                    "K-Eggs Rewards"]]]],
      [:graphics, "Graphics", [110, 120, 220], [
        ["Battle", ["Battle Animations", "Battle Movement", "Battle Type Icons", "Type Display", "Swap BattleGUI"]],
        ["Sprites", ["Random Sprites", "Joke Sprites", "Custom Eggs", "Fusion Icons"]],
        ["Screens", ["Fusion Screen", "Fusion Preview", "Big Pokémon Icons", "Summary IVs/EVs", "Dark Mode"]],
        ["Pokédex", ["Autogen dex entries", "Improved Pokedex", "Dex Evolutions", "Dex Sprite Select"]],
        ["Text", ["Game's Font", "Speech Frame"]]]],
      [:selfbattle, "Self-Battle", [200, 120, 60], [
        ["Self-Battle", ["Battle Size", "Player Size", "Level", "Team Select", "Limitless Select",
                         "Randomize Team", "Randomize Share", "Players Folder", "Battle Loop", "Stat Tracker"]],
        ["Import", ["Import Level", "Import De-Evolve", "Import as Egg", "Import Without Deletion",
                    "Import Sprite on Import"]],
        ["Export", ["Delete on Export", "Export Sprite on Export"]]]],
      [:challenges, "Challenges", [160, 80, 180], [
        ["Rules", ["Level caps", "No reviving", "No heals (battles)", "No heals (overworld)"]],
        ["KIF challenges", ["Metronome Madness", "Letdown", "Letdown Player Only", "Berserker"]],
        ["Nuzlocke", ["Nuzlocke", "Fainted Pokémon", "Nuzlocke whiteout", "Dupes clause", "Shiny clause", "Gift Pokémon", "Kuray Shop", "Safari Zone", "Nuzlocke Graveyard"]]]],
      [:game, "Game", [70, 160, 170], [
        ["Difficulty", ["Difficulty"]],
        ["Movement", ["Default Movement", "Quick HMs"]],
        ["Speed-up", ["Speed-up type", "Speed-up (Overworld)", "Speed-up (Battles)", "Speed-up Limit (Toggle)"]],
        ["Randomizer", ["Randomizer"]],
        ["Kuray Shop", ["Streamer's Dream", "Kuray QoL"]],
        ["World", ["Overworld Poison", "Tutor.net"]],
        ["Saves", ["Autosave", "Quicksave", "Save Backups", "Hatch to PC Prompt"]],
        ["Fun", ["Kuray's Shenanigans"]]]],
      [:system, "System", [130, 140, 155], [
        ["Audio", ["Music Volume", "SE Volume"]],
        ["Screen", ["Screen Size", "Device"]],
        ["Text", ["Text Speed", "Text Entry"]],
        ["Controls", ["Mouse", "Click to move", "Touch controls", "Tap to move"]],
        ["Updates and downloads", ["Updates", "Check for Updates", "Update history", "Download data"]],
        ["Test builds", ["Test Code"]],
        ["Speed", ["Frame rate", "Sprite File Cache"]],
        ["Start-up", ["Skip intro", "Title screen"]],
        ["Files", ["Imported Archives"]],
        ["Advanced", ["Increment Slider by", "Debug Exclusive", "DEBUG"]]]],
      [:modules, "Modules", [180, 120, 90], []],
      [:mods, "Mods", [90, 140, 210], []],
      [:presets, "Presets", [180, 150, 110], []],
    ]

    # Shorter names under their heading (only where the heading says it)
    RENAMES = {
      "Wild Shiny Odds" => "Wild Odds", "Shiny Gamble Odds" => "Gamble Odds",
      "Shiny Trainer Pokemon" => "Trainer Pokémon", "Shiny Colors" => "Colours",
      "PIF's Improved Shinies" => "PIF's Shinies", "Shiny Fuse Dye" => "Fuse Dye",
      "Shiny Filter" => "Filter", "Shiny Icons" => "Icons", "Shiny Animation" => "Animation",
      "PokeRadar+" => "Radar+", "Radar Chain Count" => "Chain Count",
      "Multi-Battle Radar" => "Multi-Battle", "Shiny Cache" => "Shiny Cache",
      "Auto-Battle Shiny Stop" => "Stop on Shiny", "Auto-Battle Switching" => "Switching",
      "Auto-Battle Level Up" => "Level Up", "Auto-Battle New Moves" => "New Moves",
      "Auto-Battle Evolutions" => "Evolutions",
      "Gym Leader teams" => "Leader Teams", "Your Pokémon in gyms" => "Your Pokémon",
      "EBDX Battles" => "EBDX Battles", "EBDX Camera Zoom" => "Camera Zoom",
      "EBDX Stat Stage Icons" => "Stat Stage Icons", "EBDX Own Trainer Animation" => "Own Trainer Animation",
      "Trainer Exp. Boost" => "Trainer EXP Boost", "ExpAll Redistribution" => "EXP All Sharing",
      "No-EVs Mode" => "No EVs", "Max IVs Mode" => "Max IVs", "EVs Train Mode" => "EV Training",
      "Fusion BaseStats" => "Base Stats", "NPC Fusion BaseStats" => "NPC Base Stats",
      "Self-Fusion Stat Boost" => "Self-Fusion Boost", "Dominant Fusion Types" => "Dominant Types",
      "K-Eggs Usage" => "Usage", "K-Eggs Rarity" => "Rarity", "K-Eggs Fusion Odds" => "Fusion Odds",
      "K-Eggs Fusion Pool" => "Fusion Pool", "K-Eggs Rewards" => "Rewards",
      "Improved Pokedex" => "Improved Pokédex", "Dex Evolutions" => "Evolutions",
      "Dex Sprite Select" => "Sprite Select",
      "Import Level" => "Level", "Import De-Evolve" => "De-Evolve", "Import as Egg" => "As Egg",
      "Import Without Deletion" => "Keep the File", "Import Sprite on Import" => "Sprite",
      "Delete on Export" => "Delete After", "Export Sprite on Export" => "Sprite",
      "Letdown Player Only" => "Letdown: You Only",
      "Speed-up Limit (Toggle)" => "Toggle Limit", "Speed-up type" => "Type",
      "Speed-up (Overworld)" => "Overworld", "Speed-up (Battles)" => "Battles",
      "Battle Animations" => "Animations", "Battle Movement" => "Movement", "Battle Type Icons" => "Type Icons",
      "Autogen dex entries" => "Autogen Entries",
    }
  end
end
