#!/bin/sh
set -eu
test -f vulnerability-reports/scan.complete
[ "${CI_PIPELINE_SOURCE:-}" != merge_request_event ] || exit 0
rm vulnerability-reports/scan.complete
test "${CI_JOB_STATUS:-success}" = success
lock=vulnerability-source/build/upstream/ownCloud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
mkdir -p .scan
jq -e '
  if .version != 3 or (.pins | length) == 0 then error("Missing Swift pins") else . end |
  {bomFormat: "CycloneDX", specVersion: "1.5", version: 1, components: [.pins[] |
    if .kind != "remoteSourceControl" or (.state.revision | test("^[a-f0-9]{40}$") | not)
    then error("Unsupported Swift pin") else . end |
    (.location | ltrimstr("https://") | rtrimstr(".git")) as $name |
    (.state.version // .state.revision) as $version |
    {type: "library", name: $name, version: $version,
     purl: ("pkg:swift/" + $name + "@" + $version),
     properties: [{name: "aity.tech/source-revision", value: .state.revision}]}]}
' "$lock" > vulnerability-reports/swift.cdx.json
trivy sbom --config /dev/null --ignorefile /dev/null --scanners vuln \
  --ignore-unfixed=false --exit-code 0 --format json --list-all-pkgs \
  --output .scan/trivy-swift.json vulnerability-reports/swift.cdx.json
jq -e --slurpfile bom vulnerability-reports/swift.cdx.json '
  [.Results[]? | select(.Type == "swift") | .Packages[]? | .Identifier.PURL] as $scanned |
  [$bom[0].components[].purl] - $scanned | length == 0
' .scan/trivy-swift.json >/dev/null
jq -s --arg lock "$lock" '
  .[0].Results = ([.[0].Results[]? | select(.Target != $lock)] +
    [.[1].Results[] | .Target = $lock]) | .[0]
' vulnerability-reports/trivy-source.json .scan/trivy-swift.json > vulnerability-reports/trivy-source.tmp
mv vulnerability-reports/trivy-source.tmp vulnerability-reports/trivy-source.json
digest=$(sha256sum vulnerability-reports/trivy-source.json)
count=$(jq '[.Results[]? | (.Vulnerabilities // []) | length] | add // 0' vulnerability-reports/trivy-source.json)
jq --arg sha256 "${digest%% *}" --argjson count "$count" '
  map(if .file == "trivy-source.json" then .sha256 = $sha256 | .finding_count = $count else . end)
' vulnerability-reports/reports.manifest > vulnerability-reports/reports.manifest.tmp
mv vulnerability-reports/reports.manifest.tmp vulnerability-reports/reports.manifest
touch vulnerability-reports/scan.complete
