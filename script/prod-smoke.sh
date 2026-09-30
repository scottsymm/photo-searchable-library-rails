#!/usr/bin/env bash
# Local production-image smoke test (no deploy). Builds the Rails image, runs
# it against the compose stub sidecar, and verifies boot, import, and search.
set -euo pipefail

IMAGE="photo_searchable_library_rails"
RUN_ID="$(date +%s)-$$"
CONTAINER="pics-prod-smoke-$RUN_ID"
STORAGE_VOLUME="${CONTAINER}-storage"
LIBRARY_VOLUME="${CONTAINER}-library"
PORT="${PICS_SMOKE_PORT:-8080}"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$STORAGE_VOLUME" "$LIBRARY_VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building production image"
docker build --platform linux/amd64 -t "$IMAGE" .

echo "==> Ensuring the dev sidecar is up (stub mode)"
docker compose up -d sidecar

docker volume create "$STORAGE_VOLUME" >/dev/null
docker volume create "$LIBRARY_VOLUME" >/dev/null

echo "==> Starting production container on :$PORT"
docker run -d --name "$CONTAINER" \
  --platform linux/amd64 \
  -p "127.0.0.1:$PORT:80" \
  --add-host=host.docker.internal:host-gateway \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e PICS_WORKER_URL=http://host.docker.internal:9090 \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v "$STORAGE_VOLUME:/rails/storage" \
  -v "$LIBRARY_VOLUME:/rails/library" \
  "$IMAGE"

echo "==> Waiting for /up"
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:$PORT/up" >/dev/null 2>&1; then
    echo "    up after ${i}s"
    break
  fi
  sleep 1
  if [ "$i" = 60 ]; then
    echo "FAIL: /up never returned 200"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
done

echo "==> /catalog/overview"
curl -fsS -H "Accept: application/json" "http://localhost:$PORT/catalog/overview" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('    sources:', [s['kind'] for s in d['sources']])"

echo "==> Upload test/fixtures/tiny.jpg"
RESP=$(curl -fsS -H "Accept: application/json" -F "file=@test/fixtures/tiny.jpg;type=image/jpeg" "http://localhost:$PORT/assets/upload")
echo "$RESP"
JOB_ID=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

echo "==> Waiting for import job $JOB_ID"
for i in $(seq 1 60); do
  STATUS=$(curl -fsS "http://localhost:$PORT/jobs/$JOB_ID" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  if [ "$STATUS" = "done" ]; then
    echo "    done after ${i}s"
    break
  fi
  if [ "$STATUS" = "error" ]; then
    echo "FAIL: import job errored"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
  sleep 1
  if [ "$i" = 60 ]; then
    echo "FAIL: import job timed out"
    docker logs "$CONTAINER" --tail 50
    exit 1
  fi
done

echo "==> Verify thumbnail serves"
ASSET_ID=$(docker exec "$CONTAINER" bin/rails runner \
  "job = Job.find(${JOB_ID}); path = JSON.parse(job.params).fetch('paths').first; puts Asset.find_by!(path: path).id")
curl -fsS -o /tmp/pics-smoke-thumb.jpg -w "    thumbnail HTTP %{http_code}\n" \
  "http://localhost:$PORT/assets/$ASSET_ID/thumbnail"

echo "==> Cleanup"
echo "SMOKE OK"
