#===============================================================================
# KIF Settings – the new screen (2026-10-16). It replaces Options entirely:
# the pause menu's and the load screen's Options open it, with PIF's own
# options in the same sections.
# * Sidebar: the sections of 015_KIF_SettingsData.rb, then Modules (Off / On /
#   Hidden per module), Mods (On/Off per mod and their settings) and Presets.
# * Rows: every setting KIF and its features register (KIF::Options), under
#   headings, with shorter names under their heading. Choices show as a bar
#   next to the name, or on a second line when they don't fit; sliders as a
#   slider; buttons as OPEN. An orange dot marks a setting changed from its
#   default; Z sets it back.
# * Search (A): names and descriptions in every section.
# Draws the same option objects the old screens used, so no feature changes.
#===============================================================================
module KIF
  module SettingsScreen
    Row = Struct.new(:kind, :opt, :scope, :label, :section, :heading, :indent, :mod, :action)

    module_function

    def slider?(o); o.is_a?(SliderOption); end
    def button?(o); o.is_a?(ButtonOption); end
    def choices?(o); !slider?(o) && o.respond_to?(:values) && o.values.is_a?(Array); end

    # Every setting the player can see now, in menu order:
    # [{opt:, scope:, name:, mod:, children: [{opt:, scope:}]}]
    # all: also the settings of modules that are Off/Hidden (to see where a
    # module's settings would go)
    def collect(all = false)
      out = []
      KIF::Options.all_menu_ids.each do |menu|
        parent = nil
        KIF::Options.entries(menu).each do |scope, builder|
          next if scope == :save && !KIF.in_game?
          mod = (KIF::Modules.for_proc(builder) rescue nil)
          next unless all || KIF::Modules.visible?(mod)
          opt = begin
                  builder.call
                rescue StandardError => e
                  KIF.log("KIF Settings: a #{menu} setting failed to build (#{e.class}: #{e.message})")
                  nil
                end
          next unless opt && opt.respond_to?(:name)
          name = opt.name.to_s
          if name.start_with?(" ") && parent
            parent[:children] << { :opt => opt, :scope => scope }
            next
          end
          parent = { :opt => opt, :scope => scope, :name => name.strip, :mod => mod, :children => [] }
          out << parent
        end
      end
      out.concat(root_options)
      return out
    end

    # PIF's own Options (the four menus behind its root buttons) and anything
    # mods add to the root. Returns [items, extra root rows, root scene]; the
    # scenes stay alive because their option procs belong to them.
    PIF_ROOT = ["System & Audio", "Gameplay", "Visuals & Content", "Challenge Options", "KIF Settings"]

    def pif_items(inloadscreen)
      root = PokemonGameOption_Scene.new
      root_opts = (root.pbGetOptions(inloadscreen) rescue [])
      scenes = [SystemOptionsScene]
      scenes += [GameplayOptionsScene, SpriteOptionsScene, ChallengeOptionsScene] if $game_switches
      items = []
      seen = {}
      scenes.each do |k|
        sc = k.new
        opts = begin
                 sc.pbGetOptions(inloadscreen)
               rescue StandardError => e
                 KIF.log("KIF Settings: #{k} options failed (#{e.class}: #{e.message})")
                 []
               end
        opts.each do |o|
          next unless o && o.respond_to?(:name)
          n = o.name.to_s.strip
          next if seen[n]
          seen[n] = true
          items << { :opt => o, :scope => nil, :name => n, :mod => nil, :children => [], :pif => sc }
        end
      end
      extra = root_opts.reject { |o| !o.respond_to?(:name) || PIF_ROOT.include?(o.name.to_s) || seen[o.name.to_s.strip] }
      return [items, extra, root]
    end

    # module id => [section labels] where its settings sit
    def module_sections
      map = {}
      topic_rows(collect(true)).each do |sec, list|
        label = (SECTIONS.find { |x| x[0] == sec } || [nil, sec.to_s])[1]
        list.each do |r|
          next unless r.kind == :opt && r.mod
          map[r.mod] ||= []
          map[r.mod] << label unless map[r.mod].include?(label)
        end
      end
      return map
    end

    # The rows that sat at the bottom of the old KIF Settings
    def root_options
      inc = EnumOption.new(_INTL("Increment Slider by"), KIF::Options::SLIDER_STEPS.map { |s| s.to_s },
                           proc { $PokemonSystem.raiserb }, proc { |v| $PokemonSystem.raiserb = v },
                           _INTL("For large sliders (e.g. shiny odds), how much one press changes them."))
      dbg = EnumOption.new(_INTL("DEBUG"), [_INTL("Off"), _INTL("On")],
                           proc { $PokemonSystem.debug },
                           proc { |v| $PokemonSystem.debug = v; KIF.sync_debug },
                           [_INTL("Doesn't force debug to be activated"), _INTL("Force debug to be activated")])
      return [{ :opt => inc, :scope => :global, :name => "Increment Slider by", :mod => nil, :children => [] },
              { :opt => dbg, :scope => :global, :name => "DEBUG", :mod => nil, :children => [] }]
    end

    # section id => [Row...]
    def topic_rows(items)
      by_name = {}
      items.each { |it| by_name[it[:name]] ||= it }
      placed = {}
      rows = {}
      add = lambda do |list, it, id, heading, rename|
        placed[it[:name]] = true
        label = rename ? (RENAMES[it[:name]] || it[:name]) : it[:name]
        list << Row.new(:opt, it[:opt], it[:scope], label, id, heading, 0, it[:mod])
        it[:children].each do |c|
          list << Row.new(:opt, c[:opt], c[:scope], c[:opt].name.to_s.strip, id, heading, 1, it[:mod])
        end
      end
      SECTIONS.each do |id, _label, _col, groups|
        list = []
        groups.each do |heading, names|
          found = names.map { |n| by_name[n] }.compact
          next if found.empty?
          list << Row.new(:head, nil, nil, heading, id, heading, 0, nil)
          found.each { |it| add.call(list, it, id, heading, true) }
        end
        rows[id] = list
      end
      left = items.reject { |it| placed[it[:name]] }
      unless left.empty?
        rows[:game] ||= []
        rows[:game] << Row.new(:head, nil, nil, "Other", :game, "Other", 0, nil)
        left.each { |it| add.call(rows[:game], it, :game, "Other", false) }
      end
      return rows
    end

    def module_rows
      where = (module_sections rescue {})
      KIF::Modules::MODULES.map do |id, (name, desc, _f)|
        d = _INTL(desc)
        d += " " + _INTL("Settings in: {1}.", where[id].map { |l| _INTL(l) }.join(", ")) if where[id] && !where[id].empty?
        opt = EnumOption.new(_INTL(name), KIF::Modules::STATE_NAMES.map { |s| _INTL(s) },
                             proc { KIF::Modules.state(id) }, proc { |v| KIF::Modules.set_state(id, v) }, d)
        Row.new(:opt, opt, :save, _INTL(name), :modules, nil, 0, nil)
      end
    end

    def mod_rows
      return [] unless defined?(KIF::Mods) && KIF::Mods.respond_to?(:entries)
      rows = []
      list = (KIF::Mods.entries rescue [])
      unless list.empty?
        rows << Row.new(:head, nil, nil, _INTL("Installed"), :mods, "Installed", 0, nil)
        list.each do |e|
          opt = EnumOption.new(e.name.to_s, [_INTL("Off"), _INTL("On")],
                               proc { e.enabled? ? 1 : 0 },
                               proc { |v| e.source.set_enabled(e, v == 1) if e.enabled? != (v == 1) },
                               KifModsScene.describe(e))
          rows << Row.new(:opt, opt, :global, e.name.to_s, :mods, "Installed", 0, nil)
        end
      end
      withset = list.reject { |e| e.settings.nil? || e.settings.empty? }
      cat = defined?(KIF::ModSettings) && KIF::ModSettings.active? && !KIF::ModSettings.registry.empty?
      if !withset.empty? || cat
        rows << Row.new(:head, nil, nil, _INTL("Settings"), :mods, "Settings", 0, nil)
        withset.each do |e|
          opt = ButtonOption.new(_INTL("{1} settings", e.name), nil, _INTL("Settings added by {1}", e.name))
          rows << Row.new(:opt, opt, :global, opt.name, :mods, "Settings", 0, nil, [:mod_page, e])
        end
        if cat
          opt = ButtonOption.new(_INTL("Settings by category"), nil, _INTL("Every mod's settings, sorted by category"))
          rows << Row.new(:opt, opt, :global, opt.name, :mods, "Settings", 0, nil, [:categories])
        end
      end
      return rows
    end

    def preset_rows
      return [] unless defined?(KifPresetsScene) && KIF.in_game?
      scene = KifPresetsScene.new
      return scene.pbGetOptions(false).map { |o| Row.new(:opt, o, :save, o.name.to_s, :presets, nil, 0, nil) }
    end

    #---------------------------------------------------------------------------
    # Defaults: what each row shows with a brand-new PokemonSystem (KIF's and
    # PIF's settings live there). Rows that read something else (the save's
    # difficulty, mod settings) get no default: no dot, no Z.
    # opt => value the row shows at its default
    #---------------------------------------------------------------------------
    def defaults_for(opts)
      out = {}
      real = $PokemonSystem
      return out unless real
      fresh = (PokemonSystem.new rescue nil)
      return out unless fresh
      opts.each do |o|
        next if button?(o) || !o.respond_to?(:get)
        # only rows that read PokemonSystem: with none at all, they fail
        reads = begin
                  $PokemonSystem = nil
                  o.get
                  false
                rescue StandardError
                  true
                ensure
                  $PokemonSystem = real
                end
        next unless reads
        d = begin
              $PokemonSystem = fresh
              o.get
            rescue StandardError
              nil
            ensure
              $PokemonSystem = real
            end
        out[o] = d unless d.nil?
      end
      return out
    ensure
      $PokemonSystem = real if real
    end
  end
