#===============================================================================
# F-CORE-08 – Settings presets (2026-10-10)
# Source: KIF 0.20.7 016_UI/015_UI_Options.rb:1599-1690 (SLOptionsScene:
#   12 named slots, Load / Save / Name, Options_<n>.kro in the save folder)
#
# Per-save settings (every KIF and Cody's additions setting that resets on New Game) can
# be saved into one of 12 named presets and loaded into another save, so a
# new run doesn't need every setting toggled again. Options > KIF Settings
# > Presets. Global settings are shared by every save already, so a preset
# holds only the per-save ones. Randomizer settings have their own presets
# (Randomizer > Presets & sharing).
# Changes from KIF: one file (KIF_Presets.kro in the save folder) instead of
# 13; a preset keeps only per-save KIF settings, not PIF's own options;
# settings added in later versions keep their current value when an older
# preset is loaded.
#===============================================================================
module KIF
  module Presets
    FILE  = "KIF_Presets.kro"
    SLOTS = 12
    # per-save values that are progress, not settings
    NOT_SETTINGS = [:trainerprogress, :player_wins, :enemy_wins]

    module_function

    def path
      return File.join(KIF.save_dir, FILE)
    end

    def keys
      return KIF::Options.save_keys - NOT_SETTINGS
    end

    def data
      d = nil
      begin
        d = File.open(path, "rb") { |f| Marshal.load(f) } if File.exist?(path)
      rescue StandardError => e
        KIF.log("Presets file unreadable (#{e.class}: #{e.message}) - kept as #{FILE}.bad")
        begin
          File.rename(path, path + ".bad")   # the next save must not overwrite the player's presets
        rescue StandardError
        end
      end
      d = {} unless d.is_a?(Hash)
      d[:names] = Array.new(SLOTS) { |i| "Preset #{i + 1}" } unless d[:names].is_a?(Array)
      d[:names].fill { |i| d[:names][i] || "Preset #{i + 1}" }
      d[:names] = d[:names][0, SLOTS] + Array.new([SLOTS - d[:names].length, 0].max) { |i| "Preset #{d[:names].length + i + 1}" }
      d[:slots] = {} unless d[:slots].is_a?(Hash)
      return d
    end

    def write(d)
      tmp = path + ".tmp"
      File.open(tmp, "wb") { |f| Marshal.dump(d, f) }   # whole file or nothing
      File.rename(tmp, path)
      return true
    rescue StandardError => e
      KIF.log("Presets file not written (#{e.class}: #{e.message})")
      return false
    end

    def name(i);   return data[:names][i]; end
    def filled?(i); return data[:slots][i].is_a?(Hash); end

    # The current save's settings into slot i
    def save(i)
      d = data
      d[:slots][i] = keys.each_with_object({}) { |k, h| h[k] = Marshal.load(Marshal.dump(KIF::Options.raw(k))) }   # the player's values, not a mod's locks
      ok = write(d)
      KIF.log("Settings preset #{i + 1} (#{d[:names][i]}) saved: #{d[:slots][i].length} settings") if ok
      return ok
    end

    # Slot i into the current save; returns how many settings were set
    def load(i)
      vals = data[:slots][i]
      return 0 unless vals.is_a?(Hash)
      n = 0
      known = keys
      vals.each do |k, v|
        next unless known.include?(k)
        $PokemonSystem.send(:"#{k}=", Marshal.load(Marshal.dump(v)))
        n += 1
      end
      KIF.sync_debug rescue nil
      KIF.recalc_all_stats   # Max IVs, No EVs and the fusion stat rules, as the menu does
      KIF.log("Settings preset #{i + 1} loaded: #{n} settings")
      return n
    end

    def rename(i, new_name)
      new_name = new_name.to_s.strip
      return false if new_name.empty?
      d = data
      d[:names][i] = new_name[0, 16]
      return write(d)
    end
  end
end

# The rows of the settings screen's Presets section: one per slot, each
# opening Load / Save / Rename
module KIF
  module Presets
    def self.slot_option(i)
      label = name(i)
      label += "  " + _INTL("(empty)") unless filled?(i)
      return ButtonOption.new(label, proc { slot_menu(i) },
                              filled?(i) ? _INTL("Load this preset, save this save's settings over it, or rename it.")
                                         : _INTL("Save this save's settings here, or rename the slot."))
    end

    def self.slot_options
      return [] unless KIF.in_game?
      return Array.new(SLOTS) { |i| slot_option(i) }
    end

    def self.slot_menu(i)
      n = name(i)
      cmds = [_INTL("Load"), _INTL("Save"), _INTL("Rename"), _INTL("Cancel")]
      choice = pbMessage(_INTL("{1}", n), cmds, cmds.length)
      case choice
      when 0
        if !filled?(i)
          pbPlayBuzzerSE
          pbMessage(_INTL("{1} is empty.", n))
        elsif pbConfirmMessage(_INTL("Replace this save's settings with {1}?", n))
          count = load(i)
          pbMessage(_INTL("Loaded {1} ({2} settings).", n, count))
        end
      when 1
        if !filled?(i) || pbConfirmMessage(_INTL("Overwrite {1} with this save's settings?", n))
          if save(i)
            pbMessage(_INTL("This save's settings are now in {1}.", n))
          else
            pbMessage(_INTL("The preset couldn't be saved."))
          end
        end
      when 2
        new_name = pbEnterText(_INTL("Preset name?"), 0, 16, n)
        rename(i, new_name)
      end
    end
  end
end
