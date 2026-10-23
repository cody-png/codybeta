#===============================================================================
# F-UI-13 – Mouse (new in KIF 1.2, 2026-10-22; KIF 0.20.7 and PIF 6.8.2 had
# no mouse support besides PIF's unused Mouse.getMousePos)
#
# Settings: Options > System > Controls > Mouse: Off / On (default Off; hidden
# and off on phones; off while the Mouse UI mod is loaded, which does the
# same its own way). Click to move: On / Off (default On, shown while Mouse
# is On): Off keeps the mouse in menus only. Phones show Touch controls
# (default On; JoiPlay sends taps as left clicks) and Tap to move instead.
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
# events that block, and what stepping on a map's own triggers does: stairs
# that move the player, bridge ends that turn bridge mode on or off). Clicking an event walks next to it, faces it and
# talks to it; clicking a blocked tile next to the player interacts
# (USE). Holding the button follows the pointer. Any key (but the run key)
# or a new click stops the walk; nothing happens while an event, message or
# menu runs (but the stairs and bridge ends on the way: the walk waits for
# them and goes on). Holding searches again only when the pointer reaches
# another tile or the walk ended. The
# walk drives Input.dir4, so the player's own movement code does each step.
#
# Engine: mkxp-z's Input.mouse_x/mouse_y/mouse_in_window?, MOUSELEFT/RIGHT,
# scroll_v and Graphics.show_cursor; every call checks the engine has it.
# The pointer hides after a few seconds without moving.
#===============================================================================
KIF::Options.define(:kif_mouse, 0, :global)        # 1 On, 0 Off
KIF::Options.define(:kif_mouse_walk, 1, :global)   # click (or tap) to move: 1 On, 0 Off
KIF::Options.define(:kif_touch, 1, :global)        # phones: taps as clicks, 1 On, 0 Off

KIF::Options.add(:graphics, :global) {   # placed under System > Controls (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Mouse"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mouse },
                 proc { |value| $PokemonSystem.kif_mouse = value },
                 [_INTL("The mouse does nothing in the game."),
                  _INTL("Point to choose, left click to confirm, right click to go back, wheel to scroll.")])
}

KIF::Options.add(:graphics, :global) {
  next nil if KIF.mobile? || $PokemonSystem.kif_mouse.to_i != 1
  EnumOption.new(_INTL("Click to move"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mouse_walk },
                 proc { |value| $PokemonSystem.kif_mouse_walk = value },
                 [_INTL("Clicking the map does nothing. The mouse works in menus only."),
                  _INTL("Click the map to walk there. Hold the button to keep walking toward the pointer.")])
}

# Phones (JoiPlay): taps arrive as left clicks, so the same code runs them
KIF::Options.add(:graphics, :global) {
  next nil unless KIF.mobile?
  EnumOption.new(_INTL("Touch controls"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_touch },
                 proc { |value| $PokemonSystem.kif_touch = value },
                 [_INTL("Taps do nothing in the game. Use JoiPlay's on-screen buttons."),
                  _INTL("Tap an entry to choose it. Tap the map to walk there.")])
}

KIF::Options.add(:graphics, :global) {
  next nil if !KIF.mobile? || $PokemonSystem.kif_touch.to_i != 1
  EnumOption.new(_INTL("Tap to move"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mouse_walk },
                 proc { |value| $PokemonSystem.kif_mouse_walk = value },
                 [_INTL("Tapping the map does nothing. Taps work in menus only."),
                  _INTL("Tap the map to walk there. Keep your finger down to keep walking toward it.")])
}

