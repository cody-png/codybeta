class VisitorSecretBase < SecretBase
  attr_reader :trainer_name, :trainer_badges, :trainer_game_mode
  attr_reader :trainer_appearance, :trainer_team

  def initialize(biome:, outside_map_id:, outside_entrance_position:, inside_map_id:, layout:, base_layout_type:, base_message:, trainer_data:)
    super(biome: biome,
          outside_map_id: outside_map_id,
          outside_entrance_position: outside_entrance_position,
          inside_map_id: inside_map_id,
          layout: layout,
          base_layout_type: base_layout_type,
          visitor_message: base_message,
          is_visitor: true,)

    @trainer_name = trainer_data.name
    @trainer_badges = trainer_data.nb_badges || 0
    @trainer_game_mode = trainer_data.game_mode || 0
    @trainer_appearance = trainer_data.appearance
    @trainer_team = trainer_data.team
  end

  def dump_info
    echoln "=== Visitor Secret Base ==="
    echoln "Biome: #{@biome_type}"
    echoln "Outside Map ID: #{@outside_map_id}"
    echoln "Inside Map ID: #{@inside_map_id}"
    echoln "Outside Entrance Position: #{@outside_entrance_position.inspect}"
    echoln "Inside Entrance Position: #{@inside_entrance_position.inspect}"
    echoln "Layout Type: #{@base_layout_type}"
    echoln "Base Name: #{@base_name}"
    echoln "Base Message: #{@base_message}"
    echoln "Visitor?: #{@is_visitor}"

    echoln "--- Trainer Info ---"
    echoln "Name: #{@trainer_name}"
    echoln "Badges: #{@trainer_badges}"
    echoln "Game Mode: #{@trainer_game_mode}"
    echoln "Appearance: #{@trainer_appearance.inspect}"

    echoln "--- Trainer Team ---"
    if @trainer_team && !@trainer_team.empty?
      @trainer_team.each_with_index do |pokemon, i|
        echoln "  #{i + 1}. #{pokemon.name} (#{pokemon.species}, Lv#{pokemon.level})"
      end
    else
      echoln "  (No Pokémon)"
    end

    echoln "============================="
  end

end
