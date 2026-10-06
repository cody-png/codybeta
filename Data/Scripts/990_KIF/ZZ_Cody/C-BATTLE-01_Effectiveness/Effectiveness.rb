#===============================================================================
# C-BATTLE-01 – Move effectiveness indicator (Cody)
# Cody Settings → Battles → "Move Effectiveness" (all saves, default On).
#
# Fight menu, for damaging moves only (foe names too long for the box
# scroll like a car radio display, one character every 0.3 s - Cody):
#   * a marker on each move button: green ▲ super effective, orange ▼ resisted,
#     grey ✕ no effect, nothing when neutral (pixel art at the game's 2x scale);
#   * the highlighted move's info box adds "Super eff." / "Resisted" /
#     "No effect" (single foe), or one line per foe with the multiplier
#     ("Gyarados x4", "Onix x0") when there are several foes.
# With several foes the marker shows the best result among them.
# Uses the battle's own type calculation (in-battle types, KIF type buffs,
# Scrappy, Ring Target, grounded Flying types, ...); abilities like Levitate
# or Wonder Guard are not revealed. Status moves show nothing.
#===============================================================================
KIF::Options.define(:cody_effectiveness, 1, :global)

KIF::Options.add(:cody_battles, :global) {
  EnumOption.new(_INTL("Move Effectiveness"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.cody_effectiveness },
                 proc { |value| $PokemonSystem.cody_effectiveness = value },
                 [_INTL("The Fight menu doesn't show how effective moves are"),
                  _INTL("The Fight menu shows how effective each move is against the foe")])
}

module KIF
  module MoveEffect
    OUTLINE = Color.new(48, 48, 48)
    # result => [marker rows, marker colour, text, text base, text shadow]
    STYLE = {
      :super  => [["...o...", "..o#o..", ".o###o.", "o#####o", "ooooooo"],
                  Color.new(72, 184, 72), "Super eff.", Color.new(64, 176, 64), Color.new(160, 216, 160)],
      :resist => [["ooooooo", "o#####o", ".o###o.", "..o#o..", "...o..."],
                  Color.new(232, 128, 40), "Resisted", Color.new(224, 120, 24), Color.new(240, 200, 150)],
      :none   => [["oo...oo", "o#o.o#o", ".o#o#o.", "..o#o..", ".o#o#o.", "o#o.o#o", "oo...oo"],
                  Color.new(150, 150, 150), "No effect", Color.new(120, 120, 120), Color.new(200, 200, 200)]
    }
    RANK = { :none => 0, :resist => 1, :normal => 2, :super => 3 }

    def self.on?
      return $PokemonSystem && $PokemonSystem.cody_effectiveness.to_i == 1
    end

    def self.foes(battler)
      ret = []
      battler.eachOpposing { |b| ret << b } if battler
      return ret
    end

    # Type multiplier value (Effectiveness::NORMAL_EFFECTIVE = neutral), or nil
    def self.value(move, user, target)
      return nil if !move || !user || !target || move.statusMove?
      boost = move.instance_variable_get(:@powerBoost)
      type = move.pbCalcType(user)
      move.instance_variable_set(:@powerBoost, boost)
      return move.pbCalcTypeMod(type, user, target)
    rescue => e
      KIF.log("Effectiveness check failed: #{e.message}")
      return nil
    end

    def self.result(val)
      return nil if val.nil?
      return :none if ::Effectiveness.ineffective?(val)
      return :resist if ::Effectiveness.not_very_effective?(val)
      return :super if ::Effectiveness.super_effective?(val)
      return :normal
    end

    def self.multiplier_text(val)
      m = val.to_f / ::Effectiveness::NORMAL_EFFECTIVE
      return "x0" if m == 0
      return "x1/#{(1 / m).round}" if m < 1
      return "x#{m.round}"
    end

    LINE_WIDTH   = 104   # px available for a foe line in the info box
    SCROLL_HOLD  = 1.0   # s shown at the start and at the end of a scroll
    SCROLL_STEP  = 0.3   # s per character step

    def self.now
      return Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # First character shown for a name that is `over` characters too long,
    # `t` seconds after the menu opened: hold, step one character at a time,
    # hold at the end, start again.
    def self.scroll_offset(over, t)
      return 0 if over <= 0
      cycle = SCROLL_HOLD * 2 + over * SCROLL_STEP
      t = t % cycle
      return 0 if t < SCROLL_HOLD
      return [((t - SCROLL_HOLD) / SCROLL_STEP).floor + 1, over].min
    end

    def self.draw_marker(bitmap, x, y, res)
      st = STYLE[res]
      return unless st
      st[0].each_with_index do |row, ry|
        row.each_char.with_index do |ch, rx|
          next if ch == "."
          bitmap.fill_rect(x + rx * 2, y + ry * 2, 2, 2, (ch == "o") ? OUTLINE : st[1])
        end
      end
    end
  end
end

