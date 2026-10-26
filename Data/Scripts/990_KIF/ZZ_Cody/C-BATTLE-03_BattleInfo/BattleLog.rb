#===============================================================================
# C-BATTLE-03 – Battle Info: Log page (2026-10-25)
# A player: a turn can start with 3 or 4 ability pop-ups, and with the
# speed-up on they are gone before they can be read. Every message the battle
# shows and every ability pop-up (mods' too, e.g. KIF-ER's innates) is kept,
# by turn, and Battle Info gets a Log page after Speed: newest at the bottom,
# Up / Down scroll, a green dot for lines about your Pokémon and a red one for
# the foe's (the Pokémon the line starts with, else the one whose move it is).
# Recorded where the battle hands its text to the screen (PokeBattle_Battle's
# pbDisplay family, hooked in BattleInfo.rb), so PIF's battle scene and EBDX's
# work the same, and Turn Skipper's faster or hidden round-end messages are
# kept too (it hides them later, in the scene). Text a battle item or a
# feature hands to the scene directly ("Pikachu's HP was restored.") is caught
# at the scene. Kept on the battle object only: gone after the battle, never
# in the save.
#===============================================================================
module KIF
  module BattleLog
    # shortcut: older lines drop past this many, raise it if long battles need more
    MAX = 500

    module_function

    # [[turn, side, text, popup?]]: turn 0 is before the first turn; side
    # :own, :foe or nil
    def lines(battle)
      return battle.instance_variable_get(:@kif_log) || []
    end

    def add(battle, msg, battler = nil, popup = false)
      # message codes: \PN is the player's name; the rest (\n, \c[2], \wt[5]...)
      # become a space, only the code's own letters (Essentials' codes)
      text = KIF::PixelFont.utf8(msg).gsub(/\\pn/i) { $Trainer ? $Trainer.name.to_s : "" }
                .gsub(/\\[a-z]+\[[^\]]*\]|\\(?:pm|cn|pt|wd|wm|wu|op|cl|[gnrb.|!^])|<[^>]*>|[\x00-\x1F]/i, " ").squeeze(" ").strip
      return if text.empty?
      battler ||= battle.battlers.map { |b| b && b.pokemon && [b, KIF::PixelFont.utf8(b.pbThis)] }.compact
                        .select { |_b, name| text.start_with?(name) }.max_by { |_b, name| name.length }&.first ||
                  battle.instance_variable_get(:@kif_log_actor)
      side = battler ? (KIF::BattleInfo.own?(battler) ? :own : :foe) : nil
      log = battle.instance_variable_get(:@kif_log) || battle.instance_variable_set(:@kif_log, [])
      log << [battle.instance_variable_get(:@kif_log_turn).to_i, side, text, popup]
      log.shift while log.length > MAX
    rescue StandardError => e
      KIF.log("Battle log: line not kept (#{e.class}: #{e.message})") if defined?(KIF.log)
    end

    # An ability pop-up: the name the splash shows (a mod's innate passes it)
    def popup(battle, battler, name = nil)
      return unless battler && battler.pokemon
      add(battle, _INTL("[{1}'s {2}]", battler.pbThis, name || battler.abilityName), battler, true)
    end
  end
end

class PokeBattle_Battle
  alias kif_log_pbCommandPhase pbCommandPhase unless method_defined?(:kif_log_pbCommandPhase) || private_method_defined?(:kif_log_pbCommandPhase)
  alias kif_log_pbDisplayConfirm pbDisplayConfirm unless method_defined?(:kif_log_pbDisplayConfirm) || private_method_defined?(:kif_log_pbDisplayConfirm)

  # Lines from here on belong to this turn (before it: the send-outs)
  def pbCommandPhase(*args)
    @kif_log_turn = @turnCount + 1
    return kif_log_pbCommandPhase(*args)
  end

  def pbDisplayConfirm(msg)
    KIF::BattleLog.add(self, msg)
    return kif_log_pbDisplayConfirm(msg)
  end
end

# Text handed to the scene directly (battle items, Nuzlocke, Level Caps...);
# the battle's own messages go to pbDisplayMessage, not here
class PokeBattle_Scene
  alias kif_log_pbDisplay pbDisplay unless method_defined?(:kif_log_pbDisplay) || private_method_defined?(:kif_log_pbDisplay)

  def pbDisplay(msg, *args, &block)
    KIF::BattleLog.add(@battle, msg) if @battle
    return kif_log_pbDisplay(msg, *args, &block)
  end
end

if defined?(PokeBattle_SceneEBDX)
  class PokeBattle_SceneEBDX
    alias kif_log_ebdx_pbDisplay pbDisplay unless method_defined?(:kif_log_ebdx_pbDisplay) || private_method_defined?(:kif_log_ebdx_pbDisplay)

    def pbDisplay(msg, *args, &block)
      KIF::BattleLog.add(@battle, msg) if @battle
      return kif_log_ebdx_pbDisplay(msg, *args, &block)
    end
  end
end

#-------------------------------------------------------------------------------
# The Log page
#-------------------------------------------------------------------------------
class KifBattleInfoScreen
  LOG_ROW = 20

  # Rows as drawn, built once per opening: [:turn, label] or
  # [side, text, popup?, first row of its line?]
  def log_rows
    @log_rows ||= begin
      rows = []
      last = nil
      KIF::BattleLog.lines(@battle).each do |turn, side, str, popup|
        rows << [:turn, turn == 0 ? _INTL("Start") : _INTL("Turn {1}", turn)] if turn != last
        last = turn
        wrap(PF::TEXT, str, W - 52).each_with_index { |l, i| rows << [side, l, popup, i == 0] }
      end
      rows
    end
  end

  def log_room
    return (H - 74) / LOG_ROW
  end

  def log_scroll(dir)
    top = (@log_top.to_i + dir).clamp(0, [log_rows.length - log_room, 0].max)
    return if top == @log_top
    @log_top = top
    pbPlayCursorSE
    refresh
  end

  def draw_log(b)
    rbox(b, 6, 36, W - 6, H - 30, 6, PANEL)
    rows = log_rows
    max = [rows.length - log_room, 0].max
    @log_top = (@log_top || max).clamp(0, max)   # opens on the newest lines
    return text(b, 16, 40, W - 32, 22, _INTL("Nothing has happened yet."), DIM) if rows.empty?
    y = 40
    rows[@log_top, log_room].each do |side, str, popup, first|
      if side == :turn
        heading(b, 14, W - 26, y + 4, str)
      else
        rrect(b, 16, y + 8, 21, y + 13, 2, side == :own ? OWN : FOE) if side && first
        text(b, 28, y - 1, W - 52, 22, str, popup ? ACC : TXT)
      end
      y += LOG_ROW
    end
    tri(b, W - 20, 42, :u, ACC, 4) if @log_top > 0
    tri(b, W - 20, H - 44, :d, ACC, 4) if @log_top < max
  end
end
