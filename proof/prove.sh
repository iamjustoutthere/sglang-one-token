#!/usr/bin/env bash
set -eu
# Run at the repository root. Reuses the original prover session; replace the session ID with your own.
python proof/build_artifacts.py
intent-check prove --session a3627280-2af6-4efe-8492-01f45c278a3c \
  --spec inputs/sglang06/spec.k --spec-module RUN2-SGLANG06-SPEC
# Inspect task.result=proved, no task.error, and final tool exitCode=0.
# The following body mutation restores the original capacity and deliberately
# requires the failing 600/560/1/1 witness to be admitted. Expect notProved.
set +e
intent-check prove --session a3627280-2af6-4efe-8492-01f45c278a3c \
  --spec inputs/sglang06/mutation.k --spec-module RUN2-SGLANG06-MUTATION
mutation_exit=$?
set -e
test "$mutation_exit" -eq 1
# Exit status alone is insufficient. Inspect the retained residual and task result.
