#===============================================================================
# C-GYM-01 – Gym Leader teams (Cody)
# Cody Settings → Battles (per save file):
#   * Gym Leader teams: Normal / +1 / +2 / Full – Gym Leaders bring extra
#     Pokémon to every battle (gym, rematch or story battle).
#   * Your Pokémon in gyms: Normal / +1 / +2 / Full – raises how many Pokémon
#     you may pick before a Kanto Gym Leader battle (the picker still shows).
# Extra Pokémon, made the same way every time for a save:
#   * have the gym's type (randomized gym types count), else the leader's
#     usual type, else the type most of the team shares;
#   * are fusions about as often as the rest of the team is;
#   * are as strong as the team (base stat total near the team's average);
#   * are evolved as far as their level allows, at the team's average level;
#   * are never legendaries, Pokémon already on the team, or banned Pokémon.
# On randomized saves with random trainers, the Randomizer's Gyms page
# ("Leader team size") decides instead.
#===============================================================================
KIF::Options.define(:cody_leader_teams, 0, :save)
KIF::Options.define(:cody_gym_party, 0, :save)

KIF::Options.add(:cody_battles, :save) {
  EnumOption.new(_INTL("Gym Leader teams"), [_INTL("Normal"), _INTL("+1"), _INTL("+2"), _INTL("Full")],
                 proc { $PokemonSystem.cody_leader_teams.to_i.clamp(0, 3) },
                 proc { |v| $PokemonSystem.cody_leader_teams = v },
                 [_INTL("Gym Leaders bring their usual team."),
                  _INTL("Gym Leaders bring one more Pokémon (randomized saves: the Randomizer's Gyms page decides)."),
                  _INTL("Gym Leaders bring two more Pokémon (randomized saves: the Randomizer's Gyms page decides)."),
                  _INTL("Gym Leaders bring six Pokémon (randomized saves: the Randomizer's Gyms page decides).")])
}

KIF::Options.add(:cody_battles, :save) {
  EnumOption.new(_INTL("Your Pokémon in gyms"), [_INTL("Normal"), _INTL("+1"), _INTL("+2"), _INTL("Full")],
                 proc { $PokemonSystem.cody_gym_party.to_i.clamp(0, 3) },
                 proc { |v| $PokemonSystem.cody_gym_party = v },
                 [_INTL("Kanto Gym Leaders limit how many Pokémon you can use, as usual."),
                  _INTL("You may use one more Pokémon against Kanto Gym Leaders."),
                  _INTL("You may use two more Pokémon against Kanto Gym Leaders."),
                  _INTL("You may use your whole party against Kanto Gym Leaders.")])
}

