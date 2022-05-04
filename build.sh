#!/bin/sh -eu
set -o pipefail
# elixir puts its _build dir in the root of this repo, alongside build.sh
cd $(dirname $0)
ROOT=$(pwd -P)
APP=$(basename ${ROOT})
BUILD=${ROOT}/_build
test -d ${BUILD} || mkdir ${BUILD}
cd -

# calculate FreeBSD package manifest details
DATE=$(date -u +%Y%m%d-%H%M)
# ensure tags are up to date
git fetch --tags 2>/dev/null || true
# get a git tag or nearest sha to use as a suffix to app version
GITREF=$(git describe --abbrev=7 --tags --always --first-parent 2>/dev/null || true)
# filter out trailing commit and reformat to match pkg-version(8)
# this will ensure that any subsequent commits on top of a tag
# will result in a consistent increasing version to pass to pkg
GITTAG=$(echo $GITREF | sed -E -e 's/-g.+//' -e 's/\-/./')
GITSHA=$(git describe --dirty --abbrev=7 --always 2>/dev/null || true)

# ensure we pick up OTP24 by default
export PATH=/usr/local/lib/erlang24/bin:$PATH
# UTF8 while we build
export LANG=en_US.UTF-8
export LC_ALL=${LANG}
# pre-requisite to any mix tasks
export MIX_ENV=prod
export SECRET_KEY_BASE=$(head /dev/random |sha512 | cut -c 1-32)

# borrow rebar from packages
test -x ${HOME}/.mix/rebar  || mix local.rebar --force rebar  /usr/local/bin/rebar
test -x ${HOME}/.mix/rebar3 || mix local.rebar --force rebar3 /usr/local/bin/rebar3
mix help hex >/dev/null 2>&1 || mix local.hex --force

# clean up any existing release tarballs
find ${ROOT}/rel ${BUILD} -name *z -print -delete 2>/dev/null || true

# clean up existing dependencies and build
rm -rf ${ROOT}/deps ${ROOT}/_build/rel ${ROOT}/_build/prod/rel

# build stuff
mix deps.get --only prod
mix phx.gen.secret
mix do setup, tailwind.install
mix phx.digest
mix release --overwrite --quiet

RELEASE=_build/prod/rel/${APP}
test -e "${RELEASE}" || exit 1

# use a random temporary dir for everything else
BASE=$(mktemp -d -t ${APP})
STAGING=${BASE}/staging
DEST=${STAGING}/usr/local/lib/${APP}
PKG=${BASE}/package
MANIFEST=${PKG}/manifest.ucl
TEMPLATES=${ROOT}/rel/freebsd

mkdir -p -m0750 ${PKG} ${DEST} \
    ${STAGING}/usr/local/etc/rc.d \
    ${STAGING}/usr/local/bin

# exclude non-root users during tar etc
umask 007
# get template manifest and other static files
cp -vp ${TEMPLATES}/rc.d ${STAGING}/usr/local/etc/rc.d/${APP}
cp -vp ${TEMPLATES}/app.sh ${STAGING}/usr/local/bin/${APP}
cp -vp ${TEMPLATES}/manifest.ucl ${MANIFEST}
# replace APP with actual app name in rc.d script
sed -E -i '' -e "s/APP/${APP}/g" ${STAGING}/usr/local/etc/rc.d/${APP}

# clean out mix release garbage & files with sensitive content -
# these should be distributed out of band via ops tools. Leave the
# source copy of those so we can move it to ansible easily.
rm -rf ${RELEASE}/erts*/include
cp -avp ${RELEASE}/ ${STAGING}/usr/local/lib/${APP}
rm -rf  ${STAGING}/usr/local/lib/${APP}/releases/*/sys.config \
        ${STAGING}/usr/local/lib/${APP}/releases/*/vm.args \
        ${STAGING}/usr/local/lib/${APP}/releases/*/runtime.exs \
        ${STAGING}/usr/local/lib/${APP}/releases/COOKIE

# point configs to ansible-managed directories
#ln -s /usr/local/etc/${APP}/vm.args \
#    _build/prod/rel/${APP}/releases/*/vm.args
#ln -s /usr/local/etc/${APP}/sys.config \
#_build/prod/rel/${APP}/releases/*/sys.config

