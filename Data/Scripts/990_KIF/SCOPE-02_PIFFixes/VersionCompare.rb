#===============================================================================
# SCOPE-02 – PIF fix: one way to compare versions
# PIF's is_higher_version (SystemUtils.rb) treated "6.9" and "6.9.0" as
# different, so a Mystery Gift asking for "6.9.0" refused a game on "6.9". It
# now answers with KIF.newer_version?, the compare the updater and the mod
# rules use.
#===============================================================================
KIF.guard_base("052_InfiniteFusion/Gameplay/0_Utilities/SystemUtils.rb", 2082473874, "is_higher_version")

# true when the game's version is the latest one or newer
def is_higher_version(gameVersion, latestVersion)
  return !KIF.newer_version?(latestVersion, gameVersion)
end
