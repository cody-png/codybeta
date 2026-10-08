#===============================================================================
# C-SYS-01 – Frame rate (Cody, 2026-10-08) - experimental
#   Cody Settings > Interface > "Frame rate": 40 (PIF's own), 60, 80, 100,
#   120 or Match monitor (the engine draws at most 120 frames a second).
#   The game itself always runs 40 steps a second, exactly like PIF, so
#   walking, events, waits, battles, menus and play time never change. Above
#   40, extra frames are drawn between two steps, each showing the overworld
#   part of the way from one step to the next (camera, characters, shadows,
#   weather), so walking and scrolling look smoother. Menus and battles look
#   the same as at 40.
#   If the computer can't keep up, the rate steps down on its own and comes
#   back up once things run smoothly again.
#===============================================================================
KIF::Options.define(:cody_framerate, 0, :global)   # index into KIF::FrameRate::CHOICES

module KIF
  module FrameRate
    BASE       = 40      # steps per second (PIF's frame rate)
    CHOICES    = [40, 60, 80, 100, 120, :monitor]
    MAX        = 120     # mkxp-z won't pace frames any faster
    MAX_CAMERA = 32      # px the camera may move in one step and still be drawn in between
                         # (one spare tile of map is kept around the screen while drawing)
    MAX_JUMP   = 48      # px; a sprite that moved further in one step jumped (warp, reused sprite)
    WINDOW     = 80      # steps per speed check (2 seconds)
    SLOW_STEP  = 0.030   # s; a step that took longer than this was a slow one (normal: 0.025)
    WAIT_UP    = 400     # smooth steps before trying a higher rate again (10 seconds)
    LOG_STEP   = 0.012   # s; with KIF debug on, steps slower than this are written to the frame log
    # Held keys repeat after this many steps, then in this rhythm - what the
    # engine does at 40 (it times key repeat in drawn frames, so above 40 it
    # would repeat slower; while drawing in between, key repeat is done here)
    REPEAT_START = 16
    REPEAT_DELAY = 4

    # An option row showing only the chosen value; Left/Right go round the list
    class Choice < Option
      include PropertyMixin
      attr_reader :name, :values

      def initialize(name, values, get_proc, set_proc, description = "")
        super(description)
        @name = name
        @values = values
        @getProc = get_proc
        @setProc = set_proc
      end

      def next(current)
        return (current + 1) % @values.length
      end

      def prev(current)
        return (current - 1) % @values.length
      end
    end

    @count   = 0        # Graphics.frame_count as the game sees it: steps, not drawn frames
    @logic   = BASE     # what the game set Graphics.frame_rate to (40, except the Berry Blender)
    @target  = BASE     # the chosen rate
    @rate    = BASE     # the rate in use (lower than @target while the computer can't keep up)
    @phase   = 0        # where the next drawn frame falls, in 1/@rate-of-a-step units
    @delta   = nil      # time the last step took, for Graphics.delta
    @booted  = false
    @sprites = ObjectSpace::WeakMap.new   # sprites on the map's viewport

    class << self
      attr_reader :rate, :target, :logic
      attr_accessor :count
    end

    #---------------------------------------------------------------------------
    # The setting
    #---------------------------------------------------------------------------
    def self.choice
      v = ($PokemonSystem.cody_framerate rescue 0).to_i
      return CHOICES[v] || BASE
    end

    def self.wanted
      c = choice
      return (c == :monitor) ? monitor_hz : c
    end

    def self.labels
      return CHOICES.map { |c| (c == :monitor) ? _INTL("Match monitor ({1})", monitor_hz) : c.to_s }
    end

    # The monitor's refresh rate, asked from Windows (60 if it won't say)
    def self.monitor_hz
      return @monitor_hz if @monitor_hz
      hz = nil
      begin
        if defined?(Win32API)
          api = Win32API.new("user32", "EnumDisplaySettingsW", "LLP", "L")
          mode = "\0".b * 220                       # DEVMODEW
          mode[68, 2] = [220].pack("S")             # dmSize
          hz = mode[184, 4].unpack1("L") if api.call(0, 0xFFFFFFFF, mode) != 0   # dmDisplayFrequency
        end
      rescue StandardError, ScriptError
        hz = nil
      end
      hz = 60 unless hz.is_a?(Integer) && hz > 1   # 0 and 1 mean "the hardware's default"
      @monitor_hz = [[hz, BASE].max, MAX].min
      return @monitor_hz
    end

    def self.apply(rate = nil)
      @target = rate || wanted
      use(@target)
      @backoff = WAIT_UP
      @came_up = false
    rescue => e
      KIF.log("Frame rate change failed (#{e.class}: #{e.message})")
    end

    def self.use(rate)
      @rate = rate
      @phase = 0
      @camera = nil
      @window = @slow = @good = 0
      @last_at = nil
      set_real
    end

    # Extra frames are drawn only while the game runs at its normal 40
    def self.drawing_between?
      return @rate > BASE && @logic == BASE
    end

    def self.logic=(value)
      @logic = (value.to_i > 0) ? value.to_i : BASE
      @phase = 0
      set_real
    end

    def self.set_real
      real = drawing_between? ? @rate : @logic
      Graphics.kif_fps_set_rate(real) if Graphics.kif_fps_rate != real
    end

    # n frames at 40 -> the same length of time in drawn frames
    def self.real_frames(n)
      return n unless drawing_between? && n.is_a?(Numeric)
      return (n * @rate / BASE.to_f).round
    end

    def self.boot
      return unless $PokemonSystem
      @booted = true
      apply
    end

    #---------------------------------------------------------------------------
    # One game step: draw it, plus the frames in between when above 40
    #---------------------------------------------------------------------------
    def self.step
      @count += 1
      boot unless @booted
      watch_speed if @logic == BASE && (@target > BASE || $DEBUG)
      unless drawing_between?
        @delta = nil
        yield
        return
      end
      # where the drawn frames fall: at 60 that's 2/3 | 1/3, 1 | 2/3 | 1/3, 1 ...
      fractions = []
      while @phase + BASE <= @rate
        @phase += BASE
        fractions << @phase.to_f / @rate
      end
      @phase -= @rate
      shot = capture
      total = 0
      if shot.nil? || fractions.length < 2
        # nothing on the map moved (menu, battle, standing still): one frame,
        # then the rest of the step's time is waited out instead of drawn
        yield
        total += Graphics.kif_fps_delta.to_i if Graphics.respond_to?(:kif_fps_delta)
        if fractions.length > 1
          rest = (fractions.length - 1) / @rate.to_f
          sleep(rest)
          total += (rest * 1_000_000).round
          Graphics.frame_reset if Graphics.respond_to?(:frame_reset)
        end
      else
        begin
          fractions.each do |a|
            pose(shot, a)
            yield
            total += Graphics.kif_fps_delta.to_i if Graphics.respond_to?(:kif_fps_delta)
          end
        ensure
          restore(shot)
        end
      end
      @delta = total
    end

    def self.delta
      return drawing_between? ? @delta : nil
    end

    #---------------------------------------------------------------------------
    # What moved during this step
    #---------------------------------------------------------------------------
    def self.map_viewport
      return (defined?(Spriteset_Map) && Spriteset_Map.respond_to?(:viewport)) ? Spriteset_Map.viewport : nil
    end

    def self.panorama_viewport
      return Spriteset_Map.class_variable_get(:@@viewport0)
    rescue NameError
      return nil
    end

    def self.track(sprite, viewport)
      return unless viewport && viewport.equal?(map_viewport)
      return if defined?(TilemapRenderer::TileSprite) && sprite.is_a?(TilemapRenderer::TileSprite)
      @sprites[sprite] = true
    end

    # [map id, x, y] of the screen's top left corner on the map, in pixels
    def self.camera
      return [$game_map.map_id, $game_map.display_x.to_f / Game_Map::X_SUBPIXELS,
              $game_map.display_y.to_f / Game_Map::Y_SUBPIXELS]
    end

    # How far the camera moved this step, or nil if it jumped
    def self.camera_move(now, last)
      return nil unless last
      dx = now[1] - last[1]
      dy = now[2] - last[2]
      if now[0] != last[0]
        # walked onto a connected map: its coordinates start at its own corner
        off = ($MapFactory.getRelativePos(last[0], 0, 0, now[0], 0, 0) rescue nil)
        return nil unless off
        dx += off[0] * Game_Map::TILE_WIDTH
        dy += off[1] * Game_Map::TILE_HEIGHT
      end
      return nil if dx.abs > MAX_CAMERA || dy.abs > MAX_CAMERA
      return [dx, dy]
    end

    def self.capture
      vp = map_viewport
      return nil unless vp && !vp.disposed? && $game_map
      now = camera
      cam = camera_move(now, @camera)
      @camera = now
      moving = []
      @sprites.each_key do |s|
        next if s.disposed?
        x = s.x
        y = s.y
        at = s.instance_variable_get(:@kif_fps_at)
        unless at
          s.instance_variable_set(:@kif_fps_at, [x, y])
          next
        end
        px = at[0]
        py = at[1]
        at[0] = x
        at[1] = y
        next unless cam && s.visible && s.viewport.equal?(vp)
        sdx = x - px
        sdy = y - py
        next if sdx.abs > MAX_JUMP || sdy.abs > MAX_JUMP
        # unchanged in the world (a standing NPC): the camera's slide covers it
        next if (sdx + cam[0]).abs < 0.5 && (sdy + cam[1]).abs < 0.5
        moving << [s, x, y, sdx, sdy]
      end
      return nil unless cam
      return nil if moving.empty? && cam[0].abs < 0.5 && cam[1].abs < 0.5
      vp0 = panorama_viewport
      vp0 = nil if vp0 && vp0.disposed?
      return [vp, vp.ox, vp.oy, cam[0], cam[1], moving, vp0, vp0 ? vp0.ox : 0, vp0 ? vp0.oy : 0]
    end

    SET_X = Sprite.instance_method(:x=)   # the plain setters: no attached-sprite side effects
    SET_Y = Sprite.instance_method(:y=)

    # Show the step as it was a fraction a (0 < a < 1) of the way from the last one
    def self.pose(shot, a)
      return restore(shot) if a >= 1
      vp, ox, oy, cx, cy, moving, vp0, ox0, oy0 = shot
      back = 1 - a
      sx = (-back * cx).round        # the whole map slides with the camera...
      sy = (-back * cy).round
      vp.ox = ox + sx
      vp.oy = oy + sy
      if vp0                          # (the panorama scrolls at half speed)
        vp0.ox = ox0 + (-back * cx / 2).round
        vp0.oy = oy0 + (-back * cy / 2).round
      end
      moving.each do |s, x, y, dx, dy|   # ...and what moved on it is placed between its two spots
        next if s.disposed?
        SET_X.bind_call(s, (x - back * dx).round + sx)
        SET_Y.bind_call(s, (y - back * dy).round + sy)
      end
    end

    def self.restore(shot)
      vp, ox, oy, _cx, _cy, moving, vp0, ox0, oy0 = shot
      unless vp.disposed?
        vp.ox = ox
        vp.oy = oy
      end
      if vp0 && !vp0.disposed?
        vp0.ox = ox0
        vp0.oy = oy0
      end
      moving.each do |s, x, y|
        next if s.disposed?
        SET_X.bind_call(s, x)
        SET_Y.bind_call(s, y)
      end
    end

    #---------------------------------------------------------------------------
    # Key repeat counted in steps (once per Input.update), like the engine at
    # 40: the newest pressed button repeats; raw keys (text entry) each repeat
    #---------------------------------------------------------------------------
    @repeating = nil
    @repeat_count = 0
    @raw = {}            # raw key => steps held (keys asked about with repeatex?)

    def self.buttons
      @buttons ||= [:DOWN, :LEFT, :RIGHT, :UP, :A, :B, :C, :X, :Y, :Z, :L, :R].map { |b|
        Input.const_defined?(b) ? Input.const_get(b) : nil
      }.compact.uniq
    end

    def self.button(b)
      return (b.is_a?(Symbol) && Input.const_defined?(b)) ? Input.const_get(b) : b
    end

    def self.input_step
      hit = buttons.find { |b| Input.trigger?(b) }
      if hit
        @repeating = hit
        @repeat_count = 0
      elsif @repeating && Input.press?(@repeating)
        @repeat_count += 1
      else
        @repeating = nil
      end
      @raw.each_key do |k|
        if Input.triggerex?(k)
          @raw[k] = 0
        elsif @raw[k] && Input.pressex?(k)
          @raw[k] += 1
        else
          @raw[k] = nil
        end
      end
    end

    def self.repeated?(b)
      return false unless @repeating && button(b) == @repeating
      return @repeat_count == 0 ||
             (@repeat_count >= REPEAT_START && ((@repeat_count + 1) & REPEAT_DELAY) == 0)
    end

    def self.repeated_raw?(k)
      unless @raw.key?(k)
        @raw[k] = Input.triggerex?(k) ? 0 : nil
      end
      c = @raw[k]
      return false unless c
      return c == 0 || (c >= REPEAT_START && (c + 1) % REPEAT_DELAY == 0)
    end

    #---------------------------------------------------------------------------
    # Keeping up: if most steps in the last 2 seconds were slow, go one rate
    # lower; after a smooth while, try the next one up again
    #---------------------------------------------------------------------------
    def self.clock
      return Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.watch_speed
      now = clock
      last = @last_at
      @last_at = now
      return unless last
      @window += 1
      took = now - last
      @slow += 1 if took > SLOW_STEP
      if $DEBUG
        maps = ($MapFactory ? $MapFactory.maps.map(&:map_id) : []) rescue []
        note_slow(took, maps) if took > LOG_STEP
        @maps_were = maps
      end
      return if @window < WINDOW
      if @slow > WINDOW / 2 && @rate > BASE
        lower = rates.select { |r| r < @rate }.max || BASE
        KIF.log("Frame rate: #{@rate} was too much for this computer, now #{lower}")
        # straight back down after trying a rate again: wait twice as long next time
        @backoff = [@backoff * 2, WAIT_UP * 32].min if @came_up
        @came_up = false
        use(lower)
        return
      elsif @slow < WINDOW / 10 && @rate < @target
        @good += @window
        if @good >= @backoff
          use(rates.select { |r| r > @rate }.min || @target)
          @came_up = true
          return
        end
      else
        @good = 0
      end
      @window = @slow = 0
    end

    # With KIF's debug option on: slow steps go to KIF_framelog.txt in the
    # save folder, with where the player was and what the game was doing
    def self.note_slow(took, maps)
      ev = (pbMapInterpreterRunning? rescue false)
      msg = (($game_temp && $game_temp.message_window_showing) rescue false)
      line = sprintf("%s  %5.1f ms  map %s at %s,%s  maps loaded %s%s  rate %d/%d%s%s",
                     Time.now.strftime("%H:%M:%S"), took * 1000,
                     ($game_map ? $game_map.map_id : "-"), ($game_player ? $game_player.x : "-"),
                     ($game_player ? $game_player.y : "-"), maps.inspect,
                     (@maps_were && @maps_were != maps) ? " (was #{@maps_were.inspect})" : "",
                     @rate, @target, ev ? "  event running" : "", msg ? "  message" : "")
      path = File.join((RTP.getSaveFolder rescue "."), "KIF_framelog.txt")
      File.open(path, "a") { |f| f.puts(line) }
    rescue
      nil
    end

    def self.rates
      return (CHOICES.grep(Integer) + [@target]).uniq.select { |r| r <= @target }.sort
    end

    @backoff = WAIT_UP
  end
