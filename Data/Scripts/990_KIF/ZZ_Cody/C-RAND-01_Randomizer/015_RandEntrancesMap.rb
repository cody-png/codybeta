#===============================================================================
# C-RAND-01 – Randomizer: the Entrance log map
#   The Town Map with a line for every shuffled door you have used: from the
#   door's own town or route to where the place behind it really belongs.
#   Newest first; Up/Down (or Left/Right) walk the doors, A opens the list.
#===============================================================================
module KIF
  module Rand
    module ER
      module LogMap
        TILE     = 16
        VIEW_X   = 16
        VIEW_Y   = 32
        VIEW_W   = 480
        VIEW_H   = 320
        OUTLINE  = Color.new(24, 24, 32)
        COLORS   = { dungeon: Color.new(176, 104, 232), building: Color.new(248, 200, 48) }
        SELECTED = Color.new(240, 56, 48)
        WHITE    = Color.new(248, 248, 248)
        SHADOW   = Color.new(40, 40, 48)

        module_function

        # Town-map tile of a map, or nil
        def pos_of(map_id)
          @pos_cache ||= {}
          return @pos_cache[map_id] if @pos_cache.key?(map_id)
          md = (GameData::MapMetadata.try_get(map_id) rescue nil)
          p = md && md.town_map_position
          @pos_cache[map_id] = (p.is_a?(Array) && p.length >= 3) ? [p[1], p[2]] : nil
        end

        # The doors used so far, newest first. Each entry:
        # {from: door, to: door it led to, kind: :in/:out, pool:, a: [px, py], b: [px, py]}
        # In a coupled layout going back out the way you came isn't a new line
        # (the line is shown the way in, dated by when either way was first used).
        def entries
          d = ER.dat; s = ER.state
          return [] unless d && s && s[:seen]
          found = {}       # key => [order, door, partner, kind]
          s[:seen].each_with_index do |(door_id, kind), n|
            o = d[:door_by_id][door_id]
            next unless o
            partner_id = (kind == :in ? s[:in][door_id] : (s[:out] || {})[door_id]) || door_id
            t = d[:door_by_id][partner_id]
            next unless t
            key = s[:coupled] ? [[o[:id], t[:id]].sort] : [door_id, kind]
            if found[key]
              found[key][1, 3] = [o, t, kind] if kind == :in && found[key][3] != :in
              next
            end
            found[key] = [n, o, t, kind]
          end
          out = []
          found.values.sort_by { |v| -v[0] }.each do |_, o, t, kind|
            a = pos_of(o[:map]); b = pos_of(t[:map])
            next unless a && b
            out << { from: o, to: t, kind: kind, pool: o[:pool],
                     a: [a[0] * TILE + TILE / 2, a[1] * TILE + TILE / 2],
                     b: [b[0] * TILE + TILE / 2, b[1] * TILE + TILE / 2] }
          end
          spread(out)
          return out
        end

        # Lines between the same two places bend apart, alternating sides
        def spread(list)
          groups = Hash.new(0)
          list.reverse_each do |e|                  # oldest first, so a line keeps its bend
            key = [e[:a], e[:b]].sort
            k = groups[key]
            groups[key] += 1
            e[:bend] = (0.16 + 0.12 * (k / 2)) * (k.even? ? 1 : -1)
            e[:flip] = (key[0] != e[:a])            # bend from a fixed side for both directions
            e[:loop] = k
          end
        end

        # Points along a gentle curve from a to b (a small loop when a == b)
        def points(e)
          ax, ay = e[:a]; bx, by = e[:b]
          if ax == bx && ay == by
            r = 6 + 3 * e[:loop]
            cx = ax; cy = ay - r
            n = 8 * r
            return (0..n).map { |i| t = 2 * Math::PI * i / n; [(cx + r * Math.sin(t)).round, (cy + r * Math.cos(t)).round] }
          end
          dx = bx - ax; dy = by - ay
          dist = Math.sqrt(dx * dx + dy * dy)
          sign = e[:flip] ? -1 : 1
          bend = e[:bend] * dist * sign
          mx = (ax + bx) / 2.0 - dy / dist * bend
          my = (ay + by) / 2.0 + dx / dist * bend
          n = [(dist / 1.5).ceil, 4].max
          pts = []
          (0..n).each do |i|
            t = i.to_f / n
            u = 1 - t
            x = (u * u * ax + 2 * u * t * mx + t * t * bx).round
            y = (u * u * ay + 2 * u * t * my + t * t * by).round
            pts << [x, y] unless pts.last == [x, y]
          end
          return pts
        end

        def draw_line(bmp, pts, color, width = 2, outline = true)
          pts.each { |x, y| bmp.fill_rect(x - 1, y - 1, width + 2, width + 2, OUTLINE) } if outline
          pts.each { |x, y| bmp.fill_rect(x, y, width, width, color) }
        end

        def draw_ends(bmp, e, color)
          ax, ay = e[:a]; bx, by = e[:b]
          bmp.fill_rect(ax - 3, ay - 3, 7, 7, OUTLINE)       # the door: a square
          bmp.fill_rect(ax - 2, ay - 2, 5, 5, color)
          bmp.fill_rect(bx - 3, by - 3, 7, 7, OUTLINE)       # where it led: a ring
          bmp.fill_rect(bx - 2, by - 2, 5, 5, WHITE)
          bmp.fill_rect(bx - 1, by - 1, 3, 3, color)
        end

        # The area to show for an entry: centred on the line, or on the door
        # when the line is longer than the window
        def focus(e)
          ax, ay = e[:a]; bx, by = e[:b]
          if (ax - bx).abs < VIEW_W - 64 && (ay - by).abs < VIEW_H - 96
            return [(ax + bx) / 2, (ay + by) / 2 + 16]
          end
          return [ax, ay + 16]
        end

        def line_text(e)
          o = e[:from]; t = e[:to]
          if e[:kind] == :in
            return [ER.door_name(o), _INTL("leads into {1}", ER.door_name(t))]
          end
          return [_INTL("Leaving {1}", ER.door_name(o)), _INTL("comes out at {1}", ER.door_name(t))]
        end

        def map_file
          name = (isPostgame? rescue false) ? "map_postgame" : "map"
          return "Graphics/Pictures/map/#{name}"
        end
      end

      class LogMapScene
        include LogMap

        def initialize(list)
          @list = list
          @index = 0
        end

        def start
          @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @vp.z = 99999
          @mapvp = Viewport.new(VIEW_X, VIEW_Y, VIEW_W, VIEW_H)
          @mapvp.z = 100000
          @topvp = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @topvp.z = 100001
          @sprites = {}
          @sprites["frame"] = IconSprite.new(0, 0, @vp)        # the Town Map's frame, under the map
          @sprites["frame"].setBitmap("Graphics/Pictures/mapbg")
          @sprites["map"] = IconSprite.new(0, 0, @mapvp)
          @sprites["map"].setBitmap(map_file)
          mw = @sprites["map"].bitmap.width; mh = @sprites["map"].bitmap.height
          @max_ox = [mw - VIEW_W, 0].max
          @max_oy = [mh - VIEW_H, 0].max
          # every line found so far, then the chosen one on top
          @sprites["lines"] = BitmapSprite.new(mw, mh, @mapvp)
          @sprites["lines"].opacity = 180
          draw_all
          @sprites["sel"] = BitmapSprite.new(mw, mh, @mapvp)
          here = pos_of($game_map.map_id) rescue nil
          if here
            @sprites["you"] = IconSprite.new(0, 0, @mapvp)
            @sprites["you"].setBitmap("Graphics/Pictures/map/location_icon")
            @sprites["you"].ox = @sprites["you"].bitmap.width / 2
            @sprites["you"].oy = @sprites["you"].bitmap.height / 2
            @sprites["you"].x = here[0] * TILE + TILE / 2
            @sprites["you"].y = here[1] * TILE + TILE / 2
          end
          @sprites["info"] = BitmapSprite.new(VIEW_W, 52, @topvp)
          @sprites["info"].x = VIEW_X
          @sprites["info"].y = VIEW_Y + VIEW_H - 52
          @sprites["text"] = BitmapSprite.new(Graphics.width, Graphics.height, @topvp)
          pbSetSystemFont(@sprites["text"].bitmap)
          pbSetSmallFont(@sprites["info"].bitmap)
          select(0, true)
          pbFadeInAndShow(@sprites) { update_view }
        end

        def draw_all
          bmp = @sprites["lines"].bitmap
          bmp.clear
          @list.reverse_each do |e|           # newest drawn last, so it sits on top
            draw_line(bmp, points(e), COLORS[e[:pool]] || COLORS[:building], 2, false)
          end
          @list.reverse_each { |e| draw_ends(bmp, e, COLORS[e[:pool]] || COLORS[:building]) }
        end

        def select(i, jump = false)
          @index = i
          e = @list[i]
          bmp = @sprites["sel"].bitmap
          bmp.clear
          draw_line(bmp, points(e), SELECTED, 3)
          draw_ends(bmp, e, SELECTED)
          fx, fy = focus(e)
          @target = [[[fx - VIEW_W / 2, 0].max, @max_ox].min, [[fy - VIEW_H / 2, 0].max, @max_oy].min]
          if jump
            @mapvp.ox = @target[0]; @mapvp.oy = @target[1]
          end
          draw_text
        end

        def draw_text
          e = @list[@index]
          t = @sprites["text"].bitmap
          t.clear
          s = ER.state
          found = s[:seen].map(&:first).uniq.length
          left = [s[:in].length - found, 0].max
          pbDrawShadowText(t, 16, 0, 300, 32, _INTL("Entrance log"), WHITE, SHADOW)
          pbDrawShadowText(t, Graphics.width - 316, 0, 300, 32, _INTL("{1} found, {2} to go", found, left), WHITE, SHADOW, 1)
          pbDrawShadowText(t, 16, Graphics.height - 32, Graphics.width - 32, 32,
                           _INTL("{1}/{2}   Up/Down: next door   A: list   B: back", @index + 1, @list.length), WHITE, SHADOW)
          i = @sprites["info"].bitmap
          i.clear
          i.fill_rect(0, 0, VIEW_W, 52, Color.new(16, 16, 24, 190))
          a, b = line_text(e)
          i.fill_rect(8, 10, 8, 8, OUTLINE)
          i.fill_rect(9, 11, 6, 6, COLORS[e[:pool]] || COLORS[:building])
          pbDrawShadowText(i, 22, 0, VIEW_W - 30, 26, a, WHITE, SHADOW)
          pbDrawShadowText(i, 22, 24, VIEW_W - 30, 26, b, Color.new(208, 208, 216), SHADOW)
        end

        def update_view
          if @target
            [[:ox, 0], [:oy, 1]].each do |m, k|
              cur = @mapvp.send(m)
              dest = @target[k]
              step = (dest - cur) * 0.25
              step = (dest <=> cur) if step.abs < 1 && dest != cur
              @mapvp.send("#{m}=", (cur + step).round)
            end
          end
          @frame = (@frame || 0) + 1
          @sprites["sel"].opacity = 175 + (80 * Math.sin(@frame / 8.0)).round
          pbUpdateSpriteHash(@sprites)
        end

        def main
          loop do
            Graphics.update
            Input.update
            update_view
            if Input.trigger?(Input::BACK)
              pbPlayCloseMenuSE
              break
            elsif Input.trigger?(Input::USE)
              pbPlayDecisionSE
              ER.show_list
            elsif Input.repeat?(Input::DOWN) || Input.repeat?(Input::RIGHT)
              if @list.length > 1
                pbPlayCursorSE
                select((@index + 1) % @list.length)
              end
            elsif Input.repeat?(Input::UP) || Input.repeat?(Input::LEFT)
              if @list.length > 1
                pbPlayCursorSE
                select((@index - 1) % @list.length)
              end
            end
          end
        end

        def finish
          pbFadeOutAndHide(@sprites) { update_view }
          pbDisposeSpriteHash(@sprites)
          @vp.dispose; @mapvp.dispose; @topvp.dispose
        end
      end

      class << self
        # The Entrance log: the map first, the list behind A
        def show_log
          s = state
          unless active? && s[:seen] && !s[:seen].empty?
            pbMessage(active? ? _INTL("You haven't used a shuffled door yet.") : _INTL("Entrances are not shuffled on this save."))
            return
          end
          list = LogMap.entries
          return show_list if list.empty?
          scene = LogMapScene.new(list)
          begin
            scene.start
            scene.main
          ensure
            scene.finish rescue nil
          end
        rescue => e
          KIF.log("Entrance log map failed (#{e.class}: #{e.message})")
          show_list
        end

        # The doors used so far as text, newest first
        def show_list
          s = state
          return unless active? && s[:seen] && !s[:seen].empty?
          lines = s[:seen].reverse.map { |door_id, kind| describe(door_id, kind) }.reject(&:empty?)
          lines << ""
          lines << _INTL("Doors not yet found: {1}", [s[:in].length - s[:seen].map(&:first).uniq.length, 0].max)
          Rand.show_lines(_INTL("Entrance log ({1} found, newest first)", s[:seen].map(&:first).uniq.length), lines)
        end
      end
    end
  end
end
