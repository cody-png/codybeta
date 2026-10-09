#===============================================================================
# C-RAND-01 – Randomizer: "Return to Pokémon Center" (pause menu)
#   Shuffled doors can drop you somewhere the normal game never would (below
#   a one-way ledge, inside a gym puzzle before you have Strength). With
#   Entrances on, the pause menu offers a free trip back to the last Pokémon
#   Center you used, so a bad spot is never the end of a run. Before the
#   first Center (a fresh run from Pallet) it goes home instead, the same
#   place the game sends you after a defeat then.
#   Every use is written to KIF_entrance_returns.txt in the save folder (where
#   you were, the doors you took last), so stuck spots can be found and fixed.
#===============================================================================
module KIF
  module Rand
    module ER
      RETURN_LOG = "KIF_entrance_returns.txt"
      RETURN_LOG_MAX = 300   # lines kept

      class << self
        attr_accessor :pending_return
      end

      # [map, x, y, direction, :center / :home] of the last Pokémon Center,
      # or home before any Center was used (PIF's pbStartOver does the same)
      def self.return_target
        g = $PokemonGlobal
        if g && g.pokecenterMapId.to_i > 0
          dir = g.pokecenterDirection.to_i
          return [g.pokecenterMapId, g.pokecenterX, g.pokecenterY, dir > 0 ? dir : 2, :center]
        end
        home = (GameData::Metadata.get.home rescue nil)
        return nil unless home && home[0].to_i > 0
        return [home[0], home[1], home[2], home[3].to_i > 0 ? home[3] : 2, :home]
      end

      def self.can_return?
        return false unless active?
        # from the starter on (Oak's errand before the Pokédex can strand you
        # too); never during the intro
        return false unless $game_map && $Trainer && !$Trainer.party.empty? && !$game_switches[SWITCH_DURING_INTRO]
        return false if KIF::PauseMenu.restricted?
        # the Safari Zone and the Bug-Catching Contest end through their own gates
        return false if (pbInSafari? rescue false) || (pbInBugContest? rescue false)
        t = return_target
        return t && $game_map.map_id != t[0]
      rescue
        return false
      end

      # Where you were and the last doors you used, for finding stuck spots
      def self.log_return
        s = state
        d = dat
        here = $game_map.map_id
        lines = []
        lines << "#{Time.now.strftime('%Y-%m-%d %H:%M')} seed #{Rand.seed} | at #{d[:names][here] || here} (#{here}) #{$game_player.x},#{$game_player.y}" \
                 " | badges #{$Trainer.badge_count} | party #{$Trainer.party.map(&:level).inspect}" \
                 " | settings #{s[:shape]}/#{s[:doors]}/#{s[:coupled] ? 1 : 0} regions #{(s[:regions] || [0]).inspect}"
        (s[:seen] || []).last(10).each { |id, kind| lines << "    #{describe(id, kind)}" }
        path = File.join(KIF.save_dir, RETURN_LOG)
        old = File.exist?(path) ? File.readlines(path, chomp: true) : []
        all = (old + lines).last(RETURN_LOG_MAX)
        File.open(path, "wb") { |f| f.write(all.join("\n") + "\n") }
      rescue => e
        KIF.log("Return log failed (#{e.class}: #{e.message})")
      end

      def self.do_return
        t = return_target
        return unless t
        pbFadeOutIn {
          $game_temp.player_new_map_id    = t[0]
          $game_temp.player_new_x         = t[1]
          $game_temp.player_new_y         = t[2]
          $game_temp.player_new_direction = t[3]
          pbCancelVehicles
          $scene.transfer_player
          $game_map.autoplay
          $game_map.refresh
        }
      end
    end
  end
end

KIF::PauseMenu.add(:kif_er_return,
  proc { (KIF::Rand::ER.return_target || [])[4] == :home ? "Return home" : "Return to Pokémon Center" }, icon: "menuIcons/POKEMON", order: 60,
  condition: proc { KIF::Rand::ER.can_return? },
  handler: proc { |scene|
    er = KIF::Rand::ER
    if $game_player.pbHasDependentEvents?
      scene.pbHideMenu
      pbMessage(_INTL("It can't be used when you have someone with you."))
      next :close
    end
    t = er.return_target
    name = (pbGetMapNameFromId(t[0]) rescue "")
    scene.pbHideMenu
    question = t[4] == :home ? _INTL("Go back home to {1}?", name) : _INTL("Go back to the Pokémon Center in {1}?", name)
    if pbConfirmMessage(question)
      er.log_return
      er.pending_return = true
      next :close
    end
    next :close
  })

# The trip itself happens once the menu has closed
class Scene_Map
  alias kif_erret_update update unless method_defined?(:kif_erret_update)

  def update
    kif_erret_update
    begin
      return unless KIF::Rand::ER.pending_return && $scene == self
      return if $game_temp.message_window_showing || $game_player.moving?
      KIF::Rand::ER.pending_return = false
      KIF::Rand::ER.do_return
    rescue => e
      KIF::Rand::ER.pending_return = false
      KIF.log("Return to Pokémon Center failed (#{e.class}: #{e.message})")
    end
  end
end
