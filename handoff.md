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

## 진행 중 / 보류
- [ ] mt-cli TypeScript 빌드 확인 (npm run build — 백그라운드 실행 중)

## 수동으로 실행 필요 (다음 세션에서)

### 1. Swift 파일 Xcode 프로젝트 등록
```bash
tools/add_file_to_xcodeproj.rb sources/MomentermProjectModel.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermProjectStorage.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermProjectSidebarVC.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermProjectFileTreeVC.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermProjectWindowController.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermAIToolChecker.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermStatusBarProjectComponent.swift iTerm2SharedARC
tools/add_file_to_xcodeproj.rb sources/MomentermNewTabHandler.swift iTerm2SharedARC
```

### 2. Git hooks 설치
```bash
cp .hooks/pre-commit .git/hooks/pre-commit
cp .hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

### 3. mt CLI 글로벌 링크 (테스트용)
```bash
cd mt-cli
npm run build
npm link
mt --help
```

### 4. 빌드 테스트
```bash
make run
# 또는
tools/build.sh
```

### 5. MomenTerm Project Manager 메뉴 연결
`iTermController.m` 또는 `MainMenu.xib`에서:
```objc
// Window 메뉴에 항목 추가
[MomentermProjectWindowController toggle];
```

## 다음 액션 (Phase 5~7 구현)
1. `MomentermStatusBarProjectComponent` — iTermStatusBarBaseComponent API 맞게 수정
2. `PTYTextView.m` Korean IME 수정 (docs/korean-ime-analysis.md 참고)
3. `PTYTextView.m` image paste 구현 (docs/image-paste-analysis.md 참고)
4. gstack / omc / open-spec 설치 skill 구현
5. vibe-ready-cli 실제 연동 (패키지명 확인 필요)
6. MCP 서버 scope 정책 자동화
7. guardrail 이탈 감지 시스템

## 막힌 이슈
- `iTermStatusBarBaseComponent` ObjC API 정확한 시그니처 확인 필요
  → `sources/iTermStatusBarBaseComponent.m` 읽고 맞춰야 함
- `MomentermProjectWindowController` Window 메뉴 연결 방법 확인 필요

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
