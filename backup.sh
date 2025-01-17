#!/usr/bin/env bash
set -euo pipefail

scriptdir="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"

dataset="${1}"
repo="$(basename -- "${dataset}")"

if [ -f "${scriptdir}/ignored.txt" ]; then
	process_dataset() {
		grep -q -v -x -E -f "${scriptdir}/ignored.txt" <<< "${1}"
		return "${?}"
	}
else
	process_dataset() {
		return 0
	}
fi

if ! zfs list -H -p -o name "${dataset}" &>/dev/null; then
	echo ">>> No such dataset '${dataset}'"
	exit 1
fi

tz=UTC
borg=(
	"${scriptdir}/with_env.sh"
	"${repo}"
	chrt -i 0
	borg
)

echo ">>> Getting existing archives..."
declare -A known_archives=()
for archive in $("${scriptdir}/list.sh" "${repo}" | jq -r '.archives[] | .archive'); do
	known_archives["${archive}"]="1"
done
echo ">>> Done"

# Ensure that repository exists
"${scriptdir}/with_env.sh" "${repo}" :

zfs list -H -t snapshot -o name,creation -s creation -p "${dataset}" | while read -r -a target; do
	_snapname="${target[0]}"
	ts="${target[1]}"


	snapname="$(cut -d@ -f2- <<< "${_snapname}")"
	if ! process_dataset "${snapname}"; then
		continue
	fi

	snapdate="$(env TZ="${tz}" date --date="@${ts}" "+%Y-%m-%d_%H:%M:%S")"
	name="files-${snapdate}"

	if ! [[ -v known_archives["${name}"] ]]; then
		echo ">>> Going for '${snapname}' -> '${name}'"
		comment_args=(
			--arg ds "${dataset}"
			--arg s "${snapname}"
			--arg ts "${ts}"
		)
		comment="json:$(jq "${comment_args[@]}" -c -r '{ dataset: $ds, snapshot: $s, ts: $ts }' <<< "{}" | base64 -w 0)"
		"${scriptdir}/fuse.sh" "${_snapname}" "${borg[@]}" create --progress --comment "${comment}" --compression zstd ::"${name}" "./" || {
			echo ">>> Failed to backup '${name}'"
			exit 1
		}
	else
		echo ">>> Seems like '${_snapname}' is already archived"
	fi
done
