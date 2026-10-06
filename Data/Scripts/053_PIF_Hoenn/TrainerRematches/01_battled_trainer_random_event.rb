# frozen_string_literal: true


#eventType
# :EVOLVE
# :FUSE
# :UNFUSE
# :REVERSE
# :CAUGHT
class BattledTrainerRandomEvent
  attr_accessor :eventType
  attr_accessor :caught_pokemon #species_sym

  attr_accessor :unevolved_pokemon #species_sym
  attr_accessor :evolved_pokemon #species_sym

  attr_accessor :fusion_head_pokemon #species_sym
  attr_accessor :fusion_body_pokemon #species_sym
  attr_accessor :fusion_fused_pokemon #species_sym


  attr_accessor :unreversed_pokemon #species_sym
  attr_accessor :reversed_pokemon #species_sym


  attr_accessor :unfused_pokemon #species_sym



  def initialize(eventType)
    @eventType = eventType
  end
end