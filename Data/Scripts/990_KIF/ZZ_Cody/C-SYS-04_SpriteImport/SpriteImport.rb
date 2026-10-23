#===============================================================================
# C-SYS-04 – Sprite import (2026-10-08)
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
#      KIF 0.20.x installs, the import above) are now read first, every time;
#      a decoded file is kept (load_local; Options > Others > Sprite File
#      Cache: Permanent / Per Session / Off) so a Pokémon's sprite is decoded
#      once, not on every PC/party/battle draw.
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
      extra = KIF::Paths.extra_drop_dir("Import Sprites")   # read-only game folder (phones)
      list << extra if extra
      list << PIF_IMPORT.chomp("/") if Dir.exist?(PIF_IMPORT)
      return list
    end

    # Keep the window alive during a long import, with a progress screen
    def tick
      @last_tick ||= Time.now
      return if Time.now - @last_tick < (@tick_every || 0.25)
      @last_tick = Time.now
      draw_status
      Graphics.update rescue nil
    end

    def status(line, count = nil)
      @status = [line, count]
      @last_tick = Time.now
      # a redraw costs a phone more than the files written between two of them
      @tick_every = KIF.respond_to?(:mobile?) && KIF.mobile? ? 1.0 : 0.25
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
      b.draw_text(0, mid + 52, b.width, 28, keep_archives? ? "The archive will be kept in \"#{KEEP_DIR}\"." : "The archive is deleted after unpacking (Options > System > Imported Archives to keep it).", 1)
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
      dest = game_destination(path)
      return dest if dest.nil? || KIF::Paths.game_writable?
      # read-only game folder (phones): single sprite files go to the same
      # folders in the save folder, where local_for looks too; sheets, triple
      # fusions and eggs are read by PIF from the game folder only
      return nil unless dest.start_with?(BASE_DIR + "/", INDEXED_DIR + "/")
      return KIF::Paths.writable(dest)
    end

    def game_destination(path)
      name = File.basename(path)
      return nil unless name =~ /\.png\z/i
      parts = path.tr("\\", "/").split("/").reject(&:empty?)
      folders = parts[0..-2].map(&:downcase)
      folders = folders[2..-1] if folders[0] == WORK_DIR.downcase   # inside an unpacked archive
      folders = folders[2..-1] if folders && folders[0] == HOLD_DIR.downcase   # held for the replace question
      folders ||= []
      return nil if folders.any? { |f| f =~ NOT_SPRITES && f != "basesprites" }
      if (i = folders.index("spritesheets_base"))
        return File.join(SHEETS_DIR, "spritesheets_base", *parts[-(folders.length - i)..-1])
      end
      if (i = folders.index("spritesheets_custom"))
        return File.join(SHEETS_DIR, "spritesheets_custom", *parts[-(folders.length - i)..-1])
      end
      parent = folders.last
      name = name.downcase   # the game asks for "12.34b.png": phones' storage minds the case
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
        if File.symlink?(path)   # a link from an archive: remove the link, never what it points to
          (File.delete(path) rescue (Dir.rmdir(path) rescue nil))
        elsif File.directory?(path)
          remove_tree(path)
        else
          delete_file(path)
        end
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
      fresh = !Dir.exist?(dir)
      (KIF.mkdir_p(dir) rescue nil) if fresh
      # :fresh = made this run, nothing in it to look for
      @dirs_made[dir] = (fresh ? :fresh : true) if Dir.exist?(dir)   # a folder that couldn't be made is tried again
    end

    # The size of a file already at dest, or nil. One folder listing instead of
    # a File.exist? per sprite (a stat costs ~60 ms on phone storage); a
    # *.kiftmp found there is a write a closed game cut short: deleted.
    def existing_size(dest)
      dir = File.dirname(dest)
      if @names_dir != dir
        @dirs_made[@names_dir] = true if @names_dir && @dirs_made[@names_dir] == :fresh   # has our files now
        @names_dir = dir
        @names = {}
        unless @dirs_made[dir] == :fresh
          Dir.children(dir).each do |c|
            c.end_with?(".kiftmp") ? delete_file(File.join(dir, c)) : @names[c.downcase] = true
          end
        end
      end
      return nil unless @names[File.basename(dest).downcase]   # downcased: Windows names ignore case
      return File.size(dest)
    rescue SystemCallError
      return nil
    end

    # Written to <path>.kiftmp, then renamed: a game closed mid-write never
    # leaves a cut-off sprite (it would look "different" next time)
    def write_new(path, data)
      tmp = path + ".kiftmp"
      File.open(tmp, "wb") { |f| f.write(data) }   # "wb": a leftover .kiftmp is overwritten
      File.rename(tmp, path)
    rescue SystemCallError, IOError
      delete_file(tmp) if tmp
      raise
    end

    def timed(key)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ret = yield
      s = ((@timing ||= {})[key] ||= [0.0, 0])
      s[0] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      s[1] += 1
      return ret
    end

    def log_timing(i)
      return unless @timing && KIF.respond_to?(:verbose)
      KIF.verbose("Sprite import: entry #{i}, average " + @timing.map { |k, (s, n)| "#{k} #{(s * 1000 / [n, 1].max).round(2)} ms" }.join(", "))
    end

    def info; @info ||= {}; end

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
      @tally = { moved: 0, same: 0, eggs: 0, skipped: 0, errors: 0, odd: 0, conflicts: {}, placed: {} }
      @dirs_made = {}
      @names_dir = nil
    end

    # An installed file against a zip entry: a different size is different;
    # the same size, the entry's CRC32 against the file's (no inflating)
    def same_bytes?(dest, old_size, data, size, crc)
      size ||= data.bytesize
      return false unless old_size == size
      cur = File.binread(dest)
      return crc ? Zlib.crc32(cur) == crc : cur == data
    end

    def tally; @tally ||= (reset_tally; @tally); end

    def egg_dest?(dest)
      return dest.tr("\\", "/").downcase.start_with?(EGGS_DIR.downcase + "/")
    end

    # data: the bytes, or a Proc that reads them (a zip entry is only inflated
    # when it is written); size/crc: the zip entry's, for the compare
    def place(dest, held, data: nil, from: nil, size: nil, crc: nil)
      t = tally
      if t[:placed][dest]
        t[:skipped] += 1
        return
      end
      bytes = -> { data.is_a?(Proc) ? (data = data.call) : data }
      mkdir_p(File.dirname(dest))
      if (old = timed(:exist) { existing_size(dest) })
        if from ? same_file?(from, dest) : same_bytes?(dest, old, data, size, crc)
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
          data ? write_new(held, bytes.call) : File.rename(from, held)
        end
        t[:conflicts][held] = dest
        return
      end
      data ? timed(:write) { write_new(dest, bytes.call) } : File.rename(from, dest)
      @names[File.basename(dest).downcase] = true if @names_dir == File.dirname(dest)
      t[:placed][dest] = true
      t[:moved] += 1
      bump
    rescue SystemCallError, IOError
      t[:errors] += 1   # a sprite that couldn't be written (disk full, locked): its archive is kept
    end

    # Every file under a folder (skipping our own _done / _unpacking, links -
    # an archive can hold a link to a folder elsewhere on the PC - and tar
    # output still being written, "*.part")
    def each_file(dir, top = true, &block)
      Dir.children(dir).sort.each do |c|
        path = File.join(dir, c)
        next if File.symlink?(path)
        if File.directory?(path)
          next if c.end_with?(".part")
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
      @info = { reader: "zip", from: 0, entries: 0 }
      @timing = {}
      if archive =~ /\.zip\z/i
        r = Zip.extract(archive, into, direct: root)
        # nil: it failed after sprites were written - tar would write them all again
        return r unless r == false
      end
      return false if KIF.respond_to?(:mobile?) && KIF.mobile?   # no tar on phones
      @info[:reader] = "tar"
      remove_tree(into)   # whatever the built-in reader got through before it gave up
      # tar writes into "<work>.part", renamed when it's done: a game closed
      # while tar ran leaves no half-written sprites to install next time
      part = into + ".part"
      remove_tree(part)
      mkdir_p(part)
      begin
        ok = system("tar", "-xf", archive, "-C", part) ? true : false
        File.rename(part, into) if ok
        return ok
      rescue
        return false
      end
    end

    # sprites placed (or found already there) so far this import
    def sprites_so_far
      t = tally
      return t[:moved] + t[:same] + t[:eggs] + t[:skipped] + t[:conflicts].length
    end

    # Did an unpacked archive bring anything the game uses? A pack whose
    # folders aren't known (or not sprites at all) gave nothing: it is kept
    # and reported, not deleted.
    def brought_sprites?(before, work, root)
      return true if sprites_so_far > before
      return false unless Dir.exist?(work)
      each_file(work, false) do |f|
        return true if ARCHIVES.include?(File.extname(f).downcase) || destination(f.sub(root, ""))
      end
      return false
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
        Dir.glob(File.join(root, WORK_DIR, "*.part")).each { |d| remove_tree(d) }   # tar cut short last time
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
            errors = tally[:errors]
            before = sprites_so_far
            t = tally
            was = [t[:moved], t[:same] + t[:eggs], t[:conflicts].length, t[:odd]]
            size = (File.size(path) rescue 0)
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            ok = unpack(path, work, root)
            # a resumed run placed the first part of the pack last time
            if ok && tally[:errors] == errors && (info[:from].to_i > 0 || brought_sprites?(before, work, root))
              finish_archive(path)   # unpacked: deleted (or kept, if the player asked)
            else
              failed << path
            end
            delete_file(path + Zip::PROGRESS) if File.exist?(path + Zip::PROGRESS)
            secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            w, s, r, o = [t[:moved], t[:same] + t[:eggs], t[:conflicts].length, t[:odd]].zip(was).map { |a, b| a - b }
            n = info[:entries].to_i - info[:from].to_i
            n = w + s + r if info[:reader] == "tar"
            KIF.log("Sprite import: #{File.basename(path)} (#{(size / 1048576.0).round(1)} MB, #{info[:entries]} entries): " \
                    "#{w} written, #{s} same, #{r} replaced (held), #{o} odd entries skipped, #{secs.round(1)} s, " \
                    "#{(n / [secs, 0.001].max).round} files/s, reader #{info[:reader]}" \
                    "#{info[:from].to_i > 0 ? ", resumed from entry #{info[:from]}" : ''}#{ok ? '' : ', not finished'}") if defined?(KIF.log)
            tick
          end
          break unless found
        end
        status("Moving sprites into place...", 0) if Dir.exist?(File.join(root, WORK_DIR))
        hold_root = File.join(root, HOLD_DIR)
        each_file(root, false) do |path|
          next if path.include?("/#{DONE_DIR}/")
          next delete_file(path) if path.end_with?(".kiftmp", Zip::PROGRESS)   # cut-short writes, a removed pack's progress
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
          # sprites that couldn't be moved stay for the next start
          if tally[:errors] == 0
            # an archive found inside another that couldn't be unpacked goes
            # back to the Import Sprites folder (the player is told to unpack it)
            failed.map! do |f|
              next f unless f.start_with?(work + "/") && File.file?(f)
              dst = file_after(root, File.basename(f))
              begin
                File.rename(f, dst)
              rescue SystemCallError
                next f
              end
              dst
            end
            remove_tree(work)
            @leftovers += leftovers
          end
        end
        prune(root)
      end
      t = tally
      @same = t[:same]
      @eggs = t[:eggs]
      # archive files that were never written (not sprites) count as discarded too
      return [t[:moved], t[:conflicts], t[:skipped] + t[:errors], failed.map { |f| File.basename(f) }, @leftovers.to_i + not_written]
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
      unless @exists.key?(path)
        # a read-only game folder: sprites imported into the save folder first
        @exists[path] = [KIF::Paths.writable(path), path].uniq.find { |p| File.file?(p) }
      end
      return @exists[path]
    end

    def forget_lookups
      @exists = {}
      clear_bitmaps
    end

    # Decoded sprite files, by path (the game-size bitmap). PIF keeps the
    # sprites it cuts from its sheets in memory (SpritesBitmapCache) and only
    # decodes a sheet once; the file route had no such cache, so every PC
    # cursor move, party draw or battle sprite decoded the .png again. Most
    # decode in a millisecond or two, but some files from sprite packs (ones
    # with sRGB/eXIf/iTXt metadata blocks) take 40 ms and more each time,
    # which showed as a short hang on those Pokémon (0.21.15).
    # On a hit the caller gets a private copy, as before.
    #
    # Options > Others > "Sprite File Cache" (like Shiny Cache):
    #   Permanent   - memory + a copy of the decoded pixels on disk
    #                 (Cache/KIFSprites/<name>.kbm: width, height, deflated
    #                 RGBA from Bitmap#raw_data), read back with raw_data= -
    #                 much faster than the slow .png decodes, so even the first
    #                 draw of a session is quick. A file that changed (size or
    #                 time) is decoded again and its copy replaced.
    #   Per Session - memory only
    #   Off         - decode the file on every draw (as before 0.21.26)
    BITMAP_CACHE_LIMIT = 120
    BITMAP_CACHE_LIMIT_MOBILE = 30   # ~10 MB of 288x288 bitmaps instead of ~39

    # read each time: $PokemonSystem.on_mobile can be set after this loads
    def bitmap_cache_limit
      return KIF.respond_to?(:mobile?) && KIF.mobile? ? BITMAP_CACHE_LIMIT_MOBILE : BITMAP_CACHE_LIMIT
    end
    DISK_CACHE_DIR = "Cache/KIFSprites"   # in the game folder, or the save folder when that can't be written

    def disk_cache_dir
      return KIF::Paths.writable(DISK_CACHE_DIR)
    end
    require "zlib"
    @bitmaps = {}

    def cache_mode
      return 1 unless $PokemonSystem && $PokemonSystem.respond_to?(:sprite_file_cache)
      return $PokemonSystem.sprite_file_cache.to_i   # 0 Permanent, 1 Per Session, 2 Off
    end

    def clear_bitmaps
      (@bitmaps || {}).each_value do |b|
        begin
          b.dispose if b && !b.disposed?
        rescue StandardError
          nil
        end
      end
      @bitmaps = {}
    end

    def cached_bitmaps
      @bitmaps ||= {}
    end

    def private_copy(src)
      copy = Bitmap.new(src.width, src.height)
      copy.blt(0, 0, src, Rect.new(0, 0, src.width, src.height))
      return copy
    end

    def keep_bitmap(path, src)
      cache = cached_bitmaps
      cache.delete(path)
      while cache.length >= bitmap_cache_limit
        old_path, old = cache.first
        cache.delete(old_path)
        begin
          old.dispose if old && !old.disposed?
        rescue StandardError
          nil
        end
      end
      cache[path] = private_copy(src)
    end

    # Cache/KIFSprites/<sprite name>.kbm, valid for one size + mtime of the file
    def disk_cache_path(path)
      return "#{disk_cache_dir}/#{File.basename(path, '.png')}.kbm"
    end

    def disk_stamp(path)
      st = File.stat(path)
      return [st.size, st.mtime.to_i]
    rescue SystemCallError
      return nil
    end

    # KBM1 files can hold a whole animation strip (cached before strips were
    # cut to their first frame, 0.21.54); KBM2 makes them rebuild once
    DISK_CACHE_TAG = "KBM2"

    def read_disk_cache(path)
      return nil unless Bitmap.method_defined?(:raw_data=)
      cp = disk_cache_path(path)
      return nil unless File.file?(cp)
      stamp = disk_stamp(path)
      return nil unless stamp
      data = File.binread(cp)
      return nil if data.length < 24 || data[0, 4] != DISK_CACHE_TAG
      size, mtime, w, h = data[4, 16].unpack("NNNN")
      return nil unless [size, mtime] == stamp && w > 0 && h > 0 && w <= 2048 && h <= 2048
      raw = Zlib::Inflate.inflate(data[20..-1])
      return nil unless raw.length == w * h * 4
      bmp = Bitmap.new(w, h)
      bmp.raw_data = raw
      return bmp
    rescue StandardError, Zlib::Error
      return nil
    end

    def write_disk_cache(path, bmp)
      return unless bmp.respond_to?(:raw_data)
      stamp = disk_stamp(path)
      return unless stamp
      raw = bmp.raw_data
      return unless raw && raw.length == bmp.width * bmp.height * 4
      mkdir_p(disk_cache_dir) unless File.directory?(disk_cache_dir)
      @disk_trimmed ||= (KIF.trim_cache_dir(disk_cache_dir, KIF.mobile? ? 2_000 : 20_000); true)   # ~150 MB (phones ~15 MB)
      cp = disk_cache_path(path)
      tmp = cp + ".tmp"
      File.binwrite(tmp, DISK_CACHE_TAG + [stamp[0], stamp[1], bmp.width, bmp.height].pack("NNNN") + Zlib::Deflate.deflate(raw, Zlib::BEST_SPEED))
      File.delete(cp) if File.exist?(cp)
      File.rename(tmp, cp)
    rescue StandardError, Zlib::Error => e
      KIF.log("Sprite cache: #{File.basename(path)} not written (#{e.class}: #{e.message})") if defined?(KIF.log)
      @disk_failures = @disk_failures.to_i + 1
    end

    # An animated sprite (its frames side by side, each as wide as it is tall,
    # e.g. 191.208 is 48 frames of 288) is drawn as its first frame; PIF
    # only cuts frames for files named "[n]...", so it showed the whole strip.
    # In battle, C-BATTLE-04 asks for the whole strip (keep_strips) and
    # plays it.
    MAX_STRIP_FRAMES = 48   # 288 px frames: 13,824 px wide, under the engine's 16,384 limit

    def keep_strips?; return @keep_strips ? true : false; end

    def keep_strips
      old = @keep_strips
      @keep_strips = true
      return yield
    ensure
      @keep_strips = old
    end

    # true when the file's PNG header says it's a strip (no decoding)
    def strip_file?(path)
      @strip_file ||= {}
      return @strip_file[path] if @strip_file.has_key?(path)
      head = (File.binread(path, 24) rescue nil)
      ok = false
      if head && head.bytesize == 24 && head[0, 8] == "\x89PNG\r\n\x1A\n".b
        w, h = head[16, 8].unpack("NN")
        ok = h > 0 && w > h && w % h == 0
      end
      return @strip_file[path] = ok
    end

    # the whole strip, at most MAX_STRIP_FRAMES frames, scaled like a sprite
    def load_strip(path)
      bmp = Bitmap.new(path)
      h = bmp.height
      n = [bmp.width / h, MAX_STRIP_FRAMES].min
      if n * h < bmp.width
        cut = Bitmap.new(n * h, h)
        cut.blt(0, 0, bmp, Rect.new(0, 0, n * h, h))
        bmp.dispose
        bmp = cut
      end
      anim = AnimatedBitmap.from_bitmap(bmp)
      anim.scale_bitmap(3) if h < 150   # 96 px frames: game size is 288
      return anim
    end

    def first_frame(bmp)
      w = bmp.width
      h = bmp.height
      return bmp unless h > 0 && w > h && w % h == 0
      frame = Bitmap.new(h, h)
      frame.blt(0, 0, bmp, Rect.new(0, 0, h, h))
      bmp.dispose
      return frame
    end

    def load_local(path)
      # a private copy: PIF's shiny code recolours the bitmap it gets in place,
      # and RPG::Cache would hand the same one to the next Pokémon
      return load_strip(path) if keep_strips? && strip_file?(path)   # not cached: battle only
      mode = cache_mode
      if mode != 2
        kept = cached_bitmaps[path]
        if kept && !kept.disposed?
          cached_bitmaps.delete(path)
          cached_bitmaps[path] = kept   # most recently used last
          return AnimatedBitmap.from_bitmap(private_copy(kept))
        end
        if mode == 0 && (disk = read_disk_cache(path))
          keep_bitmap(path, disk)
          return AnimatedBitmap.from_bitmap(disk)
        end
      end
      bmp = AnimatedBitmap.from_bitmap(first_frame(Bitmap.new(path)))
      bmp.scale_bitmap(3) if bmp.bitmap.width < 150   # a 96 px sprite: game size is 288
      if mode != 2
        keep_bitmap(path, bmp.bitmap)
        write_disk_cache(path, bmp.bitmap) if mode == 0 && @disk_failures.to_i < 20
      end
      return bmp
    end

    #---------------------------------------------------------------------------
    # A small .zip reader (stored and deflated entries, zip64 included)
    #---------------------------------------------------------------------------
    module Zip
      module_function

      MAX_ENTRY = 64 * 1024 * 1024

      # direct: the import folder the archive came from. Then each sprite goes
      # straight to where the game reads it (no copy in a work folder to move
      # afterwards); archives inside it are still written to `into`.
      PROGRESS       = ".kifprogress"   # next to the zip: "<entries done> <zip size> <zip mtime>"
      PROGRESS_EVERY = 1000

      def save_progress(path, done, stamp)
        File.binwrite(path, "#{done} #{stamp}\n")
      rescue SystemCallError, IOError
        nil
      end

      # true: done; false: nothing written yet, tar may try the archive;
      # nil: failed after sprites were written (no tar: it would redo them)
      def extract(archive, into, direct: nil)
        require "zlib"
        si = KIF::SpriteImport
        mobile = KIF.respond_to?(:mobile?) && KIF.mobile?
        progress = archive + PROGRESS
        st = File.stat(archive)
        stamp = "#{st.size} #{st.mtime.to_i}"
        from = 0
        if direct && File.file?(progress)
          n, s = File.read(progress).split(" ", 2)
          from = n.to_i if s.to_s.strip == stamp   # the same zip, not a new one of the same name
          KIF.log("Sprite import: previous import of #{File.basename(archive)} was interrupted at entry #{from}") if from > 0 && defined?(KIF.log)
        end
        si.info[:from] = from
        started = from > 0
        errors = si.tally[:errors]
        File.open(archive, "rb") do |f|
          list = entries(f)
          si.info[:entries] = list.length
          list.each_with_index do |(name, method, csize, offset, usize, crc), i|
            if i > 0 && i % PROGRESS_EVERY == 0
              # not past a sprite that couldn't be written: a resume tries it again
              save_progress(progress, i, stamp) if direct && i > from && si.tally[:errors] == errors
              si.log_timing(i) if i % 5000 == 0
            end
            next if i < from   # placed by the run that was cut short
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
            # an entry this reader can't take: one file this big (read whole
            # into memory here), headers not where the directory says (a
            # self-extracting .exe zip, bytes in front), a packing it doesn't
            # know (Deflate64, BZip2, LZMA). Before anything is written tar
            # gets the archive (not on phones); after, the entry is skipped -
            # tar would write every sprite again.
            odd = "over 64 MB" if usize > MAX_ENTRY
            unless odd
              f.seek(offset)
              h = f.read(30)
              odd = "bad header" unless h && h[0, 4] == "PK\x03\x04".b
            end
            odd ||= "packing method #{method}" unless method == 0 || method == 8
            begin
              raise Zlib::DataError, odd if odd
              nlen, xlen = h[26, 4].unpack("vv")
              data = lambda do
                f.seek(offset + 30 + nlen + xlen)
                raw = f.read(csize)
                method == 8 ? si.timed(:inflate) { Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw) } : raw
              end
              if direct && dest
                held = File.join(direct, KIF::SpriteImport::HOLD_DIR, File.basename(into), *safe)
                started = true
                si.place(dest, held, data: data, size: usize, crc: crc)
                si.tick
                next
              end
              data = data.call
            rescue Zlib::Error => e
              return false unless started || mobile
              si.tally[:odd] += 1
              KIF.log("Sprite import: skipped #{name} in #{File.basename(archive)} (#{e.message})") if defined?(KIF.log)
              next
            end
            out = File.join(into, *safe)
            begin
              KIF::SpriteImport.mkdir_p(File.dirname(out))
              started = true
              KIF::SpriteImport.write_new(out, data)
            rescue SystemCallError, IOError => e
              # one file that can't be written (path too long, odd name)
              # doesn't stop the rest of the pack
              # a sprite counts as an error (the archive is kept), anything else is just not written
              dest ? KIF::SpriteImport.tally[:errors] += 1 : KIF::SpriteImport.not_written += 1
              KIF.log("Sprite import: skipped #{safe.last} (#{e.class})") if defined?(KIF.log)
              next
            end
            KIF::SpriteImport.bump
            KIF::SpriteImport.tick
          end
          save_progress(progress, list.length, stamp) if direct && si.tally[:errors] == errors
        end
        return true
      rescue => e
        KIF.log("Sprite import: couldn't read #{File.basename(archive)} (#{e.class}: #{e.message})") if defined?(KIF.log)
        return started ? nil : false
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
        # every directory record, not just `count`: some zip writers wrap the
        # count past 65,535 entries without zip64
        while pos + 46 <= cd.bytesize
          break unless cd[pos, 4] == "PK\x01\x02".b
          method = cd[pos + 10, 2].unpack1("v")
          crc, csize, usize = cd[pos + 16, 12].unpack("VVV")
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
          list << [name, method, csize, offset, usize, crc]
          pos += 46 + nlen + xlen + clen
        end
        raise "central directory not where the end record says" if list.empty? && count > 0   # tar takes over
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
        tick   # a whole pack can be 250,000 files: keep the window answering
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

