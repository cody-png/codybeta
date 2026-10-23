#===============================================================================
# F-UI-13 – Mouse (new in KIF 1.2, 2026-10-22; KIF 0.20.7 and PIF 6.8.2 had
# no mouse support besides PIF's unused Mouse.getMousePos)
#
# Setting: Options > System > Controls > Mouse: Off / On (default On; hidden
# and off on phones; off while the Mouse UI mod is loaded, which does the
# same its own way).
#
# Menus: pointing at an entry selects it, left click confirms (it is the USE
# key for that frame), right click is BACK, the wheel is UP/DOWN. So every
# screen that reads keys takes clicks; SpriteWindow_Selectable (choice boxes,
# Yes/No, the pause menu, the Bag list, most PIF lists) also follows the
# pointer, and MouseScreens.rb adds the screens drawn without windows.
# A click on an active list outside its entries is dropped (it doesn't
# confirm whatever is selected).
#
# Map: left click a tile and the player walks there (A* over the tiles the
# player could step on: the map's passability, surfing, one-way ledges,
# events that block). Clicking an event walks next to it, faces it and
# talks to it; clicking a blocked tile next to the player interacts
# (USE). Holding the button follows the pointer. Any key (but the run key)
# or a new click stops the walk; nothing happens while an event, message or
# menu runs. The
# walk drives Input.dir4, so the player's own movement code does each step.
#
# Engine: mkxp-z's Input.mouse_x/mouse_y/mouse_in_window?, MOUSELEFT/RIGHT,
# scroll_v and Graphics.show_cursor; every call checks the engine has it.
# The pointer hides after a few seconds without moving.
#===============================================================================
KIF::Options.define(:kif_mouse, 1, :global)   # 1 On, 0 Off

KIF::Options.add(:graphics, :global) {   # placed under System > Controls (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Mouse"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mouse },
                 proc { |value| $PokemonSystem.kif_mouse = value },
                 [_INTL("The mouse does nothing in the game."),
                  _INTL("Point to choose, left click to confirm, right click to go back, wheel to scroll. Click the map to walk there.")])
}

