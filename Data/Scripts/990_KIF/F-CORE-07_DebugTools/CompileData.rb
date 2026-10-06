#===============================================================================
# F-CORE-07 – Decompile / recompile the game data (Reïzod)
# Source: KIF 0.20.7 020_Debug/003_Debug menus/002_Debug_MenuCommands.rb:1093-1120
#   ("Compile Data", "Write Data" under Debug > Other options...)
#
# Debug > Other options...
#   "Write Data"   – writes all game data (Data/*.dat) out as editable PBS
#                    text files in the PBS folder ("decompile").
#   "Compile Data" – compiles the PBS folder back into Data/*.dat
#                    ("recompile"), using PIF 6.8.2's own compiler (which also
#                    converts trainer events on the maps, as in KIF).
#
# 6.8.2 adaptations:
#   * 6.8.2 ships without a PBS folder and its .dat files are encrypted; its
#     compiler writes them encrypted again, so the game reads them as usual.
#   * Both ask for confirmation and remind you to back up the Data folder
#     first (port addition): 6.8.2's writer doesn't write every data file
#     (e.g. the Remix/Expert trainer lists), and compiling replaces Data
#     files.
#   * Not ported: KIF's restored in-game PBS editors (Edit Wild Encounters,
#     Trainer Types, Individual Trainers, Items, Pokémon, Regional Dexes) –
#     only decompile/recompile was asked for (Cody, 2026-10-05).
#===============================================================================
if defined?(DebugMenuCommands)
  DebugMenuCommands.register("kif_writedata", {
    "parent"      => "othermenu",
    "name"        => _INTL("Write Data"),
    "description" => _INTL("Write all data to the PBS folder."),
    "always_show" => true,
    "effect"      => proc {
      next unless pbConfirmMessage(_INTL("Write all game data to the PBS folder? Existing PBS files are replaced."))
      msgwindow = pbCreateMessageWindow
      Dir.mkdir("PBS") rescue nil unless safeIsDirectory?("PBS")
      pbMessageDisplay(msgwindow, _INTL("Writing all data..."), false)
      Graphics.update
      begin
        Compiler.write_all
        pbMessageDisplay(msgwindow, _INTL("All game data was written."))
      rescue => e
        pbMessageDisplay(msgwindow, _INTL("Writing failed: {1}", e.message))
      end
      pbDisposeMessageWindow(msgwindow)
    }
  })

  DebugMenuCommands.register("kif_compiledata", {
    "parent"      => "othermenu",
    "name"        => _INTL("Compile Data"),
    "description" => _INTL("Fully compile all data."),
    "always_show" => true,
    "effect"      => proc {
      next unless pbConfirmMessageSerious(_INTL("Compile the PBS folder into the game data? Back up the Data folder first."))
      msgwindow = pbCreateMessageWindow
      begin
        Compiler.compile_all(true) { |msg| pbMessageDisplay(msgwindow, msg, false); echoln(msg) }
        pbMessageDisplay(msgwindow, _INTL("All game data was compiled."))
      rescue => e
        pbMessageDisplay(msgwindow, _INTL("Compiling failed: {1}", e.message))
      end
      pbDisposeMessageWindow(msgwindow)
    }
  })
end
