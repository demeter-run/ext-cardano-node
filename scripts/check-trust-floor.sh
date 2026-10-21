#!/bin/sh
# Fails when Cargo.lock carries a TLS trust crate below its minimum version.
set -eu

lock="${1:-$(dirname "$0")/../Cargo.lock}"

awk '
  function below(v, min,    a, b, n, i, x, y) {
    sub(/[-+].*/, "", v)
    n = split(v, a, ".")
    split(min, b, ".")
    for (i = 1; i <= 3; i++) {
      x = (i <= n) ? a[i] + 0 : 0
      y = b[i] + 0
      if (x < y) return 1
      if (x > y) return 0
    }
    return 0
  }
  BEGIN {
    floor["webpki-roots"] = "1.0.10"
    floor["webpki-root-certs"] = "1.0.10"
    floor["rustls-webpki"] = "0.103.16"
    bad = 0
  }
  /^name = / { name = $3; gsub(/"/, "", name); next }
  /^version = / {
    version = $3; gsub(/"/, "", version)
    if ((name in floor) && below(version, floor[name])) {
      printf "%s %s is below the trust floor %s\n", name, version, floor[name]
      bad = 1
    }
    name = ""
  }
  END { exit bad }
' "$lock"
