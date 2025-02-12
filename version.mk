KUBE_MAJOR_VERSION := 1
KUBE_MINOR_VERSION := 30
KUBE_PATCH_VERSION := 9

# Compose the full Kubernetes version string
KUBE_VERSION := $(KUBE_MAJOR_VERSION).$(KUBE_MINOR_VERSION).$(KUBE_PATCH_VERSION)
