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
    MAX_BYTES_VERBOSE = 2 * 1024 * 1024
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
        return KIF::Paths.log(name)
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
            # a session that never wrote its end line was cut off (a crash
            # the error log has, a forced close, power loss): say so
            old = File.binread(path)
            unless old.include?("Session ended") || old.include?("Log full")
              File.open(path, "ab") { |f| f.write("[--] No end line: the game didn't exit normally (see KIF_errorlog.txt if it crashed)\r\n") }
            end
            File.delete(path(PREVIOUS)) if File.exist?(path(PREVIOUS))
            File.rename(path, path(PREVIOUS))
          end
        rescue
          nil
        end
        raw("KIF #{(KIF::PORT_VERSION rescue '?')} on PIF #{(Settings::GAME_VERSION_NUMBER rescue '?')} - #{@started.strftime('%Y-%m-%d %H:%M:%S')}" \
            "#{$DEBUG ? ' - debug mode' : ''}")
        raw("Engine: #{engine_text}")
        raw("Screen: #{screen_text}")
        raw("Verbose logging on (#{$DEBUG ? 'debug mode' : KIF::VERBOSE_MARKER})") if KIF.verbose?
        raw("Game folder: #{File.expand_path(".")}")
        raw("Save folder: #{KIF.save_dir}")
        raw("Logs: #{KIF::Paths.logs}")
        at_exit { finish }
      end

      # which engine build and system: mkxp-z version, platform, Ruby, the exe
      # (bug reports from phones, Wine and swapped exes look alike otherwise)
      def engine_text
        mkxp = (System::VERSION rescue nil) if defined?(System)
        platform = (System.platform rescue nil) if defined?(System)
        exe = (KIF::Updater::Win.exe_path rescue nil) if defined?(KIF::Updater::Win)
        parts = ["mkxp-z #{mkxp || '?'}", platform, "Ruby #{RUBY_VERSION}"]
        parts << File.basename(exe.to_s) if exe
        parts << "mobile" if KIF.respond_to?(:mobile?) && KIF.mobile?
        return parts.compact.join(", ")
      rescue StandardError
        return "?"
      end

      def screen_text
        parts = ["#{Graphics.width}x#{Graphics.height}"]
        scale = ($PokemonSystem.screensize rescue nil)
        parts << "size setting #{scale}" unless scale.nil?
        full = (Graphics.fullscreen rescue nil)
        parts << (full ? "fullscreen" : "window") unless full.nil?
        lang = ($PokemonSystem.language rescue nil)
        parts << "language #{lang}" unless lang.nil?
        return parts.join(", ")
      rescue StandardError
        return "?"
      end

      def max_bytes
        return KIF.verbose? ? MAX_BYTES_VERBOSE : MAX_BYTES
      end

      # Repeats are counted by their text without numbers and object ids, so
      # a failure that names a different value each frame is still one line
      def repeat_key(msg)
        return msg.gsub(/0x\h+|\d+/, "#")
      end

      def raw(line)
        return if @full
        text = line.to_s.gsub(/\r?\n/, " | ") + "\r\n"
        if @bytes + text.bytesize > max_bytes
          @full = true
          text = "[#{stamp}] Log full (#{max_bytes / 1024} KB); nothing more is written this session.\r\n"
        end
        File.open(path, "ab") { |f| f.write(text) }
        @bytes += text.bytesize
      rescue
        nil
      end

      def write(msg)
        start
        msg = msg.to_s
        key = repeat_key(msg)
        @counts[key] += 1
        return if @counts[key] > REPEATS
        raw("[#{stamp}] #{msg}#{@counts[key] == REPEATS ? '  (repeats from here on are only counted)' : ''}")
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
        raw("    KIF #{(KIF::PORT_VERSION rescue '?')}#{battle_text}")
        raw("    full error: KIF_errorlog.txt / errorlog.txt")
      rescue
        nil
      end

      # The battle at a crash: turn and each battler
      def battle_text
        return "" unless $game_temp && $game_temp.in_battle
        b = ObjectSpace.each_object(PokeBattle_Battle).find { |x| x.decision == 0 } rescue nil
        return ", in a battle" unless b
        mons = b.battlers.compact.map do |x|
          next nil unless x.pokemon
          st = x.status != :NONE ? " #{x.status}" : ""
          last = x.lastMoveUsed ? " last #{x.lastMoveUsed}" : ""
          "#{x.index}:#{x.pokemon.species} #{x.hp}/#{x.totalhp}#{st}#{last}"
        end.compact
        auto = ($PokemonSystem.autobattler rescue 0).to_i > 0 ? ", Auto-Battle on" : ""
        return ", battle turn #{b.turnCount}#{b.wildBattle? ? ' (wild)' : ''}: #{mons.join(', ')}#{auto}"
      rescue StandardError
        return ", in a battle"
      end

      # One line when a save loads (and the details that shape it)
      def note_load
        return unless $Trainer && $game_map
        secs = Graphics.frame_count / [Graphics.frame_rate, 1].max
        slot = ($Trainer.save_slot rescue nil) || "a save"
        write("Loaded #{slot}: map #{$game_map.map_id} #{(pbGetMapNameFromId($game_map.map_id) rescue '')}, " \
              "played #{secs / 3600}h #{secs / 60 % 60}m, #{$Trainer.badge_count} badges")
        if defined?(KIF::Rand) && $game_switches && $game_switches[SWITCH_RANDOMIZED_AT_LEAST_ONCE] && (KIF::Rand.available? rescue false)
          write("Randomizer: #{KIF::Rand.settings_code}")
        end
        changed = changed_settings
        write("Settings changed from default: #{changed.join(', ')}") unless changed.empty?
        if defined?(KIF::Modules) && KIF::Modules.const_defined?(:MODULES)
          off = KIF::Modules::MODULES.keys.select { |id| KIF::Modules.state(id) == KIF::Modules::OFF }
          write("Modules Off: #{off.join(', ')}") unless off.empty?
        end
      rescue StandardError => e
        write("Load note failed (#{e.class}: #{e.message})")
      end

      # KIF settings whose value isn't the default (names only, 40 at most)
      def changed_settings
        return [] unless defined?(KIF::Options) && $PokemonSystem
        out = KIF::Options.defaults.select do |key, default|
          v = ($PokemonSystem.send(key) rescue default)
          !v.nil? && v != default
        end.keys.map(&:to_s)
        return out.length > 40 ? out[0, 40] + ["#{out.length - 40} more"] : out
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
        t = Time.now
        count = ->(dir) { Dir.exist?(dir) ? Dir.children(dir).length : 0 }
        idx = "Graphics/CustomBattlers/local_sprites/indexed"
        heads = Dir.exist?(idx) ? Dir.children(idx).select { |c| File.directory?(File.join(idx, c)) } : []
        # every file in every head folder (236k with a sprite pack): only
        # counted with verbose logging; players get the folder count
        fusion_files = KIF.verbose? ? heads.sum { |h| count.call(File.join(idx, h)) } : nil
        dl = ($PokemonSystem.download_sprites rescue nil)
        write("Sprites: #{count.call('Graphics/CustomBattlers/local_sprites/BaseSprites')} base sprite files, " \
              "#{fusion_files ? "#{fusion_files} fusion sprite files in " : 'fusion sprites in '}#{heads.length} folders, " \
              "#{count.call('Graphics/CustomBattlers/spritesheets/spritesheets_base')} base sheets, " \
              "#{count.call('Graphics/CustomBattlers/spritesheets/spritesheets_custom')} custom sheets, " \
              "#{count.call('Graphics/Battlers/spritesheets_autogen')} autogen sheets; " \
              "Download data #{dl.nil? ? '?' : (dl == 0 ? 'on' : 'off')} (counted in #{((Time.now - t) * 1000).round} ms)")   # PIF's Download data: 0 = On
        waiting = Dir.exist?(KIF::Paths.import_sprites) ? Dir.children(KIF::Paths.import_sprites).reject { |c| c.start_with?("_") || c =~ /\.txt\z/i }.length : 0
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
        r = super   # PIF's own errors stay PIF's (outside the rescue)
        kif_note_missing(extractor, pif_sprite)
        return r
      end

      def kif_note_missing(extractor, pif_sprite)
        unless extractor.is_a?(CustomSpriteExtracter)
          s = pif_sprite
          what = s.type == :BASE ? "##{s.head_id}#{s.alt_letter}" : "#{s.head_id}.#{s.body_id}#{s.alt_letter} (#{s.type})"
          sheet = (extractor.getSpritesheetPath(s) rescue nil)
          KIF::SessionLog.missing_sprite("#{what} - no sprite file#{sheet ? ", no sheet #{sheet}" : ''}")
        end
      rescue => e
        KIF::SessionLog.write("Missing-sprite note failed (#{e.class}: #{e.message})")
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SessionLog::LoadScreen) if defined?(PokemonLoadScreen)
BattleSpriteLoader.prepend(KIF::SessionLog::MissingSprite) if defined?(BattleSpriteLoader)