end

#===============================================================================
class KifSettingsScreen
  include KIF::PixelUI

  W = 512
  H = 384
  PF = KIF::PixelFont
  SIDE_X1 = 144
  LIST_X0 = 150
  LIST_X1 = W - 6
  LIST_Y0 = 36
  LIST_Y1 = H - 120
  ROW_H   = 26
  HEAD_H  = 18
  LINE2_H = 26
  SIDE_Y0 = 40
  SIDE_DY = 20
  NAME_X  = LIST_X0 + 16
  VAL_X1  = LIST_X1 - 12
  SEGON   = Color.new(90, 110, 140)
  SIDESEL = Color.new(52, 66, 86)
  DOTC    = Color.new(232, 160, 48)

  attr_accessor :section, :sel, :focus

  def initialize(inloadscreen = false)
    @inloadscreen = inloadscreen
    @sections = KIF::SettingsScreen::SECTIONS.map { |id, label, col, _g| [id, label, col] }
    @section = 0
    @sel = 0
    @scroll = 0
    @side_scroll = 0
    @focus = :side
    @query = nil
    @sub = nil        # a mod's settings page shown inside the Mods section
    rebuild
    @section = next_section(-1, 1) || 0
  end

  # sections with nothing to show (every module behind them Off) are greyed
  # out and skipped
  def empty_section?(i)
    id = @sections[i][0]
    return false if id == :modules
    return (@rows[id] || []).none? { |r| r.kind == :opt }
  end

  def next_section(from, dir)
    n = @sections.length
    1.upto(n) do |k|
      i = (from + dir * k) % n
      return i unless empty_section?(i)
    end
    return nil
  end

  # (Re)reads every setting: after any change, so rows that depend on others
  # (module states, slider steps) are current
  def rebuild
    items = KIF::SettingsScreen.collect
    pif, extra, @root = KIF::SettingsScreen.pif_items(@inloadscreen)
    items = pif + items
    @rows = KIF::SettingsScreen.topic_rows(items)
    @rows[:modules] = KIF::SettingsScreen.module_rows
    @rows[:mods] = KIF::SettingsScreen.mod_rows
    unless extra.empty?
      @rows[:mods] << KIF::SettingsScreen::Row.new(:head, nil, nil, _INTL("Added to Options"), :mods, "Added to Options", 0, nil)
      extra.each { |o| @rows[:mods] << KIF::SettingsScreen::Row.new(:opt, o, nil, o.name.to_s, :mods, "Added to Options", 0, nil) }
    end
    @rows[:presets] = KIF::SettingsScreen.preset_rows
    opts = items.flat_map { |it| [it[:opt]] + it[:children].map { |c| c[:opt] } }
    @defaults = KIF::SettingsScreen.defaults_for(opts)
    if @sub
      e = @sub[:entry]
      @sub[:rows] = sub_rows_for(e) if e
    end
  end

  def query=(q)
    @query = (q.nil? || q.strip.empty?) ? nil : q.strip
    @scroll = 0
    @sel = 0
  end

  def section_id
    return @sections[@section][0]
  end

  def rows
    return @sub[:rows] if @sub
    if @query
      q = @query.downcase
      out = []
      @sections.each do |id, label, _c|
        found = (@rows[id] || []).select do |r|
          r.kind == :opt && (r.label.downcase.include?(q) || r.opt.name.to_s.downcase.include?(q) ||
                             desc_of(r.opt).downcase.include?(q))
        end
        next if found.empty?
        found.group_by(&:heading).each do |h, rs|
          out << KIF::SettingsScreen::Row.new(:head, nil, nil, h ? "#{label} > #{h}" : label, id, h, 0, nil)
          out.concat(rs)
        end
      end
      return out
    end
    return @rows[section_id] || []
  end

  def opt_rows
    list = rows
    return list.each_index.select { |i| list[i].kind == :opt }
  end

  def current
    o = opt_rows
    return nil if o.empty?
    return rows[o[@sel % o.length]]
  end

  def desc_of(opt)
    d = opt.description
    if d.is_a?(Array)
      v = (opt.get rescue 0)
      d = d[v.is_a?(Integer) ? v : 0] || d[0]
    end
    return PF.utf8(d.to_s).gsub(/\s+/, " ").strip
  end

  def changed?(r)
    return false unless r.opt && @defaults.has_key?(r.opt)
    return (r.opt.get rescue nil) != @defaults[r.opt]
  end

  #---------------------------------------------------------------------------
  # Running
  #---------------------------------------------------------------------------
  def main
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99_999
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(W, H)
    refresh
    loop do
      Graphics.update
      Input.update
      break if handle_input == :close
      tick_description
    end
    close_effects
  ensure
    @sprite.bitmap.dispose if @sprite && @sprite.bitmap
    @sprite.dispose if @sprite
    @viewport.dispose if @viewport
  end

  def handle_input
    # A (and Q / Page Up: the same button) or F / Tab: search
    return search if Input.trigger?(Input::JUMPUP) || Input.trigger?(Input::SPECIAL)
    if @focus == :side
      if Input.repeat?(Input::DOWN) || Input.repeat?(Input::UP)
        @section = next_section(@section, Input.repeat?(Input::DOWN) ? 1 : -1) || @section
        @sel = 0
        @scroll = 0
        pbPlayCursorSE
        refresh
      elsif Input.trigger?(Input::RIGHT) || Input.trigger?(Input::USE)
        if opt_rows.empty?
          pbPlayBuzzerSE
        else
          @focus = :list
          pbPlayDecisionSE
          refresh
        end
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        return :close
      end
      return nil
    end
    # the list
    n = opt_rows.length
    if n == 0
      @focus = :side unless @query
      return nil
    end
    if Input.repeat?(Input::DOWN) || Input.repeat?(Input::UP)
      @sel = (@sel + (Input.repeat?(Input::DOWN) ? 1 : -1)) % n
      pbPlayCursorSE
      refresh
    elsif Input.repeat?(Input::LEFT) || Input.repeat?(Input::RIGHT)
      change(Input.repeat?(Input::RIGHT) ? 1 : -1)
    elsif Input.trigger?(Input::USE)
      press
    elsif Input.trigger?(Input::ACTION)
      reset_default
    elsif Input.trigger?(Input::BACK)
      pbPlayCancelSE
      if @sub
        @sub = nil
        @sel = @sub_return || 0
        @scroll = 0
      elsif @query
        @query = nil
        @sel = 0
        @scroll = 0
        @focus = :side
      else
        @focus = :side
      end
      refresh
    end
    return nil
  end

  # What PIF's Options did on closing (GameOptions.rb pbEndScene): keep the
  # save's lowest difficulty, reshuffle trainers when the game mode changed
  def close_effects
    if $Trainer && $Trainer.respond_to?(:lowest_difficulty) && $Trainer.selected_difficulty < $Trainer.lowest_difficulty
      $Trainer.lowest_difficulty = $Trainer.selected_difficulty
    end
    mode = @root && @root.instance_variable_get(:@current_game_mode)
    if mode && defined?(getTrainersDataMode) && getTrainersDataMode != mode
      pbMessage(_INTL("The game was mode changed - Reshuffling trainers."))
      Kernel.pbShuffleTrainers
    end
  rescue StandardError => e
    KIF.log("KIF Settings: closing failed (#{e.class}: #{e.message})")
  end

  def change(dir)
    r = current
    return unless r
    o = r.opt
    return if KIF::SettingsScreen.button?(o)
    cur = (o.get rescue nil)
    return if cur.nil?
    nv = dir > 0 ? o.next(cur) : o.prev(cur)
    return if nv == cur
    o.set(nv)
    pbPlayCursorSE
    after_change
  end

  def reset_default
    r = current
    return pbPlayBuzzerSE unless r && @defaults.has_key?(r.opt) && changed?(r)
    r.opt.set(@defaults[r.opt])
    pbPlayDecisionSE
    after_change
  end

  def after_change
    keep = [@section, @sel, @scroll]
    rebuild
    @section, @sel, @scroll = keep
    if empty_section?(@section) && !@query && !@sub
      @focus = :side
      @section = next_section(@section, 1) || @section
      @sel = 0
      @scroll = 0
    end
    @sel = 0 if @sel >= [opt_rows.length, 1].max
    refresh
  end

  def press
    r = current
    return unless r
    if r.action
      pbPlayDecisionSE
      case r.action[0]
      when :mod_page
        e = r.action[1]
        @sub_return = @sel
        @sub = { :title => _INTL("{1} settings", e.name), :entry => e, :rows => sub_rows_for(e) }
        @sel = 0
        @scroll = 0
        refresh
      when :categories
        hidden { pbFadeOutIn { PokemonOptionScreen.new(KifModSettingsScene.new).pbStartScreen } }
        after_change
      end
      return
    end
    return pbPlayBuzzerSE unless KIF::SettingsScreen.button?(r.opt)
    pbPlayDecisionSE
    hidden { r.opt.trigger }
    after_change
  end

  # Another screen or message box takes over: this one steps aside
  def hidden
    @sprite.visible = false if @sprite
    yield
  ensure
    @sprite.visible = true if @sprite && !@sprite.disposed?
  end

  def sub_rows_for(e)
    list = [KIF::SettingsScreen::Row.new(:head, nil, nil, _INTL("{1} settings", e.name), :mods, nil, 0, nil)]
    page = KifModPageScene.new(e)
    page.pbGetOptions(false).each do |o|
      next unless o && o.respond_to?(:name)
      list << KIF::SettingsScreen::Row.new(:opt, o, :global, o.name.to_s, :mods, nil, 0, nil)
    end
    return list
  end

  def search
    pbPlayDecisionSE
    q = nil
    hidden { q = pbEnterText(_INTL("Search settings"), 0, 20, @query || "") }
    self.query = q
    @sub = nil
    @focus = opt_rows.empty? ? :side : :list
    @focus = :list if @query
    refresh
    return nil
  end

  #---------------------------------------------------------------------------
  # Drawing
  #---------------------------------------------------------------------------
  def refresh
    draw(@sprite.bitmap) if @sprite
  end

  def draw(b)
    b.fill_rect(0, 0, W, H, BG)
    draw_title(b)
    draw_sidebar(b)
    draw_list(b)
    draw_description(b)
    hints = if @focus == :side
              [[:ud, _INTL("Section")], [:lr, _INTL("Open")], ["A", _INTL("Search")], ["Esc", _INTL("Close")]]
            else
              [[:ud, _INTL("Select")], [:lr, _INTL("Change")], ["Z", _INTL("Default")],
               ["Esc", @query ? _INTL("Clear search") : (@sub ? _INTL("Back") : _INTL("Sections"))]]
            end
    footer(b, hints)
  end

  def draw_title(b)
    b.fill_rect(0, 0, W, 32, PANEL2)
    b.fill_rect(0, 31, W, 1, LINE)
    text(b, 10, 2, 200, 28, _INTL("KIF Settings"), TXT, PF::TITLE)
    x0 = 10 + PF.width(PF::TITLE, _INTL("KIF Settings")) + 12
    rbox(b, x0, 4, W - 8, 27, 5, DARK, @query ? SELB : LINE)
    c = @query ? TXT : DIM
    rbox(b, x0 + 7, 9, x0 + 16, 18, 4, c)
    rbox(b, x0 + 9, 11, x0 + 14, 16, 2, DARK)
    3.times { |i| b.fill_rect(x0 + 15 + i, 17 + i, 2, 2, c) }
    if @query
      text(b, x0 + 24, 4, 300, 23, PF.fit(PF::TEXT, @query, 200), TXT)
      n = opt_rows.length
      text(b, W - 16, 4, 0, 23, n == 1 ? _INTL("1 found") : _INTL("{1} found", n), DIM, PF::TEXT, 1)
    else
      text(b, x0 + 24, 4, 200, 23, _INTL("Search settings"), DIM)
      kw = PF.width(PF::TINY, "A") + 8
      key(b, W - 14 - kw, 8, "A")
    end
  end

  def draw_sidebar(b)
    rbox(b, 6, 36, SIDE_X1, LIST_Y1, 6, PANEL)
    fit = (LIST_Y1 - 4 - SIDE_Y0) / SIDE_DY
    @side_scroll = @section - fit + 1 if @section >= @side_scroll + fit
    @side_scroll = @section if @section < @side_scroll
    counts = {}
    rows.each { |r| counts[r.section] = counts[r.section].to_i + 1 if r.kind == :opt } if @query
    y = SIDE_Y0
    (@sections[@side_scroll, fit] || []).each_with_index do |(id, label, col), k|
      i = k + @side_scroll
      active = (i == @section) && !@query
      if active
        rbox(b, 9, y - 1, SIDE_X1 - 3, y + SIDE_DY - 2, 4, @focus == :side ? SEL : SIDESEL,
             @focus == :side ? SELB : LINE)
      end
      rbox(b, 14, y + 2, 28, y + 16, 3, Color.new(*col))
      text(b, 14, y + 3, 15, 13, label[0], TXT, PF::TINY, 2)
      dim = (@query && counts[id].nil?) || (!@query && empty_section?(i))
      name = PF.fit(PF::TEXT, _INTL(label), SIDE_X1 - 35 - (counts[id] ? 12 : 0))
      text(b, 33, y - 2, 120, 22, name, active ? TXT : (dim ? Color.new(95, 104, 118) : DIM), PF::TEXT, 0, active)
      text(b, SIDE_X1 - 8, y + 3, 0, 13, counts[id].to_s, WARN, PF::TINY, 1) if counts[id]
      y += SIDE_DY
    end
  end

  def value_mode(r)
    o = r.opt
    return :button if KIF::SettingsScreen.button?(o)
    name_w = PF.width(PF::ROW, r.label) + r.indent * 16
    if KIF::SettingsScreen.slider?(o)
      return VAL_X1 - 170 >= NAME_X + name_w + 10 ? :beside : :below
    end
    return :arrows unless KIF::SettingsScreen.choices?(o)
    seg = o.values.sum { |v| PF.width(PF::TEXT, PF.utf8(v.to_s)) + 12 }
    return :beside if VAL_X1 - seg >= NAME_X + name_w + 10
    return :below if seg <= VAL_X1 - (NAME_X + 8)
    return :arrows
  end

  def row_h(r)
    return HEAD_H if r.kind == :head
    return value_mode(r) == :below ? ROW_H + LINE2_H : ROW_H
  end

  def layout_rows
    list = rows
    ys = []
    y = 0
    list.each { |r| ys << y; y += row_h(r) }
    avail = (LIST_Y1 - 4) - (LIST_Y0 + 4)
    o = opt_rows
    i = o.empty? ? nil : o[@sel % o.length]
    if i
      top_needed = (i > 0 && list[i - 1].kind == :head) ? ys[i - 1] : ys[i]
      @scroll = top_needed if top_needed < @scroll
      while ys[i] + row_h(list[i]) - @scroll > avail
        nxt = ys.find { |v| v > @scroll }
        break unless nxt
        @scroll = nxt
      end
    end
    out = []
    list.each_index do |k|
      h = row_h(list[k])
      next if ys[k] < @scroll || ys[k] + h - @scroll > avail
      # a heading whose first row doesn't fit waits for the next scroll
      if list[k].kind == :head && list[k + 1] && ys[k + 1] + row_h(list[k + 1]) - @scroll > avail
        next
      end
      out << [k, LIST_Y0 + 4 + ys[k] - @scroll]
    end
    return [out, y, avail, i]
  end

  def draw_list(b)
    rbox(b, LIST_X0, LIST_Y0, LIST_X1, LIST_Y1, 6, PANEL)
    list = rows
    if list.empty?
      msg = if @query then _INTL("Nothing matches \"{1}\".", @query)
            elsif section_id == :mods then _INTL("No mods yet. Put them in the Mods folder.")
            elsif !KIF.in_game? then _INTL("Load a save to change these settings.")
            else _INTL("Nothing here right now.")
            end
      text(b, LIST_X0 + 12, LIST_Y0 + 8, LIST_X1 - LIST_X0 - 24, 22, PF.fit(PF::TEXT, msg, LIST_X1 - LIST_X0 - 24), DIM)
      return
    end
    out, total, avail, sel_row = layout_rows
    out.each do |i, y|
      r = list[i]
      if r.kind == :head
        heading(b, LIST_X0 + 8, LIST_X1 - 10, y + 3, r.label)
        next
      end
      selected = (i == sel_row) && @focus == :list
      mode = value_mode(r)
      rbox(b, LIST_X0 + 4, y, LIST_X1 - 8, y + row_h(r) - 2, 4, SEL, SELB) if selected
      x = NAME_X + r.indent * 16
      if r.indent > 0
        b.fill_rect(x - 9, y + 2, 1, 12, LINE)
        b.fill_rect(x - 9, y + 13, 6, 1, LINE)
      end
      rrect(b, x - 9, y + 10, x - 5, y + 14, 1, DOTC) if changed?(r)
      text(b, x, y - 1, 330, 26, r.label, TXT, PF::ROW)
      vy = (mode == :below) ? y + ROW_H + 1 : y + 2
      draw_value(b, r, vy, selected, mode)
    end
    if total > avail
      track = LIST_Y1 - LIST_Y0 - 12
      bar = [track * avail / total, 12].max
      pos = (track - bar) * @scroll / [total - avail, 1].max
      b.fill_rect(LIST_X1 - 5, LIST_Y0 + 6, 2, track, Color.new(60, 70, 86))
      b.fill_rect(LIST_X1 - 5, LIST_Y0 + 6 + pos, 2, bar, DIM)
    end
  end

  def draw_value(b, r, y, selected, mode)
    o = r.opt
    if mode == :button
      pill(b, VAL_X1, y + 3, _INTL("OPEN"), selected ? SEL : PILL, true) if o.instance_variable_get(:@onPressProc) || r.action
      return
    end
    if KIF::SettingsScreen.slider?(o)
      v = o.get.to_i + o.optstart.to_i
      span = [o.optend.to_i - o.optstart.to_i, 1].max
      frac = [[(v - o.optstart.to_i).to_f / span, 0].max, 1].min
      x0 = VAL_X1 - 170
      x1 = VAL_X1 - 60
      kx = x0 + (frac * (x1 - x0)).round
      rbox(b, x0, y + 8, x1, y + 12, 2, DARK)
      rbox(b, x0, y + 8, kx, y + 12, 2, selected ? SELB : SEGON)
      rbox(b, kx - 4, y + 4, kx + 4, y + 16, 3, TXT)
      text(b, VAL_X1, y, 0, 22, v.to_s, TXT, PF::TEXT, 1)
      return
    end
    vals = o.respond_to?(:values) ? o.values.map { |v| PF.utf8(v.to_s) } : []
    cur = (o.get rescue 0).to_i
    if KIF::SettingsScreen.choices?(o) && mode != :arrows
      widths = vals.map { |v| PF.width(PF::TEXT, v) + 12 }
      x = VAL_X1 - widths.sum
      rbox(b, x - 1, y, VAL_X1 + 1, y + 21, 4, DARK, LINE)
      vals.each_with_index do |v, k|
        if k == cur
          rbox(b, x, y + 1, x + widths[k], y + 20, 3, selected ? SELB : SEGON)
          text(b, x, y, widths[k], 22, v, selected ? SHADOW : TXT, PF::TEXT, 2)
        else
          text(b, x, y, widths[k], 22, v, DIM, PF::TEXT, 2)
        end
        x += widths[k]
      end
      return
    end
    shown = o.is_a?(NumberOption) ? (cur + o.optstart.to_i).to_s : (vals[cur] || cur.to_s)
    v = PF.fit(PF::TEXT, shown, 150)
    vw = PF.width(PF::TEXT, v)
    text(b, VAL_X1 - 14 - vw, y, vw + 2, 22, v, TXT)
    if selected
      tri(b, VAL_X1 - vw - 26, y + 5, :l, SELB)
      tri(b, VAL_X1 - 8, y + 5, :r, SELB)
    end
  end

  def draw_description(b)
    y0 = LIST_Y1 + 4
    rbox(b, 6, y0, W - 6, H - 30, 6, PANEL2, LINE)
    r = (@focus == :list || @query) ? current : nil
    if r.nil?
      label = @sub ? @sub[:title] : _INTL(@sections[@section][1])
      text(b, 14, y0 + 1, 330, 26, label, TXT, PF::ROW)
      n = opt_rows.length
      text(b, 14, y0 + 27, W - 28, 22, n == 1 ? _INTL("1 setting") : _INTL("{1} settings", n), DIM)
      return
    end
    text(b, 14, y0 + 1, 330, 26, PF.fit(PF::ROW, r.label, 330), TXT, PF::ROW)
    x = W - 14
    if r.scope && r.section != :modules && r.section != :presets && !r.action
      x -= pill(b, x, y0 + 7, r.scope == :global ? _INTL("ALL SAVES") : _INTL("THIS SAVE"), PILL, true) + 6
    end
    if @defaults.has_key?(r.opt) && KIF::SettingsScreen.choices?(r.opt)
      d = r.opt.values[@defaults[r.opt].to_i]
      pill(b, x, y0 + 7, _INTL("DEFAULT: {1}", PF.utf8(d.to_s).upcase), PILL, true) if d
    elsif @defaults.has_key?(r.opt) && KIF::SettingsScreen.slider?(r.opt)
      pill(b, x, y0 + 7, _INTL("DEFAULT: {1}", @defaults[r.opt].to_i + r.opt.optstart.to_i), PILL, true)
    end
    lines = wrap(desc_of(r.opt), W - 30)
    lines = wrap(desc_of(r.opt), W - 46) if lines.length > DESC_LINES   # room for the arrows
    first = desc_first_line(r, lines.length)
    lines[first, DESC_LINES].each_with_index do |ln, k|
      text(b, 14, y0 + 26 + k * DESC_DY, W - 34, DESC_DY, ln, TXT)
    end
    # more lines than fit: a small arrow shows which way the rest is
    if lines.length > DESC_LINES
      tri(b, W - 20, y0 + 32, :u, first > 0 ? DIM : LINE, 3)
      tri(b, W - 20, y0 + 72, :d, first + DESC_LINES < lines.length ? DIM : LINE, 3)
    end
  end

  # A description longer than the panel moves up one line at a time while
  # its row stays selected, then starts again from the top
  DESC_LINES = 3
  DESC_DY    = 17
  DESC_STEP  = 100   # frames per line
  DESC_HOLD  = 3     # steps spent on the first and last lines

  def desc_first_line(r, n)
    extra = n - DESC_LINES
    return 0 if extra <= 0
    if @desc_row != r.object_id
      @desc_row = r.object_id
      @desc_tick = 0
    end
    step = @desc_tick.to_i / DESC_STEP
    cycle = extra + 2 * DESC_HOLD
    pos = step % cycle
    return 0 if pos < DESC_HOLD
    return [pos - DESC_HOLD + 1, extra].min
  end

  def tick_description
    r = (@focus == :list || @query) ? current : nil
    return unless r && r.object_id == @desc_row
    before = @desc_tick.to_i / DESC_STEP
    @desc_tick = @desc_tick.to_i + 1
    refresh if @desc_tick / DESC_STEP != before
  end

  def wrap(str, width)
    out = []
    line = ""
    str.split(/\s+/).each do |word|
      t = line.empty? ? word : "#{line} #{word}"
      if PF.width(PF::TEXT, t) > width && !line.empty?
        out << line
        line = word
      else
        line = t
      end
    end
    out << line unless line.empty?
    return out
  end
end

#===============================================================================
# Options (pause menu and load screen) opens this screen instead of PIF's
# Options. If it fails, PIF's Options open as before and the error is logged.
#===============================================================================
KIF.guard_base("052_InfiniteFusion/System/Game Options/GameOptions.rb", 2796826256, "PokemonGameOption_Scene#pbEndScene (KifSettingsScreen#close_effects)")

class PokemonOptionScreen
  alias kif_ss_pbStartScreen pbStartScreen unless method_defined?(:kif_ss_pbStartScreen)

  def pbStartScreen(inloadscreen = false)
    if @scene.instance_of?(PokemonGameOption_Scene)
      begin
        return KifSettingsScreen.new(inloadscreen).main
      rescue StandardError => e
        KIF.log("KIF Settings failed, PIF's Options instead (#{e.class}: #{e.message})")
        KIF.log(e.backtrace.first(3).join(" | ")) if e.backtrace
      end
    end
    return kif_ss_pbStartScreen(inloadscreen)
  end
end
