#===============================================================================
# F-UI-12 – Living title screen (new in KIF 1.0, 2026-10-22; KIF 0.20.7 had
# none: it kept PIF's galaxy title)
#
# The title screen shows a world that scrolls slowly sideways: a grassy field
# (Route 1), a beach (Treasure Beach) and a forest (Viridian Forest), drawn
# from the game's own maps into Graphics/Titles/KIF/pano_N.png by
# Claude Docs/_Tools/map_mockup/titlestrips.py (with pano_walk.png: where the
# Pokémon may walk or swim). Follower sprites wander with their 4-frame walk
# cycle, Diglett dig in and out of the sand, flyers cross the sky, and every
# so often two Pokémon walk in and fuse: a flash, then the head walks on in
# the body's colour with the fusion's battle sprite above it (when a custom
# sprite for it is on this computer).
# Menu: Play (the save selection screen, unchanged), Options, Mods, Links,
# Quit.
#
# Setting: Options > System > Start-up > Title screen:
#   Living (default), Simple (one still picture, no animation; the default
#   on phones), Classic (PIF's title).
# PIF's title stays for Hoenn builds, NoIntro.krs (F-UI-09: straight to the
# save selection) and when the pictures are missing.
#
# Hooks: Scene_Intro#main (F-UI-09's NoIntro skip and SCOPE-02's radar clean-
# up wrap it too). Movement uses Graphics.delta (real time per frame), so it
# keeps its speed at any frame rate.
#===============================================================================
KIF::Options.define(:kif_title_screen, -1, :global)   # -1: not chosen yet (Simple on phones, else Living)

KIF::Options.add(:graphics, :global) {   # placed under System > Start-up (015_KIF_SettingsData)
  EnumOption.new(_INTL("Title screen"), [_INTL("Living"), _INTL("Simple"), _INTL("Classic")],
                 proc { KIF::LivingTitle.style },
                 proc { |value| $PokemonSystem.kif_title_screen = value },
                 [_INTL("Pokémon wander through a scrolling world behind the title menu."),
                  _INTL("A still picture behind the title menu. Lighter for phones and slow computers."),
                  _INTL("PIF's own title screen: press any key to go to the save selection.")])
}

module KIF
  module LivingTitle
    LIVING, SIMPLE, CLASSIC = 0, 1, 2
    DIR = "Graphics/Titles/KIF/"

    def self.style
      v = ($PokemonSystem.kif_title_screen rescue -1).to_i
      return v if v.between?(LIVING, CLASSIC)
      return KIF.mobile? ? SIMPLE : LIVING
    end

    # the title KIF draws itself (not Hoenn, not "go straight to the saves")
    def self.wanted?
      return false unless Settings::KANTO
      return false if KIF::Links.no_intro?
      return style != CLASSIC && !pbResolveBitmap(DIR + "pano_0").nil?
    end

    # the links the title's Links menu lists (the load screen's own kif: entries stay there)
    def self.links
      return [] unless defined?(Settings::MAIN_MENU_LINKS) && Settings::MAIN_MENU_LINKS.is_a?(Hash)
      return Settings::MAIN_MENU_LINKS.select { |_k, url| url.to_s.start_with?("http") }.to_a
    end
  end
end

