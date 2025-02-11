from flask import Flask, jsonify, request
from flask_cors import CORS
from kubernetes import client, config
from urllib.parse import unquote
import os
import hashlib

app = Flask(__name__)
CORS(app)

def parse_label_filters(label_query):
    """
    Parses label filters from the request query.
    Converts "zone%3Dedge%2Cworkload%2Carch%3Darm" → {'zone': 'edge', 'workload': None, 'arch': 'arm'}
    """
    if not label_query:
        return {}

    label_filters = {}
    decoded_query = unquote(label_query)  # Decode %3D and %2C

    filters = decoded_query.split(",")

    for filter_str in filters:
        key_value = filter_str.split("=")
        if len(key_value) == 2:
            label_filters[key_value[0]] = key_value[1]  # Key=Value condition
        else:
            label_filters[key_value[0]] = None  # Key exists without value constraint

    return label_filters


def get_pod_data(namespace=None, label_filters=None):
    """
    Fetches Kubernetes pod and node data.
    - Filters nodes based on provided label conditions.
    - Sends full node metadata (name + labels) to frontend.
    - Excludes completed pods.
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

            # Apply label filtering
            if label_filters:
                matches = all(
                    (key in node_labels and (value is None or node_labels[key] == value))
                    for key, value in label_filters.items()
                )
                if not matches:
                    continue

            filtered_nodes[node_name] = {
                "name": node_name,
                "labels": node_labels
            }

        # Fetch pods, either from a specific namespace or all namespaces
        if namespace:
            pod_list = v1.list_namespaced_pod(namespace)
        else:
            pod_list = v1.list_pod_for_all_namespaces(watch=False)

        pods = []

        for pod in pod_list.items:
            # **Exclude completed pods**
            if pod.status.phase == "Succeeded":
                continue
            node_name = pod.spec.node_name
            pod_name = pod.metadata.name
            deployment_name = pod.metadata.labels.get("app") or pod.metadata.labels.get("deployment", "unknown")
            ready = any(
                status.ready for status in pod.status.container_statuses or []
            ) if pod.status.container_statuses else False

            pod_data = {
                "name": pod_name,
                "node": node_name if node_name in filtered_nodes else None,  # Only include filtered nodes
                "deployment": deployment_name,
                "ready": ready,
            }

            #if node_name and node_name in filtered_nodes:
            #    filtered_nodes[node_name]["pods"].append(pod_data)
            #elif not node_name:
            pods.append(pod_data)

        return {
            "nodes": list(filtered_nodes.values()),  # Send full node data (name + labels)
            "pods": pods
        }

    except client.exceptions.ApiException as e:
        return {"error": "Kubernetes API error", "details": e.reason}, e.status
    except Exception as e:
        return {"error": "Failed to fetch pod data", "details": str(e)}, 500


@app.route("/api/pods", methods=["GET"])
def api_pods():
    """API route to get pod data, with optional namespace, label filtering, and display options"""
    namespace = request.args.get("namespace")
    label_query = request.args.get("labels")  # Example: "zone=edge,workload,arch=arm"
    label_filters = parse_label_filters(label_query)


    return jsonify(get_pod_data(namespace, label_filters))

@app.route("/api/namespaces", methods=["GET"])
def api_namespaces():
    v1 = client.CoreV1Api()
    namespaces = [ns.metadata.name for ns in v1.list_namespace().items]
    return jsonify({"namespaces": namespaces})


if __name__ == "__main__":
    debug_mode = os.getenv("FLASK_DEBUG", "False").lower() in ("true", "1")
    app.run(host="0.0.0.0", port=5010, debug=debug_mode)