# Closing the window: mkxp ends the game by raising SystemExit out of the
# next engine call. Graphics.update is one; 000_CrashLog.rb catches the rest
# (Input.update, transitions) where the game's main loop is run. PIF's
# at_exit only runs on Kernel#exit, so it can't be relied on.
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

# Loading and saving, a line each (logging only: nothing is shown here, the
# map scene doesn't exist yet while a save loads)
module Game
  class << self
    alias kif_session_load load unless method_defined?(:kif_session_load)
    alias kif_session_save save unless method_defined?(:kif_session_save)

    def load(*args, &blk)
      r = kif_session_load(*args, &blk)
      KIF::SessionLog.note_load rescue nil
      return r
    end

    def save(*args, **kw, &blk)
      r = kif_session_save(*args, **kw, &blk)
      begin
        slot = ($Trainer.save_slot rescue nil) || "save"
        KIF::SessionLog.write("Saved#{r == false ? ' FAILED' : ''}: #{slot}, map #{$game_map ? $game_map.map_id : '?'}")
      rescue StandardError
        nil
      end
      return r
    end
  end
end

# The maps you visit (kept in memory; only written with a crash).
# An alias, not a prepend: other KIF files alias transfer_player too, and an
# alias taken after a prepend of the same method calls itself for ever
# (SystemStackError on New Game, 2026-10-09).
class Scene_Map
  alias kif_session_transfer_player transfer_player unless method_defined?(:kif_session_transfer_player)

  def transfer_player(*args)
    r = kif_session_transfer_player(*args)
    if $game_map
      KIF::SessionLog.note_map($game_map.map_id)
      KIF.verbose("Map #{$game_map.map_id} #{(pbGetMapNameFromId($game_map.map_id) rescue '')}") if KIF.verbose?
    end
    return r
  end
end
