#===============================================================================
# C-RAND-01 – Randomizer: Leader team size (Cody, 2026-10-07)
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

    def self.team_extra_count(tr_type, n)
      case team_extra_setting(tr_type)
      when 1 then return [n + 1, 6].min - n
      when 2 then return [n + 2, 6].min - n
      when 3 then return [6 - n, 0].max
      end
      return 0
    end
  end
end
