#!/bin/sh
set -eux

kubeadm init --config /tmp/master-configuration.yml \
  --ignore-preflight-errors=Swap,NumCPU

kubeadm token create ${token}

[ -d $HOME/.kube ] || mkdir -p $HOME/.kube
ln -s /etc/kubernetes/admin.conf $HOME/.kube/config

until nc -z localhost 6443; do
  echo "Waiting for API server to respond"
  sleep 5
done

if ! docker pull weaveworks/weave-kube:latest; then
  # We may have an IPv6-only setup. While Docker Hub has not fully transitioned
  # (https://github.com/docker/roadmap/issues/89), work around by using the beta host.
  # This way, kubelet should be able to pull the Weave Net images so the CNI comes up properly.
  echo "Trying IPv6-only workaround"
  </tmp/weave-daemonset-k8s.yaml sed "s|image: 'weaveworks/|image: 'registry.ipv6.docker.com/weaveworks/|" | kubectl apply -f -
fi

# See: https://kubernetes.io/docs/admin/authorization/rbac/
kubectl create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --group=system:serviceaccounts
