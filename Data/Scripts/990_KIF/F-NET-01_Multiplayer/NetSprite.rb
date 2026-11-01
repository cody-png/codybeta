#===============================================================================
# F-NET-01 – Multiplayer: partners' sprites (MULTIPLAYER_PLAN.md "Sprite sync")
#
# Every Pokémon co-op sends (KIF::Coop::Mon.dump) carries
#   "sp" => [type, head, body, alt, hash]   the sprite the sender's game draws:
#            type "C" custom / "A" autogen / "B" base, head and body dex
#            numbers (body 0 for a base sprite), the alt letters, and the
#            first 16 hex digits of SHA-256 over the 96x96 frame's RGBA pixels
#   "kc" => { field => value }              KIF shiny colours (F-SHINY-01),
#            shinies only
# The receiving game ("Use partners' sprites" On, the default) draws that
# Pokémon with the same picture: from its cache of partners' sprites, or its
# own sprite for the same key when that has the same hash; otherwise it asks
# the partner for the picture (sp_get {x}) and uses its own pick until the
# picture arrives (sp_img {x, png, c}). Off: always this game's own picks.
#
# Received pictures: only one this game asked for; base64 checked; at most
# 40 KB; PNG signature, chunk CRCs, IHDR exactly 96x96 RGBA 8-bit, filter 0
# rows, inflated size exact (no zip bombs), and the pixels must hash to what
# was asked. Read by the code below, never by Bitmap.new(path); the pixels
# go into Bitmap.new(96, 96) with raw_data=. Stored only as
# <save folder>/KIF_PartnerSprites/<hash>.png (+ <hash>.txt: artist credit),
# never in Graphics/ or the sprite packs. A game only sends pictures it
# advertised itself (no file names cross the wire).
#===============================================================================
KIF::Options.define(:kif_mp_partner_sprites, 1, :global)   # 0 Off, 1 On

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Use partners' sprites"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mp_partner_sprites },
                 proc { |value| $PokemonSystem.kif_mp_partner_sprites = value },
                 [_INTL("Multiplayer: your partner's Pokémon use your own sprite picks."),
                  _INTL("Multiplayer: your partner's Pokémon look as they do in their game (their sprite picks, fetched when you don't have them).")])
}

