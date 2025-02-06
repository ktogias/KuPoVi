# Kubernetes Pod Visualizer

## Overview
This project provides a live visualization of pod placement in a Kubernetes cluster.

## Development

### Check and install host dependencies
```sh
./kupovi.sh init
```

### Start development containers and development cluster
```sh
./kupovi.sh up
```
Backend and front end will open on your browser:

- Backend: http://localhost:5010/api/pods
- Frontend: http://localhost:3010/

### Start production containers and testing cluster
```sh
./kupovi.sh up test
```
Backend and front end will open on your browser:

- Backend: http://localhost:5000/api/pods
- Frontend: http://localhost:3000/


### Stop and destroy containers and clusters
```sh
./kupovi.sh down
```

## Kubernetes Deployment

### Build and push Docker images:
```sh
docker build --target prod -t your-docker-registry/kupovi-back backend/
docker push your-docker-registry/kupovi-back

docker build --target prod -t your-docker-registry/kupovi-front backend/
docker push your-docker-registry/kupovi-front
```

### Deploy to Kubernetes (not yet implemented):
```sh
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/fronetend-deployment.yaml
```
