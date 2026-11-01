#===============================================================================
# Start-up caches (2026-11-01, PERF-BOOT)
#
# BootCache: small files in Cache/KIFBoot (the game folder, or the save folder
# when that can't be written), each made from another file and valid for that
# file's size and time. Any problem reading one = it is made again.
#
# Sprite lists. 6.8.2 reads Data/sprites/CUSTOM_SPRITES (226,000 lines) at
# every start (001_StartGame.rb:40): a regular expression and three or four
# new objects per line, ~2 s, ~3 million objects, and a Hash of 174,000
# symbols and arrays that takes ~60 MB for as long as the game runs. Here the
# list is kept as three plain arrays of numbers (a few MB), saved in the
# cache, and the Hash the game asks questions of answers from them:
# $game_temp.custom_sprites_list is a SpriteIndex::List, a Hash that looks the
# key up in the arrays. Anything else a Hash can do (a mod's each, select,
# merge ...) first fills it in, in the file's order, so the answers are the
# same; only the questions the game itself asks ([], include?, size, empty?)
# skip that. BASE_SPRITES (9,700 lines) is a plain Hash kept in the cache.
#===============================================================================
module KIF
  module Perf
    module BootCache
      FORMAT = 1
      DIR = "Cache/KIFBoot"   # in the game folder, or the save folder when that can't be written

      def self.path(name)
        return File.join(KIF::Paths.writable(DIR), name + ".kbc")
      end

      # what a cache is made from: size and time of the file
      def self.stamp(file)
        st = File.stat(file)
        return [st.size, st.mtime.to_f]
      rescue SystemCallError
        return nil
      end

      def self.read(name, key)
        f = path(name)
        return nil unless File.file?(f)
        data = Marshal.load(Zlib::Inflate.inflate(File.binread(f)))
        return (data.is_a?(Array) && data[0] == FORMAT && data[1] == key) ? data[2] : nil
      rescue StandardError
        return nil
      end

      def self.write(name, key, payload)
        f = path(name)
        KIF.mkdir_p(File.dirname(f))
        tmp = "#{f}.#{Process.pid}.tmp"
        File.binwrite(tmp, Zlib::Deflate.deflate(Marshal.dump([FORMAT, key, payload]), Zlib::BEST_SPEED))
        File.delete(f) if File.exist?(f)   # (Windows: rename won't replace)
        File.rename(tmp, f)
      rescue StandardError => e
        (File.delete(tmp) rescue nil) if tmp
        KIF.log("Boot cache #{name} not written (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
      end
    end

    module SpriteIndex
      LIMIT = 1 << 15   # head and body numbers below this fit one small integer; a bigger one = the game's own loader

      # A key as the game writes it ("B12H345") as one number, nil when no
      # such key can exist in the list
      def self.encode(key)
        return nil unless key.is_a?(Symbol)
        m = /\AB(0|[1-9]\d*)H(0|[1-9]\d*)\z/.match(key.to_s)
        return nil unless m && m[1].length < 6 && m[2].length < 6
        body = m[1].to_i
        head = m[2].to_i
        return nil if body >= LIMIT || head >= LIMIT
        return (head << 15) | body
      end

      # The lines of the list the way 001_StartGame.rb:40 reads them. nil when
      # the list holds something this index can't hold (the game's loader runs).
      def self.build_custom(path)
        first = {}           # number => place in the lists below (file order)
        ids = []             # one number per sprite name, in order of first appearance
        sets = []            # the alt letters of each ("" for none), in file order
        File.foreach(path) do |line|
          filename = line.strip
          next unless filename =~ /^(\d+)\.(\d+)([a-zA-Z]*)\.png$/
          return nil if $1.length >= 6 || $2.length >= 6
          head = $1.to_i
          body = $2.to_i
          letters = $3
          return nil if head >= LIMIT || body >= LIMIT
          id = (head << 15) | body
          i = first[id]
          unless i
            i = first[id] = ids.length
            ids << id
            sets << []
          end
          sets[i] << letters
        end
        table = []
        seen = {}
        lets = sets.map { |s| seen[s] ||= (table << s; table.length - 1) }
        perm = (0...ids.length).sort_by { |i| ids[i] }
        return [ids, lets, perm, table]
      rescue StandardError
        return nil
      end

      # the lists for the file, from the cache when it is current
      def self.custom_data(path)
        st = BootCache.stamp(path)
        return nil unless st
        data = BootCache.read("custom_sprites", st)
        return data if data.is_a?(Array) && data.length == 4 && data.all? { |a| a.is_a?(Array) } && data[0].length == data[1].length && data[0].length == data[2].length
        data = build_custom(path)
        BootCache.write("custom_sprites", st, data) if data
        return data
      end

      def self.custom_list(path)
        data = custom_data(path)
        return data ? List.new(*data) : nil
      end

      # {dex number => ["", "a", ...]} as 001_StartGame.rb:69 builds it
      def self.base_list(path)
        st = BootCache.stamp(path)
        return nil unless st
        hit = BootCache.read("base_sprites", st)
        return hit if hit.is_a?(Hash)
        index = {}
        File.foreach(path) do |line|
          filename = line.strip
          next unless filename =~ /^(\d+)([a-zA-Z]*)\.png$/
          (index[$1.to_i] ||= []) << $2
        end
        BootCache.write("base_sprites", st, index)
        return index
      rescue StandardError
        return nil
      end

      # $game_temp.custom_sprites_list. A Hash whose content is in the arrays
      # until something asks for more than a lookup.
      class List < Hash
        MEMO_MAX = 5000
        FAST = [:[], :key?, :has_key?, :include?, :member?, :empty?, :size, :length]

        def initialize(ids, lets, perm, table)
          super()
          @ids = ids
          @lets = lets
          @perm = perm
          @table = table
          @places = {}    # key => place or false (a question already answered)
          @letters = {}   # place => its Array, so the same one comes back every time
          @filled = false
        end

        # place of a key in the file-order lists, or nil
        def place(key)
          return nil if @filled
          hit = @places[key]
          return (hit || nil) unless hit.nil?
          @places.clear if @places.length >= MEMO_MAX
          id = KIF::Perf::SpriteIndex.encode(key)
          found = false
          if id
            j = @perm.bsearch_index { |p| @ids[p] >= id }
            found = @perm[j] if j && @ids[@perm[j]] == id
          end
          @places[key] = found
          return found || nil
        end

        def letters_at(i)
          @letters.clear if @letters.length >= MEMO_MAX && !@letters.key?(i)
          return @letters[i] ||= @table[@lets[i]].dup
        end

        def [](key)
          return super if @filled
          i = place(key)
          return i ? letters_at(i) : nil
        end

        def key?(key)
          return super if @filled
          return !place(key).nil?
        end
        alias has_key? key?
        alias include? key?
        alias member? key?

        def size
          return @filled ? super : @ids.length
        end
        alias length size

        def empty?
          return @filled ? super : @ids.empty?
        end

        # a random key (what keys.sample gives), without making the Hash
        def random_key
          return keys.sample if @filled
          return nil if @ids.empty?
          id = @ids[rand(@ids.length)]
          return :"B#{id & (LIMIT - 1)}H#{id >> 15}"
        end

        # every other Hash method sees the whole list
        def fill!
          return if @filled
          @filled = true   # (the Hash methods below now run as Hash's own)
          @ids.each_with_index do |id, i|
            store(:"B#{id & (LIMIT - 1)}H#{id >> 15}", @letters[i] ||= @table[@lets[i]].dup)
          end
          @places = @letters = nil
        end

        (Hash.public_instance_methods(false) - FAST).each do |m|
          define_method(m) { |*args, &blk| fill!; super(*args, &blk) }
          ruby2_keywords(m)
        end
      end
    end
  end
end

module Game
  class << self
    alias kif_perf_load_custom_sprites_list_cache load_custom_sprites_list_cache unless method_defined?(:kif_perf_load_custom_sprites_list_cache)
    alias kif_perf_load_base_sprites_list_cache load_base_sprites_list_cache unless method_defined?(:kif_perf_load_base_sprites_list_cache)

    def load_custom_sprites_list_cache
      return unless $game_temp.custom_sprites_list.empty?   # only load once at loadup
      list = KIF::Perf::SpriteIndex.custom_list(Settings::CUSTOM_SPRITES_FILE_PATH)
      return kif_perf_load_custom_sprites_list_cache unless list
      $game_temp.custom_sprites_list = list
    end

    def load_base_sprites_list_cache
      return unless $game_temp.base_sprites_list.empty?   # only load once at loadup
      list = KIF::Perf::SpriteIndex.base_list(Settings::BASE_SPRITES_FILE_PATH)
      return kif_perf_load_base_sprites_list_cache unless list
      $game_temp.base_sprites_list = list
    end
  end
end

# The two questions of the whole list the game asks. keys.sample and
# keys.length would build all 174,000 symbols for one pick.
class Object
  was_private = private_method_defined?(:getRandomFusionForIntro)
  alias kif_perf_getRandomFusionForIntro getRandomFusionForIntro unless method_defined?(:kif_perf_getRandomFusionForIntro) || private_method_defined?(:kif_perf_getRandomFusionForIntro)
  alias kif_perf_get_total_completion_percent get_total_completion_percent unless method_defined?(:kif_perf_get_total_completion_percent) || private_method_defined?(:kif_perf_get_total_completion_percent)

  def getRandomFusionForIntro()
    list = $game_temp.custom_sprites_list
    return kif_perf_getRandomFusionForIntro unless list.is_a?(KIF::Perf::SpriteIndex::List)
    random_pokemon = list.random_key || :PIKACHU
    alt_letter = list[random_pokemon]
    body_id = get_body_number_from_symbol(random_pokemon)
    head_id = get_head_number_from_symbol(random_pokemon)
    return PIFSprite.new(:CUSTOM, head_id, body_id, alt_letter)
  end

  def get_total_completion_percent()
    list = $game_temp.custom_sprites_list
    return kif_perf_get_total_completion_percent unless list.is_a?(KIF::Perf::SpriteIndex::List)
    total_nb_pokemon = (NB_POKEMON * NB_POKEMON) + NB_POKEMON
    return (list.size.to_f / total_nb_pokemon) * 100
  end
  private :getRandomFusionForIntro, :get_total_completion_percent if was_private
end
