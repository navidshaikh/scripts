#!/usr/bin/env bash

set -e

# Turn colors in this script off by setting the NO_COLOR variable in your
# environment to any value:
#
# $ NO_COLOR=1 test.sh
NO_COLOR=${NO_COLOR:-""}
if [ -z "$NO_COLOR" ]; then
  header=$'\e[1;33m'
  reset=$'\e[0m'
else
  header=''
  reset=''
fi

serving_version="nightly"
eventing_version="nightly"
istio_version="1.3.6"
#kube_version="v1.12.1"
#kube_version="v1.13.4"
kube_version="v1.15.0"

MEMORY="$(minikube config view | awk '/memory/ { print $3 }')"
CPUS="$(minikube config view | awk '/cpus/ { print $3 }')"
DISKSIZE="$(minikube config view | awk '/disk-size/ { print $3 }')"
DRIVER="$(minikube config view | awk '/vm-driver/ { print $3 }')"

header_text() {
  echo "$header$*$reset"
}

header_text "Starting Knative on minikube!"
header_text "Using Kubernetes Version:               ${kube_version}"
header_text "Using Knative Serving Version:          ${serving_version}"
header_text "Using Knative Eventing Version:         ${eventing_version}"
header_text "Using Istio (minimal) Version:          ${istio_version}"

minikube start --memory="${MEMORY:-20480}" --cpus="${CPUS:-6}" --kubernetes-version="${kube_version}" --vm-driver="${DRIVER:-kvm2}" --disk-size="${DISKSIZE:-30g}" --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"
header_text "Waiting for core k8s services to initialize"
sleep 5; while echo && kubectl get pods -n kube-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Istio Lean"
curl -L "https://raw.githubusercontent.com/knative/serving/master/third_party/istio-${istio_version}/istio-minimal.yaml" \
    | sed 's/LoadBalancer/NodePort/' \
    | kubectl apply --overwrite=true --filename -

# scale deployment/cluster-local-gateway to 1 replica
kubectl scale deployment/cluster-local-gateway --replicas=1 -n istio-system
# scale deployment/istio-ingressgateway to 1 replica
kubectl scale deployment/istio-ingressgateway --replicas=1 -n istio-system


# Label the default namespace with istio-injection=enabled.
header_text "Labeling default namespace w/ istio-injection=enabled"
kubectl label --overwrite=true namespace default istio-injection=enabled
header_text "Waiting for istio to become ready"
sleep 5; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Knative Serving"

set +e
kubectl apply --overwrite=true --selector knative.dev/crd-install=true --filename https://storage.googleapis.com/knative-nightly/serving/latest/serving.yaml
rc=$?
set -e
if [ $rc -ne 0 ]; then
   # Retry
  sleep 5
  kubectl apply --overwrite=true --selector knative.dev/crd-install=true --filename https://storage.googleapis.com/knative-nightly/serving/latest/serving.yaml
fi

curl -L "https://storage.googleapis.com/knative-nightly/serving/latest/serving.yaml" \
  | sed 's/LoadBalancer/NodePort/' \
  | kubectl apply --overwrite=true --filename -

header_text "Waiting for Knative Serving to become ready"
sleep 5; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Knative Eventing"
#kubectl apply --overwrite=true --filename https://github.com/knative/eventing/releases/download/${eventing_version}/eventing.yaml
kubectl apply --overwrite=true --selector knative.dev/crd-install=true --filename https://storage.googleapis.com/knative-nightly/eventing/latest/eventing.yaml
sleep 5
kubectl apply --overwrite=true --filename https://storage.googleapis.com/knative-nightly/eventing/latest/eventing.yaml

header_text "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
