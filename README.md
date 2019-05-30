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

## Unpack the tarball

Inside the tarball are a couple of files we are interested in -
`vm.args` and `sys.config` in particular, but feel free to browse
around - you'll see a number of files of general interest here.

```
$ export TMPDIR=$(mktemp -d)
$ tar -xzC $TMPDIR -f $(find _build/prod/rel -name \*.tar.gz)
$ less $(find $TMPDIR -name sys.config -o -name vm.args)
```

These files are what you'll want to plug into your config management
software, so you can separate the secrets inside from the package we'll
be deploying.

## Include FreeBSD scripts

In `rel/freebsd/` we now have 3 templates:

- a [pkg-create(8)] manifest file we'll use to build a deployable pkg
- an rc.d script that will end up in /usr/local/etc/rc.d/hello
- app.sh to enable running the app in the foreground for debugging

These are generic and can largely be re-used for any app without
tweaking - the new `./build.sh` script uses the name of the root
directory of this repo to customise the 3 templates, and to take the
release tarball, extract it, and prepare a deployable FreeBSD package
from it.

Note that the package itself can be put into a custom package
repository, which then can be deployed via `pkg install -r local app`
and thus also automatically upgraded via `pkg upgrade` too.

For this to work, it is recommended to use git tags liberally, and the
build script will re-use these to generate both the release name, and
the resulting package as well, by injecting this into the package
metadata.

## Create a package

Using all the above, let's tag this as `0.0.1` and let things run.

```
$ git tag 0.0.1
$ ./build.sh
...
```

##  Runtime Concerns

### epmd

One of the tweaks in the above config is that we *explicitly* don't
start epmd. There are reasons for this:

- epmd shouldn't run under the same user process as our app
- epmd by default will listen on all interfaces and ports

That's not a particularly secure setup, and we want a bit more control
over it. epmd should run under a low-privileged account, with loopback
access only unless we explicitly need distributed nodes.

### sys.config and vm.args

You'll also need to put appropriate config files into /usr/local/etc/APP
and make sure the permissions and ownership match.

### loggging

I recommend logging directly to syslog, using `logger_syslog_backend`
on hex.
