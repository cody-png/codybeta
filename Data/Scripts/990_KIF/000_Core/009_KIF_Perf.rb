#===============================================================================
# KIF::Perf – overlay-side performance fixes for base PIF 6.8.2 behaviour
# (base files are never edited).
#
# Pokemon#species_data for a fusion: 6.8.2 (001_Pokemon.rb:252-255) calls
# GameData::Species.get(@species) on every read, and for fused ids
# (010_Data/001_GameData.rb:37-53) that builds a brand-new FusedSpecies each
# time: merged movesets, tutor/egg moves, evolutions, name, dex entry, ...
# Pokemon#type1/type2/baseStats/calc_stats/moves checks all go through it,
# so a fusion in the party rebuilt its species data hundreds of times per
# screen and the AI thousands of times per turn.
# Here the built object is kept on the Pokémon and reused while its species
# is unchanged and the game data hasn't been reloaded (boot/compile token).
# Non-fused species keep 6.8.2's lookup (DATA already returns one object).
# A Pokémon loaded from a save carries an old token, so it rebuilds once.
#===============================================================================
module KIF
  module Perf
    @token = rand(2**30) + 1

    def self.token; @token; end
    def self.bump_token; @token = rand(2**30) + 1; end
  end
end

module KIF
  module DataLoad
    class << self
      alias kif_perf_run run unless method_defined?(:kif_perf_run)

      def run
        KIF::Perf.bump_token
        kif_perf_run
      end
    end
  end
end

class Pokemon
  alias kif_perf_species_data species_data unless method_defined?(:kif_perf_species_data)

  def species_data
    sd = @species_data
    if sd && @kif_sd_token == KIF::Perf.token && sd.species == @species
      return sd
    end
    sd = kif_perf_species_data
    @kif_sd_token = KIF::Perf.token
    return sd
  end
end

#-------------------------------------------------------------------------------
# Pokédex list (016_UI/Pokedex/003_UI_Pokedex_Main.rb)
#   * pbRefresh runs on every cursor move and asks for the Seen/Owned totals;
#     each total walks every fusion slot (~330,000 entries, Player::Pokedex
#     #count_dex), so scrolling dropped frames. The totals can't change while
#     the list is open, so they're counted once per visit (again after an
#     entry page closes).
#   * setIconBitmap keeps a copy of every sprite looked at and never frees
#     them; they're freed when the Pokédex closes.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    @dex_counts = nil
    class << self
      attr_accessor :dex_counts
    end
  end
end

class Player < Trainer
  class Pokedex
    alias kif_perf_seen_count seen_count unless method_defined?(:kif_perf_seen_count)
    alias kif_perf_owned_count owned_count unless method_defined?(:kif_perf_owned_count)

    def seen_count(dex = -1)
      c = KIF::Perf.dex_counts
      return kif_perf_seen_count(dex) unless c && c[:dex].equal?(self)
      key = [:seen, dex]
      return c[key] if c.key?(key)
      return c[key] = kif_perf_seen_count(dex)
    end

    def owned_count(dex = -1)
      c = KIF::Perf.dex_counts
      return kif_perf_owned_count(dex) unless c && c[:dex].equal?(self)
      key = [:owned, dex]
      return c[key] if c.key?(key)
      return c[key] = kif_perf_owned_count(dex)
    end
  end
end

class PokemonPokedex_Scene
  alias kif_perf_pbPokedex pbPokedex unless method_defined?(:kif_perf_pbPokedex)
  alias kif_perf_pbDexEntry pbDexEntry unless method_defined?(:kif_perf_pbDexEntry)
  alias kif_perf_pbEndScene pbEndScene unless method_defined?(:kif_perf_pbEndScene)

  def pbPokedex(*args)
    old = KIF::Perf.dex_counts
    KIF::Perf.dex_counts = { :dex => $Trainer.pokedex }
    begin
      return kif_perf_pbPokedex(*args)
    ensure
      KIF::Perf.dex_counts = old
    end
  end

  def pbDexEntry(*args)
    c = KIF::Perf.dex_counts
    c.delete_if { |k, _| k != :dex } if c
    return kif_perf_pbDexEntry(*args)
  end

  def pbEndScene(*args)
    ret = kif_perf_pbEndScene(*args)
    if @sprites_cache
      @sprites_cache.each_value { |bmp| bmp.dispose if bmp && !bmp.disposed? rescue nil }
      @sprites_cache = nil
    end
    return ret
  end
end

#===============================================================================
# Sprite credits lookups. 6.8.2 reads the whole Sprite_Credits.csv (~236,000
# lines) every time it picks a sprite letter (FusionSprites.rb:499,
# map_alt_sprite_letters_for_pokemon) or looks up an artist
# (SpriteCreditsUtils.rb:453, getSpriteCredits): ~90 ms each. With Random
# sprites on that happens for every Pokémon drawn (each Pokédex step, each
# battler, each fusion preview), and once per new species otherwise.
# Here the file is read once into lines grouped by sprite name without its
# letters ("25", "25a", "25b" -> "25"); each lookup then runs PIF's own
# per-line code over that group only, so the results are the same. The group
# is re-read when the file changes (size/time), e.g. after a credits download.
#===============================================================================
module KIF
  module Perf
    module Credits
      @lines = nil
      @stamp = nil

      def self.stamp
        st = File.stat(Settings::CREDITS_FILE_PATH)
        return [st.size, st.mtime.to_f]
      rescue SystemCallError
        return nil
      end

      # Lines (with their newline) whose sprite name is base + letters.
      def self.group(base)
        s = stamp
        return nil unless s
        if !@lines || @stamp != s
          @lines = nil
          idx = {}
          File.foreach(Settings::CREDITS_FILE_PATH) do |line|
            name = line[/\A[^,\r\n]*/].strip
            next if name.empty?
            key = name.sub(/[a-zA-Z]+\z/, "")
            (idx[key] ||= +"") << line
          end
          @lines = idx
          @stamp = s
        end
        return @lines[base] || ""
      rescue StandardError
        @lines = nil
        return nil
      end

      def self.reset
        @lines = nil
        @stamp = nil
      end
    end
  end
end

class Object
  unless private_method_defined?(:kif_perf_map_alt_sprite_letters_for_pokemon)
    alias kif_perf_map_alt_sprite_letters_for_pokemon map_alt_sprite_letters_for_pokemon
    alias kif_perf_getSpriteCredits getSpriteCredits
  end
  private

  def map_alt_sprite_letters_for_pokemon(spriteName)
    name = spriteName.to_s
    lines = name =~ /[a-zA-Z]\z/ ? nil : KIF::Perf::Credits.group(name)
    return kif_perf_map_alt_sprite_letters_for_pokemon(spriteName) unless lines
    alt_sprites = {}
    lines.each_line do |line|
      row = line.strip.split(',')
      sprite_name = row[0]
      next unless sprite_name && sprite_name.start_with?(name)
      suffix = sprite_name[name.length..-1] || ""
      if suffix.empty?
        alt_sprites[""] = row[2]
        next
      end
      next unless suffix.match?(/\A[a-zA-Z]+\z/)
      alt_sprites[suffix] = row[2]
    end
    return alt_sprites
  end

  def getSpriteCredits(spriteName)
    name = spriteName.to_s
    lines = KIF::Perf::Credits.group(name.sub(/[a-zA-Z]+\z/, ""))
    return kif_perf_getSpriteCredits(spriteName) unless lines
    lines.each_line do |line|
      row = line.split(',')
      return row[1] if row[0] == spriteName
    end
    return nil
  end
end
