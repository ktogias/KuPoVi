#!/bin/bash

usage_error() {
    printf "Usage: %s <command> [mode]\n\n" "$0"
    printf "%s\n" "Commands:"
    printf "  %s\n" "init           Install k3d and other development dependencies."
    printf "  %s\n" "up [dev|test]  Start the environment:"
    printf "  %s\n" "               - 'dev' (default) for development mode with a k3d cluster."
    printf "  %s\n" "               - 'test' for testing production images in a test k3d cluster."
    printf "  %s\n" "down           Stop and remove the development cluster and containers."
    printf "\n"
    printf "%s\n" "Examples:"
    printf "  %s %s\n" "$0" "init        # Install dependencies"
    printf "  %s %s\n" "$0" "up          # Start in development mode"
    printf "  %s %s\n" "$0" "up test     # Start in test mode with production images"
    printf "  %s %s\n" "$0" "down        # Stop everything"
    printf "\n"
    exit 1
}


K3D_INSTALL_SCRIPT="https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"

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

init(){
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

setup_test_cluster(){
    local ip="$1"
    local tls_san="--tls-san=${ip}"
    local modified_file="${RUNTIME_DIR}/cluster.yaml"

    # Copy the original cluster file
    cp "${SCRIPT_DIR}/cluster.yaml" "${modified_file}"

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

# Function to check if backend is ready (with timeout)
wait_for_service() {
    local name="$1"
    local url="$2"
    local timeout="$3"
    echo "Waiting for ${name} to be ready (Timeout: ${timeout} seconds)..."
    local elapsed=0
    while ! curl --output /dev/null --silent --head --fail "$url"; do
        if [[ $elapsed -ge $timeout ]]; then
            echo "❌ ${name} did not start within ${timeout} seconds. Exiting."
            exit 1
        fi
        echo -n "."
        sleep 2
        ((elapsed+=2))
    done
    echo "✅ ${name} is ready!"
}

up(){
    local mode=${1:-dev}
    # Touch runtime test cluster config 
    touch "${RUNTIME_DIR}/kubeconfig"
    docker_compose_installed
    if [ "${mode}" == "dev" ]; then
        local cluster_name="kupovi-dev"
        local backend_url="http://localhost:5010/api/pods"
        local frontend_url="http://localhost:3010/"
        local cmd="${DOCKER_COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yaml -f ${SCRIPT_DIR}/docker-compose.dev.override.yaml up --build -d"
        echo "Starting in DEVELOPMENT mode..."
    elif [ "${mode}" == "test" ]; then
        local cluster_name="kupovi-test"
        local backend_url="http://localhost:5000/api/pods"
        local frontend_url="http://localhost:3000/"
        local cmd="${DOCKER_COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yaml up --build -d"
        echo "Starting in PRODUCTION IMAGES TESTING mode..."
    else
        usage_error
    fi
    # Start Docker Compose in detached mode
    echo "Bringing Docker Compose Up..."
    ${cmd}
    echo "Determining docker network host ip..."
    get_docker_host_ip
    echo "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Adding ${HOST_IP_IN_DOCKER_NETWORK} to the development cluster TLS certificate SANs..."
    setup_test_cluster "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Starting development cluster..."
    k3d cluster create "${cluster_name}" --config "${RUNTIME_DIR}/cluster.yaml"
    setup_kubeconfig "${HOST_IP_IN_DOCKER_NETWORK}"
    echo "Restarting backend container after patching kubeconfig..."
    ${DOCKER_COMPOSE_CMD} restart backend
    
    # Wait for backend before opening browser
    wait_for_service "Backend" "${backend_url}" 30
    echo "Opening backend on browser..."
    xdg-open "${backend_url}"
    
    # Wait for frontend before opening browser
    wait_for_service "Frontend" "${frontend_url}" 30
    echo "Opening frontend on browser..."
    xdg-open "${frontend_url}"
}

down(){
    docker_compose_installed
    echo "Bringing Docker Compose down..."
    ${DOCKER_COMPOSE_CMD} down
    k3d cluster delete kupovi-dev
    k3d cluster delete kupovi-test
}

# Check if no arguments were provided
if [ $# -eq 0 ]; then
    usage_error
fi

CMD=$1
shift 1 || true

if [ "${CMD}" = "init" ]; then
    init "$@"
elif [ "${CMD}" = "up" ]; then
    up "$@"
elif [ "${CMD}" = "down" ]; then
    down "$@"
else
    echo "Invalid command: ${CMD}"
    usage_error
fi
