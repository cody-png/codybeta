# frozen_string_literal: true

class PokemonIconSprite
  def createFusionIcon()

    bodyPoke_number = getBodyID(pokemon.species)
    headPoke_number = getHeadID(pokemon.species, bodyPoke_number)

    bodyPoke = GameData::Species.get(bodyPoke_number).species
    headPoke = GameData::Species.get(headPoke_number).species

    dexNum = getDexNumberForSpecies(@pokemon.species)
    basePath = sprintf("Graphics/Pokemon/FusionIcons/icon%03d", dexNum)

    shinySuffix = ""
    shinySuffix += "_bodyShiny" if @pokemon.headShiny?
    shinySuffix += "_headShiny" if @pokemon.bodyShiny?

    fusedIconFilePath = sprintf("%s%s.png", basePath, shinySuffix)

    if File.exist?(fusedIconFilePath)
      return AnimatedBitmap.new(fusedIconFilePath)
    end

    headSprite = AnimatedBitmap.new(GameData::Species.icon_filename(headPoke, @pokemon.spriteform_head, nil, @pokemon.headShiny?))
    bodySprite = AnimatedBitmap.new(GameData::Species.icon_filename(bodyPoke, @pokemon.spriteform_body, nil, @pokemon.bodyShiny?))

    fusedIcon = Bitmap.new(headSprite.width, headSprite.height)
    fusedIcon.blt(0, 0, headSprite.bitmap, Rect.new(0, 0, headSprite.width, headSprite.height))

    for i in 0...bodySprite.width
      for j in ((bodySprite.height / 2) + Settings::FUSION_ICON_SPRITE_OFFSET)...bodySprite.height
        pixel = bodySprite.bitmap.get_pixel(i, j)
        fusedIcon.set_pixel(i, j, pixel)
      end
    end

    fusedIcon.save_to_png(fusedIconFilePath)
    return AnimatedBitmap.new(fusedIconFilePath)
  end
end