#!/bin/bash

set -euo pipefail

# TODO: I will be confused if another PR is racing mine and fails my merge
# TODO: What if the base branch of the PR is something else?
# TODO: Remove status from PRs that have lost SELECT_LABEL

BASE_BRANCH=${BASE_BRANCH:-main}
ENV_BRANCH=${ENV_BRANCH:-develop}

while getopts "b:e:l:" option; do
  case $option in
    b)
      BASE_BRANCH="$OPTARG"
      ;;
    e)
      ENV_BRANCH="$OPTARG"
      ;;
    l)
      SELECT_LABEL="$OPTARG"
      ;;
  esac
done

[ -n "$REPO_SLUG" ] || { echo "Missing env var REPO_SLUG" >&2 ; exit 1 ; }
[ -n "$SELECT_LABEL" ] || { echo "Missing required option -l <labell" >&2 ; exit 1 ; }

gh pr list \
  --state open \
  --label "$SELECT_LABEL" \
  --json=createdAt,headRefName \
  --jq='.[] | .createdAt + " " + .headRefName' \
| sort > /tmp/candidates

if [ \! -s /tmp/candidates ] ; then
  exit 0
fi

git branch -f $ENV_BRANCH $BASE_BRANCH
git switch $ENV_BRANCH

failures=0
total_branches=$(wc -l /tmp/candidates | cut -f1 -d' ')
while read ts branch ; do
  branch_sha=$(git rev-parse $branch)
  if git merge $branch ; then
    gh api --method POST \
      --field state=success \
      --field description="Merge success" \
      --field context="shortlived-environments/$ENV_BRANCH" \
      https://api.github.com/repos/$REPO_SLUG/statuses/$branch_sha
  else
    git diff
    gh api --method POST \
      --field state=failure \
      --field description="Merge failed" \
      --field context="shortlived-environments/$ENV_BRANCH" \
      https://api.github.com/repos/$REPO_SLUG/statuses/$branch_sha
    failures=$((failures + 1))
    git merge --abort
  fi
done < /tmp/candidates

git push --force-with-lease origin $ENV_BRANCH
env_sha=$(git rev-parse HEAD)

result=success
successes=$((total_branches - failures))
if [ $failures -gt 0 ] ; then
  result=failure
fi
gh api --method POST \
  --field state=$result \
  --field description="Merged $successes/$total_branches branches" \
  --field context="shortlived-environments/$ENV_BRANCH" \
  https://api.github.com/repos/$REPO_SLUG/statuses/$env_sha

rm /tmp/candidates
