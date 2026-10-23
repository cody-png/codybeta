#===============================================================================
# SCOPE-02 – PIF fix: a trainer missing from the Classic list (2026-10-22)
# PIF's rematch wrapper around pbTrainerBattle (053_PIF_Hoenn/TrainerRematches/
# 03_TrainerRematch_System.rb) reads the pre-battle text with
# GameData::Trainer.get, which raises for a trainer only in the Remix/Expert
# list (S.S. Anne's FISHERMAN Dale) or in none (New Bark's GAMBLER Tobey):
# "Unknown trainer" in every difficulty. Same wrapper, but the text comes
# from the difficulty's list (Classic as the fallback, as the battle itself
# does) and is skipped when no list has the trainer; the battle then shows
# PIF's own "trainer missing" handling instead of a crash.
#===============================================================================
if defined?(original_pbTrainerBattle)
  def pbTrainerBattle(trainerID, trainerName, endSpeech = nil,
                      doubleBattle = false, trainerPartyID = 0,
                      canLose = false, outcomeVar = 1,
                      name_override = nil, trainer_type_overide = nil,
                      event_id = nil, map_id = nil)
    trainer_data = (getTrainersDataMode.try_get(trainerID, trainerName, trainerPartyID) rescue nil) ||
                   (GameData::Trainer.try_get(trainerID, trainerName, trainerPartyID) rescue nil)
    displayPreBattleText(trainer_data) if trainer_data
    map_id = $game_map.map_id
    result = original_pbTrainerBattle(trainerID, trainerName, endSpeech, doubleBattle, trainerPartyID,
                                      canLose, outcomeVar, name_override, trainer_type_overide, event_id, map_id)
    updateRematchableTrainer(trainerID, trainerName, trainerPartyID, event_id, nil, map_id) if Settings::GAME_ID == :IF_HOENN
    return result
  end
end
