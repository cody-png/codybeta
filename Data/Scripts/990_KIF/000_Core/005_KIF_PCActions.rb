#===============================================================================
# KIF "Kuray Actions" PC submenu (F-PC-01 part)
# Source: KIF 0.20.7 016_UI/017_UI_PokemonStorage.rb:1818-1920 (pbKurayAct)
#         and :3383 (menu entry "Kuray Actions" after "Release")
#
# PIF 6.8.2 builds the Pokémon menu inside PokemonStorageScreen#
# organizeActions. While that method runs, the list it shows is recognised in
# pbShowCommands and "Kuray Actions" is inserted after "Release". Picking it
# opens the KIF submenu; the base method then sees "Cancel".
#
#   KIF::PCActions.add(:id, proc { |pkmn| label or nil },
#                      proc { |screen, pkmn, selected, heldpoke| ... })
# Actions appear in registration order; a nil label hides the action.
#===============================================================================
module KIF
  # Methods used by action handlers; mixed into every host (PC screen, party
  # menu). Features add their helpers here.
  module PCActionMethods
  end

  module PCActions
    Action = Struct.new(:id, :label, :handler)
    @actions = []

    def self.add(id, label, handler)
      @actions.reject! { |a| a.id == id }
      @actions << Action.new(id, label, handler)
    end

    def self.available(pkmn)
      acts = @actions.select { |a| !defined?(KIF::Modules) || KIF::Modules.proc_active?(a.handler) }
      return acts.map { |a| [a, (a.label.call(pkmn) rescue nil)] }.select { |_, l| l }
    end

    # Money helper used by several actions (KIF "Streamer's Dream" makes
    # everything free; that option comes with the Kuray Shop).
    def self.price(base)
      return 0 if $PokemonSystem.respond_to?(:kuraystreamerdream) && $PokemonSystem.kuraystreamerdream.to_i != 0
      return base
    end
  end
end

#===============================================================================
# KIF box menu entries (F-PC-01/02/03). KIF 017_UI_PokemonStorage.rb:4783-4830
# listed them after "Name": Lock Sorting, Lock Exporting, Buy Box, Sort,
# Sort (all Boxes), Battle, Export this Box, Export All, Import, Import
# Randomly. 6.8.2's pbBoxCommands keeps its list local, so while it runs the
# entries are inserted before "Cancel" and the base method then sees "Cancel".
#
#   KIF::BoxCommands.add(:id, proc { |screen| label or nil },
#                        proc { |screen| ... }, order: n)
#===============================================================================
module KIF
  module BoxCommands
    Command = Struct.new(:id, :label, :handler, :order, :index)
    @commands = []

    def self.add(id, label, handler, order: 100)
      @commands.reject! { |c| c.id == id }
      @commands << Command.new(id, label, handler, order, @commands.length)
    end

    def self.available(screen)
      list = @commands.select { |c| !defined?(KIF::Modules) || KIF::Modules.proc_active?(c.handler) }.sort_by { |c| [c.order, c.index] }
      return list.map { |c| [c, (c.label.call(screen) rescue nil)] }.select { |_, l| l }
    end
  end
end

#===============================================================================
# KIF multi-select entries (KIF 017_UI_PokemonStorage.rb:3265-3290: "Battle
# Selected", "Export"). Inserted before "Cancel" in 6.8.2's
# multipleSelectedPokemonCommands list ("Selected {1} Pokémon.").
#   KIF::MultiCommands.add(:id, proc { |screen, box| label or nil },
#                          proc { |screen, box| ... }, order: n)
#===============================================================================
module KIF
  module MultiCommands
    Command = Struct.new(:id, :label, :handler, :order, :index)
    @commands = []

    def self.add(id, label, handler, order: 100)
      @commands.reject! { |c| c.id == id }
      @commands << Command.new(id, label, handler, order, @commands.length)
    end

    def self.available(screen, box)
      list = @commands.select { |c| !defined?(KIF::Modules) || KIF::Modules.proc_active?(c.handler) }.sort_by { |c| [c.order, c.index] }
      return list.map { |c| [c, (c.label.call(screen, box) rescue nil)] }.select { |_, l| l }
    end
  end
end

