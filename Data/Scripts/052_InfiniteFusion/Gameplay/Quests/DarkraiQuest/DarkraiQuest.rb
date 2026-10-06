KANTO_DARKNESS_STAGE_1 = [
  50, # Lavender town
  409, # Route 8
  351, # Route 9 (east)
  495, # Route 9 (west)
  154, # Route 10
  108, # Saffron city
  1, # Cerulean City
  387, # Cerulean City (race)
  106, # Route 4
  8, # Route 24
  9, # Route 25
  400, # Pokemon Tower
  401, # Pokemon Tower
  402, # Pokemon Tower
  403, # Pokemon Tower
  467, # Pokemon Tower
  468, # Pokemon Tower
  469, # Pokemon Tower
  159, # Route 12
  349, # Rock tunnel
  350, # Rock tunnel
  512, # Rock tunnel (outdoor)
  12, # Route 5

]
KANTO_DARKNESS_STAGE_2 = [
  95, # Celadon city
  436, # Celadon city dept store (roof)
  143, # Route 23
  167, # Crimson city
  413, # Route 7
  438, # Route 16
  146, # Route 17
  106, # Route 4
  19, # Vermillion City
  36, # S.S. Anne deck
  16, # Route 6
  437, # Route 13
  155, # Route 11
  140, # Diglett cave
  398, # Diglett cave
  399, # Diglett cave
]
KANTO_DARKNESS_STAGE_3 = [
  472, # Fuchsia city
  445, # Safari Zone 1
  484, # Safari Zone 2
  485, # Safari Zone 3
  486, # Safari Zone 4
  487, # Safari Zone 5
  444, # Route 15
  440, # Route 14
  712, # Creepy house
  517, # Route 18
  57, # Route 19
  227, # Route 19 (underwater)
  56, # Route 19 (surf race)
  58, # Route 20
  480, # Route 20 underwater 1
  228, # Route 20 underwater 2
  98, # Cinnabar island
  58, # Route 21
  827, # Mt. Moon summit
]
KANTO_DARKNESS_STAGE_4 = KANTO_OUTDOOR_MAPS

def darknessEffectOnCurrentMap()
  return if !$game_switches
  return if !$game_switches[SWITCH_KANTO_DARKNESS]
  return darknessEffectOnMap($game_map.map_id)
end

def darknessEffectOnMap(map_id)
  return if !$game_switches
  return if !$game_switches[SWITCH_KANTO_DARKNESS]
  return if !KANTO_OUTDOOR_MAPS.include?(map_id)
  dark_maps = []
  dark_maps += KANTO_DARKNESS_STAGE_1 if $game_switches[SWITCH_KANTO_DARKNESS_STAGE_1]
  dark_maps += KANTO_DARKNESS_STAGE_2 if $game_switches[SWITCH_KANTO_DARKNESS_STAGE_2]
  dark_maps += KANTO_DARKNESS_STAGE_3 if $game_switches[SWITCH_KANTO_DARKNESS_STAGE_3]
  dark_maps = KANTO_OUTDOOR_MAPS if $game_switches[SWITCH_KANTO_DARKNESS_STAGE_4]
  return dark_maps.include?(map_id)
end

def apply_darkness()
  $PokemonTemp.darknessSprite = DarknessSprite.new
  darkness = $PokemonTemp.darknessSprite
  darkness.radius = 276
  while darkness.radius > 64
    Graphics.update
    Input.update
    pbUpdateSceneMap
    darkness.radius -= 4
  end
  $PokemonGlobal.flashUsed = false
  $PokemonTemp.darknessSprite.dispose
  Events.onMapSceneChange.trigger(self, $scene, true)
end

def isInMtMoon()
  mt_moon_maps = [102, 103, 105, 496, 104]
  return mt_moon_maps.include?($game_map.map_id)
end

def getMtMoonDirection()
  maps_east = [380, # Pewter city
               490, # Route 3
               303, # indigo plateau
               145, # Route 26
               147, # Route 27
  ]
  maps_south = [
    8, # Route 24
    9, # Route 25
    143, # Route 23
    167, # Crimson city
  ]
  maps_west = [
    106, # route 4
    1, # cerulean
    495, # route 9
    351, # route 9
    10 # cerulean cape
  ]
  return 2 if maps_south.include?($game_map.map_id)
  return 4 if maps_west.include?($game_map.map_id)
  return 6 if maps_east.include?($game_map.map_id)
  return 8 # north (most maps)
end

def getNextLunarFeatherHint()
  nb_feathers = pbGet(VAR_LUNAR_FEATHERS)
  case nb_feathers
  when 0
    return _INTL("Find the first feather in the northernmost dwelling in the port of exquisite sunsets...")
  when 1
    return _INTL("Amidst a nursery for Pokémon youngsters, the second feather hides, surrounded by innocence.")
  when 2
    return _INTL("Find the next one in the inn where water meets rest")
  when 3
    return _INTL("Find the next one inside the lone house in the city at the edge of civilization.")
  when 4
    return _INTL("The final feather lies back in the refuge for orphaned Pokémon...")
  else
    return _INTL("Lie in the bed... Bring me the feathers...")
  end
end