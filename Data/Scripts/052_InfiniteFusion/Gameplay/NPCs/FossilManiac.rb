def fossilsGuyBattle(level = 20, end_message = "")
  team = getFossilsGuyTeam(level)
  customTrainerBattle("Miguel",
                      :SUPERNERD,
                      team,
                      level,
                      end_message
  )

end

def getFossilsGuyTeam(level)
  base_poke_evolution_level = 20
  fossils_evolution_level_1 = 30
  fossils_evolution_level_2 = 50

  fossils = []
  base_poke = level <= base_poke_evolution_level ? :B88H109 : :B89H110
  team = []
  team << Pokemon.new(base_poke, level)

  # Mt. Moon fossil
  if $game_switches[SWITCH_PICKED_HELIC_FOSSIL]
    fossils << :KABUTO if level < fossils_evolution_level_1
    fossils << :KABUTOPS if level >= fossils_evolution_level_1
  elsif $game_switches[SWITCH_PICKED_DOME_FOSSIL]
    fossils << :OMANYTE if level < fossils_evolution_level_1
    fossils << :OMASTAR if level >= fossils_evolution_level_1
  end

  # S.S. Anne fossil
  if $game_switches[SWITCH_PICKED_LILEEP_FOSSIL]
    fossils << :ANORITH if level < fossils_evolution_level_1
    fossils << :ARMALDO if level >= fossils_evolution_level_1

  elsif $game_switches[SWITCH_PICKED_ANORITH_FOSSIL]
    fossils << :LILEEP if level < fossils_evolution_level_1
    fossils << :CRADILY if level >= fossils_evolution_level_1
  end
  # Celadon fossil
  if $game_switches[SWITCH_PICKED_ARMOR_FOSSIL]
    fossils << :CRANIDOS if level < fossils_evolution_level_2
    fossils << :RAMPARDOS if level >= fossils_evolution_level_2

  elsif $game_switches[SWITCH_PICKED_SKULL_FOSSIL]
    fossils << :SHIELDON if level < fossils_evolution_level_2
    fossils << :BASTIODON if level >= fossils_evolution_level_2
  end

  skip_next = false
  for index in 0..fossils.length
    if index == fossils.length - 1
      team << Pokemon.new(fossils[index], level)
    else
      if skip_next
        skip_next = false
        next
      end
      head_poke = fossils[index]
      body_poke = fossils[index + 1]
      if head_poke && body_poke
        newPoke = getFusionSpecies(dexNum(body_poke), dexNum(head_poke))
        team << Pokemon.new(newPoke, level)
        skip_next = true
      end
    end
  end
  return team
end