#===============================================================================
# F-UI-07 – Quick Field Moves extras (Reïzod)
# Source: KIF 0.20.7 012_Overworld/004_Overworld_FieldMoves.rb
#   :310 Rock Climb, :391 Surfacing (Dive up), :646 Headbutt   (quick paths)
#   :1051 Sweet Scent: "if !enctype ||" (fix)
#
# 6.8.2 already has KIF's setting as "Quick HMs" (Gameplay options,
# $PokemonSystem.quickHM) for Cut, Dive, Rock Smash, Strength, Surf and
# Waterfall. KIF's version also skipped the prompt and animation for:
#   * Rock Climb (also with the Climbing Gear)
#   * Surfacing from a dive
#   * Headbutt trees
# Those three are added here, using 6.8.2's Quick HMs option (no new option).
#
# Sweet Scent: 6.8.2 says "There appears to be nothing here..." whenever the
# spot HAS encounters (if enctype ||). KIF fixed it to "if !enctype ||".
#
# 6.8.2 adaptations: the three quick paths are wrappers that run the same
# checks as 6.8.2 before acting; Sweet Scent is a guarded copy (whole-file CRC
# of 004_Overworld_FieldMoves.rb also covers the checks copied above).
#===============================================================================
KIF.guard_base("012_Overworld/004_Overworld_FieldMoves.rb", 2424977901,
               "pbRockClimb/pbSurfacing/pbHeadbutt checks, pbSweetScent")

module KIF
  module QuickFieldMoves
    def self.on?
      return $PokemonSystem && $PokemonSystem.respond_to?(:quickHM) && $PokemonSystem.quickHM == 1
    end
  end
end

alias kif_qfm_pbRockClimb pbRockClimb unless defined?(kif_qfm_pbRockClimb)
alias kif_qfm_pbSurfacing pbSurfacing unless defined?(kif_qfm_pbSurfacing)
alias kif_qfm_pbHeadbutt pbHeadbutt unless defined?(kif_qfm_pbHeadbutt)

def pbRockClimb
  return kif_qfm_pbRockClimb unless KIF::QuickFieldMoves.on?
  return false if $game_player.pbFacingEvent
  movefinder = $Trainer.get_pokemon_with_move(:ROCKCLIMB)
  if !pbCheckHiddenMoveBadge(Settings::BADGE_FOR_ROCKCLIMB, false) || (!$DEBUG && !movefinder)
    return false if $PokemonBag.pbQuantity(:CLIMBINGGEAR) <= 0
  end
  climbLedge
  return true
end

def pbSurfacing
  return kif_qfm_pbSurfacing unless KIF::QuickFieldMoves.on?
  return if !$PokemonGlobal.diving
  return false if $game_player.pbFacingEvent
  surface_map_id = nil
  GameData::MapMetadata.each do |map_data|
    next if !map_data.dive_map_id || map_data.dive_map_id != $game_map.map_id
    surface_map_id = map_data.id
    break
  end
  return if !surface_map_id
  pbFadeOutIn {
    $game_temp.player_new_map_id = surface_map_id
    $game_temp.player_new_x = $game_player.x
    $game_temp.player_new_y = $game_player.y
    $game_temp.player_new_direction = $game_player.direction
    $PokemonGlobal.surfing = true
    $PokemonGlobal.diving = false
    pbUpdateVehicle
    $scene.transfer_player(false)
    surfbgm = GameData::Metadata.get.surf_BGM
    (surfbgm) ? pbBGMPlay(surfbgm) : $game_map.autoplayAsCue
    $game_map.refresh
  }
  return true
end

def pbHeadbutt(event = nil)
  return kif_qfm_pbHeadbutt(event) unless KIF::QuickFieldMoves.on?
  movefinder = $Trainer.get_pokemon_with_move(:HEADBUTT)
  if !$DEBUG && !movefinder
    pbMessage(_INTL("A Pokémon could be in this tree. Maybe a Pokémon could shake it."))
    return false
  end
  pbHeadbuttEffect(event)
  return true
end

# Copy of 6.8.2 pbSweetScent (004_Overworld_FieldMoves.rb) with KIF's fix
def pbSweetScent
  if $game_screen.weather_type != :None
    pbMessage(_INTL("The sweet scent faded for some reason..."))
    return
  end
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999
  count = 0
  viewport.color.red = 255
  viewport.color.green = 0
  viewport.color.blue = 0
  viewport.color.alpha -= 10
  alphaDiff = 12 * 20 / Graphics.frame_rate
  loop do
    if count == 0 && viewport.color.alpha < 128
      viewport.color.alpha += alphaDiff
    elsif count > Graphics.frame_rate / 4
      viewport.color.alpha -= alphaDiff
    else
      count += 1
    end
    Graphics.update
    Input.update
    pbUpdateSceneMap
    break if viewport.color.alpha <= 0
  end
  viewport.dispose
  enctype = $PokemonEncounters.encounter_type
  if !enctype || !$PokemonEncounters.encounter_possible_here? ||   # KIF: !enctype
    !pbEncounter(enctype)
    pbMessage(_INTL("There appears to be nothing here..."))
  end
end
