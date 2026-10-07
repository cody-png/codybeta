#===============================================================================
# C-RAND-01 – Randomizer: Dynamic Route and the PokéRadar (Cody, 2026-10-06)
#   * Dynamic Route (Wild encounters, 5th mode): every time a map is entered,
#     its encounter table is rolled again with Route's rules (Strength range,
#     legendaries, custom sprites, fusions). Leave, and they may be gone.
#   * PokéRadar
#       - its "every Pokémon on this route" list only uses the swap table in
#         Swap mode (PIF used it whenever any Pokémon part was on, so with
#         e.g. only starters randomized the list named Pokémon that never
#         appear and the light could never turn green);
#       - in Dynamic nothing repeats, so the list is empty (route counts as
#         catalogued and the rare can always appear);
#       - radar-only rares are randomized too: Swap = what the rare became,
#         Route = one roll per route, Dynamic Route = a roll per visit,
#         Dynamic = any Pokémon each time. A quest asking for the original
#         rare (pbHasSpecies?) accepts the randomized one;
#       - Oak's aide (Route 24 field research): in Dynamic she can't catalogue
#         anything and finishes the research; in Dynamic Route she catalogues
#         the visit and finds them all gone afterwards. Both research quests
#         complete with their quest points and reward (Cody).
#===============================================================================
module KIF
  module Rand
    def self.dynamic_route?
      return pokemon_parts_on? && data[:wild_mode] == 4
    end

    # Custom sprite list as dex numbers (PIF's own list can hold PIFSprites)
    def self.custom_dex_list
      list = custom_list
      if !@custom_dex || @custom_dex[0] != list.object_id
        @custom_dex = [list.object_id, list.map { |c| dex_of(c) }.select { |d| d > 0 }]
      end
      return @custom_dex[1]
    end

    #---------------------------------------------------------------------------
    # Dynamic Route
    #---------------------------------------------------------------------------
    def self.reroll_tables(encounters, map_id)
      tables = encounters.instance_variable_get(:@encounter_tables)
      return unless tables.is_a?(Hash) && !tables.empty?
      data[:visit] = (data[:visit] || 0) + 1
      bst = get(:wild_bst)
      fusions = sw(SWITCH_RANDOM_WILD_TO_FUSION)
      customs = (fusions && sw(SWITCH_RANDOM_WILD_ONLY_CUSTOMS)) ? custom_dex_list : []
      customs = [] if customs.length < 50
      max = fusions ? PBSpecies.maxValue : NB_POKEMON
      with_memo do
        tables.each_key do |type|
          list = tables[type]
          next unless list.is_a?(Array) && !list.empty?
          tables[type] = randomizePokemonList(list, bst, max, !customs.empty?, customs)
        end
      end
    rescue => e
      KIF.log("Dynamic Route roll failed on map #{map_id}: #{e.class}: #{e.message}")
    end

    #---------------------------------------------------------------------------
    # PokéRadar rares
    #---------------------------------------------------------------------------
    def self.radar_rare_originals
      @radar_rares ||= Settings::POKE_RADAR_ENCOUNTERS.map { |e| e[2] }.uniq
    end

    def self.radar_rare(species, map_id)
      return species unless pokemon_parts_on?
      mode = get(:wild_mode)
      return species if mode == 0
      dex = dex_of(species)
      return species if dex <= 0
      new = nil
      case mode
      when 1
        ensure_dex
        new = dex_of(($PokemonGlobal.psuedoBSTHash || {})[dex])
      when 3
        new = dex_of(dynamic_species(species))
      else
        fusions = sw(SWITCH_RANDOM_WILD_TO_FUSION)
        max = fusions ? PBSpecies.maxValue : NB_POKEMON
        key = (mode == 4) ? [:rare, map_id, dex, data[:visit].to_i] : [:rare, map_id, dex]
        new = with_seed(*key) { dex_of(getNewSpecies(dex, get(:wild_bst), false, max, sw(SWITCH_RANDOM_WILD_LEGENDARIES))) }
      end
      return species unless new && new > 0
      sp = (GameData::Species.get(new).species rescue nil)
      return species unless sp
      seen = (data[:rares_seen] ||= {})
      list = (seen[species] || []) - [sp] + [sp]
      seen[species] = list.last(20)   # Dynamic rolls a new one every time
      return sp
    end

    #---------------------------------------------------------------------------
    # Oak's aide (Route 24): the script that counts the unseen Pokémon
    #---------------------------------------------------------------------------
    AIDE_SCRIPT = "unseen=listPokemonInCurrentRoute(:Land,false,true)"
  end
end

class PokemonEncounters
  alias kif_rand_dr_setup setup unless method_defined?(:kif_rand_dr_setup)

  def setup(map_ID)
    ret = kif_rand_dr_setup(map_ID)
    KIF::Rand.reroll_tables(self, map_ID) if KIF::Rand.dynamic_route?
    return ret
  end
end

