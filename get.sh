#!/bin/sh -e

if test "$#" != 1; then
  echo "Usage: $0 USERNAME"
  exit 1
fi

username=$1
page=1
data=$(mktemp)

atexit() {
  rm "$data"
}

trap atexit EXIT

while true; do
  curl -sLH "Accept: application/vnd.github.v3+json" "https://api.github.com/users/$username/events?page=$page" > "$data"

  length=$(cat "$data" | jq 'length')
  for i in $(seq 0 $((length-1))); do
    event_type=$(cat "$data" | jq -r ".[$i].type")
    created_at=$(date --date=$(cat "$data" | jq -r ".[$i].created_at"))
    case "$event_type" in
    "CreateEvent")
      ref_type=$(cat "$data" | jq -r ".[$i].payload.ref_type")
      case "$ref_type" in
      "branch")
        branch=$(cat "$data" | jq -r ".[$i].payload.ref")
        repo=$(cat "$data" | jq -r ".[$i].repo.name")
        echo "* [$created_at] Created branch '$branch' at '$repo'";;
      "repository")
        repo=$(cat "$data" | jq -r ".[$i].repo.name")
        echo "* [$created_at] Created a new repository: $repo";;
      *)
        echo "Unknown CreateEvent type '$ref_type'."
        exit 1;;
      esac;;
    "PushEvent")
      branch=$(cat "$data" | jq -r ".[$i].payload.ref")
      repo=$(cat "$data" | jq -r ".[$i].repo.name")
      number_of_commits=$(cat "$data" | jq -r ".[$i].payload.commits | length")
      echo "* [$created_at] Pushed to '$branch' at '$repo':"
      for j in $(seq 0 $((number_of_commits-1))); do
        commit=$(cat "$data" | jq -r ".[$i].payload.commits | .[$j].message" | head -n 1 | cut -c 1-80)
        test "${#commit}" -ge 80 && commit=$commit…
        echo "  + $commit"
      done;;
    "IssueCommentEvent")
      url=$(cat "$data" | jq -r ".[$i].payload.issue.html_url")
      title=$(cat "$data" | jq -r ".[$i].payload.issue.title")
      body=$(cat "$data" | jq -r ".[$i].payload.comment.body" | head -n 1 | cut -c 1-80)
      test "${#body}" -ge 80 && body=$body…
      echo "* [$created_at] Commented on $url"
      echo "  + Title: $title"
      echo "  + Comment: $body";;
    "IssuesEvent")
      action=$(cat "$data" | jq -r ".[$i].payload.action")
      case "$action" in
      "opened")
        url=$(cat "$data" | jq -r ".[$i].payload.issue.html_url")
        title=$(cat "$data" | jq -r ".[$i].payload.issue.title")
        echo "* [$created_at] Opened issue $url"
        echo "  + $title";;
      "closed")
        url=$(cat "$data" | jq -r ".[$i].payload.issue.html_url")
        title=$(cat "$data" | jq -r ".[$i].payload.issue.title")
        echo "* [$created_at] Closed issue $url"
        echo "  + $title";;
      *)
        echo "Unknown IssuesEvent type '$action'."
        exit 1;;
      esac;;
    "PullRequestEvent")
      action=$(cat "$data" | jq -r ".[$i].payload.action")
      case "$action" in
      "closed")
        is_merged=$(cat "$data" | jq -r ".[$i].payload.pull_request.merged")
        url=$(cat "$data" | jq -r ".[$i].payload.pull_request.html_url")
        title=$(cat "$data" | jq -r ".[$i].payload.pull_request.title")
        if test "$is_merged" = "true"; then
          echo "* [$created_at] Merged pull request $url"
        else
          echo "* [$created_at] Closed pull request $url"
        fi
        echo "  + $title";;
      "opened")
        url=$(cat "$data" | jq -r ".[$i].payload.pull_request.html_url")
        title=$(cat "$data" | jq -r ".[$i].payload.pull_request.title")
        echo "* [$created_at] Opened pull request $url"
        echo "  + $title";;
      *)
        echo "Unknown PullRequestEvent type '$action'."
        exit 1;;
      esac;;
    "DeleteEvent")
      ref_type=$(cat "$data" | jq -r ".[$i].payload.ref_type")
      case "$ref_type" in
      "branch")
        branch=$(cat "$data" | jq -r ".[$i].payload.ref")
        repo=$(cat "$data" | jq -r ".[$i].repo.name")
        echo "* [$created_at] Deleted branch '$branch' at '$repo'";;
      "repository")
        repo=$(cat "$data" | jq -r ".[$i].repo.name")
        echo "* [$created_at] Deleted repository: $repo";;
      *)
        echo "Unknown DeleteEvent type '$ref_type'."
        exit 1;;
      esac;;
    "PullRequestReviewCommentEvent")
      url=$(cat "$data" | jq -r ".[$i].payload.pull_request.html_url")
      title=$(cat "$data" | jq -r ".[$i].payload.pull_request.title")
      body=$(cat "$data" | jq -r ".[$i].payload.comment.body" | head -n 1 | cut -c 1-80)
      test "${#body}" -ge 80 && body=$body…
      echo "* [$created_at] Commented on $url"
      echo "  + Title: $title"
      echo "  + Comment: $body";;
    "ForkEvent")
      repo=$(cat "$data" | jq -r ".[$i].repo.name")
      echo "* [$created_at] Forked $repo";;
    "PullRequestReviewEvent")
      # ignored for now. Does not seem very useful
      ;;
    *)
      echo "Unknown event type '$event_type'."
      exit 1;;
    esac
    echo
  done

  page=$((page+1))
  echo 1>&2
  echo -n "== Continue to page n°$page? [Y/n] " 1>&2
  read answer
  echo 1>&2
  echo 1>&2
  if test "$answer" = "n"; then
    exit 0
  fi
done
