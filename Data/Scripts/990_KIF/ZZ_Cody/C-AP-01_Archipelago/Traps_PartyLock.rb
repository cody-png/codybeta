#===============================================================================
# C-AP-01 – Archipelago Party Lock trap (2026-10-23)
#   "TRAP_PARTY_LOCK" (runs at a quiet moment like every trap, Traps.rb):
#   one random party Pokemon that can battle is locked and won't battle until
#   the slot's party_lock_unlock says so:
#     0 battles         after party_lock_battles finished battles (every
#                       battle the player fights: won, lost, run from or
#                       caught; pbAfterBattle's Events.onEndBattle)
#     1 checks          after party_lock_checks more location checks sent
#                       (KIF::AP.check!, a new location only)
#     2 pokemon_center  at the next Pokemon Center heal: the nurse's event
#                       page runs "Recover All" (event command 314) and also
#                       calls pbSetPokemonCenter; every Center nurse does both,
#                       no other healer (house beds, hotels, rivals) does
#   Rules:
#     * never the last Pokemon that can battle: at least one able, unlocked
#       Pokemon stays, or nothing is locked (and the message says so);
#       never an egg or a fainted Pokemon; at most 2 locked at a time (a
#       third trap waits in the save until one is unlocked)
#     * in battle a locked Pokemon can't lead (the first able unlocked one
#       does; a double battle shrinks if only one can), be switched in,
#       replace a fainted one or be dragged in (all go through
#       pbCanSwitchLax?, also for Auto-Battle and EBDX's party screen)
#     * as soon as no other party Pokemon can battle, the lock no longer
#       holds (in battle at once, so the player never loses with a Pokemon
#       left), and at the next quiet moment it is lifted with its message
#     * outside battles nothing changes (field moves, healing); Exp Share /
#       Exp All still give it their share (it gets no participant Exp)
#     * the lock is kept in the Pokemon (Pokemon#kif_ap_lock), so it survives
#       saving and the PC; it keeps counting down in a PC box
#     * an unlinked save ignores locks; Pinkan Island and Nuzlocke as every
#       trap (nothing here can faint a Pokemon)
#===============================================================================
class Pokemon
  attr_accessor :kif_ap_lock   # [kind, left]: "BATTLES" / "CHECKS" / "CENTER"
end

module KIF
  module AP
    module Traps
      LOCK_KINDS = %w[BATTLES CHECKS CENTER]   # party_lock_unlock 0, 1, 2
      MAX_LOCKS = 2
      @sit_out = false

      module_function

      def locked?(pk)
        l = pk.respond_to?(:kif_ap_lock) ? pk.kif_ap_lock : nil
        return l.is_a?(Array) && l[1].to_i > 0 && KIF::AP.on?
      end

      # the party, then every PC box
      def all_pokemon
        list = $Trainer ? $Trainer.party.compact : []
        boxes = ($PokemonStorage.boxes rescue nil) || []
        boxes.each { |b| b.each { |pk| list << pk if pk } if b }
        return list
      end

      def locks; all_pokemon.select { |pk| locked?(pk) }; end

      # can battle and isn't locked (PIF's own able?, not the hook below)
      def free?(pk); pk.kif_ap_able? && !locked?(pk); end

      # a locked party Pokemon sits out while another one can battle
      def sitting_out?(pk)
        return false unless pk && locked?(pk)
        return $Trainer.party.any? { |o| o && !o.equal?(pk) && free?(o) }
      rescue StandardError
        return false
      end

      # lead choice at the start of a battle (pbEnsureParticipants, pbSetUpSides)
      def sit_out
        @sit_out = true
        yield
      ensure
        @sit_out = false
      end

      def sit_out?; @sit_out; end

      def run_party_lock(who)
        kind = LOCK_KINDS[KIF::AP.opt("party_lock_unlock").to_i] || "BATTLES"
        n = case kind
            when "BATTLES" then KIF::AP.opt("party_lock_battles").to_i.clamp(1, 99)
            when "CHECKS"  then KIF::AP.opt("party_lock_checks").to_i.clamp(1, 99)
            else 1
            end
        free = $Trainer.party.select { |pk| pk && free?(pk) }
        if free.length < 2
          pbMessage(_INTL("A Party Lock Trap from {1}! Only one of your Pokémon can battle, so none is locked.", who))
          return
        end
        pk = free[rand(free.length)]
        pk.kif_ap_lock = [kind, n]
        KIF.log("Archipelago: Party Lock on #{pk.name} (#{kind} #{n})")
        pbMessage(lock_text(who, pk.name, kind, n))
      end

      def lock_text(who, name, kind, n)
        case kind
        when "BATTLES"
          return _INTL("A Party Lock Trap from {1}! {2} won't battle for 1 battle.", who, name) if n == 1
          return _INTL("A Party Lock Trap from {1}! {2} won't battle for {3} battles.", who, name, n)
        when "CHECKS"
          return _INTL("A Party Lock Trap from {1}! {2} won't battle until you send 1 more check.", who, name) if n == 1
          return _INTL("A Party Lock Trap from {1}! {2} won't battle until you send {3} more checks.", who, name, n)
        end
        return _INTL("A Party Lock Trap from {1}! {2} won't battle until your next Pokémon Center visit.", who, name)
      end

      # A battle ended / a check was sent / a Center healed: every lock of that kind
      def count_down(kind)
        return unless KIF::AP.on?
        all_pokemon.each do |pk|
          l = pk.kif_ap_lock
          next unless l.is_a?(Array) && l[0] == kind && l[1].to_i > 0
          l[1] = kind == "CENTER" ? 0 : l[1].to_i - 1
        end
      rescue StandardError => e
        KIF.log("Archipelago: Party Lock count failed (#{e.class}: #{e.message})")
      end

      # At a quiet moment: locks that ran out, or that would leave the party
      # with no Pokemon to battle, or wait for checks the slot no longer has
      def release_locks
        return unless KIF::AP.on?
        d = KIF::AP.data
        stuck = $Trainer.party.none? { |pk| pk && free?(pk) }
        no_checks = ((d[:locations] || []) - (d[:checked] || [])).empty?
        all_pokemon.each do |pk|
          l = pk.kif_ap_lock
          next unless l.is_a?(Array)
          done = l[1].to_i <= 0 || (l[0] == "CHECKS" && no_checks) ||
                 (stuck && pk.kif_ap_able? && $Trainer.party.any? { |o| o.equal?(pk) })
          next unless done
          pk.kif_ap_lock = nil
          pbMessage(_INTL("{1} is ready to battle again.", pk.name))
        end
      end

      # The nurse's page: "Recover All" next to pbSetPokemonCenter
      def nurse_page?(list)
        return (list || []).any? { |c| [355, 655].include?(c.code) && c.parameters[0].to_s.include?("pbSetPokemonCenter") }
      end
    end
  end
