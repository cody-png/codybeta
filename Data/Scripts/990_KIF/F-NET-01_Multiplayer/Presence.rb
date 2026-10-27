#===============================================================================
# F-NET-01 – Multiplayer: seeing each other on the map (presence)
# (new, 2026-10-24; design: Claude Docs/Base KIF/MULTIPLAYER_PLAN.md, section
# "Presence (branch kif-mp-presence)")
#
# While connected, the partner is drawn when they are on your map, or on a
# map joined to yours that is on screen: their skin, outfit, hair and hats as
# PIF draws the player, walking, running, biking, surfing, diving, fishing
# and jumping, with their name above. They walk through everything (a ghost):
# nothing bumps into them and they start no events; their own game runs
# their encounters and events. Nothing is sent, kept or drawn while not
# connected.
#
# Messages (added to KIF::Net::TYPES here; checked again below):
#   pr_at    where I am: map, x, y, facing, action (walk/run/bike/surf/dive/
#            fish), speed x10, hidden, and the tiles stepped on since the
#            last pr_at ([x, y], or [x, y, 1] for a jump). Sent when something
#            changed, at most 4 times a second (sooner only on a map change or
#            after 24 tiles), nothing while standing still.
#   pr_look  my outfit ids and colours: on connect and when they change;
#            again with a map change's pr_at and every 30 s of moving.
#   pr_do    what I'm doing: idle, talk (an event or a message box), menu,
#            bag, party (party, PC, a team pick), battle or trade; sent when
#            it changes, shown as an icon after the name
# Outfit ids from the other game only ever name a file inside PIF's outfit
# folders (letters, digits, _ - and spaces), so a peer can't point at
# another file.
#
# The partner's game is a little behind (up to a quarter second plus the
# line): their steps are queued and walked; 2+ steps behind they walk one
# speed faster, 16+ behind they appear at the newest place. A warp fades
# them out and in; crossing into a joined map keeps them where they are.
#===============================================================================
module KIF
  module Presence
    ACTIONS    = %w[walk run bike surf dive fish]
    LOW        = %w[surf dive fish]   # drawn 16 px lower, as PIF draws the player
    SEND_EVERY = 0.25    # seconds between pr_at while something changes
    MAX_PATH   = 24
    LOOK_AGAIN = 30.0    # seconds: the look goes again with a pr_at (and with every map change)
    HURRY_AT   = 2       # steps queued: walk one speed faster
    SNAP_AT    = 16      # steps queued: appear at the newest place
    MAX_PEERS  = 2       # partners drawn at once (2 or 3 players, never 4)
    FADE_STEP  = 26      # opacity a frame: a 10-frame fade
    TAG_Z      = 2900    # name tags over the map's sprites, under fog
    ID         = /\A[\w \-]{0,40}\z/
    COORD      = [Integer, -64, 100_000]
    COLOR      = [Integer, -1_000_000, 1_000_000]
    OFFSET_SETS = { "run" => "RUN", "surf" => "SURF", "dive" => "DIVE", "bike" => "BIKE", "fish" => "FISH" }
    ROWS       = %w[DOWN LEFT RIGHT UP]
    DEFAULT_LOOK = { "skin" => "default", "clothes" => "", "hair" => "", "hat" => "", "hat2" => "", "surf" => "",
                     "cc" => 0, "hc" => 0, "tc" => 0, "t2c" => 0, "bc" => 0 }

    KIF::Net::TYPES.merge!(
      "pr_at"   => { "m" => [Integer, 1, 100_000], "x" => COORD, "y" => COORD, "d" => [Integer, 0, 9],
                     "a" => [String, 8], "v" => [Integer, 1, 80], "h" => [Integer, 0, 1], "p" => [Array] },
      "pr_look" => { "skin" => [String, 24], "clothes" => [String, 40], "hair" => [String, 40],
                     "hat" => [String, 40], "hat2" => [String, 40], "surf" => [String, 24],
                     "cc" => COLOR, "hc" => COLOR, "tc" => COLOR, "t2c" => COLOR, "bc" => COLOR },
      "pr_do"   => { "a" => [String, 8] }
    )
    DOING      = %w[idle talk menu bag party battle trade dex card options save]

    # The local player in one frame (tests make their own)
    State = Struct.new(:m, :x, :y, :d, :a, :v, :h, :j)

    # [[x, y] or [x, y, 1], ...] or nil when anything doesn't fit
    def self.read_path(p)
      return nil unless p.is_a?(Array) && p.length <= MAX_PATH
      p.map do |e|
        return nil unless e.is_a?(Array) && (e.length == 2 || (e.length == 3 && e[2] == 1)) &&
                          e.all? { |v| v.is_a?(Integer) && v >= COORD[1] && v <= COORD[2] }
        e.length == 3 ? [e[0], e[1], 1] : [e[0], e[1]]
      end
    end

    # a checked pr_look: an id that isn't a plain name becomes "" (not drawn)
    def self.read_look(msg)
      look = {}
      %w[skin clothes hair hat hat2 surf].each { |k| look[k] = msg[k].to_s =~ ID && !(k.start_with?("hat") && msg[k].to_s == "0") ? msg[k].to_s : "" }
      look["skin"] = "default" if look["skin"].empty?
      %w[cc hc tc t2c bc].each { |k| look[k] = msg[k].to_i % 360 }   # a hue shift: only 0-359 differ
      return look
    end

    # tiles to add to a position on map `from` to get the same spot on map
    # `to`, or nil when the two maps aren't joined
    def self.map_offset(from, to)
      (MapFactoryHelper.getMapConnections[from] || []).each do |c|
        return [c[4] - c[1], c[5] - c[2]] if c[0] == from && c[3] == to
        return [c[1] - c[4], c[2] - c[5]] if c[3] == from && c[0] == to
      end
      return nil
    rescue StandardError
      return nil
    end

    def self.loaded?(map_id); $MapFactory ? $MapFactory.hasMap?(map_id) : false; end

    #---------------------------------------------------------------------------
    # One connection: what we send, and the partner's ghost
    #---------------------------------------------------------------------------
    class Link
      attr_reader :ghosts

      def initialize
        @ghosts = {}       # partner => Ghost
        @sent = nil        # State last sent
        @look_sent = nil
        @cur = nil         # State last seen
        @path = []
        @next_at = 0.0
      end

      # The local player this frame: [type, fields] to post
      def track(st, look, now)
        out = []
        if look && look != @look_sent
          @look_sent = look
          @look_due = now + LOOK_AGAIN
          out << ["pr_look", look]
        end
        sent_look = !out.empty?
        prev = @cur
        @cur = st
        if prev && prev.m != st.m
          out << ["pr_at", at(prev)] unless @path.empty?   # the old map's last steps first
          @path = []
        elsif prev && (prev.x != st.x || prev.y != st.y)
          @path << (st.j ? [st.x, st.y, 1] : [st.x, st.y])
        end
        new_map = @sent.nil? || @sent.m != st.m
        return out unless new_map || !@path.empty? || changed?(@sent, st)
        return out unless new_map || now >= @next_at || @path.length >= MAX_PATH
        # the same look again with a new map's place, or after LOOK_AGAIN s: one
        # that didn't land is put right (the other game skips an unchanged look)
        if look && !sent_look && (new_map || now >= @look_due)
          @look_due = now + LOOK_AGAIN
          out << ["pr_look", look]
        end
        out << ["pr_at", at(st)]
        @path = []
        @sent = st
        @next_at = now + SEND_EVERY
        return out
      end

      def receive(type, msg, name, key = :partner)
        g = @ghosts[key]
        unless g
          return nil if @ghosts.length >= MAX_PEERS
          g = @ghosts[key] = Ghost.new(name)
        end
        case type
        when "pr_look" then g.look = Presence.read_look(msg)
        when "pr_do" then g.doing = DOING.include?(msg["a"]) ? msg["a"] : "idle"
        else g.receive_at(msg)
        end
        return g
      end

      def update; @ghosts.each_value(&:update); end
      def close; @ghosts.each_value(&:retire); @ghosts.clear; end

      private

      def at(st)
        { "m" => st.m, "x" => st.x, "y" => st.y, "d" => st.d, "a" => st.a, "v" => st.v, "h" => st.h, "p" => @path.dup }
      end

      # speed alone (a run key pressed while standing) sends nothing
      def changed?(a, b); a.x != b.x || a.y != b.y || a.d != b.d || a.a != b.a || a.h != b.h; end
    end

    #---------------------------------------------------------------------------
    # The partner as a map character. Never in $game_map.events, so the
    # player and events never bump into it; it moves itself (no step or tile
    # events, no passability) and draws through PartnerSprite.
    #---------------------------------------------------------------------------
    class Ghost < Game_Character
      attr_reader :name, :map_id, :action, :look, :plan, :pending
      attr_writer :map
      attr_accessor :doing

      # the name tag: the name, and an icon for what they're doing unless idle
      def tag; [@name, DOING.include?(@doing) ? @doing : "idle"]; end

      def initialize(name)
        super(nil)
        @name = name.to_s
        @through = true
        @plan = []
        @map_id = nil
        @action = "walk"
        @speed = 3.0
        @want_dir = 2
        @look = nil
        @sheets = {}
        @hidden = false
        @opacity = 0
        @fade_to = 255
        @pending = nil
      end

      def hidden; @hidden; end
      def surfing?; @action == "surf" || @action == "dive"; end
      def surf_shape; (@look || DEFAULT_LOOK)["surf"]; end

      def look=(l)
        return if l == @look
        retire
        @look = l
      end

      # this action's sheet, made once a look
      def sheet
        return @sheets[@action] if @sheets.key?(@action)
        return @sheets[@action] = Presence.build_sheet(@look, @action)
      end

      def retire
        Presence.retire(@sheets.values.compact)
        @sheets = {}
      end

      # a checked pr_at; false when its path doesn't fit
      def receive_at(msg)
        path = Presence.read_path(msg["p"]) or return false
        target = [msg["x"], msg["y"]]
        m = msg["m"]
        @want_dir = msg["d"] if [2, 4, 6, 8].include?(msg["d"])
        @action = ACTIONS.include?(msg["a"]) ? msg["a"] : "walk"
        @speed = (msg["v"] / 10.0).clamp(0.5, 6.0)
        @hidden = msg["h"] == 1
        if @pending   # still fading out: arrive at the newest place
          @pending = [m, target]
          return true
        end
        if @map_id != m
          off = @map_id && Presence.map_offset(@map_id, m)
          return warp(m, target) unless off
          shift(off)   # walked into a joined map: same spot, that map's numbers
          @map_id = m
        end
        unless Presence.loaded?(m)   # not on screen here: no need to walk
          @plan.clear
          place(*target)
          return true
        end
        @plan.concat(path)
        @plan << target if (@plan.last || [@x, @y])[0, 2] != target
        if @plan.length >= SNAP_AT
          @plan.clear
          place(*target)
        end
        return true
      end

      def update
        return unless @map_id
        @fade_to = 0 if @pending && @plan.empty? && !moving? && !jumping?   # at the door: now fade out
        fade
        @moved_last_frame = @moved_this_frame
        start_next unless moving? || jumping?
        if moving? || jumping?
          glide
        else
          @moved_this_frame = false
          @direction = @want_dir if @plan.empty?
        end
        if surfing?
          p = (Graphics.frame_count % 60) / 15   # PIF's surf bob (Game_Player#update_pattern)
          @pattern = @pattern_surf = p
          @bob_height = p >= 2 ? 2 : 0
        else
          @bob_height = 0
          update_pattern
        end
      end

      private

      def warp(m, target)
        if @map_id && Presence.loaded?(@map_id) && @opacity > 0
          @pending = [m, target]   # the old map's last steps are walked first (update fades after them)
        else
          @plan.clear
          arrive(m, target)
        end
        return true
      end

      def arrive(m, target)
        @pending = nil
        @map_id = m
        place(*target)
        @direction = @want_dir
        @opacity = 0
        @fade_to = 255
      end

      def fade
        return if @opacity == @fade_to
        @opacity = @fade_to > @opacity ? [@opacity + FADE_STEP, 255].min : [@opacity - FADE_STEP, 0].max
        arrive(*@pending) if @pending && @opacity == 0
      end

      def place(x, y)
        @x = x
        @y = y
        @real_x = x * Game_Map::REAL_RES_X
        @real_y = y * Game_Map::REAL_RES_Y
        @jump_distance_left = 0
        @jump_count = 0
      end

      def shift(off)
        dx, dy = off
        @x += dx
        @y += dy
        @real_x += dx * Game_Map::REAL_RES_X
        @real_y += dy * Game_Map::REAL_RES_Y
        @plan.map! { |p| [p[0] + dx, p[1] + dy] + p[2..-1] }
      end

      def start_next
        while (nxt = @plan.shift)
          dx = nxt[0] - @x
          dy = nxt[1] - @y
          next if dx == 0 && dy == 0
          self.move_speed = [@speed + (@plan.length >= HURRY_AT ? 1 : 0), 6].min
          @direction = dx.abs > dy.abs ? (dx < 0 ? 4 : 6) : (dy < 0 ? 8 : 2)
          if nxt[2] == 1 && dx.abs <= 4 && dy.abs <= 4
            @x, @y = nxt[0], nxt[1]   # Game_Character#jump without its checks
            @jump_peak = [1, Math.sqrt(dx * dx + dy * dy)].max * Game_Map::TILE_HEIGHT * 3 / 8
            @jump_distance = [dx.abs * Game_Map::REAL_RES_X, dy.abs * Game_Map::REAL_RES_Y].max
            @jump_distance_left = 1
            @jump_count = 0
          elsif dx.abs + dy.abs == 1
            @x, @y = nxt[0], nxt[1]
          else
            place(nxt[0], nxt[1])   # moved by an event or a door on the same map
          end
          return
        end
      end

      # Game_Character#update_move without the step events: the partner's
      # own game runs those
      def glide
        d = jumping? ? jump_speed_real : move_speed_real
        tx = @x * Game_Map::REAL_RES_X
        ty = @y * Game_Map::REAL_RES_Y
        @real_x = @real_x < tx ? [@real_x + d, tx].min : [@real_x - d, tx].max
        @real_y = @real_y < ty ? [@real_y + d, ty].min : [@real_y - d, ty].max
        @jump_distance_left = [(tx - @real_x).abs, (ty - @real_y).abs].max if jumping?
        @anime_count += 1
        @moved_this_frame = true
      end
    end

    #---------------------------------------------------------------------------
    # The partner's sheet: PIF's player layers made into one picture per
    # action (Sprite_Player draws them as separate sprites; the offsets are
    # Sprite_Hair's and Sprite_Wearable's). Missing pieces fall back like
    # PIF's: the default skin, the stand-in outfit, no hair or hat. nil when
    # there's no base picture at all (only the name is shown then).
    #---------------------------------------------------------------------------
    # an AnimatedBitmap, or nil; build_sheet frees it once drawn
    def self.layer(file, hue = 0)
      return nil if file.nil? || !pbResolveBitmap(file)
      return AnimatedBitmap.new(file, hue.to_i % 360)
    end

    def self.offsets(action, row)
      set = OFFSET_SETS[action] or return Outfit_Offsets::BASE_OFFSET
      return Outfit_Offsets.const_get("#{set}_OFFSETS_#{ROWS[row]}")
    end

    # the first row with a drawn pixel in that part of bmp (h when empty)
    def self.opaque_top(bmp, x, y, w, h)
      h.times { |j| w.times { |i| return j if bmp.get_pixel(x + i, y + j).alpha > 0 } }
      return h
    end

    # a frame of `src` moved by off (+ lift up), kept inside its cell
    def self.cell_blt(out, src, sx, sy, dx, dy, off, lift, cw, ch)
      ox = off[0]
      oy = off[1] + lift
      x0 = [ox, 0].max
      y0 = [oy, 0].max
      w = cw - ox.abs
      h = ch - oy.abs
      return if w <= 0 || h <= 0
      out.blt(dx + x0, dy + y0, src, Rect.new(sx + x0 - ox, sy + y0 - oy, w, h))
    end

    def self.build_sheet(look, action)
      look ||= DEFAULT_LOOK
      loaded = []   # every layer is freed below: a hued copy would otherwise stay in RPG::Cache for good
      use = ->(ab) { ab && (loaded << ab) && ab.bitmap }
      skin = look["skin"]
      file = getBaseOverworldSpriteFilename(action, skin)
      unless file
        action = "walk"
        file = getBaseOverworldSpriteFilename(action, skin)
      end
      base = use.(layer(file)) or return nil
      out = Bitmap.new(base.width, base.height)
      cw = base.width / 4
      ch = base.height / 4
      if action == "bike" && (bike = use.(layer(getOverworldBicycleFilename, look["bc"])))
        out.blt(0, 0, bike, bike.rect)   # Sprite_Bicycle is under the player
      end
      out.blt(0, 0, base, base.rect)
      clothes = use.(layer(getOverworldOutfitFilename(look["clothes"], action), look["cc"])) ||
                use.(layer(getOverworldOutfitFilename(Settings::PLAYER_TEMP_OUTFIT_FALLBACK, action)))
      out.blt(0, 0, clothes, clothes.rect) if clothes
      hair = look["hair"].empty? ? nil : use.(layer(getOverworldHairFilename(look["hair"]), look["hc"]))
      hats = [["hat2", "t2c"], ["hat", "tc"]].map { |k, c| look[k].empty? ? nil : use.(layer(getOverworldHatFilename(look[k]), look[c])) }.compact
      4.times do |row|
        off = offsets(action, row)
        4.times do |f|
          if hair   # surf hair stays on its first frame
            hf = action == "surf" ? 0 : f
            cell_blt(out, hair, hf * cw, row * ch, f * cw, row * ch, off[hf], 0, cw, ch)
          end
          hats.each { |h| cell_blt(out, h, 0, row * ch, f * cw, row * ch, off[f], f.odd? ? -2 : 0, cw, ch) }
        end
      end
      return out
    rescue StandardError => e
      oops(e)
      return nil
    ensure
      loaded&.each { |ab| ab.dispose unless ab.disposed? }
    end

    # the Pokémon the partner surfs or dives on (Sprite_SurfBase's pictures)
    def self.surf_base(shape, action)
      key = [shape.to_s, action]
      b = @surf[key]
      return nil if b == :none
      return b.bitmap if b && !b.bitmap.disposed?   # (the cache is cleared on some warps)
      dir = Settings::PLAYER_GRAPHICS_FOLDER + Settings::PLAYER_SURFBASE_FOLDER
      file = dir + (action == "dive" ? "divemon_" : "surfmon_") + shape.to_s
      file = dir + (action == "dive" ? "divemon_Head" : "surfmon_board") if shape.to_s.empty? || !pbResolveBitmap(file)
      @surf[key] = b = pbResolveBitmap(file) ? AnimatedBitmap.new(file) : :none
      return b == :none ? nil : b.bitmap
    end

    #---------------------------------------------------------------------------
    # Drawn by every map's spriteset (as DependentEventSprites): the one whose
    # map the partner is on shows them
    #---------------------------------------------------------------------------
    class PartnerSprite
      attr_reader :key

      def initialize(viewport, map, key)
        @map = map
        @key = key
        @disposed = false
        @body = Sprite.new(viewport)
        @base = Sprite.new(viewport)
        @tag = Sprite.new(viewport)
        @tag_bmp = nil
        @tag_name = nil
        hide
      end

      def disposed?; @disposed; end

      def dispose
        return if @disposed
        [@body, @base, @tag].each(&:dispose)
        @tag_bmp.dispose if @tag_bmp
        @disposed = true
      end

      def visible?; @tag.visible; end
      def body; @body; end
      def tag; @tag; end

      def update
        return if @disposed
        g = Presence.ghost(@key)
        return hide unless g && g.map_id == @map.map_id && !g.hidden
        g.map = @map
        top = draw_body(g)
        draw_base(g)
        draw_tag(g, top)
      rescue StandardError => e   # runs inside the map's spriteset: never take the game down
        Presence.oops(e)
        hide
      end

      private

      def hide
        [@body, @base, @tag].each { |s| s.visible = false; s.bitmap = nil }
      end

      # the screen y of the top of the picture
      def draw_body(g)
        sheet = g.sheet
        ch = 64
        @head_top = 22   # no picture: where PIF's player head starts in its 80 px frames
        if sheet
          unless @body.bitmap.equal?(sheet)
            @body.bitmap = sheet
            @tops = {}
          end
          cw = sheet.width / 4
          ch = sheet.height / 4
          row = (g.direction - 2) / 2
          @body.src_rect.set(g.pattern * cw, row * ch, cw, ch)
          @head_top = (@tops[row] ||= Presence.opaque_top(sheet, 0, row * ch, cw, ch))   # the row's first frame: the tag doesn't bob
          @body.ox = cw / 2
          @body.oy = (LOW.include?(g.action) ? ch - 16 : ch) - g.bob_height
        else
          @body.bitmap = nil
        end
        @body.visible = !sheet.nil?
        @body.x = g.screen_x
        @body.y = g.screen_y
        @body.z = g.screen_z(ch)
        @body.opacity = g.opacity
        pbDayNightTint(@body)
        return @body.y - (sheet ? @body.oy : ch)
      end

      def draw_base(g)
        bmp = g.surfing? ? Presence.surf_base(g.surf_shape, g.action) : nil
        unless bmp
          @base.visible = false
          @base.bitmap = nil
          return
        end
        @base.bitmap = bmp unless @base.bitmap.equal?(bmp)
        cw = bmp.width / 4
        ch = bmp.height / 4
        @base.src_rect.set(g.pattern_surf * cw, (g.direction - 2) / 2 * ch, cw, ch)
        @base.ox = cw / 2
        @base.oy = ch - 16 - g.bob_height
        @base.x = @body.x
        @base.y = @body.y
        @base.z = @body.z - 1
        @base.opacity = @body.opacity
        @base.tone = @body.tone
        @base.visible = true
      end

      def draw_tag(g, top)
        if @tag_name != g.tag || @tag_bmp.nil?
          @tag_bmp.dispose if @tag_bmp   # replaced below, before the frame is drawn
          @tag_name = g.tag
          @tag_bmp = Presence.tag_bitmap(*@tag_name)
        end
        @tag.bitmap = @tag_bmp unless @tag.bitmap.equal?(@tag_bmp)
        @tag.ox = Presence.tag_name_width(@tag_bmp) / 2   # the name stays centred over the head
        @tag.oy = @tag_bmp.height
        @tag.x = @body.x
        @tag.y = top + @head_top - 8   # just over the top of what is drawn (a tall hat too)
        @tag.z = TAG_Z
        @tag.opacity = g.opacity
        @tag.visible = true
      end
    end

    #---------------------------------------------------------------------------
    # The game's side: one Link while connected
    #---------------------------------------------------------------------------
    @link = nil
    @retired = []       # sheets to dispose once no sprite shows them
    @retired_old = []
    @surf = {}
    @errors = {}

    class << self
      attr_reader :link
    end

    def self.ghost(key = :partner); @link && @link.ghosts[key]; end

    def self.retire(bitmaps); @retired.concat(bitmaps); end

    # a sheet is disposed a frame after it was let go: by then every sprite
    # that showed it has dropped it
    def self.flush_retired
      @retired_old.each { |b| b.dispose unless b.disposed? }
      @retired_old = @retired
      @retired = []
    end

    def self.oops(e)
      k = "#{e.class}: #{e.message}"[0, 200]
      return if @errors[k]
      @errors[k] = true
      KIF::Net.log("presence: #{k} (#{(e.backtrace || [])[0]})")
    end

    # every frame on the map (after the spritesets); never waits
    def self.frame
      flush_retired unless @retired.empty? && @retired_old.empty?
      s = KIF::Net.session
      unless s && s.connected?
        drop if @link
        return
      end
      @link ||= Link.new
      # the map's own state (talk or idle) never replaces a screen's
      doing(pbMapInterpreterRunning? || $game_temp.message_window_showing ? "talk" : "idle") if [nil, "idle", "talk"].include?(@doing)
      if (st = local_state)
        @link.track(st, local_look, KIF::Net.now).each { |type, f| s.post(type, f) }
      end
      @link.update
      attach_sprites
    rescue StandardError => e
      oops(e)
    end

    def self.receive(type, msg)
      s = KIF::Net.session
      (@link ||= Link.new).receive(type, msg, s ? s.partner : "")
    rescue StandardError => e
      oops(e)
    end

    # what this player is doing (DOING), sent when it changes
    def self.doing(a)
      return if a == (@doing || "idle")   # idle at the start: nothing to send
      s = KIF::Net.session
      return unless s && s.connected?
      @doing = a
      s.post("pr_do", "a" => a)
    rescue StandardError => e
      oops(e)
    end

    # for the name tag and the Multiplayer screen; nil when idle
    def self.doing_label(a)
      case a
      when "talk" then _INTL("talking")
      when "menu" then _INTL("in a menu")
      when "bag" then _INTL("in the Bag")
      when "party" then _INTL("with their Pokémon")
      when "battle" then _INTL("in a battle")
      when "trade" then _INTL("trading")
      when "dex" then _INTL("in the Pokédex")
      when "card" then _INTL("looking at their card")
      when "options" then _INTL("in the settings")
      when "save" then _INTL("saving")
      end
    end

    # the game's own icons, drawn at their size (PIF's art is 2x already)
    ICONS = { "talk" => "Graphics/Pictures/NPCIcons/dialogIcon", "menu" => "Graphics/Icons/menuIcons/POKENAV",
              "bag" => "Graphics/Icons/menuIcons/BAG", "party" => "Graphics/Icons/menuIcons/POKEMON",
              "battle" => "Graphics/Icons/bagPocket7", "trade" => "Graphics/Pictures/NPCIcons/tradeIcon",
              "dex" => "Graphics/Icons/menuIcons/POKEDEX", "card" => "Graphics/Icons/menuIcons/PLAYER",
              "options" => "Graphics/Icons/menuIcons/OPTIONS", "save" => "Graphics/Icons/menuIcons/SAVE" }

    # an icon's picture (kept for the session), or nil
    def self.icon(a)
      @icons ||= {}
      return @icons[a] if @icons[a] && !@icons[a].disposed?
      f = ICONS[a] && pbResolveBitmap(ICONS[a])
      return @icons[a] = f ? Bitmap.new(f) : nil
    rescue StandardError
      return nil
    end

    # the name tag: the name centred in its own part, the icon to its right
    def self.tag_bitmap(name, doing = "idle")
      probe = Bitmap.new(1, 1)
      pbSetSmallFont(probe)
      w = [probe.text_size(name).width + 8, 16].max
      probe.dispose
      ic = icon(doing)
      h = [28, ic ? ic.height : 0].max
      bmp = Bitmap.new(w + (ic ? ic.width + 2 : 0), h)
      pbSetSmallFont(bmp)
      pbDrawShadowText(bmp, 0, h - 28, w, 24, name, Color.new(248, 248, 248), Color.new(48, 48, 48), 1)
      bmp.blt(w + 2, h - ic.height - 2, ic, ic.rect) if ic
      bmp.instance_variable_set(:@kif_name_w, w)
      return bmp
    end

    def self.tag_name_width(bmp); bmp.instance_variable_get(:@kif_name_w) || bmp.width; end

    # a message box on the map: talking, unless a screen is up (its own messages)
    def self.talk; doing("talk") if [nil, "idle", "talk"].include?(@doing); end

    # in a screen until the block ends, then back to what came before
    def self.busy(a)
      prev = @doing || "idle"
      doing(a)
      return yield
    ensure
      doing(prev)
    end

    # a new connection: everything is sent again, the old ghost goes
    def self.on_connect
      drop
      @doing = nil
      @link = Link.new
    end

    def self.on_disconnect; drop; end

    def self.drop
      @link.close if @link
      @link = nil
    end

    def self.local_state
      p = $game_player
      m = $game_map
      return nil unless p && m && m.map_id.to_i > 0
      a = p.instance_variable_get(:@character_name).to_s   # not the getter: it changes PIF's run/walk state
      a = "walk" unless ACTIONS.include?(a)
      d = [2, 4, 6, 8].include?(p.direction) ? p.direction : 2
      return State.new(m.map_id, p.x, p.y, d, a, (p.move_speed.to_f * 10).round.clamp(1, 80),
                       p.transparent ? 1 : 0, p.jumping?)
    end

    def self.local_look
      t = $Trainer or return nil
      shape = (t.surfing_pokemon.shape rescue nil)
      look = {}
      { "skin" => [t.skin_tone || 0, 24], "clothes" => [t.clothes, 40], "hair" => [t.hair, 40],
        "hat" => [t.hat, 40], "hat2" => [t.hat2, 40], "surf" => [shape, 24] }.each do |k, (v, n)|
        look[k] = k.start_with?("hat") && v.to_s == "0" ? "" : v.to_s.gsub(/[\x00-\x1f\x7f]/, "")[0, n]   # a hat of 0: none (PIF's empty slot)
      end
      { "cc" => t.clothes_color, "hc" => t.hair_color, "tc" => t.hat_color, "t2c" => t.hat2_color,
        "bc" => t.bike_color }.each { |k, v| look[k] = v.to_i.clamp(COLOR[1], COLOR[2]) }
      return look
    end

    # every spriteset on screen gets a PartnerSprite per partner (new ones
    # appear after each warp; they go with their spriteset)
    def self.attach_sprites
      return unless $scene.is_a?(Scene_Map) && $scene.spritesets
      keys = @link.ghosts.keys
      return if keys.empty?
      $scene.spritesets.each_value do |ss|
        next unless ss
        list = ss.getAnimations || []
        keys.each do |k|
          next if list.any? { |sp| sp.is_a?(PartnerSprite) && sp.key == k && !sp.disposed? }
          ss.addUserSprite(PartnerSprite.new(Spriteset_Map.viewport, ss.map, k))
        end
      end
    end

    # "Alex is in Route 3." for the Multiplayer screen, or nil
    def self.where_line(name)
      g = ghost or return nil
      return nil unless g.map_id
      d = doing_label(g.doing)
      return _INTL("{1} is on this map ({2}).", name, d) if d && $game_map && g.map_id == $game_map.map_id
      return _INTL("{1} is on this map.", name) if $game_map && g.map_id == $game_map.map_id
      place = (pbGetMessage(MessageTypes::MapNames, g.map_id) rescue nil)
      place = (pbGetBasicMapNameFromId(g.map_id) rescue nil) if nil_or_empty?(place)
      return nil if nil_or_empty?(place)
      place = place.to_s.gsub(/\\PN/, name)   # "\PN's house" is theirs
      return d ? _INTL("{1} is in {2} ({3}).", name, place, d) : _INTL("{1} is in {2}.", name, place)
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e| KIF::Presence.frame }

