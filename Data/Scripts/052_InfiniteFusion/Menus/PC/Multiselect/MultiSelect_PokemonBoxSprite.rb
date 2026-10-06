class PokemonBoxSprite < SpriteWrapper
  def placePokemonMulti(index, sprites)
    arrowX = index % PokemonBox::BOX_WIDTH
    arrowY = (index / PokemonBox::BOX_WIDTH).floor
    for sprite in sprites
      spriteIndex = (sprite.heldox + arrowX) + (sprite.heldoy + arrowY) * PokemonBox::BOX_WIDTH
      @pokemonsprites[spriteIndex] = sprite
      @pokemonsprites[spriteIndex].refresh
    end
    if sprites.length > 0
      refresh
    end
  end

  def grabPokemonMulti(indexes, arrowIndex, arrow)
    grabbedSprites = []
    arrowX = arrowIndex % PokemonBox::BOX_WIDTH
    arrowY = (arrowIndex / PokemonBox::BOX_WIDTH).floor
    for index in indexes
      sprite = @pokemonsprites[index]
      if sprite && sprite.pokemon && !sprite.disposed?
        sprite.heldox = (index % PokemonBox::BOX_WIDTH) - arrowX
        sprite.heldoy = (index / PokemonBox::BOX_WIDTH).floor - arrowY
        grabbedSprites.push(sprite)
        @pokemonsprites[index] = nil
      end
    end
    if grabbedSprites.length > 0
      arrow.grabMulti(grabbedSprites)
      update
    end
  end
end