class Object
  alias kif_rand_listPokemonInCurrentRoute listPokemonInCurrentRoute unless method_defined?(:kif_rand_listPokemonInCurrentRoute) || private_method_defined?(:kif_rand_listPokemonInCurrentRoute)
  alias kif_rand_listPokeradarRareEncounters listPokeradarRareEncounters unless method_defined?(:kif_rand_listPokeradarRareEncounters) || private_method_defined?(:kif_rand_listPokeradarRareEncounters)
  alias kif_rand_pbHasSpecies pbHasSpecies? unless method_defined?(:kif_rand_pbHasSpecies) || private_method_defined?(:kif_rand_pbHasSpecies)

  # The table already holds what appears unless the swap is applied on top
  # (Swap mode only); see the header
  def listPokemonInCurrentRoute(*args)
    # Dynamic: nothing on a route repeats, so there is nothing to catalogue;
    # the radar treats the route as done (its rares can always show up)
    return [] if KIF::Rand.dynamic?
    sw = $game_switches
    if sw && sw[SWITCH_RANDOM_WILD] && !sw[SWITCH_RANDOM_WILD_AREA] && !sw[SWITCH_WILD_RANDOM_GLOBAL]
      sw[SWITCH_RANDOM_WILD_AREA] = true
      begin
        return kif_rand_listPokemonInCurrentRoute(*args)
      ensure
        sw[SWITCH_RANDOM_WILD_AREA] = false
      end
    end
    return kif_rand_listPokemonInCurrentRoute(*args)
  end

  def listPokeradarRareEncounters
    list = kif_rand_listPokeradarRareEncounters
    return list unless KIF::Rand.pokemon_parts_on?
    map = $game_map ? $game_map.map_id : 0
    return list.map { |sp| KIF::Rand.radar_rare(sp, map) }
  end

  # PIF 013_Items/005_Item_PokeRadar.rb pbPokeRadarGetEncounter, with the
  # radar-only species randomized
  alias kif_rand_pbPokeRadarGetEncounter pbPokeRadarGetEncounter unless method_defined?(:kif_rand_pbPokeRadarGetEncounter) || private_method_defined?(:kif_rand_pbPokeRadarGetEncounter)

  def pbPokeRadarGetEncounter(rarity = 0)
    return kif_rand_pbPokeRadarGetEncounter(rarity) unless KIF::Rand.pokemon_parts_on?
    if rarity > 0
      map = $game_map.map_id
      array = Settings::POKE_RADAR_ENCOUNTERS.select { |enc| enc[0] == map && GameData::Species.exists?(enc[2]) }
      if array.length > 0 && listPokemonInCurrentRoute($PokemonEncounters.encounter_type, false, true).length == 0
        rnd = rand(100)
        array.each do |enc|
          rnd -= enc[1]
          next if rnd >= 0
          level = (enc[4] && enc[4] > enc[3]) ? rand(enc[3]..enc[4]) : enc[3]
          return [KIF::Rand.radar_rare(enc[2], map), level]
        end
      end
    end
    return $PokemonEncounters.choose_wild_pokemon($PokemonEncounters.encounter_type, rarity + 1)
  end

  # "Did you catch a Buneary?" accepts what the rare became
  def pbHasSpecies?(species, *args)
    return true if kif_rand_pbHasSpecies(species, *args)
    return false unless (species.is_a?(Symbol) || species.is_a?(String)) && $PokemonGlobal && KIF::Rand.pokemon_parts_on?
    sym = species.to_sym
    return false unless KIF::Rand.radar_rare_originals.include?(sym)
    alts = (KIF::Rand.data[:rares_seen] || {})[sym] || []
    return alts.any? { |a| a != sym && kif_rand_pbHasSpecies(a, *args) }
  end
end

class Interpreter
  alias kif_rand_execute_script execute_script unless method_defined?(:kif_rand_execute_script)

  def execute_script(script)
    if script.to_s.start_with?(KIF::Rand::AIDE_SCRIPT) && kif_rand_aide?
      return true
    end
    return kif_rand_execute_script(script)
  end

  # Returns true when the aide's research was finished here (event ends)
  def kif_rand_aide?
    r = KIF::Rand
    return false unless $game_switches && r.pokemon_parts_on?
    mode = r.get(:wild_mode)
    return false unless mode == 3 || mode == 4
    if mode == 4
      unseen = listPokemonInCurrentRoute(:Land, false, true)
      return false unless unseen.empty?   # still cataloguing this visit
      lines = [_INTL("That's it, I've recorded every Pokémon on this route!"),
               _INTL("...But when I came back from reporting my findings to Professor Oak, none of the Pokémon from before were here anymore."),
               _INTL("This route changes every time someone sets foot in it! I'll have to tell the Professor.")]
    else
      lines = [_INTL("The Pokémon here are out of control!"),
               _INTL("I can't seem to get anything I encounter to show up more than once!"),
               _INTL("There's no way to catalogue a route like this. I'll report it to Professor Oak as it is.")]
    end
    lines.each do |l|
      pbCallBub(2, @event_id) rescue nil
      pbMessage(l)
    end
    finishQuest("cerulean_field_2")
    pbCallBub(2, @event_id) rescue nil
    pbMessage(_INTL("Thanks for helping me out on the field today, \\PN. You can have this, it's a small gift from me."))
    pbAcceptNewQuest("cerulean_field_3", 20, false) unless isQuestAlreadyAccepted?("cerulean_field_3")
    finishQuest("cerulean_field_3")
    Kernel.pbReceiveItem(:ULTRABALL, 5)
    $game_self_switches[[@map_id, @event_id, "D"]] = true
    $game_map.need_refresh = true
    @index = @list.size - 2 if @list   # end the event after this
    return true
  rescue => e
    KIF.log("Randomizer aide quest failed: #{e.class}: #{e.message} (#{e.backtrace.first})")
    return false
  end
end
