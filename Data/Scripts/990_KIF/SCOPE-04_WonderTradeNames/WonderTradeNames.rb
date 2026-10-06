#===============================================================================
# SCOPE-04 – KIF's extra Wonder Trade names
# Source: KIF 0.20.7 052_AddOns/WonderTrade_names.rb (vs PIF 6.4.5)
#   :145-157   trainer names (RandTrainerNames_others)
#   :1079-1096 Pokémon nicknames (RandPokeNick): KIF's contributors
# Only names 6.8.2's lists don't already have are added.
#===============================================================================
module KIF
  module WonderTradeNames
    TRAINERS = ["Miyamoto", "Silph Co.", "Santa Claus", "Team Rocket", "Mom", "Dad"]
    NICKNAMES = ["Reïzod", "Lamakhun", "Méliosa", "Garlayn", "Sylvi", "JustAnotherUser",
                 "BlueWoppo", "HungryPickles", "DemICE", "FerrousLupus", "ClemShino",
                 "Darkmost", "Globby", "TM", "Trapstarr", "TheDuoDesign", "MinamoStyle"]

    def self.add(list, names)
      names.each { |n| list.push(n) unless list.include?(n) }
    rescue => e
      KIF.log("Wonder Trade names: #{e.message}")
    end
  end
end

KIF::WonderTradeNames.add(RandTrainerNames_others, KIF::WonderTradeNames::TRAINERS) if defined?(RandTrainerNames_others)
KIF::WonderTradeNames.add(RandPokeNick, KIF::WonderTradeNames::NICKNAMES) if defined?(RandPokeNick)