# What this player is doing, for the partner's name tag (pr_do). The map's own
# frame says talk or idle; the pause menu and battles say so while they last
# (the map doesn't update meanwhile).
class Scene_Map
  alias kif_pr_call_menu call_menu unless method_defined?(:kif_pr_call_menu) || private_method_defined?(:kif_pr_call_menu)

  def call_menu
    KIF::Presence.busy("menu") { kif_pr_call_menu }
  end
end

alias kif_pr_pbBattleAnimation pbBattleAnimation unless defined?(kif_pr_pbBattleAnimation)

def pbBattleAnimation(*args, &blk)
  KIF::Presence.busy("battle") { kif_pr_pbBattleAnimation(*args, &blk) }
end

alias kif_pr_pbMessageDisplay pbMessageDisplay unless defined?(kif_pr_pbMessageDisplay)

def pbMessageDisplay(*args, &blk)
  KIF::Presence.talk if $scene.is_a?(Scene_Map) && !$game_temp.in_menu && !$game_temp.in_battle
  return kif_pr_pbMessageDisplay(*args, &blk)
end

# Screens an event or the pause menu opens (an event's screen opens before
# the map's next frame could see the event running, so each says so itself)
class PokemonBagScreen
  alias kif_pr_pbStartScreen pbStartScreen unless method_defined?(:kif_pr_pbStartScreen) || private_method_defined?(:kif_pr_pbStartScreen)
  alias kif_pr_pbChooseItemScreen pbChooseItemScreen unless method_defined?(:kif_pr_pbChooseItemScreen) || private_method_defined?(:kif_pr_pbChooseItemScreen)

  def pbStartScreen(*args, &blk); KIF::Presence.busy("bag") { kif_pr_pbStartScreen(*args, &blk) }; end
  def pbChooseItemScreen(*args, &blk); KIF::Presence.busy("bag") { kif_pr_pbChooseItemScreen(*args, &blk) }; end
