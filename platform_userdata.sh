#!/bin/bash

set -Eeuo pipefail
exec > >(tee -a /var/log/platform-userdata.log) 2>&1

echo "Configuring platform services for ${environment_name}"

retry() {
  attempts="$1"
  shift
  count=1

  until "$@"; do
    if [ "$count" -ge "$attempts" ]; then
      echo "Command failed after $count attempts: $*"
      return 1
    fi

    count=$((count + 1))
    sleep 10
  done
}

clone_tensorflow_serving() {
  rm -rf /opt/platform/source/tensorflow-serving
  git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/tensorflow/serving.git /opt/platform/source/tensorflow-serving
}

install_platform_packages() {
  apt-get install -y docker.io docker-compose-v2 git curl ca-certificates || \
    apt-get install -y docker.io docker-compose-plugin git curl ca-certificates
}

export DEBIAN_FRONTEND=noninteractive
retry 5 apt-get update -y
retry 3 install_platform_packages

systemctl enable --now docker
usermod -aG docker '${admin_username}'

# Azure Marketplace Ubuntu images include the Azure Linux Agent. Keep it
# running for Azure Run Command and other VM management operations.
systemctl enable --now walinuxagent.service 2>/dev/null || true

install -d -m 0755 /opt/platform/ar /opt/platform/vr /opt/platform/kong
install -d -m 0755 /opt/platform/models /opt/platform/source

cat <<'AR_EOF' >/opt/platform/ar/index.html
${ar_index}
AR_EOF
printf 'ok\n' >/opt/platform/ar/healthz

cat <<'VR_EOF' >/opt/platform/vr/index.html
${vr_index}
VR_EOF
printf 'ok\n' >/opt/platform/vr/healthz

cat <<'KONG_EOF' >/opt/platform/kong/kong.yml
${kong_config}
KONG_EOF

# TensorFlow Serving needs an actual SavedModel. Fetch the small official
# Half Plus Two demonstration model so the REST inference endpoint is usable
# immediately, while leaving /opt/platform/models ready for a real model.
if ! find /opt/platform/models/half_plus_two -name saved_model.pb -print -quit 2>/dev/null | grep -q .; then
  retry 3 clone_tensorflow_serving
  git -C /opt/platform/source/tensorflow-serving sparse-checkout set \
    tensorflow_serving/servables/tensorflow/testdata/saved_model_half_plus_two_cpu
  install -d -m 0755 /opt/platform/models/half_plus_two
  cp -a \
    /opt/platform/source/tensorflow-serving/tensorflow_serving/servables/tensorflow/testdata/saved_model_half_plus_two_cpu/. \
    /opt/platform/models/half_plus_two/
fi

find /opt/platform/models/half_plus_two -name saved_model.pb -print -quit | grep -q .

cat <<'COMPOSE_EOF' >/opt/platform/docker-compose.yml
${compose_config}
COMPOSE_EOF

chmod 0600 /opt/platform/docker-compose.yml /opt/platform/kong/kong.yml
cd /opt/platform

docker compose config --quiet
retry 5 docker compose pull
docker compose up -d --wait --wait-timeout 600

# Confirm that the bundled TensorFlow model answers a real prediction request.
retry 12 curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -d '{"instances":[1.0,2.0,5.0]}' \
  http://127.0.0.1:8501/v1/models/half_plus_two:predict

touch /opt/platform/bootstrap-success
echo "Missing-service platform is ready"
