#===============================================================================
# C-RAND-01 – Randomizer: Leader team size (2026-10-07)
#   Gyms page → Leader team size: Same / +1 / +2 / Full. Only Gym Leaders
#   (every battle with them); the Trainers page's Team size no longer adds to
#   Gym Leaders. With random trainers this decides instead of Cody Settings'
#   "Gym Leader teams". Takes effect with Randomize now, like the rest.
#===============================================================================
module KIF
  module Rand
    LEADER_SETTINGS = [[:leader_size, :enum, 4]]   # Same / +1 / +2 / Full
    # (only once, even if this file is loaded again)
    LEADER_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_KEYS.include?(st[0]) }
    LEADER_SETTINGS.each { |st| DATA_KEYS << st[0] unless DATA_KEYS.include?(st[0]) }
    LABELS[:leader_size] = ["Leader team size", ["Same", "+1", "+2", "Full"]]

    def self.leader_type?(tr_type)
      return tr_type.to_s.start_with?("LEADER_")
    end

    # The Same/+1/+2/Full setting that applies to this trainer class
    def self.team_extra_setting(tr_type)
      return dget(leader_type?(tr_type) ? :leader_size : :team_size)
    end

    # one rule with the leader's lines (C-GYM-01), so they name the size the battle uses
    def self.team_extra_count(tr_type, n)
      return KIF::LeaderTeams.extra_count(n, team_extra_setting(tr_type))
    end
  end
end
