# elixir-ls-mcp-bind-measurements

Measurements behind a change proposed to
[elixir-lsp/elixir-ls](https://github.com/elixir-lsp/elixir-ls), "Bind the MCP
server to loopback": the MCP TCP server calls `:gen_tcp.listen/2` without an
`{:ip, _}` option, so it binds `0.0.0.0` and, while enabled, is reachable from
the network without authentication. The change adds `ip: {127, 0, 0, 1}`.

This repository holds a small Erlang module that reproduces the listen options
before and after the change and checks reachability from inside the BEAM, a
runner that executes it in Docker's bridge network so that no host firewall is
involved, and the captured outputs per OTP version.

Companion to [otp-loopback-node-measurements](https://github.com/erts-sched/otp-loopback-node-measurements),
which does the same for Erlang distribution.

## Run it

Requirements: Docker. Nothing runs on the host.

```text
./run-docker.sh 27 28 29
```

Each run starts an official `erlang:<version>` container on the default bridge
network (its own network namespace, a non-loopback address `172.17.0.x`, zero
nftables tables), compiles `mcp_bind.erl` and runs it. Sockets are read with
`inet:sockname/1` and reachability is measured with `gen_tcp:connect/4`, not
with `ss`, `nc` or `ip`.

## Cases and results

Identical on OTP 27.3.4.17 (erts 15.2.7.13), 28.5.0.6 (erts 16.4.0.6) and
29.0.6 (erts 17.0.6). Outputs are in [`results/`](results/).

| # | Setup | Result |
|---|-------|--------|
| 1 | `master`: the listen options of `tcp_server.ex:135`, no `{ip, _}` | bind `0.0.0.0:P`; connect from the non-loopback address: `ok`; connect `::1`: `econnrefused` |
| 2 | the change: same options plus `{ip, {127,0,0,1}}` | bind `127.0.0.1:P`; connect from the non-loopback address: `econnrefused`; connect `127.0.0.1`: `ok` |
| 3 | the bridge script's `gen_tcp:connect/4` by the name `localhost`, no family option, against the `127.0.0.1` listener | `inet_db:res_option(inet6)` = `false`; `localhost` resolves to `{127,0,0,1}`; connect: `ok` |

What the rows establish:

- Row 1: the server on `master` is reachable from a non-loopback address, and
  `0.0.0.0` is not a dual-stack bind, so an IPv6 loopback client was already
  refused before the change. There is no IPv6 regression to speak of.
- Row 2: after the change the non-loopback address is refused and loopback
  still connects.
- Row 3: the TCP-to-STDIO bridge shipped with elixir-ls, which connects by the
  name `localhost`, resolves it in the `inet` family, so it would keep working
  either way. Switching it to `127.0.0.1` only removes the dependence on name
  resolution; the `::1` concern applies to third-party clients that use
  `getaddrinfo` ordering.

## Measured elsewhere

Two claims in the pull request are about the elixir-ls code itself and are not
reproduced here, because they need the project compiled:

- Starting the MCP server through the language server's own path
  (`ElixirLS.LanguageServer.MCP.Supervisor.start_link/1`) and serving a
  `tools/call` request to a client on the host's LAN address, on `master`. This
  was measured on the author's host (Linux, OTP 27, Elixir 1.20.0) and is what
  the pull request's new test asserts in CI form (bind address of the listening
  socket, red on `master`, green with the change).
- With the change, a listen failure returns `:ignore` so the language server
  survives; measured on the same host with a privileged port (`:eacces`):
  `Supervisor.start_link/1` returns `{:ok, pid}` and the process count does not
  grow after stopping the server (no orphaned accept loop).

## Not measured

- Windows and macOS. Linux containers only. `:einval` as the accept error on a
  closed listen socket on Windows is taken from OTP behaviour, not measured.
- A second physical host. The non-loopback address used is the container's own
  bridge address, which takes the same path a remote host would.

License: MIT.