#===============================================================================
# The scene
#===============================================================================
class KifLivingTitle
  DIR      = KIF::LivingTitle::DIR
  CHUNK    = 768            # px per strip (titlestrips.py)
  TILE     = 32
  # from titlestrips.py: biome by x in the loop
  BIOMES   = [[0, :grass], [704, :beach], [1440, :forest]]
  SPECIES  = {
    :grass  => { :walk => %w[BULBASAUR CHARMANDER SQUIRTLE EEVEE PIKACHU RATTATA ODDISH PIDGEY],
                 :fly  => %w[PIDGEOT SPEAROW PIDGEY] },
    :beach  => { :walk => %w[SANDSHREW TRAPINCH KRABBY SLOWPOKE], :swim => %w[TENTACOOL PSYDUCK STARYU],
                 :dig  => %w[DIGLETT], :fly => %w[WINGULL PELIPPER] },
    :forest => { :walk => %w[CATERPIE WEEDLE PIKACHU SCYTHER ODDISH PARAS], :fly => %w[HOOTHOOT] }
  }
  SCROLL   = 40.0           # px per second (1 px per game step at 40)
  WALK     = 48.0           # px per second
  WALKERS  = 8
  FLYERS   = 2
  DIGGERS  = 2               # (+2 walkers kept for fusions)
  MENU_X0  = 136            # screen columns the logo and menu cover
  MENU_X1  = 376
  BUDGET   = 40             # sprites at most (checked by the kit)
  MENU     = [[:play, "Play"], [:options, "Options"], [:mods, "Mods"], [:links, "Links"], [:quit, "Quit"]]
  WHITE    = Color.new(248, 248, 248)
  SHADOW   = Color.new(64, 64, 72)
  YELLOW   = Color.new(248, 216, 88)
  DIRROW   = { :down => 0, :left => 1, :right => 2, :up => 3 }

  attr_reader :sprites, :bitmaps, :choice, :index, :menu, :cam, :stats, :actors, :simple, :fusion

  def initialize(simple = false)
    @simple = simple
    @disposed = false
    @bitmaps = {}           # path or name => Bitmap (all disposed with the scene)
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99998
    @chunks = 0
    @chunks += 1 while pbResolveBitmap(DIR + "pano_#{@chunks}")
    raise "no title pictures in #{DIR}" if @chunks == 0
    @loop = @chunks * CHUNK
    @walk = load_bitmap(DIR + "pano_walk")
    @cam = simple ? 0.0 : rand(@chunks) * CHUNK.to_f
    @time = 0.0
    @fade = 1.0
    @stats = { :frames => 0, :time => 0.0, :max => 0.0, :sprites => 0, :fusions => 0, :no_sprite => 0 }
    @menu = :main
    @index = 0
    @choice = nil
    2.times { |i| @sprites["bg#{i}"] = Sprite.new(@viewport) }
    @bg_loaded = {}
    setup_actors unless simple
    setup_ui
    update_background
    update_actors(0.0) unless simple
    @stats[:sprites] = sprite_count
    @viewport.color = Color.new(0, 0, 0, 255)
    pbBGMPlay(Settings::KANTO ? "Pokemon Red-Blue Opening" : "title_screen")
  end

  # Scene_Intro calls this before its loop (PIF's title shows its intro here)
  def intro; end

  def disposed?; @disposed; end

  def sprite_count
    return @sprites.values.count { |s| s && !s.disposed? }
  end

  #-----------------------------------------------------------------------------
  # Bitmaps: one per file, shared, disposed with the scene
  #-----------------------------------------------------------------------------
  def load_bitmap(path)
    return @bitmaps[path] if @bitmaps.has_key?(path)
    file = pbResolveBitmap(path)
    return @bitmaps[path] = KIF::UnreadableSprites.read(file)   # a broken sprite file is skipped
  end

  def follower(species)
    return load_bitmap("Graphics/Characters/Followers/#{species}")
  end

  def drawn(name, w, h)
    return @bitmaps[name] ||= begin
      b = Bitmap.new(w, h)
      yield b
      b
    end
  end

  # a filled ellipse, rows of rects (the engine has no ellipse drawing)
  def ellipse(b, cx, cy, rx, ry, color)
    (-ry..ry).each do |dy|
      half = (rx * Math.sqrt([1.0 - (dy.to_f / ry)**2, 0].max)).round
      b.fill_rect(cx - half, cy + dy, half * 2, 1, color) if half > 0
    end
  end

  def shadow_bitmap
    drawn(:shadow, 32, 12) { |b| ellipse(b, 16, 6, 14, 5, Color.new(0, 0, 0, 70)) }
  end

  def hole_bitmap
    drawn(:hole, 36, 16) do |b|
      ellipse(b, 18, 8, 17, 7, Color.new(176, 140, 88))
      ellipse(b, 18, 8, 12, 4, Color.new(112, 84, 52))
      [[3, 2], [30, 3], [8, 13], [27, 12]].each { |x, y| b.fill_rect(x, y, 3, 3, Color.new(150, 112, 70)) }
    end
  end

  def ripple_bitmap
    drawn(:ripple, 48, 14) do |b|
      ellipse(b, 24, 7, 22, 6, Color.new(220, 240, 255, 170))
      ellipse(b, 24, 7, 18, 4, Color.new(0, 0, 0, 0))
    end
  end

  def flash_bitmap
    drawn(:flash, 96, 96) do |b|
      12.downto(1) { |k| ellipse(b, 48, 48, k * 4, k * 4, Color.new(255, 255, 235, [255, 330 - k * 26].min)) }
    end
  end

  def sparkle_bitmap
    drawn(:sparkle, 112, 112) do |b|
      5.times do |i|
        a = i * Math::PI * 2 / 5
        x = 56 + (42 * Math.cos(a)).round
        y = 56 + (42 * Math.sin(a)).round
        c = Color.new(255, 248, 200)
        b.fill_rect(x - 1, y - 6, 3, 13, c)
        b.fill_rect(x - 6, y - 1, 13, 3, c)
        b.fill_rect(x - 2, y - 2, 5, 5, c)
      end
    end
  end

  #-----------------------------------------------------------------------------
  # World: tiles and biomes
  #-----------------------------------------------------------------------------
  def wrap(x); x % @loop; end

  # 0.0...1.0 (PIF's Kernel#rand without arguments gives 0 or 1)
  def frand; Random.rand; end

  def biome_at(x)
    x = wrap(x)
    ret = BIOMES[0][1]
    BIOMES.each { |start, b| ret = b if x >= start }
    return ret
  end

  # :walk, :water or :block at a point of the world
  def tile_kind(x, y)
    return :block if y < 8 || y > 384 - 4
    return :walk unless @walk
    c = @walk.get_pixel((wrap(x) / TILE).floor, (y / TILE).floor)
    return :walk if c.alpha < 128
    return :grass if c.green > 128
    return c.blue > 128 ? :water : :block
  end

  def ground?(x, y)
    k = tile_kind(x, y)
    return k == :walk || k == :grass
  end

  # the lowest row with a pixel in ANY frame of a follower sheet (its feet);
  # flyers flap lower in later frames, and the first frame alone cut them off
  def feet(bmp)
    @feet ||= {}
    return @feet[bmp.object_id] ||= begin
      fw = bmp.width / 4; fh = bmp.height / 4
      row = (fh - 1).downto(0).find do |y|
        (0...4).any? { |r| (0...bmp.width).step(2).any? { |x| bmp.get_pixel(x, r * fh + y).alpha > 0 } }
      end
      row ? row + 1 : fh - 8
    end
  end

  def species_for(biome, kind)
    @species_ok ||= {}
    list = (SPECIES[biome] || {})[kind] || []
    list = list.select { |sp| @species_ok.has_key?(sp) ? @species_ok[sp] : (@species_ok[sp] = !pbResolveBitmap("Graphics/Characters/Followers/#{sp}").nil?) }
    return list.sample
  end

  #-----------------------------------------------------------------------------
  # Actors
  #-----------------------------------------------------------------------------
  Actor = Struct.new(:kind, :species, :x, :y, :dir, :state, :timer, :dist, :anim, :sprite, :shadow,
                     :tx, :ty, :speed, :height, :phase, :tint)

  def setup_actors
    @actors = []
    WALKERS.times do |i|
      @actors << new_actor(:walk, "w#{i}")
      spawn(@actors.last, @cam - 32, @cam + Graphics.width + 32)
    end
    DIGGERS.times do |i|
      @actors << new_actor(:dig, "d#{i}")
      spawn(@actors.last, @cam + Graphics.width, @cam + Graphics.width * 2)
    end
    2.times do |i|                 # the two that walk in to fuse (off screen until then)
      @actors << new_actor(:pair, "p#{i}")
    end
    FLYERS.times do |i|
      @actors << new_actor(:fly, "f#{i}")
      @actors.last.state = :off
      @actors.last.timer = 2.0 + i * 4 + frand * 3
    end
    @fusion = nil
    @fuse_wait = 2.5   # early: a player may not stay long (Cody, 2026-10-22)
    @sprites["flash"] = Sprite.new(@viewport)
    @sprites["flash"].bitmap = flash_bitmap
    @sprites["flash"].ox = @sprites["flash"].oy = 48
    @sprites["flash"].visible = false
    @sprites["flash"].z = 700
    @sprites["fused"] = Sprite.new(@viewport)     # the fusion's battle sprite, small, above the fused walker
    @sprites["fused"].visible = false
    @sprites["fused"].z = 650
    @sprites["sparkle"] = Sprite.new(@viewport)
    @sprites["sparkle"].bitmap = sparkle_bitmap
    @sprites["sparkle"].ox = @sprites["sparkle"].oy = 56
    @sprites["sparkle"].visible = false
    @sprites["sparkle"].z = 701
  end

  def new_actor(kind, key)
    a = Actor.new(kind, nil, 0.0, 0.0, :down, :off, 0.0, 0.0, 0.0)
    a.sprite = @sprites[key] = Sprite.new(@viewport)
    a.shadow = @sprites[key + "s"] = Sprite.new(@viewport)
    a.sprite.visible = a.shadow.visible = false
    return a
  end

  # put a walker/digger on free ground (or water) between x0 and x1
  def spawn(a, x0, x1)
    12.times do
      x = x0 + frand * (x1 - x0)
      y = (1 + rand(11)) * TILE + TILE - 6
      biome = biome_at(x)
      kind = tile_kind(x, y)
      want = case a.kind
             when :dig then (kind == :walk && (SPECIES[biome] || {})[:dig]) ? :dig : nil
             else kind == :water ? :swim : ((kind == :walk || kind == :grass) ? :walk : nil)
             end
      next unless want
      sp = species_for(biome, want)
      next unless sp
      a.x = (x / TILE).floor * TILE + TILE / 2
      a.y = y
      dress(a, sp, want)
      a.state = a.kind == :dig ? :under : :idle
      return true
    end
    a.state = :off
    a.timer = 1.0
    return false
  end

  def dress(a, sp, want)
    a.species = sp
    a.timer = frand * 1.5
    a.dir = DIRROW.keys.sample
    a.anim = frand * 4
    a.speed = want == :swim ? WALK * 0.6 : WALK
    a.height = want == :swim ? 1 : 0     # swimmers: lower half under water
    a.phase = 0.0
    a.sprite.bitmap = follower(sp)
    a.tint = nil
    a.sprite.color = Color.new(0, 0, 0, 0)
    a.shadow.bitmap = a.height == 1 ? ripple_bitmap : (a.kind == :dig ? hole_bitmap : shadow_bitmap)
    a.shadow.ox = a.shadow.bitmap.width / 2
    a.shadow.oy = a.shadow.bitmap.height / 2
  end

  def frame_size(a)
    b = a.sprite.bitmap
    return [b.width / 4, b.height / 4]
  end

  def update_walker(a, dt)
    case a.state
    when :off
      a.timer -= dt
      spawn(a, @cam + Graphics.width + 16, @cam + Graphics.width + 240) if a.timer <= 0 && a.kind == :walk
      return
    when :gone
      return
    when :idle
      a.anim += dt * 4
      a.timer -= dt
      if a.timer <= 0
        a.dir = DIRROW.keys.sample
        a.dist = TILE * (1 + rand(3))
        a.state = :walk
      end
    when :walk, :meet
      a.anim += dt * 7
      step = [a.speed * dt, a.state == :meet ? 1e9 : a.dist].min
      if a.state == :meet
        dx = a.tx - a.x; dy = a.ty - a.y
        if dx.abs < 1 && dy.abs < 1
          a.x, a.y = a.tx, a.ty
          a.state = :met
        else
          if dx.abs >= 1 then a.dir = dx > 0 ? :right : :left; a.x += [[dx, step].min, -step].max
          else a.dir = dy > 0 ? :down : :up; a.y += [[dy, step].min, -step].max
          end
        end
      else
        nx = a.x + { :left => -1, :right => 1 }.fetch(a.dir, 0) * (step + 12)
        ny = a.y + { :up => -1, :down => 1 }.fetch(a.dir, 0) * (step + 8)
        want = a.height == 1 ? :water : :walk
        if (want == :walk ? !ground?(nx, ny) : tile_kind(nx, ny) != want)
          a.state = :idle; a.timer = 0.3 + frand
        else
          a.x += { :left => -1, :right => 1 }.fetch(a.dir, 0) * step
          a.y += { :up => -1, :down => 1 }.fetch(a.dir, 0) * step
          a.dist -= step
          if a.dist <= 0
            a.state = :idle; a.timer = 0.5 + frand * 2.5
          end
        end
      end
    when :met
      a.anim += dt * 3
    end
    # scrolled off to the left: comes back later ahead of the camera
    if a.x - @cam < -48 && a.state != :meet && a.state != :met
      a.state = :off; a.timer = 0.5 + frand * 3
    end
  end

  def update_digger(a, dt)
    a.timer -= dt
    if a.state == :off
      spawn(a, @cam + Graphics.width + 16, @cam + Graphics.width + 300) if a.timer <= 0
      return
    end
    if a.timer <= 0
      a.state, a.timer = { :under => [:rise, 0.5], :rise => [:up, 1.2 + frand * 1.5],
                           :up => [:sink, 0.5], :sink => [:under, 1.0 + frand * 2.0] }[a.state]
    end
    a.anim += dt * 6
    a.state = :off if a.x - @cam < -48 && a.state == :under
  end

  def update_flyer(a, dt)
    if a.state == :off
      a.timer -= dt
      return if a.timer > 0
      sp = species_for(biome_at(@cam + Graphics.width / 2), :fly)
      return (a.timer = 2.0) unless sp
      a.species = sp
      a.sprite.bitmap = (pbResolveBitmap("Graphics/Characters/Followers/#{sp}_fly") ? follower("#{sp}_fly") : follower(sp))
      a.shadow.bitmap = shadow_bitmap
      a.shadow.ox = 16; a.shadow.oy = 6
      a.dir = rand(2) == 0 ? :left : :right
      a.x = a.dir == :left ? Graphics.width + 48.0 : -48.0      # screen space
      a.y = 150.0 + rand(200)                                    # ground under it
      a.height = 60 + rand(70)
      a.speed = 70.0 + rand(50)
      a.phase = frand * 6
      a.state = :fly
    end
    a.anim += dt * 8
    a.phase += dt
    a.x += (a.dir == :left ? -1 : 1) * a.speed * dt
    if a.x < -64 || a.x > Graphics.width + 64
      a.state = :off; a.timer = 3.0 + frand * 7
    end
  end

  def update_actors(dt)
    @actors.each do |a|
      case a.kind
      when :walk, :pair then update_walker(a, dt)
      when :dig  then update_digger(a, dt)
      when :fly  then update_flyer(a, dt)
      end
      draw_actor(a)
    end
    update_fusion(dt)
  end

  def draw_actor(a)
    s, sh = a.sprite, a.shadow
    on = ![:off, :gone].include?(a.state) && s.bitmap
    s.visible = sh.visible = on ? true : false
    return unless on
    fw, fh = frame_size(a)
    foot = feet(s.bitmap)        # feet stand on the ground line, whatever the sheet's margin
    frame = a.anim.floor % 4
    row = DIRROW[a.dir] || 0
    s.bush_depth = 0
    if a.kind == :fly
      bob = (Math.sin(a.phase * 3) * 4).round
      s.src_rect.set(frame * fw, row * fh, fw, foot)
      s.ox = fw / 2; s.oy = foot
      s.x = a.x.round; s.y = (a.y - a.height + bob).round
      s.z = 600
      sh.x = a.x.round; sh.y = a.y.round; sh.z = 3
      return
    end
    sx = (a.x - @cam).round
    if a.kind == :dig
      body = [foot - 20, 8].max
      p = { :under => 0.0, :rise => 1.0 - a.timer / 0.5, :up => 1.0, :sink => a.timer / 0.5 }[a.state] || 0.0
      show = (body * p.clamp(0.0, 1.0)).round
      s.visible = show > 0
      s.src_rect.set(frame * fw, foot - body, fw, [show, 1].max)
      s.ox = fw / 2; s.oy = 0
      s.x = sx; s.y = a.y.round - show
      s.z = 10 + a.y.round
      sh.x = sx; sh.y = a.y.round - 2; sh.z = 2
      return
    end
    cut = a.height == 1 ? 14 : 0    # swimmers: the part under water isn't drawn
    s.src_rect.set(frame * fw, row * fh, fw, foot - cut)
    s.ox = fw / 2; s.oy = foot - cut
    s.x = sx; s.y = a.y.round
    s.z = 10 + a.y.round
    s.bush_depth = 10 if a.height == 0 && tile_kind(a.x, a.y - 4) == :grass   # in tall grass, like the overworld
    sh.visible = false if s.bush_depth > 0
    sh.x = sx; sh.y = a.y.round - 1; sh.z = 1
  end

  #-----------------------------------------------------------------------------
  # Fusion: two walkers meet, a flash, then the fusion's battle sprite
  #-----------------------------------------------------------------------------
  def fusion_bitmap(head, body)
    h = (GameData::Species.get(head.to_sym).id_number rescue nil)
    b = (GameData::Species.get(body.to_sym).id_number rescue nil)
    return nil unless h && b
    # Only a custom sprite already on this computer: PIF's sprite loader may
    # decode a whole sprite sheet (3.7 s measured) or download, freezing the title.
    # shortcut: no fusion without a local custom sprite; preload a sheet during the fade-in if autogens are wanted
    file = pbResolveBitmap("#{Settings::CUSTOM_BATTLERS_FOLDER_INDEXED}#{h}/#{h}.#{b}")
    @stats[:no_sprite] += 1 unless file
    return KIF::UnreadableSprites.read(file)   # a broken sprite file is skipped
  rescue StandardError => e
    KIF.log("Living title: no fusion sprite for #{head}/#{body} (#{e.class}: #{e.message})")
    return nil
  end

  # body colours (PIF's Pokédex colour) for the fused walker's tint
  TINTS = { :Red => [232, 72, 64], :Blue => [64, 112, 232], :Yellow => [240, 208, 64], :Green => [72, 184, 88],
            :Black => [40, 40, 56], :Brown => [160, 104, 56], :Purple => [152, 80, 200], :Gray => [144, 144, 160],
            :White => [248, 248, 248], :Pink => [240, 136, 192] }

  def tint_for(body)
    rgb = TINTS[(GameData::Species.get(body.to_sym).color rescue nil)] || TINTS[:Gray]
    return Color.new(rgb[0], rgb[1], rgb[2], 96)
  end

  # The two fusion walkers come in from the right and meet at a spot
  # right of the menu. The spot keeps its place on screen (the world scrolls
  # under it) until they have fused, so it happens in view.
  def pick_fusion_pair
    free = @actors.select { |w| w.kind == :pair && w.state == :off }
    return nil if free.length < 2
    8.times do
      sx = MENU_X1 + 28 + rand(64)
      y = ((2 + rand(9)) * TILE + TILE - 6).to_f
      # the row they walk in on is open ground (no trees, ledges or water)
      next unless (sx - 20..Graphics.width + 120).step(16).all? { |x| ground?(@cam + x, y) }
      head, body = (SPECIES[biome_at(@cam + sx)] || {})[:walk].to_a.shuffle.first(2)
      next unless body && pbResolveBitmap("Graphics/Characters/Followers/#{head}") && pbResolveBitmap("Graphics/Characters/Followers/#{body}")
      a, b = free.first(2)
      [[a, head], [b, body]].each_with_index do |(w, sp), i|
        dress(w, sp, :walk)
        w.x = @cam + Graphics.width + 24 + i * 56
        w.y = y
        w.speed = WALK * 1.4
      end
      return [a, b, sx, y, fusion_bitmap(head, body)]
    end
    return nil
  end

  # walk in -> face each other -> flash -> the head walks on in the body's
  # colour, the fusion's battle sprite above it for a few seconds
  def update_fusion(dt)
    f = @fusion
    unless f
      @fuse_wait -= dt
      return if @fuse_wait > 0
      @fuse_wait = 3.0   # retry soon when no pair is free
      pair = pick_fusion_pair
      return unless pair
      a, b, sx, my, bmp = pair
      @bitmaps[:fused].dispose if @bitmaps[:fused] && !@bitmaps[:fused].disposed?
      @bitmaps[:fused] = bmp
      a.state = b.state = :meet
      a.ty = b.ty = my
      a.speed = b.speed = WALK * 1.8   # they hurry to meet (back to WALK after the flash)
      @fusion = f = { :a => a, :b => b, :sx => sx, :x => @cam + sx, :y => my, :phase => :walk, :t => 0.0 }
    end
    f[:t] += dt
    a, b = f[:a], f[:b]
    if [:walk, :face, :flash].include?(f[:phase])
      f[:x] = @cam + f[:sx]          # the meeting spot keeps its place on screen
      a.tx = f[:x] - 14
      b.tx = f[:x] + 14
      [a, b].each { |w| w.x = w.tx if w.state == :met }
    end
    case f[:phase]
    when :walk
      if (a.state == :met && b.state == :met) || f[:t] > 8.0
        [a, b].each { |w| w.state = :met; w.x, w.y = w.tx, w.ty }
        a.dir = :right
        b.dir = :left
        f[:phase] = :face; f[:t] = 0.0
      end
    when :face
      if f[:t] > 0.4
        f[:phase] = :flash; f[:t] = 0.0
      end
    when :flash
      a.state = b.state = :gone if f[:t] > 0.25
      if f[:t] > 0.6
        b.state = :off; b.timer = 2.0 + frand * 4
        a.x = f[:x]; a.state = :idle; a.timer = 1.0; a.dir = :down; a.speed = WALK
        a.tint = tint_for(b.species)
        a.sprite.color = a.tint
        @stats[:fusions] += 1
        show_fused
        f[:phase] = :fused; f[:t] = 0.0
      end
    when :fused
      if f[:t] > 4.5 || a.state == :off
        @sprites["fused"].visible = false
        @sprites["fused"].bitmap = nil
        @bitmaps.delete(:fused).dispose if @bitmaps[:fused]
        @fusion = nil
        @fuse_wait = 7.0 + frand * 5
        @sprites["sparkle"].visible = @sprites["flash"].visible = false
        return
      end
    end
    draw_fusion(f)
  end

  def show_fused
    s = @sprites["fused"]
    s.bitmap = @bitmaps[:fused]
    return unless s.bitmap
    z = 48.0 / [s.bitmap.width, 1].max
    s.zoom_x = s.zoom_y = z
    s.ox = s.bitmap.width / 2
    s.oy = s.bitmap.height
    s.visible = true
  end

  def draw_fusion(f)
    a = f[:a]
    sx = ((f[:phase] == :fused ? a.x : f[:x]) - @cam).round
    fl = @sprites["flash"]
    sp = @sprites["sparkle"]
    fl.visible = f[:phase] == :flash
    if fl.visible
      p = f[:t] / 0.6
      fl.x = sx; fl.y = f[:y] - 20
      fl.zoom_x = fl.zoom_y = 0.4 + p * 1.2
      fl.opacity = (255 * (1.0 - (p - 0.5).abs * 1.4)).clamp(0, 255)
    end
    sp.visible = (f[:phase] == :flash) || (f[:phase] == :fused && f[:t] < 1.6)
    if sp.visible
      sp.x = sx; sp.y = (f[:phase] == :fused ? a.y : f[:y]) - 24
      sp.angle = (@time * 120) % 360
      sp.opacity = f[:phase] == :fused ? (255 * (1.0 - f[:t] / 1.6)).clamp(0, 255) : 255
    end
    fz = @sprites["fused"]
    return unless fz.visible
    hop = (Math.sin(f[:t] * 6).abs * 3).round
    fz.x = sx; fz.y = a.y.round - feet(a.sprite.bitmap) + 6 - hop
    fz.opacity = (255 * [1.0, (4.5 - f[:t]) / 0.5].min).clamp(0, 255)
  end

  #-----------------------------------------------------------------------------
  # Background strips: only the two on screen are loaded
  #-----------------------------------------------------------------------------
  def update_background
    k = (@cam / CHUNK).floor
    want = [k % @chunks, (k + 1) % @chunks]
    @bg_loaded.keys.each do |i|
      next if want.include?(i)
      @sprites["bg0"].bitmap = nil if @sprites["bg0"].bitmap.equal?(@bg_loaded[i])
      @sprites["bg1"].bitmap = nil if @sprites["bg1"].bitmap.equal?(@bg_loaded[i])
      @bitmaps.delete(DIR + "pano_#{i}")
      @bg_loaded.delete(i).dispose
    end
    2.times do |n|
      i = want[n]
      @bg_loaded[i] ||= load_bitmap(DIR + "pano_#{i}")
      s = @sprites["bg#{n}"]
      s.bitmap = @bg_loaded[i] unless s.bitmap.equal?(@bg_loaded[i])
      s.x = ((k + n) * CHUNK - @cam).round
      s.z = 0
    end
  end

  #-----------------------------------------------------------------------------
  # Logo and menu
  #-----------------------------------------------------------------------------
  def setup_ui
    %w[PokemonInfiniteFusionLogo_Back_25 PokemonInfiniteFusionLogo_Main_25].each_with_index do |f, i|
      s = @sprites["logo#{i}"] = Sprite.new(@viewport)
      s.bitmap = load_bitmap("Graphics/Titles/#{f}")
      s.zoom_x = s.zoom_y = 0.78
      s.x = (Graphics.width - (s.bitmap ? s.bitmap.width * 0.78 : 0)) / 2
      s.y = 2
      s.z = 800 + i
    end
    @sprites["menu"] = Sprite.new(@viewport)
    @sprites["menu"].bitmap = @bitmaps[:menu] = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["menu"].z = 900
    draw_menu
  end

  def entries
    return MENU.map { |id, label| [id, _INTL(label)] } if @menu == :main
    return KIF::LivingTitle.links.map { |label, url| [url, _INTL(label)] } + [[:back, _INTL("Back")]]
  end

  # a frame from a PIF window skin, its middle 16x16 stretched (like the game's frames)
  def draw_frame(b, skin, x, y, w, h)
    f = load_bitmap("Graphics/Windowskins/#{skin}")
    return b.fill_rect(x, y, w, h, Color.new(72, 72, 80)) unless f
    l = (f.width - 16) / 2; t = (f.height - 16) / 2
    r = f.width - l - 16; bt = f.height - t - 16
    xs = [[0, l, l], [l, 16, w - l - r], [l + 16, r, r]]
    ys = [[0, t, t], [t, 16, h - t - bt], [t + 16, bt, bt]]
    oy = y
    ys.each do |sy, sh, dh|
      ox = x
      xs.each do |sx, sw, dw|
        b.stretch_blt(Rect.new(ox, oy, dw, dh), f, Rect.new(sx, sy, sw, sh)) if dw > 0 && dh > 0
        ox += dw
      end
      oy += dh
    end
  end

  def draw_menu
    b = @bitmaps[:menu]
    b.clear
    pbSetSystemFont(b)
    list = entries
    w = [176, list.map { |_id, s| b.text_size(s).width + 40 }.max].max
    step = [36, 196 / list.length].min
    y0 = 166
    @rects = []
    list.each_with_index do |(_id, label), i|
      x = (Graphics.width - w) / 2
      y = y0 + i * step
      draw_frame(b, "default_opaque", x, y, w, step - 2)
      if i == @index
        c = YELLOW
        b.fill_rect(x + 2, y + 2, w - 4, 2, c); b.fill_rect(x + 2, y + step - 6, w - 4, 2, c)
        b.fill_rect(x + 2, y + 2, 2, step - 6, c); b.fill_rect(x + w - 4, y + 2, 2, step - 6, c)
      end
      pbDrawTextPositions(b, [[label, Graphics.width / 2, y + (step - 2) / 2 - 18, 2, i == @index ? YELLOW : WHITE, SHADOW]])
      @rects << Rect.new(x, y, w, step - 2)
    end
    foot = [["KIF #{KIF::PORT_VERSION rescue '?'}", 8, Graphics.height - 32, 0, WHITE, Color.new(24, 24, 32)]]
    foot << [_INTL("F1: controls"), Graphics.width - 8, Graphics.height - 32, 1, WHITE, Color.new(24, 24, 32)] unless KIF.mobile?
    pbDrawTextPositions(b, foot)
  end

  def select(i)
    n = entries.length
    i %= n
    return if i == @index
    @index = i
    draw_menu
  end

  def open_links
    @menu = :links; @index = 0; draw_menu
  end

  def close_links
    @menu = :main; @index = MENU.index { |id, _| id == :links } || 0; draw_menu
  end

  # what the menu entry at @index does: :play, :options, :mods, :quit, or a link's URL
  def activate
    id = entries[@index][0]
    case id
    when :links then pbPlayDecisionSE; open_links; return nil
    when :back  then pbPlayCancelSE; close_links; return nil
    end
    return id
  end

  def update_input
    @choice = nil
    if Input.repeat?(Input::UP)
      pbPlayCursorSE; select(@index - 1)
    elsif Input.repeat?(Input::DOWN)
      pbPlayCursorSE; select(@index + 1)
    elsif Input.trigger?(Input::USE)
      @choice = activate
    elsif Input.trigger?(Input::BACK) && @menu == :links
      pbPlayCancelSE; close_links
    end
  end

  #-----------------------------------------------------------------------------
  # One frame
  #-----------------------------------------------------------------------------
  def frame_seconds
    d = (Graphics.delta_s rescue 0.0).to_f
    d = 1.0 / 40 if d <= 0 || d.nan?
    return [d, 0.1].min    # a long hitch (loading) doesn't jump the world ahead
  end

  def update(dt = nil)
    return if @disposed
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dt ||= frame_seconds
    @time += dt
    if @fade > 0
      @fade = [@fade - dt * 2.5, 0].max
      @viewport.color = Color.new(0, 0, 0, (255 * @fade).round)
    end
    unless @simple
      @cam += SCROLL * dt
      update_background
      update_actors(dt)
    end
    update_input
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    @stats[:frames] += 1
    @stats[:time] += took
    @stats[:max] = took if took > @stats[:max]
    n = sprite_count
    @stats[:sprites] = n if n > @stats[:sprites]
  end

  # hides the title while another screen is open (Options, Mods)
  def visible=(v)
    @viewport.visible = v
  end

  def dispose
    return if @disposed
    if @stats[:frames] > 0
      KIF.log(format("Living title: %d frames, update %.2f ms on average (slowest %.2f ms), up to %d sprites, %d fusions (%d without a sprite here)",
                     @stats[:frames], @stats[:time] * 1000 / @stats[:frames], @stats[:max] * 1000, @stats[:sprites], @stats[:fusions], @stats[:no_sprite]))
    end
    8.times do |i|
      @viewport.color = Color.new(0, 0, 0, 32 * (i + 1))
      Graphics.update
    end
    pbDisposeSpriteHash(@sprites)
    @bitmaps.each_value { |b| b.dispose if b && !b.disposed? }
    @bitmaps.clear
    @bg_loaded.clear
    @viewport.dispose
    @disposed = true
  end
