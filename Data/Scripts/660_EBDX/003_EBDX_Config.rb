#===============================================================================
#  Elite Battle: DX - System Settings (KIF Adapted)
#===============================================================================
module EliteBattle
  BATTLE_MOTION_TIMER = 90
  TRAINER_SPRITE_SCALE = 2
  FRONT_SPRITE_SCALE = 2
  BACK_SPRITE_SCALE = 2
  ROOM_SCALE = 2.25
  USE_LOW_HP_BGM = false
  CUSTOM_COMMON_ANIM = true
  CUSTOM_MOVE_ANIM = true
  DISABLE_SCENE_MOTION = false
  # Super shiny disabled - KIF has its own shiny system
  # SUPER_SHINY_RATE = 0
  # PERFECT_IV_SHINY = 0
  # PERFECT_IV_SUPER = 0
  SHOW_LINEUP_WILD = false
  USE_FOLLOWER_EXCEPTION = true
  SHOW_DEBUG_FEATURES = false
end

#-------------------------------------------------------------------------------
# Camera motion vectors
EliteBattle.add_vector(:CAMERA_MOTION,
  [132, 408, 24, 302, 1],
  [122, 294, 20, 322, 1],
  [238, 304, 26, 322, 1],
  [0, 384, 26, 322, 1],
  [198, 298, 18, 282, 1],
  [196, 306, 26, 242, 0.6],
  [156, 280, 18, 226, 0.6],
  [60, 280, 12, 388, 1],
  [160, 286, 16, 340, 1]
)

#-------------------------------------------------------------------------------
# Default transitions
EliteBattle.assign_transition("rainbowIntro", :ALLOW_ALL)
