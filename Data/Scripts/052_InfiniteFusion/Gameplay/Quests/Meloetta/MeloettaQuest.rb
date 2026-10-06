def playMeloettaBandMusic()
  unlocked_members = []
  unlocked_members << :DRUM if $game_switches[SWITCH_BAND_DRUMMER]
  unlocked_members << :AGUITAR if $game_switches[SWITCH_BAND_ACOUSTIC_GUITAR]
  unlocked_members << :EGUITAR if $game_switches[SWITCH_BAND_ELECTRIC_GUITAR]
  unlocked_members << :FLUTE if $game_switches[SWITCH_BAND_FLUTE]
  unlocked_members << :HARP if $game_switches[SWITCH_BAND_HARP]

  echoln unlocked_members
  echoln (unlocked_members & [:DRUM, :AGUITAR, :EGUITAR, :FLUTE, :HARP])

  track = "band/band_1"
  if unlocked_members == [:DRUM, :AGUITAR, :EGUITAR, :FLUTE, :HARP]
    track = "band/band_full"
  else
    if unlocked_members.include?(:FLUTE)
      track = "band/band_5a"
    elsif unlocked_members.include?(:HARP)
      track = "band/band_5b"
    else
      if unlocked_members.include?(:EGUITAR) && unlocked_members.include?(:AGUITAR)
        track = "band/band_4"
      elsif unlocked_members.include?(:AGUITAR)
        track = "band/band_3a"
      elsif unlocked_members.include?(:EGUITAR)
        track = "band/band_3b"
      elsif unlocked_members.include?(:DRUM)
        track = "band/band_2"
      end
    end
  end
  echoln track
  pbBGMPlay(track)
end

def apply_concert_lighting(light, duration = 1)
  tone = Tone.new(0, 0, 0)
  case light
  when :GUITAR_HIT
    tone = Tone.new(-50, -100, -50)
  when :VERSE_1
    tone = Tone.new(-90, -110, -50)
  when :VERSE_2_LIGHT
    tone = Tone.new(-40, -80, -30)
  when :VERSE_2_DIM
    tone = Tone.new(-60, -100, -50)
  when :CHORUS_1
    tone = Tone.new(0, -80, -50)
  when :CHORUS_2
    tone = Tone.new(0, -50, -80)
  when :CHORUS_3
    tone = Tone.new(0, -80, -80)
  when :CHORUS_END
    tone = Tone.new(-68, 0, -102)
  when :MELOETTA_1
    tone = Tone.new(-60, -50, 20)
  end
  $game_screen.start_tone_change(tone, duration)
end

def isTuesdayNight()
  day = getDayOfTheWeek()
  hour = pbGetTimeNow().hour
  echoln hour
  return (day == :TUESDAY && hour >= 20) || (day == :WEDNESDAY && hour < 5)
end