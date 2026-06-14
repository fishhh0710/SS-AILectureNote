FROM python:3.13-slim

# Install system dependencies needed by OpenCV (headless needs some basic glib/GL libraries)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install Python dependencies FIRST (this layer gets cached between builds
# as long as requirements.txt does not change — the biggest time saver)
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt

# Copy the rest of the code (changes here won't re-trigger pip install)
COPY . .

# Run the FastAPI server on port 8080 (Google Cloud Run default port)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
