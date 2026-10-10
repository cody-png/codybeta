#===============================================================================
# SCOPE-02 – Scroll arrows left on screen (Cody, 2026-10-10)
#   A list window's up/down scroll arrows are separate sprites whose
#   visibility is only recalculated in the window's update. Hiding the window
#   (e.g. the pause menu's pbHideMenu before Outfit, Save or Title) left an
#   arrow showing if the list was scrolled - and it stayed on screen through
#   the save prompt and back to the title screen. Hiding the window now hides
#   its arrows too; the next update shows them again as usual.
#===============================================================================
module KIF
  module HideScrollArrows
    def visible=(value)
      super
      unless value
        @uparrow.visible = false if @uparrow && !@uparrow.disposed?
        @downarrow.visible = false if @downarrow && !@downarrow.disposed?
      end
    end
  end
end

SpriteWindow_SelectableEx.prepend(KIF::HideScrollArrows)