end

# (PokemonPartyScreen#pbPokemonScreen is prepended elsewhere: prepended here too, never aliased)
module KIF
  module Presence
    module PartyBusy
      def pbPokemonScreen(*args, &blk); KIF::Presence.busy("party") { super }; end
    end
  end
end
PokemonPartyScreen.prepend(KIF::Presence::PartyBusy) unless PokemonPartyScreen < KIF::Presence::PartyBusy

# the pause menu's own screens (prepended: KIF replaces or prepends some of them already)
{ "PokemonPokedexMenuScreen" => "dex", "PokemonPokedexScreen" => "dex", "PokemonTrainerCardScreen" => "card",
  "PokemonOptionScreen" => "options", "PokemonSaveScreen" => "save" }.each do |name, st|
  next unless Object.const_defined?(name)
  klass = Object.const_get(name)
  meth = name == "PokemonSaveScreen" ? :pbSaveScreen : :pbStartScreen
  m = Module.new { define_method(meth) { |*args, &blk| KIF::Presence.busy(st) { super(*args, &blk) } } }
  klass.prepend(m) unless klass.instance_variable_get(:@kif_pr_busy)
  klass.instance_variable_set(:@kif_pr_busy, true)
end

class PokemonStorageScreen
  alias kif_pr_pbStartScreen pbStartScreen unless method_defined?(:kif_pr_pbStartScreen) || private_method_defined?(:kif_pr_pbStartScreen)

  def pbStartScreen(*args, &blk); KIF::Presence.busy("party") { kif_pr_pbStartScreen(*args, &blk) }; end
end

# a gym's team pick and other "choose your team" screens
module PokemonSelection
  class << self
    alias kif_pr_choose choose unless method_defined?(:kif_pr_choose) || private_method_defined?(:kif_pr_choose)

    def choose(*args, &blk); KIF::Presence.busy("party") { kif_pr_choose(*args, &blk) }; end
  end
end

# an event's "choose a Pokémon" (a gift, a tutor, a trade partner)
alias kif_pr_pbChoosePokemon pbChoosePokemon unless defined?(kif_pr_pbChoosePokemon)

def pbChoosePokemon(*args, &blk)
  KIF::Presence.busy("party") { kif_pr_pbChoosePokemon(*args, &blk) }
end

alias kif_pr_pbStartTrade pbStartTrade unless defined?(kif_pr_pbStartTrade)

def pbStartTrade(*args, &blk)
  KIF::Presence.busy("trade") { kif_pr_pbStartTrade(*args, &blk) }
end

alias kif_pr_pbPokemonMart pbPokemonMart unless defined?(kif_pr_pbPokemonMart)

def pbPokemonMart(*args, &blk)
  KIF::Presence.busy("menu") { kif_pr_pbPokemonMart(*args, &blk) }
end
