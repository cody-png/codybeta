#===============================================================================
# KIF session log: KIF_log.txt in the save folder
#   One file per play session, short enough to read and send:
#   * at start the last session's file becomes KIF_log_previous.txt (so a
#     crash is never wiped: its log is still there next time);
#   * a header (versions, folders, debug mode) and, at the load screen, what
#     the game has to show sprites with (sprite files, sheets, Download data);
#   * everything KIF.log reports (Entrances, sprite import, failures...);
#   * sprites that couldn't be found (one line each, the first 40);
#   * a crash: the error, where, and the last maps visited;
#   * the same line over and over is written 3 times, then only counted
#     (the counts are written when the game closes);
#   * at most MAX_BYTES per session; "Session ended" at the end means the game
#     closed normally.
#===============================================================================
module KIF
  module SessionLog
    FILE      = "KIF_log.txt"
    PREVIOUS  = "KIF_log_previous.txt"
    MAX_BYTES = 200 * 1024
    REPEATS   = 3
    MAX_MISSING_SPRITES = 40

    @started = nil
    @bytes = 0
    @counts = Hash.new(0)
    @full = false
    @maps = []
    @missing = 0

    class << self
      attr_reader :started

      def path(name = FILE)
        return File.join(KIF.save_dir, name)
      end

      def stamp
        t = (Time.now - @started).to_i
        return format("%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
      end

      def start
        return if @started
        @started = Time.now
        begin
          if File.exist?(path)
            File.delete(path(PREVIOUS)) if File.exist?(path(PREVIOUS))
            File.rename(path, path(PREVIOUS))
          end
        rescue
          nil
        end
        raw("KIF #{(KIF::PORT_VERSION rescue '?')} on PIF #{(Settings::GAME_VERSION_NUMBER rescue '?')} - #{@started.strftime('%Y-%m-%d %H:%M:%S')}" \
            "#{$DEBUG ? ' - debug mode' : ''}")
        raw("Game folder: #{Dir.pwd}")
        raw("Save folder: #{KIF.save_dir}")
        at_exit { finish }
      end

      def raw(line)
        return if @full
        text = line.to_s.gsub(/\r?\n/, " | ") + "\r\n"
        if @bytes + text.bytesize > MAX_BYTES
          @full = true
          text = "[#{stamp}] Log full (#{MAX_BYTES / 1024} KB); nothing more is written this session.\r\n"
        end
        File.open(path, "ab") { |f| f.write(text) }
        @bytes += text.bytesize
      rescue
        nil
      end

      def write(msg)
        start
        msg = msg.to_s
        @counts[msg] += 1
        return if @counts[msg] > REPEATS
        raw("[#{stamp}] #{msg}#{@counts[msg] == REPEATS ? '  (repeats from here on are only counted)' : ''}")
      end

      def finish
        return unless @started
        @counts.each { |msg, n| raw("[#{stamp}] #{n - REPEATS} more times: #{msg}") if n > REPEATS }
        raw("[#{stamp}] #{@missing - MAX_MISSING_SPRITES} more sprites couldn't be found") if @missing > MAX_MISSING_SPRITES
        raw("[#{stamp}] Session ended")
        @started = nil
      end

      # The last maps you were on, for crash reports
      def note_map(map_id)
        return if @maps.last == map_id
        @maps << map_id
        @maps.shift while @maps.length > 12
      end

      def crash(e)
        start
        where = (e.backtrace || [])[0, 4].map { |l| l.sub(/\A.*Data\/Scripts\//, "") }.join(" < ")
        raw("[#{stamp}] CRASH #{e.class}: #{e.message[0, 300]}")
        raw("    at #{where}")
        raw("    last maps: #{@maps.map { |m| "#{m} #{(pbGetMapNameFromId(m) rescue '')}" }.join(' > ')}")
        raw("    full error: KIF_errorlog.txt / errorlog.txt")
      rescue
        nil
      end

      def missing_sprite(text)
        @missing += 1
        return if @missing > MAX_MISSING_SPRITES
        write("No sprite: #{text}")
      end

      # What the game has to draw Pokémon with (written once, at the load screen)
      def sprite_report
        return if @sprites_reported
        @sprites_reported = true
        count = ->(dir) { Dir.exist?(dir) ? Dir.children(dir).length : 0 }
        idx = "Graphics/CustomBattlers/local_sprites/indexed"
        heads = Dir.exist?(idx) ? Dir.children(idx).select { |c| File.directory?(File.join(idx, c)) } : []
        fusion_files = heads.sum { |h| count.call(File.join(idx, h)) }
        dl = ($PokemonSystem.download_sprites rescue nil)
        write("Sprites: #{count.call('Graphics/CustomBattlers/local_sprites/BaseSprites')} base sprite files, " \
              "#{fusion_files} fusion sprite files in #{heads.length} folders, " \
              "#{count.call('Graphics/CustomBattlers/spritesheets/spritesheets_base')} base sheets, " \
              "#{count.call('Graphics/CustomBattlers/spritesheets/spritesheets_custom')} custom sheets, " \
              "#{count.call('Graphics/Battlers/spritesheets_autogen')} autogen sheets; " \
              "Download data #{dl.nil? ? '?' : (dl == 0 ? 'off' : 'on')}")
        waiting = Dir.exist?("Import Sprites") ? Dir.children("Import Sprites").reject { |c| c.start_with?("_") }.length : 0
        write("Import Sprites folder: #{waiting} item(s) waiting") if waiting > 0
      rescue => e
        write("Sprite report failed (#{e.class}: #{e.message})")
      end
    end

    module LoadScreen
      def pbStartLoadScreen(*args)
        KIF::SessionLog.sprite_report
        return super
      end
    end

    module MissingSprite
      def handle_unloaded_sprites(extractor, pif_sprite)
        r = super
        unless extractor.is_a?(CustomSpriteExtracter)
          s = pif_sprite
          what = s.type == :BASE ? "##{s.head_id}#{s.alt_letter}" : "#{s.head_id}.#{s.body_id}#{s.alt_letter} (#{s.type})"
          sheet = (extractor.getSpritesheetPath(s) rescue nil)
          KIF::SessionLog.missing_sprite("#{what} - no sprite file#{sheet ? ", no sheet #{sheet}" : ''}")
        end
        return r
      rescue => e
        KIF::SessionLog.write("Missing-sprite note failed (#{e.class}: #{e.message})")
        return r
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SessionLog::LoadScreen) if defined?(PokemonLoadScreen)
BattleSpriteLoader.prepend(KIF::SessionLog::MissingSprite) if defined?(BattleSpriteLoader)

# Closing the window: mkxp ends the game by raising SystemExit out of
# Graphics.update (at_exit doesn't get a turn), so the counts and "Session
# ended" are written here
module Graphics
  class << self
    alias kif_session_update update unless method_defined?(:kif_session_update)

    def update(*args)
      kif_session_update(*args)
    rescue SystemExit
      KIF::SessionLog.finish rescue nil
      raise
    end
  end
end

# Crashes: a short note here (the full text stays in the error logs)
alias kif_session_pbPrintException pbPrintException unless defined?(kif_session_pbPrintException)
def pbPrintException(e)
  KIF::SessionLog.crash(e) rescue nil
  kif_session_pbPrintException(e)
end

# The maps you visit (kept in memory; only written with a crash)
module KIF
  module SessionLog
    module Transfers
      def transfer_player(*args)
        r = super
        KIF::SessionLog.note_map($game_map.map_id) if $game_map
        return r
      end
    end
  end
end

Scene_Map.prepend(KIF::SessionLog::Transfers) if defined?(Scene_Map)
