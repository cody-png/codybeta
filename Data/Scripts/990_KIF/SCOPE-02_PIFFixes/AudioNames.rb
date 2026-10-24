#===============================================================================
# SCOPE-02 – audio names saved with an extension still play (2026-10-23)
# KIF 1.2.0 ships its WAVs and high-bitrate music as Ogg (smaller download).
# Move animations (Data/PkmnAnimations.rxdata) name their sounds with the
# extension ("PRSFX- Thunderbolt.wav"), and the audio lookup takes the name
# as given, so those sounds would go silent. The extension is dropped here
# and the file is found by its base name, whatever format it's in now.
#===============================================================================
alias kif_an_pbResolveAudioFile pbResolveAudioFile unless defined?(kif_an_pbResolveAudioFile)

def pbResolveAudioFile(str, volume = nil, pitch = nil)
  ret = kif_an_pbResolveAudioFile(str, volume, pitch)
  if ret.is_a?(RPG::AudioFile) && ret.name && ret.name[/\.(wav|mp3|ogg)\z/i]
    ret = RPG::AudioFile.new(ret.name.sub(/\.(wav|mp3|ogg)\z/i, ""), ret.volume, ret.pitch)
  end
  return ret
end
