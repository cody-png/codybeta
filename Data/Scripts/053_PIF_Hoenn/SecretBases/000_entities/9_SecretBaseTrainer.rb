class SecretBaseTrainer
  attr_accessor :name
  attr_accessor :nb_badges
  attr_accessor :game_mode
  attr_accessor :appearance #TrainerAppearance
  attr_accessor :team #Array of Pokemon

  def initialize(name, nb_badges, game_mode, appearance, team)
    @name = name
    @nb_badges = nb_badges
    @game_mode = game_mode
    @appearance = appearance
    @team = team
  end
end