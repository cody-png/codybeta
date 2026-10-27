#===============================================================================
# SCOPE-02 – PIF fix: missing sprite lists don't crash the game (2026-10-22)
# PIF reads Data/sprites/CUSTOM_SPRITES with File.foreach / File.readlines
# and no check (052/System/HttpCalls.rb list_online_custom_sprites,
# custom_exists). A copy without it (a JoiPlay player's, Loopy 2026-10-21)
# crashed in the intro: Errno::ENOENT from the randomizer's species list.
# PIF's own start-up already checks before reading it; these two now do too
# (no list: no online sprites listed / none known to exist).
#===============================================================================
alias kif_slm_list_online_custom_sprites list_online_custom_sprites unless defined?(kif_slm_list_online_custom_sprites)

def list_online_custom_sprites(*args)
  unless File.file?(Settings::CUSTOM_SPRITES_FILE_PATH)
    KIF.log("No sprite list (#{Settings::CUSTOM_SPRITES_FILE_PATH}): online custom sprites left out") if defined?(KIF.log)
    return []
  end
  return kif_slm_list_online_custom_sprites(*args)
end

alias kif_slm_custom_exists custom_exists unless defined?(kif_slm_custom_exists)

def custom_exists(target_file)
  return false unless File.file?(Settings::CUSTOM_SPRITES_FILE_PATH)
  return kif_slm_custom_exists(target_file)
end

# PIF's load screen (checkEnableSpritesDownload) only wants to know whether
# fewer than 1000 custom sprites are known, but builds the whole list for it
# each start: 580 folder listings (236,000 files with a sprite pack) and the
# list file above, read and parsed (226,000 lines). With the list file there,
# that count is the list's own, so its first 1000 good lines give the same
# answer (2026-10-27, a player's 2.5 min black screen).
alias kif_slm_checkEnableSpritesDownload checkEnableSpritesDownload unless defined?(kif_slm_checkEnableSpritesDownload)

def checkEnableSpritesDownload(*args)
  dl = ($PokemonSystem.download_sprites rescue nil)
  path = Settings::CUSTOM_SPRITES_FILE_PATH
  if dl && dl != 0 && File.file?(path)
    max = (NB_POKEMON * NB_POKEMON) + NB_POKEMON
    n = 0
    File.foreach(path) do |line|
      num = getDexNumFromFilename(line)
      n += 1 if num && num > 0 && num <= max
      break if n >= 1000
    end
    return if n >= 1000
  end
  return kif_slm_checkEnableSpritesDownload(*args)
end
