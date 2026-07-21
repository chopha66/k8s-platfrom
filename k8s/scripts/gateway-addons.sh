#!/usr/bin/env bash
# master 전용: Cilium Gateway API 활성화 (클러스터는 이미 KPR 모드 전제)
set -euo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf
GATEWAY_API_VERSION="v1.3.0"

echo "=== [1/3] Gateway API CRD 설치 ==="
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "=== [2/3] Cilium 재시작 및 대기 (CRD 재감지) ==="
kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium
cilium status --wait --wait-duration 5m

echo "=== [3/3] Gateway 리소스 적용 ==="
kubectl apply -f /home/vagrant/k8s/gateway/

echo "=== 완료. Gateway 상태: ==="
kubectl get gatewayclass
kubectl get gateway -A