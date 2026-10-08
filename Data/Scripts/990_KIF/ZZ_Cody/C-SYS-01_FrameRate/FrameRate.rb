#===============================================================================
# C-SYS-01 – Frame rate (Cody, 2026-10-08) - experimental
#   Cody Settings > Interface > "Frame rate": 40 (PIF's own) / 60.
#   Most of the engine already counts time against Graphics.frame_rate
#   (walking, event waits, fades, battle animations, HP bars, messages), so
#   at 60 those keep their speed and just get smoother. What this file adds:
#   - characters already on the map get their speeds recalculated;
#   - play time and event timers stay right when the rate changes, and
#     across saves made at either rate;
#   - pbWait(N) calls written as a plain number of 40 fps frames are
#     stretched to the same length of time (calls that already use
#     Graphics.frame_rate are left alone).
#   Menus and some scene animations with fixed frame loops run faster at 60.
#===============================================================================
KIF::Options.define(:cody_framerate, 0, :global)   # 0 = 40 fps, 1 = 60 fps

KIF::Options.add(:cody_interface, :global) {
  EnumOption.new(_INTL("Frame rate"), [_INTL("40"), _INTL("60")],
                 proc { $PokemonSystem.cody_framerate },
                 proc { |value|
                   $PokemonSystem.cody_framerate = value
                   KIF::FrameRate.apply
                 },
                 [_INTL("The game runs at 40 frames per second, like PIF."),
                  _INTL("Experimental: 60 frames per second. Walking and scrolling are smoother; some menus animate faster.")])
}

module KIF
  module FrameRate
    BASE = 40     # the rate PIF's frame counts were written for
    RATES = [40, 60]

    def self.wanted
      v = ($PokemonSystem.cody_framerate rescue 0)
      return RATES[v] || BASE
    end

    # Switch to the chosen rate, keeping everything that counts frames honest
    def self.apply(rate = nil)
      rate ||= wanted
      old = Graphics.frame_rate
      return if rate == old
      Graphics.frame_rate = rate
      rescale_counts(old, rate)
      refresh_characters
    rescue => e
      KIF.log("Frame rate change failed (#{e.class}: #{e.message})")
    end

    # Frame counters that mean "time": play time and the event timer
    def self.rescale_counts(old, rate)
      Graphics.frame_count = (Graphics.frame_count * rate / old.to_f).round
      if $game_system && $game_system.respond_to?(:timer) && $game_system.timer.to_i > 0
        $game_system.timer = ($game_system.timer * rate / old.to_f).round
      end
    end

    # Speeds are turned into per-frame amounts when they're set; set them again
    def self.refresh_characters
      chars = []
      chars << $game_player if $game_player
      chars.concat($game_map.events.values) if $game_map && $game_map.events
      if $PokemonTemp && $PokemonTemp.respond_to?(:dependentEvents) && $PokemonTemp.dependentEvents
        chars.concat($PokemonTemp.dependentEvents.realEvents) rescue nil
      end
      chars.compact.uniq.each do |c|
        next unless c.respond_to?(:move_speed=)
        # the setters skip an unchanged value, so clear it first
        sp = c.instance_variable_get(:@move_speed)
        if sp
          c.instance_variable_set(:@move_speed, nil)
          c.move_speed = sp
        end
        fr = c.instance_variable_get(:@move_frequency)
        if fr
          c.instance_variable_set(:@move_frequency, nil)
          c.move_frequency = fr
        end
        c.instance_variable_set(:@jump_speed_real, nil)
      end
    end

    # pbWait(N): is N a count of 40 fps frames, or already worked out from
    # Graphics.frame_rate? Read the calling line once and remember.
    # The game loads its scripts with only the file name as their path, so
    # the files are found by name under Data/Scripts (a name used twice is
    # told apart by which file has a pbWait on that line).
    @call_sites = {}
    def self.script_files(name)
      @script_index ||= begin
        idx = Hash.new { |h, k| h[k] = [] }
        Dir.glob("Data/Scripts/**/*.rb").each { |f| idx[File.basename(f)] << f }
        idx
      end
      return [name] if File.exist?(name)
      return @script_index[File.basename(name)]
    end

    def self.call_line(loc)
      lines = script_files(loc.path).map { |f| (File.readlines(f)[loc.lineno - 1] rescue nil) }.compact
      return lines.find { |l| l.include?("pbWait") } || lines.first || ""
    rescue
      return ""
    end

    def self.scale_wait?(loc)
      return false if Graphics.frame_rate == BASE
      return true unless loc
      key = "#{loc.path}:#{loc.lineno}"
      cached = @call_sites[key]
      return cached unless cached.nil?
      @call_sites[key] = !call_line(loc).include?("frame_rate")
    end

    # The fraction left over is carried to the next wait, so a loop of
    # pbWait(1) averages 1.5 frames at 60 instead of rounding to 2
    @carry = 0.0
    def self.wait_frames(n, loc)
      return n unless n.is_a?(Integer) && n > 0 && scale_wait?(loc)
      exact = n * Graphics.frame_rate / BASE.to_f + @carry
      frames = exact.floor
      @carry = exact - frames
      return frames
    end
  end
end

alias kif_fps_pbWait pbWait unless defined?(kif_fps_pbWait)
def pbWait(numFrames)
  kif_fps_pbWait(KIF::FrameRate.wait_frames(numFrames, caller_locations(1, 1)[0]))
end

# The rate a save's play time was counted at, so loading it at the other
# rate keeps the right play time. (No ensure_class: older saves lack it.)
SaveData.register(:kif_frame_rate) do
  save_value { Graphics.frame_rate }
  load_value { |value|
    was = value.is_a?(Integer) && value > 0 ? value : KIF::FrameRate::BASE
    if was != Graphics.frame_rate
      Graphics.frame_count = (Graphics.frame_count * Graphics.frame_rate / was.to_f).round
    end
  }
  new_game_value { Graphics.frame_rate }
end

# The setting lives with the other global options, which load at boot:
# switch on the first frame after that
module Graphics
  class << self
    alias kif_fps_update update unless method_defined?(:kif_fps_update)
    def update
      kif_fps_update
      unless KIF::FrameRate.instance_variable_get(:@booted)
        if $PokemonSystem
          KIF::FrameRate.instance_variable_set(:@booted, true)
          KIF::FrameRate.apply
        end
      end
    end
  end
end
