
#todo: limit of 10 at once

#todo: append new friends at the end of the list instead of overwriting everything

#todo: if the friend's id is already in there, update (overwrite) it
#
class SecretBaseFetcher
  SECRETBASE_DOWNLOAD_URL = "https://secretbase-download.pkmninfinitefusion.workers.dev"

    def import_friend_base(friend_player_id)
      base_json = fetch_base(friend_player_id)
      if base_json
        save_friend_base(base_json)
      else
        pbMessage(_INTL("The game couldn't find your friend's base. Make sure that they published it and that you wrote their trainer ID correctly."))
        raise "Secret Base does not exist"
      end
    end

  # Fetch a secret base by playerID
  def fetch_base(player_id)
      url = "#{SECRETBASE_DOWNLOAD_URL}/get-base?playerID=#{player_id}"

      begin
        response = HTTPLite.get(url)
        if response[:status] == 200
          echoln "[SecretBase] Downloaded base for #{player_id}"
          base_json = JSON.parse(response[:body])
          return base_json
        else
          echoln "[SecretBase] Failed with status #{response[:status]} for #{player_id}"
          return nil
        end
      rescue MKXPError => e
        echoln "[SecretBase] MKXPError: #{e.message}"
        return nil
      rescue Exception => e
        echoln "[SecretBase] Error: #{e.message}"
        return nil
      end
    end

  def save_friend_base(new_base)
    exporter = SecretBaseExporter.new
    exporter.write_base_json_to_file(new_base,SecretBaseImporter::FRIEND_BASES_FILE,true)
  end


end
