#!/bin/bash

usage_error() {
    printf "Usage: %s <command> [mode] [--no-cluster]\n\n" "$0"
    printf "%s\n" "Commands:"
    printf "  %s\n" "init                Install k3d and other development dependencies."
    printf "  %s\n" "up [dev|test]       Start the environment:"
    printf "  %s\n" "                    - 'dev' (default) for development mode with a k3d cluster."
    printf "  %s\n" "                    - 'test' for testing production images in a test k3d cluster."
    printf "  %s\n" "                    - '--no-cluster' (optional) to skip starting a k3d cluster."
    printf "  %s\n" "down                Stop and remove the development cluster and containers."
    printf "\n"
    printf "%s\n" "Examples:"
    printf "  %s %s\n" "$0" "init                  # Install dependencies"
    printf "  %s %s\n" "$0" "up                    # Start in development mode"
    printf "  %s %s\n" "$0" "up test               # Start in test mode with production images"
    printf "  %s %s\n" "$0" "up --no-cluster       # Start in development mode without a cluster"
    printf "  %s %s\n" "$0" "up dev --no-cluster   # Same as above"
    printf "  %s %s\n" "$0" "up test --no-cluster  # Start test mode without a cluster"
    printf "  %s %s\n" "$0" "down                  # Stop everything"
    printf "\n"
    exit 1
}

K3D_INSTALL_SCRIPT="https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"

command_exists() { command -v "$1" >/dev/null 2>&1; }
docker_installed() { command_exists docker || { echo "Error: Docker is not installed!"; exit 1; }; }
docker_compose_installed() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command_exists docker-compose; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "Error: Docker Compose is not installed!"
        exit 1
    fi
}
yq_installed() { command_exists yq || { echo "Error: yq is not installed!"; exit 1; }; }
install_k3d() { wget -q -O - "${K3D_INSTALL_SCRIPT}" | bash; }

get_docker_host_ip() {
    BACKEND_CONTAINER=$(${DOCKER_COMPOSE_CMD} ps -q backend)
    [ -z "${BACKEND_CONTAINER}" ] && { echo "Error: Backend container not found!"; exit 1; }
    NETWORK_NAME=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' "${BACKEND_CONTAINER}")
    [ -z "${NETWORK_NAME}" ] && { echo "Error: Could not determine network name!"; exit 1; }
    HOST_IP_IN_DOCKER_NETWORK=$(docker network inspect "$NETWORK_NAME" | jq -r '.[0].IPAM.Config[0].Gateway')
}

init() {
    docker_installed
    docker_compose_installed
    yq_installed
    install_k3d
}

setup_test_cluster() {
    local ip="$1"
    local tls_san="--tls-san=${ip}"
    local modified_file="${RUNTIME_DIR}/cluster.yaml"

    cp "${SCRIPT_DIR}/cluster.yaml" "${modified_file}"

    [ "$(yq eval '.options.k3s' "$modified_file")" == "null" ] && yq eval -i '.options.k3s = {}' "$modified_file"
    [ "$(yq eval '.options.k3s.extraArgs' "$modified_file")" == "null" ] && yq eval -i '.options.k3s.extraArgs = []' "$modified_file"

    [ "$(yq eval ".options.k3s.extraArgs[] | select(.arg == \"$tls_san\")" "$modified_file")" != "" ] && return 0
    yq eval -i ".options.k3s.extraArgs += [{\"arg\": \"$tls_san\", \"nodeFilters\": [\"server:*\"]}]" "$modified_file"
}

setup_kubeconfig() {
    local ip="$1"
    local modified_file="${RUNTIME_DIR}/kubeconfig"
    cp "${HOME}/.kube/config" "${modified_file}"
    sed -i "s/0.0.0.0/$ip/g" "${modified_file}"
}

wait_for_service() {
    local name="$1" url="$2" timeout="$3" elapsed=0
    while ! curl --output /dev/null --silent --head --fail "$url"; do
        if [[ $elapsed -ge $timeout ]]; then
            echo "❌ ${name} did not start within ${timeout} seconds."
            exit 1
        fi
        sleep 2
        ((elapsed+=2))
    done
    echo "✅ ${name} is ready!"
}

up() {
    local mode="dev"
    local NO_CLUSTER=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            dev|test) mode="$1"; shift ;;
            --no-cluster) NO_CLUSTER=1; shift ;;
            *) usage_error ;;
        esac
    done

    touch "${RUNTIME_DIR}/kubeconfig"
    docker_compose_installed

    local cluster_name="kupovi-${mode}"
    local backend_url="http://localhost:5010/api/pods"
    local frontend_url="http://localhost:3010/"
    local cmd="${DOCKER_COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yaml -f ${SCRIPT_DIR}/docker-compose.dev.override.yaml up --build -d"

    [ "${mode}" == "test" ] && backend_url="http://localhost:5000/api/pods" frontend_url="http://localhost:3000/" cmd="${DOCKER_COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yaml up --build -d"

    echo "Starting in ${mode^^} mode..."
    ${cmd}

    get_docker_host_ip
    echo "Host IP in Docker Network: ${HOST_IP_IN_DOCKER_NETWORK}"

    if [ "${NO_CLUSTER}" -eq 0 ]; then
        echo "Setting up k3d cluster..."
        setup_test_cluster "${HOST_IP_IN_DOCKER_NETWORK}"
        k3d cluster create "${cluster_name}" --config "${RUNTIME_DIR}/cluster.yaml"
    else
        echo "Skipping k3d cluster setup (--no-cluster mode enabled)."
    fi

    echo "Setting up kubeconfig..."
    setup_kubeconfig "${HOST_IP_IN_DOCKER_NETWORK}"
    ${DOCKER_COMPOSE_CMD} restart backend

    wait_for_service "Backend" "${backend_url}" 30
    xdg-open "${backend_url}"

    wait_for_service "Frontend" "${frontend_url}" 30
    xdg-open "${frontend_url}"
}

down() {
    docker_compose_installed
    ${DOCKER_COMPOSE_CMD} down
    k3d cluster delete kupovi-dev
    k3d cluster delete kupovi-test
}

[ $# -eq 0 ] && usage_error

CMD=$1
shift 1 || true

case "${CMD}" in
    init) init "$@" ;;
    up) up "$@" ;;
    down) down "$@" ;;
    *) usage_error ;;
esac
