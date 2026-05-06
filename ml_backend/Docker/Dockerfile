# Use a slim version of Python 3.13 to minimize image size.
FROM python:3.13-slim

# Set environment variables to optimize Python performance within the container.
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBUG=false

# Set the working directory inside the container.
WORKDIR /app

# Install system-level dependencies required for building C-extensions in numpy/hmmlearn.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy only the requirements file first to leverage Docker layer caching.
COPY requirements.txt .

# Install Python dependencies.
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code.
COPY . .

# Expose the port used by FastAPI.
EXPOSE 8000

# Run the FastAPI application using uvicorn.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]