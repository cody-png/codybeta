
# This allows to obtain the next move in battles by a third party instead of relying on the internal game AI.
# The game sends information about the current state of a battle and expects a move in return.
#
# To use, you need the PIF_RemoteBattlerServer script (or custom equivalent) running at the address in Settings::REMOTE_BATTLE_CONTROL_SERVER_URL (localhost by default)
# and to set Settings::REMOTE_BATTLES_CONTROL to true.
#
# PIF_RemoteBattlerServer can be set in either AI mode or HUMAN mode (manual selection)
class RemotePokeBattle_AI < PokeBattle_AI
  def initialize(battle)
    super
  end

  def pbChooseMoves(idxBattler)
    current_battler = @battle.battlers[idxBattler]
    ally_battlers, enemy_battlers = get_battlers_by_side(current_battler)

    echoln "ally_battlers: #{ally_battlers}, enemy_battler: #{enemy_battlers}"

    state_params = serialize_battle_state_to_params(current_battler, ally_battlers, enemy_battlers)
    safe_params  = convert_to_json_safe(state_params)
    json_data    = JSON.generate(safe_params)

    response = pbPostToString(Settings::REMOTE_BATTLE_CONTROL_SERVER_URL, { "battle_state" => json_data })
    response = clean_json_string(response)

    available_moves = current_battler.moves.map { |m| m.id.to_s.upcase }
    echoln available_moves

    chosen_index = available_moves.index(response) || 0
    @battle.pbRegisterMove(idxBattler, chosen_index, false)
    PBDebug.log("[Remote AI] #{current_battler.pbThis(true)} (#{current_battler.index}) will use #{current_battler.moves[chosen_index].name}")
  end

  private


  def get_battlers_by_side(current_battler)
    # Determine which side the current battler is on
    side_index = 0
    count = 0
    @battle.sideSizes.each_with_index do |size, idx|
      if @battle.battlers.index(current_battler) < count + size
        side_index = idx
        break
      end
      count += size
    end

    my_side_battlers = []
    opposing_battlers = []

    idx_counter = 0
    @battle.sideSizes.each_with_index do |size, idx|
      size.times do
        battler = @battle.battlers[idx_counter]
        if idx == side_index
          my_side_battlers << battler unless battler == current_battler
        else
          opposing_battlers << battler
        end
        idx_counter += 1
      end
    end

    return my_side_battlers, opposing_battlers
  end

  def serialize_battle_state_to_params(current_battler, ally_battlers, enemy_battlers)
    # Remove the current Pokémon from allies
    filtered_allies = ally_battlers.reject { |b| b == current_battler }

    {
      current: serialize_battler(current_battler),
      allies: (filtered_allies.first(2).map { |ally| serialize_battler(ally) } + [nil]*2)[0,2],
      enemies: (enemy_battlers.first(3).map { |enemy| serialize_battler(enemy) } + [nil]*3)[0,3]
    }
  end


  def serialize_battler(battler)
    return nil unless battler
    {
      species: get_pokemon_readable_internal_name(battler.pokemon),
      level: battler.level,
      type1: battler.type1,
      type2: battler.type2,
      ability_id: battler.ability_id,
      item_id: battler.item_id,
      gender: battler.gender,
      iv: battler.iv,
      moves: battler.moves.map { |m| m ? m.id : nil },

      # Stats
      attack: battler.attack,
      spatk: battler.spatk,
      speed: battler.speed,
      stages: battler.stages,
      total_hp: battler.totalhp,
      current_hp: battler.hp,

      # Status
      fainted: battler.fainted,
      captured: battler.captured,
      effects: battler.effects,

      # Battle history / actions
      turn_count: battler.turnCount,
      participants: battler.participants,
      last_attacker: battler.lastAttacker&.index,
      last_foe_attacker: battler.lastFoeAttacker&.index,
      last_hp_lost: battler.lastHPLost,
      last_hp_lost_from_foe: battler.lastHPLostFromFoe,
      last_move_used: battler.lastMoveUsed,
      last_move_used_type: battler.lastMoveUsedType,
      last_regular_move_used: battler.lastRegularMoveUsed,
      last_regular_move_target: battler.lastRegularMoveTarget,
      last_round_moved: battler.lastRoundMoved,
      last_move_failed: battler.lastMoveFailed,
      last_round_move_failed: battler.lastRoundMoveFailed,
      moves_used: battler.movesUsed&.map { |m| m },
      current_move: battler.currentMove,
      took_damage: battler.tookDamage,
      took_physical_hit: battler.tookPhysicalHit,
      damage_state: battler.damageState,
      initial_hp: battler.initialHP
    }
  end






  def fetch_sprite_from_web(url, destinationPath = nil)
    return false unless downloadAllowed?()
    begin
      response = HTTPLite.get(url)
      if response[:status] == 200
        if destinationPath
          File.open(destinationPath, "wb") { |f| f.write(response[:body]) }
        end
        return response[:body]
      else
        echoln "Failed to fetch from #{url}"
        return nil
      end
    rescue MKXPError => e
      echoln "MKXPError: #{e.message}"
      return nil
    rescue Errno::ENOENT => e
      echoln "File Error: #{e.message}"
      return nil
    end
  end
end


#------------------------------
# Convert objects to JSON-safe
# ------------------------------
def convert_to_json_safe(obj)
  case obj
  when Hash
    obj.each_with_object({}) { |(k,v), h| h[k.to_s] = convert_to_json_safe(v) }
  when Array
    obj.compact.map { |v| convert_to_json_safe(v) }
  when Symbol
    obj.to_s
  when TrueClass, FalseClass, NilClass, Numeric
    obj
  else
    obj.to_s
  end
end