class FightMenuDisplay
  alias cody_eff_refreshButtonNames refreshButtonNames unless method_defined?(:cody_eff_refreshButtonNames)
  alias cody_eff_refreshMoveData refreshMoveData unless method_defined?(:cody_eff_refreshMoveData)

  def refreshButtonNames
    cody_eff_refreshButtonNames
    return unless USE_GRAPHICS && KIF::MoveEffect.on? && @battler && @buttons
    foes = KIF::MoveEffect.foes(@battler)
    return if foes.empty?
    moves = @battler.moves
    @buttons.each_with_index do |button, i|
      next if !@visibility["button_#{i}"] || !moves[i]
      results = foes.map { |f| KIF::MoveEffect.result(KIF::MoveEffect.value(moves[i], @battler, f)) }.compact
      next if results.empty?
      best = results.max_by { |r| KIF::MoveEffect::RANK[r] }
      next if best == :normal
      KIF::MoveEffect.draw_marker(@pokemon_name_overlay.bitmap,
                                     button.x - self.x + 166, button.y - self.y + 12, best)
    end
  rescue => e
    KIF.log("Effectiveness markers failed: #{e.message}")
  end

  def refreshMoveData(move)
    @typeIcon.y = self.y + 20 if USE_GRAPHICS && @typeIcon
    cody_eff_refreshMoveData(move)
    @cody_lines = nil
    return unless USE_GRAPHICS && move && KIF::MoveEffect.on? && @battler
    foes = KIF::MoveEffect.foes(@battler)
    return if foes.empty? || move.statusMove?
    bmp = @infoOverlay.bitmap
    if foes.length == 1
      res = KIF::MoveEffect.result(KIF::MoveEffect.value(move, @battler, foes[0]))
      st = KIF::MoveEffect::STYLE[res]
      return unless st
      pbSetSmallFont(bmp)
      pbDrawTextPositions(bmp, [[_INTL(st[2]), 448, 66, 2, st[3], st[4]]])
      pbSetNarrowFont(bmp)
    else
      # Several foes: PP and type icon move up, one line per foe. Names too
      # long for the box scroll like a car radio display (Cody).
      @typeIcon.y = self.y + 6
      @cody_pp = nil
      if move.total_pp > 0
        base, shadow = FightMenuDisplay::TEXT_BASE_COLOR, FightMenuDisplay::TEXT_SHADOW_COLOR
        base, shadow = shadow, base if defined?(isDarkMode) && isDarkMode
        @cody_pp = [_INTL("PP: {1}/{2}", move.pp, move.total_pp), 448, 26, 2, base, shadow]
      end
      pbSetSmallFont(bmp)
      @cody_lines = []
      y = (foes.length > 2) ? 42 : 44
      foes.first(3).each do |f|
        val = KIF::MoveEffect.value(move, @battler, f)
        res = KIF::MoveEffect.result(val) || :normal
        st = KIF::MoveEffect::STYLE[res]
        base = st ? st[3] : FightMenuDisplay::TEXT_BASE_COLOR
        shadow = st ? st[4] : FightMenuDisplay::TEXT_SHADOW_COLOR
        mult = KIF::MoveEffect.multiplier_text(val || ::Effectiveness::NORMAL_EFFECTIVE)
        name = f.name.to_s
        fit = name.length
        fit -= 1 while fit > 1 && bmp.text_size("#{name[0, fit]} #{mult}").width > KIF::MoveEffect::LINE_WIDTH
        @cody_lines << { :name => name, :fit => fit, :mult => mult, :y => y, :base => base, :shadow => shadow }
        y += (foes.length > 2) ? 14 : 16
      end
      pbSetNarrowFont(bmp)
      @cody_marquee_t0 = KIF::MoveEffect.now
      @cody_marquee_key = nil
      cody_eff_draw_lines(true)
    end
  rescue => e
    KIF.log("Effectiveness text failed: #{e.message}")
  end

  def cody_eff_draw_lines(force = false)
    return unless @cody_lines && @infoOverlay && !@infoOverlay.disposed?
    t = KIF::MoveEffect.now - (@cody_marquee_t0 || 0)
    offs = @cody_lines.map { |l| KIF::MoveEffect.scroll_offset(l[:name].length - l[:fit], t) }
    return if !force && offs == @cody_marquee_key
    @cody_marquee_key = offs
    bmp = @infoOverlay.bitmap
    bmp.clear
    lines = []
    lines << @cody_pp if @cody_pp
    @cody_lines.each_with_index do |l, i|
      lines << ["#{l[:name][offs[i], l[:fit]]} #{l[:mult]}", 448, l[:y], 2, l[:base], l[:shadow]]
    end
    pbSetSmallFont(bmp)
    pbDrawTextPositions(bmp, lines)
    pbSetNarrowFont(bmp)
  end

  alias cody_eff_update update unless method_defined?(:cody_eff_update)

  def update
    cody_eff_update
    return unless @cody_lines && @cody_lines.any? { |l| l[:fit] < l[:name].length }
    cody_eff_draw_lines
  rescue => e
    KIF.log("Effectiveness scroll failed: #{e.message}")
    @cody_lines = nil
  end
end
