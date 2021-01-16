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
        commit=$(cat "$data" | jq -r ".[$i].payload.commits | .[$j].message")
        echo "  + $commit"
      done;;
    "IssueCommentEvent")
      url=$(cat "$data" | jq -r ".[$i].payload.issue.html_url")
      title=$(cat "$data" | jq -r ".[$i].payload.issue.title")
      body=$(cat "$data" | jq -r ".[$i].payload.comment.body" | head -n 1 | cut -c 1-80)
      echo "* [$created_at] Commented on $url"
      echo "  + Title: $title"
      echo "  + Comment: $body";;
    *)
      echo "Unknown event type '$event_type'."
      exit 1;;
    esac
    echo
  done

  page=$((page+1))
  echo
  echo -n "== Continue to page n°$page? [Y/n] "
  read answer
  if test $answer = "n"; then
    exit 0
  fi
done
