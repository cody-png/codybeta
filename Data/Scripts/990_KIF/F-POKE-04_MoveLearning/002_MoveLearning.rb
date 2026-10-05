#===============================================================================
# F-POKE-04 – Move learning: pre-evolution relearn, Event Moves, Fusion Tutor
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon.rb:1574-1612  getMoveRelearnerList (Reïzod),
#                                         getEventMoveList / get_event_moves
#   016_UI/021_UI_MoveRelearner.rb:166    relearner uses getMoveRelearnerList
#   052_AddOns/EggMoveTutor.rb:15-17      event moves at the Egg Move Tutor
#   052_AddOns/FusionMoveTutor.rb:101-173 ~18 moves un-commented
#   016_UI/015_UI_Options.rb:2347-2351    "Event Moves" (default Off)
#
# Move Relearner: also offers the level-up moves of every pre-evolution, up
#   to the Pokémon's level (always on, like KIF).
# Event Moves (option): the Egg Move Tutor also offers the event moves of the
#   Pokémon, its pre-evolutions and, for fusions, both parts (HungryPickle,
#   list by REKT1029 in 001_EventMoves.rb).
# Fusion Move Tutor: the moves PIF left commented out are offered again.
#
# 6.8.2 adaptations: wrappers only. Moves missing from 6.8.2's move data are
# skipped instead of crashing the menu.
#===============================================================================
KIF::Options.define(:eventmoves, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Event Moves"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.eventmoves },
                 proc { |value| $PokemonSystem.eventmoves = value },
                 [_INTL("The Egg Move Tutor only teaches egg moves."),
                  _INTL("Event Moves are available at the Egg Move Tutor.")])
}

module KIF
  module MoveLearning
    def self.move_ok?(move)
      return GameData::Move.exists?(move)
    rescue
      return false
    end

    # Species and all its pre-evolutions (closest first)
    def self.prevo_chain(species)
      chain = []
      current = species
      10.times do
        prev = GameData::Species.get(current).get_previous_species rescue current
        break if prev.nil? || prev.to_s == current.to_s || chain.include?(prev)
        chain << prev
        current = prev
      end
      return chain
    end

    # KIF get_event_moves
    def self.event_moves_of(species)
      return [] unless defined?(EVENT_MOVES)
      ret = EVENT_MOVES.fetch(species, []).dup
      prevo_chain(species).each { |s| ret |= EVENT_MOVES.fetch(s, []) }
      return ret
    end
  end
end

class Pokemon
  # KIF getMoveRelearnerList: pre-evolution level-up moves, then own moves
  def getMoveRelearnerList
    moves = species_data.moves.clone
    KIF::MoveLearning.prevo_chain(species).each do |s|
      moves.unshift(*GameData::Species.get(s).moves)
    end
    return moves
  end

  # KIF getEventMoveList
  def getEventMoveList
    sp = species_data
    if sp.is_a?(GameData::FusedSpecies) && sp.head_pokemon && sp.body_pokemon
      list = KIF::MoveLearning.event_moves_of(sp.body_pokemon.species) |
             KIF::MoveLearning.event_moves_of(sp.head_pokemon.species)
    else
      list = KIF::MoveLearning.event_moves_of(self.species)
    end
    return list.select { |m| KIF::MoveLearning.move_ok?(m) }
  end
end

class MoveRelearnerScreen
  alias kif_ml_pbGetRelearnableMoves pbGetRelearnableMoves unless method_defined?(:kif_ml_pbGetRelearnableMoves)

  def pbGetRelearnableMoves(pkmn)
    moves = kif_ml_pbGetRelearnableMoves(pkmn)
    return moves if !pkmn || pkmn.egg? || pkmn.shadowPokemon?
    KIF::MoveLearning.prevo_chain(pkmn.species).each do |s|
      GameData::Species.get(s).moves.each do |m|
        next if m[0] > pkmn.level || pkmn.hasMove?(m[1]) || moves.include?(m[1])
        moves.push(m[1]) if KIF::MoveLearning.move_ok?(m[1])
      end
    end
    return moves
  end
end

class MoveRelearner_Scene
  alias kif_ml_pbStartScene pbStartScene unless method_defined?(:kif_ml_pbStartScene)

  # The Egg Move Tutor passes its egg move list here; add the event moves.
  def pbStartScene(pokemon, moves)
    if $kif_event_moves_for && $kif_event_moves_for.equal?(pokemon)
      moves = (moves || []) | pokemon.getEventMoveList.reject { |m| pokemon.hasMove?(m) }
    end
    return kif_ml_pbStartScene(pokemon, moves)
  end
