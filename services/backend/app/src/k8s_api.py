from flask import Flask, jsonify, request
from flask_cors import CORS
from kubernetes import client, config
import os
import hashlib

app = Flask(__name__)
CORS(app)

def get_pod_data(namespace=None, filter_label=None, display_mode="both"):
    """
    Fetch pod and node data using the Kubernetes Python Client.
    Ensures that only nodes with a specified label are included.
    Allows customizing node name display format.
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
                    continue

            if display_mode == "name":
                display_name = node_name
            elif display_mode == "label":
                display_name = node_labels.get(filter_label.split("=")[0], "Unknown")
            else:
                label_value = node_labels.get(filter_label.split("=")[0], "Unknown") if filter_label else ""
                display_name = f"{node_name} ({label_value})" if filter_label else node_name

            filtered_nodes[node_name] = {"display_name": display_name, "pods": []}

        # Fetch pods, either from a specific namespace or all namespaces
        if namespace:
            pod_list = v1.list_namespaced_pod(namespace)
        else:
            pod_list = v1.list_pod_for_all_namespaces(watch=False)

        pods = []

        for pod in pod_list.items:
            node_name = pod.spec.node_name
            pod_name = pod.metadata.name
            deployment_name = pod.metadata.labels.get("app") or pod.metadata.labels.get("deployment", "unknown")
            ready = any(
                status.ready for status in pod.status.container_statuses or []
            ) if pod.status.container_statuses else False

            pod_data = {
                "name": pod_name,
                "node": None if not node_name else filtered_nodes.get(node_name, {}).get("display_name"),
                "deployment": deployment_name,
                "ready": ready,
            }

            if node_name and node_name in filtered_nodes:
                filtered_nodes[node_name]["pods"].append(pod_data)
            elif not node_name:
                pods.append(pod_data)

        return {
            "nodes": [{"name": data["display_name"]} for data in filtered_nodes.values()],
            "pods": [pod for node in filtered_nodes.values() for pod in node["pods"]] + pods
        }

    except client.exceptions.ApiException as e:
        return {"error": "Kubernetes API error", "details": e.reason}, e.status
    except Exception as e:
        return {"error": "Failed to fetch pod data", "details": str(e)}, 500


@app.route("/api/pods", methods=["GET"])
def api_pods():
    """API route to get pod data, with optional namespace, label filtering, and display options"""
    namespace = request.args.get("namespace")
    filter_label = request.args.get("label")
    display_mode = request.args.get("display", "both")

    return jsonify(get_pod_data(namespace, filter_label, display_mode))


if __name__ == "__main__":
    debug_mode = os.getenv("FLASK_DEBUG", "False").lower() in ("true", "1")
    app.run(host="0.0.0.0", port=5010, debug=debug_mode)
