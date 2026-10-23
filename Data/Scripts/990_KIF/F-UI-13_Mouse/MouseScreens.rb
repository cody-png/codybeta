#===============================================================================
# F-UI-13 – Mouse on the screens drawn without list windows (2026-10-22)
# Party, Bag pockets, Summary page tabs, battle menus (PIF's and EBDX's
# command and fight menus), PC boxes, the load screen, the living title and
# KIF's Options screen. Lists made of SpriteWindow_Selectable already follow
# the pointer (Mouse.rb).
#
# Screens whose loop reads the arrow keys right after Input.update get a
# "focus" (KIF::Mouse.with_focus) whose kif_mouse_frame runs inside that
# Input.update; it points the next arrow key at the slot under the pointer
# (KIF::Mouse.steer), and the screen's own pbChangeSelection then returns
# that slot, so the screen moves its cursor, plays its sound and redraws as
# for a key.
#===============================================================================
module KIF
  module Mouse
    @focus = []
    @target = nil

    def self.with_focus(obj)
      @focus.push(obj)
      yield
    ensure
      @focus.pop
    end

    # (end of poll) the focused screen reads the pointer
    def self.focus_frame
      @target = nil
      f = @focus.last
      return unless f && @on && (@moved || @left || @wheel != 0)   # the wheel alone too (PC boxes)
      f.kif_mouse_frame
    rescue StandardError => e
      KIF.log("Mouse (#{f.class}): #{e.class}: #{e.message}")
    end

    # this frame's arrow key moves the screen's cursor straight to target
    def self.steer(target)
      @target = target
      @key = Input::DOWN
      @any = true
    end

    def self.take_target
      t = @target
      @target = nil
      return t
    end

    # hover moves to slot (when it isn't the current one); a click picks it
    # (steer + the click's own USE), a click on nothing is dropped
    def self.pick(slot, current)
      return unless @moved || @left   # a wheel turn alone leaves the cursor to the wheel
      if slot.nil?
        swallow! if @left
      elsif slot != current
        steer(slot)
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Party
#-------------------------------------------------------------------------------
class PokemonParty_Scene
  alias kif_mouse_choose pbChoosePokemon unless method_defined?(:kif_mouse_choose)
  alias kif_mouse_change pbChangeSelection unless method_defined?(:kif_mouse_change)

  def pbChoosePokemon(*args)
    return KIF::Mouse.with_focus(self) { kif_mouse_choose(*args) }
  end

  def pbChangeSelection(key, currentsel)
    t = KIF::Mouse.take_target
    return t unless t.nil?
    return kif_mouse_change(key, currentsel)
  end

  def kif_mouse_frame
    n = Settings::MAX_PARTY_SIZE + (@multiselect ? 2 : 1)
    slot = nil
    n.times do |i|
      s = @sprites["pokemon#{i}"]
      next unless s && KIF::Mouse.over_sprite?(s)
      next if i < Settings::MAX_PARTY_SIZE && !@party[i]
      slot = i
      break
    end
    KIF::Mouse.pick(slot, @activecmd)
  end
end

