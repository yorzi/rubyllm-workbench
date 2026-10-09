#!/usr/bin/env bash
set -euo pipefail

image="${1:-rubyllm-workbench:ci}"
temporary_dir="$(mktemp -d)"
task_name="workbench-smoke-$$"
key_container="${task_name}-key"
prepare_container="${task_name}-prepare"
web_container="${task_name}-web"
demo_container="${task_name}-demo"
storage_volume="${task_name}-storage"
environment_file="${temporary_dir}/runtime.env"
response_file="${temporary_dir}/response.html"

cleanup() {
  result=$?
  trap - EXIT
  if [[ "$result" != 0 ]]; then
    docker logs "$web_container" 2>/dev/null || true
    docker logs "$demo_container" 2>/dev/null || true
  fi
  for container in "$key_container" "$prepare_container" "$web_container" "$demo_container"; do
    docker stop --time 10 "$container" >/dev/null 2>&1 || true
    docker rm --force "$container" >/dev/null 2>&1 || true
  done
  docker volume rm "$storage_volume" >/dev/null 2>&1 || true
  rm -rf "$temporary_dir"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The generated secret goes straight to a private file, never a CLI argument.
umask 077
touch "$environment_file"
chmod 600 "$environment_file"
docker run --rm --network none --name "$key_container" --entrypoint ruby "$image" \
  -rsecurerandom -e 'puts "SECRET_KEY_BASE=#{SecureRandom.hex(64)}"' > "$environment_file"
printf '%s\n' 'CI=1' 'RUBYOPT=-r/rails/script/ci/deny_provider_http.rb' >> "$environment_file"
docker volume create "$storage_volume" >/dev/null

docker run --rm --network none --name "$prepare_container" \
  --env-file "$environment_file" --mount "source=${storage_volume},target=/rails/storage" \
  --entrypoint ruby "$image" script/ci/source_smoke.rb prepare

start_server() {
  local container="$1"
  shift
  docker run --detach --name "$container" --env-file "$environment_file" \
    --mount "source=${storage_volume},target=/rails/storage" \
    --publish 127.0.0.1::80 "$@" "$image" >/dev/null
  local address
  address="$(docker port "$container" 80/tcp)"
  [[ "$address" == 127.0.0.1:* ]]
  base_url="http://${address}"
}

wait_for_health() {
  for attempt in {1..40}; do
    if curl --silent --fail --max-time 2 "${base_url}/up" >/dev/null; then
      return
    fi
    sleep 1
  done
  printf '%s\n' 'Container health check timed out.' >&2
  return 1
}

check_page() {
  local path="$1" expected="$2" status
  status="$(curl --silent --show-error --max-time 15 --output "$response_file" \
    --write-out '%{http_code}' "${base_url}${path}")"
  [[ "$status" == 200 ]]
  grep -Fq "$expected" "$response_file"
}

check_denied() {
  local method="$1" path="$2" status
  status="$(curl --silent --show-error --max-time 15 --output "$response_file" \
    --write-out '%{http_code}' --request "$method" \
    --header 'Content-Type: multipart/form-data; boundary=broken' \
    --data-binary 'synthetic malformed body' "${base_url}${path}")"
  [[ "$status" == 403 ]]
}

start_server "$web_container"
wait_for_health
check_page / 'Demo tour'
check_page /models 'Model Explorer'
check_page /projects/demo-tour 'Synthetic records'
docker exec "$web_container" ruby script/ci/source_smoke.rb records
docker restart "$web_container" >/dev/null
wait_for_health
check_page /projects/demo-tour 'Demo tour'
docker exec "$web_container" ruby script/ci/source_smoke.rb records
docker stop --time 10 "$web_container" >/dev/null
docker rm "$web_container" >/dev/null

start_server "$demo_container" --env WORKBENCH_DEMO=1
wait_for_health
check_page /projects/demo-tour 'Synthetic read-only demo'
check_page /models 'Synthetic read-only demo'
check_denied POST /projects
check_denied POST /rails/active_storage/direct_uploads
check_denied GET /rails/active_storage/blobs/redirect/fake/private.txt
check_denied GET /cable
docker exec "$demo_container" ruby script/ci/source_smoke.rb demo-check
printf '%s\n' 'Docker runtime smoke passed; cleanup stops all task containers and removes temporary data.'
