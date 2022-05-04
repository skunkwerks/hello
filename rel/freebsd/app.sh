#!/bin/sh -e
# obvious
export APP=$(basename -s .sh $0)
export HOME=/var/run/${APP}
# ensure tmp files are only user-readable
umask 077

# find latest OTP - derived paths are OS dependent
export ERTS=$(find /usr/local/lib/${APP} -type d -depth 1 -name erts-\* | tail -1)
export VERSION=$(cut -swf 2 /usr/local/lib/${APP}/releases/start_erl.data)

# config files
CONFIGS=/usr/local/etc/${APP}
export SYSCONFIG=${CONFIGS}/${APP}.config
export VMARGS=${CONFIGS}/vm.args

# BEAM essentials
export LD_LIBRARY_PATH=${ERTS}/lib:
export BINDIR=${ERTS}/bin
export PATH=${BINDIR}:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export ROOTDIR=/usr/local/lib/${APP}
export PROGNAME=${ROOTDIR}/releases/${VERSION}/${APP}.sh
export ERL_LIBS=./rel/${APP}/lib:${ROOTDIR}/lib

export MODE="-mode embedded"

# elixir
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# no turds on BEAM exit
export ERL_CRASH_DUMP=/dev/null
export ERL_CRASH_DUMP_BYTES=0
export ERL_CRASH_DUMP_SECONDS=0

# runtime dirs
export RELEASE_LOG_DIR=/var/log/${APP}
export RELEASE_TMP=/var/run/${APP}

# debug beam startup
# export VERBOSE="-init_debug "
# ensure epmd is managed by OS daemons and not tied to this app
# export EPMD="-start_epmd false"
# keep user sticky fingers out of the console
# see http://erlang.org/doc/man/run_erl.html
# export RUN_ERL_DISABLE_FLOWCNTRL=1
# export DOTERL="-boot no_dot_erlang"
# export IEX_DISABLED="-noshell"
export IEX_ENABLED="-kernel shell_history enabled -elixir ansi_enabled true -user Elixir.IEx.CLI -extra --no-halt +iex"

cd ${HOME}

exec ${BINDIR}/erlexec \
     ${VERBOSE} \
     ${DOTERL} \
     ${EPMD} \
     ${MODE} \
    -boot ${ROOTDIR}/releases/${VERSION}/start \
    -boot_var RELEASE_LIB ${ROOTDIR}/lib \
    -pa ${ROOTDIR}/lib/${APP}-${VERSION}/consolidated \
    -pz ${ROOTDIR}/lib/${APP}-${VERSION}/ebin \
    -args_file ${VMARGS} \
    -config ${SYSCONFIG} \
    ${IEX_ENABLED}