class PokemonStorageScreen
  include KIF::PCActionMethods

  alias kif_pc_organizeActions organizeActions unless method_defined?(:kif_pc_organizeActions)

  def organizeActions(selected, pokemon, heldpoke, isTransferBox)
    @kif_organize = [selected, pokemon, heldpoke, isTransferBox]
    begin
      return kif_pc_organizeActions(selected, pokemon, heldpoke, isTransferBox)
    ensure
      @kif_organize = nil
    end
  end

  alias kif_pc_pbShowCommands pbShowCommands unless method_defined?(:kif_pc_pbShowCommands)

  alias kif_box_pbBoxCommands pbBoxCommands unless method_defined?(:kif_box_pbBoxCommands)

  def pbBoxCommands(*args)
    @kif_boxcmd = true
    begin
      return kif_box_pbBoxCommands(*args)
    ensure
      @kif_boxcmd = false
    end
  end

  if method_defined?(:multipleSelectedPokemonCommands)
    alias kif_multi_cmds multipleSelectedPokemonCommands unless method_defined?(:kif_multi_cmds)

    def multipleSelectedPokemonCommands(selected, *args)
      @kif_multicmd = selected
      begin
        return kif_multi_cmds(selected, *args)
      ensure
        @kif_multicmd = nil
      end
    end
  end

  def pbShowCommands(msg, commands, index = 0)
    if @kif_multicmd
      selected = @kif_multicmd
      @kif_multicmd = nil
      return kif_multi_menu(msg, commands, index, selected[0])
    end
    if @kif_boxcmd
      @kif_boxcmd = false   # only the box menu itself
      return kif_box_menu(msg, commands, index)
    end
    ctx = @kif_organize
    return kif_pc_pbShowCommands(msg, commands, index) unless ctx
    @kif_organize = nil   # only the first (organize) menu
    selected, pokemon, heldpoke, isTransferBox = ctx
    pkmn = heldpoke || pokemon
    release_idx = commands.index(_INTL("Release"))
    cancel_idx = commands.index(_INTL("Cancel"))
    return kif_pc_pbShowCommands(msg, commands, index) if !pkmn || isTransferBox || !release_idx || !cancel_idx
    return kif_pc_pbShowCommands(msg, commands, index) if KIF::PCActions.available(pkmn).empty?
    shown = commands.dup
    pos = release_idx + 1
    shown.insert(pos, _INTL("Kuray Actions"))
    ret = kif_pc_pbShowCommands(msg, shown, index)
    if ret == pos
      kif_kuray_actions(selected, pkmn, heldpoke)
      return cancel_idx
    end
    return ret > pos ? ret - 1 : ret
  end

  def kif_box_menu(msg, commands, index)
    cancel_idx = commands.length - 1
    if msg != _INTL("What do you want to do?") || commands[cancel_idx] != _INTL("Cancel") ||
       @storage[@storage.currentBox].is_a?(StorageTransferBox)
      return kif_pc_pbShowCommands(msg, commands, index)
    end
    list = KIF::BoxCommands.available(self)
    return kif_pc_pbShowCommands(msg, commands, index) if list.empty?
    shown = commands[0...cancel_idx] + list.map { |_, l| l } + [commands[cancel_idx]]
    ret = kif_pc_pbShowCommands(msg, shown, index)
    return ret if ret < cancel_idx
    k = ret - cancel_idx
    list[k][0].handler.call(self) if k < list.length
    return cancel_idx
  end

  def kif_multi_menu(msg, commands, index, box)
    cancel_idx = commands.length - 1
    return kif_pc_pbShowCommands(msg, commands, index) if commands[cancel_idx] != _INTL("Cancel")
    list = KIF::MultiCommands.available(self, box)
    return kif_pc_pbShowCommands(msg, commands, index) if list.empty?
    shown = commands[0...cancel_idx] + list.map { |_, l| l } + [commands[cancel_idx]]
    ret = kif_pc_pbShowCommands(msg, shown, index)
    return ret if ret < cancel_idx
    k = ret - cancel_idx
    list[k][0].handler.call(self, box) if k < list.length
    return cancel_idx
  end

  def kif_kuray_actions(selected, pkmn, heldpoke)
    list = KIF::PCActions.available(pkmn)
    labels = list.map { |_, l| l } + [_INTL("Cancel")]
    cmd = kif_pc_pbShowCommands(_INTL("{1} is selected.", pkmn.name), labels)
    return if cmd < 0 || cmd >= list.length
    list[cmd][0].handler.call(self, pkmn, selected, heldpoke)
  end

  # KIF pbKurayRefresh: redraw the selected Pokémon and the whole box.
  def kif_refresh(selected)
    @scene.pbUpdateOverlay(selected[1], (selected[0] == -1) ? @storage.party : nil) rescue nil
    @scene.pbHardRefresh rescue nil
  end
end

#===============================================================================
# The same "Kuray Actions" in the party menu (Cody, 2026-10-05).
# PokemonPartyScreen#pbPokemonScreen is one long method, so the entry is
# inserted before "Cancel" when the scene shows the "Do what with X?" list.
# Picking it runs the actions and hands the base method "Cancel", which just
# returns to Pokémon selection.
#===============================================================================
module KIF
  class PartyActionHost
    include KIF::PCActionMethods

    def initialize(scene, index)
      @scene = scene
      @index = index
    end

    def pbDisplay(text)
      @scene.pbDisplay(text)
    end

    def pbConfirm(text)
      return @scene.pbDisplayConfirm(text)
    end

    def pbShowCommands(msg, commands, index = 0)
      return @scene.kif_party_raw_commands(msg, commands, index)
    end

    def kif_refresh(_selected)
      @scene.pbHardRefresh rescue (@scene.pbRefresh rescue nil)
    end

    def run(pkmn)
      list = KIF::PCActions.available(pkmn)
      labels = list.map { |_, l| l } + [_INTL("Cancel")]
      cmd = pbShowCommands(_INTL("Do what with {1}?", pkmn.name), labels)
      return if cmd < 0 || cmd >= list.length
      list[cmd][0].handler.call(self, pkmn, [-1, @index], nil)
    end
  end
