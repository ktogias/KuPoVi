#!/bin/bash

usage_error() {
    echo "Usage: $0 dev init|up|down"
    echo "Use 'dev init' to install k3d and other develompent dependencies."
    echo "Use 'dev up' to start in development mode with a testing k3d cluster."
    echo "Use 'dev down' to stop the development cluster and remove development containers"
    exit 1
}

K3D_INSTALL_SCRIPT="https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"
DEV_DIR="${SCRIPT_DIR}/dev"
DEV_CLUSTER_NAME="kupovi-dev"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Docker is installed
docker_installed() {
    if ! command_exists docker; then
        echo "Error: Docker is not installed! Please install Docker and try again."
        exit 1
    fi
}

# Function to check for Docker Compose (plugin or standalone)
docker_compose_installed() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command_exists docker-compose; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "Error: Docker Compose is not installed! Please install Docker Compose and try again."
        exit 1
    fi
}

# Function to check if yq is installed
yq_installed() {
    if ! command_exists yq; then
        echo "Error: yq is not installed! Please install yq and try again."
        exit 1
    fi
}

install_k3d(){
    echo "Installing k3d"
    wget -q -O - "${K3D_INSTALL_SCRIPT}" | bash
}

get_docker_host_ip(){
    cd "${SCRIPT_DIR}/dev" || exit 1
    # Get the backend container ID
    BACKEND_CONTAINER=$(${DOCKER_COMPOSE_CMD} ps -q backend)

    if [ -z "${BACKEND_CONTAINER}" ]; then
        echo "Error: Backend container not found!"
        exit 1
    fi

    # Get the network name of the backend container
    NETWORK_NAME=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' "${BACKEND_CONTAINER}")

    if [ -z "${NETWORK_NAME}" ]; then
        echo "Error: Could not determine network name!"
        exit 1
    fi

    # Get the host machine's IP inside the Docker network
    HOST_IP_IN_DOCKER_NETWORK=$(docker network inspect "$NETWORK_NAME" | jq -r '.[0].IPAM.Config[0].Gateway')
}

dev_init(){
    echo "Checking if docker is installed..."
    docker_installed
    echo "OK!"
    echo "Checking if docker compose is installed..."
    docker_compose_installed
    echo "OK!"
    echo "Checking if yq is installed..."
    yq_installed
    echo "OK!"
    echo "Installing/updating k3d..."
    install_k3d
    echo "OK!"
}

setup_dev_cluster(){
    local ip="$1"
    local tls_san="--tls-san=${ip}"
    local modified_file="${RUNTIME_DIR}/cluster.yaml"

    # Copy the original cluster file
    cp "${DEV_DIR}/cluster.yaml" "${modified_file}"

    # Ensure options.k3s exists in the YAML structure
    if [ "$(yq eval '.options.k3s' "$modified_file")" == "null" ]; then
        echo "Creating options.k3s section..."
        yq eval -i '.options.k3s = {}' "$modified_file"
    fi

    # Ensure extraArgs exists inside options.k3s
    if [ "$(yq eval '.options.k3s.extraArgs' "$modified_file")" == "null" ]; then
        echo "Creating extraArgs section..."
        yq eval -i '.options.k3s.extraArgs = []' "$modified_file"
    fi

    # Check if --tls-san argument already exists in extraArgs
    if [ "$(yq eval ".options.k3s.extraArgs[] | select(.arg == \"$tls_san\")" "$modified_file")" != "" ]; then
        echo "TLS-SAN already exists in the cluster.yaml. No changes made."
        return 0
    fi

    # Append the --tls-san argument under extraArgs safely
    yq eval -i ".options.k3s.extraArgs += [{\"arg\": \"$tls_san\", \"nodeFilters\": [\"server:*\"]}]" "$modified_file"

    echo "Modified cluster.yaml has been saved to $modified_file"
}

setup_kubeconfig(){
    local ip="$1"
    local modified_file="${RUNTIME_DIR}/kubeconfig"

    # Copy the original kubeconfig file
    cp "${HOME}/.kube/config" "${modified_file}"

    echo "Patching kubeconfig with IP: $ip"

    # Replace 0.0.0.0 with the host IP in the kubeconfig file
    sed -i "s/0.0.0.0/$ip/g" "${modified_file}"
}

dev_up(){
    # Touch runtime dev cluster config 
    touch "${RUNTIME_DIR}/kubeconfig"
    docker_compose_installed
    # Start Docker Compose in detached mode
    echo "Bringing Docker Compose Up..."
    cd "${SCRIPT_DIR}/dev" && ${DOCKER_COMPOSE_CMD} up -d
    echo "Determining docker network host ip..."
    get_docker_host_ip
    echo "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Adding ${HOST_IP_IN_DOCKER_NETWORK} to the development cluster TLS certificate SANs..."
    setup_dev_cluster "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Starting development cluster..."
    k3d cluster create "${DEV_CLUSTER_NAME}" --config "${RUNTIME_DIR}/cluster.yaml"
    setup_kubeconfig "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Restarting backend container after patching kubeconfig..."
    cd "${SCRIPT_DIR}/dev" && ${DOCKER_COMPOSE_CMD} restart backend
    echo "Opening backend on browser..."
    xdg-open http://localhost:5010/api/pods
    echo "Opening frontend on browser..."
    xdg-open http://localhost:3000/
}

dev_down(){
    docker_compose_installed
    echo "Bringing Docker Compose Down..."
    cd "${SCRIPT_DIR}/dev" && ${DOCKER_COMPOSE_CMD} down
    k3d cluster delete "${DEV_CLUSTER_NAME}"
}

dev(){
    # Check if no arguments were provided
    if [ $# -eq 0 ]; then
        usage_error
    fi 
    
    CMD=$1
    shift 1 || true

    if [ "${CMD}" = "init" ]; then
        dev_init
    elif [ "${CMD}" = "up" ]; then
        dev_up
    elif [ "${CMD}" = "down" ]; then
        dev_down
    else
        echo "Invalid command: ${CMD}"
        usage_error
    fi

}


# Check if no arguments were provided
if [ $# -eq 0 ]; then
    usage_error
fi

CMD=$1
shift 1 || true

if [ "${CMD}" = "dev" ]; then
    dev "$@"
else
    echo "Invalid command: ${CMD}"
    usage_error
fi
