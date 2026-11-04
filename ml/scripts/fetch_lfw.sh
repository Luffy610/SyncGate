#!/usr/bin/env bash
# Downloads the LFW view-2 evaluation set into .cache/ml/lfw (git-ignored).
#   lfw.bin   - InsightFace-format 6,000 pairs, 112x112 aligned crops
#   pairs.txt - the official LFW pair list (gives the identity names)
# Both are pinned by SHA-256. lfw.bin is a pickle: it is never unpickled,
# only tokenised (ml/eval/lfw_bin.py).
# LFW: http://vis-www.cs.umass.edu/lfw/ - research use; never commit it.
set -euo pipefail
DEST="${1:-.cache/ml}/lfw"
mkdir -p "$DEST"

fetch() { # url file sha256
  if [[ -f "$DEST/$2" ]] && echo "$3  $DEST/$2" | sha256sum -c --quiet - 2>/dev/null; then
    return
  fi
  curl -fsSL --retry 4 --retry-delay 2 -o "$DEST/$2.part" "$1"
  echo "$3  $DEST/$2.part" | sha256sum -c --quiet -
  mv "$DEST/$2.part" "$DEST/$2"
}

fetch https://media.githubusercontent.com/media/dmitriykim/oz_forensics_test/HEAD/datasets/lfw.bin \
  lfw.bin 9b711dca71a47fc9f295a28514abe8cc4e457632a8d634264691398c99569593
fetch https://raw.githubusercontent.com/davidsandberg/facenet/master/data/pairs.txt \
  pairs.txt ea42330c62c92989f9d7c03237ed5d591365e89b3e649747777b70e692dc1592
echo "LFW ready in $DEST"
