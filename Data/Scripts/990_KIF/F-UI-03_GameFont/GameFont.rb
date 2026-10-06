#===============================================================================
# F-UI-03 – Game font selection (Reïzod)
# Source: KIF 0.20.7 016_UI/015_UI_Options.rb:2547-2590 (option),
#   007_Objects and windows/002_MessageConfig.rb:33-35, :142-168, :454-466
#   (font sizes settable at runtime), 052_AddOns/IntroScreen.rb:95-118
#   (font applied at start).
#
# Graphics > "Game's Font" (all saves):
#   Default – Power Green (6.8.2's fonts)
#   FR/LG   – Power Red and Green (size 26), small/narrow Power Green Small
#   D/P     – Power Clear
#   R/B     – Power Red and Blue
# The fonts ship with PIF (Fonts/). Chinese text keeps PIF's Chinese font.
#
# 6.8.2 adaptation: no copies – the font name goes through 6.8.2's own
# MessageConfig.pbSet*FontName, and the size is set right after 6.8.2's
# pbSetSystemFont / pbSetSmallFont / pbSetNarrowFont. The choice is applied
# the first time text is drawn and whenever the option changes.
#===============================================================================
KIF::Options.define(:kurayfonts, 0, :global)

module KIF
  module GameFont
    # [system font, small font, narrow font, system size, small size, narrow size]
    FONTS = [
      ["Power Green",         "Power Green Small",  "Power Green Narrow", 29, 25, 29],
      ["Power Red and Green", "Power Green Small",  "Power Green Small",  26, 25, 26],
      ["Power Clear",         "Power Clear",        "Power Clear",        29, 25, 29],
      ["Power Red and Blue",  "Power Red and Blue", "Power Red and Blue", 29, 25, 29]
    ]
    @applied = nil

    def self.choice
      v = $PokemonSystem ? $PokemonSystem.kurayfonts.to_i : 0
      return (0...FONTS.length).include?(v) ? v : 0
    end

    def self.sync
      c = choice
      return if @applied == c
      @applied = c
      f = FONTS[c]
      MessageConfig.pbSetSystemFontName(f[0])
      MessageConfig.pbSetSmallFontName(f[1])
      MessageConfig.pbSetNarrowFontName(f[2])
    end

    SIZE_INDEX = { :system => 3, :small => 4, :narrow => 5 }

    def self.size(kind)
      return FONTS[choice][SIZE_INDEX[kind]]
    end

    def self.chinese?
      return defined?(getCurrentLanguage) && getCurrentLanguage == :CHINESE
    rescue
      return false
    end
  end
end

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Game's Font"), [_INTL("Default"), _INTL("FR/LG"), _INTL("D/P"), _INTL("R/B")],
                 proc { $PokemonSystem.kurayfonts },
                 proc { |value|
                   $PokemonSystem.kurayfonts = value
                   KIF::GameFont.sync
                 },
                 _INTL("Changes the Game's font"))
}

alias kif_font_pbSetSystemFont pbSetSystemFont unless defined?(kif_font_pbSetSystemFont)
alias kif_font_pbSetSmallFont pbSetSmallFont unless defined?(kif_font_pbSetSmallFont)
alias kif_font_pbSetNarrowFont pbSetNarrowFont unless defined?(kif_font_pbSetNarrowFont)

# Called for every text draw: with the Default font nothing is changed, so the
# wrappers only do work when another font is chosen (sizes then differ).
def pbSetSystemFont(bitmap)
  KIF::GameFont.sync
  kif_font_pbSetSystemFont(bitmap)
  bitmap.font.size = KIF::GameFont.size(:system) if KIF::GameFont.choice != 0 && !KIF::GameFont.chinese?
end

def pbSetSmallFont(bitmap)
  KIF::GameFont.sync
  kif_font_pbSetSmallFont(bitmap)
  bitmap.font.size = KIF::GameFont.size(:small) if KIF::GameFont.choice != 0 && !KIF::GameFont.chinese?
end

def pbSetNarrowFont(bitmap)
  KIF::GameFont.sync
  kif_font_pbSetNarrowFont(bitmap)
  bitmap.font.size = KIF::GameFont.size(:narrow) if KIF::GameFont.choice != 0 && !KIF::GameFont.chinese?
end
