#!/usr/bin/env bash
set -euo pipefail

tccutil reset ScreenCapture com.benmkramer.ScreenshotMaxxing
tccutil reset All com.benmkramer.ScreenshotMaxxing
mdls -name kMDItemCFBundleIdentifier /Applications/ScreenshotMaxxing.app
