# Hello

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Install Node.js dependencies with `cd assets && npm install`
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

# FreeBSD Hello

This is a quick skeleton app to show how to use distillery
and FreeBSD to ship Elixir and Erlang-based daemons via
FreeBSD's amazing pkg toolkit, and the latest OTP runtime.

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

## Prepare the release

Initialise your distillery release configuration via `mix release.init`.

We need to customise a few things to our `rel/` directory, to ensure
that various files end up in the right place, and that:

- a `config.exs` that allows us to override release settings in
    production, using `vm.args` and `sys.config` files provide to the
    BEAM runtime, `erts`
- a default `vm.args` file for use in dev mode

We'll use these config files later within FreeBSD to override the
configuration with appropriate run-time secrets, so we don't have to
store anything in the source code, or package tarball, that can be used
by an attacker against us.

## Modify `config/prod.*` files

As we will be overwriting all the secret values via `sys.config` and
`vm.args`, we don't need the additional and IMO very confusing runtime
hacks that try to merge in files from both environment variables and
existing compiled-in settings.

You'll need to set port number and hostname in `config/prod.exs`, and
We also need a `secret_key_base` that is used to keep user sessions
encrypted. I believe that this can be different for each session of
phoenix, so later on you can set it as a runtime variable.

A typical `config/prod.exs` might be:

```elixir
config :hello, HelloWeb.Endpoint,
  url: [host: "example.net", port: 4003],
  server: true,
  http: [port: 4003],
  secret_key_base: "overwritten_by_deployment_tools",
   cache_static_manifest: "priv/static/cache_manifest.json"
```

## Build the release manually and test it

```
$ mix phx.digest
$ env LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod \
    mix release --env=prod
$ env LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    _build/prod/rel/hello/bin/hello console
```

