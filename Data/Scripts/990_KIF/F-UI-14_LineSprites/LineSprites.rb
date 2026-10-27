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

    # the other species whose sprites this Pokémon may use
    def self.others(pkmn)
      return [] if pkmn.isTripleFusion?
      return line(pkmn.species) - [pkmn.species] unless pkmn.isFusion?
      body = getBodyID(pkmn.species)
      head = getHeadID(pkmn.species, body)
      heads = line(GameData::Species.get(head).species).map { |s| GameData::Species.get(s).id_number }
      bodies = line(GameData::Species.get(body).species).map { |s| GameData::Species.get(s).id_number }
      return bodies.product(heads).map { |b, h| getFusedPokemonIdFromDexNum(b, h) } - [pkmn.species]
    end
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
