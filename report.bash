COLS=${COLUMNS:-80}

hr(){
	local ch="${1:--}"
	printf "%0.s$ch" $(seq 1 "$COLS")
	echo
}

# A dataset counts as skipped when bats skipped every test in it, which the
# JUnit report already records on its testsuite element
dataset_skipped(){
	local report="$REPORT_DIR/${1}_${TAG}.xml" tests skipped

	[ -e "$report" ] || return 1
	tests=$(grep -o 'tests="[0-9]*"' "$report" | head -1 | tr -dc 0-9)
	skipped=$(grep -o 'skipped="[0-9]*"' "$report" | head -1 | tr -dc 0-9)

	[ -n "$tests" ] && [ "$tests" -gt 0 ] && [ "$tests" -eq "$skipped" ]
}

print_summary(){
	local pass=0 fail=0 skip=0 row dataset d rc elapsed test out status result reason signame found

	echo
	hr '='
	echo " OATS SUMMARY"
	hr '='

	if [ "${#RESULTS[@]}" -eq 0 ]; then
		echo " No tests were run."
		return
	fi

	printf ' %-4s  %-24s  %7s\n' "" "DATASET" "TIME"
	for row in "${RESULTS[@]}"; do
		IFS=$'\t' read -r dataset rc elapsed <<< "$row"
		if [ "$rc" -ne 0 ]; then
			fail=$((fail+1))
			printf ' \033[31m%-4s\033[0m' FAIL
		elif dataset_skipped "$dataset"; then
			skip=$((skip+1))
			printf ' \033[33m%-4s\033[0m' SKIP
		else
			pass=$((pass+1))
			printf ' \033[32m%-4s\033[0m' PASS
		fi
		printf '  %-24s  %6ss\n' "$dataset" "$elapsed"
	done

	echo
	printf ' Total: %d   \033[32mPassed: %d\033[0m   \033[31mFailed: %d\033[0m   \033[33mSkipped: %d\033[0m\n' \
		"$((pass+fail+skip))" "$pass" "$fail" "$skip"

	if [ "$fail" -gt 0 ]; then
		echo
		printf '\033[1;31m FAILURES\033[0m\n'
		for row in "${RESULTS[@]}"; do
			IFS=$'\t' read -r dataset rc elapsed <<< "$row"
			[ "$rc" -eq 0 ] && continue
			found=0
			while IFS=$'\t' read -r _ d test out status _ _ result; do
				[ "$d" == "$dataset" ] && [ "$result" == "fail" ] || continue
				found=1
				if [ "$status" != "0" ]; then
					signame=""
					[ "$status" -gt 128 ] 2>/dev/null && signame=$(kill -l $((status - 128)) 2>/dev/null)
					reason="ODM exited $status${signame:+ (SIG$signame)}"
				else
					reason="ODM exited 0, a post-run check failed"
				fi
				printf ' %s / %s: %s\n' "$dataset" "$test" "$reason"
				printf '   log: %stask_output.txt\n' "$out"
			done < "$OATS_MANIFEST"
			[ "$found" -eq 0 ] && \
				printf ' %s: a test failed before ODM ran (see the bats output above)\n' "$dataset"
		done
	fi

	echo
	printf ' JUnit reports: %s/\n' "$REPORT_DIR"
}

write_run_manifest(){
	local manifest="$RUN_DIR/run_manifest.json"
	local gpu tests datasets

	gpu=$(nvidia-smi -L 2>/dev/null | head -1)

	tests=$(jq -Rs --arg run_dir "$RUN_DIR/" '
		split("\n") |
		map(select(length > 0) | split("\t") | {
			tag: .[0],
			dataset: .[1],
			test: .[2],
			output_dir: (.[3] | ltrimstr($run_dir)),
			odm_exit_status: (.[4] | tonumber? // null),
			wall_time_s: (.[5] | tonumber? // 0),
			result_dir_bytes: (.[6] | tonumber? // 0),
			passed: (.[7] == "pass") })' "$OATS_MANIFEST")

	datasets=$(printf '%s\n' "${RESULTS[@]}" | jq -Rs 'split("\n") |
		map(select(length > 0) | split("\t") | {
		dataset: .[0], bats_exit: (.[1] | tonumber), wall_time_s: (.[2] | tonumber) })')

	jq -n \
		--arg run_key "$RUN_KEY" \
		--arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg image "$IMG" \
		--arg image_id "$IMAGE_ID" \
		--arg image_digest "$IMAGE_DIGEST" \
		--arg odm_git_revision "$ODM_REV" \
		--arg oats_git_hash "$(git rev-parse HEAD 2>/dev/null)" \
		--arg kernel "$(uname -sr)" \
		--argjson total_ram_bytes "$(awk '/MemTotal/ { print $2 * 1024; exit }' /proc/meminfo)" \
		--arg gpu "$gpu" \
		--arg group "$POSITIONAL" \
		--arg argv "$OATS_ARGV" \
		--argjson datasets "$datasets" \
		--argjson tests "$tests" \
		'{ run_key: $run_key, timestamp: $timestamp, image: $image, image_id: $image_id,
		   image_digest: $image_digest, odm_git_revision: $odm_git_revision,
		   oats_git_hash: $oats_git_hash,
		   host: { kernel: $kernel, total_ram_bytes: $total_ram_bytes, gpu: $gpu },
		   group: $group, argv: $argv,
		   datasets: $datasets, tests: $tests }' > "$manifest"

	echo
	printf ' Run manifest: %s\n' "$manifest"
}
