# Hello

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

# FreeBSD Hello

This is a quick skeleton app to show how to use distillery
and FreeBSD to ship Elixir and Erlang-based daemons via
FreeBSD's amazing pkg toolkit.

## Pre-requisites

Install elixir, hex, latest OTP, then Phoenix direct from upstream, and
update your PATH:

```
$ sudo pkg install -r FreeBSD -y \
    devel/elixir-hex \
    devel/rebar \
    devel/rebar3 \
    lang/erlang-runtime22
$ mix archive.install hex phx_new 1.4.6
$ export PATH=/usr/local/lib/erlang22/bin:$PATH
```

## Phoenix

Create a minimal app, and confirm it runs:

```
$ mix phx.new --no-ecto hello
$ cd hello
$ mix phx.server
```

## Add distillery

Prepend  `{:distillery, "~> 2.0", runtime: false},`  to your
`defp deps() do [ ....` function, then:

```
$ mix do deps.get, deps.compile, compile
```