end

KIF::Options.add(:cody_interface, :global) {
  KIF::FrameRate::Choice.new(_INTL("Frame rate"), KIF::FrameRate.labels,
                             proc { [[$PokemonSystem.cody_framerate.to_i, 0].max, KIF::FrameRate::CHOICES.length - 1].min },
                             proc { |value|
                               $PokemonSystem.cody_framerate = value
                               KIF::FrameRate.apply
                             },
                             _INTL("Frames drawn per second (experimental). The game still runs at PIF's pace; above 40 the overworld gets in-between frames."))
}

#===============================================================================
# Engine hooks
#===============================================================================
module Graphics
  class << self
    unless method_defined?(:kif_fps_draw)
      # The game's step reaches the screen here (after speed-up has skipped
      # what it skips, and before the special-transition bookkeeping)
      present = method_defined?(:update_KGC_SpecialTransition) ? :update_KGC_SpecialTransition : :update
      alias_method :kif_fps_draw, present
      define_method(present) { KIF::FrameRate.step { kif_fps_draw } }

      # The game keeps seeing its own 40 and counting steps
      alias_method :kif_fps_rate, :frame_rate
      alias_method :kif_fps_set_rate, :frame_rate=
      alias_method :kif_fps_count, :frame_count
      def frame_rate; KIF::FrameRate.logic; end
      def frame_rate=(value); KIF::FrameRate.logic = value; end
      def frame_count; KIF::FrameRate.count; end
      def frame_count=(value); KIF::FrameRate.count = value.to_i; end

      if method_defined?(:delta)
        alias_method :kif_fps_delta, :delta
        def delta; KIF::FrameRate.delta || kif_fps_delta; end
      end

      # Built-in effects that count drawn frames: same length in seconds
      trans = method_defined?(:transition_KGC_SpecialTransition) ? :transition_KGC_SpecialTransition : :transition
      if method_defined?(trans)
        alias_method :kif_fps_transition, trans
        define_method(trans) do |duration = 8, *rest|
          KIF::FrameRate.count += duration.to_i if duration.is_a?(Numeric) && duration > 0
          kif_fps_transition(KIF::FrameRate.real_frames(duration), *rest)
        end
      end
      [:wait, :fadeout, :fadein].each do |m|
        next unless method_defined?(m)
        alias_method :"kif_fps_#{m}", m
        define_method(m) do |frames, *rest|
          KIF::FrameRate.count += frames.to_i if frames.is_a?(Numeric) && frames > 0
          send(:"kif_fps_#{m}", KIF::FrameRate.real_frames(frames), *rest)
        end
      end
    end
  end
