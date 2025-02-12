# Cluster api os image
This repository contains the code to build the bootc based(fedora/centos stream) image for the use with cluster api.

## How to build the image
To build the image, you need to have the following tools installed on your machine:
- make
- podman
- buildah
- go (optional, only if you then want to upload the image to Hetzner Cloud)

###To build the image, run the following command:

make sure your git is clean & that you have a tag, if not the image will have a dev- prefix

1. ```cp creds.mk.example creds.mk```

edit creds.mk to include your repository credentials & optional Hetzner Cloud token

2. ```make build push```

*note:* to build a CentOS Stream image(broken currently) set ```OS_VARIANT=centos make ...```

3a. ```make build-qcow2``` to build a qcow2 image

3b. ```make build-raw``` to build a raw image

You will now find your image in the ```output``` directory.(qcow2 or image, depending on the variant you built)

4. ```make hcloud-upload``` to upload the image to Hetzner Cloud(optional)

## What's in the image
The image is based on the bootc image
- kubernetes specific modifications, see the `os` directory
- cloud-init
- cri-o
- kubeadm & friends (version is set in the version.mk file) and is exposed as environment variable/label/part of container tag
- default user: capi
