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
#   Bug fix (always on, KIF :146): PIF's restock rule also ran for the FOE's
#     side, so a wild/trainer Pokémon eating e.g. a Sitrus Berry deleted a
#     Sitrus Berry from the player's bag. Restricted to the player's side.
#
# NOT ported (superseded by PIF 6.8.2):
#   Skip Caught Nickname -> PIF "Prompt Nicknames" option (Gameplay options).
#   ENABLE_CRITICAL_CAPTURES = true -> left at PIF's false (see port notes).
#===============================================================================
KIF::Options.define(:recover_consumables, 0, :save)
KIF::Options.define(:skipcaughtprompt, 0, :save)

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

KIF.guard_base("011_Battle/001_Battler/006_Battler_AbilityAndItem.rb", 1740748395,
               "PokeBattle_Battler#pbRemoveItem")

class PokeBattle_Battler
  # Copy of PIF 6.8.2 pbRemoveItem with KIF's `!self.opposes?` fix.
  def pbRemoveItem(permanent = true)
    @effects[PBEffects::ChoiceBand] = nil
    @effects[PBEffects::Unburden]   = true if self.item

    if permanent && self.item == self.initialItem
      if !self.opposes? && $PokemonBag.pbQuantity(self.initialItem) >= 1   # KIF
        $PokemonBag.pbDeleteItem(self.initialItem)
      else
        setInitialItem(nil)
      end
    end
    self.item = nil
  end

  alias kif_pbConsumeItem pbConsumeItem unless method_defined?(:kif_pbConsumeItem)

  def pbConsumeItem(recoverable = true, symbiosis = true, belch = true)
    if recoverable && @item_id && $PokemonSystem.recover_consumables == 1 &&
       !self.opposes? && $PokemonBag.pbCanStore?(@item_id, 1)
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
