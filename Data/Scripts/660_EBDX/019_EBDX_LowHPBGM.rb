#===============================================================================
#  EBDX Low HP BGM System
#===============================================================================
#  Switches battle music when player's Pokemon is at low HP.
#  Toggle-guarded - only active when EBDX is enabled.
#===============================================================================

module EBDXLowHPBGM
  @original_bgm = nil
  @low_hp_playing = false
  @enabled = true

  # Low HP threshold (25% by default)
  LOW_HP_THRESHOLD = 0.25

  # Low HP BGM filename
  LOW_HP_BGM = "EBDX/Low HP"
  LOW_HP_BGM_FALLBACK = "Battle roaming"

  #=============================================================================
  #  Enable/Disable
  #=============================================================================
  def self.enabled?
    @enabled && EBDXToggle.enabled?
  end

  def self.enable
    @enabled = true
  end

  def self.disable
    @enabled = false
    restore_bgm if @low_hp_playing
  end

  #=============================================================================
  #  Check if player has low HP Pokemon
  #=============================================================================
  def self.player_has_low_hp?(battle)
    return false unless battle
    return false unless battle.pbPlayer

    # Check all player battlers
    battle.battlers.each do |b|
      next unless b && b.pbOwnedByPlayer?
      next if b.fainted?
      return true if b.hp <= (b.totalhp * LOW_HP_THRESHOLD).floor
    end

    false
  end

  #=============================================================================
  #  BGM Management
  #=============================================================================
  def self.check_and_update(battle)
    return unless enabled?
    return unless battle

    if player_has_low_hp?(battle)
      play_low_hp_bgm unless @low_hp_playing
    else
      restore_bgm if @low_hp_playing
    end
  end

  def self.play_low_hp_bgm
    return if @low_hp_playing

    # Store current BGM
    @original_bgm = $game_system.playing_bgm rescue nil

    # Try to play low HP BGM
    if pbResolveBitmap("Audio/BGM/#{LOW_HP_BGM}")
      pbBGMPlay(LOW_HP_BGM)
      @low_hp_playing = true
    elsif pbResolveBitmap("Audio/BGM/#{LOW_HP_BGM_FALLBACK}")
      # Fallback to roaming battle theme
      pbBGMPlay(LOW_HP_BGM_FALLBACK)
      @low_hp_playing = true
    end
  end

  def self.restore_bgm
    return unless @low_hp_playing

    if @original_bgm
      pbBGMPlay(@original_bgm)
    end

    @original_bgm = nil
    @low_hp_playing = false
  end

  def self.reset
    @original_bgm = nil
    @low_hp_playing = false
  end

  #=============================================================================
  #  Battle Start/End Hooks
  #=============================================================================
  def self.on_battle_start(battle)
    return unless enabled?
    reset
    # Initial check at battle start
    check_and_update(battle)
  end

  def self.on_battle_end
    return unless enabled?
    restore_bgm
    reset
  end

  def self.on_turn_end(battle)
    return unless enabled?
    check_and_update(battle)
  end
end

#===============================================================================
#  PokeBattle_Battle Hooks for Low HP BGM
#===============================================================================
if defined?(PokeBattle_Battle)
  # Hook into end of round
  if PokeBattle_Battle.method_defined?(:pbEndOfRoundPhase) && !PokeBattle_Battle.method_defined?(:pbEndOfRoundPhase_ebdx_lowhp)
    class PokeBattle_Battle
      alias pbEndOfRoundPhase_ebdx_lowhp pbEndOfRoundPhase
      def pbEndOfRoundPhase
        result = pbEndOfRoundPhase_ebdx_lowhp
        EBDXLowHPBGM.on_turn_end(self) if EBDXToggle.enabled?
        result
      end
    end
  end
end

#===============================================================================
#  Scene Integration - Reset on battle end
#===============================================================================
module EBDXLowHPBGMSceneIntegration
  def pbEndBattle(result)
    EBDXLowHPBGM.on_battle_end if EBDXToggle.enabled?
    super
  end
end

# Apply to EBDX scene if it exists
if defined?(PokeBattle_SceneEBDX)
  PokeBattle_SceneEBDX.prepend(EBDXLowHPBGMSceneIntegration)
end
