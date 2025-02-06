from flask import Flask, jsonify, request
from flask_cors import CORS
from kubernetes import client, config
import os

app = Flask(__name__)
CORS(app)

def get_pod_data(namespace=None):
    """
    Fetch pod and node data using the Kubernetes Python Client.
    Ensures that all nodes are included, even if no pods are running on them.
    """
    try:
        # Load Kubernetes configuration
        if os.getenv("KUBERNETES_SERVICE_HOST"):
            config.load_incluster_config()  # Running inside a Kubernetes cluster
        else:
            config.load_kube_config()  # Running locally, using ~/.kube/config

        v1 = client.CoreV1Api()

        # Fetch all nodes
        all_nodes = v1.list_node().items
        node_names = {node.metadata.name for node in all_nodes}  # Store node names

        # Fetch pods, either from a specific namespace or all namespaces
        if namespace:
            pod_list = v1.list_namespaced_pod(namespace)
        else:
            pod_list = v1.list_pod_for_all_namespaces(watch=False)

        nodes = {node_name: [] for node_name in node_names}  # Ensure all nodes exist in response
        pods = []

        for pod in pod_list.items:
            node_name = pod.spec.node_name
            pod_name = pod.metadata.name

            if node_name:
                nodes[node_name].append(pod_name)
            else:
                pods.append({"name": pod_name, "node": None})  # Pending pods (not yet assigned)

        # Format response
        return {
            "nodes": [{"name": node} for node in nodes.keys()],
            "pods": [{"name": pod, "node": node} for node, pod_list in nodes.items() for pod in pod_list] +
                    [{"name": pod["name"], "node": None} for pod in pods]
        }

    except client.exceptions.ApiException as e:
        return {"error": "Kubernetes API error", "details": e.reason}, e.status
    except Exception as e:
        return {"error": "Failed to fetch pod data", "details": str(e)}, 500


@app.route("/api/pods", methods=["GET"])
def api_pods():
    """API route to get pod data, with optional namespace selection"""
    namespace = request.args.get("namespace")  # Get namespace from query params
    return jsonify(get_pod_data(namespace))


if __name__ == "__main__":
    debug_mode = os.getenv("FLASK_DEBUG", "False").lower() in ("true", "1")
    app.run(host="0.0.0.0", port=5010, debug=debug_mode)
