#===============================================================================
# F-POKE-01 – Evolution Lock ("EvoLock")
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon.rb:65, :339-349      (kuray_no_evo / kuray_no_evo?)
#   016_UI/015_UI_Options.rb:2292-2297            ("Enable EvoLock", default Off)
#   016_UI/017_UI_PokemonStorage.rb:1855-1856, :2449-2464 (PC lock / unlock)
#   Blocks in: 001_Overworld_BattleStarting.rb:804 (pbEvolutionCheck),
#     001_Item_Utilities.rb:175 (Rare Candy level up), 002_Item_Effects.rb:361
#     (evolution stones), 005_UI_Trading.rb:184 (trade), New Items effects.rb
#     :493/:1357 (pbForceEvo), :1373 (pbForceDevo), PokemonFusion.rb:911
#     (fusing clears the lock).
#
# A locked Pokémon never evolves while the option is On, like an Everstone it
# doesn't have to hold. With the option Off, locks are kept but ignored and the
# PC entry is hidden (same as KIF).
#
# 6.8.2 adaptation: KIF added the check at every caller. Here it sits in
# Pokemon#check_evolution_internal, which every 6.8.2 evolution check goes
# through (level up after battle, Rare Candy, stones, trade, the party
# "Evolve" command), plus pbForceEvo (Mist Stone). The KIF Devolution Spray
# (pbForceDevo) comes with F-POKE-02 and must respect kif_evo_locked?.
# Unfusing in 6.8.2 restores the clones made at fusion time, so each part gets
# back its own pre-fusion lock.
#===============================================================================
KIF::Options.define(:kuray_no_evo, 0, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Enable EvoLock"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kuray_no_evo },
                 proc { |value| $PokemonSystem.kuray_no_evo = value },
                 [_INTL("Can't EvoLock a Pokemon without holding everstone"),
                  _INTL("Can EvoLock Pokemons in the PC")])
}

class Pokemon
  attr_writer :kuray_no_evo

  def kuray_no_evo
    return @kuray_no_evo
  end

  # KIF: 1 = locked, 0 = not locked (nil on Pokémon that never had it set)
  def kuray_no_evo?
    return @kuray_no_evo || 0
  end

  def kif_evo_locked?
    return false unless $PokemonSystem && $PokemonSystem.kuray_no_evo == 1
    return kuray_no_evo? == 1
  end

  alias kif_evolock_check_evolution_internal check_evolution_internal unless method_defined?(:kif_evolock_check_evolution_internal)

  def check_evolution_internal(*args, &block)
    return nil if kif_evo_locked?
    return kif_evolock_check_evolution_internal(*args, &block)
  end
end

alias kif_evolock_pbForceEvo pbForceEvo unless defined?(kif_evolock_pbForceEvo)

def pbForceEvo(pokemon)
  return false if pokemon.respond_to?(:kif_evo_locked?) && pokemon.kif_evo_locked?
  return kif_evolock_pbForceEvo(pokemon)
end

# KIF PokemonFusion.rb:911 – the fused Pokémon starts unlocked.
class PokemonFusionScene
  alias kif_evolock_pbFusionScreen pbFusionScreen unless method_defined?(:kif_evolock_pbFusionScreen)

  def pbFusionScreen(*args)
    head = @pokemon2
    ret = kif_evolock_pbFusionScreen(*args)
    fused = @pokemon1
    if fused && head && fused.respond_to?(:original_head) && fused.original_head &&
       fused.original_head.personalID == head.personalID
      fused.kuray_no_evo = 0
    end
    return ret
  end
end

# PC: Kuray Actions > Lock / Unlock Evolution (KIF pbKurayNoEvo)
KIF::PCActions.add(:evolock,
  proc { |pkmn|
    next nil unless $PokemonSystem.kuray_no_evo == 1
    (pkmn.kuray_no_evo? == 0) ? _INTL("Lock Evolution") : _INTL("Unlock Evolution")
  },
  proc { |screen, pkmn, _selected, _heldpoke|
    if pkmn.kuray_no_evo? == 0
      pkmn.kuray_no_evo = 1
      screen.pbDisplay(_INTL("Pokemon evolution locked!"))
    else
      pkmn.kuray_no_evo = 0
      screen.pbDisplay(_INTL("Pokemon evolution unlocked!"))
    end
  })

#-------------------------------------------------------------------------------
# Indicator (Cody, 2026-10-05): a small padlock next to the level in the
# Summary header (every page) while the Pokémon is evolution-locked and the
# option is On. Drawn with rectangles, so no new image is needed.
#-------------------------------------------------------------------------------
module KIF
  def self.draw_evolock_icon(bitmap, x, y)
    dark = Color.new(64, 64, 64)
    gold = Color.new(232, 184, 48)
    shine = Color.new(255, 232, 140)
    # shackle
    bitmap.fill_rect(x + 2, y, 8, 2, dark)
    bitmap.fill_rect(x + 2, y, 2, 7, dark)
    bitmap.fill_rect(x + 8, y, 2, 7, dark)
    # body
    bitmap.fill_rect(x, y + 6, 12, 9, dark)
    bitmap.fill_rect(x + 1, y + 7, 10, 7, gold)
    bitmap.fill_rect(x + 2, y + 8, 3, 1, shine)
    # keyhole
    bitmap.fill_rect(x + 5, y + 9, 2, 3, dark)
  end
end

class PokemonSummary_Scene
  alias kif_evolock_drawPage drawPage unless method_defined?(:kif_evolock_drawPage)

  def drawPage(page)
    kif_evolock_drawPage(page)
    return if @pokemon.nil? || @pokemon.egg? || !@pokemon.kif_evo_locked?
    KIF.draw_evolock_icon(@sprites["overlay"].bitmap, 106, 101)
  rescue => e
    KIF.log("EvoLock icon failed: #{e.message}")
  end
end

# Party screen (Cody, 2026-10-05): same padlock in the empty space between
# the level and the HP numbers (status icons sit at x 78-122, HP text starts
# around x 150).
class PokemonPartyPanel
  alias kif_evolock_refresh refresh unless method_defined?(:kif_evolock_refresh)

  def refresh
    redraw = @refreshBitmap
    kif_evolock_refresh
    return unless redraw && @pokemon && !@pokemon.egg? && @pokemon.kif_evo_locked?
    return if @text && @text.length > 0   # "ABLE"/"NOT ABLE" annotations use this spot
    return unless @overlaysprite && !@overlaysprite.disposed? && @overlaysprite.bitmap
    KIF.draw_evolock_icon(@overlaysprite.bitmap, 130, 64)
  rescue => e
    KIF.log("EvoLock party icon failed: #{e.message}")
  end
end
