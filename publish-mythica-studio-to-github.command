#!/bin/bash
# Puts this folder on GitHub as a PRIVATE repository called "mythica-studio" (run once; later runs just push new commits).
# Uses GitHub's own command-line tool (gh). Signing in happens in your browser; no passwords are stored in this folder.
cd "$(dirname "$0")" || exit 1
pause(){ echo; read -r -p "Press Return to close…" _; }
if ! command -v gh >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then echo "▸ Installing GitHub's tool (gh)…"; brew install gh || { echo "✖ Couldn't install gh."; pause; exit 1; }
  else echo "GitHub's tool (gh) isn't installed. Opening its download page: install it, then double-click this file again."; open "https://cli.github.com"; pause; exit 1; fi
fi
if ! gh auth status >/dev/null 2>&1; then echo "▸ Sign in to GitHub in your browser…"; gh auth login --web --git-protocol https || { pause; exit 1; }; fi
if git remote get-url origin >/dev/null 2>&1; then
  echo "▸ Pushing new commits…"; git push -u origin main
else
  echo "▸ Creating the private repository…"
  gh repo create mythica-studio --private --source . --remote origin --push \
    --description "Mythica Studio: write your life story month by month, with photos and videos linked in place" || { pause; exit 1; }
fi
URL="$(gh repo view --json url -q .url 2>/dev/null)"
echo; echo "✓ Done. Private repository: $URL"
echo "To invite someone later:  gh api -X PUT repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/collaborators/THEIR_GITHUB_USERNAME"
[ -n "$URL" ] && open "$URL"
pause
