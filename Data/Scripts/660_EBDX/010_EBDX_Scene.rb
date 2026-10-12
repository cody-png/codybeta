#===============================================================================
#  PokeBattle_SceneEBDX - EBDX battle scene class
#===============================================================================
#  This class INHERITS from PokeBattle_Scene to get full animation support
#  while overriding visual methods for EBDX-specific appearance.
#
#  Inheritance is safe for multiplayer because:
#  - Animation methods are purely visual (don't affect battle state)
#  - Only visual overrides are applied; sync methods remain vanilla
#  - The proxy pattern in 011_EBDX_SceneProxy.rb handles scene selection
#===============================================================================

# Debug tag for EBDX scene
EBDX_DEBUG_TAG = "EBDX-SCENE"

#===============================================================================
# Extend PokemonBattlerSprite to disable auto-positioning when EBDX controls it
# This prevents KIF's internal positioning from fighting with EBDX's camera system
#===============================================================================
if defined?(PokemonBattlerSprite)
  class PokemonBattlerSprite
    attr_accessor :ebdx_position_disabled

    alias_method :ebdx_original_pbSetPosition, :pbSetPosition if method_defined?(:pbSetPosition) && !method_defined?(:ebdx_original_pbSetPosition)

    def pbSetPosition
      return if @ebdx_position_disabled
      ebdx_original_pbSetPosition if respond_to?(:ebdx_original_pbSetPosition)
    end

    # EBDX animation helper methods
    def getCenter(zoom = true)
      z = zoom ? self.zoom_y : 1
      bmp = self.bitmap
      return [self.x, self.y] if !bmp
      x = self.x
      y = self.y - bmp.height * z / 2
      return x, y
    end

    def getAnchor(zoom = true)
      return getCenter(zoom)
    end

    def width
      return self.bitmap ? self.bitmap.width : 128
    end

    def height
      return self.bitmap ? self.bitmap.height : 128
    end

    def still
      # No-op for compatibility - KIF sprites don't have animation frames to pause
    end

    def loaded
      return self.bitmap && !self.bitmap.disposed?
    end
  end
end

