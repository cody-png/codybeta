#===============================================================================
#  Battler Bitmap Loading Functions for EBDX
#  Ported from Elite Battle DX's Battler Bitmaps.rb
#===============================================================================

#===============================================================================
#  Loads an animated BitmapWrapper for Pokemon
#===============================================================================
def pbLoadPokemonBitmap(pokemon, back = false, scale = nil, speed = 2)
  scale ||= back ? EliteBattle::BACK_SPRITE_SCALE : EliteBattle::FRONT_SPRITE_SCALE
  return pbLoadPokemonBitmapSpecies(pokemon, pokemon.species, back, scale, speed)
end

#===============================================================================
#  Loads an animated BitmapWrapper for Pokemon species
#===============================================================================
def pbLoadPokemonBitmapSpecies(pokemon, species, back = false, scale = nil, speed = 2)
  ret = nil
  pokemon = pokemon.pokemon if pokemon.respond_to?(:pokemon)
  species = pokemon.species if species.nil? && pokemon.respond_to?(:species)

  # return question marks if no species provided
  if species.nil?
    return BitmapEBDX.new("Graphics/EBDX/Battlers/000", scale || EliteBattle::FRONT_SPRITE_SCALE)
  end

  # applies scale
  scale ||= back ? EliteBattle::BACK_SPRITE_SCALE : EliteBattle::FRONT_SPRITE_SCALE

  # gets additional scale (if applicable)
  s = EliteBattle.get_data(species, :Species, (back ? :BACKSCALE : :SCALE), (pokemon.form rescue 0))
  scale = s if !s.nil? && s.is_a?(Numeric)

  # get more metrics
  s = EliteBattle.get_data(species, :Species, :SPRITESPEED, (pokemon.form rescue 0))
  speed = s if !s.nil? && s.is_a?(Numeric)

  bitmapFileName = nil

  if pokemon.respond_to?(:egg?) && pokemon.egg?
    bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/%s", species) rescue nil
    if !pbResolveBitmap(bitmapFileName)
      bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/%03d", GameData::Species.get(species).id_number) rescue nil
      if !pbResolveBitmap(bitmapFileName)
        bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/000")
      end
    end
    bitmapFileName = pbResolveBitmap(bitmapFileName)
  else
    shiny = pokemon.shiny? rescue false
    # Check for super shiny (KIF may have different implementation)
    if pokemon.respond_to?(:superVariant) && pokemon.respond_to?(:superShiny?)
      shiny = pokemon.superVariant if (!pokemon.superVariant.nil? && pokemon.superShiny?)
    end
    params = [
      species,
      back,
      (pokemon.female? rescue false),
      shiny,
      (pokemon.form rescue 0),
      (pokemon.shadowPokemon? rescue false),
      (pokemon.respond_to?(:dynamax) ? pokemon.dynamax : false),
      (pokemon.respond_to?(:gfactor) && pokemon.respond_to?(:dynamax) ? (pokemon.dynamax && pokemon.gfactor) : false)
    ]
    bitmapFileName = pbCheckPokemonBitmapFiles(params)
  end

  # Fallback to vanilla Essentials sprites if EBDX sprites not found
  if bitmapFileName.nil?
    # Try vanilla sprite path
    bitmapFileName = tryVanillaPokemonSprite(pokemon, back)
  end

  if bitmapFileName.nil?
    bitmapFileName = "Graphics/EBDX/Battlers/000"
    # Log warning
    echoln "[EBDX] Missing sprite for #{pokemon.species rescue 'unknown'} (back=#{back})"
  end

  animatedBitmap = BitmapEBDX.new(bitmapFileName, scale, speed) if bitmapFileName
  ret = animatedBitmap if bitmapFileName

  # adjusts for custom animation loops
  data = EliteBattle.get_data(species, :Species, :FRAMEANIMATION, (pokemon.form rescue 0))
  unless data.nil?
    ret.compile_loop(data) if ret.respond_to?(:compile_loop)
  end

  # applies super shiny hue
  if pokemon.respond_to?(:superHue) && pokemon.superHue && ret.respond_to?(:hue_change) && ret.respond_to?(:changedHue?)
    ret.hue_change(pokemon.superHue) if !ret.changedHue?
  end

  # refreshes bitmap
  ret.deanimate if ret.respond_to?(:deanimate)
  return ret
end

#===============================================================================
#  Try to find vanilla Essentials sprite as fallback
#===============================================================================
def tryVanillaPokemonSprite(pokemon, back)
  species = pokemon.species rescue nil
  return nil if species.nil?

  form = pokemon.form rescue 0
  shiny = pokemon.shiny? rescue false
  female = pokemon.female? rescue false
  shadow = pokemon.shadowPokemon? rescue false

  # Try GameData::Species sprite methods
  if back
    file = GameData::Species.back_sprite_filename(species, form, female ? 1 : 0, shiny, shadow) rescue nil
  else
    file = GameData::Species.front_sprite_filename(species, form, female ? 1 : 0, shiny, shadow) rescue nil
  end

  return pbResolveBitmap(file) if file && pbResolveBitmap(file)
  return nil
end