KIF::Options.define(:sprite_file_cache, 0, :global) if defined?(KIF::Options)   # 0 Permanent, 1 Per Session, 2 Off
KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Sprite File Cache"), [_INTL("Permanent"), _INTL("Per Session"), _INTL("Off")],
                 proc { $PokemonSystem.sprite_file_cache },
                 proc { |value| $PokemonSystem.sprite_file_cache = value; KIF::SpriteImport.clear_bitmaps },
                 [_INTL("Sprite files are decoded once and kept (memory and the Cache folder)"),
                  _INTL("Sprite files are decoded once per session"),
                  _INTL("Sprite files are decoded every time they are shown (slower)")])
} if defined?(KIF::Options)

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

# Files PIF opens itself (a sprite's own path: Pokédex alt sprites, special
# sprites) get the same first-frame treatment
module KIF
  module SpriteImport
    module StripFrames
      def load_pif_sprite_directly(pif_sprite)
        ret = super
        b = (ret.bitmap rescue nil)
        return ret unless b && b.height > 0 && b.width > b.height && b.width % b.height == 0
        keep = KIF::SpriteImport.keep_strips?   # battle: the strip, at most MAX_STRIP_FRAMES
        return ret if keep && b.width / b.height <= KIF::SpriteImport::MAX_STRIP_FRAMES
        w = keep ? b.height * KIF::SpriteImport::MAX_STRIP_FRAMES : b.height
        frame = Bitmap.new(w, b.height)
        frame.blt(0, 0, b, Rect.new(0, 0, w, b.height))
        ret.dispose
        return AnimatedBitmap.from_bitmap(frame)
      end
    end
  end
end

BattleSpriteLoader.prepend(KIF::SpriteImport::StripFrames) if defined?(BattleSpriteLoader)

#-------------------------------------------------------------------------------
# Pokédex sprites page: a sprite that is both on a sheet and a file was listed
# twice (once with its artist, once as "Imported sprite"). The file copy is
# listed only for letters the sheets don't have.
#-------------------------------------------------------------------------------
module KIF
  module SpriteImport
    module DexAlts
      def pbGetAvailableAlts(dex_number, includeAutogens = false)
        list = super   # PIF's own errors stay PIF's (outside the rescue)
        return list unless list.is_a?(Array)
        return kif_tidy_alts(list)
      end

      def kif_tidy_alts(list)
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
