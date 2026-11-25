#===============================================================================
# SCOPE-02 – PIF fixes: files written whole or not at all
# PIF 6.9 wrote two files in place, so a crash or a full disk part-way left a
# cut file:
#  1. The Transfer Box file (053_PIF_Hoenn/TransferBox.rb) is shared by every
#     save. It is now written through KIF.atomic_write. A file that can't be
#     read is first copied to <file>.<time>.bak (PIF's empty box then replaces
#     it, as before, so Pokémon put in the box stay saved), and a box change
#     saves the game once, not twice. A Pokémon taken out of the box is not
#     removed from the file until it is put down (see the PC screen below).
#  2. Files from the web (HttpCalls.rb download_file: the settings, credits and
#     custom Pokédex files) are written through KIF.atomic_write too, and a
#     disk error (SystemCallError) is a failed download, not a crash.
#===============================================================================
KIF.guard_base("053_PIF_Hoenn/TransferBox.rb", 2931014826,
               "StorageTransferBox#loadTransferBoxPokemon, saveTransferBox, []=")
KIF.guard_base("052_InfiniteFusion/System/HttpCalls.rb", 3232045372, "download_file")

class StorageTransferBox
  # Copy of 053_PIF_Hoenn/TransferBox.rb:43-54 that keeps a copy of a file it can't read,
  # and doesn't reload over a change not written yet (PIF reloads whenever the box comes
  # into view: with a Pokémon in the cursor that would copy it back or bring back a swapped one)
  def loadTransferBoxPokemon
    return if StorageTransferBox.unwritten.equal?(self)
    echoln "Loading transfer box"
    path = transferBoxSavePath
    if File.exist?(path)
      File.open(path, "rb") do |f|
        @pokemon = Marshal.load(f)
      end
    end
  rescue => e
    echoln "Failed to load transfer box: #{e}"
    @pokemon = Array.new(PokemonBox::BOX_SIZE, nil)
    (File.binwrite("#{path}.#{Time.now.strftime('%Y%m%d%H%M%S')}.bak", File.binread(path)) if path && File.file?(path)) rescue nil
  end

  # Copy of 053_PIF_Hoenn/TransferBox.rb:93-105
  def saveTransferBox
    return unless can_use_transfer_box?
    path = transferBoxSavePath
    dir = File.dirname(path)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    KIF.atomic_write(path) { |f| Marshal.dump(@pokemon, f) }
    StorageTransferBox.unwritten = nil if StorageTransferBox.unwritten.equal?(self)
    echoln "Transfer box saved to #{path}"
    Game.save
  rescue => e
    echoln "Failed to save transfer box: #{e}"
  end

  # The box with a change not in the shared file yet, and whether a swap is running.
  # Class-level: the box is stored inside the save, so it can't carry a flag.
  class << self
    attr_accessor :unwritten, :swapping

    # Writes the pending change, once the Pokémon taken out is somewhere else
    def flush
      box = unwritten
      return unless box
      (self.unwritten = nil; return) unless $PokemonStorage && $PokemonStorage.boxes.any? { |b| b.equal?(box) }
      box.saveTransferBox
    end
  end

  # Copy of 053_PIF_Hoenn/TransferBox.rb:56-65 without the second Game.save. A slot
  # emptied (pick-up) or changed in a swap is only marked: a Pokémon in the cursor
  # is in no file, so writing now would lose it if the game stops before it is put down
  def []=(i, value)
    return unless value.nil? || value.is_a?(Pokemon)
    return if check_is_duplicate(value)
    @pokemon[i] = value
    return unless can_use_transfer_box?
    if value.nil? || StorageTransferBox.swapping
      StorageTransferBox.unwritten = self
    else
      saveTransferBox()
    end
  end
end

# The PC screen writes the shared file once the Pokémon is put down, and the old
# placement save at put-down (@saveWhenPlaceDown) is replaced by that write
class PokemonStorageScreen
  [:pbPlace, :pbWithdraw, :pbRelease, :pbStore].each do |m|
    old = :"kif_tb_#{m}"
    alias_method old, m unless method_defined?(old)
    define_method(m) do |*args|
      ret = send(old, *args)
      StorageTransferBox.flush if @heldpkmn.nil?   # nothing in the cursor: every Pokémon is in a box or the party
      ret
    end
  end

  alias kif_tb_pbHold pbHold unless method_defined?(:kif_tb_pbHold)
  alias kif_tb_pbSwap pbSwap unless method_defined?(:kif_tb_pbSwap)
  alias kif_tb_pbStartScreen pbStartScreen unless method_defined?(:kif_tb_pbStartScreen)

  def pbHold(selected)
    kif_tb_pbHold(selected)
    @saveWhenPlaceDown = false
  end

  # The Pokémon swapped out lands in the cursor, so a swap in the Transfer Box only marks
  # the change; the next put-down writes it
  def pbSwap(selected)
    StorageTransferBox.swapping = true
    kif_tb_pbSwap(selected)
  ensure
    StorageTransferBox.swapping = false
  end

  def pbStartScreen(*args)
    return kif_tb_pbStartScreen(*args)
  ensure
    StorageTransferBox.flush if @heldpkmn.nil?
  end
end

# Copy of 052_InfiniteFusion/System/HttpCalls.rb:35-52
def download_file(url, saveLocation)
  echoln url
  begin
    response = HTTPLite.get(url)
    if response[:status] == 200
      KIF.atomic_write(saveLocation) { |file| file.write(response[:body]) }
      echoln "\nDownloaded file #{url} to #{saveLocation}"
      return saveLocation
    else
      echoln "Failed to download file #{url}"
    end
    return nil
  rescue MKXPError, SystemCallError => error
    echo error
    return nil
  end
end
