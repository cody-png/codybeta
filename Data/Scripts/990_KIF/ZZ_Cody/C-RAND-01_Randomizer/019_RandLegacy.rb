#===============================================================================
# C-RAND-01 – A world made on PIF 6.8.2 keeps its picks on PIF 6.9 (2026-11-02)
#   PIF 6.9 changed how the randomizer's picks are made (the Pokédex swap's
#   widening, the custom-sprite picker, the custom sprite list itself), so the
#   same seed would now make another game. A save is stamped with the picking
#   rules its world was made with (kif_rand[:alg]):
#     ALG_LEGACY (1)  a save randomized on 6.8.2 / KIF 1.x: PIF 6.8.2's rules
#                     and the sprite list KIF 1.x shipped, so the Pokédex swap,
#                     routes, trainers, gym teams, trades and Dynamic Route
#                     come out as they did
#     ALG_NOW (2)     a new game, or a legacy save given a new seed: PIF 6.9
#   Stamped when a save is loaded (a save with a world made before this build
#   is legacy) and at a new game. A save without a stamp counts as ALG_NOW.
#   Legendary check for numbers: KIF's own (PIF 6.9's table misreads some
#   fusion numbers), for every save.
#===============================================================================
module KIF
  module Rand
    ALG_LEGACY = 1
    ALG_NOW = 2
    LEGACY_LIST_FILE = "Data/KIF/legacy_custom_sprites.dat"

    @legacy_list_depth = 0
    @loading = 0
    class << self
      attr_accessor :legacy_list_depth, :loading
    end

    def self.alg
      a = data[:alg]
      return a if a == ALG_LEGACY || a == ALG_NOW
      # (the save being loaded: the first pick may come before Game.load is through)
      stamp_loaded if @loading > 0
      a = data[:alg]
      return (a == ALG_LEGACY || a == ALG_NOW) ? a : ALG_NOW
    end

    def self.legacy?
      return alg == ALG_LEGACY
    end

    # Is there a world made by an earlier build in the save?
    def self.made_world?
      return true if $game_switches && $game_switches[SWITCH_RANDOMIZED_AT_LEAST_ONCE]
      pg = $PokemonGlobal
      return false unless pg
      return true if pg.psuedoBSTHash && !identity_dex?(pg.psuedoBSTHash)
      return true if pg.randomTrainersHash.is_a?(Hash) && !pg.randomTrainersHash.empty?
      return !!(data[:species] || data[:ent_layout])
    end

    # A save being loaded: keep its stamp; a world made before the stamps existed is legacy
    def self.stamp_loaded
      return unless $PokemonGlobal
      a = data[:alg]
      return if a == ALG_LEGACY || a == ALG_NOW
      data[:alg] = made_world? ? ALG_LEGACY : ALG_NOW
    end

    def self.stamp_new
      data[:alg] = ALG_NOW if $PokemonGlobal
    end

    # The custom sprite list of the 6.8.2 builds, as getCustomSpeciesList returned it (species numbers in file order)
    def self.legacy_list
      return @legacy_list if @legacy_list
      @legacy_list = begin
        raw = Zlib::Inflate.inflate(File.binread(LEGACY_LIST_FILE))
        raw.unpack("w*")
      rescue => e
        KIF.log("Legacy sprite list not read (#{e.class}: #{e.message}); the current list is used")
        false
      end
      return @legacy_list
    end

    # In a legacy save the randomizer's picks use the legacy list (nil: use the current one)
    def self.legacy_list_for_picks
      return nil unless legacy? && (@seeded > 0 || @legacy_list_depth > 0)
      l = legacy_list
      return l ? l : nil
    end

    #---------------------------------------------------------------------------
    # PIF 6.8.2's picking rules, unchanged (randomizer.rb, randomizer gym leader edit.rb)
    #---------------------------------------------------------------------------
    module Legacy
      def self.bst_hash(poke_list, bst_range, show_progress = true)
        bst_hash = Hash.new
        for i in 1..NB_POKEMON
          KIF::Rand.progress(_INTL("Shuffling Pokémon..."), i.to_f / NB_POKEMON) if show_progress && KIF::Rand.seeded > 0 && i % 25 == 0
          baseStats = getBaseStatsFormattedForRandomizer(i)
          statsTotal = getStatsTotal(baseStats)
          max_bst_allowed = statsTotal + bst_range
          min_bst_allowed = statsTotal - bst_range
          playShuffleSE(i)
          random_poke = poke_list.sample
          random_poke_bst = getStatsTotal(getBaseStatsFormattedForRandomizer(random_poke))
          j = 0
          includeLegendaries = $game_switches[SWITCH_RANDOM_WILD_LEGENDARIES]
          current_species = GameData::Species.get(i).id
          random_poke_species = GameData::Species.get(random_poke).id
          while (random_poke_bst <= min_bst_allowed || random_poke_bst >= max_bst_allowed) || !legendaryOk(current_species, random_poke_species, includeLegendaries)
            random_poke = poke_list.sample
            random_poke_species = GameData::Species.get(random_poke).id
            random_poke_bst = getStatsTotal(getBaseStatsFormattedForRandomizer(random_poke))
            j += 1
            if j % 5 == 0
              min_bst_allowed -= 1
              max_bst_allowed += 1
            end
          end
          bst_hash[i] = random_poke
        end
        return bst_hash
      end

      # (the egg group flag 6.9 adds is not used)
      def self.new_species(oldSpecies, bst_range = 50, ignoreRivalPlaceholder = false, maxDexNumber = PBSpecies.maxValue, includeLegendaries = true, *_egg_group)
        oldSpecies_dex = dexNum(oldSpecies)
        return oldSpecies_dex if (oldSpecies_dex == Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES && !ignoreRivalPlaceholder)
        return oldSpecies_dex if oldSpecies_dex >= Settings::ZAPMOLCUNO_NB
        if $game_switches[SWITCH_LEGENDARY_MODE]
          new_species = convert_species_to_legendary(oldSpecies)
          return dexNum(new_species)
        end
        newspecies_dex = rand(maxDexNumber - 1) + 1
        i = 0
        while bstNotOk(newspecies_dex, oldSpecies_dex, bst_range) || !(legendaryOk(oldSpecies_dex, newspecies_dex, includeLegendaries))
          newspecies_dex = rand(maxDexNumber - 1) + 1
          i += 1
          bst_range += 5 if i % 10 == 0
        end
        return newspecies_dex
      end

      # (the egg group flag and the caches 6.9 adds are not used)
      def self.new_custom_species(oldSpecies, customSpeciesList, bst_range = 50, ignoreRivalPlaceholder = false, includeLegendaries = true, *_rest)
        if $game_switches[SWITCH_LEGENDARY_MODE]
          new_species = convert_species_to_legendary(oldSpecies)
          return dexNum(new_species)
        end
        oldSpecies_dex = dexNum(oldSpecies)
        return oldSpecies_dex if (oldSpecies_dex == Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES && !ignoreRivalPlaceholder)
        return oldSpecies_dex if oldSpecies_dex >= Settings::ZAPMOLCUNO_NB
        return oldSpecies_dex if customSpeciesList.nil? || customSpeciesList.empty?
        i = rand(customSpeciesList.length - 1) + 1
        n = 0
        newspecies_dex = customSpeciesList[i]
        while bstNotOk(newspecies_dex, oldSpecies_dex, bst_range) || !(legendaryOk(oldSpecies_dex, newspecies_dex, includeLegendaries))
          i = rand(customSpeciesList.length - 1)
          newspecies_dex = customSpeciesList[i]
          n += 1
          bst_range += 5 if n % 10 == 0
        end
        return newspecies_dex
      end
    end

    # KIF's own legendary check for a plain number: a fusion's head and body
    # are read from the number (PIF 6.9's table misreads the numbers that are
    # exact multiples of NB_POKEMON). Triple fusions and anything else: PIF's.
    def self.fast_legendary(dex)
      return nil unless dex.is_a?(Integer) && dex >= 1 && defined?(NB_POKEMON) && defined?(LEGENDARIES_LIST)
      nb = NB_POKEMON
      return nil if dex > nb * nb + nb
      if @fast_legend_token != KIF::Perf.token || @fast_legend_list != LEGENDARIES_LIST.hash
        @fast_legend_token = KIF::Perf.token
        @fast_legend_list = LEGENDARIES_LIST.hash
        @fast_legend = {}
        LEGENDARIES_LIST.each do |sym|
          d = (GameData::Species.try_get(sym) rescue nil)
          @fast_legend[d.id_number] = true if d && d.id_number <= nb
        end
      end
      return @fast_legend[dex] ? true : false if dex <= nb
      body = (dex % nb == 0) ? dex / nb - 1 : dex / nb
      head = dex - body * nb
      head = nb if head == 0
      return (@fast_legend[body] || @fast_legend[head]) ? true : false
    end
  end
