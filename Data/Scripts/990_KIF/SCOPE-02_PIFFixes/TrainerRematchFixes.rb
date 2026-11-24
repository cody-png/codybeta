# PIF's trainer rematch system: a rematch crashed on update_items, gifts changed the shared gift table,
# and several menu, partner, trade and random-event paths crashed on nil or looped without end.

def update_items(trainer)
  list = $PokemonTemp.battle_npc_used_items
  return unless list
  list.each do |item|
    index = trainer.inventory.index(item)
    trainer.inventory.delete_at(index) if index
  end
  $PokemonTemp.battle_npc_used_items = nil
  return trainer
end

# an evolution item is used up only when its Pokemon really evolves, and the first matching one wins
def evolveRebattledTrainerPokemon(trainer)
  updated_team = []
  for pokemon in trainer.currentTeam
    evolution_species = pokemon.check_evolution_on_level_up(false)
    used_item = nil
    unless evolution_species  # level-up evolution has priority over stone evolution
      trainer.list_evolution_items.each do |evolution_item|
        evolution_species = pokemon.check_evolution_on_use_item(evolution_item)
        next unless evolution_species
        used_item = evolution_item
        break
      end
    end

    if evolution_species && pokemonAllowedToEvolve(pokemon, evolution_species)
      index = used_item && trainer.inventory.index(used_item)
      trainer.inventory.delete_at(index) if index
      trainer.log_evolution_event(pokemon.species, evolution_species)
      trainer.set_pending_action(true)
      pokemon.species = evolution_species
      pokemon.pif_sprite = nil
    end
    updated_team.push(pokemon)
  end
  trainer.currentTeam = updated_team
  return trainer
end

def generateTrainerRematch(trainer, allow_double = true)
  battle_trainers = []
  battle_trainers << trainer
  partner = trainer.getLinkedTrainer
  if partner && allow_double # perma-double battles (twins, etc.)
    battle_trainers << partner
  end

  player_won = rematchable_trainer_battle(battle_trainers)
  checkTrainerRematchChallenges()
  # trainer
  updated_trainer = makeRebattledTrainerTeamGainExp(trainer, player_won)
  updated_trainer = healRebattledTrainerPokemon(updated_trainer)
  updated_trainer.set_pending_action(false)
  update_items(updated_trainer)
  updated_trainer = evolveRebattledTrainerPokemon(updated_trainer)
  trainer.increase_friendship(5)
  trainer.nb_rematches += 1
  # partner
  if partner
    updated_partner_trainer = makeRebattledTrainerTeamGainExp(partner, player_won)
    updated_partner_trainer = healRebattledTrainerPokemon(updated_partner_trainer)
    updated_partner_trainer.set_pending_action(false)
    updated_partner_trainer = evolveRebattledTrainerPokemon(updated_partner_trainer)
    updateRebattledTrainerWithKey(updated_partner_trainer&.trainerKey, updated_partner_trainer)
  end

  return updated_trainer, player_won
end

# works on copies of the gift lists, so the shared table is not changed
def find_random_trainer_item(trainer)
  rare_item_chances = 5 + (trainer.friendship / 5).floor
  chance_trainer_class_item = 40

  giving_rare_item = rand(100) < rare_item_chances
  typed_items = TRAINER_REMATCH_GIFTS[trainer.favorite_type] || TRAINER_REMATCH_GIFTS[:NORMAL]
  # :ANY is one flat list, the other types are [common, rare]
  typed_items = [typed_items, typed_items] if typed_items.equal?(TRAINER_REMATCH_GIFTS[:ANY])
  items_list = [typed_items[0] + (trainer.inventory || []), typed_items[1]]

  if TRAINER_REMATCH_SPECIFIC_GIFTS.has_key?(trainer.trainerType) && rand(100) < chance_trainer_class_item
    items_list = TRAINER_REMATCH_SPECIFIC_GIFTS[trainer.trainerType]
  end
  if giving_rare_item
    return items_list[1].sample
  else
    items = items_list[0] + TRAINER_REMATCH_GIFTS[:ANY]
    return items.sample
  end
end

def doPostBattleAction(actionType, trainer, double_allowed = true)
  event = pbMapInterpreter.get_character(0)
  map_id = $game_map.map_id if map_id.nil?
  unless trainer
    trainer = getRebattledTrainer(event.id, map_id)
  end
  return if !trainer
  trainer.clear_previous_random_events()

  case actionType
  when :BATTLE
    trainer, player_won = generateTrainerRematch(trainer, double_allowed)
  when :TRADE
    trainer = doNPCTrainerTrade(trainer)
  when :PARTNER
    partnerWithTrainer(event.id, map_id, trainer)
  end
  updateRebattledTrainer(trainer)
end

# the gift leaves the trainer's inventory only once the bag took it
def try_give_gift(trainer, event_id = nil)
  if should_give_item(trainer)
    item = select_gift_item(trainer)
    return unless item
    showGiftDialog(trainer, event_id)
    return false unless pbReceiveItem(item)
    index = trainer.inventory.index(item)
    if index
      trainer.inventory.delete_at(index)
      updateRebattledTrainer(trainer)
    end
    return true
  end
  return false
end

FORCE_REMATCH_EVENT_TRIES = 20

