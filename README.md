# K8S Platform

Vagrant와 쉘 스크립트로 구축한 3노드 Kubernetes 클러스터.  
`vagrant up` 명령 하나로 베어 VM 프로비저닝부터 클러스터 부트스트랩, CNI 설치까지 완전 자동으로 재현된다.

## 아키텍처

```
Windows 11 Host (Ryzen 7500F / 32GB)
└── VirtualBox (host-only network 192.168.56.0/24)
    ├── master    192.168.56.10   control-plane (2 vCPU / 4GB)
    ├── worker-1  192.168.56.11   worker        (2 vCPU / 4GB)
    └── worker-2  192.168.56.12   worker        (2 vCPU / 4GB)
```

| 구성 요소 | 선택 | 버전                 |
|---|---|--------------------|
| OS | Ubuntu Server | 24.04 LTS          |
| Kubernetes | kubeadm | 1.35               |
| 컨테이너 런타임 | containerd | apt 기본             |
| CNI | Cilium | cilium-cli v0.19.6 |

## 빠른 시작

```bash
git clone <this-repo> && cd k8s-platform
vagrant up          # VM 생성 → OS 준비 → kubeadm init/join → Cilium 설치
vagrant ssh master -c "kubectl get nodes"   # 3대 Ready 확인
```

클러스터 전체 삭제 후 재생성: `vagrant destroy -f && vagrant up`

## 저장소 구조

```
.
├── Vagrantfile              # VM 정의 (노드 스펙/네트워크/역할 분기)
└── scripts/
    ├── common.sh            # 3노드 공통: swap/커널/containerd/kubeadm 준비
    ├── cp-init.sh           # control-plane: kubeadm init + kubeconfig + Cilium
    └── worker-init.sh       # worker: kubeadm join
```

프로비저닝 흐름: 모든 노드가 `common.sh`를 실행한 뒤, Vagrantfile의 `role` 값에 따라 control-plane은 `master_init.sh`, worker는 `worker_init.sh`를 실행한다.

## 주요 설계 결정

**kubeadm (vs k3s).** 설치 편의보다 클러스터 구성 요소를 직접 다루는 학습 깊이를 우선했다. containerd cgroup 드라이버, CNI, 인증서 부트스트랩을 명시적으로 구성한다.

**Cilium (vs Flannel/Calico).** eBPF 기반 CNI로, 향후 NetworkPolicy·Hubble 옵저버빌리티·Gateway API까지 단일 스택으로 확장하기 위해 선택.

**고정 부트스트랩 토큰.** `vagrant up` 단일 명령 재현성을 위해 join 토큰을 고정값으로 사용하고 CA 검증을 생략했다. host-only 네트워크로 외부와 격리된 환경이라는 전제 하의 의도적 타협이며, 프로덕션이라면 TTL이 있는 토큰 발급과 `--discovery-token-ca-cert-hash` 검증을 사용해야 한다.

**쉘 provisioner (vs Ansible).** 초기엔 의존성 없는 쉘 스크립트로 시작하고 멱등성을 직접 처리했다(`command -v` 가드, 설정 파일 존재 확인). 구성이 복잡해지는 시점에 Ansible로 마이그레이션 예정.

## 겪은 문제들

**VirtualBox 부팅 멈춤 — Hyper-V 충돌.** Windows 11의 코어 격리(메모리 무결성)와 hypervisorlaunchtype이 켜져 있으면 VirtualBox VM이 부팅 중 멈춘다. `bcdedit /set hypervisorlaunchtype off` + 메모리 무결성 비활성화 + 재부팅으로 해결.

**NIC 2개 함정.** Vagrant VM은 NAT(eth0) + host-only(eth1) 이중 NIC 구조라, 기본값으로 두면 kubelet과 API 서버가 모든 노드에서 동일한 NAT IP(10.0.2.15)를 광고한다. `KUBELET_EXTRA_ARGS=--node-ip=<host-only IP>`와 `kubeadm init --apiserver-advertise-address`로 고정해 해결.

**쉘 스크립트 따옴표 파싱 에러.** `unexpected EOF while looking for matching '"'`는 에러가 난 줄이 아니라 따옴표가 열린 채 닫히지 않은 상류 지점이 원인. ShellCheck(`bash -n`)로 조기 검출.

## 로드맵

- [x] 1단계: VM 프로비저닝 + kubeadm 클러스터 자동화
- [ ] 2단계: MetalLB, Ingress, cert-manager
- [ ] 3단계: GitOps (ArgoCD)
- [ ] 4단계: 옵저버빌리티 (Prometheus/Grafana/Loki)
- [ ] 5단계: 시크릿 관리 + 보안 강화