end

KIF::FrameRate.instance_variable_set(:@count, Graphics.kif_fps_count.to_i)
KIF::FrameRate.instance_variable_set(:@logic, Graphics.kif_fps_rate.to_i > 0 ? Graphics.kif_fps_rate.to_i : KIF::FrameRate::BASE)

module Input
  class << self
    unless method_defined?(:kif_fps_input_update)
      alias_method :kif_fps_input_update, :update
      def update
        kif_fps_input_update
        KIF::FrameRate.input_step
      end
      if method_defined?(:repeat?)
        alias_method :kif_fps_repeat?, :repeat?
        def repeat?(button)
          return KIF::FrameRate.drawing_between? ? KIF::FrameRate.repeated?(button) : kif_fps_repeat?(button)
        end
      end
      if method_defined?(:repeatex?) && method_defined?(:triggerex?) && method_defined?(:pressex?)
        alias_method :kif_fps_repeatex?, :repeatex?
        def repeatex?(key, *rest)
          return kif_fps_repeatex?(key, *rest) unless rest.empty? && KIF::FrameRate.drawing_between?
          return KIF::FrameRate.repeated_raw?(key)
        end
      end
    end
  end
end

# Remember the sprites put on the map's viewport
class Sprite
  alias kif_fps_initialize initialize unless private_method_defined?(:kif_fps_initialize)

  def initialize(*args)
    kif_fps_initialize(*args)
    KIF::FrameRate.track(self, args[0])
  end