module KIF
  module LeaderTeams
    # Index in PIF's gym type list (GYM_TYPES_ARRAY / randomized var 151)
    GYM_INDEX = {
      :LEADER_Brock => 1, :LEADER_Misty => 2, :LEADER_Surge => 3, :LEADER_Erika => 4,
      :LEADER_Koga => 5, :LEADER_Sabrina => 6, :LEADER_Blaine => 7, :LEADER_Giovanni => 8,
      :LEADER_Whitney => 10, :LEADER_Kurt => 11, :LEADER_Falkner => 12, :LEADER_Clair => 13,
      :LEADER_Morty => 14, :LEADER_Pryce => 15, :LEADER_Chuck => 16, :LEADER_Jasmine => 17
    }

    @picking = false
    class << self
      attr_accessor :picking
    end

    def self.leader?(tr_type)
      return tr_type.to_s.start_with?("LEADER_")
    end

    # How many to add to a team of n for a Normal/+1/+2/Full setting
    def self.extra_count(n, setting)
      case setting.to_i
      when 1 then return [n + 1, 6].min - n
      when 2 then return [n + 2, 6].min - n
      when 3 then return [6 - n, 0].max
      end
      return 0
    end

    def self.cody_setting
      return 0 unless $PokemonSystem && $PokemonSystem.respond_to?(:cody_leader_teams)
      return $PokemonSystem.cody_leader_teams.to_i
    end

    # Randomized saves with random trainers use the Randomizer's own setting
    def self.randomizer_decides?
      return $game_switches && $game_switches[SWITCH_RANDOM_TRAINERS] ? true : false
    end

    def self.player_max(max)
      s = ($PokemonSystem.cody_gym_party.to_i rescue 0)
      return max if s <= 0
      return 6 if s >= 3
      return [max + s, 6].min
    end

    #---------------------------------------------------------------------------
    def self.gym_type(tr_type, party)
      idx = GYM_INDEX[tr_type.to_sym]
      if idx
        arr = ($game_switches[SWITCH_RANDOMIZED_GYM_TYPES] rescue false) ? $game_variables[VAR_GYM_TYPES_ARRAY] : nil
        arr = GYM_TYPES_ARRAY unless arr.is_a?(Array) && arr[idx]
        t = arr[idx]
        t = (GameData::Type.get(t).id rescue nil) if t
        return t if t
      end
      fav = (BattledTrainer::TRAINER_CLASS_FAVORITE_TYPES[tr_type.to_sym] rescue nil)
      return fav[0] if fav.is_a?(Array) && fav[0]
      counts = Hash.new(0)
      party.each { |p| p.types.uniq.each { |t| counts[t] += 1 } }
      return counts.max_by { |_t, c| c }&.first
    end

    def self.dex(sp)
      return KIF::Rand.dex_of(sp)
    end

    def self.bst(dex)
      sp = GameData::Species.get(dex)
      return sp.base_stats.values.sum
    rescue
      return 0
    end

    def self.has_type?(dex, type)
      sp = (GameData::Species.get(dex) rescue nil)
      return false unless sp
      return sp.type1 == type || sp.type2 == type
    end

    def self.legendary?(dex)
      return is_legendary(dex) ? true : false
    rescue
      return false
    end

    def self.banned?(dex)
      return KIF::Rand.respond_to?(:species_banned?) && KIF::Rand.species_banned?(dex)
    end

    # Lowest level a base Pokémon is normally seen at (level evolutions use
    # their level; stones, trades and friendship count as a bit later)
    def self.min_level(dex)
      @min_level ||= {}
      return @min_level[dex] if @min_level.key?(dex)
      @min_level[dex] = 1
      sp = GameData::Species.get(dex)
      prevo = sp.get_previous_species
      lvl = 1
      if prevo && prevo != sp.species
        pd = dex(prevo)
        base = min_level(pd)
        evo = GameData::Species.get(prevo).get_evolutions.find { |e| e[0] == sp.species }
        if evo && evo[2].is_a?(Integer) && evo[1].to_s.start_with?("Level")
          lvl = [evo[2], base].max
        else
          lvl = [base + 12, 18].max
        end
      end
      @min_level[dex] = lvl
      return lvl
    rescue
      return 1
    end

    # The stage of the line that fits the level: down while too evolved, up
    # while an evolution is already reachable
    def self.fit_level(dex, level)
      cur = dex
      10.times do
        break if min_level(cur) <= level
        prevo = GameData::Species.get(cur).get_previous_species
        pd = dex(prevo)
        break if pd == cur || pd <= 0
        cur = pd
      end
      10.times do
        evos = GameData::Species.get(cur).get_evolutions(true).map { |e| dex(e[0]) }
        evos = evos.select { |d| d > 0 && d <= NB_POKEMON && min_level(d) <= level }
        break if evos.empty?
        cur = evos[rand(evos.length)]
      end
      return cur
    rescue
      return dex
    end

    def self.bases
      @bases ||= (1..NB_POKEMON).reject { |d| legendary?(d) }
    end

    def self.typed_bases(type)
      @typed ||= {}
      @typed[type] ||= begin
        # Any member of a line whose stages have the type
        bases.select { |d| has_type?(d, type) }
      end
    end

    def self.family_root(dex)
      cur = dex
      10.times do
        p = dex(GameData::Species.get(cur).get_previous_species) rescue cur
        break if p == cur || p <= 0
        cur = p
      end
      return cur
    end

    def self.roots_of(dex)
      return [family_root(dex)] if dex <= NB_POKEMON
      b, h = KIF::Rand.parts_of(dex)
      return [family_root(b), family_root(h)]
    end

    # One extra Pokémon (dex number) or nil
    def self.pick_one(type, level, target, fused_frac, used, used_roots)
      typed = type ? typed_bases(type).reject { |d| banned?(d) } : []
      typed = bases.reject { |d| banned?(d) } if typed.empty?
      all = bases
      tol = 0.10
      600.times do |i|
        tol += 0.03 if i > 0 && i % 40 == 0
        a = fit_level(typed[rand(typed.length)], level)
        cand = a
        if rand(1000) < (fused_frac * 1000).round   # (PIF: rand() is 0 or 1)
          b = fit_level(all[rand(all.length)], level)
          next if banned?(b)
          x, y = rand(2) == 0 ? [a, b] : [b, a]
          cand = KIF::Rand.fuse(x, y)
          cand = KIF::Rand.fuse(y, x) if type && !has_type?(cand, type)
        end
        next if type && !has_type?(cand, type)
        next if used.include?(cand) || legendary?(cand) || banned?(cand)
        next if (roots_of(cand) & used_roots).any? && i < 400
        next if target > 0 && (bst(cand) - target).abs > target * tol && i < 560
        return cand
      end
      return nil
    end

    def self.add_extras(trainer, tr_data)
      return unless trainer && leader?(trainer.trainer_type)
      party = trainer.party
      return if party.empty? || party.length >= Settings::MAX_PARTY_SIZE
      n = extra_count(party.length, cody_setting)
      return if n <= 0
      level = (party.sum { |p| p.level }.to_f / party.length).round
      target = party.sum { |p| bst(dex(p.species)) }.to_f / party.length
      fused_frac = party.count { |p| KIF::Rand.fused?(dex(p.species)) }.to_f / party.length
      type = gym_type(trainer.trainer_type, party)
      used = party.map { |p| dex(p.species) }
      used_roots = []
      pid = ($Trainer.id rescue 0)
      KIF::Rand.with_seed(:leader_extras, tr_data.id.inspect, pid) do
        n.times do
          d = pick_one(type, level, target, fused_frac, used, used_roots)
          break unless d
          used << d
          used_roots.concat(roots_of(d))
          party.push(make_pokemon(d, level, trainer))
        end
      end
    end

    # Like the rest of a trainer's team (PIF's to_trainer IVs/EVs)
    def self.make_pokemon(d, level, trainer)
      sp = getSpecies(d)
      pkmn = Pokemon.new(sp.id, level, trainer)
      GameData::Stat.each_main do |s|
        pkmn.iv[s.id] = [level / 2, Pokemon::IV_STAT_LIMIT].min
        pkmn.ev[s.id] = [level * 3 / 2, Pokemon::EV_LIMIT / 6].min
      end
      pkmn.item = pbGetRandomHeldItem.id if $game_switches[SWITCH_RANDOM_HELD_ITEMS]
      pkmn.calc_stats
      return pkmn
    end
  end
