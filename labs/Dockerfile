# Improved lab variant. Instructor's exact Python 3.9 Dockerfile is in examples/.
FROM docker.io/library/python:3.12-alpine
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
EXPOSE 5000
CMD ["python", "app.py"]
