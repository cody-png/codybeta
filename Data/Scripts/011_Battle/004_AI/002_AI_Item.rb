class PokeBattle_AI
  #=============================================================================
  # Decide whether the opponent should use an item on the Pokémon
  #=============================================================================
  def pbEnemyShouldUseItem?(idxBattler)
    user = @battle.battlers[idxBattler]
    item, idxTarget = pbEnemyItemToUse(idxBattler)
    return false if !item
    # Determine target of item (always the Pokémon choosing the action)
    useType = GameData::Item.get(item).battle_use
    if [1, 2, 3, 6, 7, 8].include?(useType) # Use on Pokémon
      idxTarget = @battle.battlers[idxTarget].pokemonIndex # Party Pokémon
    end
    # Register use of item
    @battle.pbRegisterItem(idxBattler, item, idxTarget)
    PBDebug.log("[AI] #{user.pbThis} (#{user.index}) will use item #{GameData::Item.get(item).name}")
    return true
  end

  # NOTE: The AI will only consider using an item on the Pokémon it's currently
  #       choosing an action for.
  def pbEnemyItemToUse(idxBattler)
    return nil if !@battle.internalBattle
    items = @battle.pbGetOwnerItems(idxBattler)
    return nil if !items || items.length == 0
    # Determine target of item (always the Pokémon choosing the action)
    idxTarget = idxBattler # Battler using the item
    battler = @battle.battlers[idxTarget]
    pkmn = battler.pokemon
    # Item categories
    hpItems = {
      :POTION => 20,
      :SUPERPOTION => 50,
      :HYPERPOTION => 200,
      :MAXPOTION => 999,
      :BERRYJUICE => 20,
      :SWEETHEART => 20,
      :FRESHWATER => 50,
      :SODAPOP => 60,
      :LEMONADE => 80,
      :MOOMOOMILK => 100,
      :ORANBERRY => 10,
      :SITRUSBERRY => battler.totalhp / 4,
      :ENERGYPOWDER => 50,
      :ENERGYROOT => 200
    }
    hpItems[:RAGECANDYBAR] = 20 if !Settings::RAGE_CANDY_BAR_CURES_STATUS_PROBLEMS
    fullRestoreItems = [
      :FULLRESTORE
    ]
    oneStatusItems = [# Preferred over items that heal all status problems
      :AWAKENING, :CHESTOBERRY, :BLUEFLUTE,
      :ANTIDOTE, :PECHABERRY,
      :BURNHEAL, :RAWSTBERRY,
      :PARALYZEHEAL, :PARLYZHEAL, :CHERIBERRY,
      :ICEHEAL, :ASPEARBERRY
    ]
    allStatusItems = [
      :FULLHEAL, :LAVACOOKIE, :OLDGATEAU, :CASTELIACONE, :LUMIOSEGALETTE,
      :SHALOURSABLE, :BIGMALASADA, :LUMBERRY, :HEALPOWDER
    ]
    allStatusItems.push(:RAGECANDYBAR) if Settings::RAGE_CANDY_BAR_CURES_STATUS_PROBLEMS
    xItems = {
      :XATTACK => [:ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XATTACK2 => [:ATTACK, 2],
      :XATTACK3 => [:ATTACK, 3],
      :XATTACK6 => [:ATTACK, 6],
      :XDEFENSE => [:DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XDEFENSE2 => [:DEFENSE, 2],
      :XDEFENSE3 => [:DEFENSE, 3],
      :XDEFENSE6 => [:DEFENSE, 6],
      :XDEFEND => [:DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XDEFEND2 => [:DEFENSE, 2],
      :XDEFEND3 => [:DEFENSE, 3],
      :XDEFEND6 => [:DEFENSE, 6],
      :XSPATK => [:SPECIAL_ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XSPATK2 => [:SPECIAL_ATTACK, 2],
      :XSPATK3 => [:SPECIAL_ATTACK, 3],
      :XSPATK6 => [:SPECIAL_ATTACK, 6],
      :XSPECIAL => [:SPECIAL_ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XSPECIAL2 => [:SPECIAL_ATTACK, 2],
      :XSPECIAL3 => [:SPECIAL_ATTACK, 3],
      :XSPECIAL6 => [:SPECIAL_ATTACK, 6],
      :XSPDEF => [:SPECIAL_DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XSPDEF2 => [:SPECIAL_DEFENSE, 2],
      :XSPDEF3 => [:SPECIAL_DEFENSE, 3],
      :XSPDEF6 => [:SPECIAL_DEFENSE, 6],
      :XSPEED => [:SPEED, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XSPEED2 => [:SPEED, 2],
      :XSPEED3 => [:SPEED, 3],
      :XSPEED6 => [:SPEED, 6],
      :XACCURACY => [:ACCURACY, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
      :XACCURACY2 => [:ACCURACY, 2],
      :XACCURACY3 => [:ACCURACY, 3],
      :XACCURACY6 => [:ACCURACY, 6]
    }
    # Determine lost HP
    losthp = battler.totalhp - battler.hp

    # Decide if Full Restore is actually preferred
    preferFullRestore = (battler.hp <= battler.totalhp / 2 &&
      (battler.status != :NONE || battler.effects[PBEffects::Confusion] > 0))

    # Find all usable items
    usableHPItems = []
    usableStatusItems = []
    usableXItems = []

    items.each do |i|
      next if !i
      next if !@battle.pbCanUseItemOnPokemon?(i, pkmn, battler, @battle.scene, false)
      next if !ItemHandlers.triggerCanUseInBattle(i, pkmn, battler, nil, false, self, @battle.scene, false)

      itemQuantity = @battle.pbGetOwnerItems(idxBattler).count(i)

      # Healing items (potions, berries, etc.)
      if hpItems[i] && losthp > 0
        priority = 5
        # Use lower priority if only 1 or 2 left
        priority += 3 if itemQuantity <= 2
        usableHPItems.push([i, priority, hpItems[i]])
        next
      end

      # Full Restore items
      if fullRestoreItems.include?(i)
        if losthp >= battler.totalhp / 4 || battler.status != :NONE || battler.effects[PBEffects::Confusion] > 0
          # Only consider Full Restore if HP is below 25% or has status/confusion
          priority = preferFullRestore ? 3 : 7
          # Raise priority if stock is low to discourage waste
          priority += 5 if itemQuantity <= 2
          usableHPItems.push([i, priority, battler.totalhp])
          usableStatusItems.push([i, preferFullRestore ? 3 : 9])
        end
        next
      end

      # Single-status curers
      if oneStatusItems.include?(i) && battler.status != :NONE
        usableStatusItems.push([i, 5])
        next
      end

      # Full heal-type items
      if allStatusItems.include?(i) && battler.status != :NONE
        usableStatusItems.push([i, 7])
        next
      end

      # Stat-raising items
      if xItems[i]
        data = xItems[i]
        usableXItems.push([i, battler.stages[data[0]], data[1]])
        next
      end
    end

    # Prioritise using HP items (including Full Restore if really needed)
    if usableHPItems.length > 0 && (battler.hp <= battler.totalhp / 4 ||
      (battler.hp <= battler.totalhp / 2 && pbAIRandom(100) < 30))
      usableHPItems.sort! { |a, b| (a[1] == b[1]) ? a[2] <=> b[2] : a[1] <=> b[1] }
      prevItem = nil
      usableHPItems.each do |i|
        return i[0], idxTarget if i[2] >= losthp
        prevItem = i
      end
      return prevItem[0], idxTarget
    end
    return nil
  end
end