end

#===============================================================================
# Scene_Intro: KIF's title in place of PIF's GenOneStyle
#===============================================================================
class Scene_Intro
  alias kif_lt_main main unless method_defined?(:kif_lt_main)

  def main
    return kif_lt_main unless KIF::LivingTitle.wanted?
    Graphics.transition(0)
    playIntroCinematic
    updateCreditsFile if defined?(updateCreditsFile) && !File.exist?(Settings::CREDITS_FILE_PATH)
    begin
      @screen = KifLivingTitle.new(KIF::LivingTitle.style == KIF::LivingTitle::SIMPLE)
    rescue StandardError => e
      KIF.log("Living title failed, PIF's title instead (#{e.class}: #{e.message})")
      @screen.dispose if @screen.respond_to?(:dispose) && !@screen.disposed? rescue nil
      @screen = GenOneStyle.new
      @screen.intro
      self.update
      Graphics.freeze
      return
    end
    @screen.intro
    kif_lt_loop
    Graphics.freeze
  end

  def kif_lt_loop
    loop do
      Graphics.update
      Input.update
      @screen.update
      break if kif_lt_route(@screen.choice) == :leave
    end
  end

  # what a title menu choice does; :leave when the title is closed
  def kif_lt_route(choice)
    case choice
    when nil
      return nil
    when :play
      closeTitle                       # PIF's: the save selection screen, every entry as before
      return :leave
    when :options
      kif_lt_away { PokemonOptionScreen.new(PokemonGameOption_Scene.new).pbStartScreen(true) }
    when :mods
      kif_lt_away { KifSettingsScreen.new(true, :mods).main }
    when :quit
      pbPlayCloseMenuSE
      pbBGMStop(1.0)
      disposeTitle
      $scene = nil
      return :leave
    else
      openUrlInBrowser(choice.to_s)
    end
    return nil
  end

  def kif_lt_away
    pbPlayDecisionSE
    pbFadeOutIn do
      @screen.visible = false
      begin
        yield
      ensure
        @screen.visible = true
      end
    end
  end
end
