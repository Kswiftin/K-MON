<div align="center">

<img src="assets/icon.png" width="128" alt="Pokédoro 아이콘">

# Pokédoro · 포케도로

**뽀모도로 집중과 포켓몬 모험을 결합한 macOS 메뉴바 게임**

[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

[English](README.en.md) · **한국어** · [日本語](README.ja.md)

</div>

Pokédoro는 집중하는 동안 포켓몬 파트너를 모험에 보내고, 수집한 포켓몬으로 배틀과 포켓슬론을 즐기는 메뉴바 앱입니다. 평소에는 메뉴바에 `휴식 중` 또는 타이머만 표시되어 업무 중에도 자연스럽게 사용할 수 있습니다.

> 비공식·비상업 포켓몬 팬 프로젝트입니다. 포켓몬 데이터와 스프라이트는 런타임에 [PokéAPI](https://pokeapi.co/)에서 불러옵니다.

## 핵심 동작

1. 25분·50분·90분 중 집중 시간을 선택하면 현재 파트너가 같은 시간의 모험을 떠납니다.
2. 모험이 완료되면 보상을 직접 수령합니다. 수령할 때 경험치와 별의조각을 얻으며, 긴 집중일수록 보상이 커집니다. 앱을 켜 둔 시간은 기록되지만 별의조각이 자동으로 지급되지는 않습니다.
3. 완료한 세션에서는 알 조각을 얻고 신비한 알을 발견할 기회도 있습니다. 조각 10개는 알 1개가 되며, 그날 첫 모험에서는 조각을 하나 더 얻고 주간 모험 10회에는 보너스 알을 얻습니다.
4. 경험치로 파트너의 레벨을 올리고, 별의조각은 상점 구매와 랭크 배틀 판돈에 사용합니다. 홈에는 모험 수령·집중 시간·졸업을 세는 일간·주간 미션이, 도감에는 종·타입·이로치 수집 목표가 표시됩니다.

집중 중에는 방해금지 모드를 켤 수 있습니다. 시스템 알림, 플로팅 펫, 수신 배틀 신청을 막습니다.

## 배틀과 포켓슬론

- **LAN 배틀** — Bonjour로 같은 로컬 네트워크의 사용자를 찾아 신청합니다. 상대는 직접 수락하며, 신청을 받으면 알림을 띄울 수 있습니다. 배틀 중에는 창이 고정되어 열려 있습니다.
- **CPU 연습과 랭크 배틀** — CPU를 상대로 1대1·3대3·6대6을 연습하고 출전 포켓몬과 순서를 고를 수 있습니다. LAN 랭크 배틀은 Lv.50으로 보정되고, CPU 연습은 키운 레벨로 진행합니다.
- **배틀 규칙** — 타입 상성, STAB, 물리·특수 능력치, 명중, 급소, PP, 기술 우선도, 상태이상 6종, 혼란을 반영합니다.
- **체육관과 능력 랭크 변화** — 4개 타입 체육관에 3대3으로 도전하고 각 체육관의 첫 승리 보상을 받습니다. 공격·방어·특공·특방·스피드·명중·회피는 배틀 중 오르내리며, 교체하면 초기화됩니다.
- **팀 배틀과 턴 재생** — LAN 배틀도 고른 팀과 순서로 진행합니다. 확정된 턴은 한 수씩 재생되며, 설정에서 재생 속도를 고를 수 있습니다.
- **포켓슬론: 체인지릴레이** — 혼자 연습하거나 로컬 네트워크에서 최대 4명이 레이스할 수 있습니다. `→`로 달리고 `↑`·`↓`로 레인을 바꾸며, 장애물을 피하고 `C`로 포켓몬을 교체합니다.

## 화면 둘러보기

<table>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-home.gif" width="260" alt="집중 타이머와 모험 조작이 있는 홈 화면"></td>
<td width="55%" valign="middle">
<h3>집중, 모험, 보상 수령</h3>
집중 시간을 고르고 파트너의 모험을 확인한 다음, 홈에서 완료 보상을 수령합니다.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>포켓몬과 도감</h3>
보유 포켓몬을 확인하고 파트너를 교체하며, 기술·경험치와 발견한 종을 볼 수 있습니다.
</td>
<td width="45%" align="center"><img src="assets/screenshot-collection-pokedex.png" width="220" alt="도감"><br><br><img src="assets/screenshot-collection-catchlog.png" width="220" alt="포켓몬 수집 기록"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-shop-ko.png" width="220" alt="상점"></td>
<td width="55%" valign="middle">
<h3>상점과 가방</h3>
별의조각으로 알, 이상한 사탕, 민트, 연결의끈, 진화의 돌을 구매하고 가방의 아이템을 사용합니다.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>작업과 업데이트 설정</h3>
설정에서 방해금지, 알림, 로그인 시 실행, 플로팅 펫, 업데이트 확인을 관리합니다.
</td>
<td width="45%" align="center"><img src="assets/settings-ko.png" width="220" alt="설정"></td>
</tr>
</table>

> 스크린샷은 최신 UI와 다를 수 있습니다. 캡션은 현재 앱에서 확인 가능한 기능만 설명합니다.

## 설치와 빌드

macOS 14 이상(Apple Silicon 또는 Intel)이 필요합니다.

[Kswiftin/K-MON 릴리스](https://github.com/Kswiftin/K-MON/releases)에서 `Pokedoro.zip`을 받아 압축을 풀고 `Pokédoro.app`을 `/Applications`로 드래그합니다.

릴리스 앱에는 서명이 포함되어 있습니다. 최초 실행 시 Gatekeeper 확인이 표시되면 다음 방법 중 하나로 한 번 열어 주세요.

- **Finder:** `Pokédoro.app`을 Control-클릭 → **열기** → 대화상자에서 다시 **열기**.
- **터미널:** `xattr -dr com.apple.quarantine /Applications/Pokédoro.app`

배틀 신청용 알림과 LAN 탐색용 로컬 네트워크 접근 권한은 표시될 때 허용해 주세요.

소스에서 빌드하려면 다음을 실행합니다.

```bash
swift build
./scripts/build-app.sh
```

`build-app.sh`는 `/Applications/Pokédoro.app`을 생성·설치합니다(설치를 생략하면 `build/Pokédoro.app`).

## 데이터, 개인정보와 면책

- 진행 데이터와 캐시는 `~/Library/Application Support/PokeTokenBar/`에 저장됩니다.
- 배틀과 포켓슬론은 로컬 네트워크의 피어 투 피어 연결을 사용합니다. 종·진화·기술·스프라이트 데이터는 PokéAPI와 관련 정적 에셋 호스트에서 가져오며, GitHub로 업데이트를 확인합니다.
- 소스 코드는 [MIT License](LICENSE)로 제공됩니다. Pokédoro는 닌텐도, 게임프리크, 크리처스, 포켓몬 컴퍼니와 제휴·보증·후원·승인 관계가 없습니다. 포켓몬 관련 이름·캐릭터·이미지의 권리는 각 권리자에게 있습니다.