def forceRandomRematchEventOnTrainer(event_type = nil)
  event = pbMapInterpreter.get_character(0)
  map_id = $game_map.map_id if map_id.nil?
  trainer = getRebattledTrainer(event.id, map_id)
  FORCE_REMATCH_EVENT_TRIES.times do
    break if trainer.has_pending_action
    trainer = applyTrainerRandomEvents(trainer, event_type)
  end
  updateRebattledTrainer(trainer)
end

# a partner with a full team refuses the Pokemon instead of losing its last one; a missing partner no longer crashes
alias kif_orig_promptGiveToPartner promptGiveToPartner unless defined?(kif_orig_promptGiveToPartner)

def promptGiveToPartner(caughtPokemon)
  return false if !$Trainer.npcPartner
  partner = getRebattledTrainerFromKey($Trainer.npcPartner)
  return false if !partner || partner.currentTeam.length >= 6
  return kif_orig_promptGiveToPartner(caughtPokemon)
end

# the trainer's class and name are named in the offer messages for every trainer, rivals included
def generateTrainerTradeOffer(trainer)
  wanted_types = BattledTrainer::TRAINER_CLASS_FAVORITE_TYPES[trainer.trainerType]
  wanted_types = [:NORMAL] if !wanted_types || wanted_types.empty?
  trainerClassName = GameData::TrainerType.get(trainer.trainerType).name
  trainerName = pbGetMessageFromHash(MessageTypes::TrainerNames, trainer.trainerName)
  if wanted_types.include?(:ANY)
    pbChoosePokemon(1, 2)
  else
    wanted_types_string = wanted_types.map { |type|
      type_name = GameData::Type.get(type).name
      "\\C[1]#{type_name}\\C[0]"
    }.join(", ")

    pbMessage(_INTL("{1} {2} is looking for Pokémon of the following type(s):\\n{3}\\nWhich Pokémon do you want to trade?",
                    trainerClassName, trainerName, wanted_types_string))
    pbChoosePokemon(1, 2,
                    proc { |pokemon|
                      pokemon.hasOneOfTheseTypes?(wanted_types) &&
                      !pokemon.egg?
                    })
  end
  chosen_index = pbGet(1)
  if chosen_index && chosen_index >= 0
    chosen_pokemon = $Trainer.party[chosen_index]
    offered_pokemon = offerPokemonForTrade(chosen_pokemon, trainer.currentTeam, trainer.trainerType, trainer.favorite_type)
    if !offered_pokemon
      pbMessage(_INTL("{1} {2} does not want to trade...", trainerClassName, trainerName))
      return trainer
    end

    pif_sprite = BattleSpriteLoader.new.get_pif_sprite_from_species(offered_pokemon.species)
    message = _INTL("{1} {2} is offering {3} (Level {4}) for your {5}.", trainerClassName, trainerName, offered_pokemon.name, offered_pokemon.level, chosen_pokemon.name)
    showPokemonInPokeballWithMessage(pif_sprite, message)

    if pbConfirmMessage(_INTL("Trade away {1} for {2} {3}'s {4}?", chosen_pokemon.name, trainerClassName, trainerName, offered_pokemon.name))
      pbStartTrade(chosen_index, offered_pokemon, offered_pokemon.name, trainer.trainerName, 0)
      updated_party = trainer.currentTeam
      trainer.increase_friendship(10) if GameData::Type.exists?(trainer.favorite_type) && offered_pokemon.hasType?(trainer.favorite_type)
      updated_party.delete(offered_pokemon)
      updated_party << chosen_pokemon.clone

      trainer.previous_trade_timestamp = Time.now
      trainer.increase_friendship(20)
      trainer.process_party_pokemon_held_items
      return trainer
    end
  end
  return trainer
end

# a trainer with an empty team has nothing to offer
alias kif_orig_offerPokemonForTrade offerPokemonForTrade unless defined?(kif_orig_offerPokemonForTrade)

def offerPokemonForTrade(player_pokemon, npc_party, trainer_class, favorite_type)
  return nil if npc_party.nil? || npc_party.empty?
  return kif_orig_offerPokemonForTrade(player_pokemon, npc_party, trainer_class, favorite_type)
end

# a random event counts as a change by what is in the team, since the Pokemon objects are changed in place
alias kif_orig_applyTrainerRandomEvents applyTrainerRandomEvents unless defined?(kif_orig_applyTrainerRandomEvents)

def applyTrainerRandomEvents(trainer, event_type = nil)
  return kif_orig_applyTrainerRandomEvents(trainer, event_type) if trainer.has_pending_action
  before = trainer.currentTeam.map { |pkmn| pkmn.species }
  trainer = kif_orig_applyTrainerRandomEvents(trainer, event_type)
  trainer.set_pending_action(trainer.currentTeam.map { |pkmn| pkmn.species } != before)
  return trainer
end

alias kif_orig_unfuse_random_team_pokemon unfuse_random_team_pokemon unless defined?(kif_orig_unfuse_random_team_pokemon)

def unfuse_random_team_pokemon(trainer)
  trainer.inventory ||= []
  return kif_orig_unfuse_random_team_pokemon(trainer)
end

# five rolls of the same species end the loop; before, an area with a single species never ended it
def getRandomPokemonFromRoute(excluded_species, terrain)
  random_species = excluded_species
  limit = 5
  i = 0
  while random_species == excluded_species && i < limit
    terrain_type = getTimeBasedEncounter(terrain)
    wild_pokemon = getRegularEncounter(terrain_type)
    random_species = wild_pokemon[0] if wild_pokemon.is_a?(Array)
    i += 1
  end
  return GameData::Species.get(random_species)
end
