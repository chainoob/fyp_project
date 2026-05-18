FROM python:3.12-slim

# Optimize Python for containerized environments
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBUG=false

# Cloud Run defaults to port 8080
ENV PORT=8080

WORKDIR /app

# Install system dependencies for C-extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --root-user-action=ignore -r requirements.txt

# Copy application source
COPY . .

# Expose production port
EXPOSE 8080

# Run FastAPI with Gunicorn and Uvicorn workers for production stability
CMD ["gunicorn", "main:app", "--workers", "1", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8080"]