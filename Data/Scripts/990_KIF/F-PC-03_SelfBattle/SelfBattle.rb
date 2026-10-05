#===============================================================================
# F-PC-03 – Self-Battle (Reïzod, Trapstarr, DemICE)
# Source: KIF 0.20.7
#   016_UI/017_UI_PokemonStorage.rb
#     :3896-3956 createTrainer / customTrainerBattle / battlebr
#     :4088-4386 pbBattleSelected (one battle against chosen Pokémon)
#     :4870-5264 box menu "Battle" (random teams from the box, storage or the
#                ExportedPokemons folders, battle loop)
#     :3265-3283 multi-select "Battle Selected" and "Release"
#   011_Battle/003_Battle/003_Battle_StartAndEnd.rb:367-406 (no money),
#     :439-500 (no waiting at the end of a looped battle)
#   011_Battle/005_Battle scene/006_PokeBattle_Scene.rb:1-75 stat tracker
#   016_UI/015_UI_Options.rb:2880-2957 options (Self-Battle & Import)
#
# PC box menu "Battle": Battle Randomly this Box / this Box + Team / entire
#   Storage / entire Storage + Team / from ExportedPokemons. The opponent (with
#   your name) gets "Battle Size" random Pokémon from that pool; with
#   "Randomize Team" your team is also drawn from it ("Player Size"; "Randomize
#   Share" lets both sides get the same Pokémon; "Players Folder" draws your team
#   from a second ExportedPokemons folder instead).
# Multi-select "Battle Selected" (1-6 non-egg Pokémon): one battle against
#   copies of them with your team.
# Everything is a copy: no Exp, no money, nothing is lost, and your real team
#   is restored and healed afterwards (KIF healed it too). "Level" sets every
#   copy's level; "Team Select" lets you pick who fights (up to "Player Size",
#   or 6 with "Limitless Select").
# "Battle Loop" (option): box battles repeat with new random teams. Hold B
#   (Back) while a battle ends to stop. "Stat Tracker" counts wins/losses,
#   shown in battle while Auto-Battle and Battle Loop are on; folder battles
#   also append "player folder,enemy folder,result" to
#   ExportedPokemons/Data.csv.
# Multi-select "Release" is available outside Debug mode, like KIF (Cody,
#   2026-10-05; 6.8.2 limits it to Debug).
#
# 6.8.2 adaptations (see PORT_LOG):
#   * KIF toggled the loop in battle with Y; the port has no battle key for it
#     (Cody, 2026-10-05): "Battle Loop" is an option, stopped with B.
#   * Copies are made with Marshal (KIF went through its .json format).
#   * 6.8.2's "nomoney" battle rule replaces KIF's money patches; nomoneylost
#     is still set during the battle for Rocket Mode.
#   * Autosaves are skipped during a self-battle (the party is a copy then).
#   * The trainer's sprite is KIF's random trainer type 0-3 (falls back to
#     your own trainer type if one is missing).
#===============================================================================
KIF::Options.define(:sb_battlesize, 5, :save)
KIF::Options.define(:sb_randomizesize, 5, :save)
KIF::Options.define(:sb_level, 0, :save)
KIF::Options.define(:sb_randomizeteam, 0, :save)
KIF::Options.define(:sb_randomizeshare, 1, :save)
KIF::Options.define(:sb_playerfolder, 0, :save)
KIF::Options.define(:sb_select, 1, :save)
KIF::Options.define(:sb_maxing, 1, :save)
KIF::Options.define(:sb_stat_tracker, 0, :save)
KIF::Options.define(:sb_loopinput, 0, :save)
KIF::Options.define(:player_wins, 0, :save)
KIF::Options.define(:enemy_wins, 0, :save)
KIF::Options.define(:nomoneylost, 0, :save)

KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Battle Size"), (1..6).map { |i| i.to_s },
                 proc { $PokemonSystem.sb_battlesize },
                 proc { |value| $PokemonSystem.sb_battlesize = value },
                 [_INTL("1 enemy Pokemon")] + (2..6).map { |i| _INTL("{1} enemy Pokemons", i) })
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Player Size"), (1..6).map { |i| i.to_s },
                 proc { $PokemonSystem.sb_randomizesize },
                 proc { |value| $PokemonSystem.sb_randomizesize = value },
                 [_INTL("1 player Pokemon")] + (2..6).map { |i| _INTL("{1} player Pokemons", i) })
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Level"), [_INTL("Default"), "1", "5", "10", "50", "70", "100"],
                 proc { $PokemonSystem.sb_level },
                 proc { |value| $PokemonSystem.sb_level = value },
                 [_INTL("Pokemons keep their original level")] +
                 [1, 5, 10, 50, 70, 100].map { |l| _INTL("Pokemons are level {1}", l) })
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Randomize Team"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_randomizeteam },
                 proc { |value| $PokemonSystem.sb_randomizeteam = value },
                 [_INTL("Doesn't randomize your player team"),
                  _INTL("Randomize your player team as well")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Randomize Share"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_randomizeshare },
                 proc { |value| $PokemonSystem.sb_randomizeshare = value },
                 [_INTL("Doesn't allow randomize to make you share the same Pokemons"),
                  _INTL("Randomize might give you and the enemy the same Pokemons")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Players Folder"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_playerfolder },
                 proc { |value| $PokemonSystem.sb_playerfolder = value },
                 [_INTL("Does not use the Players folder to randomize the player's team."),
                  _INTL("Uses the Players Folder to randomize the player's team.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Team Select"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_select },
                 proc { |value| $PokemonSystem.sb_select = value },
                 [_INTL("Doesn't prompt you to select your team"),
                  _INTL("Let you select your team")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Limitless Select"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_maxing },
                 proc { |value| $PokemonSystem.sb_maxing = value },
                 [_INTL("You may only use the same party size"),
                  _INTL("You may perform 6v1, etc (bypass the party size)")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Battle Loop"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_loopinput },
                 proc { |value| $PokemonSystem.sb_loopinput = value },
                 [_INTL("Box Self-Battles happen once."),
                  _INTL("Box Self-Battles repeat. Hold B as a battle ends to stop.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Stat Tracker"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.sb_stat_tracker },
                 proc { |value| $PokemonSystem.sb_stat_tracker = value },
                 [_INTL("Does not display the stat tracker during AutoBattle + Battle Loop"),
                  _INTL("Shows stats such as Win/Loss tracker for Self-battle/Auto-battle")])
}

module KIF
  module SelfBattle
    LEVELS = [nil, 1, 5, 10, 50, 70, 100]
    TRAINER_TYPES = [0, 1, 2, 3]   # KIF possibletrainers
    @active = false

    class << self
      attr_reader :active
    end

    def self.opt(name)
      return $PokemonSystem.send(name).to_i
    end

    def self.loop_on?
      return opt(:sb_loopinput) == 1
    end

    def self.copy(pkmn)
      return Marshal.load(Marshal.dump(pkmn))
    rescue
      return KIF::PokeIO.from_hash(KIF::PokeIO.to_hash(pkmn))
    end

    def self.prepare(pkmn)
      c = copy(pkmn)
      return nil unless c
      lvl = LEVELS[opt(:sb_level)]
      c.level = [lvl, GameData::GrowthRate.max_level].min if lvl
      c.calc_stats
      c.heal
      return c
    end

    def self.trainer_type
      types = TRAINER_TYPES.select { |t| GameData::TrainerType.exists?(t) rescue false }
      return types.sample || $Trainer.trainer_type
    end

    # One battle. enemies: Pokémon to copy for the opponent; players: Pokémon
    # for your side (nil = your party). Returns the decision, or :cancel.
    def self.fight(enemies, players = nil, enemy_dir = nil, player_dir = nil)
      original = $Trainer.party
      foe = enemies.map { |p| prepare(p) }.compact
      team = (players || original).map { |p| prepare(p) }.compact
      return :empty if foe.none? { |p| !p.egg? } || team.none? { |p| !p.egg? }
      decision = nil
      begin
        @active = true
        $Trainer.party = team
        $Trainer.heal_party
        if opt(:sb_select) == 1
          limit = (opt(:sb_maxing) == 1) ? 6 : opt(:sb_randomizesize) + 1
          return :cancel unless PokemonSelection.choose(1, limit, true, true)
        end
        $PokemonSystem.nomoneylost = 1
        setBattleRule("noexp")
        setBattleRule("nomoney")
        setBattleRule("canLose")
        trainer = NPCTrainer.new($Trainer.name, trainer_type)
        trainer.lose_text = "..."
        trainer.party = foe
        Events.onTrainerPartyLoad.trigger(nil, trainer)
        decision = pbTrainerBattleCore(trainer)
      ensure
        PokemonSelection.restore if $PokemonGlobal.pokemonSelectionOriginalParty
        $Trainer.party = original
        $Trainer.heal_party
        $PokemonSystem.nomoneylost = 0
        @active = false
      end
      track(decision, enemy_dir, player_dir)
      return decision
    end

    # Trapstarr stat tracker
    def self.track(decision, enemy_dir, player_dir)
      return unless opt(:sb_stat_tracker) == 1
      $PokemonSystem.player_wins = opt(:player_wins) + 1 if decision == 1
      $PokemonSystem.enemy_wins = opt(:enemy_wins) + 1 if decision == 2
      if enemy_dir && player_dir
        e = enemy_dir.sub(/^#{KIF::PokeIO::FOLDER}\//, "")
        p = player_dir.sub(/^#{KIF::PokeIO::FOLDER}\//, "")
        File.open("#{KIF::PokeIO::FOLDER}/Data.csv", "a") { |f| f.write("#{p},#{e},#{decision}\n") }
      end
    rescue => e
      KIF.log("Stat tracker failed: #{e.message}")
    end

    def self.reset_tracker
      $PokemonSystem.player_wins = 0
      $PokemonSystem.enemy_wins = 0
    end

    def self.load_pool(list)
      return list.map { |x| x.is_a?(String) ? KIF::PokeIO.read_file(x) : x }.compact
    end

    # KIF re-picks a random folder (with .json files) under the chosen root
    def self.random_dir(root, exclude = nil)
      dirs = KIF::PokeIO.dirs_with_jsons(root)
      dirs.delete(exclude) if exclude && dirs.length > 1
      return dirs.sample
    end

    #---------------------------------------------------------------------------
    # Multi-select "Battle Selected"
    #---------------------------------------------------------------------------
    def self.battle_selected(screen, box)
      storage = screen.storage
      enemies = screen.getMultiSelection(box, nil).map { |i| storage[box, i] }.compact
      enemies = enemies.reject { |p| p.egg? }
      return if enemies.empty? || enemies.length > 6
      players = nil
      if opt(:sb_playerfolder) == 1 && opt(:sb_randomizeteam) == 1
        nav = KIF::PokeIO.navigate(screen, "Choose Player Sub-Directory.")
        return if nav.nil?
        pool = nav[:files].dup
        if pool.empty?
          pbPlayBuzzerSE
          screen.pbDisplay(_INTL("No Players Battler to Import!"))
          return
        end
        n = opt(:sb_randomizesize) + 1
        if pool.length < n
          n = pool.length
          screen.pbDisplay(_INTL("Battling with only {1} Pokemon(s) (Player)", n))
        end
        players = load_pool(pool.sample(n))
      end
      result = fight(enemies, players)
      if result == :empty
        pbPlayBuzzerSE
        screen.pbDisplay(_INTL("One of the team is empty!"))
      end
      screen.pbHardRefresh
    end

    #---------------------------------------------------------------------------
    # Box menu "Battle"
    #---------------------------------------------------------------------------
    def self.box_battle(screen)
      storage = screen.storage
      enemy_n = opt(:sb_battlesize) + 1
      player_n = opt(:sb_randomizesize) + 1
      randteam = opt(:sb_randomizeteam) == 1
      share = opt(:sb_randomizeshare) == 1
      playerfolder = opt(:sb_playerfolder) == 1
      cmds = [_INTL("Battle Randomly this Box"), _INTL("Battle Randomly this Box + Team"),
              _INTL("Battle Randomly entire Storage"), _INTL("Battle Randomly entire Storage + Team"),
              _INTL("Battle from ExportedPokemons"), _INTL("Nevermind")]
      choice = screen.pbShowCommands(_INTL("Battle system"), cmds)
      return if choice < 0 || choice > 4
      base_pool = []
      enemy_nav = nil
      if choice == 4
        enemy_nav = KIF::PokeIO.navigate(screen, "Choose Battler Sub-Directory.")
        return if enemy_nav.nil?
        if enemy_nav[:files].empty?
          pbPlayBuzzerSE
          screen.pbDisplay(_INTL("No Enemies Battler to Import!"))
          return
        end
        base_pool = enemy_nav[:files]
      else
        base_pool.concat($Trainer.party.compact) if choice == 1 || choice == 3
        boxes = (choice <= 1) ? [storage.currentBox] : (0...storage.maxBoxes).to_a
        boxes.each do |b|
          next if storage[b].is_a?(StorageTransferBox)
          storage.maxPokemon(b).times { |i| base_pool << storage[b, i] if storage[b, i] }
        end
        base_pool.reject! { |p| p.egg? }
      end
      enemy_dir = enemy_nav ? enemy_nav[:dir] : nil
      player_nav = nil
      player_dir = nil
      first = true
      loop do
        pool = base_pool.dup
        if !first && enemy_nav && enemy_nav[:random_root]
          enemy_dir = random_dir(enemy_nav[:random_root])
          if enemy_dir.nil?
            screen.pbDisplay(_INTL("Gave up after 50 tries on Battler folder!"))
            break
          end
          pool = KIF::PokeIO.jsons_in(enemy_dir, false)
        end
        # Player pool
        if playerfolder
          if first
            player_nav = KIF::PokeIO.navigate(screen, "Choose Player Sub-Directory.")
            return if player_nav.nil?
            player_dir = player_nav[:dir]
            if player_nav[:random_root] && !share && player_dir == enemy_dir
              player_dir = random_dir(player_nav[:random_root], enemy_dir)
            end
          elsif player_nav[:random_root]
            player_dir = random_dir(player_nav[:random_root], share ? nil : enemy_dir)
            if player_dir.nil?
              screen.pbDisplay(_INTL("Gave up after 50 tries on Player folder!"))
              break
            end
          end
          player_pool = (player_nav[:random_root] && player_dir) ? KIF::PokeIO.jsons_in(player_dir, false) : player_nav[:files].dup
          if player_pool.empty?
            pbPlayBuzzerSE
            screen.pbDisplay(_INTL("No Players Battler to Import! Using Battlers instead."))
            player_pool = pool.dup
            playerfolder = false
          end
        else
          player_pool = pool.dup
        end
        first = false
        if pool.empty?
          pbPlayBuzzerSE
          screen.pbDisplay(_INTL("No Battler to Fight!"))
          break
        end
        e_n = enemy_n
        p_n = player_n
        needing = (randteam && !share && !playerfolder) ? e_n + p_n : e_n
        if randteam && !share && pool.length < 2
          pbPlayBuzzerSE
          screen.pbDisplay(_INTL("No Battler to Fight!"))
          break
        end
        if pool.length < needing
          e_n = p_n = share ? pool.length : pool.length / 2
          screen.pbDisplay(_INTL("Battling with only {1} Pokemon(s)", e_n))
        end
        if randteam && player_pool.length < p_n
          p_n = player_pool.length
          screen.pbDisplay(_INTL("Battling with only {1} Pokemon(s) (Player)", p_n))
        end
        picked = pool.sample(e_n)
        player_pool -= picked unless share || playerfolder
        enemies = load_pool(picked)
        players = randteam ? load_pool(player_pool.sample(p_n)) : nil
        result = fight(enemies, players, enemy_nav ? enemy_dir : nil, playerfolder ? player_dir : nil)
        if result == :empty
          pbPlayBuzzerSE
          screen.pbDisplay(_INTL("One of the team is empty!"))
          break
        end
        break if result == :cancel
        Input.update
        if !loop_on? || Input.press?(Input::BACK)
          reset_tracker if loop_on?
          break
        end
      end
      screen.pbHardRefresh
    end
  end
end

# No autosave while the party is a self-battle copy
module Kernel
  class << self
    alias kif_sb_tryAutosave tryAutosave unless method_defined?(:kif_sb_tryAutosave)

    def tryAutosave(*args)
      return if KIF::SelfBattle.active
      return kif_sb_tryAutosave(*args)
    end
  end
end

# Stat tracker in battle (Trapstarr)
class PokeBattle_Scene
  alias kif_sb_pbUpdate pbUpdate unless method_defined?(:kif_sb_pbUpdate)
  alias kif_sb_pbEndBattle pbEndBattle unless method_defined?(:kif_sb_pbEndBattle)

  def kif_show_stat_tracker?
    return false unless $PokemonSystem
    return $PokemonSystem.sb_stat_tracker.to_i == 1 && $PokemonSystem.sb_loopinput.to_i == 1 &&
           $PokemonSystem.respond_to?(:autobattler) && $PokemonSystem.autobattler.to_i != 0
  end

  def kif_update_win_display
    if kif_show_stat_tracker? && @viewport
      if @kif_win_display.nil? || @kif_win_display.disposed?
        @kif_win_display = Sprite.new(@viewport)
        @kif_win_display.bitmap = Bitmap.new(Graphics.width, 24)
        @kif_win_display.z = 9999
        @kif_win_display.y = Graphics.height - 96
      end
      text = "[ Player: #{$PokemonSystem.player_wins} | Enemy: #{$PokemonSystem.enemy_wins} ]"
      return if @kif_win_text == text
      @kif_win_text = text
      bmp = @kif_win_display.bitmap
      bmp.clear
      # KIF: lighter text with dark mode on
      dark = defined?(KIF::BattleUI) ? KIF::BattleUI.dark? : false
      bmp.font.color = dark ? Color.new(225, 225, 225) : Color.new(40, 40, 44)
      bmp.draw_text(bmp.rect, text, 1)
    elsif @kif_win_display
      @kif_win_display.bitmap.dispose if @kif_win_display.bitmap
      @kif_win_display.dispose
      @kif_win_display = nil
      @kif_win_text = nil
    end
  rescue
    nil
  end

  def pbUpdate(*args)
    kif_sb_pbUpdate(*args)
    kif_update_win_display
  end

  def pbEndBattle(*args)
    if @kif_win_display
      @kif_win_display.bitmap.dispose if @kif_win_display.bitmap
      @kif_win_display.dispose unless @kif_win_display.disposed?
      @kif_win_display = nil
    end
    return kif_sb_pbEndBattle(*args)
  end
end

#-------------------------------------------------------------------------------
# Menus
#-------------------------------------------------------------------------------
KIF::BoxCommands.add(:battle, proc { |_s| _INTL("Battle") },
  proc { |s| KIF::SelfBattle.box_battle(s) }, order: 60)

KIF::MultiCommands.add(:release, proc { |_s, _b| $DEBUG ? nil : _INTL("Release") },
  proc { |s, box| s.pbReleaseMulti(box) }, order: 5)
KIF::MultiCommands.add(:battle_selected,
  proc { |s, box|
    n = s.getMultiSelection(box, nil).count { |i| s.storage[box, i] && !s.storage[box, i].egg? }
    (n > 0 && n < 7) ? _INTL("Battle Selected") : nil
  },
  proc { |s, box| KIF::SelfBattle.battle_selected(s, box) }, order: 10)
