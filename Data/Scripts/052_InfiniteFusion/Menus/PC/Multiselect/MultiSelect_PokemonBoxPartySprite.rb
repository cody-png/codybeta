class PokemonBoxPartySprite < SpriteWrapper
  def placePokemonMulti(index, sprites)
    partyIndex = @pokemonsprites.count { |i| i && i.pokemon && !i.disposed? }
    for sprite in sprites
      @pokemonsprites[partyIndex] = sprite
      partyIndex += 1
    end
    if sprites.length > 0
      @pokemonsprites.compact!
      refresh
    end
  end

  def grabPokemonMulti(indexes, arrowIndex, arrow)
    grabbedSprites = []
    arrowX = arrowIndex % 2
    arrowY = (arrowIndex / 2).floor
    for index in indexes
      sprite = @pokemonsprites[index]
      if sprite && sprite.pokemon && !sprite.disposed?
        sprite.heldox = (index % 2) - arrowX
        sprite.heldoy = (index / 2).floor - arrowY
        grabbedSprites.push(sprite)
        @pokemonsprites[index] = nil
      end
    end
    if grabbedSprites.length > 0
      arrow.grabMulti(grabbedSprites)
      @pokemonsprites.compact!
      refresh
    end
  end
end