end

# While drawing in between, keep one spare tile of map all round the screen
# (the slide can show a few pixels past the edge). The tile grid is moved one
# tile up and left by working out its tiles from a camera one tile further
# back, then drawing them one tile further on, so they land where they belong.
if defined?(TilemapRenderer)
  class TilemapRenderer
    alias kif_fps_update update unless method_defined?(:kif_fps_update)
    alias kif_fps_tile_coordinates refresh_tile_coordinates unless method_defined?(:kif_fps_tile_coordinates)
    alias kif_fps_tile_z refresh_tile_z unless method_defined?(:kif_fps_tile_z)

    def update
      ring = KIF::FrameRate.drawing_between?
      kif_fps_ring(ring) if ring != !!@kif_ring
      return kif_fps_update unless @kif_ring
      shift_x = Game_Map::TILE_WIDTH * Game_Map::X_SUBPIXELS
      shift_y = Game_Map::TILE_HEIGHT * Game_Map::Y_SUBPIXELS
      maps = (($MapFactory ? $MapFactory.maps : []) + [$game_map]).compact.uniq
      kept = maps.map { |m| [m, m.instance_variable_get(:@display_x), m.instance_variable_get(:@display_y)] }
      begin
        kept.each do |m, x, y|
          m.instance_variable_set(:@display_x, x - shift_x)
          m.instance_variable_set(:@display_y, y - shift_y)
        end
        kif_fps_update
      ensure
        kept.each do |m, x, y|
          m.instance_variable_set(:@display_x, x)
          m.instance_variable_set(:@display_y, y)
        end
      end
    end

    def refresh_tile_coordinates(tile, x, y)
      return kif_fps_tile_coordinates(tile, x, y) unless @kif_ring
      kif_fps_tile_coordinates(tile, x - 1, y - 1)
    end

    def refresh_tile_z(tile, map, y, layer, tile_id)
      kif_fps_tile_z(tile, map, @kif_ring ? y - 1 : y, layer, tile_id)
    end

    def kif_fps_ring(on)
      @tiles.each { |col| col.each { |coord| coord.each { |tile| tile.dispose } } }
      extra = on ? 3 : 1   # the usual spare row/column, plus one on each side
      @tiles_horizontal_count = (Graphics.width.to_f / DISPLAY_TILE_WIDTH).ceil + extra
      @tiles_vertical_count = (Graphics.height.to_f / DISPLAY_TILE_HEIGHT).ceil + extra
      @tiles = Array.new(@tiles_horizontal_count) {
        Array.new(@tiles_vertical_count) { Array.new(3) { TileSprite.new(@viewport) } }
      }
      @kif_ring = on
      @old_tone = nil      # new tiles take the current tone/colour on the next update
      @old_color = nil
      @need_refresh = true
    end
  end
end

# Play time is counted in steps. (Experimental builds before this one counted
# drawn frames at 60, so a save from them is converted.)
SaveData.register(:kif_frame_rate) do
  save_value { KIF::FrameRate::BASE }
  load_value { |value|
    if value.is_a?(Integer) && value > 0 && value != KIF::FrameRate::BASE
      Graphics.frame_count = (Graphics.frame_count * KIF::FrameRate::BASE / value.to_f).round
    end
  }
  new_game_value { KIF::FrameRate::BASE }
end
