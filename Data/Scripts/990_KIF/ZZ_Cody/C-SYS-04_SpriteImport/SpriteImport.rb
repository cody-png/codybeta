#===============================================================================
# C-SYS-04 – Sprite import (Cody, 2026-10-08)
#   1. Drop sprites into the "Import Sprites" folder (next to Game.exe) in any
#      shape: loose .png files, a sprite pack folder, folders inside folders,
#      a .zip (or .rar / .7z, unpacked by Windows' own tar when it can). At
#      start-up every sprite found is MOVED to where the game reads it:
#        123.png, 123a.png          -> Graphics/CustomBattlers/local_sprites/BaseSprites/
#        12.34.png, 12.34b.png      -> Graphics/CustomBattlers/local_sprites/indexed/12/
#        144.145.146.png            -> Graphics/Battlers/special/
#        .../spritesheets_base/...  -> Graphics/CustomBattlers/spritesheets/spritesheets_base/
#        .../spritesheets_custom/...-> Graphics/CustomBattlers/spritesheets/spritesheets_custom/
#      An archive is unpacked straight into a work folder, its sprites moved
#      the same way, and the archive itself is put in "Import Sprites/_done".
#      PIF's own "Sprites to import" folder works the same way. Sprites that
#      already exist are left for PIF's "replace them?" question, as before.
#   2. PIF 6.8.2 reads base sprites only from sprite sheets, and picks a
#      fusion's sprite once and remembers it. Single sprite files (old packs,
#      KIF 0.20.x installs, the import above) are now read first, every time.
#===============================================================================
module KIF
  module SpriteImport
    IMPORT_DIR  = "Import Sprites"
    DONE_DIR    = "_done"
    WORK_DIR    = "_unpacking"
    ARCHIVES    = %w[.zip .rar .7z .tar .gz .tgz]
    BASE_DIR    = "Graphics/CustomBattlers/local_sprites/BaseSprites"
    INDEXED_DIR = "Graphics/CustomBattlers/local_sprites/indexed"
    SPECIAL_DIR = "Graphics/Battlers/special"
    SHEETS_DIR  = "Graphics/CustomBattlers/spritesheets"
    PIF_IMPORT  = "Graphics/CustomBattlers/Sprites to import"

    module_function

    def import_dirs
      list = [IMPORT_DIR]
      list << PIF_IMPORT.chomp("/") if Dir.exist?(PIF_IMPORT)
      return list
    end

    # Keep the window alive during a long import
    def tick
      @last_tick ||= Time.now
      return if Time.now - @last_tick < 0.25
      @last_tick = Time.now
      Graphics.update rescue nil
    end

    # Where a sprite goes, from its name and the folders it sits in; nil = not a sprite we know
    def destination(path)
      name = File.basename(path)
      return nil unless name =~ /\.png\z/i
      parts = path.tr("\\", "/").split("/")
      if (i = parts.index { |p| p.downcase == "spritesheets_base" })
        return File.join(SHEETS_DIR, "spritesheets_base", *parts[(i + 1)..-1])
      end
      if (i = parts.index { |p| p.downcase == "spritesheets_custom" })
        return File.join(SHEETS_DIR, "spritesheets_custom", *parts[(i + 1)..-1])
      end
      case name
      when /\A\d+\.\d+\.\d+\.png\z/i
        return File.join(SPECIAL_DIR, name)
      when /\A(\d+)\.(\d+)[a-z]*\.png\z/i
        return File.join(INDEXED_DIR, $1, name)
      when /\A\d+[a-z]*\.png\z/i
        return File.join(BASE_DIR, name)
      end
      return nil
    end

    def mkdir_p(dir)
      return if dir.nil? || dir.empty? || Dir.exist?(dir)
      mkdir_p(File.dirname(dir))
      Dir.mkdir(dir) rescue nil
    end

    # Every file under a folder (skipping our own _done / _unpacking)
    def each_file(dir, top = true, &block)
      Dir.children(dir).sort.each do |c|
        path = File.join(dir, c)
        if File.directory?(path)
          next if top && [DONE_DIR, WORK_DIR].include?(c)
          each_file(path, false, &block)
        else
          yield path
        end
      end
    end

    # Remove folders left empty once their sprites have moved out
    def prune(dir, top = true)
      Dir.children(dir).each do |c|
        path = File.join(dir, c)
        next unless File.directory?(path)
        next if top && c == DONE_DIR
        prune(path, false)
      end
      Dir.rmdir(dir) if !top && Dir.children(dir).empty?
    rescue
    end

    #---------------------------------------------------------------------------
    # Archives: the built-in .zip reader, else Windows' tar (bsdtar)
    #---------------------------------------------------------------------------
    def unpack(archive, into)
      mkdir_p(into)
      # .zip: read here (no console window); anything else, or a .zip this
      # reader can't handle: Windows' tar
      return true if archive =~ /\.zip\z/i && Zip.extract(archive, into)
      begin
        return system("tar", "-xf", archive, "-C", into) ? true : false
      rescue
        return false
      end
    end

    def file_after(dir, name)
      base = File.basename(name, ".*"); ext = File.extname(name)
      path = File.join(dir, name); n = 2
      while File.exist?(path)
        path = File.join(dir, "#{base} (#{n})#{ext}"); n += 1
      end
      return path
    end

    #---------------------------------------------------------------------------
    # The import itself: returns [moved, conflicts (old => new), skipped, failed archives]
    #---------------------------------------------------------------------------
    def run
      mkdir_p(IMPORT_DIR)
      moved = 0; conflicts = {}; skipped = 0; failed = []
      import_dirs.each do |root|
        next unless Dir.exist?(root)
        # unpack archives first (each into its own work folder; an archive
        # inside an archive gets its turn on the next pass)
        3.times do
          found = false
          archives = []
          each_file(root, false) do |path|
            next if path.include?("/#{DONE_DIR}/")
            next unless ARCHIVES.include?(File.extname(path).downcase)
            next if failed.include?(path)
            archives << path
          end
          archives.each do |path|
            found = true
            work = file_after(File.join(root, WORK_DIR), File.basename(path, ".*"))
            if unpack(path, work)
              mkdir_p(File.join(root, DONE_DIR))
              File.rename(path, file_after(File.join(root, DONE_DIR), File.basename(path))) rescue nil
            else
              failed << path
            end
            tick
          end
          break unless found
        end
        placed = {}   # sprites moved in this run: a second file with the same name is left alone
        each_file(root, false) do |path|
          next if path.include?("/#{DONE_DIR}/")
          dest = destination(path.sub(root, ""))
          unless dest
            skipped += 1 unless ARCHIVES.include?(File.extname(path).downcase)
            next
          end
          if placed[dest]
            skipped += 1
          elsif File.exist?(dest)
            conflicts[path] = dest
          else
            mkdir_p(File.dirname(dest))
            begin
              File.rename(path, dest)
              placed[dest] = true
              moved += 1
            rescue
              skipped += 1
            end
          end
          tick
        end
        prune(root)
      end
      return [moved, conflicts, skipped, failed.map { |f| File.basename(f) }]
    end

    #---------------------------------------------------------------------------
    # Reading single sprite files before sprite sheets
    #---------------------------------------------------------------------------
    def local_for(pif_sprite)
      return nil unless pif_sprite
      alt = pif_sprite.alt_letter.to_s
      path = case pif_sprite.type
             when :BASE then "#{BASE_DIR}/#{pif_sprite.head_id}#{alt}.png"
             when :CUSTOM, :AUTOGEN then "#{INDEXED_DIR}/#{pif_sprite.head_id}/#{pif_sprite.head_id}.#{pif_sprite.body_id}#{alt}.png"
             end
      return nil unless path
      @exists ||= {}
      @exists[path] = File.file?(path) unless @exists.key?(path)
      return @exists[path] ? path : nil
    end

    def forget_lookups
      @exists = {}
    end

    def load_local(path)
      bmp = AnimatedBitmap.new(path)
      bmp.scale_bitmap(3) if bmp.bitmap.width < 150   # a 96 px sprite: game size is 288
      return bmp
    end

    #---------------------------------------------------------------------------
    # A small .zip reader (stored and deflated entries, zip64 included)
    #---------------------------------------------------------------------------
    module Zip
      module_function

      def extract(archive, into)
        require "zlib"
        File.open(archive, "rb") do |f|
          entries(f).each do |name, method, csize, offset|
            next if name.end_with?("/")
            safe = name.tr("\\", "/").split("/").reject { |p| p.empty? || p == "." || p == ".." }
            next if safe.empty?
            f.seek(offset)
            h = f.read(30)
            next unless h && h[0, 4] == "PK\x03\x04".b
            nlen, xlen = h[26, 4].unpack("vv")
            f.seek(offset + 30 + nlen + xlen)
            data = f.read(csize)
            data = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) if method == 8
            next unless method == 0 || method == 8
            out = File.join(into, *safe)
            KIF::SpriteImport.mkdir_p(File.dirname(out))
            File.binwrite(out, data)
            KIF::SpriteImport.tick
          end
        end
        return true
      rescue => e
        KIF.log("Sprite import: couldn't read #{File.basename(archive)} (#{e.class}: #{e.message})") if defined?(KIF.log)
        return false
      end

      # [[name, method, compressed size, local header offset], ...]
      def entries(f)
        size = f.size
        tail = [size, 65_557].min
        f.seek(size - tail)
        buf = f.read(tail)
        eocd = buf.rindex("PK\x05\x06".b)
        raise "not a zip" unless eocd
        count, cd_size, cd_off = buf[eocd + 10, 10].unpack("vVV")
        if count == 0xFFFF || cd_off == 0xFFFFFFFF
          loc = buf.rindex("PK\x06\x07".b)
          raise "zip64 locator missing" unless loc
          z64 = buf[loc + 8, 8].unpack1("Q<")
          f.seek(z64)
          rec = f.read(56)
          count, cd_size, cd_off = rec[32, 8].unpack1("Q<"), rec[40, 8].unpack1("Q<"), rec[48, 8].unpack1("Q<")
        end
        f.seek(cd_off)
        cd = f.read(cd_size)
        list = []
        pos = 0
        count.times do
          break unless cd[pos, 4] == "PK\x01\x02".b
          method = cd[pos + 10, 2].unpack1("v")
          csize, usize = cd[pos + 20, 8].unpack("VV")
          nlen, xlen, clen = cd[pos + 28, 6].unpack("vvv")
          offset = cd[pos + 42, 4].unpack1("V")
          name = cd[pos + 46, nlen].force_encoding("UTF-8")
          extra = cd[pos + 46 + nlen, xlen]
          if usize == 0xFFFFFFFF || csize == 0xFFFFFFFF || offset == 0xFFFFFFFF
            e = 0
            while e + 4 <= extra.length
              id, len = extra[e, 4].unpack("vv")
              if id == 1
                vals = extra[e + 4, len]
                k = 0
                (usize = vals[k, 8].unpack1("Q<"); k += 8) if usize == 0xFFFFFFFF
                (csize = vals[k, 8].unpack1("Q<"); k += 8) if csize == 0xFFFFFFFF
                (offset = vals[k, 8].unpack1("Q<"); k += 8) if offset == 0xFFFFFFFF
              end
              e += 4 + len
            end
          end
          list << [name, method, csize, offset]
          pos += 46 + nlen + xlen + clen
        end
        return list
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Start-up: right after PIF makes its sprite folders (and before its own flat
# import, which then finds nothing left to do); the counts are shown by PIF's
# usual load-screen messages
#-------------------------------------------------------------------------------
module KIF
  module SpriteImport
    class << self
      attr_accessor :result
    end

    def self.startup
      moved, conflicts, skipped, failed = run
      forget_lookups
      @result = [moved, conflicts, failed]
      if defined?(KIF.log) && (moved + conflicts.length + skipped + failed.length) > 0
        KIF.log("Sprite import: #{moved} moved, #{conflicts.length} already there, #{skipped} other files left, archives not opened: #{failed.inspect}")
      end
    rescue => e
      KIF.log("Sprite import failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    end
  end
end

alias kif_spriteimport_createCustomSpriteFolders createCustomSpriteFolders unless defined?(kif_spriteimport_createCustomSpriteFolders)
def createCustomSpriteFolders(*args)
  r = kif_spriteimport_createCustomSpriteFolders(*args)
  KIF::SpriteImport.startup
  return r
end

module KIF
  module SpriteImport
    module LoadScreen
      def pbStartLoadScreen(*args)
        res = KIF::SpriteImport.result
        if res
          KIF::SpriteImport.result = nil
          moved, conflicts, failed = res
          $game_temp.nb_imported_sprites = ($game_temp.nb_imported_sprites || 0) + moved
          $game_temp.unimportedSprites = (conflicts || {}).merge($game_temp.unimportedSprites || {})
          unless failed.empty?
            pbMessage(_INTL("These files in the Import Sprites folder couldn't be unpacked: {1}. Unpack them yourself and put the folder there instead.", failed.join(", ")))
          end
        end
        return super
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SpriteImport::LoadScreen) if defined?(PokemonLoadScreen)

#-------------------------------------------------------------------------------
# Single sprite files first
#-------------------------------------------------------------------------------
module KIF
  module SpriteImport
    module LocalFirst
      def load_sprite(pif_sprite, download_allowed = true)
        path = KIF::SpriteImport.local_for(pif_sprite)
        if path
          begin
            return KIF::SpriteImport.load_local(path)
          rescue => e
            KIF.log("Sprite file #{path} couldn't be read (#{e.class}: #{e.message})") if defined?(KIF.log)
          end
        end
        return super
      end
    end
  end
end

PIFSpriteExtracter.prepend(KIF::SpriteImport::LocalFirst) if defined?(PIFSpriteExtracter)
