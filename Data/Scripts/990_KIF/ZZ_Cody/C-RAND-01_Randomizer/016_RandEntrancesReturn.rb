#===============================================================================
# C-RAND-01 – Randomizer: "Return to Pokémon Center" (pause menu)
#   Shuffled doors can drop you somewhere the normal game never would (below
#   a one-way ledge, inside a gym puzzle before you have Strength). With
#   Entrances on, the pause menu offers a free trip back to the last Pokémon
#   Center you used, so a bad spot is never the end of a run. Before the
#   first Center (a fresh run from Pallet) it goes home instead, the same
#   place the game sends you after a defeat then.
#   The last Center isn't always a way out: a shuffle can put a Center inside
#   a pocket you can't leave yet (entered by a ledge, needing Surf to get
#   out). Before going there it is checked with the Entrances logic and what
#   you have now; if the game can't be finished from it, Return goes home
#   instead (Pallet, or a random start's first Center), which every layout is
#   checked from.
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

      # The town a Pokémon Center map belongs to (its own map is just called
      # "Pokémon Center", so the question read "...Pokémon Center in Pokémon
      # Center?"): the outside of its usual door, before any shuffle
      def self.center_town(map_id)
        d = (dat rescue nil)
        if d && d[:door_by_id]
          o = d[:door_by_id].values.find { |x| x[:to] && x[:to][0] == map_id }
          name = o && d[:names][o[:map]]
          return name.to_s if name && !name.to_s.empty?
        end
        return (pbGetMapNameFromId(map_id) rescue "").to_s
      end

      # [map, x, y, direction, :center / :home] of the last Pokémon Center,
      # or home before any Center was used (PIF's pbStartOver does the same)
      # or when that Center is no way out (:home_unsafe)
      def self.return_target
        g = $PokemonGlobal
        if g && g.pokecenterMapId.to_i > 0
          dir = g.pokecenterDirection.to_i
          center = [g.pokecenterMapId, g.pokecenterX, g.pokecenterY, dir > 0 ? dir : 2, :center]
          h = home_spot
          return center if h.nil? || h[0] == center[0] || place_safe?(center[0])
          return h[0, 4] + [:home_unsafe]
        end
        return home_spot
      end

      # Home: a random start's first Center, otherwise the game's home spot
      def self.home_spot
        s = state
        if s.is_a?(Hash) && Rand.dget(:ent_start).to_i >= 1 && (o = start_origin(s)) && o[:to]
          dir = o[:to_dir].to_i
          return [o[:to][0], o[:to][1], o[:to][2], dir > 0 ? dir : 2, :home]
        end
        home = (GameData::Metadata.get.home rescue nil)
        return nil unless home && home[0].to_i > 0
        return [home[0], home[1], home[2], home[3].to_i > 0 ? home[3] : 2, :home]
      end

      # Can the game still be finished from this map, with what you have now?
      # (Entrances logic; a map it doesn't model counts as safe.) Remembered
      # until a flag, badge or item changes.
      def self.place_safe?(map_id)
        d = dat
        s = state
        return true unless d && s.is_a?(Hash) && layout_current?(s)
        nodes = (map_nodes(d)[map_id.to_s] || []).reject { |k| k.include?(":g") }
        return true if nodes.empty?
        mine = current_flags(d)
        key = [map_id, s.object_id, mine.sort_by(&:to_s)]
        return @safe_cache[1] if @safe_cache && @safe_cache[0] == key
        edges = edges_for(d, s[:in], s[:out])
        ok = nodes.any? { |n| beatable?(d, sweep(d, edges, mine, nil, n)[:seen]) }
        @safe_cache = [key, ok]
        return ok
      rescue => e
        KIF.log("Return safety check failed (#{e.class}: #{e.message})")
        return true
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
        path = KIF::Paths.log(RETURN_LOG)
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
  proc { (KIF::Rand::ER.return_target || [])[4] == :center ? "Return to Pokémon Center" : "Return home" }, icon: "menuIcons/POKEMON", order: 60,
  condition: proc { KIF::Rand::ER.can_return? },
  handler: proc { |scene|
    er = KIF::Rand::ER
    if $game_player.pbHasDependentEvents?
      scene.pbHideMenu
      pbMessage(_INTL("It can't be used when you have someone with you."))
      next :close
    end
    t = er.return_target
    name = t[4] == :center ? er.center_town(t[0]) : (pbGetMapNameFromId(t[0]) rescue "")
    scene.pbHideMenu
    if t[4] == :home_unsafe
      center = er.center_town($PokemonGlobal.pokecenterMapId)
      pbMessage(_INTL("From the Pokémon Center in {1} there's no way on yet with what you have.", center))
    end
    question = t[4] == :center ? _INTL("Go back to the Pokémon Center in {1}?", name) : _INTL("Go back home to {1}?", name)
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
