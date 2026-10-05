#===============================================================================
# PIF 6.8.2 fix – option screens (Cody approved 2026-10-05)
#
# 1. Most option sub-screens create a second title window over the "Options"
#    one in pbStartScene (e.g. GameplayOptions.rb:14); the old window stays and
#    shows through behind the new title text. The stale one is disposed.
# 2. PokemonOption_Scene#initOptionsWindow (015_UI_Options.rb:496) makes the
#    list 32px taller than the space above the description box, so the last
#    visible row is cut off. The list is sized to the space instead.
# Applied to PIF's option screens only (not FusionMenu / FusionMovesMenu,
# which have their own layouts). KIF's screens do the same in 002_KIF_Options.
#===============================================================================
module KIF
  module OptionScreenFix
    def initUIElements(*args)
      ret = super
      @kif_base_title = @sprites["title"]
      return ret
    end

    def initOptionsWindow(*args)
      win = super
      win.height = Graphics.height - @sprites["title"].height - @sprites["textbox"].height
      return win
    end

    def pbFadeInAndShow(*args, &block)
      if @kif_base_title && @sprites["title"] && !@sprites["title"].equal?(@kif_base_title)
        @kif_base_title.dispose unless @kif_base_title.disposed?
        @kif_base_title = nil
      end
      return super
    end
  end
end

%w[PokemonGameOption_Scene GameplayOptionsScene SpriteOptionsScene SystemOptionsScene
   ChallengeOptionsScene AutosaveOptionsScene ExperimentalOptionsScene RandomizerOptionsScene
   RandomizerTrainerOptionsScene RandomizerWildPokemonOptionsScene RandomizerGymOptionsScene
   RandomizerItemOptionsScene].each do |name|
  next unless Object.const_defined?(name)
  klass = Object.const_get(name)
  klass.prepend(KIF::OptionScreenFix) unless klass.ancestors.include?(KIF::OptionScreenFix)
end
