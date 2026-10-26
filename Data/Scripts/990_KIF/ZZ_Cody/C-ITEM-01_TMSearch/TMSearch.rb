#===============================================================================
# C-ITEM-01 – TM compatibility search (new in KIF 1.2.6, 2026-10-26)
# A player (Discord #help): which Pokémon can learn each TM? PIF adds TMs for
# moves that are no TMs in the main games (Spore: TM102), so outside sites
# can't answer it. Players also didn't know TMs aren't used up in PIF.
#
# Bag > a TM or HM > "Who can learn": every species that can learn its move
# (base species, Pokédex order), with your party and PC Pokémon that can
# learn it listed first. The first row switches Show: All / Seen / Caught.
# "Search TMs" (same menu) lists every TM and HM in the game by move name,
# also ones you don't have, and opens the same list.
#
# The check is PIF's own: Pokemon#pokemon_can_learn_move (014_Pokemon/
# 001_Pokemon.rb: TutorMoves, level-up moves or egg moves), the one TM use
# makes through compatible_with_move?. A fusion can learn a move if its head
# or its body can (compatible_with_move?), so owned fusions are checked with
# compatible_with_move? itself. Learner lists are cached per move until the
# species data changes (KIF::Perf.token: data load, Randomizer, species
# tweaks) or the player walks onto or off Pinkan Island (the Randomizer lets
# Pokémon learn their original moves there).
#
# Hooks: PokemonBag_Scene#pbChooseItem remembers the chosen item;
# #pbShowCommands adds the two rows to that item's menu (the call whose text
# is "<item> is selected.", only made by PokemonBagScreen#pbStartScreen) and
# runs them; the Bag then gets -1, which does nothing.
#===============================================================================
module KIF
  module TMSearch
    FILTERS = ["All", "Seen", "Caught"]
    @cache = {}

    module_function

    def cache_key
      return [KIF::Perf.token, (defined?(KIF::Rand) && KIF::Rand.respond_to?(:pinkan?) && KIF::Rand.pinkan?) ? true : false]
    end

    # Base species ids that can learn the move, in Pokédex order
    def learners(move)
      key = cache_key
      @cache = {} if @cache_key != key
      @cache_key = key
      return @cache[move] ||= begin
        md = GameData::Move.get(move)
        chk = Pokemon.allocate   # pokemon_can_learn_move reads only its arguments
        (1..NB_POKEMON).map { |n| GameData::Species.try_get(n) }.compact.uniq
          .select { |sp| chk.pokemon_can_learn_move(sp, md) }.map { |sp| sp.species }
      end
    end

    # [[place, Pokémon]]: party first, then the PC boxes
    def owned(move)
      ret = []
      ($Trainer ? $Trainer.party : []).each { |pk| ret << [_INTL("Party"), pk] if teachable?(pk, move) }
      st = $PokemonStorage
      (st ? st.maxBoxes : 0).times do |b|
        box = st[b]
        st.maxPokemon(b).times { |i| pk = st[b, i]; ret << [box.name, pk] if teachable?(pk, move) }
      end
      return ret
    end

    def teachable?(pk, move)
      return false if !pk || pk.egg?
      return (pk.compatible_with_move?(move) rescue false) ? true : false
    end

    def shown(list, filter)
      dex = $Trainer && $Trainer.pokedex
      return list if filter == 0 || !dex
      return list.select { |s| filter == 1 ? dex.seen?(s) : dex.owned?(s) }
    end

    # Every TM / HM / TR in the game, by move name (TM00 is PIF's unused dummy)
    def machines
      ret = []
      GameData::Item.each { |i| ret << i if i.is_machine? && i.move && i.move != :FAKEMOVE && GameData::Move.exists?(i.move) }
      return ret.sort_by { |i| [GameData::Move.get(i.move).name, i.id_number] }
    end

    def title(item)
      return _INTL("{1} {2}", item.name, GameData::Move.get(item.move).name)
    end

    def rows(item, filter, owned, list)
      ret = [_INTL("Show: {1}   ({2}: change)", _INTL(FILTERS[filter]), KIF::Keys.name(Input::USE))]
      owned.each do |place, pk|
        sp = pk.speciesName
        ret << ((pk.name == sp) ? _INTL("{1}: {2}", place, sp) : _INTL("{1}: {2} ({3})", place, pk.name, sp))
      end
      list.each { |s| sp = GameData::Species.get(s); ret << sprintf("%03d %s", sp.id_number, sp.name) }
      ret << _INTL("No Pokémon to show.") if ret.length == 1
      return ret
    end

    def head_text(item, filter, all, list)
      t = _INTL("{1}: {2} Pokémon can learn it.", title(item), all.length)
      t = _INTL("{1}: {2} can learn it, {3} seen.", title(item), all.length, list.length) if filter == 1
      t = _INTL("{1}: {2} can learn it, {3} caught.", title(item), all.length, list.length) if filter == 2
      return t
    end

    def foot_text(item)
      used = item.is_TR? ? _INTL("A TR is used up when it is taught.") : _INTL("TMs are not used up: you can teach them again.")
      return used + "\n" + _INTL("A fusion can learn it if its head or body can.")
    end

    # The load screen's background, so the Bag doesn't show through the windows
    def backdrop(vp)
      bg = IconSprite.new(0, 0, vp)
      bg.setBitmap("Graphics/Pictures/loadbg")
      return bg
    end

    # The list screen; z keeps it above the Bag (and the TM list that opened it)
    def show(item, z = 100_001)
      item = GameData::Item.get(item)
      all = learners(item.move)
      owned = owned(item.move)
      filter = 0
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = z
      bg = backdrop(vp)
      foot = Window_UnformattedTextPokemon.newWithSize(foot_text(item), 0, Graphics.height - 96, Graphics.width, 96, vp)
      head = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, vp)
      win = Window_CommandPokemon.newWithSize([""], 0, 64, Graphics.width, Graphics.height - 160, vp)
      win.setAllowArrowsJump(true)   # Left / Right: a page
      refresh = proc do
        list = shown(all, filter)
        head.text = head_text(item, filter, all, list)
        win.commands = rows(item, filter, owned, list)
      end
      refresh.call
      win.index = 0
      loop do
        Graphics.update
        Input.update
        win.update
        if Input.trigger?(Input::BACK)
          pbPlayCancelSE
          break
        elsif Input.trigger?(Input::USE) && win.index == 0
          pbPlayDecisionSE
          filter = (filter + 1) % FILTERS.length
          refresh.call
          win.index = 0
        end
      end
      KIF.log("TM search: #{item.id} (#{all.length} learners, #{owned.length} owned)")
    ensure
      win.dispose if win
      head.dispose if head
      foot.dispose if foot
      bg.dispose if bg
      vp.dispose if vp
      eat_input
    end

    # Every TM by move name; USE opens its list
    def search
      items = machines
      return pbMessage(_INTL("There are no TMs.")) if items.empty?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 100_000
      bg = backdrop(vp)
      head = Window_UnformattedTextPokemon.newWithSize(_INTL("Choose a TM to see who can learn it."), 0, 0, Graphics.width, 64, vp)
      win = Window_CommandPokemon.newWithSize(items.map { |i| _INTL("{1} ({2})", GameData::Move.get(i.move).name, i.name) },
                                              0, 64, Graphics.width, Graphics.height - 64, vp)
      win.setAllowArrowsJump(true)
      win.index = 0
      loop do
        Graphics.update
        Input.update
        win.update
        if Input.trigger?(Input::BACK)
          pbPlayCancelSE
          break
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          show(items[win.index])
        end
      end
    ensure
      win.dispose if win
      head.dispose if head
      bg.dispose if bg
      vp.dispose if vp
      eat_input
    end

    # The Bag reads the same frame's Back press: one more update drops it
    def eat_input
      Graphics.update
      Input.update
    end
  end
end

class PokemonBag_Scene
  alias kif_tms_choose_item pbChooseItem unless method_defined?(:kif_tms_choose_item)

  def pbChooseItem(*args)
    @kif_tms_item = nil
    ret = kif_tms_choose_item(*args)
    @kif_tms_item = ret
    return ret
  end

  alias kif_tms_show_commands pbShowCommands unless method_defined?(:kif_tms_show_commands)

  def pbShowCommands(helptext, commands, index = 0)
    item = @kif_tms_item
    @kif_tms_item = nil   # only the item's own menu, not the ones it opens
    itm = item && (GameData::Item.try_get(item) rescue nil)
    if !itm || !itm.is_machine? || !itm.move || helptext != _INTL("{1} is selected.", itm.name) || commands.length < 1
      return kif_tms_show_commands(helptext, commands, index)
    end
    at = commands.length - 1   # before Cancel
    cmds = commands[0...at] + [_INTL("Who can learn"), _INTL("Search TMs")] + commands[at..-1]
    ret = kif_tms_show_commands(helptext, cmds, index)
    case ret
    when at     then KIF::TMSearch.show(itm.id)
    when at + 1 then KIF::TMSearch.search
    else return (ret > at + 1) ? ret - 2 : ret
    end
    return -1
  end
end
