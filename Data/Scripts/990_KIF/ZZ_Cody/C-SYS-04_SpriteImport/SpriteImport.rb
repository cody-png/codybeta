#===============================================================================
# C-SYS-04 – Sprite import (Cody, 2026-10-08)
#   1. Drop sprites into the "Import Sprites" folder (next to the game's .exe) in any
#      shape: loose .png files, a sprite pack folder, folders inside folders,
#      a .zip (or .rar / .7z, unpacked by Windows' own tar when it can). At
#      start-up every sprite found is MOVED to where the game reads it:
#        123.png, 123a.png          -> Graphics/CustomBattlers/local_sprites/BaseSprites/
#        12.34.png, 12.34b.png      -> Graphics/CustomBattlers/local_sprites/indexed/12/
#        144.145.146.png            -> Graphics/Battlers/special/
#        .../spritesheets_base/...  -> Graphics/CustomBattlers/spritesheets/spritesheets_base/
#        .../spritesheets_custom/...-> Graphics/CustomBattlers/spritesheets/spritesheets_custom/
#      An archive is unpacked into a work folder, its sprites moved the same
#      way, and the archive and whatever else it held (icons, outfits,
#      credits) are deleted: the installed sprites are the only copy kept.
#      Options > Others > "Imported Archives: Keep" moves the archive to an
#      "Imported archives" folder next to InfiniteFusion.exe instead (stored as the
#      KeepImportedArchives.krs marker, so it is known before anything loads).
#      PIF's own "Sprites to import" folder works the same way. A sprite
#      that is already installed, byte for byte, is just dropped; one that
#      differs is held in Import Sprites/_replace until the player answers
#      "keep yours or use the new ones?" on the load screen. A progress
#      screen shows while this runs (a full pack takes a few minutes).
#   2. PIF 6.8.2 reads base sprites only from sprite sheets, and picks a
#      fusion's sprite once and remembers it. Single sprite files (old packs,
#      KIF 0.20.x installs, the import above) are now read first, every time.
#===============================================================================
module KIF
  module SpriteImport
    DONE_DIR    = "_done"        # (older builds put archives here; left alone)
    WORK_DIR    = "_unpacking"
    HOLD_DIR    = "_replace"     # differing sprites waiting for the player's answer
    KEEP_DIR    = "Imported archives"
    KEEP_MARKER = "KeepImportedArchives.krs"

    class << self
      attr_writer :not_written
      def not_written; @not_written ||= 0; end
    end

    def self.keep_archives?
      return File.exist?(File.join(KIF.save_dir, KEEP_MARKER))
    rescue
      return false
    end

    def self.keep_archives=(on)
      path = File.join(KIF.save_dir, KEEP_MARKER)
      if on
        File.binwrite(path, "Sprite import: archives are moved to \"#{KEEP_DIR}\" instead of deleted\n") unless File.exist?(path)
      else
        File.delete(path) if File.exist?(path)
      end
    rescue
      nil
    end

    # An unpacked archive: deleted, or kept in "Imported archives"
    def self.finish_archive(path)
      if keep_archives?
        mkdir_p(KEEP_DIR)
        File.rename(path, file_after(KEEP_DIR, File.basename(path)))
      else
        File.delete(path)
      end
    rescue
      nil
    end
    ARCHIVES    = %w[.zip .rar .7z .tar .gz .tgz]
    BASE_DIR    = "Graphics/CustomBattlers/local_sprites/BaseSprites"
    INDEXED_DIR = "Graphics/CustomBattlers/local_sprites/indexed"
    SPECIAL_DIR = "Graphics/Battlers/special"
    SHEETS_DIR  = "Graphics/CustomBattlers/spritesheets"
    PIF_IMPORT  = "Graphics/CustomBattlers/Sprites to import"

    module_function

    # "Import Sprites" next to the game's .exe (KIF::Paths.root)
    def import_dir
      return KIF::Paths.import_sprites
    end

    def import_dirs
      list = [import_dir]
      list << PIF_IMPORT.chomp("/") if Dir.exist?(PIF_IMPORT)
      return list
    end

    # Keep the window alive during a long import, with a progress screen
    def tick
      @last_tick ||= Time.now
      return if Time.now - @last_tick < 0.25
      @last_tick = Time.now
      draw_status
      Graphics.update rescue nil
    end

    def status(line, count = nil)
      @status = [line, count]
      @last_tick = Time.now
      draw_status
      Graphics.update rescue nil
    end

    # one more file done (the count on the progress screen)
    def bump
      @status[1] += 1 if @status && @status[1]
    end

    def draw_status
      return unless @status
      unless @status_sprite
        vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        vp.z = 999_999
        @status_sprite = Sprite.new(vp)
        @status_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      end
      b = @status_sprite.bitmap
      b.fill_rect(0, 0, b.width, b.height, Color.new(16, 16, 24))
      b.font.size = 26
      b.font.color = Color.new(248, 248, 248)
      mid = b.height / 2
      b.draw_text(0, mid - 60, b.width, 32, "Importing sprites", 1)
      b.font.size = 22
      line, count = @status
      line += " #{count.to_s.reverse.scan(/\d{1,3}/).join(',').reverse} files" if count
      b.draw_text(0, mid - 16, b.width, 28, line, 1)
      b.font.color = Color.new(160, 160, 176)
      b.draw_text(0, mid + 24, b.width, 28, "A full sprite pack takes a few minutes. Only once per pack.", 1)
      b.draw_text(0, mid + 52, b.width, 28, keep_archives? ? "The archive will be kept in \"#{KEEP_DIR}\"." : "The archive is deleted after unpacking (Options > Others to keep it).", 1)
    rescue
      @status = nil
    end

    def hide_status
      if @status_sprite
        vp = @status_sprite.viewport
        @status_sprite.bitmap.dispose rescue nil
        @status_sprite.dispose rescue nil
        vp.dispose rescue nil
        Graphics.update rescue nil
      end
      @status_sprite = nil
      @status = nil
    end

    def same_file?(a, b)
      return false unless File.size(a) == File.size(b)
      return File.binread(a) == File.binread(b)
    rescue
      return false
    end

    EGGS_DIR = "Graphics/Battlers/Eggs"
    # Folders whose pictures are not battle sprites, whatever they are named
    # (the full sprite pack has eggs, player outfits, icons, tilesets... all
    # numbered like sprites)
    NOT_SPRITES = /\A(player|characters?|misc|pictures?|icons?|assets?|tilesets?|overworld|footprints?|trainers?|items?|ui|backups?)\z|assets|96x96/i

    # Where a sprite goes, from its name and the folders it sits in; nil = not
    # a sprite we know. A "4.7b.png" fusion is taken from any folder that isn't
    # a NOT_SPRITES one; a bare "4a.png" counts as a base sprite only in a
    # BaseSprites folder or loose near the top (where a player drops it) -
    # eggs, icons and outfits are numbered the same way.
    def destination(path)
      name = File.basename(path)
      return nil unless name =~ /\.png\z/i
      parts = path.tr("\\", "/").split("/").reject(&:empty?)
      folders = parts[0..-2].map(&:downcase)
      folders = folders[2..-1] if folders[0] == WORK_DIR.downcase   # inside an unpacked archive
      folders ||= []
      return nil if folders.any? { |f| f =~ NOT_SPRITES && f != "basesprites" }
      if (i = folders.index("spritesheets_base"))
        return File.join(SHEETS_DIR, "spritesheets_base", *parts[-(folders.length - i)..-1])
      end
      if (i = folders.index("spritesheets_custom"))
        return File.join(SHEETS_DIR, "spritesheets_custom", *parts[-(folders.length - i)..-1])
      end
      parent = folders.last
      return File.join(EGGS_DIR, name) if parent == "eggs" && name =~ /\A\d+\.png\z/i
      case name
      when /\A\d+\.\d+\.\d+[a-z]*\.png\z/i
        return File.join(SPECIAL_DIR, name)
      when /\A(\d+)\.(\d+)[a-z]*\.png\z/i
        return File.join(INDEXED_DIR, $1, name)
      when /\A\d+[a-z]*\.png\z/i
        return File.join(BASE_DIR, name) if parent == "basesprites"
        return File.join(BASE_DIR, name) if folders.length <= 1 && parent !~ /\A(eggs|triples|other)\z/
        return nil
      end
      return nil
    end

    def remove_tree(dir)
      return unless Dir.exist?(dir)
      Dir.children(dir).each do |c|
        path = File.join(dir, c)
        File.directory?(path) ? remove_tree(path) : delete_file(path)
        tick
      end
      Dir.rmdir(dir) rescue nil
    end

    # File.delete, and for a path past Windows' 260-character limit the same
    # through the \\?\ long-path form
    def delete_file(path)
      File.delete(path)
    rescue SystemCallError
      begin
        File.delete("\\\\?\\" + File.expand_path(path).tr("/", "\\")) if File::ALT_SEPARATOR
      rescue SystemCallError
        nil
      end
    end

    def mkdir_p(dir)
      return if dir.nil? || dir.empty?
      @dirs_made ||= {}
      return if @dirs_made[dir]
      unless Dir.exist?(dir)
        mkdir_p(File.dirname(dir))
        Dir.mkdir(dir) rescue nil
      end
      @dirs_made[dir] = true
    end

    #---------------------------------------------------------------------------
    # Placing one sprite (a file on disk, or a zip entry still in memory)
    #   new          -> written/moved to where the game reads it
    #   same bytes   -> dropped (already installed as it is)
    #   other bytes  -> held in Import Sprites/_replace for the player's answer,
    #                   except eggs: the game's own egg sprites are newer than
    #                   the ones in sprite packs, so a differing egg is dropped
    #   second copy  -> left (the first one of a name wins)
    #---------------------------------------------------------------------------
    def reset_tally
      @tally = { moved: 0, same: 0, eggs: 0, skipped: 0, conflicts: {}, placed: {} }
      @dirs_made = {}
    end

    def tally; @tally ||= (reset_tally; @tally); end

    def egg_dest?(dest)
      return dest.tr("\\", "/").downcase.start_with?(EGGS_DIR.downcase + "/")
    end

    def place(dest, held, data: nil, from: nil)
      t = tally
      if t[:placed][dest]
        t[:skipped] += 1
        return
      end
      if File.exist?(dest)
        if data ? (File.size(dest) == data.bytesize && File.binread(dest) == data) : same_file?(from, dest)
          (File.delete(from) rescue nil) if from
          t[:same] += 1
          return
        end
        if egg_dest?(dest)
          (File.delete(from) rescue nil) if from
          t[:eggs] += 1
          return
        end
        unless from && from == held
          mkdir_p(File.dirname(held))
          data ? File.binwrite(held, data) : File.rename(from, held)
        end
        t[:conflicts][held] = dest
        return
      end
      mkdir_p(File.dirname(dest))
      data ? File.binwrite(dest, data) : File.rename(from, dest)
      t[:placed][dest] = true
      t[:moved] += 1
      bump
    rescue SystemCallError, IOError
      t[:skipped] += 1
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
      return unless Dir.exist?(dir)
      Dir.children(dir).each do |c|
        path = File.join(dir, c)
        next unless File.directory?(path)
        next if top && c == DONE_DIR
        prune(path, false)
      end
      Dir.rmdir(dir) if !top && Dir.children(dir).reject { |c| c == ".DS_Store" || c == "desktop.ini" || c == "Thumbs.db" }.empty? && (Dir.children(dir).each { |c| File.delete(File.join(dir, c)) rescue nil }; true)
    rescue
    end

    #---------------------------------------------------------------------------
    # Archives: the built-in .zip reader, else Windows' tar (bsdtar)
    #---------------------------------------------------------------------------
    def unpack(archive, into, root = nil)
      mkdir_p(into)
      # .zip: read here (no console window), each sprite written straight to
      # where the game reads it; anything else, or a .zip this reader can't
      # handle: Windows' tar into the work folder, then the moving pass
      return true if archive =~ /\.zip\z/i && Zip.extract(archive, into, direct: root)
      remove_tree(into)   # whatever the built-in reader got through before it gave up
      mkdir_p(into)
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
      mkdir_p(import_dir)
      failed = []
      self.not_written = 0; @leftovers = 0
      reset_tally
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
            status("Unpacking #{File.basename(path)}...", 0)
            work = file_after(File.join(root, WORK_DIR), File.basename(path, ".*"))
            if unpack(path, work, root)
              finish_archive(path)   # unpacked: deleted (or kept, if the player asked)
            else
              failed << path
            end
            tick
          end
          break unless found
        end
        status("Moving sprites into place...", 0) if Dir.exist?(File.join(root, WORK_DIR))
        hold_root = File.join(root, HOLD_DIR)
        each_file(root, false) do |path|
          next if path.include?("/#{DONE_DIR}/")
          dest = destination(path.sub(root, ""))
          unless dest
            tally[:skipped] += 1 unless ARCHIVES.include?(File.extname(path).downcase) || path =~ /\.txt\z/i || File.basename(path).start_with?(".")
            next
          end
          # held outside the work folder (deleted below) until the player answers
          held = path.start_with?(hold_root + "/") ? path :
                 File.join(hold_root, path.sub(root, "").sub(%r{\A/+}, "").sub(%r{\A#{WORK_DIR}/}, ""))
          place(dest, held, from: path)
          tick
        end
        # what an archive left (icons, outfits, credits, assets) is not kept:
        # the game has no use for it and nobody wants a second copy of a pack
        work = File.join(root, WORK_DIR)
        if Dir.exist?(work)
          leftovers = 0
          each_file(work, false) { |_f| leftovers += 1 }
          remove_tree(work)
          @leftovers += leftovers
        end
        prune(root)
      end
      t = tally
      @same = t[:same]
      @eggs = t[:eggs]
      # archive files that were never written (not sprites) count as discarded too
      return [t[:moved], t[:conflicts], t[:skipped], failed.map { |f| File.basename(f) }, @leftovers.to_i + not_written]
    ensure
      hide_status
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

      # direct: the import folder the archive came from. Then each sprite goes
      # straight to where the game reads it (no copy in a work folder to move
      # afterwards); archives inside it are still written to `into`.
      def extract(archive, into, direct: nil)
        require "zlib"
        File.open(archive, "rb") do |f|
          entries(f).each do |name, method, csize, offset|
            next if name.end_with?("/")
            safe = name.tr("\\", "/").split("/").reject { |p| p.empty? || p == "." || p == ".." }
            next if safe.empty?
            # only sprites and archives are written: the rest (credits, icons,
            # outfits, tilesets) would be deleted anyway, and some of it has
            # names past Windows' 260-character path limit
            rel = File.join(KIF::SpriteImport::WORK_DIR, "x", *safe)
            nested = KIF::SpriteImport::ARCHIVES.include?(File.extname(rel).downcase)
            dest = nested ? nil : KIF::SpriteImport.destination(rel)
            unless nested || dest
              KIF::SpriteImport.not_written += 1
              next
            end
            f.seek(offset)
            h = f.read(30)
            next unless h && h[0, 4] == "PK\x03\x04".b
            nlen, xlen = h[26, 4].unpack("vv")
            f.seek(offset + 30 + nlen + xlen)
            data = f.read(csize)
            data = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) if method == 8
            next unless method == 0 || method == 8
            if direct && dest
              held = File.join(direct, KIF::SpriteImport::HOLD_DIR, File.basename(into), *safe)
              KIF::SpriteImport.place(dest, held, data: data)
              KIF::SpriteImport.tick
              next
            end
            out = File.join(into, *safe)
            begin
              KIF::SpriteImport.mkdir_p(File.dirname(out))
              File.binwrite(out, data)
            rescue SystemCallError, IOError => e
              # one file that can't be written (path too long, odd name)
              # doesn't stop the rest of the pack
              KIF::SpriteImport.not_written += 1
              KIF.log("Sprite import: skipped #{safe.last} (#{e.class})") if defined?(KIF.log)
              next
            end
            KIF::SpriteImport.bump
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
          flags = cd[pos + 8, 2].unpack1("v")
          name = cd[pos + 46, nlen].force_encoding("UTF-8")
          # names without the UTF-8 flag are old DOS code page 437
          name = name.force_encoding("IBM437").encode("UTF-8") if flags & 0x800 == 0 && !name.valid_encoding?
          name = name.scrub("_") unless name.valid_encoding?
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

    # Anything waiting in the import folders (the READ ME doesn't count)?
    def self.work_waiting?
      return import_dirs.any? do |d|
        Dir.exist?(d) && Dir.children(d).any? { |c| c !~ /\.txt\z/i && c != WORK_DIR && !c.start_with?(".") }
      end
    rescue
      return false
    end

    def self.startup
      # PIF freezes the screen (Graphics.freeze) just before this runs, so
      # nothing drawn shows until its title transition: thaw it while there
      # is an import to show, and freeze it again for PIF afterwards
      thaw = work_waiting? && defined?(Graphics) && Graphics.respond_to?(:transition)
      (Graphics.transition(0) rescue nil) if thaw
      moved, conflicts, skipped, failed, leftovers =
        defined?(KIF::FrameRate) && KIF::FrameRate.respond_to?(:hold) ? KIF::FrameRate.hold { run } : run
      forget_lookups
      @result = [moved, conflicts, failed]
      if defined?(KIF.log) && (moved + conflicts.length + skipped + failed.length + leftovers) > 0
        KIF.log("Sprite import: #{moved} moved, #{@same.to_i} already installed (dropped), #{@eggs.to_i} older egg sprites (dropped, the game's are kept), #{conflicts.length} differ from installed ones (held for the player), #{skipped} not sprites or duplicates, #{leftovers} other files from archives discarded, archives not opened: #{failed.inspect}")
      end
    rescue => e
      KIF.log("Sprite import failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    ensure
      (Graphics.freeze rescue nil) if thaw
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
          moved += KIF::SpriteImport.ask_replace(conflicts || {})
          $game_temp.nb_imported_sprites = ($game_temp.nb_imported_sprites || 0) + moved
          unless failed.empty?
            pbMessage(_INTL("These files in the Import Sprites folder couldn't be unpacked: {1}. Unpack them yourself and put the folder there instead.", failed.join(", ")))
          end
        end
        return super
      end
    end
  end
end

module KIF
  module SpriteImport
    # Sprites that differ from installed ones: the player picks, once for all.
    # Returns how many were installed.
    def self.ask_replace(conflicts)
      return 0 if conflicts.empty?
      conflicts = conflicts.select { |held, _| File.exist?(held) }
      return 0 if conflicts.empty?
      n = conflicts.length
      pbMessage(_INTL("{1} imported sprites are different from sprites you already have.", n))
      cmd = pbMessage(_INTL("Which ones should the game use?"),
                      [_INTL("Keep the ones I have"), _INTL("Use the new ones")], 0)
      done = 0
      conflicts.each do |held, dest|
        begin
          if cmd == 1
            File.delete(dest) if File.exist?(dest)
            File.rename(held, dest)
            done += 1
          else
            File.delete(held)
          end
        rescue => e
          KIF.log("Sprite import: #{File.basename(held)} (#{e.class}: #{e.message})") if defined?(KIF.log)
        end
      end
      import_dirs.each { |d| prune(d) }   # empty _replace folders go
      KIF.log("Sprite import: #{n} differing sprites - #{cmd == 1 ? "#{done} new ones used" : 'kept the installed ones'}") if defined?(KIF.log)
      return done
    rescue => e
      KIF.log("Sprite import: replace question failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      return 0
    end
  end
end

PokemonLoadScreen.prepend(KIF::SpriteImport::LoadScreen) if defined?(PokemonLoadScreen)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Imported Archives"), [_INTL("Delete"), _INTL("Keep")],
                 proc { KIF::SpriteImport.keep_archives? ? 1 : 0 },
                 proc { |value| KIF::SpriteImport.keep_archives = (value == 1) },
                 [_INTL("A sprite pack .zip/.rar is deleted once its sprites are installed"),
                  _INTL("A sprite pack .zip/.rar is moved to the Imported archives folder")])
} if defined?(KIF::Options)

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

#-------------------------------------------------------------------------------
# Pokédex sprites page: a sprite that is both on a sheet and a file was listed
# twice (once with its artist, once as "Imported sprite"). The file copy is
# listed only for letters the sheets don't have.
#-------------------------------------------------------------------------------
module KIF
  module SpriteImport
    module DexAlts
      def pbGetAvailableAlts(dex_number, includeAutogens = false)
        list = super
        return list unless list.is_a?(Array)
        letters = {}
        list.each { |a| letters[a.to_s] = true if a.is_a?(String) && !a.start_with?("local_") }
        return list.reject do |a|
          next false unless a.is_a?(String) && a.start_with?("local_")
          base = File.basename(a.split("_", 2)[1].to_s, ".*")
          letter = base =~ /\A\d+(?:\.\d+)?([a-z]*)\z/i ? $1.downcase : nil
          letter && letters[letter]
        end
      rescue => e
        KIF.log("Dex sprite list tidy failed (#{e.class}: #{e.message})") if defined?(KIF.log)
        return list
      end
    end
  end
end

PokedexUtils.prepend(KIF::SpriteImport::DexAlts) if defined?(PokedexUtils)
