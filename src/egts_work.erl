%%%-------------------------------------------------------------------
%%% @author shepver
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Дек. 2014 0:15
%%%-------------------------------------------------------------------
-module(egts_work).
-author("shepver").

-behaviour(gen_server).
-include("../include/egts_types.hrl").
-include("../include/egts_record.hrl").
%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {pid = 1, socket = null, last_data, host, port, did, accept_data, resend_count = 3}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
%%   {ok, Sock} = gen_tcp:connect('127.0.0.1', 7706, [binary, {packet, 0}]),
%%   error_logger:info_msg("connect ~p .~n", [Sock]),
%%   erlang:send_after(10, self(), run),
%%   {ok, #state{socket = Sock}}
  Data = {application:get_env(egts, host), application:get_env(egts, port), application:get_env(egts, did)},
  case Data of
    {{ok, Host}, {ok, Port}, {ok, Did}} ->
      erlang:send_after(30, self(), {connect, Host, Port, Did});
    _ -> ok
  end,
  {ok, #state{accept_data = dict:new()}}
.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_cast({connect, Host, Port, DID}, #state{pid = PID} = State) ->
  application:set_env(egts, host, Host),
  application:set_env(egts, port, Port),
  application:set_env(egts, did, DID),
  case gen_tcp:connect(Host, Port, [{packet, 0}, binary]) of
    {ok, Socket} ->
      {ok, SubType, Data} = egts_service_auth:dispatcher_identity({0, DID}),
      NumberRecord = 1, %% порядковый номер строки
      {ok, RecordData} = egts_service:auth_pack([Data, NumberRecord, SubType, 0]),
      {ok, TransportData} = egts_transport:pack([RecordData, PID]),
      case gen_tcp:send(Socket, TransportData) of
        ok ->
          {noreply, State#state{socket = Socket, host = Host, port = Port, did = DID}};
        Error ->
          error_logger:error_msg("login error reason ~p ", [Error]),
          erlang:send_after(30000, self(), {connect, Host, Port, DID}),
          {noreply, State}
      end;
    Error ->
      error_logger:error_msg("Connect error reason ~p ", [Error]),
      erlang:send_after(30000, self(), {connect, Host, Port, DID}),
      {noreply, State}
  end;

handle_cast(relogin, #state{host = Host, port = Port, did = DID, socket = Socet} = State) ->
  gen_tcp:close(Socet),
  gen_server:cast(self(), {connect, Host, Port, DID}),
  {noreply, State};

handle_cast({pos_data, {Imei, List}}, State) ->
  gen_server:cast(self(), {pos_data, {Imei, List}, 1}),
  {noreply, State};
handle_cast({pos_data, {Imei, List}, N}, #state{socket = Socet, pid = PID, accept_data = ADATA, resend_count = Count} = State) when (N =< Count) ->

  if
    Socet =:= null ->
      error_logger:error_msg("Not connect "),
      erlang:send_after(5000, self(), {pos_data, {Imei, List}, N}),
      {noreply, State};
    true ->
      IMEI = if
               is_binary(Imei) -> binary_to_list(Imei);
               is_integer(Imei) -> integer_to_list(Imei);
               is_list(Imei) -> Imei;
               is_atom(Imei) -> atom_to_list(Imei);
               true -> Imei
             end,
      OID = list_to_integer(lists:sublist(IMEI, length(IMEI) - 7, 8)),
      NewPid = if
                 PID == 65535 -> 0;
                 true -> PID + 1
               end,

      {ok, SubType, Data} = prepare_data(List),
      NumberRecord = 1, %% порядковый номер строки
      {ok, RecordData} = egts_service:posdata_pack([Data, NumberRecord, SubType, OID]),
      {ok, TransportData} = egts_transport:pack([RecordData, NewPid]),
      case gen_tcp:send(Socet, TransportData) of
        ok ->
          {noreply, State#state{pid = NewPid, accept_data = dict:store(NewPid, {pos_data, {Imei, List}, N}, ADATA)}};
        Error ->
          error_logger:error_msg("login error reason ~p ", [Error]),
          erlang:send_after(5000, self(), {pos_data, {Imei, List}, N + 1}),
          {noreply, State}
      end
  end
;

handle_cast(_Request, State) ->
  {noreply, State}.

prepare_data(List) ->
  prepare_data(List, {0, []}).
prepare_data([], {SubType, Data})
  -> {ok, SubType, Data};
prepare_data([{Event, Time, Lat, Lon, Speed, Cource, Mv} | T], {_, Data}) ->
  {ok, SubType, NewData} = egts_service_teledata:pos_data(#pos_data{ntm = Time, lat = Lat, long = Lon, spd = Speed, dir = Cource, mv = Mv, src = Event}),
  prepare_data(T, {SubType, [NewData | Data]}).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_info({pos_data, {Imei, List}, N}, State) ->
  gen_server:cast(self(), {pos_data, {Imei, List}, N}),
  {noreply, State};

handle_info({tcp, _Socket, Data}, State) ->
  List = egts:response({list, 0, Data}),
  {noreply, resend(List, State)};

handle_info({tcp_closed, _Socket}, State) ->
  gen_server:cast(self(), relogin),
  {noreply, State};

handle_info({connect, Host, Port, DID}, State) ->
  gen_server:cast(self(), {connect, Host, Port, DID}),
  {noreply, State};

handle_info(relogin, State) ->
  gen_server:cast(self(), relogin),
  {noreply, State};

handle_info(_Info, State) ->
  error_logger:info_msg("info ~p .~n", [_Info]),
  {noreply, State}.

resend([], State) -> State;
resend([Data | Tail], #state{pid = Pid, socket = Socket, accept_data = ADATA} = State) ->

  NewPid = if
             Pid == 65535 -> 0;
             true -> Pid + 1
           end,
  case egts:response({responce, NewPid, Data}) of
    {response, RPID, STATUS, SRD_LIST} ->
      if
        STATUS =/= 0 ->
          {ok, {pos_data, Val, N}} = dict:find(RPID, ADATA),
          gen_server:cast(self(), {pos_data, Val, N + 1});
        true -> ok
      end,
      error_logger:info_msg("Respone rpid ~p status ~p  r_list ~p.~n", [RPID, STATUS, egts_service:pars_for_info(SRD_LIST)]),
      resend(Tail, State#state{accept_data = dict:erase(RPID, ADATA)})
  ;
    {app_data, TransportDataResponse, DataList} ->
      gen_tcp:send(Socket, TransportDataResponse),
      error_logger:info_msg("Result list ~p .~n", [egts_service:pars_for_info(DataList)]),
      resend(Tail, State#state{pid = NewPid});
    {un, Data} ->
      error_logger:info_msg("UNResult ~p .~n", [Data]),
      resend(Tail, State)
  end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
