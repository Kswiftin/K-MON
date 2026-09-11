#!/usr/bin/env bash
# ble-probe.sh 가 남긴 CSV 를 이슈 #342 의 중단 기준으로 판정한다.
#
#   scripts/ble-probe-report.sh .build/ble-probe/baseline.csv
#
# 재는 값과 기준:
#   rate   광고 도착 빈도(건/s).  2.0/s 미만 → 구역 감지(#342 의 2번 기능)를 접는다.
#   sd     정지 상태 표준편차 = 잡음.
#   drop   사람이 사이를 막았을 때의 낙폭(기준 평균 − 창 안 최저).
#          sd 의 3배 미만 → 역시 접는다. 노드를 늘려도 주기와 낙폭은 그대로다.
#   n/창   통과 1회당 표본 수. 1~2개면 통과를 아예 못 본다.
#
# 낙폭은 Enter 로 찍은 마크가 있어야 나온다. 마크가 없으면 기준선만 출력한다(정지 측정).
# 창은 마크 시각부터 2초, 앞뒤 1초는 어느 쪽에도 안 넣는다 — 통과 전후의 접근·이탈이
# 기준선을 오염시키면 낙폭이 실제보다 작게 나온다.
set -euo pipefail

CSV="${1:-}"
[ -n "$CSV" ] && [ -f "$CSV" ] || { echo "사용법: scripts/ble-probe-report.sh <csv>"; exit 1; }

awk -F, -v window=2000 -v guard=1000 '
NR == 1 { next }                       # 헤더
$2 == "MARK" { marks[++markCount] = $1; next }
{
  n++
  ts[n] = $1; peer[n] = $2; name[n] = $3; rssi[n] = $4
  if (first == 0 || $1 < first) first = $1
  if ($1 > last) last = $1
  seen[$2] = ($3 != "" ? $3 : $2)
}
END {
  if (n == 0) { print "표본이 없다 — 상대가 광고 중인지, 터미널에 블루투스 권한이 있는지 본다."; exit 1 }
  span = (last - first) / 1000.0
  blockedSeconds = markCount * (window + 2 * guard) / 1000.0
  baseSeconds = span - blockedSeconds
  if (baseSeconds < 1) baseSeconds = span        # 마크가 촘촘하면 근사가 무너진다 — 전체 구간으로 돌린다

  for (i = 1; i <= n; i++) {
    slot = 0                                     # 0=기준선 1=창 2=완충(버림)
    for (m = 1; m <= markCount; m++) {
      if (ts[i] >= marks[m] && ts[i] <= marks[m] + window) { slot = 1; hit = m; break }
      if (ts[i] >= marks[m] - guard && ts[i] <= marks[m] + window + guard) { slot = 2; break }
    }
    p = peer[i]
    if (slot == 0) { bn[p]++; bs[p] += rssi[i]; bq[p] += rssi[i] * rssi[i] }
    else if (slot == 1) {
      key = p SUBSEP hit
      wn[key]++
      if (!(key in wmin) || rssi[i] < wmin[key]) wmin[key] = rssi[i]
    }
  }

  printf "구간 %.1fs · 표본 %d · 노드 %d · 마크 %d\n\n", span, n, length(seen), markCount
  printf "%-10s %8s %8s %7s %8s %8s %s\n", "노드", "rate/s", "mean", "sd", "drop", "n/창", "판정"

  for (p in seen) {
    if (bn[p] < 2) continue
    mean = bs[p] / bn[p]
    var = bq[p] / bn[p] - mean * mean
    sd = (var > 0) ? sqrt(var) : 0
    rate = bn[p] / baseSeconds

    dropSum = 0; dropCount = 0; sampleSum = 0
    for (m = 1; m <= markCount; m++) {
      key = p SUBSEP m
      if (!(key in wn)) continue
      dropSum += mean - wmin[key]; dropCount++; sampleSum += wn[key]
    }

    verdict = (rate >= 2.0) ? "" : "rate<2.0"
    if (dropCount > 0) {
      drop = dropSum / dropCount
      perWindow = sampleSum / dropCount
      if (drop < 3 * sd) verdict = verdict (verdict ? " " : "") "drop<3sd"
      printf "%-10s %8.2f %8.1f %7.2f %8.1f %8.1f %s\n", seen[p], rate, mean, sd, drop, perWindow,
             (verdict ? "접는다: " verdict : "통과")
    } else {
      printf "%-10s %8.2f %8.1f %7.2f %8s %8s %s\n", seen[p], rate, mean, sd, "-", "-",
             (verdict ? "접는다: " verdict : "기준선만 — 마크를 찍고 다시 잰다")
    }
  }

  if (markCount == 0) {
    print "\n마크가 없다. 통과 측정은 scan 중 사람이 지나기 직전 Enter 를 눌러 찍는다."
  }
}
' "$CSV"
