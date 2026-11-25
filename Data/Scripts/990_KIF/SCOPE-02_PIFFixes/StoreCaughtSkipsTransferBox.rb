#===============================================================================
# SCOPE-02 – PIF fix: a catch or hatch never goes into the Transfer Box
# The Transfer Box is one of $PokemonStorage.boxes, so with every normal box full
# pbStoreCaught filled it and full? counted its free slots. The box inside a save
# is only as new as that save, so storing there wrote an old list (plus the new
# Pokémon) over the file every save shares, and saved the game mid-catch.
# Nuzlocke and Soul Link already skip this box; "PC full" is now reported instead.
#===============================================================================
KIF.guard_base("014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb", 93468877,
               "PokemonStorage#full?, pbStoreCaught")

class PokemonStorage
  # Copy of 014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb:160-165 without the Transfer Box
  def full?
    for i in 0...self.maxBoxes
      next if @boxes[i].is_a?(StorageTransferBox)
      return false if !@boxes[i].full?
    end
    return true
  end

  # Copy of 014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb:249-275 without the Transfer Box
  def pbStoreCaught(pkmn)
    if self[@currentBox].is_a?(StorageTransferBox)
      @currentBox = 0
    end

    if @currentBox >= 0
      pkmn.time_form_set = nil
    end
    for i in 0...maxPokemon(@currentBox)
      if self[@currentBox, i] == nil
        self[@currentBox, i] = pkmn
        return @currentBox
      end
    end
    for j in 0...self.maxBoxes
      next if self[j].is_a?(StorageTransferBox)
      for i in 0...maxPokemon(j)
        if self[j, i] == nil
          self[j, i] = pkmn
          @currentBox = j
          return @currentBox
        end
      end
    end
    return -1
  end
end
