class SecretBasePublisher
  def initialize()
    @player_id =  $Trainer.id
  end

  def register
    if $Trainer.secretBase_uuid
      echoln "Already registered!"
    else
      begin
        payload = { playerID: @player_id }
        url = "#{Settings::SECRETBASE_UPLOAD_URL}/register"
        response = pbPostToString(url,payload)
        echoln response
        json = JSON.parse(response) rescue {}
        secret_uuid = json[:secretUUID]
        echoln json
        $Trainer.secretBase_uuid = secret_uuid
        echoln $Trainer.secretBase_uuid
        Game.save
      rescue Exception => e
        echoln e
      end
    end

    return $Trainer.secretBase_uuid

  end

  #Trainer needs to be registered before this is called
  def upload_base(base_json)
    secret_uuid = $Trainer.secretBase_uuid
    echoln secret_uuid
    unless $Trainer.secretBase_uuid
      echoln "Trainer not registered!"
      pbMessage(_INTL("The base could not be uploaded"))
    end

    payload = {
      playerID: @player_id,
      secretUUID: secret_uuid,
      baseJSON: base_json
    }
    url = "#{Settings::SECRETBASE_UPLOAD_URL}/upload-base"
    response = pbPostToString(url,payload)
    echoln response

    json = JSON.parse(response) rescue {}
    json["success"] == true
  end

  private

end