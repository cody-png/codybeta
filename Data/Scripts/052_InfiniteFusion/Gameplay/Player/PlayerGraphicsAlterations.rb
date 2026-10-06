def playPokeFluteAnimation
  # return if $Trainer.outfit != 0
  # $game_player.setDefaultCharName("players/pokeflute", 0, false)
  # Graphics.update
  # Input.update
  # pbUpdateSceneMap
end

def restoreDefaultCharacterSprite(charset_number = 0)
  meta = GameData::Metadata.get_player($Trainer.character_ID)
  $game_player.setDefaultCharName(nil, 0, false)
  $game_player.character_name = meta[1]
  Graphics.update
  Input.update
  pbUpdateSceneMap
end
