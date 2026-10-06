###################################################################################################
# Author: An Unsocial Pigeon                                                                      #
# Discord: @anunsocialpigeon                                                                      #
# For any issues or inquiries, feel free to reach out on Discord.                                 #
#                                                                                                 #
# You are allowed to use this file in your own mod,                                               # 
# on condition that you correctly credit me (An Unsocial Pigeon) <3                               #
###################################################################################################


module BaseGameType
  @baseGameType
  def self.setup
    version = File.read('Data/VERSION').strip

    if version.split('.').first.to_i < 5
      @baseGameType = "KIF"
    elsif version.split('.').first.to_i >= 5
      @baseGameType = "PIF"
    else
      raise "Unknown game type. Your mods may be out of date."  
    end

    log_message("Game is: #{@baseGameType} (#{version})")
  end

  def self.get_base_game_type()
    return @baseGameType
  end
end
BaseGameType.setup()

# Enforce recursive mod loading for KIF.
def enforce_recursive_mod_loading_kif() 
  folders = []
  Dir.foreach("Mods/") do |f|
    folders.push("Mods/#{f}") if File.directory?("Mods/#{f}") && f != "." && f != ".." && f != "ModData"
  end

  folders.sort!
  folders.each do |folder|
    load_scripts_from_folder(folder) if File.directory?(folder) && folder != "." && folder != ".."
  end

  log_message("Recursive loading of mod folders complete.")
end

# Enforce recursive mod loading for KIF.
enforce_recursive_mod_loading_kif() if BaseGameType.get_base_game_type() == "KIF"

