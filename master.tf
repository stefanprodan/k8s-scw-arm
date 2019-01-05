resource "scaleway_ip" "k8s_master_ip" {
  count = 1
}

resource "scaleway_server" "k8s_master" {
  count          = 1
  name           = "${terraform.workspace}-master-${count.index + 1}"
  image          = "${data.scaleway_image.xenial.id}"
  type           = "${var.server_type}"
  public_ip      = "${element(scaleway_ip.k8s_master_ip.*.ip, count.index)}"
  security_group = "${scaleway_security_group.master_security_group.id}"

  //  volume {
  //    size_in_gb = 50
  //    type       = "l_ssd"
  //  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = "${file(var.private_key)}"
  }
  provisioner "file" {
    source      = "scripts/"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "addons/"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "kubeadm-config.yaml"
    destination = "/tmp/kubeadm-config.yaml"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /tmp/docker-install.sh && /tmp/docker-install.sh ${var.docker_version}" && chmod g+w /tmp/kubeadm-config.yaml,
      "chmod +x /tmp/kubeadm-install.sh && /tmp/kubeadm-install.sh ${var.k8s_version}",
      "sed 's/KUBEADM_CLUSTER_PUBLIC_IP/${self.public_ip}/g' /tmp/kubeadm-config.yaml",
      "export KUBEADM_K8S_VERSION=$(apt-cache madison kubeadm | grep 1.13  | head -1 | awk '{print $3}' | rev | cut -c4-| rev)"
      "sed \"s/KUBEADM_KUBERNETES_VERSION/$${KUBEADM_K8S_VERSION}/g\" /tmp/kubeadm-config.yaml",
      "kubeadm init --ignore-preflight-errors=KubeletVersion --config=/tmp/kubeadm-config.yaml",
      "mkdir -p $HOME/.kube && cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "kubectl create secret -n kube-system generic weave-passwd --from-literal=weave-passwd=${var.weave_passwd}",
      "kubectl apply -f \"https://cloud.weave.works/k8s/net?password-secret=weave-passwd&k8s-version=$(kubectl version | base64 | tr -d '\n')\"",
      "chmod +x /tmp/monitoring-install.sh && /tmp/monitoring-install.sh ${var.arch}",
    ]
  }
  provisioner "local-exec" {
    command    = "./scripts/kubectl-conf.sh ${terraform.workspace} ${self.public_ip} ${self.private_ip} ${var.private_key}"
    on_failure = "continue"
  }
}

data "external" "kubeadm_join" {
  program = ["./scripts/kubeadm-token.sh"]

  query = {
    host = "${scaleway_ip.k8s_master_ip.0.ip}"
    key = "${var.private_key}"
  }

  depends_on = ["scaleway_server.k8s_master"]
}
