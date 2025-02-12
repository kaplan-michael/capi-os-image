#Include var files
include creds.mk
include version.mk

# Allow the OS variant & destination to be passed in
OS_VARIANT ?= fedora
IMAGE ?= capi-os-image
REGISTRY ?= quay.io/mkaplan

# Tools
IMAGE_BUILDER := quay.io/centos-bootc/bootc-image-builder:latest
HCLOUD_UPLOAD_IMAGE_VERSION := 0.3.1

SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

## Location to install tools to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	@echo "Creating local bin directory..."
	@mkdir -p $(LOCALBIN)

# Get the version from the latest Git tag (including dirty state), default to "dev" if not available.
VERSION := $(shell git describe --tags --dirty 2>/dev/null)
ifeq ($(VERSION),)
    VERSION := dev
endif

# Define OS-specific variables.
ifeq ($(OS_VARIANT),fedora)
    OS_VERSION := 41
    CONTAINERFILE := Containerfile.fedora
else ifeq ($(OS_VARIANT),centos)
    OS_VERSION := 10s
    CONTAINERFILE := Containerfile.c10s
else
    $(error Unsupported OS_VARIANT "$(OS_VARIANT)". Use "fedora" or "centos")
endif

# Compose the final image tag & name.
IMAGE_TAG = $(VERSION)-$(OS_VARIANT)-$(OS_VERSION)-kube$(KUBE_VERSION)
IMAGE_NAME=$(REGISTRY)/$(IMAGE):$(IMAGE_TAG)

.PHONY: build push login print-version

print-version:
	@echo "VERSION: $(VERSION)"
	@echo "OS_VARIANT: $(OS_VARIANT)"
	@echo "OS_VERSION: $(OS_VERSION)"
	@echo "KUBE_VERSION: $(KUBE_VERSION)"
	@echo "Composite IMAGE_TAG: $(IMAGE_TAG)"
	@echo "Final IMAGE_NAME: $(IMAGE_NAME)"

login:
	@echo "Logging in to the registry..."
	@buildah login $(REGISTRY) -u $(REGISTRY_USER) -p $(REGISTRY_PASSWORD)

build: login
	@echo "Building image $(IMAGE_NAME) using $(CONTAINERFILE)..."
	# Build the container image with Buildah.
	buildah bud \
	  --build-arg KUBE_MAJOR_VERSION=$(KUBE_MAJOR_VERSION) \
	  --build-arg KUBE_MINOR_VERSION=$(KUBE_MINOR_VERSION) \
	  --build-arg KUBE_PATCH_VERSION=$(KUBE_PATCH_VERSION) \
	  -t $(IMAGE_NAME) \
	  -f $(CONTAINERFILE) .

push: login
	@echo "Pushing image $(IMAGE_NAME)..."
	buildah push $(IMAGE_NAME)

# Build disk images
.PHONY: build-raw build-qcow2

build-raw:
	@echo "Building RAW image for $(IMAGE_NAME)"
	@echo "Ensure login to the registry"
	@sudo podman login -u=$(REGISTRY_USER) -p=$(REGISTRY_PASSWORD) $(REGISTRY)
	@echo "Ensure the image is available locally."
	@sudo podman pull $(IMAGE_NAME)
	@mkdir -p output
	@CURRENT_PWD=$(pwd)
	@echo "Run the disk image builder container."
	@sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v $(PWD)/output:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        $(IMAGE_BUILDER) \
        --type raw \
        --rootfs xfs \
        $(IMAGE_NAME)
	@echo "Rename the output file -> $(IMAGE)-$(IMAGE_TAG).raw"
	@sudo mv output/image/disk.raw output/image/$(IMAGE)-$(IMAGE_TAG).raw

build-qcow2:
	@echo "Building QCOW image for $(IMAGE_NAME)"
	@echo "Ensure login to the registry"
	@sudo podman login -u=$(REGISTRY_USER) -p=$(REGISTRY_PASSWORD) $(REGISTRY)
	@echo "Ensure the image is available locally."
	@sudo podman pull $(IMAGE_NAME)
	@mkdir -p output
	@CURRENT_PWD=$(pwd)
	@echo "Run the disk image builder container."
	@sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v $(PWD)/output:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        $(IMAGE_BUILDER) \
        --type qcow2 \
        --rootfs xfs \
        $(IMAGE_NAME)
	@echo "Rename the output file -> $(IMAGE)-$(IMAGE_TAG).qcow2"
	@sudo mv output/qcow2/disk.qcow output/qcow2/$(IMAGE)-$(IMAGE_TAG).qcow2

HCLOUD_UPLOAD_IMAGE ?= $(LOCALBIN)/hcloud-upload-image

.PHONY: hcloud-upload-image
hcloud-upload-image: $(HCLOUD_UPLOAD_IMAGE)
## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(HCLOUD_UPLOAD_IMAGE): $(LOCALBIN)
	@echo "Installing hcloud-upload-image locally using Go..."
	@test -s $(LOCALBIN)/hcloud-upload-image && $(LOCALBIN)/hcloud-upload-image --version | grep -q $(HCLOUD_UPLOAD_IMAGE_VERSION) || \
	GOBIN=$(LOCALBIN) go install github.com/apricote/hcloud-upload-image@v$(HCLOUD_UPLOAD_IMAGE_VERSION)

hcloud-upload: hcloud-upload-image
	@echo "Uploading image $(IMAGE)-$(IMAGE_TAG).raw to Hetzner Cloud..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(HCLOUD_UPLOAD_IMAGE) upload \
	    --image-path=output/image/$(IMAGE)-$(IMAGE_TAG).raw \
		--architecture=x86 \
		--description $(IMAGE)-$(IMAGE_TAG) \
		--labels version=$(IMAGE)-$(IMAGE_TAG) \
		--labels caph-image-name=$(IMAGE)-$(IMAGE_TAG)

	@echo "Ensure no dangling resources are left behind..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(HCLOUD_UPLOAD_IMAGE) cleanup
