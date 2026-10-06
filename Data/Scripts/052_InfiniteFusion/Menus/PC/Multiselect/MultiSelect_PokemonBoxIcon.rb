class PokemonBoxIcon < IconSprite
  attr_accessor :heldox
  attr_accessor :heldoy

  alias _pokemonBoxIconInitialize initialize

  def initialize(*args)
    @heldox = 0
    @heldoy = 0
    _pokemonBoxIconInitialize(*args)
  end
end
