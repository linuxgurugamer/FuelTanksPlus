#!/usr/bin/env bash

# Usage:
#   ./ksp_parts_to_csv.sh GameData > parts.csv
#   ./ksp_parts_to_csv.sh path1 path2 > parts.csv
#   ./ksp_parts_to_csv.sh . > parts.csv

set -euo pipefail

root_args=("$@")
if [ ${#root_args[@]} -eq 0 ]; then
  root_args=(".")
fi

echo "name,mass,bulkheadProfiles,LiquidFuel,LiquidFuel_max,Oxidizer,Oxidizer_max,Monopropellant,Monopropellant_max"

find "${root_args[@]}" -type f -name "*.cfg" -print0 |
while IFS= read -r -d '' file; do
  awk '
  function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
  function strip_comments(s) {
      sub(/\/\/.*/, "", s)   # strip // comments
      sub(/#.*/, "", s)      # strip # comments (rare, but harmless)
      return s
  }
  function reset_part() {
      name=""; mass=""; bulkhead=""
      lf=0; lfmax=0
      ox=0; oxmax=0
      mp=0; mpmax=0
  }
  function reset_res() {
      resName=""; resAmt=""; resMax=""
  }
  function finalize_res() {
      # Only sum if numeric; if blank, treat as 0
      if (resAmt == "") resAmt = 0
      if (resMax == "") resMax = 0

      if (resName == "LiquidFuel")      { lf    += resAmt; lfmax  += resMax }
      else if (resName == "Oxidizer")   { ox    += resAmt; oxmax  += resMax }
      else if (resName == "MonoPropellant") { mp += resAmt; mpmax  += resMax }
  }
  function finalize_part() {
      # Print even if some fields are missing; only print if we actually saw a PART block
      print name "," mass "," bulkhead "," lf "," lfmax "," ox "," oxmax "," mp "," mpmax
  }

  BEGIN {
      depth = 0

      pendingPart = 0
      inPart = 0
      partStartDepth = -1

      pendingRes = 0
      inRes = 0
      resStartDepth = -1

      reset_part()
      reset_res()
  }

  {
      raw=$0
      line=strip_comments(raw)
      line=trim(line)
      if (line == "") next

      # Token checks before brace updates (so PART / RESOURCE on same line works)
      if (!inPart) {
          if (line ~ /^PART([ \t]*\{)?$/) {
              pendingPart = 1
              # If it is "PART {", we will see { below and enter part immediately
          }
      } else {
          # Inside a PART: RESOURCE blocks can start at top level of the PART (depth == partStartDepth)
          if (!inRes && depth == partStartDepth) {
              if (line ~ /^RESOURCE([ \t]*\{)?$/) {
                  pendingRes = 1
              }
          }

          # Capture top-level fields (only when at top of PART, not inside sub-nodes)
          if (!inRes && depth == partStartDepth) {
              if (line ~ /^name[ \t]*=/) {
                  split(line, a, "="); name=trim(a[2])
              } else if (line ~ /^mass[ \t]*=/) {
                  split(line, a, "="); mass=trim(a[2])
              } else if (line ~ /^bulkheadProfiles[ \t]*=/) {
                  split(line, a, "="); bulkhead=trim(a[2])
              }
          }

          # Inside RESOURCE block: read name/amount/maxAmount
          if (inRes) {
              if (line ~ /^name[ \t]*=/) {
                  split(line, a, "="); resName=trim(a[2])
              } else if (line ~ /^amount[ \t]*=/) {
                  split(line, a, "="); resAmt=trim(a[2])
              } else if (line ~ /^maxAmount[ \t]*=/) {
                  split(line, a, "="); resMax=trim(a[2])
              }
          }
      }

      # Count braces on this line (can be multiple)
      opens = gsub(/\{/, "{", line)
      closes = gsub(/\}/, "}", line)

      # Enter PART when pendingPart and an opening brace occurs
      if (pendingPart && opens > 0) {
          pendingPart = 0
          inPart = 1
          reset_part()
          # After applying opens below, depth will increase; the PART top-level depth will be the new depth
          # We set partStartDepth after updating depth.
          markPartStart = 1
      } else {
          markPartStart = 0
      }

      # Enter RESOURCE when pendingRes and an opening brace occurs
      if (inPart && pendingRes && opens > 0) {
          pendingRes = 0
          inRes = 1
          reset_res()
          markResStart = 1
      } else {
          markResStart = 0
      }

      # Apply brace depth changes
      depth += opens

      if (markPartStart) {
          partStartDepth = depth   # top-level inside PART
      }
      if (markResStart) {
          resStartDepth = depth    # depth inside RESOURCE
      }

      # Apply closing braces (note: do after possible content capture above)
      for (k=1; k<=closes; k++) {
          # If we are about to leave a RESOURCE block, finalize it
          if (inRes && depth == resStartDepth) {
              finalize_res()
              inRes = 0
              resStartDepth = -1
          }

          # If we are about to leave a PART block, finalize it
          if (inPart && !inRes && depth == partStartDepth) {
              finalize_part()
              inPart = 0
              partStartDepth = -1
          }

          depth--
          if (depth < 0) depth = 0
      }
  }
  ' "$file"
done


