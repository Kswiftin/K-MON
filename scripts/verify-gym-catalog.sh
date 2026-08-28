#!/usr/bin/env bash
# verify-gym-catalog.sh — 체육관 카탈로그를 PokéAPI 실제 데이터와 대조한다.
#
# 관장 종 id·기술 이름은 손으로 적는 값이라 오타가 조용히 지나간다. 틀린 종 id 는 엉뚱한
# 포켓몬을 세우고, 틀린 기술 이름은 그 종만 자동 선발로 돌아가 난이도가 달라진다 —
# 둘 다 컴파일도 테스트도 통과한다.
#
# CI 에는 넣지 않는다. 외부 API 에 의존하는 검사를 CI 에 두면 pokeapi.co 가 흔들릴 때
# 무관한 PR 이 빨개진다. 카탈로그를 손댈 때 사람이 돌리는 도구다.
#
# 사용: ./scripts/verify-gym-catalog.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CATALOG="Sources/PokeTokenBar/Core/GymLeague.swift"
CACHE="${TMPDIR:-/tmp}/kmon-gym-verify"
mkdir -p "$CACHE/mon" "$CACHE/move"

fetch() {  # fetch <종류> <키> → 캐시 경로(실패 시 빈 문자열)
    local kind=$1 key=$2 path="$CACHE/$1/$2.json"
    if [[ ! -s "$path" ]]; then
        curl -sf --max-time 15 "https://pokeapi.co/api/v2/$kind/$key" -o "$path" || { rm -f "$path"; return 1; }
    fi
    [[ -s "$path" ]] && echo "$path"
}

python3 - "$CATALOG" "$CACHE" <<'PY'
import json, re, subprocess, sys, pathlib
catalog_path, cache = sys.argv[1], pathlib.Path(sys.argv[2])
src = pathlib.Path(catalog_path).read_text()

level = int(re.search(r"leaderLevel = (\d+)", src).group(1))
blocks = re.findall(
    r"Gym\(type: \.(\w+),(.*?)teamSpeciesIDs: \[([^\]]+)\](.*?)teamMoveNames: \[(.*?)\n            \]",
    src, re.S)

def get(kind, key):
    p = subprocess.run(["curl", "-sf", "--max-time", "15",
                        f"https://pokeapi.co/api/v2/{kind}/{key}"], capture_output=True)
    if p.returncode != 0:
        return None
    return json.loads(p.stdout)

problems = 0
print(f"관장 레벨 {level}\n")
for gym_type, _before_team, ids_raw, between_team_and_moves, moves_raw in blocks:
    ids = [int(x.strip()) for x in ids_raw.split(",") if x.strip()]
    rows = re.findall(r"\[([^\]]*)\]", moves_raw)
    teams = [[m.strip().strip('"') for m in r.split(",") if m.strip()] for r in rows]
    ace_match = re.search(r"aceSpeciesID:\s*(\d+)", between_team_and_moves)
    ace_id = int(ace_match.group(1)) if ace_match else None
    if ace_id is not None and ace_id != ids[-1]:
        print(f"  ✗ aceSpeciesID #{ace_id}: 팀의 마지막 상대여야 한다")
        problems += 1
    total = 0
    print(f"=== {gym_type} ===")
    for i, pid in enumerate(ids):
        mon = get("pokemon", pid)
        if mon is None:
            print(f"  ✗ #{pid} 조회 실패"); problems += 1; continue
        own = [t["type"]["name"] for t in mon["types"]]
        bst = sum(s["base_stat"] for s in mon["stats"])
        total += bst
        flag = "" if gym_type in own else (
            "   ← 타입 밖 전설 에이스" if pid == ace_id else "   ← 체육관 타입 아님")
        print(f"  {mon['name']:<12} #{pid:<4} {'/'.join(own):<14} 종족값 {bst}{flag}")
        if gym_type not in own and pid != ace_id:
            problems += 1
        for name in (teams[i] if i < len(teams) else []):
            mv = get("move", name)
            if mv is None:
                print(f"      ✗ {name}: 그런 기술이 없다 → 자동 선발로 떨어진다"); problems += 1; continue
            power = mv.get("power") or 0
            acc = mv.get("accuracy")
            ail = (mv.get("meta") or {}).get("ailment", {}).get("name")
            star = "★" if mv["type"]["name"] in own else " "
            extra = f" 상태이상:{ail}" if ail and ail != "none" else ""
            warn = ""
            if power == 0:
                warn = "   ← 위력 0(변화기): 엔진이 효과를 못 낸다"; problems += 1
            elif power >= 120:
                warn = "   ← 위력이 매우 높다(반동·자폭은 엔진 미구현)"
            print(f"      {star} {name:<18} {mv['type']['name']:<9} 위력 {power:<4} 명중 {acc if acc else '-'}{extra}{warn}")
    print(f"  → 팀 종족값 합 {total}\n")
print("문제 없음" if problems == 0 else f"확인 필요 {problems}건")
sys.exit(1 if problems else 0)
PY
