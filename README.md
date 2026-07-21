# K8S Platform

Vagrant와 쉘 스크립트로 구축한 3노드 Kubernetes 클러스터.  
kube-proxy 없는 eBPF 기반 네트워킹(Cilium KPR) 위에 로드밸런서와 Gateway API까지, 클러스터 전 계층을 코드로 재현한다.

## 아키텍처

```
Windows 11 Host (Ryzen 7500F / 32GB)
└── VirtualBox (host-only network 192.168.56.0/24)
    ├── master    192.168.56.10   control-plane (2 vCPU / 4GB)
    ├── worker-1  192.168.56.11   worker        (2 vCPU / 4GB)
    ├── worker-2  192.168.56.12   worker        (2 vCPU / 4GB)
    └── LoadBalancer IP Pool      192.168.56.200-250 (MetalLB)
```

| 구성 요소 | 선택 | 버전 |
|---|---|--------------------|
| OS | Ubuntu Server | 24.04 LTS |
| Kubernetes | kubeadm | 1.35 |
| 컨테이너 런타임 | containerd | apt 기본 |
| CNI | Cilium | cilium-cli v0.19.6 |
| LoadBalancer | MetalLB (L2 mode) | v0.16.1 |
| L7 라우팅 | Cilium Gateway API | CRD v1.3.0 |

## 빠른 시작

```bash
git clone <this-repo> && cd k8s-platform

# 1. 클러스터 부트스트랩 (VM 생성 → kubeadm init/join → Cilium)
vagrant up

# 2. 애드온 설치 (모든 노드 join 후 실행해야 함 — 아래 '겪은 문제들' 참고)
vagrant provision master --provision-with metallb-manifests,metallb-addons
vagrant provision master --provision-with gateway-manifests,gateway-addons

# 확인
vagrant ssh master -c "kubectl get nodes && kubectl get gateway -A"
```

클러스터 전체 재생성: vagrant destroy -f 후 위 과정 반복.

## 저장소 구조

```
k8s-platform/
├── Vagrantfile                    # VM 정의 (노드 스펙/네트워크/역할 분기)
├── init_vm/
│   └── scripts/
│       ├── common.sh              # 3노드 공통: swap/커널/containerd/kubeadm 준비
│       ├── master_init.sh         # master: kubeadm init(kube-proxy 제외) + Cilium KPR
│       └── worker_init.sh         # worker: kubeadm join
└── k8s/
    ├── metallb/                   # IPAddressPool / L2Advertisement
    ├── gateway/                   # GatewayClass / Gateway
    └── scripts/
        ├── metallb-addons.sh      # MetalLB 설치 + 설정
        └── gateway-addons.sh      # Gateway API CRD + Cilium Gateway 활성화
```

프로비저닝 흐름: 모든 노드가 common.sh 실행 → 역할에 따라 master_init.sh 또는 worker_init.sh 실행 → 클러스터 완성 후 애드온을 별도 단계로 설치.

## 주요 설계 결정

**kubeadm (vs k3s).**  
설치 편의보다 클러스터 구성 요소를 직접 다루는 학습 깊이를 우선했다. containerd cgroup 드라이버, CNI, 인증서 부트스트랩을 명시적으로 구성한다.

**Cilium (vs Flannel/Calico).**  
eBPF 기반 CNI로, 향후 NetworkPolicy·Hubble 옵저버빌리티·Gateway API까지 단일 스택으로 확장하기 위해 선택.

**고정 부트스트랩 토큰.**  
`vagrant up` 단일 명령 재현성을 위해 join 토큰을 고정값으로 사용하고 CA 검증을 생략했다. host-only 네트워크로 외부와 격리된 환경이라는 전제 하의 의도적 타협이며, 프로덕션이라면 TTL이 있는 토큰 발급과 `--discovery-token-ca-cert-hash` 검증을 사용해야 한다.

**쉘 provisioner (vs Ansible).**  
초기엔 의존성 없는 쉘 스크립트로 시작하고 멱등성을 직접 처리했다(`command -v` 가드, 설정 파일 존재 확인). 구성이 복잡해지는 시점에 Ansible로 마이그레이션 예정.

## 겪은 문제들

**VirtualBox 부팅 멈춤 — Hyper-V 충돌.**  
Windows 11의 코어 격리(메모리 무결성)와 hypervisorlaunchtype이 켜져 있으면 VirtualBox VM이 부팅 중 멈춘다. `bcdedit /set hypervisorlaunchtype off` + 메모리 무결성 비활성화 + 재부팅으로 해결. Windows Update 후 재발할 수 있어 주기적 확인이 필요하다.

**NIC 2개 함정.**  
Vagrant VM은 NAT + host-only 이중 NIC이라, 기본값으로 두면 kubelet과 API 서버가 모든 노드에서 동일한 NAT IP(10.0.2.15)를 광고한다. `--node-ip`와 `--apiserver-advertise-address`로 host-only IP를 고정해 해결.

**재부팅 후 kubelet 크래시 루프 (스왑 부활).**  
재부팅 후 kubelet이 기동 거부(`running with swap on is not supported`). 근본 원인은 fstab의 스왑 줄이 탭으로 구분되어 있어 `sed '/ swap /'` 패턴이 매칭에 실패, 주석 처리가 안 된 것. `swapoff -a`는 세션에만 적용되므로 재부팅으로 부활했다. `sed -ri '/\sswap\s/'`로 탭/공백 모두 처리해 해결.

**kubectl wait 레이스 컨디션.**  
`kubectl apply` 직후 `kubectl wait`는 파드가 아직 없어 `no matching resources found`로 즉시 실패한다. wait는 조건 대기만 하고 리소스 등장 대기는 하지 않는다. 파드 생성을 확인하는 폴링 루프를 앞에 추가해 해결.

**프로비저닝 순서 의존성.**  
`vagrant up`은 노드를 순차 처리하므로 master 프로비저닝 시점에 worker가 없다. 이때 애드온을 설치하면 Deployment가 스케줄될 노드가 없어 Pending에 빠진다. 애드온을 `run: "never"` provisioner로 분리해 클러스터 완성 후 실행하도록 변경.

**Cilium Gateway API (CRD 버전 불일치.)**  
cilium-cli 버전을 고정하지 않아 최신 Cilium 1.19.5가 설치됐는데, 이 버전은 Gateway API CRD v1.3.0을 요구한다. v1.1.0을 설치했더니 operator가 "Required GatewayAPI resources are not found"로 Gateway 컨트롤러를 비활성화했다. CRD를 v1.3.0으로 올리고 cilium-cli·Cilium 버전을 고정해 해결.

**CRD 설치 후 operator 재검사 필요.**  
Cilium operator는 시작 시점에 한 번만 Gateway API CRD 존재를 검사한다. CRD가 나중에 설치되면 이미 뜬 operator는 인지하지 못하므로, `rollout restart`로 재검사를 유도해야 한다. CRD의 `condition=established` 대기도 함께 필요하다.

**GatewayClass 수동 생성.**  
Cilium 1.19에선 `cilium` GatewayClass가 자동 생성되지 않는다. `controllerName: io.cilium/gateway-controller`를 가진 GatewayClass를 직접 정의해야 Gateway가 PROGRAMMED 상태가 된다.

## 로드맵

- [x] 1단계: VM 프로비저닝 + kubeadm 클러스터 자동화
- [x] 2단계: MetalLB + Cilium Gateway API
- [ ] 3단계: GitOps (ArgoCD)
- [ ] 4단계: 옵저버빌리티 (Prometheus/Grafana/Loki + Hubble)
- [ ] 5단계: 시크릿 관리 + 보안 강화