#!/usr/bin/env bash
# master 전용: kubeadm init + kubeconfig + Cilium CNI
set -euo pipefail

CP_IP="192.168.56.10"
POD_CIDR="10.244.0.0/16"
# 고정 토큰 (형식: [a-z0-9]{6}.[a-z0-9]{16}) — worker join에 사용
TOKEN="master.0123456789abcdef"
CILIUM_CLI_VERSION="latest"

# 이미 init 됐으면 스킵 (멱등성)
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "=== 이미 초기화된 클러스터, init 스킵 ==="
else
  echo "=== [1/3] kubeadm init ==="
  kubeadm init \
    --apiserver-advertise-address="${CP_IP}" \
    --pod-network-cidr="${POD_CIDR}" \
    --token "${TOKEN}" \
    --token-ttl 0
fi

echo "=== [2/3] kubeconfig 설정 (vagrant 유저) ==="
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

echo "=== [3/3] Cilium 설치 ==="
export KUBECONFIG=/etc/kubernetes/admin.conf

if ! command -v cilium &> /dev/null; then
  ARCH=$(dpkg --print-architecture)
  curl -fsSL -o /tmp/cilium.tar.gz \
    "https://github.com/cilium/cilium-cli/releases/${CILIUM_CLI_VERSION}/download/cilium-linux-${ARCH}.tar.gz"
  tar -xzf /tmp/cilium.tar.gz -C /usr/local/bin
  rm /tmp/cilium.tar.gz
fi

if ! kubectl get ds -n kube-system cilium &> /dev/null; then
  cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList="${POD_CIDR}"
fi

echo "=== 완료 ==="