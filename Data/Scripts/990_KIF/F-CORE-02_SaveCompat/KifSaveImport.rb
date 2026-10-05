#===============================================================================
# F-CORE-02 – Loading old KIF 0.20.7 saves
#
# KIF 0.20.7 (PIF 6.4.5 based) wrote two copies of the main objects
# (KIF 002_Save data/004_Game_SaveValues.rb):
#   :player / :global_metadata / :bag / :storage_system
#       -> "vanilla" clones with modded items (id_number >= 1000) stripped
#   :kuray_player / :kuray_global_metadata / :kuray_bag / :kuray_storage_system
#       -> the real, complete objects
#   :kuray_pokemon_system_file -> a whole PokemonSystem holding the per-save
#       KIF options
#
# Every save file read goes through SaveData.read_from_file (bootup, load
# screen, slot previews, backups), so it is wrapped here. For a KIF save:
#   1. the :kuray_* objects replace the stripped vanilla ones;
#   2. KIF's per-save options become this port's :kif_save_settings hash
#      (options not ported yet are carried along, see KIF::Options);
#   3. the KIF save keys are dropped, so the next save is a normal port save
#      (which old KIF can still open: its resolve_modded_data rebuilds the
#      :kuray_* keys from the vanilla ones).
# For every save (KIF, PIF 6.4.5 or older port saves):
#   4. PokemonSystem fields that PIF 6.8.2 added are filled with 6.8.2
#      defaults instead of nil; KIF's "Quick Field Moves" (quicksurf) becomes
#      PIF's quickHM.
#   5. Pokémon whose species doesn't exist in this version (KIF-only triple
#      fusions / custom Pokémon, F-DATA-01) are moved out of the party, boxes
#      and Day Care into the :kif_pending save key, so they are not shown or
#      used as placeholder Pikachu. They will be given back when their data is
#      ported. A party is never emptied this way.
# Items: PIF 6.8.2 shows unknown item IDs (KIF K-Eggs etc.) as "UNKNOWN"
# without crashing, and keeps the original ID, so they are left in place and
# become real items again once K-Eggs (F-ITEM-02) is ported.
#
# Old KIF saves are found automatically because Game.ini Title is
# "kurayinfinitefusion" (KIF's save folder, %APPDATA%\kurayinfinitefusion).
#===============================================================================
module KIF
  module SaveImport
    MODDED_KEYS = {
      :kuray_player          => :player,
      :kuray_global_metadata => :global_metadata,
      :kuray_bag             => :bag,
      :kuray_storage_system  => :storage_system
    }

    # Contents of the :kif_pending save key for the loaded file:
    #   :from     => description of the original save ("KIF (PIF 6.4.5)")
    #   :notified => whether the player has been told about the import
    #   :pokemon  => [Pokemon, ...] set aside (unknown species)
    @pending = {}
    class << self
      attr_accessor :pending
    end

    def self.kif_save?(data)
      return false unless data.is_a?(Hash)
      return MODDED_KEYS.keys.any? { |k| data.has_key?(k) } || data.has_key?(:kuray_pokemon_system_file)
    end

    def self.plain_data?(v)
      case v
      when Integer, Float, String, Symbol, true, false, nil then return true
      when Array then return v.all? { |e| plain_data?(e) }
      when Hash  then return v.all? { |k, e| plain_data?(k) && plain_data?(e) }
      end
      return false
    end

    # KIF-specific options stored on a KIF PokemonSystem object, as a Hash.
    def self.settings_from_kif_system(sys)
      hash = {}
      return hash unless sys.is_a?(PokemonSystem)
      base_ivars = PokemonSystem.new.instance_variables
      sys.instance_variables.each do |iv|
        next if base_ivars.include?(iv)
        val = sys.instance_variable_get(iv)
        next if val.nil? || !plain_data?(val)
        hash[iv.to_s.sub("@", "").to_sym] = val
      end
      return hash
    end

    def self.fill_pokemon_system(sys)
      return unless sys.is_a?(PokemonSystem)
      if sys.instance_variable_get(:@quickHM).nil?
        qs = sys.instance_variable_get(:@quicksurf)
        sys.instance_variable_set(:@quickHM, qs) if qs.is_a?(Integer)
      end
      fresh = PokemonSystem.new
      fresh.instance_variables.each do |iv|
        next unless sys.instance_variable_get(iv).nil?
        sys.instance_variable_set(iv, fresh.instance_variable_get(iv))
      end
    end

    def self.species_known?(pkmn)
      sp = pkmn.instance_variable_get(:@species)
      return true if sp.nil?
      return true if sp.to_s.match?(/\AB\d+H\d+\z/) || sp.to_s.include?("_x_") || sp.to_s.include?("/")
      return !GameData::Species::DATA[sp].nil?
    rescue
      return true
    end

    def self.game_data_loaded?
      return defined?(GameData::Species::DATA) && !GameData::Species::DATA.empty?
    rescue
      return false
    end

    # Moves Pokémon with unknown species into pending[:pokemon].
    def self.set_aside_unknown_pokemon(data, pending)
      return 0 unless game_data_loaded?
      moved = 0
      player = data[:player]
      if player && player.respond_to?(:party) && player.party.is_a?(Array)
        party = player.party
        party.dup.each do |pkmn|
          next if !pkmn.is_a?(Pokemon) || species_known?(pkmn)
          next if party.count { |p| p.is_a?(Pokemon) && species_known?(p) } == 0 # never empty the party
          party.delete_if { |p| p.equal?(pkmn) }
          pending[:pokemon] << pkmn
          moved += 1
        end
      end
      storage = data[:storage_system]
      boxes = storage.instance_variable_get(:@boxes) if storage
      if boxes.is_a?(Array)
        boxes.each do |box|
          list = box.instance_variable_get(:@pokemon)
          next unless list.is_a?(Array)
          list.each_with_index do |pkmn, i|
            next if !pkmn.is_a?(Pokemon) || species_known?(pkmn)
            pending[:pokemon] << pkmn
            list[i] = nil
            moved += 1
          end
        end
      end
      global = data[:global_metadata]
      daycare = global.instance_variable_get(:@daycare) if global
      if daycare.is_a?(Array)
        daycare.each do |slot|
          next unless slot.is_a?(Array) && slot[0].is_a?(Pokemon) && !species_known?(slot[0])
          pending[:pokemon] << slot[0]
          slot[0] = nil
          slot[1] = 0
          moved += 1
        end
      end
      return moved
    end

    def self.convert!(data)
      return data unless data.is_a?(Hash) && !data.empty?
      pending = data[:kif_pending]
      pending = {} unless pending.is_a?(Hash)
      pending[:pokemon] ||= []
      if kif_save?(data)
        MODDED_KEYS.each do |kif_key, key|
          data[key] = data[kif_key] if data[kif_key]
          data.delete(kif_key)
        end
        sys = data.delete(:kuray_pokemon_system_file)
        if !data.has_key?(:kif_save_settings)
          settings = settings_from_kif_system(sys)
          # Global KIF options lived on the bootup PokemonSystem; fall back to
          # it for anything the per-save copy lacked.
          settings_from_kif_system(data[:pokemon_system]).each { |k, v| settings[k] = v unless settings.has_key?(k) }
          data[:kif_save_settings] = settings
        end
        pending[:from] = _INTL("KIF (PIF {1})", data[:game_version].to_s)
        pending[:notified] = false
        KIF.log("Converted a KIF save (game_version #{data[:game_version]})")
      end
      fill_pokemon_system(data[:pokemon_system])
      moved = set_aside_unknown_pokemon(data, pending)
      pending[:notified] = false if moved > 0
      data[:kif_pending] = pending if pending.length > 1 || !pending[:pokemon].empty?
      return data
    end

    def self.notice_due?
      return @pending.is_a?(Hash) && @pending.has_key?(:notified) && !@pending[:notified]
    end

    def self.show_notice
      @pending[:notified] = true
      if @pending[:from]
        pbMessage(_INTL("This save was made with {1} and has been converted.", @pending[:from]))
        pbMessage(_INTL("Save the game to keep it in the new format. Options not available yet in this version are kept for later."))
      end
      n = (@pending[:pokemon] || []).length
      if n > 0
        pbMessage(_INTL("{1} Pokémon from this save aren't available in this version yet. They were set aside safely and will come back in a later update.", n))
      end
    end
  end
end

module SaveData
  class << self
    alias kif_read_from_file read_from_file unless method_defined?(:kif_read_from_file)

    def read_from_file(file_path)
      data = kif_read_from_file(file_path)
      begin
        KIF::SaveImport.convert!(data)
      rescue => e
        KIF.log("KIF save conversion failed for #{file_path}: #{e.message}")
      end
      return data
    end
  end
end

# No ensure_class (see :kif_save_settings in 000_Core/002_KIF_Options.rb).
SaveData.register(:kif_pending) do
  save_value { KIF::SaveImport.pending || {} }
  load_value { |value| KIF::SaveImport.pending = value.is_a?(Hash) ? value : {} }
  new_game_value { {} }
end

class Scene_Map
  alias kif_import_update update unless method_defined?(:kif_import_update)

  def update
    kif_import_update
    return unless $scene == self && KIF::SaveImport.notice_due?
    return if $game_temp.message_window_showing || pbMapInterpreterRunning? || $game_player.moving?
    KIF::SaveImport.show_notice
  end
end