#===============================================================================
#  Loads animated BitmapWrapper for species
#===============================================================================
def pbLoadSpeciesBitmap(species, female = false, form = 0, shiny = false, shadow = false, back = false, egg = false, scale = nil)
  ret = nil

  # return question marks if no species provided
  if species.nil?
    return BitmapEBDX.new("Graphics/EBDX/Battlers/000", scale || EliteBattle::FRONT_SPRITE_SCALE)
  end

  # applies scale
  scale ||= back ? EliteBattle::BACK_SPRITE_SCALE : EliteBattle::FRONT_SPRITE_SCALE

  # gets additional scale (if applicable)
  s = EliteBattle.get_data(species, :Species, (back ? :BACKSCALE : :SCALE), (form rescue 0))
  scale = s if !s.nil? && s.is_a?(Numeric)

  # check sprite
  if egg
    bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/%s", species) rescue nil
    if !pbResolveBitmap(bitmapFileName)
      bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/%03d", GameData::Species.get(species).id_number) rescue nil
      if !pbResolveBitmap(bitmapFileName)
        bitmapFileName = sprintf("Graphics/EBDX/Battlers/Eggs/000")
      end
    end
    bitmapFileName = pbResolveBitmap(bitmapFileName)
  else
    bitmapFileName = pbCheckPokemonBitmapFiles([species, back, female, shiny, form, shadow, false, false])
  end

  # Fallback to vanilla if not found
  if bitmapFileName.nil?
    if back
      bitmapFileName = GameData::Species.back_sprite_filename(species, form, female ? 1 : 0, shiny, shadow) rescue nil
    else
      bitmapFileName = GameData::Species.front_sprite_filename(species, form, female ? 1 : 0, shiny, shadow) rescue nil
    end
    bitmapFileName = pbResolveBitmap(bitmapFileName) if bitmapFileName
  end

  if bitmapFileName
    ret = BitmapEBDX.new(bitmapFileName, scale)
  end

  # adjusts for custom animation loops
  data = EliteBattle.get_data(species, :Species, :FRAMEANIMATION, form)
  unless data.nil?
    ret.compile_loop(data) if ret && ret.respond_to?(:compile_loop)
  end

  # refreshes bitmap
  ret.deanimate if ret && ret.respond_to?(:deanimate)
  return ret
end

#===============================================================================
#  Returns error message upon missing sprites
#===============================================================================
def missingPokeSpriteError(pokemon, back)
  error_b = back ? "Back" : "Front"
  error_b += "Shiny" if pokemon.shiny? rescue false
  error_b += "/Female/" if pokemon.female? rescue false
  error_b += " shadow" if pokemon.shadowPokemon? rescue false
  error_b += " form #{pokemon.form} " if (pokemon.form rescue 0) > 0
  return "Missing the #{error_b} sprite for #{GameData::Species.get(pokemon.species).real_name rescue 'unknown'}!"
end

#===============================================================================
#  New methods of handing Pokemon sprite name references
#===============================================================================
def pbCheckPokemonBitmapFiles(params)
  species = params[0]; back = params[1]; factors = []
  factors.push([5, params[5], false]) if params[5] && params[5] != false # shadow
  factors.push([2, params[2], false]) if params[2] && params[2] != false # gender
  factors.push([3, params[3], false]) if params[3] && params[3] != false # shiny
  factors.push([6, params[6], false]) if params[6] && params[6] != false # dynamaxed
  factors.push([7, params[7], false]) if params[7] && params[7] != false # gigantimaxed
  factors.push([4, params[4].to_s, ""]) if params[4] && params[4].to_s != "" && params[4].to_s != "0" # form
  tshadow = false; tgender = false; tshiny = false; tform = ""

  for i in 0...(2**factors.length)
    for j in 0...factors.length
      case factors[j][0]
      when 2   # gender
        tgender = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      when 3   # shiny
        tshiny = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      when 4   # form
        tform = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      when 5   # shadow
        tshadow = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      when 6   # dynamaxed
        tdyna = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      when 7   # gigantimaxed
        tgigant = ((i/(2**j))%2 == 0) ? factors[j][1] : factors[j][2]
      end
    end
    folder = "Graphics/EBDX/Battlers/"
    if tshiny && back
      folder += "BackShiny"
    elsif tshiny
      folder += "FrontShiny"
    elsif back
      folder += "Back"
    else
      folder += "Front"
    end
    dirs = []
    dirs.push("/Gigantamax") if defined?(tgigant) && tgigant
    dirs.push("/Dynamax") if defined?(tdyna) && tdyna && !(defined?(tgigant) && tgigant)
    dirs.push("/Female") if tgender
    dirs.push("")

    for dir in dirs
      bitmapFileName = sprintf("#{folder}#{dir}/%s%s%s", species, (tform != "" ? "_" + tform : ""), tshadow ? "_shadow" : "") rescue nil
      ret = pbResolveBitmap(bitmapFileName)
      return ret if ret
    end
    for dir in dirs
      begin
        bitmapFileName = sprintf("#{folder}#{dir}/%03d%s%s", GameData::Species.get(species).id_number, (tform != "" ? "_" + tform : ""), tshadow ? "_shadow" : "")
        ret = pbResolveBitmap(bitmapFileName)
        return ret if ret
      rescue
        # Species not found, continue
      end
    end
  end
  return nil
end

#===============================================================================
#  Returns full path for sprite
#===============================================================================
def pbPokemonBitmapFile(species, shiny, back = false)
  folder = "Graphics/EBDX/Battlers/"
  if shiny && back
    folder += "BackShiny/"
  elsif shiny
    folder += "FrontShiny/"
  elsif back
    folder += "Back/"
  else
    folder += "Front/"
  end
  name = sprintf("#{folder}%s", species) rescue nil
  ret = pbResolveBitmap(name)
  return ret if ret
  begin
    name = sprintf("#{folder}%03d", GameData::Species.get(species).id_number)
    return pbResolveBitmap(name)
  rescue
    return nil
  end
end
