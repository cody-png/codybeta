###################################################################################################
# Author: An Unsocial Pigeon                                                                      #
# Discord: @anunsocialpigeon                                                                      #
# For any issues or inquiries, feel free to reach out on Discord.                                 #
#                                                                                                 #
# You are allowed to use this file in your own mod,                                               # 
# on condition that you correctly credit me (An Unsocial Pigeon) <3                               #
###################################################################################################



class Spriteset_Map
  # Add a new event sprite to the spriteset
  def add_event_sprite(event)
    return if @character_sprites.any? { |sprite| sprite.character == event }

    sprite = Sprite_Character.new(@viewport1, event)
    @character_sprites.push(sprite)
  end

  # Ensure spriteset updates properly
  def update_character_sprites
    @character_sprites.each(&:update)
  end
end


# The trainer handler
module TrainerHandler
  module TrainerHandlerUtils
    # Ensure the correct map is loaded before modifying events
    def self.ensure_map_loaded(map_id)
      return if $game_map.map_id == map_id
      log_message("Loading map #{map_id}.")
      $game_map.setup(map_id)
      $game_map.refresh
    end

    # Force a map refresh
    def self.force_map_refresh
      $game_map.need_refresh = true
      $game_map.refresh
      $game_map.events.each_value(&:refresh)
      if $scene.is_a?(Scene_Map)
        $scene.updateSpritesets(true)
      end
      Graphics.update
    end
  end

  def self.event_exists(event_id)
    return $game_map.events[event_id] ? true : false
  end

  def self.create_sprite_event(map_id, trainer_id, x, y, rot = 2, sprite_name = "002", page_list = [RPG::EventCommand.new(101, 0, ["This trainer is not yet implemented..."])], animate_steps = true)
    TrainerHandlerUtils.ensure_map_loaded(map_id)

    # Skip if the trainer already exists
    if TrainerHandler.event_exists(trainer_id)
      log_message("Trainer with ID #{trainer_id} already exists. Skipping creation.")
      return
    end

    # Create RPG::Event
    event = RPG::Event.new(x, y)
    event.name = "Trainer #{trainer_id}"
    event.pages << RPG::Event::Page.new.tap do |page|
      page.step_anime = animate_steps
      page.graphic.character_name = sprite_name
      page.graphic.direction = rot
      page.trigger = 0
      page.list = page_list
      page.always_on_top = false
    end

    # Add the event to the map
    game_event = Game_Event.new(map_id, event)
    game_event.instance_variable_set(:@id, trainer_id)
    game_event.instance_variable_set(:@map, $game_map)
    game_event.character_name = sprite_name
    game_event.moveto(x, y)
    $game_map.events[trainer_id] = game_event

    if $scene.is_a?(Scene_Map) && $scene.spriteset
      $scene.spriteset.add_event_sprite(game_event)
    end

    # Force refresh
    TrainerHandlerUtils.force_map_refresh
  end



  # Create a new trainer to fight. Does not spawn it onto the map.
  def self.create_new_trainer(tr_type, tr_name, tr_version, pokemon_data)
    # pokemon_data is an array of hashes, each hash containing :species and :level
    party = []
  
    pokemon_data.each do |data|
      species = data[:species]
      level = data[:level]
  
      if species && level.between?(1, GameData::GrowthRate.max_level)
        if data.keys.length > 2
          party.push({
            :species => species,
            :level => level,
            :moves => data[:moves] || [],
            :ability_index => data[:ability_index] || 0,
            :item => data[:item] || nil,
            :gender => data[:gender] || 0,
            :nature => data[:nature] || nil,
            :iv => data[:iv] || {},
            :ev => data[:ev] || {},
            :happiness => data[:happiness] || 70,
            :shininess => data[:shininess] || false
          })
        else
          party.push({
            :species => species,
            :level => level
          })
        end
      else
        raise "Invalid species or level for Pokémon: #{data.inspect}"
      end
    end
  
    if party.empty?
      raise "A trainer must have at least one Pokémon."
    end

    # ID. This may need changing if there are more missed numbers
    id_number = (GameData::Trainer::DATA.keys.length / 2) + 2
  
    # Create trainer structure and register it in memory
    trainer_data = {
      :id => [tr_type.to_sym, tr_name, tr_version],
      :id_number => id_number,
      :trainer_type => tr_type.to_sym,
      :name => tr_name,
      :version => tr_version,
      :items => [],
      :lose_text => "...",
      :pokemon => party
    }
  
    # Every trainer has 2 ID's
    GameData::Trainer::DATA[id_number] = GameData::Trainer.new(trainer_data)
    GameData::Trainer::DATA[trainer_data[:id]] = GameData::Trainer.new(trainer_data)
  
    return trainer_data
  end

  # Get a trainer, for overwrite
  def self.get_trainer(tr_type, tr_name, tr_version = 0, modern = false)
    trainer_key = [tr_type.to_sym, tr_name, tr_version]
    data_module = modern ? GameData::TrainerModern : GameData::Trainer
    return data_module::DATA[trainer_key]
  end

  # Set a trainer, replacing the existing one
  def self.set_trainer(tr_type, tr_name, tr_version, trainer_data, modern = false)
    trainer_key = [tr_type.to_sym, tr_name, tr_version]
    data_module = modern ? GameData::TrainerModern : GameData::Trainer

    # Ensure trainer data is deep copied to avoid unintended mutations
    copied_trainer_data = trainer_data.clone
    copied_trainer_data.pokemon = trainer_data.pokemon.clone

    data_module::DATA[trainer_key] = copied_trainer_data
  end

  # Register a new trainer type to the internal database
  def self.register_trainer(tr_type, tr_name, tr_version, pokemon_data, gender=0, base_money=30)
    existing_type = GameData::TrainerType.try_get(tr_type)
    if existing_type
      log_message("Trainer type #{existing_type} already exists.")
      return existing_type
    end

    # Dynamically assign an ID number to the new trainer type
    new_trainer_type_id = GameData::TrainerType::DATA.keys.length + 1
    GameData::TrainerType.register({
      :id => tr_type,
      :id_number => new_trainer_type_id,
      :real_name => tr_type.to_s,
      :battle_BGM => "Battle trainer.ogg",
      :victory_BGM => "Victory trainer.ogg",
      :gender => gender,
      :base_money => base_money
    })
    GameData::TrainerType.save
    GameData::TrainerType.load

    log_message("Trainer type #{GameData::TrainerType.try_get(tr_type)} registered.")
  end


  # Spawn a trainer event onto the map
  def self.spawn_trainer_event(
    tr_type:,
    tr_name:, 
    tr_version:, 
    pokemon_data:, 
    map_id:, 
    event_id:, 
    x:, 
    y:, 
    page_list:, 
    sprite_name: "002", 
    rotation: 2, 
    animate_steps: true
  )
    # Ensure trainer is loaded  
    register_trainer(tr_type, tr_name, tr_version, pokemon_data)

    # Create the trainer data
    trainer = TrainerHandler.create_new_trainer(tr_type, tr_name, tr_version, pokemon_data)
    
    # Put the trainer on the map.
    TrainerHandler.create_sprite_event(
      map_id, 
      event_id, 
      x, 
      y, 
      rotation, 
      sprite_name, 
      page_list, 
      animate_steps
    )
    return trainer
  end
end




