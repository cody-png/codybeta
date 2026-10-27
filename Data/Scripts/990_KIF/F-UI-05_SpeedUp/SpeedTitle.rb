#===============================================================================
# F-UI-05 (part) – KIF window title and L/R speed keys
# Source: KIF 0.20.7 052_AddOns/Spped Up.rb:42-55 (updateTitle), :97-130
#         (AUX1 = L: speed +1, AUX2 = R: back to 1x)
#
# Window title (KIF version = this port's version):
#   "Kuray's Infinite Fusion (KIF) | Version: <KIF::PORT_VERSION> |
#    PIF Version: <6.8.2> | Speed: xN"
#   plus KIF's "Auto-Battler (ON/OFF) | Loop Self-Battle (ON/OFF)".
#   The title is only rewritten when the text changes.
#
# L / R (keyboard Q / W by default): L = next speed, R = back to 1x.
#   Only in Toggle speed-up mode (6.8.2's Hold mode has no stored speed).
#   A controller's RB (JUMPDOWN) also steps up, like the toggle key.
#   Only on the map (no menu, message or event running) and in battles –
#   6.8.2 menus use L/R themselves (Pokédex pages, quest log, clothes shop);
#   KIF reacted everywhere. Also off
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
      ret = _INTL("Kuray's Infinite Fusion (KIF) | Version: {1} | PIF Version: {2} | Speed: x{3}",
                  KIF::PORT_VERSION, Settings::GAME_VERSION_NUMBER, current_speed)
      # KIF updateTitle: Auto-Battle / Battle Loop state (F-BATTLE-02, F-PC-03)
      if $PokemonSystem && $PokemonSystem.respond_to?(:autobattler)
        auto = ($PokemonSystem.autobattler.to_i == 1) ? "(ON)" : "(OFF)"
        loop_on = ($PokemonSystem.respond_to?(:sb_loopinput) && $PokemonSystem.sb_loopinput.to_i == 1) ? "(ON)" : "(OFF)"
        ret += " | Auto-Battler #{auto} | Loop Self-Battle #{loop_on}"
      end
      return ret
    end

    # Runs every Graphics.update: only the three cheap inputs are compared;
    # the title string is rebuilt (and set) when one of them changed.
    def self.update_title
      ps = $PokemonSystem
      key = [current_speed,
             ps && ps.respond_to?(:autobattler) ? ps.autobattler.to_i : nil,
             ps && ps.respond_to?(:sb_loopinput) ? ps.sb_loopinput.to_i : nil]
      fade_notice
      return if key == @last_key
      phone_notice(key, @last_key) if @last_key && KIF.mobile?
      @last_key = key
      text = title_text
      return if text == @last_title
      @last_title = text
      System.set_window_title(text) if defined?(System) && System.respond_to?(:set_window_title)
    rescue
      nil
    end

    # Phones have no window title: a change shows at the top of the screen
    # for two seconds instead
    NOTICE_SECONDS = 2

    def self.phone_notice(key, old)
      lines = []
      lines << _INTL("Speed: x{1}", key[0]) if key[0] != old[0]
      lines << _INTL("Auto-Battler: {1}", key[1] == 1 ? _INTL("On") : _INTL("Off")) if key[1] != old[1]
      lines << _INTL("Loop Self-Battle: {1}", key[2] == 1 ? _INTL("On") : _INTL("Off")) if key[2] != old[2]
      return if lines.empty?
      @notice_text = lines.join("   ")
      @notice_until = Time.now + NOTICE_SECONDS
      unless @notice && !@notice.disposed?
        @notice = Sprite.new
        @notice.z = 999_998
        @notice.bitmap = Bitmap.new(Graphics.width, 32)
      end
      b = @notice.bitmap
      b.clear
      b.fill_rect(0, 0, b.width, b.height, Color.new(0, 0, 0, 160))
      b.font.color = Color.new(248, 248, 248)
      b.draw_text(0, 0, b.width, b.height, @notice_text, 1)
    rescue StandardError
      nil
    end

    def self.fade_notice
      return unless @notice
      return if !@notice.disposed? && Time.now < @notice_until
      (@notice.bitmap.dispose rescue nil)
      (@notice.dispose rescue nil)
      @notice = nil
    end

    def self.notice_text
      return @notice && !@notice.disposed? ? @notice_text : nil
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
      # RB (JUMPDOWN) on a controller steps up like the toggle key (2026-10-27)
      rb = Input.trigger?(Input::JUMPDOWN) && KIF::Keys.pad?
      return unless rb || Input.trigger?(Input::AUX1) || Input.trigger?(Input::AUX2)
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
