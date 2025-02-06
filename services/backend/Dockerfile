# ====== Base Stage ======
FROM python:3.10-slim AS base

WORKDIR /app

# Copy dependency files first for better caching
COPY app/requirements.txt ./

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY app/ .

# Expose API port
EXPOSE 5010


# ====== Development Stage ======
FROM base AS dev

# Run Flask in development mode with auto-reload
CMD ["flask", "--app", "src/k8s_api.py", "run", "--host=0.0.0.0", "--port=5010", "--debug"]


# ====== Production (for Both Docker & Kubernetes) ======
FROM base AS prod

# Install Gunicorn for production
RUN pip install gunicorn

# Run the production backend with Gunicorn (4 workers)
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5010", "src.k8s_api:app"]
