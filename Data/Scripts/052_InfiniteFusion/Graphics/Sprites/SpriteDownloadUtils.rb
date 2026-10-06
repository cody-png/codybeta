def promptEnableSpritesDownload
  message = _INTL("Some sprites appear to be missing from your game. \nWould you like the game to download sprites automatically while playing? (this requires an internet connection)")
  if pbConfirmMessage(message)
    $PokemonSystem.download_sprites = 0
  end
end

def update_spritepack_files()
    updateCreditsFile()
    updateOnlineCustomSpritesFile()
    reset_updated_spritesheets_cache()
    $updated_spritesheets = []
    spritesLoader = BattleSpriteLoader.new
    spritesLoader.clear_sprites_cache(:CUSTOM)
    spritesLoader.clear_sprites_cache(:BASE)

    pbMessage(_INTL("Data files updated. New sprites will now be downloaded as you play!"))
end

def reset_updated_spritesheets_cache()
  echoln "resetting updated spritesheets list"
  begin
    File.open(Settings::UPDATED_SPRITESHEETS_CACHE, 'w') { |file| file.truncate(0) }
    echoln "File reset successfully."
  rescue => e
    echoln "Failed to reset file: #{e.message}"
  end
end

def preload_party(trainer)
  spriteLoader = BattleSpriteLoader.new
  for pokemon in trainer.party
    spriteLoader.preload_sprite_from_pokemon(pokemon)
  end
end


#unused - too slow, & multithreading not possible
# def preload_party_and_boxes(storage, trainer)
#     echoln "Loading boxes and party into cache in the background"
#     start_time = Time.now
#     spriterLoader = BattleSpriteLoader.new
#     for box in storage.boxes
#       for pokemon in box.pokemon
#         if pokemon != nil
#           if !pokemon.egg?
#             spriterLoader.preload_sprite_from_pokemon(pokemon)
#           end
#         end
#       end
#     end
#     for pokemon in trainer.party
#       spriterLoader.preload_sprite_from_pokemon(pokemon)
#     end
#     end_time = Time.now
#     echoln "Finished in #{end_time - start_time} seconds"
# end


def checkEnableSpritesDownload
  if $PokemonSystem.download_sprites && $PokemonSystem.download_sprites != 0
    customSprites = getCustomSpeciesList
    if !customSprites
      promptEnableSpritesDownload
    else
      if customSprites.length < 1000
        promptEnableSpritesDownload
      end
    end
  end
end

def check_for_spritepack_update()
  $updated_spritesheets = [] if !$updated_spritesheets
  if new_spritepack_was_released()
    pbFadeOutIn() {
      return if !downloadAllowed?()
      should_update = pbConfirmMessage(_INTL("A new spritepack was released. Would you like to let the game update your game's sprites automatically?"))
      if should_update
        update_spritepack_files
      end
    }
  end
end
