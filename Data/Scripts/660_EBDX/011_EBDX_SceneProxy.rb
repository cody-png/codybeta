#===============================================================================
#  EBDX Scene Proxy - Intercepts battle scene creation
#===============================================================================
#  Aliases pbNewBattleScene to return PokeBattle_SceneEBDX when toggle is on,
#  or vanilla PokeBattle_Scene when toggle is off.
#  This is the core of the toggle system - scenes are local-only so
#  multiplayer sync is completely unaffected.
#===============================================================================

alias pbNewBattleScene_pre_ebdx660 pbNewBattleScene unless defined?(pbNewBattleScene_pre_ebdx660)
def pbNewBattleScene
  # Skip EBDX for Safari battles — EBDX crashes in Safari mode
  safari = (pbInSafari? rescue false)
  if safari
    return pbNewBattleScene_pre_ebdx660
  end
  if EBDXToggle.enabled? && defined?(PokeBattle_SceneEBDX)
    return PokeBattle_SceneEBDX.new
  else
    return pbNewBattleScene_pre_ebdx660
  end
end
