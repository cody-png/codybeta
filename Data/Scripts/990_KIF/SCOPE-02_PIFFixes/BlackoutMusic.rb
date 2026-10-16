#===============================================================================
# SCOPE-02 – PIF fix: gym music kept playing in the Pokémon Center after
# losing to Misty (2026-10-14)
# Misty's event (Map004 Cerulean City Gym, event 3) memorizes the music
# (command 247), plays her theme and battles; its last commands restore the
# memorized music (command 248). On a loss pbStartOver moves the player to the
# Pokémon Center first and the Center's music starts, then the event goes on
# and the restore puts the gym music back. It is the only event in the game
# that restores music around a battle the player can lose.
# Here a restore is skipped when the player blacked out since the music was
# memorized, so the Center keeps its own music.
#===============================================================================
class Game_Temp
  attr_accessor :kif_started_over
end

alias kif_bm_pbStartOver pbStartOver unless defined?(kif_bm_pbStartOver)

def pbStartOver(*args)
  $game_temp.kif_started_over = true if $game_temp
  return kif_bm_pbStartOver(*args)
end

class Interpreter
  alias kif_bm_command_247 command_247 unless method_defined?(:kif_bm_command_247)
  alias kif_bm_command_248 command_248 unless method_defined?(:kif_bm_command_248)

  def command_247
    $game_temp.kif_started_over = false if $game_temp
    return kif_bm_command_247
  end

  def command_248
    if $game_temp && $game_temp.kif_started_over
      $game_temp.kif_started_over = false
      KIF.log("Blackout: the event's music restore was skipped (the player is in the Pokémon Center)") if defined?(KIF.log)
      return true
    end
    return kif_bm_command_248
  end
end
