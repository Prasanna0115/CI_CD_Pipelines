#!/usr/bin/env bash
set -Eeuo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${APP_PORT:?APP_PORT is required}"

registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
image_uri="${registry}/${ECR_REPOSITORY}:${IMAGE_TAG}"

aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$registry"
docker pull "$image_uri"

had_previous=false
if docker container inspect fastapi-app >/dev/null 2>&1; then
    if docker container inspect fastapi-app-previous >/dev/null 2>&1; then
        docker rm -f fastapi-app-previous
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' fastapi-app)" = "true" ]; then
        docker stop fastapi-app
    fi
    docker rename fastapi-app fastapi-app-previous
    had_previous=true
fi

if docker run -d \
    --name fastapi-app \
    --restart unless-stopped \
    --publish "0.0.0.0:${APP_PORT}:8000" \
    --env "APP_VERSION=${IMAGE_TAG}" \
    "$image_uri"; then
    for attempt in $(seq 1 30); do
        if curl --fail --silent "http://127.0.0.1:${APP_PORT}/health"; then
            printf '\nDeployed %s and health check passed.\n' "$image_uri"
            if [ "$had_previous" = true ]; then
                docker rm -f fastapi-app-previous
            fi
            exit 0
        fi
        sleep 2
    done
fi

printf 'Deployment health check failed for %s.\n' "$image_uri" >&2
docker logs fastapi-app 2>&1 || true
docker rm -f fastapi-app >/dev/null 2>&1 || true

if [ "$had_previous" = true ]; then
    docker rename fastapi-app-previous fastapi-app
    docker start fastapi-app
fi

exit 1