end

#-------------------------------------------------------------------------------
module GameData
  class Trainer
    alias kif_leader_to_trainer to_trainer unless method_defined?(:kif_leader_to_trainer)

    def to_trainer
      trainer = kif_leader_to_trainer
      begin
        if KIF::LeaderTeams.leader?(@trainer_type) && !KIF::LeaderTeams.randomizer_decides?
          KIF::LeaderTeams.add_extras(trainer, self)
        end
      rescue => e
        KIF.log("Gym Leader extra Pokémon failed: #{e.class}: #{e.message}")
      end
      return trainer
    end
  end
end

# "Your Pokémon in gyms": the picker before a Gym Leader battle (the event's
# script asks for PokemonSelection.choose and battles a LEADER_ further on)
class Interpreter
  alias kif_leader_execute_script execute_script unless method_defined?(:kif_leader_execute_script)

  def execute_script(script)
    if script.is_a?(String) && script.include?("PokemonSelection.choose") && kif_leader_ahead?
      KIF::LeaderTeams.picking = true
      begin
        return kif_leader_execute_script(script)
      ensure
        KIF::LeaderTeams.picking = false
      end
    end
    return kif_leader_execute_script(script)
  end

  def kif_leader_ahead?
    return false unless @list && @index
    (@list[@index..-1] || []).each do |c|
      next unless c.parameters
      c.parameters.each do |p|
        return true if p.is_a?(String) && p =~ /(PBTrainers::|:)LEADER_/
      end
    end
    return false
  end
end

module PokemonSelection
  class << self
    alias kif_leader_choose choose unless method_defined?(:kif_leader_choose)

    def choose(min = 1, max = 6, canCancel = false, acceptFainted = false, ableproc = nil, indexesVar = nil)
      max = KIF::LeaderTeams.player_max(max) if KIF::LeaderTeams.picking
      return kif_leader_choose(min, max, canCancel, acceptFainted, ableproc, indexesVar)
    end
  end
end
