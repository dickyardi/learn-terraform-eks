#!/bin/bash
sed -i 's/networking.k8s.io\/v1beta1/networking.k8s.io\/v1/g' "$1"