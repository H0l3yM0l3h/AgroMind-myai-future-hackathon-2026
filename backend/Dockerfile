# Use the official Python 3.11 slim image as the base to keep the container lightweight
FROM python:3.11-slim

# Install system-level dependencies for geospatial math (GEOS and PROJ)
# libgeos-dev: required by shapely for polygon operations
# binutils: required by pyproj for coordinate transformations
# rm -rf cleans up apt cache to keep the image size small
RUN apt-get update && apt-get install -y \
    libgeos-dev \
    binutils \
    && rm -rf /var/lib/apt/lists/*

# THE FIX: Move the code to a different folder than the secret!
# Using /code instead of /app avoids conflicts with Cloud Run's secret
# volume mounts which are typically mounted under /app
WORKDIR /code

# Copy requirements first to leverage Docker layer caching —
# pip install only re-runs when requirements.txt changes, not on every code change
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application source code into the container
COPY . .

# Start the server normally
# $PORT is injected by Cloud Run at runtime (default 8080)
# Using `exec` ensures uvicorn runs as PID 1 and receives shutdown signals correctly
CMD exec uvicorn main:app --host 0.0.0.0 --port $PORT