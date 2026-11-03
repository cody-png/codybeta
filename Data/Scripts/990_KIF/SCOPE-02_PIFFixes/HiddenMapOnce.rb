#===============================================================================
# SCOPE-02 – PIF fix: the hidden-ability map is chosen once per step count
# (perf-frame, 2026-11-01)
# PIF's map-update handler (052_InfiniteFusion/Gameplay/HiddenAbilityRoutes/
# HiddenAbilityMaps.rb) calls changeHiddenMap whenever the step count is a
# multiple of 1500. It does so on EVERY frame the count stays one: all of a
# new game until the first step (count 0), and whenever the player stands
# still or talks on step 1500, 3000... Each call picked another map, and
# pbSet then asks the map to refresh every event, so those frames each paid
# for a full map refresh (about 21,000 objects a frame in a town, and the
# trade, quest and dialogue bubbles looked up again on every event).
# Once per step count (and once per loaded game) is the choice the handler
# was written for: the same list, the same odds.
#===============================================================================
module KIF
  module HiddenMapOnce
    @last = nil

    # true the first time it is asked for this step count of this game
    def self.due?
      g = $PokemonGlobal
      return true unless g
      key = [g.object_id, g.stepcount]
      return false if @last == key
      @last = key
      return true
    end
  end
end

alias kif_hm_changeHiddenMap changeHiddenMap unless defined?(kif_hm_changeHiddenMap)

def changeHiddenMap(*args)
  return unless KIF::HiddenMapOnce.due?
  return kif_hm_changeHiddenMap(*args)
end
