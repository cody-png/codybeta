#===============================================================================
# SCOPE-02 – PIF fix: Illusion never copies an Egg or a fainted Pokémon
# PIF 6.8.2's PokeBattle_Battle#pbLastInTeam has the Essentials check
# `|| !pkmn.able?` commented out, so a Zoroark line fusion came out looking
# like the Egg at the end of the party ("What will Egg do?", Cody 2026-10-11).
# Copy of the base method with that check back. Always on (a bug fix).
#===============================================================================
KIF.guard_base("011_Battle/003_Battle/002_PokeBattle_Battle.rb", 2321919076,
               "pbLastInTeam (Illusion copies the last able Pokémon)")

class PokeBattle_Battle
  def pbLastInTeam(idxBattler)
    party       = pbParty(idxBattler)
    partyOrders = pbPartyOrder(idxBattler)
    idxPartyStart, idxPartyEnd = pbTeamIndexRangeFromBattlerIndex(idxBattler)
    ret = -1
    party.each_with_index do |pkmn,i|
      next if i<idxPartyStart || i>=idxPartyEnd   # Check the team only
      next if !pkmn || !pkmn.able?   # Can't copy a fainted Pokémon or egg (KIF: check restored)
      ret = i if ret < 0 || partyOrders[i] > partyOrders[ret]
    end
    return ret
  end
end

# The battle box kept the disguise's name after the illusion wore off (PIF
# only swaps the sprite there): the box is redrawn with the real Pokémon.
class PokeBattle_Scene
  alias kif_ill_pbChangePokemon pbChangePokemon unless method_defined?(:kif_ill_pbChangePokemon)
  def pbChangePokemon(idxBattler, pkmn)
    kif_ill_pbChangePokemon(idxBattler, pkmn)
    idx = idxBattler.respond_to?(:index) ? idxBattler.index : idxBattler
    pbRefreshOne(idx) if respond_to?(:pbRefreshOne)
  end
end
