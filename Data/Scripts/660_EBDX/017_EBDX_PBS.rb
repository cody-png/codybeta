#===============================================================================
#  EBDX PBS Data Loading
#===============================================================================
#  Handles loading of EBDX-specific PBS data for environments, metrics, etc.
#  Data is loaded lazily and cached in the EliteBattle module.
#===============================================================================

module EBDXPBSLoader
  #=============================================================================
  #  Environment Data (battle backdrops by map/terrain)
  #=============================================================================
  def self.load_environments
    return if @environments_loaded
    @environments_loaded = true

    # Load environment definitions from PBS/EBDX/environments.txt
    path = "PBS/EBDX/environments.txt"
    return unless File.exist?(path)

    begin
      File.open(path, "r") do |file|
        current_env = nil
        file.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /^\[(.+)\]$/
            current_env = $1.to_sym
            EliteBattle.add_data(current_env, :Environment, {})
          elsif current_env && line =~ /^(\w+)\s*=\s*(.+)$/
            key = $1.to_sym
            value = parse_value($2)
            data = EliteBattle.get(:Environment, current_env) || {}
            data[key] = value
            EliteBattle.add_data(current_env, :Environment, data)
          end
        end
      end
    rescue
      # Silent fail - environments are optional
    end
  end

  #=============================================================================
  #  Species Metrics (sprite positioning/altitude)
  #=============================================================================
  def self.load_metrics
    return if @metrics_loaded
    @metrics_loaded = true

    # Load metrics from PBS/EBDX/metrics.txt
    path = "PBS/EBDX/metrics.txt"
    return unless File.exist?(path)

    begin
      File.open(path, "r") do |file|
        current_species = nil
        current_form = 0
        file.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /^\[(\w+)(?:,\s*(\d+))?\]$/
            current_species = $1.to_sym
            current_form = $2 ? $2.to_i : 0
          elsif current_species && line =~ /^(\w+)\s*=\s*(.+)$/
            key = $1.to_sym
            value = parse_value($2)
            EliteBattle.add_data(current_species, :Species, key, current_form, value)
          end
        end
      end
    rescue
      # Silent fail - metrics are optional
    end
  end

  #=============================================================================
  #  Trainer Speech Data
  #=============================================================================
  def self.load_trainer_speech
    return if @speech_loaded
    @speech_loaded = true

    # Load trainer speech from PBS/EBDX/trainers.txt
    path = "PBS/EBDX/trainers.txt"
    return unless File.exist?(path)

    begin
      File.open(path, "r") do |file|
        current_trainer = nil
        current_name = nil
        file.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /^\[(\w+)(?:,\s*"(.+)")?\]$/
            current_trainer = $1.to_sym
            current_name = $2
          elsif current_trainer && line =~ /^(\w+)\s*=\s*(.+)$/
            key = $1.to_sym
            value = $2.gsub(/^"(.*)"$/, '\1')  # Strip quotes
            EliteBattle.add_data(current_trainer, :Trainer, key, current_name, value)
          end
        end
      end
    rescue
      # Silent fail - trainer speech is optional
    end
  end

  #=============================================================================
  #  Helper: Parse PBS values
  #=============================================================================
  def self.parse_value(str)
    str = str.strip
    # Boolean
    return true if str.downcase == "true"
    return false if str.downcase == "false"
    # Integer
    return str.to_i if str =~ /^-?\d+$/
    # Float
    return str.to_f if str =~ /^-?\d+\.\d+$/
    # Array
    if str.start_with?("[") && str.end_with?("]")
      return str[1..-2].split(",").map { |s| parse_value(s) }
    end
    # String (strip quotes if present)
    str.gsub(/^"(.*)"$/, '\1')
  end

  #=============================================================================
  #  Load all PBS data
  #=============================================================================
  def self.load_all
    return unless EBDXToggle.enabled?
    load_environments
    load_metrics
    load_trainer_speech
  end
end

#===============================================================================
#  Auto-load PBS data when game starts (if EBDX is enabled)
#===============================================================================
if defined?(MessageTypes)
  # Hook into game load to initialize PBS data
  module EBDXPBSAutoLoader
    def self.trigger
      EBDXPBSLoader.load_all if EBDXToggle.enabled?
    end
  end
end
