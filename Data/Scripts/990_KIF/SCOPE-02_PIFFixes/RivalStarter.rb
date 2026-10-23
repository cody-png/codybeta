#===============================================================================
# SCOPE-02 – PIF fix: the Johto/Hoenn/Sinnoh starter labs (2026-10-22)
# Their rival event (Map551/552/593 ev21) still calls the old
# setRivalStarter(s1, s2, s3, choice) with three species numbers and the
# player's pick; PIF 6.8.2 only has setRivalStarter(index1, index2), so Blue
# walking up crashed with ArgumentError. The old form works again: the rival
# gets the two starters the player didn't pick, fused (as PIF 6.8.2 does).
#===============================================================================
alias kif_rs_setRivalStarter setRivalStarter unless defined?(kif_rs_setRivalStarter)

def setRivalStarter(*args)
  return kif_rs_setRivalStarter(*args) unless args.length == 4
  starters = args[0, 3].map { |s| GameData::Species.get(s).id_number }
  starters.delete_at(args[3].to_i.clamp(0, 2))
  rival = if starters.any? { |s| s > NB_POKEMON }   # already a fusion: keep it
            starters[0]
          else
            getFusionSpecies(starters[0], starters[1]).id_number
          end
  pbSet(VAR_RIVAL_STARTER, rival)
  $game_switches[SWITCH_DEFINED_RIVAL_STARTER] = true
  return rival
end
