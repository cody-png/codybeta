#===============================================================================
# SCOPE-02 – GameData::Species#get_baby_species is public again
# 6.8.2 moved it below a `private` line (010_Data/002_PBS data/008_Species.rb
# :295/:327), but the Day Care (007_Overworld_DayCare.rb:240), the randomizer's
# 1st-stage starters (025-Randomizer/randomizer.rb:363, Starters.rb:61) and
# more call it from outside. Found by the KIF Test Kit (2026-10-06).
#===============================================================================
module GameData
  class Species
    public :get_baby_species if private_method_defined?(:get_baby_species)
  end
end
