#===============================================================================
# SCOPE-02 – PIF fixes: the PC box keeps no picture that nobody draws
#
# A box is built with an icon in every one of its 30 slots, an empty one in a
# slot with no Pokemon. Putting a Pokemon down (setPokemon, and
# placePokemonMulti for the multi-select) replaced that empty icon with the
# held one and never disposed it, so each placement into an empty slot left
# one sprite behind until the whole PC was closed. The icon being replaced is
# now disposed first.
#===============================================================================
module KIF
  module PCBoxSlotLeak
    def setPokemon(index, sprite)
      KIF::PCBoxSlotLeak.drop(@pokemonsprites, index, sprite)
      super
    end

    def placePokemonMulti(index, sprites)
      ax = index % PokemonBox::BOX_WIDTH
      ay = (index / PokemonBox::BOX_WIDTH).floor
      sprites.each { |s| KIF::PCBoxSlotLeak.drop(@pokemonsprites, (s.heldox + ax) + (s.heldoy + ay) * PokemonBox::BOX_WIDTH, s) }
      super
    end

    def self.drop(list, index, incoming)
      old = list[index]
      old.dispose if old && !old.equal?(incoming) && !old.disposed?
    end
  end
end

PokemonBoxSprite.prepend(KIF::PCBoxSlotLeak) unless PokemonBoxSprite.ancestors.include?(KIF::PCBoxSlotLeak)
