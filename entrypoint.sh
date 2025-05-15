#!/bin/bash

set -xeuo pipefail

# TODO: I will be confused if another PR is racing mine and fails my merge
# TODO: What if the base branch of the PR is something else?
# TODO: Remove status from PRs that have lost SELECT_LABEL

REMOTE=${REMOTE:-origin}
BASE_BRANCH=${BASE_BRANCH:-main}
ENV_BRANCH=${ENV_BRANCH:-develop}
# TODO: Hacky; only works for PRs
ORIG_BRANCH=${ORIG_BRANCH:-$GITHUB_SHA}
ORIG_BRANCH=${ORIG_BRANCH:-$(git rev-parse --abbref-ref HEAD)}
# In case of Github PR, the actual ref run is merging base into head
# This ensures we have the branch that triggered the run.
HEAD_REF=${HEAD_REF:-$GITHUB_HEAD_REF}
HEAD_REF=${HEAD_REF:-$ORIG_BRANCH}

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
    *)
      echo "Unknown option -$option" >&2
      exit 1
  esac
done

[ -n "$GITHUB_REPOSITORY" ] || { echo "Missing env var GITHUB_REPOSITORY" >&2 ; exit 1 ; }
[ -n "$SELECT_LABEL" ] || { echo "Missing required option -l <labell" >&2 ; exit 1 ; }

git config --global user.email "bot@example.com"
git config --global user.name "shortlived-environments"
# TODO: This should prolly be elsewhere or generic
git config --global --add safe.directory /github/workspace

gh pr list \
  --state open \
  --label "$SELECT_LABEL" \
  --json=createdAt,headRefName \
  --jq='.[] | .createdAt + " " + .headRefName' \
| sort > /tmp/candidates

if [ \! -s /tmp/candidates ] ; then
  exit 0
fi

echo "Rebuilding $ENV_BRANCH at $BASE_BRANCH from pull requests tagged $SELECT_LABEL on $ORIG_BRANCH with branches:"
cat /tmp/candidates

git for-each-ref
git log --graph --stat --all
env
cat .git/config
cat .git/HEAD

if ! git rev-parse $REMOTE/$BASE_BRANCH > /dev/null 2>&1 ; then
  echo "Base $BASE_BRANCH not found; is this a shallow checkout?" >&2
  exit 1
fi

git branch -f $ENV_BRANCH $REMOTE/$BASE_BRANCH
git switch $ENV_BRANCH

failures=0
total_branches=$(wc -l /tmp/candidates | cut -f1 -d' ')
this_branch_result=failure
while read ts branch ; do
  branch_sha=$(git rev-parse $REMOTE/$branch)
  if git merge --no-ff $REMOTE/$branch ; then
    if [ "$HEAD_REF" = "$branch" ] ; then
      this_branch_result=success
    else
      gh api --method POST \
        --field state=success \
        --field description="Merge success" \
        --field context="shortlived-environments/$ENV_BRANCH" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$branch_sha
    fi
  else
    (
      echo "Trying to merge:"
      cat /tmp/candidates
      echo
      echo "Merge conflict:"
      git diff
    ) | tee /tmp/merge-conflict
    gh pr comment --body-file /tmp/merge-conflict
    if [ "$HEAD_REF" != "$branch" ] ; then
      gh api --method POST \
        --field state=failure \
        --field description="Merge failed" \
        --field context="shortlived-environments/$ENV_BRANCH" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$branch_sha
    fi
    failures=$((failures + 1))
    git merge --abort
  fi
done < /tmp/candidates

git push --force-with-lease origin $ENV_BRANCH
env_sha=$(git rev-parse HEAD)
git checkout $ORIG_BRANCH

result=success
successes=$((total_branches - failures))
if [ $failures -gt 0 ] ; then
  result=failure
fi
gh api --method POST \
  --field state=$result \
  --field description="Merged $successes/$total_branches branches" \
  --field context="shortlived-environments/$ENV_BRANCH" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$env_sha

rm /tmp/candidates

if [ "$this_branch_result" != "success" ] ; then
  exit 1
fi
