#===============================================================================
# F-UI-14 – Evolution line sprites (new in KIF, player request, 2026-10-26)
# Not in KIF 0.20.7 or PIF 6.8.2.
#
# Summary > Pokédex > Sprites lists the Pokémon's own sprites only. Here it
# also lists the sprites of the rest of its evolution line, so one Charizard
# can wear Charmeleon's sprite (a fusion: every head x body pair of its two
# lines, e.g. B6H9 also gets B4H7, B5H8...). Picking one sets only that
# Pokémon's pif_sprite: PIF's swap would also set the whole species' sprite
# (alt_sprite_substitutions) to the other species' sprite, so that entry is
# put back. PIF already draws a pif_sprite of another species everywhere
# (it does so for its shared-sprite species).
#   Only with Random Sprites On (PIF ignores per-Pokémon sprites when Off).
#   The main Pokédex and the catch prompt (a species is passed) are unchanged.
#   Evolving still picks a new sprite of the new species (PIF).
# A fusion also gets the swapped order (player request, 2026-10-27): head and
# body swapped for itself and every line pair, and the unfused sprites of both
# lines. A label over the sprites names the group (This fusion, Swapped,
# Evolution line, Unfused). Only the look changes. When the species changes
# (unfuse, reverse, fuse) a pick that isn't one of the new species' is dropped.
#===============================================================================
module KIF
  module LineSprites
    # ancestors, the species, then what it evolves into (its own branch only)
    def self.line(sp)
      data = GameData::Species.get(sp)
      ret = [data.species]
      cur = data
      10.times do
        prev = cur.get_previous_species
        break if prev == cur.species
        ret.unshift(prev)
        cur = GameData::Species.get(prev)
      end
      return (ret + data.get_family_evolutions.map { |e| e[1] }).uniq
    end

    def self.nums(dex)
      line(GameData::Species.get(dex).species).map { |s| GameData::Species.get(s).id_number }
    end

    # the other species whose sprites this Pokémon (or species) may use, in
    # list order: swapped, the line's fusions (both orders), unfused
    def self.others(pkmn)
      sp = pkmn.is_a?(Pokemon) ? pkmn.species : GameData::Species.get(pkmn).species
      dex = GameData::Species.get(sp).id_number
      return [] if isTripleFusion?(dex)
      return line(sp) - [sp] unless isFusion(dex)
      body = getBodyID(sp)
      head = getHeadID(sp, body)
      pairs = nums(body).product(nums(head))
      ret = ([[head, body]] + pairs + pairs.map(&:reverse)).map { |b, h| getFusedPokemonIdFromDexNum(b, h) }
      ret += (nums(head) + nums(body)).map { |n| GameData::Species.get(n).species }
      return ret.uniq - [sp]
    end

    # the label of a listed sprite's group
    def self.group(pkmn, sp)
      own = pkmn.species
      fusion = isSpeciesFusion(own)
      return _INTL("Unfused") if fusion && !isSpeciesFusion(sp)
      return _INTL("Swapped") if fusion && sp != own && sp == GameData::Species.get(reverseFusionSpecies(own)).species
      return _INTL("Evolution line") if sp != own && others(pkmn).include?(sp)
      return fusion ? _INTL("This fusion") : _INTL("This Pokémon")
    end
  end
end

class Pokemon
  alias kif_ls_species_set species= unless method_defined?(:kif_ls_species_set) || private_method_defined?(:kif_ls_species_set)

  # a pick of another species stays only while it is one the new species may use
  def species=(species_id)
    old = @species
    ret = kif_ls_species_set(species_id)
    ps = @pif_sprite
    if ps && old != @species && ps.species != @species
      @pif_sprite = nil unless (KIF::LineSprites.others(@species).include?(ps.species) rescue false)
    end
    return ret
  end
end

