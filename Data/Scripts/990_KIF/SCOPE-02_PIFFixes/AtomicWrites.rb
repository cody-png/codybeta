#===============================================================================
# SCOPE-02 – PIF fixes: files written whole or not at all
# PIF 6.9 wrote two files in place, so a crash or a full disk part-way left a
# cut file:
#  1. The Transfer Box file (053_PIF_Hoenn/TransferBox.rb) is shared by every
#     save. It is now written through KIF.atomic_write. A file that can't be
#     read is first copied to <file>.<time>.bak (PIF's empty box then replaces
#     it, as before, so Pokémon put in the box stay saved), and a box change
#     saves the game once, not twice.
#  2. Files from the web (HttpCalls.rb download_file: the settings, credits and
#     custom Pokédex files) are written through KIF.atomic_write too, and a
#     disk error (SystemCallError) is a failed download, not a crash.
#===============================================================================
KIF.guard_base("053_PIF_Hoenn/TransferBox.rb", 2931014826,
               "StorageTransferBox#loadTransferBoxPokemon, saveTransferBox, []=")
KIF.guard_base("052_InfiniteFusion/System/HttpCalls.rb", 3232045372, "download_file")

class StorageTransferBox
  # Copy of 053_PIF_Hoenn/TransferBox.rb:43-54 that keeps a copy of a file it can't read
  def loadTransferBoxPokemon
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
    echoln "Transfer box saved to #{path}"
    Game.save
  rescue => e
    echoln "Failed to save transfer box: #{e}"
  end

  # Copy of 053_PIF_Hoenn/TransferBox.rb:56-65 without the second Game.save
  def []=(i, value)
    return unless value.nil? || value.is_a?(Pokemon)
    return if check_is_duplicate(value)
    @pokemon[i] = value
    saveTransferBox() if can_use_transfer_box?
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
