name: build

on:
  push:
    branches: [main]
    paths:
      - Dockerfile
      - tests/**
      - .github/workflows/build.yml
  pull_request:
    paths:
      - Dockerfile
      - tests/**
      - .github/workflows/build.yml
  schedule:
    # Weekly rebuild: picks up the rolling-daily base plus latest
    # Firefox Dev / Postman / Bitwarden (their download URLs are always-latest)
    - cron: "0 6 * * 1"
  workflow_dispatch:
    inputs:
      winbox_version:
        description: "WinBox version to bake in"
        required: false
        default: "4.1"

permissions:
  contents: read
  packages: write

env:
  IMAGE: ghcr.io/${{ github.repository_owner }}/kasm-fedora-lab
  TEST_TAG: kasm-fedora-lab:ci

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Lint Dockerfile (BuildKit build checks)
        run: docker buildx build --check .

      - name: Build image (local, for testing)
        uses: docker/build-push-action@v6
        with:
          context: .
          load: true
          pull: true
          # Scheduled/manual runs bust the cache so the "latest" download
          # layers (Firefox Dev, Postman, Bitwarden) actually re-fetch
          no-cache: ${{ github.event_name == 'schedule' || github.event_name == 'workflow_dispatch' }}
          tags: ${{ env.TEST_TAG }}
          build-args: |
            WINBOX_VERSION=${{ inputs.winbox_version || '4.1' }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke test (binaries, policies, groups, dark mode)
        run: |
          docker run --rm --entrypoint bash \
            -v "$PWD/tests:/tests:ro" \
            "$TEST_TAG" /tests/smoke.sh

      # GitHub-hosted runners don't have sysbox, so --privileged stands in
      # for sysbox-runc here. Validates the same things: KasmVNC comes up
      # and the inner dockerd starts via the custom_startup hook.
      - name: Boot test (KasmVNC) + docker-in-docker test
        run: |
          # -v /var/lib/docker: inner Docker's storage must not sit on the
          # container's overlayfs (containerd snapshotter can't nest overlay).
          # Mirrors the lab_dind volume in compose / sysbox's implicit mount.
          docker run -d --name lab --privileged \
            -v /var/lib/docker \
            -e VNC_PW=citest -p 6901:6901 "$TEST_TAG"

          echo "waiting for KasmVNC..."
          ok=0
          for i in $(seq 1 45); do
            if curl -skf -u kasm_user:citest https://localhost:6901/ >/dev/null; then
              ok=1; break
            fi
            sleep 2
          done
          if [ "$ok" != "1" ]; then
            docker logs lab
            exit 1
          fi
          echo "KasmVNC is up"

          echo "testing inner docker..."
          docker exec --user 1000 lab bash -c '
            /dockerstartup/custom_startup.sh
            for i in $(seq 1 20); do
              docker info >/dev/null 2>&1 && break
              sleep 2
            done
            docker info >/dev/null || { cat /tmp/dockerd.log; exit 1; }
            docker run --rm hello-world
          '
          docker rm -fv lab

      - name: Log in to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Image metadata
        if: github.event_name != 'pull_request'
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=raw,value=latest,enable={{is_default_branch}}
            type=raw,value={{date 'YYYYMMDD'}}
            type=sha

      - name: Push to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            WINBOX_VERSION=${{ inputs.winbox_version || '4.1' }}
          cache-from: type=gha
