#===============================================================================
# SCOPE-02 – PIF fix: paths that only work where file names ignore case
# (2026-10-22, MOBILE_AUDIT)
# Windows doesn't mind "Battlers/Special" for the "special" folder; Android
# and Linux do. The missing-sprite fallback is the one that matters (without
# it a missing sprite is a crash there).
#===============================================================================
module Settings
  if !File.exist?(DEFAULT_SPRITE_PATH) && File.exist?("Graphics/Battlers/special/000.png")
    remove_const(:DEFAULT_SPRITE_PATH)
    DEFAULT_SPRITE_PATH = "Graphics/Battlers/special/000.png"
  end
end