# set permissions appropriately
chmod 0550 ${STAGING}/usr/local/etc/rc.d/${APP} \
           ${STAGING}/usr/local/bin/${APP} \
           ${STAGING}/usr/local/lib/${APP}/bin/${APP} \
           ${STAGING}/usr/local/lib/${APP}/releases/*/iex \
           ${STAGING}/usr/local/lib/${APP}/releases/*/elixir

# prepare FreeBSD manifest
# inject previously calculated details into the manifest
uclcmd set --file ${MANIFEST} --type string version ${GITTAG}
uclcmd set --file ${MANIFEST} --type string options.git ${GITSHA}
uclcmd set --file ${MANIFEST} --type string options.ref ${GITREF}
uclcmd set --file ${MANIFEST} --type string options.utc ${DATE}

# include each file, its hash, and any permissions:
# expected result:
# "/usr/local/lib/app/bin/app": {sum: 1$abc123, uname: root, gname: www, perm: 0440 }
SHA_LIST=$(find ${STAGING} -type f -exec sha256 -r {} + \
    | awk '{print "  \"" $2 "\": {uname: root, gname: www, sum: 1$" $1"}"}')
# include softlinks:
# expected result looks like:
#   "/usr/local/lib/symlink": -
LINKS_LIST=$(find ${STAGING} -type l \
    | awk '{print "  \"" $1 "\": -"}')
# include app-specific directories and permissions:
# make sure we exclude things like /usr /usr/local/ /etc/ that are
# already in place as we don't want to change their permissions
# expected result looks like:
#   "/usr/local/lib/app": {uname: root, gname: www, perm: 0550}
DIR_LIST=$(find ${STAGING} -type d -mindepth 3 -path \*/${APP}/\*  \
    | awk '{print " \"" $1 "\": {uname: root, gname: www, perm: 0750}"}')

# make runtime directories
mkdir -m0770 -p \
    ${STAGING}/usr/local/etc/${APP} \
    ${STAGING}/var/db/${APP} \
    ${STAGING}/var/log/${APP} \
    ${STAGING}/var/run/${APP}

# strip off _build/state prefix and append this UCL snippet to manifest
cat <<UCL | sed -E -e s:${STAGING}:: >> ${MANIFEST}
files: {
$SHA_LIST
$LINKS_LIST
}
directories: {
$DIR_LIST
/usr/local/etc/${APP}: {uname: root, gname: www, perm: 0770}
/var/log/${APP}: {uname: root, gname: www, perm: 0770}
/var/run/${APP}: {uname: root, gname: www, perm: 0770}
/var/db/${APP}:  {uname: root, gname: www, perm: 0770}
}
UCL

## bubblewrap the package and manifest
if test "$(uname -s)" == "FreeBSD"; then
    (umask 007;
    pkg create --verbose \
        --root-dir ${STAGING} \
        --manifest ${MANIFEST} \
        --out-dir ${BUILD}
    )
    cp ${MANIFEST} ${BUILD}/
fi

# clean up
rm -rf ${BASE}

# remind people how to publish them
ARTEFACT=$(find ${BUILD} -name ${APP}-*.txz)

cat << EOM
final manifest:   $(find ${BUILD} -name manifest.ucl)
package complete: ${ARTEFACT}
git versions:     ${GITREF} ${GITTAG} ${GITSHA}

EOM

# if we are in CI build then transfer the artefact for signing
if test -n "${CI_BUILD:-}"; then
    cp -av ${ARTEFACT} /var/db/ci/pkg/
    # clean up
    rm -rf ${BASE}
else

# remind people how to publish them
cat << EOF
to deploy, transfer the artefact, sign the packages, and kick ansible:

$ cp ${ARTEFACT} /var/www/pkg.example.net/private/
$ sudo pkg repo -o \\
    /var/www/pkg.example.net/private/ \\
    /var/www/pkg.example.net/private/ \\
    /usr/local/etc/ssl/keys/pkg.example.net.key
$ ansible-playbook site.yml --limit app_jails

to install locally:

# sudo -s
# service ${APP} stop
# pkg install -r private local/${APP}
# service ${APP} start

or run it in the foreground via:

# su -m www -c /usr/local/bin/${APP}
EOF
fi
