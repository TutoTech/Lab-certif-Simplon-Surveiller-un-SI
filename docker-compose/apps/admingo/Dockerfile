FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

# Pour le lab : Flask dev server. En vraie prod, remplacer par gunicorn.
CMD ["python", "app.py"]
