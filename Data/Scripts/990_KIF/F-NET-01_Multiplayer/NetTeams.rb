#===============================================================================
# F-NET-01 – Co-op: bigger trainer teams (branch kif-teams)
# When players fight a trainer together the trainer brings extra Pokémon, so
# the fight stays fair: 2 players get twice the team, 3 players three times.
# The extra Pokémon are pre-built, one file per trainer set (Classic, Remix,
# Expert): Data/KIF/trainers_ext_<set>.dat, made once by a script (kit tools)
# and never rolled during play, so every playthrough sees the same teams. The
# file holds, per trainer, 2n extras for n base Pokémon: the first n are the
# doubled team, all 2n the tripled one. Each extra mirrors the base Pokémon at
# its slot (same level, same fused or plain, a shared type, similar BST, the
# fusions all have a custom sprite).
#
# Where it plugs in:
#   KIF::Coop.host_battle        sets the multiplier for the battle (players)
#   GameData::Trainer#to_trainer builds base + extras in one pass, so level
#                                changes, rematch levels, Shiny trainer rolls
#                                and TrainerRolls all see the extras
#   pbTrainerBattleCore wrapper  a trainer who was loaded before the battle (two
#                                trainers spotted the player) is rebuilt bigger
#   Exp                          divided by the multiplier, so a battle pays the
#                                same in total (ExpEvIvModes, co-op guest)
# Not extended: Randomizer / Legendary mode saves, Self-Battle, partner
# trainers, the Endgame Challenge, trainers that have no entry in the file.
# Setting: "Co-op: bigger trainer teams" (the Multiplayer host's counts).
#===============================================================================
KIF::Options.define(:kif_coop_teams, 1, :global)   # 0 Off, 1 On

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Co-op: bigger trainer teams"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_coop_teams },
                 proc { |value| $PokemonSystem.kif_coop_teams = value },
                 [_INTL("Fighting together: trainers have the same Pokémon as when you play alone."),
                  _INTL("Fighting together: a trainer brings more Pokémon, one extra for each of you, and the Exp is split so a battle gives the same in total. The host's setting counts.")])
}

