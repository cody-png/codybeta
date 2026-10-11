#===============================================================================
# SCOPE-02 – PIF fix: "Prompt Nicknames" Off is honoured everywhere
# PIF 6.8.2 only checks the option when a Pokémon is caught in battle or an
# Egg hatches. Gifts (pbAddPokemon), Bug Contest catches, triple fusions and
# K-Eggs go through the global pbNickname, which always asked (Cody's
# playthrough, 2026-10-11). Always on: it only makes PIF's own setting work.
#===============================================================================
alias kif_pn_pbNickname pbNickname unless defined?(kif_pn_pbNickname)

def pbNickname(pkmn)
  return if $PokemonSystem && $PokemonSystem.respond_to?(:prompt_nicknames) && !$PokemonSystem.prompt_nicknames
  kif_pn_pbNickname(pkmn)
end
