#===============================================================================
# SCOPE-02 – PIF fix: a Pokémon already past 510 EVs
# KIF 1.2.0-1.2.2's EV Allocation could spend points past PIF's 510 in all.
# PIF's clamps (evGain.clamp(0, 510 - total)) raise ArgumentError on such a
# Pokémon at each knockout and with each vitamin or Wing. It gains no EVs
# instead; taking EVs back on the Skills page brings it under 510 again.
# Always on: Battles & Challenges Off still reaches PIF's clamps.
#===============================================================================
class PokeBattle_Battle
  alias kif_ev510_pbGainEVsOne pbGainEVsOne unless method_defined?(:kif_ev510_pbGainEVsOne)
  def pbGainEVsOne(idxParty, defeatedBattler)
    pkmn = pbParty(0)[idxParty]
    return if pkmn && KIF::EVAlloc.ev_total(pkmn) > Pokemon::EV_LIMIT
    return kif_ev510_pbGainEVsOne(idxParty, defeatedBattler)
  end
end

alias kif_ev510_pbRaiseEffortValues pbRaiseEffortValues unless defined?(kif_ev510_pbRaiseEffortValues)
def pbRaiseEffortValues(pkmn, *args)
  return 0 if KIF::EVAlloc.ev_total(pkmn) > Pokemon::EV_LIMIT
  return kif_ev510_pbRaiseEffortValues(pkmn, *args)
end

alias kif_ev510_pbJustRaiseEffortValues pbJustRaiseEffortValues unless defined?(kif_ev510_pbJustRaiseEffortValues)
def pbJustRaiseEffortValues(pkmn, *args)
  return 0 if KIF::EVAlloc.ev_total(pkmn) > Pokemon::EV_LIMIT
  return kif_ev510_pbJustRaiseEffortValues(pkmn, *args)
end
