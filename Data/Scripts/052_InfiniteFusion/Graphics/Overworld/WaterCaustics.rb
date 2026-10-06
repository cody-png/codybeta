def addWaterCausticsEffect(fog_name = "caustic1", opacity = 16)
  $game_map.fog_name = fog_name
  $game_map.fog_hue = 0
  $game_map.fog_opacity = opacity
  #$game_map.fog_blend_type = @parameters[4]
  $game_map.fog_zoom = 200
  $game_map.fog_sx = 2
  $game_map.fog_sy = 2

  $game_map.setFog2(fog_name, -3, 0, opacity,)
end

def stopWaterCausticsEffect()
  $game_map.fog_opacity = 0
  $game_map.eraseFog2()
end