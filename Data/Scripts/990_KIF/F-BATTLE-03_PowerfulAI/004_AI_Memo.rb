#===============================================================================
# F-BATTLE-03 – per-decision memo for DemICE's AI (port optimisation)
#
# DemICE's scoring calls pbRoughDamage / pbCheckMoveImmunity for the same
# (move, user, target) many times per decision: bestMoveVsTarget alone runs
# 4 damage calcs + 4 immunity checks and is itself called from ~60 places in
# the function-code scores, pbGetMoveScore and the switch logic. Nothing in
# the battle changes while a command is being chosen, so the results are
# cached for the duration of one decision (pbDefaultChooseEnemyCommand,
# pbEnemyShouldWithdrawEx?, pbChooseBestNewEnemy – nested calls share the
# cache, which is cleared when the outermost one returns).
# Fake battlers made for switch checks are new objects, so they never hit a
# real battler's entry (keys use object ids).
#===============================================================================
class PokeBattle_AI
  alias kif_memo_pbRoughDamage pbRoughDamage unless method_defined?(:kif_memo_pbRoughDamage)
  alias kif_memo_pbCheckMoveImmunity pbCheckMoveImmunity unless method_defined?(:kif_memo_pbCheckMoveImmunity)
  alias kif_memo_bestMoveVsTarget bestMoveVsTarget unless method_defined?(:kif_memo_bestMoveVsTarget)
  alias kif_memo_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand unless method_defined?(:kif_memo_pbDefaultChooseEnemyCommand)
  alias kif_memo_pbEnemyShouldWithdrawEx? pbEnemyShouldWithdrawEx? unless method_defined?(:kif_memo_pbEnemyShouldWithdrawEx?)
  alias kif_memo_pbChooseBestNewEnemy pbChooseBestNewEnemy unless method_defined?(:kif_memo_pbChooseBestNewEnemy)

  def kif_memo_scope
    @kif_memo_depth = (@kif_memo_depth || 0) + 1
    @kif_memo ||= {}
    return yield
  ensure
    @kif_memo_depth -= 1
    @kif_memo = nil if @kif_memo_depth <= 0
  end

  def pbDefaultChooseEnemyCommand(*args)
    kif_memo_scope { kif_memo_pbDefaultChooseEnemyCommand(*args) }
  end

  def pbEnemyShouldWithdrawEx?(*args)
    kif_memo_scope { kif_memo_pbEnemyShouldWithdrawEx?(*args) }
  end

  def pbChooseBestNewEnemy(*args)
    kif_memo_scope { kif_memo_pbChooseBestNewEnemy(*args) }
  end

  def pbRoughDamage(move, user, target, skill, baseDmg = 0)
    memo = @kif_memo
    return kif_memo_pbRoughDamage(move, user, target, skill, baseDmg) unless memo
    key = [:dmg, move.object_id, user.object_id, target.object_id, skill]
    return memo[key] if memo.has_key?(key)
    return memo[key] = kif_memo_pbRoughDamage(move, user, target, skill, baseDmg)
  end

  def pbCheckMoveImmunity(score, move, user, target, skill)
    memo = @kif_memo
    return kif_memo_pbCheckMoveImmunity(score, move, user, target, skill) unless memo
    key = [:imm, score <= 0, move.object_id, user.object_id, target.object_id, skill]
    return memo[key] if memo.has_key?(key)
    return memo[key] = kif_memo_pbCheckMoveImmunity(score, move, user, target, skill)
  end

  def bestMoveVsTarget(user, target, skill)
    memo = @kif_memo
    return kif_memo_bestMoveVsTarget(user, target, skill) unless memo
    key = [:best, user.object_id, target.object_id, skill]
    return memo[key] if memo.has_key?(key)
    return memo[key] = kif_memo_bestMoveVsTarget(user, target, skill)
  end
end