#-------------------------------------------------------------------------------
# PC boxes: the box grid, box name (its ends change box), Party and Exit;
# the party panel while choosing from it
#-------------------------------------------------------------------------------
class PokemonStorageScene
  alias kif_mouse_select_box pbSelectBoxInternal unless method_defined?(:kif_mouse_select_box)
  alias kif_mouse_select_party pbSelectPartyInternal unless method_defined?(:kif_mouse_select_party)
  alias kif_mouse_change pbChangeSelection unless method_defined?(:kif_mouse_change)
  alias kif_mouse_party_change pbPartyChangeSelection unless method_defined?(:kif_mouse_party_change)
  alias kif_mouse_set_arrow pbSetArrow unless method_defined?(:kif_mouse_set_arrow)
  alias kif_mouse_party_arrow pbPartySetArrow unless method_defined?(:kif_mouse_party_arrow)

  def pbSelectBoxInternal(*args)
    @kif_mouse_in = :box
    return KIF::Mouse.with_focus(self) { kif_mouse_select_box(*args) }
  end

  def pbSelectPartyInternal(*args)
    @kif_mouse_in = :party
    return KIF::Mouse.with_focus(self) { kif_mouse_select_party(*args) }
  ensure
    @kif_mouse_in = :box
  end

  def pbSetArrow(arrow, selection)
    @kif_mouse_sel = selection
    kif_mouse_set_arrow(arrow, selection)
  end

  def pbPartySetArrow(arrow, selection)
    @kif_mouse_psel = selection
    kif_mouse_party_arrow(arrow, selection)
  end

  def pbChangeSelection(key, selection)
    t = KIF::Mouse.take_target
    return t unless t.nil?
    return kif_mouse_change(key, selection)
  end

  def pbPartyChangeSelection(key, selection)
    t = KIF::Mouse.take_target
    return t unless t.nil?
    return kif_mouse_party_change(key, selection)
  end

  def kif_mouse_frame
    return kif_mouse_party_frame if @kif_mouse_in == :party
    box = @sprites["box"]
    return unless box
    m = KIF::Mouse
    # the wheel flips boxes, like PIF's box keys (Cody, 2026-10-23): up = previous
    return m.wheel_press!(m.wheel > 0 ? Input::JUMPUP : Input::JUMPDOWN) if m.wheel != 0
    w = PokemonBox::BOX_WIDTH
    slot = nil
    if m.over_rect?(box.x + 10, box.y + 30, 48 * w, 48 * PokemonBox::BOX_HEIGHT, box.viewport)
      px, py = m.view_xy(box.viewport)
      slot = (py - box.y - 30) / 48 * w + (px - box.x - 10) / 48
    elsif m.over_rect?(box.x, box.y, 324, 30, box.viewport)
      px, _py = m.view_xy(box.viewport)
      slot = -1
      if m.left && @kif_mouse_sel == -1 && (px < box.x + 81 || px >= box.x + 243)
        m.swallow!   # the ends of the box name: previous / next box
        return m.steer(px < box.x + 81 ? -4 : -5)
      end
    elsif m.over_rect?(200, 316, 140, 44)
      slot = -2   # Party
    elsif m.over_rect?(380, 316, 132, 44)
      slot = -3   # Exit
    end
    m.pick(slot, @kif_mouse_sel)
  end

  def kif_mouse_party_frame
    bp = @sprites["boxparty"]
    return unless bp
    m = KIF::Mouse
    slot = nil
    Settings::MAX_PARTY_SIZE.times do |i|
      if m.over_rect?(bp.x + 18 + 72 * (i % 2), bp.y + 2 + 16 * (i % 2) + 64 * (i / 2), 64, 64, bp.viewport)
        slot = i
        break
      end
    end
    slot = Settings::MAX_PARTY_SIZE if slot.nil? && m.over_rect?(bp.x + 18, bp.y + 230, 136, 40, bp.viewport)
    m.pick(slot, @kif_mouse_psel)
  end
end

#-------------------------------------------------------------------------------
# Bag: the pocket arrows and pocket icons
#-------------------------------------------------------------------------------
class PokemonBag_Scene
  alias kif_mouse_choose_item pbChooseItem unless method_defined?(:kif_mouse_choose_item)

  def pbChooseItem(*args)
    @kif_mouse_pocket = nil
    return KIF::Mouse.with_focus(self) { kif_mouse_choose_item(*args) }
  end

  def kif_mouse_frame
    m = KIF::Mouse
    list = @sprites["itemlist"]
    return unless list && !list.sorting
    if m.left
      if m.over_sprite?(@sprites["leftarrow"])
        @kif_mouse_pocket = nil
        return m.press!(Input::LEFT)
      elsif m.over_sprite?(@sprites["rightarrow"])
        @kif_mouse_pocket = nil
        return m.press!(Input::RIGHT)
      end
      icons = @sprites["pocketicon"]
      if icons && m.over_rect?(icons.x + 4, icons.y + 4, 22 * PokemonBag.numPockets, 24, icons.viewport)
        px, _py = m.view_xy(icons.viewport)
        @kif_mouse_pocket = [[(px - icons.x - 4) / 22 + 1, 1].max, PokemonBag.numPockets].min
        @kif_mouse_tries = PokemonBag.numPockets
        m.swallow!
      end
    end
  end

  # a clicked pocket icon: one pocket per frame, as RIGHT would (pockets
  # with nothing to choose are skipped by the Bag itself)
  alias kif_mouse_bag_update pbUpdate unless method_defined?(:kif_mouse_bag_update)

  def pbUpdate
    kif_mouse_bag_update
    return unless @kif_mouse_pocket && @sprites["itemlist"]
    cur = @sprites["itemlist"].pocket
    if cur == @kif_mouse_pocket || (@kif_mouse_tries -= 1) < 0
      @kif_mouse_pocket = nil
      return
    end
    KIF::Mouse.press!(@kif_mouse_pocket > cur ? Input::RIGHT : Input::LEFT)
  end
