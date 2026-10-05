#===============================================================================
# F-UI-05 (part) – KIF window title and L/R speed keys
# Source: KIF 0.20.7 052_AddOns/Spped Up.rb:42-55 (updateTitle), :97-130
#         (AUX1 = L: speed +1, AUX2 = R: back to 1x)
#
# Window title (Cody, 2026-10-05: KIF version = this port's version):
#   "Kuray's Infinite Fusion (KIF) | Version: <KIF::PORT_VERSION> |
#    PIF Version: <6.8.2> | Speed: xN"
#   KIF also showed Auto-Battler / Loop Self-Battle; they come with those
#   features. The title is only rewritten when the text changes.
#
# L / R (keyboard Q / W by default): L = next speed, R = back to 1x.
#   Only in Toggle speed-up mode (6.8.2's Hold mode has no stored speed).
#   Only on the map (no menu, message or event running) and in battles –
#   6.8.2 menus use L/R themselves (Pokédex pages, quest log, clothes shop);
#   KIF reacted everywhere (Cody chose map/battle only, 2026-10-05). Also off
#   while placing secret-base furniture (L/R rotate it).
#===============================================================================
module KIF
  module SpeedTitle
    @last_title = nil

    # Speed multiplier currently applied by 6.8.2's Spped Up.rb
    def self.current_speed
      return 1 unless $PokemonSystem && defined?(SPEEDUP_STAGES)
      if $PokemonSystem.speedup == 1
        return SPEEDUP_STAGES[$GameSpeed.to_i] || 1
      end
      return 1 unless $CanToggle && Input.press?(Input::X)
      return (Graphics.get_speedup_speed + 1 rescue 1)
    end

    def self.title_text
      return _INTL("Kuray's Infinite Fusion (KIF) | Version: {1} | PIF Version: {2} | Speed: x{3}",
                   KIF::PORT_VERSION, Settings::GAME_VERSION_NUMBER, current_speed)
    end

    def self.update_title
      text = title_text
      return if text == @last_title
      @last_title = text
      System.set_window_title(text) if defined?(System) && System.respond_to?(:set_window_title)
    rescue
      nil
    end

    # Map with nothing open, or any battle
    def self.keys_allowed?
      return false unless $game_temp && $PokemonSystem
      return true if $game_temp.in_battle
      return false unless $scene.is_a?(Scene_Map)
      return false if $game_temp.in_menu || $game_temp.message_window_showing
      return false if $game_temp.respond_to?(:moving_furniture) && $game_temp.moving_furniture  # Hoenn secret bases rotate with L/R
      return false if $game_system && $game_system.map_interpreter.running?
      return true
    end

    def self.check_keys
      return unless $CanToggle && defined?(SPEEDUP_STAGES)
      return unless $PokemonSystem && $PokemonSystem.speedup == 1
      return unless Input.trigger?(Input::AUX1) || Input.trigger?(Input::AUX2)
      return unless keys_allowed?
      if Input.trigger?(Input::AUX2)
        $GameSpeed = 0
      else
        $GameSpeed = ($GameSpeed.to_i + 1) % SPEEDUP_STAGES.size
      end
    rescue
      nil
    end
  end
end

# Keys are read once per input poll (some loops call Graphics.update several
# times per Input.update, which would repeat a trigger).
module Input
  class << Input
    alias kif_speedkeys_update update unless method_defined?(:kif_speedkeys_update)
  end

  def self.update
    kif_speedkeys_update
    KIF::SpeedTitle.check_keys
  end
end

module Graphics
  class << Graphics
    alias kif_title_update update unless method_defined?(:kif_title_update)
  end

  def self.update
    KIF::SpeedTitle.update_title
    kif_title_update
  end
end