end

class Object
  alias kif_legacy_get_randomized_bst_hash get_randomized_bst_hash unless method_defined?(:kif_legacy_get_randomized_bst_hash) || private_method_defined?(:kif_legacy_get_randomized_bst_hash)
  alias kif_legacy_getNewSpecies getNewSpecies unless method_defined?(:kif_legacy_getNewSpecies) || private_method_defined?(:kif_legacy_getNewSpecies)
  alias kif_legacy_getNewCustomSpecies getNewCustomSpecies unless method_defined?(:kif_legacy_getNewCustomSpecies) || private_method_defined?(:kif_legacy_getNewCustomSpecies)
  alias kif_legacy_getCustomSpeciesList getCustomSpeciesList unless method_defined?(:kif_legacy_getCustomSpeciesList) || private_method_defined?(:kif_legacy_getCustomSpeciesList)

  def get_randomized_bst_hash(*args)
    return KIF::Rand::Legacy.bst_hash(*args) if KIF::Rand.legacy?
    return kif_legacy_get_randomized_bst_hash(*args)
  end

  def getNewSpecies(*args)
    return KIF::Rand::Legacy.new_species(*args) if KIF::Rand.legacy?
    return kif_legacy_getNewSpecies(*KIF::Rand.egg_args(args))
  end

  def getNewCustomSpecies(*args)
    return KIF::Rand::Legacy.new_custom_species(*args) if KIF::Rand.legacy?
    return kif_legacy_getNewCustomSpecies(*KIF::Rand.egg_args(args))
  end

  # Only the randomizer's own picks see the old list; sprite features keep the current one
  def getCustomSpeciesList(*args)
    l = KIF::Rand.legacy_list_for_picks
    return l if l
    return kif_legacy_getCustomSpeciesList(*args)
  end
end

# PIF's custom trainer path reads the list before its seeded shuffle starts
class << Kernel
  alias kif_legacy_pbShuffleTrainersCustom pbShuffleTrainersCustom unless method_defined?(:kif_legacy_pbShuffleTrainersCustom)

  def pbShuffleTrainersCustom(*args)
    KIF::Rand.legacy_list_depth += 1
    begin
      return kif_legacy_pbShuffleTrainersCustom(*args)
    ensure
      KIF::Rand.legacy_list_depth -= 1
    end
  end
end
