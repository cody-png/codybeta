#===============================================================================
# F-CORE-02 – SaveData.read_from_file, the base the old-save import wraps
# (2026-11-01)
# Copy of PIF 6.8.2 001_SaveData.rb:42-50. The converted save is written back
# through a temp file and a rename, and a failure to write it keeps the
# converted data in memory (the file is converted again on the next read).
# It is here, ahead of KifSaveImport.rb, because that file wraps this method
# (alias kif_read_from_file) to turn old KIF saves into this port's format:
# a copy defined after it would replace the wrapper and no old save would be
# converted on reading.
#===============================================================================
KIF.guard_base("002_Save data/001_SaveData.rb", 1717219762, "SaveData.read_from_file")

module SaveData
  def self.read_from_file(file_path)
    validate file_path => String
    save_data = get_data_from_file(file_path)
    save_data = to_hash_format(save_data) if save_data.is_a?(Array)
    if !save_data.empty? && run_conversions(save_data)
      begin
        KIF::SaveBackups.write_file(file_path, Marshal.dump(save_data))
      rescue StandardError => e
        KIF.log("Converted save not written back (#{e.class}: #{e.message.to_s[0, 160]})")
      end
    end
    return save_data
  end
end