end

class MoveRelearnerScreen
  # Tell the scene which Pokémon is at the Egg Move Tutor
  alias kif_ml_pbStartScreenEgg pbStartScreenEgg unless method_defined?(:kif_ml_pbStartScreenEgg)

  def pbStartScreenEgg(pkmn)
    old = $kif_event_moves_for
    $kif_event_moves_for = ($PokemonSystem.eventmoves.to_i > 0) ? pkmn : nil
    begin
      return kif_ml_pbStartScreenEgg(pkmn)
    ensure
      $kif_event_moves_for = old
    end
  end
end

#-------------------------------------------------------------------------------
# Fusion Move Tutor (KIF FusionMoveTutor.rb:101-173, un-commented moves)
#-------------------------------------------------------------------------------
class FusionTutorService
  alias kif_ml_getCompatibleMoves getCompatibleMoves unless method_defined?(:kif_ml_getCompatibleMoves)

  def getCompatibleMoves(includeLegendaries = false)
    moves = kif_ml_getCompatibleMoves(includeLegendaries)
    return moves if includeLegendaries
    extra = []
    extra << :FIRSTIMPRESSION if is_fusion_of([:SCYTHER, :SCIZOR, :PINSIR, :FARFETCHD, :TRAPINCH, :VIBRAVA, :FLYGON, :KABUTOPS, :ARMALDO])
    extra << :CLANGINGSCALES if is_fusion_of([:EKANS, :ARBOK, :GARCHOMP, :FLYGON, :HAXORUS])
    extra << :FLYINGPRESS if is_fusion_of([:TORCHIC, :COMBUSKEN, :BLAZIKEN, :FARFETCHD, :HERACROSS]) || (hasType(:FLYING) && hasType(:FIGHTING))
    extra << :NEEDLEARM if is_fusion_of([:FERROTHORN])
    extra << :FORESTSCURSE if (hasType(:GRASS) && hasType(:GHOST))
    extra << :SPIKYSHIELD if is_fusion_of([:FERROSEED, :FERROTHORN]) || (is_fusion_of([:SANDSLASH, :JOLTEON, :CLOYSTER]) && hasType(:GRASS))
    extra << :SHOREUP if is_fusion_of([:GRIMER, :MUK]) && hasType(:GROUND)
    extra << :REVELATIONDANCE if is_fusion_of([:KECLEON, :BELLOSSOM, :CLEFAIRY, :CLEFABLE, :CLEFFA])
    extra << :BANEFULBUNKER if is_fusion_of([:TENTACOOL, :TENTACRUEL, :NIDORINA, :NIDORINO, :NIDOQUEEN, :NIDOKING, :GRIMER, :MUK, :QWILFISH])
    extra << :GRASSYTERRAIN if hasType(:GRASS)
    extra << :ACCELEROCK if is_fusion_of([:AERODACTYL, :KABUTOPS, :ANORITH, :ARMALDO])
    extra << :ANCHORSHOT if (is_fusion_of([:EMPOLEON, :STEELIX, :BELDUM, :METANG, :METAGROSS, :KLINK, :KLINKLANG, :KLANG, :ARON, :LAIRON, :AGGRON]) && hasType(:WATER)) || (is_fusion_of([:LAPRAS, :WAILORD, :KYOGRE]) && hasType(:STEEL))
    extra << :WATERSHURIKEN if is_fusion_of([:NINJASK, :LUCARIO, :ZOROARK, :BISHARP]) && hasType(:WATER)
    extra << :RELICSONG if is_fusion_of([:JYNX, :LAPRAS, :JIGGLYPUFF, :WIGGLYTUFF, :MISDREAVUS, :MISMAGIUS])
    extra << :PRISMATICLASER if is_fusion_of([:LANTURN, :AMPHAROS, :HOOH, :DEOXYS, :MEWTWO, :MEW]) && hasType(:PSYCHIC)
    extra << :PHOTONGEYSER if is_fusion_of([:LANTURN, :AMPHAROS, :HOOH, :MEW, :MEWTWO, :DEOXYS]) && hasType(:PSYCHIC)
    extra << :LUNARDANCE if is_fusion_of([:CLEFAIRY, :CLEFABLE, :STARYU, :STARMIE])
    extra << :DIAMONDSTORM if ((hasType(:FAIRY) && hasType(:ROCK)) || (hasType(:ROCK) && hasType(:STEEL))) || is_fusion_of([:DIALGA, :STEELIX])
    extra.each { |m| moves << m if !moves.include?(m) && KIF::MoveLearning.move_ok?(m) }
    return moves
  end
end
