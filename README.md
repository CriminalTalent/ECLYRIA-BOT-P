# 🧙‍♂️ Professor Bot

**Professor Bot**은 마스토돈 기반 마법학교 커뮤니티에서 운영되는 출석 및 과제 시스템을 담당하는 봇입니다. Google 스프레드시트와 연동되어 유저 출석 확인, 과제 제출 처리, 갈레온 지급, 기숙사 점수 반영 기능을 자동화합니다.

---

## 📌 기능 개요

| 명령어 | 기능 |
|--------|------|
| `[입학/이름]` | 사용자 등록 및 초기 갈레온 지급 (20G) |
| `[출석]` | 하루 1회, 2갈레온 + 기숙사 점수 1점 지급 (밤 10시 이전만 가능) |
| `[과제]` | 과제 제출 시 5갈레온 + 기숙사 점수 3점 지급 |
| 자동 날씨 안내 | 출석 시 겨울철 날씨와 주의사항이 랜덤으로 안내됨 |
| 출석 ON/OFF | `교수` 시트의 `출석기능` 열로 봇 작동 제어 |
| 기숙사 점수 반영 | 유저가 등록한 기숙사에 따라 점수 자동 누적 |

---

## 📁 Google 시트 구조

- `사용자` 시트
  - A열: ID (@username)
  - B열: 이름
  - C열: 갈레온
  - G열: 기숙사명
  - I열: 마지막 출석일

- `교수` 시트
  - A열: 항목명 (`출석기능`)
  - B열: 값 (`on` 또는 `off`)

- `기숙사` 시트
  - A열: 기숙사명
  - B열: 현재 점수

---

## ⚙️ 환경변수 (.env)

```env
GOOGLE_CREDENTIALS_PATH=config.json
GOOGLE_SHEET_ID=your_sheet_id_here
MASTODON_BASE_URL=https://your.mastodon.server
MASTODON_ACCESS_TOKEN=your_access_token
