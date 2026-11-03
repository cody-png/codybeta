#===============================================================================
# SCOPE-02 – PIF fixes: the PC screen and the Pokedex sprite page (2026-11-01)
# Found by the UI crawl, which drives every screen with keys, a pad, a mouse
# and touch for a few hundred frames and checks what each leaves behind.
#  1. Multi-select in the PC: with a range started in the party, the cursor on
#     the party's Back button (index 6; the mouse puts it there, the keyboard
#     can too) made the selection rectangle read a slot that doesn't exist
#     and the PC closed in the crash handler. The rectangle is hidden there.
#  2. Closing the PC left two of the five viewports it made (the background
#     and the message one) alive; each PC session leaked two.
#  3. The Pokedex sprite page made a new full-screen sprite for the credits on
#     every sprite change and kept only its bitmap, so the sprites were never
#     disposed. It keeps one sprite (in @sprites, disposed with the page).
#===============================================================================
KIF.guard_base("052_InfiniteFusion/Menus/PC/Multiselect/MultiSelect_Helpers.rb", 2562488303,
               "SelectionHelper.compute_rect")
KIF.guard_base("052_InfiniteFusion/Gameplay/Pokedex/UI_Pokedex_SpritesPage.rb", 1463859335,
               "PokemonPokedexInfo_Scene#init_selected_bg, #showSpriteCredits")

module SelectionHelper
  class << self
    alias kif_pcf_compute_rect compute_rect unless method_defined?(:kif_pcf_compute_rect)

    def compute_rect(scene, screen, box, selected)
      if box == SelectionConstants::BOX_NAME && screen.multiSelectRange
        indexes = screen.getMultiSelection(box, selected)
        return nil if indexes.any? { |i| i >= Settings::MAX_PARTY_SIZE }
      end
      return kif_pcf_compute_rect(scene, screen, box, selected)
    end
  end
end

class PokemonStorageScene
  alias kif_pcf_pbCloseBox pbCloseBox unless method_defined?(:kif_pcf_pbCloseBox)

  def pbCloseBox(*args)
    return kif_pcf_pbCloseBox(*args)
  ensure
    [@bgviewport, @viewport].each { |vp| vp.dispose if vp && !vp.disposed? }
  end
end

class PokemonPokedexInfo_Scene
  # Copy of 6.8.2 UI_Pokedex_SpritesPage.rb:49-70 with the credits sprite kept
  def init_selected_bg
    @sprites["bgSelected_previous"] = IconSprite.new(0, 0, @viewport)
    @sprites["bgSelected_previous"].x = X_POSITION_BG_PREVIOUS
    @sprites["bgSelected_previous"].y = Y_POSITION_BG_SMALL
    @sprites["bgSelected_previous"].setBitmap("Graphics/Pictures/Pokedex/bg_forms_selected_small")
    @sprites["bgSelected_previous"].visible = false

    @sprites["bgSelected_center"] = IconSprite.new(0, 0, @viewport)
    @sprites["bgSelected_center"].x = X_POSITION_BG_SELECTED
    @sprites["bgSelected_center"].y = Y_POSITION_BG_BIG
    @sprites["bgSelected_center"].setBitmap("Graphics/Pictures/Pokedex/bg_forms_selected_large")
    @sprites["bgSelected_center"].visible = false

    @sprites["bgSelected_next"] = IconSprite.new(0, 0, @viewport)
    @sprites["bgSelected_next"].x = X_POSITION_BG_NEXT
    @sprites["bgSelected_next"].y = Y_POSITION_BG_SMALL
    @sprites["bgSelected_next"].setBitmap("Graphics/Pictures/Pokedex/bg_forms_selected_small")
    @sprites["bgSelected_next"].visible = false

    pbDisposeSprite(@sprites, "creditsOverlay")
    @sprites["creditsOverlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    @creditsOverlay = @sprites["creditsOverlay"].bitmap
  end

  # Copy of 6.8.2 UI_Pokedex_SpritesPage.rb:452-479: the credits are drawn
  # on the one overlay bitmap, cleared first, instead of a new sprite each time
  def showSpriteCredits(filename, generated_sprite = false)
    return unless filename
    @creditsOverlay.clear

    spritename = File.basename(filename, '.*')

    if !generated_sprite
      discord_name = getSpriteCredits(spritename)
      discord_name = "Unknown artist" if !discord_name
    else
      # todo give credits to Japeal - need to differenciate unfused sprites
      discord_name = "" #"Japeal\n(Generated)"
    end
    discord_name = "Imported sprite" if @selected_pif_sprite.local_path
    author_name = File.basename(discord_name, '#*')

    x = Graphics.width / 2
    label_base_color = Color.new(248, 248, 248)
    label_shadow_color = Color.new(104, 104, 104)
    split_name = splitSpriteCredits(author_name, @creditsOverlay, @creditsOverlay.width - 20)
    line_height = @creditsOverlay.text_size(author_name).height
    textpos = split_name.each_with_index.map { |name, index|
      y = (Graphics.height - 60) + (line_height * ((index + 1) - ((split_name.length.to_f + 1) / 2)))
      [name, x, y, 2, label_base_color, label_shadow_color]
    }
    pbDrawTextPositions(@creditsOverlay, textpos)
  end
end
