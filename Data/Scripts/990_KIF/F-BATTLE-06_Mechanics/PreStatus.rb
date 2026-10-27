#===============================================================================
# F-BATTLE-06 – Pre-Status (new in KIF, player request, 2026-10-26)
# Not in KIF 0.20.7 or PIF 6.8.2.
#
#   Battles > "Pre-Status" Off / On (per save, Off): with it On, Kuray Actions
#     (PC and field party menu) > "Start Battles" picks Normal / Burned /
#     Poisoned for one Pokémon. Each time it is sent out without a status it
#     gets that status, with the same checks as a Flame Orb / Toxic Orb
#     (pbCanBurn?/pbCanPoison? with no user): Fire types can't be burned,
#     Poison/Steel types can't be poisoned, Water Veil, Immunity, Comatose,
#     Misty Terrain... still block it. For Guts / Poison Heal / Quick Feet /
#     Marvel Scale builds that would otherwise give up the held item for an Orb.
#   Off: the choice stays saved on the Pokémon and is ignored (as EvoLock).
#===============================================================================
KIF::Options.define(:prestatus, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Pre-Status"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.prestatus },
                 proc { |value| $PokemonSystem.prestatus = value },
                 [_INTL("Pokémon start battles with the status they already have."),
                  _INTL("Kuray Actions can make a Pokémon start every battle burned or poisoned.")])
}

class Pokemon
  attr_accessor :kif_prestatus   # nil, :BURN or :POISON
end

module KIF
  module PreStatus
    CHOICES = [nil, :BURN, :POISON]

    def self.on?
      return $PokemonSystem && $PokemonSystem.prestatus.to_i == 1
    end

    def self.name(status)
      return [_INTL("Normal"), _INTL("Burned"), _INTL("Poisoned")][CHOICES.index(status) || 0]
    end
  end
end

KIF::PCActions.add(:prestatus,
  proc { |pkmn|
    next nil if !KIF::PreStatus.on? || pkmn.egg?
    _INTL("Start Battles: {1}", KIF::PreStatus.name(pkmn.kif_prestatus))
  },
  proc { |screen, pkmn, _selected, _heldpoke|
    ids = KIF::PreStatus::CHOICES
    cmd = screen.pbShowCommands(_INTL("How should {1} start battles?", pkmn.name),
                                ids.map { |s| KIF::PreStatus.name(s) } + [_INTL("Cancel")],
                                ids.index(pkmn.kif_prestatus) || 0)
    pkmn.kif_prestatus = ids[cmd] if cmd.between?(0, ids.length - 1)
  })

class PokeBattle_Battle
  alias kif_prestatus_pbOnActiveOne pbOnActiveOne unless method_defined?(:kif_prestatus_pbOnActiveOne) || private_method_defined?(:kif_prestatus_pbOnActiveOne)

  def pbOnActiveOne(battler)
    ret = kif_prestatus_pbOnActiveOne(battler)
    if ret && KIF::PreStatus.on? && battler.status == :NONE && battler.pokemon
      case battler.pokemon.kif_prestatus
      when :BURN   then battler.pbBurn(nil) if battler.pbCanBurn?(nil, false)
      when :POISON then battler.pbPoison(nil) if battler.pbCanPoison?(nil, false)
      end
    end
    return ret
  end
end