module KIF
  module NetSprite
    SIZE    = 96
    MAX_PNG = 40_000     # a 96x96 RGBA frame stored raw is ~37 KB, so any real one fits
    HASH    = /\A[0-9a-f]{16}\z/
    ALT     = /\A[a-z]{0,3}\z/
    TYPES   = { "C" => :CUSTOM, "A" => :AUTOGEN, "B" => :BASE }
    SIG     = "\x89PNG\r\n\x1A\n".b
    FOLDER  = "KIF_PartnerSprites"
    # KIF shiny colour fields: name => [min, max] (Integer) or [:krs] (9 Integers) or [:bool]
    SHINY = {}
    %w[shinyValue head_shinyhue body_shinyhue].each { |k| SHINY[k] = [-180, 180] }
    %w[shinyR shinyG shinyB head_shinyr head_shinyg head_shinyb body_shinyr body_shinyg body_shinyb].each { |k| SHINY[k] = [0, 25] }
    %w[shinyimprovpif head_shinyimprovpif body_shinyimprovpif].each { |k| SHINY[k] = [0, 3] }
    SHINY["kif_filter_roll"] = [0, 1]
    %w[shinyKRS head_shinykrs body_shinykrs].each { |k| SHINY[k] = [:krs] }
    %w[head_shiny body_shiny].each { |k| SHINY[k] = [:bool] }

    KIF::Net::TYPES["sp_get"] = { "x" => [String, 16] }
    KIF::Net::TYPES["sp_img"] = { "x" => [String, 16], "png" => [String, 54_000], "c" => [String, 80] }

    @served  = {}   # hash => [raw, credit]: pictures this game advertised (newest 64)
    @hashes  = {}   # sprite key => hash or false, for this session
    @mem     = {}   # hash => raw: partners' pictures read this session
    @pending = {}   # hash => time asked
    @sent    = []   # times pictures were sent (rate)

    class << self
      attr_reader :served, :pending
    end

    def self.on?
      return false if KIF.mobile?
      return (($PokemonSystem.kif_mp_partner_sprites rescue 1) || 1).to_i == 1
    end

    def self.log(msg); KIF::Net.log("sprites: #{msg}"); end

    def self.on_connect(_s = nil)
      @pending.clear
      @hashes.clear   # sprite packs may have changed between sessions
    end

    #---------------------------------------------------------------------------
    # Files
    #---------------------------------------------------------------------------
    def self.dir; File.join(KIF.save_dir, FOLDER); end

    # the cache file for a hash; nil for anything that isn't a hash
    def self.path(hash, ext = "png")
      return nil unless hash.is_a?(String) && hash =~ HASH
      return File.join(dir, "#{hash}.#{ext}")
    end

    def self.credit(hash)
      f = path(hash, "txt")
      return (f && File.file?(f)) ? File.read(f, 200).to_s.strip : nil
    rescue SystemCallError
      return nil
    end

    def self.digest(raw); Digest::SHA256.hexdigest(raw)[0, 16]; end

    #---------------------------------------------------------------------------
    # PNG: written and read here, one shape only (96x96, RGBA 8-bit, filter 0)
    #---------------------------------------------------------------------------
    def self.chunk(type, data); [data.bytesize].pack("N") + type.b + data.b + [Zlib.crc32(type.b + data.b)].pack("N"); end

    def self.png(raw)
      stride = SIZE * 4
      rows = (0...SIZE).map { |y| "\0".b + raw.byteslice(y * stride, stride) }.join
      return SIG + chunk("IHDR", [SIZE, SIZE, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
             chunk("IDAT", Zlib::Deflate.deflate(rows, 9)) + chunk("IEND", "".b)
    end

    # RGBA pixels, or nil for anything that isn't exactly our shape
    def self.read_png(bytes)
      return nil unless bytes.is_a?(String) && bytes.bytesize.between?(45, MAX_PNG)
      b = bytes.b
      return nil unless b.byteslice(0, 8) == SIG
      pos = 8
      ihdr = nil
      idat = "".b
      last = nil
      while pos + 12 <= b.bytesize
        len = b.byteslice(pos, 4).unpack1("N")
        return nil if len > b.bytesize - pos - 12
        type = b.byteslice(pos + 4, 4)
        data = b.byteslice(pos + 8, len)
        return nil unless b.byteslice(pos + 8 + len, 4).unpack1("N") == Zlib.crc32(type + data)
        case type
        when "IHDR".b
          return nil if ihdr || pos != 8
          ihdr = data.unpack("NNCCCCC")
        when "IDAT".b then idat << data
        end
        last = type
        pos += 12 + len
        break if type == "IEND".b
      end
      return nil unless last == "IEND".b && ihdr == [SIZE, SIZE, 8, 6, 0, 0, 0]
      stride = SIZE * 4 + 1
      rows = inflate(idat, stride * SIZE) or return nil
      raw = "".b
      SIZE.times do |y|
        return nil unless rows.getbyte(y * stride) == 0
        raw << rows.byteslice(y * stride + 1, stride - 1)
      end
      return raw
    rescue StandardError
      return nil
    end

    # inflates in small steps and stops past `want` bytes
    def self.inflate(data, want)
      z = Zlib::Inflate.new
      out = "".b
      i = 0
      while i < data.bytesize
        out << z.inflate(data.byteslice(i, 256))
        return nil if out.bytesize > want
        i += 256
      end
      out << z.finish
      return out.bytesize == want ? out : nil
    rescue Zlib::Error
      return nil
    ensure
      (z.close rescue nil) if z
    end

    #---------------------------------------------------------------------------
    # This game's sprites
    #---------------------------------------------------------------------------
    # The PIFSprite this game draws p with (as FusionSprites.rb picks it), or nil
    def self.pick(p)
      return nil if p.egg? || !$PokemonSystem.alt_sprite_substitutions.is_a?(Hash)
      dex = getDexNumberForSpecies(p.species)
      return nil if isTripleFusion?(dex)
      if $PokemonSystem.random_sprites
        p.pif_sprite ||= GameData::Species.front_pif_sprite(p.species, p.shiny?, p.body_shiny, p.head_shiny)
        return p.pif_sprite
      end
      loader = BattleSpriteLoader.new
      if isFusion(dex)
        body = getBodyID(dex)
        return loader.obtain_fusion_pif_sprite(getHeadID(dex, body), body)
      end
      sub = get_sprite_substitution_id_from_dex_number(dex)
      ps = $PokemonSystem.alt_sprite_substitutions[sub]
      unless ps
        ps = loader.select_new_pif_base_sprite(dex)
        $PokemonSystem.alt_sprite_substitutions[sub] = ps   # as load_base_sprite does
      end
      return ps
    end

    def self.key(ps)
      t = TYPES.key(ps.type) or return nil
      a = ps.alt_letter.to_s
      return nil unless a =~ ALT
      return [t, ps.head_id.to_i, t == "B" ? 0 : ps.body_id.to_i, a]
    end

    def self.sprite_of(k)
      t, head, body, alt = k
      ps = PIFSprite.new(TYPES[t], head, t == "B" ? nil : body, alt)
      lp = (BattleSpriteLoader.new.check_for_local_sprite(ps) rescue nil) unless t == "A"
      ps.local_path = lp if lp
      return ps
    end

    # the unscaled 96x96 frame's pixels (from its sheet, or its own file
    # sampled down from 288x288), or nil
    def self.frame_raw(ps)
      if ps.local_path
        anim = AnimatedBitmap.new(ps.local_path)
        begin
          bmp = anim.bitmap
          return bmp.raw_data if bmp.width == SIZE && bmp.height == SIZE
          return nil unless bmp.width == SIZE * 3 && bmp.height == SIZE * 3
          px = bmp.raw_data.unpack("N*")
          return (0...SIZE * SIZE).map { |i| px[((i / SIZE) * 3 + 1) * SIZE * 3 + (i % SIZE) * 3 + 1] }.pack("N*")
        ensure
          anim.dispose
        end
      end
      ex = BattleSpriteLoader.new.get_sprite_extractor_instance(ps.type)
      return nil unless pbResolveBitmap(ex.getSpritesheetPath(ps))
      bmp = ex.load_bitmap_from_spritesheet(ps)
      begin
        return (bmp.width == SIZE && bmp.height == SIZE) ? bmp.raw_data : nil
      ensure
        bmp.dispose
      end
    rescue StandardError => e
      log("couldn't read a sprite (#{e.class}: #{e.message})")
      return nil
    end

    # hash of a key's picture in this game (once a session), or nil
    def self.hash_of(k, ps = nil)
      return @hashes[k] || nil if @hashes.key?(k)
      raw = frame_raw(ps || sprite_of(k))
      h = raw && raw.bytesize == SIZE * SIZE * 4 ? digest(raw) : nil
      @hashes.clear if @hashes.length >= 256   # (a partner's endless new keys)
      @hashes[k] = h || false
      return h
    end

    #---------------------------------------------------------------------------
    # On the wire (KIF::Coop::Mon.dump / load)
    #---------------------------------------------------------------------------
    def self.dump_into(h, p)
      ps = pick(p)
      k = ps && key(ps)
      if k
        x = hash_of(k, ps)
        if x
          h["sp"] = k + [x]
          remember(x, frame_raw(ps), ps) unless @served.key?(x)
        end
      end
      kc = shiny_dump(p)
      if kc
        h["kc"] = kc
        h["sm"] = shiny_modes(p)   # how this game draws its colours (Colours, style, filter)
      end
      return h
    rescue StandardError => e
      log("no sprite key (#{e.class}: #{e.message})")
      return h
    end

    def self.remember(x, raw, ps)
      return unless raw && raw.bytesize == SIZE * SIZE * 4 && digest(raw) == x
      c = (ps.type == :AUTOGEN ? nil : getSpriteCredits(ps.to_filename(false))) rescue nil
      @served[x] = [raw, c.to_s.strip[0, 80]]
      @served.delete(@served.keys.first) while @served.length > 64
    end

    # a checked sprite key from the wire, or nil
    def self.read_key(v)
      return nil unless v.is_a?(Array) && v.length == 5
      t, head, body, alt, x = v
      return nil unless TYPES.key?(t) && alt.is_a?(String) && alt =~ ALT && x.is_a?(String) && x =~ HASH
      max = (Settings::NB_POKEMON rescue 501)
      return nil unless head.is_a?(Integer) && head.between?(1, max) && body.is_a?(Integer)
      return nil unless t == "B" ? body == 0 : body.between?(1, max)
      return [t, head, body, alt, x]
    end

    # the sending game's colour settings: Colours (0-2), style (0-3), filter (0-2)
    MODES = [[:shinyadvanced, 2, 1], [:pifimprovedshinies, 3, 0], [:shinyfilter, 2, 2]]

    def self.shiny_modes(p)
      return MODES.map { |k, _max, d| defined?(KIF::Shiny) ? KIF::Shiny.opt(p, k, d) : d }
    end

    def self.load_into(p, h)
      if p.shiny? && h["kc"].is_a?(Hash)
        m = h["sm"]
        if m.is_a?(Array) && m.length == 3 && m.each_with_index.all? { |v, i| v.is_a?(Integer) && v.between?(0, MODES[i][1]) }
          p.instance_variable_set(:@kif_net_shiny, MODES.each_with_index.map { |(k, _, _), i| [k, m[i]] }.to_h)
        end
        shiny_load(p, h["kc"])
      end
      return p unless on?
      k = read_key(h["sp"]) or return p
      p.instance_variable_set(:@kif_net_sprite, k)
      want(k)
      return p
    rescue StandardError => e
      log("sprite key not used (#{e.class}: #{e.message})")
      return p
    end

    # a caught Pokémon is this player's own: its own sprite picks from now on
    def self.forget(p)
      p.remove_instance_variable(:@kif_net_sprite) if p.instance_variable_defined?(:@kif_net_sprite)
      p.remove_instance_variable(:@kif_net_shiny) if p.instance_variable_defined?(:@kif_net_shiny)
    end

    def self.shiny_dump(p)
      return nil unless p.shiny?
      # the colours are rolled when first drawn: a foe not drawn yet (co_begin
      # goes before the battle scene draws) is rolled here, so both games draw these
      SHINY.each { |k, r| p.send(:"#{k}?") if r[0] != :bool && p.instance_variable_get(:"@#{k}").nil? && p.respond_to?(:"#{k}?") }
      out = {}
      SHINY.each_key do |k|
        v = p.instance_variable_get(:"@#{k}")
        v = v ? true : false if SHINY[k][0] == :bool && !v.nil?
        out[k] = v.is_a?(Array) ? v.dup : v if shiny_ok?(k, v)
      end
      return out.empty? ? nil : out
    end

    def self.shiny_ok?(k, v)
      a, b = SHINY[k]
      case a
      when :bool then return v == true || v == false
      when :krs then return v.is_a?(Array) && v.length == 9 && v.all? { |x| x.is_a?(Integer) && x.between?(-200, 200) }
      else return v.is_a?(Integer) && v.between?(a, b)
      end
    end

    def self.shiny_load(p, h)
      SHINY.each_key do |k|
        v = h[k]
        p.instance_variable_set(:"@#{k}", v.is_a?(Array) ? v.dup : v) if shiny_ok?(k, v)
      end
    end

    #---------------------------------------------------------------------------
    # Partners' pictures
    #---------------------------------------------------------------------------
    # pixels for a hash from this session or the cache folder (checked again), or nil
    def self.cached_raw(x)
      return @mem[x] if @mem.key?(x)
      f = path(x) or return nil
      return nil unless File.file?(f) && File.size(f) <= MAX_PNG
      raw = read_png(File.binread(f))
      raw = nil unless raw && digest(raw) == x
      keep_mem(x, raw) if raw
      return raw
    rescue SystemCallError
      return nil
    end

    # pictures read this session: the last 200 (36 KB each)
    def self.keep_mem(x, raw)
      @mem[x] = raw
      @mem.shift while @mem.length > 200
    end

    # :cache, :own, or :asked (or nil: nothing to do)
    def self.want(k, s = nil)
      x = k[4]
      return :cache if cached_raw(x)
      return :own if hash_of(k[0, 4]) == x
      return request(s || (KIF::Net.session if KIF::Net.respond_to?(:session)), x) ? :asked : nil
    end

    def self.request(s, x)
      return false unless s&.connected? && x =~ HASH
      t = @pending[x]
      return true if t && KIF::Net.now - t < 30
      @pending.reject! { |_x, at| KIF::Net.now - at >= 30 }   # (asked of a partner that never answers)
      return false if @pending.length >= 32
      @pending[x] = KIF::Net.now
      return s.post("sp_get", "x" => x)
    end

    def self.receive(s, type, msg)
      case type
      when "sp_get"
        x = msg["x"]
        e = @served[x] or return
        now = KIF::Net.now
        @sent.reject! { |t| now - t > 10 }
        return log("too many pictures asked for; one not sent") if @sent.length >= 20
        @sent << now
        s.post("sp_img", "x" => x, "png" => [png(e[0])].pack("m0"), "c" => e[1].to_s)
      when "sp_img"
        x = msg["x"]
        return log("a picture this game didn't ask for; ignored") unless @pending.delete(x)
        bytes = (msg["png"].unpack1("m0") rescue nil)
        raw = read_png(bytes)
        return log("a picture that isn't a 96x96 PNG (or over #{MAX_PNG} bytes); ignored") unless raw
        return log("a picture that doesn't match its hash; ignored") unless digest(raw) == x
        store(x, bytes, msg["c"])
      end
    end

    def self.store(x, bytes, credit)
      keep_mem(x, read_png(bytes))
      f = path(x) or return
      @stores = @stores.to_i + 1
      if !@trimmed || @stores % 50 == 0   # the first time, then every 50 pictures: a partner can't grow the folder without limit
        @trimmed = true
        KIF.trim_cache_dir(dir, 500) if KIF.respond_to?(:trim_cache_dir)
      end
      KIF.mkdir_p(dir)
      File.binwrite(f, bytes)
      c = credit.to_s.gsub(/[\x00-\x1f\x7f\\]/, "").strip[0, 80]
      File.write(path(x, "txt"), c) unless c.empty?
    rescue SystemCallError => e
      log("couldn't save a partner's sprite (#{e.class})")
    end

    # what the battle and summary screens draw for a partner's Pokémon, or nil
    def self.bitmap_for(p)
      return nil unless on?
      k = p.instance_variable_get(:@kif_net_sprite)
      return nil unless k.is_a?(Array) && k.length == 5 && k[4].is_a?(String)
      raw = cached_raw(k[4])
      if raw
        bmp = Bitmap.new(SIZE, SIZE)
        bmp.raw_data = raw
        anim = AnimatedBitmap.from_bitmap(bmp)
        anim.scale_bitmap(3)   # the sheets' frames are drawn 3x, as the extractors do
        return anim
      end
      return BattleSpriteLoader.new.load_pif_sprite_directly(sprite_of(k[0, 4])) if hash_of(k[0, 4]) == k[4]
      want(k)
      return nil
    rescue StandardError => e
      log("partner's sprite not drawn (#{e.class}: #{e.message})")
      return nil
    end
  end
end

# Every Pokémon sprite goes through front_sprite_bitmap_pokemon (F-SHINY-01's
# hook wraps this one: this file loads first, so KIF shiny colours apply on top)
module GameData
  class Species
    class << self
      alias kif_net_front_sprite_bitmap_pokemon front_sprite_bitmap_pokemon unless method_defined?(:kif_net_front_sprite_bitmap_pokemon) || private_method_defined?(:kif_net_front_sprite_bitmap_pokemon)

      def front_sprite_bitmap_pokemon(pokemon)
        if pokemon.instance_variable_get(:@kif_net_sprite)
          anim = KIF::NetSprite.bitmap_for(pokemon)
          if anim
            anim.shiftAllColors(pokemon.id_number, pokemon.body_shiny, pokemon.head_shiny) if pokemon.shiny?
            return anim
          end
        end
        return kif_net_front_sprite_bitmap_pokemon(pokemon)
      end
    end
  end
end
