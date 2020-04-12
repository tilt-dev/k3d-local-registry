#!/usr/bin/env bash
#
# Starts a k3s cluster (via k3d) with local image registry enabled,
# and with nodes annotated such that Tilt (https://tilt.dev/) can
# auto-detect the registry.

set -o errexit



# format host:port
# Example: PUBLISH_PORTS='80:80 443:443'
PUBLISH_PORTS=''


API_SERVER_PORT="${API_SERVER_PORT:-6443}"

# desired cluster name (default is "k3s-default")
CLUSTER_NAME="${CLUSTER_NAME:-k3s-default}"



function to_int {
    local -i _num="10#${1}"
    echo "${_num}"
}

function port_is_ok {
    local _host=`echo "$1" | cut -d ":" -f 1`
    local _port=`echo "$1" | cut -d ":" -f 2`
    local -i _port_num_host=$(to_int "${_host}" 2>/dev/null)
    local -i _port_num_port=$(to_int "${_port}" 2>/dev/null)

    if (( (( $_port_num_host < 1 || $_port_num_host > 65535 )) || (( $_port_num_port < 1 || $_port_num_port > 65535 )) ))  ; then
        echo "*** ${_host}:${_port} is not a valid port for publish" 1>&2
        exit 1
    fi

    echo "${_port}"
}


# concat ports
PUBLISH=""
for PORT in $PUBLISH_PORTS;do
        result=$(port_is_ok $PORT)
        PUBLISH="${PUBLISH} --publish $PORT"
done



# 🚨 only compatible with k3d v1.x (at least for now) 🚨
if ! k3d -version | grep 'v1' > /dev/null 2>&1; then
  echo "This script only works with k3d v1.x"
  exit 1
fi


# Check if cluster already exists.
# AFAICT there's no good way to get the registry name/port from a running
# cluster, so if it already exists, just bail.
for cluster in $(k3d ls 2>/dev/null | tail -n +4 | head -n -1 | awk '{print $2}'); do
  if [ "$cluster" == "$CLUSTER_NAME" ]; then
      # TODO(maia): check if the cluster already has the appropriate annotations--then we're okay
      # TODO(maia): if cluster exists, has registry, doesn't have annotations, apply them.
      #   (Unfortunately there's no easy way to check what registristry (if any) the cluster
      #   is running, see https://github.com/rancher/k3d/issues/193)
      echo "Cluster '$cluster' already exists, aborting script."
      echo "\t(You can delete the cluster with 'k3d delete --name=$CLUSTER_NAME' and rerun this script.)"
      exit 1
  fi
done

k3d create --enable-registry --name=${CLUSTER_NAME} --api-port ${API_SERVER_PORT}  ${PUBLISH} "$@"

echo
echo "Waiting for Kubeconfig to be ready..."
timeout=$(($(date +%s) + 30))
until [[ $(date +%s) -gt $timeout ]]; do
  if k3d get-kubeconfig --name=${CLUSTER_NAME} > /dev/null 2>&1; then
    export KUBECONFIG="$(k3d get-kubeconfig --name=${CLUSTER_NAME})"
    DONE=true
    break
  fi
  sleep 0.2
done

if [ -z "$DONE" ]; then
  echo "Timed out trying to get Kubeconfig"
  exit 1
fi

# default name/port
# TODO(maia): support other names/ports
reg_name='registry.local'
reg_port='5000'

# Annotate nodes with registry info for Tilt to auto-detect
echo "Waiting for node(s) + annotating with registry info..."
DONE=""
timeout=$(($(date +%s) + 30))
until [[ $(date +%s) -gt $timeout ]]; do
  nodes=$(kubectl get nodes -o go-template --template='{{range .items}}{{printf "%s\n" .metadata.name}}{{end}}')
  if [ ! -z $nodes ]; then
    for node in $nodes; do
      kubectl annotate node "${node}" \
              tilt.dev/registry=localhost:${reg_port} \
              tilt.dev/registry-from-cluster=${reg_name}:${reg_port}
    done
    DONE=true
    break
  fi
  sleep 0.2
done

if [ -z "$DONE" ]; then
  echo "Timed out waiting for node(s) to be up"
  exit 1
fi

echo "Set kubecontext with:"
echo "\texport KUBECONFIG=\"\$(k3d get-kubeconfig --name=${CLUSTER_NAME})\""
