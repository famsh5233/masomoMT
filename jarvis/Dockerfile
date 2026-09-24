FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY jarvis ./jarvis
ENV JARVIS_DB=/data/jarvis.db JARVIS_CONTENT_DIR=/data/content
# Trust X-Forwarded-For only from the reverse proxy on the host (Docker's default bridge gateway),
# so per-address limits see the real client. Change it if your proxy runs elsewhere.
ENV FORWARDED_ALLOW_IPS=172.17.0.1,127.0.0.1
VOLUME /data
EXPOSE 8000
# No access log: the AzamPay callback URL carries its secret in the query string.
CMD ["uvicorn", "jarvis.server:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-access-log"]
