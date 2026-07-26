# Create Git Commit

Follow this workflow whenever the user asks to create a commit, commit changes, or similar.

## Workflow

### 1. Inspect latest changes

- Run `git status` to see modified, added, and untracked files.
- Run `git diff` for unstaged changes and `git diff --staged` for already-staged changes.
- Optionally run `git diff --stat` for a concise summary.

Use the output to understand what will be committed. If the user specified particular files or paths, only those are in scope for this commit.

**Break up into smaller commits when necessary.** If the changes are large or mix unrelated concerns (e.g. env config + new feature + docs), suggest or perform multiple commits: one logical change per commit. Stage and commit in batches (e.g. first commit env refactor, then commit new feature, then commit tooling). Only combine everything into one commit when the changes are clearly one cohesive change.

### 2. Stage files (git add)

- Stage the changes to include in this commit:
  - To stage everything: `git add -A` or `git add .`
  - To stage specific paths: `git add <path>...`
- If the user did not specify paths, stage all changed files that belong to this logical change (or ask when unclear).
- Re-run `git status` or `git diff --staged` to confirm what is staged before committing.

Request **git_write** when running `git add` (and `git commit`).

### 3. Generate commit message

From the staged diff (`git diff --staged`), write a single commit message that:

- **First line**: Short summary (about 50–72 chars). Use imperative mood ("Add feature" not "Added feature").
- **Optional body**: Blank line, then 1–3 sentences explaining what and why (if the summary is not enough).
- **Format**: Prefer conventional commits when it fits:
  - `feat(scope): short description`
  - `fix(scope): short description`
  - `refactor(scope): short description`
  - `docs: short description`
  - `test: short description`
  - `chore: short description`
- Scope is optional (e.g. module, app, or area). Omit scope if there is no clear one.

### 4. Commit with the generated message

- Run: `git commit -m "First line" -m "Optional body paragraph."` (use multiple `-m` for body lines, or a single `-m` for summary only).
- If the message contains characters that need escaping in the shell, quote the message appropriately.

Request **git_write** when running `git commit`.

## Summary

1. Inspect: `git status`, `git diff`, `git diff --staged`
2. If changes mix unrelated concerns, break into smaller commits (one logical change per commit).
3. Stage: `git add -A` or `git add <paths>`
4. Generate message from staged diff (imperative, conventional style when appropriate)
5. Commit: `git commit -m "..."`

Do not run `git push` unless the user explicitly asks to push. Optionally, after committing, you may ask the user if they want to push the commit.
