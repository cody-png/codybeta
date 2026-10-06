# nerf: remove x kg from each generated pokemon

def generate_weight_contest_entries(species, level, resultsVariable, nerf = 0)
  # echoln "Generating Pokemon"
  pokemon1 = pbGenerateWildPokemon(species, level) # Pokemon.new(species,level)
  pokemon2 = pbGenerateWildPokemon(species, level) # Pokemon.new(species,level)
  new_weights = []
  new_weights << calculate_pokemon_weight(pokemon1, nerf)
  new_weights << calculate_pokemon_weight(pokemon2, nerf)
  echoln new_weights
  echoln "(nerfed by -#{nerf})"
  pbSet(resultsVariable, new_weights.max)

end