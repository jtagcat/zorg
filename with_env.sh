#!/usr/bin/env bash
set -euo pipefail

repo="${1}"
shift

use_cache=1

scriptdir="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"
repodir="${scriptdir}/repos"

_borgdir="$(mktemp --tmpdir -d borghome."${USER}".XXXXXXX)"

cleanup () {
	rm -rf "${_borgdir}" || true
}

trap 'cleanup' EXIT


test -d "${repodir}/${repo}" || "${scriptdir}/init.sh" "${repo}"
"${scriptdir}/pass.sh" "${repo}" key | install -D -m 400 /dev/stdin "${_borgdir}/repo/key"


if [ "${use_cache}" = "1" ]; then
	cachedir="${scriptdir}/cache"
	mkdir -p "${cachedir}"
	export BORG_CACHE_DIR="${cachedir}"
fi

export BORG_PASSCOMMAND="${scriptdir}/pass.sh '${repo}' passphrase"
export BORG_KEY_FILE="${_borgdir}/repo/key"
export BORG_BASE_DIR="${_borgdir}"
export BORG_REPO="${repodir}/${repo}"
export BORG_SELFTEST="disabled"

"${@}"
