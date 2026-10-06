#===============================================================================
# KIF::DataLoad – run port code after the game loads its data files
# (port framework). KIF 0.20.7 replaced GameData.load_all whole in
# ChallengeMode.rb:427 (Endgame Challenge trainers, K-Eggs, species rewrite,
# mod queue all in one copy); here each feature registers its own step and
# 6.8.2's load_all stays untouched.
#
#   KIF::DataLoad.after_load_all("Endgame Challenge trainers") { ... }
#===============================================================================
module KIF
  module DataLoad
    @hooks = []

    def self.after_load_all(name, &block)
      @hooks << [name, block]
    end

    def self.run
      @hooks.each do |name, block|
        begin
          block.call
        rescue => e
          KIF.log("Data load step '#{name}' failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end

module GameData
  class << self
    alias kif_dl_load_all load_all unless method_defined?(:kif_dl_load_all)

    def load_all
      kif_dl_load_all
      KIF::DataLoad.run
    end
  end
end
