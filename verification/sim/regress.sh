#!/usr/bin/env bash
set -euo pipefail

sim_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tests=(
  axi_basic_test axi_routing_test axi_protocol_test axi_burst_size_test
  axi_outstanding_test axi_multi_master_test axi_same_slave_test
  axi_interleave_test axi_boundary_test axi_backpressure_test
  axi_error_test axi_random_test axi_random_concurrent_test
  axi_perf_test axi_reset_test axi_full_routing_test
)

make -C "$sim_dir" compile "${@}"
failed=()
for test_name in "${tests[@]}"; do
  if ! make -C "$sim_dir" run "${@}" UVM_TEST="$test_name"; then
    failed+=("$test_name")
  fi
done

if ((${#failed[@]})); then
  printf 'Regression failed (%d/%d): %s\n' "${#failed[@]}" "${#tests[@]}" "${failed[*]}" >&2
  exit 1
fi
printf 'Regression passed (%d/%d tests)\n' "${#tests[@]}" "${#tests[@]}"
