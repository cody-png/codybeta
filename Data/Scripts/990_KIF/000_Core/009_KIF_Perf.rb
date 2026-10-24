#===============================================================================
# KIF::Perf – overlay-side performance fixes for base PIF 6.8.2 behaviour
# (base files are never edited).
#
# Pokemon#species_data for a fusion: 6.8.2 (001_Pokemon.rb:252-255) calls
# GameData::Species.get(@species) on every read, and for fused ids
# (010_Data/001_GameData.rb:37-53) that builds a brand-new FusedSpecies each
# time: merged movesets, tutor/egg moves, evolutions, name, dex entry, ...
# Pokemon#type1/type2/baseStats/calc_stats/moves checks all go through it,
# so a fusion in the party rebuilt its species data hundreds of times per
# screen and the AI thousands of times per turn.
# Here the built object is kept on the Pokémon and reused while its species
# is unchanged and the game data hasn't been reloaded (boot/compile token).
# Non-fused species keep 6.8.2's lookup (DATA already returns one object).
# A Pokémon loaded from a save carries an old token, so it rebuilds once.
#===============================================================================
module KIF
  module Perf
    @token = rand(2**30) + 1

    def self.token; @token; end
    def self.bump_token; @token = rand(2**30) + 1; end
  end
end

module KIF
  module DataLoad
    class << self
      alias kif_perf_run run unless method_defined?(:kif_perf_run)

      def run
        KIF::Perf.bump_token
        kif_perf_run
      end
    end
  end
end

class Pokemon
  alias kif_perf_species_data species_data unless method_defined?(:kif_perf_species_data)

  def species_data
    sd = @species_data
    if sd && @kif_sd_token == KIF::Perf.token && sd.species == @species
      return sd
    end
    sd = kif_perf_species_data
    @kif_sd_token = KIF::Perf.token
    return sd
  end
end

#-------------------------------------------------------------------------------
# Pokédex list (016_UI/Pokedex/003_UI_Pokedex_Main.rb)
#   * pbRefresh runs on every cursor move and asks for the Seen/Owned totals;
#     each total walks every fusion slot (~330,000 entries, Player::Pokedex
#     #count_dex), so scrolling dropped frames. The totals can't change while
#     the list is open, so they're counted once per visit (again after an
#     entry page closes).
#   * setIconBitmap keeps a copy of every sprite looked at and never frees
#     them; they're freed when the Pokédex closes.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    @dex_counts = nil
    class << self
      attr_accessor :dex_counts
    end
  end
end

class Player < Trainer
  class Pokedex
    alias kif_perf_seen_count seen_count unless method_defined?(:kif_perf_seen_count)
    alias kif_perf_owned_count owned_count unless method_defined?(:kif_perf_owned_count)

    def seen_count(dex = -1)
      c = KIF::Perf.dex_counts
      return kif_perf_seen_count(dex) unless c && c[:dex].equal?(self)
      key = [:seen, dex]
      return c[key] if c.key?(key)
      return c[key] = kif_perf_seen_count(dex)
    end

    def owned_count(dex = -1)
      c = KIF::Perf.dex_counts
      return kif_perf_owned_count(dex) unless c && c[:dex].equal?(self)
      key = [:owned, dex]
      return c[key] if c.key?(key)
      return c[key] = kif_perf_owned_count(dex)
    end
  end
end

class PokemonPokedex_Scene
  alias kif_perf_pbPokedex pbPokedex unless method_defined?(:kif_perf_pbPokedex)
  alias kif_perf_pbDexEntry pbDexEntry unless method_defined?(:kif_perf_pbDexEntry)
  alias kif_perf_pbEndScene pbEndScene unless method_defined?(:kif_perf_pbEndScene)

  def pbPokedex(*args)
    old = KIF::Perf.dex_counts
    KIF::Perf.dex_counts = { :dex => $Trainer.pokedex }
    begin
      return kif_perf_pbPokedex(*args)
    ensure
      KIF::Perf.dex_counts = old
    end
  end

  def pbDexEntry(*args)
    c = KIF::Perf.dex_counts
    c.delete_if { |k, _| k != :dex } if c
    return kif_perf_pbDexEntry(*args)
  end

  def pbEndScene(*args)
    ret = kif_perf_pbEndScene(*args)
    if @sprites_cache
      @sprites_cache.each_value { |bmp| bmp.dispose if bmp && !bmp.disposed? rescue nil }
      @sprites_cache = nil
    end
    return ret
  end
