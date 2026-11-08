#!/bin/bash
# Applies the repository's GitHub settings: description, topics, features, labels, security and branch protection.
# Safe to run again; every step is idempotent.
#
#   ./scripts/github-setup.sh                      # uses the repository of the current checkout
#   ./scripts/github-setup.sh owner/clean-mac
#
# Requires the GitHub CLI (`gh auth login`) with admin rights on the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "› Configuring $REPO"

gh repo edit "$REPO" \
    --description "A fully local, open-source storage assistant for macOS. Find what fills your disk (large files, duplicates, caches, Docker, Xcode) and clean up safely. SwiftUI, no network, English and Turkish." \
    --homepage "https://github.com/$REPO#readme" \
    --enable-issues --enable-discussions --enable-wiki=false --enable-projects=false \
    --enable-merge-commit --enable-squash-merge --enable-rebase-merge=false \
    --delete-branch-on-merge --allow-update-branch \
    --add-topic macos,macos-app,swift,swiftui,disk-cleaner,disk-space,disk-usage,storage,cleaner,mac-cleaner,cleanup \
    --add-topic duplicate-finder,duplicate-files,treemap,docker,xcode,developer-tools,privacy,local-first,open-source

echo "› Labels"
python3 -c 'import json; [print(l["name"], l["color"], l["description"], sep="\t") for l in json.load(open(".github/labels.json"))]' |
while IFS=$'\t' read -r name color description; do
    gh label create "$name" --repo "$REPO" --color "$color" --description "$description" --force >/dev/null
done

echo "› Security: private vulnerability reporting, Dependabot alerts"
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null
gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null

echo "› Branch protection for main and develop (pull requests + passing CI)"
for branch in main develop; do
    gh api -X PUT "repos/$REPO/branches/$branch/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": ["build-and-test"] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0, "dismiss_stale_reviews": true },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": true
}
JSON
done

echo "✓ Done. One manual step left: upload docs/images/social-preview.png under"
echo "  https://github.com/$REPO/settings → General → Social preview"
