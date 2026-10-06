def setDifficulty(index)
  $Trainer.selected_difficulty = index
  case index
  when 0 # EASY
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = true
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = false
  when 1 # NORMAL
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = false
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = false
  when 2 # HARD
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = false
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = true
  end
end

# Old menu for changing difficulty - unused
def change_game_difficulty(down_only = false)
  message = _INTL("The game is currently on {1} difficulty.",get_difficulty_text())
  pbMessage(message)

  choice_easy = _INTL("Easy")
  choice_normal = _INTL("Normal")
  choice_hard = _INTL("Hard")
  choice_cancel = _INTL("Cancel")

  available_difficulties = []
  currentDifficulty = get_current_game_difficulty
  if down_only
    if currentDifficulty == :HARD
      available_difficulties << choice_hard
      available_difficulties << choice_normal
      available_difficulties << choice_easy
    elsif currentDifficulty == :NORMAL
      available_difficulties << choice_normal
      available_difficulties << choice_easy
    elsif currentDifficulty == :EASY
      available_difficulties << choice_easy
    end
  else
    available_difficulties << choice_easy
    available_difficulties << choice_normal
    available_difficulties << choice_hard
  end
  available_difficulties << choice_cancel
  index = pbMessage(_INTL("Select a new difficulty"), available_difficulties, available_difficulties[-1])
  choice = available_difficulties[index]
  case choice
  when choice_easy
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = true
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = false
  when choice_normal
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = false
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = false
  when choice_hard
    $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = false
    $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = true
  when choice_cancel
    return
  end

  message = _INTL("The game is currently on {1} difficulty.",get_difficulty_text())
  pbMessage(message)
end

# Get difficulty for displaying in-game
def getDisplayDifficulty
  if $game_switches[SWITCH_GAME_DIFFICULTY_EASY] || $Trainer.lowest_difficulty <= 0
    return getDisplayDifficultyFromIndex(0)
  elsif $Trainer.lowest_difficulty <= 1
    return getDisplayDifficultyFromIndex(1)
  elsif $game_switches[SWITCH_GAME_DIFFICULTY_HARD]
    return getDisplayDifficultyFromIndex(2)
  else
    return getDisplayDifficultyFromIndex(1)
  end
end

def getDisplayDifficultyFromIndex(difficultyIndex)
  return _INTL("Easy") if difficultyIndex == 0
  return _INTL("Normal") if difficultyIndex == 1
  return _INTL("Hard") if difficultyIndex == 2
  return "???"
end