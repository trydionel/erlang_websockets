-module(local_server).
-compile(export_all).

-define(TCP_OPTIONS, [{packet, 0}, {active, true}, {reuseaddr, true}]).
-define(HANDSHAKE, "HTTP/1.1 101 Web Socket Protocol Handshake\r\n" ++
  "Upgrade: WebSocket\r\n" ++
  "Connection: Upgrade\r\n" ++
  "WebSocket-Origin: http://localhost\r\n" ++
  "WebSocket-Location: ws://localhost:8809/\r\n\r\n").

%% start()
%%  This should be in another module for clarity
%%  but is included here to make the example self-contained

start() ->
  Handler = fun interact/2,
  spawn(fun() -> listen(Handler, 0) end).

interact(Browser, Clock) ->
  receive
    {browser, Browser, Str} ->
      Reversed_Str = lists:reverse(Str),
      Browser ! {send, "out ! " ++ Reversed_Str},
      interact(Browser, Clock)
  after
    1000 ->
      Browser ! {send, "clock ! tick " ++ integer_to_list(Clock)},
      interact(Browser, Clock+1)
  end.

listen(Handler, State) -> 
  % Opens a socket on port 8809 with options above
  {ok, LSocket} = gen_tcp:listen(8809, ?TCP_OPTIONS),
  
  % Accepts new connections on the opened socket
  accept(LSocket, Handler, State).

accept(LSocket, Handler, State) ->
  % Accepts a new connection
  {ok, Socket} = gen_tcp:accept(LSocket),
  
  % Spawn off another thread(?) to listen for new connections
  spawn(fun() -> accept(LSocket, Handler, State) end),
  
  % Watch for handshake
  wait(Socket, Handler, State).

wait(Socket, Handler, State) ->
  receive
    % Initial handshake request
    {tcp, Socket, Data} ->
      gen_tcp:send(Socket, ?HANDSHAKE),
      Browser = self(),
      Pid = spawn_link(fun() -> Handler(Browser, State) end),
      loop(zero, Socket, Pid);

    % Catch all other messages
    Any ->
      io:format("Received:~p~n",[Any]),
      wait(Socket, Handler, State)
  end.

loop(Buff, Socket, Pid) ->
  receive
    {tcp, Socket, Data} ->
      handle_data(Buff, Data, Socket, Pid);
    {tcp_closed, Socket} ->
      Pid ! {browser_closed, self()};
    {send, Data} ->
      gen_tcp:send(Socket, [0,Data,255]),
      loop(Buff, Socket, Pid);
    Any ->
      io:format("Received:~p~n",[Any]),
      loop(Buff, Socket, Pid)
  end.

handle_data(zero, [0|T], Socket, Pid) -> handle_data([], T, Socket, Pid);
handle_data(zero, [], Socket, Pid) -> loop(zero, Socket, Pid);
handle_data(L, [255|T], Socket, Pid) ->
  Line = lists:reverse(L),
  Pid ! {browser, self(), Line},
  handle_data(zero,T, Socket, Pid);
handle_data(L, [H|T], Socket, Pid) -> handle_data([H|L], T, Socket, Pid);
handle_data([], L, Socket, Pid) -> loop(L, Socket, Pid).