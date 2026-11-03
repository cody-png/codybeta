#===============================================================================
# F-NET-01 – Multiplayer over Steam (2026-10-26)
#
# Steam's flat C API (steam_api64.dll, Steamworks SDK 1.64) through the
# engine's Win32API, with Valve's test AppID 480 (steam_appid.txt next to
# Game.exe): friends see "Playing Spacewar". Starts only with Multiplayer On,
# on 64-bit Windows, with both files there and Steam running; otherwise
# start is false, the menu shows no Steam rows and nothing else changes.
# Multiplayer Off shuts it down (On starts it again).
# Callbacks are polled (ManualDispatch) once a frame from KIF::Net.update and
# never wait. Messages: ISteamNetworkingMessages, reliable, channel 0, each
# one frame of the usual protocol (Net.rb SteamConn, Session#host_steam).
# Every function is made at start (the Steam thread only calls them).
# MiniFFI rules (STEAM_PROBE.md): 'L' for anything 64 bits; bools read as
# 'L' & 0xFF; char* read by hand (a 'P' return would strlen a NULL).
# Events (take): [:lobby_created, ok, lobby] [:lobby_enter, lobby, response]
#   [:member, lobby, user, state bits] [:invite, lobby, friend]
#   [:session_request, peer] [:session_failed, peer]
#===============================================================================
module KIF
  module Net
    module Steam
      APP_ID = 480
      FRIENDS_ONLY = 1   # ELobbyType
      SEND = 8 | 32      # reliable, restart a broken session
      ID_STEAM = 16      # ESteamNetworkingIdentityType: a SteamID
      FUNCS = {
        InitFlat: ["SteamAPI_InitFlat", "P", "L"], Shutdown: ["SteamAPI_Shutdown", "", "V"],
        MDInit: ["SteamAPI_ManualDispatch_Init", "", "V"], Pipe: ["SteamAPI_GetHSteamPipe", "", "L"],
        RunFrame: ["SteamAPI_ManualDispatch_RunFrame", "L", "V"],
        NextCallback: ["SteamAPI_ManualDispatch_GetNextCallback", "LP", "L"],
        FreeCallback: ["SteamAPI_ManualDispatch_FreeLastCallback", "L", "V"],
        CallResult: ["SteamAPI_ManualDispatch_GetAPICallResult", "LLPLLP", "L"],
        User: ["SteamAPI_SteamUser_v023", "", "L"], MM: ["SteamAPI_SteamMatchmaking_v009", "", "L"],
        Utils: ["SteamAPI_SteamUtils_v010", "", "L"], Friends: ["SteamAPI_SteamFriends_v018", "", "L"],
        NMsg: ["SteamAPI_SteamNetworkingMessages_SteamAPI_v002", "", "L"],
        NUtil: ["SteamAPI_SteamNetworkingUtils_SteamAPI_v004", "", "L"],
        AppID: ["SteamAPI_ISteamUtils_GetAppID", "L", "L"], Overlay: ["SteamAPI_ISteamUtils_IsOverlayEnabled", "L", "L"],
        SteamID: ["SteamAPI_ISteamUser_GetSteamID", "L", "L"],
        Relay: ["SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess", "L", "V"],
        IdClear: ["SteamAPI_SteamNetworkingIdentity_Clear", "P", "V"],
        IdSet: ["SteamAPI_SteamNetworkingIdentity_SetSteamID64", "PL", "V"],
        CreateLobby: ["SteamAPI_ISteamMatchmaking_CreateLobby", "LLL", "L"],
        JoinLobby: ["SteamAPI_ISteamMatchmaking_JoinLobby", "LL", "L"],
        LeaveLobby: ["SteamAPI_ISteamMatchmaking_LeaveLobby", "LL", "V"],
        SetData: ["SteamAPI_ISteamMatchmaking_SetLobbyData", "LLPP", "L"],
        GetData: ["SteamAPI_ISteamMatchmaking_GetLobbyData", "LLP", "L"],
        SetMember: ["SteamAPI_ISteamMatchmaking_SetLobbyMemberData", "LLPP", "V"],
        GetMember: ["SteamAPI_ISteamMatchmaking_GetLobbyMemberData", "LLLP", "L"],
        Owner: ["SteamAPI_ISteamMatchmaking_GetLobbyOwner", "LL", "L"],
        Members: ["SteamAPI_ISteamMatchmaking_GetNumLobbyMembers", "LL", "L"],
        Member: ["SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex", "LLL", "L"],
        AskData: ["SteamAPI_ISteamMatchmaking_RequestLobbyData", "LL", "L"],
        Invite: ["SteamAPI_ISteamMatchmaking_InviteUserToLobby", "LLL", "L"],
        FriendCount: ["SteamAPI_ISteamFriends_GetFriendCount", "LL", "L"],
        Friend: ["SteamAPI_ISteamFriends_GetFriendByIndex", "LLL", "L"],
        FriendName: ["SteamAPI_ISteamFriends_GetFriendPersonaName", "LL", "L"],
        FriendState: ["SteamAPI_ISteamFriends_GetFriendPersonaState", "LL", "L"],
        FriendGame: ["SteamAPI_ISteamFriends_GetFriendGamePlayed", "LLP", "L"],
        InviteDialog: ["SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog", "LL", "V"],
        Send: ["SteamAPI_ISteamNetworkingMessages_SendMessageToUser", "LPPLLL", "L"],
        Receive: ["SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel", "LLPL", "L"],
        Accept: ["SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser", "LP", "L"],
        Release: ["SteamAPI_SteamNetworkingMessage_t_Release", "L", "V"],
      }
      KERNEL = { Copy: ["RtlMoveMemory", "PLL", "V"], StrLen: ["lstrlenA", "L", "L"] }
      FRIEND_FLAGS = 4   # k_EFriendFlagImmediate: real friends

      class << self
        attr_reader :me

        def ready?; @ready == true; end

        # once until shutdown (a second script run keeps it): true when Steam is there and started
        def start
          return @ready unless @ready.nil?
          @ready = false
          return false if (KIF.mobile? rescue true) || RUBY_PLATFORM !~ /mingw|mswin/ || !defined?(Win32API) || [0].pack("J").bytesize != 8
          return false unless File.exist?("steam_api64.dll") && File.exist?("steam_appid.txt")
          @fn = {}
          FUNCS.each { |k, (name, a, r)| @fn[k] = Win32API.new("steam_api64", name, a, r) }
          KERNEL.each { |k, (name, a, r)| @fn[k] = Win32API.new("kernel32", name, a, r) }
          err = "\0".b * 1024
          r = i32(@fn[:InitFlat].call(err))
          unless r == 0   # 1 failed, 2 no Steam running, 3 Steam too old
            Net.log("Steam: not started (#{r}: #{err.unpack1('Z*')[0, 80]})")
            return false
          end
          @fn[:MDInit].call
          @pipe = i32(@fn[:Pipe].call)
          @user, @mm, @utils, @friends, @nmsg, @nutil = %i[User MM Utils Friends NMsg NUtil].map { |k| @fn[k].call }
          if @pipe == 0 || [@user, @mm, @utils, @friends, @nmsg, @nutil].include?(0)
            Net.log("Steam: started, but an interface is missing")
            @fn[:Shutdown].call
            return false
          end
          @me = @fn[:SteamID].call(@user)
          @fn[:Relay].call(@nutil)   # the relay network gets ready before the first line
          @events = []
          @ids = {}
          @ready = true
          Net.log("Steam: ready (AppID #{i32(@fn[:AppID].call(@utils))})")
          return true
        rescue StandardError, ScriptError => e
          Net.log("Steam: not available (#{e.class})")
          return @ready = false
        end

        # once a frame (game thread): Steam's callbacks become events
        def pump
          return unless ready?
          @fn[:RunFrame].call(@pipe)
          msg = "\0".b * 24   # CallbackMsg_t: int user, int id, uint8* param, int size
          while b8(@fn[:NextCallback].call(@pipe, msg))
            begin
              _u, id, param, size = msg.unpack("l<l<Q<l<")
              data = read(param, [size, 4096].min)
              if id == 703   # an API call's result: fetched to free it; a lobby made comes as its own callback too, a failed join only here
                call, cb, n = data.unpack("Q<l<L<")
                buf = "\0".b * [n, 1].max
                ok = b8(@fn[:CallResult].call(@pipe, call, buf, n, cb, "\0".b * 8))
                event(cb, buf) if ok && cb == 504   # a second LobbyEnter for a join that worked is ignored (Session takes the first)
              else
                event(id, data)
              end
            ensure
              @fn[:FreeCallback].call(@pipe)
            end
          end
        rescue StandardError => e
          Net.log("Steam: callbacks failed (#{e.class}: #{e.message[0, 80]})") unless @pump_failed
          @pump_failed = true
        end

        def event(id, d)
          ev = case id
               when 513 then (r, l = d.unpack("l<x4Q<"); [:lobby_created, r == 1 && l.to_i != 0, l])   # LobbyCreated_t
               when 504 then (l, _p, _k, r = d.unpack("Q<L<Cx3L<"); [:lobby_enter, l, r])           # LobbyEnter_t
               when 506 then (l, u, _by, bits = d.unpack("Q<Q<Q<L<"); [:member, l, u, bits])         # LobbyChatUpdate_t
               when 333 then (l, f = d.unpack("Q<Q<"); [:invite, l, f])                              # GameLobbyJoinRequested_t
               when 1251, 1252   # SessionRequest_t / SessionFailed_t: both start with the peer's identity
                 t, _n, peer = d.unpack("l<l<Q<")
                 [id == 1251 ? :session_request : :session_failed, peer] if t == ID_STEAM
               end
          return unless ev && ev.none?(&:nil?)
          @events << ev
          @events.shift while @events.length > 64
        end

        def take(*kinds)
          return [] unless ready?
          mine, @events = @events.partition { |e| kinds.include?(e[0]) }
          return mine
        end

        def clear; @events&.clear; end

        def create_lobby(slots); @fn[:CreateLobby].call(@mm, FRIENDS_ONLY, slots); end
        def join_lobby(lobby); @fn[:JoinLobby].call(@mm, lobby); end
        def leave_lobby(lobby); @fn[:LeaveLobby].call(@mm, lobby) if ready?; end
        def set_lobby_data(lobby, k, v); b8(@fn[:SetData].call(@mm, lobby, z(k), z(v))); end
        def lobby_data(lobby, k); cstr(@fn[:GetData].call(@mm, lobby, z(k))); end
        def set_member_data(lobby, k, v); @fn[:SetMember].call(@mm, lobby, z(k), z(v)); end
        def member_data(lobby, user, k); cstr(@fn[:GetMember].call(@mm, lobby, user, z(k))); end
        def lobby_owner(lobby); @fn[:Owner].call(@mm, lobby); end
        def request_lobby_data(lobby); b8(@fn[:AskData].call(@mm, lobby)); end
        def invite(lobby, friend); b8(@fn[:Invite].call(@mm, lobby, friend)); end
        def overlay?; b8(@fn[:Overlay].call(@utils)); end
        def invite_dialog(lobby); @fn[:InviteDialog].call(@friends, lobby); end
        def name(id); cstr(@fn[:FriendName].call(@friends, id)); end

        def lobby_members(lobby)
          n = i32(@fn[:Members].call(@mm, lobby)).clamp(0, 250)
          return (0...n).map { |i| @fn[:Member].call(@mm, lobby, i) }
        end

        def friends
          n = i32(@fn[:FriendCount].call(@friends, FRIEND_FLAGS)).clamp(0, 2000)
          return (0...n).map { |i| @fn[:Friend].call(@friends, i, FRIEND_FLAGS) }
        end

        # [[friend, name], ...] online (persona state not offline)
        def friends_online
          friends.select { |f| i32(@fn[:FriendState].call(@friends, f)) != 0 }.map { |f| [f, name(f)] }
        end

        # [[friend, lobby], ...]: friends in this AppID who are in a lobby
        def friend_lobbies
          friends.filter_map do |f|
            info = "\0".b * 32   # FriendGameInfo_t: game id, ip, ports, lobby at 16
            next unless b8(@fn[:FriendGame].call(@friends, f, info))
            game, lobby = info.unpack("Q<x8Q<")
            [f, lobby] if game & 0xffffff == APP_ID && lobby != 0
          end
        end

        # Steam thread and game thread: true sent, :full (k_EResultLimitExceeded: over 512 KB queued, try again later), false failed
        def send_to(peer, bytes)
          return false unless ready?
          r = i32(@fn[:Send].call(@nmsg, identity(peer), bytes, bytes.bytesize, SEND, 0))
          return r == 1 || (r == 25 ? :full : false)
        end

        def accept(peer); b8(@fn[:Accept].call(@nmsg, identity(peer))); end

        # [[bytes, peer], ...]; a message longer than a frame is cut to one byte more (the line closes on it)
        def receive
          return [] unless ready?
          ptrs = "\0".b * 128
          n = i32(@fn[:Receive].call(@nmsg, 0, ptrs, 16))
          return [] if n <= 0
          out = ptrs.unpack("Q<#{n}").map do |p|
            begin
              m = read(p, 200)   # SteamNetworkingMessage_t: data at 0, size at 8, peer identity at 16, channel at 192
              data, size = m.unpack("Q<l<")
              t = m[16, 4].unpack1("l<")
              [read(data, size.clamp(0, MAX_FRAME + 1)), t == ID_STEAM ? m[24, 8].unpack1("Q<") : 0]
            ensure
              @fn[:Release].call(p)
            end
          end
          return out.reject { |_, peer| peer == 0 }
        end

        # Multiplayer Off or the game closing; start can init again after it
        def shutdown
          return unless ready?
          @ready = nil
          @fn[:Shutdown].call
          Net.log("Steam: shut down")
        end

        private

        def identity(peer)
          @ids[peer] ||= begin
            id = "\0".b * 136
            @fn[:IdClear].call(id)
            @fn[:IdSet].call(id, peer)
            id
          end
        end

        def i32(v); v &= 0xffffffff; v >= 0x80000000 ? v - 0x100000000 : v; end
        def b8(v); (v & 0xff) != 0; end
        def z(s); "#{s}\0"; end

        def read(addr, len)
          return "".b if addr == 0 || len <= 0
          buf = "\0".b * len
          @fn[:Copy].call(buf, addr, len)
          return buf
        end

        # a char* as UTF-8 text ("" for NULL)
        def cstr(addr)
          return "" if addr == 0
          return read(addr, i32(@fn[:StrLen].call(addr)).clamp(0, 8192)).force_encoding("UTF-8").scrub("?")
        end
      end
    end
  end
end
