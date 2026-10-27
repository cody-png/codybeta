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
#   Unlocks (2026-10-27, Cody): Burned needs a Flame Orb, Poisoned a Toxic Orb.
#     Each unlocks for the save once the item is in the Bag or held by a party
#     or PC Pokémon (PokemonBag#pbStoreItem, save load, and each time the menu
#     opens) and stays unlocked. A locked choice is listed with "(needs ...)"
#     and can't be picked; a Pokémon set before the unlocks keeps its choice.
#===============================================================================
KIF::Options.define(:prestatus, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Pre-Status"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.prestatus },
                 proc { |value| $PokemonSystem.prestatus = value },
                 [_INTL("Pokémon start battles with the status they already have."),
                  _INTL("Kuray Actions can make a Pokémon start battles burned (after a Flame Orb) or poisoned (after a Toxic Orb).")])
}

class Pokemon
  attr_accessor :kif_prestatus   # nil, :BURN or :POISON
end

class PokemonGlobalMetadata
  attr_writer :kif_prestatus_unlocked
  def kif_prestatus_unlocked
    @kif_prestatus_unlocked ||= []   # statuses unlocked in this save
  end
end

module KIF
  module PreStatus
    CHOICES = [nil, :BURN, :POISON]

    def self.on?
      return $PokemonSystem && $PokemonSystem.prestatus.to_i == 1
    end

    ITEMS = { :BURN => :FLAMEORB, :POISON => :TOXICORB }

    def self.name(status)
      return [_INTL("Normal"), _INTL("Burned"), _INTL("Poisoned")][CHOICES.index(status) || 0]
    end

    def self.unlocked?(status)
      return true if !ITEMS[status]
      return !!($PokemonGlobal && $PokemonGlobal.kif_prestatus_unlocked.include?(status))
    end

    def self.unlock(item)
      status = ITEMS.key(item)
      return if !status || !$PokemonGlobal || unlocked?(status)
      $PokemonGlobal.kif_prestatus_unlocked << status
      KIF.log("Pre-Status: #{name(status)} unlocked (#{item})") if defined?(KIF.log)
    end

    # The Bag, and items held in the party and the PC
    def self.scan
      return if !$PokemonGlobal || ITEMS.keys.all? { |s| unlocked?(s) }
      mons = ($Trainer ? $Trainer.party : []).to_a.dup
      if $PokemonStorage
        $PokemonStorage.maxBoxes.times { |b| $PokemonStorage.maxPokemon(b).times { |i| mons << $PokemonStorage[b, i] } }
      end
      ITEMS.each_value do |item|
        unlock(item) if ($PokemonBag && $PokemonBag.pbHasItem?(item)) || mons.any? { |p| p && p.item_id == item }
      end
    end
  end
end

KIF::PCActions.add(:prestatus,
  proc { |pkmn|
    next nil if !KIF::PreStatus.on? || pkmn.egg?
    _INTL("Start Battles: {1}", KIF::PreStatus.name(pkmn.kif_prestatus))
  },
  proc { |screen, pkmn, _selected, _heldpoke|
    ps = KIF::PreStatus
    ps.scan
    ids = ps::CHOICES
    names = ids.map { |s|
      next ps.name(s) if ps.unlocked?(s)
      _INTL("{1} (needs {2})", ps.name(s), GameData::Item.get(ps::ITEMS[s]).name)
    }
    cmd = screen.pbShowCommands(_INTL("How should {1} start battles?", pkmn.name),
                                names + [_INTL("Cancel")], ids.index(pkmn.kif_prestatus) || 0)
    # a locked choice can't be picked (one set before the unlocks stays as it is)
    pkmn.kif_prestatus = ids[cmd] if cmd.between?(0, ids.length - 1) && ps.unlocked?(ids[cmd])
  })

class PokemonBag
  alias kif_prestatus_pbStoreItem pbStoreItem unless method_defined?(:kif_prestatus_pbStoreItem) || private_method_defined?(:kif_prestatus_pbStoreItem)

  def pbStoreItem(item, *args)
    ret = kif_prestatus_pbStoreItem(item, *args)
    begin
      KIF::PreStatus.unlock(GameData::Item.get(item).id) if ret
    rescue StandardError
    end
    return ret
  end
end

# Saves that already had the item
alias kif_prestatus_onLoadExistingGame onLoadExistingGame unless Object.method_defined?(:kif_prestatus_onLoadExistingGame) || Object.private_method_defined?(:kif_prestatus_onLoadExistingGame)

def onLoadExistingGame(*args)
  ret = kif_prestatus_onLoadExistingGame(*args)
  begin
    KIF::PreStatus.scan
  rescue StandardError => e
    KIF.log("Pre-Status: unlock check failed (#{e.class}: #{e.message})") if defined?(KIF.log)
  end
  return ret
end

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
