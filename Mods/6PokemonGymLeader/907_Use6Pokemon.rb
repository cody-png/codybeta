###################################################################################################
# Author: An Unsocial Pigeon                                                                      #
# Discord: @anunsocialpigeon                                                                      #
# For any issues or inquiries, feel free to reach out on Discord.                                 #
#                                                                                                 #
# You are allowed to use this file in your own mod,                                               # 
# on condition that you correctly credit me (An Unsocial Pigeon) <3                               #
###################################################################################################


module PokemonSelection
  class << self
    alias_method :original_choose, :choose

    # Override the choose method to force 
    def choose(min=1, max=6, canCancel=false, acceptFainted=false, ableproc=nil)
      map_id = $game_map.map_id if $game_map && $game_map.map_id
      log_message("PokemonSelection.choose called from map #{map_id}") if map_id
      
      gym_map_ids = [
        386,          # Brock's gym
        4,            # Misty's gym
        24,           # Surge's gym
        542,          # Erika's gym
        479,          # Koga's gym
        152,          # Sabrina's gym
        221,          # Blaine's gym
        85            # Giovanni's gym
      ]
      
      return original_choose(min, map_id && gym_map_ids.include?(map_id) ? 6 : max, canCancel, acceptFainted, ableproc)
    end
  end
end



