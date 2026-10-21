FROM python:3.9-alpine
WORKDIR /app
COPY . .
RUN pip install flask redis
CMD ["python", "app.py"]
