#===============================================================================
# SCOPE-02 – PIF fix: a catch or hatch uses the Transfer Box last, from a fresh copy
# The Transfer Box is one of $PokemonStorage.boxes, so with every normal box full
# pbStoreCaught filled it. The box inside a save is only as new as that save, so
# storing there wrote an old list (plus the new Pokémon) over the file every save
# shares. Now the normal boxes come first; the Transfer Box is the last resort, is
# reloaded from the shared file before a Pokémon goes in, and the file is written at
# once (StorageTransferBox#[]=). Many PIF callers ignore a "PC full" result (the
# Pokémon would be gone), so the box can't just be skipped. On a randomized save it
# is only a normal box and keeps its place in the order.
#===============================================================================
KIF.guard_base("014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb", 93468877,
               "PokemonStorage#full?, pbStoreCaught")

class PokemonStorage
  # Box numbers to fill, in order: the usable Transfer Box last
  def kif_box_order
    (0...self.maxBoxes).partition { |j| !(@boxes[j].is_a?(StorageTransferBox) && @boxes[j].can_use_transfer_box?) }.flatten
  end

  # Copy of 014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb:160-165 with the Transfer Box last and fresh
  def full?
    kif_box_order.each do |j|
      @boxes[j].loadTransferBoxPokemon if @boxes[j].is_a?(StorageTransferBox) && @boxes[j].can_use_transfer_box?
      return false if !@boxes[j].full?
    end
    return true
  end

  # Copy of 014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb:249-275 with the Transfer Box last and fresh
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
    for j in kif_box_order
      tb = self[j].is_a?(StorageTransferBox) && self[j].can_use_transfer_box?
      self[j].loadTransferBoxPokemon if tb
      for i in 0...maxPokemon(j)
        if self[j, i] == nil
          self[j, i] = pkmn
          next unless self[j, i].equal?(pkmn)   # the Transfer Box refuses a duplicate id
          @currentBox = j unless tb
          return j
        end
      end
    end
    return -1
  end
end
