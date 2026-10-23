# Sourced by the scenario tests (tools/*test.sh): CPCEC with scripted keys
# and RAM dumps. The times are VBLs counted as if the game started at
# VBL 850; BOOT (the loader's extra time: the title first) is added to all
# of them, so a change to the boot only changes BOOT.
BOOT=${BOOT:-210}
export BOOT

# scenario <prefix> <keys: key:from-to,...> <dumps: f1,f2,...> <last> [timeout s]
# (SHOTS="f1,f2": BMP screenshots too, <prefix>NNNNN.bmp: tools/screenshots.sh)
scenario() {
	local out=$1 keys=$2 dumps=$3 last=$4 k a b f o=() d=() s=()
	for k in ${keys//,/ }; do
		a=${k#*:}; b=${a#*-}; a=${a%-*}
		o+=("${k%%:*}:$((a + BOOT))-$((b + BOOT))")
	done
	for f in ${dumps//,/ }; do d+=($((f + BOOT))); done
	for f in ${SHOTS//,/ }; do s+=($((f + BOOT))); done
	rm -f "$out"*.ram "$out"*.bmp
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
		CPCEC_KEYS="$(IFS=,; echo "${o[*]}")" CPCEC_DUMPS="$(IFS=,; echo "${d[*]}")" \
		CPCEC_SHOTS="$(IFS=,; echo "${s[*]}")" \
		CPCEC_PREFIX="$out" CPCEC_EXIT=$((last + BOOT)) \
		timeout "${5:-900}" "${CPCEC:-$HOME/tools/cpcec/cpcec}" -S -r0 -O -m2 -k1 -g0 build/cwl_en.dsk >/dev/null 2>&1 || true
}