class PokemonPokedexInfo_Scene
  alias kif_ls_pbGetAvailableForms pbGetAvailableForms unless method_defined?(:kif_ls_pbGetAvailableForms) || private_method_defined?(:kif_ls_pbGetAvailableForms)

  def pbGetAvailableForms(species = nil)
    ret = kif_ls_pbGetAvailableForms(species)
    return ret unless species.nil? && @pokemon && !@pokemon.egg? && $PokemonSystem.random_sprites
    begin
      KIF::LineSprites.others(@pokemon).each { |sp| ret += kif_ls_pbGetAvailableForms(sp) }
      ret = ret.uniq { |s| [s.species, s.alt_letter] }
    rescue StandardError => e
      KIF.log("Line sprites: #{e.class}: #{e.message}")
    end
    return ret
  end

  alias kif_ls_set_displayed_to_current_alt set_displayed_to_current_alt unless method_defined?(:kif_ls_set_displayed_to_current_alt) || private_method_defined?(:kif_ls_set_displayed_to_current_alt)

  # PIF matches the letter only: with line-mates listed, also match the species
  def set_displayed_to_current_alt(alts)
    cur = @pokemon && @pokemon.pif_sprite
    i = cur && alts.index { |s| s.species == cur.species && s.alt_letter == cur.alt_letter }
    return @selected_index = @selected_index + i if i
    return kif_ls_set_displayed_to_current_alt(alts)
  end

  alias kif_ls_pbChooseAlt pbChooseAlt unless method_defined?(:kif_ls_pbChooseAlt) || private_method_defined?(:kif_ls_pbChooseAlt)

  # Blacklist mode (Down on the Sprites page) sets which sprites the species
  # gets at random, by letter: it lists PIF's own sprites only (Up from there
  # picks from those too, until the page is opened again)
  def pbChooseAlt(*args)
    full = @available
    mates = (@selecting_blacklist && @pokemon && full) ? KIF::LineSprites.others(@pokemon) : []
    own = full.reject { |s| mates.include?(s.species) } unless mates.empty?
    return kif_ls_pbChooseAlt(*args) if own.nil? || own.empty? || own.length == full.length
    sel = full[@selected_index]
    begin
      @available = own
      @selected_index = own.index { |s| s.equal?(sel) } || 0
      update_displayed
      return kif_ls_pbChooseAlt(*args)
    ensure
      sel = @available[@selected_index]
      @available = full
      @selected_index = full.index { |s| s.equal?(sel) } || 0
      update_displayed
    end
  end

  alias kif_ls_swap_main_sprite swap_main_sprite unless method_defined?(:kif_ls_swap_main_sprite) || private_method_defined?(:kif_ls_swap_main_sprite)

  def swap_main_sprite(*args)
    pick = @selected_pif_sprite
    unless @pokemon && pick && KIF::LineSprites.others(@pokemon).include?(pick.species)
      return kif_ls_swap_main_sprite(*args)
    end
    subs = $PokemonSystem.alt_sprite_substitutions
    id = get_substitution_id(dexNum(@species))
    had = subs.has_key?(id)
    old = subs[id]
    ret = kif_ls_swap_main_sprite(*args)
    had ? subs[id] = old : subs.delete(id)   # a line-mate's sprite is for this Pokemon only
    return ret
  end
end

class PokemonPokedexInfo_Scene
  alias kif_ls_update_displayed update_displayed unless method_defined?(:kif_ls_update_displayed) || private_method_defined?(:kif_ls_update_displayed)

  # names the selected sprite's group over it (Summary, with other species listed)
  def update_displayed(*args)
    ret = kif_ls_update_displayed(*args)
    begin
      ov = @creditsOverlay
      sel = @available && @available[@selected_index]
      return ret unless @pokemon && sel && ov && !ov.disposed?
      return ret if @available.all? { |s| s.species == @pokemon.species }
      ov.fill_rect(140, 36, 232, 56, Color.new(0, 0, 0, 0))
      pbDrawTextPositions(ov, [[KIF::LineSprites.group(@pokemon, sel.species), Graphics.width / 2, 50, 2,
                                Color.new(88, 88, 80), Color.new(168, 184, 184)]])
    rescue StandardError => e
      KIF.log("Line sprites: #{e.class}: #{e.message}")
    end
    return ret
  end
end
