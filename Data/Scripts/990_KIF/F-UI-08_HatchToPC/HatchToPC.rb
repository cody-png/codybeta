#===============================================================================
# F-UI-08 – Egg hatch -> "send to PC?" prompt
# Source: KIF 0.20.7 016_UI/001_Non-interactive UI/003_UI_EggHatching.rb
#         (#KurayX sent hatched to PC asking: :119-126 and :245-252)
#
# After an Egg hatches: "Do you wish to send {1} to the PC?" -> Yes stores it
# with pbStoreCaught and removes it from the party: "{1} was sent to the PC."
#
# KIF threaded a new `eggindex` argument through pbHatch / pbHatchAnimation /
# pbStartScreen / pbMain. Here pbHatch is wrapped instead and the Pokémon is
# found in the party by identity, so no base signature changes.
# Differences from KIF (see port notes):
#   * Option "Hatch to PC Prompt" (hatchtopc, default On). KIF always asked.
#   * Not offered if it would leave the party without a non-Egg Pokémon.
#   * If every box is full the Pokémon stays in the party.
#   * Asked once after the hatch scene (KIF asked inside the animation, before
#     the Pokédex registration message).
#===============================================================================
KIF::Options.define(:hatchtopc, 1, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Hatch to PC Prompt"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.hatchtopc },
                 proc { |value| $PokemonSystem.hatchtopc = value },
                 [_INTL("Hatched Pokémon stay in your party."),
                  _INTL("Ask whether to send a hatched Pokémon to the PC.")])
}

alias kif_pbHatch pbHatch unless defined?(kif_pbHatch)

def pbHatch(pokemon, *args)
  ret = kif_pbHatch(pokemon, *args)
  kif_offer_hatched_to_pc(pokemon)
  return ret
end

def kif_offer_hatched_to_pc(pokemon)
  return unless $PokemonSystem.hatchtopc == 1
  idx = $Trainer.party.index { |p| p.equal?(pokemon) }
  return if idx.nil? || pokemon.egg?
  others = $Trainer.party.each_with_index.count { |p, i| i != idx && p && !p.egg? }
  return if others == 0
  if pbConfirmMessage(_INTL("Do you wish to send {1} to the PC?", pokemon.name))
    if $PokemonStorage.pbStoreCaught(pokemon) < 0   # PC full (KIF lost it here)
      pbMessage(_INTL("The PC is full."))
      return
    end
    $Trainer.party.delete_at(idx)
    pbMessage(_INTL("{1} was sent to the PC.", pokemon.name))
  end
end
