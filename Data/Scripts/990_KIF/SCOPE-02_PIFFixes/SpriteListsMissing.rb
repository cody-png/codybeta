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
