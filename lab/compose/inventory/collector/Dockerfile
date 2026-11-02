FROM python:3.13-slim
RUN pip install --no-cache-dir requests
WORKDIR /app
COPY collector.py .
CMD ["python", "-u", "collector.py"]
