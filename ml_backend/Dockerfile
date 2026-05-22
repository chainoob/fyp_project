FROM python:3.12-slim

# Optimize Python for containerized environments
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBUG=false

# Cloud Run defaults to port 8080
ENV PORT=8080

WORKDIR /app

# Install system dependencies for C-extensions and HDF5 compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libhdf5-dev \
    pkg-config \
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
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "--timeout", "120", "-b", "0.0.0.0:8080", "main:app"]