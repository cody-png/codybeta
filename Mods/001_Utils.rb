###################################################################################################
# Author: An Unsocial Pigeon                                                                      #
# Discord: @anunsocialpigeon                                                                      #
# For any issues or inquiries, feel free to reach out on Discord.                                 #
#                                                                                                 #
# You are allowed to use this file in your own mod,                                               # 
# on condition that you correctly credit me (An Unsocial Pigeon) <3                               #
###################################################################################################


module DebugMode
  @debug_mode = true

  def self.debug_mode
    @debug_mode
  end
end


# Helper method to log messages to a file for debugging
def log_message(message)
  return unless DebugMode.debug_mode
  File.open("mod_load_debug.txt", "a") do |file|
    file.puts("#{Time.now}: #{message}")
  end
end

# Clear the file on first load
File.open("mod_load_debug.txt", "w") do |file|
  file.puts("")
end



def get_national_dex(if_id)
  return GameData::NAT_DEX_MAPPING[if_id] ? GameData::NAT_DEX_MAPPING[if_id] : if_id
end

# Store information about where to save shit for the mods to use.
class ModData
  @location = Dir.pwd.end_with?("KIF/") ? "Mods/ModData/" : "Scripts/Data/998_Mods/ModData"

  def self.location
    return @location
  end
end


class LastMapLoadedTracker
  @@last_map_id = nil
  @@last_maps = []

  def self.last_map_id
    @@last_map_id
  end

  def self.last_map_id=(map_id)
    @@last_map_id = map_id
    @@last_maps << map_id
    @@last_maps.shift if @@last_maps.length > 5
  end

  def self.last_maps
    @@last_maps
  end

end

Events.onMapChange += proc {
  if $game_map 
    LastMapLoadedTracker.last_map_id = $game_map.map_id
  end
}




