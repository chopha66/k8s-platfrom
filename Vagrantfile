# -*- mode: ruby -*-
# 3-node Kubernetes Platform: master 1 + worker 2
# Usage
# vagrant up          3대 전부 부팅 (첫 실행은 박스 다운로드로 10분+)
# vagrant status      상태 확인
# vagrant ssh master      control-plane 접속
# vagrant halt        전체 정지
# vagrant destroy -f  전부 삭제 후 재생성 가능 (이게 IaC의 맛)

VAGRANT_BOX = "bento/ubuntu-24.04"

NODES = [
  { name: "master", role: "master", ip: "192.168.56.10", cpus: 2, memory: 4096 },
  { name: "worker-1", ip: "192.168.56.11", cpus: 2, memory: 4096 },
  { name: "worker-2", ip: "192.168.56.12", cpus: 2, memory: 4096 },
]

Vagrant.configure("2") do |config|
  config.vm.box = VAGRANT_BOX
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |node|
    config.vm.define node[:name] do |n|
      n.vm.hostname = node[:name]
      n.vm.network "private_network", ip: node[:ip]

      n.vm.provider "virtualbox" do |vb|
        vb.name   = "k8s-#{node[:name]}"
        vb.cpus   = node[:cpus]
        vb.memory = node[:memory]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end

      # /etc/hosts 등록 (중복 방지)
      n.vm.provision "hosts", type: "shell", inline: <<-SHELL
        grep -q "192.168.56.10 master" /etc/hosts || cat >> /etc/hosts <<EOF
192.168.56.10 master
192.168.56.11 worker-1
192.168.56.12 worker-2
EOF
      SHELL

      # kubeadm 사전 준비 (3대 공통)
      n.vm.provision "common", type: "shell", path: "init_vm/scripts/common.sh"

      # 역할별 프로비저닝
      if node[:role] == "master"
        n.vm.provision "master-init", type: "shell", path: "init_vm/scripts/master_init.sh"
        # worker join 후 수동 실행 : vagrant provision master --provision-with metallb-manifests,metallb-addons
        n.vm.provision "metallb-manifests", type: "file",
            source: "k8s/metallb", destination: "/home/vagrant/k8s/metallb"
        n.vm.provision "metallb-addons", type: "shell", path: "k8s/scripts/metallb-addons.sh", run: "never"
        # worker join 후 수동 실행 : vagrant provision master --provision-with gateway-manifests,gateway-addons
        n.vm.provision "gateway-manifests", type: "file",
            source: "k8s/gateway", destination: "/home/vagrant/k8s/gateway"
        n.vm.provision "gateway-addons", type: "shell", path: "k8s/scripts/gateway-addons.sh", run: "never"
      else
        n.vm.provision "worker-init", type: "shell", path: "init_vm/scripts/worker_init.sh"
      end
    end
  end
end