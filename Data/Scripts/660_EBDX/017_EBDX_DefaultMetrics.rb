#===============================================================================
#  Default EBDX Metrics - Hardcoded from PBS/EBDX/metrics.txt
#-------------------------------------------------------------------------------
#  This bypasses the need for EBDX's PBS compiler by directly setting up
#  the vectors and battler metrics that BattleSceneRoom needs.
#===============================================================================

module EliteBattle
  #-----------------------------------------------------------------------------
  #  Setup default vectors (from metrics.txt [VECTORS] section)
  #  Format: x, y, angle, scale, zoom
  #-----------------------------------------------------------------------------
  def self.setup_default_vectors
    # Vector format: x, y, angle, scale, zoom
    # x/y = camera position offset, angle = tilt, scale = field of view, zoom = zoom level

    # SINGLE battle vector (main view for single battles - centered, sees both sides)
    add_vector(:SINGLE, 134, 328, 26, 242, 1)
    # DOUBLE battle vector (slightly wider view)
    add_vector(:DOUBLE, 134, 328, 24, 262, 1)
    # TRIPLE battle vector
    add_vector(:TRIPLE, 134, 328, 22, 282, 1)
    # SENDOUT vector (for Pokemon sendout animation - zoomed in on player side)
    add_vector(:SENDOUT, 234, 306, 24, 206, 0.5)
    # ENEMY vector (intro view - zoomed in on enemy side)
    # Higher scale = more zoomed in, shifted position to focus on enemy
    add_vector(:ENEMY, 80, 380, 30, 320, 1.2)
    # PLAYER vector (view focused on player side)
    add_vector(:PLAYER, 200, 290, 24, 260, 1)
    # DUAL vector (for dual battles)
    add_vector(:DUAL, 196, 306, 26, 242, 0.6)
    # DYNAMAX vector
    add_vector(:DYNAMAX, 202, 308, 18, 136, 0.5)

    echoln "[EBDX] Vectors initialized: #{@vectors.keys.inspect}"
  end

  #-----------------------------------------------------------------------------
  #  Setup default battler positions (from metrics.txt [BATTLERPOS-X] sections)
  #  NOTE: Y values adjusted for KIF sprite positioning formula
  #  Original EBDX Y values (252, 262, etc.) result in off-screen positions
  #  Adjusted to produce visible on-screen positions with our position formula
  #-----------------------------------------------------------------------------
  def self.setup_default_battler_metrics
    # IMPORTANT: Essentials battle index layout:
    # - 1v1: Player=0, Enemy=1
    # - 2v2: Player=0,4  Enemy=1,5
    # - 3v3: Player=0,2,4  Enemy=1,3,5
    # So indices 2,3 are only used in 3v3 (middle Pokemon)
    # And indices 4,5 are used in both 2v2 and 3v3
    #
    # Original EBDX metrics.txt values:
    # BATTLERPOS-0: Single=116,252,21  Double=92,240,21   Triple=76,234,21
    # BATTLERPOS-1: Single=234,152,11  Double=256,164,15  Triple=264,156,18
    # BATTLERPOS-2: Double=192,262,25  Triple=152,244,25
    # BATTLERPOS-3: Double=198,152,11  Triple=210,154,15
    # BATTLERPOS-4: Triple=230,254,28
    # BATTLERPOS-5: Triple=162,152,11
    #
    # Y values adjusted for screen visibility (subtract ~45 from player Y values)

    # BATTLERPOS-0 (Player's first Pokemon - always used)
    battler_position(0,
      :X, 116, 92, 86,     # Single=116, Double=92, Triple=86 (+10 right)
      :Y, 207, 205, 214,   # Triple: +25 down (189->214)
      :Z, 21, 21, 26       # Triple: increased for smaller size
    )

    # BATTLERPOS-1 (Opponent's first Pokemon - always used)
    battler_position(1,
      :X, 234, 256, 289,   # Triple: +25 right (264->289)
      :Y, 152, 164, 156,   # Original values (enemy Y is fine)
      :Z, 11, 15, 18
    )

    # BATTLERPOS-2 (Player's 2nd Pokemon in 2v2, middle in 3v3)
    # In 2v2: Battler index 4 uses this
    battler_position(2,
      :X, 116, 177, 152,   # Double: 177, Triple=152 (no X change)
      :Y, 207, 222, 224,   # Triple: +25 down (199->224)
      :Z, 21, 25, 30       # Triple: increased for smaller size
    )

    # BATTLERPOS-3 (Opponent's 2nd Pokemon in 2v2, middle in 3v3)
    # In 2v2: Battler index 5 uses this
    battler_position(3,
      :X, 234, 198, 230,   # Triple: +20 right (210->230)
      :Y, 152, 152, 154,   # Original values
      :Z, 11, 11, 15
    )

    # BATTLERPOS-4 (Player's 3rd Pokemon - 3v3 only)
    battler_position(4,
      :X, 116, 116, 220,   # Triple: -10 left (230->220)
      :Y, 207, 207, 234,   # Triple: +25 down (209->234)
      :Z, 21, 21, 33       # Triple: increased for smaller size
    )

    # BATTLERPOS-5 (Opponent's 3rd Pokemon - 3v3 only)
    battler_position(5,
      :X, 234, 234, 177,   # Triple: +15 right (162->177)
      :Y, 152, 152, 152,   # Original values
      :Z, 11, 11, 11
    )
  end

  #-----------------------------------------------------------------------------
  #  Initialize all default EBDX data
  #-----------------------------------------------------------------------------
  def self.setup_default_data
    setup_default_vectors
    setup_default_battler_metrics
    echoln "[EBDX] Default vectors and battler metrics initialized."
    echoln "[EBDX] Vectors: #{@vectors.keys.inspect}"
    echoln "[EBDX] BattlerMetrics keys: #{@battlerMetrics.keys.inspect}"
    # Log to multiplayer debug if available
    if defined?(MultiplayerDebug)
      MultiplayerDebug.info("EBDX-INIT", "Vectors: #{@vectors.keys.inspect}")
      MultiplayerDebug.info("EBDX-INIT", "BattlerMetrics: #{@battlerMetrics.inspect}")
    end
  end
end

#===============================================================================
#  Register as a config process AND run immediately at load time
#===============================================================================
# Run immediately when file loads (backup)
EliteBattle.setup_default_data

# Also register as a config process (called during setupData)
EliteBattle.configProcess(:DEFAULT_METRICS) do
  # Only run if battlerMetrics is empty (not already set up)
  if EliteBattle.get(:battlerMetrics).nil? || EliteBattle.get(:battlerMetrics).empty?
    EliteBattle.setup_default_data
  end
end
