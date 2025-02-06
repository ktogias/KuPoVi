from flask import Flask, jsonify
from flask_cors import CORS  # Import CORS
import subprocess
import json

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

def get_pod_data():
    cmd = "kubectl get pods -o json"
    result = subprocess.run(cmd.split(), capture_output=True, text=True)
    pods_json = json.loads(result.stdout)

    nodes = {}
    pods = []

    for pod in pods_json["items"]:
        # Check if 'nodeName' exists in the pod spec
        node_name = pod["spec"].get("nodeName")
        pod_name = pod["metadata"]["name"]

        if node_name:
            # Add to nodes if nodeName is present
            if node_name not in nodes:
                nodes[node_name] = []

            nodes[node_name].append(pod_name)
        else:
            # Add to pods list without a node
            pods.append({"name": pod_name, "node": None})

    return {
        "nodes": [{"name": node} for node in nodes],
        "pods": [{"name": pod, "node": node} for node, pod_list in nodes.items() for pod in pod_list] +
                [{"name": pod["name"], "node": None} for pod in pods]
    }


@app.route("/api/pods", methods=["GET"])
def api_pods():
    return jsonify(get_pod_data())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5010, debug=True)
