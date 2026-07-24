#!/bin/sh
set -eu

# The Supervisor needs OPAMP_TOKEN, but the managed Collector does not. Never
# let a remotely managed Collector config expand or export the fleet credential.
unset OPAMP_TOKEN

# Feature gates configure the managed Collector, not the Supervisor process
# that runs as PID 1. The Helm chart serializes a validated list into this
# variable. Validate it again at the image boundary before turning it into a
# Collector argument; quoting prevents the value from being interpreted by the
# shell.
collector_feature_gates=${O11Y_COLLECTOR_FEATURE_GATES:-}
case "$collector_feature_gates" in
  "")
    ;;
  ,*|*,|*,,*|*[!A-Za-z0-9._,+-]*)
    echo "invalid O11Y_COLLECTOR_FEATURE_GATES value" >&2
    exit 64
    ;;
esac

exec_collector() {
  if [ -n "$collector_feature_gates" ]; then
    for argument in "$@"; do
      case "$argument" in
        --feature-gates|--feature-gates=*)
          echo "feature gates must be configured only through O11Y_COLLECTOR_FEATURE_GATES" >&2
          exit 64
          ;;
      esac
    done
    set -- "$@" "--feature-gates=$collector_feature_gates"
  fi

  exec /usr/local/bin/otelcol-contrib "$@"
}

# opampsupervisor 0.156.0 appends its currently effective --config when it
# invokes `otelcol validate` for a candidate configuration. If the current file
# is invalid, that makes every replacement fail validation as well. Validate
# only the candidate file; normal Collector commands remain unchanged.
if [ "${1:-}" = "validate" ] && [ "${2:-}" = "--config" ] && [ "$#" -ge 5 ]; then
  candidate_config=$3
  shift 3
  if [ "${1:-}" = "--config" ]; then
    shift 2
  fi
  exec_collector validate --config "$candidate_config" "$@"
fi

exec_collector "$@"
