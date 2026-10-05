#===============================================================================
# Ability Capsule / Secret Capsule – ability picker (port addition, requested
# by Cody 2026-10-05; not a KIF 0.20.7 feature)
#
# 6.8.2: the Ability Capsule only swaps between the two regular abilities
#   (013_Items/002_Item_Effects.rb:1115) and the Secret Capsule is marked
#   "NOT FULLY IMPLEMENTED" (052_InfiniteFusion/Gameplay/Items/New Items
#   effects.rb:1401).
# Here both open a list of the abilities the Pokémon may have:
#   Ability Capsule – the regular abilities: of the species, or for a fusion
#                     of its head and its body species. No hidden abilities.
#   Secret Capsule  – the same plus the hidden abilities.
# The Pokémon's current ability is left out. Nothing to choose (e.g. an
# unfused Pokémon with a single regular ability) → "It won't have any
# effect." Cancelling keeps the item.
#===============================================================================
module KIF
  module AbilityCapsule
    # Species data whose abilities count (head and body for a fusion)
    def self.parts(pkmn)
      sp = pkmn.species_data
      if sp.is_a?(GameData::FusedSpecies) && sp.body_pokemon && sp.head_pokemon
        return [sp.body_pokemon, sp.head_pokemon]
      end
      return [sp]
    end

    def self.choices(pkmn, hidden)
      list = []
      parts(pkmn).each do |d|
        list.concat(Array(d.abilities).compact)
        list.concat(Array(d.hidden_abilities).compact) if hidden
      end
      list = list.map { |a| GameData::Ability.try_get(a) }.compact.map(&:id).uniq
      return list - [pkmn.ability_id]
    end

    def self.use(pkmn, scene, hidden)
      if pkmn.egg? || pkmn.isSpecies?(:ZYGARDE)
        scene.pbDisplay(_INTL("It won't have any effect."))
        return false
      end
      list = choices(pkmn, hidden)
      if list.empty?
        scene.pbDisplay(_INTL("It won't have any effect."))
        return false
      end
      names = list.map { |a| GameData::Ability.get(a).name }
      cmd = scene.pbShowCommands(_INTL("Change {1}'s Ability to which one?", pkmn.name),
                                 names + [_INTL("Cancel")])
      return false if cmd.nil? || cmd < 0 || cmd >= list.length
      abil = list[cmd]
      entry = pkmn.getAbilityList.find { |a, _i| a == abil }
      pkmn.ability_index = entry[1] if entry
      pkmn.ability = abil
      scene.pbHardRefresh if scene.respond_to?(:pbHardRefresh)
      scene.pbDisplay(_INTL("{1}'s Ability changed to {2}!", pkmn.name, names[cmd]))
      return true
    end
  end
end

ItemHandlers::UseOnPokemon.add(:ABILITYCAPSULE, proc { |item, pkmn, scene|
  next KIF::AbilityCapsule.use(pkmn, scene, false)
})

ItemHandlers::UseOnPokemon.add(:SECRETCAPSULE, proc { |item, pkmn, scene|
  next KIF::AbilityCapsule.use(pkmn, scene, true)
})
