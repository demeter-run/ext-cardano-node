#!/bin/bash
#
# Usage: readiness.sh [MAX_TIP_AGE_SECONDS]
#
# Passes while syncProgress is within 99-100. syncProgress has two decimals, so
# on mainnet it still reads 99 or more with a tip weeks old. MAX_TIP_AGE_SECONDS
# adds a check that the tip is no older than that many seconds of wall clock.

MAX_TIP_AGE_SECONDS="$1"

if [ -n "$MAX_TIP_AGE_SECONDS" ] && ! [[ "$MAX_TIP_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MAX_TIP_AGE_SECONDS must be a positive integer, got '$MAX_TIP_AGE_SECONDS'"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to use this script."
    exit 1
fi

if ! command -v cardano-cli &> /dev/null; then
    echo "Error: cardano-cli is not installed. Please install cardano-cli to use this script."
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "Error: bc is not installed. Please install bc to use this script."
    exit 1
fi

if [ "$CARDANO_NODE_NETWORK_ID" == "764824073" ]; then
    NETWORK_ARGS=(--mainnet)
else
    NETWORK_ARGS=(--testnet-magic "$CARDANO_NODE_NETWORK_ID")
fi

JSON_DATA=$(cardano-cli query tip "${NETWORK_ARGS[@]}")

SYNC_PROGRESS=$(echo "$JSON_DATA" | jq -r '.syncProgress')
MIN_EXPECTED_SYNC_PROGRESS="99.00"
MAX_EXPECTED_SYNC_PROGRESS="100.00"

if (( $(echo "$SYNC_PROGRESS >= $MIN_EXPECTED_SYNC_PROGRESS" | bc -l) )) && (( $(echo "$SYNC_PROGRESS <= $MAX_EXPECTED_SYNC_PROGRESS" | bc -l) )); then
    echo "syncProgress is within the acceptable range of 99 to 100"
else
    echo "Error: syncProgress is not within the acceptable range of 99 to 100"
    exit 1
fi

if [ -z "$MAX_TIP_AGE_SECONDS" ]; then
    exit 0
fi

# Compare slots rather than converting the tip to a time: the node's own era
# history maps the oldest accepted time to a slot, whatever the slot length.
# The conversion fails when that time is past the node's forecast horizon
# (about 36 h ahead of its tip on mainnet), which only happens to a stale node.
TIP_SLOT=$(echo "$JSON_DATA" | jq -r '.slot')
OLDEST_ACCEPTED_TIME=$(date -u -d "@$(( $(date +%s) - MAX_TIP_AGE_SECONDS ))" +%Y-%m-%dT%H:%M:%SZ)

if ! OLDEST_ACCEPTED_SLOT=$(cardano-cli query slot-number "${NETWORK_ARGS[@]}" "$OLDEST_ACCEPTED_TIME"); then
    echo "Error: could not convert $OLDEST_ACCEPTED_TIME to a slot; the tip is too old"
    exit 1
fi

if (( TIP_SLOT < OLDEST_ACCEPTED_SLOT )); then
    echo "Error: tip slot $TIP_SLOT is older than $MAX_TIP_AGE_SECONDS s (slot $OLDEST_ACCEPTED_SLOT)"
    exit 1
fi

echo "tip slot $TIP_SLOT is within $MAX_TIP_AGE_SECONDS s of now"