end

#===============================================================================
# Sprite credits lookups. 6.8.2 reads the whole Sprite_Credits.csv (~236,000
# lines) every time it picks a sprite letter (FusionSprites.rb:499,
# map_alt_sprite_letters_for_pokemon) or looks up an artist
# (SpriteCreditsUtils.rb:453, getSpriteCredits): ~90 ms each. With Random
# sprites on that happens for every Pokémon drawn (each Pokédex step, each
# battler, each fusion preview), and once per new species otherwise.
# Here the file is read once into lines grouped by sprite name without its
# letters ("25", "25a", "25b" -> "25"); each lookup then runs PIF's own
# per-line code over that group only, so the results are the same. The group
# is re-read when the file changes (size/time), e.g. after a credits download.
#===============================================================================
module KIF
  module Perf
    module Credits
      @lines = nil
      @stamp = nil

      def self.stamp
        st = File.stat(Settings::CREDITS_FILE_PATH)
        return [st.size, st.mtime.to_f]
      rescue SystemCallError
        return nil
      end

      # Lines (with their newline) whose sprite name is base + letters.
      def self.group(base)
        s = stamp
        return nil unless s
        if !@lines || @stamp != s
          @lines = nil
          idx = {}
          File.foreach(Settings::CREDITS_FILE_PATH) do |line|
            name = line[/\A[^,\r\n]*/].strip
            next if name.empty?
            key = name.sub(/[a-zA-Z]+\z/, "")
            (idx[key] ||= +"") << line
          end
          @lines = idx
          @stamp = s
        end
        return @lines[base] || ""
      rescue StandardError
        @lines = nil
        return nil
      end

      def self.reset
        @lines = nil
        @stamp = nil
      end
    end
  end
end

class Object
  unless private_method_defined?(:kif_perf_map_alt_sprite_letters_for_pokemon)
    alias kif_perf_map_alt_sprite_letters_for_pokemon map_alt_sprite_letters_for_pokemon
    alias kif_perf_getSpriteCredits getSpriteCredits
  end
  private

  def map_alt_sprite_letters_for_pokemon(spriteName)
    name = spriteName.to_s
    lines = name =~ /[a-zA-Z]\z/ ? nil : KIF::Perf::Credits.group(name)
    return kif_perf_map_alt_sprite_letters_for_pokemon(spriteName) unless lines
    alt_sprites = {}
    lines.each_line do |line|
      row = line.strip.split(',')
      sprite_name = row[0]
      next unless sprite_name && sprite_name.start_with?(name)
      suffix = sprite_name[name.length..-1] || ""
      if suffix.empty?
        alt_sprites[""] = row[2]
        next
      end
      next unless suffix.match?(/\A[a-zA-Z]+\z/)
      alt_sprites[suffix] = row[2]
    end
    return alt_sprites
  end

  def getSpriteCredits(spriteName)
    name = spriteName.to_s
    lines = KIF::Perf::Credits.group(name.sub(/[a-zA-Z]+\z/, ""))
    return kif_perf_getSpriteCredits(spriteName) unless lines
    lines.each_line do |line|
      row = line.split(',')
      return row[1] if row[0] == spriteName
    end
    return nil
  end
end

#===============================================================================
# Game text tables: empty entries as nil. The species / kind / Pokédex entry
# / form tables (001_Technical/003_Intl_Messages.rb) have a slot for every
# possible fusion number - 1,000,034 each - and almost all of them hold a
# separate empty string: ~4 million objects (~160 MB) that every full
# garbage collection walks through. Messages#get already answers "" for a
# nil entry (a fresh one each time), so storing nil changes nothing for the
# game; the count (getCount) stays the same.
#===============================================================================
module KIF
  module Perf
    def self.compact_messages(msgs)
      return 0 unless msgs.is_a?(Array)
      n = 0
      msgs.each do |arr|
        next unless arr.is_a?(Array) && arr.length > 10_000
        arr.each_index do |i|
          s = arr[i]
          next unless s.is_a?(String) && s.empty?
          arr[i] = nil
          n += 1
        end
      end
      return n
    rescue StandardError
      return 0
    end
  end
end

