#!/usr/bin/env bash
# master 전용: ArgoCD 설치 + root App(App of Apps) 등록
set -euo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf
ARGOCD_VERSION="v3.4.5"

echo "=== [1/5] ArgoCD 설치 ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "=== [2/5] argocd-server insecure 모드 전환 ==="
kubectl -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'

echo "=== [3/5] ArgoCD 파드 대기 ==="
# 파드 생성 대기
for i in $(seq 1 60); do
  if [ "$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)" -gt 0 ]; then
    break
  fi
  sleep 2
done
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s

# insecure 설정을 확실히 반영하기 위해 서버 재시작
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=180s

echo "=== [4/5] root App(App of Apps) 등록 ==="
kubectl apply -f /home/vagrant/argocd/resources/root-app.yaml
kubectl apply -f /home/vagrant/argocd/resources/http-route.yaml

echo "=== [5/5] 초기 admin 비밀번호 ==="
echo "ArgoCD UI 접속용 admin 초기 비밀번호:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=== 완료. UI 접근은 port-forward 또는 Gateway 노출 필요 ==="