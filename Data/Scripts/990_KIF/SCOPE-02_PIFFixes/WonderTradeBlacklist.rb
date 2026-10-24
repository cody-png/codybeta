#===============================================================================
# SCOPE-02 – PIF fix: Wonder Trade's never-give list works (2026-10-23)
# pbWonderTrade (052_InfiniteFusion/Gameplay/WonderTrade/Wondertrade.rb) adds
# Arceus, Mew, Celebi, Lugia, Ho-Oh and Mewtwo to a list it never gives, but
# checkifBlacklisted compared those symbols with dex numbers, so nothing ever
# matched: after the League (or on a premium trade's lucky roll) they could be
# given. Fixing the compare alone would crash: the line that uses it also reads
# ignoreExcept, whose definition PIF commented out ("tiny chance to include
# legendaries"), so it is defined here as never.
# Found by the kit's hook sweep (416).
#===============================================================================
def checkifBlacklisted(species, blacklist)
  ids = blacklist.map { |s| s.is_a?(Integer) ? s : (GameData::Species.get(s).id_number rescue nil) }.compact
  return true if ids.include?(getBasePokemonID(species, true))
  return true if ids.include?(getBasePokemonID(species, false))
  return false
end

# pbWonderTrade's "&& !ignoreExcept": the never-give list always applies
def ignoreExcept
  return false
end