end

#-------------------------------------------------------------------------------
# Summary: the page tabs at the top right
#-------------------------------------------------------------------------------
class PokemonSummary_Scene
  KIF_MOUSE_TABS_X = 230
  KIF_MOUSE_TAB_W  = 56

  alias kif_mouse_summary_update pbUpdate unless method_defined?(:kif_mouse_summary_update)

  def pbUpdate
    kif_mouse_summary_update
    m = KIF::Mouse
    return unless m.clicked? && m.over_rect?(KIF_MOUSE_TABS_X, 4, KIF_MOUSE_TAB_W * 5, 52)
    # only the page view itself (not its move list, markings or menus)
    return unless caller_locations(1, 1)[0].label.to_s.end_with?("pbScene")
    m.swallow!
    return if @pokemon.egg?
    page = (m.x - KIF_MOUSE_TABS_X) / KIF_MOUSE_TAB_W + 1
    return if page == @page || page < 1 || page > 5
    return pbPlayBuzzerSE if page == 5 && (!$Trainer.has_pokedex || !@is_player)
    @page = page
    @ribbonOffset = 0
    pbPlayCursorSE
    drawPage(@page)
  end
end

#-------------------------------------------------------------------------------
# Battle menus (PIF's): Fight/Bag/Pokémon/Run, moves, targets
#-------------------------------------------------------------------------------
class BattleMenuBase
  alias kif_mouse_menu_update update unless method_defined?(:kif_mouse_menu_update)

  def update
    kif_mouse_menu_update
    kif_mouse_hover if KIF::Mouse.active? && @visible && !disposed?
  end

  def kif_mouse_hover
    m = KIF::Mouse
    return if is_a?(TargetMenuDisplay) && @mode == 1   # every target at once
    i = nil
    if @buttons
      @buttons.each_with_index do |b, k|
        next unless b && b.visible && m.over_sprite?(b)
        next if is_a?(TargetMenuDisplay) && (@texts.nil? || @texts[k].nil?)
        i = k
        break
      end
    elsif @cmdWindow && @cmdWindow.visible
      i = m.window_item(@cmdWindow)
    else
      return
    end
    if i.nil?
      m.swallow! if m.left
    elsif i != @index
      self.index = i
    end
  end
end

#-------------------------------------------------------------------------------
# EBDX battle menus: command bar and move buttons
#-------------------------------------------------------------------------------
if defined?(CommandWindowEBDX)
  class CommandWindowEBDX
    alias kif_mouse_ebdx_update update unless method_defined?(:kif_mouse_ebdx_update)

    def update
      kif_mouse_ebdx_update
      return unless KIF::Mouse.active? && @sprites && @indexes
      bg = @sprites["bg"]
      return unless bg && bg.bitmap && bg.y < Graphics.height - 8   # the bar is shown
      hit = nil
      @indexes.length.times do |i|
        s = @sprites["b#{i}"]
        next unless s && KIF::Mouse.over_sprite?(s)
        hit = i
        break
      end
      if hit.nil?
        KIF::Mouse.swallow! if KIF::Mouse.left && KIF::Mouse.over_sprite?(bg)
      elsif hit != @index
        @index = hit
        pbPlayCursorSE
      end
    end
  end