end

Events.onEndBattle += proc { |_sender, _e| KIF::AP::Traps.count_down("BATTLES") if $PokemonGlobal && $PokemonGlobal.kif_ap }

class Pokemon
  alias kif_ap_able? able? unless method_defined?(:kif_ap_able?)

  def able?
    return false if KIF::AP::Traps.sit_out? && KIF::AP::Traps.sitting_out?(self)
    return kif_ap_able?
  end
end

class PokeBattle_Battle
  alias kif_ap_pbCanSwitchLax? pbCanSwitchLax? unless method_defined?(:kif_ap_pbCanSwitchLax?)
  alias kif_ap_pbEnsureParticipants pbEnsureParticipants unless method_defined?(:kif_ap_pbEnsureParticipants)
  alias kif_ap_pbSetUpSides pbSetUpSides unless method_defined?(:kif_ap_pbSetUpSides)

  def pbCanSwitchLax?(idxBattler, idxParty, partyScene = nil)
    return false unless kif_ap_pbCanSwitchLax?(idxBattler, idxParty, partyScene)
    return true if idxParty < 0 || opposes?(idxBattler)
    pk = pbParty(idxBattler)[idxParty]
    return true unless KIF::AP::Traps.sitting_out?(pk)
    partyScene.pbDisplay(_INTL("{1} is under a Party Lock and won't battle!", pk.name)) if partyScene
    return false
  end

  def pbEnsureParticipants(*args)
    KIF::AP::Traps.sit_out { kif_ap_pbEnsureParticipants(*args) }
  end

  def pbSetUpSides(*args)
    KIF::AP::Traps.sit_out { kif_ap_pbSetUpSides(*args) }
  end
end

class Interpreter
  alias kif_ap_command_314 command_314 unless method_defined?(:kif_ap_command_314)

  def command_314
    ret = kif_ap_command_314
    begin
      if @parameters[0] == 0 && KIF::AP::Traps.nurse_page?(@list)
        KIF::AP::Traps.count_down("CENTER")
        KIF::AP::Traps.lift_curse   # Traps_Curse.rb
      end
    rescue StandardError => e
      KIF.log("Archipelago: Party Lock Center check failed (#{e.class}: #{e.message})")
    end
    return ret
  end
end

class PokemonPartyPanel
  alias kif_ap_lock_refresh refresh unless method_defined?(:kif_ap_lock_refresh)

  def refresh
    redraw = @refreshBitmap
    kif_ap_lock_refresh
    begin
      return unless redraw && @pokemon && KIF::AP::Traps.locked?(@pokemon)
      return unless @overlaysprite && !@overlaysprite.disposed? && @overlaysprite.bitmap
      pbSetSmallFont(@overlaysprite.bitmap)
      pbDrawTextPositions(@overlaysprite.bitmap, [[_INTL("LOCKED"), 150, 70, 0, Color.new(248, 96, 96), Color.new(72, 24, 24)]])
    rescue StandardError => e
      KIF.log("Archipelago: Party Lock tag failed (#{e.class}: #{e.message})")
    end
  end
end
