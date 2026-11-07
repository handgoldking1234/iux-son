# 우리 가계도 (iux-son) — 작업 안내서

## 한 줄 요약
밀양손씨 목사공파 가계도 웹앱. 촌수·호칭 자동 계산, 가로/세로 트리, 표 편집. 단일 HTML + Supabase.

- 주소: https://son.iux.kr
- 설정 안내: `supabase-설정.md`, `배포방법.md`

## 확정된 결정
| 항목 | 결정 |
|---|---|
| 목적 | 4촌·6촌 등 정확한 친인척 관계 정리. 단순하게, 본인 사용 먼저 |
| 편집 | **공개 편집** (로그인 없이 누구나 수정). 예전 로그인 방식(카카오·이메일 + 편집자 등록)은 `schema-login-version.sql`로 보관 |
| DB | 새 프로젝트 대신 기존 `iux-cloud` Supabase 프로젝트에 테이블을 얹음 (`schema-open.sql`) |
| 검색 노출 | 차단 (`robots.txt`, `vercel.json`의 `X-Robots-Tag: noindex`) |
| 오프라인 | `SB_URL`/`SB_KEY`를 비우면 localStorage만 사용 |

## 코드 지도 (index.html)
- 저장·동기화: `load`, `save`, `queuePush`, `updateSaveBadge`, `exportJSON`, `importJSON`
- 촌수 엔진: `chain`, `chon`(촌수), `callName`(호칭), `hangryeol`(항렬), `relText`, `isDesc`, `reparent`
- 트리: `layoutH`·`renderH`(가로), `renderV`(세로), `fit`, `zoomAt`
- 패널: `openPanel`, `infoHTML`, `ancPath`(직계 계보), `sibsOf`, `doDelete`, `doUndo`

## 데이터 주의
36대 '손사익'은 미확인(추정) — 대동보 대조 필요. 실제 가족 정보가 들어가므로 공개 범위를 넓히는 변경은 먼저 상의.

---

## 공통 작업 원칙 (IUX 프로젝트 전체)
- **언어:** 화면 문구·문서·커밋 메시지는 한국어. 쉬운 말, 기술 용어 최소화.
- **퍼블리싱 시안:** 순수 HTML/CSS + 간단한 스크립트만 넣는다. 서버·DB 연동 코드는 개발 단계에서 따로 붙인다.
- **아이콘:** Lucide. 디자인 시스템을 따로 정하지 않았으면 스포티파이 스타일(다크/화이트 + 포인트 컬러)을 기본으로 쓴다.
- **배포:** GitHub `main` → Vercel 자동 배포. 도메인은 가비아 `iux.kr`의 서브도메인(`*.iux.kr` CNAME → Vercel)을 쓴다.
- **DB:** Supabase 무료 플랜은 활성 프로젝트 2개까지라, 새 프로젝트를 만들지 말고 기존 `iux-cloud`(studio) 프로젝트에 테이블을 얹는 것을 먼저 검토한다.
- **비밀값:** 공개 저장소다. 서비스 키·AI 키·비밀번호는 절대 커밋하지 않는다. 키는 Vercel 환경 변수나 Supabase secrets에 둔다. Supabase anon(public) 키만 코드에 넣을 수 있다.
- **확인:** 고친 뒤에는 브라우저 콘솔 오류 0개, 모바일(390px)과 PC 화면을 눈으로 확인하고 나서 완료라고 한다.
- **브랜치:** `main`은 배포 중인 상태. 큰 작업이나 검증 전 작업은 브랜치(`wip/…`, `claude/…`)에 올리고, `main`을 강제 푸시(-f)로 덮어쓰지 않는다.
- **전체 프로젝트 목록:** https://github.com/handgoldking1234/iux-app/blob/main/docs/PROJECTS.md
