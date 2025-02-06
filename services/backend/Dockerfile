# Base image for Python
FROM python:3.10-slim

# Set the working directory
WORKDIR /app

# Install kubectl
RUN apt-get update && apt-get install -y curl \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/ \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the backend files
COPY app/ /app

# Install dependencies
RUN pip install --no-cache-dir flask flask-cors

# Expose the backend port
EXPOSE 5010

# Run the backend
CMD ["python", "src/k8s_api.py"]
