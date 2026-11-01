#===============================================================================
# Battle Movement (Options > Battle > Battle Movement) did nothing in EBDX and
# only twitched in PIF's scene (Bishsume, v1.2.13).
# PokemonBattlerSprite#update bobs an idle Pokemon 2 px up and down over a
# 160-frame wave, from the frame counter the scene passes in. The scene's
# counter wraps every 24 frames (frame_rate * 12 / 20), so only a 24-frame slice
# of the wave ever played: a 1 px step every 0.6 s. EBDX's scene passes no
# counter, so every frame was frame 0 and the sprite sat still, 1 px off.
# The idle bob now runs on the game's frame count (the same value on every
# call in a frame, so EBDX updating a sprite twice a frame doesn't speed it up).
# Choosing and targeted sprites keep the scene's counter, and the option is
# still read by PIF's code: Off = no bob.
#===============================================================================
class PokemonBattlerSprite
  alias kif_bob_update update unless method_defined?(:kif_bob_update) || private_method_defined?(:kif_bob_update)
  def update(frameCounter = 0, *rest)
    frameCounter = Graphics.frame_count unless @selected == 1 || @selected == 2
    return kif_bob_update(frameCounter, *rest)
  end
end