module KIF
  module Coop
    RULES["kif_coop_teams"] = [0, 1]   # the Multiplayer host's setting is the one used in every shared battle
  end

  module Teams
    FILES = { classic: "Data/KIF/trainers_ext_classic.dat", remix: "Data/KIF/trainers_ext_remix.dat",
              expert: "Data/KIF/trainers_ext_expert.dat" }
    MAX = 3   # players in a battle (the lobby takes up to 3)

    @mult = 1
    @tables = {}
    @building = false

    class << self
      attr_reader :mult

      def on?
        return KIF::Coop.rule("kif_coop_teams") == 1
      rescue StandardError
        return false
      end

      # the block runs with the team multiplier of a shared battle: the number of
      # players in it (1 = no extension)
      def with_mult(players)
        old = @mult
        @mult = on? && players.is_a?(Integer) ? players.clamp(1, MAX) : 1
        return yield
      ensure
        @mult = old
      end

      # a trainer built under with_mult was made bigger by this much, else nil
      def team_mult(trainer)
        m = trainer.instance_variable_get(:@kif_team_mult) if trainer
        return m.is_a?(Integer) && m > 1 ? m : nil
      end

      # Gym Leader "+N Pokémon" extras (LeaderTeams) must not pile on top
      def skip_extras?(trainer)
        return @building || !team_mult(trainer).nil?
      end

      # The pre-built extras of a trainer record (the set matches the record's own
      # class, so Remix's Classic-only trainers use the Classic file), nil if none
      def table(rec)
        return table_for(mode_of(rec))
      end

      def table_for(mode)
        return @tables[mode] ||= load_file(mode)
      end

      # which data set the record came from (the loaded records are not told apart by class)
      def mode_of(rec)
        k = [rec.trainer_type, rec.real_name, rec.version]
        return :remix if GameData::TrainerModern::DATA[k].equal?(rec)
        return :expert if GameData::TrainerExpert::DATA[k].equal?(rec)
        return :classic
      end

      def load_file(mode)
        path = FILES[mode]
        return {} unless File.exist?(path)
        d = Marshal.load(File.binread(path))   # shipped game data, never from a peer
        return d.is_a?(Hash) ? d : {}
      rescue StandardError => e
        KIF.log("Co-op trainer teams: #{path} not read (#{e.class}: #{e.message})")
        return {}
      end

      def eligible?
        return false unless @mult > 1
        return false if $game_switches && $game_switches[SWITCH_RANDOM_TRAINERS]   # Randomizer and Legendary mode
        return false if defined?(KIF::SelfBattle) && KIF::SelfBattle.active
        return false if defined?(KIF.loading_partner) && KIF.loading_partner
        return false if defined?(KIF::Endgame) && KIF::Endgame.challenge_map?
        return true
      end

      # The record's Pokémon hashes with the extras mixed in, nil if it has none:
      # base 1, its twins, base 2, its twins ... so the ace pair comes last
      def merged(rec)
        return nil unless eligible?
        ex = table(rec)[[rec.trainer_type, rec.real_name, rec.version]]
        base = rec.pokemon
        n = base.length
        m = @mult
        return nil unless ex.is_a?(Array) && n > 0 && ex.length >= n * (m - 1)
        out = []
        n.times do |i|
          out << base[i]
          (m - 1).times do |s|
            e = ex[s * n + i]
            return nil unless e.is_a?(Hash) && e[:species] && e[:twin].is_a?(Integer) && base[e[:twin]]
            out << e.merge(level: base[e[:twin]][:level])
          end
        end
        return out
      end

      def build(rec)
        list = merged(rec)
        return yield unless list
        keep = rec.instance_variable_get(:@pokemon)
        @building = true
        begin
          rec.instance_variable_set(:@pokemon, list)
          trainer = yield
        ensure
          rec.instance_variable_set(:@pokemon, keep)
          @building = false
        end
        trainer.instance_variable_set(:@kif_team_mult, @mult) if trainer
        return trainer
      end

      # pbTrainerBattleCore's arguments: a trainer loaded before the battle began
      # (two trainers spotted the player; the first waits) is loaded again, now with
      # the multiplier on. Trainers made another way (customTrainerBattle, Dem and
      # Eusine) carry no roll key and stay as they are.
      def extend_waiting(args)
        return args unless @mult > 1
        return args.map do |a|
          next a unless a.is_a?(NPCTrainer) && !team_mult(a)
          k = a.instance_variable_get(:@kif_roll_key)
          next a unless k.to_s =~ /\A([^|]+)\|(.*)\|(\d+)\z/
          fresh = reload($1.to_sym, $2, $3.to_i)
          next a unless fresh && team_mult(fresh)
          fresh.lose_text = a.lose_text
          Events.onTrainerPartyLoad.trigger(nil, fresh)
          fresh
        end
      rescue StandardError => e
        KIF.log("Co-op trainer teams: waiting trainer left as is (#{e.class}: #{e.message})")
        return args
      end

      def reload(type, name, ver)
        t = pbLoadTrainer(type, name, ver)
        if !t && $game_switches[SWITCH_MODERN_MODE]   # as pbTrainerBattle does
          $game_switches[SWITCH_MODERN_MODE] = false
          begin
            t = pbLoadTrainer(type, name, ver)
          ensure
            $game_switches[SWITCH_MODERN_MODE] = true
          end
        end
        return t
      end

      # The multiplier the foe's trainer was made with (a foe the partner's game
      # pays Exp for carries it on the battler)
      def foe_mult(battle, defeated)
        m = defeated.instance_variable_get(:@kif_team_mult)
        return m if m.is_a?(Integer) && m > 1
        return 1 unless battle.trainerBattle? && battle.opponent
        t = (battle.pbGetOwnerFromBattlerIndex(defeated.index) rescue nil)
        return team_mult(t) || 1
      end

      # Exp for one defeated foe: split by the team multiplier, so the battle gives the same in total
      def exp_share(exp, battle, defeated)
        m = foe_mult(battle, defeated)
        return exp if m <= 1 || exp <= 0
        return [exp / m, 1].max
      end
    end
  end
end

module GameData
  class Trainer
    alias kif_teams_to_trainer to_trainer unless method_defined?(:kif_teams_to_trainer)

    def to_trainer
      return kif_teams_to_trainer if KIF::Teams.mult <= 1
      return KIF::Teams.build(self) { kif_teams_to_trainer }
    end
  end
end

# TrainerRolls keeps each trainer's rolls per party slot under type|name|version; an
# extended team has another slot order, so it gets its own record (|x2, |x3). Runs
# before TrainerRolls' own handler (loaded later, in ZZ_Cody).
Events.onTrainerPartyLoad += proc { |_sender, e|
  t = e.is_a?(Array) ? e[0] : e
  m = KIF::Teams.team_mult(t)
  k = t.instance_variable_get(:@kif_roll_key) if m
  t.instance_variable_set(:@kif_roll_key, "#{k}|x#{m}") if k && !k.end_with?("|x#{m}")
}
