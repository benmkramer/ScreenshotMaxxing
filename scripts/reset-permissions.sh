#!/usr/bin/env bash
set -euo pipefail

for bundle_id in \
  com.benmkramer.ScreenshotMaxxing \
  com.benmkramer.ScreenshotMaxxing.dev
do
  tccutil reset ScreenCapture "$bundle_id"
  tccutil reset All "$bundle_id"
done

mdls -name kMDItemCFBundleIdentifier /Applications/ScreenshotMaxxing.app
