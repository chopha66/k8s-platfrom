#!/usr/bin/env bash
# master 전용: 클러스터 애드온 설치 (MetalLB)
set -euo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf
METALLB_VERSION="v0.16.1"
MANIFEST_DIR="/home/vagrant/k8s/metallb"

echo "=== [1/3] MetalLB 본체 설치 ==="
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "=== [2/3] MetalLB 파드 대기 ==="
for i in $(seq 1 30); do
  if [ "$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | wc -l)" -gt 0 ]; then
    break
  fi
  sleep 2
done

kubectl wait --namespace metallb-system \
  --for=condition=ready pod --selector=app=metallb --timeout=180s

echo "=== [3/3] IP 풀 / L2 설정 적용 ==="
kubectl apply -f "${MANIFEST_DIR}"

echo "=== 완료 ==="