class PokeBattle_SceneEBDX < PokeBattle_Scene
  # Add EBDX-specific accessors (inherited ones come from parent)
  attr_accessor :abortable
  attr_accessor :idleTimer, :safaribattle, :vector, :inMoveAnim
  attr_accessor :sendingOut, :afterAnim, :lowHPBGM
  attr_accessor :briefmessage, :sprites, :introdone
  attr_accessor :playerLineUp, :opponentLineUp
  attr_reader :viewport, :dexview, :battle, :battlers, :commandWindow, :fightWindow, :bagWindow
  attr_reader :smTrainerSequence, :smSpeciesSequence, :firstsendout

  BLANK       = 0
  MESSAGE_BOX = 1
  COMMAND_BOX = 2
  FIGHT_BOX   = 3
  TARGET_BOX  = 4

  MESSAGE_PAUSE_TIME = (Graphics.frame_rate*0.25).floor

  def inspect
    return self.to_s.chop
  end

  #=============================================================================
  #  Initialization
  #=============================================================================
  def pbStartBattle(battle)
    begin
      @battle = battle
      @battlers = battle.battlers
      @abortable = false
      @aborted = false
      @battleEnd = false
      # EBDX-specific vars
      @firstsendout = true
    @inMoveAnim = false
    @lastcmd = [0, 0, 0, 0]
    @lastmove = [0, 0, 0, 0]
    @orgPos = nil
    @shadowAngle = 60
    @idleTimer = 0
    @idleSpeed = [40, 0]
    @animationCount = 1
    @showingplayer = true
    @showingenemy = true
    @briefmessage = false
    @lowHPBGM = false
    @introdone = false
    @dataBoxesHidden = false
    @sprites = {}
    @animations = []
    @frameCounter = 0
    @lastCmd = Array.new(@battlers.length, 0)
    @lastMove = Array.new(@battlers.length, 0)
    # Check for VS sequences
    @integratedVS = false
    @minorAnimation = false
    @smTrainerSequence = nil
    @smSpeciesSequence = nil
    if @battle.opponent
      begin
        @integratedVS = @battle.opponent.length < 2 && !EliteBattle.get(:smAnim) &&
          EliteBattle.can_transition?("integratedVS", @battle.opponent[0].trainer_type, :Trainer,
            @battle.opponent[0].name, (@battle.opponent[0].respond_to?(:partyID) ? @battle.opponent[0].partyID : 0))
        @minorAnimation = !@integratedVS &&
          EliteBattle.can_transition?("minorTrainer", @battle.opponent[0].trainer_type, :Trainer,
            @battle.opponent[0].name, (@battle.opponent[0].respond_to?(:partyID) ? @battle.opponent[0].partyID : 0))
      rescue
        @integratedVS = false
        @minorAnimation = false
      end
    end
    # Setup vector
    vec = EliteBattle.get_vector(:ENEMY)
    if @battle.opponent && @minorAnimation
      vec = EliteBattle.get_vector(:MAIN, @battle)
      vec[0] -= Graphics.width/2
    end
    @vector = Vector.new(*vec)
    @vector.battle = @battle
    # Viewport setup
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @dexview = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @dexview.z = 99999
    @msgview = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @msgview.z = 99999
    @traineryoffset = (Graphics.height - 320)
    @foeyoffset = (@traineryoffset*3/4).floor
    # Load battle background
    loadBackdrop
    # Load UI elements
    self.loadUIElements
    # NOTE: Do NOT call backdrop.update() here!
    # The refresh() method in loadBackdrop already calculated battler positions for MAIN vector.
    # At this point @vector is ENEMY, so update() would overwrite MAIN positions with ENEMY positions.
    # The correct positions are already stored in the battler sprites from refresh()->position().

    # Initialize sprites (using KIF's sprite system, NOT DynamicPokemonSprite)
    initializeSprites
    pbSetMessageMode(false)
    # Start scene animation
    startSceneAnimation
    rescue => e
      raise e
    end
  end

  #=============================================================================
  #  Backdrop loading
  #=============================================================================
  def loadBackdrop
    begin
      # Try EBDX backdrop system
      if defined?(BattleSceneRoom)
        env_data = getDefaultEnvironmentData
        @sprites["battlebg"] = BattleSceneRoom.new(@viewport, self, env_data)
      else
        loadVanillaBackdrop
      end
    rescue => e
      loadVanillaBackdrop
    end

    # trainer_Anim - ONLY create for trainer battles with minorAnimation
    # For wild battles (@battle.opponent is nil), don't create it at all
    if @battle.opponent && @minorAnimation && !@smTrainerSequence
      @sprites["trainer_Anim"] = ScrollingSprite.new(@viewport)
      begin
        base = "outdoor"
        begin
          try = sprintf("%03d", GameData::TrainerType.get(@battle.opponent[0].trainer_type).id_number)
          base = try if pbResolveBitmap("Graphics/EBDX/Transitions/Common/#{try}")
        rescue; end
        @sprites["trainer_Anim"].setBitmap("Graphics/EBDX/Transitions/Common/#{base}")
      rescue; end
      @sprites["trainer_Anim"].direction = -1
      @sprites["trainer_Anim"].speed = 48
      @sprites["trainer_Anim"].z = 97
    end
    # For wild battles, trainer_Anim is nil - no blue rectangle
  end

  # Get default environment data for BattleSceneRoom
  def getDefaultEnvironmentData
    data = nil

    # Try to get environment from EBDX system
    if defined?(EliteBattle) && EliteBattle.respond_to?(:getNextBattleEnv)
      begin
        data = EliteBattle.getNextBattleEnv(@battle)
        data = nil if !data.is_a?(Hash) || data.empty?
      rescue
        data = nil
      end
    end

    # Build default environment data based on battle context
    outdoor = EliteBattle.respond_to?(:outdoor_map?) ? EliteBattle.outdoor_map? : true

    if data.nil?
      data = {
        "backdrop" => "Field",
        "outdoor" => outdoor,
        "sky" => outdoor
      }
    end

    # Ensure outdoor flag is set
    data["outdoor"] = outdoor if !data.has_key?("outdoor")

    # Add grass for outdoor environments that don't already have grass
    # Always add grass for outdoor wild battles in field-type environments
    if outdoor && defined?(TerrainEBDX::TALLGRASS) && !data.has_key?("tallGrass")
      # Check environment - add grass for most outdoor non-special environments
      env = nil
      begin
        env = @battle.environment if @battle.respond_to?(:environment)
      rescue
        env = nil
      end

      # Add grass unless in water, cave, or other special environments
      shouldAddGrass = env.nil? || [:None, :Grass, :TallGrass].include?(env)

      if shouldAddGrass
        data.merge!(TerrainEBDX::TALLGRASS)
      end
    end
    return data
  end

  def loadVanillaBackdrop
    backdropFilename = @battle.respond_to?(:backdropBase) ? @battle.backdropBase : ""
    baseFilename = "Graphics/Battlebacks/#{backdropFilename}_bg"
    if pbResolveBitmap(baseFilename)
      @sprites["battlebg"] = AnimatedPlane.new(@viewport)
      @sprites["battlebg"].setBitmap(baseFilename)
      @sprites["battlebg"].z = 0
    else
      @sprites["battlebg"] = Sprite.new(@viewport)
      @sprites["battlebg"].z = 0
    end
    # Define battler/trainer position stub methods on the bg sprite
    bg = @sprites["battlebg"]
    def bg.battler(i)
      s = Struct.new(:x, :y, :z).new(0, 0, 50 + i)
      return s
    end
    def bg.trainer(i)
      s = Struct.new(:x, :y, :z).new(0, 0, 50 + i)
      return s
    end
  end

  #=============================================================================
  #  Initialize sprites (using KIF's native PokemonBattlerSprite)
  #=============================================================================
  def initializeSprites
    # Player back sprites
    @battle.player.each_with_index do |pl, i|
      plfile = GameData::TrainerType.player_back_sprite_filename(pl.trainer_type)
      pbAddSprite("player_#{i}", 0, 0, plfile, @viewport)
      if @sprites["player_#{i}"].bitmap.nil?
        @sprites["player_#{i}"].bitmap = Bitmap.new(2, 2)
      end
      @sprites["player_#{i}"].x = 40 + i*100
      @sprites["player_#{i}"].y = Graphics.height - @sprites["player_#{i}"].bitmap.height
      @sprites["player_#{i}"].z = 50
      @sprites["player_#{i}"].opacity = 0
      @sprites["player_#{i}"].src_rect.width /= 5 if @sprites["player_#{i}"].bitmap.width > @sprites["player_#{i}"].bitmap.height
    end

    # Trainer front sprites (using basic Sprite for KIF compatibility)
    if @battle.opponent
      @battle.opponent.each_with_index do |t, i|
        trfile = GameData::TrainerType.front_sprite_filename(t.trainer_type)
        pbAddSprite("trainer_#{i}", 0, 0, trfile, @viewport)
        @sprites["trainer_#{i}"].z = 100
        # Set anchor to bottom-center (same as vanilla) so EBDX positioning works correctly
        if @sprites["trainer_#{i}"].bitmap
          @sprites["trainer_#{i}"].ox = @sprites["trainer_#{i}"].src_rect.width / 2
          @sprites["trainer_#{i}"].oy = @sprites["trainer_#{i}"].bitmap.height
        end
        # Start with dark tone - will fade in during startSceneAnimation
        @sprites["trainer_#{i}"].tone = Tone.new(-255, -255, -255, -255)
      end
    end

    # Pokemon sprites (using KIF's native PokemonBattlerSprite)
    battleAnimations = ($PokemonSystem.battlescene == 0) rescue true
    @battlers.each_with_index do |b, i|
      next if !b
      sideSize = @battle.pbSideSize(i % 2)
      @sprites["pokemon_#{i}"] = PokemonBattlerSprite.new(@viewport, sideSize, i, battleAnimations)
      @sprites["pokemon_#{i}"].z = 100 + i
      # Disable KIF auto-positioning - EBDX controls sprite positions via animateScene
      @sprites["pokemon_#{i}"].ebdx_position_disabled = true if @sprites["pokemon_#{i}"].respond_to?(:ebdx_position_disabled=)
      # Create shadow sprite
      @sprites["shadow_#{i}"] = PokemonBattlerShadowSprite.new(@viewport, sideSize, i) rescue nil
      @sprites["shadow_#{i}"].visible = false if @sprites["shadow_#{i}"]
      # Create soft round drop shadow
      @sprites["rshadow_#{i}"] = Sprite.new(@viewport)
      @sprites["rshadow_#{i}"].bitmap = ebdxCreateRoundShadowBitmap
      @sprites["rshadow_#{i}"].ox = @sprites["rshadow_#{i}"].bitmap.width / 2
      @sprites["rshadow_#{i}"].oy = @sprites["rshadow_#{i}"].bitmap.height
      @sprites["rshadow_#{i}"].z = 50
      @sprites["rshadow_#{i}"].visible = false
    end
    # Wild battler bitmaps
    loadWildBitmaps
  end

  # Returns a Y offset (in pixels) to lower battler sprites in 1v1 battles
  def ebdxBattlerYOffset
    return (@battle.pbSideSize(0) == 1 && @battle.pbSideSize(1) == 1) ? 25 : 0
  end

  # Generates a soft elliptical gradient bitmap for the round drop shadow
  def ebdxCreateRoundShadowBitmap(w = 100, h = 26)
    bmp = Bitmap.new(w, h)
    cx = w / 2.0
    cy = h / 2.0
    for py in 0...h
      for px in 0...w
        dx = (px - cx) / cx
        dy = (py - cy) / cy
        dist = Math.sqrt(dx * dx + dy * dy)
        next if dist >= 1.0
        alpha = ((1.0 - dist) ** 1.2 * 255).to_i
        bmp.set_pixel(px, py, Color.new(0, 0, 0, alpha))
      end
    end
    bmp
  end

  # Syncs the round shadow sprite under the Pokemon sprite every frame
  def ebdxUpdateRoundShadow(i)
    rs = @sprites["rshadow_#{i}"]
    pk = @sprites["pokemon_#{i}"]
    return if !rs || rs.disposed? || !pk
    # Show only when the Pokemon sprite is visible and loaded
    rs.visible = pk.visible && pk.bitmap && !pk.bitmap.disposed?
    return unless rs.visible
    # Track the Pokemon's feet (x is centered, y is bottom of sprite since oy = bitmap height)
    # pk.y returns @spriteY (logical), but the actual drawn y = @spriteY + @spriteYExtra
    # @spriteYExtra holds animation offsets (bobbing, sendout arcs, etc.)
    y_extra = pk.instance_variable_get(:@spriteYExtra) rescue 0
    rs.x = pk.x
    rs.y = pk.y + (y_extra || 0)
    rs.zoom_x = pk.zoom_x
    rs.zoom_y = pk.zoom_x * 0.16   # always flat on the ground regardless of vertical zoom
    rs.opacity = pk.opacity * 0.55
    rs.z = pk.z - 1
  end

  def loadWildBitmaps
    # NOTE: Do NOT call backdrop.update() here!
    # The refresh() method already calculated battler positions for MAIN vector.
    # Calling update() would recalculate using @scene.vector (ENEMY at this point),
    # which overwrites the correct MAIN positions with wrong ENEMY positions.

    if @battle.wildBattle?
      @battle.pbParty(1).each_with_index do |pkmn, i|
        idx = i*2 + 1
        next if !@sprites["pokemon_#{idx}"]
        # Set Pokemon bitmap using KIF's native method
        @sprites["pokemon_#{idx}"].setPokemonBitmap(pkmn, false)

        # CRITICAL: Call pbSetOrigin to set ox/oy anchor points correctly!
        # Since we block pbSetPosition (via @ebdx_position_disabled), pbSetOrigin never gets called.
        # Without proper ox/oy, sprites are positioned from top-left instead of bottom-center.
        @sprites["pokemon_#{idx}"].pbSetOrigin if @sprites["pokemon_#{idx}"].respond_to?(:pbSetOrigin)

        # CUSTOM EBDX POSITIONING - Use backdrop battler positions instead of KIF's pbSetPosition
        if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
          battlerPos = @sprites["battlebg"].battler(idx) rescue nil
          if battlerPos
            @sprites["pokemon_#{idx}"].x = battlerPos.x
            @sprites["pokemon_#{idx}"].y = battlerPos.y + ebdxBattlerYOffset
            @sprites["pokemon_#{idx}"].z = battlerPos.z rescue (100 + idx)
            # KIF sprite zoom - CONSTANT size, camera zoom doesn't affect sprite scale
            # (Only background zooms for perspective effect, sprites stay same size)
            baseZoom = 1.0
            @sprites["pokemon_#{idx}"].zoom_x = baseZoom
            @sprites["pokemon_#{idx}"].zoom_y = baseZoom
          end
        else
          # Fallback to KIF positioning if backdrop not available
          @sprites["pokemon_#{idx}"].pbSetPosition if @sprites["pokemon_#{idx}"].respond_to?(:pbSetPosition)
        end

        # Start with dark tone - will fade in during startSceneAnimation
        @sprites["pokemon_#{idx}"].tone = Tone.new(-255, -255, -255)
        @sprites["pokemon_#{idx}"].visible = true
      end
    end

    # Initialize follower battler if applicable
    if !EliteBattle.follower(@battle).nil? && !@safaribattle
      idx = EliteBattle.follower(@battle)
      pkmn = @battlers[idx].pokemon
      @sprites["pokemon_#{idx}"].setPokemonBitmap(pkmn, true)
      # CRITICAL: Call pbSetOrigin to set ox/oy anchor points correctly!
      @sprites["pokemon_#{idx}"].pbSetOrigin if @sprites["pokemon_#{idx}"].respond_to?(:pbSetOrigin)
      # CUSTOM EBDX POSITIONING for follower
      if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
        battlerPos = @sprites["battlebg"].battler(idx) rescue nil
        if battlerPos
          @sprites["pokemon_#{idx}"].x = battlerPos.x
          @sprites["pokemon_#{idx}"].y = battlerPos.y + ebdxBattlerYOffset
          @sprites["pokemon_#{idx}"].z = battlerPos.z rescue (100 + idx)
          # Constant sprite zoom (player side = 1.0)
          @sprites["pokemon_#{idx}"].zoom_x = 1.0
          @sprites["pokemon_#{idx}"].zoom_y = 1.0
        end
      else
        @sprites["pokemon_#{idx}"].pbSetPosition if @sprites["pokemon_#{idx}"].respond_to?(:pbSetPosition)
      end
      @sprites["pokemon_#{idx}"].tone = Tone.new(-255, -255, -255)
      @sprites["pokemon_#{idx}"].visible = true
      @sprites["dataBox_#{idx}"].render if @sprites["dataBox_#{idx}"]
    end

    # Render ALL databoxes (both player and opponent/wild)
    @battle.battlers.each_with_index do |b, i|
      next if !b
      if @sprites["dataBox_#{i}"]
        @sprites["dataBox_#{i}"].render if @sprites["dataBox_#{i}"].respond_to?(:render)
        @sprites["dataBox_#{i}"].appear if @sprites["dataBox_#{i}"].respond_to?(:appear)
        @sprites["dataBox_#{i}"].visible = true if @sprites["dataBox_#{i}"].respond_to?(:visible=)
      end
    end
  end

  #=============================================================================
  #  UI Elements loading
  #=============================================================================
  def loadUIElements
    # Data boxes
    @battle.battlers.each_with_index do |b, i|
      next if !b
      if defined?(DataBoxEBDX)
        @sprites["dataBox_#{i}"] = DataBoxEBDX.new(b, @msgview, @battle.pbPlayer, self)
      else
        @sprites["dataBox_#{i}"] = PokemonDataBox.new(b, @battle.pbSideSize(0) == 1, @viewport)
      end
    end
    # Message box
    begin
      bmp1 = Bitmap.smartWindow(Rect.new(8, 8, 8, 8), Rect.new(0, 0, @viewport.rect.width - 28, 82), "Graphics/EBDX/Pictures/UI/skin1")
      bmp2 = Bitmap.smartWindow(Rect.new(8, 8, 8, 8), Rect.new(0, 0, @viewport.rect.width - 28, 82), "Graphics/EBDX/Pictures/UI/skin2")
      @sprites["messageBox"] = Sprite.new(@msgview)
      @sprites["messageBox"].bitmap = Bitmap.new(@viewport.rect.width - 28, 82*2)
      @sprites["messageBox"].bitmap.blt(0, 0, bmp1, bmp1.rect)
      @sprites["messageBox"].bitmap.blt(0, 82, bmp2, bmp2.rect)
      @sprites["messageBox"].x = @viewport.rect.width/2 - @sprites["messageBox"].src_rect.width/2
      @sprites["messageBox"].y = @viewport.rect.height - 86
      @sprites["messageBox"].z = 99999
      @sprites["messageBox"].src_rect.height /= 2
      @sprites["messageBox"].visible = false
    rescue
      @sprites["messageBox"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 96, @msgview)
      @sprites["messageBox"].visible = false
    end
    # Help window
    @sprites["helpwindow"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, 32, 32, @msgview)
    @sprites["helpwindow"].visible = false
    @sprites["helpwindow"].z = 100000
    # Message window - y aligned so text content sits inside the messageBox skin.
    # Skin: y=(height-86), height=82, inner area (8px border): (height-78)..(height-12).
    # With borderY=32 (16px top padding), window must start at (height-78)-16 = height-94
    # so line 1 starts at height-78 and line 2 ends at height-14, both within the skin.
    @sprites["messageWindow"] = Window_AdvancedTextPokemon.newWithSize(
      "", 16, Graphics.height - 94, Graphics.width - 32, 96, @msgview
    )
    @sprites["messageWindow"].letterbyletter = true
    @sprites["messageWindow"].cursorMode = 2
    @sprites["messageWindow"].z = 100000
    # Hide the vanilla window chrome (border + background) so it doesn't stack on top of
    # the EBDX messageBox skin. opacity=0 hides the frame, back_opacity=0 hides the fill.
    # The text contents remain fully visible since contents_opacity is unaffected.
    @sprites["messageWindow"].opacity = 0
    @sprites["messageWindow"].back_opacity = 0
    @sprites["messageWindow"].visible = false  # Start hidden, show when text is displayed
    # Vanilla compat command/fight windows (some code references these)
    @sprites["commandWindow"] = CommandMenuDisplay.new(@msgview, 0) rescue nil
    @sprites["commandWindow"].visible = false if @sprites["commandWindow"]
    @sprites["fightWindow"] = FightMenuDisplay.new(@msgview, 0) rescue nil
    @sprites["fightWindow"].visible = false if @sprites["fightWindow"]
    @sprites["targetWindow"] = TargetMenuDisplay.new(@msgview, 0) rescue nil
    @sprites["targetWindow"].visible = false if @sprites["targetWindow"]
    # EBDX UI widgets
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    loadUIElements: Creating EBDX UI widgets...") if defined?(MultiplayerDebug)
    if defined?(CommandWindowEBDX)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating CommandWindowEBDX...") if defined?(MultiplayerDebug)
      @commandWindow = CommandWindowEBDX.new(@msgview, @battle, self, @safaribattle)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating FightWindowEBDX...") if defined?(MultiplayerDebug)
      @fightWindow = FightWindowEBDX.new(@msgview, @battle, self)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating BagWindowEBDX...") if defined?(MultiplayerDebug)
      @bagWindow = BagWindowEBDX.new(self, @msgview)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating PartyLineupEBDX (player)...") if defined?(MultiplayerDebug)
      @playerLineUp = PartyLineupEBDX.new(@viewport, self, @battle, 0)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating PartyLineupEBDX (opponent)...") if defined?(MultiplayerDebug)
      @opponentLineUp = PartyLineupEBDX.new(@viewport, self, @battle, 1)
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      Creating TargetWindowEBDX...") if defined?(MultiplayerDebug)
      @targetWindow = TargetWindowEBDX.new(@msgview, @battle, self)
      8.times do
        @commandWindow.hide
        @fightWindow.hide
      end
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      EBDX widgets done") if defined?(MultiplayerDebug)
    else
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "      CommandWindowEBDX not defined, skipping EBDX widgets") if defined?(MultiplayerDebug)
    end
    # Ability message sprite (with background, border, slide animation)
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    loadUIElements: Creating ability message sprite...") if defined?(MultiplayerDebug)
    begin
      bg_src = pbBitmap("Graphics/EBDX/Pictures/UI/abilityMessage")
      # Store background + border as reusable template
      @abilityMsgBg = Bitmap.new(bg_src.width, bg_src.height)
      @abilityMsgBg.blt(0, 0, bg_src, bg_src.rect)
      bg_src.dispose
      bw = @abilityMsgBg.width; bh = @abilityMsgBg.height
      border = Color.new(255, 255, 255, 160)
      @abilityMsgBg.fill_rect(0, 0, bw, 2, border)       # top
      @abilityMsgBg.fill_rect(0, bh - 2, bw, 2, border)  # bottom
      @abilityMsgBg.fill_rect(0, 0, 2, bh, border)       # left
      @abilityMsgBg.fill_rect(bw - 2, 0, 2, bh, border)  # right
      # Create the display sprite
      @sprites["abilityMessage"] = Sprite.new(@msgview)
      @sprites["abilityMessage"].bitmap = Bitmap.new(bw, bh)
      @sprites["abilityMessage"].oy = bh / 2
      @sprites["abilityMessage"].opacity = 0
      @sprites["abilityMessage"].visible = false
      @sprites["abilityMessage"].z = 99999
      # Animation state
      @abilityMsgState  = :idle
      @abilityMsgFrames = 0
      @abilityMsgStartX  = 0
      @abilityMsgTargetX = 0
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "    loadUIElements: Ability message sprite done") if defined?(MultiplayerDebug)
    rescue => e
      # Ability splash fallback
      MultiplayerDebug.warn(EBDX_DEBUG_TAG, "    loadUIElements: Ability message sprite failed (#{e.class}: #{e.message})") if defined?(MultiplayerDebug)
    end
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    loadUIElements: END") if defined?(MultiplayerDebug)
  end

  #=============================================================================
  #  Scene animation start
  #=============================================================================
  def startSceneAnimation
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: BEGIN") if defined?(MultiplayerDebug)

    # NOTE: Do NOT call backdrop.update() here!
    # The correct MAIN vector positions were already set in loadWildBitmaps/refresh().
    # Calling update() would recalculate for current vector (ENEMY at this point).

    # Hide trainer_Anim for non-minorAnimation battles
    if @sprites["trainer_Anim"]
      @sprites["trainer_Anim"].visible = !@smTrainerSequence && @minorAnimation
    end

    # Create black overlay for fade-in
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Creating fade sprite...") if defined?(MultiplayerDebug)
    black = Sprite.new(@viewport)
    black.z = 99999
    black.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    black.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))

    # Get daylight tint from backdrop (for night effect)
    daylightTone = Tone.new(0, 0, 0)
    if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:daylightTone)
      daylightTone = @sprites["battlebg"].daylightTone rescue Tone.new(0, 0, 0)
    end
    echoln "[EBDX] startSceneAnimation: daylightTone = #{daylightTone.inspect}" rescue nil

    # EBDX: Vector starts at ENEMY (set in pbStartBattle), now animate to MAIN
    # Just set target and let update() animate - don't manually set internal vars!
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Setting target vector (MAIN)...") if defined?(MultiplayerDebug)
    mainVector = EliteBattle.get_vector(:MAIN, @battle)
    @vector.force
    @vector.set(mainVector)
    @vector.inc = 0.1  # Slow for dramatic zoom effect

    # EBDX animation: Fade from black + zoom out SIMULTANEOUSLY (22 frames)
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Running fade+zoom loop...") if defined?(MultiplayerDebug)
    22.times do |i|
      # Fade trainers from black tone (start after frame 11)
      if @battle.opponent && i > 11
        @battle.opponent.length.times do |t|
          if @sprites["trainer_#{t}"]
            @sprites["trainer_#{t}"].tone.all += 12.75 if @sprites["trainer_#{t}"].tone.all < 0
            @sprites["trainer_#{t}"].tone.gray += 12.75 if @sprites["trainer_#{t}"].tone.gray < 0
          end
        end
      end

      # Fade wild Pokemon from black tone (simultaneous with zoom)
      if @battle.wildBattle? && i > 6
        @battle.pbParty(1).length.times do |m|
          idx = m*2 + 1
          next if !@sprites["pokemon_#{idx}"]
          @sprites["pokemon_#{idx}"].tone.all += 16 if @sprites["pokemon_#{idx}"].tone.all < 0
          @sprites["pokemon_#{idx}"].tone.gray += 16 if @sprites["pokemon_#{idx}"].tone.gray < 0
        end
      end

      # Fade from black (complete in ~8 frames)
      black.opacity -= 32 if black.opacity > 0
      self.wait(1, true)
    end
    black.dispose
    @vector.inc = 0.2
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Fade complete") if defined?(MultiplayerDebug)
    # Party lineups
    if @battle.trainerBattle?
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Showing party lineups...") if defined?(MultiplayerDebug)
      pbShowPartyLineup(0)
      pbShowPartyLineup(1)
    end
    # Wild Pokemon cries and databoxes
    # Wild Pokemon play cry here since they don't have ball burst animation
    if @battle.wildBattle?
      @battle.pbParty(1).each_with_index do |pkmn, i|
        playBattlerCry(@battlers[i*2 + 1]) if respond_to?(:playBattlerCry)
      end
      # Show databoxes
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Showing wild databoxes...") if defined?(MultiplayerDebug)
      @battle.pbParty(1).length.times do |m|
        idx = m*2 + 1
        @sprites["dataBox_#{idx}"].appear if @sprites["dataBox_#{idx}"] && @sprites["dataBox_#{idx}"].respond_to?(:appear)
      end

      # Fade wild pokemon tones to NORMAL (0,0,0) - NOT to night tint!
      # Pokemon sprites should NOT have night tint - only backdrop elements get that
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Fading wild pokemon to normal...") if defined?(MultiplayerDebug)
      16.times do
        @battle.pbParty(1).length.times do |m|
          idx = m*2 + 1
          next if !@sprites["pokemon_#{idx}"]
          # Fade to normal tone (0,0,0,0)
          @sprites["pokemon_#{idx}"].tone.all += 16 if @sprites["pokemon_#{idx}"].tone.all < 0
          @sprites["pokemon_#{idx}"].tone.gray += 16 if @sprites["pokemon_#{idx}"].tone.gray < 0
        end
        self.wait(1, true)
      end

      # Ensure final tone is normal (NOT night tint)
      # NOTE: Do NOT call pbSetPosition here - positions were already set correctly
      # in loadWildBitmaps using EBDX backdrop. Calling pbSetPosition would reset
      # to vanilla KIF positions and break EBDX positioning.
      @battle.pbParty(1).length.times do |m|
        idx = m*2 + 1
        next if !@sprites["pokemon_#{idx}"]
        @sprites["pokemon_#{idx}"].tone = Tone.new(0, 0, 0, 0)
      end

      # Shiny animation
      @battle.pbParty(1).each_with_index do |pkmn, i|
        idx = i*2 + 1
        next if !@sprites["pokemon_#{idx}"]
        battler = @battlers[idx]
        if shinyBattler?(battler) && ($PokemonSystem.battlescene == 0)
          pbCommonAnimation("Shiny", battler, nil) rescue nil
        end
      end
    end
    # Debug: ensure wild Pokemon sprites are still visible after animation
    if @battle.wildBattle? && defined?(MultiplayerDebug)
      @battle.pbParty(1).length.times do |m|
        idx = m*2 + 1
        sprite = @sprites["pokemon_#{idx}"]
        if sprite
          MultiplayerDebug.info(EBDX_DEBUG_TAG, "    POST-ANIMATION pokemon_#{idx}: visible=#{sprite.visible}, opacity=#{sprite.opacity}, bitmap=#{sprite.bitmap ? 'YES' : 'NIL'}")
        end
      end
    end

    # Trainer fade-in
    if @battle.trainerBattle? && @battle.opponent
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: Fading in trainers...") if defined?(MultiplayerDebug)
      @battle.opponent.length.times do |t|
        next if !@sprites["trainer_#{t}"]
        16.times do
          @sprites["trainer_#{t}"].tone.all += 25.5 if @sprites["trainer_#{t}"].tone.all < 0
          @sprites["trainer_#{t}"].tone.gray += 25.5 if @sprites["trainer_#{t}"].tone.gray < 0
          self.wait(1, true)
        end
      end
    end
    MultiplayerDebug.info(EBDX_DEBUG_TAG, "    startSceneAnimation: END") if defined?(MultiplayerDebug)

    # NOTE: Do NOT call forceRefreshAllPositions here!
    # The correct MAIN vector positions were set in loadWildBitmaps.
    # At this point, the vector is still transitioning from ENEMY to MAIN.
    # animateScene with align=true will handle position updates as vector moves.
  end

  #=============================================================================
  #  Force refresh positions for ALL battlers
  #  Called after intro and sendout to ensure correct MAIN vector positioning
  #=============================================================================
  def forceRefreshAllPositions
    return unless @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)

    # Force backdrop to update with current vector
    @sprites["battlebg"].update

    # Update ALL Pokemon positions from backdrop
    @battle.battlers.each_with_index do |b, i|
      next if !b || !@sprites["pokemon_#{i}"]

      battlerPos = @sprites["battlebg"].battler(i) rescue nil
      next unless battlerPos

      sprite = @sprites["pokemon_#{i}"]
      sprite.x = battlerPos.x
      sprite.y = battlerPos.y + ebdxBattlerYOffset
      sprite.z = battlerPos.z rescue (100 + i)

      # Set constant zoom based on side
      # Player side (i%2 == 0): 1.0, Enemy side (i%2 == 1): 1.0
      baseZoom = 1.0
      sprite.zoom_x = baseZoom
      sprite.zoom_y = baseZoom

      # Ensure visible
      sprite.visible = true if b.hp > 0
    end
  end

  #=============================================================================
  #  Graphics and frame updates
  #=============================================================================
  def pbGraphicsUpdate
    # Update animations
    if @animations && @animations.length > 0
      shouldCompact = false
      @animations.each_with_index do |a, i|
        a.update
        if a.animDone?
          a.dispose
          @animations[i] = nil
          shouldCompact = true
        end
      end
      @animations.compact! if shouldCompact
    end
    # Update backdrop
    @sprites["battlebg"].update if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)
    # Update vector
    @vector.update if @vector
    Graphics.update
    @frameCounter += 1
    @frameCounter = @frameCounter%(Graphics.frame_rate*12/20)
  end

  def pbUpdate(cw = nil)
    pbGraphicsUpdate
    pbInputUpdate
    pbFrameUpdate(cw)
  end

  def pbInputUpdate
    Input.update
    if Input.trigger?(Input::BACK) && @abortable && !@aborted
      @aborted = true
      @battle.pbAbort
    end
  end

  def pbFrameUpdate(cw = nil)
    cw.update if cw
    @battle.battlers.each_with_index do |b, i|
      next if !b
      # DataBoxEBDX.update takes no arguments
      @sprites["dataBox_#{i}"].update if @sprites["dataBox_#{i}"] && @sprites["dataBox_#{i}"].respond_to?(:update)
      # DynamicPokemonSprite.update takes optional scale_y argument
      if @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].respond_to?(:update)
        # Check if it's a DynamicPokemonSprite (takes optional arg) or other sprite
        if @sprites["pokemon_#{i}"].is_a?(DynamicPokemonSprite)
          @sprites["pokemon_#{i}"].update
        else
          @sprites["pokemon_#{i}"].update rescue nil
        end
      end
      @sprites["shadow_#{i}"].update if @sprites["shadow_#{i}"] && @sprites["shadow_#{i}"].respond_to?(:update)
    end
    # EBDX command/fight window updates are handled in their input loops
    # (pbCommandMenuEBDX / pbFightMenu) — NOT here, because their update()
    # methods unconditionally set selector.visible = true which causes
    # red selector corners to persist on screen outside of menu use.
    @playerLineUp.update if @playerLineUp && @playerLineUp.respond_to?(:update)
    @opponentLineUp.update if @opponentLineUp && @opponentLineUp.respond_to?(:update)
    updateAbilityMessage if respond_to?(:updateAbilityMessage)
  end

  def pbRefresh
    @battle.battlers.each_with_index do |b, i|
      next if !b
      @sprites["dataBox_#{i}"].refresh if @sprites["dataBox_#{i}"]
    end
  end

  def pbRefreshOne(idxBattler)
    @sprites["dataBox_#{idxBattler}"].refresh if @sprites["dataBox_#{idxBattler}"]
  end

  #=============================================================================
  #  Wait utility
  #=============================================================================
  def wait(frames = 1, align = false)
    frames.times do
      if align
        animateScene(true) if respond_to?(:animateScene)
      end
      pbGraphicsUpdate
      Input.update
    end
  end

  def animateScene(align = false, smanim = false)
    # DEBUG: Log Pokemon positions every ~1 second (40 frames)
    @debugPosCounter ||= 0
    @debugPosCounter += 1
    if @debugPosCounter >= 40 && defined?(MultiplayerDebug)
      @debugPosCounter = 0
      # Determine current state
      state = "UNKNOWN"
      state = "INTRO" if !@introdone
      state = "SENDOUT" if @sendingOut
      state = "COMMAND" if @introdone && !@sendingOut && !@inMoveAnim
      state = "MOVE_ANIM" if @inMoveAnim
      # Log state and vector info
      if @vector
        MultiplayerDebug.info("POS-DEBUG", "[#{state}] Vector: x=#{@vector.x.round(1)}, y=#{@vector.y.round(1)}, x2=#{@vector.x2.round(1)}, y2=#{@vector.y2.round(1)}, zoom1=#{@vector.zoom1.round(2)}")
      end
      # Log backdrop info
      if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
        bg = @sprites["battlebg"].instance_variable_get(:@sprites)["bg"] rescue nil
        if bg
          MultiplayerDebug.info("POS-DEBUG", "[#{state}] Backdrop: x=#{bg.x.round(1)}, y=#{bg.y.round(1)}, ox=#{bg.ox.round(1)}, oy=#{bg.oy.round(1)}, zoom=#{bg.zoom_x.round(2)}")
        end
      end
      # Log Pokemon positions
      [0, 1].each do |i|
        next unless @sprites["pokemon_#{i}"]
        sprite = @sprites["pokemon_#{i}"]
        battlerPos = @sprites["battlebg"].battler(i) rescue nil
        bp_info = battlerPos ? "backdrop=(#{battlerPos.x.round(1)},#{battlerPos.y.round(1)})" : "backdrop=NIL"
        MultiplayerDebug.info("POS-DEBUG", "[#{state}] Pokemon_#{i}: sprite=(#{sprite.x.round(1)},#{sprite.y.round(1)}) #{bp_info} zoom=#{sprite.zoom_x.round(2)} visible=#{sprite.visible}")
      end
    end

    # Special intro animations
    @smTrainerSequence.update if @smTrainerSequence && @smTrainerSequence.respond_to?(:started) && @smTrainerSequence.started
    @smSpeciesSequence.update if @smSpeciesSequence && @smSpeciesSequence.respond_to?(:started) && @smSpeciesSequence.started
    @integratedVSSequence.update if @integratedVSSequence
    @integratedVSSequence.finish if @introdone && @integratedVSSequence

    # Update player lineup and opponent lineup
    @playerLineUp.update if @playerLineUp && @playerLineUp.respond_to?(:update) && !@playerLineUp.disposed?
    @opponentLineUp.update if @opponentLineUp && @opponentLineUp.respond_to?(:update) && !@opponentLineUp.disposed?

    # Fancy message update
    @fancyMsg.update if @fancyMsg && !@fancyMsg.disposed?

    # Update vector positions (this interpolates toward target)
    @vector.update if @vector

    # Message window clearing trick
    if @inMoveAnim.is_a?(Numeric)
      @inMoveAnim += 1
      if @inMoveAnim > Graphics.frame_rate*0.5
        clearMessageWindow if respond_to?(:clearMessageWindow)
        @inMoveAnim = false
      end
    end

    # Update backdrop
    @sprites["battlebg"].update if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)

    # trainer_Anim - ONLY for trainer battles with minorAnimation
    # For wild battles this sprite doesn't exist (nil), so no blue rectangle
    if @sprites["trainer_Anim"]
      @sprites["trainer_Anim"].update if @sprites["trainer_Anim"].respond_to?(:update)
      # Fade out after intro is done
      @sprites["trainer_Anim"].opacity -= 8 if @introdone && @sprites["trainer_Anim"].opacity > 0
    end

    # Idle timer for random camera motion
    @idleTimer += 1 if @idleTimer >= 0
    @lastMotion = nil if @idleTimer < 0

    # Safari player positioning
    @sprites["player_"].x += (40-@sprites["player_"].x)/4 if @safaribattle && @sprites["player_"] && @playerfix

    # Update battler sprites with CUSTOM POSITIONING SYSTEM
    # Uses EBDX backdrop positions and zoom formula adapted for KIF sprites
    @battle.battlers.each_with_index do |b, i|
      next if !b || !@sprites["pokemon_#{i}"]

      # Update sprite animation
      @sprites["pokemon_#{i}"].update if @sprites["pokemon_#{i}"].respond_to?(:update)

      # Update databox
      @sprites["dataBox_#{i}"].update if @sprites["dataBox_#{i}"] && @sprites["dataBox_#{i}"].respond_to?(:update)

      # CUSTOM EBDX POSITIONING FOR KIF SPRITES
      # CRITICAL: Don't update positions during intro animation!
      # The initial positions were set correctly for MAIN vector in loadWildBitmaps.
      # Updating during intro would use the transitioning vector (ENEMY->MAIN),
      # which gives wrong positions. Only update positions AFTER intro completes.
      isEnemySide = (i % 2 == 1)
      hasBackdrop = @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
      if isEnemySide
        # Enemy Pokemon ALWAYS track camera (including during intro and sendout)
        # This ensures they appear stationary relative to the ground, not the screen
        shouldUpdatePos = hasBackdrop
      elsif !@introdone
        # Player side during intro: don't update positions
        shouldUpdatePos = false
      else
        # Player side after intro: only when align=true and not sending out
        shouldUpdatePos = align && !@sendingOut && hasBackdrop
      end
      if shouldUpdatePos
        # Get EBDX backdrop position for this battler
        battlerPos = @sprites["battlebg"].battler(i) rescue nil
        if battlerPos
          # DEBUG: Log position updates
          @posUpdateCounter ||= 0
          @posUpdateCounter += 1
          if @posUpdateCounter % 40 == 1 && defined?(MultiplayerDebug)
            state = @introdone ? (@sendingOut ? "SENDOUT" : "BATTLE") : "INTRO"
            oldX = @sprites["pokemon_#{i}"].x
            oldY = @sprites["pokemon_#{i}"].y
            MultiplayerDebug.info("POS-UPDATE", "[#{state}] Pokemon_#{i}: (#{oldX.round(1)},#{oldY.round(1)}) -> (#{battlerPos.x.round(1)},#{battlerPos.y.round(1)})")
          end
          # Set position from EBDX backdrop
          @sprites["pokemon_#{i}"].x = battlerPos.x
          @sprites["pokemon_#{i}"].y = battlerPos.y + ebdxBattlerYOffset
          @sprites["pokemon_#{i}"].z = battlerPos.z rescue (100 + i)

          # KIF sprite zoom - CONSTANT size regardless of camera zoom
          # Both sides: 1.0 base
          # Only background zooms for perspective effect, sprites stay same size
          baseZoom = 1.0
          @sprites["pokemon_#{i}"].zoom_x = baseZoom
          @sprites["pokemon_#{i}"].zoom_y = baseZoom
        end
      end
      # Sync round shadow to the Pokemon sprite's current position every frame
      ebdxUpdateRoundShadow(i)

      # Random idle camera motion
      if !@orgPos.nil? && @idleTimer > (@lastMotion.nil? ? EliteBattle::BATTLE_MOTION_TIMER*Graphics.frame_rate : EliteBattle::BATTLE_MOTION_TIMER*Graphics.frame_rate*0.5) && @vector.finished? && !@safaribattle
        @vector.inc = 0.005*(rand(4)+1)
        a = EliteBattle.random_vector(@battle, @lastMotion) rescue []
        if a.length > 0
          @lastMotion = rand(a.length)
          setVector(a[@lastMotion]) if respond_to?(:setVector)
        end
      end
    end

    # Update trainer sprites with EBDX positioning
    if @battle.opponent
      @battle.opponent.length.times do |t|
        next if !@sprites["trainer_#{t}"]
        @sprites["trainer_#{t}"].update if @sprites["trainer_#{t}"].respond_to?(:update)

        # CUSTOM EBDX POSITIONING FOR TRAINER SPRITES
        # Skip during sendout animation
        if align && !@sendingOut && @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:trainer)
          trainerPos = @sprites["battlebg"].trainer(t * 2 + 1) rescue nil
          if trainerPos
            @sprites["trainer_#{t}"].x = trainerPos.x
            @sprites["trainer_#{t}"].y = trainerPos.y
            @sprites["trainer_#{t}"].z = trainerPos.z rescue 100
            # Constant trainer zoom (no camera-linked scaling)
            @sprites["trainer_#{t}"].zoom_x = 1.0
            @sprites["trainer_#{t}"].zoom_y = 1.0
          end
        end
      end
    end
  end

  #=============================================================================
  #  Window displays (match vanilla interface exactly)
  #=============================================================================
  def pbShowWindow(windowType)
    return unless @sprites
    # Message box background shows for MESSAGE, COMMAND, and FIGHT boxes (like EBDX)
    @sprites["messageBox"].visible = (windowType == MESSAGE_BOX ||
                                      windowType == COMMAND_BOX ||
                                      windowType == FIGHT_BOX) if @sprites["messageBox"]
    # Message window (text) only shows for MESSAGE_BOX
    @sprites["messageWindow"].visible = (windowType == MESSAGE_BOX) if @sprites["messageWindow"]
    @sprites["commandWindow"].visible = (windowType == COMMAND_BOX) if @sprites["commandWindow"]
    @sprites["fightWindow"].visible   = (windowType == FIGHT_BOX) if @sprites["fightWindow"]
    @sprites["targetWindow"].visible  = (windowType == TARGET_BOX) if @sprites["targetWindow"]
  end

  def pbSetMessageMode(mode)
    @sprites["messageWindow"].letterbyletter = (mode ? false : true) if @sprites["messageWindow"]
  end

  def pbWaitMessage
    return if !@briefMessage
    pbShowWindow(MESSAGE_BOX)
    cw = @sprites["messageWindow"]
    MESSAGE_PAUSE_TIME.times { pbUpdate(cw) }
    cw.text = ""
    cw.visible = false
    @briefMessage = false
  end

  def pbDisplayMessage(msg, brief = false)
    pbWaitMessage
    pbShowWindow(MESSAGE_BOX)
    cw = @sprites["messageWindow"]
    cw.setText(msg)
    PBDebug.log(msg)
    yielded = false
    i = 0
    loop do
      pbUpdate(cw)
      if !cw.busy?
        if !yielded
          yield if block_given?
          yielded = true
        end
        if brief
          @briefMessage = true
          break
        end
        if i >= MESSAGE_PAUSE_TIME
          cw.text = ""
          cw.visible = false
          break
        end
        i += 1
      end
      if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE) || @abortable || ($PokemonSystem && $PokemonSystem.respond_to?(:autobattler) && $PokemonSystem.autobattler && $PokemonSystem.autobattler != 0)
        if cw.busy?
          pbPlayDecisionSE if cw.pausing? && !@abortable
          cw.skipAhead
        elsif !@abortable
          cw.text = ""
          cw.visible = false
          break
        end
      end
    end
  end
  alias pbDisplay pbDisplayMessage

  def pbDisplayPausedMessage(msg)
    pbWaitMessage
    pbShowWindow(MESSAGE_BOX)
    cw = @sprites["messageWindow"]
    cw.text = _INTL("{1}\1", msg)
    PBDebug.log(msg)
    yielded = false
    i = 0
    loop do
      pbUpdate(cw)
      if !cw.busy?
        if !yielded
          yield if block_given?
          yielded = true
        end
        if !@battleEnd
          if i >= MESSAGE_PAUSE_TIME*3
            cw.text = ""
            cw.visible = false
            break
          end
          i += 1
        end
      end
      if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE) || @abortable || ($PokemonSystem && $PokemonSystem.respond_to?(:autobattler) && $PokemonSystem.autobattler && $PokemonSystem.autobattler != 0)
        if cw.busy?
          pbPlayDecisionSE if cw.pausing? && !@abortable
          cw.skipAhead
        elsif !@abortable
          cw.text = ""
          pbPlayDecisionSE
          break
        end
      end
    end
  end

  def pbDisplayConfirmMessage(msg)
    return pbShowCommands(msg, [_INTL("Yes"), _INTL("No")], 1) == 0
  end

  def pbShowCommands(msg, commands, defaultValue)
    pbWaitMessage
    pbShowWindow(MESSAGE_BOX)
    dw = @sprites["messageWindow"]
    dw.text = msg
    cw = Window_CommandPokemon.new(commands)
    cw.x = Graphics.width - cw.width
    cw.y = Graphics.height - cw.height - dw.height
    cw.z = dw.z + 1
    cw.index = 0
    cw.viewport = @viewport
    PBDebug.log(msg)
    loop do
      cw.visible = (!dw.busy?)
      pbUpdate(cw)
      dw.update
      if Input.trigger?(Input::BACK) && defaultValue >= 0
        if dw.busy?
          pbPlayDecisionSE if dw.pausing?
          dw.resume
        else
          cw.dispose
          dw.text = ""
          return defaultValue
        end
      elsif Input.trigger?(Input::USE)
        if dw.busy?
          pbPlayDecisionSE if dw.pausing?
          dw.resume
        else
          cw.dispose
          dw.text = ""
          return cw.index
        end
      end
    end
  end

  #=============================================================================
  #  Sprite utilities
  #=============================================================================
  def pbAddSprite(id, x, y, filename, viewport)
    sprite = IconSprite.new(x, y, viewport)
    sprite.setBitmap(filename) rescue nil if filename
    @sprites[id] = sprite
    return sprite
  end

  def pbAddPlane(id, filename, viewport)
    sprite = AnimatedPlane.new(viewport)
    sprite.setBitmap(filename) if filename
    @sprites[id] = sprite
    return sprite
  end

  def pbDisposeSprites
    pbDisposeSpriteHash(@sprites)
    @commandWindow.dispose if @commandWindow && @commandWindow.respond_to?(:dispose)
    @fightWindow.dispose if @fightWindow && @fightWindow.respond_to?(:dispose)
    @bagWindow.dispose if @bagWindow && @bagWindow.respond_to?(:dispose)
    @targetWindow.dispose if @targetWindow && @targetWindow.respond_to?(:dispose) && @targetWindow.is_a?(TargetWindowEBDX)
    @playerLineUp.dispose if @playerLineUp && @playerLineUp.respond_to?(:dispose)
    @opponentLineUp.dispose if @opponentLineUp && @opponentLineUp.respond_to?(:dispose)
  end

  #=============================================================================
  #  Databox visibility
  #=============================================================================
  def pbHideAllDataboxes(side = nil)
    return if @dataBoxesHidden
    @battlers.each_with_index do |b, i|
      next if !b || (!side.nil? && i%2 != side)
      @sprites["dataBox_#{i}"].visible = false if @sprites["dataBox_#{i}"]
    end
    @dataBoxesHidden = true
  end

  def pbShowAllDataboxes(side = nil)
    @battlers.each_with_index do |b, i|
      next if !b || (!side.nil? && i%2 != side)
      @sprites["dataBox_#{i}"].visible = true if @sprites["dataBox_#{i}"]
    end
    @dataBoxesHidden = false
  end

  #=============================================================================
  #  Selection
  #=============================================================================
  def pbSelectBattler(idxBattler, selectMode = 1)
    numWindows = @battle.sideSizes.max*2
    for i in 0...numWindows
      sel = (idxBattler.is_a?(Array)) ? !idxBattler[i].nil? : i == idxBattler
      selVal = (sel) ? selectMode : 0
      @sprites["dataBox_#{i}"].selected = selVal if @sprites["dataBox_#{i}"]
      @sprites["pokemon_#{i}"].selected = selVal if @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].respond_to?(:selected=)
    end
  end

  def pbDeselectAll(index = nil)
    @battle.battlers.each_with_index do |b, i|
      next if !b
      @sprites["dataBox_#{i}"].selected = false if @sprites["dataBox_#{i}"] && @sprites["dataBox_#{i}"].respond_to?(:selected=)
      @sprites["pokemon_#{i}"].selected = false if @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].respond_to?(:selected=)
    end
    @sprites["dataBox_#{index}"].selected = true if !index.nil? && @sprites["dataBox_#{index}"] && @sprites["dataBox_#{index}"].respond_to?(:selected=)
  end

  #=============================================================================
  #  Battle phases
  #=============================================================================
  def pbBeginCommandPhase
    @sprites["messageWindow"].text = "" if @sprites["messageWindow"]
  end

  def pbBeginAttackPhase
    pbSelectBattler(-1)
    pbShowWindow(MESSAGE_BOX)
  end

  def pbBeginEndOfRoundPhase
  end

  def pbEndBattle(_result)
    @abortable = false
    @battleEnd = true
    pbShowWindow(BLANK)
    pbBGMFade(1.0)
    pbFadeOutAndHide(@sprites)
    pbDisposeSprites
    # Clean up EBDX state
    EliteBattle.set(:nextVectors, [])
  end

  #=============================================================================
  #  Pokemon changes
  #=============================================================================
  def pbChangePokemon(idxBattler, pkmn)
    idxBattler = idxBattler.index if idxBattler.respond_to?(:index)
    pkmnSprite = @sprites["pokemon_#{idxBattler}"]
    shadowSprite = @sprites["shadow_#{idxBattler}"]
    back = !@battle.opposes?(idxBattler)
    shadowSprite.setPokemonBitmap(pkmn) if shadowSprite && shadowSprite.respond_to?(:setPokemonBitmap)
    if pkmnSprite
      if pkmnSprite.respond_to?(:setPokemonBitmapFiles)
        pkmnSprite.setPokemonBitmapFiles(pkmn, back)
      elsif pkmnSprite.respond_to?(:setPokemonBitmap)
        pkmnSprite.setPokemonBitmap(pkmn, back)
      end
      # CRITICAL: Call pbSetOrigin to set ox/oy anchor points correctly!
      pkmnSprite.pbSetOrigin if pkmnSprite.respond_to?(:pbSetOrigin)
    end
  end

  def pbResetMoveIndex(idxBattler)
    @lastMove[idxBattler] = 0
  end

  def pbSwapBattlerSprites(idxA, idxB)
    @sprites["pokemon_#{idxA}"], @sprites["pokemon_#{idxB}"] = @sprites["pokemon_#{idxB}"], @sprites["pokemon_#{idxA}"]
    @sprites["shadow_#{idxA}"], @sprites["shadow_#{idxB}"] = @sprites["shadow_#{idxB}"], @sprites["shadow_#{idxA}"]
    @lastCmd[idxA], @lastCmd[idxB] = @lastCmd[idxB], @lastCmd[idxA]
    @lastMove[idxA], @lastMove[idxB] = @lastMove[idxB], @lastMove[idxA]
    [idxA, idxB].each do |i|
      @sprites["pokemon_#{i}"].index = i if @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].respond_to?(:index=)
      @sprites["shadow_#{i}"].index = i if @sprites["shadow_#{i}"] && @sprites["shadow_#{i}"].respond_to?(:index=)
      @sprites["dataBox_#{i}"].battler = @battle.battlers[i] if @sprites["dataBox_#{i}"]

      # Use EBDX backdrop positioning instead of vanilla pbSetPosition
      if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler) && @sprites["pokemon_#{i}"]
        battlerPos = @sprites["battlebg"].battler(i) rescue nil
        if battlerPos
          sprite = @sprites["pokemon_#{i}"]
          sprite.x = battlerPos.x
          sprite.y = battlerPos.y + ebdxBattlerYOffset
          sprite.z = battlerPos.z rescue (100 + i)
          # Constant sprite zoom based on side
          baseZoom = 1.0
          sprite.zoom_x = baseZoom
          sprite.zoom_y = baseZoom
        end
      elsif @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].respond_to?(:pbSetPosition)
        # Fallback to KIF positioning if no backdrop
        @sprites["pokemon_#{i}"].pbSetPosition
      end

      # Shadow positioning
      if @sprites["shadow_#{i}"] && @sprites["shadow_#{i}"].respond_to?(:pbSetPosition)
        @sprites["shadow_#{i}"].pbSetPosition
      end
    end
    pbRefresh
  end

  #=============================================================================
  #  Party lineup
  #=============================================================================
  def inPartyAnimation?
    return @animations.length > 0
  end

  def pbShowPartyLineup(side)
    if side == 0 && @playerLineUp
      @playerLineUp.toggle = true if @playerLineUp.respond_to?(:toggle=)
    elsif side == 1 && @opponentLineUp
      @opponentLineUp.toggle = true if @opponentLineUp.respond_to?(:toggle=)
    end
  end

  #=============================================================================
  #  Helper methods
  #=============================================================================
  def playBattlerCry(battler)
    return if !battler
    pokemon = battler.displayPokemon rescue battler.pokemon
    return if !pokemon
    begin
      cry = GameData::Species.cry_filename_from_pokemon(pokemon)
      pbSEPlay(cry) if cry
    rescue
      GameData::Species.play_cry_from_pokemon(pokemon) rescue nil
    end
  end

  def shinyBattler?(battler)
    return false if !battler
    pokemon = battler.pokemon rescue nil
    return false if !pokemon
    return pokemon.shiny?
  end

  #=============================================================================
  #  Victory themes
  #=============================================================================
  def pbWildBattleSuccess
    @battleEnd = true
    bgm = "EBDX/Victory Against Wild"
    bgm = $PokemonGlobal.nextBattleME if $PokemonGlobal.nextBattleME
    if !@battle.opponent && @battlers[1]
      s = EliteBattle.get_data(@battlers[1].species, :Species, :VICTORYTHEME, (@battlers[1].form rescue 0)) rescue nil
      bgm = s if !s.nil?
    end
    pbBGMPlay(bgm)
  end

  def pbTrainerBattleSuccess
    @battleEnd = true
    bgm = "EBDX/Victory Against Trainer"
    bgm = $PokemonGlobal.nextBattleME.clone if $PokemonGlobal.nextBattleME
    if @battle.opponent
      s = EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :VICTORYTHEME, @battle.opponent[0]) rescue nil
      bgm = s if !s.nil?
    end
    pbBGMPlay(bgm)
  end

  #=============================================================================
  #  Sendout animations with player backsprite and pokeball
  #=============================================================================
  def pbSendOutBattlers(sendOuts, startBattle = false)
    return if sendOuts.length == 0
    @briefMessage = false
    @sendingOut = true

    # Determine if this is a player sendout or opponent sendout
    playerSendout = sendOuts.any? { |pair| !@battle.opposes?(pair[0]) }

    if playerSendout
      playerBattlerSendOut(sendOuts, startBattle)
    else
      # Opponent sendout - simpler animation
      opponentBattlerSendOut(sendOuts, startBattle)
    end

    # CRITICAL: Set @sendingOut = false BEFORE vector reset and wait
    # This allows animateScene to update ALL Pokemon positions during camera transition
    @sendingOut = false
    @vector.reset if @vector.respond_to?(:reset)
    self.wait(12, true)

    # CRITICAL: Force position refresh for ALL Pokemon after sendout completes
    # This ensures both player AND enemy positions are correct for MAIN vector
    forceRefreshAllPositions
  end

  # Player sendout with backsprite and pokeball animation
  # EBDX style: zoom out first, then throw, then release
  def playerBattlerSendOut(sendOuts, startBattle = false)
    return if sendOuts.length == 0

    # Filter for player-side sendouts only
    playerSendouts = sendOuts.select { |pair| !@battle.opposes?(pair[0]) }
    return if playerSendouts.empty?

    # Get daylight tone for final Pokemon color
    daylightTone = Tone.new(0, 0, 0)
    if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:daylightTone)
      daylightTone = @sprites["battlebg"].daylightTone rescue Tone.new(0, 0, 0)
    end

    # Prepare Pokemon sprites and databoxes
    playerSendouts.each do |idxBattler, pkmn|
      next if !@sprites["pokemon_#{idxBattler}"]
      sprite = @sprites["pokemon_#{idxBattler}"]

      # Set Pokemon bitmap first (back sprite for player)
      if sprite.respond_to?(:setPokemonBitmap)
        sprite.setPokemonBitmap(pkmn, true)
      end
      # CRITICAL: Call pbSetOrigin to set ox/oy anchor points correctly!
      sprite.pbSetOrigin if sprite.respond_to?(:pbSetOrigin)

      # Hide initially with white tone
      sprite.visible = false
      sprite.opacity = 255
      sprite.tone = Tone.new(255, 255, 255) if sprite.respond_to?(:tone=)

      # Render databox (but don't show yet)
      @sprites["dataBox_#{idxBattler}"].render if @sprites["dataBox_#{idxBattler}"] && @sprites["dataBox_#{idxBattler}"].respond_to?(:render)
    end

    # Check if trainer animation should be skipped (Multiplayer Options setting)
    skipTrainerAnim = defined?($PokemonSystem) &&
                      $PokemonSystem.respond_to?(:mp_skip_trainer_anim) &&
                      ($PokemonSystem.mp_skip_trainer_anim || 0) == 1

    #==========================================================================
    # PHASE 1: Vector animation + Player fade-in (EBDX: zoom out to SENDOUT)
    #==========================================================================
    if startBattle
      # Set vector to SENDOUT position
      v = EliteBattle.get_vector(:SENDOUT) rescue EliteBattle.get_vector(:MAIN, @battle)
      @vector.set(v)

      if skipTrainerAnim
        # Hide trainer sprites immediately and skip the 44-frame fade-in
        playerSendouts.each_with_index do |pair, m|
          next if !@sprites["player_#{m}"]
          @sprites["player_#{m}"].opacity = 0
          @sprites["player_#{m}"].visible = false
        end
        # Short wait so backdrop updates battler positions before PHASE 3
        8.times { self.wait(1, true) }
      else
        # Reset player sprites
        playerSendouts.each_with_index do |pair, m|
          next if !@sprites["player_#{m}"]
          @sprites["player_#{m}"].opacity = 0
          if @sprites["player_#{m}"].bitmap
            frameWidth = @sprites["player_#{m}"].bitmap.width / 5
            if frameWidth > 0
              @sprites["player_#{m}"].src_rect.width = frameWidth
              @sprites["player_#{m}"].src_rect.x = 0
            end
          end
        end

        # EBDX: 44 frames for player fade-in + vector zoom animation
        44.times do |i|
          playerSendouts.each_with_index do |pair, m|
            next if !@sprites["player_#{m}"]
            @sprites["player_#{m}"].opacity += 6 if @sprites["player_#{m}"].opacity < 255
          end
          self.wait(1, true)
        end
      end
    else
      # Mid-battle sendout: 20 frames
      v = EliteBattle.get_vector(:MAIN, @battle)
      @vector.set(v)
      20.times { self.wait(1, true) }
    end

    #==========================================================================
    # PHASE 2: Player throw animation (at zoomed out position)
    #==========================================================================
    if startBattle && !skipTrainerAnim
      # Throw animation frames (7 frames for wind-up)
      7.times do |j|
        playerSendouts.each_with_index do |pair, m|
          next if !@sprites["player_#{m}"]
          if j == 0 && @sprites["player_#{m}"].bitmap
            frameWidth = @sprites["player_#{m}"].bitmap.width / 5
            @sprites["player_#{m}"].src_rect.x = frameWidth if frameWidth > 0
          end
          @sprites["player_#{m}"].x -= 2 if j > 0
        end
        self.wait(1, false)
      end
      self.wait(6, true)

      # Throw release (6 frames)
      6.times do |j|
        playerSendouts.each_with_index do |pair, m|
          next if !@sprites["player_#{m}"]
          if @sprites["player_#{m}"].bitmap && j % 2 == 0
            frameWidth = @sprites["player_#{m}"].bitmap.width / 5
            if frameWidth > 0
              currentFrame = (@sprites["player_#{m}"].src_rect.x / frameWidth).to_i
              nextFrame = [currentFrame + 1, 4].min
              @sprites["player_#{m}"].src_rect.x = nextFrame * frameWidth
            end
          end
          @sprites["player_#{m}"].x += 3 if j < 4
        end
        self.wait(1, false)
      end
    end

    # Play throw sound
    pbSEPlay("EBDX/Throw") rescue pbSEPlay("Battle throw")

    #==========================================================================
    # PHASE 3: Pokeball trajectory (at zoomed out position)
    #==========================================================================
    pokeballs = {}
    ballFrame = 0

    # Calculate zoom factor for ball size
    addzoom = 1.0
    if @vector && @vector.respond_to?(:zoom1) && startBattle
      addzoom = ((@vector.zoom1 ** 0.75) * 2) rescue 2.0
    end

    playerSendouts.each do |idxBattler, pkmn|
      ballType = pkmn.poke_ball rescue :POKEBALL
      ballPath = "Graphics/EBDX/Pictures/Pokeballs/#{ballType}"
      ballPath = "Graphics/EBDX/Pictures/Pokeballs/POKEBALL" if !pbResolveBitmap(ballPath)
      next if !pbResolveBitmap(ballPath)

      pokeballs[idxBattler] = Sprite.new(@viewport)
      pokeballs[idxBattler].bitmap = pbBitmap(ballPath) rescue nil
      next if !pokeballs[idxBattler].bitmap

      pokeballs[idxBattler].src_rect.set(0, 0, 41, 40)
      pokeballs[idxBattler].ox = 20
      pokeballs[idxBattler].oy = 20
      pokeballs[idxBattler].z = 19
      pokeballs[idxBattler].opacity = 0
      pokeballs[idxBattler].zoom_x = 0.75 * addzoom
      pokeballs[idxBattler].zoom_y = 0.75 * addzoom
    end

    # CRITICAL: Force backdrop update to ensure battler positions are calculated
    # with the current vector (SENDOUT) before we read target positions
    if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)
      @sprites["battlebg"].update
    end

    # Get target positions from backdrop battler positions
    targetPositions = {}
    playerSendouts.each do |idxBattler, pkmn|
      if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
        battlerPos = @sprites["battlebg"].battler(idxBattler) rescue nil
        if battlerPos
          targetPositions[idxBattler] = { x: battlerPos.x, y: battlerPos.y + ebdxBattlerYOffset }
        else
          targetPositions[idxBattler] = { x: Graphics.width / 4, y: Graphics.height / 2 }
        end
      else
        targetPositions[idxBattler] = { x: Graphics.width / 4, y: Graphics.height / 2 }
      end
    end

    # Ball trajectory animation (48 frames like EBDX)
    48.times do |j|
      ballFrame = (ballFrame + 1) % 8

      playerSendouts.each do |idxBattler, pkmn|
        next if !pokeballs[idxBattler]

        # Animate ball spinning
        pokeballs[idxBattler].src_rect.y = ballFrame * 40

        if j < 28
          # Calculate arc positions
          targetX = targetPositions[idxBattler][:x]
          targetY = targetPositions[idxBattler][:y] - 120

          startX = startBattle ? 80 : 100
          startY = startBattle ? Graphics.height - 40 : Graphics.height - 70

          t = j / 27.0
          pokeballs[idxBattler].x = startX + (targetX - startX) * t
          # Parabolic arc with higher peak
          arcHeight = startBattle ? 160 : 120
          pokeballs[idxBattler].y = startY + (targetY - startY) * t - arcHeight * Math.sin(t * Math::PI)
        end

        pokeballs[idxBattler].opacity += 42 if pokeballs[idxBattler].opacity < 255
      end

      self.wait(1, false)
    end

    #==========================================================================
    # PHASE 4: Ball burst and Pokemon release
    #==========================================================================
    pbSEPlay("Battle recall") rescue nil

    # Create ball bursts and show Pokemon
    ballBursts = {}
    playerSendouts.each do |idxBattler, pkmn|
      playBattlerCry(@battlers[idxBattler]) if respond_to?(:playBattlerCry)

      next if !pokeballs[idxBattler]

      burstX = pokeballs[idxBattler].x
      burstY = pokeballs[idxBattler].y
      ballType = pkmn.poke_ball rescue :POKEBALL

      # Create burst effect (at zoomed out scale)
      burstScale = startBattle ? 1.0 : 2.0
      if defined?(EBBallBurst)
        ballBursts[idxBattler] = EBBallBurst.new(@viewport, burstX, burstY, 29, burstScale, ballType)
      end

      # Make Pokemon visible at burst location
      sprite = @sprites["pokemon_#{idxBattler}"]
      next if !sprite
      sprite.visible = true
      sprite.x = burstX  # Set X position to where ball burst
      sprite.y = burstY  # Start at burst location (ball already lands above final position)
      sprite.zoom_x = 0
      sprite.zoom_y = 0

      # Show databox
      @sprites["dataBox_#{idxBattler}"].appear if @sprites["dataBox_#{idxBattler}"] && @sprites["dataBox_#{idxBattler}"].respond_to?(:appear)
    end

    # Calculate zoom curve for Pokemon appearing (20 frames)
    20.times do |j|
      playerSendouts.each_with_index do |pair, m|
        next if !@sprites["player_#{m}"] || !startBattle
        @sprites["player_#{m}"].opacity -= 13 if @sprites["player_#{m}"].opacity > 0
      end

      playerSendouts.each do |idxBattler, pkmn|
        # Update ball bursts
        if ballBursts[idxBattler]
          ballBursts[idxBattler].update
        end

        # Fade out pokeball
        if pokeballs[idxBattler] && j >= 4
          pokeballs[idxBattler].opacity -= 51
        end

        next if !@sprites["pokemon_#{idxBattler}"]
        sprite = @sprites["pokemon_#{idxBattler}"]
        next if j < 4

        # Zoom in Pokemon: simple 0 → 1.0 for KIF sprites
        # (Don't use EBDX zoom formula - KIF sprites handle their own size)
        zoomFactor = (j - 4) / 15.0
        zoomFactor = [zoomFactor, 1.0].min
        sprite.zoom_x = zoomFactor
        sprite.zoom_y = zoomFactor

        # Show databox
        @sprites["dataBox_#{idxBattler}"].show if @sprites["dataBox_#{idxBattler}"] && @sprites["dataBox_#{idxBattler}"].respond_to?(:show)
      end

      self.wait(1, false)
    end

    # Continue burst animation (22 frames) + tone fade
    22.times do |j|
      playerSendouts.each do |idxBattler, pkmn|
        # Update bursts
        if ballBursts[idxBattler]
          ballBursts[idxBattler].update
          ballBursts[idxBattler].dispose if j == 21
        end

        next if !@sprites["pokemon_#{idxBattler}"]
        sprite = @sprites["pokemon_#{idxBattler}"]
        next if j < 8

        # Fade tone from white (255) to normal (0) - NOT to night tint!
        # Pokemon sprites should NOT have night tint applied
        if sprite.tone
          sprite.tone.red -= 51 if sprite.tone.red > 0
          sprite.tone.green -= 51 if sprite.tone.green > 0
          sprite.tone.blue -= 51 if sprite.tone.blue > 0
        end
      end
      self.wait(1, false)
    end

    #==========================================================================
    # PHASE 5: Pokemon drop to final position + cleanup
    #==========================================================================
    if startBattle
      # Temporarily disable sendingOut flag so animateScene can update positions
      # This ensures Pokemon positions follow the camera as it transitions
      @sendingOut = false

      # Drop animation (12 frames) - positions update dynamically from backdrop
      12.times do |j|
        # Force backdrop update to get current positions
        @sprites["battlebg"].update if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)

        playerSendouts.each do |idxBattler, pkmn|
          next if !@sprites["pokemon_#{idxBattler}"]
          sprite = @sprites["pokemon_#{idxBattler}"]

          # Get CURRENT position from backdrop (not stale targetPositions)
          if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
            battlerPos = @sprites["battlebg"].battler(idxBattler) rescue nil
            if battlerPos
              # Update X position to follow camera
              sprite.x = battlerPos.x
              # Y position: interpolate down to final position
              finalY = battlerPos.y + ebdxBattlerYOffset
              if sprite.y < finalY
                sprite.y += 10
                sprite.y = finalY if sprite.y > finalY
              end
              # Constant sprite zoom (player side = 1.0)
              baseZoom = 1.0
              sprite.zoom_x = baseZoom
              sprite.zoom_y = baseZoom
            end
          end
        end
        self.wait(1, true)
      end
      # NOTE: Keep @sendingOut = false so positions update during camera transition to MAIN
    end

    # Final cleanup
    pokeballs.each { |idx, ball| ball.dispose if ball && !ball.disposed? }
    ballBursts.each_value { |burst| burst.dispose if burst && burst.respond_to?(:dispose) && !burst.disposed? }

    # Force backdrop update to ensure positions are current for MAIN vector
    if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:update)
      @sprites["battlebg"].update
    end

    # Ensure final state - EBDX positioning with custom zoom
    playerSendouts.each do |idxBattler, pkmn|
      next if !@sprites["pokemon_#{idxBattler}"]
      sprite = @sprites["pokemon_#{idxBattler}"]

      # CUSTOM EBDX POSITIONING - Use backdrop battler position with zoom formula
      if @sprites["battlebg"] && @sprites["battlebg"].respond_to?(:battler)
        battlerPos = @sprites["battlebg"].battler(idxBattler) rescue nil
        if battlerPos
          sprite.x = battlerPos.x
          sprite.y = battlerPos.y + ebdxBattlerYOffset
          sprite.z = battlerPos.z rescue (100 + idxBattler)
          # Constant sprite zoom (player side = 1.0)
          sprite.zoom_x = 1.0
          sprite.zoom_y = 1.0
        end
      else
        # Fallback to KIF positioning
        sprite.zoom_x = 1.0
        sprite.zoom_y = 1.0
        sprite.pbSetPosition if sprite.respond_to?(:pbSetPosition)
      end

      # Normal tone (0,0,0,0) - Pokemon sprites should NOT have night tint
      sprite.tone = Tone.new(0, 0, 0, 0) if sprite.respond_to?(:tone=)

      # Cry already played in PHASE 4 (after ball burst) - don't play again

      # Shiny animation
      if pkmn.shiny? && ($PokemonSystem.battlescene == 0)
        pbCommonAnimation("Shiny", @battlers[idxBattler], nil) rescue nil
      end
    end

    @firstsendout = false
    # Mark intro as done after first sendout completes
    # This allows position updates in animateScene to work normally
    @introdone = true if startBattle
  end

  # Opponent sendout (simpler animation)
  def opponentBattlerSendOut(sendOuts, startBattle = false)
    # Hide trainer sprites (vanilla uses TrainerFadeAnimation for this)
    if @battle.opponent
      # Fade out trainer sprites over 16 frames
      16.times do |i|
        @battle.opponent.length.times do |t|
          next if !@sprites["trainer_#{t}"]
          @sprites["trainer_#{t}"].opacity -= 16
        end
        self.wait(1, true)
      end
      # Ensure fully hidden
      @battle.opponent.length.times do |t|
        next if !@sprites["trainer_#{t}"]
        @sprites["trainer_#{t}"].visible = false
        @sprites["trainer_#{t}"].opacity = 0
      end
    end

    sendOuts.each do |idxBattler, pkmn|
      next if !@sprites["pokemon_#{idxBattler}"]
      sprite = @sprites["pokemon_#{idxBattler}"]

      if sprite.respond_to?(:setPokemonBitmap)
        sprite.setPokemonBitmap(pkmn, false)  # false = front sprite for opponent
      end
      # CRITICAL: Call pbSetOrigin to set ox/oy anchor points correctly!
      sprite.pbSetOrigin if sprite.respond_to?(:pbSetOrigin)
      sprite.visible = true
      sprite.opacity = 255
      sprite.tone = Tone.new(0, 0, 0, 0) if sprite.respond_to?(:tone=)

      # Show databox
      @sprites["dataBox_#{idxBattler}"].render if @sprites["dataBox_#{idxBattler}"] && @sprites["dataBox_#{idxBattler}"].respond_to?(:render)
      @sprites["dataBox_#{idxBattler}"].appear if @sprites["dataBox_#{idxBattler}"] && @sprites["dataBox_#{idxBattler}"].respond_to?(:appear)

      # Play cry
      GameData::Species.play_cry_from_pokemon(pkmn) rescue nil

      # Shiny animation
      if pkmn.shiny? && ($PokemonSystem.battlescene == 0)
        pbCommonAnimation("Shiny", @battlers[idxBattler], nil) rescue nil
      end
    end
  end

  #=============================================================================
  #  Recall animation — Full EBDX burst animation
  #  Source: EBDX reference + 009_EBDX_SceneAnimations.rb
  #=============================================================================
  def pbRecall(idxBattler)
    return if !@sprites["pokemon_#{idxBattler}"]
    battler = @battle.battlers[idxBattler]
    return if battler && battler.fainted?
    # Get ball type for burst color
    balltype = :POKEBALL
    begin
      balltype = battler.pokemon.poke_ball if battler && battler.pokemon
    rescue
      balltype = :POKEBALL
    end
    poke = @sprites["pokemon_#{idxBattler}"]
    # Skip animation if Pokemon is hidden
    isHidden = poke.respond_to?(:hidden) && poke.hidden
    poke.resetParticles if poke.respond_to?(:resetParticles)
    pbSEPlay("Battle recall") if !isHidden
    zoom = poke.zoom_x / 20.0
    @sprites["dataBox_#{idxBattler}"].visible = false if @sprites["dataBox_#{idxBattler}"]
    # Create ball burst at Pokemon position
    ballburst = EBBallBurst.new(poke.viewport, poke.x, poke.y, 29, poke.zoom_x, balltype)
    ballburst.recall if !isHidden
    # 32-frame animation: white tone + shrink + databox slide
    for i in 0...32
      next if isHidden
      if i < 20
        poke.tone.red += 25.5
        poke.tone.green += 25.5
        poke.tone.blue += 25.5
        # Slide databox out
        if @sprites["dataBox_#{idxBattler}"]
          if idxBattler % 2 == 0  # Player side slides right
            @sprites["dataBox_#{idxBattler}"].x += 26
          else  # Enemy side slides left
            @sprites["dataBox_#{idxBattler}"].x -= 26
          end
          @sprites["dataBox_#{idxBattler}"].opacity -= 25.5
        end
        poke.zoom_x -= zoom
        poke.zoom_y -= zoom
      end
      ballburst.update
      self.wait
    end
    ballburst.dispose
    poke.visible = false
    # Restore low HP BGM if applicable
    setBGMLowHP(false) if respond_to?(:setBGMLowHP)
  end

  #=============================================================================
  #  Faint animation (simplified)
  #=============================================================================
  def pbFaintBattler(battler)
    idxBattler = battler.index
    return if !@sprites["pokemon_#{idxBattler}"]
    # Play cry
    GameData::Species.play_cry_from_pokemon(battler.pokemon, 100, 75) rescue nil
    # Fade out
    16.times do
      @sprites["pokemon_#{idxBattler}"].opacity -= 16
      self.wait(1, true)
    end
    @sprites["pokemon_#{idxBattler}"].visible = false
    @sprites["pokemon_#{idxBattler}"].opacity = 255
    @sprites["dataBox_#{idxBattler}"].visible = false if @sprites["dataBox_#{idxBattler}"]
  end

  #=============================================================================
  #  Damage animations
  #=============================================================================
  def pbDamageAnimation(battler, effectiveness = 0)
    return if !battler || !@sprites["pokemon_#{battler.index}"]
    sprite = @sprites["pokemon_#{battler.index}"]
    # Flash red
    8.times do |i|
      sprite.visible = (i % 2 == 0)
      self.wait(2)
    end
    sprite.visible = true
  end

  def pbHitAndHPLossAnimation(targets)
    @briefMessage = false

    # EBDX ATTACK ZOOM: Zoom to first target during damage
    firstTarget = nil
    targets.each do |t|
      next if !t[0] || t[0].damageState.unaffected
      firstTarget = t[0]
      break
    end

    if firstTarget && @vector && !EliteBattle::DISABLE_SCENE_MOTION &&
        ($PokemonSystem.mp_ebdx_zoom_disabled || 0) == 0
      targetIsPlayer = !@battle.opposes?(firstTarget.index)
      targetVector = getAttackVector(firstTarget.index, targetIsPlayer)
      @vector.inc = 0.3  # Quick zoom to target for impact
      @vector.force
      @vector.set(targetVector)
    end

    # Wait for zoom to partially complete before damage (8 frames)
    8.times { self.wait(1, true) } if respond_to?(:wait)

    # Prepare damage effects
    effect = []
    indexes = []
    targets.each do |t|
      next if !t[0] || t[0].damageState.unaffected
      effect.push(t[2] || 0)  # Type modifier (0=normal, 1=weak, 2=super)
      indexes.push(t[0].index)
      # Trigger damage tint on databox
      databox = @sprites["dataBox_#{t[0].index}"]
      if databox
        databox.damage if databox.respond_to?(:damage)
        databox.animateHP(t[1], t[0].hp) if databox.respond_to?(:animateHP)
      end
    end
    # Play damage SE
    maxEffect = effect.max || 0
    case maxEffect
    when 0; pbSEPlay("Battle damage normal")
    when 1; pbSEPlay("Battle damage weak")
    when 2; pbSEPlay("Battle damage super")
    end
    # Do damage animation (sprite blink)
    targets.each do |t|
      next if !t[0] || t[0].damageState.unaffected
      pbDamageAnimation(t[0], t[0].damageState.typeMod)
    end
    # Wait for HP animations to complete
    loop do
      pbUpdate
      allDone = true
      targets.each do |t|
        next if !t[0] || t[0].damageState.unaffected
        databox = @sprites["dataBox_#{t[0].index}"]
        next if !databox || !databox.respond_to?(:animatingHP)
        if databox.animatingHP
          allDone = false
          break
        end
      end
      break if allDone
    end

    # EBDX ATTACK ZOOM: Reset to main vector after damage display
    if @vector && !EliteBattle::DISABLE_SCENE_MOTION
      @vector.inc = 0.2
      @vector.reset
      # Wait a bit for reset animation
      6.times { self.wait(1, true) }
    end

    # Force refresh ALL positions after damage to ensure correct placement
    forceRefreshAllPositions
  end

  def pbHPChanged(battler, oldhp, anim = false)
    return if !battler
    databox = @sprites["dataBox_#{battler.index}"]
    if databox && databox.respond_to?(:animateHP)
      databox.animateHP(oldhp, battler.hp)
      # Wait for animation to complete
      while databox.respond_to?(:animatingHP) && databox.animatingHP
        pbUpdate
      end
    end
  end

  #=============================================================================
  #  Attack zoom helper - Get vector for zooming on a battler
  #  Returns a more dramatic zoom vector for noticeable camera movement
  #=============================================================================
  def getAttackVector(battlerIndex, isPlayerSide)
    # Use custom attack vectors that zoom in more dramatically than default
    # Format: x, y, angle, scale, zoom1, zoom2
    if isPlayerSide
      # Zoom on player's Pokemon (back sprite side)
      # More zoomed in than PLAYER vector for dramatic effect
      # Shift camera left and down to focus on player side
      vector = [180, 310, 22, 200, 1.3, 1]
    else
      # Zoom on enemy Pokemon (front sprite side)
      # More zoomed in than ENEMY vector for dramatic effect
      # Shift camera right and up to focus on enemy side
      vector = [60, 400, 32, 360, 1.4, 1]
    end
    return vector
  end

  #=============================================================================
  #  Animation playback - EBDX animations with vanilla fallback
  #=============================================================================
  # Override to try EBDX custom animations first, fall back to vanilla if none exist
  def pbAnimation(moveID, user, targets, hitNum = 0)
    # Skip if animations are disabled
    return if $PokemonSystem.battlescene != 0

    userIndex = user ? user.index : 0
    targetIndex = if targets.is_a?(Array)
      targets.empty? ? userIndex : targets[0].index
    elsif targets
      targets.index
    else
      userIndex
    end
    userIsPlayer = user ? !@battle.opposes?(userIndex) : true

    # EBDX ATTACK ZOOM: Zoom in on attacker before animation
    if @vector && !EliteBattle::DISABLE_SCENE_MOTION &&
        ($PokemonSystem.mp_ebdx_zoom_disabled || 0) == 0
      attackerVector = getAttackVector(userIndex, userIsPlayer)
      @vector.inc = 0.25  # Faster zoom for more noticeable effect
      @vector.force
      @vector.set(attackerVector)
      # Wait for zoom to complete (16 frames = ~0.4 sec at 40fps)
      16.times { self.wait(1, true) }
    end

    # Try EBDX animation first
    if EBDXToggle.enabled? && defined?(EliteBattle) && EliteBattle.respond_to?(:playMoveAnimation)
      begin
        species = user ? user.species : nil

        # Debug: Log animation attempt
        MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbAnimation called: moveID=#{moveID.inspect}, species=#{species.inspect}") if defined?(MultiplayerDebug)

        # playMoveAnimation returns false if no EBDX animation exists
        played = EliteBattle.playMoveAnimation(moveID, self, userIndex, targetIndex, hitNum, false, species)
        MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbAnimation result: #{played}") if defined?(MultiplayerDebug)
        if played
          # EBDX animation played - fast camera return + cleanup
          if @vector && !EliteBattle::DISABLE_SCENE_MOTION
            @vector.reset        # Sets target to MAIN (resets inc to 0.2)
            @vector.inc = 0.5    # Override: fast return (99.9% settled in 10 frames)
            10.times { self.wait(1, true) }
          end
          # Safety: ensure viewport is clean after animation
          @viewport.color = Color.new(0, 0, 0, 0) if @viewport rescue nil
          forceRefreshAllPositions
          return
        end
      rescue => e
        # Log error but continue to vanilla fallback
        MultiplayerDebug.warn(EBDX_DEBUG_TAG, "pbAnimation ERROR: #{e.message}") if defined?(MultiplayerDebug)
        MultiplayerDebug.warn(EBDX_DEBUG_TAG, "Backtrace: #{e.backtrace[0..3].join("\n")}") if defined?(MultiplayerDebug)
        # Safety: ensure viewport is clean even after crash
        @viewport.color = Color.new(0, 0, 0, 0) if @viewport rescue nil
      end
    else
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbAnimation SKIPPED: toggle=#{EBDXToggle.enabled?}") if defined?(MultiplayerDebug)
    end

    # Fall back to vanilla animation
    super(moveID, user, targets, hitNum)

    # EBDX ATTACK ZOOM: Fast camera return after vanilla animation
    if @vector && !EliteBattle::DISABLE_SCENE_MOTION
      @vector.inc = 0.5  # Fast return
      @vector.reset
      10.times { self.wait(1, true) }
    end

    # Safety: ensure viewport is clean
    @viewport.color = Color.new(0, 0, 0, 0) if @viewport rescue nil

    # Force refresh ALL positions after animation to ensure correct placement
    forceRefreshAllPositions
  end

  # Override common animation to try EBDX first
  def pbCommonAnimation(animName, user = nil, target = nil)
    return if nil_or_empty?(animName)

    # Try EBDX common animation first
    if EBDXToggle.enabled? && defined?(EliteBattle) && EliteBattle.respond_to?(:playCommonAnimation)
      begin
        userIndex = user ? user.index : 0
        targetIndex = target ? (target.is_a?(Array) ? target[0].index : target.index) : userIndex
        symbol = animName.upcase.to_sym

        # Debug: Log animation attempt
        MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbCommonAnimation called: #{animName} -> #{symbol}, userIndex=#{userIndex}, targetIndex=#{targetIndex}") if defined?(MultiplayerDebug)

        # playCommonAnimation returns false if no EBDX animation exists
        played = EliteBattle.playCommonAnimation(symbol, self, userIndex, targetIndex, 0)
        MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbCommonAnimation result: #{played}") if defined?(MultiplayerDebug)
        return if played  # EBDX animation played successfully
      rescue => e
        # Log error but continue to vanilla fallback
        MultiplayerDebug.warn(EBDX_DEBUG_TAG, "pbCommonAnimation ERROR: #{e.message}") if defined?(MultiplayerDebug)
        MultiplayerDebug.warn(EBDX_DEBUG_TAG, "Backtrace: #{e.backtrace[0..3].join("\n")}") if defined?(MultiplayerDebug)
      end
    else
      MultiplayerDebug.info(EBDX_DEBUG_TAG, "pbCommonAnimation SKIPPED: toggle=#{EBDXToggle.enabled?}, EliteBattle=#{defined?(EliteBattle)}") if defined?(MultiplayerDebug)
    end

    # Fall back to vanilla animation
    super(animName, user, target)
  end

  #=============================================================================
  #  Throw Pokeball — Full EBDX animation ported from reference
  #  Source: EBDX/Plugins/Elite Battle DX/[000] Scripts/Battle Scene Animations/Battler Capture.rb
  #=============================================================================
  def pbThrowAndDeflect(ball, targetBattler); end
  def pbHideCaptureBall(idxBattler); end

  def pbThrow(ball, shakes, critical, targetBattler, showPlayer = false)
    @orgPos = nil; @playerfix = false if @safaribattle
    ballframe = 0
    # Ball sprite setup
    bstr = "Graphics/EBDX/Pictures/Pokeballs/#{ball}"
    ballbmp = pbResolveBitmap(bstr) ? pbBitmap(bstr) : pbBitmap("Graphics/EBDX/Pictures/Pokeballs/POKEBALL")
    spritePoke = @sprites["pokemon_#{targetBattler}"]
    # Shadow sprite
    @sprites["ballshadow"] = Sprite.new(@viewport)
    @sprites["ballshadow"].bitmap = Bitmap.new(34, 34)
    @sprites["ballshadow"].bitmap.bmp_circle(Color.black)
    @sprites["ballshadow"].ox = @sprites["ballshadow"].bitmap.width/2
    @sprites["ballshadow"].oy = @sprites["ballshadow"].bitmap.height/2 + 2
    @sprites["ballshadow"].z = 32
    @sprites["ballshadow"].opacity = 255*0.25
    @sprites["ballshadow"].visible = false
    # Ball sprite
    @sprites["captureball"] = Sprite.new(@viewport)
    @sprites["captureball"].bitmap = ballbmp
    @sprites["captureball"].src_rect.set(0, ballframe*40, 41, 40)
    @sprites["captureball"].ox = 20
    @sprites["captureball"].oy = 20
    @sprites["captureball"].z = 32
    @sprites["captureball"].zoom_x = 4
    @sprites["captureball"].zoom_y = 4
    @sprites["captureball"].visible = false
    pokeball = @sprites["captureball"]
    shadow = @sprites["ballshadow"]
    # Position camera — use backdrop spoof to get target coordinates
    sx, sy = @sprites["battlebg"].spoof(EliteBattle.get_vector(:ENEMY), targetBattler)
    curve = calculateCurve(sx-260, sy-160, sx-60, sy-200, sx, sy-140, 24)
    # Position pokeball at start
    pokeball.x = sx - 260
    pokeball.y = sy - 100
    pokeball.visible = true
    shadow.x = pokeball.x
    shadow.y = pokeball.y
    shadow.zoom_x = 0
    shadow.zoom_y = 0
    shadow.visible = true
    # Throwing animation
    pbHideAllDataboxes(0)
    critical ? pbSEPlay("EBDX/Throw Critical") : pbSEPlay("EBDX/Throw")
    for i in 0...28
      @vector.set(EliteBattle.get_vector(:ENEMY)) if i == 4
      # Fade out player in safari battle
      if @safaribattle && i < 16
        @sprites["player_0"].x -= 75
        @sprites["player_0"].y += 38
        @sprites["player_0"].zoom_x += 0.125
        @sprites["player_0"].zoom_y += 0.125
      end
      # Increment ball frame (spinning)
      ballframe += 1
      ballframe = 0 if ballframe > 7
      if i < 24
        pokeball.x = curve[i][0]
        pokeball.y = curve[i][1]
        pokeball.zoom_x -= (pokeball.zoom_x - spritePoke.zoom_x)*0.2
        pokeball.zoom_y -= (pokeball.zoom_y - spritePoke.zoom_y)*0.2
        shadow.x = pokeball.x
        shadow.y = pokeball.y + 140 + 16 + (24-i)
        shadow.zoom_x += 0.8/24
        shadow.zoom_y += 0.3/24
      end
      pokeball.src_rect.set(0, ballframe*40, 41, 40)
      self.wait(1, true)
    end
    # Additional spin
    for i in 0...4
      pokeball.src_rect.set(0, (7+i)*40, 41, 40)
      self.wait
    end
    pbSEPlay("Battle recall")
    # Ball burst — Pokemon absorption
    pokeball.z = spritePoke.z-1; shadow.z = pokeball.z-1
    spritePoke.showshadow = false if spritePoke.respond_to?(:showshadow=)
    ballburst = EBBallBurst.new(pokeball.viewport, pokeball.x, pokeball.y, 50, @vector.zoom1, ball)
    ballburst.catching
    clearMessageWindow
    # Play burst animation + sprite zoom out
    for i in 0...32
      if i < 20
        spritePoke.zoom_x -= 0.075
        spritePoke.zoom_y -= 0.075
        spritePoke.tone.all += 25.5
        spritePoke.y -= 8
      elsif i == 20
        if spritePoke.respond_to?(:zoom=)
          spritePoke.zoom = 0
        else
          spritePoke.zoom_x = 0
          spritePoke.zoom_y = 0
        end
      end
      ballburst.update
      self.wait
    end
    ballburst.dispose
    spritePoke.y += 160
    # Reset ball frame
    pokeball.src_rect.y -= 40; self.wait
    pokeball.src_rect.y = 0; self.wait
    t = 0; ti = 51
    # Tone flash
    10.times do
      t += ti; ti = -51 if t >= 255
      pokeball.tone = Tone.new(t, t, t)
      self.wait
    end
    # Drop ball to floor
    pbSEPlay("Battle jump to ball")
    for i in 0...20
      pokeball.src_rect.y = 40*(((i-6)/2)+1) if i%2 == 0 && i >= 6
      pokeball.y += 7
      shadow.zoom_x += 0.01
      shadow.zoom_y += 0.01
      self.wait
    end
    pokeball.src_rect.y = 0
    pbSEPlay("Battle ball drop")
    # Bounce animation
    for i in 0...14
      pokeball.src_rect.y = 40*((i/2)+1) if i%2 == 0
      pokeball.y -= 6 if i < 7
      pokeball.y += 6 if i >= 7
      if i <= 7
        shadow.zoom_x -= 0.005
        shadow.zoom_y -= 0.005
      else
        shadow.zoom_x += 0.005
        shadow.zoom_y += 0.005
      end
      self.wait
    end
    pokeball.src_rect.y = 0
    pbSEPlay("Battle ball drop", 80)
    # Ball shake sequence
    [shakes, 3].min.times do
      self.wait(40)
      pbSEPlay("Battle ball shake")
      pokeball.src_rect.y = 11*40
      self.wait
      for i in 0...2
        2.times do
          pokeball.src_rect.y += 40*(i < 1 ? 1 : -1)
          self.wait
        end
      end
      pokeball.src_rect.y = 14*40
      self.wait
      for i in 0...2
        2.times do
          pokeball.src_rect.y += 40*(i < 1 ? 1 : -1)
          self.wait
        end
      end
      pokeball.src_rect.y = 0
      self.wait
    end
    # Escape if 3 or fewer shakes
    if shakes < 4
      clearMessageWindow
      self.wait(40)
      pokeball.src_rect.y = 9*40
      self.wait
      pokeball.src_rect.y += 40
      self.wait
      pbSEPlay("Battle recall")
      spritePoke.showshadow = true if spritePoke.respond_to?(:showshadow=)
      # Generate ball burst for escape
      ballburst = EBBallBurst.new(pokeball.viewport, pokeball.x, pokeball.y, 50, @vector.zoom1, ball)
      for i in 0...32
        if i < 20
          pokeball.opacity -= 25.5
          shadow.opacity -= 4
          spritePoke.zoom_x += 0.075
          spritePoke.zoom_y += 0.075
          spritePoke.tone.all -= 25.5 if spritePoke.tone.all > 0
        end
        ballburst.update
        self.wait
      end
      ballburst.dispose
      @vector.reset
      pbShowAllDataboxes(0)
      20.times do
        if @safaribattle
          @sprites["player_0"].x += 60
          @sprites["player_0"].y -= 30
          @sprites["player_0"].zoom_x -= 0.1
          @sprites["player_0"].zoom_y -= 0.1
        end
        self.wait(1, true)
      end
    else
      # Capture success animation
      clearMessageWindow
      @caughtBattler = @battle.pbParty(1)[targetBattler/2]
      spritePoke.visible = false
      spritePoke.resetParticles if spritePoke.respond_to?(:resetParticles)
      spritePoke.charged = false if spritePoke.respond_to?(:charged=)
      self.wait(40)
      pbSEPlay("Battle ball drop", 80)
      pokeball.color = Color.new(0, 0, 0, 0)
      fp = {}
      for j in 0...3
        fp["#{j}"] = Sprite.new(pokeball.viewport)
        fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebStar")
        fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
        fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
        fp["#{j}"].x = pokeball.x
        fp["#{j}"].y = pokeball.y
        fp["#{j}"].opacity = 0
        fp["#{j}"].z = pokeball.z + 1
      end
      for i in 0...16
        for j in 0...3
          fp["#{j}"].y -= [3,4,3][j]
          fp["#{j}"].x -= [3,0,-3][j]
          fp["#{j}"].opacity += 32*(i < 8 ? 1 : -1)
          fp["#{j}"].angle += [4,2,-4][j]
        end
        @sprites["dataBox_#{targetBattler}"].opacity -= 25.5 if @sprites["dataBox_#{targetBattler}"]
        pokeball.color.alpha += 8
        self.wait
      end
      # Dispose star sprites
      fp.each_value { |s| s.dispose if s && !s.disposed? }
      # If snagging opponent's battler
      if @battle.opponent
        5.times do
          pokeball.opacity -= 51
          shadow.opacity -= 13
          self.wait
        end
        @vector.reset
        pbShowAllDataboxes(0)
        self.wait(20, true)
      end
      spritePoke.clear if spritePoke.respond_to?(:clear)
    end
    @playerfix = true if @safaribattle
    self.briefmessage = true
  end
  attr_reader :caughtBattler

  #=============================================================================
  #  Capture success — plays ME and cleans up ball sprites
  #  Source: EBDX/Plugins/Elite Battle DX/[000] Scripts/Battle Scene Animations/Battler Capture.rb
  #=============================================================================
  def pbThrowSuccess
    return if @battle.opponent
    @briefmessage = true
    # Try to resolve species-specific capture ME
    me = "EBDX/Capture Success"
    begin
      sme = @caughtBattler ? EliteBattle.get_data(@caughtBattler.species, :Species, :CAPTUREME) : nil
      me = sme if !sme.nil?
    rescue
      # Fallback to default
    end
    # Play ME
    pbMEPlay(me)
    # Wait for audio to complete
    begin
      frames = (getPlayTime("Audio/ME/#{me}") * Graphics.frame_rate).ceil + 4
    rescue
      frames = Graphics.frame_rate * 4  # Fallback: 4 seconds
    end
    self.wait(frames)
    pbMEStop
    # Fade out ball + shadow
    5.times do
      @sprites["ballshadow"].opacity -= 16 if @sprites["ballshadow"]
      @sprites["captureball"].opacity -= 52 if @sprites["captureball"]
      self.wait
    end
    @sprites["ballshadow"].dispose if @sprites["ballshadow"]
    @sprites["captureball"].dispose if @sprites["captureball"]
    pbShowAllDataboxes(0)
    @vector.reset
  end

  #=============================================================================
  #  EXP bar
  #=============================================================================
  def pbEXPBar(battler, startExp, endExp, tempExp1, tempExp2)
    return if !battler
    dataBox = @sprites["dataBox_#{battler.index}"]
    return if !dataBox || !dataBox.respond_to?(:animateEXP)
    dataBox.refreshExpLevel if dataBox.respond_to?(:refreshExpLevel)
    expRange      = endExp - startExp
    barWidth      = dataBox.respond_to?(:expBarWidth) ? dataBox.expBarWidth : 100
    startExpLevel = expRange == 0 ? 0 : (tempExp1 - startExp) * barWidth / expRange
    endExpLevel   = expRange == 0 ? 0 : (tempExp2 - startExp) * barWidth / expRange
    dataBox.animateEXP(startExpLevel, endExpLevel)
    while dataBox.respond_to?(:animatingEXP) && dataBox.animatingEXP
      pbUpdate
    end
  end

  def pbLevelUp(*args)
    pbMEPlay("Evolution start") rescue nil
    pbWait(Graphics.frame_rate) rescue nil
  end

  #=============================================================================
  #  Ability splash (animated slide-in / linger / slide-out)
  #=============================================================================
  ABILITY_SLIDE_FRAMES  = 10   # ~0.25s slide in/out
  ABILITY_LINGER_FRAMES = 120  # ~3s visible
  ABILITY_FADE_FRAMES   = 10

  def pbShowAbilitySplash(battler, delay = false, logTrigger = true, abilityName = nil)
    return if !battler || !battler.abilityActive?
    spr = @sprites["abilityMessage"]
    return if !spr || !spr.bitmap
    # Redraw: background + border + text
    spr.bitmap.clear
    spr.bitmap.blt(0, 0, @abilityMsgBg, @abilityMsgBg.rect) if @abilityMsgBg
    abilityName ||= battler.abilityName
    pbSetSmallFont(spr.bitmap)
    textPos = [[_INTL("{1}'s {2}", battler.pbThis, abilityName),
                spr.bitmap.width / 2, 2, 2,
                Color.new(255, 255, 255), Color.new(32, 32, 32)]]
    pbDrawTextPositions(spr.bitmap, textPos)
    # Set up slide animation based on battler side
    side = battler.index % 2
    bw = spr.bitmap.width
    if side == 0  # Player side — slide from left
      @abilityMsgStartX  = -bw
      @abilityMsgTargetX = 10
      spr.y = 200
    else          # Opponent side — slide from right
      @abilityMsgStartX  = Graphics.width
      @abilityMsgTargetX = Graphics.width - bw - 10
      spr.y = 80
    end
    spr.x = @abilityMsgStartX
    spr.opacity = 0
    spr.visible = true
    spr.zoom_y = 1
    @abilityMsgState  = :slide_in
    @abilityMsgFrames = 0
    pbSEPlay("EBDX/Ability Message") rescue nil
  end

  def pbHideAbilitySplash(battler = nil)
    spr = @sprites["abilityMessage"]
    return if !spr
    if @abilityMsgState == :slide_in || @abilityMsgState == :linger
      @abilityMsgState  = :slide_out
      @abilityMsgFrames = 0
    elsif @abilityMsgState == :idle
      spr.visible = false
      spr.opacity = 0
    end
  end

  def pbReplaceAbilitySplash(battler)
    pbShowAbilitySplash(battler)
  end

  # Called every frame from pbFrameUpdate
  def updateAbilityMessage
    return if !@abilityMsgState || @abilityMsgState == :idle
    spr = @sprites["abilityMessage"]
    return if !spr
    @abilityMsgFrames += 1
    case @abilityMsgState
    when :slide_in
      t = [@abilityMsgFrames.to_f / ABILITY_SLIDE_FRAMES, 1.0].min
      ease = 1.0 - (1.0 - t) ** 2  # ease-out (decelerate)
      spr.x = (@abilityMsgStartX + (@abilityMsgTargetX - @abilityMsgStartX) * ease).to_i
      spr.opacity = (255 * t).to_i
      if @abilityMsgFrames >= ABILITY_SLIDE_FRAMES
        spr.x = @abilityMsgTargetX
        spr.opacity = 255
        @abilityMsgState  = :linger
        @abilityMsgFrames = 0
      end
    when :linger
      if @abilityMsgFrames >= ABILITY_LINGER_FRAMES
        @abilityMsgState  = :slide_out
        @abilityMsgFrames = 0
      end
    when :slide_out
      t = [@abilityMsgFrames.to_f / ABILITY_FADE_FRAMES, 1.0].min
      ease = t * t  # ease-in (accelerate)
      spr.x = (@abilityMsgTargetX + (@abilityMsgStartX - @abilityMsgTargetX) * ease).to_i
      spr.opacity = (255 * (1.0 - t)).to_i
      if @abilityMsgFrames >= ABILITY_FADE_FRAMES
        spr.visible = false
        spr.opacity = 0
        @abilityMsgState  = :idle
        @abilityMsgFrames = 0
      end
    end
  end

  #=============================================================================
  #  Command menu (delegates to EBDX or vanilla)
  #=============================================================================
  def pbCommandMenu(idxBattler, firstAction)
    # Clear any lingering message text before showing command menu
    clearMessageWindow(true) if respond_to?(:clearMessageWindow)
    if @commandWindow && @commandWindow.is_a?(CommandWindowEBDX)
      return pbCommandMenuEBDX(idxBattler, firstAction)
    else
      return pbCommandMenuVanilla(idxBattler, firstAction)
    end
  end

  def pbCommandMenuEBDX(idxBattler, firstAction)
    @commandWindow.refreshCommands(idxBattler) if @commandWindow.respond_to?(:refreshCommands)
    @commandWindow.showPlay if @commandWindow.respond_to?(:showPlay)
    @commandWindow.index = 0 if @commandWindow.respond_to?(:index=)
    numCommands = @commandWindow.indexes.length rescue 4
    ret = -1
    loop do
      pbUpdate(@commandWindow)
      # Handle directional input for navigation
      if Input.trigger?(Input::LEFT)
        @commandWindow.index = (@commandWindow.index - 1) % numCommands if @commandWindow.respond_to?(:index=)
        pbPlayCursorSE
      elsif Input.trigger?(Input::RIGHT)
        @commandWindow.index = (@commandWindow.index + 1) % numCommands if @commandWindow.respond_to?(:index=)
        pbPlayCursorSE
      elsif Input.trigger?(Input::UP)
        @commandWindow.index = (@commandWindow.index - 1) % numCommands if @commandWindow.respond_to?(:index=)
        pbPlayCursorSE
      elsif Input.trigger?(Input::DOWN)
        @commandWindow.index = (@commandWindow.index + 1) % numCommands if @commandWindow.respond_to?(:index=)
        pbPlayCursorSE
      elsif Input.trigger?(Input::USE)
        # Return the actual command index from @indexes array
        ret = @commandWindow.indexes[@commandWindow.index] rescue @commandWindow.index
        pbPlayDecisionSE
        break
      elsif Input.trigger?(Input::BACK)
        if firstAction
          pbPlayBuzzerSE
        else
          ret = -1
          pbPlayCancelSE
          break
        end
      end
    end
    @commandWindow.hidePlay if @commandWindow.respond_to?(:hidePlay)
    return ret
  end

  def pbCommandMenuVanilla(idxBattler, firstAction)
    pbShowWindow(COMMAND_BOX)
    cw = @sprites["commandWindow"]
    cw.setTexts([_INTL("Fight"), _INTL("Bag"), _INTL("Pokémon"), _INTL("Run")])  rescue nil
    cw.index = 0 rescue nil
    ret = -1
    loop do
      pbUpdate(cw)
      if Input.trigger?(Input::USE)
        ret = cw.index rescue 0
        pbPlayDecisionSE
        break
      elsif Input.trigger?(Input::BACK)
        if firstAction
          pbPlayBuzzerSE
        else
          ret = -1
          pbPlayCancelSE
          break
        end
      end
    end
    return ret
  end

  #=============================================================================
  #  Fight menu
  #=============================================================================
  def pbFightMenu(idxBattler, megaEvoPossible = false)
    # Clear any lingering message text before showing fight menu
    clearMessageWindow(true) if respond_to?(:clearMessageWindow)
    battler = @battle.battlers[idxBattler]
    cw = @fightWindow || @sprites["fightWindow"]

    # Setup the fight window
    if @fightWindow && @fightWindow.is_a?(FightWindowEBDX)
      @fightWindow.battler = battler if @fightWindow.respond_to?(:battler=)
      @fightWindow.generateButtons if @fightWindow.respond_to?(:generateButtons)
      @fightWindow.megaButton if megaEvoPossible && @fightWindow.respond_to?(:megaButton)
    end

    # Initialize move index (remember last selected move)
    moveIndex = 0
    if battler.moves[@lastMove[idxBattler]] && battler.moves[@lastMove[idxBattler]].id
      moveIndex = @lastMove[idxBattler]
    end

    # Set shift mode (for triple battles)
    cw.shiftMode = (@battle.pbCanShift?(idxBattler)) ? 1 : 0 if cw.respond_to?(:shiftMode=)

    # Set initial index and mega mode
    if cw.respond_to?(:setIndexAndMode)
      cw.setIndexAndMode(moveIndex, (megaEvoPossible) ? 1 : 0)
    else
      cw.index = moveIndex if cw.respond_to?(:index=)
    end

    numMoves = cw.nummoves rescue 4
    needFullRefresh = true
    needRefresh = false

    loop do
      # Show fight menu on first loop or after invalid selection
      if needFullRefresh
        if @fightWindow && @fightWindow.is_a?(FightWindowEBDX)
          @fightWindow.showPlay if @fightWindow.respond_to?(:showPlay)
        else
          pbShowWindow(FIGHT_BOX)
        end
        pbSelectBattler(idxBattler)
        needFullRefresh = false
      end

      # Refresh mega evolution display if needed
      if needRefresh
        if megaEvoPossible && cw.respond_to?(:mode=)
          newMode = (@battle.pbRegisteredMegaEvolution?(idxBattler)) ? 2 : 1
          cw.mode = newMode if newMode != cw.mode
        end
        needRefresh = false
      end

      oldIndex = cw.index rescue 0
      pbUpdate(cw)

      # Handle directional input for navigation
      if Input.trigger?(Input::LEFT)
        cw.index -= 1 if cw.respond_to?(:index=) && (cw.index & 1) == 1
        pbSEPlay("EBDX/SE_Select1", 80) if cw.index != oldIndex
      elsif Input.trigger?(Input::RIGHT)
        if battler.moves[cw.index + 1] && battler.moves[cw.index + 1].id
          cw.index += 1 if cw.respond_to?(:index=) && (cw.index & 1) == 0
        end
        pbSEPlay("EBDX/SE_Select1", 80) if cw.index != oldIndex
      elsif Input.trigger?(Input::UP)
        cw.index -= 2 if cw.respond_to?(:index=) && (cw.index & 2) == 2
        pbSEPlay("EBDX/SE_Select1", 80) if cw.index != oldIndex
      elsif Input.trigger?(Input::DOWN)
        if battler.moves[cw.index + 2] && battler.moves[cw.index + 2].id
          cw.index += 2 if cw.respond_to?(:index=) && (cw.index & 2) == 0
        end
        pbSEPlay("EBDX/SE_Select1", 80) if cw.index != oldIndex
      elsif Input.trigger?(Input::USE)
        # Confirm move selection - yield to the battle system's block
        pbSEPlay("EBDX/SE_Select2", 80)
        ret = cw.index rescue 0
        # Yield the selected index; if block returns true, we're done
        # If block returns false (invalid selection), continue loop
        if yield ret
          @lastMove[idxBattler] = ret
          @fightWindow.hidePlay if @fightWindow && @fightWindow.respond_to?(:hidePlay)
          return
        end
        needFullRefresh = true
        needRefresh = true
      elsif Input.trigger?(Input::BACK)
        # Cancel - yield -1
        pbSEPlay("EBDX/SE_Select3", 80)
        if yield -1
          @fightWindow.hidePlay if @fightWindow && @fightWindow.respond_to?(:hidePlay)
          return
        end
        needRefresh = true
      elsif Input.trigger?(Input::ACTION)
        # Toggle Mega Evolution
        if megaEvoPossible
          pbPlayDecisionSE
          # Update mega button visual state
          if @fightWindow && @fightWindow.respond_to?(:megaButtonTrigger)
            @fightWindow.megaButtonTrigger
          end
          if yield -2
            @fightWindow.hidePlay if @fightWindow && @fightWindow.respond_to?(:hidePlay)
            return
          end
          needRefresh = true
        end
      elsif Input.trigger?(Input::SPECIAL)
        # Shift command (triple battles)
        shiftMode = cw.respond_to?(:shiftMode) ? cw.shiftMode : 0
        if shiftMode > 0
          pbPlayDecisionSE
          if yield -3
            @fightWindow.hidePlay if @fightWindow && @fightWindow.respond_to?(:hidePlay)
            return
          end
          needRefresh = true
        end
      end
    end
  end

  #=============================================================================
  #  Item menu - Uses EBDX Bag UI overlay
  #=============================================================================
  def pbItemMenu(idxBattler, _firstAction)
    # Reset idle timer and vector
    @idleTimer = -1 if respond_to?(:idleTimer=)
    @vector.reset if @vector && @vector.respond_to?(:reset)
    @vector.inc = 0.2 if @vector && @vector.respond_to?(:inc=)

    # Update input to prevent misclicks
    Input.update

    # Use EBDX bag window if available
    if @bagWindow && @bagWindow.is_a?(BagWindowEBDX)
      # Show the EBDX bag UI
      @bagWindow.show if @bagWindow.respond_to?(:show)

      # Main selection loop
      loop do
        # Input and scene updates
        Input.update
        @bagWindow.update if @bagWindow.respond_to?(:update)

        # Check if finished (cancelled out)
        break if @bagWindow.finished

        # Check if item selected and confirmed
        if !@bagWindow.ret.nil? && @bagWindow.useItem?
          # Get item data
          item = GameData::Item.get(@bagWindow.ret)
          useType = item.battle_use

          # Handle different use types
          case useType
          when 1, 2, 3, 6, 7, 8   # Use on Pokémon/Pokémon's move/battler
            # For items that target Pokemon, we need party selection
            # Hide bag and show party screen
            @bagWindow.hide if @bagWindow.respond_to?(:hide)

            # Get player's party
            party = @battle.pbParty(idxBattler)
            partyPos = @battle.pbPartyOrder(idxBattler)
            partyStart, _partyEnd = @battle.pbTeamIndexRangeFromBattlerIndex(idxBattler)
            modParty = @battle.pbPlayerDisplayParty(idxBattler)

            # Auto-select if only one Pokemon
            if useType == 1 || useType == 6   # Use on Pokémon
              if @battle.pbTeamLengthFromBattlerIndex(idxBattler) == 1
                if yield item.id, useType, @battle.battlers[idxBattler].pokemonIndex, -1, @bagWindow
                  @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
                  return
                end
              end
            elsif useType == 3 || useType == 8   # Use on battler
              if @battle.pbPlayerBattlerCount == 1
                if yield item.id, useType, @battle.battlers[idxBattler].pokemonIndex, -1, @bagWindow
                  @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
                  return
                end
              end
            end

            # Start party screen for target selection
            pkmnScene = PokemonParty_Scene.new
            pkmnScreen = PokemonPartyScreen.new(pkmnScene, modParty)
            pkmnScreen.pbStartScene(_INTL("Use on which Pokémon?"), @battle.pbNumPositions(0, 0))
            idxParty = -1

            loop do
              pkmnScene.pbSetHelpText(_INTL("Use on which Pokémon?"))
              idxParty = pkmnScreen.pbChoosePokemon
              break if idxParty < 0

              idxPartyRet = -1
              partyPos.each_with_index do |pos, i|
                next if pos != idxParty + partyStart
                idxPartyRet = i
                break
              end
              next if idxPartyRet < 0

              pkmn = party[idxPartyRet]
              next if !pkmn || pkmn.egg?

              idxMove = -1
              if useType == 2 || useType == 7   # Use on Pokémon's move
                idxMove = pkmnScreen.pbChooseMove(pkmn, _INTL("Restore which move?"))
                next if idxMove < 0
              end

              if yield item.id, useType, idxPartyRet, idxMove, pkmnScene
                pkmnScene.pbEndScene
                @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
                $lastUsed = item.id
                return
              end
            end

            pkmnScene.pbEndScene
            # Cancelled - show bag again
            @bagWindow.show if @bagWindow.respond_to?(:show)

          when 4, 9   # Use on opposing battler (Poké Balls)
            idxTarget = -1
            if @battle.pbOpposingBattlerCount(idxBattler) == 1
              @battle.eachOtherSideBattler(idxBattler) { |b| idxTarget = b.index }
              if yield item.id, useType, idxTarget, -1, @bagWindow
                @bagWindow.hide if @bagWindow.respond_to?(:hide)
                @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
                $lastUsed = item.id
                return
              end
            else
              # Multiple targets - need target selection
              @bagWindow.hide if @bagWindow.respond_to?(:hide)
              idxTarget = pbChooseTarget(idxBattler, GameData::Target.get(:Foe))
              if idxTarget >= 0
                if yield item.id, useType, idxTarget, -1, self
                  @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
                  $lastUsed = item.id
                  return
                end
              end
              # Cancelled - show bag again
              @bagWindow.show if @bagWindow.respond_to?(:show)
            end

          when 5, 10   # Use no target
            if yield item.id, useType, idxBattler, -1, @bagWindow
              @bagWindow.hide if @bagWindow.respond_to?(:hide)
              @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
              $lastUsed = item.id
              return
            end
          end
        end

        # Animate scene
        animateScene if respond_to?(:animateScene)
        pbGraphicsUpdate if respond_to?(:pbGraphicsUpdate)
        Graphics.update
      end

      # Close out bag
      @bagWindow.clearSel if @bagWindow.respond_to?(:clearSel)
      @bagWindow.hide if @bagWindow.respond_to?(:hide)
    else
      # Fallback to vanilla bag screen
      visibleSprites = pbFadeOutAndHide(@sprites)
      itemScene = PokemonBag_Scene.new
      itemScreen = PokemonBagScreen.new(itemScene, $PokemonBag)
      item = itemScreen.pbChooseItemScreen(Proc.new { |itm|
        useType = GameData::Item.get(itm).battle_use
        next useType && useType > 0
      })
      pbFadeInAndShow(@sprites, visibleSprites)
      return item
    end
  end

  #=============================================================================
  #  Target selection - creates target texts and handles navigation
  #=============================================================================
  def pbCreateTargetTexts(idxBattler, target_data)
    texts = Array.new(@battle.battlers.length) do |i|
      next nil if !@battle.battlers[i]
      showName = false
      case target_data.id
      when :None, :User, :RandomNearFoe
        showName = (i == idxBattler)
      when :UserSide
        showName = !@battle.opposes?(i, idxBattler)
      when :FoeSide
        showName = @battle.opposes?(i, idxBattler)
      when :BothSides
        showName = true
      else
        showName = @battle.pbMoveCanTarget?(i, idxBattler, target_data)
      end
      next nil if !showName
      next (@battle.battlers[i].fainted?) ? "" : @battle.battlers[i].name
    end
    return texts
  end

  def pbFirstTarget(idxBattler, target_data)
    case target_data.id
    when :NearAlly
      @battle.eachSameSideBattler(idxBattler) do |b|
        next if b.index == idxBattler || !@battle.nearBattlers?(b, idxBattler)
        next if b.fainted?
        return b.index
      end
      @battle.eachSameSideBattler(idxBattler) do |b|
        next if b.index == idxBattler || !@battle.nearBattlers?(b, idxBattler)
        return b.index
      end
    when :NearFoe, :NearOther
      indices = @battle.pbGetOpposingIndicesInOrder(idxBattler)
      indices.each { |i| return i if @battle.nearBattlers?(i, idxBattler) && !@battle.battlers[i].fainted? }
      indices.each { |i| return i if @battle.nearBattlers?(i, idxBattler) }
    when :Foe, :Other
      indices = @battle.pbGetOpposingIndicesInOrder(idxBattler)
      indices.each { |i| return i if !@battle.battlers[i].fainted? }
      indices.each { |i| return i }
    end
    return idxBattler   # Target the user initially
  end

  def pbChooseTarget(idxBattler, target_data, visibleSprites = nil)
    # Create an array of battler names (only valid targets are named)
    texts = pbCreateTargetTexts(idxBattler, target_data)
    # Determine mode based on target_data
    mode = (target_data.num_targets == 1) ? 0 : 1

    # Hide the fight window when showing target selection
    if @fightWindow && @fightWindow.respond_to?(:hidePlay)
      @fightWindow.hidePlay
    elsif @sprites["fightWindow"]
      @sprites["fightWindow"].visible = false
    end

    if @targetWindow && @targetWindow.is_a?(TargetWindowEBDX)
      # Use EBDX target window
      @targetWindow.refresh(texts) if @targetWindow.respond_to?(:refresh)
      @targetWindow.index = pbFirstTarget(idxBattler, target_data)
      @targetWindow.showPlay if @targetWindow.respond_to?(:showPlay)
      cw = @targetWindow
    else
      pbShowWindow(TARGET_BOX)
      cw = @sprites["targetWindow"]
      cw.setDetails(texts, mode) if cw.respond_to?(:setDetails)
      cw.index = pbFirstTarget(idxBattler, target_data)
    end

    # Select initial battler/data box
    pbSelectBattler((mode == 0) ? cw.index : texts, 2)
    pbFadeInAndShow(@sprites, visibleSprites) if visibleSprites
    ret = -1

    loop do
      oldIndex = cw.index
      pbUpdate(cw)
      # Update selected target with navigation
      if mode == 0   # Choosing just one target, can change index
        if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
          inc = ((cw.index % 2) == 0) ? -2 : 2
          inc *= -1 if Input.trigger?(Input::RIGHT)
          indexLength = @battle.sideSizes[cw.index % 2] * 2
          newIndex = cw.index
          loop do
            newIndex += inc
            break if newIndex < 0 || newIndex >= indexLength
            next if texts[newIndex].nil?
            cw.index = newIndex
            break
          end
        elsif (Input.trigger?(Input::UP) && (cw.index % 2) == 0) ||
              (Input.trigger?(Input::DOWN) && (cw.index % 2) == 1)
          tryIndex = @battle.pbGetOpposingIndicesInOrder(cw.index)
          tryIndex.each do |idxBattlerTry|
            next if texts[idxBattlerTry].nil?
            cw.index = idxBattlerTry
            break
          end
        end
        if cw.index != oldIndex
          pbPlayCursorSE
          pbSelectBattler(cw.index, 2)   # Select the new battler/data box
        end
      end
      if Input.trigger?(Input::USE)
        ret = cw.index
        pbPlayDecisionSE
        break
      elsif Input.trigger?(Input::BACK)
        ret = -1
        pbPlayCancelSE
        break
      end
    end
    pbSelectBattler(-1)   # Deselect all battlers/data boxes
    @targetWindow.hidePlay if @targetWindow && @targetWindow.respond_to?(:hidePlay)
    return ret
  end

  #=============================================================================
  #  Opponent show/hide
  #=============================================================================
  def pbShowOpponent(idxTrainer)
    # Show opponent trainer sprite
    if @sprites["trainer_#{idxTrainer}"]
      @sprites["trainer_#{idxTrainer}"].visible = true
      @sprites["trainer_#{idxTrainer}"].opacity = 255
    end
  end

  def pbHideOpponent(idxTrainer)
    if @sprites["trainer_#{idxTrainer}"]
      @sprites["trainer_#{idxTrainer}"].visible = false
    end
  end

  #=============================================================================
  #  Party screen - Use KIF's native party screen
  #=============================================================================
  def pbPartyScreen(idxBattler, canCancel = false)
    # Fade out and hide all sprites
    visibleSprites = pbFadeOutAndHide(@sprites)

    # Get player's party
    partyPos = @battle.pbPartyOrder(idxBattler)
    partyStart, _partyEnd = @battle.pbTeamIndexRangeFromBattlerIndex(idxBattler)
    modParty = @battle.pbPlayerDisplayParty(idxBattler)

    # Start party screen
    scene = PokemonParty_Scene.new
    switchScreen = PokemonPartyScreen.new(scene, modParty)
    switchScreen.pbStartScene(_INTL("Choose a Pokémon."), @battle.pbNumPositions(0, 0))

    # Loop while in party screen
    loop do
      # Select a Pokémon
      scene.pbSetHelpText(_INTL("Choose a Pokémon."))
      idxParty = switchScreen.pbChoosePokemon
      if idxParty < 0
        next if !canCancel
        break
      end

      # Choose a command for the selected Pokémon
      cmdSwitch  = -1
      cmdSummary = -1
      commands = []
      commands[cmdSwitch = commands.length] = _INTL("Switch In") if modParty[idxParty].able?
      commands[cmdSummary = commands.length] = _INTL("Summary")
      commands[commands.length] = _INTL("Cancel")
      command = scene.pbShowCommands(_INTL("Do what with {1}?", modParty[idxParty].name), commands)

      if cmdSwitch >= 0 && command == cmdSwitch   # Switch In
        idxPartyRet = -1
        partyPos.each_with_index do |pos, i|
          next if pos != idxParty + partyStart
          idxPartyRet = i
          break
        end
        break if yield idxPartyRet, switchScreen
      elsif cmdSummary >= 0 && command == cmdSummary   # Summary
        scene.pbSummary(idxParty, true)
      end
    end

    # Close party screen
    switchScreen.pbEndScene

    # Fade back in
    pbFadeInAndShow(@sprites, visibleSprites)
  end

  #=============================================================================
  #  Trainer battle speech (EBDX feature)
  #=============================================================================
  def pbTrainerBattleSpeech(*args)
    # Trainer speech from scripted battles - no-op if no battle script loaded
    return if !@battle.respond_to?(:midspeech) || !defined?(@midspeech)
  end

  #=============================================================================
  #  Low HP BGM
  #=============================================================================
  def setBGMLowHP(play = false)
    return if !EliteBattle::USE_LOW_HP_BGM
    return if !EBDXToggle.enabled?
    # Check if any player pokemon is low HP
    anyLow = false
    @battle.battlers.each_with_index do |b, i|
      next if !b || i % 2 != 0
      anyLow = true if b.respond_to?(:lowHP?) && b.lowHP?
    end
    if anyLow && !@lowHPBGM && play
      @lowHPBGM = true
      pbBGMPlay("EBDX/Low HP") rescue nil
    elsif !anyLow && @lowHPBGM
      @lowHPBGM = false
    end
  end

  #=============================================================================
  #  Scene alignment helpers
  #=============================================================================
  def alignSprites(sprite, target)
    sprite.ox = sprite.src_rect.width/2
    sprite.oy = sprite.src_rect.height/2
    sprite.x = target.x
    sprite.y = target.y
  end

  def getRealVector(targetindex, player)
    vector = EliteBattle.get_vector(:BATTLER, player)
    return vector
  end

  def applySpriteProperties(sprite1, sprite2)
    sprite2.x = sprite1.x
    sprite2.y = sprite1.y
    sprite2.z = sprite1.z
    sprite2.zoom_x = sprite1.zoom_x
    sprite2.zoom_y = sprite1.zoom_y
    sprite2.opacity = sprite1.opacity
    sprite2.angle = sprite1.angle
    sprite2.tone = sprite1.tone
    sprite2.color = sprite1.color
    sprite2.visible = sprite1.visible
  end

  def pbResetParams
    @vector.reset if @vector
    @orgPos = nil
    @vector.inc = 0.2 if @vector
    @vector.lock if @vector
  end

  def setVector(*args)
    return if !@vector
    if args[0].is_a?(Array)
      @vector.set(*args)
    else
      @vector.set(args)
    end
  end

  def moveEntireScene(x = 0, y = 0, lock = true, bypass = false, except = nil)
    return if !bypass && EliteBattle::DISABLE_SCENE_MOTION
    for i in 0...4
      next if !i.nil? && i == except
      @sprites["pokemon_#{i}"].x += x if @sprites["pokemon_#{i}"]
      @sprites["pokemon_#{i}"].y += y if @sprites["pokemon_#{i}"]
    end
    @vector.x += x; @vector.y += y
    return if !lock; return if @orgPos.nil?
    @orgPos[0] += x; @orgPos[1] += y
  end

  def revertMoveTransformations(index)
    if @sprites["pokemon_#{index}"] && @sprites["pokemon_#{index}"].respond_to?(:hidden) && @sprites["pokemon_#{index}"].hidden
      @sprites["pokemon_#{index}"].hidden = false
      @sprites["pokemon_#{index}"].visible = true
    end
  end

  #=============================================================================
  #  Substitute handling
  #=============================================================================
  def setSubstitute(index, set)
    sprite = @sprites["pokemon_#{index}"]
    return if !sprite
    if set && sprite.respond_to?(:setSubstitute)
      sprite.setSubstitute(@battlers[index].pokemon)
    elsif !set && sprite.respond_to?(:removeSubstitute)
      sprite.removeSubstitute
    end
  end

  def substitueAll(targets)
    return if !targets
    targets.each do |t|
      next if !t[0]
      setSubstitute(t[0].index, t[0].effects[PBEffects::Substitute] > 0)
    end
  end

  #=============================================================================
  #  Compatibility stubs for methods called by battle/multiplayer code
  #=============================================================================
  def pbSaveShadows
    yield if block_given?
  end

  def clearMessageWindow(full = false)
    if @sprites["messageWindow"]
      @sprites["messageWindow"].text = ""
      @sprites["messageWindow"].visible = false
    end
    pbShowWindow(BLANK) if full
  end

  def windowVisible?
    return @sprites["messageWindow"] && @sprites["messageWindow"].visible
  end

  def changeMessageViewport(vp)
    @sprites["messageWindow"].viewport = vp if @sprites["messageWindow"]
  end
end
