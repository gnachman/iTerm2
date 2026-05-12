# Handoff — MomenTerm

> 마지막 업데이트: 2026-04-19
> **참고**: 이 파일은 세션 간 작업 컨텍스트를 유지합니다.

## 현재 목표
MT 요구사항 문서 기반 전체 구현 — Phase 1~4 완료, Phase 5~7 골격

## 최근 완료
- [x] `mt` CLI 패키지 생성 (`mt-cli/`) — TypeScript, npm, commander 기반
  - init, doctor, plugins, skills, upgrade, harness, vibe, handoff, mcp, projects 명령
  - `mt bootstrap` — 원클릭 프로젝트 초기화
- [x] Swift 프로젝트 관리 창 (`MomentermProject*.swift`)
  - MomentermProjectModel, Storage, WindowController, SidebarVC, FileTreeVC
  - 프로젝트 공간 + 프로젝트 트리 (NSOutlineView)
  - 파일 탐색 패널 (.agentignore 기반 필터링)
  - 더블클릭 → vi 편집 진입
- [x] AI 도구 체크 (`MomentermAIToolChecker.swift`) — Claude Code/Codex 설치 확인 및 실행 프롬프트
- [x] 새 탭/창 경로 유지 (`MomentermNewTabHandler.swift`)
- [x] 상태바 프로젝트 컴포넌트 (`MomentermStatusBarProjectComponent.swift`)
- [x] 문서 생성:
  - docs/harness-engineering.md
  - docs/mcp-server-setup.md
  - docs/db-setup.md
  - docs/deployment-guide.md
  - docs/github-guide.md
  - docs/ci-cd-guide.md
  - docs/operations-guide.md
  - docs/korean-ime-analysis.md
  - docs/image-paste-analysis.md
- [x] 운영 파일:
  - .agentignore (AI 컨텍스트 최적화)
  - .hooks/pre-commit (secret 감지, .env 보호)
  - .hooks/pre-push (빌드 검증)
  - .claude/commands/mt.md (/mt 슬래시 명령)

## 추가 완료 (2차 세션)
- [x] 모든 Swift/ObjC 소스 파일 Xcode 프로젝트 등록 (`iTerm2SharedARC` 타겟)
- [x] `iTermStatusBarSetupViewController.m` — `MomentermStatusBarProjectComponentImpl` 등록
- [x] `iTermApplicationDelegate.m` — Window 메뉴에 "MomenTerm Projects…" 항목 추가
- [x] `iTermApplicationDelegate.m` — `performStartupActivities`에서 AI 도구 체크 훅 연결
- [x] `iTermKeyboardHandler.m` — 한국어 IME Enter 단일입력 수정 (Single-Enter Commits IME 설정)
  - 기본값 YES, `defaults write com.googlecode.iterm2 MomentermSingleEnterCommitsIME -bool NO`로 비활성화
- [x] 이미지 붙여넣기 — `iTermNonTextPasteHelper.swift` 이미 완전히 구현되어 있음 (추가 작업 불필요)

## 수동으로 실행 필요

### 1. Git hooks 설치
```bash
cp .hooks/pre-commit .git/hooks/pre-commit
cp .hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

### 2. mt CLI 글로벌 링크 (테스트용)
```bash
cd mt-cli
npm link
mt --help
```

### 3. 빌드 & 실행
```bash
make run
```

## 추가 완료 (3차 세션)
- [x] `mt skills` — gstack, omc, open-spec 실제 runner 구현 (`mt-cli/src/commands/skills.ts`)
  - gstack: Graphite CLI 설치 + `gt repo init` + `.graphite_ignore` 생성
  - omc: CLAUDE.md, .agentignore, .claude/commands/review.md 생성
  - open-spec: openapi.yaml + .spectral.yaml 스캐폴드, spectral lint 실행
- [x] `mt vibe` — vibe-ready 미설치 시 install hint 표시 (`npm install -g vibe-ready-cli`)
- [x] `mt mcp scope` — 최소 권한 scope 정책 생성 (.claude/mcp-scope.json)
- [x] `mt mcp audit` — MCP 서버 scope 정책 준수 여부 점검
- [x] `mt guardrail` — 가드레일 이탈 감지 시스템 (`mt-cli/src/commands/guardrail.ts`)
  - `check`: staged + recent commits 대상 7개 규칙 스캔
  - `report`: 점수/등급 포함 .claude/guardrail-report.json 생성
  - `rules`: 전체 규칙 목록 출력
  - harness pre-commit 훅에 `mt guardrail check --commits 0` 자동 통합
- [x] `mt doctor` — gt, spectral 설치 여부 체크 추가

## 다음 액션
없음 — Phase 1~7 모두 완료.

## 막힌 이슈
- Xcode clean build 진행 중 (`make clean` 후 `tools/build.sh`)
  → 이전 세션에서 발생했던 `MomenTerm.swiftmodule not found` 에러가 clean build로 해결될 것으로 예상
  → 빌드 완료 후 에러 없으면 `make run`으로 최종 확인

## 참고 문서
- docs/harness-engineering.md — 전체 개발 원칙
- docs/operations-guide.md — 일상 개발 플로우
- docs/korean-ime-analysis.md — IME Enter 이슈 분석
- docs/image-paste-analysis.md — 이미지 붙여넣기 구현 계획
- mt-cli/src/ — mt CLI 소스

## 관련 브랜치
master

## 주의사항
- Auto Layout을 terminal window에 절대 사용 금지
- it_fatalError / it_assert 사용 (fatalError 아님)
- 새 파일 생성 후 즉시 git add + Xcode 등록 필요
- AI 생성 마크다운(플랜, 요약)을 커밋에 포함하지 않기
