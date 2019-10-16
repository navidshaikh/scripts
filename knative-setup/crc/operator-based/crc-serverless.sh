set -x

readonly TEST_NAMESPACE="kn"
readonly SERVING_RELEASE="release-v0.8.1"
readonly SERVING_NAMESPACE="knative-serving"
readonly SERVICEMESH_NAMESPACE="istio-system"

env

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function install_servicemesh(){
  echo ">>Installing ServiceMesh"

  # Install the ServiceMesh Operator
  oc apply -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/operator-install.yaml

  # Wait for the istio-operator pod to appear
  timeout 1800 '[[ $(oc get pods -n openshift-operators | grep -c istio-operator) -eq 0 ]]' || return 1

  # Wait until the Operator pod is up and running
  wait_until_pods_running openshift-operators || return 1

  # Deploy ServiceMesh
  oc new-project $SERVICEMESH_NAMESPACE
  oc apply -n $SERVICEMESH_NAMESPACE -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/controlplane-install.yaml
  cat <<EOF | oc apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: ${SERVICEMESH_NAMESPACE}
spec:
  members:
  - ${SERVING_NAMESPACE}
  - ${TEST_NAMESPACE}
EOF

  # Wait for the ingressgateway pod to appear.
  timeout 1800 '[[ $(oc get pods -n $SERVICEMESH_NAMESPACE | grep -c istio-ingressgateway) -eq 0 ]]' || return 1

  wait_until_pods_running $SERVICEMESH_NAMESPACE

  echo ">>ServiceMesh installed successfully"
}

function install_knative_serving(){
  echo ">>Installing Knative serving"

  oc new-project $SERVING_NAMESPACE

  # Deploy Serverless Operator
  deploy_serverless_operator

  # Wait for the CRD to appear
  timeout 1800 '[[ $(oc get crd | grep -c knativeservings) -eq 0 ]]' || return 1

  # Install Knative Serving
  cat <<-EOF | oc apply -f -
apiVersion: serving.knative.dev/v1alpha1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: ${SERVING_NAMESPACE}
EOF

  # Wait for 6 pods to appear first
  timeout 1800 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 6 ]]' || return

  wait_until_pods_running $SERVING_NAMESPACE || return 1

  echo ">>Knative Serving installed successfully"
}

function deploy_serverless_operator(){
  oc apply -f operator-install.yaml
}

function create_test_namespace(){
  oc new-project $TEST_NAMESPACE
  oc adm policy add-scc-to-user privileged -z default -n $TEST_NAMESPACE
}

# Waits until all pods are running in the given namespace.
# Parameters: $1 - namespace.
function wait_until_pods_running() {
  echo -n "Waiting until all pods in namespace $1 are up"
  for i in {1..150}; do  # timeout after 5 minutes
    local pods="$(kubectl get pods --no-headers -n $1 2>/dev/null)"
    # All pods must be running
    local not_running=$(echo "${pods}" | grep -v Running | grep -v Completed | wc -l)
    if [[ -n "${pods}" && ${not_running} -eq 0 ]]; then
      local all_ready=1
      while read pod ; do
        local status=(`echo -n ${pod} | cut -f2 -d' ' | tr '/' ' '`)
        # All containers must be ready
        [[ -z ${status[0]} ]] && all_ready=0 && break
        [[ -z ${status[1]} ]] && all_ready=0 && break
        [[ ${status[0]} -lt 1 ]] && all_ready=0 && break
        [[ ${status[1]} -lt 1 ]] && all_ready=0 && break
        [[ ${status[0]} -ne ${status[1]} ]] && all_ready=0 && break
      done <<< "$(echo "${pods}" | grep -v Completed)"
      if (( all_ready )); then
        echo -e "\nAll pods are up:\n${pods}"
        return 0
      fi
    fi
    echo -n "."
    sleep 2
  done
  echo -e "\n\nERROR: timeout waiting for pods to come up\n${pods}"
  return 1
}

function delete_knative_openshift() {
  echo ">> Bringing down Knative Serving"
  oc delete --ignore-not-found=true -f openshift/serverless/operator-install.yaml
  oc delete --ignore-not-found=true project $SERVING_NAMESPACE
}

function delete_test_namespace(){
  echo ">> Deleting test namespaces"
  oc delete project $TEST_NAMESPACE
}

function delete_service_mesh(){
  echo ">> Bringin down Service Mesh"
  oc delete --ignore-not-found=true -n $SERVICEMESH_NAMESPACE -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/controlplane-install.yaml
  oc delete --ignore-not-found=true -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/operator-install.yaml
}

function teardown() {
  delete_test_namespace
  delete_service_mesh
  delete_knative_openshift
}

create_test_namespace || exit 1

failed=0

(( !failed )) && install_servicemesh || failed=1

(( !failed )) && install_knative_serving || failed=1

#teardown

(( failed )) && exit 1

echo ">> Success!"
