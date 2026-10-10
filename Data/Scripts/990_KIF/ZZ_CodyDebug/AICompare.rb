#===============================================================================
# Cody Debug – AI compare log (testing build only)
#   With it on (Cody Debug > AI compare log), every time the AI picks an
#   action for a Pokémon, the game first asks the OTHER AI (PIF's or
#   DemICE's, whichever isn't the one set in Options > Battles) what it would
#   do, undoes that, then lets the real one decide. Both answers go to
#   KIF_ai_compare.txt in the save folder, one line per decision, plus a
#   tally at the end of each battle. Both runs start from the same random
#   seed, so a difference comes from the AIs, not from luck. Replacements
#   after a faint are compared the same way.
#   Nothing of the "other" run stays: its choice is cancelled (an item it
#   took from the trainer's bag goes back) and Mega Evolution marks are put
#   back as they were.
#===============================================================================
module KIF
  module AICompare
    MARKER = "AICompare.krs"
    LOG    = "KIF_ai_compare.txt"

    class << self
      attr_accessor :busy

      def marker_path; File.join(KIF.save_dir, MARKER); end
      def log_path;    KIF::Paths.log(LOG);             end

      def on?
        @on = File.exist?(marker_path) if @on.nil?
        return @on
      end

      def on=(v)
        @on = v
        if v
          File.write(marker_path, "AI compare log on\n") rescue nil
        else
          File.delete(marker_path) rescue nil
        end
      end

      def tally; @tally ||= Hash.new(0); end

      def write(line)
        File.open(log_path, "a") { |f| f.puts(line) }
      rescue => e
        KIF.log("AI compare log failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      end

      # Runs the block as the other AI: flips Options > Battles > Battle AI
      def as_other
        old = $PokemonSystem.powerfulai
        $PokemonSystem.powerfulai = (old.to_i == 0) ? 1 : 0
        yield
      ensure
        $PokemonSystem.powerfulai = old
      end

      def ai_name(on = KIF::PowerfulAI.on?); on ? "DemICE" : "PIF"; end

      def who(battle, b)
        return "?" unless b
        side = battle.opposes?(b.index) ? "foe" : "own"
        return "#{side} #{b.name} (#{b.hp}/#{b.totalhp})"
      end

      def describe(battle, idx, choice, mega_before)
        return "nothing" unless choice && choice[0]
        mega = battle.instance_variable_get(:@megaEvolution)
        megatxt = (mega && mega != mega_before) ? " + Mega" : ""
        case choice[0]
        when :UseMove
          mv = choice[2]
          name = mv ? mv.name : "move #{choice[1]}"
          t = choice[3].to_i
          tgt = (t >= 0 && battle.battlers[t]) ? " -> #{battle.battlers[t].name}#{battle.opposes?(idx, t) ? '' : ' (ally)'}" : ""
          return "#{name}#{tgt}#{megatxt}"
        when :SwitchOut
          pk = battle.pbParty(idx)[choice[1]] rescue nil
          return "switch to #{pk ? pk.name : choice[1]}"
        when :UseItem
          return "item #{(GameData::Item.get(choice[1]).name rescue choice[1])}"
        else
          return choice[0].to_s
        end
      end

      def kind(desc)
        return :switch if desc.start_with?("switch")
        return :item if desc.start_with?("item")
        return :move
      end

      def note(battle, idx, other_desc, real_desc)
        same = (other_desc == real_desc)
        tally[same ? :same : :different] += 1
        tally[:"#{kind(real_desc)}_by_#{ai_name}"] += 1
        tally[:"#{kind(other_desc)}_by_#{ai_name(!KIF::PowerfulAI.on?)}"] += 1
        foes = battle.battlers.select { |b| b && !b.fainted? && battle.opposes?(idx, b.index) }.map { |b| "#{b.name} #{b.hp}/#{b.totalhp}" }
        write(sprintf("turn %d  %s vs %s\n    %-7s %s\n    %-7s %s%s",
                      battle.turnCount + 1, who(battle, battle.battlers[idx]), foes.join(", "),
                      ai_name + ":", real_desc, ai_name(!KIF::PowerfulAI.on?) + ":", other_desc,
                      same ? "   (same)" : "   <- different"))
      end

      def battle_start(battle)
        @tally = Hash.new(0)
        foes = battle.opponent ? battle.opponent.map { |t| t.full_name rescue t.name }.join(" & ") : "wild"
        write("\n=== #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}  #{foes}  (in charge: #{ai_name}; also asked: #{ai_name(!KIF::PowerfulAI.on?)}) map #{$game_map ? $game_map.map_id : '-'}")
      end

      def battle_end(decision)
        t = tally
        total = t[:same] + t[:different]
        return if total == 0
        extra = t.keys.reject { |k| [:same, :different].include?(k) }.sort.map { |k| "#{k} #{t[k]}" }.join(", ")
        write(sprintf("=== end (%s): %d decisions, %d same, %d different (%d%%). %s",
                      decision.to_s, total, t[:same], t[:different], (t[:different] * 100.0 / total).round, extra))
      end
    end
  end
end

class PokeBattle_AI
  alias kif_cmp_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand unless method_defined?(:kif_cmp_pbDefaultChooseEnemyCommand)
  alias kif_cmp_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy unless method_defined?(:kif_cmp_pbDefaultChooseNewEnemy)

  def pbDefaultChooseEnemyCommand(idxBattler)
    cmp = KIF::AICompare
    return kif_cmp_pbDefaultChooseEnemyCommand(idxBattler) unless cmp.on? && !cmp.busy && defined?(KIF::PowerfulAI)
    other = nil
    seed = rand(1 << 30)
    mega = @battle.instance_variable_get(:@megaEvolution)
    mega_before = mega ? Marshal.load(Marshal.dump(mega)) : nil
    begin
      cmp.busy = true
      @battle.pbClearChoice(idxBattler)
      srand(seed)
      cmp.as_other { kif_cmp_pbDefaultChooseEnemyCommand(idxBattler) }
      other = cmp.describe(@battle, idxBattler, @battle.choices[idxBattler], mega_before)
    rescue => e
      other = "error #{e.class}: #{e.message}"
    ensure
      (@battle.pbCancelChoice(idxBattler) rescue nil)
      @battle.pbClearChoice(idxBattler)
      @battle.instance_variable_set(:@megaEvolution, mega_before) if mega_before
      cmp.busy = false
    end
    srand(seed)
    ret = kif_cmp_pbDefaultChooseEnemyCommand(idxBattler)
    begin
      cmp.note(@battle, idxBattler, other, cmp.describe(@battle, idxBattler, @battle.choices[idxBattler], mega_before))
    rescue => e
      cmp.write("compare failed: #{e.class}: #{e.message}")
    end
    return ret
  end

  def pbDefaultChooseNewEnemy(idxBattler, party)
    cmp = KIF::AICompare
    return kif_cmp_pbDefaultChooseNewEnemy(idxBattler, party) unless cmp.on? && !cmp.busy && defined?(KIF::PowerfulAI)
    seed = rand(1 << 30)
    other = begin
      cmp.busy = true
      srand(seed)
      cmp.as_other { kif_cmp_pbDefaultChooseNewEnemy(idxBattler, party) }
    rescue => e
      "error #{e.class}"
    ensure
      cmp.busy = false
    end
    srand(seed)
    ret = kif_cmp_pbDefaultChooseNewEnemy(idxBattler, party)
    begin
      name = lambda { |i| i.is_a?(Integer) && i >= 0 && party[i] ? "send out #{party[i].name}" : "send out #{i.inspect}" }
      cmp.note(@battle, idxBattler, name.call(other), name.call(ret))
    rescue => e
      cmp.write("compare failed: #{e.class}: #{e.message}")
    end
    return ret
  end
end

class PokeBattle_Battle
  alias kif_cmp_pbStartBattle pbStartBattle unless method_defined?(:kif_cmp_pbStartBattle)

  def pbStartBattle(*args)
    KIF::AICompare.battle_start(self) if KIF::AICompare.on? rescue nil
    ret = kif_cmp_pbStartBattle(*args)
    KIF::AICompare.battle_end(@decision) if KIF::AICompare.on? rescue nil
    return ret
  end
end
