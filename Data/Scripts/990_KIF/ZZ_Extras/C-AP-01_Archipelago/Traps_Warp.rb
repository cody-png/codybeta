#===============================================================================
# C-AP-01 – Archipelago Warp trap (2026-10-23)
#   "TRAP_WARP" (a quiet moment, as every trap, Traps.rb): the player is sent
#   to the last Pokemon Center they healed at, as after a defeat but with no
#   money lost and no heal. The place and the trip are the Entrance
#   Randomizer's "Return to Pokemon Center" (016_RandEntrancesReturn.rb:
#   ER.return_target / ER.do_return): PIF's blackout spot (pokecenterMapId,
#   in front of the nurse), home before any Center (PIF's pbStartOver does
#   the same; "You were sent back home."), and pbCancelVehicles, so a surfing or cycling player lands on
#   foot on the Center's floor (always walkable: nothing can strand them).
#   Waits (stays in the save) while: in the Safari Zone or the Bug-Catching
#   Contest (they end through their own gates), in the Pokemon League (the
#   lobby, Elite Four, Champion, Hall of Fame), someone walks with the player
#   (an escort), during the intro, while a scene holds the player (movement
#   lock switch or the player hidden: Moonlit Forest's dream), or with no
#   Pokemon; never on Pinkan Island (Traps.run_one) and never to a Center
#   there (home instead). Out of a gym the gym's type is reset (pbStartOver).
#   Party Lock and Confusion don't matter here: the trip doesn't touch the
#   party, and Confusion only turns the buttons while walking.
#===============================================================================
module KIF
  module AP
    module Traps
      LEAGUE_MAPS = [314, 315, 316, 317, 318, 328, 341]   # Indigo Plateau's League: lobby, Elite Four, Champion, Hall of Fame

      module_function

      # The one place that picks where the Warp trap sends the player.
      # TODO: once Archipelago links saves with Entrances (door shuffle) on,
      # send them to the spawn / start point here instead (ER.home_spot) while
      # Entrances are on; linked saves have Entrances off today (FORCED).
      def warp_target
        er = KIF::Rand::ER
        t = er.return_target
        t = er.home_spot if t && KIF::Rand.pinkan?(t[0].to_i)
        return t
      end

      def warp_ready?
        return false if pbInSafari? || pbInBugContest?
        return false if LEAGUE_MAPS.include?($game_map.map_id)
        return false if $game_switches[SWITCH_DURING_INTRO] || $Trainer.party.empty?
        return false if $game_player.pbHasDependentEvents?
        # a scene that holds the player (Moonlit Forest's dream): only its own events let go
        return false if $game_switches[SWITCH_LOCK_PLAYER_MOVEMENT] || $game_player.transparent
        return !warp_target.nil?
      rescue StandardError
        return false
      end

      def run_warp(who)
        t = warp_target
        pbMessage(t[4] == :center ? _INTL("A Warp Trap from {1}! You were sent back to the last Pokémon Center.", who) :
                                    _INTL("A Warp Trap from {1}! You were sent back home.", who))
        KIF.log("Archipelago: Warp trap from map #{$game_map.map_id} to #{t[0]} (#{t[4]})")
        # out of a gym without its exit tiles: as pbStartOver, or trainers everywhere keep its type
        $game_variables[VAR_CURRENT_GYM_TYPE] = -1
        KIF::Rand::ER.do_return(t)
      end
    end
  end
end