end

if defined?(FightWindowEBDX)
  class FightWindowEBDX
    alias kif_mouse_ebdx_update update unless method_defined?(:kif_mouse_ebdx_update)

    def update
      kif_mouse_ebdx_update
      return unless KIF::Mouse.active? && @button.is_a?(Hash) && @nummoves
      @nummoves.times do |i|
        s = @button["#{i}"]
        next unless s && KIF::Mouse.over_sprite?(s)
        if i != @index
          @index = i
          pbSEPlay("EBDX/SE_Select1", 80)
        end
        break
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Load screen: the panels, and the arrows that switch save files
#-------------------------------------------------------------------------------
# prepended: Nuzlocke and SaveFolder prepend pbChoose too (never alias it)
module KIF
  module Mouse
    module LoadChoose
      def pbChoose(*args)
        @kif_mouse_continue = args[1]   # MultiSaves: pbChoose(commands, continue_idx)
        return KIF::Mouse.with_focus(self) { super(*args) }
      end
    end
  end
end
PokemonLoad_Scene.prepend(KIF::Mouse::LoadChoose) unless PokemonLoad_Scene.ancestors.include?(KIF::Mouse::LoadChoose)

class PokemonLoad_Scene
  # Every panel's bitmap is 222 px tall, but only the Continue panel fills it;
  # the other rows draw 46 px (a hit test on the bitmap found an earlier row)
  def kif_mouse_panel_at
    m = KIF::Mouse
    i = 0
    while (s = @sprites["panel#{i}"])
      h = s.instance_variable_get(:@isContinue) ? 222 : 46
      # rows pushed to an edge would scroll the list under the pointer
      if s.visible && s.y >= 0 && s.y + h <= Graphics.height && m.over_rect?(s.x, s.y, s.bitmap ? s.bitmap.width : 416, h, s.viewport)
        return i
      end
      i += 1
    end
    return nil
  end

  def kif_mouse_select(cw, slot)
    old = cw.index
    cw.index = slot
    pbSelectPanel(old, slot) if respond_to?(:pbSelectPanel)
    pbPlayCursorSE
  end

  def kif_mouse_frame
    m = KIF::Mouse
    cw = @sprites["cmdwindow"]
    return unless cw
    lang = @sprites["langicon"]
    if @language_option_selected   # the globe is chosen (MultiSaves)
      return if m.over_sprite?(lang)          # a click there is USE
      m.eat_wheel!
      return m.press!(Input::DOWN) if m.left || (m.moved && kif_mouse_panel_at)   # back to Continue
      return
    end
    if m.wheel != 0   # one row per notch (as UP on Continue would pick the globe)
      n = (@sprites["cmdwindow"].commands.length rescue 0)
      slot = cw.index - m.wheel
      m.eat_wheel!
      kif_mouse_select(cw, slot) if slot >= 0 && slot < n
      return
    end
    if m.left
      %w[leftarrow rightarrow].each do |k|
        next unless m.over_sprite?(@sprites[k])
        return m.press!(k == "leftarrow" ? Input::LEFT : Input::RIGHT)
      end
      if @show_language_option && @kif_mouse_continue && m.over_sprite?(lang)
        kif_mouse_select(cw, @kif_mouse_continue) if cw.index != @kif_mouse_continue
        return m.press!(Input::UP)   # MultiSaves: UP on Continue picks the globe
      end
    end
    slot = kif_mouse_panel_at
    if slot.nil?
      m.swallow! if m.left
    elsif slot != cw.index
      kif_mouse_select(cw, slot)
    end
  end
end

#-------------------------------------------------------------------------------
# Living title menu
#-------------------------------------------------------------------------------
if defined?(KifLivingTitle)
  class KifLivingTitle
    alias kif_mouse_update_input update_input unless method_defined?(:kif_mouse_update_input)

    def update_input
      m = KIF::Mouse
      if m.active? && @rects
        i = @rects.index { |r| m.over_rect?(r.x, r.y, r.width, r.height) }
        if i.nil?
          m.swallow! if m.left
        elsif i != @index
          pbPlayCursorSE if m.moved
          select(i)
        end
      end
      kif_mouse_update_input
    end
  end