module KIF
  module Mouse
    HIDE_AFTER = 3.0   # seconds without moving before the pointer hides
    SEARCH_CAP = 2000  # tiles one path search may look at
    MARGIN     = 8     # tiles around the start and goal a path may use
    REPATHS    = 3     # new paths tried when someone steps in the way
    WHEEL_QUEUE   = 3  # wheel notches kept for the next frames
    WHEEL_LOCK_PX = 6  # pointer travel that ends the hover pause after a wheel turn
    RECT_SET = Rect.instance_method(:set) unless const_defined?(:RECT_SET)
    SPRITEWINDOW_WIDTH = SpriteWindow.instance_method(:width=) unless const_defined?(:SPRITEWINDOW_WIDTH)
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

    # setting On (Mouse on a PC, Touch controls on a phone), the engine has a
    # mouse, and the Mouse UI mod isn't loaded
    def self.on?
      return false unless engine?
      return false if defined?(::MouseUI)
      if KIF.mobile?
        phone_test?
        return (($PokemonSystem.kif_touch rescue 1) || 1).to_i == 1
      end
      return (($PokemonSystem.kif_mouse rescue 0) || 0).to_i == 1
    end

    # Testing taps on a phone: a TapLog.krs marker file sends the first taps,
    # the keys the engine sends and how each walk ended to KIF_mousetest.txt
    PHONE_TEST = "TapLog.krs"

    def self.phone_test?
      if @phone_test.nil?
        @phone_test = KIF.marker?(PHONE_TEST) ? true : false
        KIF.log("Tap log on (#{PHONE_TEST}); engine mouse calls: #{engine?}") if @phone_test
      end
      return @phone_test
    end

    # its own file: the session log folds lines that differ only in numbers
    def self.log_phone_test(x, y, moved, extra = nil)
      return unless @phone_test && (@left || @right || moved || extra)
      return if (@test_lines = @test_lines.to_i + 1) > 400
      line = format("%.2f %d,%d left=%s held=%s right=%s moved=%s %s %s\r\n", Process.clock_gettime(Process::CLOCK_MONOTONIC),
                    x, y, @left, @held, @right, moved, $scene.class, extra)
      File.open(File.join(KIF::Paths.logs, "KIF_mousetest.txt"), "ab") { |f| f.write(line) }
    rescue StandardError
    end

    # Click to move (only asked while the mouse is on)
    def self.walk?
      return (($PokemonSystem.kif_mouse_walk rescue 1) || 1).to_i == 1
    end

    # JoiPlay reports taps in the window the engine started with (640x480),
    # not in the game's own size after PIF resizes it (512x384): a tap there
    # landed 25% too far right and down. The PC engine already converts.
    START_SIZE = [(Graphics.width rescue 0), (Graphics.height rescue 0)]

    def self.game_xy(x, y)
      return [x, y] unless KIF.mobile?
      sw, sh = START_SIZE
      return [x, y] if sw <= 0 || sh <= 0 || (sw == Graphics.width && sh == Graphics.height)
      return [x * Graphics.width / sw, y * Graphics.height / sh]
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
      # the marker stays up while the walk goes on; it goes when the map
      # stopped updating (a scene over it) or the walk ended
      @polls = @polls.to_i + 1
      hide_marker if @marker_poll != @polls - 1 || @path.nil?
      @on = on?
      unless @on
        @moved = @left = @right = @held = @any = false
        @wheel = 0
        stop if @path
        cursor(true) if @cursor_set
        return
      end
      inside = in_window?
      nx, ny = game_xy(Input.mouse_x.to_i, Input.mouse_y.to_i)
      moved = inside && !@x.nil? && (nx != @x || ny != @y)
      @x = nx
      @y = ny
      @left  = inside && Input.kif_mouse_trigger?(Input::MOUSELEFT)
      @right = inside && Input.kif_mouse_trigger?(Input::MOUSERIGHT)
      @held  = inside && Input.kif_mouse_press?(Input::MOUSELEFT)
      if @phone_test
        log_phone_test(nx, ny, moved)
        # keys the engine itself sends (JoiPlay may turn a tap into a key too)
        keys = [:USE, :BACK, :ACTION, :SPECIAL].select { |k| Input.kif_mouse_trigger?(Input.const_get(k)) }
        d = Input.kif_mouse_dir4
        log_phone_test(nx, ny, false, "keys=#{keys.join('+')} dir=#{d}") if !keys.empty? || d != @test_dir.to_i
        @test_dir = d
      end
      # scroll_v: the notches turned since the last Input.update (mkxp-z sums
      # SDL wheel events and resets it each update; up is positive). One step
      # a frame; notches that came together follow on the next frames.
      raw = (inside && Input.respond_to?(:scroll_v)) ? Input.scroll_v.to_i : 0
      rest = inside ? @wheel_rest.to_i : 0
      rest = 0 if raw != 0 && (raw > 0) != (rest > 0)
      rest = [[rest + raw, WHEEL_QUEUE].min, -WHEEL_QUEUE].max
      @wheel = rest <=> 0
      @wheel_rest = rest - @wheel
      # after a wheel turn the list moved under a still pointer: pointing
      # counts again only once the pointer really moves
      if @wheel != 0
        @lock_x = nx
        @lock_y = ny
        moved = false
      elsif moved && @lock_x
        if (nx - @lock_x).abs + (ny - @lock_y).abs <= WHEEL_LOCK_PX
          moved = false
        else
          @lock_x = nil
        end
      end
      @moved = moved
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
    # a screen turns the wheel into another key (PC: boxes), not UP/DOWN
    def self.wheel_press!(k)
      @key = k
      @any = true
      @wheel = 0
    end
    # a screen used the wheel itself: it isn't UP/DOWN too
    def self.eat_wheel!; @wheel = 0; end
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
      set_index_top(w, i, w.top_row)
    end

    # The wheel steps an active list by one row, before the list's own update
    # (which would read it as UP/DOWN and re-centre the list: a jump of
    # several rows after pointing). The list scrolls only when the entry
    # would leave it.
    def self.window_wheel(w)
      return if w.disposed? || !w.active || !w.visible || w.index < 0 || w.itemCount <= 0
      return if w.instance_variable_get(:@ignore_input)
      cols = [w.columns, 1].max
      ni = w.index + (@wheel > 0 ? -cols : cols)
      @wheel = 0   # this list took the turn
      return if ni < 0 || ni >= w.itemCount
      row = ni / cols
      page = [w.page_row_max, 1].max
      top = w.top_row
      top = row if row < top
      top = row - page + 1 if row > top + page - 1
      set_index_top(w, ni, top)
      pbPlayCursorSE
    end

    def self.set_index_top(w, i, top)
      w.index = i
      return if w.top_row == top
      w.top_row = top
      cols = [w.columns, 1].max
      cw = (w.width - w.borderX) / cols
      # WindowCursorRect#set re-applies the width, and Window_CommandPokemon#width=
      # re-centres the list: set the plain Rect and redraw the frame directly
      RECT_SET.bind(w.cursor_rect).call(i % cols * (cw + w.columnSpacing), i / cols * w.rowHeight - top * w.rowHeight, cw, w.rowHeight)
      SPRITEWINDOW_WIDTH.bind(w).call(w.width) if w.is_a?(SpriteWindow)
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
      return true if route_moves?(pl) || ($PokemonTemp && $PokemonTemp.miniupdate)
      return false
    end

    # a forced route that steps, jumps or waits (a cutscene); not one that only
    # changes how the player looks (some maps' parallel events set the
    # player's opacity every frame)
    def self.route_moves?(pl)
      return false unless pl.move_route_forcing
      route = pl.instance_variable_get(:@move_route)
      return true unless route && route.list
      return route.list.any? { |c| c.code.between?(1, 15) }
    end

    # Start of every Scene_Map#update
    def self.map_step
      @on_map = true
      return stop if @path && !(@on && walk?)
      return unless @on && walk?
      pl = $game_player
      return unless pl && $game_map
      stop if @path && real_key?
      # a stair or bridge end of the path the player just stepped on: PIF
      # only marks it starting at the end of that step; its interpreter takes
      # it next frame, after this. The walk waits for it and goes on after.
      waiting = @path && @trans && !@trans.empty? &&
                $game_map.events.each_value.any? { |e| @trans[e.id] && e.starting }
      if waiting || map_busy?(pl)
        @pending = nil
        return unless @path
        if waiting
          @hold = true
        elsif pbMapInterpreterRunning?
          @hold = (@trans && @trans[pbMapInterpreter.instance_variable_get(:@event_id)]) ? true : false
        end   # else (its move route still going): as it was
        return stop unless @hold
        @dir = 0
        return show_marker
      end
      @hold = false
      @drag_moved = true if @drag && @moved
      if @left && !@left_used
        @left_used = true
        stop
        @pending = mouse_tile
        @drag = true
        @drag_x, @drag_y = @pending
        @drag_moved = false
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
        log_phone_test(@x, @y, false, "tile=#{tx},#{ty} player=#{pl.x},#{pl.y} path=#{@path ? @path.length / 2 : 'none'}") if @phone_test
      elsif @drag && (@drag_moved || @path.nil?)
        # holding the button: a new search when the pointer moved to another
        # tile, or once the last walk ended (not every step: the map scrolls
        # under a still pointer)
        @drag_moved = false
        tx, ty = mouse_tile
        if (tx != @drag_x || ty != @drag_y) && $game_map.valid?(tx, ty) && (tx != pl.x || ty != pl.y)
          @drag_x = tx
          @drag_y = ty
          walk_to(pl, tx, ty, nil)
        end
      end
      follow(pl) if @path
    end

    # the map tile under the pointer; past the map's edge (small maps, the
    # black border) the nearest tile of the map
    def self.mouse_tile
      px = [[@x, 0].max, Graphics.width - 1].min
      py = [[@y, 0].max, Graphics.height - 1].min
      tx = (($game_map.display_x + px * Game_Map::X_SUBPIXELS) / Game_Map::REAL_RES_X.to_f).floor
      ty = (($game_map.display_y + py * Game_Map::Y_SUBPIXELS) / Game_Map::REAL_RES_Y.to_f).floor
      tx = [[tx, 0].max, $game_map.width - 1].min
      ty = [[ty, 0].max, $game_map.height - 1].min
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
      # a tile that can't be reached: as close to it as the way goes
      path = find_path(pl.x, pl.y, tx, ty, !ev.nil?, closest: ev.nil?)
      return false unless path && (!path.empty? || ev)
      @path = path
      @trans = @found_trans
      @pi = 0
      @gx = ev ? tx : path[-2]
      @gy = ev ? ty : path[-1]
      @face_event = !ev.nil?
      @repaths = 0
      @map_id = $game_map.map_id
      return true
    end

    def self.stop
      log_phone_test(@x.to_i, @y.to_i, false, "walk stopped at line #{caller_locations(1, 1)[0].lineno}") if @phone_test && @path
      @path = nil
      @trans = nil
      @hold = false
      @dir = 0
      @face_event = false
      hide_marker
    end

    def self.follow(pl)
      return stop if @map_id != $game_map.map_id
      return show_marker if pl.moving? || pl.jumping?
      # the tile reached: the next one, or the one after it when a stair's
      # move route carried the player past its own tile (no further: a path
      # may cross a tile twice, under a bridge and then over it)
      j = @pi
      j += 2 if j < @path.length && !(pl.x == @path[j] && pl.y == @path[j + 1])
      if j < @path.length && pl.x == @path[j] && pl.y == @path[j + 1]
        @pi = j + 2
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

    # the marker's four corners, each an L turned outward (top-left, top-right,
    # bottom-left, bottom-right): [x, y, w, h] of their bars in a 32x32 tile
    def self.marker_rects
      s = Game_Map::TILE_WIDTH
      inset = 3
      len = 8
      th = 2
      out = []
      [[1, 1], [-1, 1], [1, -1], [-1, -1]].each do |sx, sy|
        x = sx > 0 ? inset : s - inset - len   # the horizontal bar runs from the corner inward
        y = sy > 0 ? inset : s - inset - th
        out << [x, y, len, th]
        x = sx > 0 ? inset : s - inset - th
        y = sy > 0 ? inset : s - inset - len
        out << [x, y, th, len]
      end
      return out
    end

    def self.hide_marker
      @marker.visible = false if @marker && !@marker.disposed? && @marker.visible
    end

    # every frame of the walk, so it stays up (one sprite for the whole game)
    def self.show_marker
      @marker_poll = @polls
      return unless @gx
      if @marker.nil? || @marker.disposed?
        @marker_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @marker_vp.z = 1
        @marker = Sprite.new(@marker_vp)
        b = Bitmap.new(Game_Map::TILE_WIDTH, Game_Map::TILE_HEIGHT)
        dark = Color.new(24, 24, 32, 200)
        light = Color.new(248, 248, 248, 230)
        marker_rects.each do |x, y, w, h|
          b.fill_rect(x - 1, y - 1, w + 2, h + 2, dark)
        end
        marker_rects.each { |x, y, w, h| b.fill_rect(x, y, w, h, light) }
        @marker.bitmap = b
      end
      @marker.x = ((@gx * Game_Map::REAL_RES_X - $game_map.display_x) / Game_Map::X_SUBPIXELS).round
      @marker.y = ((@gy * Game_Map::REAL_RES_Y - $game_map.display_y) / Game_Map::Y_SUBPIXELS).round
      @marker.visible = true
    end

    #---------------------------------------------------------------------------
    # A* over the tiles the player can step on. near: stop on a tile next to
    # the goal (or across a counter from it). Returns the tiles to walk
    # through as [x1, y1, x2, y2, ...] (a ledge jump skips its ledge tile; a
    # stair event's tile is followed by the tile its move route ends on), or
    # nil when the goal can't be reached.
    # Each step is searched in the bridge mode the player would be in there:
    # stepping on a bridge end (an event with pbBridgeOn/pbBridgeOff) changes
    # which tiles count from then on, as it does for the player.
    # @found_trans: the ids of the stair and bridge events the path steps on.
    #---------------------------------------------------------------------------
    def self.find_path(sx, sy, tx, ty, near = false, pl = $game_player, map = $game_map, closest: false)
      x0 = [[sx, tx].min - MARGIN, 0].max
      y0 = [[sy, ty].min - MARGIN, 0].max
      x1 = [[sx, tx].max + MARGIN, map.width - 1].min
      y1 = [[sy, ty].max + MARGIN, map.height - 1].min
      return nil if tx < x0 || tx > x1 || ty < y0 || ty > y1
      bw = x1 - x0 + 1
      n = bw * (y1 - y0 + 1)
      # events a step onto starts (Player/Event Touch, mostly without a
      # graphic): stairs, bridge ends, doors, scenes. Events in the way are
      # left to the player's own passable?, as for a key press (one without
      # a graphic isn't in the way: PIF lets the player walk over it).
      touch = {}
      map.events.each_value do |ev|
        next if ev == pl || !(ev.trigger == 1 || ev.trigger == 2) || ev.list.nil?
        next if ev.x < x0 || ev.x > x1 || ev.y < y0 || ev.y > y1
        touch[(ev.y - y0) * bw + (ev.x - x0)] = ev
      end
      glob = $PokemonGlobal
      bridge0 = glob ? glob.bridge.to_i : 0
      on_h = bridge0 > 0 ? bridge0 : 2   # passability only asks bridge > 0, not the height
      surfing = glob && glob.surfing
      # a state is a tile and the bridge mode: tile * 2 + (bridge on ? 1 : 0)
      g = Array.new(2 * n)
      came = Array.new(2 * n)
      lands = {}   # state reached by a stair: the stair's own tile
      trans = {}   # state reached over a stair or bridge end: its event id
      heap_f = []
      heap_n = []
      start = ((sy - y0) * bw + (sx - x0)) * 2 + (bridge0 > 0 ? 1 : 0)
      g[start] = 0
      heap_push(heap_f, heap_n, 0, start)
      seen = 0
      goal = nil
      best = nil     # closest: the reached tile nearest the goal
      best_d = nil
      begin
        until heap_n.empty?
          cur = heap_pop(heap_f, heap_n)
          cell = cur >> 1
          cx = cell % bw + x0
          cy = cell / bw + y0
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
          if closest && (best_d.nil? || dist < best_d)
            best = cur
            best_d = dist
          end
          seen += 1
          break if seen > SEARCH_CAP
          glob.bridge = ((cur & 1) == 1 ? on_h : 0) if glob
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
            nb = cur & 1
            land = nil
            ev_id = nil
            ev = touch[(ny - y0) * bw + (nx - x0)]
            if ev
              r = touch_result(ev, d, nx, ny, pl)
              if r
                lx, ly, br = r
                ev_id = ev.id
                if br
                  nb = br > 0 ? 1 : 0
                end
                if lx != nx || ly != ny
                  next if lx < x0 || lx > x1 || ly < y0 || ly > y1
                  land = [nx, ny]
                  cost += (lx - nx).abs + (ly - ny).abs
                  nx = lx
                  ny = ly
                end
              elsif !(nx == tx && ny == ty)
                next if ev.list.any? { |c| c.code == 201 }   # a door: only when clicked
                cost += 8   # a scene starts there: only when there's no other way
              end
            end
            ni = ((ny - y0) * bw + (nx - x0)) * 2 + nb
            ng = g[cur] + cost
            next if g[ni] && g[ni] <= ng
            g[ni] = ng
            came[ni] = cur
            if land then lands[ni] = land else lands.delete(ni) end
            if ev_id then trans[ni] = ev_id else trans.delete(ni) end
            h = (nx - tx).abs + (ny - ty).abs
            h -= 1 if near && h > 0
            heap_push(heap_f, heap_n, ng + h, ni)
          end
        end
      ensure
        glob.bridge = bridge0 if glob
      end
      goal = best if goal.nil? && best && best != start
      return nil unless goal
      out = []
      @found_trans = {}
      c = goal
      while c != start
        cell = c >> 1
        out.unshift(cell / bw + y0)
        out.unshift(cell % bw + x0)
        if (st = lands[c])
          out.unshift(st[1])
          out.unshift(st[0])
        end
        @found_trans[trans[c]] = true if trans[c]
        c = came[c]
      end
      return out
    end

    # Where stepping onto a touch event (moving toward d) leaves the player:
    # [x, y, bridge] (bridge: the height pbBridgeOn sets, 0 for pbBridgeOff,
    # nil when it stays). Only for events that do nothing else: a branch on
    # the player's direction, player move routes, waits, bridge scripts (PIF's
    # stairs and bridge ends). nil for anything else (a scene, a door...).
    def self.touch_result(ev, d, x, y, pl)
      list = ev.list
      bridge = nil
      dir = d
      i = 0
      while i < list.length
        c = list[i]
        case c.code
        when 0, 106, 108, 121, 122, 123, 210, 408, 412, 509   # (switches, variables, self switches)
        when 111   # Conditional Branch: only "the player faces ..."
          p = c.parameters
          return nil unless p[0] == 6 && p[1] == -1
          if p[2] != dir   # false: on to its Else, or past its end
            i += 1
            i += 1 while i < list.length && !((list[i].code == 411 || list[i].code == 412) && list[i].indent == c.indent)
          end
        when 411   # the branch taken ends here: past the Else part
          i += 1 while i < list.length && !(list[i].code == 412 && list[i].indent == c.indent)
        when 209   # Set Move Route
          if c.parameters[0] != -1   # another event's route (a scene around the step): not the player's way
            i += 1
            next
          end
          route = c.parameters[1]
          return nil if route.repeat
          through = false
          route.list.each do |mc|
            code = mc.code
            if (1..4).include?(code) || code == 12 || code == 13
              md = code <= 4 ? code * 2 : (code == 12 ? dir : 10 - dir)
              if through || pl.passable?(x, y, md)
                x += DXA[md]
                y += DYA[md]
              elsif !route.skippable
                return nil
              end
              dir = md unless code == 13
            elsif (5..8).include?(code)   # diagonals, turning as Game_Character does
              dx = (code == 5 || code == 7) ? -1 : 1
              dy = code <= 6 ? 1 : -1
              x += dx
              y += dy
              hd = dx < 0 ? 4 : 6
              vd = dy > 0 ? 2 : 8
              dir = dir == 10 - hd ? hd : (dir == 10 - vd ? vd : dir)
            elsif code == 14
              x += mc.parameters[0].to_i
              y += mc.parameters[1].to_i
            elsif (16..19).include?(code)
              dir = (code - 15) * 2
            elsif code == 20 || code == 21
              dir = (code == 20 ? { 2 => 4, 4 => 8, 6 => 2, 8 => 6 } : { 2 => 6, 4 => 2, 6 => 8, 8 => 4 })[dir] || dir
            elsif code == 22
              dir = 10 - dir
            elsif code == 37 || code == 38
              through = code == 37
            elsif !(code == 0 || code == 15 || (29..44).include?(code))
              return nil   # random moves, scripts...
            end
          end
        when 355, 655
          s = c.parameters[0].to_s.strip
          if s =~ /\ApbBridgeOn(?:\((\d*)\))?\z/
            bridge = $1.to_s.empty? ? 2 : $1.to_i
          elsif s =~ /\ApbBridgeOff(?:\(\))?\z/
            bridge = 0
          else
            return nil
          end
        else
          return nil
        end
        i += 1
      end
      return [x, y, bridge]
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
    KIF::Mouse.window_wheel(self) if KIF::Mouse.wheel != 0
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
