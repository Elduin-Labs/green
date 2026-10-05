#!/bin/sh
# Builds Green.app. Then double-click Green.app to start him.
cd "$(dirname "$0")" || exit 1
swiftc -O Green.swift -o Green.app/Contents/MacOS/Green
