#===============================================================================
#  EBDX Class Overrides - Minor cosmetic-only class reopenings
#===============================================================================
#  Toggle-guarded enhancements to message windows and minor UI elements.
#  These do NOT modify behavior when EBDX is off.
#===============================================================================

#===============================================================================
#  Enhanced Message Window for EBDX
#===============================================================================
class Window_AdvancedTextPokemonEBDX < Window_AdvancedTextPokemon
  attr_accessor :ebdx_style

  def initialize(*args)
    super(*args)
    @ebdx_style = false
  end

  def applyEBDXStyle
    return unless EBDXToggle.enabled?
    @ebdx_style = true
    # Apply EBDX visual styling
    self.windowskin = RPG::Cache.windowskin("EBDX/message") rescue self.windowskin
  end
end

#===============================================================================
#  Battle Message Enhancements (toggle-guarded)
#===============================================================================
if defined?(PokeBattle_Scene)
  class PokeBattle_Scene
    # Store original method
    alias pbShowWindow_ebdx660 pbShowWindow unless method_defined?(:pbShowWindow_ebdx660)
    def pbShowWindow(windowtype)
      pbShowWindow_ebdx660(windowtype)
      # EBDX styling handled by PokeBattle_SceneEBDX instead
    end
  end
end

#===============================================================================
#  Trainer Speech Helper (for EBDX trainer dialogue)
#===============================================================================
module EBDXTrainerSpeech
  # Get trainer speech for a specific context
  def self.get_speech(trainer, context)
    return nil unless EBDXToggle.enabled?
    return nil unless trainer

    # Try to get speech from EBDX data
    speech = EliteBattle.get_data(trainer.trainer_type, :Trainer, context, trainer.name) rescue nil
    return speech if speech

    # Fall back to generic speech
    generic = EliteBattle.get_data(trainer.trainer_type, :Trainer, context) rescue nil
    return generic
  end

  # Speech contexts
  CONTEXTS = {
    :intro => :INTRO_SPEECH,
    :sendout => :SENDOUT_SPEECH,
    :recall => :RECALL_SPEECH,
    :low_hp => :LOWHP_SPEECH,
    :last_pokemon => :LASTPOKE_SPEECH,
    :win => :WIN_SPEECH,
    :lose => :LOSE_SPEECH
  }

  def self.get_intro(trainer)
    get_speech(trainer, :INTRO_SPEECH)
  end

  def self.get_sendout(trainer)
    get_speech(trainer, :SENDOUT_SPEECH)
  end

  def self.get_low_hp(trainer)
    get_speech(trainer, :LOWHP_SPEECH)
  end

  def self.get_last_pokemon(trainer)
    get_speech(trainer, :LASTPOKE_SPEECH)
  end
end

#===============================================================================
#  Screen Tone Handler for EBDX transitions
#===============================================================================
module EBDXScreenTone
  @current_tone = nil

  def self.apply(tone, duration = 0)
    return unless EBDXToggle.enabled?
    @current_tone = tone
    if $game_screen
      $game_screen.start_tone_change(tone, duration)
    end
  end

  def self.reset(duration = 0)
    apply(Tone.new(0, 0, 0, 0), duration)
  end

  def self.flash_white(duration = 8)
    return unless EBDXToggle.enabled?
    if $game_screen
      $game_screen.start_flash(Color.new(255, 255, 255, 255), duration)
    end
  end
end

#===============================================================================
#  Battle Intro Fade Handler
#===============================================================================
module EBDXBattleIntro
  def self.perform_intro_fade
    return false unless EBDXToggle.enabled?

    # Fade to black
    16.times do |i|
      Graphics.brightness = 255 - (i * 16)
      Graphics.update
    end
    Graphics.brightness = 0

    true
  end

  def self.perform_intro_reveal
    return false unless EBDXToggle.enabled?

    # Fade in from black
    16.times do |i|
      Graphics.brightness = i * 16
      Graphics.update
    end
    Graphics.brightness = 255

    true
  end
end
