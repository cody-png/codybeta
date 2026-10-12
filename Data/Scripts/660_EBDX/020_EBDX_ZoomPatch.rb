#==============================================================================
# EBDX Camera Patch — integrates mp_ebdx_zoom_disabled setting
#
# When "Battle Zoom" is Off, the camera is locked to the neutral MAIN vector
# during the battle — no panning, tilting, or zoom during move selection or
# attack animations. The battle-start intro (camera zoom-out + Pokémon unveil)
# is deliberately excluded: the lock only activates after the first command
# phase begins, so the opening seconds look normal regardless of the setting.
#
# HOW IT WORKS
# ─────────────
# EBDXCamPatch.intro_done? tracks whether the intro has finished:
#   • reset to false when the battle scene initialises (pbStartBattle)
#   • set to true on the first call to pbBeginCommandPhase
# Vector#update is patched to snap every component to MAIN when both the
# setting is on AND the intro is done.  @set is synced at the same time so
# toggling the setting back on mid-battle resumes from a clean state.
#==============================================================================

module EBDXCamPatch
  @intro_done = false

  def self.intro_done?
    @intro_done
  end

  def self.mark_intro_done
    @intro_done = true
  end

  def self.reset
    @intro_done = false
  end
end

#------------------------------------------------------------------------------
# Vector patch — lock camera after intro when setting is on
#------------------------------------------------------------------------------
class Vector
  alias _mp_cam_orig_update update unless method_defined?(:_mp_cam_orig_update)

  def update
    if ($PokemonSystem rescue nil)&.mp_ebdx_zoom_disabled == 1 && EBDXCamPatch.intro_done?
      main = EliteBattle.get_vector(:MAIN, @battle)
      @x     = main[0].to_f
      @y     = main[1].to_f
      @angle = main[2].to_f
      @scale = main[3].to_f
      @zoom1 = 1.0
      @zoom2 = 1.0
      @set   = main.dup
      @set[4] = 1.0
      @set[5] = 1.0
      self.calculate
      return
    end

    @x     += ((@set[0] - @x    )*@inc)/self.delta
    @y     += ((@set[1] - @y    )*@inc)/self.delta
    @angle += ((@set[2] - @angle)*@inc)/self.delta
    @scale += ((@set[3] - @scale)*@inc)/self.delta
    @zoom1 += ((@set[4] - @zoom1)*@inc)/self.delta
    @zoom2 += ((@set[5] - @zoom2)*@inc)/self.delta
    self.calculate
  end
end

#------------------------------------------------------------------------------
# Scene hooks — manage the intro flag lifetime
#------------------------------------------------------------------------------
class PokeBattle_SceneEBDX
  # Reset flag at battle start so each new battle gets the intro
  alias _mp_cam_orig_pbStartBattle pbStartBattle unless method_defined?(:_mp_cam_orig_pbStartBattle)
  def pbStartBattle(battle)
    EBDXCamPatch.reset
    _mp_cam_orig_pbStartBattle(battle)
  end

  # Mark intro done on the very first command phase
  alias _mp_cam_orig_pbBeginCommandPhase pbBeginCommandPhase unless method_defined?(:_mp_cam_orig_pbBeginCommandPhase)
  def pbBeginCommandPhase
    EBDXCamPatch.mark_intro_done
    _mp_cam_orig_pbBeginCommandPhase
  end
end
