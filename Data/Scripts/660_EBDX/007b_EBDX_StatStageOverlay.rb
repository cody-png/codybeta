#===============================================================================
#  EBDX Stat Stage Overlay
#  Adds Pokemon Showdown-style stat change indicators to EBDX databoxes.
#  Active stat stages appear as colored pill badges below the HP container,
#  e.g. "+1Atk", "-2Def". Pills update live and vanish when a stat returns to 0.
#===============================================================================

# Ordered list of [stat_id, display_abbreviation] for the overlay.
# Only stats with non-zero stages are rendered.
EBDX_STAT_STAGE_LIST = [
  [:ATTACK,          "Atk"],
  [:DEFENSE,         "Def"],
  [:SPECIAL_ATTACK,  "SpA"],
  [:SPECIAL_DEFENSE, "SpD"],
  [:SPEED,           "Spe"],
  [:ACCURACY,        "Acc"],
  [:EVASION,         "Eva"],
]

# Font size for pill text (smaller than the 25px small font used elsewhere)
EBDX_SS_FONT_SIZE    = 13

# Pill visual constants
EBDX_SS_PILL_H       = 13   # pixel height of each pill badge
EBDX_SS_PILL_PAD_X   = 2    # horizontal text padding inside pill
EBDX_SS_PILL_GAP     = 2    # gap between consecutive pills
EBDX_SS_BITMAP_H     = 16   # stat-stage bitmap height (pill + breathing room)
# Fixed bitmap width sized for 7 worst-case pills at 13px font (~22px each + gap)
EBDX_SS_BITMAP_W     = 260

# Colors for positive / negative stages
EBDX_SS_COLOR_POS_FILL    = Color.new(35, 155, 70)     # green fill (boost)
EBDX_SS_COLOR_NEG_FILL    = Color.new(185, 45, 45)     # red fill  (drop)
EBDX_SS_COLOR_BIG_POS     = Color.new(20, 120, 210)    # blue fill  (+3 or more)
EBDX_SS_COLOR_BIG_NEG     = Color.new(210, 20, 20)     # deep red   (-3 or less)
EBDX_SS_COLOR_BORDER      = Color.new(8,   8,  8, 215) # near-black border
EBDX_SS_COLOR_TEXT        = Color.white

class DataBoxEBDX
  #-----------------------------------------------------------------------------
  #  Hook into setUp to append the stat-stage sprite after normal setup
  #-----------------------------------------------------------------------------
  alias_method :ebdx_ss_setUp, :setUp
  def setUp
    ebdx_ss_setUp
    @cached_stages = nil
    @sprites["statStages"] = Sprite.new(@viewport)
    @sprites["statStages"].bitmap = Bitmap.new(EBDX_SS_BITMAP_W, EBDX_SS_BITMAP_H)
    pbSetSmallFont(@sprites["statStages"].bitmap)
    @sprites["statStages"].bitmap.font.size = EBDX_SS_FONT_SIZE
    @sprites["statStages"].z = 10
    # Sit just below the container (which ends at c_ey + c_h)
    c_ey = self.getMetric("container", :y)
    c_h  = @showexp ? 26 : 14
    @sprites["statStages"].ex = @playerpoke ? 16 : 20
    @sprites["statStages"].ey = c_ey + c_h + 3
  end

  #-----------------------------------------------------------------------------
  #  Hook into refresh (force-redraws pills when the databox refreshes)
  #-----------------------------------------------------------------------------
  alias_method :ebdx_ss_refresh, :refresh
  def refresh
    ebdx_ss_refresh
    drawStatStages(true)
  end

  #-----------------------------------------------------------------------------
  #  Hook into update (redraws only when stage values actually change)
  #-----------------------------------------------------------------------------
  alias_method :ebdx_ss_update, :update
  def update
    ebdx_ss_update
    drawStatStages
  end

  #-----------------------------------------------------------------------------
  #  Draw (or clear) the stat stage pill row
  #  force: when true, always redraws even if stages haven't changed
  #-----------------------------------------------------------------------------
  def drawStatStages(force = false)
    return unless @sprites["statStages"] && !@sprites["statStages"].disposed?
    # Respect the MP settings toggle; clear pills immediately when turned off
    unless ($PokemonSystem.mp_stat_stage_overlay rescue 1) == 1
      @sprites["statStages"].bitmap.clear unless @cached_stages.nil?
      @cached_stages = nil
      return
    end
    return unless @battler && @battler.stages

    # Build a lightweight snapshot for dirty-checking
    snapshot = {}
    EBDX_STAT_STAGE_LIST.each { |id, _| snapshot[id] = (@battler.stages[id] || 0) }
    return if !force && snapshot == @cached_stages
    @cached_stages = snapshot.dup

    bmp = @sprites["statStages"].bitmap
    bmp.clear
    pbSetSmallFont(bmp)
    bmp.font.size = EBDX_SS_FONT_SIZE

    cx = 0
    EBDX_STAT_STAGE_LIST.each do |stat_id, abbrev|
      stage = snapshot[stat_id]
      next if stage == 0

      sign   = stage > 0 ? "+" : ""
      label  = "#{sign}#{stage}#{abbrev}"
      tw     = bmp.text_size(label).width
      pill_w = tw + EBDX_SS_PILL_PAD_X * 2 - 1

      # Safety guard — should never trigger at EBDX_SS_BITMAP_W = 260
      break if cx + pill_w > bmp.width

      # --- Background border ---
      bmp.fill_rect(cx, 0, pill_w, EBDX_SS_PILL_H, EBDX_SS_COLOR_BORDER)

      # --- Colored fill based on stage sign and magnitude ---
      fill = if stage >= 3
               EBDX_SS_COLOR_BIG_POS
             elsif stage > 0
               EBDX_SS_COLOR_POS_FILL
             elsif stage <= -3
               EBDX_SS_COLOR_BIG_NEG
             else
               EBDX_SS_COLOR_NEG_FILL
             end
      bmp.fill_rect(cx + 1, 1, pill_w - 2, EBDX_SS_PILL_H - 2, fill)

      # --- Text: plain white, no outline, so glyphs stay crisp ---
      bmp.font.color = EBDX_SS_COLOR_TEXT
      bmp.draw_text(cx + EBDX_SS_PILL_PAD_X - 1, 3, pill_w, EBDX_SS_PILL_H, label, 0)

      cx += pill_w + EBDX_SS_PILL_GAP
    end
  end
end