end

#-------------------------------------------------------------------------------
# KIF's Options screen: sections, rows, choices, sliders
#-------------------------------------------------------------------------------
class KifSettingsScreen
  alias kif_mouse_handle_input handle_input unless method_defined?(:kif_mouse_handle_input)

  def handle_input
    kif_mouse_wheel_focus if KIF::Mouse.wheel != 0 && !@editing
    kif_mouse_settings if KIF::Mouse.active?
    return kif_mouse_handle_input
  end

  # the wheel scrolls the part under the pointer: the sections or the list
  # (it stays UP/DOWN for the screen's own code)
  def kif_mouse_wheel_focus
    m = KIF::Mouse
    if m.x < SIDE_X1
      @focus = :side if !@query && !@sub && @focus != :side
    elsif @focus != :list && !opt_rows.empty?
      @focus = :list
      refresh
    end
  end

  def kif_mouse_settings
    m = KIF::Mouse
    if @editing
      if m.left
        m.swallow!
        stop_search(:list)
      end
      return
    end
    if m.left && m.y < LIST_Y0   # the title bar: search
      m.swallow!
      return search
    end
    if m.x < SIDE_X1 && m.y >= SIDE_Y0 && m.y < LIST_Y1 - 4
      i = @side_scroll + (m.y - SIDE_Y0) / SIDE_DY
      return m.swallow! if @query || @sub || i >= @sections.length || empty_section?(i)
      if i != @section || @focus != :side
        @section = i
        @sel = 0
        @scroll = 0
        @focus = :side
        pbPlayCursorSE
        refresh
      end
      return
    end
    list = rows
    hit = nil
    if m.x >= LIST_X0 && m.y >= LIST_Y0 && m.y < LIST_Y1 && !list.empty?
      out, _total, _avail, _sel = layout_rows
      hit = out.find { |k, y| list[k].kind == :opt && m.y >= y && m.y < y + row_h(list[k]) }
    end
    return m.swallow! if hit.nil? && m.left   # nothing there: the click does nothing
    return unless hit
    k, y = hit
    n = opt_rows.index(k)
    if n != @sel || @focus != :list
      @sel = n
      @focus = :list
      pbPlayCursorSE if m.moved
      refresh
    end
    kif_mouse_value_click(list[k], y) if m.left
  end

  # a click on the value: that choice, that slider spot, or the arrows
  def kif_mouse_value_click(r, y)
    m = KIF::Mouse
    o = r.opt
    mode = value_mode(r)
    return if mode == :button || r.action   # USE opens it
    m.swallow!
    return locked_buzz(r) if locked_by(o)
    vy = (mode == :below) ? y + ROW_H + 1 : y + 2
    on_value_line = m.y >= vy && m.y < vy + 22
    if KIF::SettingsScreen.slider?(o)
      x0 = VAL_X1 - 170
      x1 = VAL_X1 - 60
      return change(1) unless on_value_line && m.x >= x0 - 4 && m.x <= x1 + 4
      span = o.optend.to_i - o.optstart.to_i
      frac = [[(m.x - x0).to_f / (x1 - x0), 0].max, 1].min
      nv = (frac * span).round
      return if nv == o.get.to_i
      o.set(nv)
      pbPlayCursorSE
      return after_change
    end
    if KIF::SettingsScreen.choices?(o) && mode != :arrows
      vals = o.values.map { |v| PF.utf8(v.to_s) }
      widths = vals.map { |v| PF.width(PF::TEXT, v) + 12 }
      x = VAL_X1 - widths.sum
      if on_value_line && m.x >= x && m.x < VAL_X1
        k = 0
        while k < widths.length - 1 && m.x >= x + widths[k]
          x += widths[k]
          k += 1
        end
        return if k == (o.get rescue 0).to_i
        o.set(k)
        pbPlayCursorSE
        return after_change
      end
      return change(1)
    end
    # arrows: left half back, right half on
    change(m.x < VAL_X1 - 80 ? -1 : 1)
  end
end
