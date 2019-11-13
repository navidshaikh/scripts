set -x

readonly SERVING_NAMESPACE="knative-serving"
readonly OLM_NAMESPACE="openshift-marketplace"

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

function install_knative_serving(){
  echo ">>Installing Knative serving"

  oc new-project $SERVING_NAMESPACE

  # Deploy Serverless Operator
  deploy_serverless_operator

  # Install Knative Serving
  cat <<-EOF | oc apply -f -
apiVersion: serving.knative.dev/v1alpha1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: ${SERVING_NAMESPACE}
EOF

  # Wait for 4 pods to appear first
  timeout 1800 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 4 ]]' || return

  wait_until_pods_running $SERVING_NAMESPACE || return 1

  echo ">>Knative Serving installed successfully"
}

function deploy_serverless_operator(){
  git clone https://github.com/openshift-knative/serverless-operator.git /tmp/serverless-operator
  /tmp/serverless-operator/hack/catalog.sh | oc apply -n $OLM_NAMESPACE -f -
  rm -rf /tmp/serverless-operator

  timeout 900 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c serverless) -eq 0 ]]' || ret

  wait_until_pods_running $OLM_NAMESPACE

  cat <<-EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: serverless-operator-sub
  generateName: serverless-operator-
  namespace: openshift-operators
spec:
  source: serverless-operator
  sourceNamespace: $OLM_NAMESPACE
  name: serverless-operator
  channel: techpreview
EOF

  # Wait for the CRD to appear
  timeout 900 '[[ $(oc get crd | grep -c knativeservings) -eq 0 ]]' || return 1
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

failed=0

(( !failed )) && install_knative_serving || failed=1

(( failed )) && exit 1

echo ">> Success!"
