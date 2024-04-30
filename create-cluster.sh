#!/bin/bash

KIND_CLUSTER_NAME="kubeflow"
KIND_CLUSTER_CONFIG_PATH="cluster-config.yaml"
KIND_IMAGE="kindest/node:v1.27.11@sha256:681253009e68069b8e01aad36a1e0fa8cf18bb0ab3e5c4069b2e65cafdd70843"
NVIDIA_DEVICE_PLUGIN_VERSION="v0.15.0"
KUBEFLOW_MANIFESTS_VERSION="v1.8.1"

# Set nvidia runtime as default and enable injecting GPUs with volume mounts
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled
sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
sudo systemctl restart docker

kind create cluster \
	--name "${KIND_CLUSTER_NAME}" \
	--config "${KIND_CLUSTER_CONFIG_PATH}" \
	--image "${KIND_IMAGE}"

# Install nvidia-container-toolkit
docker exec "${KIND_CLUSTER_NAME}-control-plane" bash -c "
	apt-get update && apt-get install -y gpg
	curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
	curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
		sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
		tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
	sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
	apt-get update && apt-get install -y nvidia-container-toolkit
	nvidia-ctk config --set nvidia-container-runtime.modes.cdi.annotation-prefixes=nvidia.cdi.k8s.io/
	nvidia-ctk runtime configure --runtime=containerd --set-as-default --cdi.enabled
	systemctl restart containerd
"

# Install nvidia-device-plugin
kubectl create -f "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${NVIDIA_DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml"

# Install kubeflow
sudo sysctl fs.inotify.max_user_instances=2280
sudo sysctl fs.inotify.max_user_watches=1255360
(
	cd kubeflow/manifests
	git fetch --all --tags --prune
	git checkout "${KUBEFLOW_MANIFESTS_VERSION}"
	while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
)
