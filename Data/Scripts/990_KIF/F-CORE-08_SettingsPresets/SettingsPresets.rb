#===============================================================================
# F-CORE-08 – Settings presets (tester request, 2026-10-10)
# Source: KIF 0.20.7 016_UI/015_UI_Options.rb:1599-1690 (SLOptionsScene:
#   12 named slots, Load / Save / Name, Options_<n>.kro in the save folder)
#
# Per-save settings (every KIF and Cody setting that resets on New Game) can
# be saved into one of 12 named presets and loaded into another save, so a
# new run doesn't need every setting toggled again. KIF Settings > Settings
# Presets. Global settings are shared by every save already, so a preset
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
        KIF.log("Presets file unreadable (#{e.class}: #{e.message})")
      end
      d = {} unless d.is_a?(Hash)
      d[:names] = Array.new(SLOTS) { |i| "Preset #{i + 1}" } unless d[:names].is_a?(Array)
      d[:names].fill { |i| d[:names][i] || "Preset #{i + 1}" }
      d[:names] = d[:names][0, SLOTS] + Array.new([SLOTS - d[:names].length, 0].max) { |i| "Preset #{d[:names].length + i + 1}" }
      d[:slots] = {} unless d[:slots].is_a?(Hash)
      return d
    end

    def write(d)
      File.open(path, "wb") { |f| Marshal.dump(d, f) }
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
      d[:slots][i] = keys.each_with_object({}) { |k, h| h[k] = Marshal.load(Marshal.dump($PokemonSystem.send(k))) }
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

class KifPresetsScene < KifOptionsBaseScene
  def kif_title; "Settings Presets"; end
  def kif_colors; [[200, 130, 200], [115, 75, 115]]; end

  def getDefaultDescription
    return _INTL("Save this file's settings, or load them into another save.")
  end

  def slot_option(i)
    label = KIF::Presets.name(i)
    label += "  " + _INTL("(empty)") unless KIF::Presets.filled?(i)
    return ButtonOption.new(label, proc { kif_slot_menu(i) },
                            _INTL("Load, save or rename this preset."))
  end

  def pbGetOptions(inloadscreen = false)
    return [kif_header_option("### LOAD A SAVE TO USE PRESETS ###")] unless KIF.in_game?
    return Array.new(KIF::Presets::SLOTS) { |i| slot_option(i) }
  end

  def kif_slot_menu(i)
    name = KIF::Presets.name(i)
    cmds = [_INTL("Load"), _INTL("Save"), _INTL("Rename"), _INTL("Cancel")]
    choice = pbMessage(_INTL("{1}", name), cmds, cmds.length)
    case choice
    when 0
      if !KIF::Presets.filled?(i)
        pbPlayBuzzerSE
        pbMessage(_INTL("{1} is empty.", name))
      elsif pbConfirmMessage(_INTL("Replace this save's settings with {1}?", name))
        n = KIF::Presets.load(i)
        pbMessage(_INTL("Loaded {1} ({2} settings).", name, n))
      end
    when 1
      if !KIF::Presets.filled?(i) || pbConfirmMessage(_INTL("Overwrite {1} with this save's settings?", name))
        if KIF::Presets.save(i)
          pbMessage(_INTL("This save's settings are now in {1}.", name))
        else
          pbMessage(_INTL("The preset couldn't be saved."))
        end
      end
    when 2
      new_name = pbEnterText(_INTL("Preset name?"), 0, 16, name)
      KIF::Presets.rename(i, new_name)
    end
    kif_refresh_slot(i)
  end

  def kif_refresh_slot(i)
    return unless @PokemonOptions && @sprites && @sprites["option"]
    @PokemonOptions[i] = slot_option(i)
    @sprites["option"].refresh rescue nil
  end
end

class KifOptionsScene < KifOptionsBaseScene
  alias kif_presets_pbGetOptions pbGetOptions unless method_defined?(:kif_presets_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_presets_pbGetOptions(inloadscreen)
    btn = ButtonOption.new(_INTL("Settings Presets"), proc { kif_open_presets },
                           _INTL("Save this file's settings, or load them into another save."))
    idx = options.index { |o| o.respond_to?(:name) && o.name == _INTL("Increment Slider by") }
    idx ? options.insert(idx, btn) : options.push(btn)
    return options
  end

  def kif_open_presets
    pbFadeOutIn {
      PokemonOptionScreen.new(KifPresetsScene.new).pbStartScreen
    }
  end
end
