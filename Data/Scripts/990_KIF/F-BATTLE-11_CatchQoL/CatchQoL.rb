#===============================================================================
# F-BATTLE-11 – Catch & post-battle QoL
# Source: KIF 0.20.7
#   011_Battle/001_Battler/006_Battler_AbilityAndItem.rb:146,158-160 (Trapstarr)
#   052_AddOns/GameplayUtils.rb:932-934 (skipcaughtprompt)
#
#   Recover Consumables (recover_consumables): when one of the PLAYER's
#     Pokémon consumes its held item (berries, gems, ...), one copy is put in
#     the bag first. PIF's own restock rule (pbRemoveItem: if the bag holds the
#     item, take one from the bag and keep the held item for after battle)
#     then takes it back out, so the net effect is the Pokémon keeps its item
#     after battle and the bag is unchanged.
#   Skip Caught Prompt (skipcaughtprompt): with a full party, a caught Pokémon
#     always goes to the PC instead of showing PIF's "Your team is full!"
#     menu. (Pinkan Island's keep-or-release prompt, a 6.8.2 quest mechanic,
#     is left alone.)
#   Items to Bag (items_to_bag, 2026-10-26, player request): a Pokémon that
#     already holds an item still steals with Thief/Covet in WILD battles and
#     still finds items with Pickup after battle; the new item goes to the
#     Bag. Trainer battles stay as in PIF (their items come back after
#     battle, so a Bag copy would be a free item). Only the wild Pokémon's
#     own item: one the player gave it (Trick, Switcheroo, Bestow) comes
#     back after battle too.
#   Bug fix (always on, KIF :146): PIF's restock rule also ran for the FOE's
#     side, so a wild/trainer Pokémon eating e.g. a Sitrus Berry deleted a
#     Sitrus Berry from the player's bag. Restricted to the player's side.
#
# NOT ported (superseded by PIF 6.8.2):
#   Skip Caught Nickname -> PIF "Prompt Nicknames" option (Gameplay options).
#   ENABLE_CRITICAL_CAPTURES -> ported as an option, see CriticalCaptures.rb.
#===============================================================================
KIF::Options.define(:recover_consumables, 0, :save)
KIF::Options.define(:skipcaughtprompt, 0, :save)
KIF::Options.define(:items_to_bag, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Recover Consumables"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.recover_consumables },
                 proc { |value| $PokemonSystem.recover_consumables = value },
                 [_INTL("Don't recover consumable items after battle"),
                  _INTL("Recover consumable items after battle")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Skip Caught Prompt"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.skipcaughtprompt },
                 proc { |value| $PokemonSystem.skipcaughtprompt = value },
                 [_INTL("If your party is full, allows you to put the caught pokemon on your party."),
                  _INTL("If your party is full, always send the caught pokemon to the PC.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Items to Bag"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.items_to_bag },
                 proc { |value| $PokemonSystem.items_to_bag = value },
                 [_INTL("Thief, Covet and Pickup only work for a Pokémon with no held item."),
                  _INTL("If it holds an item, what it steals from wild Pokémon or finds with Pickup goes to the Bag.")])
}

KIF.guard_base("011_Battle/001_Battler/006_Battler_AbilityAndItem.rb", 1740748395,
               "PokeBattle_Battler#pbRemoveItem")

class PokeBattle_Battler
  # Copy of PIF 6.8.2 pbRemoveItem with KIF's `!self.opposes?` fix.
  def pbRemoveItem(permanent = true)
    @effects[PBEffects::ChoiceBand] = nil
    @effects[PBEffects::Unburden]   = true if self.item

    if permanent && self.item == self.initialItem
      if pbOwnedByPlayerSerious? && !(defined?(KIF::SelfBattle) && KIF::SelfBattle.active) && $PokemonBag.pbQuantity(self.initialItem) >= 1   # KIF (not in a Self-Battle: copies)
        $PokemonBag.pbDeleteItem(self.initialItem)
      else
        setInitialItem(nil)
      end
    end
    self.item = nil
  end

  alias kif_pbConsumeItem pbConsumeItem unless method_defined?(:kif_pbConsumeItem)

  def pbConsumeItem(recoverable = true, symbiosis = true, belch = true)
    # only the item it started with: pbRemoveItem takes that copy back from the
    # Bag at the next restock; a stolen or picked-up berry would be a free item
    if recoverable && @item_id && @item_id == self.initialItem && $PokemonSystem.recover_consumables == 1 &&
       pbOwnedByPlayerSerious? && !(defined?(KIF::SelfBattle) && KIF::SelfBattle.active) &&
       $PokemonBag.pbCanStore?(@item_id, 1)   # not a partner's item, not a Self-Battle copy
      $PokemonBag.pbStoreItem(@item_id, 1)
    end
    kif_pbConsumeItem(recoverable, symbiosis, belch)
  end
end

alias kif_promptCaughtPokemonAction promptCaughtPokemonAction unless defined?(kif_promptCaughtPokemonAction)

def promptCaughtPokemonAction(pokemon)
  if $PokemonSystem.skipcaughtprompt == 1 && $Trainer.party_full? &&
     !(isOnPinkanIsland() && !$game_switches[SWITCH_PINKAN_FINISHED])
    return pbStorePokemon(pokemon)
  end
  return kif_promptCaughtPokemonAction(pokemon)
end

# Items to Bag: Thief/Covet with a held item, wild battles only. The target
# must be a foe (an ally's item comes back after battle: a copy otherwise).
class PokeBattle_Move_0F1
  alias kif_bag_pbEffectAfterAllHits pbEffectAfterAllHits unless method_defined?(:kif_bag_pbEffectAfterAllHits) || private_method_defined?(:kif_bag_pbEffectAfterAllHits)

  def pbEffectAfterAllHits(user, target)
    if $PokemonSystem.items_to_bag == 1 && @battle.wildBattle? && user.pbOwnedByPlayerSerious? &&
       target.opposes?(user) && !user.fainted? && user.item && target.item &&
       target.item_id == target.initialItem &&   # not one the player gave it: that one comes back after battle
       !target.damageState.unaffected && !target.damageState.substitute &&
       !target.unlosableItem?(target.item) &&
       !(target.hasActiveAbility?(:STICKYHOLD) && !@battle.moldBreaker) &&
       $PokemonBag.pbCanStore?(target.item)
      item = target.item
      name = target.itemName
      target.pbRemoveItem(false)   # a caught Pokemon's item follows battler#item=, so no copy
      $PokemonBag.pbStoreItem(item)
      @battle.pbDisplay(_INTL("{1} stole {2}'s {3} and put it in the Bag!", user.pbThis, target.pbThis(true), name))
      return
    end
    kif_bag_pbEffectAfterAllHits(user, target)
  end
end

alias kif_bag_pbPickup pbPickup unless defined?(kif_bag_pbPickup)

# Items to Bag: Pickup with a held item runs PIF's own roll and table on an
# empty hand, then moves the find to the Bag and gives the held item back.
def pbPickup(pkmn)
  if $PokemonSystem.items_to_bag != 1 || !pkmn.hasItem? || pkmn.egg? || !pkmn.hasAbility?(:PICKUP) ||
     (defined?(KIF::SelfBattle) && KIF::SelfBattle.active)
    return kif_bag_pbPickup(pkmn)
  end
  held = pkmn.item
  found = nil
  begin
    pkmn.item = nil
    kif_bag_pbPickup(pkmn)
    found = pkmn.item
  ensure
    pkmn.item = held
  end
  return if !found || !$PokemonBag.pbCanStore?(found)
  $PokemonBag.pbStoreItem(found)
  pbMessage(_INTL("{1} found one {2} with Pickup. It was put in the Bag.", pkmn.name, found.name))
end
