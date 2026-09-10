%% Measurements behind elixir-lsp/elixir-ls PR "Bind the MCP server to loopback".
%% Reproduces the listen options of apps/language_server/lib/language_server/mcp/tcp_server.ex
%% before and after the change, and checks reachability from inside the BEAM.
%% Meant to run in a network namespace of its own (see run-docker.sh), where the host's firewall rules do not apply.
-module(mcp_bind).
-export([main/0]).

main() ->
    {ok, Ifs} = inet:getifaddrs(),
    [Eth | _] = [A || {_, Os} <- Ifs, {addr, A = {A1, _, _, _}} <- Os, A1 =/= 127],
    io:format("environment~n  OTP ~s erts-~s~n  non-loopback IPv4: ~s~n",
              [erlang:system_info(otp_release), erlang:system_info(version), inet:ntoa(Eth)]),
    Pre = [binary, {packet, line}, {active, false}, {reuseaddr, true}],

    io:format("~n## 1. master (68df44b6): listen options as in tcp_server.ex:135 (no {ip,_})~n"),
    {ok, L0} = gen_tcp:listen(0, Pre),
    {ok, {A0, P0}} = inet:sockname(L0),
    io:format("  -> bind ~s:~w~n", [inet:ntoa(A0), P0]),
    io:format("  -> connect from non-loopback ~s -> ~p~n", [inet:ntoa(Eth), tag(gen_tcp:connect(Eth, P0, [binary], 800))]),
    io:format("  -> connect ::1 (IPv6 loopback)  -> ~p   (0.0.0.0 is not a dual-stack bind)~n",
              [tag(gen_tcp:connect({0, 0, 0, 0, 0, 0, 0, 1}, P0, [binary, inet6], 800))]),
    gen_tcp:close(L0),

    io:format("~n## 2. fix: same options plus {ip, {127,0,0,1}}~n"),
    {ok, L1} = gen_tcp:listen(0, [{ip, {127, 0, 0, 1}} | Pre]),
    {ok, {A1, P1}} = inet:sockname(L1),
    io:format("  -> bind ~s:~w~n", [inet:ntoa(A1), P1]),
    io:format("  -> connect from non-loopback ~s -> ~p~n", [inet:ntoa(Eth), tag(gen_tcp:connect(Eth, P1, [binary], 800))]),
    io:format("  -> connect 127.0.0.1             -> ~p~n", [tag(gen_tcp:connect({127, 0, 0, 1}, P1, [binary], 800))]),
    gen_tcp:close(L1),

    io:format("~n## 3. bridge: gen_tcp:connect by the name \"localhost\", no family option~n"),
    io:format("  -> inet_db:res_option(inet6) = ~p~n", [inet_db:res_option(inet6)]),
    io:format("  -> inet:getaddr(\"localhost\", inet) = ~p~n", [inet:getaddr("localhost", inet)]),
    {ok, L2} = gen_tcp:listen(0, [{ip, {127, 0, 0, 1}} | Pre]),
    {ok, {_, P2}} = inet:sockname(L2),
    io:format("  -> connect(\"localhost\") to the 127.0.0.1 listener -> ~p   (resolved in the inet family)~n",
              [tag(gen_tcp:connect("localhost", P2, [binary, {active, false}, {packet, line}, {buffer, 65536}], 800))]),
    gen_tcp:close(L2),
    io:format("~ndone~n"),
    halt().

tag({ok, S}) -> gen_tcp:close(S), ok;
tag(Other) -> Other.
