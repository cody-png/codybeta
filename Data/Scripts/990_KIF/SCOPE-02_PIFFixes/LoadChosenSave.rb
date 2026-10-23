#===============================================================================
# SCOPE-02 – A save loads with its own Game_System (2026-10-23)
#
# PIF reads a few save values once at start-up, from the NEWEST save file
# (Game.set_up_system -> SaveData.load_bootup_values): :game_system,
# :pokemon_system and the two version stamps. Game.load later only loads the
# values that aren't loaded yet, so loading any other file kept the newest
# file's $game_system, and with it that file's map interpreter. Cody loaded
# File A while File E (newer, saved by the autosave in the middle of the new-
# game intro on map 160) was the newest: File A's map then ran the rest of
# File E's intro script (setStarterEasterEgg, then the Silph Co. cutscene).
# A new game started after the load screen read a save kept it as well.
#
# Fix: Game.load reloads :game_system and the version stamps from the file
# being loaded, and Game.start_new makes a fresh Game_System. $PokemonSystem
# stays as it is: it holds the options (PIF's and KIF's global ones), which
# the load screen's Options already edit before a file is chosen; KIF's
# per-save settings come from :kif_save_settings.
#===============================================================================
module KIF
  module LoadChosenSave
    RELOAD = [:game_system, :essentials_version, :game_version]

    def self.unload(only_in = nil)
      vals = SaveData.instance_variable_get(:@values) || []
      vals.each do |v|
        next unless RELOAD.include?(v.id)
        next if only_in && !only_in.has_key?(v.id)
        v.mark_as_unloaded
      end
    rescue StandardError => e
      KIF.log("Save load: start-up values not reset (#{e.class}: #{e.message})")
    end
  end
end

module Game
  class << self
    alias kif_lcs_load load unless method_defined?(:kif_lcs_load)
    alias kif_lcs_start_new start_new unless method_defined?(:kif_lcs_start_new)

    def load(save_data, *args, &blk)
      KIF::LoadChosenSave.unload(save_data) if save_data.is_a?(Hash)
      return kif_lcs_load(save_data, *args, &blk)
    end

    def start_new(*args, &blk)
      KIF::LoadChosenSave.unload({ :game_system => true })
      return kif_lcs_start_new(*args, &blk)
    end
  end
end
