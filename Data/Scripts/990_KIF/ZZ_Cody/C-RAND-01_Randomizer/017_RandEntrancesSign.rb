#===============================================================================
# C-RAND-01 – Randomizer: Entrances door signs (2026-10-22)
#   Facing a shuffled door you've already used shows where it leads ("To:
#   Cerulean Gym"), in the top-left corner (where the map name shows) or just
#   above the door (Door signs: Off / Corner / Above door). It goes away when
#   you turn, move off, or a message, menu or event starts.
#===============================================================================
module KIF
  module Rand
    module ER
      # "To: <map>" for the door in front of the player, or nil (unused,
      # not shuffled, or no door there)
      def self.sign_text
        return nil unless active? && $game_player && $game_map
        dir = $game_player.direction
        fx = $game_player.x + (dir == 6 ? 1 : dir == 4 ? -1 : 0)
        fy = $game_player.y + (dir == 2 ? 1 : dir == 8 ? -1 : 0)
        seen = state[:seen] || []
        $game_map.events.each_value do |ev|
          next unless ev.x == fx && ev.y == fy
          t = targets[[$game_map.map_id, ev.id]]
          next unless t && seen.include?([t[4], t[5]])
          name = dat[:names][t[0]].to_s
          return name.empty? ? nil : _INTL("To: {1}", name)
        end
        return nil
      end

      # Shown only while nothing else is on screen
      def self.sign_allowed?
        return false if $game_temp.message_window_showing || $game_temp.in_menu
        return false if $game_temp.player_transferring || $game_temp.transition_processing
        return false if $game_player.moving? || pbMapInterpreterRunning?
        return true
      end

      class DoorSign
        def initialize(owner = nil)
          @owner = owner   # the spriteset it belongs to: only the current map's shows
          @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @viewport.z = 99999
          @window = nil
          @text = nil
          @tick = 0
        end

        def disposed?
          return @viewport.disposed?
        end

        def dispose
          @window.dispose if @window && !@window.disposed?
          @viewport.dispose unless @viewport.disposed?
        end

        def update
          return if disposed?
          @tick += 1
          return unless @tick % 4 == 1   # a look every few frames is plenty
          mode = Rand.dget(:ent_sign)
          mine = @owner.nil? || (.respond_to?(:spriteset) && $scene.spriteset.equal?(@owner))
          text = (mode > 0 && mine && ER.sign_allowed?) ? ER.sign_text : nil
          if text != @text
            @text = text
            @window.dispose if @window && !@window.disposed?
            @window = text ? make_window(text, mode) : nil
          end
        rescue => e
          @text = nil
          KIF.log("Door sign failed (#{e.class}: #{e.message})")
        end

        def make_window(text, mode)
          w = Window_AdvancedTextPokemon.new(text)
          w.resizeToFit(text, Graphics.width)
          w.viewport = @viewport
          if mode == 2   # above the door, kept on screen
            dir = $game_player.direction
            ex = $game_player.screen_x + (dir == 6 ? 32 : dir == 4 ? -32 : 0)
            ey = $game_player.screen_y - 32 + (dir == 2 ? 32 : dir == 8 ? -32 : 0)
            w.x = [[ex - w.width / 2, 0].max, Graphics.width - w.width].min
            w.y = [ey - w.height - 4, 0].max
          else
            w.x = 0
            w.y = 0
          end
          return w
        end
      end

      # one sign per map spriteset, kept on the spriteset itself (crossing
      # back to a still-loaded map reuses its sign)
      def self.update_sign
        return unless $scene.is_a?(Scene_Map) && (spr = $scene.spriteset)
        sign = spr.instance_variable_get(:@kif_door_sign)
        return if sign && !sign.disposed?
        sign = DoorSign.new(spr)
        spr.instance_variable_set(:@kif_door_sign, sign)
        spr.addUserSprite(sign)
      end
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e| KIF::Rand::ER.update_sign if KIF::Rand.dget(:ent_sign) > 0 && KIF::Rand::ER.active? }
