#!/usr/bin/env bash
# 3개 노드 공통: kubeadm 사전 준비
# 멱등성을 위해 이미 설치된 경우 건너뛰도록 작성
set -euo pipefail

K8S_VERSION="v1.35"   # kubeadm/kubelet/kubectl 마이너 버전

echo "=== [1/5] 스왑 비활성화 ==="
swapoff -a
sed -ri '/\sswap\s/ s/^/#/' /etc/fstab

echo "=== [2/5] 커널 모듈 및 sysctl ==="
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null

echo "=== [3/5] containerd 설치 ==="
if ! command -v containerd &> /dev/null; then
  apt-get update -qq
  apt-get install -y -qq containerd
fi

# SystemdCgroup 활성화 (kubelet과 cgroup 드라이버 일치 필수)
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "=== [4/5] kubeadm / kubelet / kubectl 설치 ==="
if ! command -v kubeadm &> /dev/null; then
  apt-get install -y -qq apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
  apt-get update -qq
  apt-get install -y -qq kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
fi

echo "=== [5/5] kubelet 노드 IP 고정 ==="
# Vagrant는 NIC이 2개(NAT + host-only)라서 kubelet이 NAT IP를 잡는 문제 방지
NODE_IP=$(ip -4 addr show | grep -oP '192\.168\.56\.\d+' | head -1)
cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF

echo "=== 완료: $(hostname) (node-ip: ${NODE_IP}) ==="