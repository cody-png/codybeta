#===============================================================================
# F-CORE-04 – Mods folder (DemICE)
# Source: KIF 0.20.7
#   999_Main/999_Main.rb:138-146   passModdedPokemon
#   999_Main/999_Main.rb:150, :154 queue reset; Dir["./Mods/*.rb"] loaded
#                                  right after PluginManager.runPlugins
#   201_Kuray/003_KurayPokemonRevamp.rb:2-9  kuray_modqueue (Species.register)
#   ChallengeMode.rb:457           queue applied in GameData.load_all
#
# Every .rb file in the game's Mods folder (next to Game.exe) is loaded once
# at boot, in name order, after all game and port scripts and before the
# game data loads – same moment as KIF. A mod can add or replace species with
#   passModdedPokemon({ :id => ..., :id_number => ..., ... })   # Species hash
# (applied every time the game data loads, after the port's own changes).
#
# Port additions:
#   * The Mods folder is created on first boot if missing (KIF shipped it).
#   * A mod that raises an error is skipped and the error is written to
#     KIF_errorlog.txt instead of stopping the game.
#   * 6.8.2's own scripts don't need KIF's alias guards: mods load once.
#===============================================================================
$POKEMONDATA_QUEUEING ||= []

def passModdedPokemon(data = {})
  return if !data.is_a?(Hash) || data.empty?
  $POKEMONDATA_QUEUEING.push(data)
end

module KIF
  module Mods
    FOLDER = "Mods"
    @loaded = false
    @failed = []
    class << self
      attr_reader :failed
    end

    def self.load_all
      return if @loaded
      @loaded = true
      # Registered here (after every port script) so modded species are
      # applied after the port's own data changes.
      KIF::DataLoad.after_load_all("Modded Pokémon (Mods folder)") { KIF::Mods.apply_species }
      Dir.mkdir(FOLDER) unless File.directory?(FOLDER)
      Dir[File.join(".", FOLDER, "*.rb")].sort.each do |file|
        begin
          load File.expand_path(file)
          KIF.log("Mod loaded: #{File.basename(file)}")
        rescue Exception => e
          raise if e.is_a?(SystemExit) || (defined?(Reset) && e.is_a?(Reset))
          @failed << File.basename(file)
          KIF::CrashLog.write("Mod skipped: #{file}\r\n" + KIF::CrashLog.describe(e)) if defined?(KIF::CrashLog)
          KIF.log("Mod failed: #{File.basename(file)}: #{e.class}: #{e.message}")
        end
      end
    rescue => e
      KIF.log("Mods folder failed: #{e.message}")
    end

    # KIF kuray_modqueue
    def self.apply_species
      return if $POKEMONDATA_QUEUEING.nil? || $POKEMONDATA_QUEUEING.empty?
      $POKEMONDATA_QUEUEING.each do |data|
        begin
          GameData::Species.register(data)
        rescue => e
          KIF.log("Modded Pokémon #{data[:id].inspect} failed: #{e.message}")
        end
      end
    end
  end
end

module PluginManager
  class << self
    alias kif_mods_runPlugins runPlugins unless method_defined?(:kif_mods_runPlugins)

    def runPlugins(*args)
      ret = kif_mods_runPlugins(*args)
      KIF::Mods.load_all
      return ret
    end
  end
end