#-------------------------------------------------------------------------------
# messages.dat read once at start-up, not twice. 6.8.2 loads it into the main
# table (999_Main.rb:171), then Game.set_up_system loads the language file
# over it (001_StartGame.rb:110, "english.dat" - not shipped, so the main
# table ends up empty), and the first text lookup then loads messages.dat
# again for the fallback table: ~2 s on a PC thrown away (much more on a
# phone). The first copy now goes to the fallback, when that one hasn't
# loaded yet, is waiting for the same file, the file is unchanged and nothing
# was written into the main table since.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    def self.messages_stamp(file)
      st = File.stat(file)
      return [st.size, st.mtime]
    rescue StandardError
      return nil
    end

    # main: the Messages about to load another file
    def self.hand_over_messages(main)
      from = main.instance_variable_get(:@kif_loaded_from)
      return false unless from && defined?(MessageTypes)
      main.instance_variable_set(:@kif_loaded_from, nil)
      return false unless main.equal?(MessageTypes.class_variable_get(:@@messages))
      fb = MessageTypes.class_variable_get(:@@messagesFallback)
      return false unless fb.instance_variable_get(:@messages).nil? && fb.instance_variable_get(:@filename) == from[0]
      return false unless messages_stamp(from[0]) == from[1]
      fb.instance_variable_set(:@messages, main.instance_variable_get(:@messages))
      fb.instance_variable_set(:@filename, nil)
      return true
    rescue StandardError
      return false
    end

    #---------------------------------------------------------------------------
    # Text tables kept ready to load. Decoding messages.dat (31 MB: XOR, then
    # Marshal.load of ~4 million mostly empty entries, then the compacting
    # above) takes ~2 s on a PC at every start; the same tables saved once
    # already compacted (zlib, ~1 MB) load in ~0.1 s. Remade when the file's
    # size or time changes; any problem reading it = the normal load.
    #---------------------------------------------------------------------------
    module TextCache
      FORMAT = 1
      DIR = "Cache/KIFText"   # in the game folder, or the save folder when that can't be written

      def self.path(file)
        return File.join(KIF::Paths.writable(DIR), File.basename(file.to_s) + ".kifcache")
      end

      def self.key(file, stamp)
        return [FORMAT, File.basename(file.to_s), stamp[0], stamp[1].to_f]
      end

      def self.read(file, stamp)
        f = path(file)
        return nil unless File.file?(f)
        k, tables = Marshal.load(Zlib::Inflate.inflate(File.binread(f)))
        return (k == key(file, stamp) && tables.is_a?(Array)) ? tables : nil
      rescue StandardError
        return nil
      end

      def self.write(file, stamp, tables)
        f = path(file)
        KIF.mkdir_p(File.dirname(f))
        tmp = "#{f}.#{Process.pid}.tmp"
        File.binwrite(tmp, Zlib::Deflate.deflate(Marshal.dump([key(file, stamp), tables]), Zlib::BEST_SPEED))
        File.delete(f) if File.exist?(f)   # (Windows: rename won't replace)
        File.rename(tmp, f)
      rescue StandardError => e
        (File.delete(tmp) rescue nil) if tmp
        KIF.log("Text cache not written (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
      end
    end
  end
end

class Messages
  alias kif_perf_loadMessageFile loadMessageFile unless method_defined?(:kif_perf_loadMessageFile)

  def loadMessageFile(*args)
    KIF::Perf.hand_over_messages(self)
    stamp = KIF::Perf.messages_stamp(args[0])
    cached = stamp && KIF::Perf::TextCache.read(args[0], stamp)
    if cached
      ret = @messages = cached
    else
      ret = kif_perf_loadMessageFile(*args)
      KIF::Perf.compact_messages(@messages)
      KIF::Perf::TextCache.write(args[0], stamp, @messages) if stamp && @messages.is_a?(Array)
    end
    @kif_loaded_from = (@messages && stamp) ? [args[0], stamp] : nil
    return ret
  end

  # a table something wrote into isn't the file's any more
  [:set, :setMessages, :addMessages, :setMessagesAsHash, :addMessagesAsHash,
   :setMapMessagesAsHash, :addMapMessagesAsHash].each do |m|
    next unless method_defined?(m)
    orig = :"kif_perf_#{m}"
    alias_method orig, m unless method_defined?(orig)
    define_method(m) do |*args, &blk|
      @kif_loaded_from = nil
      return send(orig, *args, &blk)
    end
  end
end

# already loaded before this file (the fallback tables load at start-up)
begin
  [:@@messages, :@@messagesFallback].each do |cv|
    next unless defined?(MessageTypes) && MessageTypes.class_variable_defined?(cv)
    m = MessageTypes.class_variable_get(cv)
    KIF::Perf.compact_messages(m.instance_variable_get(:@messages)) if m
  end
rescue StandardError
  nil
end

#===============================================================================
# Encryption.xor (001_Technical/000_Encryption.rb) decodes messages.dat (31 MB)
# one byte at a time in Ruby: ~7 s the first time any text is looked up.
# Same result, four bytes at a time: ~1.2 s. Used for reading and writing.
#===============================================================================
module Encryption
  class << self
    alias kif_perf_xor xor unless method_defined?(:kif_perf_xor)

    def xor(data)
      key = ENCRYPTION_KEY
      return kif_perf_xor(data) unless key.length == 16
      n = data.bytesize
      full = n - n % 16
      k0, k1, k2, k3 = key.pack("C*").unpack("L<4")
      w = data.byteslice(0, full).unpack("L<*")
      i = 0
      len = w.length
      while i < len
        w[i] ^= k0
        w[i + 1] ^= k1
        w[i + 2] ^= k2
        w[i + 3] ^= k3
        i += 4
      end
      out = w.pack("L<*")
      out << data.byteslice(full, n - full).bytes.each_with_index.map { |b, j| b ^ key[j] }.pack("C*") if n > full
      return out
    end
  end
end

#===============================================================================
# "./Game.rgssad" (an encrypted archive; KIF ships none): 6.8.2 asks the disk
# for it before every picture or data file lookup (pbGetFileChar, pbRgssOpen,
# pbRgssExists?, 001_Technical/002_Files/001_FileTests.rb), so about half of
# all file checks are for it (273 of 553 opening the party, 182 of 364 opening
# the PC). It can't appear or vanish while the game runs: checked once.
#===============================================================================
module KIF
  module Perf
    def self.archive?
      @archive = yield if @archive.nil?
      return @archive
    end
  end
end

class Object
  was_private = private_method_defined?(:safeExists?)
  alias kif_perf_safeExists? safeExists? unless method_defined?(:kif_perf_safeExists?) || private_method_defined?(:kif_perf_safeExists?)

  def safeExists?(f)
    return KIF::Perf.archive? { kif_perf_safeExists?(f) } if f == "./Game.rgssad"
    return kif_perf_safeExists?(f)
  end
  private :safeExists? if was_private
end

#===============================================================================
# UI pictures (Graphics/Pictures/...) looked up once. pbResolveBitmap
# (001_FileTests.rb:121) asks the disk for .png, .gif and .dat every time:
# opening the party resolved 31 pictures 101 times, 241 file checks, most of
# them for "_dark" variants this install doesn't ship. The game's pictures
# don't come or go while it runs, so the answer is kept per name (and
# language, and set of mod files: a mod that loads afterwards starts afresh).
#===============================================================================
module KIF
  module Perf
    PICTURES = %r{\AGraphics[/\\]Pictures[/\\]}i

    def self.picture_memo
      mods = defined?(KIF::ModAssets) ? KIF::ModAssets.files : nil
      lang = ($PokemonSystem.language rescue nil)
      unless @pic_memo && @pic_mods.equal?(mods) && @pic_lang == lang
        @pic_memo = {}
        @pic_mods = mods
        @pic_lang = lang
      end
      return @pic_memo
    end
  end
end

class Object
  was_private = private_method_defined?(:pbResolveBitmap)
  alias kif_perf_pbResolveBitmap pbResolveBitmap unless method_defined?(:kif_perf_pbResolveBitmap) || private_method_defined?(:kif_perf_pbResolveBitmap)

  def pbResolveBitmap(x)
    return kif_perf_pbResolveBitmap(x) unless x.is_a?(String) && x.match?(KIF::Perf::PICTURES)
    memo = KIF::Perf.picture_memo
    ret = memo.fetch(x) { memo[x.dup] = kif_perf_pbResolveBitmap(x) }
    return ret ? ret.dup : nil
  end
  private :pbResolveBitmap if was_private
end
