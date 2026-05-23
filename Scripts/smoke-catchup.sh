#!/usr/bin/env bash
# Manual smoke for TASK-020 (F-20 Catch-up Scheduler).
# Requires app to be runnable: swift run CityDeveloper.
#
# Setup:
#   1. Clean state:
#      rm -f ~/Library/Application\ Support/CityDeveloper/{events.jsonl,state.json,catchup-state.json}
#   2. Run with mock source:
#      CITY_SMOKE_CATCHUP=1 swift run CityDeveloper
#
# Expected:
#   - On start: immediate scan creates one mock event → "Mock task #1" unit
#     appears on map within ~1 sec.
#   - After ~5 min (or the interval set in Settings): second mock event fires.
#   - On restart without CITY_SMOKE_CATCHUP=1: no new mock events (source not
#     registered), catchup-state.json unchanged.
#   - catchup-state.json contains "mock" key with lastCheckTs.
#
# Check after first run:
#   cat ~/Library/Application\ Support/CityDeveloper/catchup-state.json | jq .
#   → should show:
#     {
#       "sources": {
#         "mock": { "lastCheckTs": "<ISO8601>" }
#       },
#       "version": 1
#     }
#
# Check dedup (second run, no new events expected from same mock source):
#   CITY_SMOKE_CATCHUP=1 swift run CityDeveloper
#   → mock registers again, immediate scan fires → one more unit (by design,
#     MockEventSource always generates an event per scan; real sources would
#     check since timestamp and return empty when nothing is new).
#
# Check Settings interval change reschedules Timer:
#   1. Launch: CITY_SMOKE_CATCHUP=1 swift run CityDeveloper
#   2. Open Settings → set Catch-up interval to 3 min.
#   3. Observe errors.log if needed; after 3 min a new mock event fires.
#      tail -f ~/Library/Application\ Support/CityDeveloper/errors.log
#
# Normal mode (no mock):
#   swift run CityDeveloper
#   → app starts, no mock source, catchup-state.json stays as-is (or empty).
echo "Smoke instructions printed above. Run the app manually as described."
