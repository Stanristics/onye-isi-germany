#!/usr/bin/env bash
# Usage:  ./push-to-github.sh https://github.com/YOUR-USERNAME/onye-isi.git
# Create the empty repository on github.com first (no README, no .gitignore).
set -e
REPO_URL="${1:?Usage: ./push-to-github.sh https://github.com/YOUR-USERNAME/onye-isi.git}"

# Safety check: stop if anything that looks like a secret key is in the project
if grep -rIlE --exclude-dir=.git --exclude=push-to-github.sh 'gsk_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{30,}|sb_secret_' . ; then
  echo "STOP: the files above look like they contain a secret key. Remove it, then run again."; exit 1
fi

[ -d .git ] || git init -b main
git add .
git commit -m "Onye Isi: marketplace with Supabase auth, bookings, admin and AI features" || echo "Nothing new to commit"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "$REPO_URL"
git push -u origin main
echo "Done. Connect the repo in Netlify (publish directory: public)."
