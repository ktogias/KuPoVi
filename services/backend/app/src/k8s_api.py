from flask import Flask, jsonify, request
from flask_cors import CORS
from kubernetes import client, config
import os

app = Flask(__name__)
CORS(app)

def get_pod_data(namespace=None, filter_label=None):
    """
    Fetch pod and node data using the Kubernetes Python Client.
    Ensures that only nodes with a specified label are included.
    Pods on filtered-out nodes are also excluded.
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

        # Filter nodes by the given label
        filtered_nodes = {}
        for node in all_nodes:
            node_name = node.metadata.name
            node_labels = node.metadata.labels

            if filter_label:
                key, value = filter_label.split("=") if "=" in filter_label else (filter_label, None)
                if key not in node_labels or (value and node_labels[key] != value):
                    continue  # Skip nodes that don't match the label filter

            filtered_nodes[node_name] = []

        # Fetch pods, either from a specific namespace or all namespaces
        if namespace:
            pod_list = v1.list_namespaced_pod(namespace)
        else:
            pod_list = v1.list_pod_for_all_namespaces(watch=False)

        pods = []

        for pod in pod_list.items:
            node_name = pod.spec.node_name
            pod_name = pod.metadata.name

            if node_name and node_name in filtered_nodes:
                filtered_nodes[node_name].append(pod_name)
            elif not node_name:
                pods.append({"name": pod_name, "node": None})  # Pending pods

        # Format response
        return {
            "nodes": [{"name": node} for node in filtered_nodes.keys()],
            "pods": [{"name": pod, "node": node} for node, pod_list in filtered_nodes.items() for pod in pod_list] +
                    [{"name": pod["name"], "node": None} for pod in pods]  # Include unassigned pods
        }

    except client.exceptions.ApiException as e:
        return {"error": "Kubernetes API error", "details": e.reason}, e.status
    except Exception as e:
        return {"error": "Failed to fetch pod data", "details": str(e)}, 500


@app.route("/api/pods", methods=["GET"])
def api_pods():
    """API route to get pod data, with optional namespace and label filtering"""
    namespace = request.args.get("namespace")  # Get namespace from query params
    filter_label = request.args.get("label")  # Get node label filter (e.g., label=zone=us-east)

    return jsonify(get_pod_data(namespace, filter_label))


if __name__ == "__main__":
    debug_mode = os.getenv("FLASK_DEBUG", "False").lower() in ("true", "1")
    app.run(host="0.0.0.0", port=5010, debug=debug_mode)
