#===============================================================================
# C-AP-01 – Archipelago PP Drain trap (2026-10-23)
#   "TRAP_PP_DRAIN" (a quiet moment on the map, as every trap, Traps.rb): one
#   random move of the lead Pokemon (the first able one, never an egg) that
#   still has PP drops to 0 PP. No move with PP left, or no Pokemon that can
#   battle: nothing happens (and the message says so). HP and status are not
#   touched (Nuzlocke); a Pokemon Center, an Ether or a Leppa Berry restores
#   the PP as usual.
#===============================================================================
module KIF
  module AP
    module Traps
      module_function

      def run_pp_drain(who)
        pk = $Trainer.first_able_pokemon
        unless pk
          pbMessage(_INTL("A PP Drain Trap from {1}! None of your Pokémon can battle, so nothing happens.", who))
          return
        end
        moves = pk.moves.select { |m| m && m.id && m.pp > 0 }
        if moves.empty?
          pbMessage(_INTL("A PP Drain Trap from {1}! {2}'s moves have no PP left, so nothing happens.", who, pk.name))
          return
        end
        m = moves[rand(moves.length)]
        m.pp = 0
        KIF.log("Archipelago: PP Drain on #{pk.name}'s #{m.id}")
        pbMessage(_INTL("A PP Drain Trap from {1}! {2}'s {3} ran out of PP.", who, pk.name, m.name))
      end
    end
  end
end