end

#-------------------------------------------------------------------------------
# Party menus copied from older game versions (mods round 2, 2026-10-10)
#   Some mods replace PokemonPartyScreen#pbPokemonScreen with an older copy
#   of the party menu (GhostNPC Buddy), which has no "Evolve!", "Change
#   moves", "Fuse" or "Unfuse". When the "Do what with X?" list lacks one
#   that PIF 6.8.2 would show for that Pokémon, it is added back before
#   "Cancel" and runs PIF's own handler. The vanilla menu always has them,
#   so nothing changes without such a mod.
#-------------------------------------------------------------------------------
module KIF
  module PartyMenuCompat
    def self.missing(pkmn, commands)
      out = []
      evolve = _INTL("Evolve!")
      if !commands.include?(evolve) && pkmn.respond_to?(:evolve_from_party) && pkmn.evolve_from_party &&
         (!defined?(pokemonAllowedToEvolve) || pokemonAllowedToEvolve(pkmn))
        out << [:evolve, evolve]
      end
      moves = _INTL("Change moves")
      out << [:moves, moves] if !pkmn.egg? && !commands.include?(moves)
      if defined?(playerHasFusionItems) && playerHasFusionItems
        if pkmn.isFusion?
          out << [:unfuse, _INTL("Unfuse")] unless commands.include?(_INTL("Unfuse"))
        else
          out << [:fuse, _INTL("Fuse")] unless commands.include?(_INTL("Fuse"))
        end
      end
      return out
    rescue StandardError
      return []
    end

    def self.run(screen, kind, pkmn, idx)
      case kind
      when :evolve then screen.evolvePokemon(pkmn)
      when :moves  then screen.pbRememberMoves(pkmn)
      when :fuse   then screen.fuseFromParty(pkmn, idx)
      when :unfuse then screen.unfuseFromParty(pkmn, idx)
      end
      screen.pbRefresh rescue nil
    end

    module ScreenHook
      def pbPokemonScreen(*args)
        @scene.instance_variable_set(:@kif_party_screen, self) if @scene
        super
      end
    end
  end
end
PokemonPartyScreen.prepend(KIF::PartyMenuCompat::ScreenHook)

class PokemonParty_Scene
  alias kif_party_pbChoosePokemon pbChoosePokemon unless method_defined?(:kif_party_pbChoosePokemon)

  def pbChoosePokemon(*args)
    ret = kif_party_pbChoosePokemon(*args)
    @kif_last_choice = ret.is_a?(Array) ? ret[1] : ret
    return ret
  end

  alias kif_party_raw_commands pbShowCommands unless method_defined?(:kif_party_raw_commands)

  def pbShowCommands(helptext, commands, index = 0)
    # a mod may replace pbChoosePokemon (Mouse UI): fall back to the cursor
    idx = @kif_last_choice.is_a?(Integer) ? @kif_last_choice : @activecmd
    pkmn = (idx.is_a?(Integer) && idx >= 0 && @party) ? @party[idx] : nil
    cancel = _INTL("Cancel")
    if pkmn.nil? || commands.last != cancel || !commands.include?(_INTL("Summary")) ||
       helptext != _INTL("Do what with {1}?", pkmn.name)
      return kif_party_raw_commands(helptext, commands, index)
    end
    extras = @kif_party_screen ? KIF::PartyMenuCompat.missing(pkmn, commands) : []
    # field party menu only (the battle party list has the same header)
    kuray = !($game_temp && $game_temp.in_battle) && !KIF::PCActions.available(pkmn).empty?
    return kif_party_raw_commands(helptext, commands, index) if extras.empty? && !kuray
    pos = commands.length - 1
    added = extras.map { |_, label| label }
    added << _INTL("Kuray Actions") if kuray
    shown = commands[0...pos] + added + [cancel]
    ret = kif_party_raw_commands(helptext, shown, index)
    return ret if ret < pos
    if ret < pos + extras.length
      KIF::PartyMenuCompat.run(@kif_party_screen, extras[ret - pos][0], pkmn, idx)
      return pos   # "Cancel" in the base list
    end
    if kuray && ret == pos + extras.length
      KIF::PartyActionHost.new(self, idx).run(pkmn)
      pbRefresh rescue nil
      return pos   # "Cancel" in the base list
    end
    return pos     # "Cancel"
  end
end
