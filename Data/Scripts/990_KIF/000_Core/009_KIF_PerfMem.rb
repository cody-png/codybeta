#===============================================================================
# KIF::Perf, memory: big data files read when needed, not held or re-parsed
# (base files are never edited; loads after 009_KIF_Perf.rb).
#
# Two of them (Data/pokedex/dex.json, Data/sprites/Sprite_Credits.csv) are
# looked up by name, a few lines at a time. A small packed index (crc32 of the
# name, offset and length of its text in the file: 12 bytes a line or entry)
# points into the file; a lookup reads just its own bytes. The index is made
# once per version of the file and kept in Cache/KIFText.
#===============================================================================
require "zlib"

module KIF
  module Perf
    module PackedIndex
      REC = 12   # crc32, offset, length (32 bits each)

      # recs: [[crc, offset, length]] -> the index, sorted by crc then offset
      # (so entries with one name come out in file order)
      def self.pack(recs)
        return recs.sort.map { |r| r.pack("NNN") }.join
      end

      # [[offset, length]] of the records whose crc matches, in file order
      def self.slices(idx, crc)
        n = idx.bytesize / REC
        lo = 0
        hi = n
        while lo < hi
          mid = (lo + hi) / 2
          if idx.byteslice(mid * REC, 4).unpack1("N") < crc
            lo = mid + 1
          else
            hi = mid
          end
        end
        out = []
        while lo < n
          c, off, len = idx.byteslice(lo * REC, REC).unpack("NNN")
          break if c != crc
          out << [off, len]
          lo += 1
        end
        return out
      end

      # The index for file (stamp = its size and time): from Cache/KIFText if
      # made before, else from the block (which returns the packed index, or
      # nil when the file isn't what the index expects), then saved.
      def self.fetch(file, stamp)
        cached = KIF::Perf::TextCache.read(file, stamp)
        return cached[0] if cached && cached[0].is_a?(String) && cached[0].bytesize % REC == 0
        packed = yield
        KIF::Perf::TextCache.write(file, stamp, [packed]) if packed
        return packed
      end

      def self.stamp(file)
        st = File.stat(file)
        return [st.size, st.mtime.to_f]
      rescue SystemCallError
        return nil
      end

      def self.read_slices(file, runs)
        return File.open(file, "rb") { |f| runs.map { |off, len| f.seek(off); f.read(len) } }
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Custom Pokédex entries (Data/pokedex/dex.json, 18.8 MB, ~66,000 entries,
# nearly one per sprite). 6.8.2's getCustomDexEntry
# (016_UI/Pokedex/004_UI_Pokedex_Entry.rb) read and parsed the whole file for
# every entry page of a custom sprite: ~330,000 objects (50+ MB at its peak)
# made and thrown away each time, and the memory the parse grew into was
# never given back. Now a page reads and parses only its own entries, in file
# order, so the answer is the same. Anything unexpected (a file that isn't a
# list of flat entries, a sprite name with escapes, a read error) = 6.8.2's
# way.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    module CustomDex
      OBJECT = /\{(?:[^"{}]|"(?:[^"\\]|\\.)*")*\}/n
      SPRITE = /"sprite"\s*:\s*"((?:[^"\\]|\\.)*)"/n
      @index = nil
      @stamp = nil

      # The packed index of file, or nil (use 6.8.2's way)
      def self.index(file)
        s = PackedIndex.stamp(file)
        return nil unless s
        return (@index.is_a?(String) ? @index : nil) if @index && @stamp == s
        @stamp = s
        @index = :none   # (stays so for this file if it can't be indexed: no retry on every page)
        packed = PackedIndex.fetch(file, s) { build(file) }
        @index = packed if packed
        return packed
      rescue StandardError, NoMemoryError => e
        KIF.log("Custom Pokédex index not made (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
        return nil
      end

      def self.build(file)
        data = File.binread(file)
        recs = []
        data.scan(OBJECT) do
          m = $~
          whole = m[0]
          name = whole[SPRITE, 1]
          return nil if name.nil? || name.include?("\\")   # (unusual: the old way)
          recs << [Zlib.crc32(name), m.begin(0), whole.bytesize]
        end
        return recs.empty? ? nil : PackedIndex.pack(recs)
      end

      # [[entry text, author]] for the sprite file name, [] when it has none,
      # nil when the index can't answer (the caller then does it the old way)
      def self.entries(file, sprite)
        idx = index(file)
        return nil unless idx
        parts = PackedIndex.read_slices(file, PackedIndex.slices(idx, Zlib.crc32(sprite.to_s)))
        return [] if parts.empty?
        parsed = HTTPLite::JSON.parse("[" + parts.join(",").force_encoding(Encoding::UTF_8) + "]")
        return nil unless parsed.is_a?(Array)
        return parsed.select { |e| e.is_a?(Hash) && e["sprite"] == sprite }.map { |e| [e["entry"], e["author"]] }
      rescue StandardError => e
        KIF.log("Custom Pokédex entry read failed (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
        return nil
      end

      def self.reset
        @index = nil
        @stamp = nil
      end
    end
  end
end

class PokemonPokedexInfo_Scene
  alias kif_perfmem_getCustomDexEntry getCustomDexEntry unless method_defined?(:kif_perfmem_getCustomDexEntry)

  def getCustomDexEntry(pif_sprite)
    sprite = pif_sprite.to_filename()
    found = KIF::Perf::CustomDex.entries(Settings::CUSTOM_DEX_ENTRIES_PATH, sprite)
    return kif_perfmem_getCustomDexEntry(pif_sprite) if found.nil?
    if found.empty?
      echoln "No custom entry found for sprite " + sprite.to_s
      return nil
    end
    return found
  end
end

#-------------------------------------------------------------------------------
# Sprite credits (Data/sprites/Sprite_Credits.csv, 6.3 MB, 236,000 lines).
# 009_KIF_Perf.rb's Credits.group kept the whole file in memory as 174,000
# strings grouped by sprite name (~28 MB, 2+ s to make at the first sprite
# pick). Same answer (the lines of one name, in file order), read from the file
# through the index instead.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    module Credits
      @pm_index = nil
      @pm_stamp = nil

      class << self
        alias kif_perfmem_group group unless method_defined?(:kif_perfmem_group)
        alias kif_perfmem_reset reset unless method_defined?(:kif_perfmem_reset)

        # the name a line is grouped by: its sprite name without letters (nil: no name)
        def pm_key(line)
          name = line[/\A[^,\r\n]*/].strip
          return name.empty? ? nil : name.sub(/[a-zA-Z]+\z/, "")
        end

        def pm_build(file)
          recs = []
          pos = 0
          prev = nil
          start = 0
          File.open(file, "rb") do |f|
            f.each_line do |line|
              k = pm_key(line)
              if k != prev
                recs << [Zlib.crc32(prev), start, pos - start] if prev
                prev = k
                start = pos
              end
              pos += line.bytesize
            end
          end
          recs << [Zlib.crc32(prev), start, pos - start] if prev
          return recs.empty? ? nil : PackedIndex.pack(recs)
        end

        def pm_index(s)
          return @pm_index if @pm_index && @pm_stamp == s
          @pm_stamp = s
          @pm_index = PackedIndex.fetch(Settings::CREDITS_FILE_PATH, s) { pm_build(Settings::CREDITS_FILE_PATH) }
          return @pm_index
        end

        def group(base)
          s = stamp
          return nil unless s
          idx = pm_index(s)
          return kif_perfmem_group(base) unless idx
          base = base.to_s
          runs = PackedIndex.slices(idx, Zlib.crc32(base))
          return "" if runs.empty?
          text = PackedIndex.read_slices(Settings::CREDITS_FILE_PATH, runs).join.force_encoding(Encoding::UTF_8)
          text.gsub!("\r\n", "\n") if File::ALT_SEPARATOR   # (6.8.2 read the file in text mode: Windows drops the CR)
          out = +""
          text.each_line { |l| out << l if pm_key(l) == base }
          return out
        rescue StandardError
          @pm_index = nil
          @pm_stamp = nil
          return kif_perfmem_group(base)
        end

        def reset
          @pm_index = nil
          @pm_stamp = nil
          kif_perfmem_reset
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Game text tables (001_Technical/003_Intl_Messages.rb). The species / kind /
# Pokédex entry / form tables have a slot for every fusion number (1,000,034),
# but hold ~600 texts (15 for forms): 4 arrays of 8 MB that are nearly all
# nil, loaded at every start and walked by every full garbage collection.
# 009_KIF_Perf.rb already stores the empty ones as nil; here those tables
# become a Hash of the slots that hold text (SparseTable), ~100 KB. The
# game only reads them through Messages#get / #set / #getCount, which answer
# as before ("" for a slot with no text; the count is the old length).
# A cache file made before this (arrays) is made sparse when read, once.
#-------------------------------------------------------------------------------
module KIF
  module Perf
    class SparseTable < Hash
      attr_accessor :slots   # the length of the array this stands for

      def [](i)
        i = i.to_int if !i.is_a?(Integer) && i.respond_to?(:to_int)
        i += @slots if i.is_a?(Integer) && i < 0
        return super(i)
      end

      def []=(i, v)
        i = i.to_int if !i.is_a?(Integer) && i.respond_to?(:to_int)
        @slots = i + 1 if i.is_a?(Integer) && i >= @slots
        return v.nil? ? (delete(i); v) : super(i, v)
      end

      # the array it stands for (debug tools that write the tables out)
      def to_dense
        a = Array.new(@slots)
        each { |k, v| a[k] = v if k.is_a?(Integer) && k >= 0 && k < @slots }
        return a
      end
    end

    class << self
      alias kif_perfmem_compact_messages compact_messages unless method_defined?(:kif_perfmem_compact_messages)

      # Number of tables made sparse
      def sparsify_messages(msgs)
        return 0 unless msgs.is_a?(Array)
        n = 0
        msgs.each_with_index do |arr, i|
          next unless arr.is_a?(Array) && arr.length > 10_000
          t = SparseTable.new
          t.slots = arr.length
          arr.each_with_index { |s, j| t[j] = s unless s.nil? || (s.is_a?(String) && s.empty?) }
          msgs[i] = t
          n += 1
        end
        return n
      rescue StandardError
        return 0
      end

      # The count it returned is the number of empty texts dropped (a table
      # only just made sparse has none: they are gone with it)
      def compact_messages(msgs)
        return 0 unless msgs.is_a?(Array)
        empties = 0
        msgs.each { |arr| empties += arr.count { |s| s.is_a?(String) && s.empty? } if arr.is_a?(Array) && arr.length > 10_000 }
        sparsify_messages(msgs)
        return empties
      rescue StandardError
        return 0
      end
    end

    module TextCache
      class << self
        alias kif_perfmem_read read unless method_defined?(:kif_perfmem_read)

        def read(file, stamp)
          tables = kif_perfmem_read(file, stamp)
          write(file, stamp, tables) if tables && KIF::Perf.sparsify_messages(tables) > 0
          return tables
        end
      end
    end
  end
end

class Messages
  alias kif_perfmem_saveMessages saveMessages unless method_defined?(:kif_perfmem_saveMessages)

  def getCount(type)
    delayedLoad
    return 0 if !@messages
    t = @messages[type]
    return 0 if !t
    return t.is_a?(KIF::Perf::SparseTable) ? t.slots : t.length
  end

  # saved as arrays, as 6.8.2 reads them
  def saveMessages(filename = nil)
    tables = @messages
    return kif_perfmem_saveMessages(filename) unless tables.is_a?(Array) && tables.any? { |t| t.is_a?(KIF::Perf::SparseTable) }
    begin
      @messages = tables.map { |t| t.is_a?(KIF::Perf::SparseTable) ? t.to_dense : t }
      return kif_perfmem_saveMessages(filename)
    ensure
      @messages = tables
    end
  end

  class << self
    alias kif_perfmem_writeObject writeObject unless method_defined?(:kif_perfmem_writeObject)

    def writeObject(f, msgs, secname, origMessages = nil)
      msgs = msgs.to_dense if msgs.is_a?(KIF::Perf::SparseTable)
      return kif_perfmem_writeObject(f, msgs, secname, origMessages)
    end
  end
end

# tables loaded before this file ran
begin
  [:@@messages, :@@messagesFallback].each do |cv|
    next unless defined?(MessageTypes) && MessageTypes.class_variable_defined?(cv)
    m = MessageTypes.class_variable_get(cv)
    KIF::Perf.sparsify_messages(m.instance_variable_get(:@messages)) if m
  end
rescue StandardError
  nil
end