module KIF
  module Mouse
    HIDE_AFTER = 3.0   # seconds without moving before the pointer hides
    SEARCH_CAP = 2000  # tiles one path search may look at
    MARGIN     = 8     # tiles around the start and goal a path may use
    REPATHS    = 3     # new paths tried when someone steps in the way
    DIRS = [2, 4, 6, 8].freeze
    DXA  = [0, 0, 0, 0, -1, 0, 1, 0, 0].freeze
    DYA  = [0, 0, 1, 0, 0, 0, 0, 0, -1].freeze
    CANCEL_KEYS = [:USE, :BACK, :SPECIAL].freeze   # not ACTION: holding the run key runs along the path

    @x = @y = nil
    @on = @moved = @left = @right = @held = @any = false
    @swallow = @on_map = @use_now = @left_used = false
    @wheel = 0
    @key = nil
    @dir = 0
    @path = nil

    class << self
      attr_reader :x, :y, :moved, :left, :right, :held, :wheel, :dir, :path, :on
      attr_accessor :on_map
    end

    def self.engine?
      return @engine unless @engine.nil?
      @engine = (Input.respond_to?(:mouse_x) && Input.respond_to?(:mouse_y) && defined?(Input::MOUSELEFT)) ? true : false
    end

    # setting On, a PC, the engine has a mouse, and the Mouse UI mod isn't loaded
    def self.on?
      return false unless engine?
      return false if defined?(::MouseUI)
      return false if KIF.mobile?
      return (($PokemonSystem.kif_mouse rescue 1) || 1).to_i == 1
    end

    def self.in_window?
      return Input.mouse_in_window? if Input.respond_to?(:mouse_in_window?)
      return Input.mouse_in_window if Input.respond_to?(:mouse_in_window)
      return true
    end

    # After every Input.update: this frame's pointer, buttons and wheel
    def self.poll
      @swallow = @on_map = @use_now = @left_used = false
      @key = nil
      @marker.visible = false if @marker && !@marker.disposed?
      @on = on?
      unless @on
        @moved = @left = @right = @held = @any = false
        @wheel = 0
        stop if @path
        cursor(true) if @cursor_set
        return
      end
      inside = in_window?
      nx = Input.mouse_x.to_i
      ny = Input.mouse_y.to_i
      @moved = inside && !@x.nil? && (nx != @x || ny != @y)
      @x = nx
      @y = ny
      @left  = inside && Input.kif_mouse_trigger?(Input::MOUSELEFT)
      @right = inside && Input.kif_mouse_trigger?(Input::MOUSERIGHT)
      @held  = inside && Input.kif_mouse_press?(Input::MOUSELEFT)
      @wheel = (inside && Input.respond_to?(:scroll_v)) ? Input.scroll_v.to_i : 0
      @any = @left || @right || @wheel != 0
      stop if @path && $game_temp && $game_temp.in_battle
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @seen = now if @moved || @left || @right || @wheel != 0
      cursor(!@seen.nil? && now - @seen < HIDE_AFTER)
      focus_frame if @focus   # MouseScreens.rb
    end

    def self.cursor(show)
      return if @cursor_shown == show
      return unless Graphics.respond_to?(:show_cursor=)
      @cursor_set = !show
      @cursor_shown = show
      Graphics.show_cursor = show
    rescue StandardError
    end

    # The keys a click, the wheel or a screen of MouseScreens.rb press this frame
    def self.virtual?(k)
      return false unless @any
      return true if k == @key
      if k == Input::USE
        return @on_map ? @use_now : (@left && !@swallow)
      elsif k == Input::BACK
        return @right && !@swallow
      elsif k == Input::UP
        return @wheel > 0 && !@on_map
      elsif k == Input::DOWN
        return @wheel < 0 && !@on_map
      end
      return false
    end

    # a screen handled the click itself: it isn't USE/BACK too
    def self.swallow!; @swallow = true; end
    # a screen turns a click into a key (LEFT, RIGHT...) for this frame
    def self.press!(k)
      @key = k
      @any = true
      @swallow = true
    end
    def self.clicked?; @on && @left && !@swallow; end
    def self.active?; @on && (@moved || @left); end

    #---------------------------------------------------------------------------
    # Pointer hit tests
    #---------------------------------------------------------------------------
    def self.view_xy(vp)
      return [@x, @y] unless vp
      r = vp.rect
      return [@x - r.x + vp.ox, @y - r.y + vp.oy]
    end

    # the pointer inside a sprite (its visible bitmap part)
    def self.over_sprite?(s, pad = 0)
      return false if s.nil? || s.disposed? || !s.visible || s.bitmap.nil? || s.bitmap.disposed?
      px, py = view_xy(s.viewport)
      w = s.src_rect.width * s.zoom_x
      h = s.src_rect.height * s.zoom_y
      x0 = s.x - s.ox * s.zoom_x
      y0 = s.y - s.oy * s.zoom_y
      return px >= x0 - pad && px < x0 + w + pad && py >= y0 - pad && py < y0 + h + pad
    end

    def self.over_rect?(x, y, w, h, vp = nil)
      px, py = view_xy(vp)
      return px >= x && px < x + w && py >= y && py < y + h
    end

    # The entry of a list window under the pointer, or nil
    def self.window_item(w)
      px, py = view_xy(w.viewport)
      return nil if px < w.x || px >= w.x + w.width || py < w.y || py >= w.y + w.height
      cx = px - w.x - w.leftEdge
      cy = py - w.y - w.topEdge
      top = w.top_item
      last = [top + w.page_item_max, w.itemCount].min
      i = top
      while i < last
        r = w.itemRect(i)
        return i if r.width > 0 && cx >= r.x && cx < r.x + r.width && cy >= r.y && cy < r.y + r.height
        i += 1
      end
      return nil
    end

    # Hover and click for a SpriteWindow_Selectable (after its own update)
    def self.window(w)
      return unless @on && (@moved || @left)
      return if w.disposed? || !w.active || !w.visible || w.index < 0 || w.itemCount <= 0
      return if w.instance_variable_get(:@ignore_input)
      i = window_item(w)
      if i.nil?
        @swallow = true if @left && !@swallow   # a click beside the entries doesn't confirm
        return
      end
      return if i == w.index
      select_keep_scroll(w, i)
      pbPlayCursorSE if @moved
    end

    # PIF's lists keep the cursor in the middle: pointing at an entry would
    # scroll the list under the pointer, so the list stays where it was
    def self.select_keep_scroll(w, i)
      top = w.top_row
      w.index = i
      return if w.top_row == top
      w.top_row = top
      cols = [w.columns, 1].max
      cw = (w.width - w.borderX) / cols
      w.cursor_rect.set(i % cols * (cw + w.columnSpacing), i / cols * w.rowHeight - top * w.rowHeight, cw, w.rowHeight)
      w.refresh
    end

    #---------------------------------------------------------------------------
    # Click to move
    #---------------------------------------------------------------------------
    def self.real_key?
      return true if Input.kif_mouse_dir4 != 0
      CANCEL_KEYS.each { |k| return true if Input.kif_mouse_trigger?(Input.const_get(k)) }
      return false
    end

    def self.map_busy?(pl)
      return true if pbMapInterpreterRunning? || $game_temp.message_window_showing || $game_temp.in_menu
      return true if $game_temp.player_transferring || $game_temp.transition_processing
      return true if pl.move_route_forcing || ($PokemonTemp && $PokemonTemp.miniupdate)
      return false
    end

    # Start of every Scene_Map#update
    def self.map_step
      @on_map = true
      return unless @on
      pl = $game_player
      return unless pl && $game_map
      stop if @path && real_key?
      if map_busy?(pl)
        stop if @path
        @pending = nil
        return
      end
      if @left && !@left_used
        @left_used = true
        stop
        @pending = mouse_tile
        @drag = true
        @drag_x, @drag_y = @pending
      elsif @right
        stop
        @drag = false
      end
      @drag = false unless @held
      return follow(pl) if pl.moving? || pl.jumping?
      if @pending
        tx, ty = @pending
        @pending = nil
        click_tile(pl, tx, ty)
      elsif @drag
        # holding the button: follow the pointer (one search per tile it enters)
        tx, ty = mouse_tile
        if (tx != @drag_x || ty != @drag_y) && $game_map.valid?(tx, ty) && (tx != pl.x || ty != pl.y)
          @drag_x = tx
          @drag_y = ty
          walk_to(pl, tx, ty, nil)
        end
      end
      follow(pl) if @path
    end

    def self.mouse_tile
      tx = (($game_map.display_x + @x * Game_Map::X_SUBPIXELS) / Game_Map::REAL_RES_X.to_f).floor
      ty = (($game_map.display_y + @y * Game_Map::Y_SUBPIXELS) / Game_Map::REAL_RES_Y.to_f).floor
      return [tx, ty]
    end

    def self.dir_to(dx, dy)
      return 0 if dx != 0 && dy != 0
      return dx > 0 ? 6 : 4 if dx != 0
      return dy > 0 ? 2 : 8 if dy != 0
      return 0
    end

    # an event the player could talk to on that tile (what USE would start)
    def self.event_at(tx, ty)
      $game_map.events.each_value do |ev|
        next unless ev.at_coordinate?(tx, ty)
        next if ev.jumping? || ev.over_trigger?
        return ev
      end
      return nil
    end

    def self.face(pl, d)
      case d
      when 2 then pl.turn_down
      when 4 then pl.turn_left
      when 6 then pl.turn_right
      when 8 then pl.turn_up
      end
    end

    def self.interact(pl, d)
      face(pl, d)
      @use_now = true
      @any = true
    end

    def self.click_tile(pl, tx, ty)
      return unless $game_map.valid?(tx, ty)
      dx = tx - pl.x
      dy = ty - pl.y
      return if dx == 0 && dy == 0
      ev = event_at(tx, ty)
      d = dir_to(dx, dy)
      @drag = false if ev
      if dx.abs + dy.abs == 1 && (ev || !pl.passable?(pl.x, pl.y, d))
        @drag = false
        return interact(pl, d)   # talk, or what USE does there (Surf, Cut, a sign...)
      end
      if ev && dx.abs + dy.abs == 2 && d > 0 && $game_map.counter?(pl.x + DXA[d], pl.y + DYA[d])
        return interact(pl, d)   # across a shop counter
      end
      walk_to(pl, tx, ty, ev)
    end

    def self.walk_to(pl, tx, ty, ev)
      path = find_path(pl.x, pl.y, tx, ty, !ev.nil?)
      return false unless path
      @path = path
      @pi = 0
      @gx = tx
      @gy = ty
      @face_event = !ev.nil?
      @repaths = 0
      @map_id = $game_map.map_id
      return true
    end

    def self.stop
      @path = nil
      @dir = 0
      @face_event = false
    end

    def self.follow(pl)
      return stop if @map_id != $game_map.map_id
      return if pl.moving? || pl.jumping?
      while @pi < @path.length && pl.x == @path[@pi] && pl.y == @path[@pi + 1]
        @pi += 2
        @repaths = 0
      end
      if @pi >= @path.length
        arrive(pl)
        return
      end
      d = next_dir(pl)
      if d == 0
        return stop if @repaths >= REPATHS
        @repaths += 1
        return stop unless walk_to(pl, @gx, @gy, @face_event ? true : nil) && (d = next_dir(pl)) > 0
      end
      @dir = d
      show_marker
    end

    # the step toward the next tile of the path, 0 when it can't be taken now
    def self.next_dir(pl)
      dx = @path[@pi] - pl.x
      dy = @path[@pi + 1] - pl.y
      d = dir_to(dx, dy)
      return 0 if d == 0 || dx.abs + dy.abs > 2
      return 0 unless pl.passable?(pl.x, pl.y, d)
      return d
    end

    def self.arrive(pl)
      fe = @face_event
      gx = @gx
      gy = @gy
      stop
      interact(pl, dir_to(gx - pl.x, gy - pl.y)) if fe   # face it and talk (Cody)
    end

    def self.show_marker
      return unless @gx
      if @marker.nil? || @marker.disposed?
        @marker_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @marker_vp.z = 1
        @marker = Sprite.new(@marker_vp)
        b = Bitmap.new(Game_Map::TILE_WIDTH, Game_Map::TILE_HEIGHT)
        dark = Color.new(24, 24, 32, 200)
        light = Color.new(248, 248, 248, 230)
        [[4, 4, 1, 1], [20, 4, -1, 1], [4, 20, 1, -1], [20, 20, -1, -1]].each do |cx, cy, sx, sy|
          bx = sx > 0 ? cx : cx + 8
          by = sy > 0 ? cy : cy + 8
          b.fill_rect(bx - 1, by - 1, 10, 4, dark)
          b.fill_rect(bx - 1, by - 1, 4, 10, dark)
          b.fill_rect(bx, by, 8, 2, light)
          b.fill_rect(bx, by, 2, 8, light)
        end
        @marker.bitmap = b
      end
      @marker.x = ((@gx * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round
      @marker.y = ((@gy * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round
      @marker.visible = true
    end

    #---------------------------------------------------------------------------
    # A* over the tiles the player can step on. near: stop on a tile next to
    # the goal (or across a counter from it). Returns the tiles to walk
    # through as [x1, y1, x2, y2, ...] (a ledge jump skips its ledge tile),
    # or nil when the goal can't be reached.
    #---------------------------------------------------------------------------
    def self.find_path(sx, sy, tx, ty, near = false, pl = $game_player, map = $game_map)
      x0 = [[sx, tx].min - MARGIN, 0].max
      y0 = [[sy, ty].min - MARGIN, 0].max
      x1 = [[sx, tx].max + MARGIN, map.width - 1].min
      y1 = [[sy, ty].max + MARGIN, map.height - 1].min
      return nil if tx < x0 || tx > x1 || ty < y0 || ty > y1
      bw = x1 - x0 + 1
      n = bw * (y1 - y0 + 1)
      # events that block a tile on the way (the goal itself may hold one)
      blocked = Array.new(n, false)
      map.events.each_value do |ev|
        next if ev.through || ev == pl
        ev.each_occupied_tile do |i, j|
          blocked[(j - y0) * bw + (i - x0)] = true if i >= x0 && i <= x1 && j >= y0 && j <= y1
        end
      end
      surfing = $PokemonGlobal && $PokemonGlobal.surfing
      g = Array.new(n)
      came = Array.new(n)
      heap_f = []
      heap_n = []
      start = (sy - y0) * bw + (sx - x0)
      g[start] = 0
      heap_push(heap_f, heap_n, 0, start)
      seen = 0
      goal = nil
      until heap_n.empty?
        cur = heap_pop(heap_f, heap_n)
        cx = cur % bw + x0
        cy = cur / bw + y0
        dist = (cx - tx).abs + (cy - ty).abs
        at_goal = if near
                    dist == 1 || (dist == 2 && (cx == tx || cy == ty) && map.counter?((cx + tx) / 2, (cy + ty) / 2))
                  else
                    dist == 0
                  end
        if at_goal
          goal = cur
          break
        end
        seen += 1
        break if seen > SEARCH_CAP
        here_water = surfing && map.terrain_tag(cx, cy).can_surf
        DIRS.each do |d|
          next unless pl.passable?(cx, cy, d)
          nx = cx + DXA[d]
          ny = cy + DYA[d]
          next if nx < x0 || nx > x1 || ny < y0 || ny > y1
          tag = map.terrain_tag(nx, ny)
          cost = 1
          if tag.ledge
            next if surfing
            nx += DXA[d]
            ny += DYA[d]
            next if nx < x0 || nx > x1 || ny < y0 || ny > y1
            next unless pl.passable?(nx, ny, 0)   # the landing, as Game_Character#jump checks it
            tag = map.terrain_tag(nx, ny)
            cost = 2
          end
          next if surfing && !here_water && tag.can_surf   # off the water, Surf ends
          next if tag.respond_to?(:chair) && tag.chair
          next if near && nx == tx && ny == ty
          ni = (ny - y0) * bw + (nx - x0)
          next if blocked[ni] && !(nx == tx && ny == ty)
          ng = g[cur] + cost
          next if g[ni] && g[ni] <= ng
          g[ni] = ng
          came[ni] = cur
          h = (nx - tx).abs + (ny - ty).abs
          h -= 1 if near && h > 0
          heap_push(heap_f, heap_n, ng + h, ni)
        end
      end
      return nil unless goal
      out = []
      c = goal
      while c != start
        out.unshift(c / bw + y0)
        out.unshift(c % bw + x0)
        c = came[c]
      end
      return out
    end

    def self.heap_push(f, nodes, pri, node)
      f << pri
      nodes << node
      i = f.length - 1
      while i > 0
        p = (i - 1) / 2
        break if f[p] <= f[i]
        f[p], f[i] = f[i], f[p]
        nodes[p], nodes[i] = nodes[i], nodes[p]
        i = p
      end
    end

    def self.heap_pop(f, nodes)
      top = nodes[0]
      lf = f.pop
      ln = nodes.pop
      return top if nodes.empty?
      f[0] = lf
      nodes[0] = ln
      i = 0
      len = f.length
      loop do
        l = 2 * i + 1
        break if l >= len
        r = l + 1
        m = (r < len && f[r] < f[l]) ? r : l
        break if f[i] <= f[m]
        f[m], f[i] = f[i], f[m]
        nodes[m], nodes[i] = nodes[i], nodes[m]
        i = m
      end
      return top
    end
  end
end

#===============================================================================
# Hooks
#===============================================================================
module Input
  class << Input
    alias kif_mouse_update update unless method_defined?(:kif_mouse_update)
    alias kif_mouse_trigger? trigger? unless method_defined?(:kif_mouse_trigger?)
    alias kif_mouse_repeat? repeat? unless method_defined?(:kif_mouse_repeat?)
    alias kif_mouse_press? press? unless method_defined?(:kif_mouse_press?)
    alias kif_mouse_dir4 dir4 unless method_defined?(:kif_mouse_dir4)
    alias kif_mouse_dir8 dir8 unless method_defined?(:kif_mouse_dir8)
  end

  def self.update(*args)
    ret = kif_mouse_update(*args)
    begin
      KIF::Mouse.poll
    rescue StandardError => e
      KIF.log("Mouse: #{e.class}: #{e.message}") unless @kif_mouse_logged
      @kif_mouse_logged = true
    end
    return ret
  end

  def self.trigger?(button)
    return kif_mouse_trigger?(button) || KIF::Mouse.virtual?(button)
  end

  def self.repeat?(button)
    return kif_mouse_repeat?(button) || KIF::Mouse.virtual?(button)
  end

  def self.dir4
    d = KIF::Mouse.dir
    return d if d > 0 && KIF::Mouse.on_map
    return kif_mouse_dir4
  end

  def self.dir8
    d = KIF::Mouse.dir
    return d if d > 0 && KIF::Mouse.on_map
    return kif_mouse_dir8
  end
end

class SpriteWindow_Selectable
  alias kif_mouse_win_update update unless method_defined?(:kif_mouse_win_update)

  def update
    kif_mouse_win_update
    KIF::Mouse.window(self) if KIF::Mouse.active?
  end
end

class Scene_Map
  alias kif_mouse_map_update update unless method_defined?(:kif_mouse_map_update)

  def update
    begin
      KIF::Mouse.map_step
    rescue StandardError => e
      KIF.log("Mouse (map): #{e.class}: #{e.message}")
      KIF::Mouse.stop
    end
    kif_mouse_map_update
  end
end
