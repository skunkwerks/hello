#!/bin/sh
#
# PROVIDE: APP
# REQUIRE: networking epmd
# AFTER: epmd
# KEYWORD:

. /etc/rc.subr

name="APP"
rcvar="${name}_enable"

extra_commands="status"
start_cmd="${name}_start"
stop_cmd="${name}_stop"
status_cmd="${name}_status"

load_rc_config $name
: ${APP_enable:="no"}
: ${APP_user:="APP"}
: ${APP_zflags:="-start_epmd true"}
: ${APP_command="/usr/local/lib/APP/bin/APP"}

APP_run()
{
umask 077
/usr/bin/env \
  HOME="/var/run/APP" \
  RELEASE_COOKIE="ignored_but_elixir_wants_it_my_precioussss" \
  RELEASE_TMP="/var/run/APP" \
  RELEASE_VM_ARGS="/usr/local/etc/APP/vm.args" \
  RELEASE_SYS_CONFIG="/usr/local/etc/APP/APP" \
  ERL_ZFLAGS="${APP_zflags}" \
  su -m "${APP_user}" -c "${APP_command} daemon"
}

# On each run, we ensure we are starting from a clean slate.
# At shutdown we kill any stray processes just in case.
# Logs are stored using syslog but there are some minimal
# startup and heart logs from the runtime that are worth
# keeping in case of debugging BEAM crashes.

APP_start()
{
  rm -rf /var/run/APP/.erlang.cookie
  APP_stop
  APP_run
}

APP_stop()
{
  # kill only the process listed in the pidfile and only if the user matches
  pkill -TERM -U ${APP_user} -f beam.smp
  sleep 3
  pkill -KILL -U ${APP_user} -f beam.smp
}

APP_status()
{
  pid_check=$(pgrep -U ${APP_user} -f beam.smp)
  test "$pid_check" && echo "${name} is running."
}

load_rc_config $name
run_rc_command "$1"

