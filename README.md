# Kubernetes Pod Visualizer

## Overview
This project provides a live visualization of pod placement in a Kubernetes cluster.

## Development

### Check and install host dependencies
```sh
./kupovi.sh dev init
```

### Start development containers and cluster
```sh
./kupovi.sh dev up
```
Backend and front end will open on your browser:

- Backend: http://localhost:5010/api/pods
- Frontend: http://localhost:3000/


### Stop and destroy development containers and cluster
```sh
./kupovi.sh dev down
```

## Kubernetes Deployment

### Build and push Docker images:
```sh
docker build -t your-dockerhub-username/k8s-api backend/
docker push your-dockerhub-username/k8s-api
```

### Deploy to Kubernetes:
```sh
kubectl apply -f k8s/backend-deployment.yaml
```
