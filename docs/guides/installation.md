# 설치와 권한

macOS 14 이상(Apple Silicon 또는 Intel)이 필요합니다.

[Kswiftin/K-MON 릴리스](https://github.com/Kswiftin/K-MON/releases)에서 `Pokedoro.zip`을 받아 압축을 풀고 `Pokédoro.app`을 `/Applications`로 드래그합니다.

릴리스 앱에는 서명이 포함되어 있습니다. 최초 실행 시 Gatekeeper 확인이 표시되면 다음 방법 중 하나로 한 번 열어 주세요.

- **Finder:** `Pokédoro.app`을 Control-클릭 → **열기** → 대화상자에서 다시 **열기**.
- **터미널:** `xattr -dr com.apple.quarantine /Applications/Pokédoro.app`

배틀 신청용 알림과 LAN 탐색용 로컬 네트워크 접근 권한은 표시될 때 허용해 주세요. 한 번 허용하면
이후 버전 업그레이드에서 다시 묻지 않습니다 — 릴리스는 버전이 바뀌어도 같은 서명 신원을 씁니다.
배틀을 쓰지 않는다면 **설정 → 알림 → 배틀 신청 받기**를 끄면 LAN 탐색을 아예 시작하지 않아
로컬 네트워크 권한을 묻지 않습니다.

**설정 → 알림 → 근처 기기에 내 존재 알리기(실험)** 는 기본값이 꺼짐입니다. 켜면 블루투스로
신호만 내보내 근처의 다른 Pokédoro 가 "옆에 누가 있다" 를 알 수 있게 합니다. 내보내는 것은
실행할 때마다 새로 뽑는 임의의 8자리 이름뿐이고, 트레이너 이름·식별자·세이브는 싣지 않으며
받지도 않습니다. 켤 때만 블루투스 권한을 묻습니다.



소스에서 실행하려면 [개발 환경과 검증](../development/setup.md)을 참고하세요.
